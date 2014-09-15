// Copyright (c) 2014 segfault.jp. All rights reserved.

import Foundation

/// A composable object which represents an event stream where multiple events are flowing.
public struct Stream<A> {

    private let o: Source<A>
    
    private init(_ o: Source<A>) { self.o = o }

    public func subscribe(f: Packet<A> -> ()) { return open().subscribe(f) }

    public func open(callerContext: ExecutionContext, _ cont: Channel<A> -> (Packet<A> -> ())?) -> Channel<A> {
        return o.open(callerContext, cont)
    }
    
    public func open(callerContext: ExecutionContext) -> Channel<A> {
        return o.open(callerContext) { _ in nil }
    }
}

/// A subscription of an event stream.
public class Channel<A> {
    
    public func subscribe(f: Packet<A> -> ()) { abort() }
    
    public func close() {}
    
    public var isClosed: Bool { get { return true } }
}

/// An event.
public enum Packet<A> {

    case Done()
    case Fail(NSError)
    case Next(Box <A>)

    public var value: A? { get {
        switch self {
        case .Next(let x): return +x
        default:
            return nil
        }
    }}
    
    func map<B>(f: A -> B) -> Packet<B> {
        switch self {
        case let .Next(x): return .Next(x.map(f))
        case let .Fail(x): return .Fail(x)
        case let .Done( ): return .Done( )
        }
    }

}

public extension Stream {

    public func innerBind<B>(f: () -> A -> Stream<B>) -> Stream<B> { return Stream<B>(InnerBinding(self, f)) }
    public func outerBind<B>(f: () -> A -> Stream<B>) -> Stream<B> { return Stream<B>(OuterBinding(self, f)) }
    
    public func flatMap<B>(f: A -> Stream<B>) -> Stream<B> { return self >>+ f }
    
    public func map<B>(f: A -> B) -> Stream<B> { return flatMap { Streams.pure(f($0)) } }

    public func filter(predicate: A -> Bool) -> Stream<A> {
        return flatMap { predicate($0) ? Streams.pure($0): Streams.done() }
    }

    public func pack() -> Stream<Packet<A>> {
        return Streams.source([.AllowSync]) { chan in
            var base: Channel<A>? = nil
            chan.setCloseHandler {
                base?.close()
                base = nil
            }
            self.open(chan.calleeContext) {
                base = $0
                return { chan.emitIfOpen(.Next(Box($0))) }
            }
        }
    }

    public func onClose<X>(action: () -> X) -> Stream<A> {
        return Streams.source([.AllowSync]) { chan in
            var base: Channel<A>? = nil
            chan.setCloseHandler {
                chan.callerContext.schedule(chan.calleeContext, 0) {
                    action()
                    base?.close()
                    base = nil
                }
            }
            self.open(chan.calleeContext) {
                base = $0
                return { chan.emitIfOpen($0) }
            }
        }
    }
    
    public func foreach<X>(action: A -> X) -> Stream<A> {
        return map {
            action($0)
            return $0
        }
    }
    
    public func isolated<B>(property: [ExecutionProperty], f: Stream<A> -> Stream<B>) -> Stream<B> {
        return pipe(property) { chan in
            (f(pipe([]) { _ in (self, chan.callerContext) }), chan.calleeContext)
        }
    }
    
    public func zipWithContext() -> Stream<(A, ExecutionContext)> {
        return Streams.source() { chan in
            var base: Channel<A>? = nil
            chan.setCloseHandler {
                base?.close()
                base = nil
            }
            self.open(chan.calleeContext) {
                base = $0
                return { chan.emitIfOpen($0.map { ($0, chan.calleeContext) } ) }
            }
        }
    }
}

// TODO thread safe
private func pipe<A>(property: [ExecutionProperty], f: Dispatcher<A> -> (Stream<A>, ExecutionContext)) -> Stream<A> {
    return Streams.source(property) { chan in
        var base: Channel<A>? = nil
        chan.setCloseHandler {
            base?.close()
            base = nil
        }
        let (s, context) = f(chan)
        s .open(context) { ( base = $0 )
            return { chan.emitIfOpen($0) }
        }
    }
}

public class Streams {

    public class func source<A>(f: Dispatcher<A> -> ()) -> Stream<A> { return source([], f) }
    
    public class func source<A>(property: [ExecutionProperty], f: Dispatcher<A> -> ()) -> Stream<A> {
        return Stream(ClosureSource<A>(property, f))
    }

    public class func pure<A>(value: A) -> Stream<A> { return source { $0.flush(value) } }
    
