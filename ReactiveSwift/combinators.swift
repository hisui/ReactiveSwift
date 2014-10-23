// Copyright (c) 2014 segfault.jp. All rights reserved.

import Foundation

public extension Stream {

    public func delay(delay: Double) -> Stream<A> {
        return flatMap { Streams.repeat($0, delay).take(1) }
    }
    
    public func sample<B>(tick: Stream<B>) -> Stream<(A?, B)> {
        return race(tick, self).innerBind {
            var last: Box<A?> = Box(nil)
            return {
                switch $0 {
                case .Left (let box): return Streams.pure((last.raw, box.raw))
                case .Right(let box):
                    last = Box(+box)
                    return Streams.done()
                }
            }
        }
    }
    
    public func sample(interval: Double) -> Stream<A?> {
        return sample(Streams.repeat((), interval) ).map { $0.0 }
    }
    
    public func throttle(interval: Double) -> Stream<A> {
        return outerBind {{ Streams.timeout(interval, $0) }}
    }
 
    public func takeWhile(predicate: A -> Bool) -> Stream<A> { return takeWhile { predicate } }
    
    public func skipWhile(predicate: A -> Bool) -> Stream<A> { return skipWhile { predicate } }

    public func take(n: UInt) -> Stream<A> {
        return n > 0 ? takeWhile { counter( n ) } : Streams.done()
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
            var g = f()
            return {
                switch $0 {
                case .Done:
                    return Streams.args(.Next(Box(a)), .Done())

                case .Fail(let x):
                    return Streams.pure(.Fail(x))
                    
                case .Next(let x):
                    a = g(a, x.raw)
                    return Streams.done()
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
                return Streams.pure(e)
            }
        })
    }
    
    public func barrier(that: Stream<Stream<A>>) -> Stream<A> {
        return race(self, that).merge {
            var count = 0
            return { $0.fold(
                { o in count == 0 ? Streams.pure(o): Streams.done() },
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
            during: { Streams.pure(.Next(Box($0))) },
            follow: { Streams.args(.Next(Box($0)), .Done()) })
    }
    
    public func skipWhile(predicate: () -> A -> Bool) -> Stream<A> {
        return switchIf(predicate,
            during: { _ in Streams.done() },
            follow: { e in Streams.pure(.Next(Box(e))) })
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
                return Streams.pure(e)
            }
        })
    }
    
    public func closeBy<X>(s: Stream<X>) -> Stream<A> {
        let cut = NSError()
        return mix([self, s.flatMap { _ in Streams.fail(cut) }])
        .recover { e in
            e == cut ? Streams.done( ):
                       Streams.fail(e)
        }
    }
    
    public func fill<B>(e: B) -> Stream<B> { return map { _ in e } }

}

private func counter<X>(var n: UInt) -> (X -> Bool) { return { _ in --n == 0 } }

public extension Streams {
    
    public class func timeout<A>(delay: Double, _ value: A) -> Stream<A> {
        return repeat(value, delay).take(1)
    }

}
    
public func flatten<A>(s: Stream<Stream<A>>) -> Stream<A> { return s.flatMap { $0 } }

public func mix<A>(a: [Stream<A>]) -> Stream<A> { return merge(Streams.list(a)) }

public func seq<A>(a: [Stream<A>]) -> Stream<[A]> {
    return a.reduce(Streams.pure([])) { zip($0, $1).map { $0.0 + [$0.1] } }
}

public func concat<A>(a: [Stream<A>]) -> Stream<A> { return flatten(Streams.list(a)) }

public func race<A, B>(a: Stream<A>, b: Stream<B>) -> Stream<Either<A, B>>
{
    return mix([a.map { .Left(Box($0)) }, b.map { .Right(Box($0)) }])
}

public func distinct<A: Equatable>(s: Stream<A>) -> Stream<A> {
    return s.innerBind {
        var last: A? = nil
        return { e in
            if (last != e) {
                last  = e
                return Streams.pure(e)
            }
            else {
                return Streams.done()
            }
        }
    }
}

// TODO HList
public func combineLatest<A, B>(a: Stream<A>, b: Stream<B>) -> Stream<(A, B)> {
    return race(a, b).innerBind {
        var lhs: Box<A>? = nil
        var rhs: Box<B>? = nil
        return {
            switch $0 {
            case .Left (let box): lhs = box
            case .Right(let box): rhs = box
            }
            return (lhs != nil && rhs != nil
                ? Streams.pure((lhs!.raw, rhs!.raw))
                : Streams.done())
        }
    }
}

// TODO done, HList
public func zip<A, B>(a: Stream<A>, b: Stream<B>) -> Stream<(A, B)> {
    // let exit = NSError()
    return race(a /* .fails(exit) */, b /* .fails(exit) */).innerBind {
        let queue = ArrayDeque<Either<A, B>>()
        return { e in
            switch ((queue.head, e)) {
            case ((.Some(.Left(let l)), .Right(let r))):
                queue.shift()
                return Streams.pure((l.raw, r.raw))
                
            case ((.Some(.Right(let r)), .Left(let l))):
                queue.shift()
                return Streams.pure((l.raw, r.raw))
                
            default:
                queue.push(e)
                return Streams.done()
            }
        }
    }
    // .recover { $0 === exit ? Streams.done(): Streams.fail($0) }
}

public func compact<A>(s: Stream<A?>) -> Stream<A> {
    return s.flatMap { e in
        if let o = e {
            return Streams.pure(o)
        }
        else {
            return Streams.done( )
        }
    }
}

extension Channel {
    public func autoclose() -> Channel<A> { return AutoClosing(self) }
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
