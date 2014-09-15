// Copyright (c) 2014 segfault.jp. All rights reserved.

import XCTest
import ReactiveSwift

class SubjectTests: XCTestCase {

    func testSimple() {
        
        let exec = FakeExecutor()
        let subj = Subject(1)
        
        var received1: Packet<Int> = .Done()
        let chan1 = subj.split().open(exec.newContext()) { _ in { received1 = $0 }}
        
        XCTAssertEqual(1, subj.subscribers)
        XCTAssertTrue(received1.value == nil)
        
        var received2: Packet<Int> = .Done()
        let chan2 = subj.split().open(exec.newContext()) { _ in { received2 = $0 }}
        
        XCTAssertEqual(2, subj.subscribers)
        XCTAssertTrue(received2.value == nil)
        
        subj.currentValue = 2
        XCTAssertTrue(received1.value == nil)
        XCTAssertTrue(received2.value == nil)
        
        while exec.consumeNext() {}
        
        XCTAssertTrue(received1.value == 2)
        XCTAssertTrue(received2.value == 2)

        chan1.close()
        chan2.close()
        XCTAssertEqual(2, subj.subscribers)
        
        while exec.consumeNext() {}
        
        XCTAssertEqual(0, subj.subscribers)
        XCTAssertTrue(received1.value == nil)
        XCTAssertTrue(received2.value == nil)

    }
    
}
