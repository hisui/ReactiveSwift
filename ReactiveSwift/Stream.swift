// Copyright (c) 2014 segfault.jp. All rights reserved.

import Foundation

/// A composable object which represents an event stream where multiple events are flowing.
public class Stream<A> {
    
    typealias Cont = Channel<A> -> (Packet<A> -> ())?

    public func subscribe(f: Packet<A> -> ()) { return open().subscribe(f) }

    public func open(callerContext: ExecutionContext, _ cont: Cont) -> Channel<A> {
        abort()
    }
    
    public func open(callerContext: ExecutionContext) -> Channel<A> {
        return open(callerContext) { _ in nil }
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
    
    public var error: NSError? { get {
        switch self {
        case .Fail(let x): return x
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
    
    public func merge<B>(f: () -> A -> Stream<B>) -> Stream<B> { return merge(-1, f) }
    
    public func merge<B>(count: Int, _ f: () -> A -> Stream<B>) -> Stream<B> {
        return Merge(self, f, count)
    }

    public func innerBind<B>(f: () -> A -> Stream<B>) -> Stream<B> { return merge(1, f) }
    
    public func outerBind<B>(f: () -> A -> Stream<B>) -> Stream<B> {
        return merge {
            var last: Dispatcher<B>? = nil
            let bind = f()
            return { e in
                return Streams.pipe([.AllowSync]) {
                    last?.emitIfOpen(.Done())
                    last = $0
                    return bind(e)
                }
            }
        }
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
        return flatMap { e in Streams.pipe(property) { _ in f(Streams.pure(e)) } }
    }
    
    public func zipWith<B>(value: B) -> Stream<(A, B)> { return map { ($0, value) } }
    
    public func zipWithContext() -> Stream<(A, ExecutionContext)> {
        return Streams.pipe([.AllowSync]) { self.zipWith($0.calleeContext) }
    }
    
    public func groupBy<K: Hashable>(f: A -> K) -> Stream<Channel<(K, A)>> {
        return Streams.source() { outer in
            var base: Channel<A>?
            var map = [K: Dispatcher<(K, A)>]()
            outer.setCloseHandler {
                base?.close()
                base = nil
                for e in map.values { e.close() }
            }
            self.open(outer.calleeContext) { (base = $0)
                return { e in
                    switch e {
                    case .Next(let x):
                        let k = f(+x)
                        var chan = map[k]
                        if (chan == nil) {
                            chan = Dispatcher(outer.callerContext, outer.calleeContext)
                            map[k] = chan
                            outer.emitIfOpen(.Next(Box(chan!)))
                        }
                        chan!.emit(.Next(Box((k, x.raw))))
                    default:
                        for o in map.values { o.emit(e.map { _ in undefined() } ) }
                    }
                }
            }
        }
    }

}

private func undefined<X>() -> X { abort() }

public class Streams {

    public class func source<A>(f: Dispatcher<A> -> ()) -> Stream<A> { return source([], f) }
    
    public class func source<A>(property: [ExecutionProperty], f: Dispatcher<A> -> ()) -> Stream<A> {
        return ClosureSource<A>(property, f)
    }
    
    public class func none<A>() -> Stream<A> { return source { _ in () } }

    public class func pure<A>(value: A) -> Stream<A> {
        return source([.AllowSync]) { $0.flush(value) }
    }
    
    public class func done<A>() -> Stream<A> {
        return source([.AllowSync]) { $0.emit(.Done()) }
    }
    
    public class func fail<A>(error: NSError) -> Stream<A> {
        return source([.AllowSync]) { $0.emit(.Fail(error)) }
    }

    public class func list<A>(a: [A]) -> Stream<A> {
        return source([.AllowSync]) { chan in
            var i = 0
            while i < a.count && !chan.isClosed {
                chan.emit(.Next(Box( a[i++] )))
            }
            chan.emitIfOpen(.Done())
        }
    }
    
    public class func exec<A>(property: [ExecutionProperty], f: () -> A) -> Stream<A> {
        return source(property) { $0.flush(f()) }
    }
    
    public class func range<A: ForwardIndexType>(range: Range<A>) -> Stream<A> {
        return source { chan in
            for e in range {
                if !chan.isClosed { chan.emit(.Next(Box(e))) }
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

    public class func repeat<A>(value: A, _ delay: Double) -> Stream<A> {
        return Streams.source { chan in
            var holder: A? = value
            chan.setCloseHandler {
                holder = nil
            }
            repeatWhile(chan.calleeContext, delay) {
                if let e = holder {
                    chan.emitIfOpen(.Next(Box(e)))
                }
                return !chan.isClosed
            }
        }
    }
    
    public class func merge<A>(a: Stream<Stream<A>>, _ count: Int = -1) -> Stream<A> {
        return a.merge(count) {{ $0 }}
    }
    
    public class func pipe<A>(property: [ExecutionProperty], _ f: Dispatcher<A> -> Stream<A>) -> Stream<A> {
        return Streams.source(property) { chan in
            var base: Channel<A>? = nil
            chan.setCloseHandler {
                base?.close()
                base = nil
            }
            f(chan).open(chan.calleeContext) {
                base = $0
                return { chan.emitIfOpen($0) }
            }
        }
    }

}

private func repeatWhile(context: ExecutionContext, delay: Double, f: () -> Bool) {
    context.schedule(nil, delay) {
        if f() { repeatWhile(context, delay, f) }
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
        calleeContext.ensureCurrentlyInCompatibleContext()
        if calleeOpen {
            switch e {
            case .Next:
                callerContext.schedule(calleeContext, 0) {
                    if (self.callerOpen) {
                        self.callerContext.ensureCurrentlyInCompatibleContext()
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
                    self.calleeContext.schedule(self.callerContext, 0) {
                        self.completeToClose()
                    }
                }
            }
        }
    }
    
    public var isClosed: Bool { get { return !calleeOpen } }

    public func setCloseHandler(f: () -> ()) {
        calleeContext.ensureCurrentlyInCompatibleContext()
        assert(closeHandler == nil, "Dispatcher<>#setCloseHandler cannot be called twice.")
        if (calleeOpen) {
            closeHandler = f
        }
    }

    override public func subscribe(f: Packet<A> -> ()) {
        callerContext.ensureCurrentlyInCompatibleContext()
        assert(eventHandler == nil, "Channel<>#subscribe has alreay been called.")
        if (callerOpen) {
            eventHandler = f
        }
    }

    override public func close() {
        callerContext.ensureCurrentlyInCompatibleContext()
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
        closeHandler?()
        closeHandler = nil
        calleeContext.close()
    }

}

class Source<A>: Stream<A> {

    override func open(callerContext: ExecutionContext, _ cont: Cont) -> Channel<A> {
        let chan = Dispatcher<A>(callerContext, isolate(callerContext))
        if let f = cont(chan) {
            chan.subscribe(f)
        }
        chan.calleeContext.schedule(callerContext, 0) {
            self.invoke(chan)
        }
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
        
        var alive = [Channel<B>]()
        var base: Channel<A>? = nil
        var next: (Packet<A> -> ())!
        chan.setCloseHandler {
            base?.close()
            base = nil
            next = nil
            for e in alive { e.close() }
        }
        
        let queue = ArrayDeque<Packet<A>>()
        let block = self.block()
        next = { e in
            if let x = e.value {
                block(x).open(chan.calleeContext) { o in
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
                            if let e = queue.pop() { next(e) }
                        }
                    }
                }
            }
            else if alive.count > 0 {
                queue.push(e)
            }
            else {
                chan.emitIfOpen(.Done())
            }
        }
        outer.open(chan.calleeContext) { ( base = $0 )
            return { e in
                if let x = e.error {
                    chan.emitIfOpen(.Fail(x))
                }
                else if alive.count != self.count {
                    next(e)
                }
                else {
                    queue.unshift(e)
                }
            }
        }
    }
    
    override func isolate(callerContext: ExecutionContext) -> ExecutionContext {
        return callerContext.requires([.AllowSync])
    }
}
