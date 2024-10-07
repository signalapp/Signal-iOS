//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
public import GRDB

extension Attachment {
    public struct Record: Codable, MutablePersistableRecord, FetchableRecord, Equatable, UInt64SafeRecord {

        public typealias IDType = Int64

        var sqliteId: IDType?
        let blurHash: String?
        let sha256ContentHash: Data?
        let encryptedByteCount: UInt32?
        let unencryptedByteCount: UInt32?
        let mimeType: String
        let encryptionKey: Data
        let digestSHA256Ciphertext: Data?
        var contentType: UInt32?
        var transitCdnNumber: UInt32?
        var transitCdnKey: String?
        var transitUploadTimestamp: UInt64?
        var transitEncryptionKey: Data?
        var transitUnencryptedByteCount: UInt32?
        var transitDigestSHA256Ciphertext: Data?
        var lastTransitDownloadAttemptTimestamp: UInt64?
        let mediaName: String?
        var mediaTierCdnNumber: UInt32?
        var mediaTierDigestSHA256Ciphertext: Data?
        var mediaTierUnencryptedByteCount: UInt32?
        var mediaTierUploadEra: String?
        var lastMediaTierDownloadAttemptTimestamp: UInt64?
        var thumbnailCdnNumber: UInt32?
        var thumbnailUploadEra: String?
        var lastThumbnailDownloadAttemptTimestamp: UInt64?
        let localRelativeFilePath: String?
        let localRelativeFilePathThumbnail: String?
        let cachedAudioDurationSeconds: Double?
        let cachedMediaHeightPixels: UInt32?
        let cachedMediaWidthPixels: UInt32?
        let cachedVideoDurationSeconds: Double?
        let audioWaveformRelativeFilePath: String?
        let videoStillFrameRelativeFilePath: String?
        let originalAttachmentIdForQuotedReply: Int64?
        var mediaTierIncrementalMac: Data?
        var mediaTierIncrementalMacChunkSize: UInt32?
        let transitTierIncrementalMac: Data?
        let transitTierIncrementalMacChunkSize: UInt32?

        // MARK: - Coding Keys

        public enum CodingKeys: String, CodingKey {
            case sqliteId = "id"
            case blurHash
            case mimeType
            case sha256ContentHash
            case encryptedByteCount
            case unencryptedByteCount
            case contentType
            case encryptionKey
            case digestSHA256Ciphertext
            case transitCdnNumber
            case transitCdnKey
            case transitUploadTimestamp
            case transitEncryptionKey
            case transitUnencryptedByteCount
            case transitDigestSHA256Ciphertext
            case lastTransitDownloadAttemptTimestamp
            case mediaName
            case mediaTierCdnNumber
            case mediaTierUnencryptedByteCount
            case mediaTierUploadEra
            case mediaTierDigestSHA256Ciphertext
            case lastMediaTierDownloadAttemptTimestamp
            case thumbnailCdnNumber
            case thumbnailUploadEra
            case lastThumbnailDownloadAttemptTimestamp
            case localRelativeFilePath
            case localRelativeFilePathThumbnail
            case cachedAudioDurationSeconds
            case cachedMediaHeightPixels
            case cachedMediaWidthPixels
            case cachedVideoDurationSeconds
            case audioWaveformRelativeFilePath
            case videoStillFrameRelativeFilePath
            case originalAttachmentIdForQuotedReply
            case mediaTierIncrementalMac
            case mediaTierIncrementalMacChunkSize
            case transitTierIncrementalMac
            case transitTierIncrementalMacChunkSize
        }

        // MARK: - UInt64SafeRecord

        public static var uint64Fields: [KeyPath<Attachment.Record, UInt64>] { [] }

        public static var uint64OptionalFields: [KeyPath<Self, UInt64?>] {
            return [
                \.transitUploadTimestamp,
                \.lastTransitDownloadAttemptTimestamp,
                \.lastMediaTierDownloadAttemptTimestamp,
                \.lastThumbnailDownloadAttemptTimestamp
            ]
        }

        // MARK: - MutablePersistableRecord

        public static let databaseTableName: String = "Attachment"

        public mutating func didInsert(with rowID: Int64, for column: String?) {
            self.sqliteId = rowID
        }

        // MARK: - Initializers

