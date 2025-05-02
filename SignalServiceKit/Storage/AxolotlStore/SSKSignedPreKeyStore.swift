//
// Copyright 2020 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
public import LibSignalClient

private let lastPreKeyRotationDate = "lastKeyRotationDate"

public class SSKSignedPreKeyStore: NSObject {

    private let identity: OWSIdentity
    private let keyStore: KeyValueStore
    private let metadataStore: KeyValueStore

    public init(for identity: OWSIdentity) {
        self.identity = identity

        switch identity {
        case .aci:
            self.keyStore = KeyValueStore(collection: "TSStorageManagerSignedPreKeyStoreCollection")
            self.metadataStore = KeyValueStore(collection: "TSStorageManagerSignedPreKeyMetadataCollection")
        case .pni:
            self.keyStore = KeyValueStore(collection: "TSStorageManagerPNISignedPreKeyStoreCollection")
            self.metadataStore = KeyValueStore(collection: "TSStorageManagerPNISignedPreKeyMetadataCollection")
        }
    }

    // MARK: - SignedPreKeyStore transactions

    public func loadSignedPreKey(_ signedPreKeyId: Int32, transaction: DBReadTransaction) -> SignalServiceKit.SignedPreKeyRecord? {
        keyStore.signedPreKeyRecord(key: keyValueStoreKey(int: Int(signedPreKeyId)), transaction: transaction)
    }

    public func storeSignedPreKey(_ signedPreKeyId: Int32, signedPreKeyRecord: SignalServiceKit.SignedPreKeyRecord, transaction: DBWriteTransaction) {
        keyStore.setSignedPreKeyRecord(signedPreKeyRecord, key: keyValueStoreKey(int: Int(signedPreKeyId)), transaction: transaction)
    }

    public func removeSignedPreKey(_ signedPreKeyId: Int32, transaction: DBWriteTransaction) {
        Logger.info("Removing signed prekey id: \(signedPreKeyId).")
        keyStore.removeValue(forKey: keyValueStoreKey(int: Int(signedPreKeyId)), transaction: transaction)
    }

    private func keyValueStoreKey(int: Int) -> String {
        return NSNumber(value: int).stringValue
    }

    func setReplacedAtToNowIfNil(exceptFor justUploadedSignedPreKey: SignalServiceKit.SignedPreKeyRecord, transaction tx: DBWriteTransaction) {
        let exceptForKey = keyValueStoreKey(int: Int(justUploadedSignedPreKey.id))
        keyStore.allKeys(transaction: tx).forEach { key in autoreleasepool {
            if key == exceptForKey {
                return
            }
            let record = keyStore.getObject(key, ofClass: SignalServiceKit.SignedPreKeyRecord.self, transaction: tx)
            guard let record, record.replacedAt == nil else {
                return
            }
            record.setReplacedAtToNow()
            storeSignedPreKey(record.id, signedPreKeyRecord: record, transaction: tx)
        }}
    }

    public func cullSignedPreKeyRecords(gracePeriod: TimeInterval, transaction tx: DBWriteTransaction) {
        keyStore.allKeys(transaction: tx).forEach { key in autoreleasepool {
            let record = keyStore.getObject(key, ofClass: SignalServiceKit.SignedPreKeyRecord.self, transaction: tx)
            guard let record else {
                owsFailDebug("Couldn't decode SignedPreKeyRecord.")
                keyStore.removeValue(forKey: key, transaction: tx)
                return
            }
            guard
                let replacedAt = record.replacedAt,
                fabs(replacedAt.timeIntervalSinceNow) > (PreKeyManagerImpl.Constants.maxUnacknowledgedSessionAge + gracePeriod)
            else {
                // Never delete signed prekeys until they're obsolete for N days.
                return
            }
            Logger.info("Deleting signed prekey id: \(record.id), generatedAt: \(record.generatedAt), replacedAt: \(replacedAt)")
            keyStore.removeValue(forKey: key, transaction: tx)
        }}
    }

    // MARK: -

    public func generateRandomSignedRecord() -> SignalServiceKit.SignedPreKeyRecord {
        let identityKeyPair = SSKEnvironment.shared.databaseStorageRef.read { DependenciesBridge.shared.identityManager.identityKeyPair(for: identity, tx: $0) }
        guard let identityKeyPair else {
            owsFail("identity key unexpectedly unavailable")
        }
        return generateSignedPreKey(signedBy: identityKeyPair)
    }

    // MARK: - Prekey rotation tracking

    public func setLastSuccessfulRotationDate(_ date: Date, transaction: DBWriteTransaction) {
        metadataStore.setDate(date, key: lastPreKeyRotationDate, transaction: transaction)
    }

    public func getLastSuccessfulRotationDate(transaction: DBReadTransaction) -> Date? {
        metadataStore.getDate(lastPreKeyRotationDate, transaction: transaction)
    }

    public func removeAll(transaction: DBWriteTransaction) {
        Logger.warn("")
        keyStore.removeAll(transaction: transaction)
        metadataStore.removeAll(transaction: transaction)
    }
}

extension SSKSignedPreKeyStore {
    @objc
    public class func generateSignedPreKey(
        signedBy identityKeyPair: ECKeyPair
    ) -> SignalServiceKit.SignedPreKeyRecord {
        let keyPair = ECKeyPair.generateKeyPair()

        // Signed prekey ids must be > 0.
        let preKeyId = Int32.random(in: 1..<Int32.max)

        return SignedPreKeyRecord(
            id: preKeyId,
            keyPair: keyPair,
            signature: Data(identityKeyPair.keyPair.privateKey.generateSignature(
                message: Data(keyPair.keyPair.publicKey.serialize())
            )),
            generatedAt: Date(),
            replacedAt: nil
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
        // This isn't used today. If it's used in the future, `replacedAt` will
        // need to be handled (though it seems likely that nil would be an
        // acceptable default).
        owsAssertDebug(CurrentAppContext().isRunningTests, "This can't be used for updating existing records.")

        let sskRecord = try record.asSSKRecord()

        self.storeSignedPreKey(Int32(bitPattern: id),
                               signedPreKeyRecord: sskRecord,
                               transaction: context.asTransaction)
    }
}

extension LibSignalClient.SignedPreKeyRecord {
    func asSSKRecord() throws -> SignalServiceKit.SignedPreKeyRecord {
        let keyPair = IdentityKeyPair(
            publicKey: try self.publicKey(),
            privateKey: try self.privateKey()
        )

        return SignalServiceKit.SignedPreKeyRecord(
            id: Int32(bitPattern: self.id),
            keyPair: ECKeyPair(keyPair),
            signature: Data(self.signature),
            generatedAt: Date(millisecondsSince1970: self.timestamp),
            replacedAt: nil
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

extension KeyValueStore {
    fileprivate func signedPreKeyRecord(key: String, transaction: DBReadTransaction) -> SignalServiceKit.SignedPreKeyRecord? {
        return getObject(key, ofClass: SignalServiceKit.SignedPreKeyRecord.self, transaction: transaction)
    }

    fileprivate func setSignedPreKeyRecord(_ record: SignalServiceKit.SignedPreKeyRecord, key: String, transaction: DBWriteTransaction) {
        setObject(record, key: key, transaction: transaction)
    }
}
