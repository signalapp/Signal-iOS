//
// Copyright 2018 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

@objc
public enum SignalServiceError: Int, Error {
    case obsoleteLinkedDevice
}

// MARK: -

public protocol SignalServiceClient {
    func deprecated_requestPreauthChallenge(e164: String, pushToken: String, isVoipToken: Bool) -> Promise<Void>
    func deprecated_requestVerificationCode(e164: String, preauthChallenge: String?, captchaToken: String?, transport: TSVerificationTransport) -> Promise<Void>
    func verifySecondaryDevice(verificationCode: String, phoneNumber: String, authKey: String, encryptedDeviceName: Data) -> Promise<VerifySecondaryDeviceResponse>
    func getAvailablePreKeys(for identity: OWSIdentity) -> Promise<Int>
    /// If a username and password are both provided, those are used for the request's
    /// Authentication header. Otherwise, the default header is used (whatever's on
    /// TSAccountManager).
    func registerPreKeys(
        for identity: OWSIdentity,
        identityKey: IdentityKey,
        signedPreKeyRecord: SignedPreKeyRecord,
        preKeyRecords: [PreKeyRecord],
        auth: ChatServiceAuth
    ) -> Promise<Void>
    func setCurrentSignedPreKey(_ signedPreKey: SignedPreKeyRecord, for identity: OWSIdentity) -> Promise<Void>
    func requestUDSenderCertificate(uuidOnly: Bool) -> Promise<Data>
    func updatePrimaryDeviceAccountAttributes() -> Promise<Void>
    func getAccountWhoAmI() -> Promise<WhoAmIRequestFactory.Responses.WhoAmI>
    func requestStorageAuth() -> Promise<(username: String, password: String)>
    func getRemoteConfig() -> Promise<[String: RemoteConfigItem]>

    // MARK: - Secondary Devices

    func updateSecondaryDeviceCapabilities() -> Promise<Void>
}

// MARK: -

public enum RemoteConfigItem {
    case isEnabled(isEnabled: Bool)
    case value(value: AnyObject)
}

// MARK: -

/// Based on libsignal-service-java's PushServiceSocket class
@objc
public class SignalServiceRestClient: NSObject, SignalServiceClient {

    public static let shared = SignalServiceRestClient()

    // MARK: - Public

    public func deprecated_requestPreauthChallenge(e164: String, pushToken: String, isVoipToken: Bool) -> Promise<Void> {
        let request = OWSRequestFactory.deprecated_requestPreauthChallenge(
            e164: e164,
            pushToken: pushToken,
            isVoipToken: isVoipToken
        )
        return networkManager.makePromise(request: request).asVoid()
    }

    public func deprecated_requestVerificationCode(e164: String, preauthChallenge: String?, captchaToken: String?, transport: TSVerificationTransport) -> Promise<Void> {
        let request = OWSRequestFactory.requestVerificationCodeRequest(e164: e164,
                                                                       preauthChallenge: preauthChallenge,
                                                                       captchaToken: captchaToken,
                                                                       transport: transport)
        return networkManager.makePromise(request: request).asVoid()
    }

    public func getAvailablePreKeys(for identity: OWSIdentity) -> Promise<Int> {
        Logger.debug("")

        let request = OWSRequestFactory.availablePreKeysCountRequest(for: identity)
        return firstly {
            networkManager.makePromise(request: request)
        }.map(on: DispatchQueue.global()) { response in
            Logger.debug("got response")
            guard let json = response.responseBodyJson else {
                throw OWSAssertionError("Missing or invalid JSON.")
            }
            guard let params = ParamParser(responseObject: json) else {
                throw OWSAssertionError("Missing or invalid response.")
            }

            let count: Int = try params.required(key: "count")

            return count
        }
    }

    public func registerPreKeys(
        for identity: OWSIdentity,
        identityKey: IdentityKey,
        signedPreKeyRecord: SignedPreKeyRecord,
        preKeyRecords: [PreKeyRecord],
        auth: ChatServiceAuth
    ) -> Promise<Void> {
        Logger.debug("")

        let request = OWSRequestFactory.registerPrekeysRequest(
            identity: identity,
            identityKey: identityKey,
            signedPreKeyRecord: signedPreKeyRecord,
            prekeyRecords: preKeyRecords,
            auth: auth
        )
        return networkManager.makePromise(request: request).asVoid()
    }

    public func setCurrentSignedPreKey(_ signedPreKey: SignedPreKeyRecord, for identity: OWSIdentity) -> Promise<Void> {
        Logger.debug("")

        let request = OWSRequestFactory.registerSignedPrekeyRequest(for: identity, signedPreKey: signedPreKey)
        return networkManager.makePromise(request: request).asVoid()
    }

