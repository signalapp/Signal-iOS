//
// Copyright 2021 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

public import LibSignalClient

struct SentSenderKey {
    var recipient: ServiceId
    var messages: [SentDeviceMessage]
}

public class OldSenderKeyStore {
    public typealias DistributionId = UUID
    fileprivate typealias KeyId = String
    fileprivate static func buildKeyId(authorAci: Aci, distributionId: DistributionId) -> KeyId {
        "\(authorAci.serviceIdUppercaseString).\(distributionId.uuidString)"
    }

    public init() {
        SwiftSingletons.register(self)
    }

    /// Returns the distributionId the current device uses to tag senderKey messages sent to the thread.
    public func distributionIdForSendingToThread(_ thread: TSThread, writeTx: DBWriteTransaction) -> DistributionId {
        distributionIdForSendingToThreadId(thread.threadUniqueId, writeTx: writeTx)
    }

    /// Returns a list of devices that already have the current device's sender
    /// key for the thread.
    func readyRecipients(
        for thread: TSThread,
        limitedTo intendedRecipients: Set<ServiceId>,
        tx: DBReadTransaction,
    ) -> [ServiceId: [SenderKeySentToRecipientDevice]] {
        let sentKeyInfo = { () -> [SignalServiceAddress: SKDMSendInfo]? in
            guard let keyId = keyIdForSendingToThreadId(thread.threadUniqueId, readTx: tx) else {
                // If we haven't saved a distributionId yet, then there's no way we have
                // any sentKeyInfo.
                return nil
            }
            return getKeyMetadata(for: keyId, readTx: tx)?.sentKeyInfo
        }()

        // Iterate over intended recipients. If all of their devices have received
        // a copy of the Sender Key (this may be vacuously true), they're ready.
        var result = [ServiceId: [SenderKeySentToRecipientDevice]]()
        for intendedRecipient in intendedRecipients {
            let priorSendRecipientState: SenderKeySentToRecipient = (
                sentKeyInfo?[SignalServiceAddress(intendedRecipient)]?.keyRecipient
                    ?? SenderKeySentToRecipient(devices: []),
            )
            do {
                // Only remove the recipient in question from our send targets if the cached state contains
                // every device from the current state. Any new devices mean we need to re-send.
                let currentRecipientState = try self.recipientState(for: intendedRecipient, tx: tx)
                result[intendedRecipient] = sentToRecipientDevices(currentRecipientState, priorRecipient: priorSendRecipientState)
            } catch {
                // It's likely there's no session for the current recipient. Maybe it was cleared?
                // In this case, we just assume we need to send a new SKDM
                if case SignalError.invalidState = error {
                    Logger.warn("Invalid session state. Cannot build recipient state for \(intendedRecipient). \(error)")
                } else {
                    owsFailDebug("Failed to fetch current recipient state for \(intendedRecipient): \(error)")
                }
            }
        }
        return result
    }

    /// Builds SenderKeyRecipientDevices for the given address by fetching all of the devices and corresponding registrationIds
    private func recipientState(for serviceId: ServiceId, tx: DBReadTransaction) throws -> [RecipientDeviceState] {
        let recipientDatabaseTable = DependenciesBridge.shared.recipientDatabaseTable
        guard let recipient = recipientDatabaseTable.fetchRecipient(serviceId: serviceId, transaction: tx) else {
            throw OWSAssertionError("Invalid device array")
        }
        let deviceIds = recipient.deviceIds
        let sessionStore = DependenciesBridge.shared.signalProtocolStoreManager.signalProtocolStore(for: .aci).sessionStore
        return try deviceIds.map { deviceId -> RecipientDeviceState in
            // We have to fetch the registrationId since deviceIds can be reused. By
            // comparing a set of (deviceId, registrationId) structs, we should be able
            // to detect reused deviceIds that will need an SKDM.
            let registrationId = try sessionStore.loadSession(
                forServiceId: serviceId,
                deviceId: deviceId,
                tx: tx,
            )?.remoteRegistrationId()

            return RecipientDeviceState(deviceId: deviceId, registrationId: registrationId)
        }
    }

