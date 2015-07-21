// Copyright (c) 2014 segfault.jp. All rights reserved.

infix operator >>| { associativity left precedence 95 }

// experimental
public protocol Monad {
    typealias Obj
    func >>| (fa: Self, f: Obj -> Self) -> Self
    static func pure(a: Obj) -> Self
}

public func pure<MA: Monad>(a: MA.Obj) -> MA { return MA.pure(a) }

extension Either: Monad {
    public typealias Obj = R
    public static func pure(a: R) -> Either<L, R> { return .Right(a) }
}

public func >>| <L, A, B>(ma: Either<L, A>, f: A -> Either<L, B>) -> Either<L, B> {
    switch ma {
    case .Left (let e): return .Left(e)
    case .Right(let e): return f(e)
    }
}

extension Packet: Monad {
    typealias Obj = A
    public static func pure(a: A) -> Packet<A> { return .Next(a) }
}

public func >>| <A, B>(ma: Packet<A>, f: A -> Packet<B>) -> Packet<B> {
    switch ma {
    case let .Next(e): return f(e)
    case let .Fail(x): return .Fail(x)
    case     .Done   : return .Done
    }
}

public func >>| <A, B>(ma: A?, f: A -> B?) -> B? {
    switch ma {
    case let .Some(a): return f(a)
    case     .None( ): return .None
    }
}
