//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import SignalCoreKit
import SignalServiceKit

public class ProvisioningCoordinatorImpl: ProvisioningCoordinator {

    private let db: DB
    private let identityManager: OWSIdentityManager
    private let messageFactory: Shims.MessageFactory
    private let preKeyManager: PreKeyManager
    private let profileManager: Shims.ProfileManager
    private let pushRegistrationManager: Shims.PushRegistrationManager
    private let receiptManager: Shims.ReceiptManager
    private let registrationStateChangeManager: RegistrationStateChangeManager
    private let signalService: OWSSignalServiceProtocol
    private let socketManager: SocketManager
    private let storageServiceManager: StorageServiceManager
    private let svr: SecureValueRecovery
    private let syncManager: Shims.SyncManager
    private let threadStore: ThreadStore
    private let tsAccountManager: TSAccountManager
    private let udManager: Shims.UDManager

    public init(
        db: DB,
        identityManager: OWSIdentityManager,
        messageFactory: Shims.MessageFactory,
        preKeyManager: PreKeyManager,
        profileManager: Shims.ProfileManager,
        pushRegistrationManager: Shims.PushRegistrationManager,
        receiptManager: Shims.ReceiptManager,
        registrationStateChangeManager: RegistrationStateChangeManager,
        signalService: OWSSignalServiceProtocol,
        socketManager: SocketManager,
        storageServiceManager: StorageServiceManager,
        svr: SecureValueRecovery,
        syncManager: Shims.SyncManager,
        threadStore: ThreadStore,
        tsAccountManager: TSAccountManager,
        udManager: Shims.UDManager
    ) {
        self.db = db
        self.identityManager = identityManager
        self.messageFactory = messageFactory
        self.preKeyManager = preKeyManager
        self.profileManager = profileManager
        self.pushRegistrationManager = pushRegistrationManager
        self.receiptManager = receiptManager
        self.registrationStateChangeManager = registrationStateChangeManager
        self.signalService = signalService
        self.socketManager = socketManager
        self.storageServiceManager = storageServiceManager
        self.svr = svr
        self.syncManager = syncManager
        self.threadStore = threadStore
        self.tsAccountManager = tsAccountManager
        self.udManager = udManager
    }

