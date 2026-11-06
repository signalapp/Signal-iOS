//
// Copyright 2026 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import LibSignalClient
import Testing

@testable import SignalServiceKit

struct SenderKeyStoreTest {
    let db = InMemoryDB()
    let store = SenderKeyStore()
    let aci = Aci.randomForTesting()

    /// Sender key IDs are captured and used across transactions. If a Sender
    /// Key can be deleted and a new one created in its place (with the same
    /// ID), this may cause subsequent logic to refer to the wrong Sender Key.
    @Test
    func testNoIdReuse() throws {
        try db.write { tx in
            let recipient = try SignalRecipient.insertRecord(tx: tx)
            let senderKey1 = try upsertRandomSenderKey(recipientId: recipient.id, tx: tx)
            try senderKey1.delete(tx.database)
            let senderKey2 = try upsertRandomSenderKey(recipientId: recipient.id, tx: tx)
            #expect(senderKey1.id != senderKey2.id)
        }
    }

    /// We can redundantly distribute the Sender Key to devices that already
    /// have it when a recipient adds a new device to their account.
    @Test
    func testSentToRedundant() throws {
        try db.write { tx in
            let localRecipient = try SignalRecipient.insertRecord(tx: tx)
            let senderKey = try upsertRandomSenderKey(recipientId: localRecipient.id, tx: tx)
            let otherRecipient = try SignalRecipient.insertRecord(tx: tx)
            try store.upsertSentToRecord(
                senderKeyId: senderKey.id,
                recipientId: otherRecipient.id,
                deviceId: .primary,
                registrationId: 123,
                tx: tx,
            )
            try store.upsertSentToRecord(
                senderKeyId: senderKey.id,
                recipientId: otherRecipient.id,
                deviceId: .primary,
                registrationId: 124,
                tx: tx,
            )
            let sentToRecords = store.fetchSentToRecords(senderKeyId: senderKey.id, tx: tx)
            #expect(sentToRecords.map(\.registrationId) == [124])
        }
    }

    /// A SenderKey or Recipient might be deleted while we're distributing a
    /// Sender Key. This case should throw an error without crashing.
    @Test
    func testSentToConstraint() throws {
        try db.write { tx in
            let localRecipient = try SignalRecipient.insertRecord(tx: tx)
            let senderKey = try upsertRandomSenderKey(recipientId: localRecipient.id, tx: tx)
            let otherRecipient = try SignalRecipient.insertRecord(tx: tx)
            try store.upsertSentToRecord(
                senderKeyId: senderKey.id,
                recipientId: otherRecipient.id,
                deviceId: .primary,
                registrationId: 123,
                tx: tx,
            )
            #expect(throws: ConstraintError.self) {
                try store.upsertSentToRecord(
                    senderKeyId: senderKey.id + 1,
                    recipientId: otherRecipient.id,
                    deviceId: .primary,
                    registrationId: 123,
                    tx: tx,
                )
            }
            #expect(throws: ConstraintError.self) {
                try store.upsertSentToRecord(
                    senderKeyId: senderKey.id,
                    recipientId: otherRecipient.id + 1,
                    deviceId: .primary,
                    registrationId: 123,
                    tx: tx,
                )
            }
        }
    }

    /// Newly-distributed or generated Sender Keys should reset the `insertedAt`
    /// timestamp (which is used to determine when they expire). Simply using a
    /// Sender Key doesn't update the timestamp.
    @Test
    func testInsertedAt() throws {
        try db.write { tx in
            let recipient = try SignalRecipient.insertRecord(tx: tx)
            let distributionId = UUID()
            let senderKeyV1 = try upsertRandomSenderKey(
                recipientId: recipient.id,
                distributionId: distributionId,
                dateProvider: { Date(timeIntervalSince1970: 1783520000) },
                tx: tx,
            )
            let senderKeyV2 = try upsertRandomSenderKey(
                recipientId: recipient.id,
                distributionId: distributionId,
                shouldUpdateInsertedAtDate: false,
                dateProvider: { Date(timeIntervalSince1970: 1783520001) },
                tx: tx,
            )
            #expect(senderKeyV1.insertedAt == senderKeyV2.insertedAt)
            #expect(senderKeyV1.insertedAt == store.fetchSenderKeyRecord(
                recipientId: recipient.id,
                deviceId: .primary,
                distributionId: distributionId,
                tx: tx,
            )!.insertedAt)
            let senderKeyV3 = try upsertRandomSenderKey(
                recipientId: recipient.id,
                distributionId: distributionId,
                shouldUpdateInsertedAtDate: true,
                dateProvider: { Date(timeIntervalSince1970: 1783520002) },
                tx: tx,
            )
            #expect(senderKeyV1.insertedAt < senderKeyV3.insertedAt)
            #expect(senderKeyV1.insertedAt < store.fetchSenderKeyRecord(
                recipientId: recipient.id,
                deviceId: .primary,
                distributionId: distributionId,
                tx: tx,
            )!.insertedAt)
        }
    }

    private func upsertRandomSenderKey(
        recipientId: SignalRecipient.RowId,
        distributionId: UUID = UUID(),
        shouldUpdateInsertedAtDate: Bool = true,
        dateProvider: DateProvider = { Date() },
        tx: DBWriteTransaction,
    ) throws -> SignalServiceKit.SenderKeyRecord {
        return store.upsertSenderKey(
            try MockSenderKeyStore.randomSendingKey(aci: aci, deviceId: .primary, distributionId: distributionId),
            forRecipientId: recipientId,
            deviceId: .primary,
            distributionId: distributionId,
            deletionType: .thisDevice,
            shouldUpdateInsertedAtDate: shouldUpdateInsertedAtDate,
            dateProvider: dateProvider,
            tx: tx,
        )
    }
}

