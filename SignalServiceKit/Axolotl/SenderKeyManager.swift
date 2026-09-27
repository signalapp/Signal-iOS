//
// Copyright 2025 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import LibSignalClient

class SenderKeyManager {
    fileprivate let sendingDistributionIdStore = KeyValueStore(collection: "SenderKeyStore_SendingDistributionId")

    fileprivate let oldSenderKeyStore: OldSenderKeyStore
    fileprivate let recipientFetcher: RecipientFetcher
    fileprivate let recipientStore: RecipientDatabaseTable
    fileprivate let senderKeyStore: SignalServiceKit.SenderKeyStore
    fileprivate let sessionStore: SignalServiceKit.SessionStore

    init(
        oldSenderKeyStore: OldSenderKeyStore,
        recipientFetcher: RecipientFetcher,
        recipientStore: RecipientDatabaseTable,
        senderKeyStore: SignalServiceKit.SenderKeyStore,
        sessionStore: SignalServiceKit.SessionStore,
    ) {
        self.oldSenderKeyStore = oldSenderKeyStore
        self.recipientFetcher = recipientFetcher
        self.recipientStore = recipientStore
        self.senderKeyStore = senderKeyStore
        self.sessionStore = sessionStore
    }

    func resetAll(tx: DBWriteTransaction) {
        oldSenderKeyStore.resetAll(tx: tx)
        sendingDistributionIdStore.removeAll(transaction: tx)
        failIfThrows {
            // Delete these first
            try SenderKeySentToDeviceRecord
                .deleteAll(tx.database)
            // So that FOREIGN KEY lookups when deleting these are faster
            try SenderKeyRecord
                .deleteAll(tx.database)
        }
    }

    // MARK: - Sender Key Records

    fileprivate func storeSenderKey(
        from sender: LibSignalClient.ProtocolAddress,
        distributionId: UUID,
        record: LibSignalClient.SenderKeyRecord,
        deletionType: SenderKeyRecord.DeletionType,
        shouldUpdateInsertedAtDate: Bool,
        dateProvider: DateProvider,
        context: any LibSignalClient.StoreContext,
    ) throws {
        let tx = context.asTransaction
        guard let senderAci = sender.serviceId as? Aci else {
            throw OWSAssertionError("must have ACI for sender keys")
        }
        let keyId = OldSenderKeyStore.buildKeyId(authorAci: senderAci, distributionId: distributionId)
        oldSenderKeyStore.removeKeyMetadata(forKeyId: keyId, tx: tx)
        let recipient = recipientFetcher.fetchOrCreate(serviceId: senderAci, tx: tx)
        _ = senderKeyStore.upsertSenderKey(
            record,
            forRecipientId: recipient.id,
            deviceId: sender.deviceIdObj,
            distributionId: distributionId,
            deletionType: deletionType,
            shouldUpdateInsertedAtDate: shouldUpdateInsertedAtDate,
            dateProvider: dateProvider,
            tx: tx,
        )
    }

    fileprivate func loadSenderKey(
        from sender: LibSignalClient.ProtocolAddress,
        distributionId: UUID,
        context: any LibSignalClient.StoreContext,
    ) throws -> LibSignalClient.SenderKeyRecord? {
        let tx = context.asTransaction
        guard let senderAci = sender.serviceId as? Aci else {
            throw OWSAssertionError("must have ACI for sender keys")
        }
        let serializedRecord = (
            _loadSenderKey(forSenderAci: senderAci, deviceId: sender.deviceIdObj, distributionId: distributionId, tx: tx)
                ?? _loadOldSenderKey(forSenderAci: senderAci, distributionId: distributionId, tx: tx),
        )
        guard let serializedRecord else {
            return nil
        }
        do {
            return try LibSignalClient.SenderKeyRecord(bytes: serializedRecord)
        } catch {
            Logger.warn("bypassing malformed sender key record: \(error)")
            return nil
        }
    }

