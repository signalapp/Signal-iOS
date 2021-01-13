//
//  Copyright (c) 2020 Open Whisper Systems. All rights reserved.
//

import Foundation
import PromiseKit
import SignalServiceKit

/**
 * Signal is actually two services - textSecure for messages and red phone (for calls). 
 * AccountManager delegates to both.
 */
@objc
public class AccountManager: NSObject {

    // MARK: - Dependencies

    var profileManager: OWSProfileManager {
        return OWSProfileManager.shared()
    }

    private var networkManager: TSNetworkManager {
        return SSKEnvironment.shared.networkManager
    }

    private var preferences: OWSPreferences {
        return Environment.shared.preferences
    }

    private var tsAccountManager: TSAccountManager {
        return TSAccountManager.shared()
    }

    private var accountServiceClient: AccountServiceClient {
        return SSKEnvironment.shared.accountServiceClient
    }

    private var storageServiceManager: StorageServiceManagerProtocol {
        return SSKEnvironment.shared.storageServiceManager
    }

    private var deviceService: DeviceService {
        return DeviceService.shared
    }

    var pushRegistrationManager: PushRegistrationManager {
        return AppEnvironment.shared.pushRegistrationManager
    }

    var readReceiptManager: OWSReadReceiptManager {
        return OWSReadReceiptManager.shared()
    }

    var identityManager: OWSIdentityManager {
        return SSKEnvironment.shared.identityManager
    }

    var databaseStorage: SDSDatabaseStorage {
        return SDSDatabaseStorage.shared
    }

    // MARK: -

    @objc
    public override init() {
        super.init()

        SwiftSingletons.register(self)

        AppReadiness.runNowOrWhenAppDidBecomeReady {
            if self.tsAccountManager.isRegistered {
                self.recordUuidIfNecessary()
            }
        }
    }

    // MARK: registration

    @objc
    func requestAccountVerificationObjC(recipientId: String, captchaToken: String?, isSMS: Bool) -> AnyPromise {
        return AnyPromise(requestAccountVerification(recipientId: recipientId, captchaToken: captchaToken, isSMS: isSMS))
    }

    func requestAccountVerification(recipientId: String, captchaToken: String?, isSMS: Bool) -> Promise<Void> {
        let transport: TSVerificationTransport = isSMS ? .SMS : .voice

        return firstly { () -> Promise<String?> in
            guard !self.tsAccountManager.isRegistered else {
                throw OWSAssertionError("requesting account verification when already registered")
            }

            self.tsAccountManager.phoneNumberAwaitingVerification = recipientId

            return self.getPreauthChallenge(recipientId: recipientId)
        }.then { (preauthChallenge: String?) -> Promise<Void> in
            self.accountServiceClient.requestVerificationCode(recipientId: recipientId,
                                                              preauthChallenge: preauthChallenge,
                                                              captchaToken: captchaToken,
                                                              transport: transport)
        }
    }

    func getPreauthChallenge(recipientId: String) -> Promise<String?> {
        return firstly {
            return self.pushRegistrationManager.requestPushTokens()
        }.then { (_: String, voipToken: String) -> Promise<String?> in
            let (pushPromise, pushResolver) = Promise<String>.pending()
            self.pushRegistrationManager.preauthChallengeResolver = pushResolver

            return self.accountServiceClient.requestPreauthChallenge(recipientId: recipientId, pushToken: voipToken).then { () -> Promise<String?> in
                let timeout: TimeInterval
                if OWSIsDebugBuild() && TSConstants.isUsingProductionService {
                    // won't receive production voip in debug build, don't wait for long
                    timeout = 0.5
                } else {
                    timeout = 5
                }

                return pushPromise.nilTimeout(seconds: timeout)
            }
        }.recover { (error: Error) -> Promise<String?> in
            switch error {
            case PushRegistrationError.pushNotSupported(description: let description):
                Logger.warn("Push not supported: \(description)")
            case is NetworkManagerError:
                // not deployed to production yet.
                if error.httpStatusCode == 404 {
                    Logger.warn("404 while requesting preauthChallenge: \(error)")
                } else {
                    fallthrough
                }
            default:
                owsFailDebug("error while requesting preauthChallenge: \(error)")
            }
            return Promise.value(nil)
        }
    }

