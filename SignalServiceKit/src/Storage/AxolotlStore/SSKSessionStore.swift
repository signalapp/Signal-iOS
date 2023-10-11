//
// Copyright 2020 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import LibSignalClient

public final class SSKSessionStore: SignalSessionStore {
    fileprivate typealias SessionsByDeviceDictionary = [Int32: AnyObject]

    private let keyValueStore: KeyValueStore
    private let recipientIdFinder: RecipientIdFinder

    public init(
        for identity: OWSIdentity,
        keyValueStoreFactory: KeyValueStoreFactory,
        recipientIdFinder: RecipientIdFinder
    ) {
        LegacySessionRecord.setUpKeyedArchiverSubstitutions()

        self.keyValueStore = keyValueStoreFactory.keyValueStore(collection: {
            switch identity {
            case .aci:
                return "TSStorageManagerSessionStoreCollection"
            case .pni:
                return "TSStorageManagerPNISessionStoreCollection"
            }
        }())
        self.recipientIdFinder = recipientIdFinder
    }

    fileprivate func loadSerializedSession(
        for serviceId: ServiceId,
        deviceId: UInt32,
        tx: DBReadTransaction
    ) throws -> Data? {
        switch recipientIdFinder.recipientId(for: serviceId, tx: tx) {
        case .none:
            return nil
        case .some(.success(let recipientId)):
            return loadSerializedSession(for: recipientId, deviceId: deviceId, tx: tx)
        case .some(.failure(let error)):
            switch error {
            case .mustNotUsePniBecauseAciExists:
                throw error
            }
        }
    }

    private func serializedSession(fromDatabaseRepresentation entry: Any) -> Data? {
        switch entry {
        case let data as Data:
            return data
        case let record as LegacySessionRecord:
            do {
                return try record.serializeProto()
            } catch {
                owsFailDebug("failed to serialize AxolotlKit session: \(error)")
                return nil
            }
        default:
            owsFailDebug("unexpected entry in session store: \(entry)")
            return nil
        }
    }

    private func loadSerializedSession(
        for recipientId: String,
        deviceId: UInt32,
        tx: DBReadTransaction
    ) -> Data? {
        owsAssertDebug(!recipientId.isEmpty)
        owsAssertDebug(deviceId > 0)

        let dictionary = keyValueStore.getObject(forKey: recipientId, transaction: tx) as! SessionsByDeviceDictionary?
        guard let entry = dictionary?[Int32(bitPattern: deviceId)] else {
            return nil
        }
        return serializedSession(fromDatabaseRepresentation: entry)
    }

    fileprivate func storeSerializedSession(
        _ sessionData: Data,
        for serviceId: ServiceId,
        deviceId: UInt32,
        tx: DBWriteTransaction
    ) throws {
        switch recipientIdFinder.ensureRecipientId(for: serviceId, tx: tx) {
        case .failure(let error):
            switch error {
            case .mustNotUsePniBecauseAciExists:
                throw error
            }
        case .success(let recipientId):
            storeSerializedSession(for: recipientId, deviceId: deviceId, sessionData: sessionData, tx: tx)
        }
    }

    private func storeSerializedSession(
        for recipientId: String,
        deviceId: UInt32,
        sessionData: Data,
        tx: DBWriteTransaction
    ) {
        owsAssertDebug(!recipientId.isEmpty)
        owsAssertDebug(deviceId > 0)

        var dictionary = (keyValueStore.getObject(forKey: recipientId, transaction: tx) as! SessionsByDeviceDictionary?) ?? [:]
        dictionary[Int32(bitPattern: deviceId)] = sessionData as NSData
        keyValueStore.setObject(dictionary, key: recipientId, transaction: tx)
    }

    public func mightContainSession(for recipient: SignalRecipient, tx: DBReadTransaction) -> Bool {
        return keyValueStore.hasValue(recipient.uniqueId, transaction: tx)
    }

    public func mergeRecipient(_ recipient: SignalRecipient, into targetRecipient: SignalRecipient, tx: DBWriteTransaction) {
        let recipientPair = MergePair(fromValue: recipient, intoValue: targetRecipient)
        let sessionBlob = recipientPair.map { keyValueStore.getData($0.uniqueId, transaction: tx) }
        guard let fromValue = sessionBlob.fromValue else {
            return
        }
        if sessionBlob.intoValue == nil {
            keyValueStore.setData(fromValue, key: targetRecipient.uniqueId, transaction: tx)
        }
        keyValueStore.removeValue(forKey: recipient.uniqueId, transaction: tx)
    }

    public func deleteAllSessions(for serviceId: ServiceId, tx: DBWriteTransaction) {
        Logger.info("deleting all sessions for \(serviceId)")
        switch recipientIdFinder.recipientId(for: serviceId, tx: tx) {
        case .none, .some(.failure(.mustNotUsePniBecauseAciExists)):
            // There can't possibly be any sessions that need to be deleted.
            return
        case .some(.success(let recipientId)):
            owsAssertDebug(!recipientId.isEmpty)
            keyValueStore.removeValue(forKey: recipientId, transaction: tx)
        }
    }

