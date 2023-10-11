//
// Copyright 2020 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import LibSignalClient

public class SSKSessionStore: NSObject {
    fileprivate typealias SessionsByDeviceDictionary = [Int32: AnyObject]

    private let keyValueStore: SDSKeyValueStore

    @objc(initForIdentity:)
    public init(for identity: OWSIdentity) {
        LegacySessionRecord.setUpKeyedArchiverSubstitutions()

        switch identity {
        case .aci:
            keyValueStore = SDSKeyValueStore(collection: "TSStorageManagerSessionStoreCollection")
        case .pni:
            keyValueStore = SDSKeyValueStore(collection: "TSStorageManagerPNISessionStoreCollection")
        }
    }

    fileprivate func loadSerializedSession(
        for serviceId: ServiceId,
        deviceId: UInt32,
        tx: SDSAnyReadTransaction
    ) -> Data? {
        guard let recipientId = OWSAccountIdFinder.recipientId(for: serviceId, tx: tx) else {
            return nil
        }
        return loadSerializedSession(for: recipientId, deviceId: deviceId, tx: tx)
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
        tx: SDSAnyReadTransaction
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
        tx: SDSAnyWriteTransaction
    ) {
        let recipientId = OWSAccountIdFinder.ensureRecipientId(for: serviceId, tx: tx)
        storeSerializedSession(for: recipientId, deviceId: deviceId, sessionData: sessionData, tx: tx)
    }

    private func storeSerializedSession(
        for recipientId: String,
        deviceId: UInt32,
        sessionData: Data,
        tx: SDSAnyWriteTransaction
    ) {
        owsAssertDebug(!recipientId.isEmpty)
        owsAssertDebug(deviceId > 0)

        var dictionary = (keyValueStore.getObject(forKey: recipientId, transaction: tx) as! SessionsByDeviceDictionary?) ?? [:]
        dictionary[Int32(bitPattern: deviceId)] = sessionData as NSData
        keyValueStore.setObject(dictionary, key: recipientId, transaction: tx)
    }

    public func containsActiveSession(
        forAccountId accountId: String,
        deviceId: UInt32,
        tx: SDSAnyReadTransaction
    ) -> Bool {
        return loadSerializedSession(for: accountId, deviceId: deviceId, tx: tx) != nil
    }

    public func deleteAllSessions(for serviceId: ServiceId, tx: SDSAnyWriteTransaction) {
        guard let recipientId = OWSAccountIdFinder.recipientId(for: serviceId, tx: tx) else {
            // There can't possibly be any sessions that need to be deleted.
            return
        }
        owsAssertDebug(!recipientId.isEmpty)
        Logger.info("deleting all sessions for \(serviceId)")
        keyValueStore.removeValue(forKey: recipientId, transaction: tx)
    }

    public func archiveAllSessions(for serviceId: ServiceId, tx: SDSAnyWriteTransaction) {
        Logger.info("archiving all sessions for \(serviceId)")
        guard let recipientId = OWSAccountIdFinder.recipientId(for: serviceId, tx: tx) else {
            // There can't possibly be any sessions that need to be archived.
            return
        }
        archiveAllSessions(for: recipientId, tx: tx)
    }

    public func archiveAllSessions(for address: SignalServiceAddress, tx: SDSAnyWriteTransaction) {
        Logger.info("archiving all sessions for \(address)")
        guard let recipientId = OWSAccountIdFinder.accountId(forAddress: address, transaction: tx) else {
            // There can't possibly be any sessions that need to be archived.
            return
        }
        archiveAllSessions(for: recipientId, tx: tx)
    }

    private func archiveAllSessions(for recipientId: AccountId, tx: SDSAnyWriteTransaction) {
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

    public func resetSessionStore(_ transaction: SDSAnyWriteTransaction) {
        Logger.warn("resetting session store")
        keyValueStore.removeAll(transaction: transaction)
    }

    @objc
    public func printAllSessions(transaction: SDSAnyReadTransaction) {
        Logger.debug("All Sessions.")
        keyValueStore.enumerateKeysAndObjects(transaction: transaction) { key, value, _ in
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
        tx: SDSAnyReadTransaction
    ) throws -> SessionRecord? {
        guard let serializedData = loadSerializedSession(for: serviceId, deviceId: deviceId, tx: tx) else {
            return nil
        }
        return try SessionRecord(bytes: serializedData)
    }

    fileprivate func storeSession(
        _ record: SessionRecord,
        for serviceId: ServiceId,
        deviceId: UInt32,
        tx: SDSAnyWriteTransaction
    ) throws {
        storeSerializedSession(Data(record.serialize()), for: serviceId, deviceId: deviceId, tx: tx)
    }

    public func archiveSession(for serviceId: ServiceId, deviceId: UInt32, tx: SDSAnyWriteTransaction) {
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
        return try loadSession(for: address.serviceId, deviceId: address.deviceId, tx: context.asTransaction)
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
        try storeSession(record, for: address.serviceId, deviceId: address.deviceId, tx: context.asTransaction)
    }
}

#if TESTABLE_BUILD

extension SSKSessionStore {
    public func removeAll(transaction: SDSAnyWriteTransaction) {
        keyValueStore.removeAll(transaction: transaction)
    }
}

#endif
