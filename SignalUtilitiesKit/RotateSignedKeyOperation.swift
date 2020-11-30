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

    public override func run() {
        Logger.debug("")

        guard tsAccountManager.isRegistered() else {
            Logger.debug("skipping - not registered")
            return
        }
        
        DispatchQueue.global().async {
            let storage = OWSPrimaryStorage.shared()
            let signedPreKeyRecord = storage.generateRandomSignedRecord()
            signedPreKeyRecord.markAsAcceptedByService()
            storage.storeSignedPreKey(signedPreKeyRecord.id, signedPreKeyRecord: signedPreKeyRecord)
            storage.setCurrentSignedPrekeyId(signedPreKeyRecord.id)
            TSPreKeyManager.clearPreKeyUpdateFailureCount()
            TSPreKeyManager.clearSignedPreKeyRecords()
            SNLog("Signed pre key rotated successfully.")
            self.reportSuccess()
        }
    }

    override public func didFail(error: Error) {
        Logger.debug("don't report SPK rotation failure w/ non NetworkManager error: \(error)")
    }
}
