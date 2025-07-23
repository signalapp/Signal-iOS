//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import AVFoundation
import CryptoKit
import Foundation

public class AttachmentContentValidatorImpl: AttachmentContentValidator {

    private let attachmentStore: AttachmentStore
    private let audioWaveformManager: AudioWaveformManager
    private let db: DB
    private let orphanedAttachmentCleaner: OrphanedAttachmentCleaner

    public init(
        attachmentStore: AttachmentStore,
        audioWaveformManager: AudioWaveformManager,
        db: DB,
        orphanedAttachmentCleaner: OrphanedAttachmentCleaner
    ) {
        self.attachmentStore = attachmentStore
        self.audioWaveformManager = audioWaveformManager
        self.db = db
        self.orphanedAttachmentCleaner = orphanedAttachmentCleaner
    }

    public func validateContents(
        dataSource: DataSource,
        shouldConsume: Bool,
        mimeType: String,
        renderingFlag: AttachmentReference.RenderingFlag,
        sourceFilename: String?
    ) throws -> PendingAttachment {
        let inputType: InputType = {
            if
                let fileDataSource = dataSource as? DataSourcePath,
                let fileUrl = fileDataSource.dataUrl
            {
                return .unencryptedFile(fileUrl)
            } else {
                return .inMemory(dataSource.data)
            }
        }()
        let primaryFilePlaintextHash = try computePlaintextHash(inputType: inputType)
        let encryptionKey = encryptionKeyToUse(primaryFilePlaintextHash: primaryFilePlaintextHash, inputEncryptionKey: nil)
        let pendingAttachment = try validateContents(
            inputs: ["": Input(
                type: inputType,
                primaryFilePlaintextHash: primaryFilePlaintextHash,
                encryptionKey: encryptionKey,
                mimeType: mimeType,
                renderingFlag: renderingFlag,
                sourceFilename: sourceFilename
            )]
        ).values.first!

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
        let inputType = InputType.inMemory(data)
        let primaryFilePlaintextHash = try computePlaintextHash(inputType: inputType)
        let encryptionKey = encryptionKeyToUse(primaryFilePlaintextHash: primaryFilePlaintextHash, inputEncryptionKey: nil)
        let pendingAttachment = try validateContents(
            inputs: ["": Input(
                type: inputType,
                primaryFilePlaintextHash: primaryFilePlaintextHash,
                encryptionKey: encryptionKey,
                mimeType: mimeType,
                renderingFlag: renderingFlag,
                sourceFilename: sourceFilename
            )]
        ).values.first!

        return pendingAttachment
    }

    public func validateDownloadedContents(
        ofEncryptedFileAt fileUrl: URL,
        encryptionKey inputEncryptionKey: Data,
        plaintextLength: UInt32?,
        integrityCheck: AttachmentIntegrityCheck,
        mimeType: String,
        renderingFlag: AttachmentReference.RenderingFlag,
        sourceFilename: String?
    ) throws -> PendingAttachment {
        // Very very first thing: validate the integrity check.
        // Throw if this fails.
        var decryptedLength = 0
        try Cryptography.decryptFile(
            at: fileUrl,
            metadata: .init(
                key: inputEncryptionKey,
                integrityCheck: integrityCheck,
                plaintextLength: plaintextLength.map(Int.init)
            ),
            output: { data in
                decryptedLength += data.count
            }
        )
        let plaintextLength = plaintextLength ?? UInt32(decryptedLength)

        let inputType = InputType.encryptedFile(
            fileUrl,
            inputEncryptionKey: inputEncryptionKey,
            plaintextLength: plaintextLength,
            integrityCheck: integrityCheck
        )
        let primaryFilePlaintextHash = try computePlaintextHash(inputType: inputType)
        return try validateContents(
            inputs: ["": Input(
                type: inputType,
                primaryFilePlaintextHash: primaryFilePlaintextHash,
                encryptionKey: encryptionKeyToUse(primaryFilePlaintextHash: primaryFilePlaintextHash, inputEncryptionKey: inputEncryptionKey),
                mimeType: mimeType,
                renderingFlag: renderingFlag,
                sourceFilename: sourceFilename
            )]
        ).values.first!
    }

