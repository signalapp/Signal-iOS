//
// Copyright 2020 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

public import LibSignalClient

public final class SSKSessionStore: SignalSessionStore {
    // Note that even though the values here are always serialized Data,
    // using AnyObject here defers any checking or conversion of the values
    // when converting from an NSDictionary.
    fileprivate typealias SessionsByDeviceDictionary = [Int32: AnyObject]

    private let keyValueStore: KeyValueStore
    private let recipientIdFinder: RecipientIdFinder

    public init(
        for identity: OWSIdentity,
        recipientIdFinder: RecipientIdFinder
    ) {
        self.keyValueStore = KeyValueStore(collection: {
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
        switch recipientIdFinder.recipientUniqueId(for: serviceId, tx: tx) {
        case .none:
            return nil
        case .some(.success(let recipientUniqueId)):
            return loadSerializedSession(for: recipientUniqueId, deviceId: deviceId, tx: tx)
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
        default:
            owsFailDebug("unexpected entry in session store: \(type(of: entry))")
            return nil
        }
    }

    private func loadSerializedSession(
        for recipientUniqueId: String,
        deviceId: UInt32,
        tx: DBReadTransaction
    ) -> Data? {
        owsAssertDebug(!recipientUniqueId.isEmpty)
        owsAssertDebug(deviceId > 0)

        let dictionary = loadAllSerializedSessions(for: recipientUniqueId, tx: tx)
        guard let entry = dictionary?[Int32(bitPattern: deviceId)] else {
            return nil
        }
        return serializedSession(fromDatabaseRepresentation: entry)
    }

    private func loadAllSerializedSessions(
        for recipientUniqueId: String,
        tx: DBReadTransaction
    ) -> SessionsByDeviceDictionary? {
        owsAssertDebug(!recipientUniqueId.isEmpty)

        guard let serialized = keyValueStore.getData(recipientUniqueId, transaction: tx) else {
            return nil
        }

        let rawDictionary: NSDictionary?
        do {
            rawDictionary = try NSKeyedUnarchiver.unarchivedObject(ofClasses: [NSDictionary.self, NSNumber.self, NSData.self], from: serialized) as? NSDictionary
        } catch let error as NSError {
            // Deliberately don't log the full error; it might contain session data.
            Logger.error("Unknown data (or legacy session) in session store; continuing as if there were no stored sessions (\(error.domain) \(error.code))")
            return nil
        }

        guard let dictionary = rawDictionary as? SessionsByDeviceDictionary else {
            Logger.error("Invalid device ID keys in session store; continuing as if there were no stored sessions")
            return nil
        }

        return dictionary
    }

    fileprivate func storeSerializedSession(
        _ sessionData: Data,
        for serviceId: ServiceId,
        deviceId: UInt32,
        tx: DBWriteTransaction
    ) throws {
        switch recipientIdFinder.ensureRecipientUniqueId(for: serviceId, tx: tx) {
        case .failure(let error):
            switch error {
            case .mustNotUsePniBecauseAciExists:
                throw error
            }
        case .success(let recipientUniqueId):
            storeSerializedSession(for: recipientUniqueId, deviceId: deviceId, sessionData: sessionData, tx: tx)
        }
    }

    private func storeSerializedSession(
        for recipientUniqueId: String,
        deviceId: UInt32,
        sessionData: Data,
        tx: DBWriteTransaction
    ) {
        owsAssertDebug(!recipientUniqueId.isEmpty)
        owsAssertDebug(deviceId > 0)

        var dictionary = loadAllSerializedSessions(for: recipientUniqueId, tx: tx) ?? [:]
        dictionary[Int32(bitPattern: deviceId)] = sessionData as NSData
        saveSerializedSessions(dictionary, for: recipientUniqueId, tx: tx)
    }

    private func saveSerializedSessions(
        _ sessions: SessionsByDeviceDictionary,
        for recipientUniqueId: String,
        tx: DBWriteTransaction
    ) {
        // Avoid using KeyValueStore.setObject(_:key:transaction:).
        // The database-based KV store implicitly archives using NSKeyedArchiver,
        // but the in-memory one for testing does not.
        // In order for loadAllSerializedSessions(for:tx:) to manually control deserialization,
        // we need to consistently archive.
        // This will also make it easier to potentially move away from NSKeyedArchiver in the future.
        do {
            let archived = try NSKeyedArchiver.archivedData(withRootObject: sessions, requiringSecureCoding: true)
            keyValueStore.setData(archived, key: recipientUniqueId, transaction: tx)
        } catch {
            Logger.debug("failed to serialize session data: \(error)\n\(sessions)")
            owsFailDebug("failed to serialize session data")
            // At least clear out whatever's in the store, so we don't keep old sessions around longer than we should.
            keyValueStore.setData(nil, key: recipientUniqueId, transaction: tx)
        }
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
        switch recipientIdFinder.recipientUniqueId(for: serviceId, tx: tx) {
        case .none, .some(.failure(.mustNotUsePniBecauseAciExists)):
            // There can't possibly be any sessions that need to be deleted.
            return
        case .some(.success(let recipientUniqueId)):
            owsAssertDebug(!recipientUniqueId.isEmpty)
            deleteAllSessions(for: recipientUniqueId, tx: tx)
        }
    }

    public func deleteAllSessions(for recipientUniqueId: RecipientUniqueId, tx: DBWriteTransaction) {
        keyValueStore.removeValue(forKey: recipientUniqueId, transaction: tx)
    }

    public func archiveAllSessions(for serviceId: ServiceId, tx: DBWriteTransaction) {
        Logger.info("archiving all sessions for \(serviceId)")
        switch recipientIdFinder.recipientUniqueId(for: serviceId, tx: tx) {
        case .none, .some(.failure(.mustNotUsePniBecauseAciExists)):
            // There can't possibly be any sessions that need to be archived.
            return
        case .some(.success(let recipientUniqueId)):
            archiveAllSessions(for: recipientUniqueId, tx: tx)
        }
    }

    public func archiveAllSessions(for address: SignalServiceAddress, tx: DBWriteTransaction) {
        Logger.info("archiving all sessions for \(address)")
        switch recipientIdFinder.recipientUniqueId(for: address, tx: tx) {
        case .none, .some(.failure(.mustNotUsePniBecauseAciExists)):
            // There can't possibly be any sessions that need to be archived.
            return
        case .some(.success(let recipientUniqueId)):
            archiveAllSessions(for: recipientUniqueId, tx: tx)
        }
    }

    private func archiveAllSessions(for recipientUniqueId: RecipientUniqueId, tx: DBWriteTransaction) {
        owsAssertDebug(!recipientUniqueId.isEmpty)

        guard let dictionary = loadAllSerializedSessions(for: recipientUniqueId, tx: tx) else {
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

        saveSerializedSessions(newDictionary, for: recipientUniqueId, tx: tx)
    }

    public func resetSessionStore(tx: DBWriteTransaction) {
        Logger.warn("resetting session store")
        keyValueStore.removeAll(transaction: tx)
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
    // Available through `@testable import`
    internal var keyValueStoreForTesting: KeyValueStore {
        self.keyValueStore
    }

    public func removeAll(tx: DBWriteTransaction) {
        keyValueStore.removeAll(transaction: tx)
    }
}

#endif
