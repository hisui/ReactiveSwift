// Copyright (c) 2014 segfault.jp. All rights reserved.

import XCTest
import ReactiveSwift

class SeqViewTests: XCTestCase {
    
    func testGenralUse() {
        
        let exec = FakeExecutor()
        let subj = SeqCollection([1, 2, 3])
        
        var received: Packet<[SeqDiff<Int>]> = .Done()
        let chan = subj.unwrap.open(exec.newContext()) { $0.subscribe { received = $0 }}
        
        // TODO It should be 0..
        XCTAssertEqual(1, subj.subscribers)
        XCTAssertEqual([1, 2, 3], subj.array)

        exec.consumeAll()
        
        XCTAssertEqual(1, subj.subscribers)
        XCTAssertEqual([1, 2, 3], subj.array)
        
        XCTAssertTrue(received.value![0].insert == [1, 2, 3])
        
        subj.addLast(4)
        
        XCTAssertEqual([1, 2, 3, 4], subj.array)
        XCTAssertTrue(received.value![0].insert == [1, 2, 3])
        
        exec.consumeAll()
        
        XCTAssertEqual([1, 2, 3, 4], subj.array)
        XCTAssertTrue(received.value![0].insert == [4])
        
    }
    
    func testBiMap() {
        
        let exec = FakeExecutor()
        let a = SeqCollection([1, 2, 3])
        let b = a.bimap({ $0 * 2 }, { $0 / 2 }, exec.newContext())
        
        XCTAssertEqual([1, 2, 3], a.array)
        XCTAssertEqual([2, 4, 6], b.array)
        
        a.addHead(0)
        
        XCTAssertEqual([0, 1, 2, 3], a.array)
        XCTAssertEqual([   2, 4, 6], b.array)
        
        exec.consumeAll()
        
        XCTAssertEqual(1, a.subscribers)
        XCTAssertEqual(1, b.subscribers)
        XCTAssertEqual([0, 1, 2, 3], a.array)
        XCTAssertEqual([0, 2, 4, 6], b.array)
        
        b.addLast(8)
        
        XCTAssertEqual([0, 1, 2, 3   ], a.array)
        XCTAssertEqual([0, 2, 4, 6, 8], b.array)
        
        exec.consumeAll()
        
        XCTAssertEqual(1, a.subscribers)
        XCTAssertEqual(1, b.subscribers)
        XCTAssertEqual([0, 1, 2, 3, 4], a.array)
        XCTAssertEqual([0, 2, 4, 6, 8], b.array)

    }
    
}
