//
//  Copyright (c) 2021 Open Whisper Systems. All rights reserved.
//

import SignalClient

extension SSKPreKeyStore: PreKeyStore {
    enum Error: Swift.Error {
        case noPreKeyWithId(UInt32)
    }

    public func loadPreKey(id: UInt32, context: StoreContext) throws -> SignalClient.PreKeyRecord {
        guard let preKey = self.loadPreKey(Int32(bitPattern: id), transaction: context.asTransaction) else {
            throw Error.noPreKeyWithId(id)
        }
        let keyPair = preKey.keyPair.identityKeyPair
        return try .init(id: UInt32(bitPattern: preKey.id),
                         publicKey: keyPair.publicKey,
                         privateKey: keyPair.privateKey)
    }

    public func storePreKey(_ record: SignalClient.PreKeyRecord, id: UInt32, context: StoreContext) throws {
        let keyPair = IdentityKeyPair(publicKey: record.publicKey, privateKey: record.privateKey)
        self.storePreKey(Int32(bitPattern: id),
                         preKeyRecord: SignalServiceKit.PreKeyRecord(id: Int32(bitPattern: id),
                                                                     keyPair: ECKeyPair(keyPair),
                                                                     createdAt: Date()),
                         transaction: context.asTransaction)
    }

    public func removePreKey(id: UInt32, context: StoreContext) throws {
        self.removePreKey(Int32(bitPattern: id), transaction: context.asTransaction)
    }

}
