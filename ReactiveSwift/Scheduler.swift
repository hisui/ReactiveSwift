// Copyright (c) 2014 segfault.jp. All rights reserved.

import Foundation

/// An abstract representation of an isolated process like the "actor".
public class PID: Hashable {
    
    public var hashValue: Int { return 0 }
    
    public func equals(o: PID) -> Bool { return false }
}

/// The properties which are  used when `ExecutionContext#spawn` create a new one.
public enum ExecutionProperty: Equatable {
    case Isolated, Actor(PID), AllowSync //, ForceSync
}

/// This class serves the interfaces for which the client programs have tasks executed,
/// and is responsible for determination of where and how is the tasks to be invoked.
public protocol ExecutionContext {
    
    /// Returns a current time whose timeline is specific to an actual implementation.
    var currentTime: NSDate { get }

    /// Schedules the given task to be invoked on this context.
    func schedule(callerContext: ExecutionContext?, _ delay: Double, _ task: () -> ())
    
    /// Spawns another new context derived to this, whose behavior will be guided by the given properties.
    func requires(properties: [ExecutionProperty]) -> ExecutionContext

    /// Closes this context and if possible releases the resources in this context.
    func close()
    
    /// Ensures that the caller of this method is really running in this context. And if not the application would abort.
    func ensureCurrentlyInCompatibleContext()

}

public func ==(lhs: PID, rhs: PID) -> Bool { return lhs.equals(rhs) }

// TODO w/a The Swift compiler in future may be capable of automatically generating the codes like the following..
public func ==(lhs: ExecutionProperty, rhs: ExecutionProperty) -> Bool {
    switch lhs {
    case .Isolated:
        switch rhs {
        case .Isolated: return true
        default: ()
        }
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
    }
    return false
}
