//
//  Copyright (c) 2020 Open Whisper Systems. All rights reserved.
//

import SignalClient

@objc
public class SenderKeyStore: NSObject {

    // MARK: - Storage properties
    private let storageLock = UnfairLock()
    private var threadMappingCache: [UUID: ThreadUniqueId] = [:]
    private var metadataCache: [SenderKeyNamespace.Id: SenderKeyMetadata] = [:]

    public override init() {
        super.init()
        SwiftSingletons.register(self)
    }

    /// Records a many-to-one mapping of distributionID to thread
    public func recordDistributionId(_ uuid: UUID, for thread: TSGroupThread, writeTx: SDSAnyWriteTransaction) {
        storageLock.withLock {
            setThreadId(thread.uniqueId, forDistributionId: uuid, writeTx: writeTx)
        }
    }

    /// Records that the current sender key for the `thread` has been delivered to `participant`
    public func recordSenderKeyDelivery(
        for thread: TSGroupThread,
        to participantUuid: UUID,
        participantDevice: UInt32,
        writeTx: SDSAnyWriteTransaction) {

        guard let namespace = SenderKeyNamespace(currentDeviceAndThreadId: thread.uniqueId) else { return }

        storageLock.withLock {
            guard let existingMetadata = getMetadata(for: namespace, readTx: writeTx) else {
                owsFailDebug("Failed to look up metadata")
                return
            }
            var updatedMetadata = existingMetadata
            updatedMetadata.deliveredDevices.insert(.init(uuid: participantUuid, deviceId: participantDevice))
            setMetadata(updatedMetadata, for: namespace, writeTx: writeTx)
        }
    }
}

extension SenderKeyStore: SignalClient.SenderKeyStore {

    public func storeSenderKey(
        from sender: ProtocolAddress,
        distributionId: UUID,
        record: SenderKeyRecord,
        context: StoreContext) throws {

        let writeTx = context.asTransaction

        guard let metadata = SenderKeyMetadata(
                record: record,
                sender: sender,
                distributionId: distributionId,
                readTx: writeTx) else {
            // TODO: Error handling
            throw NSError(domain: "", code: 0)
        }

        setMetadata(metadata, for: metadata.identifier, writeTx: writeTx)
    }

    public func loadSenderKey(
        from sender: ProtocolAddress,
        distributionId: UUID,
        context: StoreContext
    ) throws -> SenderKeyRecord? {

        let readTx = context.asTransaction
        guard let threadId = threadIdForDistributionId(distributionId, readTx: readTx) else { return nil }
        let namespace = SenderKeyNamespace(threadId: threadId, ownerUuid: sender.uuid, ownerDeviceId: sender.deviceId)
        let metadata = getMetadata(for: namespace, readTx: readTx)

        return metadata?.record
    }
}

// MARK: - Storage

fileprivate extension SenderKeyStore {
    private static let threadMappingStore = SDSKeyValueStore(collection: "SenderKeyStore_ThreadMapping")
    private static let metadataStore = SDSKeyValueStore(collection: "SenderKeyStore_MetadataStore")
    private var threadMappingStore: SDSKeyValueStore { Self.threadMappingStore }
    private var metadataStore: SDSKeyValueStore { Self.metadataStore }

    func getMetadata(for namespace: SenderKeyNamespace, readTx: SDSAnyReadTransaction) -> SenderKeyMetadata? {
        storageLock.assertOwner()

        return metadataCache[namespace.id] ?? {
            let persisted: SenderKeyMetadata?
            do {
                persisted = try metadataStore.getCodableValue(forKey: namespace.id, transaction: readTx)
            } catch {
                owsFailDebug("Failed to deserialize sender key: \(error)")
                persisted = nil
            }
            metadataCache[namespace.id] = persisted
            return persisted
        }()
    }

    func setMetadata(_ metadata: SenderKeyMetadata?, for namespace: SenderKeyNamespace, writeTx: SDSAnyWriteTransaction) {
        storageLock.assertOwner()

        do {
            try metadataStore.setCodable(metadata, key: namespace.id, transaction: writeTx)
            metadataCache[namespace.id] = metadata
        } catch {
            owsFailDebug("Failed to persist sender key: \(error)")
        }
    }

    func threadIdForDistributionId(_ distributionId: UUID, readTx: SDSAnyReadTransaction) -> String? {
        storageLock.assertOwner()

        return threadMappingCache[distributionId] ?? {
            let threadId = threadMappingStore.getString(distributionId.uuidString, transaction: readTx)
            threadMappingCache[distributionId] = threadId
            return threadId
        }()
    }

    func setThreadId(_ threadId: String, forDistributionId distributionId: UUID, writeTx: SDSAnyWriteTransaction) {
        storageLock.assertOwner()

        threadMappingStore.setString(threadId, key: distributionId.uuidString, transaction: writeTx)
        threadMappingCache[distributionId] = threadId
    }
}

