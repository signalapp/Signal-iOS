//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import AVFoundation
import CryptoKit
import Foundation

public class AttachmentContentValidatorImpl: AttachmentContentValidator {

    private let audioWaveformManager: AudioWaveformManager
    private let orphanedAttachmentCleaner: OrphanedAttachmentCleaner

    public init(
        audioWaveformManager: AudioWaveformManager,
        orphanedAttachmentCleaner: OrphanedAttachmentCleaner
    ) {
        self.audioWaveformManager = audioWaveformManager
        self.orphanedAttachmentCleaner = orphanedAttachmentCleaner
    }

    public func validateContents(
        dataSource: DataSource,
        shouldConsume: Bool,
        mimeType: String,
        renderingFlag: AttachmentReference.RenderingFlag,
        sourceFilename: String?
    ) throws -> PendingAttachment {
        let input: Input = {
            if
                let fileDataSource = dataSource as? DataSourcePath,
                let fileUrl = fileDataSource.dataUrl
            {
                return .unencryptedFile(fileUrl)
            } else {
                return .inMemory(dataSource.data)
            }
        }()
        let encryptionKey = Cryptography.randomAttachmentEncryptionKey()
        let pendingAttachment = try validateContents(
            input: input,
            encryptionKey: encryptionKey,
            mimeType: mimeType,
            renderingFlag: renderingFlag,
            sourceFilename: sourceFilename
        )

        if shouldConsume {
            try dataSource.consumeAndDelete()
        }

        return pendingAttachment
    }

    public func validateContents(
        data: Data,
        mimeType: String,
        renderingFlag: AttachmentReference.RenderingFlag,
        sourceFilename: String?
    ) throws -> PendingAttachment {
        let encryptionKey = Cryptography.randomAttachmentEncryptionKey()
        let pendingAttachment = try validateContents(
            input: .inMemory(data),
            encryptionKey: encryptionKey,
            mimeType: mimeType,
            renderingFlag: renderingFlag,
            sourceFilename: sourceFilename
        )

        return pendingAttachment
    }

    public func validateContents(
        ofEncryptedFileAt fileUrl: URL,
        encryptionKey: Data,
        plaintextLength: UInt32?,
        digestSHA256Ciphertext: Data,
        mimeType: String,
        renderingFlag: AttachmentReference.RenderingFlag,
        sourceFilename: String?
    ) throws -> PendingAttachment {
        // Very very first thing: validate the digest.
        // Throw if this fails.
        var decryptedLength = 0
        try Cryptography.decryptFile(
            at: fileUrl,
            metadata: .init(
                key: encryptionKey,
                digest: digestSHA256Ciphertext,
                plaintextLength: plaintextLength.map(Int.init)
            ),
            output: { data in
                decryptedLength += data.count
            }
        )
        let plaintextLength = plaintextLength ?? UInt32(decryptedLength)

        let input = Input.encryptedFile(
            fileUrl,
            encryptionKey: encryptionKey,
            plaintextLength: plaintextLength,
            digestSHA256Ciphertext: digestSHA256Ciphertext
        )
        return try validateContents(
            input: input,
            encryptionKey: encryptionKey,
            mimeType: mimeType,
            renderingFlag: renderingFlag,
            sourceFilename: sourceFilename
        )
    }

    public func reValidateContents(
        ofEncryptedFileAt fileUrl: URL,
        encryptionKey: Data,
        plaintextLength: UInt32,
        mimeType: String
    ) throws -> RevalidatedAttachment {
        let input = Input.encryptedFile(
            fileUrl,
            encryptionKey: encryptionKey,
            plaintextLength: plaintextLength,
            // No need to validate digest
            digestSHA256Ciphertext: nil
        )
        var mimeType = mimeType
        let contentTypeResult = try validateContentType(
            input: input,
            encryptionKey: encryptionKey,
            mimeType: &mimeType
        )
        return try prepareAttachmentContentTypeFiles(
            input: input,
            encryptionKey: encryptionKey,
            mimeType: mimeType,
            contentResult: contentTypeResult
        )
    }

