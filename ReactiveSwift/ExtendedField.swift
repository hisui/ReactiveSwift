// Copyright (c) 2015 segfault.jp. All rights reserved.

import Foundation

public class ExtendedField<T: AnyObject> {
    
    private let raw: NSString = "extended-field-key"
    
    public init() {
    }
    
    private var key: UnsafeMutablePointer<Void> {
        return UnsafeMutablePointer<Void>(Unmanaged<NSString>.passRetained(raw).toOpaque())
    }
    
    public subscript(o: NSObject) -> T? {
        get {
            return o.getAdditionalField(key) as? T
        }
        set {
            o.setAdditionalField(key, newValue)
        }
    }

}

