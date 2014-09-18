// Copyright (c) 2014 segfault.jp. All rights reserved.

// TODO w/a
public class Box<A> {
    
    public let raw: A
    
    public init(_ raw: A) { self.raw = raw }
    
    public func map<B>(f: A -> B) -> Box<B> { return Box<B>(f(raw)) }
}

@transparent prefix func + <T>(box: Box<T>) -> T { return box.raw }
