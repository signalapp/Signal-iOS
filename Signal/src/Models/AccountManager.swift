//
// Copyright 2016 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import SignalMessaging
import SignalServiceKit

public enum AccountManagerError: Error {
    case reregistrationDifferentAccount
}

// MARK: -

public class AccountManager: NSObject, Dependencies {

    public override init() {
        super.init()

        SwiftSingletons.register(self)
    }

    func performInitialStorageServiceRestore(authedDevice: AuthedDevice = .implicit) -> Promise<Void> {
        BenchEventStart(title: "waiting for initial storage service restore", eventId: "initial-storage-service-restore")
        return firstly {
            self.storageServiceManager.restoreOrCreateManifestIfNecessary(authedDevice: authedDevice)
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
                    self.profileManagerImpl.reuploadLocalProfilePromise(authedAccount: authedDevice.authedAccount)
                }.catch { error in
                    Logger.error("error: \(error)")
                }
            } else {
                Logger.debug("no local profile name restored.")
            }

            BenchEventComplete(eventId: "initial-storage-service-restore")
        }.timeout(seconds: 60)
    }

    // MARK: Linking

    func completeSecondaryLinking(provisionMessage: ProvisionMessage, deviceName: String) -> Promise<Void> {
        // * Primary devices that are re-registering can provision instead with a new uuid.
        // * Secondary devices _cannot_ be re-linked to primaries with a different uuid, but
        //   `reregistering` state does not apply to secondaries.
        switch DependenciesBridge.shared.tsAccountManager.registrationStateWithMaybeSneakyTransaction {
        case .reregistering(let reregistrationPhoneNumber, let reregistrationAci):
            var canChangePhoneNumbers = false
            if let oldAci = reregistrationAci, let newAci = provisionMessage.aci, oldAci == newAci {
                canChangePhoneNumbers = true
            }
            if
                !canChangePhoneNumbers,
                reregistrationPhoneNumber != provisionMessage.phoneNumber
            {
                Logger.warn("Cannot provision with a different phone number from reregistration.")
                return Promise(error: AccountManagerError.reregistrationDifferentAccount)
            }
        default:
            break
        }

        guard let phoneNumber = E164(provisionMessage.phoneNumber) else {
            return Promise(error: OWSAssertionError("Primary E164 isn't valid"))
        }

        guard let aci = provisionMessage.aci else {
            return Promise(error: OWSAssertionError("Missing ACI in provisioning message!"))
        }

        guard let pni = provisionMessage.pni else {
            return Promise(error: OWSAssertionError("Missing PNI in provisioning message!"))
        }

        // Cycle socket and censorship circumvention state as e164 could be changing.
        signalService.updateHasCensoredPhoneNumberDuringProvisioning(phoneNumber)
        socketManager.cycleSocket()

        let serverAuthToken = generateServerAuthToken()

        var prekeyBundlesCreated: RegistrationPreKeyUploadBundles?

        return firstly { () -> Promise<RegistrationRequestFactory.ApnRegistrationId?> in
            return pushRegistrationManager.requestPushTokens(forceRotation: false)
                .map(on: SyncScheduler()) { return $0 }
                .recover { (error) -> Promise<RegistrationRequestFactory.ApnRegistrationId?> in
                    switch error {
                    case PushRegistrationError.pushNotSupported(let description):
                        // This can happen with:
                        // - simulators, none of which support receiving push notifications
                        // - on iOS11 devices which have disabled "Allow Notifications" and disabled "Enable Background Refresh" in the system settings.
                        Logger.info("Recovered push registration error. Leaving as manual message fetcher because push not supported: \(description)")

                        // no-op since secondary devices already start as manual message fetchers
                        return .value(nil)
                    default:
                        return .init(error: error)
                    }
                }
        }.then { (apnRegistrationId) -> Promise<(RegistrationRequestFactory.ApnRegistrationId?, RegistrationPreKeyUploadBundles)> in
            return DependenciesBridge.shared.preKeyManager
                .createPreKeysForProvisioning(
                    aciIdentityKeyPair: provisionMessage.aciIdentityKeyPair,
                    pniIdentityKeyPair: provisionMessage.pniIdentityKeyPair
                )
                .map(on: SyncScheduler()) {
                    prekeyBundlesCreated = $0
                    return (apnRegistrationId, $0)
                }
        }.then { (apnRegistrationId, prekeyBundles) throws -> Promise<VerifySecondaryDeviceResponse> in
            let encryptedDeviceName = try DeviceNames.encryptDeviceName(
                plaintext: deviceName,
                identityKeyPair: provisionMessage.aciIdentityKeyPair.keyPair
            )

            return self.accountServiceClient.verifySecondaryDevice(
                verificationCode: provisionMessage.provisioningCode,
                phoneNumber: provisionMessage.phoneNumber,
                authKey: serverAuthToken,
                encryptedDeviceName: encryptedDeviceName,
                apnRegistrationId: apnRegistrationId,
                prekeyBundles: prekeyBundles
            )
        }.done { (response: VerifySecondaryDeviceResponse) in
            if pni != response.pni {
                throw OWSAssertionError("PNI from primary is out of sync with the server!")
            }

            self.databaseStorage.write { transaction in
                let identityManager = DependenciesBridge.shared.identityManager

                identityManager.setIdentityKeyPair(
                    provisionMessage.aciIdentityKeyPair,
                    for: .aci,
                    tx: transaction.asV2Write
                )

                identityManager.setIdentityKeyPair(
                    provisionMessage.pniIdentityKeyPair,
                    for: .pni,
                    tx: transaction.asV2Write
                )

                self.profileManagerImpl.setLocalProfileKey(
                    provisionMessage.profileKey,
                    userProfileWriter: .linking,
                    authedAccount: .implicit(),
                    transaction: transaction
                )

                if let areReadReceiptsEnabled = provisionMessage.areReadReceiptsEnabled {
                    self.receiptManager.setAreReadReceiptsEnabled(
                        areReadReceiptsEnabled,
                        transaction: transaction
                    )
                }

                DependenciesBridge.shared.registrationStateChangeManager.didLinkSecondary(
                    e164: phoneNumber,
                    aci: aci,
                    pni: pni,
                    authToken: serverAuthToken,
                    deviceId: response.deviceId,
                    tx: transaction.asV2Write
                )
            }
        }.then { _ -> Promise<Void> in
            if let prekeyBundlesCreated {
                return DependenciesBridge.shared.preKeyManager.finalizeRegistrationPreKeys(prekeyBundlesCreated, uploadDidSucceed: true)
                    .then {
                        return DependenciesBridge.shared.preKeyManager.rotateOneTimePreKeysForRegistration(auth: .implicit())
                    }
            }
            return DependenciesBridge.shared.preKeyManager.rotateOneTimePreKeysForRegistration(auth: .implicit())
        }.recover { error -> Promise<Void> in
            if let prekeyBundlesCreated {
                return DependenciesBridge.shared.preKeyManager.finalizeRegistrationPreKeys(prekeyBundlesCreated, uploadDidSucceed: false)
                    .then { () -> Promise<Void> in
                        return .init(error: error)
                    }
            }
            return .init(error: error)
        }.then(on: DispatchQueue.global()) {
            let hasBackedUpMasterKey = self.databaseStorage.read { tx in
                DependenciesBridge.shared.svr.hasBackedUpMasterKey(transaction: tx.asV2Read)
            }
            return Promise.wrapAsync {
                let capabilities = AccountAttributes.Capabilities(hasSVRBackups: hasBackedUpMasterKey)
                try await self.serviceClient.updateSecondaryDeviceCapabilities(capabilities)
            }
        }.done {
            DependenciesBridge.shared.db.write { tx in
                DependenciesBridge.shared.registrationStateChangeManager.didFinishProvisioningSecondary(tx: tx)
            }
        }.then { _ -> Promise<Void> in
            BenchEventStart(title: "waiting for initial storage service restore", eventId: "initial-storage-service-restore")

            self.databaseStorage.asyncWrite { transaction in
                OWSSyncManager.shared.sendKeysSyncRequestMessage(transaction: transaction)
            }

            let storageServiceRestorePromise = firstly {
                NotificationCenter.default.observe(once: .OWSSyncManagerKeysSyncDidComplete).asVoid()
            }.then {
                StorageServiceManagerImpl.shared.restoreOrCreateManifestIfNecessary(authedDevice: .implicit).asVoid()
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
                OWSSyncManager.shared.sendInitialSyncRequestsAwaitingCreatedThreadOrdering(timeoutSeconds: 60)
            }.done(on: DispatchQueue.global() ) { orderedThreadIds in
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

            return Promise.when(fulfilled: [storageServiceRestorePromise, initialSyncMessagePromise])
        }
    }

    private func syncPushTokens() -> Promise<Void> {
        Logger.info("")
        return Promise.wrapAsync { try await SyncPushTokensJob(mode: .forceUpload).run() }
    }

    // MARK: Message Delivery

    func updatePushTokens(pushToken: String, voipToken: String?) -> Promise<Void> {
        let request = OWSRequestFactory.registerForPushRequest(
            withPushIdentifier: pushToken,
            voipIdentifier: voipToken
        )
        return updatePushTokens(request: request)
    }

    func updatePushTokens(request: TSRequest) -> Promise<Void> {
        return updatePushTokens(request: request, remainingRetries: 3)
    }

    private func updatePushTokens(
        request: TSRequest,
        remainingRetries: Int
    ) -> Promise<Void> {
        return networkManager.makePromise(request: request)
            .asVoid()
            .recover(on: DispatchQueue.global()) { error -> Promise<Void> in
                if remainingRetries > 0 {
                    return self.updatePushTokens(
                        request: request,
                        remainingRetries: remainingRetries - 1
                    )
                } else {
                    owsFailDebugUnlessNetworkFailure(error)
                    return Promise(error: error)
                }
            }
    }

    // MARK: Turn Server

    func getTurnServerInfo() -> Promise<TurnServerInfo> {
        let request = OWSRequestFactory.turnServerInfoRequest()
        return firstly {
            Self.networkManager.makePromise(request: request)
        }.map(on: DispatchQueue.global()) { response in
            guard let json = response.responseBodyJson,
                  let responseDictionary = json as? [String: AnyObject],
                  let turnServerInfo = TurnServerInfo(attributes: responseDictionary) else {
                throw OWSAssertionError("Missing or invalid JSON")
            }
            return turnServerInfo
        }
    }

    private func generateServerAuthToken() -> String {
        return Cryptography.generateRandomBytes(16).hexadecimalString
    }
}
