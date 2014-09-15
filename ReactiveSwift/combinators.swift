// Copyright (c) 2014 segfault.jp. All rights reserved.

import Foundation

public extension Stream {

    public func delay(delay: Double) -> Stream<A> { return self >>+ { Streams.timeout(delay, $0) } }
 
    public func takeWhile(predicate: A -> Bool) -> Stream<A> { return takeWhile_0 { predicate } }
    
    public func skipWhile(predicate: A -> Bool) -> Stream<A> { return skipWhile_0 { predicate } }

    public func take(n: UInt) -> Stream<A> {
        return n > 0 ? takeWhile_0 { counter( n ) } : Streams.done()
    }
    
    public func skip(n: UInt) -> Stream<A> {
        return n > 0 ? skipWhile_0 { counter(n+1) } : self
    }

    public func fold<B>(initial: B, _ f: () -> (B, A) -> B) -> Stream<B> {
        return Streams.unpack(self.pack().innerBind {
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
        return Streams.unpack(pack().flatMap { e in
            switch e {
            case .Fail(let x):
                return aux(x).pack()
            default:
                return Streams.pure(e)
            }
        })
    }
    
    // TODO
    public func groupBy<K: Hashable, Equatable>(f: A -> K) -> Stream<(K, Stream<A>)> {
        abort()
    }
    
    // TODO test, error, done
    public func barrier(that: Stream<Stream<A>>) -> Stream<A> {
        return Streams.source { chan in
            var block: Channel<A>? = nil
            var inner: Channel<A>? = nil
            var outer: Channel<Stream<A>>? = nil
            chan.setCloseHandler {
                block?.close()
                inner?.close()
                outer?.close()
            }
            self.open(chan.calleeContext) { (block = $0)
                return { if inner == nil { chan.emitIfOpen($0) } }
            }
            that.open(chan.calleeContext) { (outer = $0)
                return { $0.value?
                    .onClose { inner = nil }
                    .open(chan.calleeContext) {
                        inner = $0
                        return { if let o = $0.value { chan.emitIfOpen(.Next(Box(o))) } }
                    }
                    ()
                }
            }
        }
    }

    public func fails(error: NSError) -> Stream<A> {
        return Streams.unpack(pack().map { e in
            switch e {
            case .Fail: return e
            case .Next: return e
            case .Done: return .Fail(error)
            }
        })
    }

    public func switchIf<B>(predicate: () -> A -> Bool
        , during: A -> Stream<Packet<B>>
        , follow: A -> Stream<Packet<B>>) -> Stream<B>
    {
        return Streams.unpack(self.innerBind {
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
    
    private func takeWhile_0(predicate: () -> A -> Bool) -> Stream<A> {
        return switchIf(predicate,
            during: { Streams.pure(.Next(Box($0))) },
            follow: { Streams.args(.Next(Box($0)), .Done()) })
    }
    
    private func skipWhile_0(predicate: () -> A -> Bool) -> Stream<A> {
        return switchIf(predicate,
            during: { _ in Streams.done() },
            follow: { e in Streams.pure(.Next(Box(e))) })
    }

}

private func counter<X>(var n: UInt) -> (X -> Bool) { return { _ in --n == 0 } }

public extension Streams {
    
    public class func flatten<A>(s: Stream<Stream<A>>) -> Stream<A> { return s >>+ { $0 } }
    
    public class func mix<A>(a: [Stream<A>]) -> Stream<A> { return a.reduce(done(), (><)) }
    
    public class func seq<A>(a: [Stream<A>]) -> Stream<[A]> {
        return a.reduce(pure([])) { Streams.conj($0, $1).map { $0.0 + [$0.1] } }
    }

    public class func concat<A>(a: [Stream<A>]) -> Stream<A> { return flatten(list(a)) }
    
    public class func race<A, B>(a: Stream<A>, _ b: Stream<B>) -> Stream<Either<A, B>>
    {
        return a.map { .Left(Box($0)) } >< b.map { .Right(Box($0)) }
    }
    
    public class func distinct<A: Equatable>(s: Stream<A>) -> Stream<A> {
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
    public class func disj<A, B>(a: Stream<A>, _ b: Stream<B>) -> Stream<(A, B)> {
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
    public class func conj<A, B>(a: Stream<A>, _ b: Stream<B>) -> Stream<(A, B)> {
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

}
