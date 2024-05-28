//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

/// TSResourceStore + mutations needed for upload handling.
public protocol TSResourceUploadStore: TSResourceStore {

    func updateAsUploaded(
        attachmentStream: TSResourceStream,
        info: Attachment.TransitTierInfo,
        tx: DBWriteTransaction
    ) throws
}
