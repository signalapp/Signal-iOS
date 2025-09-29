//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import CoreImage
import Foundation
import SDWebImageWebPCoder

final public class AttachmentThumbnailServiceImpl: AttachmentThumbnailService {

    public init() {}

    private let taskQueue = ConcurrentTaskQueue(concurrentLimit: 1)

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
            return try? await taskQueue.run { [weak self] in
                return self?.thumbnailImageSync(for: attachmentStream, quality: quality)
            }
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

    public func backupThumbnailData(image: UIImage) throws -> Data {
        let initialMaxFileSize = UInt32(CGFloat(AttachmentThumbnailQuality.backupThumbnailMaxSizeBytes) * 0.8)
        return try backupThumbnailData(
            image: image,
            targetMaxFileSize: initialMaxFileSize
        )
    }

    private func backupThumbnailData(
        image: UIImage,
        targetMaxFileSize: UInt32
    ) throws -> Data {
        let maxPixelSize = AttachmentThumbnailQuality.backupThumbnailDimensionPixels
        let targetSize: CGSize
        if image.pixelSize.largerAxis > maxPixelSize {
            let scaleRatio = maxPixelSize / image.pixelSize.largerAxis
            targetSize = CGSize(
                width: image.size.width * scaleRatio,
                height: image.size.height * scaleRatio
            )
        } else {
            targetSize = image.size
        }

        guard let data = SDImageWebPCoder.shared.encodedData(
            with: image,
            format: .webP,
            options: [
                .encodeWebPMethod: 6,
                .encodeMaxFileSize: targetMaxFileSize,
                .encodeMaxPixelSize: targetSize
            ]
        ) else {
            throw OWSAssertionError("Unable to generate webp")
        }
        if data.count > AttachmentThumbnailQuality.backupThumbnailMaxSizeBytes {
            if targetMaxFileSize < 256 {
                throw OWSAssertionError("Generated thumbnail too large")
            } else {
                let nextTargetMaxFileSize = UInt32(Double(targetMaxFileSize) * 0.25)
                return try backupThumbnailData(
                    image: image,
                    targetMaxFileSize: nextTargetMaxFileSize
                )
            }
        }
        return data
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
                    mimeType: MimeTypeUtil.thumbnailMimetype(
                        fullsizeMimeType: attachmentStream.mimeType,
                        quality: quality
                    )
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
            let thumbnailMimeType = MimeTypeUtil.thumbnailMimetype(
                fullsizeMimeType: attachmentStream.mimeType,
                quality: quality
            )

            let imageData: Data?
            switch thumbnailMimeType{
            case MimeType.imagePng.rawValue:
                imageData = thumbnail.pngData()
            case MimeType.imageJpeg.rawValue:
                imageData = thumbnail.jpegData(compressionQuality: 0.85)
            case MimeType.imageWebp.rawValue where quality == .backupThumbnail:
                imageData = try? backupThumbnailData(image: thumbnail)
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
