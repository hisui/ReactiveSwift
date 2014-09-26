// Copyright (c) 2014 segfault.jp. All rights reserved.

import Foundation

public class Subject<A>: Stream<A> {

    private let property: [ExecutionProperty]
    private var channels = [Dispatcher<A>] ()
    private var value: A
    
    public init(_ initialValue: A, _ property: [ExecutionProperty]=[]) {
        self.value = initialValue
        self.property = property
    }

    public var currentValue: A {
        set(a) {
            value = a
            for chan in channels {
                chan.calleeContext.schedule(nil, 0) {
                    chan.emitIfOpen(.Next(Box(a)))
                }
            }
        }
        get { return self.value }
    }
    
    override public func open(callerContext: ExecutionContext, _ cont: Cont) -> Channel<A> {
        let chan = Dispatcher<A>(callerContext, callerContext.requires(property))
        chan.setCloseHandler {
            for i in 0 ..< self.channels.count {
                if (self.channels[i] === chan) {
                    self.channels.removeAtIndex(i)
                    break
                }
            }
        }
        channels.append(chan)
        if let f = cont(chan) {
            chan.subscribe(f)
        }
        chan.emitIfOpen(.Next(Box(self.value)))
        return chan
    }
    
    public var subscribers: Int { get { return channels.count } }

}
