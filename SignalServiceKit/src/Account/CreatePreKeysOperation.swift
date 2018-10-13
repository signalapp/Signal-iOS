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
    }
}
