//
//  Copyright (c) 2020 Open Whisper Systems. All rights reserved.
//

import SignalClient

@objc
public class SenderKeyStore: NSObject {

    // MARK: - Storage properties
    private let storageLock = UnfairLock()
    private var sendingDistributionIdCache: [ThreadUniqueId: UUID] = [:]
    private var keyCache: [UUID: KeyMetadata] = [:]

    public override init() {
        super.init()
        SwiftSingletons.register(self)
    }

    /// Returns the distributionId the current device uses to tag senderKey messages sent to the thread.
    public func distributionIdForSendingToThread(_ thread: TSGroupThread, writeTx: SDSAnyWriteTransaction) -> UUID {
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
    ) -> [SignalServiceAddress] {

        let allRecipients = addresses.compactMap { SignalRecipient.get(address: $0, mustHaveDevices: false, transaction: writeTx) }
        guard allRecipients.count == addresses.count,
              allRecipients.allSatisfy({ $0.address.uuid != nil }) else {
            owsFailDebug("")
            return []
        }

        let allDevicesMap: [SignalServiceAddress: Set<UInt32>] = allRecipients.reduce(into: [:]) { (builder, recipient) in
            if let deviceArray = recipient.devices.array as? [NSNumber] {
                builder[recipient.address] = Set(deviceArray.map { $0.uint32Value })
            } else {
                owsFailDebug("Invalid device array")
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
        writeTx: SDSAnyWriteTransaction) {

        // TODO: owsFailDebug
        guard let recipient = SignalRecipient.get(address: address, mustHaveDevices: false, transaction: writeTx) else { return }
        guard let uuid = address.uuid else { return }
        guard let currentDeviceSet = (recipient.devices.array as? [NSNumber])?.map({ $0.uint32Value }) else { return }

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

    // TODO
    public func resetSenderKeyDeliverRecord(
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

    public func skdmBytesForGroupThread(_ groupThread: TSGroupThread, writeTx: SDSAnyWriteTransaction) -> Data? {
        do {
            guard let localAddress = tsAccountManager.localAddress else {
                throw OWSAssertionError("No local address")
            }
            let protocolAddress = try ProtocolAddress(from: localAddress, deviceId: tsAccountManager.storedDeviceId())
            let distributionId = distributionIdForSendingToThread(groupThread, writeTx: writeTx)
            let skdm = try SenderKeyDistributionMessage(from: protocolAddress,
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
        storageLock.withLock {
            let writeTx = context.asTransaction
            let metadata = KeyMetadata(record: record, sender: sender, distributionId: distributionId, readTx: writeTx)
            setMetadata(metadata, for: distributionId, writeTx: writeTx)
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

    func getKeyMetadata(for distributionId: UUID, readTx: SDSAnyReadTransaction) -> KeyMetadata? {
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

    func setMetadata(_ metadata: KeyMetadata?, for distributionId: UUID, writeTx: SDSAnyWriteTransaction) {
        storageLock.assertOwner()
        do {
            try keyMetadataStore.setCodable(metadata, key: distributionId.uuidString, transaction: writeTx)
            keyCache[distributionId] = metadata
        } catch {
            owsFailDebug("Failed to persist sender key: \(error)")
        }
    }

    func distributionIdForSendingToThreadId(_ threadId: ThreadUniqueId, writeTx: SDSAnyWriteTransaction) -> UUID {
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

fileprivate struct KeyMetadata: Codable {
    let distributionId: UUID
    let ownerUuid: UUID
    let ownerDeviceId: UInt32

    private let recordData: [UInt8]
    var record: SenderKeyRecord? {
        do {
            return try SenderKeyRecord(bytes: recordData)
        } catch {
            owsFailDebug("Failed to deserialize sender key record")
            return nil
        }
    }

    var deliveredDevices: [UUID: Set<UInt32>]
    let creationDate: Date

    init?(record: SenderKeyRecord, sender: ProtocolAddress, distributionId: UUID, readTx: SDSAnyReadTransaction) {
        self.recordData = record.serialize()
        self.distributionId = distributionId
        self.ownerUuid = sender.uuid
        self.ownerDeviceId = sender.deviceId
        self.creationDate = Date()
        self.deliveredDevices = [:]
    }
}

// MARK: - Helper extensions

fileprivate typealias ThreadUniqueId = String
fileprivate extension TSGroupThread {
    var threadUniqueId: ThreadUniqueId { uniqueId }
}

fileprivate extension ProtocolAddress {
    convenience init(from recipientAddress: SignalServiceAddress, deviceId: UInt32) throws {
        try self.init(name: recipientAddress.uuidString ?? recipientAddress.phoneNumber!, deviceId: deviceId)
    }

    var uuid: UUID {
        UUID(uuidString: name) ?? {
            owsFailDebug("Bad uuid string")
            return UUID()
        }()
    }
}
