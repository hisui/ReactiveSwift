// Copyright (c) 2014 segfault.jp. All rights reserved.

import Foundation

/// A composable object which represents an event stream where multiple events are flowing.
public struct Stream<A> {

    private let o: Source<A>
    
    init(_ o: Source<A>) { self.o = o }

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
    
    public func merge<B>(f: () -> A -> Stream<B>, _ count: Int=Int.max) -> Stream<B> {
        return Stream<B>(Merge(self, f, count))
    }

    public func innerBind<B>(f: () -> A -> Stream<B>) -> Stream<B> { return merge(f, 1) }
    
    public func outerBind<B>(f: () -> A -> Stream<B>) -> Stream<B> {
        return Stream<B>(OuterBinding(self, f))
    }
    
    public func flatMap<B>(f: A -> Stream<B>) -> Stream<B> { return innerBind({f}) }
    
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

    public func onClose(action: () -> ()) -> Stream<A> {
        return Streams.source([.AllowSync]) { chan in
            var base: Channel<A>? = nil
            chan.setCloseHandler {
                chan.callerContext.schedule(chan.calleeContext, 0, action)
                base?.close()
                base = nil
            }
            self.open(chan.calleeContext) {
                base = $0
                return { chan.emitIfOpen($0) }
            }
        }
    }
    
    public func foreach(action: A -> ()) -> Stream<A> {
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
    
    public class func merge<A>(a: Stream<Stream<A>>, _ count: Int=Int.max) -> Stream<A> {
        return a.merge({{ $0 }}, count)
    }
}

// TODO It shall be separated into `Channel` and `Dispatcher` alone..
/// An instance of this class emits events to `Channel` corresponding to itself.
public class Dispatcher<A>: Channel<A> {
    
    public let callerContext: ExecutionContext
    public let calleeContext: ExecutionContext

    private var eventHandler: (Packet<A> -> ())? // accessed only from callerContext
    private var closeHandler: (() -> ())?        // accessed only from calleeContext
    private var calleeOpen = true
    private var callerOpen = true

    public init(_ callerContext: ExecutionContext, _ calleeContext: ExecutionContext) {
        self.callerContext = callerContext
        self.calleeContext = calleeContext
    }

    public func flush(e: A) {
        assert(calleeOpen, "This channel was closed.")
        emitIfOpen(.Next(Box(e)))
        emitIfOpen(.Done())
    }
    
    // TODO emitAndWait: Cont<()>
    public func emit(e: Packet<A>) {
        assert(calleeOpen, "This channel was closed.")
        emitIfOpen(e)
    }
    
    public func emitIfOpen(e: Packet<A>) {
        if calleeOpen {
            switch e {
            case .Next:
                callerContext.schedule(calleeContext, 0) {
                    if (self.callerOpen) {
                        self.eventHandler?(e)
                    }
                }
            default:
                calleeOpen = false
                callerContext.schedule(calleeContext, 0) {
                    if (self.callerOpen) {
                        self.eventHandler?(e)
                        self.eventHandler = nil
                    }
                    self.completeToClose()
                }
            }
        }
    }
    
    public var isClosed: Bool { get { return !calleeOpen } }

    public func setCloseHandler(f: () -> ()) {
        assert(closeHandler == nil, "Dispatcher<>#setCloseHandler cannot be called twice.")
        if (calleeOpen) {
            closeHandler = f
        }
    }

    override public func subscribe(f: Packet<A> -> ()) {
        assert(eventHandler == nil, "Channel<>#subscribe has alreay been called.")
        if (callerOpen) {
            eventHandler = f
        }
    }

    override public func close() {
        if (callerOpen) {
            callerOpen = false
            calleeContext.schedule(callerContext, 0) {
                if (self.calleeOpen) {
                    self.calleeOpen = false
                    self.completeToClose()
                }
            }
            eventHandler = nil
        }
    }
    
    private func completeToClose() {
        self.calleeContext.schedule(self.callerContext, 0) {
            self.closeHandler?()
            self.closeHandler = nil
        }
    }

}

class Source<A> {

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

private final class ClosureSource<A>: Source<A>  {
    
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

private final class OuterBinding<A, B>: Source<B> {

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

private final class Merge<A, B>: Source<B> {
    
    private let outer: Stream<A>
    private let count: Int
    private let block: () -> A -> Stream<B>
    
    init(_ outer: Stream<A>, _ block: () -> A -> Stream<B>, _ count: Int) {
        self.outer = outer
        self.count = count
        self.block = block
    }

    override func invoke(chan: Dispatcher<B>) {
        
        var base: Channel<A>? = nil
        var alive: [Channel<B>] = []
        let queue = ArrayDeque<Packet<A>>()
        
        chan.setCloseHandler {
            queue.clear()
            base?.close()
            base = nil
            for e in alive {
                e.close()
            }
            alive.removeAll(keepCapacity: false)
        }

        var next: (Packet<A> -> ())? = nil
        let bind = block()
        next = { e in
            switch e {
            case .Next(let x):
                bind(+x).open(chan.calleeContext) { o in
                    alive.append(o)
                    return { e in
                        switch e {
                        case let .Next(_): chan.emitIfOpen(e)
                        case let .Fail(x): chan.emitIfOpen(.Fail(x))
                            fallthrough
                        default:
                            for i in 0 ..< alive.count {
                                if (alive[i] === o) {
                                    alive.removeAtIndex(i)
                                    break
                                }
                            }
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
                if alive.count < self.count { next!($0) } else { queue.unshift($0) }
            }
        }
    }
    
    override func isolate(callerContext: ExecutionContext) -> ExecutionContext {
        return callerContext.requires([.AllowSync])
    }
}
