//
// Copyright 2020 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import LibSignalClient

public class PreKeyStoreImpl {
    private let identity: OWSIdentity
    private let metadataStore: KeyValueStore
    private let preKeyStore: PreKeyStore

    init(for identity: OWSIdentity, preKeyStore: PreKeyStore) {
        self.identity = identity
        self.metadataStore = KeyValueStore(
            collection: {
                switch identity {
                case .aci: "TSStorageInternalSettingsCollection"
                case .pni: "TSStorageManagerPNIPreKeyMetadataCollection"
                }
            }(),
        )
        self.preKeyStore = preKeyStore
    }

    func allocatePreKeyIds(tx: DBWriteTransaction) -> ClosedRange<UInt32> {
        return preKeyStore.allocatePreKeyIds(
            in: metadataStore,
            lastPreKeyIdKey: "TSStorageInternalSettingsNextPreKeyId",
            count: 100,
            tx: tx,
        )
    }

    static func generatePreKeyRecords(forPreKeyIds keyIds: ClosedRange<UInt32>) -> [LibSignalClient.PreKeyRecord] {
        Logger.info("Generating \(keyIds.count) pre keys from \(keyIds.lowerBound) through \(keyIds.upperBound)")
        return keyIds.map {
            let privateKey = PrivateKey.generate()
            return try! LibSignalClient.PreKeyRecord(
                id: $0,
                publicKey: privateKey.publicKey,
                privateKey: privateKey,
            )
        }
    }

    func storePreKeyRecords(_ preKeyRecords: [LibSignalClient.PreKeyRecord], tx: DBWriteTransaction) {
        for preKeyRecord in preKeyRecords {
            preKeyStore.forIdentity(self.identity).upsertPreKeyRecord(
                preKeyRecord.serialize(),
                keyId: preKeyRecord.id,
                in: .oneTime,
                isOneTime: true,
                tx: tx,
            )
        }
    }

    func setReplacedAtToNowIfNil(exceptFor exceptForPreKeyIds: [UInt32], tx: DBWriteTransaction) {
        preKeyStore.setReplacedAtIfNil(
            to: Date(),
            in: .oneTime,
            identity: self.identity,
            isOneTime: true,
            exceptFor: exceptForPreKeyIds,
            tx: tx,
        )
    }

    func removeMetadata(tx: DBWriteTransaction) {
        metadataStore.removeAll(transaction: tx)
    }
}
