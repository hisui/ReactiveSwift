// Copyright (c) 2014 segfault.jp. All rights reserved.

import UIKit

private var swipeEventSubjectKey = "swipeEventSubjectKey"
private var tapEventSubjectKey = "tapEventSubjectKey"
private var panEventSubjectKey = "panEventSubjectKey"

public extension UIView {

    private func gestureEventSubject<T: UIGestureRecognizer>
        (key: UnsafePointer<()>, f: (AnyObject, Selector) -> T) -> Stream<T>
    {
        let pass: ClosureObserver = getAdditionalFieldOrUpdate(key) {
            let subj = ForeignSource<T>()
            let pass = ClosureObserver { (e: T) in
                subj.emitValue(e)
            }
            pass.userData = subj
            self.addGestureRecognizer(f(pass, pass.selector))
            return pass
        }
        return pass.userData as! Stream<T>
    }
    
    public func swipeGestureSubjectOf(direction: UISwipeGestureRecognizerDirection)
        -> Stream<UISwipeGestureRecognizer>
    {
        return gestureEventSubject(&swipeEventSubjectKey) {
            let o = UISwipeGestureRecognizer(target: $0, action: $1)
            o.direction = direction
            return o
        }
    }

    public var tapGestureSubject: Stream<UITapGestureRecognizer> {
        return gestureEventSubject(&tapEventSubjectKey) {
            UITapGestureRecognizer(target: $0, action: $1)
        }
    }
    
    public var panGestureSubject: Stream<UIPanGestureRecognizer> {
        return gestureEventSubject(&panEventSubjectKey) {
            let o = UIPanGestureRecognizer(target: $0, action: $1)
            o.delegate = simulteniousRecognizingEnabler
            return o
        }
    }

    public var dragSubject: Stream<(CGPoint, Stream<CGPoint>)> {
        var last: ForeignSource<CGPoint>?
        return panGestureSubject.flatMap { [weak self] e in
            switch e.state {
            case .Began:
                last?.emit(.Done)
                last = ForeignSource<CGPoint>()
                return Streams.pure((e.locationInView(self!), last! as Stream<CGPoint>))
            case .Ended, .Possible:
                last?.emit(.Done)
                last = nil
            default:
                last?.emitValue(e.locationInView(self!))
            }
            return .done()
        }
    }

}

@objc private class SimulteniousRecognizingEnabler: NSObject, UIGestureRecognizerDelegate {
    @objc func gestureRecognizer(_: UIGestureRecognizer, shouldRecognizeSimultaneouslyWithGestureRecognizer _: UIGestureRecognizer) -> Bool {
        return true
    }
}

private let simulteniousRecognizingEnabler = SimulteniousRecognizingEnabler()
