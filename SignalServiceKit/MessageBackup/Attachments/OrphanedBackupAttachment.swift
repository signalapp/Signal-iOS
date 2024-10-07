//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
public import GRDB

/// Record type for OrphanedBackupAttachment table rows.
///
/// The table is used to enqueue locally deleted attachments to be deleted off the media tier cdn.
public struct OrphanedBackupAttachment: Codable, FetchableRecord, MutablePersistableRecord {

    public typealias IDType = Int64

    /// Sqlite row id
    public private(set) var id: IDType?
    /// The cdn number in which the attachment lives on the media tier.
    public let cdnNumber: UInt32
    /// The media name of the attachment (used to derive the cdn url).
    /// Set when the attachment was orphaned locally, where we know
    /// the mediaName.
    public let mediaName: String?
    /// The mediaID of the attachment (derived from the mediaName).
    /// Set when the attachment was orphaned by discovering it on the
    /// server cdn without a corresponding local attachment; we have
    /// no way to map the mediaID back to the name.
    public let mediaId: Data?
    /// May be unknown if orphaned by discovering it on the server cdn;
    /// the server cannot distinguish thumbnails from fullsize.
    public let type: `Type`?

    /// WARNING: these values are hardcoded into triggers in the sql schema; if they
    /// change those triggers need to be recreated in a migration.
    public enum `Type`: Int, Codable {
        case fullsize = 0
        case thumbnail = 1
    }

    private init(
        id: Int64? = nil,
        cdnNumber: UInt32,
        mediaName: String?,
        mediaId: Data?,
        type: `Type`?
    ) {
        self.id = id
        self.cdnNumber = cdnNumber
        self.mediaName = mediaName
        self.mediaId = mediaId
        self.type = type
    }

    public static func locallyOrphaned(
        cdnNumber: UInt32,
        mediaName: String,
        type: `Type`
    ) -> OrphanedBackupAttachment {
        return OrphanedBackupAttachment(
            id: nil,
            cdnNumber: cdnNumber,
            mediaName: mediaName,
            mediaId: nil,
            type: type
        )
    }

    public static func discoveredOnServer(
        cdnNumber: UInt32,
        mediaId: Data
    ) -> OrphanedBackupAttachment {
        return OrphanedBackupAttachment(
            id: nil,
            cdnNumber: cdnNumber,
            mediaName: nil,
            mediaId: mediaId,
            type: nil
        )
    }

    // MARK: FetchableRecord

    public static var databaseTableName: String { "OrphanedBackupAttachment" }

    // MARK: MutablePersistableRecord

    public mutating func didInsert(with rowID: Int64, for column: String?) {
        self.id = rowID
    }

    // MARK: Codable

    public enum CodingKeys: String, CodingKey {
        case id
        case cdnNumber
        case mediaName
        case mediaId
        case type
    }
}
