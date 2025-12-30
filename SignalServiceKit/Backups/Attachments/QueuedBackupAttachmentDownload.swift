//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
public import GRDB

/// Record type for BackupAttachmentDownloadQueue rows.
///
/// The table is used only as an intermediary to ensure proper ordering. As we restore a backup,
/// we insert attachments that need downloading into this table first. Once we are done restoring,
/// we walk over this table in reverse order and insert rows into the AttachmentDownloadQueue table
/// for _actual_ downloading.
/// In this way we ensure proper download ordering; AttachmentDownloadQueue downloads FIFO,
/// but we want to download things we see in the backup in LIFO order. This table allows us to
/// do that reordering after we are done processing the backup in its normal order.
public struct QueuedBackupAttachmentDownload: Codable, FetchableRecord, MutablePersistableRecord {

    public typealias IDType = Int64

    /// Sqlite row id
    public var id: IDType?

    /// Row id of the associated attachment (the one we want to download) in the Attachments table.
    public let attachmentRowId: Attachment.IDType

    // If true, this row represents the download of a thumbnail, which
    // always comes from the media tier.
    // If false, represents the download of the fullsize attachment,
    // which may come from the media or transit tier.
    public let isThumbnail: Bool

    /// If true, we _believe_ this attachment can be downloaded from the media tier (and may also
    /// be downloadable from the transit tier, as a fallback).
    /// If false, only downloadable from the transit tier.
    /// Always true for thumbnails, as those only exist on media tier.
    public var canDownloadFromMediaTier: Bool

    /// Timestamp of the newest message that owns this attachment (or nil if non-message attachment).
    /// May get out of date with source; if the newest owner for an attachment is deleted we won't
    /// update this value in this table, but that just means the attachment has a higher sort priority
    /// than it otherwise would which is fine.
    @DBUInt64Optional
    public var maxOwnerTimestamp: UInt64?

    /// This timestamp should only be used to sort and to compare to the current time.
    /// It should NOT be interpreted as being the timestamp of the attachment or some owning
    /// message.
    /// We initialize this to (now - maxOwnerTimestamp) so that:
    /// 1. It is eligible to attempt
    /// 2. Newer attachments have lower values and therefore sorted first
    /// Because of this the timestamp value can be arbitrary, and in fact technically
    /// older attachments might have a lower value than newer ones, depending
    /// on the enqueue time relative to the attachment's timestamp. This is mostly
    /// fine as we will get to everything eventually and it keeps things simple.
    @DBUInt64
    public var minRetryTimestamp: UInt64

    public var numRetries: UInt8

    public var state: State

    public enum State: Int, Codable {
        /// We may download this in the future, but current state prevents us from doing so.
        /// Will transition to ready if state changes.
        case ineligible = 0
        /// Ready to download.
        case ready = 1
        /// Downloaded; maintained to keep track of already-downloaded byte count.
        case done = 2
    }

    /// Estimated byte count for the download.
    /// Should NOT be considered definitively accurate, but okay to use
    /// for estimation in UI and such.
    public let estimatedByteCount: UInt32

    // MARK: - API

    public init(
        id: Int64? = nil,
        attachmentRowId: Attachment.IDType,
        isThumbnail: Bool,
        canDownloadFromMediaTier: Bool,
        maxOwnerTimestamp: UInt64?,
        minRetryTimestamp: UInt64,
        state: State,
        estimatedByteCount: UInt32,
    ) {
        self.id = id
        self.attachmentRowId = attachmentRowId
        self.isThumbnail = isThumbnail
        self.canDownloadFromMediaTier = canDownloadFromMediaTier
        self._maxOwnerTimestamp = DBUInt64Optional(wrappedValue: maxOwnerTimestamp)
        self._minRetryTimestamp = DBUInt64(wrappedValue: minRetryTimestamp)
        self.numRetries = 0
        self.state = state
        self.estimatedByteCount = estimatedByteCount
    }

    // MARK: FetchableRecord

    public static var databaseTableName: String { "BackupAttachmentDownloadQueue" }

    // MARK: MutablePersistableRecord

    public mutating func didInsert(with rowID: Int64, for column: String?) {
        self.id = rowID
    }

    // MARK: Codable

    public enum CodingKeys: String, CodingKey {
        case id
        case attachmentRowId
        case isThumbnail
        case canDownloadFromMediaTier
        case maxOwnerTimestamp
        case minRetryTimestamp
        case numRetries
        case state
        case estimatedByteCount
    }
}
