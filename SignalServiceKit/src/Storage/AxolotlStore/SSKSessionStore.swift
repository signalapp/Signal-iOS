//
//  Copyright (c) 2021 Open Whisper Systems. All rights reserved.
//

import SignalClient

extension SSKSessionStore {
    fileprivate func loadSignalClientSession(
        for address: SignalServiceAddress,
        deviceId: Int32,
        transaction: SDSAnyWriteTransaction
    ) throws -> SignalClient.SessionRecord? {
        let record = loadSession(for: address, deviceId: deviceId, transaction: transaction)
        guard record.sessionState()?.rootKey != nil else {
            return nil
        }
        return try SessionRecord(bytes: record.serializeProto())
    }

    fileprivate func storeSignalClientSession(_ record: SignalClient.SessionRecord,
                                              for address: SignalServiceAddress,
                                              deviceId: Int32,
                                              transaction: SDSAnyWriteTransaction) throws {
        storeSession(try AxolotlKit.SessionRecord(serializedProto: Data(record.serialize())),
                     for: address,
                     deviceId: deviceId,
                     transaction: transaction)
    }

    public func archiveSession(for address: SignalServiceAddress,
                               deviceId: Int32,
                               transaction: SDSAnyWriteTransaction) {
        do {
            guard let session = try self.loadSignalClientSession(for: address,
                                                                 deviceId: deviceId,
                                                                 transaction: transaction) else {
                return
            }
            session.archiveCurrentState()
            try self.storeSignalClientSession(session, for: address, deviceId: deviceId, transaction: transaction)
        } catch {
            owsFailDebug("\(error)")
        }
    }

    @objc
    private func archiveSessions(
        _ sessionRecords: [NSNumber: AxolotlKit.SessionRecord]
    ) -> [NSNumber: AxolotlKit.SessionRecord] {
        return sessionRecords.mapValues { record in
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
    }
}

extension SSKSessionStore: SignalClient.SessionStore {
    public func loadSession(for address: ProtocolAddress, context: StoreContext) throws -> SignalClient.SessionRecord? {
        return try loadSignalClientSession(for: SignalServiceAddress(from: address),
                                           deviceId: Int32(bitPattern: address.deviceId),
                                           transaction: context.asTransaction)
    }

    public func storeSession(_ record: SignalClient.SessionRecord,
                             for address: ProtocolAddress,
                             context: StoreContext) throws {
        try storeSignalClientSession(record,
                                     for: SignalServiceAddress(from: address),
                                     deviceId: Int32(bitPattern: address.deviceId),
                                     transaction: context.asTransaction)
    }
}
