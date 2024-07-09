//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import AVKit
import Foundation

extension TSAttachmentMigration {

    struct PendingV2AttachmentFile {
        let blurHash: String?
        let sha256ContentHash: Data
        let encryptedByteCount: UInt32
        let unencryptedByteCount: UInt32
        let mimeType: String
        let encryptionKey: Data
        let digestSHA256Ciphertext: Data
        let localRelativeFilePath: String
        let renderingFlag: TSAttachmentMigration.V2RenderingFlag
        let sourceFilename: String?
        let validatedContentType: TSAttachmentMigration.V2Attachment.ContentType
        let audioDurationSeconds: Double?
        let mediaSizePixels: CGSize?
        let videoDurationSeconds: Double?
        let audioWaveformRelativeFilePath: String?
        let videoStillFrameRelativeFilePath: String?
    }

    class V2AttachmentContentValidator {

        // Note that unlike "live" attachment validation which assigns final
        // attachment file locations on the fly, the migrations are required
        // to "reserve" the final location using a random but persisted UUID.
        // This way if the migration is interrupted, any files we managed
        // to create before interruption are simply written over instead of
        // living forever unreferenced and consuming space.
        struct ReservedRelativeFileIds {
            let primaryFile: UUID
            let audioWaveform: UUID
            let videoStillFrame: UUID
        }

        static func validateContents(
            unencryptedFileUrl: URL,
            reservedFileIds: ReservedRelativeFileIds,
            encryptionKey: Data? = nil,
            mimeType: String,
            renderingFlag: TSAttachmentMigration.V2RenderingFlag,
            sourceFilename: String?
        ) throws -> TSAttachmentMigration.PendingV2AttachmentFile {
            let encryptionKey = encryptionKey ?? Cryptography.randomAttachmentEncryptionKey()
            let pendingAttachment = try validateContents(
                unencryptedFileUrl: unencryptedFileUrl,
                reservedFileIds: reservedFileIds,
                encryptionKey: encryptionKey,
                mimeType: mimeType,
                renderingFlag: renderingFlag,
                sourceFilename: sourceFilename
            )

            return pendingAttachment
        }

        private static func validateContents(
            unencryptedFileUrl: URL,
            reservedFileIds: ReservedRelativeFileIds,
            encryptionKey: Data,
            mimeType: String,
            renderingFlag: TSAttachmentMigration.V2RenderingFlag,
            sourceFilename: String?
        ) throws -> TSAttachmentMigration.PendingV2AttachmentFile {
            var mimeType = mimeType
            let contentTypeResult = try validateContentType(
                unencryptedFileUrl: unencryptedFileUrl,
                reservedFileIds: reservedFileIds,
                encryptionKey: encryptionKey,
                mimeType: &mimeType
            )
            return try prepareAttachmentFiles(
                unencryptedFileUrl,
                reservedFileIds: reservedFileIds,
                encryptionKey: encryptionKey,
                mimeType: mimeType,
                renderingFlag: renderingFlag,
                sourceFilename: sourceFilename,
                contentResult: contentTypeResult
            )
        }

        private static let thumbnailDimensionPointsForQuotedReply: CGFloat = 200

