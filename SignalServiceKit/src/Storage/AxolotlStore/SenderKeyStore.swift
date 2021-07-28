//
//  Copyright (c) 2021 Open Whisper Systems. All rights reserved.
//

import SignalClient

@objc
public class SenderKeyStore: NSObject {
    public typealias DistributionId = UUID

    // MARK: - Storage properties
    private let storageLock = UnfairLock()
    private var sendingDistributionIdCache: [ThreadUniqueId: DistributionId] = [:]
    private var keyCache: [DistributionId: KeyMetadata] = [:]

    public override init() {
        super.init()
        SwiftSingletons.register(self)
    }

    /// Returns the distributionId the current device uses to tag senderKey messages sent to the thread.
    public func distributionIdForSendingToThread(_ thread: TSGroupThread, writeTx: SDSAnyWriteTransaction) -> DistributionId {
        storageLock.withLock {
            distributionIdForSendingToThreadId(thread.threadUniqueId, writeTx: writeTx)
        }
    }

    /// Returns a list of addresses that may not have the current device's sender key for the thread.
    @objc
    public func recipientsInNeedOfSenderKey(
        for thread: TSGroupThread,
        addresses: [SignalServiceAddress],
        writeTx: SDSAnyWriteTransaction
    ) throws -> [SignalServiceAddress] {

        let allRecipients = addresses.compactMap {
            SignalRecipient.get(address: $0, mustHaveDevices: false, transaction: writeTx)
        }
        guard allRecipients.count == addresses.count,
              allRecipients.allSatisfy({ $0.address.uuid != nil }) else {
            owsFailDebug("All sender key recipients must have UUID")
            return []
        }

        let allDevicesMap: [SignalServiceAddress: Set<UInt32>] = try allRecipients
            .reduce(into: [:]) { (builder, recipient) in
                if let deviceArray = recipient.devices.array as? [NSNumber] {
                    builder[recipient.address] = Set(deviceArray.map { $0.uint32Value })
                } else {
                    throw OWSAssertionError("Invalid device array")
                }
            }

        return storageLock.withLock {
            let distributionId = distributionIdForSendingToThreadId(thread.threadUniqueId, writeTx: writeTx)
            guard let deliveredDevices = getKeyMetadata(for: distributionId, readTx: writeTx)?.deliveredDevices else {
                return Array(allDevicesMap.keys)
            }

            return Array(allDevicesMap.filter { (address: SignalServiceAddress, currentDeviceSet: Set<UInt32>) in
                guard let uuid = address.uuid else {
                    owsFailDebug("Invalid address.")
                    return false
                }

                // We should send a sender key distribution message to the candidate address if its
                // current device set contains devices that we haven't already delivered a sender key to
                if let alreadyDeliveredDevices = deliveredDevices[uuid] {
                    return currentDeviceSet.subtracting(alreadyDeliveredDevices).isEmpty == false
                } else {
                    return true
                }
            }.keys)
        }
    }

    /// Records that the current sender key for the `thread` has been delivered to `participant`
    public func recordSenderKeyDelivery(
        for thread: TSGroupThread,
        to address: SignalServiceAddress,
        writeTx: SDSAnyWriteTransaction) throws {
        guard let uuid = address.uuid else { throw OWSAssertionError("Invalid address") }
        guard let recipient = SignalRecipient.get(address: address, mustHaveDevices: false, transaction: writeTx) else {
            throw OWSAssertionError("Missing recipient")
        }
        guard let currentDeviceSet = (recipient.devices.array as? [NSNumber])?.map({ $0.uint32Value }) else {
            throw OWSAssertionError("Invalid device set")
        }

        storageLock.withLock {
            let distributionId = distributionIdForSendingToThreadId(thread.threadUniqueId, writeTx: writeTx)
            guard let existingMetadata = getKeyMetadata(for: distributionId, readTx: writeTx) else {
                owsFailDebug("Failed to look up metadata")
                return
            }
            var updatedMetadata = existingMetadata
            updatedMetadata.deliveredDevices[uuid, default: Set()].formUnion(currentDeviceSet)
            setMetadata(updatedMetadata, for: distributionId, writeTx: writeTx)
        }
    }

    @objc
    public func resetSenderKeyDeliveryRecord(
        for thread: TSGroupThread,
        address: SignalServiceAddress,
        writeTx: SDSAnyWriteTransaction) {

        guard let uuid = address.uuid else { return }
        storageLock.withLock {
            let distributionId = distributionIdForSendingToThreadId(thread.threadUniqueId, writeTx: writeTx)
            guard let existingMetadata = getKeyMetadata(for: distributionId, readTx: writeTx) else {
                owsFailDebug("Failed to look up metadata")
                return
            }
            var updatedMetadata = existingMetadata
            updatedMetadata.deliveredDevices[uuid] = Set()
            setMetadata(updatedMetadata, for: distributionId, writeTx: writeTx)
        }
    }

