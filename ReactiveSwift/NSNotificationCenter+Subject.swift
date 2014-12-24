// Copyright (c) 2014 segfault.jp. All rights reserved.

import Foundation

public extension NSNotificationCenter {

    public func streamOfEvent(name: String) -> Stream<NSNotification> {
        return Streams.source { chan in
            var observer: NotificationObserver? = NotificationObserver(self, name) {
                chan.emitValue($0)
            }
            chan.setCloseHandler {
                observer = nil
            }
        }
    }
    
}

class NotificationObserver {
    
    private let subject: NSNotificationCenter
    private let handler: NSNotification -> ()
    
    init(_ subject: NSNotificationCenter?, _ name: String, _ handler: NSNotification -> ()) {
        self.handler = handler
        self.subject = subject ?? NSNotificationCenter.defaultCenter()
        self.subject.addObserver(self, selector: "notify:", name: name, object: nil)
    }

    deinit {
        subject.removeObserver(self)
    }
    
    @objc func notify(o: NSNotification) { handler(o) }

}