    public func validateContents(
        ofBackupMediaFileAt fileUrl: URL,
        outerEncryptionData: EncryptionMetadata,
        innerEncryptionData: EncryptionMetadata,
        finalEncryptionKey: Data,
        mimeType: String,
        renderingFlag: AttachmentReference.RenderingFlag,
        sourceFilename: String?
    ) throws -> any PendingAttachment {

        // This temp file becomes the new attachment source, and will
        // be owned by that part of the process and doesn't need to be
        // cleaned up here.
        let tmpFileUrl = OWSFileSystem.temporaryFileUrl()
        try Cryptography.decryptFile(
            at: fileUrl,
            metadata: outerEncryptionData,
            output: tmpFileUrl
        )

        // Get plaintext length if not given, and validate digest if given.
        let plaintextLength: Int
        if let innerPlainTextLength = innerEncryptionData.plaintextLength, innerEncryptionData.digest == nil {
            plaintextLength = innerPlainTextLength
        } else {
            var decryptedLength = 0
            try Cryptography.decryptFile(
                at: tmpFileUrl,
                metadata: innerEncryptionData,
                output: { data in
                    decryptedLength += data.count
                }
            )
            plaintextLength = decryptedLength
        }

        let input = Input.encryptedFile(
            tmpFileUrl,
            encryptionKey: innerEncryptionData.key,
            plaintextLength: UInt32(plaintextLength),
            digestSHA256Ciphertext: innerEncryptionData.digest
        )
        return try validateContents(
            input: input,
            encryptionKey: finalEncryptionKey,
            mimeType: mimeType,
            renderingFlag: renderingFlag,
            sourceFilename: sourceFilename
        )
    }

    public func prepareOversizeTextIfNeeded(
        from messageBody: MessageBody
    ) throws -> ValidatedMessageBody? {
        guard !messageBody.text.isEmpty else {
            return nil
        }
        let truncatedText = messageBody.text.trimmedIfNeeded(maxByteCount: Int(kOversizeTextMessageSizeThreshold))
        guard let truncatedText else {
            // No need to truncate
            return .inline(messageBody)
        }
        let truncatedBody = MessageBody(text: truncatedText, ranges: messageBody.ranges)

        guard let textData = messageBody.text.data(using: .utf8) else {
            throw OWSAssertionError("Unable to encode text")
        }
        let input = Input.inMemory(textData)
        let encryptionKey = Cryptography.randomAttachmentEncryptionKey()
        let pendingAttachment = try self.validateContents(
            input: input,
            encryptionKey: encryptionKey,
            mimeType: MimeType.textXSignalPlain.rawValue,
            renderingFlag: .default,
            sourceFilename: nil
        )

        return .oversize(truncated: truncatedBody, fullsize: pendingAttachment)
    }

    public func prepareQuotedReplyThumbnail(
        fromOriginalAttachment originalAttachment: AttachmentStream,
        originalReference: AttachmentReference
    ) throws -> QuotedReplyAttachmentDataSource {
        let pendingAttachment = try prepareQuotedReplyThumbnail(
            fromOriginalAttachmentStream: originalAttachment,
            renderingFlag: originalReference.renderingFlag,
            sourceFilename: originalReference.sourceFilename
        )

        let originalMessageRowId: Int64?
        switch originalReference.owner {
        case .message(let messageSource):
            originalMessageRowId = messageSource.messageRowId
        case .storyMessage, .thread:
            owsFailDebug("Should not be quote replying a non-message attachment")
            originalMessageRowId = nil
        }

        return .fromPendingAttachment(
            pendingAttachment,
            originalAttachmentMimeType: originalAttachment.attachment.mimeType,
            originalAttachmentSourceFilename: originalReference.sourceFilename,
            originalMessageRowId: originalMessageRowId
        )
    }

