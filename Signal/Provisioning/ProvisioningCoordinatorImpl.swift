//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import LibSignalClient
import SignalServiceKit

class ProvisioningCoordinatorImpl: ProvisioningCoordinator {

    private let chatConnectionManager: ChatConnectionManager
    private let db: any DB
    private let deviceService: OWSDeviceService
    private let identityManager: OWSIdentityManager
    private let linkAndSyncManager: LinkAndSyncManager
    private let accountKeyStore: AccountKeyStore
    private let messageFactory: Shims.MessageFactory
    private let preKeyManager: PreKeyManager
    private let profileManager: Shims.ProfileManager
    private let pushRegistrationManager: Shims.PushRegistrationManager
    private let receiptManager: Shims.ReceiptManager
    private let registrationStateChangeManager: RegistrationStateChangeManager
    private let signalProtocolStoreManager: SignalProtocolStoreManager
    private let signalService: OWSSignalServiceProtocol
    private let storageServiceManager: StorageServiceManager
    private let svr: SecureValueRecovery
    private let syncManager: Shims.SyncManager
    private let threadStore: ThreadStore
    private let tsAccountManager: TSAccountManager
    private let udManager: Shims.UDManager

    init(
        chatConnectionManager: ChatConnectionManager,
        db: any DB,
        deviceService: OWSDeviceService,
        identityManager: OWSIdentityManager,
        linkAndSyncManager: LinkAndSyncManager,
        accountKeyStore: AccountKeyStore,
        messageFactory: Shims.MessageFactory,
        preKeyManager: PreKeyManager,
        profileManager: Shims.ProfileManager,
        pushRegistrationManager: Shims.PushRegistrationManager,
        receiptManager: Shims.ReceiptManager,
        registrationStateChangeManager: RegistrationStateChangeManager,
        signalProtocolStoreManager: SignalProtocolStoreManager,
        signalService: OWSSignalServiceProtocol,
        storageServiceManager: StorageServiceManager,
        svr: SecureValueRecovery,
        syncManager: Shims.SyncManager,
        threadStore: ThreadStore,
        tsAccountManager: TSAccountManager,
        udManager: Shims.UDManager
    ) {
        self.chatConnectionManager = chatConnectionManager
        self.db = db
        self.deviceService = deviceService
        self.identityManager = identityManager
        self.linkAndSyncManager = linkAndSyncManager
        self.accountKeyStore = accountKeyStore
        self.messageFactory = messageFactory
        self.preKeyManager = preKeyManager
        self.profileManager = profileManager
        self.pushRegistrationManager = pushRegistrationManager
        self.receiptManager = receiptManager
        self.registrationStateChangeManager = registrationStateChangeManager
        self.signalProtocolStoreManager = signalProtocolStoreManager
        self.signalService = signalService
        self.storageServiceManager = storageServiceManager
        self.svr = svr
        self.syncManager = syncManager
        self.threadStore = threadStore
        self.tsAccountManager = tsAccountManager
        self.udManager = udManager
    }

    func completeProvisioning(
        provisionMessage: LinkingProvisioningMessage,
        deviceName: String,
        progressViewModel: LinkAndSyncSecondaryProgressViewModel
    ) async throws(CompleteProvisioningError) {
        // * Primary devices that are re-registering can provision instead as long as either
        // the phone number or aci matches.
        // * Secondary devices _cannot_ be re-linked to primaries with a different aci.
        switch self.tsAccountManager.registrationStateWithMaybeSneakyTransaction {
        case .reregistering(let reregistrationPhoneNumber, let reregistrationAci):
            let acisMatch = reregistrationAci != nil && reregistrationAci == provisionMessage.aci
            let phoneNumbersMatch = reregistrationPhoneNumber == provisionMessage.phoneNumber
            guard acisMatch || phoneNumbersMatch else {
                Logger.warn("Cannot re-link primary a different aci and phone number")
                throw .previouslyLinkedWithDifferentAccount
            }
        case .relinking(_, let relinkingAci):
            if let oldAci = relinkingAci, oldAci != provisionMessage.aci {
                Logger.warn("Cannot re-link with a different aci")
                throw .previouslyLinkedWithDifferentAccount
            }
        default:
            break
        }

        guard let phoneNumber = E164(provisionMessage.phoneNumber) else {
            throw .genericError(OWSAssertionError("Primary E164 isn't valid"))
        }

        let result = try await completeProvisioning_updateCensorshipCircumvention(
            provisionMessage: provisionMessage,
            deviceName: deviceName,
            aci: provisionMessage.aci,
            pni: provisionMessage.pni,
            phoneNumber: phoneNumber
        )

        try await continueFromLinkNSync(
            authedDevice: result.authedDevice,
            ephemeralBackupKey: provisionMessage.ephemeralBackupKey,
            progressViewModel: progressViewModel,
            undoAllPreviousSteps: result.undoBlock
        )
    }

