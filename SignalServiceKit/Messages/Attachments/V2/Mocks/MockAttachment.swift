//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

#if TESTABLE_BUILD

// MARK: - Infos

extension Attachment.StreamInfo {
    public static func mock(
        plaintextHash: Data = Randomness.generateRandomBytes(32),
        mediaName: String = UUID().uuidString,
        encryptedByteCount: UInt32 = .random(in: 0..<95_000_000),
        unencryptedByteCount: UInt32 = .random(in: 0..<95_000_000),
        ciphertextDigest: Data = Randomness.generateRandomBytes(32),
        localRelativeFilePath: String = UUID().uuidString,
    ) -> Attachment.StreamInfo {
        return Attachment.StreamInfo(
            plaintextHash: plaintextHash,
            mediaName: mediaName,
            encryptedByteCount: encryptedByteCount,
            unencryptedByteCount: unencryptedByteCount,
            cachedMediaSizePixels: nil,
            cachedVideoDuration: nil,
            cachedVideoStillFrameRelativeFilePath: nil,
            cachedAudioDuration: nil,
            cachedAudioWaveformRelativeFilePath: nil,
            ciphertextDigest: ciphertextDigest,
            localRelativeFilePath: localRelativeFilePath,
        )
    }
}

extension Attachment.TransitTierInfo {
    public static func mock(
        cdnNumber: UInt32? = nil,
        cdnKey: String? = nil,
        uploadTimestamp: UInt64? = nil,
        encryptionKey: Data? = nil,
        unencryptedByteCount: UInt32? = nil,
        integrityCheck: AttachmentIntegrityCheck? = nil,
        incrementalMacInfo: Attachment.IncrementalMacInfo? = nil,
        lastDownloadAttemptTimestamp: UInt64? = nil,
    ) -> Attachment.TransitTierInfo {
        return Attachment.TransitTierInfo(
            cdnNumber: cdnNumber ?? 3,
            cdnKey: cdnKey ?? "\(UInt64.random(in: 0..<(.max)))",
            uploadTimestamp: uploadTimestamp ?? Date().ows_millisecondsSince1970,
            encryptionKey: encryptionKey ?? Randomness.generateRandomBytes(64),
            unencryptedByteCount: unencryptedByteCount ?? UInt32.random(in: 0..<95_000_000),
            integrityCheck: integrityCheck ?? .ciphertextDigest(Randomness.generateRandomBytes(32)),
            incrementalMacInfo: incrementalMacInfo,
            lastDownloadAttemptTimestamp: lastDownloadAttemptTimestamp,
        )
    }
}

extension Attachment.MediaTierInfo {
    public static func mock(
        cdnNumber: UInt32? = nil,
        unencryptedByteCount: UInt32? = nil,
        plaintextHash: Data? = nil,
        incrementalMacInfo: Attachment.IncrementalMacInfo? = nil,
        uploadEra: String? = nil,
        lastDownloadAttemptTimestamp: UInt64? = nil,
    ) -> Attachment.MediaTierInfo {
        return Attachment.MediaTierInfo(
            cdnNumber: cdnNumber ?? 3,
            unencryptedByteCount: unencryptedByteCount ?? 16,
            plaintextHash: plaintextHash ?? Randomness.generateRandomBytes(32),
            incrementalMacInfo: incrementalMacInfo,
            uploadEra: uploadEra ?? "1",
            lastDownloadAttemptTimestamp: lastDownloadAttemptTimestamp,
        )
    }
}

extension Attachment.ThumbnailMediaTierInfo {
    public static func mock(
        cdnNumber: UInt32? = nil,
        uploadEra: String? = nil,
        lastDownloadAttemptTimestamp: UInt64? = nil,
    ) -> Attachment.ThumbnailMediaTierInfo {
        return Attachment.ThumbnailMediaTierInfo(
            cdnNumber: cdnNumber ?? 3,
            uploadEra: uploadEra ?? "1",
            lastDownloadAttemptTimestamp: lastDownloadAttemptTimestamp,
        )
    }
}

extension Attachment.Record {

