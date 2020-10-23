//
//  Copyright (c) 2020 Open Whisper Systems. All rights reserved.
//

import SignalClient

extension SSKSignedPreKeyStore: SignalClient.SignedPreKeyStore {
    enum Error: Swift.Error {
        case noPreKeyWithId(UInt32)
    }

    public func loadSignedPreKey(id: UInt32,
                                 context: UnsafeMutableRawPointer?) throws -> SignalClient.SignedPreKeyRecord {
        guard let preKey = self.loadSignedPreKey(Int32(bitPattern: id),
                                                 transaction: context!.load(as: SDSAnyWriteTransaction.self)) else {
            throw Error.noPreKeyWithId(id)
        }
        return try .init(
            id: UInt32(bitPattern: preKey.id),
            timestamp: preKey.createdAt?.ows_millisecondsSince1970 ?? 0,
            privateKey: preKey.keyPair.identityKeyPair.privateKey,
            signature: preKey.signature)
    }

    public func storeSignedPreKey(_ record: SignalClient.SignedPreKeyRecord,
                                  id: UInt32,
                                  context: UnsafeMutableRawPointer?) throws {
        let keyPair = IdentityKeyPair(publicKey: try record.publicKey(), privateKey: try record.privateKey())
        let axolotlRecord = AxolotlKit.SignedPreKeyRecord(
            id: Int32(bitPattern: id),
            keyPair: ECKeyPair(keyPair),
            signature: Data(try record.signature()),
            generatedAt: Date(millisecondsSince1970: try record.timestamp()))
        self.storeSignedPreKey(Int32(bitPattern: id),
                               signedPreKeyRecord: axolotlRecord,
                               transaction: context!.load(as: SDSAnyWriteTransaction.self))
    }

}