    public func reValidateContents(
        ofEncryptedFileAt fileUrl: URL,
        encryptionKey: Data,
        plaintextLength: UInt32,
        mimeType: String
    ) throws -> RevalidatedAttachment {
        let inputType = InputType.encryptedFile(
            fileUrl,
            inputEncryptionKey: encryptionKey,
            plaintextLength: plaintextLength,
            // No need to validate integrity check
            integrityCheck: nil
        )
        let primaryFilePlaintextHash = try computePlaintextHash(inputType: inputType)
        let contentTypeResult = try validateContentType(
            input: Input(
                type: inputType,
                primaryFilePlaintextHash: primaryFilePlaintextHash,
                encryptionKey: encryptionKey,
                mimeType: mimeType,
                // Unused and irrelevant
                renderingFlag: .default,
                // Unused and irrelevant
                sourceFilename: nil
            )
        )
        return try prepareAttachmentContentTypeFiles(
            contentResults: ["": contentTypeResult]
        ).values.first!
    }

    public func validateContents(
        ofBackupMediaFileAt fileUrl: URL,
        outerDecryptionData: DecryptionMetadata,
        innerDecryptionData: DecryptionMetadata,
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
            metadata: outerDecryptionData,
            output: tmpFileUrl
        )

        func makeInputType(plaintextLength: Int) -> InputType {
            return InputType.encryptedFile(
                tmpFileUrl,
                inputEncryptionKey: innerDecryptionData.key,
                plaintextLength: UInt32(plaintextLength),
                integrityCheck: innerDecryptionData.integrityCheck
            )
        }