    private func _loadSenderKey(
        forSenderAci senderAci: Aci,
        deviceId: DeviceId,
        distributionId: UUID,
        tx: DBReadTransaction,
    ) -> Data? {
        let recipient = recipientStore.fetchRecipient(serviceId: senderAci, transaction: tx)
        guard let recipient else {
            return nil
        }
        let senderKeyRecord = senderKeyStore.fetchSenderKeyRecord(
            recipientId: recipient.id,
            deviceId: deviceId,
            distributionId: distributionId,
            tx: tx,
        )
        guard let senderKeyRecord else {
            return nil
        }
        return senderKeyRecord.serializedRecord
    }

    private func _loadOldSenderKey(
        forSenderAci senderAci: Aci,
        distributionId: UUID,
        tx: DBReadTransaction,
    ) -> Data? {
        guard BuildFlags.decodeOldSenderKeys else {
            return nil
        }
        return oldSenderKeyStore.loadSenderKey(
            forSenderAci: senderAci,
            distributionId: distributionId,
            tx: tx,
        )
    }
}

// MARK: -

/// Interfaces between LibSignal and SenderKeyManager.
///
/// Adds additional "context" that's not reflected in StoreContext. For
/// example, this type stores whether or not storeSenderKey should also
/// update the insertion date when upserting a record. It also conveys that
/// Sender Keys being stored have been received from other devices.
class SenderKeyReceivingManager: LibSignalClient.SenderKeyStore {
    private let senderKeyManager: SenderKeyManager
    private let shouldUpdateInsertedAtDate: Bool

    init(senderKeyManager: SenderKeyManager, shouldUpdateInsertedAtDate: Bool) {
        self.senderKeyManager = senderKeyManager
        self.shouldUpdateInsertedAtDate = shouldUpdateInsertedAtDate
    }

    func storeSenderKey(from sender: ProtocolAddress, distributionId: UUID, record: LibSignalClient.SenderKeyRecord, context: any StoreContext) throws {
        try senderKeyManager.storeSenderKey(
            from: sender,
            distributionId: distributionId,
            record: record,
            deletionType: .otherDevice,
            shouldUpdateInsertedAtDate: shouldUpdateInsertedAtDate,
            dateProvider: { Date() },
            context: context,
        )
    }

    func loadSenderKey(from sender: ProtocolAddress, distributionId: UUID, context: any StoreContext) throws -> LibSignalClient.SenderKeyRecord? {
        return try senderKeyManager.loadSenderKey(from: sender, distributionId: distributionId, context: context)
    }
}

// MARK: -

/// Provides send-specific code; interfaces between LibSignal and SenderKeyManager.
class SenderKeySendingManager: LibSignalClient.SenderKeyStore, ThreadRemoverObserver {
    private let senderKeyManager: SenderKeyManager
    private let dateProvider: DateProvider

    init(senderKeyManager: SenderKeyManager, dateProvider: @escaping DateProvider) {
        self.senderKeyManager = senderKeyManager
        self.dateProvider = dateProvider
    }

    func storeSenderKey(from sender: ProtocolAddress, distributionId: UUID, record: LibSignalClient.SenderKeyRecord, context: any StoreContext) throws {
        try senderKeyManager.storeSenderKey(
            from: sender,
            distributionId: distributionId,
            record: record,
            deletionType: .thisDevice,
            shouldUpdateInsertedAtDate: false,
            dateProvider: dateProvider,
            context: context,
        )
    }

    func loadSenderKey(from sender: ProtocolAddress, distributionId: UUID, context: any StoreContext) throws -> LibSignalClient.SenderKeyRecord? {
        return try senderKeyManager.loadSenderKey(from: sender, distributionId: distributionId, context: context)
    }