    public static func mockPointer(
        blurHash: String? = UUID().uuidString,
        mimeType: String = MimeType.imageJpeg.rawValue,
        encryptionKey: Data = Randomness.generateRandomBytes(64),
        transitTierInfo: Attachment.TransitTierInfo = .mock(),
    ) -> Attachment.Record {
        return .forInsertingPointer(
            blurHash: blurHash,
            mimeType: mimeType,
            contentType: Attachment.ContentType(mimeType: mimeType),
            encryptionKey: encryptionKey,
            latestTransitTierInfo: transitTierInfo,
        )
    }

    public static func mockStream(
        blurHash: String? = UUID().uuidString,
        mimeType: String = MimeType.imageJpeg.rawValue,
        encryptionKey: Data = Randomness.generateRandomBytes(64),
        plaintextHash: Data? = nil,
        mediaName: String? = nil,
        streamInfo: Attachment.StreamInfo = .mock(),
    ) -> Attachment.Record {
        return .forInsertingStream(
            blurHash: blurHash,
            mimeType: mimeType,
            contentType: Attachment.ContentType(mimeType: mimeType),
            encryptionKey: encryptionKey,
            streamInfo: streamInfo,
            plaintextHash: plaintextHash ?? streamInfo.plaintextHash,
            mediaName: mediaName ?? streamInfo.mediaName,
        )
    }
}

extension Attachment {

    public static func mock(
        blurHash: String? = nil,
        mimeType: String = MimeType.applicationOctetStream.rawValue,
        encryptionKey: Data = Randomness.generateRandomBytes(64),
        plaintextHash: Data? = nil,
        mediaName: String? = nil,
        streamInfo: Attachment.StreamInfo? = nil,
        transitTierInfo: Attachment.TransitTierInfo? = nil,
        mediaTierInfo: Attachment.MediaTierInfo? = nil,
        thumbnailInfo: Attachment.ThumbnailMediaTierInfo? = nil,
        localRelativeFilePathThumbnail: String? = nil,
        originalAttachmentIdForQuotedReply: Attachment.IDType? = nil,
        lastFullscreenViewTimestamp: UInt64? = nil,
    ) -> Attachment {
        let record = Attachment.Record(
            sqliteId: .random(in: 0..<(.max)),
            blurHash: blurHash,
            mimeType: mimeType,
            contentType: Attachment.ContentType(mimeType: mimeType),
            encryptionKey: encryptionKey,
            plaintextHash: plaintextHash ?? streamInfo?.plaintextHash,
            mediaName: mediaName ?? streamInfo?.mediaName,
            localRelativeFilePathThumbnail: localRelativeFilePathThumbnail,
            streamInfo: streamInfo,
            latestTransitTierInfo: transitTierInfo,
            originalTransitTierInfo: transitTierInfo?.encryptionKey == encryptionKey ? transitTierInfo : nil,
            mediaTierInfo: mediaTierInfo,
            thumbnailMediaTierInfo: thumbnailInfo,
            originalAttachmentIdForQuotedReply: originalAttachmentIdForQuotedReply,
            lastFullscreenViewTimestamp: lastFullscreenViewTimestamp,
        )

        return try! Attachment(record: record)
    }
}

extension AttachmentStream {

    public static func mock(
        blurHash: String? = nil,
        mimeType: String = MimeType.applicationOctetStream.rawValue,
        mediaName: String? = nil,
        streamInfo: Attachment.StreamInfo = .mock(),
        transitTierInfo: Attachment.TransitTierInfo? = nil,
        mediaTierInfo: Attachment.MediaTierInfo? = nil,
        thumbnailInfo: Attachment.ThumbnailMediaTierInfo? = nil,
        localRelativeFilePathThumbnail: String? = nil,
    ) -> AttachmentStream {
        let attachment = Attachment.mock(
            blurHash: blurHash,
            mimeType: mimeType,
            mediaName: mediaName,
            streamInfo: streamInfo,
            transitTierInfo: transitTierInfo,
            mediaTierInfo: mediaTierInfo,
            thumbnailInfo: thumbnailInfo,
            localRelativeFilePathThumbnail: localRelativeFilePathThumbnail,
        )
        return AttachmentStream(attachment: attachment)!
    }
}

#endif
