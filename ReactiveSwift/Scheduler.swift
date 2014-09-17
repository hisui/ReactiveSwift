// Copyright (c) 2014 segfault.jp. All rights reserved.

import Foundation

/// An abstract representation of an isolated process like the "actor".
public class PID: Hashable {
    
    public var hashValue: Int { get { return 0 } }
    
    public func equals(o: PID) -> Bool { return false }
}

/// The properties which are  used when `ExecutionContext#spawn` create a new one.
public enum ExecutionProperty: Equatable {
    case Actor(PID), AllowSync, Priority(UInt16)
}

/// This class serves the interfaces for which the client programs have tasks executed,
/// and is responsible for determination of where and how is the tasks to be invoked.
public protocol ExecutionContext {
    
    /// Returns a current time whose timeline is specific to an actual implementation.
    var currentTime: NSDate { get }

    // TODO deadline, priority, naming and so on
    /// Schedules the given task to be invoked on this context.
    func schedule(callerContext: ExecutionContext?, _ delay: Double, _ task: () -> ())
    
    /// Spawns another new context derived to this, whose behavior will be guided by the given properties.
    func requires(properties: [ExecutionProperty]) -> ExecutionContext

}

public func ==(lhs: PID, rhs: PID) -> Bool { return lhs.equals(rhs) }

// TODO w/a The Swift compiler in future may be capable of automatically generating the codes like the following..
public func ==(lhs: ExecutionProperty, rhs: ExecutionProperty) -> Bool {
    switch lhs {
    case .Actor(let e):
        switch rhs {
        case .Actor(e): return true
        default: ()
        }
    case .AllowSync:
        switch rhs {
        case .AllowSync: return true
        default: ()
        }
    case .Priority(let e):
        switch rhs {
        case .Priority(e): return true
        default: ()
        }
    }
    return false
}
