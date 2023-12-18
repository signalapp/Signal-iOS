//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import SignalServiceKit

#if TESTABLE_BUILD

public class MockSMEnvironment: SMEnvironment {

    public static func activate() {
        setShared(MockSMEnvironment())
    }

    private init() {
        let preferences = Preferences()
        let proximityMonitoringManager = OWSProximityMonitoringManagerImpl()
        let avatarBuilder = AvatarBuilder()
        let smJobQueues = SignalMessagingJobQueues(
            db: DependenciesBridge.shared.db,
            reachabilityManager: SSKEnvironment.shared.reachabilityManagerRef
        )

        super.init(
            preferences: preferences,
            proximityMonitoringManager: proximityMonitoringManager,
            avatarBuilder: avatarBuilder,
            smJobQueues: smJobQueues
        )
    }
}

#endif
