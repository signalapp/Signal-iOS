//
//  Copyright (c) 2020 Open Whisper Systems. All rights reserved.
//

import SignalClient

extension SSKPreKeyStore: SignalClient.PreKeyStore {
    enum Error: Swift.Error {
        case noPreKeyWithId(UInt32)
    }

    public func loadPreKey(id: UInt32, context: UnsafeMutableRawPointer?) throws -> SignalClient.PreKeyRecord {
        guard let preKey = self.loadPreKey(Int32(bitPattern: id),
                                           protocolContext: context!.load(as: SDSAnyWriteTransaction.self)) else {
            throw Error.noPreKeyWithId(id)
        }
        let keyPair = preKey.keyPair.identityKeyPair
        return try .init(id: UInt32(bitPattern: preKey.id),
                         publicKey: keyPair.publicKey,
                         privateKey: keyPair.privateKey)
    }

    public func storePreKey(_ record: SignalClient.PreKeyRecord, id: UInt32, context: UnsafeMutableRawPointer?) throws {
        let keyPair = IdentityKeyPair(publicKey: record.publicKey, privateKey: record.privateKey)
        self.storePreKey(Int32(bitPattern: id),
                         preKeyRecord: AxolotlKit.PreKeyRecord(id: Int32(bitPattern: id),
                                                               keyPair: ECKeyPair(keyPair),
                                                               createdAt: Date()),
                         protocolContext: context!.load(as: SDSAnyWriteTransaction.self))
    }

    public func removePreKey(id: UInt32, context: UnsafeMutableRawPointer?) throws {
        self.removePreKey(Int32(bitPattern: id), protocolContext: context!.load(as: SDSAnyWriteTransaction.self))
    }

}