    // MARK: Link'n'Sync

    private class LinkAndSyncError: ProvisioningLinkAndSyncError {
        let error: SecondaryLinkNSyncError
        let ephemeralBackupKey: BackupKey
        let authedDevice: AuthedDevice.Explicit
        let progressViewModel: LinkAndSyncSecondaryProgressViewModel
        let undoAllPreviousSteps: () async throws -> Void
        weak var provisioningCoordinator: ProvisioningCoordinatorImpl?

        init(
            error: SecondaryLinkNSyncError,
            ephemeralBackupKey: BackupKey,
            authedDevice: AuthedDevice.Explicit,
            progressViewModel: LinkAndSyncSecondaryProgressViewModel,
            undoAllPreviousSteps: @escaping () async throws -> Void,
            provisioningCoordinator: ProvisioningCoordinatorImpl
        ) {
            self.error = error
            self.ephemeralBackupKey = ephemeralBackupKey
            self.authedDevice = authedDevice
            self.progressViewModel = progressViewModel
            self.undoAllPreviousSteps = undoAllPreviousSteps
            self.provisioningCoordinator = provisioningCoordinator
        }

        func retryLinkAndSync() async throws(CompleteProvisioningError) {
            guard let provisioningCoordinator else {
                throw .genericError(OWSAssertionError("ProvisioningCoordinator deallocated!"))
            }
            try await provisioningCoordinator.continueFromLinkNSync(
                authedDevice: authedDevice,
                ephemeralBackupKey: ephemeralBackupKey,
                progressViewModel: progressViewModel,
                undoAllPreviousSteps: undoAllPreviousSteps
            )
        }

        func continueWithoutSyncing() async throws(CompleteProvisioningError) {
            guard let provisioningCoordinator else {
                throw .genericError(OWSAssertionError("ProvisioningCoordinator deallocated!"))
            }
            try await provisioningCoordinator.completeProvisioning_nonReversibleSteps(
                authedDevice: authedDevice,
                didLinkNSync: false,
                postLinkNSyncProgress: nil
            )
        }

        func restartProvisioning() async throws {
            try await undoAllPreviousSteps()
        }
    }

    private func continueFromLinkNSync(
        authedDevice: AuthedDevice.Explicit,
        ephemeralBackupKey: BackupKey?,
        progressViewModel: LinkAndSyncSecondaryProgressViewModel,
        undoAllPreviousSteps: @escaping () async throws -> Void
    ) async throws(CompleteProvisioningError) {
        var didLinkNSync = false
        var postLinkNSyncProgress: OWSProgressSource?
        if
            FeatureFlags.linkAndSyncLinkedImport,
            let ephemeralBackupKey
        {
            postLinkNSyncProgress = try await completeProvisioning_linkAndSync(
                ephemeralBackupKey: ephemeralBackupKey,
                authedDevice: authedDevice,
                progressViewModel: progressViewModel,
                undoAllPreviousSteps: undoAllPreviousSteps
            )
            didLinkNSync = true
        }

        try await completeProvisioning_nonReversibleSteps(
            authedDevice: authedDevice,
            didLinkNSync: didLinkNSync,
            postLinkNSyncProgress: postLinkNSyncProgress
        )
    }

    // MARK: - Steps

    struct CompleteProvisioningStepResult {
        let authedDevice: AuthedDevice.Explicit
        var undoBlock: () async throws -> Void

        func withUndoOnFailureStep(_ nextUndoBlock: @escaping () async throws -> Void) -> Self {
            let undoBlock = self.undoBlock
            return CompleteProvisioningStepResult(authedDevice: authedDevice, undoBlock: {
                try await undoBlock()
                try await nextUndoBlock()
            })
        }
    }

