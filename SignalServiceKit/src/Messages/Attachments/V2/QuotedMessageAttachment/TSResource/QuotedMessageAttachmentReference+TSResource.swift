//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

extension QuotedMessageAttachmentReference {

    var tsReference: TSQuotedMessageResourceReference {
        switch self {
        case .thumbnail(let thumbnail):
            return .thumbnail(thumbnail.tsThumbnail)
        case .stub(let stub):
            return .stub(stub)
        }
    }
}

extension QuotedMessageAttachmentReference.Thumbnail {

    var tsThumbnail: TSQuotedMessageResourceReference.Thumbnail {
        return .init(
            attachmentRef: attachmentRef,
            mimeType: mimeType,
            sourceFilename: sourceFilename
        )
    }
}
