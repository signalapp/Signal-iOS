//
//  Copyright (c) 2019 Open Whisper Systems. All rights reserved.
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

        self.signedPreKeyStore.storeSignedPreKey(signedPreKeyRecord.id, signedPreKeyRecord: signedPreKeyRecord)
        firstly {
            return self.accountServiceClient.setSignedPreKey(signedPreKeyRecord)
        }.done(on: DispatchQueue.global()) {
            Logger.info("Successfully uploaded signed PreKey")
            signedPreKeyRecord.markAsAcceptedByService()
            self.signedPreKeyStore.storeSignedPreKey(signedPreKeyRecord.id, signedPreKeyRecord: signedPreKeyRecord)
            self.signedPreKeyStore.setCurrentSignedPrekeyId(signedPreKeyRecord.id)

            TSPreKeyManager.clearPreKeyUpdateFailureCount()
            TSPreKeyManager.clearSignedPreKeyRecords()

            Logger.debug("done")
            self.reportSuccess()
        }.catch { error in
            self.reportError(withUndefinedRetry: error)
        }.retainUntilComplete()
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
