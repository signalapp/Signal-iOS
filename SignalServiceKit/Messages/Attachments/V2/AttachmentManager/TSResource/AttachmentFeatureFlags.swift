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

    public static let readMessages = false
    public static let writeMessages = false

    public static let incrementalMigration = false
}
