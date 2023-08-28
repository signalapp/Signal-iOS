//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

extension PreKeyTasks {

    internal class PersistBase {

        fileprivate let dateProvider: DateProvider
        fileprivate let db: DB
        fileprivate let preKeyStore: SignalPreKeyStore
        fileprivate let signedPreKeyStore: SignalSignedPreKeyStore
        fileprivate let kyberPreKeyStore: SignalKyberPreKeyStore

        internal init(
            dateProvider: @escaping DateProvider,
            db: DB,
            preKeyStore: SignalPreKeyStore,
            signedPreKeyStore: SignalSignedPreKeyStore,
            kyberPreKeyStore: SignalKyberPreKeyStore
        ) {
            self.dateProvider = dateProvider
            self.db = db
            self.preKeyStore = preKeyStore
            self.signedPreKeyStore = signedPreKeyStore
            self.kyberPreKeyStore = kyberPreKeyStore
        }

        fileprivate func persistForSuccessulUpload(bundle: PreKeyUploadBundle) throws {
            try self.db.write { tx in
                // save last-resort PQ key here as well (if created)
                if let signedPreKeyRecord = bundle.getSignedPreKey() {

                    // Mark the new Signed Prekey as accepted
                    self.signedPreKeyStore.storeSignedPreKeyAsAcceptedAndCurrent(
                        signedPreKeyId: signedPreKeyRecord.id,
                        signedPreKeyRecord: signedPreKeyRecord,
                        tx: tx
                    )

                    self.signedPreKeyStore.setLastSuccessfulPreKeyRotationDate(self.dateProvider(), tx: tx)

                    self.signedPreKeyStore.cullSignedPreKeyRecords(tx: tx)
                }

                if let lastResortPreKey = bundle.getLastResortPreKey() {

                    try self.kyberPreKeyStore.storeLastResortPreKeyAndMarkAsCurrent(
                        record: lastResortPreKey,
                        tx: tx
                    )

                    // Register a successful key rotation
                    self.kyberPreKeyStore.setLastSuccessfulPreKeyRotationDate(self.dateProvider(), tx: tx)

                    // Cleanup any old keys
                    try self.kyberPreKeyStore.cullLastResortPreKeyRecords(tx: tx)
                }

                if let newPreKeyRecords = bundle.getPreKeyRecords() {

                    // Store newly added prekeys
                    self.preKeyStore.storePreKeyRecords(newPreKeyRecords, tx: tx)

                    // OneTime PreKey Cleanup
                    self.preKeyStore.cullPreKeyRecords(tx: tx)
                }

                if let pqPreKeyRecords = bundle.getPqPreKeyRecords() {
                    try self.kyberPreKeyStore.storeKyberPreKeyRecords(records: pqPreKeyRecords, tx: tx)

                    try self.kyberPreKeyStore.cullOneTimePreKeyRecords(tx: tx)
                }
            }
        }
    }

    /// Unlike the below method, this does not mark the stored prekeys as "current" or "accepted by server"
    /// TODO: should the concept of "current" and "accepted" go away?
    internal class PersistPriorToUpload: PersistBase {

        func runTask(
            bundle: PreKeyUploadBundle
        ) throws {
            try self.db.write { tx in
                if let signedPreKeyRecord = bundle.getSignedPreKey() {
                    self.signedPreKeyStore.storeSignedPreKey(
                        signedPreKeyRecord.id,
                        signedPreKeyRecord: signedPreKeyRecord,
                        tx: tx
                    )
                }
                if let lastResortPreKey = bundle.getLastResortPreKey() {
                    try self.kyberPreKeyStore.storeKyberPreKey(
                        record: lastResortPreKey,
                        tx: tx
                    )
                }
                if let newPreKeyRecords = bundle.getPreKeyRecords() {
                    self.preKeyStore.storePreKeyRecords(newPreKeyRecords, tx: tx)
                }
                if let pqPreKeyRecords = bundle.getPqPreKeyRecords() {
                    try self.kyberPreKeyStore.storeKyberPreKeyRecords(records: pqPreKeyRecords, tx: tx)
                }
            }
        }
    }

    internal class PersistAfterRegistration: PersistBase {

        func runTask(
            bundle: RegistrationPreKeyUploadBundle,
            uploadDidSucceed: Bool
        ) throws {
            if uploadDidSucceed {
                try persistForSuccessulUpload(bundle: bundle)
            } else {
                // Wipe the keys.
                self.db.write { tx in
                    self.signedPreKeyStore.removeSignedPreKey(bundle.signedPreKey, tx: tx)
                    self.kyberPreKeyStore.removeLastResortPreKey(record: bundle.lastResortPreKey, tx: tx)
                }
            }
        }
    }

    internal class PersistSuccesfulUpload: PersistBase {

        func runTask(
            bundle: PreKeyUploadBundle
        ) throws {
            try persistForSuccessulUpload(bundle: bundle)
        }
    }
}
