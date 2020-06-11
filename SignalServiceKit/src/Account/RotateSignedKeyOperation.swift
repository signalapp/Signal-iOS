//
//  Copyright (c) 2020 Open Whisper Systems. All rights reserved.
//

import Foundation
import PromiseKit

@objc(SSKRotateSignedPreKeyOperation)
public class RotateSignedPreKeyOperation: OWSOperation {
    private var tsAccountManager: TSAccountManager {
        return TSAccountManager.sharedInstance()
    }

    private var accountServiceClient: AccountServiceClient {
        return SSKEnvironment.shared.accountServiceClient
    }

    private var signedPreKeyStore: SSKSignedPreKeyStore {
        return SSKEnvironment.shared.signedPreKeyStore
    }

    public override func run() {
        Logger.debug("")

        guard tsAccountManager.isRegistered else {
            Logger.debug("skipping - not registered")
            return
        }

        let signedPreKeyRecord: SignedPreKeyRecord = self.signedPreKeyStore.generateRandomSignedRecord()

        firstly(on: .global()) { () -> Promise<Void> in
            self.signedPreKeyStore.storeSignedPreKey(signedPreKeyRecord.id, signedPreKeyRecord: signedPreKeyRecord)
            return self.accountServiceClient.setSignedPreKey(signedPreKeyRecord)
        }.done(on: .global()) { () in
            Logger.info("Successfully uploaded signed PreKey")
            signedPreKeyRecord.markAsAcceptedByService()
            self.signedPreKeyStore.storeSignedPreKey(signedPreKeyRecord.id, signedPreKeyRecord: signedPreKeyRecord)
            self.signedPreKeyStore.setCurrentSignedPrekeyId(signedPreKeyRecord.id)

            TSPreKeyManager.clearPreKeyUpdateFailureCount()
            TSPreKeyManager.clearSignedPreKeyRecords()

            Logger.info("done")
            self.reportSuccess()
        }.catch(on: .global()) { error in
            self.reportError(withUndefinedRetry: error)
        }
    }

    override public func didFail(error: Error) {
        guard !IsNetworkConnectivityFailure(error) else {
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
