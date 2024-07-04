//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
@testable import SignalServiceKit

extension TSAttachmentUpload {
    enum Mocks {
        typealias BlurHash = _TSAttachmentUpload_BlurHashMock
    }
}

class _TSAttachmentUpload_BlurHashMock: TSAttachmentUpload.Shims.BlurHash {

    func isValidVisualMedia(_ attachment: TSAttachmentStream) -> Bool {
        return true
    }

    func thumbnailImageSmallSync(_ attachment: TSAttachmentStream) -> UIImage? {
        return UIImage()
    }

    func computeBlurHashSync(for image: UIImage) throws -> String {
        return ""
    }

    func update(_ attachment: TSAttachment, withBlurHash: String, tx: DBWriteTransaction) {
        return
    }
}

// MARK: - TSResourceStore

class TSResourceUploadStoreMock: TSResourceStoreMock, TSResourceUploadStore {
    var filename: String!
    var size: Int!
    var uploadedAttachments = [TSResourceStream]()

    override func fetch(_ ids: [TSResourceId], tx: DBReadTransaction) -> [TSResource] {
        return []
    }

    func updateAsUploaded(
        attachmentStream: TSResourceStream,
        info: Attachment.TransitTierInfo,
        tx: DBWriteTransaction
    ) {
        uploadedAttachments.append(attachmentStream)
    }
}
