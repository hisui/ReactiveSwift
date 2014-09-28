// Copyright (c) 2014 segfault.jp. All rights reserved.

import XCTest
import ReactiveSwift

private extension Stream {
    func isolated<B>(name: String, f: Stream<A> -> Stream<B>) -> Stream<B> {
        return isolated([.Actor(FakePID(name))], f: f)
    }
}

class StreamTests: XCTestCase {
    
    var executor: FakeExecutor? = nil
    var contexts = [ExecutionContext]()
    
    func consumeUntil(time: Double) {
        executor!.consumeUntil(time)
    }
    
    func consumeAll() {
        executor!.consumeAll()
    }

    func newContext(_ name: String = __FUNCTION__) -> ExecutionContext {
        let context = executor!.newContext(name)
        contexts.append(context)
        return context
    }
    
    func toArray<A>(s: Stream<A>, _ name: String = __FUNCTION__) -> [A] {
        var a = [A]()
        s.open(newContext(name)).subscribe {
            if let o = $0.value { a.append(o) }
        }
        consumeAll()
        return a
    }

    override func setUp() {
        executor = FakeExecutor()
        contexts = []
    }
    
    override func tearDown() {
        consumeUntil(Double.infinity)
        for e in contexts {
            e.close()
        }
        XCTAssertEqual(0, executor!.numberOfRunningContexts)
        executor = nil
        contexts.removeAll(keepCapacity: true)
    }
    
    func testSimple() {
        XCTAssertEqual(["foo"], toArray(Streams.pure("foo")))
    }
    
    func testCreateStreamFromCertainElements() {
        
        XCTAssertEqual(["foo"], toArray(Streams.pure("foo"))
            , "`Streams.pure()` returns a stream just with one element.")
        
        XCTAssertEqual([2, 3, 5], toArray(Streams.args(2, 3, 5))
            , "`Streams.args()` returns a stream whose form is identical to its argument values.")
        
        XCTAssertEqual(Array<Int>(), toArray(Streams.done())
            , "`Streams.done()` returns an empty stream.")
        
        XCTAssertEqual([1, 2, 3], toArray(Streams.range(1 ... 3)))
    }

    func testSubscribeCanBeInvokedMultipleTimes() {
        
        let a = [2, 3, 5]
        let s = Streams.list(a)
        
        XCTAssertEqual(a, toArray(s))
        XCTAssertEqual(a, toArray(s))
        XCTAssertEqual(a, toArray(s))
    }
    
    func testMap() {
        XCTAssertEqual([4, 9, 25], toArray(Streams.args(2, 3, 5).map { $0 * $0 })
            , "Stream#map() makes a stream whose elements are the results of the function applications to the original stream's elements.")
    }
    
    func testFlatMap() {
        
        let given = Streams.args("f o o", "b a r", "b a z")
        
        XCTAssertEqual(["f", "o", "o", "b", "a", "r", "b", "a", "z"]
            , toArray(given.flatMap { Streams.list($0.componentsSeparatedByString(" ")) })
            , "Stream#flatMap()")
    }
    
    func testFilter() {
        
        let given = Streams.range(0 ... 9)
        
        XCTAssertEqual([1, 3, 5, 7, 9], toArray(given.filter({ $0 % 2 == 1 })))
        XCTAssertEqual([0, 2, 4, 6, 8], toArray(given.filter({ $0 % 2 == 0 })))
    }
    
    func testTakeAndSkip() {
        
        XCTAssertEqual([1, 2, 3, 4, 5, 6, 7, 8, 9]
            , toArray(Streams.range(1 ... 9).skip(0).take(9)))
        
        XCTAssertEqual([]
            , toArray(Streams.range(1 ... 9).take(0).skip(9)))
        
        XCTAssertEqual([2, 3, 4, 5, 6, 7, 8]
            , toArray(Streams.range(1 ... 9).skip(1).take(7)))
    }
    
    func testFlatten() {
        
        let given: Stream<Stream<String>> = Streams.args(
            Streams.pure("A"),
            Streams.pure("B"),
            Streams.pure("C"))
        
        let result: Stream<String> = Streams.flatten(given)
        
        XCTAssertEqual(["A", "B", "C"], toArray(result))
    }
    
