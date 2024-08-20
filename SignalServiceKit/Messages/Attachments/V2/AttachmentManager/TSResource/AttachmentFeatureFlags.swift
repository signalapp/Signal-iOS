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

    public static var readMessages = true
    public static var writeMessages = true

    public static var incrementalMigration = true
}