    /// - Returns: `true` if `priorRecipient` contains every device in
    /// `currentRecipient`; `false` if `currentRecipient` doesn't have any
    /// devices or any devices don't have established sessions
    private func sentToRecipientDevices(_ currentRecipientDevices: [RecipientDeviceState], priorRecipient: SenderKeySentToRecipient) -> [SenderKeySentToRecipientDevice]? {
        var hypotheticalSentToDevices = [SenderKeySentToRecipientDevice]()
        for recipientDevice in currentRecipientDevices {
            guard let registrationId = recipientDevice.registrationId else {
                // If there are any devices without registration IDs, we assume they're new
                // and will definitely require an SKDM.
                return nil
            }
            hypotheticalSentToDevices.append(SenderKeySentToRecipientDevice(deviceId: recipientDevice.deviceId, registrationId: registrationId))
        }
        // Otherwise, we can skip the SKDM if it's been sent to every device.
        if priorRecipient.devices.isSuperset(of: hypotheticalSentToDevices) {
            return hypotheticalSentToDevices
        }
        return nil
    }

    /// Records that the current sender key for the `thread` has been sent to `participant`
    func recordSentSenderKeys(
        _ sentSenderKeys: [SentSenderKey],
        for thread: TSThread,
        writeTx: DBWriteTransaction,
    ) throws {
        guard
            let keyId = keyIdForSendingToThreadId(thread.threadUniqueId, writeTx: writeTx),
            let existingMetadata = getKeyMetadata(for: keyId, readTx: writeTx)
        else {
            throw OWSAssertionError("Failed to look up key metadata")
        }
        var updatedMetadata = existingMetadata
        for sentSenderKey in sentSenderKeys {
            updatedMetadata.recordSentSenderKey(sentSenderKey)
        }
        setMetadata(updatedMetadata, writeTx: writeTx)
    }

    public func resetSenderKeyDeliveryRecord(
        for thread: TSThread,
        serviceId: ServiceId,
        writeTx: DBWriteTransaction,
    ) {
        guard
            let keyId = keyIdForSendingToThreadId(thread.threadUniqueId, writeTx: writeTx),
            let existingMetadata = getKeyMetadata(for: keyId, readTx: writeTx)
        else {
            Logger.info("Failed to look up senderkey metadata")
            return
        }
        var updatedMetadata = existingMetadata
        updatedMetadata.resetDeliveryRecord(for: serviceId)
        setMetadata(updatedMetadata, writeTx: writeTx)
    }

    private func isKeyValid(for thread: TSThread, maxSenderKeyAge: TimeInterval, tx: DBReadTransaction) -> Bool {
        guard
            let keyId = keyIdForSendingToThreadId(thread.threadUniqueId, readTx: tx),
            let keyMetadata = getKeyMetadata(for: keyId, readTx: tx)
        else {
            return false
        }

        guard keyMetadata.isValid(maxSenderKeyAge: maxSenderKeyAge) else {
            return false
        }

        // It's valid if the recipients for the key are still in the group.
        let currentRecipients = thread.recipientAddresses(with: tx)
        return keyMetadata.currentRecipients.subtracting(currentRecipients).isEmpty
    }

    public func expireSendingKeyIfNecessary(for thread: TSThread, maxSenderKeyAge: TimeInterval, tx: DBWriteTransaction) {
        guard let keyId = keyIdForSendingToThreadId(thread.threadUniqueId, readTx: tx) else {
            return
        }

        if !isKeyValid(for: thread, maxSenderKeyAge: maxSenderKeyAge, tx: tx) {
            setMetadata(nil, for: keyId, writeTx: tx)
        }
    }

    public func resetSenderKeySession(for thread: TSThread, transaction writeTx: DBWriteTransaction) {
        guard let keyId = keyIdForSendingToThreadId(thread.threadUniqueId, writeTx: writeTx) else {
            return
        }
        setMetadata(nil, for: keyId, writeTx: writeTx)
    }

    public func resetSenderKeyStore(transaction writeTx: DBWriteTransaction) {
        keyMetadataStore.removeAll(transaction: writeTx)
        sendingDistributionIdStore.removeAll(transaction: writeTx)
    }

    public func skdmBytesForThread(_ thread: TSThread, tx: DBWriteTransaction) -> Data? {
        guard let localIdentifiers = DependenciesBridge.shared.tsAccountManager.localIdentifiers(tx: tx) else {
            return nil
        }
        return skdmBytesForThread(
            thread,
            localAci: localIdentifiers.aci,
            localDeviceId: DependenciesBridge.shared.tsAccountManager.storedDeviceId(tx: tx),
            tx: tx,
        )
    }

