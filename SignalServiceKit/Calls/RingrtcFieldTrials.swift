//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

/// Utilities for saving and loading RingRTC field trials from ``UserDefaults``.
///
/// We want to run various WebRTC "field trials", which we set up via RingRTC's ``CallManager``.
/// We want to gate these field trials on remote config values. Unfortunately, the iOS app
/// initializes ``CallManager`` early during app startup, before the remote config values are ready.
/// To work around this without a larger refactor, we cache these remote config values in
/// ``UserDefaults``.
public enum RingrtcFieldTrials {
    private static var disableNwPathMonitorTrialKey: String { "ringrtcDisableNwPathMonitorFieldTrial" }

    public static func trials(with userDefaults: UserDefaults) -> [String: String] {
        var result = [String: String]()

        if isNwPathMonitorTrialEnabled(with: userDefaults) {
            result["WebRTC-Network-UseNWPathMonitor"] = "Enabled"
        }

        return result
    }

    private static func isNwPathMonitorTrialEnabled(with userDefaults: UserDefaults) -> Bool {
        !userDefaults.bool(forKey: disableNwPathMonitorTrialKey)
    }

    static func saveNwPathMonitorTrialState(isEnabled: Bool, in userDefaults: UserDefaults) {
        Logger.info("Saving RingRTC nwPathMonitor field trial state as \(isEnabled)")
        if isEnabled {
            userDefaults.removeObject(forKey: disableNwPathMonitorTrialKey)
        } else {
            userDefaults.set(true, forKey: disableNwPathMonitorTrialKey)
        }
    }
}
