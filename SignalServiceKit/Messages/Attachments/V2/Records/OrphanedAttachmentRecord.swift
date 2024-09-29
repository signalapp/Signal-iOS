//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
public import GRDB

/// Represents "orphaned" files that one belonged to an Attachment that has since been deleted.
/// Consumers of this table should delete the associate file(s) and _then_ delete the row from this table.
public struct OrphanedAttachmentRecord: Codable, FetchableRecord, MutablePersistableRecord {

    public typealias IDType = Int64

    var sqliteId: IDType?
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
        case sqliteId = "id"
        case isPendingAttachment = "isPendingAttachment"
        case localRelativeFilePath
        case localRelativeFilePathThumbnail
        case localRelativeFilePathAudioWaveform
        case localRelativeFilePathVideoStillFrame
    }

    // MARK: - MutablePersistableRecord

    public static let databaseTableName: String = "OrphanedAttachment"

    public mutating func didInsert(with rowID: Int64, for column: String?) {
        self.sqliteId = rowID
    }

    // MARK: - Initializers

    internal init(
        sqliteId: IDType? = nil,
        isPendingAttachment: Bool = false,
        localRelativeFilePath: String?,
        localRelativeFilePathThumbnail: String?,
        localRelativeFilePathAudioWaveform: String?,
        localRelativeFilePathVideoStillFrame: String?
    ) {
        self.sqliteId = sqliteId
        self.isPendingAttachment = isPendingAttachment
        self.localRelativeFilePath = localRelativeFilePath
        self.localRelativeFilePathThumbnail = localRelativeFilePathThumbnail
        self.localRelativeFilePathAudioWaveform = localRelativeFilePathAudioWaveform
        self.localRelativeFilePathVideoStillFrame = localRelativeFilePathVideoStillFrame
    }
}
