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
    private let identityManager: OWSIdentityManager
    private let linkAndSyncManager: LinkAndSyncManager
    private let accountKeyStore: AccountKeyStore
    private let networkManager: any NetworkManagerProtocol
    private let preKeyManager: PreKeyManager
    private let profileManager: ProfileManager
    private let pushRegistrationManager: Shims.PushRegistrationManager
    private let receiptManager: Shims.ReceiptManager
    private let registrationStateChangeManager: RegistrationStateChangeManager
    private let registrationWebSocketManager: any RegistrationWebSocketManager
    private let signalProtocolStoreManager: SignalProtocolStoreManager
    private let signalService: OWSSignalServiceProtocol
    private let storageServiceManager: StorageServiceManager
    private let svr: SecureValueRecovery
    private let syncManager: SyncManagerProtocol
    private let threadStore: ThreadStore
    private let tsAccountManager: TSAccountManager
    private let udManager: OWSUDManager

    init(
        chatConnectionManager: ChatConnectionManager,
        db: any DB,
        identityManager: OWSIdentityManager,
        linkAndSyncManager: LinkAndSyncManager,
        accountKeyStore: AccountKeyStore,
        networkManager: any NetworkManagerProtocol,
        preKeyManager: PreKeyManager,
        profileManager: ProfileManager,
        pushRegistrationManager: Shims.PushRegistrationManager,
        receiptManager: Shims.ReceiptManager,
        registrationStateChangeManager: RegistrationStateChangeManager,
        registrationWebSocketManager: any RegistrationWebSocketManager,
        signalProtocolStoreManager: SignalProtocolStoreManager,
        signalService: OWSSignalServiceProtocol,
        storageServiceManager: StorageServiceManager,
        svr: SecureValueRecovery,
        syncManager: SyncManagerProtocol,
        threadStore: ThreadStore,
        tsAccountManager: TSAccountManager,
        udManager: OWSUDManager,
    ) {
        self.chatConnectionManager = chatConnectionManager
        self.db = db
        self.identityManager = identityManager
        self.linkAndSyncManager = linkAndSyncManager
        self.accountKeyStore = accountKeyStore
        self.networkManager = networkManager
        self.preKeyManager = preKeyManager
        self.profileManager = profileManager
        self.pushRegistrationManager = pushRegistrationManager
        self.receiptManager = receiptManager
        self.registrationStateChangeManager = registrationStateChangeManager
        self.registrationWebSocketManager = registrationWebSocketManager
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
        progressViewModel: LinkAndSyncSecondaryProgressViewModel,
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
            phoneNumber: phoneNumber,
        )

        try await continueFromLinkNSync(
            authedDevice: result.authedDevice,
            ephemeralBackupKey: provisionMessage.ephemeralBackupKey,
            progressViewModel: progressViewModel,
            undoAllPreviousSteps: result.undoBlock,
        )
    }

    // MARK: Link'n'Sync

    private class LinkAndSyncError: ProvisioningLinkAndSyncError {
        let error: SecondaryLinkNSyncError
        let ephemeralBackupKey: MessageRootBackupKey
        let authedDevice: AuthedDevice.Explicit
        let progressViewModel: LinkAndSyncSecondaryProgressViewModel
        let undoAllPreviousSteps: () async throws -> Void
        weak var provisioningCoordinator: ProvisioningCoordinatorImpl?

        init(
            error: SecondaryLinkNSyncError,
            ephemeralBackupKey: MessageRootBackupKey,
            authedDevice: AuthedDevice.Explicit,
            progressViewModel: LinkAndSyncSecondaryProgressViewModel,
            undoAllPreviousSteps: @escaping () async throws -> Void,
            provisioningCoordinator: ProvisioningCoordinatorImpl,
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
                undoAllPreviousSteps: undoAllPreviousSteps,
            )
        }

        func continueWithoutSyncing() async throws(CompleteProvisioningError) {
            guard let provisioningCoordinator else {
                throw .genericError(OWSAssertionError("ProvisioningCoordinator deallocated!"))
            }
            try await provisioningCoordinator.completeProvisioning_nonReversibleSteps(
                authedDevice: authedDevice,
                didLinkNSync: false,
            )
        }

        func restartProvisioning() async throws {
            try await undoAllPreviousSteps()
        }
    }

    private func continueFromLinkNSync(
        authedDevice: AuthedDevice.Explicit,
        ephemeralBackupKey: MessageRootBackupKey?,
        progressViewModel: LinkAndSyncSecondaryProgressViewModel,
        undoAllPreviousSteps: @escaping () async throws -> Void,
    ) async throws(CompleteProvisioningError) {
        var didLinkNSync = false
        if let ephemeralBackupKey {
            try await completeProvisioning_linkAndSync(
                ephemeralBackupKey: ephemeralBackupKey,
                authedDevice: authedDevice,
                progressViewModel: progressViewModel,
                undoAllPreviousSteps: undoAllPreviousSteps,
            )
            didLinkNSync = true
        }

        try await completeProvisioning_nonReversibleSteps(
            authedDevice: authedDevice,
            didLinkNSync: didLinkNSync,
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
        phoneNumber: E164,
    ) async throws(CompleteProvisioningError) -> CompleteProvisioningStepResult {
        // Update censorship circumvention state as e164 could be changing.
        signalService.updateHasCensoredPhoneNumberDuringProvisioning(phoneNumber)

        return try await completeProvisioning_createPrekeys(
            provisionMessage: provisionMessage,
            deviceName: deviceName,
            aci: aci,
            pni: pni,
            phoneNumber: phoneNumber,
        ).withUndoOnFailureStep {
            self.signalService.resetHasCensoredPhoneNumberFromProvisioning()
        }
    }

    private func completeProvisioning_createPrekeys(
        provisionMessage: LinkingProvisioningMessage,
        deviceName: String,
        aci: Aci,
        pni: Pni,
        phoneNumber: E164,
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
                    pniIdentityKeyPair: provisionMessage.pniIdentityKeyPair.asECKeyPair,
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
            prekeyBundles: prekeyBundles,
        ).withUndoOnFailureStep {
            try await self.preKeyManager.finalizeRegistrationPreKeys(
                prekeyBundles,
                uploadDidSucceed: false,
            ).value
        }
    }

    private func completeProvisioning_createRegistrationIds(
        provisionMessage: LinkingProvisioningMessage,
        deviceName: String,
        aci: Aci,
        pni: Pni,
        phoneNumber: E164,
        prekeyBundles: RegistrationPreKeyUploadBundles,
    ) async throws(CompleteProvisioningError) -> CompleteProvisioningStepResult {
        return try await completeProvisioning_verifyAndLinkOnServer(
            provisionMessage: provisionMessage,
            deviceName: deviceName,
            aci: aci,
            pni: pni,
            phoneNumber: phoneNumber,
            prekeyBundles: prekeyBundles,
            aciRegistrationId: RegistrationIdGenerator.generate(),
            pniRegistrationId: RegistrationIdGenerator.generate(),
        ).withUndoOnFailureStep {
            await self.db.awaitableWrite { tx in
                self.tsAccountManager.clearRegistrationIds(tx: tx)
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
        pniRegistrationId: UInt32,
    ) async throws(CompleteProvisioningError) -> CompleteProvisioningStepResult {
        let apnRegistrationId: RegistrationRequestFactory.ApnRegistrationId?
        let encryptedDeviceName: Data
        do {
            apnRegistrationId = try await getApnRegistrationId()
            encryptedDeviceName = try OWSDeviceNames.encryptDeviceName(
                plaintext: deviceName,
                identityKeyPair: provisionMessage.aciIdentityKeyPair,
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
            prekeyBundles: prekeyBundles,
        )

        await registrationWebSocketManager.acquireRestrictedWebSocket(
            chatServiceAuth: authedDevice.authedAccount.chatServiceAuth,
        )

        return try await completeProvisioning_setLocalKeys(
            provisionMessage: provisionMessage,
            prekeyBundles: prekeyBundles,
            authedDevice: authedDevice,
            aciRegistrationId: aciRegistrationId,
            pniRegistrationId: pniRegistrationId,
        ).withUndoOnFailureStep {
            try await self.undoVerifyAndLinkOnServer(authedDevice: authedDevice)
        }
    }

    private func completeProvisioning_setLocalKeys(
        provisionMessage: LinkingProvisioningMessage,
        prekeyBundles: RegistrationPreKeyUploadBundles,
        authedDevice: AuthedDevice.Explicit,
        aciRegistrationId: UInt32,
        pniRegistrationId: UInt32,
    ) async throws(CompleteProvisioningError) -> CompleteProvisioningStepResult {
        let error: CompleteProvisioningError? = await self.db.awaitableWrite { tx in
            self.identityManager.setIdentityKeyPair(
                provisionMessage.aciIdentityKeyPair.asECKeyPair,
                for: .aci,
                tx: tx,
            )
            self.identityManager.setIdentityKeyPair(
                provisionMessage.pniIdentityKeyPair.asECKeyPair,
                for: .pni,
                tx: tx,
            )

            self.profileManager.setLocalProfileKey(
                provisionMessage.profileKey,
                userProfileWriter: .linking,
                transaction: tx,
            )

            self.tsAccountManager.setRegistrationId(aciRegistrationId, for: .aci, tx: tx)
            self.tsAccountManager.setRegistrationId(pniRegistrationId, for: .pni, tx: tx)

            do {
                try svr.storeKeys(
                    fromProvisioningMessage: provisionMessage,
                    authedDevice: .explicit(authedDevice),
                    tx: tx,
                )
            } catch {
                switch error {
                case SVR.KeysError.missingMasterKey:
                    owsFailDebug("Failed to store master key from provisioning message")
                    return .obsoleteLinkedDeviceError
                case SVR.KeysError.missingOrInvalidMRBK:
                    return .obsoleteLinkedDeviceError
                default:
                    owsFailDebug("Unexpected Error")
                }
            }

            self.receiptManager.setAreReadReceiptsEnabled(
                provisionMessage.areReadReceiptsEnabled,
                tx: tx,
            )

            return nil
        }
        if let error {
            throw error
        }

        return try await completeProvisioning_finalizePrekeys(
            provisionMessage: provisionMessage,
            prekeyBundles: prekeyBundles,
            authedDevice: authedDevice,
        ).withUndoOnFailureStep {
            await self.db.awaitableWrite { tx in
                self.identityManager.wipeIdentityKeysFromFailedProvisioning(tx: tx)

                // Set to a random value (we never set it to nil)
                self.profileManager.setLocalProfileKey(
                    Aes256Key.generateRandom(),
                    userProfileWriter: .linking,
                    transaction: tx,
                )
                self.svr.clearKeys(transaction: tx)

                // reset to default (false)
                self.receiptManager.setAreReadReceiptsEnabled(
                    false,
                    tx: tx,
                )

                self.accountKeyStore.wipeMediaRootBackupKeyFromFailedProvisioning(tx: tx)
            }
        }
    }

    private func completeProvisioning_finalizePrekeys(
        provisionMessage: LinkingProvisioningMessage,
        prekeyBundles: RegistrationPreKeyUploadBundles,
        authedDevice: AuthedDevice.Explicit,
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
            },
        )
    }

    // MARK: -

    private func completeProvisioning_linkAndSync(
        ephemeralBackupKey: MessageRootBackupKey,
        authedDevice: AuthedDevice.Explicit,
        progressViewModel: LinkAndSyncSecondaryProgressViewModel,
        undoAllPreviousSteps: @escaping () async throws -> Void,
    ) async throws(CompleteProvisioningError) {
        let linkNSyncProgress = await OWSSequentialProgress<SecondaryLinkNSyncProgressPhase>.createSink { progress in
            await MainActor.run {
                progressViewModel.updateProgress(progress)
            }
        }

        do {
            try await self.linkAndSyncManager.waitForBackupAndRestore(
                localIdentifiers: authedDevice.localIdentifiers,
                auth: authedDevice.authedAccount.chatServiceAuth,
                ephemeralBackupKey: ephemeralBackupKey,
                progress: linkNSyncProgress,
            )
        } catch let error {
            Logger.error("Failed link'n'sync \(error)")
            throw .linkAndSyncError(LinkAndSyncError(
                error: error,
                ephemeralBackupKey: ephemeralBackupKey,
                authedDevice: authedDevice,
                progressViewModel: progressViewModel,
                undoAllPreviousSteps: undoAllPreviousSteps,
                provisioningCoordinator: self,
            ))
        }
    }

    // MARK: -

    private func completeProvisioning_nonReversibleSteps(
        authedDevice: AuthedDevice.Explicit,
        didLinkNSync: Bool,
    ) async throws(CompleteProvisioningError) {
        let hasBackedUpMasterKey = self.db.read { tx in
            self.svr.hasBackedUpMasterKey(transaction: tx)
        }
        let capabilities = AccountAttributes.Capabilities(hasSVRBackups: hasBackedUpMasterKey)
        do {
            try await Service.makeUpdateSecondaryDeviceCapabilitiesRequest(
                capabilities: capabilities,
                auth: authedDevice.authedAccount.chatServiceAuth,
                networkManager: self.networkManager,
                tsAccountManager: self.tsAccountManager,
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
                tx: tx,
            )
        }

        await registrationWebSocketManager.releaseRestrictedWebSocket(isRegistered: true)

        return try await performNecessarySyncsAndRestores(
            authedDevice: authedDevice,
            didLinkNSync: didLinkNSync,
        )
    }

    private func performNecessarySyncsAndRestores(
        authedDevice: AuthedDevice.Explicit,
        didLinkNSync: Bool,
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
        authedDevice: AuthedDevice,
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
                .sendInitialSyncRequestsAwaitingCreatedThreadOrdering(timeoutSeconds: 60).awaitable()
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
                    let infoMessage = TSInfoMessage(thread: thread, messageType: .syncedThread)
                    infoMessage.anyInsert(transaction: tx)
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
        prekeyBundles: RegistrationPreKeyUploadBundles,
    ) async throws(CompleteProvisioningError) -> AuthedDevice.Explicit {
        let serverAuthToken = generateServerAuthToken()

        let accountAttributes = self.db.read { tx in
            return self.makeAccountAttributes(
                encryptedDeviceName: encryptedDeviceName,
                isManualMessageFetchEnabled: apnRegistrationId == nil,
                profileKey: provisionMessage.profileKey,
                aciRegistrationId: aciRegistrationId,
                pniRegistrationId: pniRegistrationId,
                tx: tx,
            )
        }

        let rawVerifyDeviceResponse = await Self.Service.makeVerifySecondaryDeviceRequest(
            verificationCode: provisionMessage.provisioningCode,
            phoneNumber: provisionMessage.phoneNumber,
            authPassword: serverAuthToken,
            accountAttributes: accountAttributes,
            apnRegistrationId: apnRegistrationId,
            prekeyBundles: prekeyBundles,
            signalService: self.signalService,
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
            authPassword: serverAuthToken,
        )
        return authedDevice
    }

    private func undoVerifyAndLinkOnServer(authedDevice: AuthedDevice.Explicit) async throws(CompleteProvisioningError) {
        do {
            try await registrationStateChangeManager.unlinkLocalDevice(
                localDeviceId: .valid(authedDevice.deviceId),
                auth: authedDevice.authedAccount.chatServiceAuth,
            )
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
        isManualMessageFetchEnabled: Bool,
        profileKey: Aes256Key,
        aciRegistrationId: UInt32,
        pniRegistrationId: UInt32,
        tx: DBReadTransaction,
    ) -> AccountAttributes {
        let udAccessKey = SMKUDAccessKey(profileKey: profileKey).keyData.base64EncodedString()
        let allowUnrestrictedUD = udManager.shouldAllowUnrestrictedAccessLocal(transaction: tx)

        // Linked-device provisioning uses the same AccountAttributes object as
        // primary-device registration; however, the reglock token is ignored by
        // the server.
        let reglockToken: String? = nil

        let registrationRecoveryPassword = accountKeyStore.getMasterKey(tx: tx)?.data(
            for: .registrationRecoveryPassword,
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
            reglockToken: reglockToken,
            registrationRecoveryPassword: registrationRecoveryPassword,
            encryptedDeviceName: encryptedDeviceName,
            discoverableByPhoneNumber: phoneNumberDiscoverability,
            capabilities: AccountAttributes.Capabilities(hasSVRBackups: hasSVRBackups),
        )
    }

    private func generateServerAuthToken() -> String {
        return Randomness.generateRandomBytes(16).hexadecimalString
    }
}
