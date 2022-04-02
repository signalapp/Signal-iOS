//
//  Copyright (c) 2022 Open Whisper Systems. All rights reserved.
//

import Foundation

@objc(SSKRotateSignedPreKeyOperation)
public class RotateSignedPreKeyOperation: OWSOperation {

    public override func run() {
        Logger.debug("")

        guard tsAccountManager.isRegistered else {
            Logger.debug("skipping - not registered")
            return
        }

        // PNI TODO: parameterize this entire operation on OWSIdentity
        let signalProtocolStore = self.signalProtocolStore(for: .aci)
        let signedPreKeyRecord: SignedPreKeyRecord = signalProtocolStore.signedPreKeyStore.generateRandomSignedRecord()

        firstly(on: .global()) { () -> Promise<Void> in
            self.messageProcessor.fetchingAndProcessingCompletePromise()
        }.then(on: .global()) { () -> Promise<Void> in
            self.databaseStorage.write { transaction in
                signalProtocolStore.signedPreKeyStore.storeSignedPreKey(signedPreKeyRecord.id,
                                                                        signedPreKeyRecord: signedPreKeyRecord,
                                                                        transaction: transaction)
            }
            return self.accountServiceClient.setSignedPreKey(signedPreKeyRecord)
        }.done(on: .global()) { () in
            Logger.info("Successfully uploaded signed PreKey")
            signedPreKeyRecord.markAsAcceptedByService()
            self.databaseStorage.write { transaction in
                signalProtocolStore.signedPreKeyStore.storeSignedPreKey(signedPreKeyRecord.id,
                                                                        signedPreKeyRecord: signedPreKeyRecord,
                                                                        transaction: transaction)
                signalProtocolStore.signedPreKeyStore.setCurrentSignedPrekeyId(signedPreKeyRecord.id,
                                                                               transaction: transaction)
                signalProtocolStore.signedPreKeyStore.cullSignedPreKeyRecords(transaction: transaction)
            }

            TSPreKeyManager.clearPreKeyUpdateFailureCount()

            Logger.info("done")
            self.reportSuccess()
        }.catch(on: .global()) { error in
            self.reportError(withUndefinedRetry: error)
        }
    }

    override public func didFail(error: Error) {
        guard !error.isNetworkConnectivityFailure else {
            Logger.debug("don't report SPK rotation failure w/ network error")
            return
        }
        guard let statusCode = error.httpStatusCode else {
            Logger.debug("don't report SPK rotation failure w/ non NetworkManager error: \(error)")
            return
        }
        guard statusCode >= 400 && statusCode <= 599 else {
            Logger.debug("don't report SPK rotation failure w/ non application error")
            return
        }

        TSPreKeyManager.incrementPreKeyUpdateFailureCount()
    }
}
