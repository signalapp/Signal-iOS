//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Testing
@testable import SignalServiceKit

struct RingrtcFieldTrialsTest {
    @Test(arguments: [
        (nil, true),
        ("true", false),
        ("false", true),
    ])
    func testNwPathMonitorEnabled(testCase: (valueFlag: String?, isEnabled: Bool)) {
        let valueFlags = testCase.valueFlag.map { ["ios.ringrtcNwPathMonitorTrialKillSwitch": $0] } ?? [:]
        let remoteConfig = RemoteConfig(clockSkew: 0, valueFlags: valueFlags)
        let trials = RingrtcFieldTrials.trials(with: remoteConfig)
        #expect(trials["WebRTC-Network-UseNWPathMonitor"] == (testCase.isEnabled ? "Enabled" : nil))
    }
}
