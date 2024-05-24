//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

extension Attachment {

    /// Collection of parameters for building Attachments.
    ///
    /// Identical to ``Attachment`` except it doesn't have the id (sqlite row id).
    /// Since prior to insertion we don't _have_ a row id, callers can't provide an Attachment
    /// instance for insertion. Instead they provide one of these, from which we can create
    /// an Attachment (actually an Attachment.Record) for insertion, and afterwards get
    /// back the fully fledged Attachment with id included.
    public struct ConstructionParams {
        public let blurHash: String?
        public let mimeType: String
        public let encryptionKey: Data
        public let streamInfo: StreamInfo?
        public let transitTierInfo: TransitTierInfo?
        public let mediaName: String?
        public let mediaTierInfo: MediaTierInfo?
        public let thumbnailMediaTierInfo: ThumbnailMediaTierInfo?
        public let localRelativeFilePathThumbnail: String?

        private init(
            blurHash: String?,
            mimeType: String,
            encryptionKey: Data,
            streamInfo: StreamInfo?,
            transitTierInfo: TransitTierInfo?,
            mediaName: String?,
            mediaTierInfo: MediaTierInfo?,
            thumbnailMediaTierInfo: ThumbnailMediaTierInfo?,
            localRelativeFilePathThumbnail: String?
        ) {
            self.blurHash = blurHash
            self.mimeType = mimeType
            self.encryptionKey = encryptionKey
            self.streamInfo = streamInfo
            self.transitTierInfo = transitTierInfo
            self.mediaName = mediaName
            self.mediaTierInfo = mediaTierInfo
            self.thumbnailMediaTierInfo = thumbnailMediaTierInfo
            self.localRelativeFilePathThumbnail = localRelativeFilePathThumbnail
        }

        public static func fromPointer(
            blurHash: String?,
            mimeType: String,
            encryptionKey: Data,
            transitTierInfo: TransitTierInfo
        ) -> ConstructionParams {
            return .init(
                blurHash: blurHash,
                mimeType: mimeType,
                encryptionKey: encryptionKey,
                streamInfo: nil,
                transitTierInfo: transitTierInfo,
                mediaName: nil,
                mediaTierInfo: nil,
                thumbnailMediaTierInfo: nil,
                localRelativeFilePathThumbnail: nil
            )
        }

        public static func fromStream(
            blurHash: String?,
            mimeType: String,
            encryptionKey: Data,
            streamInfo: StreamInfo,
            mediaName: String
        ) -> ConstructionParams {
            return .init(
                blurHash: blurHash,
                mimeType: mimeType,
                encryptionKey: encryptionKey,
                streamInfo: streamInfo,
                transitTierInfo: nil,
                mediaName: mediaName,
                mediaTierInfo: nil,
                thumbnailMediaTierInfo: nil,
                localRelativeFilePathThumbnail: nil
            )
        }

        public static func fromBackup(
            blurHash: String?,
            mimeType: String,
            encryptionKey: Data,
            transitTierInfo: TransitTierInfo?,
            mediaName: String,
            mediaTierInfo: MediaTierInfo?,
            thumbnailMediaTierInfo: ThumbnailMediaTierInfo?
        ) -> ConstructionParams {
            return .init(
                blurHash: blurHash,
                mimeType: mimeType,
                encryptionKey: encryptionKey,
                streamInfo: nil,
                transitTierInfo: transitTierInfo,
                mediaName: mediaName,
                mediaTierInfo: mediaTierInfo,
                thumbnailMediaTierInfo: thumbnailMediaTierInfo,
                localRelativeFilePathThumbnail: nil
            )
        }
    }
}
