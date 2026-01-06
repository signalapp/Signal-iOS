//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
public import GRDB

/// Represents "orphaned" files that one belonged to an Attachment that has since been deleted.
/// Consumers of this table should delete the associate file(s) and _then_ delete the row from this table.
public struct OrphanedAttachmentRecord: Codable, FetchableRecord, PersistableRecord {

    public typealias RowId = Int64

    let id: RowId
    /// If true, the files in question are going to be uses for a as-yet-uncreated attachment.
    /// We want to delete these if creation fails, but for these (and only these) we want to
    /// wait a bit to give attachment creation a chance to succeed first.
    var isPendingAttachment: Bool
    let localRelativeFilePath: String?
    let localRelativeFilePathThumbnail: String?
    let localRelativeFilePathAudioWaveform: String?
    let localRelativeFilePathVideoStillFrame: String?

    // MARK: - Coding Keys

    public enum CodingKeys: String, CodingKey {
        case id
        case isPendingAttachment
        case localRelativeFilePath
        case localRelativeFilePathThumbnail
        case localRelativeFilePathAudioWaveform
        case localRelativeFilePathVideoStillFrame
    }

    // MARK: - MutablePersistableRecord

    public static let databaseTableName: String = "OrphanedAttachment"

    // MARK: - Insertion

    public struct InsertableRecord {
        let isPendingAttachment: Bool
        let localRelativeFilePath: String?
        let localRelativeFilePathThumbnail: String?
        let localRelativeFilePathAudioWaveform: String?
        let localRelativeFilePathVideoStillFrame: String?
    }

    static func insertRecord(_ insertableRecord: InsertableRecord, tx: DBWriteTransaction) -> Self {
        return failIfThrows {
            return try OrphanedAttachmentRecord.fetchOne(
                tx.database,
                sql: """
                INSERT INTO \(Self.databaseTableName) (
                    \(CodingKeys.isPendingAttachment.rawValue),
                    \(CodingKeys.localRelativeFilePath.rawValue),
                    \(CodingKeys.localRelativeFilePathThumbnail.rawValue),
                    \(CodingKeys.localRelativeFilePathAudioWaveform.rawValue),
                    \(CodingKeys.localRelativeFilePathVideoStillFrame.rawValue)
                ) VALUES (?, ?, ?, ?, ?) RETURNING *
                """,
                arguments: [
                    insertableRecord.isPendingAttachment,
                    insertableRecord.localRelativeFilePath,
                    insertableRecord.localRelativeFilePathThumbnail,
                    insertableRecord.localRelativeFilePathAudioWaveform,
                    insertableRecord.localRelativeFilePathVideoStillFrame,
                ],
            )!
        }
    }
}
