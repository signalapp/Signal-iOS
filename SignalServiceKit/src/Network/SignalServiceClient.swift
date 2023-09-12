//
// Copyright 2018 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import LibSignalClient

@objc
public enum SignalServiceError: Int, Error {
    case obsoleteLinkedDevice
}

// MARK: -

public protocol SignalServiceClient {
    func verifySecondaryDevice(
        verificationCode: String,
        phoneNumber: String,
        authKey: String,
        encryptedDeviceName: Data,
        apnRegistrationId: RegistrationRequestFactory.ApnRegistrationId?,
        prekeyBundles: RegistrationPreKeyUploadBundles
    ) -> Promise<VerifySecondaryDeviceResponse>
    func getAvailablePreKeys(for identity: OWSIdentity) -> Promise<(ecCount: Int, pqCount: Int)>
    /// If a username and password are both provided, those are used for the request's
    /// Authentication header. Otherwise, the default header is used (whatever's on
    /// TSAccountManager).
    func registerPreKeys(
        for identity: OWSIdentity,
        identityKey: Data,
        signedPreKeyRecord: SignalServiceKit.SignedPreKeyRecord?,
        preKeyRecords: [SignalServiceKit.PreKeyRecord]?,
        pqLastResortPreKeyRecord: KyberPreKeyRecord?,
        pqPreKeyRecords: [KyberPreKeyRecord]?,
        auth: ChatServiceAuth
    ) -> Promise<Void>
    func setCurrentSignedPreKey(_ signedPreKey: SignalServiceKit.SignedPreKeyRecord, for identity: OWSIdentity) -> Promise<Void>
    func requestUDSenderCertificate(uuidOnly: Bool) -> Promise<Data>
    func updatePrimaryDeviceAccountAttributes() -> Promise<Void>
    func getAccountWhoAmI() -> Promise<WhoAmIRequestFactory.Responses.WhoAmI>
    func requestStorageAuth(chatServiceAuth: ChatServiceAuth) -> Promise<(username: String, password: String)>
    func getRemoteConfig(auth: ChatServiceAuth) -> Promise<RemoteConfigResponse>

    // MARK: - Secondary Devices

    func updateSecondaryDeviceCapabilities(hasBackedUpMasterKey: Bool) -> Promise<Void>
}

// MARK: -

public enum RemoteConfigItem {
    case isEnabled(isEnabled: Bool)
    case value(value: AnyObject)
}

public struct RemoteConfigResponse {
    public let items: [String: RemoteConfigItem]
    public let serverEpochTimeSeconds: UInt64?
}

// MARK: -

/// Based on libsignal-service-java's PushServiceSocket class
@objc
public class SignalServiceRestClient: NSObject, SignalServiceClient, Dependencies {

    public static let shared = SignalServiceRestClient()

    // MARK: - Public

    public func getAvailablePreKeys(for identity: OWSIdentity) -> Promise<(ecCount: Int, pqCount: Int)> {
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

            let ecCount: Int = try params.required(key: "count")
            let pqCount: Int = try params.optional(key: "pqCount") ?? 0

            return (ecCount, pqCount)
        }
    }

    public func registerPreKeys(
        for identity: OWSIdentity,
        identityKey: Data,
        signedPreKeyRecord: SignalServiceKit.SignedPreKeyRecord?,
        preKeyRecords: [SignalServiceKit.PreKeyRecord]?,
        pqLastResortPreKeyRecord: KyberPreKeyRecord?,
        pqPreKeyRecords: [KyberPreKeyRecord]?,
        auth: ChatServiceAuth
    ) -> Promise<Void> {
        Logger.debug("")

        let request = OWSRequestFactory.registerPrekeysRequest(
            identity: identity,
            identityKey: identityKey,
            signedPreKeyRecord: signedPreKeyRecord,
            prekeyRecords: preKeyRecords,
            pqLastResortPreKeyRecord: pqLastResortPreKeyRecord,
            pqPreKeyRecords: pqPreKeyRecords,
            auth: auth
        )
        return networkManager.makePromise(request: request).asVoid()
    }

    public func setCurrentSignedPreKey(_ signedPreKey: SignalServiceKit.SignedPreKeyRecord, for identity: OWSIdentity) -> Promise<Void> {
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

        let attributes = self.databaseStorage.write { transaction in
            return AccountAttributes.generateForPrimaryDevice(
                fromDependencies: self,
                svr: DependenciesBridge.shared.svr,
                transaction: transaction
            )
        }
        let request = AccountAttributesRequestFactory.updatePrimaryDeviceAttributesRequest(attributes)
        return networkManager.makePromise(request: request).asVoid()
    }

    public func getAccountWhoAmI() -> Promise<WhoAmIRequestFactory.Responses.WhoAmI> {
        let request = WhoAmIRequestFactory.whoAmIRequest(auth: .implicit())

        return firstly {
            networkManager.makePromise(request: request)
        }.map(on: DispatchQueue.global()) { response in
            guard let json = response.responseBodyData else {
                throw OWSAssertionError("Missing or invalid JSON.")
            }
            return try JSONDecoder().decode(WhoAmIRequestFactory.Responses.WhoAmI.self, from: json)
        }
    }

    public func requestStorageAuth(chatServiceAuth: ChatServiceAuth) -> Promise<(username: String, password: String)> {
        let request = OWSRequestFactory.storageAuthRequest()
        request.setAuth(chatServiceAuth)
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

    public func verifySecondaryDevice(
        verificationCode: String,
        phoneNumber: String,
        authKey: String,
        encryptedDeviceName: Data,
        apnRegistrationId: RegistrationRequestFactory.ApnRegistrationId?,
        prekeyBundles: RegistrationPreKeyUploadBundles
    ) -> Promise<VerifySecondaryDeviceResponse> {

        let accountAttributes = self.databaseStorage.write { transaction in
            return AccountAttributes.generateForSecondaryDevice(
                fromDependencies: self,
                svr: DependenciesBridge.shared.svr,
                encryptedDeviceName: encryptedDeviceName,
                transaction: transaction
            )
        }

        let request = OWSRequestFactory.verifySecondaryDeviceRequest(
            verificationCode: verificationCode,
            phoneNumber: phoneNumber,
            authPassword: authKey,
            attributes: accountAttributes,
            apnRegistrationId: apnRegistrationId,
            prekeyBundles: prekeyBundles
        )

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
            let pni = Pni(fromUUID: try parser.required(key: "pni"))

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
    public func getRemoteConfig(auth: ChatServiceAuth) -> Promise<RemoteConfigResponse> {
        let request = OWSRequestFactory.getRemoteConfigRequest()
        request.setAuth(auth)

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
            let serverEpochTimeSeconds: UInt64? = try parser.optional(key: "serverEpochTime")

            let items: [String: RemoteConfigItem] = try config.reduce([:]) { accum, item in
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

            return .init(items: items, serverEpochTimeSeconds: serverEpochTimeSeconds)
        }
    }

    // MARK: - Secondary Devices

    public func updateSecondaryDeviceCapabilities(hasBackedUpMasterKey: Bool) -> Promise<Void> {
        let request = OWSRequestFactory.updateSecondaryDeviceCapabilitiesRequest(withHasBackedUpMasterKey: hasBackedUpMasterKey)
        return self.networkManager.makePromise(request: request).asVoid()
    }
}

// MARK: -

public struct VerifySecondaryDeviceResponse {
    public let pni: Pni
    public let deviceId: UInt32
}
