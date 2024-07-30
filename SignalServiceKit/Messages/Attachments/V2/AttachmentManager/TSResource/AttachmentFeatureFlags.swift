//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

public enum AttachmentFeatureFlags {

    public static let readThreadWallpapers = true
    public static let writeThreadWallpapers = true

    public static let readStories = true
    public static let writeStories = true

    public static var readMessages: Bool {
        FeatureFlags.v2MessageAttachmentsForceEnable
            || (userDefaults?.bool(forKey: enableForMessagesKey) == true)
    }
    public static var writeMessages: Bool {
        FeatureFlags.v2MessageAttachmentsForceEnable
            || (userDefaults?.bool(forKey: enableForMessagesKey) == true)
    }

    public static var incrementalMigration: Bool {
        FeatureFlags.v2MessageAttachmentsForceEnable
            || (userDefaults?.bool(forKey: enableForMessagesKey) == true)
    }

    private static let enableForMessagesKey = "AttachmentFeatureFlags_enableForMessages"

    public static func enableV2ForMessages() {
        guard FeatureFlags.v2MessageAttachmentsToggle else { return }
        userDefaults?.set(true, forKey: enableForMessagesKey)
    }

    private static let userDefaults = UserDefaults(suiteName: TSConstants.applicationGroup)
}