    func fetchDistributionId(forThreadUniqueId threadUniqueId: String, tx: DBReadTransaction) -> UUID? {
        return senderKeyManager.sendingDistributionIdStore.getString(threadUniqueId, transaction: tx).flatMap(UUID.init(uuidString:))
    }

    func fetchOrCreateDistributionId(forThreadUniqueId threadUniqueId: String, tx: DBWriteTransaction) -> UUID {
        if let distributionId = fetchDistributionId(forThreadUniqueId: threadUniqueId, tx: tx) {
            return distributionId
        }
        let distributionId = UUID()
        senderKeyManager.sendingDistributionIdStore.setString(distributionId.uuidString, key: threadUniqueId, transaction: tx)
        return distributionId
    }

    private func removeDistributionId(forThreadUniqueId threadUniqueId: String, tx: DBWriteTransaction) {
        senderKeyManager.sendingDistributionIdStore.removeValue(forKey: threadUniqueId, transaction: tx)
    }

    func deleteSenderKey(
        forThreadUniqueId threadUniqueId: String,
        localAci: Aci,
        localDeviceId: DeviceId,
        tx: DBWriteTransaction,
    ) {
        let senderKey = fetchSenderKey(
            forThreadUniqueId: threadUniqueId,
            localAci: localAci,
            localDeviceId: localDeviceId,
            tx: tx,
        )
        guard let senderKey else {
            return
        }
        failIfThrows {
            try senderKey.delete(tx.database)
        }
    }

    func readyRecipients(
        forThreadUniqueId threadUniqueId: String,
        attemptServiceIds: Set<ServiceId>,
        acceptableServiceIds: Set<ServiceId>,
        maxSenderKeyAge: TimeInterval,
        now: Date,
        localAci: Aci,
        localDeviceId: DeviceId,
        tx: DBWriteTransaction,
    ) -> [ServiceId: [SenderKeySentToDevice]] {
        owsPrecondition(acceptableServiceIds.isSuperset(of: attemptServiceIds))
        let recipientFetcher = senderKeyManager.recipientFetcher
        let senderKeyStore = senderKeyManager.senderKeyStore

        let distributionId = fetchOrCreateDistributionId(forThreadUniqueId: threadUniqueId, tx: tx)
        let localRecipient = recipientFetcher.fetchOrCreate(serviceId: localAci, tx: tx)

        migrateSenderKeyIfNeeded(
            distributionId: distributionId,
            localAci: localAci,
            localDeviceId: localDeviceId,
            tx: tx,
        )

        // We should already have recipients, but we can create them if we don't.
        var attemptRecipients = [(ServiceId, SignalRecipient)]()
        var acceptableRecipientIds = Set<SignalRecipient.RowId>()
        for serviceId in acceptableServiceIds {
            let recipient = recipientFetcher.fetchOrCreate(serviceId: serviceId, tx: tx)
            acceptableRecipientIds.insert(recipient.id)
            if attemptServiceIds.contains(serviceId) {
                attemptRecipients.append((serviceId, recipient))
            }
        }

        var senderKeyRecord = senderKeyStore.fetchSenderKeyRecord(
            recipientId: localRecipient.id,
            deviceId: localDeviceId,
            distributionId: distributionId,
            tx: tx,
        )
        if let innerSenderKeyRecord = senderKeyRecord {
            // If too much time has elapsed, we must delete the Sender Key.
            if now.timeIntervalSince(innerSenderKeyRecord.insertedAtDate) >= maxSenderKeyAge {
                failIfThrows {
                    try innerSenderKeyRecord.delete(tx.database)
                }
                senderKeyRecord = nil
            }
        }
        var senderKeySentToRecords = [SenderKeySentToDeviceRecord]()
        if let innerSenderKeyRecord = senderKeyRecord {
            senderKeySentToRecords = senderKeyStore.fetchSentToRecords(senderKeyId: innerSenderKeyRecord.id, tx: tx)
            // If a recipient is no longer acceptable, we must delete the Sender Key.
            if senderKeySentToRecords.contains(where: { !acceptableRecipientIds.contains($0.recipientId) }) {
                failIfThrows {
                    try innerSenderKeyRecord.delete(tx.database)
                }
                senderKeyRecord = nil
                senderKeySentToRecords = []
            }
        }

        var sentToRecipientRecords = [SignalRecipient.RowId: [SenderKeySentToDeviceRecord]]()
        for senderKeySentToRecord in senderKeySentToRecords {
            sentToRecipientRecords[senderKeySentToRecord.recipientId, default: []].append(senderKeySentToRecord)
        }

        // Iterate over intended recipients. If all of their devices have received
        // a copy of the Sender Key (this may be vacuously true), they're ready.
        var result = [ServiceId: [SenderKeySentToDevice]]()
        for (serviceId, recipient) in attemptRecipients {
            if serviceId is Pni, !recipient.canSendToPni() {
                Logger.warn("can't use Sender Key for \(serviceId) because we know their ACI")
                continue
            }
            let currentDeviceStates: [RecipientDeviceState]
            do {
                currentDeviceStates = try self.recipientDeviceStates(forRecipient: recipient, tx: tx)
            } catch SignalError.sessionNotFound {
                // We don't have a session, so they're not ready.
                continue
            } catch {
                // Something else went wrong, so assume they're not ready.
                owsFailDebug("couldn't fetch session for \(serviceId): \(error)")
                continue
            }

            // Only remove the recipient in question from our send targets if the cached state contains
            // every device from the current state. Any new devices mean we need to re-send.
            result[serviceId] = sentToRecipientDevices(
                currentDeviceStates,
                priorRecipientSentToDeviceRecords: sentToRecipientRecords[recipient.id] ?? [],
            )
        }
        return result
    }

