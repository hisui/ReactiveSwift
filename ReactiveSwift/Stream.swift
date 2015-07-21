// Copyright (c) 2014 segfault.jp. All rights reserved.

import Foundation

/// A composable object which represents an event stream where multiple events are flowing.
public class Stream<A>: Streams {

    public func subscribe(f: Packet<A> -> ()) { return open().subscribe(f) }

    public func open(callerContext: ExecutionContext, _ cont: Channel<A> -> ()) -> Channel<A> {
        return undefined()
    }
    
    public func open(callerContext: ExecutionContext) -> Channel<A> {
        return open(callerContext) { _ in }
    }
    
    public func open() -> Channel<A> { return open(GCDExecutionContext()) }

}

/// A subscription of an event stream.
public class Channel<A> {
    
    public func subscribe(f: Packet<A> -> ()) { return undefined() }
    
    public func close() {}

}

/// An event.
public enum Packet<A> {

    case Done()
    case Fail(NSError)
    case Next(Box <A>)

    public var value: A? {
        switch self {
        case .Next(let x): return +x
        default:
            return nil
        }
    }
    
    public var error: NSError? {
        switch self {
        case .Fail(let x): return x
        default:
            return nil
        }
    }
    
    public func map<B>(f: A -> B) -> Packet<B> {
        switch self {
        case let .Next(x): return .Next(x.map(f))
        case let .Fail(x): return .Fail(x)
        case     .Done( ): return .Done( )
        }
    }
    
    public func nullify<B>() -> Packet<B> { return map { _ in undefined() } }

}

public extension Stream {
    
    public func merge<B>(f: () -> A -> Stream<B>) -> Stream<B> { return merge(Int.max, f) }
    
    public func merge<B>(count: Int, _ f: () -> A -> Stream<B>) -> Stream<B> {
        return Merge(self, f, count)
    }

    public func innerBind<B>(f: () -> A -> Stream<B>) -> Stream<B> { return merge(1, f) }
    
    public func outerBind<B>(f: () -> A -> Stream<B>) -> Stream<B> {
        return merge {
            var last: Dispatcher<B>?
            let bind = f()
            return { e in
                return pipe([.AllowSync]) {
                    last?.emitIfOpen(.Done())
                    last = $0
                    return bind(e)
                }
            }
        }
    }
    
    public func flatMap<B>(f: A -> Stream<B>) -> Stream<B> { return innerBind({f}) }
    
    public func map<B>(f: A -> B) -> Stream<B> { return flatMap { .pure(f($0)) } }

    public func filter(predicate: A -> Bool) -> Stream<A> {
        return flatMap { predicate($0) ? .pure($0): .done() }
    }

    public func pack() -> Stream<Packet<A>> {
        return Streams.source([.AllowSync]) { chan in
            var base: Channel<A>?
            chan.setCloseHandler {
                base?.close()
                base = nil
            }
            self.open(chan.calleeContext) {
                base = $0
                base!.subscribe {
                    chan.emitIfOpen(.Next(Box($0)))
                }
            }
        }
    }

    public func onClose(action: () -> ()) -> Stream<A> {
        return Streams.source([.AllowSync]) { chan in
            var base: Channel<A>?
            chan.setCloseHandler {
                chan.callerContext.schedule(chan.calleeContext, 0, action)
                base?.close()
                base = nil
            }
            self.open(chan.calleeContext) {
                base = $0
                base!.subscribe { chan.emitIfOpen($0) }
            }
        }
    }
    
    public func foreach(action: A -> ()) -> Stream<A> {
        return map {
            action($0)
            return $0
        }
    }
    
    public func isolated<B>(f: Stream<A> -> Stream<B>) -> Stream<B> { return isolated([.Isolated], f) }
    
    public func isolated<B>(property: [ExecutionProperty], _ f: Stream<A> -> Stream<B>) -> Stream<B> {
        return flatMap { e in
            pipe(property) { _ in f(.pure(e)) }
        }
    }

    public func zipWith<B>(value: B) -> Stream<(A, B)> { return map { ($0, value) } }
    
    public func zipWithContext() -> Stream<(A, ExecutionContext)> {
        return pipe([.AllowSync]) { self.zipWith($0.calleeContext) }
    }

    // Carrying inside streams out of the outside stream causes to lose "stability of meaning" of stream.
    public func groupBy<K: Hashable>(f: A -> K) -> Stream<Stream<(K, A)>> {
        return Streams.source([.AllowSync]) { outer in
            var base: Channel<A>?
            var map = [K: ForeignSource<(K, A)>]()
            outer.setCloseHandler {
                map.removeAll(keepCapacity: false)
                base?.close()
                base = nil
            }
            self.open(outer.calleeContext) {
                base = $0
                base!.subscribe { e in
                    switch e {
                    case .Next(let x):
                        let k = f(+x)
                        var chan = map[k]
                        if (chan == nil) {
                            chan = ForeignSource()
                            map[k] = chan
                            outer.emitIfOpen(.Next(Box(chan!)))
                        }
                        chan!.emitValue((k, x.raw))
                    default:
                        for o in map.values { o.emit(e.nullify()) }
                        outer.emit(e.nullify())
                    }
                }
            }
        }
    }
    
    public func switchIf<B>(predicate: () -> A -> Bool
        , during: A -> Stream<Packet<B>>
        , follow: A -> Stream<Packet<B>>) -> Stream<B>
    {
        return unpack(innerBind {
            let f = predicate()
            var b = false
            return { e in
                if !b {
                    b = f(e)
                }
                return ( b ? follow(e): during(e) )
            }
        })
    }

}

func undefined<X>() -> X { abort() }