// MARK: - Model

fileprivate struct SenderKeyNamespace {
    let threadId: String
    let ownerUuid: UUID
    let ownerDeviceId: UInt32

    init(threadId: String, ownerUuid: UUID, ownerDeviceId: UInt32) {
        self.threadId = threadId
        self.ownerUuid = ownerUuid
        self.ownerDeviceId = ownerDeviceId
    }

    init?(currentDeviceAndThreadId threadId: String) {
        let accountManager = SSKEnvironment.shared.tsAccountManager
        guard let uuid = accountManager.localUuid else { return nil }
        self.init(threadId: threadId, ownerUuid: uuid, ownerDeviceId: accountManager.storedDeviceId())
    }

    typealias Id = String
    var id: Id {
        "\(threadId)::\(ownerUuid.uuidString)::\(ownerDeviceId)"
    }
}

fileprivate struct SenderKeyMetadata: Dependencies, Codable {

    private let recordData: [UInt8]
    var record: SenderKeyRecord? {
        do {
            return try SenderKeyRecord(bytes: recordData)
        } catch {
            owsFailDebug("Failed to deserialize sender key record")
            return nil
        }
    }

    let threadId: ThreadUniqueId
    let distributionId: UUID
    let ownerUuid: UUID
    let ownerDeviceId: UInt32

    // These properties only matter if we own the key and use it for encrypting.
    // If the SenderKeyRecord is used for decrypting, these aren't used.
    struct DeviceTuple: Codable, Hashable {
        let uuid: UUID
        let deviceId: UInt32
    }
    var deliveredDevices: Set<DeviceTuple>
    let creationDate: Date

    init?(record: SenderKeyRecord, sender: ProtocolAddress, distributionId: UUID, readTx: SDSAnyReadTransaction) {
        self.recordData = record.serialize()
        self.distributionId = distributionId
        self.ownerUuid = sender.uuid
        self.ownerDeviceId = sender.deviceId

        self.creationDate = Date()
        self.deliveredDevices = Set()

        let correspondingThreadId = SDSDatabaseStorage.shared.read { readTx in
            SSKEnvironment.shared.senderKeyStore.threadIdForDistributionId(distributionId, readTx: readTx)
        }
        guard let threadId = correspondingThreadId else {
            owsFailDebug("Unknown distribution Id")
            return nil
        }
        self.threadId = threadId
    }

    var isValidForSending: Bool {
        let localUuid = tsAccountManager.localUuid
        let localDeviceId = tsAccountManager.storedDeviceId()
        return ownerUuid == localUuid && ownerDeviceId == localDeviceId
    }

    var identifier: SenderKeyNamespace {
        SenderKeyNamespace(threadId: threadId, ownerUuid: ownerUuid, ownerDeviceId: ownerDeviceId)
    }
}

// MARK: - Helper extensions

fileprivate typealias ThreadUniqueId = String
fileprivate extension TSGroupThread {
    var threadUniqueId: ThreadUniqueId { uniqueId }
}

fileprivate extension ProtocolAddress {
    var uuid: UUID {
        UUID(uuidString: name) ?? {
            owsFailDebug("Bad uuid string")
            return UUID()
        }()
    }
}