        private static func prepareQuotedReplyThumbnail(
            fromOriginalAttachmentStream stream: TSAttachmentMigration.V1Attachment,
            reservedFileIds: ReservedRelativeFileIds,
            renderingFlag: AttachmentReference.RenderingFlag,
            sourceFilename: String?
        ) throws -> TSAttachmentMigration.PendingV2AttachmentFile {
            guard let localFilePath = stream.localFilePath else {
                throw OWSAssertionError("Non stream")
            }

            let originalImage: UIImage

            // The thing called "contentType" on TSAttachment is the MIME type.
            let contentType = self.rawContentType(mimeType: stream.contentType)
            switch contentType {
            case .invalid, .audio, .file:
                throw OWSAssertionError("Non visual media target")
            case .image, .animatedImage:
                guard let image = UIImage(contentsOfFile: localFilePath) else {
                    throw OWSAssertionError("Unable to read image")
                }
                originalImage = image
            case .video:
                let asset: AVAsset = AVAsset(url: URL(fileURLWithPath: localFilePath))

                guard TSAttachmentMigration.OWSMediaUtils.isValidVideo(asset: asset) else {
                    throw OWSAssertionError("Unable to read video")
                }

                originalImage = try TSAttachmentMigration.OWSMediaUtils.thumbnail(
                    forVideo: asset,
                    maxSizePixels: .square(AttachmentThumbnailQuality.large.thumbnailDimensionPoints())
                )
            }

            guard
                let resizedImage = TSAttachmentMigration.OWSMediaUtils.resize(
                    image: originalImage,
                    maxDimensionPoints: Self.thumbnailDimensionPointsForQuotedReply
                ),
                let imageData = resizedImage.jpegData(compressionQuality: 0.8)
            else {
                throw OWSAssertionError("Unable to create thumbnail")
            }

            let tmpFile = OWSFileSystem.temporaryFileUrl(isAvailableWhileDeviceLocked: true)
            try imageData.write(to: tmpFile)

            let renderingFlagForThumbnail: TSAttachmentMigration.V2RenderingFlag
            switch renderingFlag {
            case .borderless:
                // Preserve borderless flag from the original
                renderingFlagForThumbnail = .borderless
            case .default, .voiceMessage, .shouldLoop:
                // Other cases become default for the still image.
                renderingFlagForThumbnail = .default
            }

            return try Self.validateContents(
                unencryptedFileUrl: tmpFile,
                reservedFileIds: reservedFileIds,
                mimeType: "image/jpeg",
                renderingFlag: renderingFlagForThumbnail,
                sourceFilename: sourceFilename
            )
        }

        // MARK: Content Type Validation

        static let supportedVideoMimeTypes: Set<String> = [
            "video/3gpp",
            "video/3gpp2",
            "video/mp4",
            "video/quicktime",
            "video/x-m4v",
            "video/mpeg",
        ]
        static let supportedAudioMimeTypes: Set<String> = [
            "audio/aac",
            "audio/x-m4p",
            "audio/x-m4b",
            "audio/x-m4a",
            "audio/wav",
            "audio/x-wav",
            "audio/x-mpeg",
            "audio/mpeg",
            "audio/mp4",
            "audio/mp3",
            "audio/mpeg3",
            "audio/x-mp3",
            "audio/x-mpeg3",
            "audio/aiff",
            "audio/x-aiff",
            "audio/3gpp2",
            "audio/3gpp",
        ]
        static let supportedImageMimeTypes: Set<String> = [
            "image/jpeg",
            "image/pjpeg",
            "image/png",
            "image/tiff",
            "image/x-tiff",
            "image/bmp",
            "image/x-windows-bmp",
            "image/heic",
            "image/heif",
            "image/webp",
        ]

        static let supportedDefinitelyAnimatedMimeTypes: Set<String> = [
            "image/gif",
            "image/apng",
            "image/vnd.mozilla.apng",
        ]

        public static let supportedMaybeAnimatedMimeTypes: Set<String> = Set([
            "image/webp",
            "image/png",
        ]).union(supportedDefinitelyAnimatedMimeTypes)

        private static func rawContentType(mimeType: String) -> TSAttachmentMigration.V2Attachment.ContentType {
            if Self.supportedVideoMimeTypes.contains(mimeType) {
                return .video
            } else if Self.supportedAudioMimeTypes.contains(mimeType) {
                return .audio
            } else if Self.supportedDefinitelyAnimatedMimeTypes.contains(mimeType) {
                return .animatedImage
            } else if Self.supportedImageMimeTypes.contains(mimeType) {
                return .image
            } else if Self.supportedMaybeAnimatedMimeTypes.contains(mimeType) {
                return .animatedImage
            } else {
                return .file
            }
        }

