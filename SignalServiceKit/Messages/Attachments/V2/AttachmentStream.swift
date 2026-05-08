//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

public import AVFoundation
import Foundation
public import SDWebImage

/// Represents a downloaded attachment with the fullsize contents available on local disk.
public class AttachmentStream {

    public let attachment: Attachment
    public let info: Attachment.StreamInfo

    public var id: Attachment.IDType { attachment.id }
    public var mimeType: String { attachment.mimeType }
    public var contentType: Attachment.ContentType { attachment.contentType }

    public var ciphertextDigest: Data { info.ciphertextDigest }
    public var plaintextHash: Data { info.plaintextHash }
    public var mediaName: String { info.mediaName }
    public var encryptedByteCount: UInt32 { info.encryptedByteCount }
    public var unencryptedByteCount: UInt32 { info.unencryptedByteCount }
    public var cachedMediaSizePixels: CGSize? { info.cachedMediaSizePixels }
    public var cachedVideoDuration: TimeInterval? { info.cachedVideoDuration }
    public var cachedVideoStillFrameRelativeFilePath: String? { info.cachedVideoStillFrameRelativeFilePath }
    public var cachedAudioDuration: TimeInterval? { info.cachedAudioDuration }
    public var cachedAudioWaveformRelativeFilePath: String? { info.cachedAudioWaveformRelativeFilePath }
    public var localRelativeFilePath: String { info.localRelativeFilePath }

    // MARK: - Init

    public init(
        attachment: Attachment,
        info: Attachment.StreamInfo,
    ) {
        self.attachment = attachment
        self.info = info
    }

    public convenience init?(attachment: Attachment) {
        guard
            let info = attachment.streamInfo
        else {
            return nil
        }
        self.init(
            attachment: attachment,
            info: info,
        )
    }

    // MARK: -

    /// Generate a new (random) relative file path for an attachment file.
    /// Can be used for the primary file, thumbnail, audio waveform, etc.
    public static func newRelativeFilePath() -> String {
        let id = UUID().uuidString
        // Make a subdirectory with the first two characters.
        // This is meaningless except to avoid slowing down the filesystem
        // with every attachment file at the top level.
        return "\(id.prefix(2))/\(id)"
    }

    public static func attachmentsDirectory() -> URL {
        return OWSFileSystem.appSharedDataDirectoryURL().appendingPathComponent("attachment_files")
    }

    /// Given a relative "attachment file" path, returns the absolute path.
    /// "Attachment files" include fullsize files (localRelativeFilePath), thumbnails, audio waveforms, video still frames.
    /// All files related to attachments are in the same root directory, with subdirectories only based off the first few characters of their filename.
    public static func absoluteAttachmentFileURL(relativeFilePath: String) -> URL {
        return attachmentsDirectory().appendingPathComponent(relativeFilePath)
    }

    /// WARNING: deletes all files in the attachments directory _without_ deleting their owning Attachments.
    /// Should ONLY be used after deleting all attachments, to quickly delete all files without waiting for
    /// OrphanedAttachmentCleaner to get around to them (but the cleaner should handle the files already being gone).
    public static func deleteAllAttachmentFiles() {
        OWSFileSystem.deleteContents(ofDirectory: attachmentsDirectory().path)
    }

    // MARK: -

    public var fileURL: URL {
        return Self.absoluteAttachmentFileURL(relativeFilePath: self.localRelativeFilePath)
    }

