// Copyright (c) 2014 segfault.jp. All rights reserved.

import Foundation

public class FakePID: PID {
    
    public let name: String
    
    public init(_ name: String) { self.name = name }
    
    public override func equals(o: PID) -> Bool { return (o as? FakePID)?.name == name }

}

public class FakeExecutionContext: ExecutionContext, CustomStringConvertible {

    private let executor: FakeExecutor
    private let synch: Bool
    private let actor: String

    public let name: String
    
    private init(_ executor: FakeExecutor, _ synch: Bool, _ actor: String, _ name: String) {
        self.executor = executor
        self.synch = synch
        self.actor = actor
        self.name = name
        executor.count++
    }
    
    public var description: String { return "\(name)@\(actor)" }
    
    public var pid: String { return actor }

    public var currentTime: NSDate {
        return NSDate(timeIntervalSince1970: executor.currentTime)
    }
    
    public func schedule(callerContext: ExecutionContext?, _ delay: Double, _ task: () -> ()) {
        if synch
            && delay == 0
            && actor == (callerContext as? FakeExecutionContext)?.actor
        {
            call(task)()
        }
        else {
            executor.schedule(delay, call(task))
        }
    }

    public func requires(property: [ExecutionProperty]) -> ExecutionContext {
        return executor.newContext(property, FakePID(actor), name)
    }
    
    public func close() { executor.count-- }

    public func ensureCurrentlyInCompatibleContext() {
        if let top = executor.stack.last?.actor {
            assert(top == actor, "[error] Out of context violation occured; `\(actor)` != `\(top)`")
        }
    }

    private func call(f: () -> ())() {
        executor.stack.push(self)
        f()
        executor.stack.pop()
    }

}

public class FakeExecutor {
    
    private var currentTime: Double = 0
    private var tasks = [Task]()
    private var count = 0
    private let stack = ArrayDeque<FakeExecutionContext>()

    public init() {}
    
    public var numberOfRunningContexts: Int { get { return count } }

    public func newContext(name: String = __FUNCTION__) -> ExecutionContext {
        return newContext([], nil, name)
    }

    public func newContext(property: [ExecutionProperty], _ pid: FakePID? = nil, _ name: String = __FUNCTION__) -> ExecutionContext {
        var actor = pid?.name
        var synch = false
        for e in property {
            switch e {
            case .Actor(let pid as FakePID): actor = pid.name
            case .AllowSync:
                synch = true
            default:
                ()
            }
        }
        return FakeExecutionContext(self, synch, actor ?? "main", name)
    }

    public func consumeAll() -> Bool {
        return consumeUntil(currentTime)
    }

    public func consumeUntil (time: Double, _ cond: () -> Bool = { true }) -> Bool {
        assert(currentTime <= time)
        var n = 0
        while cond() {
            var a = Array<Int>()
            var t = Double.infinity
            for (i, e) in tasks.enumerate() {
                if (e.time <= min(time, t)) {
                    if (t > e.time) {
                        t = e.time
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
                tasks[i].task()
            }
            for i in Array(a.reverse()) { tasks.removeAtIndex(i) }
        }
        currentTime = time
        return n > 0
    }

    func schedule(delay: Double, _ f: () -> ()) {
        tasks.append(Task(currentTime + delay, f))
    }

}

private class Task {
    
    let time: Double
    let task: () -> ()
    
    init(_ time: Double, _ task: () -> ()) {
        self.time = time
        self.task = task
    }
}
