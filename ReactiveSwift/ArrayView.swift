// Copyright (c) 2014 segfault.jp. All rights reserved.

import Foundation

public class ArrayView<E>: SubjectSource<[ArrayDiff<E>]> {

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
    
    override func initialValue() -> UpdateItem? { return [ArrayDiff<E>(0, 0, raw)] }

    public override subscript(i: Int) -> E? {
        get { return ((0 ..< Int(count)) ~= i) ? raw[i]: nil }
        set(e) {
            apply([ArrayDiff(UInt(i), 1, [e!])], nil)
        }
    }

    public func bimap<F>(f: E -> F, _ g: F -> E) -> ArrayCollection<F> {
        let peer = ArrayCollection<F>(raw.map(f))
        setMappingBetween2(self, peer) { $0.map { $0.map(f) } }
        setMappingBetween2(peer, self) { $0.map { $0.map(g) } }
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

    public override func apply(update: UpdateType) {
        for diff in update.detail {
            assert(diff.offset + diff.delete <= count)
            raw.replaceRange(
                Int (diff.offset) ..<
                Int (diff.offset + diff.delete), with: diff.insert)
        }
        super.commit(update)
    }

    public func apply(diff: ArrayDiff<E>, _ sender: AnyObject?) { apply([diff], sender) }
    
    public func apply(a: [ArrayDiff<E>], _ sender: AnyObject?) {
        apply(Update(a, sender))
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
