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
        case deletedAtTimestamp
    }

    public static let databaseTableName: String = "DeletedCallRecord"

    /// This record's SQLite row ID, if it represents a record that has already
    /// been inserted.
    private(set) var id: Int64?

    /// A string representation of the UInt64 ID for this call.
    ///
    /// SQLite stores values as Int64 and we've had issues with UInt64 and GRDB,
    /// so as a workaround we store it as a string.
    private let callIdString: String

    /// The unique ID of this call, shared across clients.
    var callId: UInt64 { return UInt64(callIdString)! }

    /// The SQLite row ID of the thread this call belongs to.
    let threadRowId: Int64

    /// The timestamp at which the ``CallRecord`` this record represents was
    /// deleted.
    let deletedAtTimestamp: UInt64

    init(
        callId: UInt64,
        threadRowId: Int64,
        deletedAtTimestamp: UInt64 = Date().ows_millisecondsSince1970
    ) {
        self.callIdString = String(callId)
        self.threadRowId = threadRowId
        self.deletedAtTimestamp = deletedAtTimestamp
    }

    convenience init(callRecord: CallRecord) {
        self.init(
            callId: callRecord.callId,
            threadRowId: callRecord.threadRowId
        )
    }

    public func didInsert(with rowID: Int64, for column: String?) {
        id = rowID
    }
}

#if TESTABLE_BUILD

extension DeletedCallRecord {
    func matches(callRecord: CallRecord) -> Bool {
        if
            callId == callRecord.callId,
            threadRowId == callRecord.threadRowId
        {
            return true
        }

        return false
    }

    func matches(_ other: DeletedCallRecord) -> Bool {
        if
            id == other.id,
            callId == other.callId,
            threadRowId == other.threadRowId,
            deletedAtTimestamp == other.deletedAtTimestamp
        {
            return true
        }

        return false
    }
}

#endif