    public func prepareQuotedReplyThumbnail(
        fromOriginalAttachmentStream: AttachmentStream
    ) throws -> PendingAttachment {
        return try self.prepareQuotedReplyThumbnail(
            fromOriginalAttachmentStream: fromOriginalAttachmentStream,
            // These are irrelevant for this usage
            renderingFlag: .default,
            sourceFilename: nil
        )
    }

    // MARK: - Private

    private struct PendingAttachmentImpl: PendingAttachment {
        let blurHash: String?
        let sha256ContentHash: Data
        let encryptedByteCount: UInt32
        let unencryptedByteCount: UInt32
        let mimeType: String
        let encryptionKey: Data
        let digestSHA256Ciphertext: Data
        let localRelativeFilePath: String
        private(set) var renderingFlag: AttachmentReference.RenderingFlag
        let sourceFilename: String?
        let validatedContentType: Attachment.ContentType
        let orphanRecordId: OrphanedAttachmentRecord.IDType

        mutating func removeBorderlessRenderingFlagIfPresent() {
            switch renderingFlag {
            case .borderless:
                renderingFlag = .default
            default:
                return
            }
        }
    }

    private struct RevalidatedAttachmentImpl: RevalidatedAttachment {
        let validatedContentType: Attachment.ContentType
        let mimeType: String
        let blurHash: String?
        let orphanRecordId: OrphanedAttachmentRecord.IDType
    }

    private enum Input {
        case inMemory(Data)
        case unencryptedFile(URL)
        case encryptedFile(
            URL,
            encryptionKey: Data,
            plaintextLength: UInt32,
            digestSHA256Ciphertext: Data?
        )
    }

    private func validateContents(
        input: Input,
        encryptionKey: Data,
        mimeType: String,
        renderingFlag: AttachmentReference.RenderingFlag,
        sourceFilename: String?
    ) throws -> PendingAttachment {
        var mimeType = mimeType
        let contentTypeResult = try validateContentType(
            input: input,
            encryptionKey: encryptionKey,
            mimeType: &mimeType
        )
        return try prepareAttachmentFiles(
            input: input,
            encryptionKey: encryptionKey,
            mimeType: mimeType,
            renderingFlag: renderingFlag,
            sourceFilename: sourceFilename,
            contentResult: contentTypeResult
        )
    }

    private func prepareQuotedReplyThumbnail(
        fromOriginalAttachmentStream stream: AttachmentStream,
        renderingFlag: AttachmentReference.RenderingFlag,
        sourceFilename: String?
    ) throws -> PendingAttachment {
        let isVisualMedia = stream.contentType.isVisualMedia
        guard isVisualMedia else {
            throw OWSAssertionError("Non visual media target")
        }

        guard
            let imageData = stream
                .thumbnailImageSync(quality: .small)?
                .resized(maxDimensionPoints: AttachmentThumbnailQuality.thumbnailDimensionPointsForQuotedReply)?
                .jpegData(compressionQuality: 0.8)
        else {
            throw OWSAssertionError("Unable to create thumbnail")
        }

        let renderingFlagForThumbnail: AttachmentReference.RenderingFlag
        switch renderingFlag {
        case .borderless:
            // Preserve borderless flag from the original
            renderingFlagForThumbnail = .borderless
        case .default, .voiceMessage, .shouldLoop:
            // Other cases become default for the still image.
            renderingFlagForThumbnail = .default
        }

        return try self.validateContents(
            data: imageData,
            mimeType: MimeType.imageJpeg.rawValue,
            renderingFlag: renderingFlagForThumbnail,
            sourceFilename: sourceFilename
        )
    }

    // MARK: Content Type Validation

    private func rawContentType(mimeType: String) -> Attachment.ContentTypeRaw {
        if MimeTypeUtil.isSupportedVideoMimeType(mimeType) {
            return .video
        } else if MimeTypeUtil.isSupportedAudioMimeType(mimeType) {
            return .audio
        } else if MimeTypeUtil.isSupportedDefinitelyAnimatedMimeType(mimeType) {
            return .animatedImage
        } else if MimeTypeUtil.isSupportedImageMimeType(mimeType) {
            return .image
        } else if MimeTypeUtil.isSupportedMaybeAnimatedMimeType(mimeType) {
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
            reservedRelativeFilePath: String = AttachmentStream.newRelativeFilePath()
        ) {
            self.tmpFileUrl = tmpFileUrl
            self.isTmpFileEncrypted = isTmpFileEncrypted
            self.reservedRelativeFilePath = reservedRelativeFilePath
        }
    }

