// Copyright (c) 2014 segfault.jp. All rights reserved.

import Foundation

// TODO
public class Subject<A> {

    // TODO
    private let writerContext: ExecutionContext
    private var channels = Array<Dispatcher<A>> ()
    private var value: A
    
    init(_ initialValue: A, _ context: ExecutionContext) {
        self.value = initialValue
        self.writerContext = context
    }
    
    public var currentValue: A {
        set(a) {
            value = a
            for chan in channels {
                chan.emitIfOpen(.Next(Box(a)))
            }
        }
        get { return self.value }
    }

    public func split() -> Stream<A> {
        // TODO notify packets are from "hot" channel
        return Streams.source { chan in
            self.channels.append(chan)
            chan.setCloseHandler {
                // remove chan from self.channels
            }
            chan.emit(.Next(Box(self.value)))
        }
    }

}
