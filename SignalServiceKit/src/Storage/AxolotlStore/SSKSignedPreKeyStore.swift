//
// Copyright 2020 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import LibSignalClient

extension SSKSignedPreKeyStore {
    func storeSignedPreKeyAsAcceptedAndCurrent(
        signedPreKeyId: Int32,
        signedPreKeyRecord: SignalServiceKit.SignedPreKeyRecord,
        transaction: SDSAnyWriteTransaction
    ) {
        signedPreKeyRecord.markAsAcceptedByService()

        storeSignedPreKey(
            signedPreKeyId,
            signedPreKeyRecord: signedPreKeyRecord,
            transaction: transaction
        )

        setCurrentSignedPrekeyId(
            signedPreKeyId,
            transaction: transaction
        )
    }
}

extension SSKSignedPreKeyStore: LibSignalClient.SignedPreKeyStore {
    enum Error: Swift.Error {
        case noPreKeyWithId(UInt32)
    }

    public func loadSignedPreKey(id: UInt32, context: StoreContext) throws -> LibSignalClient.SignedPreKeyRecord {
        guard let preKey = self.loadSignedPreKey(Int32(bitPattern: id), transaction: context.asTransaction) else {
            throw Error.noPreKeyWithId(id)
        }

        return try preKey.asLSCRecord()
    }

    public func storeSignedPreKey(_ record: LibSignalClient.SignedPreKeyRecord, id: UInt32, context: StoreContext) throws {
        let sskRecord = record.asSSKRecord()

        self.storeSignedPreKey(Int32(bitPattern: id),
                               signedPreKeyRecord: sskRecord,
                               transaction: context.asTransaction)
    }
}

extension LibSignalClient.SignedPreKeyRecord {
    func asSSKRecord() -> SignalServiceKit.SignedPreKeyRecord {
        let keyPair = IdentityKeyPair(
            publicKey: self.publicKey,
            privateKey: self.privateKey
        )

        return SignalServiceKit.SignedPreKeyRecord(
            id: Int32(bitPattern: self.id),
            keyPair: ECKeyPair(keyPair),
            signature: Data(self.signature),
            generatedAt: Date(millisecondsSince1970: self.timestamp)
        )
    }
}

extension SignalServiceKit.SignedPreKeyRecord {
    func asLSCRecord() throws -> LibSignalClient.SignedPreKeyRecord {
        try LibSignalClient.SignedPreKeyRecord(
            id: UInt32(bitPattern: self.id),
            timestamp: self.createdAt?.ows_millisecondsSince1970 ?? 0,
            privateKey: self.keyPair.identityKeyPair.privateKey,
            signature: self.signature
        )
    }
}
