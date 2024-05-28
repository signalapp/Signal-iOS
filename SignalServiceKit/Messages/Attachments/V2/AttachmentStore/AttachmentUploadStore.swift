//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

/// AttachmentStore + mutations needed for upload handling.
public protocol AttachmentUploadStore: AttachmentStore {

    /// Mark the attachment as having been uploaded to the transit tier.
    func markUploadedToTransitTier(
        attachmentStream: AttachmentStream,
        info: Attachment.TransitTierInfo,
        tx: DBWriteTransaction
    ) throws
}
