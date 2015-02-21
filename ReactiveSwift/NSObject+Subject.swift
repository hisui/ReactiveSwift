// Copyright (c) 2014 segfault.jp. All rights reserved.

import Foundation

public extension NSObject {
    
    public func setAdditionalField(key: UnsafePointer<Void>, _ o: AnyObject?) {
        objc_setAssociatedObject(self, key, o, objc_AssociationPolicy(OBJC_ASSOCIATION_RETAIN_NONATOMIC))
    }
    
    public func getAdditionalField(key: UnsafePointer<Void>) -> AnyObject? {
        return objc_getAssociatedObject(self, key)
    }
    
    func getAdditionalFieldOrUpdate<T: AnyObject>(key: UnsafePointer<Void>, f: () -> T) -> T {
        if let o = getAdditionalField(key) as? T {
            return o
        }
        let o = f()
        setAdditionalField(key, o)
        return o
    }
    
    var opaquePointer: COpaquePointer {
        return Unmanaged<NSObject>.passUnretained(self).toOpaque()
    }
    
    public var deinitSubject: Stream<COpaquePointer> {
        return getAdditionalFieldOrUpdate(&deinitSubjectKey) { DeinitNotifier(self.opaquePointer) }.subject.unwrap.skip(1)
    }

    public func kvoSubject<A: AnyObject>(keyPath: String) -> Subject<A> {
        return getAdditionalFieldOrUpdate(&kvoSubjectKey) { KVOSubject(self, keyPath) }.subject
    }

}

private var deinitSubjectKey = "deinitSubjectKey"

private class DeinitNotifier {

    let subject = Subject<COpaquePointer>(COpaquePointer())
    let pointer: COpaquePointer
    
    init(_ pointer: COpaquePointer) { self.pointer = pointer }
    
    deinit { subject.value = pointer }

}

private var kvoSubjectKey = "kvoSubjectKey"

private class KVOSubject<T: AnyObject>: NSObject {

    let subject: Subject<T>
    let pointer: COpaquePointer
    let keyPath: String
    
    init(_ o: NSObject, _ keyPath: String) {
        self.subject = Subject(o.valueForKey(keyPath) as! T)
        self.pointer = o.opaquePointer
        self.keyPath = keyPath
        super.init()

        subject.open(GCDExecutionContext().requires([.AllowSync])).subscribe { [unowned self] e in
            if let o = e.value {
                if o.sender !== self {
                    Unmanaged<NSObject>.fromOpaque(self.pointer)
                        .takeUnretainedValue().setValue(o.detail, forKey: keyPath)
                }
            }
        }
        o.addObserver(self, forKeyPath: keyPath, options: NSKeyValueObservingOptions.New, context: nil)
    }

    deinit {
        Unmanaged<NSObject>.fromOpaque(pointer)
            .takeUnretainedValue().removeObserver(self, forKeyPath: keyPath)
    }
    
    override func observeValueForKeyPath(keyPath: String, ofObject o: AnyObject, change: [NSObject:AnyObject], context: UnsafeMutablePointer<()>) {
        subject.update(change[NSKeyValueChangeNewKey] as! T, by: self)
    }

}

