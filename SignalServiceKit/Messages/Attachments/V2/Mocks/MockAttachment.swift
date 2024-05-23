//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

#if TESTABLE_BUILD

// MARK: - Infos

extension Attachment.StreamInfo {
    public static func mock(
        sha256ContentHash: Data? = nil,
        encryptedByteCount: UInt32? = nil,
        unencryptedByteCount: UInt32? = nil,
        contentType: Attachment.ContentType? = nil,
        digestSHA256Ciphertext: Data? = nil,
        localRelativeFilePath: String? = nil
    ) -> Attachment.StreamInfo {
        return Attachment.StreamInfo(
            sha256ContentHash: sha256ContentHash ?? UInt64.random(in: 0..<(.max)).bigEndianData,
            encryptedByteCount: encryptedByteCount ?? UInt32.random(in: 0..<(UInt32(OWSMediaUtils.kMaxFileSizeGeneric))),
            unencryptedByteCount: unencryptedByteCount ?? UInt32.random(in: 0..<(UInt32(OWSMediaUtils.kMaxFileSizeGeneric))),
            contentType: contentType ?? .file,
            digestSHA256Ciphertext: digestSHA256Ciphertext ?? UInt64.random(in: 0..<(.max)).bigEndianData,
            localRelativeFilePath: localRelativeFilePath ?? UUID().uuidString
        )
    }
}

extension Attachment.TransitTierInfo {
    public static func mock(
        cdnNumber: UInt32? = nil,
        cdnKey: String? = nil,
        uploadTimestamp: UInt64? = nil,
        encryptionKey: Data? = nil,
        encryptedByteCount: UInt32? = nil,
        digestSHA256Ciphertext: Data? = nil,
        lastDownloadAttemptTimestamp: UInt64? = nil
    ) -> Attachment.TransitTierInfo {
        return Attachment.TransitTierInfo(
            cdnNumber: cdnNumber ?? 3,
            cdnKey: cdnKey ?? "\(UInt64.random(in: 0..<(.max)))",
            uploadTimestamp: uploadTimestamp ?? Date().ows_millisecondsSince1970,
            encryptionKey: encryptionKey ?? UInt64.random(in: 0..<(.max)).bigEndianData,
            encryptedByteCount: encryptedByteCount ?? UInt32.random(in: 0..<(UInt32(OWSMediaUtils.kMaxFileSizeGeneric))),
            digestSHA256Ciphertext: digestSHA256Ciphertext ?? UInt64.random(in: 0..<(.max)).bigEndianData,
            lastDownloadAttemptTimestamp: lastDownloadAttemptTimestamp
        )
    }
}

extension Attachment.MediaTierInfo {
    public static func mock(
        cdnNumber: UInt32? = nil,
        uploadEra: String? = nil,
        lastDownloadAttemptTimestamp: UInt64? = nil
    ) -> Attachment.MediaTierInfo {
        return Attachment.MediaTierInfo(
            cdnNumber: cdnNumber ?? 3,
            uploadEra: uploadEra ?? "1",
            lastDownloadAttemptTimestamp: lastDownloadAttemptTimestamp
        )
    }
}

extension Attachment.ThumbnailMediaTierInfo {
    public static func mock(
        cdnNumber: UInt32? = nil,
        uploadEra: String? = nil,
        lastDownloadAttemptTimestamp: UInt64? = nil
    ) -> Attachment.ThumbnailMediaTierInfo {
        return Attachment.ThumbnailMediaTierInfo(
            cdnNumber: cdnNumber ?? 3,
            uploadEra: uploadEra ?? "1",
            lastDownloadAttemptTimestamp: lastDownloadAttemptTimestamp
        )
    }
}

// MARK: - Attachment

public class MockAttachment: Attachment {

