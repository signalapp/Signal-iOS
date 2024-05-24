//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import GRDB

extension Attachment {
    public struct Record: Codable, MutablePersistableRecord, FetchableRecord, Equatable {

        var sqliteId: Int64?
        let blurHash: String?
        let sha256ContentHash: Data?
        let encryptedByteCount: UInt32?
        let unencryptedByteCount: UInt32?
        let mimeType: String
        let encryptionKey: Data
        let digestSHA256Ciphertext: Data?
        let contentType: UInt32?
        let transitCdnNumber: UInt32?
        let transitCdnKey: String?
        let transitUploadTimestamp: UInt64?
        let transitEncryptionKey: Data?
        let transitEncryptedByteCount: UInt32?
        let transitDigestSHA256Ciphertext: Data?
        let lastTransitDownloadAttemptTimestamp: UInt64?
        let mediaName: String?
        let mediaTierCdnNumber: UInt32?
        let mediaTierUploadEra: String?
        let lastMediaTierDownloadAttemptTimestamp: UInt64?
        let thumbnailCdnNumber: UInt32?
        let thumbnailUploadEra: String?
        let lastThumbnailDownloadAttemptTimestamp: UInt64?
        let localRelativeFilePath: String?
        let localRelativeFilePathThumbnail: String?
        let cachedAudioDurationSeconds: Double?
        let cachedMediaHeightPixels: UInt32?
        let cachedMediaWidthPixels: UInt32?
        let cachedVideoDurationSeconds: Double?
        let audioWaveformRelativeFilePath: String?
        let videoStillFrameRelativeFilePath: String?

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
            case transitEncryptedByteCount
            case transitDigestSHA256Ciphertext
            case lastTransitDownloadAttemptTimestamp
            case mediaName
            case mediaTierCdnNumber
            case mediaTierUploadEra
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
        }

        // MARK: - MutablePersistableRecord

        public static let databaseTableName: String = "Attachment"

        public mutating func didInsert(with rowID: Int64, for column: String?) {
            self.sqliteId = rowID
        }

        // MARK: - Initializers

        internal init(
            sqliteId: Int64? = nil,
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
            transitEncryptedByteCount: UInt32?,
            transitDigestSHA256Ciphertext: Data?,
            lastTransitDownloadAttemptTimestamp: UInt64?,
            mediaName: String?,
            mediaTierCdnNumber: UInt32?,
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
            videoStillFrameRelativeFilePath: String?
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
            self.transitEncryptedByteCount = transitEncryptedByteCount
            self.transitDigestSHA256Ciphertext = transitDigestSHA256Ciphertext
            self.lastTransitDownloadAttemptTimestamp = lastTransitDownloadAttemptTimestamp
            self.mediaName = mediaName
            self.mediaTierCdnNumber = mediaTierCdnNumber
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
                thumbnailMediaTierInfo: attachment.thumbnailMediaTierInfo
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
                thumbnailMediaTierInfo: params.thumbnailMediaTierInfo
            )
        }

        internal init(
            sqliteId: Int64,
            blurHash: String?,
            mimeType: String,
            encryptionKey: Data,
            mediaName: String?,
            localRelativeFilePathThumbnail: String?,
            streamInfo: Attachment.StreamInfo?,
            transitTierInfo: Attachment.TransitTierInfo?,
            mediaTierInfo: Attachment.MediaTierInfo?,
            thumbnailMediaTierInfo: Attachment.ThumbnailMediaTierInfo?
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
                thumbnailMediaTierInfo: thumbnailMediaTierInfo
            )
        }

        // Private as we want to be deliberate around when sqlite id is not provided.
        private init(
            optionalSqliteId: Int64?,
            blurHash: String?,
            mimeType: String,
            encryptionKey: Data,
            mediaName: String?,
            localRelativeFilePathThumbnail: String?,
            streamInfo: Attachment.StreamInfo?,
            transitTierInfo: Attachment.TransitTierInfo?,
            mediaTierInfo: Attachment.MediaTierInfo?,
            thumbnailMediaTierInfo: Attachment.ThumbnailMediaTierInfo?
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
            self.transitEncryptedByteCount = transitTierInfo?.encryptedByteCount
            self.transitDigestSHA256Ciphertext = transitTierInfo?.digestSHA256Ciphertext
            self.lastTransitDownloadAttemptTimestamp = transitTierInfo?.lastDownloadAttemptTimestamp
            self.mediaName = mediaName
            self.mediaTierCdnNumber = mediaTierInfo?.cdnNumber
            self.mediaTierUploadEra = mediaTierInfo?.uploadEra
            self.lastMediaTierDownloadAttemptTimestamp = mediaTierInfo?.lastDownloadAttemptTimestamp
            self.thumbnailCdnNumber = thumbnailMediaTierInfo?.cdnNumber
            self.thumbnailUploadEra = thumbnailMediaTierInfo?.uploadEra
            self.lastThumbnailDownloadAttemptTimestamp = thumbnailMediaTierInfo?.lastDownloadAttemptTimestamp
            self.localRelativeFilePath = streamInfo?.localRelativeFilePath
            self.localRelativeFilePathThumbnail = localRelativeFilePathThumbnail

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
