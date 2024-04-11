//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

#if TESTABLE_BUILD

// MARK: - Infos

extension Attachment.StreamInfo {
    public static func mock(
        contentHash: String? = nil,
        encryptedByteCount: UInt32? = nil,
        unenecryptedByteCount: UInt32? = nil,
        contentType: Attachment.ContentType? = nil,
        encryptionKey: Data? = nil,
        encryptedFileSha256Digest: Data? = nil
    ) -> Attachment.StreamInfo {
        return Attachment.StreamInfo(
            contentHash: contentHash ?? "\(UInt64.random(in: 0..<(.max)))",
            encryptedByteCount: encryptedByteCount ?? UInt32.random(in: 0..<(UInt32(OWSMediaUtils.kMaxFileSizeGeneric))),
            unenecryptedByteCount: unenecryptedByteCount ?? UInt32.random(in: 0..<(UInt32(OWSMediaUtils.kMaxFileSizeGeneric))),
            contentType: contentType ?? .file,
            encryptionKey: encryptionKey ?? UInt64.random(in: 0..<(.max)).bigEndianData,
            encryptedFileSha256Digest: encryptedFileSha256Digest ?? UInt64.random(in: 0..<(.max)).bigEndianData
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
        encryptedFileSha256Digest: Data? = nil,
        lastDownloadAttemptTimestamp: UInt64? = nil
    ) -> Attachment.TransitTierInfo {
        return Attachment.TransitTierInfo(
            cdnNumber: cdnNumber ?? 3,
            cdnKey: cdnKey ?? "\(UInt64.random(in: 0..<(.max)))",
            uploadTimestamp: uploadTimestamp ?? Date().ows_millisecondsSince1970,
            encryptionKey: encryptionKey ?? UInt64.random(in: 0..<(.max)).bigEndianData,
            encryptedByteCount: encryptedByteCount ?? UInt32.random(in: 0..<(UInt32(OWSMediaUtils.kMaxFileSizeGeneric))),
            encryptedFileSha256Digest: encryptedFileSha256Digest ?? UInt64.random(in: 0..<(.max)).bigEndianData,
            lastDownloadAttemptTimestamp: lastDownloadAttemptTimestamp
        )
    }
}

extension Attachment.MediaTierInfo {
    public static func mock(
        cdnNumber: UInt32? = nil,
        uploadEra: UInt64? = nil,
        lastDownloadAttemptTimestamp: UInt64? = nil
    ) -> Attachment.MediaTierInfo {
        return Attachment.MediaTierInfo(
            cdnNumber: cdnNumber ?? 3,
            uploadEra: uploadEra ?? 1,
            lastDownloadAttemptTimestamp: lastDownloadAttemptTimestamp
        )
    }
}

extension Attachment.ThumbnailMediaTierInfo {
    public static func mock(
        cdnNumber: UInt32? = nil,
        uploadEra: UInt64? = nil,
        lastDownloadAttemptTimestamp: UInt64? = nil
    ) -> Attachment.ThumbnailMediaTierInfo {
        return Attachment.ThumbnailMediaTierInfo(
            cdnNumber: cdnNumber ?? 3,
            uploadEra: uploadEra ?? 1,
            lastDownloadAttemptTimestamp: lastDownloadAttemptTimestamp
        )
    }
}

// MARK: - Attachment

public class MockAttachment: Attachment {

    public static func mock(
        blurHash: String? = nil,
        mimeType: String? = nil,
        mediaName: String? = nil,
        streamInfo: Attachment.StreamInfo? = nil,
        transitTierInfo: Attachment.TransitTierInfo? = nil,
        mediaTierInfo: Attachment.MediaTierInfo? = nil,
        thumbnailInfo: Attachment.ThumbnailMediaTierInfo? = nil,
        localRelativeFilePath: String? = nil,
        localRelativeFilePathThumbnail: String? = nil
    ) -> MockAttachment {
        return MockAttachment(
            id: .random(in: 0..<(.max)),
            blurHash: blurHash,
            contentHash: streamInfo?.contentHash,
            encryptedByteCount: streamInfo?.encryptedByteCount,
            unenecryptedByteCount: streamInfo?.unenecryptedByteCount,
            mimeType: mimeType ?? MimeType.applicationOctetStream.rawValue,
            contentType: streamInfo?.contentType,
            encryptionKey: streamInfo?.encryptionKey,
            encryptedFileSha256Digest: streamInfo?.encryptedFileSha256Digest,
            transitCdnNumber: transitTierInfo?.cdnNumber,
            transitCdnKey: transitTierInfo?.cdnKey,
            transitUploadTimestamp: transitTierInfo?.uploadTimestamp,
            transitEncryptionKey: transitTierInfo?.encryptionKey,
            transitEncryptedByteCount: transitTierInfo?.encryptedByteCount,
            transitEncryptedFileSha256Digest: transitTierInfo?.encryptedFileSha256Digest,
            lastTransitDownloadAttemptTimestamp: transitTierInfo?.lastDownloadAttemptTimestamp,
            mediaName: mediaName ?? "\(UInt64.random(in: 0..<(.max)))",
            mediaCdnNumber: mediaTierInfo?.cdnNumber,
            mediaTierUploadEra: mediaTierInfo?.uploadEra,
            lastMediaDownloadAttemptTimestamp: mediaTierInfo?.lastDownloadAttemptTimestamp,
            thumbnailCdnNumber: thumbnailInfo?.cdnNumber,
            thumbnailUploadEra: thumbnailInfo?.uploadEra,
            lastThumbnailDownloadAttemptTimestamp: thumbnailInfo?.lastDownloadAttemptTimestamp,
            localRelativeFilePath: localRelativeFilePath,
            localRelativeFilePathThumbnail: localRelativeFilePathThumbnail
        )
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
