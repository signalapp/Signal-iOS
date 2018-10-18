//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

import Foundation
import PromiseKit
import SignalMetadataKit

public typealias RecipientIdentifier = String

@objc
public protocol SignalServiceClientObjC {
    @objc func updateAccountAttributesObjC() -> AnyPromise
}

public protocol SignalServiceClient: SignalServiceClientObjC {
    func getAvailablePreKeys() -> Promise<Int>
    func registerPreKeys(identityKey: IdentityKey, signedPreKeyRecord: SignedPreKeyRecord, preKeyRecords: [PreKeyRecord]) -> Promise<Void>
    func setCurrentSignedPreKey(_ signedPreKey: SignedPreKeyRecord) -> Promise<Void>
    func requestUDSenderCertificate() -> Promise<Data>
    func updateAccountAttributes() -> Promise<Void>
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

    public func retrieveProfile(recipientId: RecipientIdentifier, unidentifiedAccess: SSKUnidentifiedAccess?) -> Promise<SignalServiceProfile> {
        let (promise, resolver) = Promise<(task: URLSessionDataTask, responseObject: Any?)>.pending()

        let request = OWSRequestFactory.getProfileRequest(recipientId: recipientId, unidentifiedAccess: unidentifiedAccess)
        networkManager.makeRequest(request,
                         success: { task, responseObject in
                            resolver.fulfill((task: task, responseObject: responseObject))
        },
                         failure: { task, error in
                            let statusCode = task.statusCode()
                            if unidentifiedAccess != nil && (statusCode == 401 || statusCode == 403) {
                                Logger.verbose("REST profile request failing over to non-UD auth.")
                                let nonUDRequest = OWSRequestFactory.getProfileRequest(recipientId: recipientId, unidentifiedAccess: nil)
                                self.networkManager.makeRequest(nonUDRequest,
                                                           success: { task, responseObject in
                                                            resolver.fulfill((task: task, responseObject: responseObject))
                                },
                                                           failure: { task, error in
                                                            let nmError = NetworkManagerError.taskError(task: task, underlyingError: error)
                                                            let nsError: NSError = nmError as NSError
                                                            nsError.isRetryable = (error as NSError).isRetryable
                                                            resolver.reject(nsError)
                                })
                                return
                            }
                            Logger.info("REST profile request failed.")
                            let nmError = NetworkManagerError.taskError(task: task, underlyingError: error)
                            let nsError: NSError = nmError as NSError
                            nsError.isRetryable = (error as NSError).isRetryable
                            resolver.reject(nsError)
        })
        return promise.map { _, responseObject in
            Logger.info("REST profile request succeeded.")
            return try SignalServiceProfile(recipientId: recipientId, responseObject: responseObject)
        }
    }
}
