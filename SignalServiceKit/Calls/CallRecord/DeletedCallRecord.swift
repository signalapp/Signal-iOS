//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import GRDB

/// A record representing a ``CallRecord`` that was deleted.
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

    init(callId: UInt64, threadRowId: Int64, deletedAtTimestamp: UInt64) {
        self.callIdString = String(callId)
        self.threadRowId = threadRowId
        self.deletedAtTimestamp = deletedAtTimestamp
    }

    convenience init(deletedCallRecord: CallRecord) {
        self.init(
            callId: deletedCallRecord.callId,
            threadRowId: deletedCallRecord.threadRowId,
            deletedAtTimestamp: Date().ows_millisecondsSince1970
        )
    }

    public func didInsert(with rowID: Int64, for column: String?) {
        id = rowID
    }
}

#if TESTABLE_BUILD

extension DeletedCallRecord {
    func matches(
        _ other: DeletedCallRecord,
        ignoringDeletedAtTimestamp: Bool = false
    ) -> Bool {
        if
            id == other.id,
            callId == other.callId,
            threadRowId == other.threadRowId,
            (
                ignoringDeletedAtTimestamp ||
                deletedAtTimestamp == other.deletedAtTimestamp
            )
        {
            return true
        }

        return false
    }
}

#endif