        fileprivate struct PendingFile {
            let tmpFileUrl: URL
            let isTmpFileEncrypted: Bool
            let reservedRelativeFilePath: String

            init(
                tmpFileUrl: URL,
                isTmpFileEncrypted: Bool,
                reservedRelativeFilePath: String
            ) {
                self.tmpFileUrl = tmpFileUrl
                self.isTmpFileEncrypted = isTmpFileEncrypted
                self.reservedRelativeFilePath = reservedRelativeFilePath
            }
        }

        private struct ContentTypeResult {
            let contentType: TSAttachmentMigration.V2Attachment.ContentType
            let audioDurationSeconds: Double?
            let mediaSizePixels: CGSize?
            let videoDurationSeconds: Double?
            let blurHash: String?
            let audioWaveformFile: TSAttachmentMigration.V2AttachmentContentValidator.PendingFile?
            let videoStillFrameFile: TSAttachmentMigration.V2AttachmentContentValidator.PendingFile?
        }

        private static func validateContentType(
            unencryptedFileUrl: URL,
            reservedFileIds: ReservedRelativeFileIds,
            encryptionKey: Data,
            mimeType: inout String
        ) throws -> ContentTypeResult {
            let invalidResult = ContentTypeResult(
                contentType: .invalid,
                audioDurationSeconds: nil,
                mediaSizePixels: nil,
                videoDurationSeconds: nil,
                blurHash: nil,
                audioWaveformFile: nil,
                videoStillFrameFile: nil
            )

            switch rawContentType(mimeType: mimeType) {
            case .invalid:
                return invalidResult
            case .file:
                return ContentTypeResult(
                    contentType: .file,
                    audioDurationSeconds: nil,
                    mediaSizePixels: nil,
                    videoDurationSeconds: nil,
                    blurHash: nil,
                    audioWaveformFile: nil,
                    videoStillFrameFile: nil
                )
            case .image, .animatedImage:
                return try validateImageContentType(
                    unencryptedFileUrl,
                    mimeType: &mimeType
                ) ?? invalidResult
            case .video:
                return try validateVideoContentType(
                    unencryptedFileUrl,
                    reservedFileIds: reservedFileIds,
                    mimeType: mimeType,
                    encryptionKey: encryptionKey
                ) ?? invalidResult
            case .audio:
                return try validateAudioContentType(
                    unencryptedFileUrl,
                    reservedFileIds: reservedFileIds,
                    mimeType: mimeType,
                    encryptionKey: encryptionKey
                ) ?? invalidResult
            }
        }

        // MARK: Image/Animated

        // Includes static and animated image validation.
        private static func validateImageContentType(
            _ unencryptedFileUrl: URL,
            mimeType: inout String
        ) throws -> ContentTypeResult? {
            let imageSource: TSAttachmentMigration.OWSImageSource = try {
                return try TSAttachmentMigration.OWSImageSource(fileUrl: unencryptedFileUrl)
            }()

            guard let imageMetadata = imageSource.imageMetadata(
                mimeTypeForValidation: mimeType
            ) else {
                return nil
            }

            guard imageMetadata.isValid else {
                return nil
            }

            let pixelSize = imageMetadata.pixelSize

            let blurHash: String? = {
                guard let image = UIImage(contentsOfFile: unencryptedFileUrl.path) else {
                    return nil
                }
                return try? BlurHash.computeBlurHashSync(for: image)
            }()

            let contentType: TSAttachmentMigration.V2Attachment.ContentType
            if imageMetadata.isAnimated {
                contentType = .animatedImage
            } else {
                contentType = .image
            }
            return ContentTypeResult(
                contentType: contentType,
                audioDurationSeconds: nil,
                mediaSizePixels: pixelSize,
                videoDurationSeconds: nil,
                blurHash: blurHash,
                audioWaveformFile: nil,
                videoStillFrameFile: nil
            )
        }

