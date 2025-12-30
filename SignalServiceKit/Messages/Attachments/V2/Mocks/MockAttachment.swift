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
        mediaName: String? = nil,
        encryptedByteCount: UInt32? = nil,
        unencryptedByteCount: UInt32? = nil,
        contentType: Attachment.ContentType? = nil,
        digestSHA256Ciphertext: Data? = nil,
        localRelativeFilePath: String? = nil,
    ) -> Attachment.StreamInfo {
        return Attachment.StreamInfo(
            sha256ContentHash: sha256ContentHash ?? Randomness.generateRandomBytes(32),
            mediaName: mediaName ?? UUID().uuidString,
            encryptedByteCount: encryptedByteCount ?? UInt32.random(in: 0..<UInt32(OWSMediaUtils.kMaxFileSizeGeneric)),
            unencryptedByteCount: unencryptedByteCount ?? UInt32.random(in: 0..<UInt32(OWSMediaUtils.kMaxFileSizeGeneric)),
            contentType: contentType ?? .file,
            digestSHA256Ciphertext: digestSHA256Ciphertext ?? Randomness.generateRandomBytes(32),
            localRelativeFilePath: localRelativeFilePath ?? UUID().uuidString,
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
            unencryptedByteCount: unencryptedByteCount ?? UInt32.random(in: 0..<UInt32(OWSMediaUtils.kMaxFileSizeGeneric)),
            integrityCheck: integrityCheck ?? .digestSHA256Ciphertext(Randomness.generateRandomBytes(32)),
            incrementalMacInfo: incrementalMacInfo,
            lastDownloadAttemptTimestamp: lastDownloadAttemptTimestamp,
        )
    }
}

extension Attachment.MediaTierInfo {
    public static func mock(
        cdnNumber: UInt32? = nil,
        unencryptedByteCount: UInt32? = nil,
        sha256ContentHash: Data? = nil,
        incrementalMacInfo: Attachment.IncrementalMacInfo? = nil,
        uploadEra: String? = nil,
        lastDownloadAttemptTimestamp: UInt64? = nil,
    ) -> Attachment.MediaTierInfo {
        return Attachment.MediaTierInfo(
            cdnNumber: cdnNumber ?? 3,
            unencryptedByteCount: unencryptedByteCount ?? 16,
            sha256ContentHash: sha256ContentHash ?? Randomness.generateRandomBytes(32),
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

// MARK: - Params

extension Attachment.ConstructionParams {

    public static func mockPointer(
        blurHash: String? = UUID().uuidString,
        mimeType: String = MimeType.imageJpeg.rawValue,
        encryptionKey: Data = UUID().data,
        transitTierInfo: Attachment.TransitTierInfo = .mock(),
    ) -> Attachment.ConstructionParams {
        return Attachment.ConstructionParams.fromPointer(
            blurHash: blurHash,
            mimeType: mimeType,
            encryptionKey: encryptionKey,
            latestTransitTierInfo: transitTierInfo,
        )
    }

    public static func mockStream(
        blurHash: String? = UUID().uuidString,
        mimeType: String = MimeType.imageJpeg.rawValue,
        encryptionKey: Data = UUID().data,
        sha256ContentHash: Data? = nil,
        mediaName: String? = nil,
        streamInfo: Attachment.StreamInfo = .mock(),
    ) -> Attachment.ConstructionParams {
        return Attachment.ConstructionParams.fromStream(
            blurHash: blurHash,
            mimeType: mimeType,
            encryptionKey: encryptionKey,
            streamInfo: streamInfo,
            sha256ContentHash: sha256ContentHash ?? streamInfo.sha256ContentHash,
            mediaName: mediaName ?? streamInfo.mediaName,
        )
    }
}

// MARK: - Attachment

public class MockAttachment: Attachment {

    public static func mock(
        blurHash: String? = nil,
        mimeType: String? = nil,
        encryptionKey: Data? = nil,
        sha256ContentHash: Data? = nil,
        mediaName: String? = nil,
        streamInfo: Attachment.StreamInfo? = nil,
        transitTierInfo: Attachment.TransitTierInfo? = nil,
        mediaTierInfo: Attachment.MediaTierInfo? = nil,
        thumbnailInfo: Attachment.ThumbnailMediaTierInfo? = nil,
        localRelativeFilePathThumbnail: String? = nil,
        originalAttachmentIdForQuotedReply: Attachment.IDType? = nil,
        lastFullscreenViewTimestamp: UInt64? = nil,
    ) -> MockAttachment {
        let record = Attachment.Record(
            sqliteId: .random(in: 0..<(.max)),
            blurHash: blurHash,
            mimeType: mimeType ?? MimeType.applicationOctetStream.rawValue,
            encryptionKey: encryptionKey ?? Randomness.generateRandomBytes(64),
            sha256ContentHash: sha256ContentHash ?? streamInfo?.sha256ContentHash ?? UUID().data,
            mediaName: mediaName ?? streamInfo?.mediaName ?? UUID().uuidString,
            localRelativeFilePathThumbnail: localRelativeFilePathThumbnail,
            streamInfo: streamInfo,
            latestTransitTierInfo: transitTierInfo,
            originalTransitTierInfo: transitTierInfo?.encryptionKey == encryptionKey ? transitTierInfo : nil,
            mediaTierInfo: mediaTierInfo,
            thumbnailMediaTierInfo: thumbnailInfo,
            originalAttachmentIdForQuotedReply: originalAttachmentIdForQuotedReply,
            lastFullscreenViewTimestamp: lastFullscreenViewTimestamp,
        )

        return try! MockAttachment(record: record)
    }

    override public func asStream() -> AttachmentStream? {
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
        localRelativeFilePathThumbnail: String? = nil,
    ) -> MockAttachmentStream {
        let attachment = MockAttachment.mock(
            blurHash: blurHash,
            mimeType: mimeType,
            mediaName: mediaName,
            streamInfo: streamInfo,
            transitTierInfo: transitTierInfo,
            mediaTierInfo: mediaTierInfo,
            thumbnailInfo: thumbnailInfo,
            localRelativeFilePathThumbnail: localRelativeFilePathThumbnail,
        )
        return MockAttachmentStream(attachment: attachment)!
    }

    override public var fileURL: URL {
        return URL(string: localRelativeFilePath)!
    }
}

#endif
