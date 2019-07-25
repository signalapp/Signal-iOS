//
//  Copyright (c) 2019 Open Whisper Systems. All rights reserved.
//

import Foundation
import PromiseKit

// We generate 100 one-time prekeys at a time.  We should replenish
// whenever ~2/3 of them have been consumed.
let kEphemeralPreKeysMinimumCount: UInt = 35

@objc(SSKRefreshPreKeysOperation)
public class RefreshPreKeysOperation: OWSOperation {

    private var tsAccountManager: TSAccountManager {
        return TSAccountManager.sharedInstance()
    }

    private var accountServiceClient: AccountServiceClient {
        return SSKEnvironment.shared.accountServiceClient
    }

    private var signedPreKeyStore: SSKSignedPreKeyStore {
        return SSKEnvironment.shared.signedPreKeyStore
    }

    private var preKeyStore: SSKPreKeyStore {
        return SSKEnvironment.shared.preKeyStore
    }

    private var identityKeyManager: OWSIdentityManager {
        return OWSIdentityManager.shared()
    }

    public override func run() {
        Logger.debug("")

        guard tsAccountManager.isRegistered else {
            Logger.debug("skipping - not registered")
            return
        }

        firstly {
            self.accountServiceClient.getPreKeysCount()
        }.then(on: DispatchQueue.global()) { preKeysCount -> Promise<Void> in
            Logger.debug("preKeysCount: \(preKeysCount)")
            guard preKeysCount < kEphemeralPreKeysMinimumCount || self.signedPreKeyStore.currentSignedPrekeyId() == nil else {
                Logger.debug("Available keys sufficient: \(preKeysCount)")
                return Promise.value(())
            }

            let identityKey: Data = self.identityKeyManager.identityKeyPair()!.publicKey
            let signedPreKeyRecord: SignedPreKeyRecord = self.signedPreKeyStore.generateRandomSignedRecord()
            let preKeyRecords: [PreKeyRecord] = self.preKeyStore.generatePreKeyRecords()

            self.signedPreKeyStore.storeSignedPreKey(signedPreKeyRecord.id, signedPreKeyRecord: signedPreKeyRecord)
            self.preKeyStore.storePreKeyRecords(preKeyRecords)

            return firstly {
                self.accountServiceClient.setPreKeys(identityKey: identityKey, signedPreKeyRecord: signedPreKeyRecord, preKeyRecords: preKeyRecords)
            }.done {
                signedPreKeyRecord.markAsAcceptedByService()
                self.signedPreKeyStore.storeSignedPreKey(signedPreKeyRecord.id, signedPreKeyRecord: signedPreKeyRecord)
                self.signedPreKeyStore.setCurrentSignedPrekeyId(signedPreKeyRecord.id)

                TSPreKeyManager.clearPreKeyUpdateFailureCount()
                TSPreKeyManager.clearSignedPreKeyRecords()
            }
        }.done {
            Logger.debug("done")
            self.reportSuccess()
        }.catch { error in
            self.reportError(withUndefinedRetry: error)
        }.retainUntilComplete()
    }

    public override func didSucceed() {
        TSPreKeyManager.refreshPreKeysDidSucceed()
    }

    override public func didFail(error: Error) {
        switch error {
        case let networkManagerError as NetworkManagerError:
            guard !networkManagerError.isNetworkError else {
                Logger.debug("don't report SPK rotation failure w/ network error")
                return
            }

            guard networkManagerError.statusCode >= 400 && networkManagerError.statusCode <= 599 else {
                Logger.debug("don't report SPK rotation failure w/ non application error")
                return
            }

            TSPreKeyManager.incrementPreKeyUpdateFailureCount()
        default:
            Logger.debug("don't report SPK rotation failure w/ non NetworkManager error: \(error)")
        }
    }
}