    private func completeProvisioning_updateCensorshipCircumvention(
        provisionMessage: LinkingProvisioningMessage,
        deviceName: String,
        aci: Aci,
        pni: Pni,
        phoneNumber: E164
    ) async throws(CompleteProvisioningError) -> CompleteProvisioningStepResult {
        // Update censorship circumvention state as e164 could be changing.
        signalService.updateHasCensoredPhoneNumberDuringProvisioning(phoneNumber)

        return try await completeProvisioning_createPrekeys(
            provisionMessage: provisionMessage,
            deviceName: deviceName,
            aci: aci,
            pni: pni,
            phoneNumber: phoneNumber
        ).withUndoOnFailureStep {
            self.signalService.resetHasCensoredPhoneNumberFromProvisioning()
        }
    }

    private func completeProvisioning_createPrekeys(
        provisionMessage: LinkingProvisioningMessage,
        deviceName: String,
        aci: Aci,
        pni: Pni,
        phoneNumber: E164
    ) async throws(CompleteProvisioningError) -> CompleteProvisioningStepResult {
        let prekeyBundles: RegistrationPreKeyUploadBundles
        do {
            // This should be the last failable thing we do before making the verification
            // request, because if the verification request fails we need to clean up prekey
            // state created by this method.
            // If we did add new (failable) method calls between this and the verification
            // request invocation, we would have to make sure we similarly clean up prekey
            // state if there are failures.
            prekeyBundles = try await self.preKeyManager
                .createPreKeysForProvisioning(
                    aciIdentityKeyPair: provisionMessage.aciIdentityKeyPair.asECKeyPair,
                    pniIdentityKeyPair: provisionMessage.pniIdentityKeyPair.asECKeyPair
                )
                .value
        } catch {
            throw .genericError(error)
        }

        return try await completeProvisioning_createRegistrationIds(
            provisionMessage: provisionMessage,
            deviceName: deviceName,
            aci: aci,
            pni: pni,
            phoneNumber: phoneNumber,
            prekeyBundles: prekeyBundles
        ).withUndoOnFailureStep {
            try await self.preKeyManager.finalizeRegistrationPreKeys(
                prekeyBundles,
                uploadDidSucceed: false
            ).value
        }
    }

    private func completeProvisioning_createRegistrationIds(
        provisionMessage: LinkingProvisioningMessage,
        deviceName: String,
        aci: Aci,
        pni: Pni,
        phoneNumber: E164,
        prekeyBundles: RegistrationPreKeyUploadBundles
    ) async throws(CompleteProvisioningError) -> CompleteProvisioningStepResult {
        let (aciRegistrationId, pniRegistrationId) = await self.db.awaitableWrite { tx in
            return (
                tsAccountManager.getOrGenerateAciRegistrationId(tx: tx),
                tsAccountManager.getOrGeneratePniRegistrationId(tx: tx)
            )
        }

        return try await completeProvisioning_verifyAndLinkOnServer(
            provisionMessage: provisionMessage,
            deviceName: deviceName,
            aci: aci,
            pni: pni,
            phoneNumber: phoneNumber,
            prekeyBundles: prekeyBundles,
            aciRegistrationId: aciRegistrationId,
            pniRegistrationId: pniRegistrationId
        ).withUndoOnFailureStep {
            await self.db.awaitableWrite { tx in
                self.tsAccountManager.wipeRegistrationIdsFromFailedProvisioning(tx: tx)
            }
        }
    }

