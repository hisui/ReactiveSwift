// Copyright (c) 2014 segfault.jp. All rights reserved.

import Foundation

public class Subject<A>: SubjectSource<A> {

    private var last: A
    
    public init(_ initialValue: A, _ name: String = __FUNCTION__) {
        self.last = initialValue
        super.init(name)
    }

    public var value: A {
        set(a) {
            merge(Update(a, self as AnyObject))
        }
        get { return last }
    }
    
    public func update(a: A, by o: AnyObject) {
        merge(Update(a, o))
    }
    
    override public func merge(a: Update<A>) {
        last = a.detail
        commit(a)
    }

    override public var firstValue: Box<A> { return Box(last) }

    public func bimap<B>(f: A -> B, _ g: B -> A, _ context: ExecutionContext) -> Subject<B> {
        let peer = Subject<B>(f(last))
        setMappingBetween2(self, b: peer, f: f, context: context)
        setMappingBetween2(peer, b: self, f: g, context: context)
        return peer
    }

}

public class Update<A> {
    
    public let sender: AnyObject?
    public let detail: A
    
    public init(_ detail: A, _ sender: AnyObject?) {
        self.sender = sender
        self.detail = detail
    }
    
    public func map<B>(f: A -> B) -> Update<B> { return Update<B>(f(detail), sender) }

}

public class SubjectSource<A>: ForeignSource<Update<A>>, Mergeable {
    
    public let name: String
    
    public typealias UpdateDiff = A
    public typealias UpdateType = Update<A>
    
    public init(_ name: String = __FUNCTION__) {
        self.name = name
    }
    
    public func merge(a: Update<A>) { return undefined() }

    // TODO protected
    public func commit(a: Update<A>) { emitValue(a) }
    
    var firstValue: Box<A> {
        return undefined()
    }

    override final func invoke(chan: Dispatcher<Update<A>>) {
        super.invoke(chan)
        chan.emitValue(Update(+firstValue, self))
    }
    
    public var unwrap: Stream<A> { return map { $0.detail } }

}

public protocol Mergeable {
    
    typealias UpdateDiff
    
    func merge(a: Update<UpdateDiff>)
}

func setMappingBetween2<A, B>(a: SubjectSource<A>, b: SubjectSource<B>, f: A -> B, context: ExecutionContext) {
    (setMappingBetween2(a, b: b, f: f) as Stream<()>).open(context)
}

// TODO fixes memory leak
func setMappingBetween2<A, B, X>(a: SubjectSource<A>, b: SubjectSource<B>, f: A -> B) -> Stream<X> {
    return a.skip(1)
    .foreach { o in
        if o.sender !== b { b.merge(o.map(f)) }
    }
    .nullify()
}