    public func archiveAllSessions(for serviceId: ServiceId, tx: DBWriteTransaction) {
        Logger.info("archiving all sessions for \(serviceId)")
        switch recipientIdFinder.recipientId(for: serviceId, tx: tx) {
        case .none, .some(.failure(.mustNotUsePniBecauseAciExists)):
            // There can't possibly be any sessions that need to be archived.
            return
        case .some(.success(let recipientId)):
            archiveAllSessions(for: recipientId, tx: tx)
        }
    }

    public func archiveAllSessions(for address: SignalServiceAddress, tx: DBWriteTransaction) {
        Logger.info("archiving all sessions for \(address)")
        switch recipientIdFinder.recipientId(for: address, tx: tx) {
        case .none, .some(.failure(.mustNotUsePniBecauseAciExists)):
            // There can't possibly be any sessions that need to be archived.
            return
        case .some(.success(let recipientId)):
            archiveAllSessions(for: recipientId, tx: tx)
        }
    }

    private func archiveAllSessions(for recipientId: AccountId, tx: DBWriteTransaction) {
        owsAssertDebug(!recipientId.isEmpty)

        guard let dictionary = keyValueStore.getObject(forKey: recipientId, transaction: tx) as! SessionsByDeviceDictionary? else {
            // We never had a session for this account in the first place.
            return
        }

        let newDictionary: SessionsByDeviceDictionary = dictionary.mapValues { record in
            guard let data = serializedSession(fromDatabaseRepresentation: record) else {
                // We've already logged an error; skip this session.
                return record
            }

            do {
                let session = try SessionRecord(bytes: data)
                session.archiveCurrentState()
                return Data(session.serialize()) as NSData
            } catch {
                owsFailDebug("\(error)")
                return record
            }
        }

        keyValueStore.setObject(newDictionary, key: recipientId, transaction: tx)
    }

    public func resetSessionStore(tx: DBWriteTransaction) {
        Logger.warn("resetting session store")
        keyValueStore.removeAll(transaction: tx)
    }

    public func printAll(tx: DBReadTransaction) {
        Logger.debug("All Sessions.")
        keyValueStore.enumerateKeysAndObjects(transaction: tx) { key, value, _ in
            guard let deviceSessions = value as? NSDictionary else {
                owsFailDebug("Unexpected type: \(type(of: value)) in collection.")
                return
            }

            Logger.debug("     Sessions for recipient: \(key)")
            deviceSessions.enumerateKeysAndObjects { key, value, _ in
                guard let data = self.serializedSession(fromDatabaseRepresentation: value) else {
                    // We've already logged an error here, just move on.
                    return
                }
                do {
                    let sessionRecord = try SessionRecord(bytes: data)
                    Logger.debug("         Device: \(key) hasCurrentState: \(sessionRecord.hasCurrentState)")
                } catch {
                    owsFailDebug("invalid session record: \(error)")
                }
            }
        }
    }
}

extension SSKSessionStore {
    public func loadSession(
        for serviceId: ServiceId,
        deviceId: UInt32,
        tx: DBReadTransaction
    ) throws -> SessionRecord? {
        guard let serializedData = try loadSerializedSession(for: serviceId, deviceId: deviceId, tx: tx) else {
            return nil
        }
        return try SessionRecord(bytes: serializedData)
    }

    fileprivate func storeSession(
        _ record: SessionRecord,
        for serviceId: ServiceId,
        deviceId: UInt32,
        tx: DBWriteTransaction
    ) throws {
        try storeSerializedSession(Data(record.serialize()), for: serviceId, deviceId: deviceId, tx: tx)
    }

    public func archiveSession(for serviceId: ServiceId, deviceId: UInt32, tx: DBWriteTransaction) {
        do {
            guard let session = try loadSession(for: serviceId, deviceId: deviceId, tx: tx) else {
                return
            }
            session.archiveCurrentState()
            try storeSession(session, for: serviceId, deviceId: deviceId, tx: tx)
        } catch {
            owsFailDebug("\(error)")
        }
    }
}

extension SSKSessionStore: LibSignalClient.SessionStore {
    public func loadSession(for address: ProtocolAddress, context: StoreContext) throws -> SessionRecord? {
        return try loadSession(for: address.serviceId, deviceId: address.deviceId, tx: context.asTransaction.asV2Read)
    }

    public func loadExistingSessions(
        for addresses: [ProtocolAddress],
        context: StoreContext
    ) throws -> [SessionRecord] {

        try addresses.compactMap {
            try loadSession(for: $0, context: context)
        }
    }

    public func storeSession(_ record: SessionRecord, for address: ProtocolAddress, context: StoreContext) throws {
        try storeSession(record, for: address.serviceId, deviceId: address.deviceId, tx: context.asTransaction.asV2Write)
    }
}

#if TESTABLE_BUILD

extension SSKSessionStore {
    public func removeAll(tx: DBWriteTransaction) {
        keyValueStore.removeAll(transaction: tx)
    }
}

#endif
