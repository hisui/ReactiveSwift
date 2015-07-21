// Copyright (c) 2014 segfault.jp. All rights reserved.

import Foundation

public extension NSNotificationCenter {

    public func streamOfEvent(name: String, _ object: AnyObject? = nil) -> Stream<NSNotification> {
        return Streams.source { chan in
            var observer: NotificationObserver? = NotificationObserver(self, name, object) {
                chan.emitValue($0)
            }
            chan.setCloseHandler {
                if (observer != nil) {
                    observer  = nil
                }
            }
        }
    }
    
}

class NotificationObserver {
    
    private let subject: NSNotificationCenter
    private let handler: NSNotification -> ()
    
    init(_ subject: NSNotificationCenter?, _ name: String, _ object: AnyObject?, _ handler: NSNotification -> ()) {
        self.handler = handler
        self.subject = subject ?? NSNotificationCenter.defaultCenter()
        self.subject.addObserver(self, selector: "notify:", name: name, object: object)
    }

    deinit {
        subject.removeObserver(self)
    }
    
    @objc func notify(o: NSNotification) { handler(o) }

}
