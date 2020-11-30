//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

import Foundation

public class SwiftSingletons: NSObject {
    public static let shared = SwiftSingletons()

    private var classSet = Set<String>()

    private override init() {
        super.init()
    }

    public func register(_ singleton: AnyObject) {
        guard !CurrentAppContext().isRunningTests else {
            return
        }
        guard _isDebugAssertConfiguration() else {
            return
        }
        let singletonClassName = String(describing: type(of: singleton))
        guard !classSet.contains(singletonClassName) else {
            owsFailDebug("Duplicate singleton: \(singletonClassName).")
            return
        }
        Logger.verbose("Registering singleton: \(singletonClassName).")
        classSet.insert(singletonClassName)
    }

    public static func register(_ singleton: AnyObject) {
        shared.register(singleton)
    }
}