    func register(verificationCode: String, pin: String?, checkForAvailableTransfer: Bool) -> Promise<Void> {
        guard verificationCode.count > 0 else {
            let error = OWSErrorWithCodeDescription(.userError,
                                                    NSLocalizedString("REGISTRATION_ERROR_BLANK_VERIFICATION_CODE",
                                                                      comment: "alert body during registration"))
            return Promise(error: error)
        }

        Logger.debug("registering with signal server")

        return firstly {
            self.registerForTextSecure(verificationCode: verificationCode, pin: pin, checkForAvailableTransfer: checkForAvailableTransfer)
        }.then { response -> Promise<Void> in
            assert(response.uuid != nil)
            self.tsAccountManager.uuidAwaitingVerification = response.uuid

            self.databaseStorage.write { transaction in
                if !self.tsAccountManager.isReregistering {
                    // For new users, read receipts are on by default.
                    self.readReceiptManager.setAreReadReceiptsEnabled(true,
                                                                      transaction: transaction)

                    // New users also have the onboarding banner cards enabled
                    GetStartedBannerViewController.enableAllCards(writeTx: transaction)
                }

                // If the user previously had a PIN, but we don't have record of it,
                // mark them as pending restoration during onboarding. Reg lock users
                // will have already restored their PIN by this point.
                if response.hasPreviouslyUsedKBS, !KeyBackupService.hasMasterKey {
                    KeyBackupService.recordPendingRestoration(transaction: transaction)
                }
            }

            return self.accountServiceClient.updatePrimaryDeviceAccountAttributes()
        }.then {
            self.createPreKeys()
        }.done {
            self.profileManager.fetchLocalUsersProfile()
        }.then { _ -> Promise<Void> in
            return self.syncPushTokens().recover { (error) -> Promise<Void> in
                switch error {
                case PushRegistrationError.pushNotSupported(let description):
                    // This can happen with:
                    // - simulators, none of which support receiving push notifications
                    // - on iOS11 devices which have disabled "Allow Notifications" and disabled "Enable Background Refresh" in the system settings.
                    Logger.info("Recovered push registration error. Registering for manual message fetcher because push not supported: \(description)")
                    self.tsAccountManager.setIsManualMessageFetchEnabled(true)
                    return self.accountServiceClient.updatePrimaryDeviceAccountAttributes()
                default:
                    throw error
                }
            }
        }.done {
            self.completeRegistration()
        }.then { _ -> Promise<Void> in
            self.performInitialStorageServiceRestore()
        }
    }

    func performInitialStorageServiceRestore() -> Promise<Void> {
        BenchEventStart(title: "waiting for initial storage service restore", eventId: "initial-storage-service-restore")
        return firstly {
            self.storageServiceManager.restoreOrCreateManifestIfNecessary().asVoid()
        }.done {
            // In the case that we restored our profile from a previous registration,
            // re-upload it so that the user does not need to refill in all the details.
            // Right now the avatar will always be lost since we do not store avatars in
            // the storage service.

            if self.profileManager.hasProfileName || self.profileManager.localProfileAvatarData() != nil {
                Logger.debug("restored local profile name. Uploading...")
                // if we don't have a `localGivenName`, there's nothing to upload, and trying
                // to upload would fail.

                // Note we *don't* return this promise. There's no need to block registration on
                // it completing, and if there are any errors, it's durable.
                firstly {
                    self.profileManager.reuploadLocalProfilePromise()
                }.catch { error in
                    Logger.error("error: \(error)")
                }
            } else {
                Logger.debug("no local profile name restored.")
            }

            BenchEventComplete(eventId: "initial-storage-service-restore")
        }.timeout(seconds: 60)
    }

