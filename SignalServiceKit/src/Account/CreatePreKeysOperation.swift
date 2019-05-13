//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

import Foundation
import PromiseKit

@objc(SSKCreatePreKeysOperation)
public class CreatePreKeysOperation: OWSOperation {

    private var accountServiceClient: AccountServiceClient {
        return AccountServiceClient.shared
    }

    private var primaryStorage: OWSPrimaryStorage {
        return OWSPrimaryStorage.shared()
    }

    private var identityKeyManager: OWSIdentityManager {
        return OWSIdentityManager.shared()
    }

    public override func run() {
        Logger.debug("")

        if self.identityKeyManager.identityKeyPair() == nil {
            self.identityKeyManager.generateNewIdentityKey()
        }
        
        /// Loki: We don't generate PreKeyRecords here.
        /// This is because we need the records to be linked to a contact since we don't have a central server.
        /// It is done automatically when we generate a PreKeyBundle to send to a contact (`generatePreKeyBundleForContact:`).
        /// You can use `getPreKeyForContact:` to generate one if needed.
        let signedPreKeyRecord = self.primaryStorage.generateRandomSignedRecord()
        signedPreKeyRecord.markAsAcceptedByService()
        self.primaryStorage.storeSignedPreKey(signedPreKeyRecord.id, signedPreKeyRecord: signedPreKeyRecord)
        self.primaryStorage.setCurrentSignedPrekeyId(signedPreKeyRecord.id)

        Logger.debug("done")
        self.reportSuccess()
        
        /* Loki: Original Code
        * ==================
        let identityKey: Data = self.identityKeyManager.identityKeyPair()!.publicKey
        let signedPreKeyRecord: SignedPreKeyRecord = self.primaryStorage.generateRandomSignedRecord()
        let preKeyRecords: [PreKeyRecord] = self.primaryStorage.generatePreKeyRecords()

        self.primaryStorage.storeSignedPreKey(signedPreKeyRecord.id, signedPreKeyRecord: signedPreKeyRecord)
        self.primaryStorage.storePreKeyRecords(preKeyRecords)

        firstly {
            self.accountServiceClient.setPreKeys(identityKey: identityKey, signedPreKeyRecord: signedPreKeyRecord, preKeyRecords: preKeyRecords)
        }.done {
            signedPreKeyRecord.markAsAcceptedByService()
            self.primaryStorage.storeSignedPreKey(signedPreKeyRecord.id, signedPreKeyRecord: signedPreKeyRecord)
            self.primaryStorage.setCurrentSignedPrekeyId(signedPreKeyRecord.id)

            Logger.debug("done")
            self.reportSuccess()
        }.catch { error in
            self.reportError(error)
        }.retainUntilComplete()
        */
    }
}
