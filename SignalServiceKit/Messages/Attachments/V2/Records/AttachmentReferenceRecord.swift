//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import GRDB

extension AttachmentReference {

    public struct MessageAttachmentReferenceRecord: Codable, PersistableRecord, FetchableRecord {

        let ownerType: UInt32
        let ownerRowId: Int64
        let attachmentRowId: Int64
        let receivedAtTimestamp: UInt64
        let contentType: UInt32?
        let renderingFlag: UInt32
        let idInMessage: String?
        let orderInMessage: UInt32?
        let threadRowId: Int64
        let caption: String?
        let sourceFilename: String?
        let sourceUnencryptedByteCount: UInt32?
        let sourceMediaHeightPixels: UInt32?
        let sourceMediaWidthPixels: UInt32?
        let stickerPackId: Data?
        let stickerId: UInt32?

        // MARK: - Coding Keys

        public enum CodingKeys: String, CodingKey {
            case ownerType
            case ownerRowId
            case attachmentRowId
            case receivedAtTimestamp
            case contentType
            case renderingFlag
            case idInMessage
            case orderInMessage
            case threadRowId
            case caption
            case sourceFilename
            case sourceUnencryptedByteCount
            case sourceMediaHeightPixels
            case sourceMediaWidthPixels
            case stickerPackId
            case stickerId
        }

        // MARK: - PersistableRecord

        public static let databaseTableName: String = "MessageAttachmentReference"
    }

    public struct StoryMessageAttachmentReferenceRecord: Codable, PersistableRecord, FetchableRecord {

        let ownerType: UInt32
        let ownerRowId: Int64
        let attachmentRowId: Int64
        let shouldLoop: Bool
        let caption: String?
        let captionBodyRanges: Data?
        let sourceFilename: String?
        let sourceUnencryptedByteCount: UInt32?
        let sourceMediaHeightPixels: UInt32?
        let sourceMediaWidthPixels: UInt32?

        // MARK: - Coding Keys

        public enum CodingKeys: String, CodingKey {
            case ownerType
            case ownerRowId
            case attachmentRowId
            case shouldLoop
            case caption
            case captionBodyRanges
            case sourceFilename
            case sourceUnencryptedByteCount
            case sourceMediaHeightPixels
            case sourceMediaWidthPixels
        }

        // MARK: - PersistableRecord

        public static let databaseTableName: String = "StoryMessageAttachmentReference"
    }

    public struct ThreadAttachmentReferenceRecord: Codable, PersistableRecord, FetchableRecord {

        let ownerRowId: Int64?
        let attachmentRowId: Int64
        let creationTimestamp: UInt64

        // MARK: - Coding Keys

        public enum CodingKeys: String, CodingKey {
            case ownerRowId
            case attachmentRowId
            case creationTimestamp
        }

        // MARK: - PersistableRecord

        public static let databaseTableName: String = "ThreadAttachmentReference"
    }
}
