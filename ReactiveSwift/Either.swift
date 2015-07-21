// Copyright (c) 2014 segfault.jp. All rights reserved.

public enum Either<L, R> {
    
    case Left(L), Right(R)
    
    public func fold<V>(@noescape lhs: L -> V, @noescape _ rhs: R -> V) -> V {
        switch self {
        case .Left (let e): return lhs(e)
        case .Right(let e): return rhs(e)
        }
    }
    
    public var right: R? { return fold(null, {$0}) }
    public var  left: L? { return fold({$0}, null) }
    
}

func null<A, B>(_: A) -> B? { return nil }

public func == <L: Equatable, R: Equatable>(lhs: Either<L, R>, rhs: Either<L, R>) -> Bool {
    return lhs.fold({$0 == rhs.left}, {$0 == rhs.right})
}
