//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

import Foundation
import PromiseKit

@objc(SSKCreatePreKeysOperation)
public class CreatePreKeysOperation: OWSOperation {

    private var primaryStorage: OWSPrimaryStorage {
        return OWSPrimaryStorage.shared()
    }

    private var identityKeyManager: OWSIdentityManager {
        return OWSIdentityManager.shared()
    }

    public override func run() {
        Logger.debug("")

        if identityKeyManager.identityKeyPair() == nil {
            identityKeyManager.generateNewIdentityKeyPair()
        }

        SessionManagementProtocol.createPreKeys()
        reportSuccess()
    }
}
