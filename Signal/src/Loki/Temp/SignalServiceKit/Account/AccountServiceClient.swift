//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

import Foundation
import PromiseKit

// TODO define actual type, and validate length
public typealias IdentityKey = Data

/// based on libsignal-service-java's AccountManager class
@objc(SSKAccountServiceClient)
public class AccountServiceClient: NSObject {

    static var shared = AccountServiceClient()

    private let serviceClient: SignalServiceClient

    override init() {
        self.serviceClient = SignalServiceRestClient()
    }

    public func getPreKeysCount() -> Promise<Int> {
        return serviceClient.getAvailablePreKeys()
    }

    public func setPreKeys(identityKey: IdentityKey, signedPreKeyRecord: SignedPreKeyRecord, preKeyRecords: [PreKeyRecord]) -> Promise<Void> {
        return serviceClient.registerPreKeys(identityKey: identityKey, signedPreKeyRecord: signedPreKeyRecord, preKeyRecords: preKeyRecords)
    }

    public func setSignedPreKey(_ signedPreKey: SignedPreKeyRecord) -> Promise<Void> {
        return serviceClient.setCurrentSignedPreKey(signedPreKey)
    }
}