    private struct RecipientDeviceState {
        var deviceId: DeviceId
        var registrationId: UInt32?
    }

    /// Builds RecipientDeviceStates for the given recipient by fetching the registration ID for each device ID.
    private func recipientDeviceStates(
        forRecipient recipient: SignalRecipient,
        tx: DBReadTransaction,
    ) throws -> [RecipientDeviceState] {
        let sessionStore = senderKeyManager.sessionStore
        return try recipient.deviceIds.map { deviceId -> RecipientDeviceState in
            // We have to fetch the registrationId since deviceIds can be reused. By
            // comparing a set of (deviceId, registrationId) structs, we are better
            // able to detect reused device IDs that need an SKDM.
            let registrationId = try sessionStore.fetchSession(
                forRecipientId: recipient.id,
                localIdentity: .aci,
                deviceId: deviceId,
                tx: tx,
            )?.remoteRegistrationId()
            return RecipientDeviceState(deviceId: deviceId, registrationId: registrationId)
        }
    }

    private func sentToRecipientDevices(
        _ currentRecipientDevices: [RecipientDeviceState],
        priorRecipientSentToDeviceRecords: [SenderKeySentToDeviceRecord],
    ) -> [SenderKeySentToDevice]? {
        var requiredSentToDevices = [SenderKeySentToDevice]()
        for recipientDevice in currentRecipientDevices {
            guard let registrationId = recipientDevice.registrationId else {
                // If there are any devices without registration IDs, we assume they're new
                // and will definitely require an SKDM.
                return nil
            }
            requiredSentToDevices.append(SenderKeySentToDevice(deviceId: recipientDevice.deviceId, registrationId: registrationId))
        }
        let priorRecipientSentToDevices = Set(priorRecipientSentToDeviceRecords.map {
            return SenderKeySentToDevice(deviceId: $0.deviceId, registrationId: $0.registrationId)
        })
        // Otherwise, we can skip the SKDM if it's been sent to every device.
        if priorRecipientSentToDevices.isSuperset(of: requiredSentToDevices) {
            return requiredSentToDevices
        }
        return nil
    }

