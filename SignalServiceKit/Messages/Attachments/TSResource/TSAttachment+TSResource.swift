//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

public import AVFoundation
import Foundation
public import YYImage

extension TSAttachment: TSResource {

    public var resourceId: TSResourceId {
        return .legacy(uniqueId: self.uniqueId)
    }

    public var resourceBlurHash: String? {
        return blurHash
    }

    public var transitCdnNumber: UInt32? {
        return cdnNumber
    }

    public var transitCdnKey: String? {
        return cdnKey
    }

    public var transitUploadTimestamp: UInt64? {
        return uploadTimestamp
    }

    public var unencryptedResourceByteCount: UInt32? {
        return byteCount
    }

    public var resourceEncryptionKey: Data? {
        return encryptionKey
    }

    public var encryptedResourceByteCount: UInt32? {
        guard
            let originalFilePath = (self as? TSAttachmentStream)?.originalFilePath,
            let nsFileSize = OWSFileSystem.fileSize(ofPath: originalFilePath)
        else {
            return nil
        }
        return nsFileSize.uint32Value
    }

    public var encryptedResourceSha256Digest: Data? {
        if let pointer = self as? TSAttachmentPointer {
            return pointer.digest
        } else if let stream = self as? TSAttachmentStream {
            return stream.digest
        }

        return nil
    }

    public var knownPlaintextResourceSha256Hash: Data? {
        // V1 attachments do not track a digest of their plaintext contents.
        return nil
    }

    public var isUploadedToTransitTier: Bool {
        if let stream = self as? TSAttachmentStream {
            return stream.isUploaded
        } else if self is TSAttachmentPointer {
            return true
        } else {
            return false
        }
    }

    public var hasMediaTierInfo: Bool {
        return false
    }

    public var mimeType: String {
        return contentType
    }

    public var concreteType: ConcreteTSResource {
        return .legacy(self)
    }

    public func asResourceStream() -> TSResourceStream? {
        let stream = self as? TSAttachmentStream
        guard stream?.originalFilePath != nil else {
            // Not _really_ a stream without a file.
            return nil
        }
        return stream
    }

    public func asResourceBackupThumbnail() -> TSResourceBackupThumbnail? {
        return nil
    }

    public func attachmentType(forContainingMessage: TSMessage, tx: DBReadTransaction) -> TSAttachmentType {
        return attachmentType
    }

    public func caption(forContainingMessage: TSMessage, tx: DBReadTransaction) -> String? {
        return caption
    }
}

extension TSAttachmentStream: TSResourceStream {

    public func decryptedRawData() throws -> Data {
        guard let originalFilePath else {
            throw OWSAssertionError("Missing file path!")
        }
        return try NSData(contentsOfFile: originalFilePath) as Data
    }

    public func decryptedLongText() throws -> String {
        guard let fileUrl = self.originalMediaURL else {
            throw OWSAssertionError("Missing file")
        }

        let data = try Data(contentsOf: fileUrl)

        guard let text = String(data: data, encoding: .utf8) else {
            throw OWSAssertionError("Can't parse oversize text data.")
        }
        return text
    }

    public func decryptedImage() throws -> UIImage {
        // TSAttachments keep the file decrypted on disk.
        guard let originalImage = self.originalImage else {
            throw OWSAssertionError("Not a valid image!")
        }
        return originalImage
    }

    public func decryptedYYImage() throws -> YYImage {
        guard let filePath = self.originalFilePath else {
            throw OWSAssertionError("Missing file")
        }
        guard let image = YYImage(contentsOfFile: filePath) else {
            throw OWSAssertionError("Invalid image")
        }
        return image
    }

    public func decryptedAVAsset() throws -> AVAsset {
        return try AVAsset.from(self)
    }

    public var concreteStreamType: ConcreteTSResourceStream {
        return .legacy(self)
    }

