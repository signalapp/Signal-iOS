//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

public class AttachmentThumbnailServiceImpl: AttachmentThumbnailService {

    public init() {}

    private var taskQueue = SerialTaskQueue()

    public func thumbnailImage(
        for attachmentStream: AttachmentStream,
        quality: AttachmentThumbnailQuality
    ) async -> UIImage? {
        return try? await taskQueue.enqueue(operation: {
            return self.thumbnailImageSync(for: attachmentStream, quality: quality)
        }).value
    }

    public func thumbnailImageSync(
        for attachmentStream: AttachmentStream,
        quality: AttachmentThumbnailQuality
    ) -> UIImage? {
        fatalError("Unimplemented")
    }
}
