//
//  Copyright (c) 2020 Open Whisper Systems. All rights reserved.
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
    func verifySecondaryDevice(deviceName: String, verificationCode: String, phoneNumber: String, authKey: String) -> Promise<UInt32>
    func getAvailablePreKeys() -> Promise<Int>
    func registerPreKeys(identityKey: IdentityKey, signedPreKeyRecord: SignedPreKeyRecord, preKeyRecords: [PreKeyRecord]) -> Promise<Void>
    func setCurrentSignedPreKey(_ signedPreKey: SignedPreKeyRecord) -> Promise<Void>
    func requestUDSenderCertificate() -> Promise<Data>
    func updateAccountAttributes() -> Promise<Void>
    func getAccountUuid() -> Promise<UUID>
    func requestStorageAuth() -> Promise<(username: String, password: String)>
    func getRemoteConfig() -> Promise<[String: Bool]>
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

    public func requestStorageAuth() -> Promise<(username: String, password: String)> {
        let request = OWSRequestFactory.storageAuthRequest()
        return networkManager.makePromise(request: request).map { _, responseObject in
            guard let parser = ParamParser(responseObject: responseObject) else {
                throw OWSErrorMakeUnableToProcessServerResponseError()
            }

            let username: String = try parser.required(key: "username")
            let password: String = try parser.required(key: "password")

            return (username: username, password: password)
        }
    }

    public func verifySecondaryDevice(deviceName: String,
                                      verificationCode: String,
                                      phoneNumber: String,
                                      authKey: String) -> Promise<UInt32> {

        let request = OWSRequestFactory.verifySecondaryDeviceRequest(verificationCode: verificationCode,
                                                                     phoneNumber: phoneNumber,
                                                                     authKey: authKey,
                                                                     deviceName: deviceName)

        return networkManager.makePromise(request: request).map { _, responseObject in
            guard let parser = ParamParser(responseObject: responseObject) else {
                throw OWSErrorMakeUnableToProcessServerResponseError()
            }

            let deviceId: UInt32 = try parser.required(key: "deviceId")
            return deviceId
        }
    }

    // yields a map of ["feature_name": isEnabled]
    public func getRemoteConfig() -> Promise<[String: Bool]> {
        let request = OWSRequestFactory.getRemoteConfigRequest()

        return networkManager.makePromise(request: request).map { _, responseObject in
            guard let parser = ParamParser(responseObject: responseObject) else {
                throw OWSErrorMakeUnableToProcessServerResponseError()
            }

            let config: [[String: Any]] = try parser.required(key: "config")

            return try config.reduce([:]) { accum, item in
                var accum = accum
                guard let itemParser = ParamParser(responseObject: item) else {
                    throw OWSErrorMakeUnableToProcessServerResponseError()
                }

                let name: String = try itemParser.required(key: "name")
                let isEnabled: Bool = try itemParser.required(key: "enabled")
                accum[name] = isEnabled

                return accum
            }
        }
    }

    // MARK: - Helpers

    private func unexpectedServerResponseError() -> Error {
        return OWSErrorMakeUnableToProcessServerResponseError()
    }
}
