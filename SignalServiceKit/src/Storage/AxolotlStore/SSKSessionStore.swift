//
//  Copyright (c) 2021 Open Whisper Systems. All rights reserved.
//

import SignalClient

public class SSKSessionStore: NSObject {
    fileprivate typealias SessionsByDeviceDictionary = [Int32: AxolotlKit.SessionRecord]

    @objc // Used by migration, exposed in <SignalMessaging/PrivateMethodsForMigration.h>
    private let keyValueStore = SDSKeyValueStore(collection: "TSStorageManagerSessionStoreCollection")

    private var accountIdFinder: OWSAccountIdFinder {
        return OWSAccountIdFinder()
    }

    fileprivate func loadSerializedSession(for address: SignalServiceAddress,
                                           deviceId: Int32,
                                           transaction: SDSAnyWriteTransaction) -> Data? {
        owsAssertDebug(address.isValid)
        let accountId = accountIdFinder.ensureAccountId(forAddress: address, transaction: transaction)
        return loadSerializedSession(forAccountId: accountId, deviceId: deviceId, transaction: transaction)
    }

    private func loadSerializedSession(forAccountId accountId: String,
                                       deviceId: Int32,
                                       transaction: SDSAnyReadTransaction) -> Data? {
        owsAssertDebug(!accountId.isEmpty)
        owsAssertDebug(deviceId > 0)

        let dictionary = keyValueStore.getObject(forKey: accountId,
                                                 transaction: transaction) as! SessionsByDeviceDictionary?

        do {
            return try dictionary?[deviceId]?.serializeProto()
        } catch {
            owsFailDebug("failed to serialize AxolotlKit session: \(error)")
            return nil
        }
    }

    fileprivate func storeSerializedSession(_ sessionData: Data,
                                            for address: SignalServiceAddress,
                                            deviceId: Int32,
                                            transaction: SDSAnyWriteTransaction) {
        owsAssertDebug(address.isValid)
        let accountId = accountIdFinder.ensureAccountId(forAddress: address, transaction: transaction)
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

        let session: AxolotlKit.SessionRecord
        do {
            session = try .init(serializedProto: sessionData)
        } catch {
            owsFail("trying to store data that isn't a valid session: \(error)")
        }

        // We need to ensure subsequent usage of this SessionRecord does not consider this session as "fresh". Normally
        // this  is achieved by marking things as "not fresh" at the point of deserialization - when we fetch a
        // SessionRecord from YapDB (initWithCoder:). However, because YapDB has an object cache, rather than
        // fetching/deserializing, it's possible we'd get back *this* exact instance of the object (which, at this
        // point, is still potentially "fresh"), thus we explicitly mark this instance as "unfresh", any time we save.
        // NOTE: this may no longer be necessary now that we have a non-caching session db connection.
        session.markAsUnFresh()

        var dictionary = (keyValueStore.getObject(forKey: accountId,
                                                  transaction: transaction) as! SessionsByDeviceDictionary?) ?? [:]
        dictionary[deviceId] = session
        keyValueStore.setObject(dictionary, key: accountId, transaction: transaction)
    }

    @objc(containsSessionForAddress:deviceId:transaction:)
    public func containsSession(for address: SignalServiceAddress,
                                deviceId: Int32,
                                transaction: SDSAnyWriteTransaction) -> Bool {
        owsAssertDebug(address.isValid)
        let accountId = accountIdFinder.ensureAccountId(forAddress: address, transaction: transaction)
        return containsSession(forAccountId: accountId, deviceId: deviceId, transaction: transaction)
    }

    @objc
    public func containsSession(forAccountId accountId: String,
                                deviceId: Int32,
                                transaction: SDSAnyReadTransaction) -> Bool {
        guard let serializedData = loadSerializedSession(forAccountId: accountId,
                                                         deviceId: deviceId,
                                                         transaction: transaction) else {
            return false
        }

        do {
            // FIXME: Expose a SignalClient version of this instead of poking at the protobuf.
            let sessionStructure = try SessionRecordProtos_RecordStructure(serializedData: serializedData)
            return sessionStructure.hasCurrentSession
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

        OWSLogger.info("deleting session for accountId: \(accountId) device: \(deviceId)")

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
        let accountId = accountIdFinder.ensureAccountId(forAddress: address, transaction: transaction)
        return deleteAllSessions(forAccountId: accountId, transaction: transaction)
    }

    private func deleteAllSessions(forAccountId accountId: String,
                                   transaction: SDSAnyWriteTransaction) {
        owsAssertDebug(!accountId.isEmpty)
        OWSLogger.info("deleting all sessions for contact: \(accountId)")
        keyValueStore.removeValue(forKey: accountId, transaction: transaction)
    }

    @objc(archiveAllSessionsForAddress:transaction:)
    public func archiveAllSessions(for address: SignalServiceAddress, transaction: SDSAnyWriteTransaction) {
        owsAssertDebug(address.isValid)
        let accountId = accountIdFinder.ensureAccountId(forAddress: address, transaction: transaction)
        return archiveAllSessions(forAccountId: accountId, transaction: transaction)
    }

    @objc
    public func archiveAllSessions(forAccountId accountId: String,
                                   transaction: SDSAnyWriteTransaction) {
        owsAssertDebug(!accountId.isEmpty)
        OWSLogger.info("archiving all sessions for contact: \(accountId)")

        guard let dictionary = keyValueStore.getObject(forKey: accountId,
                                                       transaction: transaction) as! SessionsByDeviceDictionary? else {
            // We never had a session for this account in the first place.
            return
        }

        let newDictionary: SessionsByDeviceDictionary = dictionary.mapValues { record in
            do {
                guard record.sessionState()?.rootKey != nil else {
                    return record
                }
                let session = try SignalClient.SessionRecord(bytes: record.serializeProto())
                session.archiveCurrentState()
                return try AxolotlKit.SessionRecord(serializedProto: Data(session.serialize()))
            } catch {
                owsFailDebug("\(error)")
                return record
            }
        }

        keyValueStore.setObject(newDictionary, key: accountId, transaction: transaction)
    }

    @objc
    public func resetSessionStore(_ transaction: SDSAnyWriteTransaction) {
        OWSLogger.warn("resetting session store")
        keyValueStore.removeAll(transaction: transaction)
    }

    @objc
    public func printAllSessions(transaction: SDSAnyReadTransaction) {
        OWSLogger.debug("All Sessions.")
        keyValueStore.enumerateKeysAndObjects(transaction: transaction) { key, value, _ in
            guard let deviceSessions = value as? NSDictionary else {
                owsFailDebug("Unexpected type: \(type(of: value)) in collection.")
                return
            }

            OWSLogger.debug("     Sessions for recipient: \(key)")
            deviceSessions.enumerateKeysAndObjects { key, value, _ in
                guard let sessionRecord = value as? AxolotlKit.SessionRecord else {
                    owsFailDebug("Unexpected type: \(type(of: value)) in collection")
                    return
                }
                // FIXME: This won't be super useful with SignalClient, which won't have persistent objects to poke at.
                let activeState = sessionRecord.sessionState().map { String(describing: $0) } ?? "(none)"
                let previousStates = sessionRecord.previousSessionStates() ?? []
                OWSLogger.debug("         Device: \(key)" +
                                    " SessionRecord: \(sessionRecord)" +
                                    " activeSessionState: \(activeState)" +
                                    " previousSessionStates: \(previousStates)")
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
        return containsSession(forAccountId: contactIdentifier,
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
