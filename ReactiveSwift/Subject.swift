// Copyright (c) 2014 segfault.jp. All rights reserved.

import Foundation

public class Subject<A>: SubjectSource<A> {

    private var last: A
    
    public init(_ initialValue: A) { self.last = initialValue }

    public var value: A {
        set(a) {
            merge(Update(a, self as AnyObject))
        }
        get { return last }
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

public class SubjectSource<A>: Source<Update<A>> {
    
    typealias UpdateItem = A
    typealias UpdateType = Update<A>
    
    private var channels = [Dispatcher<Update<A>>] ()
    
    deinit {
        for chan in channels {
            chan.calleeContext.schedule(nil, 0) {
                chan.emitIfOpen(.Done())
            }
        }
    }
    
    public func merge(a: Update<A>) { return undefined() }

    func commit(a: Update<A>) {
        // TODO
        for chan in channels {
            chan.calleeContext.schedule(nil, 0) {
                chan.emitIfOpen(.Next(Box(a)))
            }
        }
    }
    
    func firstValue() -> Box<UpdateItem> {
        return undefined()
    }

    override final func invoke(chan: Dispatcher<Update<A>>) {
        chan.emitValue(Update(+firstValue(), self))
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
    
    // TODO
    override final func isolate(callerContext: ExecutionContext) -> ExecutionContext {
        callerContext.ensureCurrentlyInCompatibleContext()
        return callerContext.requires([.AllowSync])
    }
    
    public var subscribers: Int { return channels.count }
    
    public var unwrap: Stream<A> { return map { $0.detail } }

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