    public static func mock(
        blurHash: String? = nil,
        mimeType: String? = nil,
        encryptionKey: Data? = nil,
        mediaName: String? = nil,
        streamInfo: Attachment.StreamInfo? = nil,
        transitTierInfo: Attachment.TransitTierInfo? = nil,
        mediaTierInfo: Attachment.MediaTierInfo? = nil,
        thumbnailInfo: Attachment.ThumbnailMediaTierInfo? = nil,
        localRelativeFilePath: String? = nil,
        localRelativeFilePathThumbnail: String? = nil,
        cachedAudioDurationSeconds: Double? = nil,
        cachedMediaHeightPixels: UInt32? = nil,
        cachedMediaWidthPixels: UInt32? = nil,
        cachedVideoDurationSeconds: Double? = nil,
        audioWaveformRelativeFilePath: String? = nil,
        videoStillFrameRelativeFilePath: String? = nil
    ) -> MockAttachment {
        let record = Attachment.Record(
           sqliteId: .random(in: 0..<(.max)),
           blurHash: blurHash,
           sha256ContentHash: streamInfo?.sha256ContentHash,
           encryptedByteCount: streamInfo?.encryptedByteCount,
           unencryptedByteCount: streamInfo?.unencryptedByteCount,
           mimeType: mimeType ?? MimeType.applicationOctetStream.rawValue,
           encryptionKey: encryptionKey ?? UInt64.random(in: 0..<(.max)).bigEndianData,
           digestSHA256Ciphertext: streamInfo?.digestSHA256Ciphertext,
           contentType: (streamInfo?.contentType.raw.rawValue).map { UInt32(exactly: $0) } ?? nil,
           transitCdnNumber: transitTierInfo?.cdnNumber,
           transitCdnKey: transitTierInfo?.cdnKey,
           transitUploadTimestamp: transitTierInfo?.uploadTimestamp,
           transitEncryptionKey: transitTierInfo?.encryptionKey,
           transitEncryptedByteCount: transitTierInfo?.encryptedByteCount,
           transitDigestSHA256Ciphertext: transitTierInfo?.digestSHA256Ciphertext,
           lastTransitDownloadAttemptTimestamp: transitTierInfo?.lastDownloadAttemptTimestamp,
           mediaName: mediaName ?? "\(UInt64.random(in: 0..<(.max)))",
           mediaTierCdnNumber: mediaTierInfo?.cdnNumber,
           mediaTierUploadEra: mediaTierInfo?.uploadEra,
           lastMediaTierDownloadAttemptTimestamp: mediaTierInfo?.lastDownloadAttemptTimestamp,
           thumbnailCdnNumber: thumbnailInfo?.cdnNumber,
           thumbnailUploadEra: thumbnailInfo?.uploadEra,
           lastThumbnailDownloadAttemptTimestamp: thumbnailInfo?.lastDownloadAttemptTimestamp,
           localRelativeFilePath: localRelativeFilePath,
           localRelativeFilePathThumbnail: localRelativeFilePathThumbnail,
           /// Always set these values so we never fail validation.
           cachedAudioDurationSeconds: cachedAudioDurationSeconds ?? 10,
           cachedMediaHeightPixels: cachedMediaHeightPixels ?? 100,
           cachedMediaWidthPixels: cachedMediaWidthPixels ?? 100,
           cachedVideoDurationSeconds: cachedVideoDurationSeconds ?? 10,
           audioWaveformRelativeFilePath: nil,
           videoStillFrameRelativeFilePath: nil
       )

        return try! MockAttachment(record: record)
    }

    public override func asStream() -> AttachmentStream? {
        return MockAttachmentStream(attachment: self)
    }
}

public class MockAttachmentStream: AttachmentStream {

    public static func mock(
        blurHash: String? = nil,
        mimeType: String? = nil,
        mediaName: String? = nil,
        streamInfo: Attachment.StreamInfo = .mock(),
        transitTierInfo: Attachment.TransitTierInfo? = nil,
        mediaTierInfo: Attachment.MediaTierInfo? = nil,
        thumbnailInfo: Attachment.ThumbnailMediaTierInfo? = nil,
        localRelativeFilePath: String = "/some/file/path",
        localRelativeFilePathThumbnail: String? = nil
    ) -> MockAttachmentStream {
        let attachment = MockAttachment.mock(
            blurHash: blurHash,
            mimeType: mimeType,
            mediaName: mediaName,
            streamInfo: streamInfo,
            transitTierInfo: transitTierInfo,
            mediaTierInfo: mediaTierInfo,
            thumbnailInfo: thumbnailInfo,
            localRelativeFilePath: localRelativeFilePath,
            localRelativeFilePathThumbnail: localRelativeFilePathThumbnail
        )
        return MockAttachmentStream(attachment: attachment)!
    }

    public override var fileURL: URL {
        return URL(string: localRelativeFilePath)!
    }
}

#endif
