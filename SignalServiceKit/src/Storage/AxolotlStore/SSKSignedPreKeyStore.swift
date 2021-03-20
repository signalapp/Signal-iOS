//
//  Copyright (c) 2021 Open Whisper Systems. All rights reserved.
//

import SignalClient

extension SSKSignedPreKeyStore: SignedPreKeyStore {
    enum Error: Swift.Error {
        case noPreKeyWithId(UInt32)
    }

    public func loadSignedPreKey(id: UInt32, context: StoreContext) throws -> SignalClient.SignedPreKeyRecord {
        guard let preKey = self.loadSignedPreKey(Int32(bitPattern: id), transaction: context.asTransaction) else {
            throw Error.noPreKeyWithId(id)
        }
        return try .init(
            id: UInt32(bitPattern: preKey.id),
            timestamp: preKey.createdAt?.ows_millisecondsSince1970 ?? 0,
            privateKey: preKey.keyPair.identityKeyPair.privateKey,
            signature: preKey.signature)
    }

    public func storeSignedPreKey(_ record: SignalClient.SignedPreKeyRecord, id: UInt32, context: StoreContext) throws {
        let keyPair = IdentityKeyPair(publicKey: record.publicKey, privateKey: record.privateKey)
        let axolotlRecord = SignalServiceKit.SignedPreKeyRecord(
            id: Int32(bitPattern: id),
            keyPair: ECKeyPair(keyPair),
            signature: Data(record.signature),
            generatedAt: Date(millisecondsSince1970: record.timestamp))
        self.storeSignedPreKey(Int32(bitPattern: id),
                               signedPreKeyRecord: axolotlRecord,
                               transaction: context.asTransaction)
    }

}
