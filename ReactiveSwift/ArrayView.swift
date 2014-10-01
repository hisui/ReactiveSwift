// Copyright (c) 2014 segfault.jp. All rights reserved.

import Foundation

public class ArrayView<E>: SubjectSource<Update<AnyObject?, [ArrayDiff<E>]>> {
    
    typealias UpdateType = Update<AnyObject?, [ArrayDiff<E>]>

    public subscript(i: Int) -> E? { return nil }
    
    public func map<F>(f: E -> F) -> ArrayView<F> { return ArrayView<F>() }

    // TODO Swift compiler does'nt support overriding getter/setter yet
    // public var count: UInt { return undefined() }
    // public var array: [E]  { return undefined() }
    
    public func size() -> UInt { return 0 }

}

public class ArrayCollection<E>: ArrayView<E> {

    private var raw: [E]
    
    init(_ a: [E] = []) { raw = a }
    
    override func invoke(chan: Dispatcher<UpdateType>) {
        super.invoke(chan)
        super.emitValue(UpdateType(self, [ArrayDiff<E>(0, 0, raw)]))
    }
    
    public override subscript(i: Int) -> E? {
        get { return ((0 ..< Int(count)) ~= i) ? raw[i]: nil }
        set(e) {
            apply([ArrayDiff(UInt(i), 1, [e!])], nil)
        }
    }

    public func bimap<F>(f: E -> F, _ g: F -> E) -> ArrayCollection<F> {
        let peer = ArrayCollection<F>(raw.map(f))
        setMappingBetween(self, peer, f)
        setMappingBetween(peer, self, g)
        return peer
    }
    
    public override func map<F>(f: E -> F) -> ArrayView<F> {
        return bimap(f, { _ in undefined() })
    }

    // TODO less costly implementation
    public func filter(f: E -> Bool) -> ArrayView<E> {
        let a = ArrayCollection<E>()
        subscribe {
            if let o = $0.value { a.assign(self.raw.filter(f)) }
        }
        return a
    }

    public func apply(update: UpdateType) { apply(update.detail, update.sender) }
    
    public func apply(diff: ArrayDiff<E>, _ sender: AnyObject?) { apply([diff], sender) }
    
    public func apply(a: [ArrayDiff<E>], _ sender: AnyObject?) {
        for diff in a {
            assert(diff.offset + diff.delete <= count)
            raw.replaceRange(
                Int (diff.offset) ..<
                    Int (diff.offset + diff.delete), with: diff.insert)
        }
        super.emitValue(Update(sender, a))
    }
    
    public func addHead(e: E, sender: AnyObject?=nil) {
        apply(ArrayDiff(0, 0, [e]), sender)
    }
    
    public func addLast(e: E, sender: AnyObject?=nil) {
        apply(ArrayDiff(count, 0, [e]), sender)
    }
    
    public func removeAt(i: Int, sender: AnyObject?=nil) {
        apply(ArrayDiff(UInt(i), 1), sender)
    }
    
    public func insertAt(i: Int, _ e: E, sender: AnyObject?=nil) {
        apply(ArrayDiff(UInt(i), 0, [e]), sender)
    }
    
    public func assign(a: [E], sender: AnyObject?=nil) {
        apply(ArrayDiff(0, count, a), sender)
    }
    
    public func assign(f: [E] -> [E], sender: AnyObject?=nil) {
        apply(ArrayDiff(0, count, f(raw)), sender)
    }
    
    public func move(i: Int, to j: Int, sender: AnyObject?=nil) {
        if let a = self[i] {
            apply([
                ArrayDiff(UInt(i), 1),
                ArrayDiff(UInt(j), 0, [a]),
            ], sender)
        }
    }
    
    public var count: UInt { return UInt(raw.count) }
    
    public var array: [E]  { return raw }
    
    public override func size() -> UInt { return count }

}

public class ArrayDiff<E> {
    
    public let offset: UInt
    public let delete: UInt
    public let insert: [E]
    
    public init(_ offset: UInt = 0, _ delete: UInt = 0, _ insert: [E] = []) {
        self.offset = offset
        self.delete = delete
        self.insert = insert
    }
    
    public func map<B>(f: E -> B) -> ArrayDiff<B> {
        return ArrayDiff<B>(offset, delete, insert.map(f))
    }
    
}

public class Update<Sender, Detail> {
    
    public let sender: Sender
    public let detail: Detail
    
    public init(_ sender: Sender, _ detail: Detail) {
        self.sender = sender
        self.detail = detail
    }
    
    public func map<B>(f: Detail -> B) -> Update<Sender, B> {
        return Update<Sender, B>(sender, f(detail))
    }
}

// TODO fixes memory leak
private func setMappingBetween<A, B>(a: ArrayCollection<A>, b: ArrayCollection<B>, f: A -> B) {
    a.skip(1).subscribe { e in
        if let o = e.value {
            if o.sender !== b { b.apply(o.detail.map { $0.map(f) }, a) }
        }
    }
}

