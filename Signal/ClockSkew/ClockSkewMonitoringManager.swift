//
// Copyright 2026 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import SignalServiceKit

/// Responsible for blocking use of the main app while the device's clock is
/// skewed too far from the server's.
class ClockSkewMonitoringManager {
    private let clockSkewManager: ClockSkewManager
    private let windowManager: WindowManager

    init(
        clockSkewManager: ClockSkewManager,
        windowManager: WindowManager,
    ) {
        self.clockSkewManager = clockSkewManager
        self.windowManager = windowManager
    }

    func start() {
        AssertIsOnMainThread()

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(clockSkewDidChange),
            name: .clockSkewDidChange,
            object: nil,
        )

        updateIsBlocked()
    }

    @objc
    private func clockSkewDidChange() {
        AssertIsOnMainThread()

        updateIsBlocked()
    }

    private func updateIsBlocked() {
        // The skew is re-measured when the clock changes or we become active, so
        // a user who corrects their clock gets unblocked without relaunching.
        windowManager.isClockSkewBlockActive = clockSkewManager.isClockSkewed
    }
}
