//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import GRDB

/// Represents "orphaned" files that one belonged to an Attachment that has since been deleted.
/// Consumers of this table should delete the associate file(s) and _then_ delete the row from this table.
public struct OrphanedAttachmentRecord: Codable, FetchableRecord, MutablePersistableRecord {

    var sqliteId: Int64?
    let localRelativeFilePath: String?
    let localRelativeFilePathThumbnail: String?
    let localRelativeFilePathAudioWaveform: String?
    let localRelativeFilePathVideoStillFrame: String?

    // MARK: - Coding Keys

    public enum CodingKeys: String, CodingKey {
        case sqliteId = "id"
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
        sqliteId: Int64? = nil,
        localRelativeFilePath: String?,
        localRelativeFilePathThumbnail: String?,
        localRelativeFilePathAudioWaveform: String?,
        localRelativeFilePathVideoStillFrame: String?
    ) {
        self.sqliteId = sqliteId
        self.localRelativeFilePath = localRelativeFilePath
        self.localRelativeFilePathThumbnail = localRelativeFilePathThumbnail
        self.localRelativeFilePathAudioWaveform = localRelativeFilePathAudioWaveform
        self.localRelativeFilePathVideoStillFrame = localRelativeFilePathVideoStillFrame
    }
}
