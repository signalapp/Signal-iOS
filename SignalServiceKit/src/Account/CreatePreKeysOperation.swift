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

        let signalProtocolStore = self.signalProtocolStore(for: .aci)
        let signedPreKeyRecord: SignedPreKeyRecord = signalProtocolStore.signedPreKeyStore.generateRandomSignedRecord()
        let preKeyRecords: [PreKeyRecord] = signalProtocolStore.preKeyStore.generatePreKeyRecords()

        self.databaseStorage.write { transaction in
            signalProtocolStore.signedPreKeyStore.storeSignedPreKey(signedPreKeyRecord.id,
                                                                    signedPreKeyRecord: signedPreKeyRecord,
                                                                    transaction: transaction)
        }
        signalProtocolStore.preKeyStore.storePreKeyRecords(preKeyRecords)

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
                signalProtocolStore.signedPreKeyStore.storeSignedPreKey(signedPreKeyRecord.id,
                                                                        signedPreKeyRecord: signedPreKeyRecord,
                                                                        transaction: transaction)
            }
            signalProtocolStore.signedPreKeyStore.setCurrentSignedPrekeyId(signedPreKeyRecord.id)

            Logger.debug("done")
            self.reportSuccess()
        }.catch { error in
            self.reportError(withUndefinedRetry: error)
        }
    }
}
