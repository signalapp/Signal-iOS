//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

extension OWSLinkPreview {

    internal enum AttachmentReference {
        /// If uniqueId is nil, there is no attachment.
        case legacy(uniqueId: String?)
        /// There may or may not be an attachment, check the AttachmentReferences table.
        case v2
    }

    fileprivate var attachmentReference: AttachmentReference {
        if usesV2AttachmentReference {
            return .v2
        }
        return .legacy(uniqueId: self.legacyImageAttachmentId)
    }

    public static func withoutImage(urlString: String, title: String? = nil) -> OWSLinkPreview {
        let attachmentRef: AttachmentReference = FeatureFlags.newAttachmentsUseV2 ? .v2 : .legacy(uniqueId: nil)
        return OWSLinkPreview(urlString: urlString, title: title, attachmentRef: attachmentRef)
    }
}
