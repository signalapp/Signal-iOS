//
// Copyright 2025 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
public import GRDB
import LibSignalClient

/// A Sender Key, either for ourselves or somebody else.
public struct SenderKeyRecord: Codable, FetchableRecord, PersistableRecord {
    public static let databaseTableName: String = "SenderKey"
    typealias RowId = Int64

    let id: RowId
    let ownerRecipientId: SignalRecipient.RowId
    let ownerDeviceId: DeviceId
    let distributionId: UUID
    let deletionType: DeletionType
    var insertedAt: Int64
    var serializedRecord: Data

    public var insertedAtDate: Date {
        set { self.insertedAt = Int64(newValue.timeIntervalSince1970) }
        get { Date(timeIntervalSince1970: TimeInterval(self.insertedAt)) }
    }

    public enum DeletionType: Int64, Codable {
        /// A Sender Key for the current user/device, used for sending. Because we
        /// own this key, we can delete it whenever we want.
        case thisDevice = 0

        /// A Sender Key from some other device (either an entirely different user
        /// or one of our linked devices). In practice, we don't use Sender Keys to
        /// send messages to ourselves, so it's always another user.
        case otherDevice = 1
    }

    enum CodingKeys: String, CodingKey {
        case id
        case ownerRecipientId
        case ownerDeviceId
        case distributionId
        case deletionType
        case insertedAt
        case serializedRecord
    }

    enum Columns {
        static let id = Column(CodingKeys.id.rawValue)
        static let ownerRecipientId = Column(CodingKeys.ownerRecipientId.rawValue)
        static let ownerDeviceId = Column(CodingKeys.ownerDeviceId.rawValue)
        static let distributionId = Column(CodingKeys.distributionId.rawValue)
        static let deletionType = Column(CodingKeys.deletionType.rawValue)
        static let insertedAt = Column(CodingKeys.insertedAt.rawValue)
        static let serializedRecord = Column(CodingKeys.serializedRecord.rawValue)
    }

    static func insertRecord(
        ownerRecipientId: SignalRecipient.RowId,
        ownerDeviceId: DeviceId,
        distributionId: UUID,
        deletionType: DeletionType,
        insertedAtDate: Date,
        serializedRecord: Data,
        tx: DBWriteTransaction,
    ) -> Self {
        return failIfThrows {
            return try Self.fetchOne(
                tx.database,
                sql: """
                INSERT INTO \(SenderKeyRecord.databaseTableName) (
                    \(Columns.ownerRecipientId.name),
                    \(Columns.ownerDeviceId.name),
                    \(Columns.distributionId.name),
                    \(Columns.deletionType.name),
                    \(Columns.insertedAt.name),
                    \(Columns.serializedRecord.name)
                ) VALUES (?, ?, ?, ?, ?, ?) RETURNING *
                """,
                arguments: [
                    ownerRecipientId,
                    ownerDeviceId.rawValue,
                    distributionId,
                    deletionType.rawValue,
                    Int64(insertedAtDate.timeIntervalSince1970),
                    serializedRecord,
                ],
            ).owsFailUnwrap("must return value or error")
        }
    }
}

// MARK: -

/// Indicates to whom we've sent a Sender Key Distribution Message (SKDM).
///
/// There is a 1:N relationship between SenderKeyRecord and this record,
/// where N is "every device for every recipient".
///
/// The devices stored in this record are ready to decrypt messages we send
/// using the Sender Key. Before using a Sender Key, we must ensure the
/// intended recipients have received a copy of the Sender Key. In the
/// common case, all intended recipients will already have the Sener Key,
/// and we can move immediately to the multi-recipient endpoint. In the less
/// common case, we must send a Sender Key Distribution Message (SKDM) to
/// each recipient individually before using the multi-recipient endpoint.
struct SenderKeySentToDeviceRecord: Codable, FetchableRecord, PersistableRecord {
    static let databaseTableName: String = "SenderKeySentToDevice"

    static let persistenceConflictPolicy = PersistenceConflictPolicy(insert: .replace, update: .abort)

    /// The row ID of the Sender Key we distributed.
    ///
    /// We create SentToDevice records when we distribute a Sender Key to
    /// somebody else. In practice, therefore, `senderKeyId` will always refer
    /// to one of our own Sender Keys.
    let senderKeyId: SenderKeyRecord.RowId

    /// The row ID of the recipient to whom we distributed our Sender Key.
    let recipientId: SignalRecipient.RowId

    /// The device ID of the recipient to whom we distributed our Sender Key.
    let deviceId: DeviceId

