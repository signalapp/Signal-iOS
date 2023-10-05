//
// Copyright 2021 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import LibSignalClient

@objc
public class SenderKeyStore: NSObject {
    public typealias DistributionId = UUID
    fileprivate typealias KeyId = String
    fileprivate static func buildKeyId(authorAci: Aci, distributionId: DistributionId) -> KeyId {
        "\(authorAci.serviceIdUppercaseString).\(distributionId.uuidString)"
    }

    // MARK: - Storage properties
    private let storageLock = UnfairLock()
    private var sendingDistributionIdCache: LRUCache<ThreadUniqueId, DistributionId> = LRUCache(maxSize: 100)
    private var keyCache: LRUCache<KeyId, KeyMetadata> = LRUCache(maxSize: 100)

    public override init() {
        super.init()
        SwiftSingletons.register(self)

        // We need to clear the key cache on cross-process database writes,
        // because other processes might have received a new SKDM or generated a new chain...
        NotificationCenter.default.addObserver(keyCache,
                                               selector: #selector(keyCache.clear),
                                               name: SDSDatabaseStorage.didReceiveCrossProcessNotificationAlwaysSync,
                                               object: nil)
        // ...but we don't need to clear the sending distribution ID cache, since values in that table don't change once
        // set (unless the user clears all their sender key state, which only happens when re-registering).
    }

    /// Returns the distributionId the current device uses to tag senderKey messages sent to the thread.
    public func distributionIdForSendingToThread(_ thread: TSThread, writeTx: SDSAnyWriteTransaction) -> DistributionId {
        storageLock.withLock {
            distributionIdForSendingToThreadId(thread.threadUniqueId, writeTx: writeTx)
        }
    }

    /// Returns a list of addresses that may not have the current device's sender key for the thread.
    public func recipientsInNeedOfSenderKey(
        for thread: TSThread,
        serviceIds: [ServiceId],
        readTx: SDSAnyReadTransaction
    ) -> [ServiceId] {
        var serviceIdsNeedingSenderKey = Set(serviceIds)

        storageLock.withLock {
            // If we haven't saved a distributionId yet, then there's no way we have any keyMetadata cached
            // All intended recipients will certainly need an SKDM (if they even support sender key)
            guard
                let keyId = keyIdForSendingToThreadId(thread.threadUniqueId, readTx: readTx),
                let keyMetadata = getKeyMetadata(for: keyId, readTx: readTx)
            else {
                return
            }

            // Iterate over each cached recipient. If no new devices or reregistrations have occurred since
            // we last recorded an SKDM send, we can skip sending to them.
            for (address, sendInfo) in keyMetadata.sentKeyInfo {
                guard let serviceId = address.serviceId else {
                    continue
                }
                do {
                    let priorSendRecipientState = sendInfo.keyRecipient

                    // Only remove the recipient in question from our send targets if the cached state contains
                    // every device from the current state. Any new devices mean we need to re-send.
                    let currentRecipientState = try KeyRecipient.currentState(for: serviceId, transaction: readTx)
                    if priorSendRecipientState.containsEveryDevice(from: currentRecipientState) {
                        serviceIdsNeedingSenderKey.remove(serviceId)
                    }
                } catch {
                    // It's likely there's no session for the current recipient. Maybe it was cleared?
                    // In this case, we just assume we need to send a new SKDM
                    if case SignalError.invalidState(_) = error {
                        Logger.warn("Invalid session state. Cannot build recipient state for \(serviceId). \(error)")
                    } else {
                        owsFailDebug("Failed to fetch current recipient state for \(serviceId): \(error)")
                    }
                }
            }
        }
        return Array(serviceIdsNeedingSenderKey)
    }

    /// Records that the current sender key for the `thread` has been sent to `participant`
    @objc
    public func recordSenderKeySent(
        for thread: TSThread,
        to serviceId: ServiceIdObjC,
        timestamp: UInt64,
        writeTx: SDSAnyWriteTransaction) throws {
        try storageLock.withLock {
            guard
                let keyId = keyIdForSendingToThreadId(thread.threadUniqueId, writeTx: writeTx),
                let existingMetadata = getKeyMetadata(for: keyId, readTx: writeTx)
            else {
                throw OWSAssertionError("Failed to look up key metadata")
            }
            var updatedMetadata = existingMetadata
            try updatedMetadata.recordSKDMSent(at: timestamp, serviceId: serviceId.wrappedValue, transaction: writeTx)
            setMetadata(updatedMetadata, writeTx: writeTx)
        }
    }

