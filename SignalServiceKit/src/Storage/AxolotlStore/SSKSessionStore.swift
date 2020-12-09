//
//  Copyright (c) 2020 Open Whisper Systems. All rights reserved.
//

import SignalClient

extension SSKSessionStore: SignalClient.SessionStore {
    public func loadSession(for address: ProtocolAddress, context: StoreContext) throws -> SignalClient.SessionRecord? {
        let record = loadSession(for: SignalServiceAddress(from: address),
                                 deviceId: Int32(bitPattern: address.deviceId),
                                 transaction: context.asTransaction)
        guard record.sessionState()?.rootKey != nil else {
            return nil
        }
        return try SessionRecord(bytes: record.serializeProto())
    }

    public func storeSession(_ record: SignalClient.SessionRecord,
                             for address: ProtocolAddress,
                             context: StoreContext) throws {
        storeSession(try AxolotlKit.SessionRecord(serializedProto: Data(record.serialize())),
                     for: SignalServiceAddress(from: address),
                     deviceId: Int32(bitPattern: address.deviceId),
                     transaction: context.asTransaction)
    }
}