    /// - parameter filename: if provided, the output file url will use this name, minus any file extension (which
    /// will instead be inferred from the file contents) and made url-safe AND user-friendly. If nil, a random file name is used.
    public func makeDecryptedCopy(filename: String?) throws -> URL {
        var pathExtension: String = {
            if let pathExtension = MimeTypeUtil.fileExtensionForMimeType(mimeType) {
                return pathExtension
            } else if
                let filename,
                let filenameUrl = URL(string: filename),
                let pathExtension = filenameUrl.pathExtension.nilIfEmpty
            {
                return pathExtension
            } else {
                return "bin"
            }
        }()
        // Special-case the "aac" filetype we use for voice messages (for legacy reasons)
        // to use a .m4a file extension, not .aac, since AVAudioPlayer can't handle .aac
        // properly. Doesn't affect file contents.
        if pathExtension == "aac" {
            pathExtension = "m4a"
        }

        let tmpURL: URL
        if let filename {
            var normalizedFilename = (filename as NSString)
                .deletingPathExtension
                .trimmingCharacters(in: .whitespaces)

            // Ensure that the filename is a valid filesystem name, replacing invalid characters with an underscore.
            let invalidCharacterSets: [CharacterSet] = [.whitespacesAndNewlines, .illegalCharacters, .controlCharacters, .init(charactersIn: "<>|\\:()&;?*/~")]
            for invalidCharacterSet in invalidCharacterSets {
                normalizedFilename = normalizedFilename.components(separatedBy: invalidCharacterSet).joined(separator: "_")
            }

            // Remove leading periods to prevent hidden files, "." and ".." special file names.
            let dotPrefixLength = normalizedFilename.prefix { $0 == "." }.count
            normalizedFilename.removeFirst(dotPrefixLength)

            tmpURL = OWSFileSystem.temporaryFileUrl(
                fileName: normalizedFilename,
                fileExtension: pathExtension,
                isAvailableWhileDeviceLocked: false,
            )
            try OWSFileSystem.deleteFileIfExists(url: tmpURL)
        } else {
            tmpURL = OWSFileSystem.temporaryFileUrl(
                fileExtension: pathExtension,
                isAvailableWhileDeviceLocked: false,
            )
        }
        // hmac and digest are validated at download time; no need to revalidate every read.
        try Cryptography.decryptFileWithoutValidating(
            at: fileURL,
            metadata: DecryptionMetadata(
                key: AttachmentKey(combinedKey: attachment.encryptionKey),
                plaintextLength: UInt64(safeCast: info.unencryptedByteCount),
            ),
            output: tmpURL,
        )
        return tmpURL
    }

    public func decryptedRawData() throws -> Data {
        // hmac and digest are validated at download time; no need to revalidate every read.
        return try Cryptography.decryptFileWithoutValidating(
            at: fileURL,
            metadata: DecryptionMetadata(
                key: AttachmentKey(combinedKey: attachment.encryptionKey),
                plaintextLength: UInt64(safeCast: info.unencryptedByteCount),
            ),
        )
    }

    public func decryptedLongText() throws -> String {
        let data = try decryptedRawData()
        guard let text = String(data: data, encoding: .utf8) else {
            throw OWSAssertionError("Can't parse oversize text data.")
        }
        return text
    }

    public func imageMetadata() -> ImageMetadata? {
        switch contentType {
        case .file, .video, .audio:
            return nil
        case .image:
            break
        }

        do {
            let attachmentKey = try AttachmentKey(combinedKey: attachment.encryptionKey)
            let imageSource = try EncryptedFileHandleImageSource(
                encryptedFileUrl: fileURL,
                attachmentKey: attachmentKey,
                plaintextLength: UInt64(safeCast: unencryptedByteCount),
            )

            return imageSource.imageMetadata()
        } catch {
            return nil
        }
    }

    public func decryptedImage() throws -> UIImage {
        switch contentType {
        case .file, .audio:
            throw OWSAssertionError("Requesting image from non-visual attachment")
        case .image:
            return try UIImage.from(self)
        case .video:
            guard let stillImageRelativeFilePath = info.cachedVideoStillFrameRelativeFilePath else {
                throw OWSAssertionError("Still image unavailable for video")
            }
            return try UIImage.fromEncryptedFile(
                at: Self.absoluteAttachmentFileURL(relativeFilePath: stillImageRelativeFilePath),
                attachmentKey: AttachmentKey(combinedKey: attachment.encryptionKey),
                plaintextLength: nil,
                mimeType: OWSMediaUtils.videoStillFrameMimeType.rawValue,
            )
        }
    }

    public func decryptedSDAnimatedImage() throws -> SDAnimatedImage {
        switch contentType {
        case .file, .audio, .video:
            throw OWSAssertionError("Requesting image from non-visual attachment")
        case .image:
            return try SDAnimatedImage.sdImage(from: self)
        }
    }

    public func decryptedAVAsset() throws -> AVAsset {
        switch contentType {
        case .file, .image:
            throw OWSAssertionError("Requesting AVAsset from incompatible attachment")
        case .video, .audio:
            return try AVAsset.from(self)
        }
    }

    // MARK: - Thumbnails

    public func thumbnailImage(quality: AttachmentThumbnailQuality) async -> UIImage? {
        return await DependenciesBridge.shared.attachmentThumbnailService
            .thumbnailImage(for: self, quality: quality)
    }

    public func thumbnailImageSync(quality: AttachmentThumbnailQuality) -> UIImage? {
        return DependenciesBridge.shared.attachmentThumbnailService
            .thumbnailImageSync(for: self, quality: quality)
    }
}