    public func skdmBytesForThread(
        _ thread: TSThread,
        localAci: Aci,
        localDeviceId: LocalDeviceId,
        tx: DBWriteTransaction,
    ) -> Data? {
        guard let localDeviceId = localDeviceId.ifValid else {
            owsFailDebug("Can't construct sender key message if we're not registered")
            return nil
        }
        do {
            let localAddress = ProtocolAddress(localAci, deviceId: localDeviceId)
            let distributionId = distributionIdForSendingToThread(thread, writeTx: tx)
            let skdm = try SenderKeyDistributionMessage(
                from: localAddress,
                distributionId: distributionId,
                store: self,
                context: tx,
            )
            return skdm.serialize()
        } catch {
            owsFailDebug("Failed to construct sender key message: \(error)")
            return nil
        }
    }
}

// MARK: - <LibSignalClient.SenderKeyStore>

extension OldSenderKeyStore: LibSignalClient.SenderKeyStore {
    public func storeSenderKey(
        from sender: ProtocolAddress,
        distributionId: UUID,
        record: SenderKeyRecord,
        context: StoreContext,
    ) throws {
        let tx = context.asTransaction

        guard let senderAci = sender.serviceId as? Aci else {
            throw OWSAssertionError("Invalid protocol address: must have ACI")
        }

        guard let localIdentifiers = DependenciesBridge.shared.tsAccountManager.localIdentifiers(tx: tx) else {
            throw OWSAssertionError("Not registered.")
        }

        let keyId = Self.buildKeyId(authorAci: senderAci, distributionId: distributionId)

        var updatedValue: KeyMetadata
        if let existingMetadata = getKeyMetadata(for: keyId, readTx: tx) {
            updatedValue = existingMetadata
        } else {
            updatedValue = KeyMetadata(
                record: record,
                senderAci: senderAci,
                senderDeviceId: sender.deviceIdObj,
                localIdentifiers: localIdentifiers,
                localDeviceId: DependenciesBridge.shared.tsAccountManager.storedDeviceId(tx: tx),
                distributionId: distributionId,
            )
        }
        updatedValue.record = record
        setMetadata(updatedValue, writeTx: tx)
    }

    public func loadSenderKey(
        from sender: ProtocolAddress,
        distributionId: UUID,
        context: StoreContext,
    ) throws -> SenderKeyRecord? {
        guard let senderAci = sender.serviceId as? Aci else {
            throw OWSAssertionError("Invalid protocol address: must have ACI")
        }

        let readTx = context.asTransaction
        let keyId = Self.buildKeyId(authorAci: senderAci, distributionId: distributionId)
        let metadata = getKeyMetadata(for: keyId, readTx: readTx)
        return metadata?.record
    }
}

// MARK: - Storage

extension OldSenderKeyStore {
    private static let sendingDistributionIdStore = KeyValueStore(collection: "SenderKeyStore_SendingDistributionId")
    private static let keyMetadataStore = KeyValueStore(collection: "SenderKeyStore_KeyMetadata")
    private var sendingDistributionIdStore: KeyValueStore { Self.sendingDistributionIdStore }
    private var keyMetadataStore: KeyValueStore { Self.keyMetadataStore }

    private func getKeyMetadata(for keyId: KeyId, readTx: DBReadTransaction) -> KeyMetadata? {
        let persisted: KeyMetadata?
        do {
            persisted = try keyMetadataStore.getCodableValue(forKey: keyId, transaction: readTx)
        } catch {
            owsFailDebug("Failed to deserialize sender key: \(error)")
            persisted = nil
        }
        return persisted
    }

    private func setMetadata(_ metadata: KeyMetadata, writeTx: DBWriteTransaction) {
        setMetadata(metadata, for: metadata.keyId, writeTx: writeTx)
    }

    private func setMetadata(_ metadata: KeyMetadata?, for keyId: KeyId, writeTx: DBWriteTransaction) {
        do {
            if let metadata {
                owsAssertDebug(metadata.keyId == keyId)
                try keyMetadataStore.setCodable(metadata, key: keyId, transaction: writeTx)
            } else {
                keyMetadataStore.removeValue(forKey: keyId, transaction: writeTx)
            }
        } catch {
            owsFailDebug("Failed to persist sender key: \(error)")
        }
    }

    private func distributionIdForSendingToThreadId(_ threadId: ThreadUniqueId, readTx: DBReadTransaction) -> DistributionId? {
        if
            let persistedString: String = sendingDistributionIdStore.getString(threadId, transaction: readTx),
            let persistedUUID = UUID(uuidString: persistedString)
        {
            return persistedUUID
        } else {
            // No distributionId yet. Return nil.
            return nil
        }
    }