        internal init(
            sqliteId: IDType? = nil,
            blurHash: String?,
            sha256ContentHash: Data?,
            encryptedByteCount: UInt32?,
            unencryptedByteCount: UInt32?,
            mimeType: String,
            encryptionKey: Data,
            digestSHA256Ciphertext: Data?,
            contentType: UInt32?,
            transitCdnNumber: UInt32?,
            transitCdnKey: String?,
            transitUploadTimestamp: UInt64?,
            transitEncryptionKey: Data?,
            transitUnencryptedByteCount: UInt32?,
            transitDigestSHA256Ciphertext: Data?,
            lastTransitDownloadAttemptTimestamp: UInt64?,
            mediaName: String?,
            mediaTierCdnNumber: UInt32?,
            mediaTierDigestSHA256Ciphertext: Data?,
            mediaTierUnencryptedByteCount: UInt32?,
            mediaTierUploadEra: String?,
            lastMediaTierDownloadAttemptTimestamp: UInt64?,
            thumbnailCdnNumber: UInt32?,
            thumbnailUploadEra: String?,
            lastThumbnailDownloadAttemptTimestamp: UInt64?,
            localRelativeFilePath: String?,
            localRelativeFilePathThumbnail: String?,
            cachedAudioDurationSeconds: Double?,
            cachedMediaHeightPixels: UInt32?,
            cachedMediaWidthPixels: UInt32?,
            cachedVideoDurationSeconds: Double?,
            audioWaveformRelativeFilePath: String?,
            videoStillFrameRelativeFilePath: String?,
            originalAttachmentIdForQuotedReply: Int64?,
            mediaTierIncrementalMac: Data?,
            mediaTierIncrementalMacChunkSize: UInt32?,
            transitTierIncrementalMac: Data?,
            transitTierIncrementalMacChunkSize: UInt32?
        ) {
            self.sqliteId = sqliteId
            self.blurHash = blurHash
            self.sha256ContentHash = sha256ContentHash
            self.encryptedByteCount = encryptedByteCount
            self.unencryptedByteCount = unencryptedByteCount
            self.mimeType = mimeType
            self.encryptionKey = encryptionKey
            self.digestSHA256Ciphertext = digestSHA256Ciphertext
            self.contentType = contentType
            self.transitCdnNumber = transitCdnNumber
            self.transitCdnKey = transitCdnKey
            self.transitUploadTimestamp = transitUploadTimestamp
            self.transitEncryptionKey = transitEncryptionKey
            self.transitUnencryptedByteCount = transitUnencryptedByteCount
            self.transitDigestSHA256Ciphertext = transitDigestSHA256Ciphertext
            self.lastTransitDownloadAttemptTimestamp = lastTransitDownloadAttemptTimestamp
            self.mediaName = mediaName
            self.mediaTierCdnNumber = mediaTierCdnNumber
            self.mediaTierDigestSHA256Ciphertext = mediaTierDigestSHA256Ciphertext
            self.mediaTierUnencryptedByteCount = mediaTierUnencryptedByteCount
            self.mediaTierUploadEra = mediaTierUploadEra
            self.lastMediaTierDownloadAttemptTimestamp = lastMediaTierDownloadAttemptTimestamp
            self.thumbnailCdnNumber = thumbnailCdnNumber
            self.thumbnailUploadEra = thumbnailUploadEra
            self.lastThumbnailDownloadAttemptTimestamp = lastThumbnailDownloadAttemptTimestamp
            self.localRelativeFilePath = localRelativeFilePath
            self.localRelativeFilePathThumbnail = localRelativeFilePathThumbnail
            self.cachedAudioDurationSeconds = cachedAudioDurationSeconds
            self.cachedMediaHeightPixels = cachedMediaHeightPixels
            self.cachedMediaWidthPixels = cachedMediaWidthPixels
            self.cachedVideoDurationSeconds = cachedVideoDurationSeconds
            self.audioWaveformRelativeFilePath = audioWaveformRelativeFilePath
            self.videoStillFrameRelativeFilePath = videoStillFrameRelativeFilePath
            self.originalAttachmentIdForQuotedReply = originalAttachmentIdForQuotedReply
            self.mediaTierIncrementalMac = mediaTierIncrementalMac
            self.mediaTierIncrementalMacChunkSize = mediaTierIncrementalMacChunkSize
            self.transitTierIncrementalMac = transitTierIncrementalMac
            self.transitTierIncrementalMacChunkSize = transitTierIncrementalMacChunkSize
        }