    func completeSecondaryLinking(provisionMessage: ProvisionMessage, deviceName: String) -> Promise<Void> {
        tsAccountManager.phoneNumberAwaitingVerification = provisionMessage.phoneNumber
        tsAccountManager.uuidAwaitingVerification = provisionMessage.uuid

        let serverAuthToken = generateServerAuthToken()

        return firstly { () throws -> Promise<UInt32> in
            let encryptedDeviceName = try DeviceNames.encryptDeviceName(plaintext: deviceName,
                                                                        identityKeyPair: provisionMessage.identityKeyPair)

            return accountServiceClient.verifySecondaryDevice(verificationCode: provisionMessage.provisioningCode,
                                                              phoneNumber: provisionMessage.phoneNumber,
                                                              authKey: serverAuthToken,
                                                              encryptedDeviceName: encryptedDeviceName)
        }.done { (deviceId: UInt32) in
            self.databaseStorage.write { transaction in
                self.identityManager.storeIdentityKeyPair(provisionMessage.identityKeyPair,
                                                          transaction: transaction)

                self.profileManager.setLocalProfileKey(provisionMessage.profileKey,
                                                       wasLocallyInitiated: false,
                                                       transaction: transaction)

                if let areReadReceiptsEnabled = provisionMessage.areReadReceiptsEnabled {
                    self.readReceiptManager.setAreReadReceiptsEnabled(areReadReceiptsEnabled,
                                                                      transaction: transaction)
                }

                self.tsAccountManager.setStoredServerAuthToken(serverAuthToken,
                                                               deviceId: deviceId,
                                                               transaction: transaction)

                self.tsAccountManager.setStoredDeviceName(deviceName,
                                                          transaction: transaction)
            }
        }.then { _ -> Promise<Void> in
            self.createPreKeys()
        }.then { _ -> Promise<Void> in
            return self.syncPushTokens().recover { error in
                switch error {
                case PushRegistrationError.pushNotSupported(let description):
                    // This can happen with:
                    // - simulators, none of which support receiving push notifications
                    // - on iOS11 devices which have disabled "Allow Notifications" and disabled "Enable Background Refresh" in the system settings.
                    Logger.info("Recovered push registration error. Leaving as manual message fetcher because push not supported: \(description)")

                    // no-op since secondary devices already start as manual message fetchers
                    return
                default:
                    throw error
                }
            }
        }.then(on: .global()) {
            self.deviceService.updateSecondaryDeviceCapabilities()
        }.done {
            self.completeRegistration()
        }.then { _ -> Promise<Void> in
            BenchEventStart(title: "waiting for initial storage service restore", eventId: "initial-storage-service-restore")

            self.databaseStorage.asyncWrite { transaction in
                OWSSyncManager.shared().sendKeysSyncRequestMessage(transaction: transaction)
            }

            let storageServiceRestorePromise = firstly {
                NotificationCenter.default.observe(once: .OWSSyncManagerKeysSyncDidComplete).asVoid()
            }.then {
                StorageServiceManager.shared.restoreOrCreateManifestIfNecessary().asVoid()
            }.ensure {
                BenchEventComplete(eventId: "initial-storage-service-restore")
            }.timeout(seconds: 60)

            // we wait a bit for the initial syncs to come in before proceeding to the inbox
            // because we want to present the inbox already populated with groups and contacts,
            // rather than have the trickle in moments later.
            // TODO: Eventually, we can rely entirely on the storage service and will no longer
            // need to do any initial sync beyond the "keys" sync. For now, we try and do both
            // operations in parallel.
            BenchEventStart(title: "waiting for initial contact and group sync", eventId: "initial-contact-sync")

            let initialSyncMessagePromise = firstly {
                OWSSyncManager.shared().sendInitialSyncRequestsAwaitingCreatedThreadOrdering(timeoutSeconds: 60)
            }.done(on: .global() ) { orderedThreadIds in
                Logger.debug("orderedThreadIds: \(orderedThreadIds)")
                // Maintain the remote sort ordering of threads by inserting `syncedThread` messages
                // in that thread order.
                self.databaseStorage.write { transaction in
                    for threadId in orderedThreadIds.reversed() {
                        guard let thread = TSThread.anyFetch(uniqueId: threadId, transaction: transaction) else {
                            owsFailDebug("thread was unexpectedly nil")
                            continue
                        }
                        let message = TSInfoMessage(thread: thread,
                                                    messageType: .syncedThread)
                        message.anyInsert(transaction: transaction)
                    }
                }
            }.ensure {
                BenchEventComplete(eventId: "initial-contact-sync")
            }

            return when(fulfilled: [storageServiceRestorePromise, initialSyncMessagePromise])
        }
    }

    private struct RegistrationResponse {
        var uuid: UUID?
        var hasPreviouslyUsedKBS = false
    }

    private func registerForTextSecure(verificationCode: String, pin: String?, checkForAvailableTransfer: Bool) -> Promise<RegistrationResponse> {
        let serverAuthToken = generateServerAuthToken()

        return Promise<Any?> { resolver in
            guard let phoneNumber = tsAccountManager.phoneNumberAwaitingVerification else {
                throw OWSAssertionError("phoneNumberAwaitingVerification was unexpectedly nil")
            }

            let request = OWSRequestFactory.verifyPrimaryDeviceRequest(verificationCode: verificationCode,
                                                                       phoneNumber: phoneNumber,
                                                                       authKey: serverAuthToken,
                                                                       pin: pin,
                                                                       checkForAvailableTransfer: checkForAvailableTransfer)

            tsAccountManager.verifyAccount(with: request,
                                           success: resolver.fulfill,
                                           failure: resolver.reject)
        }.map(on: .global()) { responseObject throws -> RegistrationResponse in
            self.databaseStorage.write { transaction in
                self.tsAccountManager.setStoredServerAuthToken(serverAuthToken,
                                                               deviceId: OWSDevicePrimaryDeviceId,
                                                               transaction: transaction)
            }

            guard let responseObject = responseObject else {
                owsFailDebug("unexpectedly missing responseObject")
                throw OWSErrorMakeUnableToProcessServerResponseError()
            }

            guard let params = ParamParser(responseObject: responseObject) else {
                owsFailDebug("params was unexpectedly nil")
                throw OWSErrorMakeUnableToProcessServerResponseError()
            }

            var registrationResponse = RegistrationResponse()

            // TODO UUID: this UUID param should be non-optional when the production service is updated
            if let uuidString: String = try params.optional(key: "uuid") {
                guard let uuid = UUID(uuidString: uuidString) else {
                    owsFailDebug("invalid uuidString: \(uuidString)")
                    throw OWSErrorMakeUnableToProcessServerResponseError()
                }
                registrationResponse.uuid = uuid
            }

            registrationResponse.hasPreviouslyUsedKBS = try params.optional(key: "storageCapable") ?? false

            return registrationResponse
        }
    }