    func testConcat() {
        
        XCTAssertEqual(["A", "B", "C"], toArray(
            Streams.concat([
                Streams.pure("A"),
                Streams.pure("B"),
                Streams.pure("C") ])))
    }

    func testZip() {
        
        let a = Streams.args("A", "B", "C")
        let b = Streams.args(1, 2, 3)

        let result = toArray(Streams.zip(a, b))
        XCTAssertEqual(["A", "B", "C"], result.map { $0.0 })
        XCTAssertEqual([  1,   2,   3], result.map { $0.1 })

    }
    
    // TODO
    func testFold() {
        // The linker fails linking a mangled symbol to `fold`
        // XCTAssertEqual([2*3*5], Streams.args(2, 3, 5).fold(1) {{ $0 * $1 }}.array)
    }
    
    func testDistinct() {
        XCTAssertEqual([1, 2, 3, 4, 5],
            toArray(Streams.distinct(Streams.args(1, 2, 3, 3, 4, 4, 4, 5, 5, 5, 5, 5))))
    }
    
    func testSeq() {
        
        let given: Stream<[String]> = Streams.seq([
            Streams.pure("A"),
            Streams.pure("B"),
            Streams.pure("C")])
        
        for i in 1 ... 3 {
            XCTAssertEqual([["A", "B", "C"]], toArray(given))
        }
    }
    
    func testOnCloseAndForEach() {
        
        var passed1 = 0
        var passed2 = 0
        
        var closed1 = 0
        var closed2 = 0
        
        let given: Stream<Int> = (Streams.range(0 ... 9)
            .foreach { _ in passed1++; () }
            .onClose {      closed1++; () }
            .skip(2)
            .take(3)
            .foreach { _ in passed2++; () }
            .onClose {      closed2++; () }
        )
        
        for i in 1 ... 1 {
            XCTAssertEqual([2, 3, 4], toArray(given))
            
            XCTAssertEqual(5*i, passed1)
            XCTAssertEqual(3*i, passed2)
            
            XCTAssertEqual(i, closed1)
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
            XCTAssertEqual(["A", "B", "C"].map { "\($0):main:iso1:iso2:iso1:iso3:main" }, toArray(given))
        }
    }
    
    func testFailsAndRecover() {
        
        let error = NSError()
        
        XCTAssertEqual([error], toArray(Streams.fail(error).recover { Streams.pure($0) }))
    }
    
    // time-related
    func testOuterBind() {

        var value: String? = nil
        var count: Int     = 0

        var outer: Dispatcher<Stream<String>>? = nil
        let chan = Streams.source { outer = $0 }.outerBind {{ $0 }}.open(newContext())
        chan.subscribe {
            value = $0.value
            count++
        }
        
        consumeAll()
        outer!.emit(.Next(Box(Streams.pure("A"))))
        
        consumeAll()
        XCTAssertEqual("A", value!)
        XCTAssertEqual(1, count)

        var inner1: Dispatcher<String>? = nil
        outer?.emit(.Next(Box(Streams.source {
            inner1 = $0
            inner1?.setCloseHandler { inner1 = nil }
        })))
        
        consumeAll()
        XCTAssertTrue(inner1 != nil)
        XCTAssertEqual("A", value!)
        XCTAssertEqual(1, count)
        
        inner1!.emit(.Next(Box("B")))
        
        consumeAll()
        XCTAssertEqual("B", value!)
        XCTAssertEqual(2, count)
        
        var inner2: Dispatcher<String>? = nil
        outer!.emit(.Next(Box(Streams.source {
            inner2 = $0
            inner2?.setCloseHandler { inner2 = nil }
        })))

        consumeAll()
        XCTAssertEqual("B", value!)
        XCTAssertEqual(2, count)
        XCTAssertTrue(inner1 == nil)
        XCTAssertTrue(inner2 != nil)
        
        inner2!.emit(.Next(Box("C")))
        inner2!.emit(.Done())
        
        consumeAll()
        XCTAssertEqual("C", value!)
        XCTAssertEqual(3, count)
        XCTAssertTrue(inner1 == nil)
        XCTAssertTrue(inner2 == nil)
        
        outer!.emit(.Done())

        consumeAll()
        XCTAssertTrue(value == nil)
        XCTAssertEqual(4, count)

    }
    
