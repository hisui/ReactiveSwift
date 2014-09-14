// Copyright (c) 2014 segfault.jp. All rights reserved.

import Foundation

public class GCDQueue: PID {
    
    let raw: dispatch_queue_t
    
    public init(_ raw: dispatch_queue_t) { self.raw = raw }
    
    public override func equals(o: PID) -> Bool {
        return (o as? GCDQueue)?.raw == raw
    }
}

public class GCDExecutionContext: ExecutionContext {

    private let config: GCDExecutionContextConfig

    private init(_ config: GCDExecutionContextConfig) { self.config = config }
    
    public convenience init(_ queue: dispatch_queue_t) {
        self.init(GCDExecutionContextConfig(synch: false, queue: queue))
    }
    
    public convenience init() {
        self.init(dispatch_get_main_queue())
    }
    
    public var currentTime: NSDate { get { return NSDate() } }

    public func schedule(callerContext: ExecutionContext?, _ delay: Double, _ task: () -> ()) {
        let queue = config.queue
        if (delay == 0) {
            if (callerContext as? GCDExecutionContext)?.config.queue == queue {
                task()
                return
            }
            dispatch_async(queue, task)
        }
        else {
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, Int64(delay * Double(NSEC_PER_SEC))), queue, task)
        }
    }
    
    public func requires(property: [ExecutionProperty]) -> ExecutionContext {
        return GCDExecutionContext(GCDExecutionContextConfig.parse(property, config.queue))
    }

}

public extension Stream {
    
    public func open() -> Channel<A> {
        return open(GCDExecutionContext())
    }
    
    public func isolated<B>(queue: dispatch_queue_t, f: Stream<A> -> Stream<B>) -> Stream<B> {
        return isolated([.Actor(GCDQueue(queue))], f: f)
    }
}

private struct GCDExecutionContextConfig {
    
    var synch: Bool
    var queue: dispatch_queue_t
    
    static func parse(property: [ExecutionProperty], _ defaultQueue: dispatch_queue_t) -> GCDExecutionContextConfig {
        var o = GCDExecutionContextConfig(synch: false, queue: defaultQueue)
        for e in property {
            switch e {
            case .AllowSync:
                o.synch = true
                
            case .Actor(let queue as GCDQueue):
                o.queue = queue.raw
                
            default:
                ()
            }
        }
        return o
    }
}
