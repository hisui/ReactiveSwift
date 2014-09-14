// Copyright (c) 2014 segfault.jp. All rights reserved.

public enum Either<L, R> {
    
    case  Left(Box<L>), Right(Box<R>)
    
    func fold<V>(lhs: L -> V, rhs: R -> V) -> V {
        switch self {
        case .Left (let box): return lhs(+box)
        case .Right(let box): return rhs(+box)
        }
    }
    
    public var right: R? { get {
        switch self {
        case .Right(let box): return +box
        default:
            return nil
        }
    }}
}
