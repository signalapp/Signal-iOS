//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

public class AttachmentThumbnailServiceImpl: AttachmentThumbnailService {

    public init() {}

    private let taskQueue = SerialTaskQueue()

    public func thumbnailImage(
        for attachmentStream: AttachmentStream,
        quality: AttachmentThumbnailQuality
    ) async -> UIImage? {
        // Check if we even need to generate anything before enqueing.
        switch thumbnailSpec(for: attachmentStream, quality: quality) {
        case .cannotGenerate:
            return nil
        case .originalFits(let image):
            return image
        case .requiresGeneration:
            return try? await taskQueue.enqueue(operation: {
                return self.thumbnailImageSync(for: attachmentStream, quality: quality)
            }).value
        }
    }

    public func thumbnailImageSync(
        for attachmentStream: AttachmentStream,
        quality: AttachmentThumbnailQuality
    ) -> UIImage? {
        switch thumbnailSpec(for: attachmentStream, quality: quality) {
        case .cannotGenerate:
            return nil
        case .originalFits(let image):
            return image
        case .requiresGeneration:
            break
        }

        if let cached = cachedThumbnail(for: attachmentStream, quality: quality) {
            return cached
        }

        let thumbnailImage: UIImage?
        if attachmentStream.mimeType == MimeType.imageWebp.rawValue {
            thumbnailImage = try? attachmentStream
                .decryptedRawData()
                .stillForWebpData()?
                .resized(maxDimensionPoints: quality.thumbnailDimensionPoints())
        } else {
            thumbnailImage = try? UIImage
                .fromEncryptedFile(
                    at: AttachmentStream.absoluteAttachmentFileURL(
                        relativeFilePath: attachmentStream.localRelativeFilePath
                    ),
                    encryptionKey: attachmentStream.attachment.encryptionKey,
                    plaintextLength: attachmentStream.unencryptedByteCount,
                    mimeType: attachmentStream.mimeType
                )
                .resized(maxDimensionPoints: quality.thumbnailDimensionPoints())
        }

        guard let thumbnailImage else {
            owsFailDebug("Unable to generate thumbnail")
            return nil
        }
        cacheThumbnail(thumbnailImage, for: attachmentStream, quality: quality)
        return thumbnailImage
    }

    private enum ThumbnailSpec {
        case cannotGenerate
        case originalFits(UIImage)
        case requiresGeneration
    }

    private func thumbnailSpec(
        for attachmentStream: AttachmentStream,
        quality: AttachmentThumbnailQuality
    ) -> ThumbnailSpec {
        switch attachmentStream.contentType {
        case .invalid, .file, .audio:
            return .cannotGenerate

        case .video:
            // We always provide the still frame regardless of size,
            // since video is already size-limited.
            if let image = try? attachmentStream.decryptedImage() {
                return .originalFits(image)
            } else {
                return .cannotGenerate
            }

        case .image(let pixelSize), .animatedImage(let pixelSize):
            let pointSize = AttachmentThumbnailQuality.pointSize(pixelSize: pixelSize)
            let targetSize = quality.thumbnailDimensionPoints()

            if pointSize.width < targetSize, pointSize.height < targetSize {
                if let image = try? attachmentStream.decryptedImage() {
                    return .originalFits(image)
                } else {
                    // If we can't read the original image, we can't generate.
                    return .cannotGenerate
                }
            } else {
                return .requiresGeneration
            }
        }
    }

    private func cachedThumbnail(
        for attachmentStream: AttachmentStream,
        quality: AttachmentThumbnailQuality
    ) -> UIImage? {
        let cacheUrl = AttachmentThumbnailQuality.thumbnailCacheFileUrl(
            for: attachmentStream,
            at: quality
        )
        if OWSFileSystem.fileOrFolderExists(url: cacheUrl) {
            do {
                return try UIImage.fromEncryptedFile(
                    at: cacheUrl,
                    encryptionKey: attachmentStream.attachment.encryptionKey,
                    // thumbnails have no special padding;
                    // therefore no plaintext length needed.
                    plaintextLength: nil,
                    mimeType: MimeTypeUtil.thumbnailMimetype(fullsizeMimeType: attachmentStream.mimeType)
                )
            } catch {
                Logger.error("Failed to read cached attachment.")
                // Delete the cached file, and just recompute.
                try? OWSFileSystem.deleteFile(url: cacheUrl)
                return nil
            }
        }
        return nil
    }

    private func cacheThumbnail(
        _ thumbnail: UIImage,
        for attachmentStream: AttachmentStream,
        quality: AttachmentThumbnailQuality
    ) {
        let cacheUrl = AttachmentThumbnailQuality.thumbnailCacheFileUrl(
            for: attachmentStream,
            at: quality
        )
        do {
            try OWSFileSystem.deleteFileIfExists(url: cacheUrl)
            let thumbnailMimeType = MimeTypeUtil.thumbnailMimetype(fullsizeMimeType: attachmentStream.mimeType)

            let imageData: Data?
            switch thumbnailMimeType{
            case MimeType.imagePng.rawValue:
                imageData = thumbnail.pngData()
            case MimeType.imageJpeg.rawValue:
                imageData = thumbnail.jpegData(compressionQuality: 0.85)
            default:
                owsFailDebug("Unknown thumbnail mime type!")
                return
            }

            guard let imageData else {
                owsFailDebug("Unable to generate thumbnail data")
                return
            }

            // Encrypt _without_ custom padding; we never send these files
            // and just use them locally, so no need for custom padding
            // that later requires out-of-band plaintext length tracking
            // so we can trim the custom padding at read time.
            let (encryptedImageData, _) = try Cryptography.encrypt(
                imageData,
                encryptionKey: attachmentStream.attachment.encryptionKey
            )

            try encryptedImageData.write(to: cacheUrl, options: .atomic)
        } catch {
            owsFailDebug("Failed to cache thumbnail image")
        }
    }
}
