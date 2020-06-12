//
//  Copyright (c) 2020 Open Whisper Systems. All rights reserved.
//

import Foundation
import PromiseKit
import SignalMetadataKit

@objc
public class MessageSending: NSObject {

    // MARK: - Dependencies

    private class var databaseStorage: SDSDatabaseStorage {
        return SDSDatabaseStorage.shared
    }

    private class var sessionStore: SSKSessionStore {
        return SSKEnvironment.shared.sessionStore
    }

    private class var preKeyStore: SSKPreKeyStore {
        return SSKEnvironment.shared.preKeyStore
    }

    private class var signedPreKeyStore: SSKSignedPreKeyStore {
        return SSKEnvironment.shared.signedPreKeyStore
    }

    private class var identityManager: OWSIdentityManager {
        return OWSIdentityManager.shared()
    }

    private class var tsAccountManager: TSAccountManager {
        return .sharedInstance()
    }

    // MARK: -

    @available(*, unavailable, message:"Do not instantiate this class.")
    private override init() {
    }

    // MARK: -

    @objc
    public class func ensureSessionsforMessageSendsObjc(_ messageSends: [OWSMessageSend],
                                                        ignoreErrors: Bool) -> AnyPromise {
        AnyPromise(ensureSessions(forMessageSends: messageSends,
                                  ignoreErrors: ignoreErrors))
    }

    private struct SessionStates {
        let deviceAlreadyHasSession = AtomicUInt(0)
        let deviceDeviceSessionCreated = AtomicUInt(0)
        let failure = AtomicUInt(0)
    }

    private class func ensureSessions(forMessageSends messageSends: [OWSMessageSend],
                                      ignoreErrors: Bool) -> Promise<Void> {
        let promise = firstly(on: .global()) { () -> Promise<Void> in
            var promises = [Promise<Void>]()
            for messageSend in messageSends {
                promises += self.ensureSessions(forMessageSend: messageSend,
                                                ignoreErrors: ignoreErrors)
            }
            if !promises.isEmpty {
                Logger.info("Prekey fetches: \(promises.count)")
            }
            return when(fulfilled: promises).asVoid()
        }
        if !ignoreErrors {
            promise.catch(on: .global()) { _ in
                owsFailDebug("The promises should never fail.")
            }
        }
        return promise
    }

    private class func ensureSessions(forMessageSend messageSend: OWSMessageSend,
                                      ignoreErrors: Bool) -> [Promise<Void>] {
        let recipient: SignalRecipient = messageSend.recipient
        var deviceIds = messageSend.deviceIds.map { $0.uint32Value }
        if messageSend.isLocalAddress {
            let localDeviceId = tsAccountManager.storedDeviceId()
            deviceIds = deviceIds.filter { $0 != localDeviceId }
        }

        guard let accountId = recipient.accountId else {
            owsFailDebug("Missing account.")
            return []
        }
        let deviceIdsWithoutSessions = databaseStorage.read { transaction in
            deviceIds.filter { deviceId in
                !self.sessionStore.containsSession(forAccountId: accountId,
                                                   deviceId: Int32(deviceId),
                                                   transaction: transaction)
            }
        }
        guard !deviceIdsWithoutSessions.isEmpty else {
            return []
        }

        var promises = [Promise<Void>]()
        for deviceId in deviceIds {

            Logger.verbose("Fetching prekey for: \(messageSend.recipient.address), \(deviceId)")

            let promise: Promise<Void> = firstly(on: .global()) { () -> Promise<PreKeyBundle> in
                let (promise, resolver) = Promise<PreKeyBundle>.pending()
                self.makePrekeyRequest(messageSend: messageSend,
                                       deviceId: NSNumber(value: deviceId),
                                       success: { preKeyBundle in
                                        guard let preKeyBundle = preKeyBundle else {
                                            return resolver.reject(OWSAssertionError("Missing preKeyBundle."))
                                        }
                                        resolver.fulfill(preKeyBundle)
                },
                                       failure: { error in
                                        resolver.reject(error)

                })
                return promise
            }.done(on: .global()) { (preKeyBundle: PreKeyBundle) -> Void in
                try self.databaseStorage.write { transaction in
                    try self.createSession(forPreKeyBundle: preKeyBundle,
                                           accountId: accountId,
                                           deviceId: NSNumber(value: deviceId),
                                           transaction: transaction)
                }
            }.recover(on: .global()) { (error: Error) in
                if let statusCode = error.httpStatusCode,
                    statusCode == 404 {
                    self.databaseStorage.write { transaction in
                        recipient.updateRegisteredRecipientWithDevices(toAdd: nil,
                                                                       devicesToRemove: [NSNumber(value: deviceId)],
                                                                       transaction: transaction)
                    }
                    messageSend.removeDeviceId(NSNumber(value: deviceId))
                }
                if ignoreErrors {
                    Logger.warn("Ignoring error: \(error)")
                } else {
                    throw error
                }
            }
            promises.append(promise)
        }
        return promises
    }

    @objc
    public class func makePrekeyRequest(messageSend: OWSMessageSend,
                                        deviceId: NSNumber,
                                        success: @escaping (PreKeyBundle?) -> Void,
                                        failure: @escaping (Error) -> Void) {
        assert(!Thread.isMainThread)

        let recipientAddress = messageSend.recipient.address
        assert(recipientAddress.isValid)

        let requestMaker = RequestMaker(label: "Prekey Fetch",
                                        requestFactoryBlock: { (udAccessKeyForRequest: SMKUDAccessKey?) -> TSRequest? in
                                            OWSRequestFactory.recipientPreKeyRequest(with: recipientAddress,
                                                                                     deviceId: deviceId.stringValue,
                                                                                     udAccessKey: udAccessKeyForRequest)
        }, udAuthFailureBlock: {
            // Note the UD auth failure so subsequent retries
            // to this recipient also use basic auth.
            messageSend.setHasUDAuthFailed()
        }, websocketFailureBlock: {
            // Note the websocket failure so subsequent retries
            // to this recipient also use REST.
            messageSend.hasWebsocketSendFailed = true
        }, address: recipientAddress,
           udAccess: messageSend.udSendingAccess?.udAccess,
           canFailoverUDAuth: true)

        firstly(on: .global()) { () -> Promise<RequestMakerResult> in
            return requestMaker.makeRequest()
        }.done(on: .global()) { (result: RequestMakerResult) in
            guard let responseObject = result.responseObject as? [AnyHashable: Any] else {
                throw OWSAssertionError("Prekey fetch missing response object.")
            }
            let bundle = PreKeyBundle(from: responseObject, forDeviceNumber: deviceId)
            success(bundle)
        }.catch(on: .global()) { error in
            failure(error)
        }
    }

    private class func createSession(forPreKeyBundle preKeyBundle: PreKeyBundle,
                                     accountId: String,
                                     deviceId: NSNumber,
                                     transaction: SDSAnyWriteTransaction) throws {
        assert(!Thread.isMainThread)

        let builder = SessionBuilder(sessionStore: sessionStore,
                                     preKeyStore: preKeyStore,
                                     signedPreKeyStore: signedPreKeyStore,
                                     identityKeyStore: identityManager,
                                     recipientId: accountId,
                                     deviceId: deviceId.int32Value)
        try builder.processPrekeyBundle(preKeyBundle,
                                        protocolContext: transaction)
    }
}