    func buildSenderKeyDistributionMessage(
        forThreadUniqueId threadUniqueId: String,
        localAci: Aci,
        localDeviceId: DeviceId,
        tx: DBWriteTransaction,
    ) throws -> SenderKeyDistributionMessage {
        let localAddress = ProtocolAddress(localAci, deviceId: localDeviceId)
        let distributionId = fetchOrCreateDistributionId(forThreadUniqueId: threadUniqueId, tx: tx)
        // Migrate here in case this is an OWSOutgoingResendResponse.
        migrateSenderKeyIfNeeded(
            distributionId: distributionId,
            localAci: localAci,
            localDeviceId: localDeviceId,
            tx: tx,
        )
        return try LibSignalClient.SenderKeyDistributionMessage(
            from: localAddress,
            distributionId: distributionId,
            store: self,
            context: tx,
        )
    }

    func fetchSenderKeyId(
        forThreadUniqueId threadUniqueId: String,
        localAci: Aci,
        localDeviceId: DeviceId,
        tx: DBReadTransaction,
    ) -> SenderKeyRecord.RowId? {
        let senderKey = fetchSenderKey(
            forThreadUniqueId: threadUniqueId,
            localAci: localAci,
            localDeviceId: localDeviceId,
            tx: tx,
        )
        return senderKey?.id
    }

    private func fetchSenderKey(
        forThreadUniqueId threadUniqueId: String,
        localAci: Aci,
        localDeviceId: DeviceId,
        tx: DBReadTransaction,
    ) -> SenderKeyRecord? {
        let recipientStore = senderKeyManager.recipientStore
        let senderKeyStore = senderKeyManager.senderKeyStore

        guard let distributionId = fetchDistributionId(forThreadUniqueId: threadUniqueId, tx: tx) else {
            return nil
        }
        guard let localRecipient = recipientStore.fetchRecipient(serviceId: localAci, transaction: tx) else {
            return nil
        }
        return senderKeyStore.fetchSenderKeyRecord(
            recipientId: localRecipient.id,
            deviceId: localDeviceId,
            distributionId: distributionId,
            tx: tx,
        )
    }

    func recordSentSenderKeys(
        _ sentSenderKeys: [SentSenderKey],
        forSenderKeyId senderKeyId: SenderKeyRecord.RowId,
        tx: DBWriteTransaction,
    ) {
        let recipientStore = senderKeyManager.recipientStore
        let senderKeyStore = senderKeyManager.senderKeyStore

        for sentSenderKey in sentSenderKeys {
            let recipient = recipientStore.fetchRecipient(serviceId: sentSenderKey.recipient, transaction: tx)
            guard let recipient else {
                Logger.warn("can't record sent sender key for non-existent recipient: \(sentSenderKey.recipient)")
                continue
            }
            for message in sentSenderKey.messages {
                do throws(ConstraintError) {
                    try senderKeyStore.upsertSentToRecord(
                        senderKeyId: senderKeyId,
                        recipientId: recipient.id,
                        deviceId: message.destinationDeviceId,
                        registrationId: message.destinationRegistrationId,
                        tx: tx,
                    )
                } catch {
                    Logger.warn("can't record sender key as sent because the key was deleted")
                }
            }
        }
    }

    func resetDeliveryRecord(senderKeyId: SenderKeyRecord.RowId, recipientId: SignalRecipient.RowId, tx: DBWriteTransaction) {
        let senderKeyStore = senderKeyManager.senderKeyStore
        senderKeyStore.resetDeliveryRecord(senderKeyId: senderKeyId, recipientId: recipientId, tx: tx)
    }

    // MARK: - Migrating Sender Keys

