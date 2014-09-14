// Copyright (c) 2014 segfault.jp. All rights reserved.

infix operator >>| { associativity left precedence 95 }

// experimental
public protocol Monad {
    typealias Obj
    func >>| (fa: Self, f: Obj -> Self) -> Self
    class func pure(a: Obj) -> Self
}

public func pure<MA: Monad>(a: MA.Obj) -> MA { return MA.pure(a) }

// public func join<MA: Monad where MA.Obj == MA>(ma: MA) -> MA.Obj { return ma >>| { $0 } }

extension Either: Monad {
    public typealias Obj = R
    public static func pure(a: R) -> Either<L, R> { return .Right(Box(a)) }
}

public func >>| <L, A, B>(ma: Either<L, A>, f: A -> Either<L, B>) -> Either<L, B> {
    switch ma {
    case .Left (let box): return .Left(box)
    case .Right(let box): return f(+box)
    }
}

extension Stream: Monad {
    typealias Obj = A
    public static func pure(a: A) -> Stream<A> { return Streams.pure(a) }
}

public func >>| <A, B>(ma: Stream<A>, f: A -> Stream<B>) -> Stream<B> {
    return ma.flatMap(f)
}

extension Packet: Monad {
    typealias Obj = A
    public static func pure(a: A) -> Packet<A> { return .Next(Box(a)) }
}

public func >>| <A, B>(ma: Packet<A>, f: A -> Packet<B>) -> Packet<B> {
    switch ma {
    case let .Next(x): return f(+x)
    case let .Fail(x): return .Fail(x)
    case let .Done   : return .Done( )
    }
}
