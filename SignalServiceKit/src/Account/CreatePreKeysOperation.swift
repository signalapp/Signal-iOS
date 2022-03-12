//
//  Copyright (c) 2022 Open Whisper Systems. All rights reserved.
//

import Foundation

@objc(SSKCreatePreKeysOperation)
public class CreatePreKeysOperation: OWSOperation {

    public override func run() {
        Logger.debug("")

        let identityKeyPair = self.identityManager.identityKeyPair(for: .aci) ?? self.identityManager.generateNewIdentityKey(for: .aci)
        let identityKey: Data = identityKeyPair.publicKey
        let signedPreKeyRecord: SignedPreKeyRecord = self.signedPreKeyStore.generateRandomSignedRecord()
        let preKeyRecords: [PreKeyRecord] = self.preKeyStore.generatePreKeyRecords()

        self.databaseStorage.write { transaction in
            self.signedPreKeyStore.storeSignedPreKey(signedPreKeyRecord.id,
                                                     signedPreKeyRecord: signedPreKeyRecord,
                                                     transaction: transaction)
        }
        self.preKeyStore.storePreKeyRecords(preKeyRecords)

        firstly(on: .global()) { () -> Promise<Void> in
            guard self.tsAccountManager.isRegisteredAndReady else {
                return Promise.value(())
            }
            return self.messageProcessor.fetchingAndProcessingCompletePromise()
        }.then(on: .global()) { () -> Promise<Void> in
            self.accountServiceClient.setPreKeys(identityKey: identityKey,
                                                 signedPreKeyRecord: signedPreKeyRecord,
                                                 preKeyRecords: preKeyRecords)
        }.done {
            signedPreKeyRecord.markAsAcceptedByService()
            self.databaseStorage.write { transaction in
                self.signedPreKeyStore.storeSignedPreKey(signedPreKeyRecord.id,
                                                         signedPreKeyRecord: signedPreKeyRecord,
                                                         transaction: transaction)
            }
            self.signedPreKeyStore.setCurrentSignedPrekeyId(signedPreKeyRecord.id)

            Logger.debug("done")
            self.reportSuccess()
        }.catch { error in
            self.reportError(withUndefinedRetry: error)
        }
    }
}
