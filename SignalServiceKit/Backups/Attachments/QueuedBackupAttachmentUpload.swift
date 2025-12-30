//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
public import GRDB

/// Record type for BackupAttachmentUploadQueue rows.
///
/// The table is the source of truth on what attachments need uploading to the media tier.
///
/// We insert into this table when...
/// 1. We create a new attachment stream
/// 2. We download an attachment pointer (that isn't already backed up)
/// 3. We query the server for backed up attachments and discover one we thought
///   was uploaded, isn't.
/// We remove from this table when...
/// 1. We upload to media tier (duh)
/// 2. We delete the attachment (using foreign key cascade rules)
/// 3. We query the server for backed up attachments and discover one is already backed up
///
/// We DO NOT clear this table based on subscription state changes; though we only actually run
/// the queue and upload when paid tier, we keep the queue (and in fact continue to populate it with
/// new attachments per (1)  and (2)) even while free tier.
///
/// When we're paid tier, we run the queue by popping off this table one at a time and delegating upload
/// to AttachmentUploadManager which itself has its own AttachmentUploadQueue.
///
/// This qeue ensures proper upload ordering; AttachmentUploadQueue uploads FIFO,
/// but we want to upload things we archive in the backup in owner timestamp order (newest first).
/// This table allows us to do that reordering after we are done processing the backup in its normal order.
public struct QueuedBackupAttachmentUpload: Codable, FetchableRecord, MutablePersistableRecord {

    public typealias IDType = Int64

    /// Sqlite row id
    public private(set) var id: IDType?

    /// Row id of the associated attachment (the one we want to upload) in the Attachments table.
    public let attachmentRowId: Attachment.IDType

    /// The highest priority owner among all references to this attachment.
    /// Newer owners are prioritized, with thread wallpapers counted as newest (encoded as null).
    ///
    /// It is possible for this to get out of date if e.g. some attachment has multiple owners
    /// and the highest "priority" owner is deleted; we wouldn't update the value(s) in this
    /// table. This is fine; the upload will stay higher priority than it _should_ be but this
    /// isn't the end of the world and lets us ignore complex update cascades.
    public var highestPriorityOwnerType: OwnerType

    /// If true, this is an upload of the fullsize version of the attachment.
    /// Otherwise it is an upload of the thumbnail size.
    /// A single attachment can have both enqueued at the same time.
    public let isFullsize: Bool

    /// Estimated byte count for the upload, including padding and encryption overhead.
    /// Should NOT be considered definitively accurate, but okay to use
    /// for estimation in UI and such.
    public let estimatedByteCount: UInt32

    /// Number of retries (due to e.g. network failures).
    public var numRetries: UInt32
    /// Minimum timestamp at which this upload can be retried (if it failed in the past)
    @DBUInt64
    public var minRetryTimestamp: UInt64

    public var state: State

    public enum OwnerType {
        case threadWallpaper
        /// Timestamp of the newest message that owns this attachment.
        /// Used to determine priority of upload (ordering of the pop-off-queue query).
        case message(timestamp: UInt64)
    }

    public enum State: Int, Codable {
        case ready = 0
        case done = 1
    }

    public init(
        id: Int64? = nil,
        attachmentRowId: Attachment.IDType,
        highestPriorityOwnerType: OwnerType,
        isFullsize: Bool,
        estimatedByteCount: UInt32,
        numRetries: UInt32 = 0,
        minRetryTimestamp: UInt64 = 0,
        state: State = .ready,
    ) {
        self.id = id
        self.attachmentRowId = attachmentRowId
        self.highestPriorityOwnerType = highestPriorityOwnerType
        self.isFullsize = isFullsize
        self.estimatedByteCount = estimatedByteCount
        self.numRetries = numRetries
        self._minRetryTimestamp = DBUInt64(wrappedValue: minRetryTimestamp)
        self.state = state
    }

    // MARK: FetchableRecord

    public static var databaseTableName: String { "BackupAttachmentUploadQueue" }

    // MARK: MutablePersistableRecord

    public mutating func didInsert(with rowID: Int64, for column: String?) {
        self.id = rowID
    }

    // MARK: - Codable

    public enum CodingKeys: String, CodingKey {
        case id
        case attachmentRowId
        case maxOwnerTimestamp
        case isFullsize
        case estimatedByteCount
        case numRetries
        case minRetryTimestamp
        case state
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try container.decode(Int64.self, forKey: .id)
        self.attachmentRowId = try container.decode(Attachment.IDType.self, forKey: .attachmentRowId)
        let maxOwnerTimestamp = try container.decodeIfPresent(Int64.self, forKey: .maxOwnerTimestamp)
            .map { UInt64(bitPattern: $0) }
        if let maxOwnerTimestamp {
            self.highestPriorityOwnerType = .message(timestamp: maxOwnerTimestamp)
        } else {
            self.highestPriorityOwnerType = .threadWallpaper
        }
        self.isFullsize = try container.decode(Bool.self, forKey: .isFullsize)
        self.estimatedByteCount = try container.decode(UInt32.self, forKey: .estimatedByteCount)
        self.numRetries = try container.decode(UInt32.self, forKey: .numRetries)
        self.minRetryTimestamp = try container.decode(UInt64.self, forKey: .minRetryTimestamp)
        self.state = try container.decode(State.self, forKey: .state)
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(attachmentRowId, forKey: .attachmentRowId)
        switch highestPriorityOwnerType {
        case .threadWallpaper:
            try container.encodeNil(forKey: .maxOwnerTimestamp)
        case .message(let timestamp):
            let intValue = Int64(bitPattern: timestamp)
            try container.encode(intValue, forKey: .maxOwnerTimestamp)
        }
        try container.encode(isFullsize, forKey: .isFullsize)
        try container.encode(estimatedByteCount, forKey: .estimatedByteCount)
        try container.encode(numRetries, forKey: .numRetries)
        try container.encode(minRetryTimestamp, forKey: .minRetryTimestamp)
        try container.encode(state, forKey: .state)
    }
}
