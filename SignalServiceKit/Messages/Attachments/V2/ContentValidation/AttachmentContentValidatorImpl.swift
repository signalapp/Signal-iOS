//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import AVFoundation
import Foundation

public class AttachmentContentValidatorImpl: AttachmentContentValidator {

    private let audioWaveformManager: AudioWaveformManager

    public init(
        audioWaveformManager: AudioWaveformManager
    ) {
        self.audioWaveformManager = audioWaveformManager
    }

    public func validateContents(
        dataSource: DataSource,
        mimeType: String,
        sourceFilename: String?
    ) async throws -> PendingAttachment {
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
        return try await validateContents(
            input: input,
            mimeType: mimeType,
            sourceFilename: sourceFilename
        )
    }

    public func validateContents(
        ofEncryptedFileAt fileUrl: URL,
        encryptionKey: Data,
        plaintextLength: UInt32,
        digestSHA256Ciphertext: Data,
        mimeType: String,
        sourceFilename: String?
    ) async throws -> PendingAttachment {
        let input = Input.encryptedFile(
            fileUrl,
            encryptionKey: encryptionKey,
            plaintextLength: plaintextLength
        )
        return try await validateContents(
            input: input,
            mimeType: mimeType,
            sourceFilename: sourceFilename
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
        let sourceFilename: String?
        let validatedContentType: Attachment.ContentType
    }

    private enum Input {
        case inMemory(Data)
        case unencryptedFile(URL)
        case encryptedFile(URL, encryptionKey: Data, plaintextLength: UInt32)
    }

    private func validateContents(
        input: Input,
        mimeType: String,
        sourceFilename: String?
    ) async throws -> PendingAttachment {
        _ = try await validateContentType(input: input, mimeType: mimeType)
        fatalError("Unimplemented")
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

    private func validateContentType(
        input: Input,
        mimeType: String
    ) async throws -> Attachment.ContentType {
        switch rawContentType(mimeType: mimeType) {
        case .invalid:
            return .invalid
        case .file:
            return .file
        case .image, .animatedImage:
            return try await validateImageContentType(input, mimeType: mimeType)
        case .video:
            return try await validateVideoContentType(input, mimeType: mimeType)
        case .audio:
            return try await validateAudioContentType(input, mimeType: mimeType)
        }
    }

    // MARK: Image/Animated

    // Includes static and animated image validation.
    private func validateImageContentType(_ input: Input, mimeType: String) async throws -> Attachment.ContentType {
        let imageSource: OWSImageSource = try {
            switch input {
            case .inMemory(let data):
                return data
            case .unencryptedFile(let fileUrl):
                return try FileHandleImageSource(fileUrl: fileUrl)
            case let .encryptedFile(fileUrl, encryptionKey, plaintextLength):
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
            return .invalid
        case .valid(let metadata):
            imageMetadata = metadata
        case .mimeTypeMismatch(let metadata), .fileExtensionMismatch(let metadata):
            // Ignore these types of errors for now; we did so historically
            // and introducing a new failure mode should be done carefully
            // as it may cause us to blow up for attachments we previously "handled"
            // even if the contents didn't match the mime type.
            owsFailDebug("MIME type mismatch")
            imageMetadata = metadata
        }

        guard imageMetadata.isValid else {
            return .invalid
        }

        let pixelSize = imageMetadata.pixelSize
        if imageMetadata.isAnimated {
            return .animatedImage(pixelSize: pixelSize)
        } else {
            return .image(pixelSize: pixelSize)
        }
    }

    // MARK: Video

    private func validateVideoContentType(_ input: Input, mimeType: String) async throws -> Attachment.ContentType {
        fatalError("Unimplemented")
    }

    // MARK: Audio

    private func validateAudioContentType(_ input: Input, mimeType: String) async throws -> Attachment.ContentType {
        let duration: TimeInterval
        do {
            duration = try await computeAudioDuration(input, mimeType: mimeType)
        } catch let error as NSError {
            if
                error.domain == NSOSStatusErrorDomain,
                (error.code == kAudioFileInvalidFileError || error.code == kAudioFileStreamError_InvalidFile)
            {
                // These say the audio file is invalid.
                // Eat them and return invalid instead of throwing
                return .invalid
            } else {
                throw error
            }
        }

        let waveformRelativeFilePath: String?
        do {
            _ = try await self.createAudioWaveform(input, mimeType: mimeType)
            // TODO: deal with file copying to the final location
            waveformRelativeFilePath = nil
        } catch {
            waveformRelativeFilePath = nil
        }

        return .audio(duration: duration, waveformRelativeFilePath: waveformRelativeFilePath)
    }

    // TODO someday: this loads an AVAsset (sometimes), and so does the audio waveform
    // computation. We can combine them so we don't waste effort.
    private func computeAudioDuration(_ input: Input, mimeType: String) async throws -> TimeInterval {
        switch input {
        case .inMemory(let data):
            let player = try AVAudioPlayer(data: data)
            player.prepareToPlay()
            return player.duration
        case .unencryptedFile(let fileUrl):
            let player = try AVAudioPlayer(contentsOf: fileUrl)
            player.prepareToPlay()
            return player.duration
        case let .encryptedFile(fileUrl, encryptionKey, plaintextLength):
            // We can't load an AVAudioPlayer for encrypted files.
            // Use AVAsset instead.
            let asset = try AVAsset.fromEncryptedFile(
                at: fileUrl,
                encryptionKey: encryptionKey,
                plaintextLength: plaintextLength,
                mimeType: mimeType
            )
            return asset.duration.seconds
        }
    }

    private enum AudioWaveformFile {
        case unencrypted(URL)
        case encrypted(URL, encryptionKey: Data)
    }

    private func createAudioWaveform(_ input: Input, mimeType: String) async throws -> AudioWaveformFile {
        let outputWaveformFile = OWSFileSystem.temporaryFileUrl()
        switch input {
        case .inMemory(let data):
            // We have to write the data to a temporary file.
            // AVAsset needs a file on disk to read from.
            let fileUrl = OWSFileSystem.temporaryFileUrl(fileExtension: MimeTypeUtil.fileExtensionForMimeType(mimeType))
            try data.write(to: fileUrl)
            let waveformTask = audioWaveformManager.audioWaveform(forAudioPath: fileUrl.path, waveformPath: outputWaveformFile.path)
            // We don't actually need the waveform now, it will be written to the output file.
            _ = try await waveformTask.value
            return .unencrypted(outputWaveformFile)
        case .unencryptedFile(let fileUrl):
            let waveformTask = audioWaveformManager.audioWaveform(forAudioPath: fileUrl.path, waveformPath: outputWaveformFile.path)
            // We don't actually need the waveform now, it will be written to the output file.
            _ = try await waveformTask.value
            return .unencrypted(outputWaveformFile)
        case let .encryptedFile(fileUrl, encryptionKey, plaintextLength):
            try await audioWaveformManager.audioWaveform(
                forEncryptedAudioFileAtPath: fileUrl.path,
                encryptionKey: encryptionKey,
                plaintextDataLength: plaintextLength,
                mimeType: mimeType,
                outputWaveformPath: outputWaveformFile.path
            )
            return .encrypted(outputWaveformFile, encryptionKey: encryptionKey)
        }
    }
}
