//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

public enum AttachmentFeatureFlags {
    /// Setting this to true will prevent the migration of TSMessage's TSAttachments from making
    /// _further_ progress. Already-migrated TSAttachments cannot be undone; we also cannot
    /// turn off usage of v2 for _new_ attachments.
    /// This is "break glass", to be used if migrations are crash-looping, to prevent the crash looping
    /// until a fix can be merged and this can be re-set to false to continue the migration.
    public static var incrementalMigrationBreakGlass = false
}
