// Copyright (c) 2014 segfault.jp. All rights reserved.

import XCTest
import ReactiveSwift

// helper extension for easy testing
private extension Stream {
    var array: [A] {
        get { return FakeExecutor.accumulateElementsWhile(self) { true } }
    }
    
    func isolated<B>(name: String, f: Stream<A> -> Stream<B>) -> Stream<B> {
        return isolated([.Actor(FakePID(name))], f: f)
    }
}

class StreamTests: XCTestCase {

    func testCreateStreamFromCertainElements() {
        
        XCTAssertEqual(["foo"], Streams.pure("foo").array
            , "`Streams.pure()` returns a stream just with one element.")
        
        XCTAssertEqual([2, 3, 5], Streams.args(2, 3, 5).array
            , "`Streams.args()` returns a stream whose form is identical to its argument values.")
        
        XCTAssertEqual(Array<Int>(), Streams.done().array
            , "`Streams.done()` returns an empty stream.")
    }
    
    func testCreateNeverEndingStream() {
        
        let executor = FakeExecutor()

        ( Streams.none() as Stream<()> )
            .open(executor.newContext()).subscribe { _ in }
        
        XCTAssertFalse(executor.consumeNext())
    }
    
    func testSubscribeCanBeInvokedMultipleTimes() {
        
        let a = [2, 3, 5]
        let s = Streams.list(a)
        
        XCTAssertEqual(a, s.array)
        XCTAssertEqual(a, s.array)
        XCTAssertEqual(a, s.array)
    }
    
    func testMixTwoStreams() {
    }
    
    func testMap() {
        XCTAssertEqual([4, 9, 25], Streams.args(2, 3, 5).map { $0 * $0 }.array
            , "Stream#map() makes a stream whose elements are the results of the function applications to the original stream's elements.")
    }
    
    func testFlatMap() {
        
        let given = Streams.args("f o o", "b a r", "b a z")
        
        XCTAssertEqual(["f", "o", "o", "b", "a", "r", "b", "a", "z"]
            , given.flatMap { Streams.list($0.componentsSeparatedByString(" ")) }.array
            , "Stream#flatMap()")
    }
    
    func testFilter() {
        
        let given = Streams.args(0, 1, 2, 3, 4, 5, 6, 7, 8, 9)
        
        XCTAssertEqual([1, 3, 5, 7, 9], given.filter({ $0 % 2 == 1 }).array)
        XCTAssertEqual([0, 2, 4, 6, 8], given.filter({ $0 % 2 == 0 }).array)
    }
    
    func testTakeAndSkip() {
        
        XCTAssertEqual([1, 2, 3, 4, 5, 6, 7, 8, 9]
            , Streams.args(1, 2, 3, 4, 5, 6, 7, 8, 9).skip(0).take(9).array)
        
        XCTAssertEqual([]
            , Streams.args(1, 2, 3, 4, 5, 6, 7, 8, 9).take(0).skip(9).array)
        
        XCTAssertEqual([2, 3, 4, 5, 6, 7, 8]
            , Streams.args(1, 2, 3, 4, 5, 6, 7, 8, 9).skip(1).take(7).array)
    }
    
    func testFlatten() {
        
        let given: Stream<Stream<String>> = Streams.args(
            Streams.pure("A"),
            Streams.pure("B"),
            Streams.pure("C"))
        
        let result: Stream<String> = Streams.flatten(given)
        
        XCTAssertEqual(["A", "B", "C"], result.array)
    }
    
    func testConcat() {
        
        XCTAssertEqual(["A", "B", "C"], Streams.concat([
            Streams.pure("A"),
            Streams.pure("B"),
            Streams.pure("C") ]).array)
    }

    func testConj() {
        
        let a = Streams.args("A", "B", "C")
        let b = Streams.args(1, 2, 3)

        let result = Streams.conj(a, b).array
        XCTAssertEqual(["A", "B", "C"], result.map { $0.0 })
        XCTAssertEqual([  1,   2,   3], result.map { $0.1 })
        
        // The swift compiler does'nt accept this code..
        // XCTAssertEqual([("A", 1), ("B", 2), ("C", 3)], Streams.conj(a, b).array)
    }
    
    // TODO
    func testFold() {
        // The linker fails linking a mangled symbol to `fold`
        // XCTAssertEqual([2*3*5], Streams.args(2, 3, 5).fold(1) {{ $0 * $1 }}.array)
    }
    
    func testDistinct() {
        XCTAssertEqual([1, 2, 3, 4, 5], Streams.distinct(Streams.args(1, 2, 3, 3, 4, 4, 4, 5, 5, 5, 5, 5)).array)
    }
    
    // TODO
    func testRace() {
        
        let given: Stream<Either<String, Int>> =
        Streams.race(
            Streams.pure("A"),
            Streams.pure( 1 ))
        
        for i in 1 ... 3 {
            let a = given.array
            XCTAssertEqual(2, a.count)

            switch (a[0], a[1]) {
            case (.Left(let l), .Right(let r)):
                XCTAssertEqual(l.raw, "A")
                XCTAssertEqual(r.raw,  1 )
                
            case (.Right(let r), .Left(let l)):
                XCTAssertEqual(l.raw, "A")
                XCTAssertEqual(r.raw,  1 )
                
            default:
                XCTFail("unreachable")
            }
        }
    }
    
    func testSeq() {
        
        let given: Stream<[String]> = Streams.seq([
            Streams.pure("A"),
            Streams.pure("B"),
            Streams.pure("C")])
        
        for i in 1 ... 3 {
            XCTAssertEqual([["A", "B", "C"]], given.array)
        }
    }
    
    func testOnCloseAndForEach() {
        
        var passed1 = 0
        var passed2 = 0
        
        var closed1 = 0
        var closed2 = 0
        
        let given: Stream<Int> = (Streams.args(0, 1, 2, 3, 4, 5, 6, 7, 8, 9)
            .foreach { _ in passed1++ }
            .onClose {      closed1++ }
            .skip(2)
            .take(3)
            .foreach { _ in passed2++ }
            .onClose {      closed2++ })
        
        for i in 1 ... 3 {
            XCTAssertEqual([2, 3, 4], given.array)
            
            XCTAssertEqual(5*i, passed1)
            XCTAssertEqual(3*i, passed2)
            
            XCTAssertEqual(i, closed2)
            XCTAssertEqual(i, closed2)
        }
    }
    
    func testIsolation() {
        
        let f = { (e: String, ctx: ExecutionContext) in "\(e):\((ctx as FakeExecutionContext).pid)" }
        
        let given = (Streams.args("A", "B", "C")
            .zipWithContext().map(f)
            .isolated("iso1") { $0
                .zipWithContext().map(f)
                .isolated("iso2") { $0.zipWithContext().map(f) }
                .zipWithContext().map(f)
            }
            .isolated("iso3") { $0.zipWithContext().map(f) }
            .zipWithContext().map(f))
        
        for i in 1 ... 3 {
            XCTAssertEqual(["A", "B", "C"].map { "\($0):main:iso1:iso2:iso1:iso3:main" }, given.array)
        }
    }
    
    func testRecover() {
        
        let error = NSError()
        
        XCTAssertEqual([error], Streams.fail(error).recover { Streams.pure($0) }.array)
    }

}
