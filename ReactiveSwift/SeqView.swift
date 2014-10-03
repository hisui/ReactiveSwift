// Copyright (c) 2014 segfault.jp. All rights reserved.

import Foundation

public class SeqView<E>: SubjectSource<[SeqDiff<E>]> {

    public init() {}
    
    override public func firstValue() -> Box<UpdateItem> { return Box([]) }

    public subscript(i: Int) -> E? { return nil }
    
    public func map<F>(f: E -> F) -> Stream<SeqView<F>> {
        return Streams.pure(SeqView<F>())
    }

    public func map<F>(f: E -> F, _ context: ExecutionContext) -> SeqView<F> {
        return SeqView<F>()
    }

    // TODO Swift compiler does'nt support overriding getter/setter yet
    // public var count: UInt { return undefined() }
    // public var array: [E]  { return undefined() }
    
    public func size() -> UInt { return 0 }
    
    public func compose() -> Stream<[E]> { return unwrap.map { _ in undefined() } }

}

public class SeqCollection<E>: SeqView<E> {

    private var raw: [E]
    
    public init(_ a: [E] = []) { raw = a }
    
    override public func firstValue() -> Box<UpdateItem> {
        return Box([SeqDiff<E>(0, 0, raw)])
    }
    
    override public func merge(update: UpdateType) {
        for diff in update.detail {
            assert(diff.offset + diff.delete <= count)
            raw.replaceRange(
                Int (diff.offset) ..<
                    Int (diff.offset + diff.delete), with: diff.insert)
        }
        commit(update)
    }

    override public subscript(i: Int) -> E? {
        get { return ((0 ..< Int(count)) ~= i) ? raw[i]: nil }
        set(e) {
            apply([SeqDiff(UInt(i), 1, [e!])], nil)
        }
    }

    override public func map<F>(f: E -> F) -> Stream<SeqView<F>> {
        return bimap(f, { _ in undefined() }).map { $0 as SeqView<F> }
    }
    
    override public func map<F>(f: E -> F,  _ context: ExecutionContext) -> SeqView<F> {
        return bimap(f, { _ in undefined() }, context)
    }

    public func bimap<F>(f: E -> F, _ g: F -> E, _ context: ExecutionContext) -> SeqCollection<F> {
        let peer = SeqCollection<F>(raw.map(f))
        setMappingBetween2(self, peer, { $0.map { $0.map(f) } }, context)
        setMappingBetween2(peer, self, { $0.map { $0.map(g) } }, context)
        return peer
    }

    public func bimap<F>(f: E -> F, _ g: F -> E) -> Stream<SeqCollection<F>> {
        return Streams.lazy(SeqCollection<F>(raw.map(f))).flatMap { (peer: SeqCollection<F>) in
            Streams.mix([
                Streams.pure(peer),
                setMappingBetween2(self, peer, { $0.map { $0.map(f) } }),
                setMappingBetween2(peer, self, { $0.map { $0.map(g) } }),
            ])
        }
    }

    // TODO less costly implementation
    public func filter(f: E -> Bool) -> SeqView<E> {
        let a = SeqCollection<E>()
        subscribe {
            if let o = $0.value { a.assign(self.raw.filter(f)) }
        }
        return a
    }
    
    // TODO
    public func biFilter(f: E -> Bool) -> SeqCollection<E> {
        abort()
    }
    
    // TODO
    public func sortedBy(lt: (E, E) -> Bool) -> SortedSeqView<E> {
        abort()
    }
    
    // TODO
    public func biSortedBy(lt: (E, E) -> Bool) -> SortedSeqCollection<E> {
        abort()
    }

    public func apply(diff: SeqDiff<E>, _ sender: AnyObject?) { apply([diff], sender) }
    
    public func apply(a: [SeqDiff<E>], _ sender: AnyObject?) {
        merge(Update(a, sender ?? self))
    }

    public func addHead(e: E, sender: AnyObject? = nil) {
        apply(SeqDiff(0, 0, [e]), sender)
    }
    
    public func addLast(e: E, sender: AnyObject? = nil) {
        apply(SeqDiff(count, 0, [e]), sender)
    }
    
    public func removeAt(i: Int, sender: AnyObject? = nil) {
        apply(SeqDiff(UInt(i), 1), sender)
    }
    
    public func insertAt(i: Int, _ e: E, sender: AnyObject? = nil) {
        apply(SeqDiff(UInt(i), 0, [e]), sender)
    }
    
    public func assign(a: [E], sender: AnyObject? = nil) {
        apply(SeqDiff(0, count, a), sender)
    }
    
    public func assign(f: [E] -> [E], sender: AnyObject? = nil) {
        apply(SeqDiff(0, count, f(raw)), sender)
    }
    
    public func move(i: Int, to j: Int, sender: AnyObject? = nil) {
        if let a = self[i] {
            apply([
                SeqDiff(UInt(i), 1),
                SeqDiff(UInt(j), 0, [a]),
            ], sender)
        }
    }
    
    public var count: UInt { return UInt(raw.count) }
    
    public var array: [E]  { return raw }
    
    override public func size() -> UInt { return count }
    
    override public func compose() -> Stream<[E]> {
        return unwrap.map { [unowned self] _ in self.raw }
    }

}

public class SeqDiff<E> {
    
    public let offset: UInt
    public let delete: UInt
    public let insert: [E]
    
    public init(_ offset: UInt = 0, _ delete: UInt = 0, _ insert: [E] = []) {
        self.offset = offset
        self.delete = delete
        self.insert = insert
    }
    
    public func map<B>(f: E -> B) -> SeqDiff<B> { return SeqDiff<B>(offset, delete, insert.map(f)) }

}
