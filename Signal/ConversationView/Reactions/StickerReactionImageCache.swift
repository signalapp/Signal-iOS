//
// Copyright 2026 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import SDWebImage
import SignalServiceKit

/// LRU cache of in-memory sticker images decoded from attachment streams.
actor StickerReactionImageCache {
    private let cache = LRUCache<Attachment.IDType, UIImage>(maxSize: 24)

    private var inFlightLoads = [Attachment.IDType: Task<UIImage?, Never>]()

    /// Reads from cache if available, else loads from disk and puts in the cache.
    func image(for stream: AttachmentStream) async -> UIImage? {
        if let cached = cache.get(key: stream.id) {
            return cached
        }

        if let existingTask = inFlightLoads[stream.id] {
            return await existingTask.value
        }

        // Not cancellable but that's ok; these aren't that expensive
        // and callsites (as of writing) don't cancel loads anyway.
        let task = Task<UIImage?, Never> {
            let image: UIImage?
            if stream.contentType.isAnimatedImage {
                image = try? stream.decryptedSDAnimatedImage()
            } else {
                image = stream.thumbnailImageSync(quality: .small)
            }
            return image
        }

        inFlightLoads[stream.id] = task
        let image = await task.value
        inFlightLoads[stream.id] = nil

        if let image {
            cache.set(key: stream.id, value: image)
        }
        return image
    }

    func clear() {
        cache.removeAllObjects()
        inFlightLoads.removeAll()
    }
}