    public class func none<A>() -> Stream<A> { return source { _ in () } }
    
    public class func done<A>() -> Stream<A> { return source { $0.emit(.Done()) } }
    
    public class func fail<A>(error: NSError) -> Stream<A> { return source { $0.emit(.Fail(error)) } }

    public class func list<A>(a: [A]) -> Stream<A> {
        return source { chan in
            var i = 0
            while i < a.count && !chan.isClosed {
                chan.emit(.Next(Box( a[i++] )))
            }
            chan.emitIfOpen(.Done())
        }
    }
    
    public class func args<A>(a: A...) -> Stream<A> { return list(a) }

    public class func unpack<A>(s: Stream<Packet<A>>) -> Stream<A> {
        return source([.AllowSync]) { chan in
            var base: Channel<Packet<A>>? = nil
            chan.setCloseHandler {
                base?.close()
                base = nil
            }
            s.open(chan.calleeContext) {
                base = $0
                return { chan.emitIfOpen($0 >>| { $0 }) }
            }
        }
    }

    public class func timeout<A>(delay: Double, _ value: A) -> Stream<A> {
        return Streams.source { chan in
            var holder: A? = value
            chan.setCloseHandler {
                holder = nil
            }
            chan.calleeContext.schedule(nil, delay) {
                if let e = holder { chan.flush(e) }
            }
        }
    }
}

infix operator >>* { associativity left precedence 255 }
public func >>* <A, B>(s: Stream<A>, f: A -> Stream<B>) -> Stream<B> {
    return Stream(OuterBinding(s) { f })
}

infix operator >>+ { associativity left precedence 255 }
public func >>+ <A, B>(s: Stream<A>, f: A -> Stream<B>) -> Stream<B> {
    return Stream(InnerBinding(s) { f })
}

infix operator >< { associativity left precedence 255 }
public func >< <A>(a: Stream<A>, b: Stream<A>) -> Stream<A> {
    return Stream(Mix(a, b))
}

private enum State { case Open, Closing, Closed }

// TODO It shall be separated into `Channel` and `Dispatcher` alone..
/// An instance of this class emits events to `Channel` corresponding to itself.
public class Dispatcher<A>: Channel<A> {
    
    public let callerContext: ExecutionContext
    public let calleeContext: ExecutionContext

    private var handler: (Packet<A> -> ())?
    private var closeHandler:  (( ) -> ())?
    private var closeState = State.Open
    
    public init(_ callerContext: ExecutionContext, _ calleeContext: ExecutionContext) {
        self.callerContext = callerContext
        self.calleeContext = calleeContext
    }

    public func flush(e: A) {
        assert(!isClosed, "This channel was closed.")
        emitIfOpen(.Next(Box(e)))
        emitIfOpen(.Done())
    }
    
    // TODO emitAndWait: Cont<()>
    public func emit(e: Packet<A>) {
        assert(!isClosed, "This channel was closed.")
        emitIfOpen(e)
    }
    
    public func emitIfOpen(e: Packet<A>) {
        if !isClosed {
            switch e {
            case .Next:
                callerContext.schedule(calleeContext, 0) {
                    if self.closeState != .Closed { self.handler!(e) }
                }
            default:
                closeState = .Closing
                callerContext.schedule(calleeContext, 0) {
                    if (self.closeState != .Closed) {
                        self.closeState  = .Closed
                        self.close_0(e)
                    }
                }
            }
        }
    }

    public func setCloseHandler(f: () -> ()) {
        assert(closeHandler == nil, "Dispatcher<>#setCloseHandler cannot be called twice.")
        closeHandler = f
    }
    
    override public func subscribe(f: Packet<A> -> ()) {
        assert(handler == nil, "Channel<>#subscribe has alreay been called.")
        handler = f
    }
    
    // TODO thread safe
    override public func close() {
        if (closeState != .Closed) {
            closeState  = .Closed
            callerContext.schedule(nil, 0) {
                self.close_0(.Done())
            }
        }
    }
    
    // TODO thread safe
    override public var isClosed: Bool { get { return closeState != .Open } }

    private func close_0(e: Packet<A>) {
        handler?(e)
        handler = nil
        calleeContext.schedule(nil, 0) {
            self.closeHandler?()
            self.closeHandler = nil
        }
    }
}

private class Source<A> {

    func open(callerContext: ExecutionContext, _ cont: Channel<A> -> (Packet<A> -> ())?) -> Channel<A> {
        let chan = Dispatcher<A>(callerContext, isolate(callerContext))
        if let f = cont(chan) {
            chan.subscribe(f)
        }
        invoke(chan)
        return chan
    }
    
