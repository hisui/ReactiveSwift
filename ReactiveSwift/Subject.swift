// Copyright (c) 2014 segfault.jp. All rights reserved.

import Foundation

public class Subject<A> {

    private let property: [ExecutionProperty]
    private var channels = Array<Dispatcher<A>> ()
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

    public func split() -> Stream<A> {
        // TODO notify packets are from "hot" channel
        return Streams.source(property) { chan in
            self.channels.append(chan)
            chan.setCloseHandler {
                for i in 0 ..< self.channels.count {
                    if (self.channels[i] === chan) {
                        self.channels.removeAtIndex(i)
                        break
                    }
                }
            }
            chan.emit(.Next(Box(self.value)))
        }
    }
    
    public var subscribers: Int { get { return channels.count } }

}
