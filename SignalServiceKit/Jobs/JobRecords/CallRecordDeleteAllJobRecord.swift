//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

public final class CallRecordDeleteAllJobRecord: JobRecord, FactoryInitializableFromRecordType {
    override class var jobRecordType: JobRecord.JobRecordType { .callRecordDeleteAll }

    /// Whether this job should send a "delete all" `CallLogEvent` sync message.
    /// - SeeAlso ``OutgoingCallLogEventSyncMessage``.
    let sendDeleteAllSyncMessage: Bool

    /// A stringified call ID of a ``CallRecord`` that represents the
    /// most-recent call that should be deleted by this job. The call ID itself
    /// is a `UInt64`, but SQLite can only store `Int64`, so we wrap it in a
    /// string to accomodate `UInt64` values greater than `Int64.max`.
    ///
    /// - SeeAlso ``CallRecord/callId``
    private let _deleteAllBeforeCallIdString: String?

    /// The call ID of a ``CallRecord`` that represents the most-recent call
    /// that should be deleted by this job.
    ///
    /// - Important
    /// This property will be `nil` for legacy job records, or jobs enqueued
    /// based on a legacy sync message, in which case we will fall back to
    /// `deleteAllBeforeTimestamp`.
    var deleteAllBeforeCallId: UInt64? {
        _deleteAllBeforeCallIdString.map { UInt64($0)! }
    }

    /// The call ID of a ``CallRecord`` that represents the most-recent call
    /// that should be deleted by this job.
    ///
    /// - Important
    /// This property will be `nil` for legacy job records, or jobs enqueued
    /// based on a legacy sync message, in which case we will fall back to
    /// `deleteAllBeforeTimestamp`.
    let deleteAllBeforeConversationId: Data?

    /// A "call began" timestamp before (and at) which all earlier calls should
    /// be deleted.
    let deleteAllBeforeTimestamp: UInt64

    init(
        sendDeleteAllSyncMessage: Bool,
        deleteAllBeforeCallId: UInt64?,
        deleteAllBeforeConversationId: Data?,
        deleteAllBeforeTimestamp: UInt64,
        failureCount: UInt = 0,
        status: Status = .ready
    ) {
        self.sendDeleteAllSyncMessage = sendDeleteAllSyncMessage
        self._deleteAllBeforeCallIdString = deleteAllBeforeCallId.map { String($0) }
        self.deleteAllBeforeConversationId = deleteAllBeforeConversationId
        self.deleteAllBeforeTimestamp = deleteAllBeforeTimestamp

        super.init(
            failureCount: failureCount,
            status: status
        )
    }

    required init(forRecordTypeFactoryInitializationFrom decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        sendDeleteAllSyncMessage = try container.decode(Bool.self, forKey: .sendDeleteAllSyncMessage)
        deleteAllBeforeTimestamp = try container.decode(UInt64.self, forKey: .deleteAllBeforeTimestamp)

        if
            let callIdString = try container.decodeIfPresent(String.self, forKey: .deleteAllBeforeCallId),
            let conversationId = try container.decodeIfPresent(Data.self, forKey: .deleteAllBeforeConversationId)
        {
            _deleteAllBeforeCallIdString = callIdString
            deleteAllBeforeConversationId = conversationId
        } else {
            _deleteAllBeforeCallIdString = nil
            deleteAllBeforeConversationId = nil
        }

        try super.init(baseClassDuringFactoryInitializationFrom: container.superDecoder())
    }

    override public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)

        try super.encode(to: container.superEncoder())

        try container.encode(sendDeleteAllSyncMessage, forKey: .sendDeleteAllSyncMessage)
        try container.encode(deleteAllBeforeTimestamp, forKey: .deleteAllBeforeTimestamp)

        if let _deleteAllBeforeCallIdString, let deleteAllBeforeConversationId {
            try container.encode(_deleteAllBeforeCallIdString, forKey: .deleteAllBeforeCallId)
            try container.encode(deleteAllBeforeConversationId, forKey: .deleteAllBeforeConversationId)
        }
    }
}