    public func completeProvisioning(
        provisionMessage: ProvisionMessage,
        deviceName: String
    ) async -> CompleteProvisioningResult {
        // * Primary devices that are re-registering can provision instead as long as either
        // the phone number or aci matches.
        // * Secondary devices _cannot_ be re-linked to primaries with a different aci.
        switch self.tsAccountManager.registrationStateWithMaybeSneakyTransaction {
        case .reregistering(let reregistrationPhoneNumber, let reregistrationAci):
            let acisMatch = reregistrationAci != nil && reregistrationAci == provisionMessage.aci
            let phoneNumbersMatch = reregistrationPhoneNumber == provisionMessage.phoneNumber
            guard acisMatch || phoneNumbersMatch else {
                Logger.warn("Cannot re-link primary a different aci and phone number")
                return .previouslyLinkedWithDifferentAccount
            }
        case .relinking(_, let relinkingAci):
            if let oldAci = relinkingAci, let newAci = provisionMessage.aci, oldAci != newAci {
                Logger.warn("Cannot re-link with a different aci")
                return .previouslyLinkedWithDifferentAccount
            }
        default:
            break
        }

        guard let phoneNumber = E164(provisionMessage.phoneNumber) else {
            return .genericError(OWSAssertionError("Primary E164 isn't valid"))
        }

        guard let aci = provisionMessage.aci else {
            return .genericError(OWSAssertionError("Missing ACI in provisioning message!"))
        }

        guard let pni = provisionMessage.pni else {
            return .genericError(OWSAssertionError("Missing PNI in provisioning message!"))
        }

        // Update censorship circumvention state as e164 could be changing.
        signalService.updateHasCensoredPhoneNumberDuringProvisioning(phoneNumber)

        let serverAuthToken = generateServerAuthToken()

        let apnRegistrationId: RegistrationRequestFactory.ApnRegistrationId?
        let prekeyBundles: RegistrationPreKeyUploadBundles
        let encryptedDeviceName: Data
        do {
            apnRegistrationId = try await getApnRegistrationId()
            encryptedDeviceName = try DeviceNames.encryptDeviceName(
                plaintext: deviceName,
                identityKeyPair: provisionMessage.aciIdentityKeyPair.keyPair
            )
            // This should be the last failable thing we do before making the verification
            // request, because if the verification request fails we need to clean up prekey
            // state created by this method.
            // If we did add new (failable) method calls between this and the verification
            // request invocation, we would have to make sure we similarly clean up prekey
            // state if there are failures.
            prekeyBundles = try await self.preKeyManager
                .createPreKeysForProvisioning(
                    aciIdentityKeyPair: provisionMessage.aciIdentityKeyPair,
                    pniIdentityKeyPair: provisionMessage.pniIdentityKeyPair
                )
                .value
        } catch {
            return .genericError(error)
        }

        let accountAttributes = await self.db.awaitableWrite { tx in
            return self.makeAccountAttributes(
                encryptedDeviceName: encryptedDeviceName,
                profileKey: provisionMessage.profileKey,
                tx: tx
            )
        }

        let rawVerifyDeviceResponse = await Self.Service.makeVerifySecondaryDeviceRequest(
            verificationCode: provisionMessage.provisioningCode,
            phoneNumber: provisionMessage.phoneNumber,
            authPassword: serverAuthToken,
            accountAttributes: accountAttributes,
            apnRegistrationId: apnRegistrationId,
            prekeyBundles: prekeyBundles,
            signalService: self.signalService
        )

        let verifyDeviceResponse: ProvisioningServiceResponses.VerifySecondaryDeviceResponse
        switch rawVerifyDeviceResponse {
        case .genericError(let error):
            try? await self.preKeyManager
                .finalizeRegistrationPreKeys(prekeyBundles, uploadDidSucceed: false)
                .value
            return .genericError(error)
        case .obsoleteLinkedDevice:
            try? await self.preKeyManager
                .finalizeRegistrationPreKeys(prekeyBundles, uploadDidSucceed: false)
                .value
            return .obsoleteLinkedDeviceError
        case .deviceLimitExceeded(let error):
            try? await self.preKeyManager
                .finalizeRegistrationPreKeys(prekeyBundles, uploadDidSucceed: false)
                .value
            return .deviceLimitExceededError(error)
        case .success(let response):
            verifyDeviceResponse = response
        }
        if pni != verifyDeviceResponse.pni {
            try? await self.preKeyManager
                .finalizeRegistrationPreKeys(prekeyBundles, uploadDidSucceed: false)
                .value
            return .genericError(OWSAssertionError("PNI from primary is out of sync with the server!"))
        }

        let authedDevice = AuthedDevice.explicit(.init(
            aci: aci,
            phoneNumber: phoneNumber,
            pni: pni,
            deviceId: .secondary(verifyDeviceResponse.deviceId),
            authPassword: serverAuthToken
        ))

        await self.db.awaitableWrite { tx in
            self.identityManager.setIdentityKeyPair(
                provisionMessage.aciIdentityKeyPair,
                for: .aci,
                tx: tx
            )
            self.identityManager.setIdentityKeyPair(
                provisionMessage.pniIdentityKeyPair,
                for: .pni,
                tx: tx
            )

            self.profileManager.setLocalProfileKey(
                provisionMessage.profileKey,
                userProfileWriter: .linking,
                authedAccount: authedDevice.authedAccount,
                tx: tx
            )
            if let masterKey = provisionMessage.masterKey {
                self.svr.storeSyncedMasterKey(
                    data: masterKey,
                    authedDevice: .implicit,
                    updateStorageService: false,
                    transaction: tx
                )
            }

            if let areReadReceiptsEnabled = provisionMessage.areReadReceiptsEnabled {
                self.receiptManager.setAreReadReceiptsEnabled(
                    areReadReceiptsEnabled,
                    tx: tx
                )
            }
        }
        do {
            try await self.preKeyManager
                .finalizeRegistrationPreKeys(prekeyBundles, uploadDidSucceed: true)
                .value
            try await self.preKeyManager
                .rotateOneTimePreKeysForRegistration(auth: authedDevice.authedAccount.chatServiceAuth)
                .value
        } catch {
            return .genericError(error)
        }

        let hasBackedUpMasterKey = self.db.read { tx in
            self.svr.hasBackedUpMasterKey(transaction: tx)
        }
        let capabilities = AccountAttributes.Capabilities(hasSVRBackups: hasBackedUpMasterKey)
        do {
            try await Service.makeUpdateSecondaryDeviceCapabilitiesRequest(
                capabilities: capabilities,
                auth: authedDevice.authedAccount.chatServiceAuth,
                signalService: self.signalService,
                tsAccountManager: self.tsAccountManager
            )
        } catch {
            return .genericError(error)
        }
        await self.db.awaitableWrite { tx in
            self.registrationStateChangeManager.didProvisionSecondary(
                e164: phoneNumber,
                aci: aci,
                pni: pni,
                authToken: serverAuthToken,
                deviceId: verifyDeviceResponse.deviceId,
                tx: tx
            )
        }

        return await performNecessarySyncsAndRestores(
            authedDevice: authedDevice,
            hasMasterKeyInProvisioningMessage: provisionMessage.masterKey != nil
        )
    }

