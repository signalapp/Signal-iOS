//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import XCTest
@testable import SignalServiceKit

final class RingrtcFieldTrialsTest: XCTestCase {
    func testNwPathMonitorEnabledWhenUnspecified() {
        let userDefaults = TestUtils.userDefaults()

        let trials = RingrtcFieldTrials.trials(with: userDefaults)

        XCTAssertEqual(trials["WebRTC-Network-UseNWPathMonitor"], "Enabled")
    }

    func testNwPathMonitorExplicitlyEnabled() {
        let userDefaults = TestUtils.userDefaults()
        RingrtcFieldTrials.saveNwPathMonitorTrialState(isEnabled: true, in: userDefaults)

        let trials = RingrtcFieldTrials.trials(with: userDefaults)

        XCTAssertEqual(trials["WebRTC-Network-UseNWPathMonitor"], "Enabled")
    }

    func testNwPathMonitorDisabled() {
        let userDefaults = TestUtils.userDefaults()
        RingrtcFieldTrials.saveNwPathMonitorTrialState(isEnabled: false, in: userDefaults)

        let trials = RingrtcFieldTrials.trials(with: userDefaults)

        XCTAssertNil(trials["WebRTC-Network-UseNWPathMonitor"])
    }
}
