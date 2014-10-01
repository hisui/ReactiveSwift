// Copyright (c) 2014 segfault.jp. All rights reserved.

import XCTest
import ReactiveSwift

class SubjectTests: XCTestCase {

    func testGenralUse() {
        
        let exec = FakeExecutor()
        let subj = Subject(1)
        
        var received1: Packet<Int> = .Done()
        let chan1 = subj.unwrap.open(exec.newContext()) { _ in { received1 = $0 }}
        
        XCTAssertEqual(0, subj.subscribers)
        XCTAssertTrue(received1.value == nil)
        
        exec.consumeAll()
        
        XCTAssertEqual(1, subj.subscribers)
        XCTAssertTrue(received1.value == 1)
        
        var received2: Packet<Int> = .Done()
        let chan2 = subj.unwrap.open(exec.newContext()) { _ in { received2 = $0 }}
        
        XCTAssertEqual(1, subj.subscribers)
        XCTAssertTrue(received2.value == nil)
        
        exec.consumeAll()
        
        XCTAssertEqual(2, subj.subscribers)
        XCTAssertTrue(received2.value == 1)
        
        subj.value = 2
        XCTAssertTrue(received1.value == 1)
        XCTAssertTrue(received2.value == 1)
        
        exec.consumeAll()
        
        XCTAssertTrue(received1.value == 2)
        XCTAssertTrue(received2.value == 2)

        chan1.close()
        chan2.close()
        XCTAssertEqual(2, subj.subscribers)
        
        exec.consumeAll()
        
        XCTAssertEqual(0, subj.subscribers)
    }
    
    func testDisposingSubjectCausesCloseAllSubscriptions() {
        
        let exec = FakeExecutor()
        var subj = Subject(1)
        
        var received1: Packet<Int>? = nil
        var received2: Packet<Int>? = nil
        
        let chan1 = subj.unwrap.open(exec.newContext()) { _ in { received1 = $0 }}
        let chan2 = subj.unwrap.open(exec.newContext()) { _ in { received2 = $0 }}
        
        exec.consumeAll()
        
        XCTAssertEqual(2, subj.subscribers)
        XCTAssertTrue(received1!.value == 1)
        XCTAssertTrue(received2!.value == 1)
        
        // overwrite the old `Subject`
        subj = Subject(2)
        
        exec.consumeAll()
        
        XCTAssertTrue(received1!.value == nil)
        XCTAssertTrue(received2!.value == nil)
    }
    
    func testBiMap() {
        
        let exec = FakeExecutor()
        let a = Subject(1)
        let b = a.bimap({ $0 * 2 }, { $0 / 2 }, exec.newContext())
        
        XCTAssertEqual(1, a.value)
        XCTAssertEqual(2, b.value)
        
        a.value = 2
        
        XCTAssertEqual(2, a.value)
        XCTAssertEqual(2, b.value)
        
        exec.consumeAll()
        
        XCTAssertEqual(1, a.subscribers)
        XCTAssertEqual(1, b.subscribers)
        XCTAssertEqual(2, a.value)
        XCTAssertEqual(4, b.value)
        
        b.value = 6
        
        XCTAssertEqual(2, a.value)
        XCTAssertEqual(6, b.value)
        
        exec.consumeAll()
        
        XCTAssertEqual(3, a.value)
        XCTAssertEqual(6, b.value)

    }
    
}