    public func resetSenderKeyDeliveryRecord(
        for thread: TSThread,
        serviceId: ServiceId,
        writeTx: SDSAnyWriteTransaction
    ) {
        storageLock.withLock {
            guard let keyId = keyIdForSendingToThreadId(thread.threadUniqueId, writeTx: writeTx),
                  let existingMetadata = getKeyMetadata(for: keyId, readTx: writeTx) else {
                Logger.info("Failed to look up senderkey metadata")
                return
            }
            var updatedMetadata = existingMetadata
            updatedMetadata.resetDeliveryRecord(for: serviceId)
            setMetadata(updatedMetadata, writeTx: writeTx)
        }
    }

    private func _locked_isKeyValid(for thread: TSThread, readTx: SDSAnyReadTransaction) -> Bool {
        storageLock.assertOwner()

        guard let keyId = keyIdForSendingToThreadId(thread.threadUniqueId, readTx: readTx),
              let keyMetadata = getKeyMetadata(for: keyId, readTx: readTx) else { return false }

        guard keyMetadata.isValid else { return false }

        let currentRecipients = thread.recipientAddresses(with: readTx)
        let wasRecipientRemovedFromThread = keyMetadata.currentRecipients.subtracting(currentRecipients).count > 0

        return keyMetadata.isValid && !wasRecipientRemovedFromThread
    }

    public func isKeyValid(for thread: TSThread, readTx: SDSAnyReadTransaction) -> Bool {
        storageLock.withLock {
            _locked_isKeyValid(for: thread, readTx: readTx)
        }
    }

    public func expireSendingKeyIfNecessary(for thread: TSThread, writeTx: SDSAnyWriteTransaction) {
        storageLock.withLock {
            guard let keyId = keyIdForSendingToThreadId(thread.threadUniqueId, readTx: writeTx) else { return }

            if !_locked_isKeyValid(for: thread, readTx: writeTx) {
                setMetadata(nil, for: keyId, writeTx: writeTx)
            }
        }
    }

    @objc
    public func resetSenderKeySession(for thread: TSThread, transaction writeTx: SDSAnyWriteTransaction) {
        storageLock.withLock {
            guard let keyId = keyIdForSendingToThreadId(thread.threadUniqueId, writeTx: writeTx) else { return }
            setMetadata(nil, for: keyId, writeTx: writeTx)
        }
    }

    @objc
    public func resetSenderKeyStore(transaction writeTx: SDSAnyWriteTransaction) {
        storageLock.withLock {
            sendingDistributionIdCache.clear()
            keyCache.clear()
            keyMetadataStore.removeAll(transaction: writeTx)
            sendingDistributionIdStore.removeAll(transaction: writeTx)
        }
    }

    @objc
    public func skdmBytesForThread(_ thread: TSThread, tx: SDSAnyWriteTransaction) -> Data? {
        guard let localIdentifiers = DependenciesBridge.shared.tsAccountManager.localIdentifiers(tx: tx.asV2Read) else {
            return nil
        }
        return skdmBytesForThread(
            thread,
            localAci: localIdentifiers.aci,
            localDeviceId: DependenciesBridge.shared.tsAccountManager.storedDeviceId(tx: tx.asV2Read),
            tx: tx
        )
    }

    public func skdmBytesForThread(
        _ thread: TSThread,
        localAci: Aci,
        localDeviceId: UInt32,
        tx: SDSAnyWriteTransaction
    ) -> Data? {
        do {
            let localAddress = ProtocolAddress(localAci, deviceId: localDeviceId)
            let distributionId = distributionIdForSendingToThread(thread, writeTx: tx)
            let skdm = try SenderKeyDistributionMessage(
                from: localAddress,
                distributionId: distributionId,
                store: self,
                context: tx
            )
            return Data(skdm.serialize())
        } catch {
            owsFailDebug("Failed to construct sender key message: \(error)")
            return nil
        }
    }
}

