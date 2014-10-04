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

    override public func firstValue() -> Box<A> { return Box(last) }

    public func bimap<B>(f: A -> B, _ g: B -> A, _ context: ExecutionContext) -> Subject<B> {
        let peer = Subject<B>(f(last))
        setMappingBetween2(self, peer, f, context)
        setMappingBetween2(peer, self, g, context)
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

public class SubjectSource<A>: ForeignSource<Update<A>> {
    
    public let name: String
    
    typealias UpdateItem = A
    typealias UpdateType = Update<A>
    
    public init(_ name: String = __FUNCTION__) {
        self.name = name
    }
    
    public func merge(a: Update<A>) { return undefined() }

    func commit(a: Update<A>) { emitValue(a) }
    
    func firstValue() -> Box<UpdateItem> {
        return undefined()
    }

    override final func invoke(chan: Dispatcher<Update<A>>) {
        super.invoke(chan)
        chan.emitValue(Update(+firstValue(), self))
    }
    
    public var unwrap: Stream<A> { return map { $0.detail } }

}

public class ForeignSource<A>: Source<A> {
    
    private var channels = [Dispatcher<A>] ()
    
    deinit {
        for chan in channels {
            chan.calleeContext.schedule(nil, 0) {
                chan.emitIfOpen(.Done())
            }
        }
    }
    
    final func emitValue(a: A) { emit(.Next(Box(a))) }

    final func emit(a: Packet<A>) {
        // TODO
        for chan in channels {
            chan.calleeContext.schedule(nil, 0) {
                chan.emitIfOpen(a)
            }
        }
    }
    
    override func invoke(chan: Dispatcher<A>) {
        chan.setCloseHandler { [weak self] in
            for i in 0 ..< (self?.channels.count ?? 0) { // TODO thread safe
                if (self!.channels[i] === chan) {
                    self!.channels.removeAtIndex(i)
                    break
                }
            }
        }
        channels.append(chan)
    }

    override func isolate(callerContext: ExecutionContext) -> ExecutionContext {
        return callerContext.requires([.AllowSync])
    }

    public var subscribers: Int { return channels.count }
    
}

func setMappingBetween2<A, B>(a: SubjectSource<A>, b: SubjectSource<B>, f: A -> B, context: ExecutionContext) {
    (setMappingBetween2(a, b, f) as Stream<()>).open(context)
}

// TODO fixes memory leak
func setMappingBetween2<A, B, X>(a: SubjectSource<A>, b: SubjectSource<B>, f: A -> B) -> Stream<X> {
    return a.skip(1)
    .foreach { o in
        if o.sender !== b { b.merge(o.map(f)) }
    }
    .nullify()
}