    private struct ContentTypeResult {
        let contentType: Attachment.ContentType
        let blurHash: String?
        let audioWaveformFile: PendingFile?
        let videoStillFrameFile: PendingFile?
    }

    private func validateContentType(
        input: Input,
        encryptionKey: Data,
        mimeType: inout String
    ) throws -> ContentTypeResult {
        let contentType: Attachment.ContentType
        let blurHash: String?
        let audioWaveformFile: PendingFile?
        let videoStillFrameFile: PendingFile?
        switch rawContentType(mimeType: mimeType) {
        case .invalid:
            contentType = .invalid
            blurHash = nil
            audioWaveformFile = nil
            videoStillFrameFile = nil
        case .file:
            contentType = .file
            blurHash = nil
            audioWaveformFile = nil
            videoStillFrameFile = nil
        case .image, .animatedImage:
            (contentType, blurHash) = try validateImageContentType(input, mimeType: &mimeType)
            audioWaveformFile = nil
            videoStillFrameFile = nil
        case .video:
            (contentType, videoStillFrameFile, blurHash) = try validateVideoContentType(
                input,
                mimeType: mimeType,
                encryptionKey: encryptionKey
            )
            audioWaveformFile = nil
        case .audio:
            (contentType, audioWaveformFile) = try validateAudioContentType(
                input,
                mimeType: mimeType,
                encryptionKey: encryptionKey
            )
            blurHash = nil
            videoStillFrameFile = nil
        }
        return ContentTypeResult(
            contentType: contentType,
            blurHash: blurHash,
            audioWaveformFile: audioWaveformFile,
            videoStillFrameFile: videoStillFrameFile
        )
    }

    // MARK: Image/Animated

    // Includes static and animated image validation.
    private func validateImageContentType(
        _ input: Input,
        mimeType: inout String
    ) throws -> (Attachment.ContentType, blurHash: String?) {
        let imageSource: OWSImageSource = try {
            switch input {
            case .inMemory(let data):
                return data
            case .unencryptedFile(let fileUrl):
                return try FileHandleImageSource(fileUrl: fileUrl)
            case let .encryptedFile(fileUrl, encryptionKey, plaintextLength, _):
                return try EncryptedFileHandleImageSource(
                    encryptedFileUrl: fileUrl,
                    encryptionKey: encryptionKey,
                    plaintextLength: plaintextLength
                )
            }
        }()

        let imageMetadataResult = imageSource.imageMetadata(
            mimeTypeForValidation: mimeType
        )

        let imageMetadata: ImageMetadata
        switch imageMetadataResult {
        case .genericSizeLimitExceeded:
            throw OWSAssertionError("Attachment size should have been validated before reching this point!")
        case .imageTypeSizeLimitExceeded:
            throw OWSAssertionError("Image size too large")
        case .invalid:
            return (.invalid, nil)
        case .valid(let metadata):
            imageMetadata = metadata
        case .mimeTypeMismatch(let metadata), .fileExtensionMismatch(let metadata):
            // Ignore these types of errors for now; we did so historically
            // and introducing a new failure mode should be done carefully
            // as it may cause us to blow up for attachments we previously "handled"
            // even if the contents didn't match the mime type.
            Logger.error("MIME type mismatch")
            mimeType = metadata.mimeType ?? mimeType
            imageMetadata = metadata
        }

        guard imageMetadata.isValid else {
            return (.invalid, nil)
        }

        let pixelSize = imageMetadata.pixelSize

        let blurHash: String? = {
            switch input {
            case .inMemory(let data):
                guard let image = UIImage(data: data) else {
                    return nil
                }
                return try? BlurHash.computeBlurHashSync(for: image)
            case .unencryptedFile(let fileUrl):
                guard let image = UIImage(contentsOfFile: fileUrl.path) else {
                    return nil
                }
                return try? BlurHash.computeBlurHashSync(for: image)
            case .encryptedFile(let fileUrl, let encryptionKey, let plaintextLength, _):
                guard
                    let image = try? UIImage.fromEncryptedFile(
                        at: fileUrl,
                        encryptionKey: encryptionKey,
                        plaintextLength: plaintextLength,
                        mimeType: mimeType
                    )
                else {
                    return nil
                }
                return try? BlurHash.computeBlurHashSync(for: image)
            }
        }()

        if imageMetadata.isAnimated {
            return (.animatedImage(pixelSize: pixelSize), blurHash)
        } else {
            return (.image(pixelSize: pixelSize), blurHash)
        }
    }

