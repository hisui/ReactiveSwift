// Copyright (c) 2014 segfault.jp. All rights reserved.

import Foundation

public class SeqView<E>: SubjectSource<[SeqDiff<E>]>, SequenceType {

    typealias Generator = IndexingGenerator<[E]>
    
    public init() {}
    
    public func generate() -> Generator { return array.generate() }
    
    override public var firstValue: Box<UpdateDiff> { return Box([]) }

    public subscript(i: Int) -> E? { return nil }
    
    public func map<F>(f: E -> F) -> Stream<SeqView<F>> {
        return .pure(SeqView<F>())
    }

    public func map<F>(f: E -> F, _ context: ExecutionContext) -> SeqView<F> {
        return SeqView<F>()
    }
    
    public func sortedBy(lt: (E, E) -> Bool) -> Stream<SeqView<E>> {
        return .pure(SeqView<E>())
    }
    
    public func filterBy(f: E -> Bool) -> Stream<SeqView<E>> {
        return .pure(SeqView<E>())
    }

    public var count: UInt { return 0 }
    
    public var array: [E]  { return [] }
    
    public func compose() -> Stream<[E]> { return map { _ in undefined() } }

}

public class MutableSeqView<E>: SeqView<E> {

    override public subscript(i: Int) -> E? {
        get { return undefined() }
        set(e) {
            apply([SeqDiff(UInt(i), 1, [e!])], nil)
        }
    }

    override public func map<F>(f: E -> F) -> Stream<SeqView<F>> {
        return bimap(f, { _ in undefined() }).map { $0 as SeqView<F> }
    }
    
    // deprecated
    override public func map<F>(f: E -> F,  _ context: ExecutionContext) -> SeqView<F> {
        return bimap(f, { _ in undefined() }, context)
    }

    // deprecated
    public func bimap<F>(f: E -> F, _ g: F -> E, _ context: ExecutionContext) -> SeqCollection<F> {
        return undefined()
    }

    public func bimap<F>(f: E -> F, _ g: F -> E) -> Stream<SeqCollection<F>> {
        return undefined()
    }
    
    override public func sortedBy(lt: (E, E) -> Bool) -> Stream<SeqView<E>> {
        return undefined()
    }

    override public func filterBy(f: E -> Bool) -> Stream<SeqView<E>> {
        return undefined()
    }

    public func biFilter(f: E -> Bool) -> SeqCollection<E> {
        return undefined()
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
        apply(SeqDiff(0, count, f(array)), sender)
    }
    
    public func move(i: Int, to j: Int, sender: AnyObject? = nil) {
        if let a = self[i] {
            apply([
                SeqDiff(UInt(i), 1),
                SeqDiff(UInt(j), 0, [a]),
            ], sender)
        }
    }

    public func removeFirst(sender: AnyObject? = nil, f: E -> Bool) {
        for (i, e) in self.enumerate() { if f(e) {
            removeAt(i, sender: sender)
            break
        }}
    }
    
    public func updateFirst(o: E, sender: AnyObject? = nil, f: E -> Bool) -> Bool {
        for (i, e) in self.enumerate() { if f(e) {
            self[i] = o
            return true
        }}
        return false
    }

}

public class SeqCollection<E>: MutableSeqView<E> {
    
    private var raw: [E]
    
    public init(_ a: [E] = []) { raw = a }

    override public subscript(i: Int) -> E? {
        get { return ((0 ..< Int(count)) ~= i) ? raw[i]: nil }
        set(e) {
            super[i] = e
        }
    }
    
    override public var firstValue: Box<UpdateDiff> {
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

    override public var count: UInt { return UInt(raw.count) }
    
    override public var array: [E]  { return raw }
    
    // deprecated
    override public func bimap<F>(f: E -> F, _ g: F -> E, _ context: ExecutionContext) -> SeqCollection<F> {
        let peer = SeqCollection<F>(raw.map(f))
        setMappingBetween2(self, b: peer, f: { $0.map { $0.map(f) } }, context: context)
        setMappingBetween2(peer, b: self, f: { $0.map { $0.map(g) } }, context: context)
        return peer
    }
    
    override public func bimap<F>(f: E -> F, _ g: F -> E) -> Stream<SeqCollection<F>> {
        return Streams.lazy { SeqCollection<F>(self.raw.map(f)) }.flatMap { (peer: SeqCollection<F>) in
            mix([
                .pure(peer),
                setMappingBetween2(self, b: peer, f: { $0.map { $0.map(f) } }),
                setMappingBetween2(peer, b: self, f: { $0.map { $0.map(g) } }),
            ])
        }
    }
    
    // TODO less costly implementation
    override public func sortedBy(lt: (E, E) -> Bool) -> Stream<SeqView<E>> {
        let a = SeqCollection<E>()
        return concat([
            .pure(a),
            foreach { [weak self] _ in a.assign(self!.raw.sort(lt)) }.nullify()
        ])
    }
    
    // TODO less costly implementation
    override public func filterBy(f: E -> Bool) -> Stream<SeqView<E>> {
        let a = SeqCollection<E>()
        return concat([
            .pure(a),
            foreach { [weak self] _ in a.assign(self!.raw.filter(f)) }.nullify()
        ])
    }
    
    // TODO
    override public func biFilter(f: E -> Bool) -> SeqCollection<E> {
        abort()
    }
    
    override public func compose() -> Stream<[E]> { return map { _ in self.raw } }

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
