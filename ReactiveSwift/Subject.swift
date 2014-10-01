// Copyright (c) 2014 segfault.jp. All rights reserved.

import Foundation

public class Subject<A>: SubjectSource<A> {

    private var last: A
    
    public init(_ initialValue: A) { self.last = initialValue }

    public var value: A {
        set(a) {
            last = a
            commit(a, self as AnyObject)
        }
        get { return last }
    }

    override func initialValue() -> A? { return value }

    public func bimap<B>(f: A -> B, g: B -> A) -> Subject<B> {
        let peer = Subject<B>(f(last))
        setMappingBetween2(self, peer, f)
        setMappingBetween2(peer, self, g)
        return peer
    }

}

public class Update<A> {
    
    public let sender: AnyObject?
    public let detail: A
    
    public init(_ detail: A, _ sender: AnyObject? = nil) {
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
        println("deinit!!!")
        for chan in channels {
            chan.calleeContext.schedule(nil, 0) {
                chan.emitIfOpen(.Done())
            }
        }
    }
    
    func apply(a: Update<A>) { return undefined() }

    func commit(a: A, _ sender: AnyObject? = nil) {
        commit(Update(a, sender))
    }
    
    func commit(a: Update<A>) {
        for chan in channels {
            chan.calleeContext.schedule(nil, 0) {
                chan.emitIfOpen(.Next(Box(a)))
            }
        }
    }
    
    func initialValue() -> UpdateItem? { return nil }

    override final func invoke(chan: Dispatcher<Update<A>>) {
        chan.setCloseHandler { [weak self] in
            for i in 0 ..< (self?.channels.count ?? 0) { // TODO thread safe
                if (self!.channels[i] === chan) {
                    self!.channels.removeAtIndex(i)
                    break
                }
            }
        }
        channels.append(chan)
        if let o = initialValue() {
            chan.emitValue(Update(o, self))
        }
    }
    
    public var subscribers: Int { return channels.count }
    
    public var unwrap: Stream<A> { return map { $0.detail } }

}

// TODO fixes memory leak
func setMappingBetween2<A, B>(a: SubjectSource<A>, b: SubjectSource<B>, f: A -> B) {
    a.skip(1).subscribe {
        if let o = $0.value { if o.sender !== b { b.apply(o.map(f)) } }
    }
}
