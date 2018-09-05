//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

import Foundation
import PromiseKit

// TODO define actual type, and validate length
public typealias IdentityKey = Data

@objc(SSKAccountManager)
public class AccountManager: NSObject {

    static var shared = AccountManager()

    private let serviceSocket: ServiceSocket

    override init() {
        self.serviceSocket = ServiceRestSocket()
    }

    public func getPreKeysCount() -> Promise<Int> {
        return serviceSocket.getAvailablePreKeys()
    }

    public func setPreKeys(identityKey: IdentityKey, signedPreKeyRecord: SignedPreKeyRecord, preKeyRecords: [PreKeyRecord]) -> Promise<Void> {
        return serviceSocket.registerPreKeys(identityKey: identityKey, signedPreKeyRecord: signedPreKeyRecord, preKeyRecords: preKeyRecords)
    }

    public func setSignedPreKey(_ signedPreKey: SignedPreKeyRecord) -> Promise<Void> {
        return serviceSocket.setCurrentSignedPreKey(signedPreKey)
    }
}