        internal init(attachment: Attachment) {
            self.init(
                sqliteId: attachment.id,
                blurHash: attachment.blurHash,
                mimeType: attachment.mimeType,
                encryptionKey: attachment.encryptionKey,
                mediaName: attachment.mediaName,
                localRelativeFilePathThumbnail: attachment.localRelativeFilePathThumbnail,
                streamInfo: attachment.streamInfo,
                transitTierInfo: attachment.transitTierInfo,
                mediaTierInfo: attachment.mediaTierInfo,
                thumbnailMediaTierInfo: attachment.thumbnailMediaTierInfo,
                originalAttachmentIdForQuotedReply: attachment.originalAttachmentIdForQuotedReply
            )
        }

        internal init(params: Attachment.ConstructionParams) {
            self.init(
                optionalSqliteId: nil,
                blurHash: params.blurHash,
                mimeType: params.mimeType,
                encryptionKey: params.encryptionKey,
                mediaName: params.mediaName,
                localRelativeFilePathThumbnail: params.localRelativeFilePathThumbnail,
                streamInfo: params.streamInfo,
                transitTierInfo: params.transitTierInfo,
                mediaTierInfo: params.mediaTierInfo,
                thumbnailMediaTierInfo: params.thumbnailMediaTierInfo,
                originalAttachmentIdForQuotedReply: params.originalAttachmentIdForQuotedReply
            )
        }

        internal init(
            sqliteId: IDType,
            blurHash: String?,
            mimeType: String,
            encryptionKey: Data,
            mediaName: String?,
            localRelativeFilePathThumbnail: String?,
            streamInfo: Attachment.StreamInfo?,
            transitTierInfo: Attachment.TransitTierInfo?,
            mediaTierInfo: Attachment.MediaTierInfo?,
            thumbnailMediaTierInfo: Attachment.ThumbnailMediaTierInfo?,
            originalAttachmentIdForQuotedReply: Int64?
        ) {
            self.init(
                optionalSqliteId: sqliteId,
                blurHash: blurHash,
                mimeType: mimeType,
                encryptionKey: encryptionKey,
                mediaName: mediaName,
                localRelativeFilePathThumbnail: localRelativeFilePathThumbnail,
                streamInfo: streamInfo,
                transitTierInfo: transitTierInfo,
                mediaTierInfo: mediaTierInfo,
                thumbnailMediaTierInfo: thumbnailMediaTierInfo,
                originalAttachmentIdForQuotedReply: originalAttachmentIdForQuotedReply
            )
        }

