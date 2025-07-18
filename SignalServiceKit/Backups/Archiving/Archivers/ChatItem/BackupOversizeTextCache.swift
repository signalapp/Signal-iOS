//
// Copyright 2025 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

public import GRDB

/// This table is used exclusively by backups to import/export inlined "oversize" text.
///
/// For Context: "oversize" text is when a message's body exceeds ``kOversizeTextMessageSizeThreshold`` bytes;
/// the full text (including the first ``kOversizeTextMessageSizeThreshold`` bytes) is represented as an Attachment
/// for purposes of message sending/receiving.
/// Backups have a separate, larger threshold (``BackupOversizeTextCache/maxTextLengthBytes``). All oversize
/// text attachments are truncated to this length and inlined in the backup proto (bytes past this length are simply dropped).
///
/// Because the _rest of the app_ represents oversize text as an attachment file on disk, but backups prefers not to do file i/o\*,
/// we instead write all inlined oversize text to this table to be used by import/export.
///
/// For export, we populate this table as part of backups, before opening the write tx. Population is incremental; we don't
/// wipe the table so we only need to populate any new oversize text atachments that got created since the last backup.
///
/// For import, we populate the table with inlined text from the backup, and block backup restore completion on then translating
/// all the inlined text into Attachment stream files after the backup write tx commits.
///
/// \* Two reasons to avoid file i/o
///   1. performance
///   2. during restore if we cancel/terminate the whole backup write transaction is rolled back but any file i/o we did
///     at the same time is not rolled back; we'd need a mechanism to clean up the files.
public struct BackupOversizeTextCache: Codable, FetchableRecord, MutablePersistableRecord {

    /// Every row in this table is limited to this many bytes (not characters) of text, in both
    /// the Swift model object and at the SQLite level.
    public static let maxTextLengthBytes = 128 * 1024

    public typealias IDType = Int64

    public private(set) var id: IDType?
    public let attachmentRowId: Attachment.IDType
    public let text: String

    fileprivate init(id: IDType?, attachmentRowId: Attachment.IDType, text: String) {
        self.id = id
        self.attachmentRowId = attachmentRowId
        self.text = text
    }

    // MARK: FetchableRecord

    public static var databaseTableName: String { "BackupOversizeTextCache" }

    // MARK: MutablePersistableRecord

    public mutating func didInsert(with rowID: Int64, for column: String?) {
        self.id = rowID
    }

    // MARK: Codable

    public enum CodingKeys: String, CodingKey {
        case id
        case attachmentRowId
        case text
    }
}
