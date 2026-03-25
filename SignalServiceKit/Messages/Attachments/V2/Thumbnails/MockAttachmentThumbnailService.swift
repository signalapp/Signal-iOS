//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

#if TESTABLE_BUILD

import Foundation
public import UIKit

open class MockAttachmentThumbnailService: AttachmentThumbnailService {

    public init() {}

    open func thumbnailImage(
        for attachmentStream: AttachmentStream,
        quality: AttachmentThumbnailQuality,
    ) async -> UIImage? {
        return nil
    }

    open func thumbnailImageSync(
        for attachmentStream: AttachmentStream,
        quality: AttachmentThumbnailQuality,
    ) -> UIImage? {
        return nil
    }

    open func backupThumbnailData(image: UIImage) throws -> Data {
        return Data()
    }
}

#endif