    private func migrateSenderKeyIfNeeded(
        distributionId: UUID,
        localAci: Aci,
        localDeviceId: DeviceId,
        tx: DBWriteTransaction,
    ) {
        guard BuildFlags.decodeOldSenderKeys else {
            return
        }

        let oldSenderKeyStore = senderKeyManager.oldSenderKeyStore
        let recipientFetcher = senderKeyManager.recipientFetcher
        let senderKeyStore = senderKeyManager.senderKeyStore

        let keyId = OldSenderKeyStore.buildKeyId(authorAci: localAci, distributionId: distributionId)
        let oldKeyMetadata: KeyMetadata?
        do {
            oldKeyMetadata = try oldSenderKeyStore.getKeyMetadata(forKeyId: keyId, tx: tx)
        } catch {
            oldSenderKeyStore.removeKeyMetadata(forKeyId: keyId, tx: tx)
            Logger.warn("deleted malformed sender key: \(error)")
            return
        }
        guard let oldKeyMetadata else {
            // There's nothing that needs to be migrated. (This is the common case.)
            return
        }
        // We're migrating something; no matter what, even if we hit an error, we
        // want to delete it from OldSenderKeyStore.
        oldSenderKeyStore.removeKeyMetadata(forKeyId: keyId, tx: tx)

        guard oldKeyMetadata.isForEncrypting else {
            owsFailDebug("can't use sender key for encrypting")
            return
        }
        guard oldKeyMetadata.ownerAci == localAci else {
            owsFailDebug("can't use sender key unless we're the owner")
            return
        }
        guard oldKeyMetadata.ownerDeviceId == localDeviceId else {
            owsFailDebug("can't use sender key unless we're the owning device")
            return
        }
        guard oldKeyMetadata.distributionId == distributionId else {
            owsFailDebug("can't use sender key for another distribution id")
            return
        }

        let senderKey: LibSignalClient.SenderKeyRecord
        do {
            senderKey = try LibSignalClient.SenderKeyRecord(bytes: oldKeyMetadata.serializedRecord)
        } catch {
            Logger.warn("couldn't decode sender key: \(error)")
            return
        }

        let localRecipient = recipientFetcher.fetchOrCreate(serviceId: localAci, tx: tx)

        // There shouldn't be an existing record, but if there is one, delete it.
        // This avoids collisions when migrating the records.
        let existingSenderKeyRecord = senderKeyStore.fetchSenderKeyRecord(
            recipientId: localRecipient.id,
            deviceId: localDeviceId,
            distributionId: distributionId,
            tx: tx,
        )
        failIfThrows {
            try existingSenderKeyRecord?.delete(tx.database)
        }

        // Insert the Sender Key.
        let senderKeyRecord = senderKeyStore.upsertSenderKey(
            senderKey,
            forRecipientId: localRecipient.id,
            deviceId: localDeviceId,
            distributionId: distributionId,
            deletionType: .thisDevice,
            shouldUpdateInsertedAtDate: true,
            dateProvider: { oldKeyMetadata.creationDate },
            tx: tx,
        )

        // Insert the "sent to" records.
        for (address, sendInfo) in oldKeyMetadata.sentKeyInfo {
            guard let serviceId = address.serviceId else {
                Logger.warn("skipping 'sent to' record for recipient with no service id")
                continue
            }
            let recipient = recipientFetcher.fetchOrCreate(serviceId: serviceId, tx: tx)
            for device in sendInfo.keyRecipient.devices {
                do throws(ConstraintError) {
                    try senderKeyStore.upsertSentToRecord(
                        senderKeyId: senderKeyRecord.id,
                        recipientId: recipient.id,
                        deviceId: device.deviceId,
                        registrationId: device.registrationId,
                        tx: tx,
                    )
                } catch {
                    owsFail("can't be missing SenderKeyRecord or Recipient we just fetched")
                }
            }
        }
    }

    // MARK: - ThreadRemoverObserver

    func didRemoveThread(_ thread: TSThread, tx: DBWriteTransaction) {
        removeDistributionId(forThreadUniqueId: thread.uniqueId, tx: tx)
    }
}
