// Copyright (c) 2014 segfault.jp. All rights reserved.

public enum Either<L, R> {
    
    case Left(L), Right(R)
    
    public func fold<V>(lhs: L -> V, _ rhs: R -> V) -> V {
        switch self {
        case .Left (let e): return lhs(e)
        case .Right(let e): return rhs(e)
        }
    }
    
    public var right: R? {
        switch self {
        case .Right(let e): return e
        default:
            return nil
        }
    }
}
