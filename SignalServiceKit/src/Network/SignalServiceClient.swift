//
//  Copyright (c) 2019 Open Whisper Systems. All rights reserved.
//

import Foundation
import PromiseKit
import SignalMetadataKit

@objc
public protocol SignalServiceClientObjC {
    @objc func updateAccountAttributesObjC() -> AnyPromise
}

public protocol SignalServiceClient: SignalServiceClientObjC {
    func requestPreauthChallenge(recipientId: String, pushToken: String) -> Promise<Void>
    func requestVerificationCode(recipientId: String, preauthChallenge: String?, captchaToken: String?, transport: TSVerificationTransport) -> Promise<Void>
    func getAvailablePreKeys() -> Promise<Int>
    func registerPreKeys(identityKey: IdentityKey, signedPreKeyRecord: SignedPreKeyRecord, preKeyRecords: [PreKeyRecord]) -> Promise<Void>
    func setCurrentSignedPreKey(_ signedPreKey: SignedPreKeyRecord) -> Promise<Void>
    func requestUDSenderCertificate() -> Promise<Data>
    func updateAccountAttributes() -> Promise<Void>
    func getAccountUuid() -> Promise<UUID>
}

/// Based on libsignal-service-java's PushServiceSocket class
@objc
public class SignalServiceRestClient: NSObject, SignalServiceClient {

    // MARK: - Dependencies

    var networkManager: TSNetworkManager {
        return TSNetworkManager.shared()
    }

    private var udManager: OWSUDManager {
        return SSKEnvironment.shared.udManager
    }

    // MARK: - Public

    public func requestPreauthChallenge(recipientId: String, pushToken: String) -> Promise<Void> {
        let request = OWSRequestFactory.requestPreauthChallengeRequest(recipientId: recipientId,
                                                                       pushToken: pushToken)
        return networkManager.makePromise(request: request).asVoid()
    }

    public func requestVerificationCode(recipientId: String, preauthChallenge: String?, captchaToken: String?, transport: TSVerificationTransport) -> Promise<Void> {
        let request = OWSRequestFactory.requestVerificationCodeRequest(withPhoneNumber: recipientId,
                                                                       preauthChallenge: preauthChallenge,
                                                                       captchaToken: captchaToken,
                                                                       transport: transport)
        return networkManager.makePromise(request: request).asVoid()
    }

    public func getAvailablePreKeys() -> Promise<Int> {
        Logger.debug("")

        let request = OWSRequestFactory.availablePreKeysCountRequest()
        return firstly {
            networkManager.makePromise(request: request)
        }.map { _, responseObject in
            Logger.debug("got response")
            guard let params = ParamParser(responseObject: responseObject) else {
                throw self.unexpectedServerResponseError()
            }

            let count: Int = try params.required(key: "count")

            return count
        }
    }

    public func registerPreKeys(identityKey: IdentityKey, signedPreKeyRecord: SignedPreKeyRecord, preKeyRecords: [PreKeyRecord]) -> Promise<Void> {
        Logger.debug("")

        let request = OWSRequestFactory.registerPrekeysRequest(withPrekeyArray: preKeyRecords, identityKey: identityKey, signedPreKey: signedPreKeyRecord)
        return networkManager.makePromise(request: request).asVoid()
    }

    public func setCurrentSignedPreKey(_ signedPreKey: SignedPreKeyRecord) -> Promise<Void> {
        Logger.debug("")

        let request = OWSRequestFactory.registerSignedPrekeyRequest(with: signedPreKey)
        return networkManager.makePromise(request: request).asVoid()
    }

    public func requestUDSenderCertificate() -> Promise<Data> {
        let request = OWSRequestFactory.udSenderCertificateRequest()
        return firstly {
            self.networkManager.makePromise(request: request)
        }.map { _, responseObject in
            guard let parser = ParamParser(responseObject: responseObject) else {
                throw OWSUDError.invalidData(description: "Invalid sender certificate response")
            }

            return try parser.requiredBase64EncodedData(key: "certificate")
        }
    }

    @objc
    public func updateAccountAttributesObjC() -> AnyPromise {
        return AnyPromise(updateAccountAttributes())
    }

    public func updateAccountAttributes() -> Promise<Void> {
        let request = OWSRequestFactory.updateAttributesRequest()
        return networkManager.makePromise(request: request).asVoid()
    }

    public func getAccountUuid() -> Promise<UUID> {
        let request = OWSRequestFactory.accountWhoAmIRequest()

        return networkManager.makePromise(request: request).map { _, responseObject in
            guard let parser = ParamParser(responseObject: responseObject) else {
                throw OWSErrorMakeUnableToProcessServerResponseError()
            }

            let uuidString: String = try parser.required(key: "uuid")

            guard let uuid = UUID(uuidString: uuidString) else {
                throw OWSErrorMakeUnableToProcessServerResponseError()
            }

            return uuid
        }
    }

    // MARK: - Helpers

    private func unexpectedServerResponseError() -> Error {
        return OWSErrorMakeUnableToProcessServerResponseError()
    }
}
