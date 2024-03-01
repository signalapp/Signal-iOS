//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

extension AttachmentReference: TSResourceReference {
    public var resourceId: TSResourceId {
        fatalError("Unimplemented!")
    }

    public var sourceFilename: String? {
        switch owner {
        case let .message(.bodyAttachment(metadata)):
            return metadata.sourceFilename
        case let .message(.quotedReply(metadata)):
            return metadata.sourceFilename
        default:
            // Other types don't expose sourceFilename
            return nil
        }
    }
}