    private func performNecessarySyncsAndRestores(
        authedDevice: AuthedDevice,
        hasMasterKeyInProvisioningMessage: Bool
    ) async -> CompleteProvisioningResult {
        async let storageServiceRestore: Void = self.performInitialStorageServiceRestore(
            authedDevice: authedDevice,
            hasMasterKeyInProvisioningMessage: hasMasterKeyInProvisioningMessage
        )
        async let contactSync: Void = self.performInitialContactSync()
        do {
            _ = try await (storageServiceRestore, contactSync)
        } catch {
            return .genericError(error)
        }
        return .success
    }

    private func performInitialStorageServiceRestore(
        authedDevice: AuthedDevice,
        hasMasterKeyInProvisioningMessage: Bool
    ) async throws {
        if !hasMasterKeyInProvisioningMessage {
            // If we didn't get a master key in the provisioning message, we have
            // to request to sync one now.
            // TODO: 90 days after all primaries include the master key in every
            // provisioning message, we can make it non-optional and remove this
            // branch entirely.
            async let syncDidComplete: Void = NotificationCenter.default.observeOnce(.OWSSyncManagerKeysSyncDidComplete)

            async let requestKeys: Void = self.db.awaitableWrite { tx in
                self.syncManager.sendKeysSyncRequestMessage(tx: tx)
            }

            _ = await (syncDidComplete, requestKeys)
        }

        try await self.storageServiceManager
            .restoreOrCreateManifestIfNecessary(authedDevice: authedDevice)
            .timeout(seconds: 60, substituteValue: ())
            .awaitable()
    }

    private func performInitialContactSync() async throws {
        // we wait a bit for the initial syncs to come in before proceeding to the inbox
        // because we want to present the inbox already populated with groups and contacts,
        // rather than have the trickle in moments later.
        // NOTE: in practice...groups do trickle in later, as of the time of this comment.
        // TODO: Eventually, we can rely entirely on the storage service and will no longer
        // need to do any initial sync. For now, we try and do both operations in parallel.

        let orderedThreadIds = try await syncManager
            .sendInitialSyncRequestsAwaitingCreatedThreadOrdering(timeout: 60)

        // Maintain the remote sort ordering of threads by inserting `syncedThread` messages
        // in that thread order.
        await self.db.awaitableWrite { tx in
            for threadId in orderedThreadIds.reversed() {
                guard let thread = self.threadStore.fetchThread(uniqueId: threadId, tx: tx) else {
                    owsFailDebug("thread was unexpectedly nil")
                    continue
                }
                self.messageFactory.insertInfoMessage(into: thread, messageType: .syncedThread, tx: tx)
            }
        }
    }

