//
//  Copyright (c) 2021 Open Whisper Systems. All rights reserved.
//

import SignalClient

public class SSKSessionStore: NSObject {
    fileprivate typealias SessionsByDeviceDictionary = [Int32: AnyObject]

    @objc // Used by migration, exposed in <SignalMessaging/PrivateMethodsForMigration.h>
    private let keyValueStore = SDSKeyValueStore(collection: "TSStorageManagerSessionStoreCollection")

    fileprivate func loadSerializedSession(for address: SignalServiceAddress,
                                           deviceId: Int32,
                                           transaction: SDSAnyWriteTransaction) -> Data? {
        owsAssertDebug(address.isValid)
        let accountId = OWSAccountIdFinder.ensureAccountId(forAddress: address, transaction: transaction)
        return loadSerializedSession(forAccountId: accountId, deviceId: deviceId, transaction: transaction)
    }

    fileprivate func serializedSession(fromDatabaseRepresentation entry: Any) -> Data? {
        switch entry {
        case let data as Data:
            return data
        case let record as AxolotlKit.SessionRecord:
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
                                      transaction: SDSAnyWriteTransaction) -> Bool {
        owsAssertDebug(address.isValid)
        let accountId = OWSAccountIdFinder.ensureAccountId(forAddress: address, transaction: transaction)
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
            let session = try SignalClient.SessionRecord(bytes: serializedData)
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
                let session = try SignalClient.SessionRecord(bytes: data)
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
                    let sessionRecord = try SignalClient.SessionRecord(bytes: data)
                    Logger.debug("         Device: \(key) hasCurrentState: \(sessionRecord.hasCurrentState)")
                } catch {
                    owsFailDebug("invalid session record: \(error)")
                }
            }
        }
    }
}

extension SSKSessionStore {
    fileprivate func loadSession(
        for address: SignalServiceAddress,
        deviceId: Int32,
        transaction: SDSAnyWriteTransaction
    ) throws -> SignalClient.SessionRecord? {
        guard let serializedData = loadSerializedSession(for: address,
                                                         deviceId: deviceId,
                                                         transaction: transaction) else {
            return nil
        }
        return try SessionRecord(bytes: serializedData)
    }

    fileprivate func storeSession(_ record: SignalClient.SessionRecord,
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

extension SSKSessionStore: SignalClient.SessionStore {
    public func loadSession(for address: ProtocolAddress, context: StoreContext) throws -> SignalClient.SessionRecord? {
        return try loadSession(for: SignalServiceAddress(from: address),
                               deviceId: Int32(bitPattern: address.deviceId),
                               transaction: context.asTransaction)
    }

    public func storeSession(_ record: SignalClient.SessionRecord,
                             for address: ProtocolAddress,
                             context: StoreContext) throws {
        try storeSession(record,
                         for: SignalServiceAddress(from: address),
                         deviceId: Int32(bitPattern: address.deviceId),
                         transaction: context.asTransaction)
    }
}

extension SSKSessionStore: AxolotlKit.SessionStore {
    @available(*, deprecated, message: "use the strongly typed `transaction:` flavor instead")
    public func loadSession(_ contactIdentifier: String,
                            deviceId: Int32,
                            protocolContext: SPKProtocolReadContext?) -> AxolotlKit.SessionRecord {
        guard let sessionData = loadSerializedSession(forAccountId: contactIdentifier,
                                                      deviceId: deviceId,
                                                      transaction: protocolContext as! SDSAnyReadTransaction) else {
            return SessionRecord()
        }
        do {
            return try AxolotlKit.SessionRecord(serializedProto: sessionData)
        } catch {
            owsFailDebug("serialized session data was not valid: \(error)")
            return SessionRecord()
        }
    }

    @available(*, deprecated, message: "use the strongly typed `transaction:` flavor instead")
    public func subDevicesSessions(_ contactIdentifier: String, protocolContext: SPKProtocolWriteContext?) -> [Any] {
        owsFail("subDeviceSessions is unused")
    }

    @available(*, deprecated, message: "use the strongly typed `transaction:` flavor instead")
    public func storeSession(_ contactIdentifier: String,
                             deviceId: Int32,
                             session: AxolotlKit.SessionRecord,
                             protocolContext: SPKProtocolWriteContext?) {
        do {
            storeSerializedSession(forAccountId: contactIdentifier,
                                   deviceId: deviceId,
                                   sessionData: try session.serializeProto(),
                                   transaction: protocolContext as! SDSAnyWriteTransaction)
        } catch {
            owsFail("could not serialize session: \(error)")
        }
    }

    @available(*, deprecated, message: "use the strongly typed `transaction:` flavor instead")
    public func containsSession(_ contactIdentifier: String,
                                deviceId: Int32,
                                protocolContext: SPKProtocolReadContext?) -> Bool {
        return containsActiveSession(forAccountId: contactIdentifier,
                                     deviceId: deviceId,
                                     transaction: protocolContext as! SDSAnyReadTransaction)
    }

    @available(*, deprecated, message: "use the strongly typed `transaction:` flavor instead")
    public func deleteSession(forContact contactIdentifier: String,
                              deviceId: Int32,
                              protocolContext: SPKProtocolWriteContext?) {
        deleteSession(forAccountId: contactIdentifier,
                      deviceId: deviceId,
                      transaction: protocolContext as! SDSAnyWriteTransaction)
    }

    @available(*, deprecated, message: "use the strongly typed `transaction:` flavor instead")
    public func deleteAllSessions(forContact contactIdentifier: String, protocolContext: SPKProtocolWriteContext?) {
        deleteAllSessions(forAccountId: contactIdentifier, transaction: protocolContext as! SDSAnyWriteTransaction)
    }
}