    private func completeProvisioning_verifyAndLinkOnServer(
        provisionMessage: LinkingProvisioningMessage,
        deviceName: String,
        aci: Aci,
        pni: Pni,
        phoneNumber: E164,
        prekeyBundles: RegistrationPreKeyUploadBundles,
        aciRegistrationId: UInt32,
        pniRegistrationId: UInt32
    ) async throws(CompleteProvisioningError) -> CompleteProvisioningStepResult {
        let apnRegistrationId: RegistrationRequestFactory.ApnRegistrationId?
        let encryptedDeviceName: Data
        do {
            apnRegistrationId = try await getApnRegistrationId()
            encryptedDeviceName = try DeviceNames.encryptDeviceName(
                plaintext: deviceName,
                identityKeyPair: provisionMessage.aciIdentityKeyPair
            )
        } catch {
            throw .genericError(error)
        }

        let authedDevice = try await self.verifyAndLinkOnServer(
            provisionMessage: provisionMessage,
            aci: aci,
            pni: pni,
            phoneNumber: phoneNumber,
            aciRegistrationId: aciRegistrationId,
            pniRegistrationId: pniRegistrationId,
            encryptedDeviceName: encryptedDeviceName,
            apnRegistrationId: apnRegistrationId,
            prekeyBundles: prekeyBundles
        )

        return try await completeProvisioning_setLocalKeys(
            provisionMessage: provisionMessage,
            prekeyBundles: prekeyBundles,
            authedDevice: authedDevice
        ).withUndoOnFailureStep {
            try await self.undoVerifyAndLinkOnServer(authedDevice: authedDevice)
        }
    }

    private func completeProvisioning_setLocalKeys(
        provisionMessage: LinkingProvisioningMessage,
        prekeyBundles: RegistrationPreKeyUploadBundles,
        authedDevice: AuthedDevice.Explicit
    ) async throws(CompleteProvisioningError) -> CompleteProvisioningStepResult {
        let error: CompleteProvisioningError? = await self.db.awaitableWrite { tx in
            self.identityManager.setIdentityKeyPair(
                provisionMessage.aciIdentityKeyPair.asECKeyPair,
                for: .aci,
                tx: tx
            )
            self.identityManager.setIdentityKeyPair(
                provisionMessage.pniIdentityKeyPair.asECKeyPair,
                for: .pni,
                tx: tx
            )

            self.profileManager.setLocalProfileKey(
                provisionMessage.profileKey,
                userProfileWriter: .linking,
                tx: tx
            )

            do {
                try svr.storeKeys(
                    fromProvisioningMessage: provisionMessage,
                    authedDevice: .explicit(authedDevice),
                    tx: tx
                )
            } catch {
                switch error {
                case SVR.KeysError.missingMasterKey:
                    owsFailDebug("Failed to store master key from provisioning message")
                    return .obsoleteLinkedDeviceError
                case SVR.KeysError.missingMediaRootBackupKey:
                    if FeatureFlags.linkAndSyncLinkedImport || FeatureFlags.messageBackupFileAlpha {
                        return .obsoleteLinkedDeviceError
                    } else {
                        Logger.warn("Invalid MRBK; ignoring")
                        owsFailDebug("Failed to store MBRK from provisioning message")
                    }
                default:
                    owsFailDebug("Unexpected Error")
                }
            }

            self.receiptManager.setAreReadReceiptsEnabled(
                provisionMessage.areReadReceiptsEnabled,
                tx: tx
            )

            return nil
        }
        if let error {
            throw error
        }

        return try await completeProvisioning_finalizePrekeys(
            provisionMessage: provisionMessage,
            prekeyBundles: prekeyBundles,
            authedDevice: authedDevice
        ).withUndoOnFailureStep {
            await self.db.awaitableWrite { tx in
                self.identityManager.wipeIdentityKeysFromFailedProvisioning(tx: tx)

                // Set to a random value (we never set it to nil)
                self.profileManager.setLocalProfileKey(
                    Aes256Key.generateRandom(),
                    userProfileWriter: .linking,
                    tx: tx
                )
                self.svr.clearKeys(transaction: tx)

                // reset to default (false)
                self.receiptManager.setAreReadReceiptsEnabled(
                    false,
                    tx: tx
                )

                self.accountKeyStore.wipeMediaRootBackupKeyFromFailedProvisioning(tx: tx)
            }
        }
    }

    private func completeProvisioning_finalizePrekeys(
        provisionMessage: LinkingProvisioningMessage,
        prekeyBundles: RegistrationPreKeyUploadBundles,
        authedDevice: AuthedDevice.Explicit
    ) async throws(CompleteProvisioningError) -> CompleteProvisioningStepResult {
        do {
            try await self.preKeyManager
                .finalizeRegistrationPreKeys(prekeyBundles, uploadDidSucceed: true)
                .value
            try await self.preKeyManager
                .rotateOneTimePreKeysForRegistration(auth: authedDevice.authedAccount.chatServiceAuth)
                .value
        } catch {
            throw .genericError(error)
        }

        return CompleteProvisioningStepResult(
            authedDevice: authedDevice,
            undoBlock: {
                await self.db.awaitableWrite { tx in
                    self.signalProtocolStoreManager.removeAllKeys(tx: tx)
                }
            }
        )
    }

