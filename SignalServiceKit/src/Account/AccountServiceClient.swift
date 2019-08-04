//
//  Copyright (c) 2019 Open Whisper Systems. All rights reserved.
//

import Foundation
import PromiseKit

// TODO define actual type, and validate length
public typealias IdentityKey = Data

public enum AccountServiceClientError: Error {
    case captchaRequired
}

/// based on libsignal-service-java's AccountManager class
@objc(SSKAccountServiceClient)
public class AccountServiceClient: NSObject {

    public static var shared = AccountServiceClient()

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
            switch error {
            case let networkingError as NetworkManagerError:
                if networkingError.statusCode == 402 {
                    throw AccountServiceClientError.captchaRequired
                }
            default:
                break
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
}