    public func expireSendingKeyIfNecessary(for thread: TSGroupThread, writeTx: SDSAnyWriteTransaction) {
        storageLock.withLock {
            let distributionId = distributionIdForSendingToThreadId(thread.uniqueId, writeTx: writeTx)
            guard let keyMetadata = getKeyMetadata(for: distributionId, readTx: writeTx) else { return }

            if !keyMetadata.isValid {
                setMetadata(nil, for: distributionId, writeTx: writeTx)
            }
        }
    }

    @objc
    public func resetSenderKeySession(for thread: TSGroupThread, transaction writeTx: SDSAnyWriteTransaction) {
        storageLock.withLock {
            let distributionId = distributionIdForSendingToThreadId(thread.threadUniqueId, writeTx: writeTx)
            setMetadata(nil, for: distributionId, writeTx: writeTx)
        }
    }

    @objc
    public func resetSenderKeyStore(transaction writeTx: SDSAnyWriteTransaction) {
        storageLock.withLock {
            sendingDistributionIdCache = [:]
            keyCache = [:]
            keyMetadataStore.removeAll(transaction: writeTx)
            sendingDistributionIdStore.removeAll(transaction: writeTx)
        }
    }

    public func skdmBytesForGroupThread(_ groupThread: TSGroupThread, writeTx: SDSAnyWriteTransaction) -> Data? {
        do {
            guard let localAddress = ProtocolAddress.localAddress, localAddress.uuid != nil else {
                throw OWSAssertionError("No local address")
            }
            let distributionId = distributionIdForSendingToThread(groupThread, writeTx: writeTx)
            let skdm = try SenderKeyDistributionMessage(from: localAddress,
                                                        distributionId: distributionId,
                                                        store: self,
                                                        context: writeTx)
            return Data(skdm.serialize())
        } catch {
            owsFailDebug("Failed to construct sender key message: \(error)")
            return nil
        }
    }
}

extension SenderKeyStore: SignalClient.SenderKeyStore {

    public func storeSenderKey(
        from sender: ProtocolAddress,
        distributionId: UUID,
        record: SenderKeyRecord,
        context: StoreContext
    ) throws {
        try storageLock.withLock {
            let writeTx = context.asTransaction

            var updatedValue: KeyMetadata
            if let existingMetadata = getKeyMetadata(for: distributionId, readTx: writeTx) {
                updatedValue = existingMetadata
            } else {
                updatedValue = try KeyMetadata(record: record, sender: sender, distributionId: distributionId)
            }
            updatedValue.record = record
            setMetadata(updatedValue, for: distributionId, writeTx: writeTx)
        }
    }

    public func loadSenderKey(
        from sender: ProtocolAddress,
        distributionId: UUID,
        context: StoreContext
    ) throws -> SenderKeyRecord? {
        storageLock.withLock {
            let readTx = context.asTransaction
            let metadata = getKeyMetadata(for: distributionId, readTx: readTx)
            return metadata?.record
        }
    }
}

// MARK: - Storage

fileprivate extension SenderKeyStore {
    private static let sendingDistributionIdStore = SDSKeyValueStore(collection: "SenderKeyStore_SendingDistributionId")
    private static let keyMetadataStore = SDSKeyValueStore(collection: "SenderKeyStore_KeyMetadata")
    private var sendingDistributionIdStore: SDSKeyValueStore { Self.sendingDistributionIdStore }
    private var keyMetadataStore: SDSKeyValueStore { Self.keyMetadataStore }

    func getKeyMetadata(for distributionId: DistributionId, readTx: SDSAnyReadTransaction) -> KeyMetadata? {
        storageLock.assertOwner()
        return keyCache[distributionId] ?? {
            let persisted: KeyMetadata?
            do {
                persisted = try keyMetadataStore.getCodableValue(forKey: distributionId.uuidString, transaction: readTx)
            } catch {
                owsFailDebug("Failed to deserialize sender key: \(error)")
                persisted = nil
            }
            keyCache[distributionId] = persisted
            return persisted
        }()
    }

    func setMetadata(_ metadata: KeyMetadata?, for distributionId: DistributionId, writeTx: SDSAnyWriteTransaction) {
        storageLock.assertOwner()
        do {
            if let metadata = metadata {
                try keyMetadataStore.setCodable(metadata, key: distributionId.uuidString, transaction: writeTx)
            } else {
                keyMetadataStore.removeValue(forKey: distributionId.uuidString, transaction: writeTx)
            }
            keyCache[distributionId] = metadata
        } catch {
            owsFailDebug("Failed to persist sender key: \(error)")
        }
    }

    func distributionIdForSendingToThreadId(_ threadId: ThreadUniqueId, writeTx: SDSAnyWriteTransaction) -> DistributionId {
        storageLock.assertOwner()

        if let cachedValue = sendingDistributionIdCache[threadId] {
            return cachedValue
        } else if let persistedString: String = sendingDistributionIdStore.getString(threadId, transaction: writeTx),
                  let persistedUUID = UUID(uuidString: persistedString) {
            sendingDistributionIdCache[threadId] = persistedUUID
            return persistedUUID
        } else {
            let distributionId = UUID()
            sendingDistributionIdStore.setString(distributionId.uuidString, key: threadId, transaction: writeTx)
            sendingDistributionIdCache[threadId] = distributionId
            return distributionId
        }
    }
}

