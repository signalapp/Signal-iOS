//
// Copyright 2018 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

// TODO define actual type, and validate length
public typealias IdentityKey = Data

public enum AccountServiceClientError: Error {
    case captchaRequired
}

/// based on libsignal-service-java's AccountManager class
@objc
public class AccountServiceClient: NSObject {

    // MARK: - Public

    public func deprecated_requestPreauthChallenge(e164: String, pushToken: String, isVoipToken: Bool) -> Promise<Void> {
        serviceClient.deprecated_requestPreauthChallenge(e164: e164, pushToken: pushToken, isVoipToken: isVoipToken)
    }

    public func deprecated_requestVerificationCode(e164: String, preauthChallenge: String?, captchaToken: String?, transport: TSVerificationTransport) -> Promise<Void> {
        serviceClient.deprecated_requestVerificationCode(e164: e164,
                                              preauthChallenge: preauthChallenge,
                                              captchaToken: captchaToken,
                                              transport: transport).recover { error -> Void in
            if error.httpStatusCode == 402 {
                throw AccountServiceClientError.captchaRequired
            }
            throw error
        }
    }

    public func getPreKeysCount(for identity: OWSIdentity) -> Promise<Int> {
        return serviceClient.getAvailablePreKeys(for: identity)
    }

    public func setPreKeys(
        for identity: OWSIdentity,
        identityKey: IdentityKey,
        signedPreKeyRecord: SignedPreKeyRecord?,
        preKeyRecords: [PreKeyRecord]?,
        auth: ChatServiceAuth
    ) -> Promise<Void> {
        return serviceClient.registerPreKeys(
            for: identity,
            identityKey: identityKey,
            signedPreKeyRecord: signedPreKeyRecord,
            preKeyRecords: preKeyRecords,
            auth: auth
        )
    }

    public func setSignedPreKey(_ signedPreKey: SignedPreKeyRecord, for identity: OWSIdentity) -> Promise<Void> {
        return serviceClient.setCurrentSignedPreKey(signedPreKey, for: identity)
    }

    public func updatePrimaryDeviceAccountAttributes() -> Promise<Void> {
        return serviceClient.updatePrimaryDeviceAccountAttributes()
    }

    public func getAccountWhoAmI() -> Promise<WhoAmIRequestFactory.Responses.WhoAmI> {
        return serviceClient.getAccountWhoAmI()
    }

    public func verifySecondaryDevice(verificationCode: String,
                                      phoneNumber: String,
                                      authKey: String,
                                      encryptedDeviceName: Data) -> Promise<VerifySecondaryDeviceResponse> {
        return serviceClient.verifySecondaryDevice(verificationCode: verificationCode, phoneNumber: phoneNumber, authKey: authKey, encryptedDeviceName: encryptedDeviceName)
    }
}