// MARK: - <LibSignalClient.SenderKeyStore>

extension SenderKeyStore: LibSignalClient.SenderKeyStore {
    public func storeSenderKey(
        from sender: ProtocolAddress,
        distributionId: UUID,
        record: SenderKeyRecord,
        context: StoreContext
    ) throws {
        let tx = context.asTransaction

        guard let senderAci = sender.serviceId as? Aci else {
            throw OWSAssertionError("Invalid protocol address: must have ACI")
        }

        guard let localIdentifiers = DependenciesBridge.shared.tsAccountManager.localIdentifiers(tx: tx.asV2Read) else {
            throw OWSAssertionError("Not registered.")
        }

        return storageLock.withLock {
            let keyId = Self.buildKeyId(authorAci: senderAci, distributionId: distributionId)

            var updatedValue: KeyMetadata
            if let existingMetadata = getKeyMetadata(for: keyId, readTx: tx) {
                updatedValue = existingMetadata
            } else {
                updatedValue = KeyMetadata(
                    record: record,
                    senderAci: senderAci,
                    senderDeviceId: sender.deviceId,
                    localIdentifiers: localIdentifiers,
                    localDeviceId: DependenciesBridge.shared.tsAccountManager.storedDeviceId(tx: tx.asV2Read),
                    distributionId: distributionId
                )
            }
            updatedValue.record = record
            setMetadata(updatedValue, writeTx: tx)
        }
    }

    public func loadSenderKey(
        from sender: ProtocolAddress,
        distributionId: UUID,
        context: StoreContext
    ) throws -> SenderKeyRecord? {
        guard let senderAci = sender.serviceId as? Aci else {
            throw OWSAssertionError("Invalid protocol address: must have ACI")
        }

        return storageLock.withLock {
            let readTx = context.asTransaction
            let keyId = Self.buildKeyId(authorAci: senderAci, distributionId: distributionId)
            let metadata = getKeyMetadata(for: keyId, readTx: readTx)
            return metadata?.record
        }
    }
}

// MARK: - Storage

extension SenderKeyStore {
    private static let sendingDistributionIdStore = SDSKeyValueStore(collection: "SenderKeyStore_SendingDistributionId")
    private static let keyMetadataStore = SDSKeyValueStore(collection: "SenderKeyStore_KeyMetadata")
    private var sendingDistributionIdStore: SDSKeyValueStore { Self.sendingDistributionIdStore }
    private var keyMetadataStore: SDSKeyValueStore { Self.keyMetadataStore }

    fileprivate func getKeyMetadata(for keyId: KeyId, readTx: SDSAnyReadTransaction) -> KeyMetadata? {
        storageLock.assertOwner()
        return keyCache[keyId] ?? {
            let persisted: KeyMetadata?
            do {
                persisted = try keyMetadataStore.getCodableValue(forKey: keyId, transaction: readTx)
            } catch {
                owsFailDebug("Failed to deserialize sender key: \(error)")
                persisted = nil
            }
            keyCache[keyId] = persisted
            return persisted
        }()
    }

    fileprivate func setMetadata(_ metadata: KeyMetadata, writeTx: SDSAnyWriteTransaction) {
        setMetadata(metadata, for: metadata.keyId, writeTx: writeTx)
    }

    fileprivate func setMetadata(_ metadata: KeyMetadata?, for keyId: KeyId, writeTx: SDSAnyWriteTransaction) {
        storageLock.assertOwner()
        do {
            if let metadata = metadata {
                owsAssertDebug(metadata.keyId == keyId)
                try keyMetadataStore.setCodable(metadata, key: keyId, transaction: writeTx)
            } else {
                keyMetadataStore.removeValue(forKey: keyId, transaction: writeTx)
            }
            keyCache[keyId] = metadata
        } catch {
            owsFailDebug("Failed to persist sender key: \(error)")
        }
    }

