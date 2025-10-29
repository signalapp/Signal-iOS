//
// Copyright 2020 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import LibSignalClient

private let lastPreKeyRotationDate = "lastKeyRotationDate"

public class SignedPreKeyStoreImpl {
    private let identity: OWSIdentity
    private let metadataStore: KeyValueStore
    private let preKeyStore: PreKeyStore

    init(for identity: OWSIdentity, preKeyStore: PreKeyStore) {
        self.identity = identity
        self.metadataStore = KeyValueStore(
            collection: {
                switch identity {
                case .aci: "TSStorageManagerSignedPreKeyMetadataCollection"
                case .pni: "TSStorageManagerPNISignedPreKeyMetadataCollection"
                }
            }(),
        )
        self.preKeyStore = preKeyStore
    }

    func setReplacedAtToNowIfNil(exceptFor justUploadedSignedPreKeyId: UInt32, tx: DBWriteTransaction) {
        preKeyStore.setReplacedAtIfNil(
            to: Date(),
            in: .signed,
            identity: self.identity,
            isOneTime: false,
            exceptFor: [justUploadedSignedPreKeyId],
            tx: tx,
        )
    }

    func setLastSuccessfulRotationDate(_ date: Date, tx: DBWriteTransaction) {
        metadataStore.setDate(date, key: lastPreKeyRotationDate, transaction: tx)
    }

    func getLastSuccessfulRotationDate(tx: DBReadTransaction) -> Date? {
        metadataStore.getDate(lastPreKeyRotationDate, transaction: tx)
    }

    func removeMetadata(tx: DBWriteTransaction) {
        metadataStore.removeAll(transaction: tx)
    }

    func allocatePreKeyId(tx: DBWriteTransaction) -> UInt32 {
        return preKeyStore.allocatePreKeyIds(
            in: self.metadataStore,
            lastPreKeyIdKey: "TSStorageInternalSettingsNextPreKeyId",
            count: 1,
            tx: tx,
        ).upperBound
    }

    static func generateSignedPreKey(
        keyId: UInt32,
        signedBy identityKey: PrivateKey,
    ) -> LibSignalClient.SignedPreKeyRecord {
        Logger.info("generating signed pre key \(keyId)")
        let privateKey = PrivateKey.generate()
        return try! LibSignalClient.SignedPreKeyRecord(
            id: keyId,
            timestamp: Date().ows_millisecondsSince1970,
            privateKey: privateKey,
            signature: identityKey.generateSignature(message: privateKey.publicKey.serialize()),
        )
    }

    func storeSignedPreKey(_ signedPreKey: LibSignalClient.SignedPreKeyRecord, tx: DBWriteTransaction) {
        preKeyStore.forIdentity(self.identity).upsertPreKeyRecord(
            signedPreKey.serialize(),
            keyId: signedPreKey.id,
            in: .signed,
            isOneTime: false,
            tx: tx,
        )
    }
}