    func invoke(chan: Dispatcher<A>) { abort() }
    
    func isolate(callerContext: ExecutionContext) -> ExecutionContext {
        return callerContext.requires([])
    }
}

private class ClosureSource<A>: Source<A>  {
    
    private let property: [ExecutionProperty]
    private let runnable: Dispatcher<A> -> ()
    
    init(_ property: [ExecutionProperty], _ runnable: Dispatcher<A> -> ()) {
        self.property = property
        self.runnable = runnable
    }

    override func invoke(chan: Dispatcher<A>) { runnable(chan) }
    
    override func isolate(callerContext: ExecutionContext) -> ExecutionContext {
        return callerContext.requires(property)
    }
}

private class Mix<A>: Source<A> {

    private let a: Stream<A>
    private let b: Stream<A>
    
    init(_ a: Stream<A>, _ b: Stream<A>) {
        self.a = a
        self.b = b
    }
    
    override func invoke(chan: Dispatcher<A>) {
        var a: Channel<A>? = nil
        var b: Channel<A>? = nil
        let f = { (o: Channel<A>) in { (e: Packet<A>) -> () in
            switch e {
            case .Done():
                if (a === o
                    ? (a = nil, b)
                    : (b = nil, a)).1 != nil { return }
                
            default: ()
            }
            chan.emitIfOpen(e)
        }}
        chan.setCloseHandler {
            a?.close(); a = nil
            b?.close(); b = nil
        }
        self.a.open(chan.calleeContext, { a = $0; return f(a!) })
        self.b.open(chan.calleeContext, { b = $0; return f(b!) })
    }
}

private class OuterBinding<A, B>: Source<B> {

    private let outer: Stream<A>
    private let block: () -> A -> Stream<B>
    
    init(_ outer: Stream<A>, _ block: () -> A -> Stream<B>) {
        self.outer = outer
        self.block = block
    }
    
    override func invoke(chan: Dispatcher<B>) {

        var base: Channel<A>? = nil
        var last: Channel<B>? = nil

        chan.setCloseHandler {
            last?.close(); last = nil
            base?.close(); base = nil
        }
        outer.open(chan.calleeContext) { ( base = $0 )
            let bind = self.block()
            return { e in
                last?.close()
                last = nil
                switch e {
                case .Next(let x):
                    last = bind(+x).open(chan.calleeContext) { ( last = $0 )
                        return { e in
                            switch e {
                            case let .Next(_): chan.emit(e)
                            case let .Fail(x): chan.emit(.Fail(x))
                                fallthrough
                            default:
                                last = nil
                            }
                        }
                    }
                
                case let .Fail(x): chan.emitIfOpen(.Fail(x))
                case let .Done( ): chan.emitIfOpen(.Done( ))
                }
            }
        }
    }
    
    override func isolate(callerContext: ExecutionContext) -> ExecutionContext {
        return callerContext.requires([.AllowSync])
    }
}

// TODO Solve the memory leak issue
private class InnerBinding<A, B>: Source<B> {
    
    private let outer: Stream<A>
    private let block: () -> A -> Stream<B>

    init(_ outer: Stream<A>, _ block: () -> A -> Stream<B>) {
        self.outer = outer
        self.block = block
    }
    
    override func invoke(chan: Dispatcher<B>) {
        
        var base: Channel<A>? = nil
        var last: Channel<B>? = nil
        let queue = ArrayDeque<Packet<A>>()
        
        chan.setCloseHandler {
            last?.close(); last = nil
            base?.close(); base = nil
            queue.clear()
        }

        var next: (Packet<A> -> ())? = nil
        let bind = block()
        next = { e in
            
            switch e {
            case .Next(let x):
                bind(+x).open(chan.calleeContext) { ( last = $0 )
                    return { e in
                        switch e {
                        case let .Next(_): chan.emitIfOpen(e)
                        case let .Fail(x): chan.emitIfOpen(.Fail(x))
                            fallthrough
                        default:
                            last = nil
                            if let e = queue.pop() { next!(e) }
                        }
                    }
                }
            case let .Fail(x): chan.emitIfOpen(.Fail(x))
            case let .Done( ): chan.emitIfOpen(.Done( ))
            }
        }
        outer.open(chan.calleeContext) { ( base = $0 )
            return {
                if last != nil { queue.unshift($0) } else { next!($0) }
            }
        }
    }
    
    override func isolate(callerContext: ExecutionContext) -> ExecutionContext {
        return callerContext.requires([.AllowSync])
    }
}