    fileprivate func distributionIdForSendingToThreadId(_ threadId: ThreadUniqueId, readTx: SDSAnyReadTransaction) -> DistributionId? {
        storageLock.assertOwner()

        if let cachedValue = sendingDistributionIdCache[threadId] {
            return cachedValue
        } else if let persistedString: String = sendingDistributionIdStore.getString(threadId, transaction: readTx),
                  let persistedUUID = UUID(uuidString: persistedString) {
            sendingDistributionIdCache[threadId] = persistedUUID
            return persistedUUID
        } else {
            // No distributionId yet. Return nil.
            return nil
        }
    }

    fileprivate func keyIdForSendingToThreadId(_ threadId: ThreadUniqueId, readTx: SDSAnyReadTransaction) -> KeyId? {
        storageLock.assertOwner()

        guard let localAci = DependenciesBridge.shared.tsAccountManager.localIdentifiers(tx: readTx.asV2Read)?.aci else {
            owsFailDebug("Not registered.")
            return nil
        }
        guard let distributionId = distributionIdForSendingToThreadId(threadId, readTx: readTx) else {
            return nil
        }
        return Self.buildKeyId(authorAci: localAci, distributionId: distributionId)
    }

    fileprivate func distributionIdForSendingToThreadId(_ threadId: ThreadUniqueId, writeTx: SDSAnyWriteTransaction) -> DistributionId {
        storageLock.assertOwner()

        if let existingId = distributionIdForSendingToThreadId(threadId, readTx: writeTx) {
            return existingId
        } else {
            let distributionId = UUID()
            sendingDistributionIdStore.setString(distributionId.uuidString, key: threadId, transaction: writeTx)
            sendingDistributionIdCache[threadId] = distributionId
            return distributionId
        }
    }

    fileprivate func keyIdForSendingToThreadId(_ threadId: ThreadUniqueId, writeTx: SDSAnyWriteTransaction) -> KeyId? {
        storageLock.assertOwner()

        guard let localAci = DependenciesBridge.shared.tsAccountManager.localIdentifiers(tx: writeTx.asV2Read)?.aci else {
            owsFailDebug("Not registered.")
            return nil
        }
        let distributionId = distributionIdForSendingToThreadId(threadId, writeTx: writeTx)
        return Self.buildKeyId(authorAci: localAci, distributionId: distributionId)
    }

    // MARK: Migration

