//
// Copyright 2026 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

public enum RingrtcSvcConfig {
    public static func enableSvc(with remoteConfig: RemoteConfig) -> Bool {
        if DebugFlags.callingEnableSvc.get() {
            return true
        }
        return remoteConfig.ringrtcSvcEnabled
    }

    public static func svcMode(with remoteConfig: RemoteConfig) -> String {
        return remoteConfig.ringrtcSvcMode
    }

    public static func svcModeForScreenshare(with remoteConfig: RemoteConfig) -> String {
        return remoteConfig.ringrtcSvcModeForScreenshare
    }

    public static func svcMaxBitrateBps(with remoteConfig: RemoteConfig) -> UInt32 {
        let value = DebugFlags.callingSvcMaxBitrateBps.get()
        if value > 0 {
            return UInt32(value)
        }
        return remoteConfig.ringrtcSvcMaxBitrateBps
    }
}