    public var cachedContentType: TSResourceContentType? {

        if isAudioMimeType {
            // Historically we did not cache this value. Rely on the mime type.
            return .audio(duration: audioDurationMetadata())
        }

        if isValidVideoCached?.boolValue == true {
            return .video(duration: self.videoDuration?.doubleValue, pixelSize: self.mediaPixelSizeMetadata())
        }

        if isAnimatedCached?.boolValue == true {
            return .animatedImage(pixelSize: self.mediaPixelSizeMetadata())
        }

        // It can be _both_ a valid image and animated, so
        // if we cached isValidImage but haven't checked and cached
        // if its animated, we don't want to return that its an image.
        // It could be animated, we don't know.
        if
            let isValidImageCached,
            isValidImageCached.boolValue
        {
            if !MimeTypeUtil.isSupportedMaybeAnimatedMimeType(mimeType) {
                // Definitely not animated.
                return .image(pixelSize: self.mediaPixelSizeMetadata())
            } else if isAnimatedCached?.boolValue == false {
                // We've checked and its not animated.
                return .image(pixelSize: self.mediaPixelSizeMetadata())
            } else {
                // Otherwise we can't know if this is a still or
                // animated image.
                return nil
            }
        }

        // If we have a known mime type, and the isValid{type} value is set and false,
        // we know its invalid.
        if isValidVideoCached?.boolValue == false, MimeTypeUtil.isSupportedVideoMimeType(mimeType) {
            return .invalid
        }
        if isValidImageCached?.boolValue == false, MimeTypeUtil.isSupportedImageMimeType(mimeType) {
            return .invalid
        }
        if isAnimatedCached?.boolValue == false, MimeTypeUtil.isSupportedDefinitelyAnimatedMimeType(mimeType) {
            return .invalid
        }

        // If we got this far no cached value was true.
        // But if they're all non-nil, we can return .file.
        // Otherwise we haven't checked (and cached) all the types
        // and we must return nil.
        if
            isValidVideoCached != nil,
            isValidImageCached != nil,
            isAnimatedCached != nil
        {
            return .file
        }

        return nil
    }

    public func computeContentType() -> TSResourceContentType {
        if let cachedContentType {
            return cachedContentType
        }

        // If the cache lookup fails, switch to the hard fetches.
        if isVideoMimeType && isValidVideo {
            return .video(duration: self.videoDuration?.doubleValue, pixelSize: mediaPixelSizeMetadata())
        } else if getAnimatedMimeType() != .notAnimated && isAnimatedContent {
            return .animatedImage(pixelSize: mediaPixelSizeMetadata())
        } else if isImageMimeType && isValidImage {
            return .image(pixelSize: mediaPixelSizeMetadata())
        }
        // We did not previously have utilities for determining
        // "valid" audio content. Rely on the cached value's
        // usage of the mime type check to catch that content type.

        return .file
    }

    public func computeIsValidVisualMedia() -> Bool {
        return self.isValidVisualMedia
    }

    private func mediaPixelSizeMetadata() -> TSResourceContentType.Metadata<CGSize> {
        let attachment = self
        return .init(
            getCached: { [attachment] in
                if
                    let cachedImageWidth = attachment.cachedImageWidth,
                    let cachedImageHeight = attachment.cachedImageHeight,
                    cachedImageWidth.floatValue > 0,
                    cachedImageHeight.floatValue > 0
                {
                    return .init(
                        width: CGFloat(cachedImageWidth.floatValue),
                        height: CGFloat(cachedImageHeight.floatValue)
                    )
                } else {
                    return nil
                }
            },
            compute: { [attachment] in
                return attachment.imageSizePixels
            }
        )
    }

    private func audioDurationMetadata() -> TSResourceContentType.Metadata<TimeInterval> {
        let attachment = self
        return .init(
            getCached: { [attachment] in
                return attachment.cachedAudioDurationSeconds?.doubleValue
            },
            compute: { [attachment] in
                return attachment.audioDurationSeconds()
            }
        )
    }

    // MARK: - Thumbnails

    public func thumbnailImage(quality: AttachmentThumbnailQuality) async -> UIImage? {
        return await withCheckedContinuation { continuation in
            self.thumbnailImage(
                quality: quality.tsQuality,
                success: { image in
                    continuation.resume(returning: image)
                },
                failure: {
                    continuation.resume(returning: nil)
                }
            )
        }
    }

    public func thumbnailImageSync(quality: AttachmentThumbnailQuality) -> UIImage? {
        return self.thumbnailImageSync(quality: quality.tsQuality)
    }

    // MARK: - Audio waveform

    public func audioWaveform() -> Task<AudioWaveform, Error> {
        DependenciesBridge.shared.audioWaveformManager.audioWaveform(forAttachment: self, highPriority: false)
    }

    public func highPriorityAudioWaveform() -> Task<AudioWaveform, Error> {
        DependenciesBridge.shared.audioWaveformManager.audioWaveform(forAttachment: self, highPriority: true)
    }
}

extension TSAttachment {

    var asResourcePointer: TSResourcePointer? {
        guard self.cdnKey.isEmpty.negated, self.cdnNumber > 0 else {
            return nil
        }
        return TSResourcePointer(resource: self, cdnNumber: self.cdnNumber, cdnKey: self.cdnKey)
    }
}
