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
    public let mediaName: String
    public let type: `Type`

    /// WARNING: these values are hardcoded into triggers in the sql schema; if they
    /// change those triggers need to be recreated in a migration.
    public enum `Type`: Int, Codable {
        case fullsize = 0
        case thumbnail = 1
    }

    public init(
        id: Int64? = nil,
        cdnNumber: UInt32,
        mediaName: String,
        type: `Type`
    ) {
        self.id = id
        self.cdnNumber = cdnNumber
        self.mediaName = mediaName
        self.type = type
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
        case type
    }
}