    // MARK: Video

    private func validateVideoContentType(
        _ input: Input,
        mimeType: String,
        encryptionKey: Data
    ) throws -> (Attachment.ContentType, stillFrame: PendingFile?, blurHash: String?) {
        let byteSize: Int = {
            switch input {
            case .inMemory(let data):
                return data.count
            case .unencryptedFile(let fileUrl):
                return OWSFileSystem.fileSize(of: fileUrl)?.intValue ?? 0
            case .encryptedFile(_, _, let plaintextLength, _):
                return Int(plaintextLength)
            }
        }()
        guard byteSize < SignalAttachment.kMaxFileSizeVideo else {
            throw OWSAssertionError("Video too big!")
        }

        let asset: AVAsset = try {
            switch input {
            case .inMemory(let data):
                // We have to write to disk to load an AVAsset.
                let tmpFile = OWSFileSystem.temporaryFileUrl(
                    fileExtension: MimeTypeUtil.fileExtensionForMimeType(mimeType),
                    isAvailableWhileDeviceLocked: true
                )
                try data.write(to: tmpFile)
                return AVAsset(url: tmpFile)
            case .unencryptedFile(let fileUrl):
                return AVAsset(url: fileUrl)
            case let .encryptedFile(fileUrl, encryptionKey, plaintextLength, _):
                return try AVAsset.fromEncryptedFile(
                    at: fileUrl,
                    encryptionKey: encryptionKey,
                    plaintextLength: plaintextLength,
                    mimeType: mimeType
                )
            }
        }()

        guard asset.isReadable, OWSMediaUtils.isValidVideo(asset: asset) else {
            return (.invalid, nil, nil)
        }

        let thumbnailImage = try? OWSMediaUtils.thumbnail(
            forVideo: asset,
            maxSizePixels: .square(AttachmentThumbnailQuality.large.thumbnailDimensionPoints())
        )
        guard let thumbnailImage else {
            return (.invalid, nil, nil)
        }
        owsAssertDebug(
            OWSMediaUtils.videoStillFrameMimeType == MimeType.imageJpeg,
            "Saving thumbnail as jpeg, which is not expected mime type"
        )
        let stillFrameFile: PendingFile? = try thumbnailImage
            // Don't compress; we already size-limited this thumbnail, it already has whatever
            // compression applied to the source video, and we want a high fidelity still frame.
            .jpegData(compressionQuality: 1)
            .map { thumbnailData in
                let thumbnailTmpFile = OWSFileSystem.temporaryFileUrl(isAvailableWhileDeviceLocked: true)
                let (encryptedThumbnail, _) = try Cryptography.encrypt(thumbnailData, encryptionKey: encryptionKey)
                try encryptedThumbnail.write(to: thumbnailTmpFile)
                return PendingFile(tmpFileUrl: thumbnailTmpFile, isTmpFileEncrypted: true)
            }

        let blurHash = try? BlurHash.computeBlurHashSync(for: thumbnailImage)

        let duration = asset.duration.seconds

        // We have historically used the size of the still frame as the video size.
        let pixelSize = thumbnailImage.pixelSize

        return (
            .video(
                duration: duration,
                pixelSize: pixelSize,
                stillFrameRelativeFilePath: stillFrameFile?.reservedRelativeFilePath
            ),
            stillFrameFile,
            blurHash
        )
    }

