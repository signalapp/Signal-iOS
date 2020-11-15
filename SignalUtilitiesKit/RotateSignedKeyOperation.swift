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

    private var primaryStorage: OWSPrimaryStorage {
        return OWSPrimaryStorage.shared()
    }

    public override func run() {
        Logger.debug("")

        guard tsAccountManager.isRegistered() else {
            Logger.debug("skipping - not registered")
            return
        }
        
        DispatchQueue.global().async {
            SessionManagementProtocol.rotateSignedPreKey()
            self.reportSuccess()
        }
    }

    override public func didFail(error: Error) {
        Logger.debug("don't report SPK rotation failure w/ non NetworkManager error: \(error)")
    }
}
