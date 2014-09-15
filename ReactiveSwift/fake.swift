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
    }
    
    public var pid: String { get { return actor } }

    // TODO introduce virtual (manipulatable) timeline mechanism
    public var currentTime: NSDate { get { return NSDate() } }
    
    public func schedule(callerContext: ExecutionContext?, _ delay: Double, _ task: () -> ()) {
        if (synch) {
            task()
            return
        }
        executor.tasks.push(task)
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
}

public class FakeExecutor {
    
    let tasks = ArrayDeque<() -> ()>()
    
    public init() {}

    public func newContext() -> ExecutionContext { return FakeExecutionContext(self, false, "main") }

    public func consumeNext() -> Bool { return tasks.shift()?() != nil }
    
    public func accumulateElementsWhile<A>(s: Stream<A>, _ cond: () -> Bool) -> [A] {
        var a = Array<A>()
        s.open(newContext()).subscribe {
            if let o = $0.value { a.append(o) }
        }
        while cond() && consumeNext() { /* no-op */ }
        return a
    }
    
    public class func accumulateElementsWhile<A>(s: Stream<A>, _ cond: () -> Bool) -> [A] {
        return FakeExecutor().accumulateElementsWhile(s, cond)
    }
}