    // MARK: - Helpers

    private func getApnRegistrationId() async throws -> RegistrationRequestFactory.ApnRegistrationId? {
        do {
            return try await pushRegistrationManager
                .requestPushTokens(forceRotation: false)
        } catch let error {
            switch error {
            case PushRegistrationError.pushNotSupported(let description):
                // This can happen with:
                // - simulators, none of which support receiving push notifications
                // - on iOS11 devices which have disabled "Allow Notifications" and disabled "Enable Background Refresh" in the system settings.
                Logger.info("Recovered push registration error. Leaving as manual message fetcher because push not supported: \(description)")

                // no-op since secondary devices already start as manual message fetchers.
                // Use a nil apn reg id.
                return nil
            default:
                throw error
            }
        }
    }

    private typealias VerifySecondaryDeviceResponse = Service.VerifySecondaryDeviceResponse

    private func makeAccountAttributes(
        encryptedDeviceName encryptedDeviceNameRaw: Data,
        profileKey: OWSAES256Key,
        tx: DBWriteTransaction
    ) -> AccountAttributes {
        // Secondary devices only use account attributes during registration;
        // at this time they have historically set this to true.
        // Some forensic investigation is required as to why, but the best bet
        // is that some form of message delivery needs to succeed _before_ it
        // sets its APNS token, and thus it needs manual message fetch enabled.

        // This field is scoped to the device that sets it and does not overwrite
        // the attribute from the primary device.

        // TODO: can we change this with atomic device linking?
        let isManualMessageFetchEnabled = true

        let registrationId = tsAccountManager.getOrGenerateAciRegistrationId(tx: tx)
        let pniRegistrationId = tsAccountManager.getOrGeneratePniRegistrationId(tx: tx)

        let udAccessKey: String
        do {
            udAccessKey = try SMKUDAccessKey(profileKey: profileKey.keyData).keyData.base64EncodedString()
        } catch {
            // Crash app if UD cannot be enabled.
            owsFail("Could not determine UD access key: \(error).")
        }
        let allowUnrestrictedUD = udManager.shouldAllowUnrestrictedAccessLocal(tx: tx)

        // Historical note: secondary device registration uses the same AccountAttributes object,
        // but some fields, like reglock and pin, are ignored by the server.
        // Don't bother with this field at all; just put explicit none.
        let twoFaMode: AccountAttributes.TwoFactorAuthMode = .none

        let registrationRecoveryPassword = svr.data(
            for: .registrationRecoveryPassword,
            transaction: tx
        )?.canonicalStringRepresentation

        let encryptedDeviceName = encryptedDeviceNameRaw.base64EncodedString()

        let phoneNumberDiscoverability = tsAccountManager.phoneNumberDiscoverability(tx: tx)

        let hasSVRBackups = svr.hasBackedUpMasterKey(transaction: tx)

        return AccountAttributes(
            isManualMessageFetchEnabled: isManualMessageFetchEnabled,
            registrationId: registrationId,
            pniRegistrationId: pniRegistrationId,
            unidentifiedAccessKey: udAccessKey,
            unrestrictedUnidentifiedAccess: allowUnrestrictedUD,
            twofaMode: twoFaMode,
            registrationRecoveryPassword: registrationRecoveryPassword,
            encryptedDeviceName: encryptedDeviceName,
            discoverableByPhoneNumber: phoneNumberDiscoverability,
            hasSVRBackups: hasSVRBackups
        )
    }

    private func generateServerAuthToken() -> String {
        return Cryptography.generateRandomBytes(16).hexadecimalString
    }
}
