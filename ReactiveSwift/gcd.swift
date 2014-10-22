// Copyright (c) 2014 segfault.jp. All rights reserved.

import Foundation

public class GCDQueue: PID {
    
    let raw: dispatch_queue_t
    
    public init(_ raw: dispatch_queue_t) { self.raw = raw }
    
    public override func equals(o: PID) -> Bool { return (o as? GCDQueue)?.raw == raw }
    
}

public class GCDExecutionContext: ExecutionContext {

    private let config: GCDExecutionContextConfig

    private init(_ config: GCDExecutionContextConfig) { self.config = config }
    
    public convenience init(_ queue: GCDQueue) {
        self.init(GCDExecutionContextConfig(synch: false, queue: queue))
    }
    
    public convenience init() {
        self.init(GCDQueue(dispatch_get_main_queue()))
    }
    
    public var currentTime: NSDate { get { return NSDate() } }

    public func schedule(callerContext: ExecutionContext?, _ delay: Double, _ task: () -> ()) {
        let queue = config.queue
        if (delay == 0) {
            if config.synch && (callerContext as? GCDExecutionContext)?.config.queue == queue {
                task()
                return
            }
            dispatch_async(queue.raw, task)
        }
        else {
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, Int64(delay * Double(NSEC_PER_SEC))), queue.raw, task)
        }
    }
    
    public func requires(property: [ExecutionProperty]) -> ExecutionContext {
        return GCDExecutionContext(GCDExecutionContextConfig.parse(property, config.queue))
    }

    public func close() { /* no-op */ }

    public func ensureCurrentlyInCompatibleContext() { /* no-op */ }

}

public extension Stream {

    public func isolated<B>(queue: dispatch_queue_t, _ f: Stream<A> -> Stream<B>) -> Stream<B> {
        return isolated([.Actor(GCDQueue(queue))], f)
    }

}

private struct GCDExecutionContextConfig {
    
    var synch: Bool
    var queue: GCDQueue
    
    static func parse(property: [ExecutionProperty], _ defaultQueue: GCDQueue) -> GCDExecutionContextConfig {
        var o = GCDExecutionContextConfig(synch: false, queue: defaultQueue)
        for e in property {
            switch e {
            case .AllowSync:
                o.synch = true
                
            case .Isolated:
                o.queue = newQueue()
                
            case .Actor(let pid as GCDQueue):
                o.queue = pid
                
            case .Actor(let pid):
                println("Unsupported PID type :: `\(pid)`")
                abort()
            }
        }
        return o
    }
}

private func newQueue() -> GCDQueue {
    return GCDQueue(dispatch_queue_create("jp.segfault.ReactiveSwift", DISPATCH_QUEUE_SERIAL))
}