    // time-related
    func testRepeatAndDelay() {
        
        var value: String? = nil
        var count: Int     = 0
        
        let chan = Streams.repeat("A", 2).open(newContext())
        chan.subscribe {
            value = $0.value
            count++
        }

        consumeUntil(1)
        XCTAssertTrue(value == nil)
        XCTAssertEqual(0, count)
        
        consumeUntil(3)
        XCTAssertEqual("A", value!)
        XCTAssertEqual(1, count)
        
        consumeUntil(5)
        XCTAssertEqual("A", value!)
        XCTAssertEqual(2, count)
        
        chan.close()
        
        consumeUntil(100)
        XCTAssertEqual("A", value!)
        XCTAssertEqual(2, count)

    }
    
    // time-related
    func testTimeout() {
        
        var store = [String]()
        var count = 0

        let context = newContext()
        Streams.timeout(2, "A")
        .open(context)
        .subscribe {
            if let e = $0.value { store.append(e) }
            count++
        }

        consumeUntil(1)
        XCTAssertEqual([], store)
        XCTAssertEqual(0, count)
        
        consumeUntil(100)
        XCTAssertEqual(["A"], store)
        XCTAssertEqual(2, count) // .Next("A") + .Done()
    }
    
    // time-related
    func testThrottle() {

        var value: String? = nil
        var count: Int     = 0
        
        let chan = Streams.concat([
            Streams.timeout(1, "A"), // 1 (<=)
            Streams.timeout(3, "B"), // 4
            Streams.timeout(1, "C"), // 5
            Streams.timeout(1, "D"), // 6
            Streams.timeout(3, "E"), // 9
            Streams.timeout(3, "F"), // 12
            ])
            .throttle(2).open(newContext())
        
        chan.subscribe {
            value = $0.value
            count++
        }

        consumeUntil(2)
        XCTAssertTrue(value == nil)
        XCTAssertEqual(0, count)
        
        consumeUntil(4)
        XCTAssertEqual("A", value!)
        XCTAssertEqual(1, count)
        
        consumeUntil(7)
        XCTAssertEqual("A", value!)
        XCTAssertEqual(1, count)
        
        consumeUntil(9)
        XCTAssertEqual("D", value!)
        XCTAssertEqual(2, count)
        
        consumeUntil(13)
        XCTAssertEqual("E", value!)
        XCTAssertEqual(3, count)
        
        consumeUntil(15)
        XCTAssertTrue(value == nil)
        XCTAssertEqual(5, count)

    }
    
    // time-related
    func testSample() {
        // TODO
    }
    
    // nondeterministic
    func testMerge() {
        // TODO
    }
    
    //  nondeterministic
    func testMix() {
        
        let given: Stream<String> =
        Streams.mix([
            Streams.pure("A"),
            Streams.pure("B")])
        
        for i in 1 ... 3 {
            let a = toArray(given)
            executor?.consumeAll()
            XCTAssertTrue(a == ["A", "B"] || a == ["B", "A"])
        }
    }
    
    //  nondeterministic
    func testRace() {
        
        let given: Stream<Either<String, Int>> =
        Streams.race(
            Streams.pure("A"),
            Streams.pure( 1 ))
        
        for i in 1 ... 3 {
            let a = toArray(given)
            if (a.count == 2) {
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
            XCTAssertEqual(2, a.count)
        }
    }
    
    func testGroupBy() {
        
        let given = Streams.range(0 ... 9)
        var group = [[Int]]()
        
        given
        .groupBy { $0 % 2 }
        .foreach { chan in
            let i = group.count
            group.append([])
            chan.subscribe {
                if let o = $0.value { group[i].append(o.1) }
            }
        }
        .open(newContext())
        
        consumeAll()
        
        XCTAssertEqual([0, 2, 4, 6, 8], group[0])
        XCTAssertEqual([1, 3, 5, 7, 9], group[1])
    }

}