// MARK: -

class MockSenderKeyStore: LibSignalClient.SenderKeyStore {
    var serializedRecords = [String: Data]()

    func storeSenderKey(
        from sender: ProtocolAddress,
        distributionId: UUID,
        record: LibSignalClient.SenderKeyRecord,
        context: any StoreContext,
    ) throws {
        let key = "\(sender).\(distributionId)"
        serializedRecords[key] = record.serialize()
    }

    func loadSenderKey(
        from sender: ProtocolAddress,
        distributionId: UUID,
        context: any StoreContext,
    ) throws -> LibSignalClient.SenderKeyRecord? {
        let key = "\(sender).\(distributionId)"
        guard let serializedRecord = serializedRecords[key] else {
            return nil
        }
        return try LibSignalClient.SenderKeyRecord(bytes: serializedRecord)
    }

    private func buildSenderKeyDistributionMessage(
        aci: Aci,
        deviceId: DeviceId,
        distributionId: UUID,
    ) throws -> LibSignalClient.SenderKeyDistributionMessage {
        return try LibSignalClient.SenderKeyDistributionMessage(
            from: ProtocolAddress(aci, deviceId: deviceId),
            distributionId: distributionId,
            store: self,
            context: NullContext(),
        )
    }

    static func randomSendingKey(aci: Aci, deviceId: DeviceId, distributionId: UUID) throws -> LibSignalClient.SenderKeyRecord {
        let mockStore = MockSenderKeyStore()
        _ = try mockStore.buildSenderKeyDistributionMessage(aci: aci, deviceId: deviceId, distributionId: distributionId)
        let serializedRecord = mockStore.serializedRecords.values.first!
        return try! LibSignalClient.SenderKeyRecord(bytes: serializedRecord)
    }

    static func randomReceivingKey(aci: Aci, deviceId: DeviceId, distributionId: UUID) throws -> LibSignalClient.SenderKeyRecord {
        let sendingStore = MockSenderKeyStore()
        let receivingStore = MockSenderKeyStore()
        try processSenderKeyDistributionMessage(
            sendingStore.buildSenderKeyDistributionMessage(aci: aci, deviceId: deviceId, distributionId: distributionId),
            from: ProtocolAddress(aci, deviceId: deviceId),
            store: receivingStore,
            context: NullContext(),
        )
        let serializedRecord = receivingStore.serializedRecords.values.first!
        return try! LibSignalClient.SenderKeyRecord(bytes: serializedRecord)
    }
}
