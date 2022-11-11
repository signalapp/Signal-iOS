//
// Copyright 2017 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

public class SwiftSingletons: NSObject {
    private static let shared = SwiftSingletons()

    private var registeredTypes = Set<ObjectIdentifier>()

    private override init() {
        super.init()
    }

    public func register(_ singleton: AnyObject) {
        assert({
            guard !CurrentAppContext().isRunningTests else {
                // Allow multiple registrations while tests are running.
                return true
            }
            let singletonTypeIdentifier = ObjectIdentifier(type(of: singleton))
            let (justAdded, _) = registeredTypes.insert(singletonTypeIdentifier)
            return justAdded
        }(), "Duplicate singleton.")
    }

    public static func register(_ singleton: AnyObject) {
        shared.register(singleton)
    }
}