    static func performKeyIdMigration(transaction writeTx: SDSAnyWriteTransaction) {
        let oldKeys = keyMetadataStore.allKeys(transaction: writeTx)

        oldKeys.forEach { oldKey in
            autoreleasepool {
                do {
                    let existingValue: KeyMetadata? = try keyMetadataStore.getCodableValue(forKey: oldKey, transaction: writeTx)
                    if let existingValue = existingValue, existingValue.keyId != oldKey {
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

    // MARK: Logging

    static private var logThrottleExpiration = AtomicValue<Date>(Date.distantPast)

    // This method traverses all groups where `recipient` is a member and logs out information on any sent
    // sender key distribution messages.
    public func logSKDMInfo(for recipient: SignalServiceAddress, transaction: SDSAnyReadTransaction) {
        guard let localAci = DependenciesBridge.shared.tsAccountManager.localIdentifiers(tx: transaction.asV2Read)?.aci else { return }

        // To avoid doing too much work for a flood of failed decryptions, we'll only honor an SKDM log
        // dump request every 10s. That's frequent enough to be captured in a log zip.
        guard Self.logThrottleExpiration.get().isBeforeNow else {
            Logger.info("Dumped SKDM logs recently. Ignoring request for \(recipient)...")
            return
        }
        Self.logThrottleExpiration.set(Date() + 10.0)

        // We deliberately avoid the cached pathways here and just query the database directly
        // Locality isn't super useful when we're just iterating over everything. This would just
        // cache a bunch of memory that we might not end up using later.
        Logger.info("Logging info about all SKDMs sent to \(recipient)")
        for commonThread in TSGroupThread.groupThreads(with: recipient, transaction: transaction) {
            autoreleasepool {
                let threadId = commonThread.threadUniqueId
                let distributionIdString = sendingDistributionIdStore.getString(threadId, transaction: transaction)
                let distributionId = distributionIdString.flatMap { UUID(uuidString: $0) }
                guard let distributionId = distributionId else { return }

                // Once we have a distributionId, for a thread, we'll log *something* for the thread
                let keyId = Self.buildKeyId(authorAci: localAci, distributionId: distributionId)
                let keyMetadata: KeyMetadata?
                do {
                    keyMetadata = try keyMetadataStore.getCodableValue(forKey: keyId, transaction: transaction)
                } catch {
                    owsFailDebug("Failed to deserialize key metadata \(error)")
                    keyMetadata = nil
                }

                let prefix = "--> Thread \(threadId) with distributionId \(distributionId):   "
                if let keyMetadata = keyMetadata, let sendInfo = keyMetadata.sentKeyInfo[recipient] {
                    Logger.info("\(prefix) Sent SKDM at timestamp: \(sendInfo.skdmTimestamp) for sender key created at: \(keyMetadata.creationDate)")
                } else if let keyMetadata = keyMetadata {
                    Logger.info("\(prefix) Have not sent SKDM for sender key created at: \(keyMetadata.creationDate). SKDM sent to \(keyMetadata.sentKeyInfo.count) others")
                } else {
                    Logger.info("\(prefix) No recorded key metadata")
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
    let skdmTimestamp: UInt64
    let keyRecipient: KeyRecipient
}

// MARK: KeyRecipient

/// Stores information about a recipient of a sender key
/// Helpful for diffing across deviceId and registrationId changes.
/// If a new device shows up, we need to make sure that we send a copy of our sender key to the address
private struct KeyRecipient: Codable, Dependencies {

    struct Device: Codable, Hashable {
        let deviceId: UInt32
        let registrationId: UInt32?

        init(deviceId: UInt32, registrationId: UInt32?) {
            self.deviceId = deviceId
            self.registrationId = registrationId
        }

        static func == (lhs: Device, rhs: Device) -> Bool {
            // We can only be sure that a device hasn't changed if the registrationIds
            // are the same. If either registrationId is nil, that means the Device was
            // constructed before we had a session established for the device.
            //
            // If we end up trying to send a SenderKey message to a device without a
            // session, this ensures that we will always send an SKDM to that device. A
            // session will be created in order to send the SKDM, so by the time we're
            // ready to mark success we should have something to store.
            guard lhs.registrationId != nil, rhs.registrationId != nil else { return false }
            return lhs.registrationId == rhs.registrationId && lhs.deviceId == rhs.deviceId
        }
    }

    enum CodingKeys: String, CodingKey {
        case devices

        // We previously stored "ownerAddress" on the recipient. This is redundant
        // because "sentKeyInfo" stores the same value, and that's the one we use.
    }

    let devices: Set<Device>

    private init(devices: Set<Device>) {
        self.devices = devices
    }

    /// Build a KeyRecipient for the given address by fetching all of the devices and corresponding registrationIds
    static func currentState(for serviceId: ServiceId, transaction: SDSAnyReadTransaction) throws -> KeyRecipient {
        guard
            let recipient = SignalRecipient.fetchRecipient(
                for: SignalServiceAddress(serviceId),
                onlyIfRegistered: false,
                tx: transaction
            )
        else {
            throw OWSAssertionError("Invalid device array")
        }
        let deviceIds = recipient.deviceIds
        let protocolAddresses = deviceIds.map { ProtocolAddress(serviceId, deviceId: $0) }
        let sessionStore = DependenciesBridge.shared.signalProtocolStoreManager.signalProtocolStore(for: .aci).sessionStore
        let devices: [Device] = try protocolAddresses.map {
            // We have to fetch the registrationId since deviceIds can be reused.
            // By comparing a set of (deviceId,registrationId) structs, we should be able to detect reused
            // deviceIds that will need an SKDM
            let registrationId = try sessionStore.loadSession(
                for: SignalServiceAddress(from: $0),
                deviceId: Int32($0.deviceId),
                tx: transaction.asV2Read
            )?.remoteRegistrationId()

            return Device(deviceId: $0.deviceId, registrationId: registrationId)
        }
        return KeyRecipient(devices: Set(devices))
    }

    /// Returns `true` as long as the argument does not contain any devices that are unknown to the receiver
    func containsEveryDevice(from other: KeyRecipient) -> Bool {
        let newDevices = other.devices.subtracting(self.devices)
        return newDevices.isEmpty
    }
}

// MARK: KeyMetadata

/// Stores information about a sender key, it's owner, it's distributionId, and all recipients who have been sent the sender key
private struct KeyMetadata {
    let distributionId: SenderKeyStore.DistributionId
    @AciUuid var ownerAci: Aci
    let ownerDeviceId: UInt32

    var keyId: String { SenderKeyStore.buildKeyId(authorAci: ownerAci, distributionId: distributionId) }

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
            if let newValue = newValue {
                serializedRecord = Data(newValue.serialize())
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
        senderDeviceId: UInt32,
        localIdentifiers: LocalIdentifiers,
        localDeviceId: UInt32,
        distributionId: SenderKeyStore.DistributionId
    ) {
        self.serializedRecord = Data(record.serialize())
        self.distributionId = distributionId
        self._ownerAci = AciUuid(wrappedValue: senderAci)
        self.ownerDeviceId = senderDeviceId
        self.isForEncrypting = senderAci == localIdentifiers.aci && senderDeviceId == localDeviceId
        self.creationDate = Date()
        self.sentKeyInfo = [:]
    }

    var isValid: Bool {
        // Keys we've received from others are always valid
        guard isForEncrypting else { return true }

        // If we're using it for encryption, it must be less than a month old
        let expirationDate = creationDate.addingTimeInterval(kMonthInterval)
        return (expirationDate.isAfterNow && isForEncrypting)
    }

    mutating func resetDeliveryRecord(for serviceId: ServiceId) {
        sentKeyInfo[SignalServiceAddress(serviceId)] = nil
    }

    mutating func recordSKDMSent(at timestamp: UInt64, serviceId: ServiceId, transaction: SDSAnyReadTransaction) throws {
        let recipient = try KeyRecipient.currentState(for: serviceId, transaction: transaction)
        let sendInfo = SKDMSendInfo(skdmTimestamp: timestamp, keyRecipient: recipient)
        sentKeyInfo[SignalServiceAddress(serviceId)] = sendInfo
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

        distributionId = try container.decode(SenderKeyStore.DistributionId.self, forKey: .distributionId)
        _ownerAci = try container.decode(AciUuid.self, forKey: .ownerAci)
        ownerDeviceId = try container.decode(UInt32.self, forKey: .ownerDeviceId)
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
        // - V2: Record a mapping of SignalServiceAddress -> KeyRecipient. This allowed us to
        //       track additional info about the recipient of a key like registrationId
        // - V3: Record a mapping of SignalServiceAddress -> SKDMSendInfo. This allows us to
        //       record even more information about the send that's not specific to the recipient.
        //       Right now, this is just used to record the SKDM timestamp.
        //
        // Hopefully this doesn't need to change in the future. We now have a place to hang information
        // about the recipient (KeyRecipient) and the context of the sent SKDM (SKDMSendInfo)
        if let sendInfo = try container.decodeIfPresent([SignalServiceAddress: SKDMSendInfo].self, forKey: .sentKeyInfo) {
            sentKeyInfo = sendInfo
        } else if let keyRecipients = try legacyValues.decodeIfPresent([SignalServiceAddress: KeyRecipient].self, forKey: .keyRecipients) {
            sentKeyInfo = keyRecipients.mapValues { SKDMSendInfo(skdmTimestamp: 0, keyRecipient: $0) }
        } else {
            // There's no way to migrate from our V1 storage. That's okay, we can just reset the dictionary. The only
            // consequence here is we'll resend an SKDM that our recipients already have. No big deal.
            sentKeyInfo = [:]
        }
    }
}

// MARK: - Helper extensions

private typealias ThreadUniqueId = String
fileprivate extension TSThread {
    var threadUniqueId: ThreadUniqueId { uniqueId }
}