        // MARK: Video

        private static func validateVideoContentType(
            _ unencryptedFileUrl: URL,
            reservedFileIds: ReservedRelativeFileIds,
            mimeType: String,
            encryptionKey: Data
        ) throws -> ContentTypeResult? {
            let byteSize: Int = {
                return OWSFileSystem.fileSize(of: unencryptedFileUrl)?.intValue ?? 0
            }()
            guard byteSize < SignalAttachment.kMaxFileSizeVideo else {
                throw OWSAssertionError("Video too big!")
            }

            let asset: AVAsset = {
                return AVAsset(url: unencryptedFileUrl)
            }()

            guard TSAttachmentMigration.OWSMediaUtils.isValidVideo(asset: asset) else {
                return nil
            }

            let thumbnailImage = try? TSAttachmentMigration.OWSMediaUtils.thumbnail(
                forVideo: asset,
                maxSizePixels: .square(AttachmentThumbnailQuality.large.thumbnailDimensionPoints())
            )
            guard let thumbnailImage else {
                return nil
            }
            let stillFrameFile: TSAttachmentMigration.V2AttachmentContentValidator.PendingFile? = try thumbnailImage
            // Don't compress; we already size-limited this thumbnail, it already has whatever
            // compression applied to the source video, and we want a high fidelity still frame.
                .jpegData(compressionQuality: 1)
                .map { thumbnailData in
                    let thumbnailTmpFile = OWSFileSystem.temporaryFileUrl(isAvailableWhileDeviceLocked: true)
                    let (encryptedThumbnail, _) = try Cryptography.encrypt(thumbnailData, encryptionKey: encryptionKey)
                    try encryptedThumbnail.write(to: thumbnailTmpFile)
                    return TSAttachmentMigration.V2AttachmentContentValidator.PendingFile(
                        tmpFileUrl: thumbnailTmpFile,
                        isTmpFileEncrypted: true,
                        reservedRelativeFilePath: TSAttachmentMigration.V2Attachment.relativeFilePath(
                            reservedUUID: reservedFileIds.videoStillFrame
                        )
                    )
                }

            let blurHash = try? BlurHash.computeBlurHashSync(for: thumbnailImage)

            let duration = asset.duration.seconds

            // We have historically used the size of the still frame as the video size.
            let pixelSize = thumbnailImage.pixelSize

            return ContentTypeResult(
                contentType: .video,
                audioDurationSeconds: nil,
                mediaSizePixels: pixelSize,
                videoDurationSeconds: duration,
                blurHash: blurHash,
                audioWaveformFile: nil,
                videoStillFrameFile: stillFrameFile
            )
        }

        // MARK: Audio

        private static func validateAudioContentType(
            _ unencryptedFileUrl: URL,
            reservedFileIds: ReservedRelativeFileIds,
            mimeType: String,
            encryptionKey: Data
        ) throws -> ContentTypeResult? {
            let duration: TimeInterval
            do {
                duration = try computeAudioDuration(unencryptedFileUrl, mimeType: mimeType)
            } catch let error as NSError {
                if
                    error.domain == NSOSStatusErrorDomain,
                    (error.code == kAudioFileInvalidFileError || error.code == kAudioFileStreamError_InvalidFile)
                {
                    // These say the audio file is invalid.
                    // Eat them and return invalid instead of throwing
                    return nil
                } else {
                    throw error
                }
            }

            // Don't require the waveform file.
            let waveformFile = try? self.createAudioWaveform(
                unencryptedFileUrl,
                reservedFileIds: reservedFileIds,
                mimeType: mimeType,
                encryptionKey: encryptionKey
            )

            return ContentTypeResult(
                contentType: .audio,
                audioDurationSeconds: duration,
                mediaSizePixels: nil,
                videoDurationSeconds: nil,
                blurHash: nil,
                audioWaveformFile: waveformFile,
                videoStillFrameFile: nil
            )
        }

