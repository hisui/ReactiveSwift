// Copyright (c) 2014 segfault.jp. All rights reserved.

import XCTest
import ReactiveSwift

class ArrayDequeTests: XCTestCase {

    func testPush() {
        
        let a = ArrayDeque<String>(1)
        a.push("a")
        a.push("b")
        a.push("c")
        
        XCTAssertEqual(["a", "b", "c"], a.toArray())
    }
    
    func testUnshift() {
        
        let a = ArrayDeque<String>(1)
        a.unshift("a")
        a.unshift("b")
        a.unshift("c")
        
        XCTAssertEqual(["c", "b", "a"], a.toArray())
    }
    
    func testPop() {
        
        let a = ArrayDeque<String>(1)
        a.push("a")
        a.push("b")
        a.push("c")
        
        XCTAssertEqual("c", a.pop()!)
        XCTAssertEqual(["a", "b"], a.toArray())
        
        XCTAssertEqual("b", a.pop()!)
        XCTAssertEqual("a", a.pop()!)
        XCTAssertEqual([], a.toArray())
        
        XCTAssert(nil == a.pop())
        XCTAssertEqual([], a.toArray())

    }
    
    func testShift() {
        
        let a = ArrayDeque<String>(1)
        a.push("a")
        a.push("b")
        a.push("c")
        
        XCTAssertEqual("a", a.shift()!)
        XCTAssertEqual(["b", "c"], a.toArray())
        
        XCTAssertEqual("b", a.shift()!)
        XCTAssertEqual("c", a.shift()!)
        XCTAssertEqual([], a.toArray())
        
        XCTAssert(nil == a.shift())
        XCTAssertEqual([], a.toArray())
        
    }
    
}
