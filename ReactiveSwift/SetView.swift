// Copyright (c) 2014 segfault.jp. All rights reserved.

import Foundation

public class SetView<E: Hashable>: SubjectSource<SetDiff<E>> {
    
    public init() {}
    
    override public var firstValue: Box<UpdateDiff> { return Box(SetDiff()) }
    
    public subscript(i: Int) -> E? { return nil }
    
    public func map<F>(f: E -> F) -> Stream<SetView<F>> {
        return Streams.pure(SetView<F>())
    }
    
    public func map<F>(f: E -> F, _ context: ExecutionContext) -> SetView<F> {
        return SetView<F>()
    }

    public var count: UInt { return 0 }
    
    public var array: [E]  { return [] }

    public func compose() -> Stream<[E: ()]> { return unwrap.map { _ in undefined() } }

}

public class SetCollection<E: Hashable>: SetView<E> {
    
    private var raw: [E: ()]
    
    public init(a: [E] = []) { self.raw = newDictionary(a, value: ()) }
    
    override public var firstValue: Box<UpdateDiff> {
        return Box(SetDiff(Array(raw.keys)))
    }
    
    override public func merge(update: UpdateType) {
        for e in update.detail.delete {
            raw.removeValueForKey(e)
        }
        for e in update.detail.insert {
            raw.updateValue((), forKey: e)
        }
        commit(update)
    }
    
    public func update(diff: SetDiff<E>, _ sender: AnyObject? = nil) {
        merge(Update(diff, sender ?? self))
    }

    public func delete(e: E, sender: AnyObject? = nil) { update(SetDiff([], [e]), sender) }
    
    public func insert(e: E, sender: AnyObject? = nil) { update(SetDiff([e], []), sender) }
    
    public func assign(a: [E], sender: AnyObject? = nil) {
        let tmp = newDictionary(a, value: ())
        var delete = [E]()
        var insert = [E]()
        for e in tmp.keys { if !raw.containsKey(e) { insert.append(e) } }
        for e in raw.keys { if !tmp.containsKey(e) { delete.append(e) } }
        update(SetDiff(insert, delete))
    }
    
    override public var count: UInt { return UInt(raw.count) }
    
    override public var array: [E]  { return raw.keys.array }
    
    override public func compose() -> Stream<[E: ()]> {
        return unwrap.map { [unowned self] _ in self.raw }
    }

}

public class SetDiff<E: Hashable> {
    
    public let insert: [E]
    public let delete: [E]
    
    public init(_ insert: [E] = [], _ delete: [E] = []) {
        self.insert = insert
        self.delete = delete
    }

}

extension Dictionary {
    func containsKey(key: Key) -> Bool {
        switch self[key] {
        case .Some(_): return true
        case .None   : return false
        }
    }
}

private func newDictionary<K: Hashable, V>(keys: [K], value: V) -> [K: V] {
    var o = [K: V]()
    for e in keys { o[e] = value }
    return o
}
