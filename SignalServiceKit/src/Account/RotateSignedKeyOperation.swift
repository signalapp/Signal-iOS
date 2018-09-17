//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

import Foundation
import PromiseKit

@objc(SSKRotateSignedPreKeyOperation)
public class RotateSignedPreKeyOperation: OWSOperation {
    private var tsAccountManager: TSAccountManager {
        return TSAccountManager.sharedInstance()
    }

    private var accountServiceClient: AccountServiceClient {
        return AccountServiceClient.shared
    }

    private var primaryStorage: OWSPrimaryStorage {
        return OWSPrimaryStorage.shared()
    }

    public override func run() {
        Logger.debug("")

        guard tsAccountManager.isRegistered() else {
            Logger.debug("skipping - not registered")
            return
        }

        let signedPreKeyRecord: SignedPreKeyRecord = self.primaryStorage.generateRandomSignedRecord()

        firstly {
            self.primaryStorage.storeSignedPreKey(signedPreKeyRecord.id, signedPreKeyRecord: signedPreKeyRecord)
            return self.accountServiceClient.setSignedPreKey(signedPreKeyRecord)
        }.then(on: DispatchQueue.global()) { () -> Void in
            Logger.info("Successfully uploaded signed PreKey")
            signedPreKeyRecord.markAsAcceptedByService()
            self.primaryStorage.storeSignedPreKey(signedPreKeyRecord.id, signedPreKeyRecord: signedPreKeyRecord)
            self.primaryStorage.setCurrentSignedPrekeyId(signedPreKeyRecord.id)

            TSPreKeyManager.clearPreKeyUpdateFailureCount()
            TSPreKeyManager.clearSignedPreKeyRecords()
        }.then { () -> Void in
            Logger.debug("done")
            self.reportSuccess()
        }.catch { error in
            self.reportError(error)
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