public class Streams {

    public class func source<A>(f: Dispatcher<A> -> ()) -> Stream<A> { return source([], f) }
    
    public class func source<A>(property: [ExecutionProperty], _ f: Dispatcher<A> -> ()) -> Stream<A> {
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
            for var i = 0; i < a.count && !chan.isClosed; ++i {
                chan.emitValue(a[i])
            }
            chan.emitIfOpen(.Done())
        }
    }
    
    public class func exec<A>(property: [ExecutionProperty], f: () -> A) -> Stream<A> {
        return source(property) { $0.flush(f()) }
    }
    
    public class func lazy<A>(f: () -> A) -> Stream<A> {
        return source([.AllowSync]) { $0.flush(f()) }
    }
    
    public class func range<A: ForwardIndexType>(range: Range<A>) -> Stream<A> {
        return source { chan in
            for e in range {
                if !chan.isClosed { chan.emitValue(e) }
            }
            chan.emitIfOpen(.Done())
        }
    }

    public class func args<A>(a: A...) -> Stream<A> { return list(a) }

    public class func `repeat`<A>(value: A, _ delay: Double) -> Stream<A> {
        return Streams.source { chan in
            var holder: A? = value
            chan.setCloseHandler {
                holder = nil
            }
            repeatWhile(chan.calleeContext, delay: delay) {
                if let e = holder {
                    chan.emitIfOpen(.Next(Box(e)))
                }
                return !chan.isClosed
            }
        }
    }

}

public func unpack<A>(s: Stream<Packet<A>>) -> Stream<A> {
    return Streams.source([.AllowSync]) { chan in
        var base: Channel<Packet<A>>?
        chan.setCloseHandler {
            base?.close()
            base = nil
        }
        s.open(chan.calleeContext) {
            base = $0
            base!.subscribe {
                chan.emitIfOpen($0 >>| { $0 })
            }
        }
    }
}

public func merge<A>(a: Stream<Stream<A>>, _ count: Int = Int.max) -> Stream<A> {
    return a.merge(count) {{ $0 }}
}

private func pipe<A>(property: [ExecutionProperty], f: Dispatcher<A> -> Stream<A>) -> Stream<A> {
    return Streams.source(property) { chan in
        var base: Channel<A>?
        chan.setCloseHandler {
            base?.close()
            base = nil
        }
        f(chan).open(chan.calleeContext) {
            base = $0
            base!.subscribe { chan.emitIfOpen($0) }
        }
    }
}

private func repeatWhile(context: ExecutionContext, delay: Double, f: () -> Bool) {
    context.schedule(nil, delay) {
        if f() { repeatWhile(context, delay: delay, f: f) }
    }
}

/// An instance of this class emits events to `Channel` corresponding to itself.
public class Dispatcher<A>: Channel<A> {
    
    // TODO It shall be separated into `Channel` and `Dispatcher` alone..
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
        emitValue(e)
        emitIfOpen(.Done())
    }
    
    public func emitValue(e: A) {
        emit(.Next(Box(e)))
    }

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

public class ForeignSource<A>: Source<A> {
    
    private var channels = [Dispatcher<A>] ()
    
    deinit {
        for chan in channels {
            chan.calleeContext.schedule(nil, 0) {
                chan.emitIfOpen(.Done())
            }
        }
    }
    
    public override init() {}
    
    public final func emitValue(a: A) { emit(.Next(Box(a))) }
    
    public final func emit(a: Packet<A>) {
        // TODO close
        for chan in channels {
            chan.calleeContext.schedule(nil, 0) {
                chan.emitIfOpen(a)
            }
        }
    }
    
    override func invoke(chan: Dispatcher<A>) {
        chan.setCloseHandler { [weak self] in
            for i in 0 ..< (self?.channels.count ?? 0) { // TODO thread safe
                if (self!.channels[i] === chan) {
                    self!.channels.removeAtIndex(i)
                    break
                }
            }
        }
        channels.append(chan)
    }

    override func isolate(callerContext: ExecutionContext) -> ExecutionContext {
        return callerContext.requires([.AllowSync])
    }
    
    public var subscribers: Int { return channels.count }
    
}

class Source<A>: Stream<A> {

    override func open(callerContext: ExecutionContext, _ cont: Channel<A> -> ()) -> Channel<A> {
        let (chan) = Dispatcher<A>(callerContext, isolate(callerContext))
        cont(chan)
        chan.calleeContext.schedule(callerContext, 0) { self.invoke(chan) }
        return chan
    }
    
    func invoke(chan: Dispatcher<A>) { return undefined() }
    
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
        var base: Channel<A>?
        var next: (Packet<A> -> ())!
        chan.setCloseHandler {
            base?.close()
            base = nil
            next = nil
            for e in alive { e.close() }
        }
        
        let queue = ArrayDeque<Packet<A>>()
        let block = self.block()
        let count = self.count
        next = { e in
            if let x = e.value {
                block(x).open(chan.calleeContext) { inner in
                    alive.append(inner)
                    inner.subscribe { e in
                        switch e {
                        case let .Next(_): chan.emitIfOpen(e)
                        case let .Fail(x): chan.emitIfOpen(.Fail(x))
                            fallthrough
                        default:
                            for i in 0 ..< alive.count {
                                if (alive[i] === inner) {
                                    alive.removeAtIndex(i)
                                    break
                                }
                            }
                            if let o = queue.pop() { next?(o) }
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
        outer.open(chan.calleeContext) {
            base = $0
            base!.subscribe { e in
                if let x = e.error {
                    chan.emitIfOpen(.Fail(x))
                }
                else if alive.count != count {
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
