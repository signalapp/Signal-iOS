//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

/// Just a container for simple static helper methods on KeyBackupServiceImpl
/// that can be shared with other classes (incl. objc classes).
@objc
public final class KeyBackupServiceObjcBridge: NSObject {

    private override init() {}

    @objc
    public static func normalizePin(_ pin: String) -> String {
        return KeyBackupServiceImpl.normalizePin(pin)
    }

    @objc
    public static var hasBackedUpMasterKey: Bool {
        DependenciesBridge.shared.keyBackupService.hasBackedUpMasterKey
    }

    @objc
    public static func deriveRegistrationLockToken() -> String? {
        return DependenciesBridge.shared.keyBackupService.deriveRegistrationLockToken()
    }
}
