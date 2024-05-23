//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import GRDB

extension Attachment {
    public struct Record: Codable, MutablePersistableRecord, FetchableRecord {

        internal(set) var sqliteId: Int64?
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
    }
}
