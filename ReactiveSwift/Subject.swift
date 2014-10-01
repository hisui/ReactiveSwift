// Copyright (c) 2014 segfault.jp. All rights reserved.

import Foundation

public class Subject<A>: SubjectSource<A> {

    private var holder: A
    
    public init(_ initialValue: A) {
        self.holder = initialValue
    }
    
    deinit {
        for chan in channels {
            chan.calleeContext.schedule(nil, 0) {
                chan.emitIfOpen(.Done())
            }
        }
    }

    public var value: A {
        set(a) {
            holder = (a)
            emitValue(a)
        }
        get { return holder }
    }
    
    override func invoke(chan: Dispatcher<A>) {
        super.invoke(chan)
        super.emitValue(value)
    }

}

public class SubjectSource<A>: Source<A> {
    
    private var channels = [Dispatcher<A>] ()
    
    deinit {
        for chan in channels {
            chan.calleeContext.schedule(nil, 0) {
                chan.emitIfOpen(.Done())
            }
        }
    }
    
    func emitValue(a: A) {
        for chan in channels {
            chan.calleeContext.schedule(nil, 0) {
                chan.emitIfOpen(.Next(Box(a)))
            }
        }
    }

    override func invoke(chan: Dispatcher<A>) {
        chan.setCloseHandler { [weak self] in
            for i in 0 ..< (self?.channels.count ?? 0) { // TODO thread safe
                if (self!.channels[i] === chan) {
                    self!.channels.removeAtIndex(i)
                    break
                }
            }
        }
        channels.append(chan)
    }
    
    public var subscribers: Int { return channels.count }
}
