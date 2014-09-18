// Copyright (c) 2014 segfault.jp. All rights reserved.

import Foundation

public class FakePID: PID {
    
    public let name: String
    
    public init(_ name: String) { self.name = name }
    
    public override func equals(o: PID) -> Bool {
        return (o as? FakePID)?.name == name
    }
}

public class FakeExecutionContext: ExecutionContext {

    private let executor: FakeExecutor
    private let synch: Bool
    private let actor: String
    
    private init(_ executor: FakeExecutor, _ synch: Bool, _ actor: String) {
        self.executor = executor
        self.synch = synch
        self.actor = actor
        executor.count++
    }
    
    public var pid: String { get { return actor } }

    public var currentTime: NSDate {
        get {
            return NSDate(timeIntervalSince1970: executor.currentTime)
        }
    }
    
    public func schedule(callerContext: ExecutionContext?, _ delay: Double, _ task: () -> ()) {
        if synch && delay == 0 {
            task()
        }
        else {
            executor.schedule(delay, task)
        }
    }

    public func requires(property: [ExecutionProperty]) -> ExecutionContext {
        var actor: String = self.actor
        for e in property {
            switch e {
            case .Actor(let pid as FakePID): actor = pid.name
            default: ()
            }
        }
        return FakeExecutionContext(executor, find(property, .AllowSync) != nil, actor)
    }
    
    public func close() { executor.count-- }

}

public class FakeExecutor {
    
    private var currentTime: Double = 0
    private var tasks = [Task]()
    private var count = 0
    
    public init() {}
    
    public var numberOfRunningContexts: Int { get { return count } }

    public func newContext() -> ExecutionContext { return FakeExecutionContext(self, false, "main") }
    
    public func consumeAll() -> Bool {
        return consumeUntil(currentTime)
    }

    public func consumeUntil (time: Double, _ cond: () -> Bool = { true }) -> Bool {
        assert(currentTime <= time)
        var n = 0
        while cond() {
            var a = Array<Int>()
            var t = Double.infinity
            for var i = 0; i < tasks.count; ++i {
                let e = tasks[i]
                if (e.t <= min(time, t)) {
                    if (e.t < t) {
                        t = e.t
                        a.removeAll(keepCapacity: true)
                    }
                    a.append(i)
                }
            }
            if a.isEmpty {
                break
            }
            currentTime = t
            for i in a {
                n++
                tasks[i].f()
            }
            for i in reverse(a) { tasks.removeAtIndex(i) }
        }
        currentTime = time
        return n > 0
    }
    
    public func accumulateElementsWhile<A>(s: Stream<A>, _ cond: () -> Bool) -> [A] {
        var a = Array<A>()
        s.open(newContext()).subscribe {
            if let o = $0.value { a.append(o) }
        }
        consumeUntil(currentTime, cond)
        return a
    }
    
    public class func accumulateElementsWhile<A>(s: Stream<A>, _ cond: () -> Bool) -> [A] {
        return FakeExecutor().accumulateElementsWhile(s, cond)
    }
    
    func schedule(delay: Double, _ f: () -> ()) {
        tasks.append(Task(currentTime + delay, f))
    }

}

private class Task {
    
    let t: Double
    let f: () -> ()
    
    init(_ t: Double, _ f: () -> ()) {
        self.t = t
        self.f = f
    }
}
