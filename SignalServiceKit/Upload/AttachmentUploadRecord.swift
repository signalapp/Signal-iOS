//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
public import GRDB

/// Represents an attempt to upload an attachment
public struct AttachmentUploadRecord: Codable, FetchableRecord, MutablePersistableRecord {
    public static let databaseTableName: String = "AttachmentUploadRecord"

    public enum SourceType: Int, Codable {
        case transit
        case media
        case thumbnail
    }

    var sqliteId: Attachment.IDType?

    var sourceType: SourceType
    var attachmentId: Attachment.Record.IDType
    var uploadForm: Upload.Form?
    var uploadFormTimestamp: UInt64?
    var localMetadata: Upload.LocalUploadMetadata?
    var uploadSessionUrl: URL?
    var attempt: UInt32 = 0

    public enum CodingKeys: String, CodingKey {
        case sqliteId = "id"
        case sourceType
        case attachmentId
        case uploadForm
        case uploadFormTimestamp
        case localMetadata
        case uploadSessionUrl
        case attempt
    }

    mutating public func didInsert(with rowID: Int64, for column: String?) {
        sqliteId = rowID
    }
}
