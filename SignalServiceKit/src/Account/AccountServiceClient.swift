//
//  Copyright (c) 2020 Open Whisper Systems. All rights reserved.
//

import Foundation
import PromiseKit

// TODO define actual type, and validate length
public typealias IdentityKey = Data

public enum AccountServiceClientError: Error {
    case captchaRequired
}

/// based on libsignal-service-java's AccountManager class
@objc
public class AccountServiceClient: NSObject {

    private let serviceClient: SignalServiceClient

    override init() {
        self.serviceClient = SignalServiceRestClient()
    }

    // MARK: - Public

    public func requestPreauthChallenge(recipientId: String, pushToken: String) -> Promise<Void> {
        return serviceClient.requestPreauthChallenge(recipientId: recipientId, pushToken: pushToken)
    }

    public func requestVerificationCode(recipientId: String, preauthChallenge: String?, captchaToken: String?, transport: TSVerificationTransport) -> Promise<Void> {
        return serviceClient.requestVerificationCode(recipientId: recipientId,
                                                     preauthChallenge: preauthChallenge,
                                                     captchaToken: captchaToken,
                                                     transport: transport).recover { error in
                                                        if error.httpStatusCode == 402 {
                                                            throw AccountServiceClientError.captchaRequired
                                                        }
            throw error
        }
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

    public func updatePrimaryDeviceAccountAttributes() -> Promise<Void> {
        return serviceClient.updatePrimaryDeviceAccountAttributes()
    }

    public func getUuid() -> Promise<UUID> {
        return serviceClient.getAccountUuid()
    }

    public func verifySecondaryDevice(verificationCode: String,
                                      phoneNumber: String,
                                      authKey: String,
                                      encryptedDeviceName: Data) -> Promise<UInt32> {
        return serviceClient.verifySecondaryDevice(verificationCode: verificationCode, phoneNumber: phoneNumber, authKey: authKey, encryptedDeviceName: encryptedDeviceName)
    }
}