    public func requestUDSenderCertificate(uuidOnly: Bool) -> Promise<Data> {
        let request = OWSRequestFactory.udSenderCertificateRequest(uuidOnly: uuidOnly)
        return firstly {
            self.networkManager.makePromise(request: request)
        }.map(on: DispatchQueue.global()) { response in
            guard let json = response.responseBodyJson else {
                throw OWSUDError.invalidData(description: "Missing or invalid JSON")
            }
            guard let parser = ParamParser(responseObject: json) else {
                throw OWSUDError.invalidData(description: "Invalid sender certificate response")
            }

            return try parser.requiredBase64EncodedData(key: "certificate")
        }
    }

    public func updatePrimaryDeviceAccountAttributes() -> Promise<Void> {
        guard tsAccountManager.isPrimaryDevice else {
            return Promise(error: OWSAssertionError("only primary device should update account attributes"))
        }

        let request = OWSRequestFactory.updatePrimaryDeviceAttributesRequest()
        return networkManager.makePromise(request: request).asVoid()
    }

    public func getAccountWhoAmI() -> Promise<WhoAmIRequestFactory.Responses.WhoAmI> {
        let request = WhoAmIRequestFactory.whoAmIRequest()

        return firstly {
            networkManager.makePromise(request: request)
        }.map(on: DispatchQueue.global()) { response in
            guard let json = response.responseBodyData else {
                throw OWSAssertionError("Missing or invalid JSON.")
            }
            return try JSONDecoder().decode(WhoAmIRequestFactory.Responses.WhoAmI.self, from: json)
        }
    }

    public func requestStorageAuth() -> Promise<(username: String, password: String)> {
        let request = OWSRequestFactory.storageAuthRequest()
        return firstly {
            networkManager.makePromise(request: request)
        }.map(on: DispatchQueue.global()) { response in
            guard let json = response.responseBodyJson else {
                throw OWSAssertionError("Missing or invalid JSON.")
            }
            guard let parser = ParamParser(responseObject: json) else {
                throw OWSAssertionError("Missing or invalid response.")
            }

            let username: String = try parser.required(key: "username")
            let password: String = try parser.required(key: "password")

            return (username: username, password: password)
        }
    }

    public func verifySecondaryDevice(verificationCode: String,
                                      phoneNumber: String,
                                      authKey: String,
                                      encryptedDeviceName: Data) -> Promise<VerifySecondaryDeviceResponse> {

        let request = OWSRequestFactory.verifySecondaryDeviceRequest(verificationCode: verificationCode,
                                                                     phoneNumber: phoneNumber,
                                                                     authKey: authKey,
                                                                     encryptedDeviceName: encryptedDeviceName)

        return firstly {
            networkManager.makePromise(request: request)
        }.map(on: DispatchQueue.global()) { response in
            guard let json = response.responseBodyJson else {
                throw OWSAssertionError("Missing or invalid JSON.")
            }
            guard let parser = ParamParser(responseObject: json) else {
                throw OWSAssertionError("Missing or invalid response.")
            }

            let deviceId: UInt32 = try parser.required(key: "deviceId")
            let pni: UUID = try parser.required(key: "pni")

            return VerifySecondaryDeviceResponse(pni: pni, deviceId: deviceId)
        }.recover { error -> Promise<VerifySecondaryDeviceResponse> in
            if let statusCode = error.httpStatusCode, statusCode == 409 {
                // Convert 409 errors into .obsoleteLinkedDevice so that they can be
                // explicitly handled.
                throw SignalServiceError.obsoleteLinkedDevice
            } else {
                throw DeviceLimitExceededError(error) ?? error
            }
        }
    }

    // yields a map of ["feature_name": isEnabled]
    public func getRemoteConfig() -> Promise<[String: RemoteConfigItem]> {
        let request = OWSRequestFactory.getRemoteConfigRequest()

        return firstly {
            networkManager.makePromise(request: request)
        }.map(on: DispatchQueue.global()) { response in
            guard let json = response.responseBodyJson else {
                throw OWSAssertionError("Missing or invalid JSON.")
            }
            guard let parser = ParamParser(responseObject: json) else {
                throw OWSAssertionError("Missing or invalid response.")
            }

            let config: [[String: Any]] = try parser.required(key: "config")

            return try config.reduce([:]) { accum, item in
                var accum = accum
                guard let itemParser = ParamParser(responseObject: item) else {
                    throw OWSAssertionError("Missing or invalid remote config item.")
                }

                let name: String = try itemParser.required(key: "name")
                let isEnabled: Bool = try itemParser.required(key: "enabled")

                if let value: AnyObject = try itemParser.optional(key: "value") {
                    accum[name] = RemoteConfigItem.value(value: value)
                } else {
                    accum[name] = RemoteConfigItem.isEnabled(isEnabled: isEnabled)
                }

                return accum
            }
        }
    }

    // MARK: - Secondary Devices

    public func updateSecondaryDeviceCapabilities() -> Promise<Void> {
        let request = OWSRequestFactory.updateSecondaryDeviceCapabilitiesRequest()
        return self.networkManager.makePromise(request: request).asVoid()
    }
}

// MARK: -

public struct VerifySecondaryDeviceResponse {
    public let pni: UUID
    public let deviceId: UInt32
}
