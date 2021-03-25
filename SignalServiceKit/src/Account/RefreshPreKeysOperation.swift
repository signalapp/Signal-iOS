//
//  Copyright (c) 2021 Open Whisper Systems. All rights reserved.
//

import Foundation
import PromiseKit

// We generate 100 one-time prekeys at a time.  We should replenish
// whenever ~2/3 of them have been consumed.
let kEphemeralPreKeysMinimumCount: UInt = 35

@objc(SSKRefreshPreKeysOperation)
public class RefreshPreKeysOperation: OWSOperation {

    public override func run() {
        Logger.debug("")

        guard tsAccountManager.isRegistered else {
            Logger.debug("skipping - not registered")
            return
        }

        firstly(on: .global()) { () -> Promise<Void> in
            self.messageProcessor.fetchingAndProcessingCompletePromise()
        }.then(on: .global()) { () -> Promise<Int> in
            self.accountServiceClient.getPreKeysCount()
        }.then(on: .global()) { (preKeysCount: Int) -> Promise<Void> in
            Logger.info("preKeysCount: \(preKeysCount)")
            guard preKeysCount < kEphemeralPreKeysMinimumCount || self.signedPreKeyStore.currentSignedPrekeyId() == nil else {
                Logger.debug("Available keys sufficient: \(preKeysCount)")
                return Promise.value(())
            }

            let identityKey: Data = self.identityManager.identityKeyPair()!.publicKey
            let signedPreKeyRecord: SignedPreKeyRecord = self.signedPreKeyStore.generateRandomSignedRecord()
            let preKeyRecords: [PreKeyRecord] = self.preKeyStore.generatePreKeyRecords()

            self.databaseStorage.write { transaction in
                self.signedPreKeyStore.storeSignedPreKey(signedPreKeyRecord.id,
                                                         signedPreKeyRecord: signedPreKeyRecord,
                                                         transaction: transaction)
            }
            self.preKeyStore.storePreKeyRecords(preKeyRecords)

            return firstly(on: .global()) { () -> Promise<Void> in
                self.accountServiceClient.setPreKeys(identityKey: identityKey, signedPreKeyRecord: signedPreKeyRecord, preKeyRecords: preKeyRecords)
            }.done(on: .global()) { () in
                signedPreKeyRecord.markAsAcceptedByService()

                self.databaseStorage.write { transaction in
                    self.signedPreKeyStore.storeSignedPreKey(signedPreKeyRecord.id,
                                                             signedPreKeyRecord: signedPreKeyRecord,
                                                             transaction: transaction)
                }
                self.signedPreKeyStore.setCurrentSignedPrekeyId(signedPreKeyRecord.id)

                TSPreKeyManager.clearPreKeyUpdateFailureCount()
                TSPreKeyManager.clearSignedPreKeyRecords()
                TSPreKeyManager.cullPreKeyRecords()
            }
        }.done(on: .global()) {
            Logger.info("done")
            self.reportSuccess()
        }.catch(on: .global()) { error in
            self.reportError(withUndefinedRetry: error)
        }
    }

    public override func didSucceed() {
        TSPreKeyManager.refreshPreKeysDidSucceed()
    }

    override public func didFail(error: Error) {
        guard !IsNetworkConnectivityFailure(error) else {
            Logger.debug("don't report PK rotation failure w/ network error")
            return
        }
        guard let statusCode = error.httpStatusCode else {
            Logger.debug("don't report PK rotation failure w/ non NetworkManager error: \(error)")
            return
        }
        guard statusCode >= 400 && statusCode <= 599 else {
            Logger.debug("don't report PK rotation failure w/ non application error")
            return
        }

        TSPreKeyManager.incrementPreKeyUpdateFailureCount()
    }
}