    // MARK: -

    private func completeProvisioning_linkAndSync(
        ephemeralBackupKey: BackupKey,
        authedDevice: AuthedDevice.Explicit,
        progressViewModel: LinkAndSyncSecondaryProgressViewModel,
        undoAllPreviousSteps: @escaping () async throws -> Void
    ) async throws(CompleteProvisioningError) -> OWSProgressSource? {
        let progress = OWSProgress.createSink { progress in
            Task { @MainActor in
                progressViewModel.updateProgress(progress)
            }
        }
        let linkNSyncProgress = await progress.addChild(
            withLabel: LocalizationNotNeeded("Link'n'sync"),
            unitCount: 99
        )

        let postLinkNSyncProgress = await progress.addSource(
            withLabel: LocalizationNotNeeded("Post-link'n'sync"),
            unitCount: 1
        )

        do {
            try await self.linkAndSyncManager.waitForBackupAndRestore(
                localIdentifiers: authedDevice.localIdentifiers,
                auth: authedDevice.authedAccount.chatServiceAuth,
                ephemeralBackupKey: ephemeralBackupKey,
                progress: linkNSyncProgress
            )
            return postLinkNSyncProgress
        } catch let error {
            Logger.error("Failed link'n'sync \(error)")
            throw .linkAndSyncError(LinkAndSyncError(
                error: error,
                ephemeralBackupKey: ephemeralBackupKey,
                authedDevice: authedDevice,
                progressViewModel: progressViewModel,
                undoAllPreviousSteps: undoAllPreviousSteps,
                provisioningCoordinator: self
            ))
        }
    }

    // MARK: -

    private func completeProvisioning_nonReversibleSteps(
        authedDevice: AuthedDevice.Explicit,
        didLinkNSync: Bool,
        postLinkNSyncProgress: OWSProgressSource?
    ) async throws(CompleteProvisioningError) {
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
            throw .genericError(error)
        }

        await self.db.awaitableWrite { tx in
            self.registrationStateChangeManager.didProvisionSecondary(
                e164: authedDevice.phoneNumber,
                aci: authedDevice.aci,
                pni: authedDevice.pni,
                authToken: authedDevice.authPassword,
                deviceId: authedDevice.deviceId,
                tx: tx
            )
        }

