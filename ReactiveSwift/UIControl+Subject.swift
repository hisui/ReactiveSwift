// Copyright (c) 2014 segfault.jp. All rights reserved.

import UIKit

public extension UIControl {
    
    private func addTarget(event: UIControlEvents, f: () -> ()) -> ClosureObserver {
        let thunk = ClosureObserver(f)
        addTarget(thunk, action: thunk.selector, forControlEvents: event)
        return thunk
    }
    
    private func removeTarget(event: UIControlEvents, _ thunk: ClosureObserver) {
        removeTarget(thunk, action: thunk.selector, forControlEvents: event)
    }

    public func streamOfEvent(event: UIControlEvents) -> Stream<()> {
        return Streams.source { [weak self] chan in
            if let o = self {
                let memo = o.addTarget(event) {
                    chan.emitValue(())
                }
                chan.setCloseHandler { [weak self] in
                    self?.removeTarget(event, memo)
                    ()
                }
            }
        }.closeBy(deinitSubject)
    }

}

func subjectForEvent<T, S: UIControl>(event: UIControlEvents, from: S
    , key: UnsafePointer<String>
    , getter:  S -> T
    , setter: (S, T) -> ()) -> Subject<T>
{
    return from.getAdditionalFieldOrUpdate(key) {
        let subj = Subject(getter(from))
        let memo = from.addTarget(event) { [weak from, weak subj] in
            if let tmp = from {
                subj?.update(getter(tmp), by: tmp)
            }
        }
        subj.subscribe { [weak from] e in
            if let tmp = from {
                if let o = e.value {
                    if o.sender !== tmp { setter(tmp, o.detail) }
                }
                else {
                    tmp.removeTarget(event, memo)
                }
            }
        }
        return subj
    }
}
