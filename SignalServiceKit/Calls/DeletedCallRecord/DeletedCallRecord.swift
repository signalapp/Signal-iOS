//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import GRDB

/// A record representing a ``CallRecord`` that was deleted.
///
/// When a ``CallRecord`` is deleted, a ``DeletedCallRecord`` is inserted in its
/// place. This allows us to track that the record for a given call was deleted;
/// without this, we could delete the record for a call, then receive an update
/// for that call that results in us spuriosuly re-creating a record for that
/// call. Instead, the presence of a ``DeletedCallRecord`` allows us to instead
/// silently ignore updates for the call they refer to.
///
/// A ``DeletedCallRecord`` is kept for a short period – at the time of writing,
/// the period is 8h – after which point we assume the call it refers to will
/// have ended and it can be deleted. See ``DeletedCallRecordCleanupManager``
/// for that cleanup of "expired" ``DeletedCallRecord``s.
final class DeletedCallRecord: Codable, PersistableRecord, FetchableRecord {
    enum CodingKeys: String, CodingKey {
        case id
        case callIdString = "callId"
        case threadRowId
        case callLinkRowId
        case deletedAtTimestamp
    }

    public static let databaseTableName: String = "DeletedCallRecord"

    /// This record's SQLite row ID, if it represents a record that has already
    /// been inserted.
    private(set) var id: Int64?

    /// The unique ID of this call, shared across clients.
    let callId: UInt64

    let conversationId: CallRecord.ConversationID

    /// The timestamp at which the ``CallRecord`` this record represents was
    /// deleted.
    let deletedAtTimestamp: UInt64

    init(
        callId: UInt64,
        conversationId: CallRecord.ConversationID,
        deletedAtTimestamp: UInt64 = Date().ows_millisecondsSince1970
    ) {
        self.callId = callId
        self.conversationId = conversationId
        self.deletedAtTimestamp = deletedAtTimestamp
    }

    convenience init(callRecord: CallRecord) {
        self.init(
            callId: callRecord.callId,
            conversationId: callRecord.conversationId
        )
    }

    public func didInsert(with rowID: Int64, for column: String?) {
        id = rowID
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try container.decodeIfPresent(Int64.self, forKey: .id)
        self.callId = UInt64(try container.decode(String.self, forKey: .callIdString))!
        if let threadRowId = try container.decodeIfPresent(Int64.self, forKey: .threadRowId) {
            self.conversationId = .thread(threadRowId: threadRowId)
        } else {
            self.conversationId = .callLink(callLinkRowId: try container.decode(Int64.self, forKey: .callLinkRowId))
        }
        self.deletedAtTimestamp = UInt64(bitPattern: try container.decode(Int64.self, forKey: .deletedAtTimestamp))
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(self.id, forKey: .id)
        try container.encode(String(self.callId), forKey: .callIdString)
        switch self.conversationId {
        case .thread(let threadRowId):
            try container.encode(threadRowId, forKey: .threadRowId)
        case .callLink(let callLinkRowId):
            try container.encode(callLinkRowId, forKey: .callLinkRowId)
        }
        try container.encode(Int64(bitPattern: self.deletedAtTimestamp), forKey: .deletedAtTimestamp)
    }
}

#if TESTABLE_BUILD

extension DeletedCallRecord {
    func matches(callRecord: CallRecord) -> Bool {
        return (
            self.callId == callRecord.callId
            && self.conversationId == callRecord.conversationId
        )
    }

    func matches(_ other: DeletedCallRecord) -> Bool {
        return (
            self.id == other.id
            && self.callId == other.callId
            && self.conversationId == other.conversationId
            && self.deletedAtTimestamp == other.deletedAtTimestamp
        )
    }
}

#endif