        // Private as we want to be deliberate around when sqlite id is not provided.
        private init(
            optionalSqliteId: IDType?,
            blurHash: String?,
            mimeType: String,
            encryptionKey: Data,
            mediaName: String?,
            localRelativeFilePathThumbnail: String?,
            streamInfo: Attachment.StreamInfo?,
            transitTierInfo: Attachment.TransitTierInfo?,
            mediaTierInfo: Attachment.MediaTierInfo?,
            thumbnailMediaTierInfo: Attachment.ThumbnailMediaTierInfo?,
            originalAttachmentIdForQuotedReply: Int64?
        ) {
            self.sqliteId = optionalSqliteId
            self.blurHash = blurHash
            self.sha256ContentHash = streamInfo?.sha256ContentHash
            self.encryptedByteCount = streamInfo?.encryptedByteCount
            self.unencryptedByteCount = streamInfo?.unencryptedByteCount
            self.mimeType = mimeType
            self.encryptionKey = encryptionKey
            self.digestSHA256Ciphertext = streamInfo?.digestSHA256Ciphertext
            self.contentType = (streamInfo?.contentType.raw.rawValue).map { UInt32($0) }
            self.transitCdnNumber = transitTierInfo?.cdnNumber
            self.transitCdnKey = transitTierInfo?.cdnKey
            self.transitUploadTimestamp = transitTierInfo?.uploadTimestamp
            self.transitEncryptionKey = transitTierInfo?.encryptionKey
            self.transitUnencryptedByteCount = transitTierInfo?.unencryptedByteCount
            self.transitDigestSHA256Ciphertext = transitTierInfo?.digestSHA256Ciphertext
            self.transitTierIncrementalMac = transitTierInfo?.incrementalMacInfo?.mac
            self.transitTierIncrementalMacChunkSize = transitTierInfo?.incrementalMacInfo?.chunkSize
            self.lastTransitDownloadAttemptTimestamp = transitTierInfo?.lastDownloadAttemptTimestamp
            self.mediaName = mediaName
            self.mediaTierCdnNumber = mediaTierInfo?.cdnNumber
            self.mediaTierDigestSHA256Ciphertext = mediaTierInfo?.digestSHA256Ciphertext
            self.mediaTierUnencryptedByteCount = mediaTierInfo?.unencryptedByteCount
            self.mediaTierIncrementalMac = mediaTierInfo?.incrementalMacInfo?.mac
            self.mediaTierIncrementalMacChunkSize = mediaTierInfo?.incrementalMacInfo?.chunkSize
            self.mediaTierUploadEra = mediaTierInfo?.uploadEra
            self.lastMediaTierDownloadAttemptTimestamp = mediaTierInfo?.lastDownloadAttemptTimestamp
            self.thumbnailCdnNumber = thumbnailMediaTierInfo?.cdnNumber
            self.thumbnailUploadEra = thumbnailMediaTierInfo?.uploadEra
            self.lastThumbnailDownloadAttemptTimestamp = thumbnailMediaTierInfo?.lastDownloadAttemptTimestamp
            self.localRelativeFilePath = streamInfo?.localRelativeFilePath
            self.localRelativeFilePathThumbnail = localRelativeFilePathThumbnail
            self.originalAttachmentIdForQuotedReply = originalAttachmentIdForQuotedReply

            let cachedAudioDurationSeconds: TimeInterval?
            let cachedMediaSizePixels: CGSize?
            let cachedVideoDurationSeconds: TimeInterval?
            let audioWaveformRelativeFilePath: String?
            let videoStillFrameRelativeFilePath: String?

            switch streamInfo?.contentType {
            case .invalid, .file, nil:
                cachedAudioDurationSeconds = nil
                cachedMediaSizePixels = nil
                cachedVideoDurationSeconds = nil
                audioWaveformRelativeFilePath = nil
                videoStillFrameRelativeFilePath = nil
            case .image(let pixelSize):
                cachedAudioDurationSeconds = nil
                cachedMediaSizePixels = pixelSize
                cachedVideoDurationSeconds = nil
                audioWaveformRelativeFilePath = nil
                videoStillFrameRelativeFilePath = nil
            case .video(let duration, let pixelSize, let stillFrameRelativeFilePath):
                cachedAudioDurationSeconds = nil
                cachedMediaSizePixels = pixelSize
                cachedVideoDurationSeconds = duration
                audioWaveformRelativeFilePath = nil
                videoStillFrameRelativeFilePath = stillFrameRelativeFilePath
            case .animatedImage(let pixelSize):
                cachedAudioDurationSeconds = nil
                cachedMediaSizePixels = pixelSize
                cachedVideoDurationSeconds = nil
                audioWaveformRelativeFilePath = nil
                videoStillFrameRelativeFilePath = nil
            case .audio(let duration, let waveformRelativeFilePath):
                cachedAudioDurationSeconds = duration
                cachedMediaSizePixels = nil
                cachedVideoDurationSeconds = nil
                audioWaveformRelativeFilePath = waveformRelativeFilePath
                videoStillFrameRelativeFilePath = nil
            }

            self.cachedAudioDurationSeconds = cachedAudioDurationSeconds
            self.cachedMediaHeightPixels = cachedMediaSizePixels.map { UInt32(exactly: $0.height.rounded()) } ?? nil
            self.cachedMediaWidthPixels = cachedMediaSizePixels.map { UInt32(exactly: $0.width.rounded()) } ?? nil
            self.cachedVideoDurationSeconds = cachedVideoDurationSeconds
            self.audioWaveformRelativeFilePath = audioWaveformRelativeFilePath
            self.videoStillFrameRelativeFilePath = videoStillFrameRelativeFilePath
        }
    }
}
