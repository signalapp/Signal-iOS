//
// Copyright 2021 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import LibSignalClient
import GRDB

class MessageSendLogObjC: NSObject {
    @objc
    @available(swift, obsoleted: 1.0)
    static func deleteAllPayloads(forInteraction interaction: TSInteraction, tx: SDSAnyWriteTransaction) {
        let messageSendLog = SSKEnvironment.shared.messageSendLogRef
        messageSendLog.deleteAllPayloadsForInteraction(interaction, tx: tx)
    }

    @objc
    @available(swift, obsoleted: 1.0)
    static func recordPayload(
        _ plaintext: Data,
        forMessageBeingSent message: TSOutgoingMessage,
        tx: SDSAnyWriteTransaction
    ) -> NSNumber? {
        let messageSendLog = SSKEnvironment.shared.messageSendLogRef
        return messageSendLog.recordPayload(plaintext, for: message, tx: tx).map { NSNumber(value: $0) }
    }
}

public class MessageSendLog {
    private let databaseStorage: SDSDatabaseStorage
    private let dateProvider: DateProvider

    public init(
        databaseStorage: SDSDatabaseStorage,
        dateProvider: @escaping DateProvider
    ) {
        self.databaseStorage = databaseStorage
        self.dateProvider = dateProvider
    }

    private static let payloadLifetime = RemoteConfig.messageSendLogEntryLifetime

    private func currentExpiredPayloadTimestamp() -> UInt64 {
        dateProvider().addingTimeInterval(-Self.payloadLifetime).ows_millisecondsSince1970
    }

    struct Payload: Codable, FetchableRecord, MutablePersistableRecord {
        static let databaseTableName = "MessageSendLog_Payload"

        var payloadId: Int64?
        let plaintextContent: Data
        let contentHint: SealedSenderContentHint
        let sentTimestamp: UInt64
        let uniqueThreadId: String
        // Indicates whether or not this payload is in the process of being sent.
        // Used to prevent deletion of the MSL entry if a recipient acks delivery
        // before we've finished sending to another recipient.
        var sendComplete: Bool

        init(
            plaintextContent: Data,
            contentHint: SealedSenderContentHint,
            sentTimestamp: UInt64,
            uniqueThreadId: String,
            sendComplete: Bool
        ) {
            self.plaintextContent = plaintextContent
            self.contentHint = contentHint
            self.sentTimestamp = sentTimestamp
            self.uniqueThreadId = uniqueThreadId
            self.sendComplete = sendComplete
        }

        mutating func didInsert(with rowID: Int64, for column: String?) {
            guard column == "payloadId" else { return owsFailDebug("Expected payloadId") }
            payloadId = rowID
        }
    }

    struct Recipient: Codable, FetchableRecord, PersistableRecord {
        static let databaseTableName = "MessageSendLog_Recipient"

        let payloadId: Int64
        let recipientUUID: String
        let recipientDeviceId: Int64
    }

    struct Message: Codable, FetchableRecord, PersistableRecord {
        static let databaseTableName = "MessageSendLog_Message"

        let payloadId: Int64
        let uniqueId: String
    }

    func recordPayload(_ plaintext: Data, for message: TSOutgoingMessage, tx: SDSAnyWriteTransaction) -> Int64? {
        guard !RemoteConfig.messageResendKillSwitch else {
            return nil
        }
        guard message.shouldRecordSendLog else { return nil }

        let existingValue: (payloadId: Int64, payload: Payload)?
        do {
            existingValue = try fetchUniquePayload(for: message, tx: tx)
        } catch {
            owsFailDebug("")
            return nil
        }

        if let existingValue {
            // We found an existing payload. This message was probably a partial
            // failure the first time. Double check the plaintext matches. If it does,
            // we can use the existing payloadId. If not, we can't record MSL entries
            // for subsequent sends because the timestamp and threadId will alias each
            // other.
            if existingValue.payload.plaintextContent == plaintext {
                // If we're working to record a payload, this message is no longer
                // complete. We set "sendComplete" false to make sure if a delivery receipt
                // comes in before we finish sending to the remaining recipients that we
                // don't clear out our payload.
                do {
                    var existingPayload = existingValue.payload
                    existingPayload.sendComplete = false
                    try existingPayload.update(tx.unwrapGrdbWrite.database)
                } catch {
                    owsFailDebug("Failed to mark existing payload incomplete.")
                }

                return existingValue.payloadId
            }

            // If a sync message aliases with another message, it's not great but it's
            // not a major issue. The MSL is critical for correct behavior of sender
            // key messages. For non sender key messages, it's a nice-to-have in case
            // some unforeseen decryption failure happens.
            owsAssertDebug(message is OWSOutgoingSyncMessage, "Found an MSL inconsistency for a non-sync message.")
            return nil
        }

        // No existing payload found. Create a new one and insert it.
        do {
            var payload = Payload(
                plaintextContent: plaintext,
                contentHint: message.contentHint,
                sentTimestamp: message.timestamp,
                uniqueThreadId: message.uniqueThreadId,
                sendComplete: false
            )
            try payload.insert(tx.unwrapGrdbWrite.database)

            guard let payloadId = payload.payloadId else {
                throw OWSAssertionError("We must have a payloadId after inserting.")
            }

            // If the payload was successfully recorded, we should also record any
            // interactions related to this payload. This should not fail.
            try message.relatedUniqueIds.forEach { uniqueId in
                try Message(payloadId: payloadId, uniqueId: uniqueId).insert(tx.unwrapGrdbWrite.database)
            }
            return payloadId
        } catch {
            owsFailDebug("Unexpected MSL payload insertion error \(error)")
            return nil
        }
    }

