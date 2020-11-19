//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
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

    private var identityKeyManager: OWSIdentityManager {
        return OWSIdentityManager.shared()
    }

    public override func run() {
        Logger.debug("")

        guard tsAccountManager.isRegistered() else {
            Logger.debug("Skipping pre key refresh; user isn't registered.")
            return
        }
        
        DispatchQueue.global().async {
            let storage = OWSPrimaryStorage.shared()
            guard storage.currentSignedPrekeyId() == nil else { return }
            let signedPreKeyRecord = storage.generateRandomSignedRecord()
            signedPreKeyRecord.markAsAcceptedByService()
            storage.storeSignedPreKey(signedPreKeyRecord.id, signedPreKeyRecord: signedPreKeyRecord)
            storage.setCurrentSignedPrekeyId(signedPreKeyRecord.id)
            TSPreKeyManager.clearPreKeyUpdateFailureCount()
            TSPreKeyManager.clearSignedPreKeyRecords()
            SNLog("Signed pre key refreshed successfully.")
            self.reportSuccess()
        }
    }

    public override func didSucceed() {
        TSPreKeyManager.refreshPreKeysDidSucceed()
    }

    override public func didFail(error: Error) {
        Logger.debug("Don't report SPK rotation failure w/ non NetworkManager error: \(error)")
    }
}