    // MARK: Audio

    private func validateAudioContentType(
        _ input: Input,
        mimeType: String,
        encryptionKey: Data
    ) throws -> (Attachment.ContentType, waveform: PendingFile?) {
        let duration: TimeInterval
        do {
            duration = try computeAudioDuration(input, mimeType: mimeType)
        } catch let error as NSError {
            if
                error.domain == NSOSStatusErrorDomain,
                (error.code == kAudioFileInvalidFileError || error.code == kAudioFileStreamError_InvalidFile)
            {
                // These say the audio file is invalid.
                // Eat them and return invalid instead of throwing
                return (.invalid, nil)
            } else if error is UnreadableAudioFileError {
                // Treat this as an invalid audio file
                return (.invalid, nil)
            } else {
                throw error
            }
        }

        // Don't require the waveform file.
        let waveformFile = try? self.createAudioWaveform(
            input,
            mimeType: mimeType,
            encryptionKey: encryptionKey
        )

        return (
            .audio(duration: duration, waveformRelativeFilePath: waveformFile?.reservedRelativeFilePath),
            waveformFile
        )
    }

    private struct UnreadableAudioFileError: Error {}

    // TODO someday: this loads an AVAsset (sometimes), and so does the audio waveform
    // computation. We can combine them so we don't waste effort.
    private func computeAudioDuration(_ input: Input, mimeType: String) throws -> TimeInterval {
        switch input {
        case .inMemory(let data):
            let player = try AVAudioPlayer(data: data)
            player.prepareToPlay()
            return player.duration
        case .unencryptedFile(let fileUrl):
            let player = try AVAudioPlayer(contentsOf: fileUrl)
            player.prepareToPlay()
            return player.duration
        case let .encryptedFile(fileUrl, encryptionKey, plaintextLength, _):
            // We can't load an AVAudioPlayer for encrypted files.
            // Use AVAsset instead.
            let asset = try AVAsset.fromEncryptedFile(
                at: fileUrl,
                encryptionKey: encryptionKey,
                plaintextLength: plaintextLength,
                mimeType: mimeType
            )
            guard asset.isReadable else {
                throw UnreadableAudioFileError()
            }
            return asset.duration.seconds
        }
    }

    private enum AudioWaveformFile {
        case unencrypted(URL)
        case encrypted(URL, encryptionKey: Data)
    }

    private func createAudioWaveform(
        _ input: Input,
        mimeType: String,
        encryptionKey: Data
    ) throws -> PendingFile {
        let waveform: AudioWaveform
        switch input {
        case .inMemory(let data):
            // We have to write the data to a temporary file.
            // AVAsset needs a file on disk to read from.
            let fileUrl = OWSFileSystem.temporaryFileUrl(
                fileExtension: MimeTypeUtil.fileExtensionForMimeType(mimeType),
                isAvailableWhileDeviceLocked: true
            )
            try data.write(to: fileUrl)
            waveform = try audioWaveformManager.audioWaveformSync(forAudioPath: fileUrl.path)

        case .unencryptedFile(let fileUrl):
            waveform = try audioWaveformManager.audioWaveformSync(forAudioPath: fileUrl.path)
        case let .encryptedFile(fileUrl, encryptionKey, plaintextLength, _):
            waveform = try audioWaveformManager.audioWaveformSync(
                forEncryptedAudioFileAtPath: fileUrl.path,
                encryptionKey: encryptionKey,
                plaintextDataLength: plaintextLength,
                mimeType: mimeType
            )
        }

        let outputWaveformFile = OWSFileSystem.temporaryFileUrl(isAvailableWhileDeviceLocked: true)

        let waveformData = try waveform.archive()
        let (encryptedWaveform, _) = try Cryptography.encrypt(waveformData, encryptionKey: encryptionKey)
        try encryptedWaveform.write(to: outputWaveformFile, options: .atomicWrite)

        return .init(
            tmpFileUrl: outputWaveformFile,
            isTmpFileEncrypted: true
        )
    }

