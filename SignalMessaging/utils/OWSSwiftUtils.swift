//
//  Copyright (c) 2017 Open Whisper Systems. All rights reserved.
//

import Foundation

/**
 * We synchronize access to state in this class using this queue.
 */
public func assertOnQueue(_ queue: DispatchQueue) {
    if #available(iOS 10.0, *) {
        dispatchPrecondition(condition: .onQueue(queue))
    } else {
        // Skipping check on <iOS10, since syntax is different and it's just a development convenience.
    }
}

public func owsFail(_ message: String) {
    Logger.error(message)
    Logger.flush()
    assertionFailure(message)
}

public class SwiftSingletons: NSObject {
    public static let shared = SwiftSingletons()

    private var classSet = Set<String>()

    private override init() {
        super.init()
    }

    public func register(_ singleton: AnyObject) {
        guard _isDebugAssertConfiguration() else {
            return
        }
        let singletonClassName = String(describing:type(of:singleton))
        guard !classSet.contains(singletonClassName) else {
            owsFail("\(self.logTag()) in \(#function) Duplicate singleton: \(singletonClassName).")
            return
        }
        Logger.verbose("\(self.logTag()) in \(#function) Registering singleton: \(singletonClassName).")
        classSet.insert(singletonClassName)
    }

    public static func register(_ singleton: AnyObject) {
        shared.register(singleton)
    }
}
