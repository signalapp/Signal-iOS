//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

import Foundation
import PromiseKit
import SignalMetadataKit

public typealias RecipientIdentifier = String

public protocol SignalServiceClient {
    func getAvailablePreKeys() -> Promise<Int>
    func registerPreKeys(identityKey: IdentityKey, signedPreKeyRecord: SignedPreKeyRecord, preKeyRecords: [PreKeyRecord]) -> Promise<Void>
    func setCurrentSignedPreKey(_ signedPreKey: SignedPreKeyRecord) -> Promise<Void>
    func requestUDSenderCertificate() -> Promise<Data>
    func updateAcountAttributes() -> Promise<Void>
    func retrieveProfile(recipientId: RecipientIdentifier, unidentifiedAccess: SSKUnidentifiedAccess?) -> Promise<SignalServiceProfile>
}

/// Based on libsignal-service-java's PushServiceSocket class
@objc
public class SignalServiceRestClient: NSObject, SignalServiceClient {

    var networkManager: TSNetworkManager {
        return TSNetworkManager.shared()
    }

    func unexpectedServerResponseError() -> Error {
        return OWSErrorMakeUnableToProcessServerResponseError()
    }

    public func getAvailablePreKeys() -> Promise<Int> {
        Logger.debug("")

        let request = OWSRequestFactory.availablePreKeysCountRequest()
        return networkManager.makePromise(request: request).then { (_, responseObject) -> Int in
            Logger.debug("got response")
            guard let params = ParamParser(responseObject: responseObject) else {
                throw self.unexpectedServerResponseError()
            }

            let count: Int = try! params.required(key: "count")

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
        return self.networkManager.makePromise(request: request)
            .then(execute: { (_, responseObject) -> Data in
                let certificateData = try self.parseUDSenderCertificateResponse(responseObject: responseObject)

                return certificateData
            })
    }

    private func parseUDSenderCertificateResponse(responseObject: Any?) throws -> Data {
        guard let parser = ParamParser(responseObject: responseObject) else {
            throw OWSUDError.invalidData(description: "Invalid sender certificate response")
        }

        return try parser.requiredBase64EncodedData(key: "certificate")
    }

    public func updateAcountAttributes() -> Promise<Void> {
        let request = OWSRequestFactory.updateAttributesRequest()
        let promise: Promise<Void> = networkManager.makePromise(request: request)
            .then(execute: { (_, _) in
                Logger.info("updated account attributes on server")
            }).catch(execute: { (error) in
                Logger.error("failed to update account attributes on server with error: \(error)")
            })
        return promise
    }

    public func retrieveProfile(recipientId: RecipientIdentifier, unidentifiedAccess: SSKUnidentifiedAccess?) -> Promise<SignalServiceProfile> {
        let request = OWSRequestFactory.getProfileRequest(recipientId: recipientId, unidentifiedAccess: unidentifiedAccess)
        return networkManager.makePromise(request: request).then { (task: URLSessionDataTask, responseObject: Any?) in
            return try SignalServiceProfile(recipientId: recipientId, responseObject: responseObject)
        }
    }
}