    // MARK: - File Preparation

    private func prepareAttachmentFiles(
        input: Input,
        encryptionKey: Data,
        mimeType: String,
        renderingFlag: AttachmentReference.RenderingFlag,
        sourceFilename: String?,
        contentResult: ContentTypeResult
    ) throws -> PendingAttachmentImpl {
        let primaryFilePlaintextHash = try computePlaintextHash(input: input)

        // First encrypt the files that need encrypting.
        let (primaryPendingFile, primaryFileMetadata) = try encryptPrimaryFile(
            input: input,
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

        let orphanRecordId = try commitOrphanRecordWithSneakyTransaction(
            primaryPendingFile: primaryPendingFile,
            audioWaveformFile: contentResult.audioWaveformFile,
            videoStillFrameFile: contentResult.videoStillFrameFile,
            encryptionKey: encryptionKey
        )

        return PendingAttachmentImpl(
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
            orphanRecordId: orphanRecordId
        )
    }

    private func prepareAttachmentContentTypeFiles(
        input: Input,
        encryptionKey: Data,
        mimeType: String,
        contentResult: ContentTypeResult
    ) throws -> RevalidatedAttachmentImpl {
        let orphanRecordId = try commitOrphanRecordWithSneakyTransaction(
            primaryPendingFile: nil,
            audioWaveformFile: contentResult.audioWaveformFile,
            videoStillFrameFile: contentResult.videoStillFrameFile,
            encryptionKey: encryptionKey
        )

        return RevalidatedAttachmentImpl(
            validatedContentType: contentResult.contentType,
            mimeType: mimeType,
            blurHash: contentResult.blurHash,
            orphanRecordId: orphanRecordId
        )
    }

    private func commitOrphanRecordWithSneakyTransaction(
        primaryPendingFile: PendingFile?,
        audioWaveformFile: PendingFile?,
        videoStillFrameFile: PendingFile?,
        encryptionKey: Data
    ) throws -> OrphanedAttachmentRecord.IDType {
        let audioWaveformFile = try audioWaveformFile?.encryptFileIfNeeded(
            encryptionKey: encryptionKey
        )
        let videoStillFrameFile = try videoStillFrameFile?.encryptFileIfNeeded(
            encryptionKey: encryptionKey
        )

        // Before we copy files to their final location, orphan them.
        // This ensures if we exit for _any_ reason before we create their
        // associated Attachment row, the files will be cleaned up.
        // See OrphanedAttachmentCleaner for details.
        let orphanRecord = OrphanedAttachmentRecord(
            isPendingAttachment: true,
            localRelativeFilePath: primaryPendingFile?.reservedRelativeFilePath,
            // We don't pre-generate thumbnails for local attachments.
            localRelativeFilePathThumbnail: nil,
            localRelativeFilePathAudioWaveform: audioWaveformFile?.reservedRelativeFilePath,
            localRelativeFilePathVideoStillFrame: videoStillFrameFile?.reservedRelativeFilePath
        )
        let orphanRecordId = try orphanedAttachmentCleaner.commitPendingAttachmentWithSneakyTransaction(orphanRecord)

        // Now we can copy files.
        for pendingFile in [primaryPendingFile, audioWaveformFile, videoStillFrameFile].compacted() {
            let destinationUrl = AttachmentStream.absoluteAttachmentFileURL(
                relativeFilePath: pendingFile.reservedRelativeFilePath
            )
            guard OWSFileSystem.ensureDirectoryExists(destinationUrl.deletingLastPathComponent().path) else {
                throw OWSAssertionError("Unable to create directory")
            }
            try OWSFileSystem.moveFile(
                from: pendingFile.tmpFileUrl,
                to: destinationUrl
            )
        }

        return orphanRecordId
    }

    // MARK: - Encryption

    private func computePlaintextHash(input: Input) throws -> Data {
        switch input {
        case .inMemory(let data):
            return Data(SHA256.hash(data: data))
        case .unencryptedFile(let fileUrl):
            return try Cryptography.computeSHA256DigestOfFile(at: fileUrl)
        case .encryptedFile(let fileUrl, let encryptionKey, let plaintextLength, _):
            let fileHandle = try Cryptography.encryptedAttachmentFileHandle(
                at: fileUrl,
                plaintextLength: plaintextLength,
                encryptionKey: encryptionKey
            )
            var sha256 = SHA256()
            var bytesRemaining = plaintextLength
            while bytesRemaining > 0 {
                // Read in 1mb chunks.
                let data = try fileHandle.read(upToCount: 1024 * 1024)
                sha256.update(data: data)
                guard let bytesRead = UInt32(exactly: data.count) else {
                    throw OWSAssertionError("\(data.count) would not fit in UInt32")
                }
                bytesRemaining -= bytesRead
            }
            return Data(sha256.finalize())
        }
    }

    private func encryptPrimaryFile(
        input: Input,
        encryptionKey: Data
    ) throws -> (PendingFile, EncryptionMetadata) {
        switch input {
        case .inMemory(let data):
            let (encryptedData, encryptionMetadata) = try Cryptography.encrypt(
                data,
                encryptionKey: encryptionKey,
                applyExtraPadding: true
            )
            // We'll unwrap the digest again later, but unwrap and fail
            // early so we don't waste time writing bytes to disk.
            guard encryptionMetadata.digest != nil else {
                throw OWSAssertionError("No digest in output")
            }
            let outputFile = OWSFileSystem.temporaryFileUrl(isAvailableWhileDeviceLocked: true)
            try encryptedData.write(to: outputFile)
            return (
                PendingFile(
                    tmpFileUrl: outputFile,
                    isTmpFileEncrypted: true
                ),
                encryptionMetadata
            )
        case .unencryptedFile(let fileUrl):
            let outputFile = OWSFileSystem.temporaryFileUrl(isAvailableWhileDeviceLocked: true)
            let encryptionMetadata = try Cryptography.encryptAttachment(
                at: fileUrl,
                output: outputFile,
                encryptionKey: encryptionKey
            )
            return (
                PendingFile(
                    tmpFileUrl: outputFile,
                    isTmpFileEncrypted: true
                ),
                encryptionMetadata
            )
        case .encryptedFile(let fileUrl, let inputEncryptionKey, let plaintextLength, let digestParam):
            // If the input and output encryption keys are the same
            // the file is already encrypted, so nothing to encrypt.
            // Just compute the digest if we don't already have it.
            // If they don't match, re-encrypt the source to a new file
            // and pass back the updated encryption metadata
            if inputEncryptionKey == encryptionKey {

                let digest: Data
                if let digestParam {
                    digest = digestParam
                } else {
                    // Compute the digest over the entire encrypted file.
                    digest = try Cryptography.computeSHA256DigestOfFile(at: fileUrl)
                }
                return (
                    PendingFile(
                        tmpFileUrl: fileUrl,
                        isTmpFileEncrypted: true
                    ),
                    EncryptionMetadata(
                        key: encryptionKey,
                        digest: digest,
                        plaintextLength: Int(plaintextLength)
                    )
                )
            } else {
                let fileHandle = try Cryptography.encryptedFileHandle(at: fileUrl, encryptionKey: inputEncryptionKey)
                let outputFile = OWSFileSystem.temporaryFileUrl(isAvailableWhileDeviceLocked: true)
                let encryptionMetadata = try Cryptography.reencryptFileHandle(
                    at: fileHandle,
                    encryptionKey: encryptionKey,
                    encryptedOutputUrl: outputFile,
                    applyExtraPadding: false
                )
                return (
                    PendingFile(
                        tmpFileUrl: outputFile,
                        isTmpFileEncrypted: true
                    ),
                    encryptionMetadata
                )
            }
        }
    }
}

extension AttachmentContentValidatorImpl.PendingFile {

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