// MARK: - Model

private struct KeyMetadata: Codable {
    let distributionId: SenderKeyStore.DistributionId
    let ownerUuid: UUID
    let ownerDeviceId: UInt32

    private var recordData: [UInt8]
    var record: SenderKeyRecord? {
        get {
            do {
                return try SenderKeyRecord(bytes: recordData)
            } catch {
                owsFailDebug("Failed to deserialize sender key record")
                return nil
            }
        }
        set {
            if let newValue = newValue {
                recordData = newValue.serialize()
            } else {
                owsFailDebug("Invalid new value")
                recordData = []
            }
        }
    }

    let creationDate: Date
    var deliveredDevices: [UUID: Set<UInt32>]
    var isForEncrypting: Bool

    init(record: SenderKeyRecord, sender: ProtocolAddress, distributionId: SenderKeyStore.DistributionId) throws {
        guard let uuid = sender.uuid else {
            throw OWSAssertionError("Invalid sender. Must have UUID")
        }

        self.recordData = record.serialize()
        self.distributionId = distributionId
        self.ownerUuid = uuid
        self.ownerDeviceId = sender.deviceId

        self.isForEncrypting = sender.isCurrentDevice
        self.creationDate = Date()
        self.deliveredDevices = [:]
    }

    var isValid: Bool {
        // Keys we've received from others are always valid
        guard isForEncrypting else { return true }

        // If we're using it for encryption, it must be less than a month old
        let expirationDate = creationDate.addingTimeInterval(kMonthInterval)
        return (expirationDate.isAfterNow && isForEncrypting)
    }
}

// MARK: - Helper extensions

private typealias ThreadUniqueId = String
fileprivate extension TSGroupThread {
    var threadUniqueId: ThreadUniqueId { uniqueId }
}

extension ProtocolAddress {

    // TODO: Replace implementation for Swift 5.5 with throwable computed properties
    //    static var localAddress: ProtocolAddress {
    //        get throws {
    //            ...
    //            guard let address = address else { throw OWSAssertionError("No recipient address") }
    //            return try ProtocolAddress(from: address, deviceId: deviceId)
    @available(swift, obsoleted: 5.5, message: "Please swap out commented implementation in SenderKeyStore.swift")
    static var localAddress: ProtocolAddress? {
        get {
            let tsAccountManager = SSKEnvironment.shared.tsAccountManager
            let address = tsAccountManager.localAddress
            let deviceId = SSKEnvironment.shared.tsAccountManager.storedDeviceId()
            return try? address.map { try ProtocolAddress(from: $0, deviceId: deviceId) }
        }
    }

    convenience init(from recipientAddress: SignalServiceAddress, deviceId: UInt32) throws {
        if let uuid = recipientAddress.uuid {
            try self.init(uuid: uuid, deviceId: deviceId)
        } else {
            try self.init(name: recipientAddress.phoneNumber!, deviceId: deviceId)
        }
    }

    convenience init(uuid: UUID, deviceId: UInt32) throws {
        try self.init(name: uuid.uuidString, deviceId: deviceId)
    }

    var uuid: UUID? {
        UUID(uuidString: name)
    }

    var isCurrentDevice: Bool {
        let tsAccountManager = SSKEnvironment.shared.tsAccountManager
        return (uuid == tsAccountManager.localUuid) && (deviceId == tsAccountManager.storedDeviceId())
    }
}
