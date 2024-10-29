//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

final class BulkDeleteInteractionJobRecord: JobRecord, FactoryInitializableFromRecordType {
    override class var jobRecordType: JobRecord.JobRecordType { .bulkDeleteInteractionJobRecord }

    /// The row ID of the most-recent addressable message before which we want
    /// to bulk-delete.
    let anchorMessageRowId: Int64
    /// If set, represents the row ID of the most-recent message (addressable or
    /// not) in the thread at the time a bulk-delete job was created for a "full
    /// thread delete". Note that this value may not be equivalent to
    /// ``anchorMessageRowId``, if the thread contains non-addressable messages
    /// newer than the anchor addressable message.
    ///
    /// This field is set if the bulk-delete represents a full thread deletion,
    /// and is `nil` otherwise.
    let fullThreadDeletionAnchorMessageRowId: Int64?
    /// The unique ID of the thread within which to bulk-delete.
    let threadUniqueId: String

    init(
        anchorMessageRowId: Int64,
        fullThreadDeletionAnchorMessageRowId: Int64?,
        threadUniqueId: String,
        failureCount: UInt = 0,
        status: Status = .ready
    ) {
        self.threadUniqueId = threadUniqueId
        self.fullThreadDeletionAnchorMessageRowId = fullThreadDeletionAnchorMessageRowId
        self.anchorMessageRowId = anchorMessageRowId

        super.init(
            failureCount: failureCount,
            status: status
        )
    }

    required init(forRecordTypeFactoryInitializationFrom decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        anchorMessageRowId = try container.decode(Int64.self, forKey: .BDIJR_anchorMessageRowId)
        fullThreadDeletionAnchorMessageRowId = try container.decodeIfPresent(Int64.self, forKey: .BDIJR_fullThreadDeletionAnchorMessageRowId)
        threadUniqueId = try container.decode(String.self, forKey: .BDIJR_threadUniqueId)

        try super.init(baseClassDuringFactoryInitializationFrom: container.superDecoder())
    }

    override public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)

        try super.encode(to: container.superEncoder())

        try container.encode(anchorMessageRowId, forKey: .BDIJR_anchorMessageRowId)
        try container.encodeIfPresent(fullThreadDeletionAnchorMessageRowId, forKey: .BDIJR_fullThreadDeletionAnchorMessageRowId)
        try container.encode(threadUniqueId, forKey: .BDIJR_threadUniqueId)
    }
}
