// Copyright (c) 2014 segfault.jp. All rights reserved.

import UIKit

public extension UIButton {
    
    public var touchUpInsideSubject: Stream<()> {
        return streamOfEvent(.TouchUpInside)
    }

}

private var touchUpInsideSubjectKey = "touchUpInsideSubjectKey"
