//
//  Copyright (c) 2019 Open Whisper Systems. All rights reserved.
//

import Foundation
import PromiseKit

@objc(SSKCreatePreKeysOperation)
public class CreatePreKeysOperation: OWSOperation {

    private var accountServiceClient: AccountServiceClient {
        return SSKEnvironment.shared.accountServiceClient
    }

    private var preKeyStore: SSKPreKeyStore {
        return SSKEnvironment.shared.preKeyStore
    }

    private var signedPreKeyStore: SSKSignedPreKeyStore {
        return SSKEnvironment.shared.signedPreKeyStore
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
        let signedPreKeyRecord: SignedPreKeyRecord = self.signedPreKeyStore.generateRandomSignedRecord()
        let preKeyRecords: [PreKeyRecord] = self.preKeyStore.generatePreKeyRecords()

        self.signedPreKeyStore.storeSignedPreKey(signedPreKeyRecord.id, signedPreKeyRecord: signedPreKeyRecord)
        self.preKeyStore.storePreKeyRecords(preKeyRecords)

        firstly {
            self.accountServiceClient.setPreKeys(identityKey: identityKey, signedPreKeyRecord: signedPreKeyRecord, preKeyRecords: preKeyRecords)
        }.done {
            signedPreKeyRecord.markAsAcceptedByService()
            self.signedPreKeyStore.storeSignedPreKey(signedPreKeyRecord.id, signedPreKeyRecord: signedPreKeyRecord)
            self.signedPreKeyStore.setCurrentSignedPrekeyId(signedPreKeyRecord.id)

            Logger.debug("done")
            self.reportSuccess()
        }.catch { error in
            self.reportError(withUndefinedRetry: error)
        }.retainUntilComplete()
    }
}