        if let postLinkNSyncProgress {
            return try await postLinkNSyncProgress.updatePeriodically(
                timeInterval: 0.1,
                estimatedTimeToCompletion: 5,
                work: { () throws(CompleteProvisioningError) -> Void in
                    return try await self.performNecessarySyncsAndRestores(
                        authedDevice: authedDevice,
                        didLinkNSync: didLinkNSync
                    )
                }
            )
        } else {
            return try await performNecessarySyncsAndRestores(
                authedDevice: authedDevice,
                didLinkNSync: didLinkNSync
            )
        }
    }

    private func performNecessarySyncsAndRestores(
        authedDevice: AuthedDevice.Explicit,
        didLinkNSync: Bool
    ) async throws(CompleteProvisioningError) {
        func doSyncsAndRestores() async throws(CompleteProvisioningError) {
            try await performInitialStorageServiceRestore(authedDevice: .explicit(authedDevice))
            try await performInitialContactSync(didLinkNSync: didLinkNSync)
        }

        if didLinkNSync {
            // Because link'n'sync gives us basic contact info, we don't
            // block on a contact sync after doing one. We still do the
            // contact sync in the background to get contact avatars.
            Task {
                try await doSyncsAndRestores()
            }
        } else {
            try await doSyncsAndRestores()
        }
    }

    private func performInitialStorageServiceRestore(
        authedDevice: AuthedDevice
    ) async throws(CompleteProvisioningError) {
        do {
            try await self.storageServiceManager
                .restoreOrCreateManifestIfNecessary(authedDevice: authedDevice, masterKeySource: .implicit)
                .timeout(seconds: 60, substituteValue: ())
                .awaitable()
        } catch {
            throw .genericError(error)
        }
    }

    private func performInitialContactSync(didLinkNSync: Bool) async throws(CompleteProvisioningError) {
        // we wait a bit for the initial syncs to come in before proceeding to the inbox
        // because we want to present the inbox already populated with groups and contacts,
        // rather than have the trickle in moments later.
        // NOTE: in practice...groups do trickle in later, as of the time of this comment.
        // TODO: Eventually, we can rely entirely on the storage service and will no longer
        // need to do any initial sync. For now, we try and do both operations in parallel.

        let orderedThreadIds: [String]
        do {
            orderedThreadIds = try await syncManager
                .sendInitialSyncRequestsAwaitingCreatedThreadOrdering(timeout: 60)
        } catch {
            throw .genericError(error)
        }

        if !didLinkNSync {
            // Maintain the remote sort ordering of threads by inserting `syncedThread` messages
            // in that thread order. Don't do this if we link'n'synced.
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
    }

    // MARK: Network steps

    private func verifyAndLinkOnServer(
        provisionMessage: LinkingProvisioningMessage,
        aci: Aci,
        pni: Pni,
        phoneNumber: E164,
        aciRegistrationId: UInt32,
        pniRegistrationId: UInt32,
        encryptedDeviceName: Data,
        apnRegistrationId: RegistrationRequestFactory.ApnRegistrationId?,
        prekeyBundles: RegistrationPreKeyUploadBundles
    ) async throws(CompleteProvisioningError) -> AuthedDevice.Explicit {
        let serverAuthToken = generateServerAuthToken()

        let accountAttributes = self.db.read { tx in
            return self.makeAccountAttributes(
                encryptedDeviceName: encryptedDeviceName,
                profileKey: provisionMessage.profileKey,
                aciRegistrationId: aciRegistrationId,
                pniRegistrationId: pniRegistrationId,
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
            throw .genericError(error)
        case .obsoleteLinkedDevice:
            throw .obsoleteLinkedDeviceError
        case .deviceLimitExceeded(let error):
            throw .deviceLimitExceededError(error)
        case .success(let response):
            verifyDeviceResponse = response
        }
        if pni != verifyDeviceResponse.pni {
            throw .genericError(OWSAssertionError("PNI from primary is out of sync with the server!"))
        }
        if verifyDeviceResponse.deviceId.isPrimary {
            throw .genericError(OWSAssertionError("Server is trying to link device as primary!"))
        }

        let authedDevice = AuthedDevice.Explicit(
            aci: aci,
            phoneNumber: phoneNumber,
            pni: pni,
            deviceId: verifyDeviceResponse.deviceId,
            authPassword: serverAuthToken
        )
        return authedDevice
    }

    private func undoVerifyAndLinkOnServer(authedDevice: AuthedDevice.Explicit) async throws(CompleteProvisioningError) {
        do {
            try await deviceService.unlinkDevice(deviceId: authedDevice.deviceId, auth: authedDevice.authedAccount.chatServiceAuth)
        } catch {
            throw .genericError(error)
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
        profileKey: Aes256Key,
        aciRegistrationId: UInt32,
        pniRegistrationId: UInt32,
        tx: DBReadTransaction
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

        let udAccessKey = SMKUDAccessKey(profileKey: profileKey).keyData.base64EncodedString()
        let allowUnrestrictedUD = udManager.shouldAllowUnrestrictedAccessLocal(tx: tx)

        // Historical note: secondary device registration uses the same AccountAttributes object,
        // but some fields, like reglock and pin, are ignored by the server.
        // Don't bother with this field at all; just put explicit none.
        let twoFaMode: AccountAttributes.TwoFactorAuthMode = .none

        let registrationRecoveryPassword = accountKeyStore.getMasterKey(tx: tx)?.data(
            for: .registrationRecoveryPassword
        ).canonicalStringRepresentation

        let encryptedDeviceName = encryptedDeviceNameRaw.base64EncodedString()

        let phoneNumberDiscoverability = tsAccountManager.phoneNumberDiscoverability(tx: tx)

        let hasSVRBackups = svr.hasBackedUpMasterKey(transaction: tx)

        return AccountAttributes(
            isManualMessageFetchEnabled: isManualMessageFetchEnabled,
            registrationId: aciRegistrationId,
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
        return Randomness.generateRandomBytes(16).hexadecimalString
    }
}