    /// The registration ID of the recipient at the time we distributed our
    /// Sender Key. If the registration ID changes, we distribute an updated
    /// copy of our Sender Key to avoid a decryption/resend request cycle.
    let registrationId: UInt32

    enum CodingKeys: String, CodingKey {
        case senderKeyId
        case recipientId
        case deviceId
        case registrationId
    }

    enum Columns {
        static let senderKeyId = Column(CodingKeys.senderKeyId.rawValue)
        static let recipientId = Column(CodingKeys.recipientId.rawValue)
        static let deviceId = Column(CodingKeys.deviceId.rawValue)
        static let registrationId = Column(CodingKeys.registrationId.rawValue)
    }
}

// MARK: -

public struct SenderKeyStore {
    func resetDeliveryRecord(
        senderKeyId: SenderKeyRecord.RowId,
        recipientId: SignalRecipient.RowId,
        tx: DBWriteTransaction,
    ) {
        let deleteQuery = SenderKeySentToDeviceRecord
            .filter(SenderKeySentToDeviceRecord.Columns.senderKeyId == senderKeyId)
            .filter(SenderKeySentToDeviceRecord.Columns.recipientId == recipientId)
        failIfThrows {
            try deleteQuery.deleteAll(tx.database)
        }
    }

    func upsertSentToRecord(
        senderKeyId: SenderKeyRecord.RowId,
        recipientId: SignalRecipient.RowId,
        deviceId: DeviceId,
        registrationId: UInt32,
        tx: DBWriteTransaction,
    ) throws(ConstraintError) {
        try failIfThrowsUnlessConstraintError {
            try SenderKeySentToDeviceRecord(
                senderKeyId: senderKeyId,
                recipientId: recipientId,
                deviceId: deviceId,
                registrationId: registrationId,
            ).insert(tx.database)
        }
    }

    func fetchSentToRecords(senderKeyId: SenderKeyRecord.RowId, tx: DBReadTransaction) -> [SenderKeySentToDeviceRecord] {
        let fetchQuery = SenderKeySentToDeviceRecord
            .filter(SenderKeySentToDeviceRecord.Columns.senderKeyId == senderKeyId)
        return failIfThrows { try fetchQuery.fetchAll(tx.database) }
    }

    public func fetchOldestSenderKeyRecord(
        deletionType: SenderKeyRecord.DeletionType,
        tx: DBReadTransaction,
    ) -> SenderKeyRecord? {
        let fetchQuery = SenderKeyRecord
            .filter(SenderKeyRecord.Columns.deletionType == deletionType.rawValue)
            .order(SenderKeyRecord.Columns.insertedAt.asc)
        return failIfThrows { try fetchQuery.fetchOne(tx.database) }
    }

    func fetchSenderKeyRecord(
        recipientId: SignalRecipient.RowId,
        deviceId: DeviceId,
        distributionId: UUID,
        tx: DBReadTransaction,
    ) -> SenderKeyRecord? {
        let fetchQuery = SenderKeyRecord
            .filter(SenderKeyRecord.Columns.ownerRecipientId == recipientId)
            .filter(SenderKeyRecord.Columns.ownerDeviceId == deviceId.rawValue)
            .filter(SenderKeyRecord.Columns.distributionId == distributionId.data)
        return failIfThrows { try fetchQuery.fetchOne(tx.database) }
    }

    @discardableResult
    func upsertSenderKey(
        _ senderKey: LibSignalClient.SenderKeyRecord,
        forRecipientId recipientId: SignalRecipient.RowId,
        deviceId: DeviceId,
        distributionId: UUID,
        deletionType: SenderKeyRecord.DeletionType,
        shouldUpdateInsertedAtDate: Bool,
        dateProvider: DateProvider,
        tx: DBWriteTransaction,
    ) -> SenderKeyRecord {
        let serializedRecord = senderKey.serialize()
        let senderKeyRecord = fetchSenderKeyRecord(
            recipientId: recipientId,
            deviceId: deviceId,
            distributionId: distributionId,
            tx: tx,
        )
        if var senderKeyRecord {
            senderKeyRecord.serializedRecord = serializedRecord
            if shouldUpdateInsertedAtDate {
                senderKeyRecord.insertedAtDate = dateProvider()
            }
            failIfThrows { try senderKeyRecord.update(tx.database) }
            return senderKeyRecord
        } else {
            return SenderKeyRecord.insertRecord(
                ownerRecipientId: recipientId,
                ownerDeviceId: deviceId,
                distributionId: distributionId,
                deletionType: deletionType,
                insertedAtDate: dateProvider(),
                serializedRecord: serializedRecord,
                tx: tx,
            )
        }
    }
}
