//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

// TODO: this is just a stub, essentially a holding cell
// for the unimplemented method below.
public class LegacyAttachmentMigrator {

    public static func createQuotedReplyMessageThumbnail(
        migratingLegacyAttachment attachment: TSAttachment,
        quotedReplyMessageId: Int64
    ) throws -> (Attachment.ConstructionParams, AttachmentReference.ConstructionParams) {
        fatalError("Unimplemented!")
    }
}
