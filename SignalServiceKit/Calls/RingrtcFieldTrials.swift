//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

/// Utilities for loading RingRTC field trials from ``RemoteConfig``s.
public enum RingrtcFieldTrials {
    public static func trials(with remoteConfig: RemoteConfig) -> [String: String] {
        var result = [String: String]()

        if remoteConfig.ringrtcNwPathMonitorTrial {
            result["WebRTC-Network-UseNWPathMonitor"] = "Enabled"
        }

        return result
    }
}