        // TODO someday: this loads an AVAsset (sometimes), and so does the audio waveform
        // computation. We can combine them so we don't waste effort.
        private static func computeAudioDuration(_ unencryptedFileUrl: URL, mimeType: String) throws -> TimeInterval {
            let player = try AVAudioPlayer(contentsOf: unencryptedFileUrl)
            player.prepareToPlay()
            return player.duration
        }

        private enum AudioWaveformFile {
            case unencrypted(URL)
            case encrypted(URL, encryptionKey: Data)
        }

        private static func createAudioWaveform(
            _ unencryptedFileUrl: URL,
            reservedFileIds: ReservedRelativeFileIds,
            mimeType: String,
            encryptionKey: Data
        ) throws -> TSAttachmentMigration.V2AttachmentContentValidator.PendingFile {
            let waveform: TSAttachmentMigration.AudioWaveform = try TSAttachmentMigration.AudioWaveformManager
                .buildAudioWaveForm(unencryptedFilePath: unencryptedFileUrl.path)

            let outputWaveformFile = OWSFileSystem.temporaryFileUrl(isAvailableWhileDeviceLocked: true)

            let waveformData = try waveform.archive()
            let (encryptedWaveform, _) = try Cryptography.encrypt(waveformData, encryptionKey: encryptionKey)
            try encryptedWaveform.write(to: outputWaveformFile, options: .atomicWrite)

            return .init(
                tmpFileUrl: outputWaveformFile,
                isTmpFileEncrypted: true,
                reservedRelativeFilePath: TSAttachmentMigration.V2Attachment.relativeFilePath(
                    reservedUUID: reservedFileIds.audioWaveform
                )
            )
        }

        // MARK: - File Preparation

        private static func prepareAttachmentFiles(
            _ unencryptedFileUrl: URL,
            reservedFileIds: ReservedRelativeFileIds,
            encryptionKey: Data,
            mimeType: String,
            renderingFlag: TSAttachmentMigration.V2RenderingFlag,
            sourceFilename: String?,
            contentResult: ContentTypeResult
        ) throws -> TSAttachmentMigration.PendingV2AttachmentFile {
            let primaryFilePlaintextHash = try computePlaintextHash(unencryptedFileUrl: unencryptedFileUrl)

            // First encrypt the files that need encrypting.
            let (primaryPendingFile, primaryFileMetadata) = try encryptPrimaryFile(
                unencryptedFileUrl: unencryptedFileUrl,
                reservedFileIds: reservedFileIds,
                encryptionKey: encryptionKey
            )
            guard let primaryFileDigest = primaryFileMetadata.digest else {
                throw OWSAssertionError("No digest in output")
            }
            guard
                let primaryPlaintextLength = primaryFileMetadata.plaintextLength
                    .map(UInt32.init(exactly:)) ?? nil
            else {
                throw OWSAssertionError("File too large")
            }

            guard
                let primaryEncryptedLength = OWSFileSystem.fileSize(
                    of: primaryPendingFile.tmpFileUrl
                )?.uint32Value
            else {
                throw OWSAssertionError("Couldn't determine size")
            }

            let audioWaveformFile = try contentResult.audioWaveformFile?.encryptFileIfNeeded(
                encryptionKey: encryptionKey
            )
            let videoStillFrameFile = try contentResult.videoStillFrameFile?.encryptFileIfNeeded(
                encryptionKey: encryptionKey
            )

            // Now we can copy files.
            for pendingFile in [primaryPendingFile, audioWaveformFile, videoStillFrameFile].compacted() {
                let destinationUrl = TSAttachmentMigration.V2Attachment.absoluteAttachmentFileURL(
                    relativeFilePath: pendingFile.reservedRelativeFilePath
                )
                guard OWSFileSystem.ensureDirectoryExists(destinationUrl.deletingLastPathComponent().path) else {
                    throw OWSAssertionError("Unable to create directory")
                }
                if OWSFileSystem.fileOrFolderExists(url: destinationUrl) {
                    // If something is at our reserved (random) location, since collisions are absurdly
                    // unlikely, it must mean we previously created the file at the reserved location
                    // but were interrupted. Delete what was there and keep going.
                    try OWSFileSystem.deleteFile(url: destinationUrl)
                }
                try OWSFileSystem.moveFile(
                    from: pendingFile.tmpFileUrl,
                    to: destinationUrl
                )
            }

            return TSAttachmentMigration.PendingV2AttachmentFile(
                blurHash: contentResult.blurHash,
                sha256ContentHash: primaryFilePlaintextHash,
                encryptedByteCount: primaryEncryptedLength,
                unencryptedByteCount: primaryPlaintextLength,
                mimeType: mimeType,
                encryptionKey: encryptionKey,
                digestSHA256Ciphertext: primaryFileDigest,
                localRelativeFilePath: primaryPendingFile.reservedRelativeFilePath,
                renderingFlag: renderingFlag,
                sourceFilename: sourceFilename,
                validatedContentType: contentResult.contentType,
                audioDurationSeconds: contentResult.audioDurationSeconds,
                mediaSizePixels: contentResult.mediaSizePixels,
                videoDurationSeconds: contentResult.videoDurationSeconds,
                audioWaveformRelativeFilePath: contentResult.audioWaveformFile?.reservedRelativeFilePath,
                videoStillFrameRelativeFilePath: contentResult.videoStillFrameFile?.reservedRelativeFilePath
            )
        }

