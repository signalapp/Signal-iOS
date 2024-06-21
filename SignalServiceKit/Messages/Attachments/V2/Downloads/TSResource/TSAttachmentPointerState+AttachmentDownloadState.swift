//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

extension TSAttachmentPointerState {

    var asDownloadState: AttachmentDownloadState {
        switch self {
        case .enqueued:
            return .enqueuedOrDownloading
        case .downloading:
            return .enqueuedOrDownloading
        case .failed:
            return .failed
        case .pendingMessageRequest, .pendingManualDownload:
            // This distinction is irrelevant for v2;
            // its just not enqueued, and we enqueue it
            // when we enqueue it.
            return .none
        }
    }
}
