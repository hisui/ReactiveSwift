// Copyright (c) 2014 segfault.jp. All rights reserved.

import UIKit

public extension UITextField {
    
    public var textSubject: Subject<String> {
        return subjectForEvent(.EditingChanged, from: self
            , &textSubjectKey
            , getter: { $0.text }
            , setter: { $0.text = $1 }
        )
    }
    
}

private var textSubjectKey = "textSubjectKey"
