//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import SignalServiceKit

/**
 *
 * SMEnvironment is a data and data accessor class.
 * It handles application-level component wiring in order to support mocks for testing.
 * It also handles network configuration for testing/deployment server configurations.
 *
 **/

public class SMEnvironment: NSObject {

    private static var _shared: SMEnvironment?

    public static var shared: SMEnvironment { _shared! }

    public static func setShared(_ environment: SMEnvironment) {
        // The main app environment should only be set once.
        //
        // App extensions may be opened multiple times in the same process,
        // so statics will persist.
        owsAssert(_shared == nil || !CurrentAppContext().isMainApp || CurrentAppContext().isRunningTests)
        _shared = environment
    }

    public let preferencesRef: Preferences
    public let proximityMonitoringManagerRef: OWSProximityMonitoringManager
    public let avatarBuilderRef: AvatarBuilder
    public let smJobQueuesRef: SignalMessagingJobQueues

    // This property is configured after SMEnvironment is created.
    public var lightweightCallManagerRef: LightweightCallManager?

    public init(
        preferences: Preferences,
        proximityMonitoringManager: OWSProximityMonitoringManager,
        avatarBuilder: AvatarBuilder,
        smJobQueues: SignalMessagingJobQueues
    ) {
        preferencesRef = preferences
        proximityMonitoringManagerRef = proximityMonitoringManager
        avatarBuilderRef = avatarBuilder
        smJobQueuesRef = smJobQueues

        super.init()

        SwiftSingletons.register(self)
    }
}