    private func keyIdForSendingToThreadId(_ threadId: ThreadUniqueId, readTx: DBReadTransaction) -> KeyId? {
        guard let localAci = DependenciesBridge.shared.tsAccountManager.localIdentifiers(tx: readTx)?.aci else {
            owsFailDebug("Not registered.")
            return nil
        }
        guard let distributionId = distributionIdForSendingToThreadId(threadId, readTx: readTx) else {
            return nil
        }
        return Self.buildKeyId(authorAci: localAci, distributionId: distributionId)
    }

    private func distributionIdForSendingToThreadId(_ threadId: ThreadUniqueId, writeTx: DBWriteTransaction) -> DistributionId {
        if let existingId = distributionIdForSendingToThreadId(threadId, readTx: writeTx) {
            return existingId
        } else {
            let distributionId = UUID()
            sendingDistributionIdStore.setString(distributionId.uuidString, key: threadId, transaction: writeTx)
            return distributionId
        }
    }

    private func keyIdForSendingToThreadId(_ threadId: ThreadUniqueId, writeTx: DBWriteTransaction) -> KeyId? {
        guard let localAci = DependenciesBridge.shared.tsAccountManager.localIdentifiers(tx: writeTx)?.aci else {
            owsFailDebug("Not registered.")
            return nil
        }
        let distributionId = distributionIdForSendingToThreadId(threadId, writeTx: writeTx)
        return Self.buildKeyId(authorAci: localAci, distributionId: distributionId)
    }

    // MARK: Migration

    static func performKeyIdMigration(transaction writeTx: DBWriteTransaction) {
        let oldKeys = keyMetadataStore.allKeys(transaction: writeTx)

        oldKeys.forEach { oldKey in
            autoreleasepool {
                do {
                    let existingValue: KeyMetadata? = try keyMetadataStore.getCodableValue(forKey: oldKey, transaction: writeTx)
                    if let existingValue, existingValue.keyId != oldKey {
                        try keyMetadataStore.setCodable(existingValue, key: existingValue.keyId, transaction: writeTx)
                        keyMetadataStore.removeValue(forKey: oldKey, transaction: writeTx)
                    }
                } catch {
                    owsFailDebug("Failed to serialize key metadata: \(error)")
                    keyMetadataStore.removeValue(forKey: oldKey, transaction: writeTx)
                }
            }
        }
    }
}

// MARK: - Model

// MARK: SKDMSendInfo

/// Stores information about a sent SKDM
/// Currently just tracks the sent timestamp and the recipient.
private struct SKDMSendInfo: Codable {
    let keyRecipient: SenderKeySentToRecipient
}

// MARK: RecipientDeviceState

private struct RecipientDeviceState {
    var deviceId: DeviceId
    var registrationId: UInt32?
}

// MARK: SenderKeySentToRecipientDevice

struct SenderKeySentToRecipientDevice: Codable, Hashable {
    let deviceId: DeviceId
    let registrationId: UInt32
}

// MARK: SenderKeySentToRecipient

/// Stores information about a recipient of a sender key
/// Helpful for diffing across deviceId and registrationId changes.
/// If a new device shows up, we need to make sure that we send a copy of our sender key to the address
private struct SenderKeySentToRecipient: Codable {

    enum CodingKeys: String, CodingKey {
        case devices

        // We previously stored "ownerAddress" on the recipient. This is redundant
        // because "sentKeyInfo" stores the same value, and that's the one we use.
    }

    let devices: Set<SenderKeySentToRecipientDevice>

    fileprivate init(devices: Set<SenderKeySentToRecipientDevice>) {
        self.devices = devices
    }
}

// MARK: KeyMetadata

/// Stores information about a sender key, it's owner, it's distributionId, and all recipients who have been sent the sender key
private struct KeyMetadata {
    let distributionId: OldSenderKeyStore.DistributionId
    @AciUuid var ownerAci: Aci
    let ownerDeviceId: DeviceId

    var keyId: String { OldSenderKeyStore.buildKeyId(authorAci: ownerAci, distributionId: distributionId) }

    private var serializedRecord: Data
    var record: SenderKeyRecord? {
        get {
            do {
                return try SenderKeyRecord(bytes: serializedRecord)
            } catch {
                owsFailDebug("Failed to deserialize sender key record")
                return nil
            }
        }
        set {
            if let newValue {
                serializedRecord = newValue.serialize()
            } else {
                owsFailDebug("Invalid new value")
                serializedRecord = Data()
            }
        }
    }

    let creationDate: Date
    var isForEncrypting: Bool
    private(set) var sentKeyInfo: [SignalServiceAddress: SKDMSendInfo]
    var currentRecipients: Set<SignalServiceAddress> { Set(sentKeyInfo.keys) }