        // Get plaintext length if not given, and validate integrity check if given.
        let inputType: InputType
        let primaryFilePlaintextHash: Data
        if let innerPlainTextLength = innerDecryptionData.plaintextLength, innerDecryptionData.integrityCheck == nil {
            inputType = makeInputType(plaintextLength: innerPlainTextLength)
            primaryFilePlaintextHash = try computePlaintextHash(inputType: inputType)
        } else {
            var decryptedLength = 0
            var sha256 = SHA256()
            try Cryptography.decryptFile(
                at: tmpFileUrl,
                metadata: innerDecryptionData,
                output: { data in
                    decryptedLength += data.count
                    sha256.update(data: data)
                }
            )
            inputType =  makeInputType(plaintextLength: decryptedLength)
            primaryFilePlaintextHash = Data(sha256.finalize())
        }
        return try validateContents(
            inputs: ["": Input(
                type: inputType,
                primaryFilePlaintextHash: primaryFilePlaintextHash,
                encryptionKey: encryptionKeyToUse(primaryFilePlaintextHash: primaryFilePlaintextHash, inputEncryptionKey: finalEncryptionKey),
                mimeType: mimeType,
                renderingFlag: renderingFlag,
                sourceFilename: sourceFilename
            )]
        ).values.first!
    }

    public func prepareOversizeTextsIfNeeded<Key: Hashable>(
        from texts: [Key: MessageBody]
    ) throws -> [Key: ValidatedMessageBody] {
        var truncatedBodies = [Key: MessageBody]()
        var oversizedTextInputs = [Key: Input]()
        var results = [Key: ValidatedMessageBody]()
        for (key, messageBody) in texts {
            guard !messageBody.text.isEmpty else {
                // Skip this one and don't put it in results
                continue
            }
            let truncatedText = messageBody.text.trimmedIfNeeded(maxByteCount: Int(kOversizeTextMessageSizeThreshold))
            guard let truncatedText else {
                // No need to truncate
                results[key] = .inline(messageBody)
                continue
            }
            let truncatedBody = MessageBody(text: truncatedText, ranges: messageBody.ranges)
            truncatedBodies[key] = truncatedBody
            let inputType = InputType.inMemory(Data(messageBody.text.utf8))
            let primaryFilePlaintextHash = try computePlaintextHash(inputType: inputType)
            let encryptionKey = encryptionKeyToUse(primaryFilePlaintextHash: primaryFilePlaintextHash, inputEncryptionKey: nil)
            oversizedTextInputs[key] = Input(
                type: inputType,
                primaryFilePlaintextHash: primaryFilePlaintextHash,
                encryptionKey: encryptionKey,
                mimeType: MimeType.textXSignalPlain.rawValue,
                renderingFlag: .default,
                sourceFilename: nil
            )
        }

        let pendingAttachments = try self.validateContents(
            inputs: oversizedTextInputs
        )

        for (key, pendingAttachment) in pendingAttachments {
            guard let truncatedBody = truncatedBodies[key] else {
                throw OWSAssertionError("Missing truncated body!")
            }
            results[key] = .oversize(truncated: truncatedBody, fullsize: pendingAttachment)
        }

        return results
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

    private enum InputType {
        case inMemory(Data)
        case unencryptedFile(URL)
        case encryptedFile(
            URL,
            inputEncryptionKey: Data,
            plaintextLength: UInt32,
            integrityCheck: AttachmentIntegrityCheck?
        )
    }

    private class Input {
        let type: InputType
        let primaryFilePlaintextHash: Data
        let encryptionKey: Data
        /// Gets overriden in some cases when we validate content type.
        var mimeType: String
        let renderingFlag: AttachmentReference.RenderingFlag
        let sourceFilename: String?

        init(
            type: InputType,
            primaryFilePlaintextHash: Data,
            encryptionKey: Data,
            mimeType: String,
            renderingFlag: AttachmentReference.RenderingFlag,
            sourceFilename: String?
        ) {
            self.type = type
            self.primaryFilePlaintextHash = primaryFilePlaintextHash
            self.encryptionKey = encryptionKey
            self.mimeType = mimeType
            self.renderingFlag = renderingFlag
            self.sourceFilename = sourceFilename
        }
    }

    private func validateContents<Key: Hashable>(
        inputs: [Key: Input],
    ) throws -> [Key: PendingAttachment] {
        let contentTypeResults: [Key: ContentTypeResult] = try inputs.mapValues { input in
            return try validateContentType(
                input: input
            )
        }
        return try prepareAttachmentFiles(
            contentResults: contentTypeResults
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
        let input: Input
        let contentType: Attachment.ContentType
        let blurHash: String?
        let audioWaveformFile: PendingFile?
        let videoStillFrameFile: PendingFile?
    }

    private func validateContentType(
        input: Input
    ) throws -> ContentTypeResult {
        let contentType: Attachment.ContentType
        let blurHash: String?
        let audioWaveformFile: PendingFile?
        let videoStillFrameFile: PendingFile?
        switch rawContentType(mimeType: input.mimeType) {
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
            var mimeType = input.mimeType
            (contentType, blurHash) = try validateImageContentType(input, mimeType: &mimeType)
            input.mimeType = mimeType
            audioWaveformFile = nil
            videoStillFrameFile = nil
        case .video:
            (contentType, videoStillFrameFile, blurHash) = try validateVideoContentType(
                input
            )
            audioWaveformFile = nil
        case .audio:
            (contentType, audioWaveformFile) = try validateAudioContentType(
                input
            )
            blurHash = nil
            videoStillFrameFile = nil
        }
        return ContentTypeResult(
            input: input,
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
            switch input.type {
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
            switch input.type {
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
        _ input: Input
    ) throws -> (Attachment.ContentType, stillFrame: PendingFile?, blurHash: String?) {
        let byteSize: Int = {
            switch input.type {
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
            switch input.type {
            case .inMemory(let data):
                // We have to write to disk to load an AVAsset.
                let tmpFile = OWSFileSystem.temporaryFileUrl(
                    fileExtension: MimeTypeUtil.fileExtensionForMimeType(input.mimeType),
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
                    mimeType: input.mimeType
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
                let (encryptedThumbnail, _) = try Cryptography.encrypt(thumbnailData, encryptionKey: input.encryptionKey)
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
    ) throws -> (Attachment.ContentType, waveform: PendingFile?) {
        let duration: TimeInterval
        do {
            duration = try computeAudioDuration(input, mimeType: input.mimeType)
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
            mimeType: input.mimeType,
            encryptionKey: input.encryptionKey
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
        switch input.type {
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
        switch input.type {
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

    private struct PreparedContentResult {
        let contentResult: ContentTypeResult

        struct PrimaryFile {
            let pendingFile: PendingFile
            let digest: Data
            let plaintextLength: UInt32
            let encryptedLength: UInt32
        }

        let primaryFile: PrimaryFile?

        var input: Input { contentResult.input }
        var audioWaveformFile: PendingFile? { contentResult.audioWaveformFile }
        var videoStillFrameFile: PendingFile? { contentResult.videoStillFrameFile }
    }

    private func prepareAttachmentFiles<Key: Hashable>(
        contentResults: [Key: ContentTypeResult],
    ) throws -> [Key: PendingAttachmentImpl] {
        // First encrypt the files that need encrypting.
        let preparedContentResults = try contentResults.mapValues { contentResult in
            let (primaryPendingFile, primaryFileMetadata) = try encryptPrimaryFile(
                input: contentResult.input
            )
            let primaryFileDigest = primaryFileMetadata.digest
            guard
                let primaryPlaintextLength = UInt32.init(exactly: primaryFileMetadata.plaintextLength)
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
            return PreparedContentResult(
                contentResult: contentResult,
                primaryFile: PreparedContentResult.PrimaryFile(
                    pendingFile: primaryPendingFile,
                    digest: primaryFileDigest,
                    plaintextLength: primaryPlaintextLength,
                    encryptedLength: primaryEncryptedLength
                )
            )
        }

        let orphanRecordIds = try commitOrphanRecordsWithSneakyTransaction(
            contentResults: preparedContentResults
        )

        var pendingAttachments = [Key: PendingAttachmentImpl]()
        for (key, contentResult) in preparedContentResults {
            guard let primaryFile = contentResult.primaryFile else {
                throw OWSAssertionError("Missing primary file!")
            }
            guard let orphanRecordId = orphanRecordIds[key] else {
                throw OWSAssertionError("Missing orphan record!")
            }
            let input = contentResult.contentResult.input
            pendingAttachments[key] = PendingAttachmentImpl(
                blurHash: contentResult.contentResult.blurHash,
                sha256ContentHash: input.primaryFilePlaintextHash,
                encryptedByteCount: primaryFile.encryptedLength,
                unencryptedByteCount: primaryFile.plaintextLength,
                mimeType: input.mimeType,
                encryptionKey: input.encryptionKey,
                digestSHA256Ciphertext: primaryFile.digest,
                localRelativeFilePath: primaryFile.pendingFile.reservedRelativeFilePath,
                renderingFlag: input.renderingFlag,
                sourceFilename: input.sourceFilename,
                validatedContentType: contentResult.contentResult.contentType,
                orphanRecordId: orphanRecordId
            )
        }
        return pendingAttachments
    }

    private func prepareAttachmentContentTypeFiles<Key: Hashable>(
        contentResults: [Key: ContentTypeResult]
    ) throws -> [Key: RevalidatedAttachmentImpl] {
        let orphanRecordIds = try commitOrphanRecordsWithSneakyTransaction(
            contentResults: contentResults.mapValues {
                return PreparedContentResult(
                    contentResult: $0,
                    primaryFile: nil,
                )
            }
        )

        var results = [Key: RevalidatedAttachmentImpl]()
        for (key, contentResult) in contentResults {
            guard let orphanRecordId = orphanRecordIds[key] else {
                throw OWSAssertionError("Missing orphan record!")
            }
            results[key] = RevalidatedAttachmentImpl(
                validatedContentType: contentResult.contentType,
                mimeType: contentResult.input.mimeType,
                blurHash: contentResult.blurHash,
                orphanRecordId: orphanRecordId
            )
        }
        return results
    }

    private func commitOrphanRecordsWithSneakyTransaction<Key: Hashable>(
        contentResults: [Key: PreparedContentResult]
    ) throws -> [Key: OrphanedAttachmentRecord.IDType] {
        var orphanRecords = [Key: OrphanedAttachmentRecord]()
        var filesForCopying = [PendingFile]()
        for (key, contentResult) in contentResults {
            let audioWaveformFile = try contentResult.audioWaveformFile?.encryptFileIfNeeded(
                encryptionKey: contentResult.input.encryptionKey
            )
            let videoStillFrameFile = try contentResult.videoStillFrameFile?.encryptFileIfNeeded(
                encryptionKey: contentResult.input.encryptionKey
            )

            // Before we copy files to their final location, orphan them.
            // This ensures if we exit for _any_ reason before we create their
            // associated Attachment row, the files will be cleaned up.
            // See OrphanedAttachmentCleaner for details.
            let orphanRecord = OrphanedAttachmentRecord(
                isPendingAttachment: true,
                localRelativeFilePath: contentResult.primaryFile?.pendingFile.reservedRelativeFilePath,
                // We don't pre-generate thumbnails for local attachments.
                localRelativeFilePathThumbnail: nil,
                localRelativeFilePathAudioWaveform: audioWaveformFile?.reservedRelativeFilePath,
                localRelativeFilePathVideoStillFrame: videoStillFrameFile?.reservedRelativeFilePath
            )
            orphanRecords[key] = orphanRecord
            if let primaryPendingFile = contentResult.primaryFile?.pendingFile {
                filesForCopying.append(primaryPendingFile)
            }
            if let audioWaveformFile {
                filesForCopying.append(audioWaveformFile)
            }
            if let videoStillFrameFile {
                filesForCopying.append(videoStillFrameFile)
            }
        }
        let orphanRecordIds = try orphanedAttachmentCleaner.commitPendingAttachmentsWithSneakyTransaction(orphanRecords)

        // Now we can copy files.
        for pendingFile in filesForCopying {
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

        return orphanRecordIds
    }

    // MARK: - Encryption

    private func computePlaintextHash(inputType: InputType) throws -> Data {
        let plaintextHash: Data = try {
            switch inputType {
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
        }()
        return plaintextHash
    }

    private func encryptPrimaryFile(
        input: Input
    ) throws -> (PendingFile, EncryptionMetadata) {
        switch input.type {
        case .inMemory(let data):
            let (encryptedData, encryptionMetadata) = try Cryptography.encrypt(
                data,
                encryptionKey: input.encryptionKey,
                applyExtraPadding: true
            )
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
                encryptionKey: input.encryptionKey
            )
            return (
                PendingFile(
                    tmpFileUrl: outputFile,
                    isTmpFileEncrypted: true
                ),
                encryptionMetadata
            )
        case .encryptedFile(let fileUrl, let inputEncryptionKey, let plaintextLength, let integrityCheckParam):
            // If the input and output encryption keys are the same
            // the file is already encrypted, so nothing to encrypt.
            // Just compute the digest if we don't already have it.
            // If they don't match, re-encrypt the source to a new file
            // and pass back the updated encryption metadata
            if inputEncryptionKey == input.encryptionKey {

                guard let encryptedLength = OWSFileSystem.fileSize(of: fileUrl)?.intValue else {
                    throw OWSAssertionError("Unable to get file length")
                }

                let digest: Data
                switch integrityCheckParam {
                case .digestSHA256Ciphertext(let digestParam):
                    // We separately verify the digest from the integrity check, so use it here.
                    digest = digestParam
                case nil, .sha256ContentHash:
                    // Compute the digest over the entire encrypted file.
                    digest = try Cryptography.computeSHA256DigestOfFile(at: fileUrl)
                }
                return (
                    PendingFile(
                        tmpFileUrl: fileUrl,
                        isTmpFileEncrypted: true
                    ),
                    EncryptionMetadata(
                        key: input.encryptionKey,
                        digest: digest,
                        length: encryptedLength,
                        plaintextLength: Int(plaintextLength)
                    )
                )
            } else {
                let fileHandle = try Cryptography.encryptedFileHandle(at: fileUrl, encryptionKey: inputEncryptionKey)
                let outputFile = OWSFileSystem.temporaryFileUrl(isAvailableWhileDeviceLocked: true)
                let encryptionMetadata = try Cryptography.reencryptFileHandle(
                    at: fileHandle,
                    encryptionKey: input.encryptionKey,
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

    // MARK: Handling duplicates

    /// When processing some input file, we may have an existing attachment at the same
    /// plaintext hash. If we do, as an optimization, we should reuse that attachment's encryption
    /// key for our new file. This way, when we merge the new file and the old attachment, we
    /// can keep everything from both. If the encryption keys didn't match in the merging process,
    /// we would have to discard e.g. media tier information that is downstream of the key.
    ///
    /// Note: the merge happens later in a separate write tx, so things can change between now and
    /// then. That's ok; worst case when we merge two different encryption keys we drop media tier
    /// uploads and have to reupload again, and everything recovers.
    private func encryptionKeyToUse(primaryFilePlaintextHash: Data, inputEncryptionKey: Data?) -> Data {
        let existingAttachment = db.read(block: { tx in
            attachmentStore.fetchAttachment(sha256ContentHash: primaryFilePlaintextHash, tx: tx)
        })
        if let existingAttachment {
            return existingAttachment.encryptionKey
        } else {
            return inputEncryptionKey ?? Cryptography.randomAttachmentEncryptionKey()
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
