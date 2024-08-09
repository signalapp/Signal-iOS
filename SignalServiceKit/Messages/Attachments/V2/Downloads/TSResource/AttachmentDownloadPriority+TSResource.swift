//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

extension AttachmentDownloadPriority {

    /// V2 priority corresponds to old "behavior" in terms of which checks it bypasses.
    var tsDownloadBehavior: TSAttachmentDownloadBehavior {
        switch self {
        case .backupRestoreHigh, .backupRestoreLow:
            return .default
        case .default:
            return .default
        case .userInitiated:
            return .bypassAll
        case .localClone:
            // This won't actually download, so we "bypass" rules.
            return .bypassAll
        }
    }
}
