//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import LibSignalClient

public class KyberPreKeyStoreImpl {

    enum Constants {
        static let lastKeyId = "lastKeyId"
        static let lastKeyRotationDate = "lastKeyRotationDate"
    }

    private let identity: OWSIdentity
    private let metadataStore: KeyValueStore
    private let dateProvider: DateProvider
    private let preKeyStore: PreKeyStore

    init(
        for identity: OWSIdentity,
        dateProvider: @escaping DateProvider,
        preKeyStore: PreKeyStore,
    ) {
        self.identity = identity
        self.dateProvider = dateProvider
        self.metadataStore = KeyValueStore(collection: {
            switch identity {
            case .aci: "SSKKyberPreKeyStoreACIMetadataStore"
            case .pni: "SSKKyberPreKeyStorePNIMetadataStore"
            }
        }())
        self.preKeyStore = preKeyStore
    }

    func allocatePreKeyIds(count: Int, tx: DBWriteTransaction) -> ClosedRange<UInt32> {
        return preKeyStore.allocatePreKeyIds(in: metadataStore, lastPreKeyIdKey: Constants.lastKeyId, count: count, tx: tx)
    }

    static func generatePreKeyRecord(
        keyId: UInt32,
        now: Date,
        signedBy identityKey: PrivateKey,
    ) -> LibSignalClient.KyberPreKeyRecord {
        let keyPair = KEMKeyPair.generate()
        let signature = identityKey.generateSignature(message: keyPair.publicKey.serialize())
        return try! LibSignalClient.KyberPreKeyRecord(
            id: keyId,
            timestamp: now.ows_millisecondsSince1970,
            keyPair: keyPair,
            signature: signature,
        )
    }

    func generatePreKeyRecords(
        forPreKeyIds keyIds: ClosedRange<UInt32>,
        signedBy identityKey: PrivateKey,
    ) -> [LibSignalClient.KyberPreKeyRecord] {
        Logger.info("Generating \(keyIds.count) pre keys from \(keyIds.lowerBound) through \(keyIds.upperBound)")
        let now = dateProvider()
        return keyIds.map {
            return Self.generatePreKeyRecord(keyId: $0, now: now, signedBy: identityKey)
        }
    }

    func generateLastResortKyberPreKeyForChangeNumber(signedBy identityKey: PrivateKey) -> LibSignalClient.KyberPreKeyRecord {
        return Self.generatePreKeyRecord(keyId: PreKeyId.random(), now: dateProvider(), signedBy: identityKey)
    }

    func storePreKeyRecords(
        _ preKeyRecords: [LibSignalClient.KyberPreKeyRecord],
        isLastResort: Bool,
        tx: DBWriteTransaction,
    ) {
        for preKeyRecord in preKeyRecords {
            preKeyStore.forIdentity(self.identity).upsertPreKeyRecord(
                preKeyRecord.serialize(),
                keyId: preKeyRecord.id,
                in: .kyber,
                isOneTime: !isLastResort,
                tx: tx,
            )
        }
    }

    func storeLastResortPreKeyFromChangeNumber(_ lastResortPreKey: LibSignalClient.KyberPreKeyRecord, tx: DBWriteTransaction) {
        storePreKeyRecords([lastResortPreKey], isLastResort: true, tx: tx)
        metadataStore.setInt32(Int32(lastResortPreKey.id), key: Constants.lastKeyId, transaction: tx)
    }

    func removeMetadata(tx: DBWriteTransaction) {
        self.metadataStore.removeAll(transaction: tx)
    }

    func setLastSuccessfulRotationDate(_ date: Date, tx: DBWriteTransaction) {
        self.metadataStore.setDate(date, key: Constants.lastKeyRotationDate, transaction: tx)
    }

    func getLastSuccessfulRotationDate(tx: DBReadTransaction) -> Date? {
        self.metadataStore.getDate(Constants.lastKeyRotationDate, transaction: tx)
    }

    func setReplacedAtToNowIfNil(exceptFor preKeyIds: [UInt32], isLastResort: Bool, tx: DBWriteTransaction) {
        preKeyStore.setReplacedAtIfNil(
            to: dateProvider(),
            in: .kyber,
            identity: self.identity,
            isOneTime: !isLastResort,
            exceptFor: preKeyIds,
            tx: tx,
        )
    }
}