        // MARK: - Encryption

        private static func computePlaintextHash(unencryptedFileUrl: URL) throws -> Data {
            return try Cryptography.computeSHA256DigestOfFile(at: unencryptedFileUrl)
        }

        private static func encryptPrimaryFile(
            unencryptedFileUrl: URL,
            reservedFileIds: ReservedRelativeFileIds,
            encryptionKey: Data
        ) throws -> (TSAttachmentMigration.V2AttachmentContentValidator.PendingFile, EncryptionMetadata) {
            let outputFile = OWSFileSystem.temporaryFileUrl(isAvailableWhileDeviceLocked: true)
            let encryptionMetadata = try Cryptography.encryptAttachment(
                at: unencryptedFileUrl,
                output: outputFile,
                encryptionKey: encryptionKey
            )
            return (
                TSAttachmentMigration.V2AttachmentContentValidator.PendingFile(
                    tmpFileUrl: outputFile,
                    isTmpFileEncrypted: true,
                    reservedRelativeFilePath: TSAttachmentMigration.V2Attachment.relativeFilePath(
                        reservedUUID: reservedFileIds.primaryFile
                    )
                ),
                encryptionMetadata
            )
        }
    }
}

extension TSAttachmentMigration.V2AttachmentContentValidator.PendingFile {

    fileprivate func encryptFileIfNeeded(
        encryptionKey: Data
    ) throws -> Self {
        if isTmpFileEncrypted {
            return self
        }

        let outputFile = OWSFileSystem.temporaryFileUrl(isAvailableWhileDeviceLocked: true)
        // Encrypt _without_ custom padding; we never send these files
        // and just use them locally, so no need for custom padding
        // that later requires out-of-band plaintext length tracking
        // so we can trim the custom padding at read time.
        _ = try Cryptography.encryptFile(
            at: tmpFileUrl,
            output: outputFile,
            encryptionKey: encryptionKey
        )
        return Self(
            tmpFileUrl: outputFile,
            isTmpFileEncrypted: true,
            // Preserve the reserved file path; this is already
            // on the ContentType enum and musn't be changed.
            reservedRelativeFilePath: self.reservedRelativeFilePath
        )
    }
}