    @objc
    public func fakeRegistration() {
        fakeRegisterForTests(phoneNumber: "+15551231234", uuid: UUID())
        SignalApp.shared().showConversationSplitView()
    }

    private func fakeRegisterForTests(phoneNumber: String, uuid: UUID) {
        let serverAuthToken = generateServerAuthToken()
        let identityKeyPair = Curve25519.generateKeyPair()
        let profileKey = OWSAES256Key.generateRandom()

        tsAccountManager.phoneNumberAwaitingVerification = phoneNumber
        tsAccountManager.uuidAwaitingVerification = uuid

        databaseStorage.write { transaction in
            self.identityManager.storeIdentityKeyPair(identityKeyPair,
                                                      transaction: transaction)
            self.profileManager.setLocalProfileKey(profileKey,
                                                   wasLocallyInitiated: false,
                                                   transaction: transaction)
            self.tsAccountManager.setStoredServerAuthToken(serverAuthToken,
                                                           deviceId: 1,
                                                           transaction: transaction)
        }
        completeRegistration()
    }

    private func createPreKeys() -> Promise<Void> {
        return Promise { resolver in
            TSPreKeyManager.createPreKeys(success: { resolver.fulfill(()) },
                                          failure: resolver.reject)
        }
    }

    private func syncPushTokens() -> Promise<Void> {
        Logger.info("")
        let job = SyncPushTokensJob(accountManager: self, preferences: self.preferences)
        job.uploadOnlyIfStale = false
        return job.run()
    }

    private func completeRegistration() {
        Logger.info("")
        tsAccountManager.didRegister()
    }

    // MARK: Message Delivery

    func updatePushTokens(pushToken: String, voipToken: String) -> Promise<Void> {
        return Promise { resolver in
            tsAccountManager.registerForPushNotifications(pushToken: pushToken,
                                                          voipToken: voipToken,
                                                          success: { resolver.fulfill(()) },
                                                          failure: resolver.reject)
        }
    }

    // MARK: Turn Server

    func getTurnServerInfo() -> Promise<TurnServerInfo> {
        return Promise { resolver in
            self.networkManager.makeRequest(OWSRequestFactory.turnServerInfoRequest(),
                                            success: { (_: URLSessionDataTask, responseObject: Any?) in
                                                guard responseObject != nil else {
                                                    return resolver.reject(OWSErrorMakeUnableToProcessServerResponseError())
                                                }

                                                if let responseDictionary = responseObject as? [String: AnyObject] {
                                                    if let turnServerInfo = TurnServerInfo(attributes: responseDictionary) {
                                                        return resolver.fulfill(turnServerInfo)
                                                    }
                                                    Logger.error("unexpected server response:\(responseDictionary)")
                                                }
                                                return resolver.reject(OWSErrorMakeUnableToProcessServerResponseError())
            },
                                            failure: { (_: URLSessionDataTask, error: Error) in
                                                    return resolver.reject(error)
            })
        }
    }

    func recordUuidIfNecessary() {
        DispatchQueue.global().async {
            _ = self.ensureUuid().catch { error in
                // Until we're in a UUID-only world, don't require a
                // local UUID.
                owsFailDebug("error: \(error)")
            }
        }
    }

    func ensureUuid() -> Promise<UUID> {
        if let existingUuid = tsAccountManager.localUuid {
            return Promise.value(existingUuid)
        }

        return accountServiceClient.getUuid().map(on: DispatchQueue.global()) { uuid in
            // It's possible this method could be called multiple times, so we check
            // again if it's been set. We dont bother serializing access since it should
            // be idempotent.
            if let existingUuid = self.tsAccountManager.localUuid {
                assert(existingUuid == uuid)
                return existingUuid
            }
            Logger.info("Recording UUID for legacy user")
            self.tsAccountManager.recordUuidForLegacyUser(uuid)
            return uuid
        }
    }

    private func generateServerAuthToken() -> String {
        return Cryptography.generateRandomBytes(16).hexadecimalString
    }
}
