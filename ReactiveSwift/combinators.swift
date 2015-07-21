// Copyright (c) 2014 segfault.jp. All rights reserved.

import Foundation

public extension Stream {

    public func delay(delay: Double) -> Stream<A> {
        return flatMap { Streams.`repeat`($0, delay).take(1) }
    }
    
    public func sample<B>(tick: Stream<B>) -> Stream<(A?, B)> {
        return race(tick, self).innerBind {
            var last: Box<A?> = Box(nil)
            return {
                switch $0 {
                case .Left (let e): return .pure((last.raw, e))
                case .Right(let e):
                    last = Box(e)
                    return .done()
                }
            }
        }
    }
    
    public func sample(interval: Double) -> Stream<A?> {
        return sample(Streams.`repeat`((), interval) ).map { $0.0 }
    }
    
    public func throttle(interval: Double) -> Stream<A> {
        return outerBind {{ .timeout(interval, $0) }}
    }
 
    public func takeWhile(predicate: A -> Bool) -> Stream<A> { return takeWhile { predicate } }
    
    public func skipWhile(predicate: A -> Bool) -> Stream<A> { return skipWhile { predicate } }

    public func take(n: UInt) -> Stream<A> {
        return n > 0 ? takeWhile { counter( n ) } : .done()
    }
    
    public func skip(n: UInt) -> Stream<A> {
        return n > 0 ? skipWhile { counter(n+1) } : self
    }
    
    public func fold<B>(initial: B, _ f: (B, A) -> B) -> Stream<B> {
        return fold(initial) { f }
    }

    public func fold<B>(initial: B, _ f: () -> (B, A) -> B) -> Stream<B> {
        return unpack(pack().innerBind {
            var a = initial
            let g = f()
            return {
                switch $0 {
                case .Done:
                    return .args(.Next(Box(a)), .Done())

                case .Fail(let x):
                    return .pure(.Fail(x))
                    
                case .Next(let x):
                    a = g(a, x.raw)
                    return .done()
                }
            }
        })
    }

    public func recover(aux: NSError -> Stream<A>) -> Stream<A> {
        return unpack(pack().flatMap { e in
            switch e {
            case .Fail(let x):
                return aux(x).pack()
            default:
                return .pure(e)
            }
        })
    }
    
    public func barrier(that: Stream<Stream<A>>) -> Stream<A> {
        return race(self, that).merge {
            var count = 0
            return { $0.fold(
                { o in count == 0 ? .pure(o): .done() },
                { o in
                    ++count
                    return o.onClose { count -= 1 }
                })
            }
        }
    }

    public func fails(error: NSError) -> Stream<A> {
        return unpack(pack().map { e in
            switch e {
            case .Fail: return e
            case .Next: return e
            case .Done: return .Fail(error)
            }
        })
    }
    
    public func takeWhile(predicate: () -> A -> Bool) -> Stream<A> {
        return switchIf(predicate,
            during: { .pure(.Next(Box($0))) },
            follow: { .args(.Next(Box($0)), .Done()) })
    }
    
    public func skipWhile(predicate: () -> A -> Bool) -> Stream<A> {
        return switchIf(predicate,
            during: { _ in .done() },
            follow: { e in .pure(.Next(Box(e))) })
    }
    
    public func nullify<B>() -> Stream<B> { return filter { _ in false }.map { _ in undefined() } }

    public func parMap<B>(f: A -> B) -> Stream<B> {
        return merge {{ e in Streams.exec([.Isolated]) { f(e) } }}
    }
    
    public func continueBy(f: () -> Stream<A>) -> Stream<A> {
        return unpack(pack().flatMap { e in
            switch e {
            case .Done: return f().pack()
            default:
                return .pure(e)
            }
        })
    }
    
    public func closeBy<X>(s: Stream<X>) -> Stream<A> {
        let cut = NSError(domain: "Stream#closeBy", code: 0, userInfo: nil)
        return mix([self, s.flatMap { _ in .fail(cut) }])
        .recover { e in
            e == cut ? .done(): .fail(e)
        }
    }
    
    public func fill<B>(e: B) -> Stream<B> { return map { _ in e } }

}

private func counter<X>(var n: UInt) -> (X -> Bool) { return { _ in --n == 0 } }

public extension Streams {
    
    public class func timeout<A>(delay: Double, _ value: A) -> Stream<A> {
        return `repeat`(value, delay).take(1)
    }

}
    
public func flatten<A>(s: Stream<Stream<A>>) -> Stream<A> { return s.flatMap { $0 } }

public func mix<A>(a: [Stream<A>]) -> Stream<A> { return merge(.list(a)) }

public func seq<A>(a: [Stream<A>]) -> Stream<[A]> {
    return a.reduce(.pure([])) { zip($0, $1).map { $0.0 + [$0.1] } }
}

public func concat<A>(a: [Stream<A>]) -> Stream<A> { return flatten(.list(a)) }

public func race<A, B>(a: Stream<A>, _ b: Stream<B>) -> Stream<Either<A, B>>
{
    return mix([a.map { .Left($0) }, b.map { .Right($0) }])
}

public func distinct<A: Equatable>(s: Stream<A>) -> Stream<A> {
    return s.innerBind {
        var last: A? = nil
        return { e in
            if (last != e) {
                last  = e
                return .pure(e)
            }
            else {
                return .done()
            }
        }
    }
}

// TODO HList
public func combineLatest<A, B>(a: Stream<A>, _ b: Stream<B>) -> Stream<(A, B)> {
    return race(a, b).innerBind {
        var lhs: Box<A>? = nil
        var rhs: Box<B>? = nil
        return {
            switch $0 {
            case .Left (let e): lhs = Box(e)
            case .Right(let e): rhs = Box(e)
            }
            return (lhs != nil && rhs != nil
                ? .pure((lhs!.raw, rhs!.raw))
                : .done())
        }
    }
}

// TODO done, HList
public func zip<A, B>(a: Stream<A>, _ b: Stream<B>) -> Stream<(A, B)> {
    // let exit = NSError()
    return race(a /* .fails(exit) */, b /* .fails(exit) */).innerBind {
        let queue = ArrayDeque<Either<A, B>>()
        return { e in
            switch ((queue.head, e)) {
            case ((.Some(.Left(let l)), .Right(let r))):
                queue.shift()
                return .pure((l, r))
                
            case ((.Some(.Right(let r)), .Left(let l))):
                queue.shift()
                return .pure((l, r))
                
            default:
                queue.push(e)
                return .done()
            }
        }
    }
    // .recover { $0 === exit ? Streams.done(): Streams.fail($0) }
}

public func compact<A>(s: Stream<A?>) -> Stream<A> {
    return s.flatMap { $0.map(Streams.pure) ?? .done() }
}

public func + <A>(a: Stream<A>, b: Stream<A>) -> Stream<A> { return concat([a, b]) }

extension Channel {
    
    public func autoclose() -> Channel<A> {
        return AutoClosing(self)
    }
    
    public func publish() -> Stream<A> {
        return PublishSource(autoclose())
    }
    
}

private class AutoClosing<A>: Channel<A> {

    var origin: Channel<A>?
    
    init(_ origin: Channel<A>) { self.origin = origin }
    
    deinit { origin?.close() }
    
    override func subscribe(f: Packet<A> -> ()) {
        origin?.subscribe(f)
    }
    
    override func close() {
        origin?.close()
        origin = nil
    }
    
}

private class PublishSource<A>: ForeignSource<A> {
    
    private var channel: Channel<A>!
    
    required init(_ channel: Channel<A>) {
        super.init()
        self.channel = channel
        self.channel.subscribe(emit)
    }
    
}