    func mergePayloads(from fromThreadUniqueId: String, into intoThreadUniqueId: String, tx: SDSAnyWriteTransaction) {
        do {
            let db = tx.unwrapGrdbWrite.database
            try fetchRequest(threadUniqueId: fromThreadUniqueId).updateAll(db, Column("uniqueThreadId").set(to: intoThreadUniqueId))
        } catch {
            owsFailDebug("Couldn't update MSL entries: \(error)")
        }
    }

    func fetchPayload(
        recipientAci: Aci,
        recipientDeviceId: UInt32,
        timestamp: UInt64,
        tx: SDSAnyReadTransaction
    ) -> Payload? {
        guard !RemoteConfig.messageResendKillSwitch else {
            return nil
        }

        guard timestamp > currentExpiredPayloadTimestamp() else {
            return nil
        }

        let existingValue: (payloadId: Int64, payload: Payload)?
        do {
            let recipientAlias = TableAlias()
            let request = Payload
                .joining(required: Payload.hasMany(Recipient.self).aliased(recipientAlias))
                .filter(Column("sentTimestamp") == timestamp)
                .filter(recipientAlias[Column("recipientUUID")] == recipientAci.serviceIdUppercaseString)
                .filter(recipientAlias[Column("recipientDeviceId")] == Int64(recipientDeviceId))
            existingValue = try fetchUniquePayload(query: request, tx: tx)
        } catch {
            owsFailDebug("\(error)")
            return nil
        }
        guard let existingValue else {
            return nil
        }
        return existingValue.payload
    }

    public func sendComplete(message: TSOutgoingMessage, tx: SDSAnyWriteTransaction) {
        guard !RemoteConfig.messageResendKillSwitch else {
            return
        }
        guard message.shouldRecordSendLog else { return }

        do {
            let db = tx.unwrapGrdbWrite.database
            guard var (_, payload) = try fetchUniquePayload(for: message, tx: tx) else {
                return
            }
            payload.sendComplete = true
            try payload.update(db)
            try deletePayloadIfNecessary(payload, tx: tx)
        } catch {
            owsFailDebug("Failed to mark send complete for \(message.timestamp): \(error)")
        }
    }

    private func fetchRequest(threadUniqueId: String) -> QueryInterfaceRequest<Payload> {
        return Payload.filter(Column("uniqueThreadId") == threadUniqueId)
    }

    private func fetchUniquePayload(
        for message: TSOutgoingMessage,
        tx: SDSAnyReadTransaction
    ) throws -> (Int64, Payload)? {
        let query = fetchRequest(threadUniqueId: message.uniqueThreadId).filter(Column("sentTimestamp") == message.timestamp)
        return try fetchUniquePayload(query: query, tx: tx)
    }

    private func fetchUniquePayload(
        query: QueryInterfaceRequest<Payload>,
        tx: SDSAnyReadTransaction
    ) throws -> (Int64, Payload)? {
        let payloads = try query.fetchAll(tx.unwrapGrdbRead.database)
        guard let payload = payloads.first else {
            return nil
        }
        guard let payloadId = payload.payloadId else {
            throw OWSAssertionError("Fetched payload without a rowid.")
        }
        guard payloads.count == 1 else {
            throw OWSAssertionError("Duplicate payloads in the MSL.")
        }
        return (payloadId, payload)
    }