    init(
        record: SenderKeyRecord,
        senderAci: Aci,
        senderDeviceId: DeviceId,
        localIdentifiers: LocalIdentifiers,
        localDeviceId: LocalDeviceId,
        distributionId: OldSenderKeyStore.DistributionId,
    ) {
        self.serializedRecord = record.serialize()
        self.distributionId = distributionId
        self._ownerAci = AciUuid(wrappedValue: senderAci)
        self.ownerDeviceId = senderDeviceId
        self.isForEncrypting = senderAci == localIdentifiers.aci && localDeviceId.equals(senderDeviceId)
        self.creationDate = Date()
        self.sentKeyInfo = [:]
    }

    func isValid(maxSenderKeyAge: TimeInterval) -> Bool {
        switch isForEncrypting {
        case true:
            return -creationDate.timeIntervalSinceNow < maxSenderKeyAge
        case false:
            // Keys we've received from others are always valid
            return true
        }
    }

    mutating func resetDeliveryRecord(for serviceId: ServiceId) {
        sentKeyInfo[SignalServiceAddress(serviceId)] = nil
    }

    mutating func recordSentSenderKey(_ sentSenderKey: SentSenderKey) {
        let recipient = SenderKeySentToRecipient(devices: Set(sentSenderKey.messages.map {
            return SenderKeySentToRecipientDevice(deviceId: $0.destinationDeviceId, registrationId: $0.destinationRegistrationId)
        }))
        let sendInfo = SKDMSendInfo(keyRecipient: recipient)
        sentKeyInfo[SignalServiceAddress(sentSenderKey.recipient)] = sendInfo
    }
}

extension KeyMetadata: Codable {
    enum CodingKeys: String, CodingKey {
        case distributionId
        case ownerAci = "ownerUuid"
        case ownerDeviceId
        case serializedRecord

        case creationDate
        case sentKeyInfo
        case isForEncrypting

        enum LegacyKeys: String, CodingKey {
            case keyRecipients
            case recordData
        }
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let legacyValues = try decoder.container(keyedBy: CodingKeys.LegacyKeys.self)

        distributionId = try container.decode(OldSenderKeyStore.DistributionId.self, forKey: .distributionId)
        _ownerAci = try container.decode(AciUuid.self, forKey: .ownerAci)
        ownerDeviceId = try container.decode(DeviceId.self, forKey: .ownerDeviceId)
        creationDate = try container.decode(Date.self, forKey: .creationDate)
        isForEncrypting = try container.decode(Bool.self, forKey: .isForEncrypting)

        // We used to store this as an Array, but that serializes poorly in most Codable formats. Now we use Data.
        if let serializedRecord = try container.decodeIfPresent(Data.self, forKey: .serializedRecord) {
            self.serializedRecord = serializedRecord
        } else if let recordData = try legacyValues.decodeIfPresent([UInt8].self, forKey: .recordData) {
            serializedRecord = Data(recordData)
        } else {
            // We lost the entire record. "This should never happen."
            throw OWSAssertionError("failed to deserialize SenderKey record")
        }

        // There have been a few iterations of our delivery tracking. Briefly we have:
        // - V1: We just recorded a mapping from UUID -> Set<DeviceIds>
        // - V2: Record a mapping of SignalServiceAddress -> SenderKeySentToRecipient. This allowed us to
        //       track additional info about the recipient of a key like registrationId
        // - V3: Record a mapping of SignalServiceAddress -> SKDMSendInfo. This allows us to
        //       record even more information about the send that's not specific to the recipient.
        //       Right now, this is just used to record the SKDM timestamp.
        //
        // Hopefully this doesn't need to change in the future. We now have a place to hang information
        // about the recipient (SenderKeySentToRecipient) and the context of the sent SKDM (SKDMSendInfo)
        if let sendInfo = try container.decodeIfPresent([SignalServiceAddress: SKDMSendInfo].self, forKey: .sentKeyInfo) {
            sentKeyInfo = sendInfo
        } else if let keyRecipients = try legacyValues.decodeIfPresent([SignalServiceAddress: SenderKeySentToRecipient].self, forKey: .keyRecipients) {
            sentKeyInfo = keyRecipients.mapValues { SKDMSendInfo(keyRecipient: $0) }
        } else {
            // There's no way to migrate from our V1 storage. That's okay, we can just reset the dictionary. The only
            // consequence here is we'll resend an SKDM that our recipients already have. No big deal.
            sentKeyInfo = [:]
        }
    }
}

// MARK: - Helper extensions

private typealias ThreadUniqueId = String
private extension TSThread {
    var threadUniqueId: ThreadUniqueId { uniqueId }
}
