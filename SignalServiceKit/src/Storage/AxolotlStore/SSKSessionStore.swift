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

    fileprivate func loadSerializedSession(for address: SignalServiceAddress,
                                           deviceId: Int32,
                                           transaction: SDSAnyReadTransaction) -> Data? {
        owsAssertDebug(address.isValid)
        guard let accountId = OWSAccountIdFinder.accountId(forAddress: address, transaction: transaction) else {
            Logger.info("No accountId for: \(address). There must not be a stored session.")
            return nil
        }
        return loadSerializedSession(forAccountId: accountId, deviceId: deviceId, transaction: transaction)
    }

    fileprivate func serializedSession(fromDatabaseRepresentation entry: Any) -> Data? {
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

    private func loadSerializedSession(forAccountId accountId: String,
                                       deviceId: Int32,
                                       transaction: SDSAnyReadTransaction) -> Data? {
        owsAssertDebug(!accountId.isEmpty)
        owsAssertDebug(deviceId > 0)

        let dictionary = keyValueStore.getObject(forKey: accountId,
                                                 transaction: transaction) as! SessionsByDeviceDictionary?
        guard let entry = dictionary?[deviceId] else {
            return nil
        }
        return serializedSession(fromDatabaseRepresentation: entry)
    }

    fileprivate func storeSerializedSession(_ sessionData: Data,
                                            for address: SignalServiceAddress,
                                            deviceId: Int32,
                                            transaction: SDSAnyWriteTransaction) {
        owsAssertDebug(address.isValid)
        let accountId = OWSAccountIdFinder.ensureAccountId(forAddress: address, transaction: transaction)
        storeSerializedSession(forAccountId: accountId,
                               deviceId: deviceId,
                               sessionData: sessionData,
                               transaction: transaction)
    }

    private func storeSerializedSession(forAccountId accountId: String,
                                        deviceId: Int32,
                                        sessionData: Data,
                                        transaction: SDSAnyWriteTransaction) {
        owsAssertDebug(!accountId.isEmpty)
        owsAssertDebug(deviceId > 0)

        var dictionary = (keyValueStore.getObject(forKey: accountId,
                                                  transaction: transaction) as! SessionsByDeviceDictionary?) ?? [:]
        dictionary[deviceId] = sessionData as NSData
        keyValueStore.setObject(dictionary, key: accountId, transaction: transaction)
    }

    @objc(containsActiveSessionForAddress:deviceId:transaction:)
    public func containsActiveSession(for address: SignalServiceAddress,
                                      deviceId: Int32,
                                      transaction: SDSAnyReadTransaction) -> Bool {
        owsAssertDebug(address.isValid)
        guard let accountId = OWSAccountIdFinder.accountId(forAddress: address, transaction: transaction) else {
            Logger.info("No accountId for: \(address). There must not be a stored session.")
            return false
        }
        return containsActiveSession(forAccountId: accountId, deviceId: deviceId, transaction: transaction)
    }

    @objc
    public func containsActiveSession(forAccountId accountId: String,
                                      deviceId: Int32,
                                      transaction: SDSAnyReadTransaction) -> Bool {
        guard let serializedData = loadSerializedSession(forAccountId: accountId,
                                                         deviceId: deviceId,
                                                         transaction: transaction) else {
            return false
        }

        do {
            let session = try SessionRecord(bytes: serializedData)
            return session.hasCurrentState
        } catch {
            owsFailDebug("serialized session data was not valid: \(error)")
            return false
        }
    }

    private func deleteSession(forAccountId accountId: String,
                               deviceId: Int32,
                               transaction: SDSAnyWriteTransaction) {
        owsAssertDebug(!accountId.isEmpty)
        owsAssertDebug(deviceId > 0)

        Logger.info("deleting session for accountId: \(accountId) device: \(deviceId)")

        guard var dictionary = keyValueStore.getObject(forKey: accountId,
                                                       transaction: transaction) as! SessionsByDeviceDictionary? else {
            // We never had a session for this account in the first place.
            return
        }

        dictionary.removeValue(forKey: deviceId)
        keyValueStore.setObject(dictionary, key: accountId, transaction: transaction)
    }

    @objc(deleteAllSessionsForAddress:transaction:)
    public func deleteAllSessions(for address: SignalServiceAddress, transaction: SDSAnyWriteTransaction) {
        owsAssertDebug(address.isValid)
        let accountId = OWSAccountIdFinder.ensureAccountId(forAddress: address, transaction: transaction)
        return deleteAllSessions(forAccountId: accountId, transaction: transaction)
    }

    private func deleteAllSessions(forAccountId accountId: String,
                                   transaction: SDSAnyWriteTransaction) {
        owsAssertDebug(!accountId.isEmpty)
        Logger.info("deleting all sessions for contact: \(accountId)")
        keyValueStore.removeValue(forKey: accountId, transaction: transaction)
    }

    @objc(archiveAllSessionsForAddress:transaction:)
    public func archiveAllSessions(for address: SignalServiceAddress, transaction: SDSAnyWriteTransaction) {
        owsAssertDebug(address.isValid)
        let accountId = OWSAccountIdFinder.ensureAccountId(forAddress: address, transaction: transaction)
        return archiveAllSessions(forAccountId: accountId, transaction: transaction)
    }

    @objc
    public func archiveAllSessions(forAccountId accountId: String,
                                   transaction: SDSAnyWriteTransaction) {
        owsAssertDebug(!accountId.isEmpty)
        Logger.info("archiving all sessions for contact: \(accountId)")

        guard let dictionary = keyValueStore.getObject(forKey: accountId,
                                                       transaction: transaction) as! SessionsByDeviceDictionary? else {
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

        keyValueStore.setObject(newDictionary, key: accountId, transaction: transaction)
    }

    @objc
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
        for address: SignalServiceAddress,
        deviceId: Int32,
        transaction: SDSAnyReadTransaction
    ) throws -> SessionRecord? {
        guard let serializedData = loadSerializedSession(for: address,
                                                         deviceId: deviceId,
                                                         transaction: transaction) else {
            return nil
        }
        return try SessionRecord(bytes: serializedData)
    }

    fileprivate func storeSession(_ record: SessionRecord,
                                  for address: SignalServiceAddress,
                                  deviceId: Int32,
                                  transaction: SDSAnyWriteTransaction) throws {
        storeSerializedSession(Data(record.serialize()), for: address, deviceId: deviceId, transaction: transaction)
    }

    public func archiveSession(for address: SignalServiceAddress,
                               deviceId: Int32,
                               transaction: SDSAnyWriteTransaction) {
        do {
            guard let session = try self.loadSession(for: address, deviceId: deviceId, transaction: transaction) else {
                return
            }
            session.archiveCurrentState()
            try self.storeSession(session, for: address, deviceId: deviceId, transaction: transaction)
        } catch {
            owsFailDebug("\(error)")
        }
    }
}

extension SSKSessionStore: SessionStore {
    public func loadSession(for address: ProtocolAddress, context: StoreContext) throws -> SessionRecord? {
        return try loadSession(for: SignalServiceAddress(from: address),
                               deviceId: Int32(bitPattern: address.deviceId),
                               transaction: context.asTransaction)
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
        try storeSession(record,
                         for: SignalServiceAddress(from: address),
                         deviceId: Int32(bitPattern: address.deviceId),
                         transaction: context.asTransaction)
    }
}

#if TESTABLE_BUILD

@objc
extension SSKSessionStore {
    func removeAll(transaction: SDSAnyWriteTransaction) {
        keyValueStore.removeAll(transaction: transaction)
    }
}

#endif