    /// Deletes a payload once it's sent & delivered to everyone.
    private func deletePayloadIfNecessary(_ payload: Payload, tx: SDSAnyWriteTransaction) throws {
        let db = tx.unwrapGrdbWrite.database

        guard payload.sendComplete else {
            return
        }

        let recipientCount = try Recipient.filter(Column("payloadId") == payload.payloadId).limit(1).fetchCount(db)
        guard recipientCount == 0 else {
            return
        }

        try payload.delete(db)
    }

    func deviceIdsPendingDelivery(
        for payloadId: Int64,
        recipientAci: Aci,
        tx: SDSAnyReadTransaction
    ) -> [UInt32?]? {
        do {
            return try Recipient
                .filter(Column("payloadId") == payloadId)
                .filter(Column("recipientUuid") == recipientAci.serviceIdUppercaseString)
                .select(Column("recipientDeviceId"), as: Int64.self)
                .fetchAll(tx.unwrapGrdbRead.database)
                .map { UInt32(exactly: $0) }
        } catch {
            owsFailDebug("\(error)")
            return nil
        }
    }

    func recordPendingDelivery(
        payloadId: Int64,
        recipientAci: Aci,
        recipientDeviceId: UInt32,
        message: TSOutgoingMessage,
        tx: SDSAnyWriteTransaction
    ) {
        guard !RemoteConfig.messageResendKillSwitch else {
            return
        }
        do {
            try Recipient(
                payloadId: payloadId,
                recipientUUID: recipientAci.serviceIdUppercaseString,
                recipientDeviceId: Int64(recipientDeviceId)
            ).insert(tx.unwrapGrdbWrite.database)
        } catch let error as DatabaseError where error.extendedResultCode == .SQLITE_CONSTRAINT_FOREIGNKEY {
            // There's a tiny race where a recipient could send a delivery receipt before we record an MSL entry
            // This might cause the payload entry to be deleted before we can mark the recipient as sent. This
            // would mean that we'd hit a foreign key constraint failure when trying to save the recipient since
            // the payload is now missing.

            // This block of code just avoids a spurious assert by only asserting if the message has not been marked delivered:
            let dbCopy = TSOutgoingMessage.anyFetchOutgoingMessage(uniqueId: message.uniqueId, transaction: tx)
            owsAssertDebug(dbCopy?.recipientState(for: SignalServiceAddress(recipientAci))?.deliveryTimestamp != nil)
        } catch {
            owsFailDebug("Failed to record pending delivery \(error)")
        }
    }

    func recordSuccessfulDelivery(
        message: TSOutgoingMessage,
        recipientAci: Aci,
        recipientDeviceId: UInt32,
        tx: SDSAnyWriteTransaction
    ) {
        guard !RemoteConfig.messageResendKillSwitch else {
            return
        }
        do {
            guard let (payloadId, payload) = try fetchUniquePayload(for: message, tx: tx) else {
                return
            }

            let db = tx.unwrapGrdbWrite.database
            try Recipient
                .filter(Column("payloadId") == payloadId)
                .filter(Column("recipientUuid") == recipientAci.serviceIdUppercaseString)
                .filter(Column("recipientDeviceId") == recipientDeviceId)
                .deleteAll(db)

            try deletePayloadIfNecessary(payload, tx: tx)
        } catch {
            owsFailDebug("Failed to record successful delivery \(error)")
        }
    }

    func deleteAllPayloadsForInteraction(
        _ interaction: TSInteraction,
        tx: SDSAnyWriteTransaction
    ) {
        do {
            let db = tx.unwrapGrdbWrite.database
            let messages = try Message.filter(Column("uniqueId") == interaction.uniqueId).fetchAll(db)
            for message in messages {
                try Payload.filter(Column("payloadId") == message.payloadId).deleteAll(db)
            }
        } catch {
            owsFailDebug("Failed to delete payloads for interaction(\(interaction.uniqueId)): \(error)")
        }
    }

    public func schedulePeriodicCleanup(on scheduler: Scheduler) {
        scheduler.async {
            self._performPeriodicCleanup(on: scheduler)
        }
    }

    private func _performPeriodicCleanup(on scheduler: Scheduler) {
        let expirationTimestamp = currentExpiredPayloadTimestamp()
        do {
            try databaseStorage.write { tx in
                let db = tx.unwrapGrdbWrite.database
                return try Payload.filter(Column("sentTimestamp") < expirationTimestamp).deleteAll(db)
            }
        } catch {
            Logger.warn("Couldn't prune stale MSL entries \(error)")
        }

        scheduler.asyncAfter(wallDeadline: .now() + kDayInterval) {
            self._performPeriodicCleanup(on: scheduler)
        }
    }
}
