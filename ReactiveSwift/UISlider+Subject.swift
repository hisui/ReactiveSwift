// Copyright (c) 2014 segfault.jp. All rights reserved.

import UIKit

public extension UISlider {
    
    public var valueSubject: Subject<Float> {
        return subjectForEvent(.ValueChanged, from: self
            , &valueSubjectKey
            , getter: { $0.value }
            , setter: { $0.value = $1 }
        )
    }
    
}

private var valueSubjectKey = "valueSubjectKey"
