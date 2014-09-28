// Copyright (c) 2014 segfault.jp. All rights reserved.

import Foundation

public class Subject<A>: Source<A> {

    private var channels = [Dispatcher<A>] ()
    private var value: A
    
    public init(_ initialValue: A) {
        self.value = initialValue
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
        get { return value }
    }
    
    override func invoke(chan: Dispatcher<A>) {
        chan.emit(.Next(Box(value)))
        chan.setCloseHandler {
            for i in 0 ..< self.channels.count { // TODO thread safe
                if (self.channels[i] === chan) {
                    self.channels.removeAtIndex(i)
                    break
                }
            }
        }
        channels.append(chan)
    }
    
    public var subscribers: Int { return channels.count }

}
