// Copyright (c) 2014 segfault.jp. All rights reserved.

public class ArrayDeque<A> {
    
    private var dest: [A?]
    private var base: Int = 0
    private var size: Int = 0
    
    public init(_ capacity: Int=8) {
        var n = 1
        while n < capacity {
            n *= 2
        }
        dest = [A?](count:n, repeatedValue:nil)
    }
    
    public var count: Int { return size }

    public subscript(i: Int) -> A? { return (0 <= i && i < size) ? get(i): nil }
    
    public var head: A? { return self[0] }
    
    public var last: A? { return self[size - 1] }

    public func clear() {
        dest = [A?](count:1, repeatedValue:nil)
        base = 0
        size = 0
    }
    
    public func toArray() -> [A] {
        var a = Array<A?>(count:size, repeatedValue:nil)
        drainTo(&a)
        return a.map { $0! }
    }

    public func unshift(e: A) {
        doubleCapacityIfFull()
        if base == 0 { base = dest.count }
        base--
        size++
        dest[base] = e
    }
    
    public func shift() -> A? {
        if size == 0 { return nil }
        let e = dest[base]
        size--
        base++
        base &= dest.count - 1
        return e
    }
    
    public func push(e: A) {
        doubleCapacityIfFull()
        dest[(base + size++) & (dest.count - 1)] = e
    }
    
    public func pop() -> A? {
        return size > 0 ? get(--size): nil
    }

    private func get(i: Int) -> A? {
        return dest[ (base + i) & (dest.count - 1) ]
    }

    private func doubleCapacityIfFull() {
        if dest.count == size {
            doubleCapacity()
        }
    }
    
    private func doubleCapacity() {
        var a = [A?](count:dest.count * 2, repeatedValue:nil)
        drainTo(&a)
        dest = a
        base = 0
    }
    
    private func drainTo(inout o: [A?]) {
        var i = 0
        var j = base
        var n = size
        while i < n {
            o[i++] = dest[j]
            j += 1
            j &= dest.count - 1
        }
    }
}
