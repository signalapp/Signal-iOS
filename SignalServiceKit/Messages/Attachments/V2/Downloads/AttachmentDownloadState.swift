//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

/// Note that this state is scoped to a source; the download state
/// for the transit tier may differ from the media tier.
public enum AttachmentDownloadState {
    /// There is no pending download for this attachment, likely because none
    /// was triggered by the user or by auto-download settings.
    case none

    /// The download is enqueued and will be downloaded once the queue is freed.
    case enqueued

    /// There is an in-progress download.
    case downloading

    /// The download was attempted but failed.
    case failed
}
