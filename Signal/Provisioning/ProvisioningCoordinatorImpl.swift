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
        let oldLocalIdentifiers: ReregisteringLocalIdentifiers?
        switch self.tsAccountManager.registrationStateWithMaybeSneakyTransaction {
        case .reregistering(let localIdentifiers):
            oldLocalIdentifiers = localIdentifiers
            let oldPhoneNumber: String = localIdentifiers.phoneNumber
            guard oldPhoneNumber == provisionMessage.phoneNumberState.phoneNumber.e164.stringValue else {
                Logger.warn("can't re-link primary a different phone number")
                throw .previouslyLinkedWithDifferentAccount
            }
        case .relinking(let localIdentifiers):
            oldLocalIdentifiers = localIdentifiers
        default:
            oldLocalIdentifiers = nil
        }

        if let oldAci = oldLocalIdentifiers?.aci {
            guard oldAci == provisionMessage.aci else {
                Logger.warn("can't re-link with a different aci")
                throw .previouslyLinkedWithDifferentAccount
            }
        }

        let result = try await completeProvisioning_updateCensorshipCircumvention(
            provisionMessage: provisionMessage,
            deviceName: deviceName,
        )

        try await continueFromLinkNSync(
            authedAccount: result.authedAccount,
            ephemeralBackupKey: provisionMessage.ephemeralBackupKey,
            progressViewModel: progressViewModel,
            undoAllPreviousSteps: result.undoBlock,
        )
    }

    // MARK: Link'n'Sync

    class LinkAndSyncError {
        let error: any Error
        let ephemeralBackupKey: MessageRootBackupKey
        let authedAccount: AuthedAccount.Explicit
        let progressViewModel: LinkAndSyncSecondaryProgressViewModel
        let undoAllPreviousSteps: () async throws -> Void
        weak var provisioningCoordinator: ProvisioningCoordinatorImpl?

        init(
            error: any Error,
            ephemeralBackupKey: MessageRootBackupKey,
            authedAccount: AuthedAccount.Explicit,
            progressViewModel: LinkAndSyncSecondaryProgressViewModel,
            undoAllPreviousSteps: @escaping () async throws -> Void,
            provisioningCoordinator: ProvisioningCoordinatorImpl,
        ) {
            self.error = error
            self.ephemeralBackupKey = ephemeralBackupKey
            self.authedAccount = authedAccount
            self.progressViewModel = progressViewModel
            self.undoAllPreviousSteps = undoAllPreviousSteps
            self.provisioningCoordinator = provisioningCoordinator
        }

        func retryLinkAndSync() async throws(CompleteProvisioningError) {
            guard let provisioningCoordinator else {
                throw .genericError(OWSAssertionError("ProvisioningCoordinator deallocated!"))
            }
            try await provisioningCoordinator.continueFromLinkNSync(
                authedAccount: authedAccount,
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
                authedAccount: authedAccount,
                didLinkNSync: false,
            )
        }

        func restartProvisioning() async throws {
            try await undoAllPreviousSteps()
        }
    }

    private func continueFromLinkNSync(
        authedAccount: AuthedAccount.Explicit,
        ephemeralBackupKey: MessageRootBackupKey?,
        progressViewModel: LinkAndSyncSecondaryProgressViewModel,
        undoAllPreviousSteps: @escaping () async throws -> Void,
    ) async throws(CompleteProvisioningError) {
        var didLinkNSync = false
        if let ephemeralBackupKey {
            try await completeProvisioning_linkAndSync(
                ephemeralBackupKey: ephemeralBackupKey,
                authedAccount: authedAccount,
                progressViewModel: progressViewModel,
                undoAllPreviousSteps: undoAllPreviousSteps,
            )
            didLinkNSync = true
        }

        try await completeProvisioning_nonReversibleSteps(
            authedAccount: authedAccount,
            didLinkNSync: didLinkNSync,
        )
    }

    // MARK: - Steps

    struct CompleteProvisioningStepResult {
        let authedAccount: AuthedAccount.Explicit
        var undoBlock: () async throws -> Void

        func withUndoOnFailureStep(_ nextUndoBlock: @escaping () async throws -> Void) -> Self {
            let undoBlock = self.undoBlock
            return CompleteProvisioningStepResult(authedAccount: authedAccount, undoBlock: {
                try await undoBlock()
                try await nextUndoBlock()
            })
        }
    }

    private func completeProvisioning_updateCensorshipCircumvention(
        provisionMessage: LinkingProvisioningMessage,
        deviceName: String,
    ) async throws(CompleteProvisioningError) -> CompleteProvisioningStepResult {
        // Update censorship circumvention state as e164 could be changing.
        signalService.updateHasCensoredPhoneNumberDuringProvisioning(provisionMessage.phoneNumberState.phoneNumber.e164)

        return try await completeProvisioning_createPreKeys(
            provisionMessage: provisionMessage,
            deviceName: deviceName,
        ).withUndoOnFailureStep {
            self.signalService.resetHasCensoredPhoneNumberFromProvisioning()
        }
    }

    private func completeProvisioning_createPreKeys(
        provisionMessage: LinkingProvisioningMessage,
        deviceName: String,
    ) async throws(CompleteProvisioningError) -> CompleteProvisioningStepResult {
        let aciPreKeyBundle = await self.preKeyManager.createPreKeysForProvisioning(
            forIdentity: .aci,
            keyPair: provisionMessage.aciIdentityKeyPair,
        )
        let pniPreKeyBundle = await self.preKeyManager.createPreKeysForProvisioning(
            forIdentity: .pni,
            keyPair: provisionMessage.phoneNumberState.pniIdentityKeyPair,
        )

        return try await completeProvisioning_createRegistrationIds(
            provisionMessage: provisionMessage,
            deviceName: deviceName,
            aciPreKeyBundle: aciPreKeyBundle,
            pniPreKeyBundle: pniPreKeyBundle,
        ).withUndoOnFailureStep {
            await self.preKeyManager.finalizeRegistrationPreKeyBundle(
                aciPreKeyBundle,
                uploadDidSucceed: false,
            )
            await self.preKeyManager.finalizeRegistrationPreKeyBundle(
                pniPreKeyBundle,
                uploadDidSucceed: false,
            )
        }
    }

    private func completeProvisioning_createRegistrationIds(
        provisionMessage: LinkingProvisioningMessage,
        deviceName: String,
        aciPreKeyBundle: RegistrationPreKeyUploadBundle,
        pniPreKeyBundle: RegistrationPreKeyUploadBundle,
    ) async throws(CompleteProvisioningError) -> CompleteProvisioningStepResult {
        return try await completeProvisioning_verifyAndLinkOnServer(
            provisionMessage: provisionMessage,
            deviceName: deviceName,
            aciPreKeyBundle: aciPreKeyBundle,
            pniPreKeyBundle: pniPreKeyBundle,
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
        aciPreKeyBundle: RegistrationPreKeyUploadBundle,
        pniPreKeyBundle: RegistrationPreKeyUploadBundle,
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

        let authedAccount = try await self.verifyAndLinkOnServer(
            provisionMessage: provisionMessage,
            aciPreKeyBundle: aciPreKeyBundle,
            pniPreKeyBundle: pniPreKeyBundle,
            aciRegistrationId: aciRegistrationId,
            pniRegistrationId: pniRegistrationId,
            encryptedDeviceName: encryptedDeviceName,
            apnRegistrationId: apnRegistrationId,
        )

        await registrationWebSocketManager.acquireRestrictedWebSocket(
            chatServiceAuth: authedAccount.chatServiceAuth,
        )

        return try await completeProvisioning_setLocalKeys(
            provisionMessage: provisionMessage,
            aciPreKeyBundle: aciPreKeyBundle,
            pniPreKeyBundle: pniPreKeyBundle,
            authedAccount: authedAccount,
            aciRegistrationId: aciRegistrationId,
            pniRegistrationId: pniRegistrationId,
        ).withUndoOnFailureStep {
            try await self.undoVerifyAndLinkOnServer(authedAccount: authedAccount)
        }
    }

    private func completeProvisioning_setLocalKeys(
        provisionMessage: LinkingProvisioningMessage,
        aciPreKeyBundle: RegistrationPreKeyUploadBundle,
        pniPreKeyBundle: RegistrationPreKeyUploadBundle,
        authedAccount: AuthedAccount.Explicit,
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
                provisionMessage.phoneNumberState.pniIdentityKeyPair.asECKeyPair,
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

            self.svr.storeKeys(
                fromProvisioningMessage: provisionMessage,
                authedAccount: .explicit(authedAccount),
                tx: tx,
            )

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
            aciPreKeyBundle: aciPreKeyBundle,
            pniPreKeyBundle: pniPreKeyBundle,
            authedAccount: authedAccount,
        ).withUndoOnFailureStep {
            await self.db.awaitableWrite { tx in
                self.identityManager.wipeIdentityKeysFromFailedProvisioning(tx: tx)

                // Set to a random value (we never set it to nil)
                self.profileManager.setLocalProfileKey(
                    Aes256Key.generateRandom(),
                    userProfileWriter: .linking,
                    transaction: tx,
                )

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
        aciPreKeyBundle: RegistrationPreKeyUploadBundle,
        pniPreKeyBundle: RegistrationPreKeyUploadBundle,
        authedAccount: AuthedAccount.Explicit,
    ) async throws(CompleteProvisioningError) -> CompleteProvisioningStepResult {
        await self.preKeyManager.finalizeRegistrationPreKeyBundle(aciPreKeyBundle, uploadDidSucceed: true)
        await self.preKeyManager.finalizeRegistrationPreKeyBundle(pniPreKeyBundle, uploadDidSucceed: true)
        do {
            try await self.preKeyManager
                .rotateOneTimePreKeysForRegistration(auth: authedAccount.chatServiceAuth)
        } catch {
            throw .genericError(error)
        }

        return CompleteProvisioningStepResult(
            authedAccount: authedAccount,
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
        authedAccount: AuthedAccount.Explicit,
        progressViewModel: LinkAndSyncSecondaryProgressViewModel,
        undoAllPreviousSteps: @escaping () async throws -> Void,
    ) async throws(CompleteProvisioningError) {
        let linkNSyncProgress = OWSSequentialProgress<SecondaryLinkNSyncProgressPhase>.createSink { progress in
            await MainActor.run {
                progressViewModel.updateProgress(progress)
            }
        }

        do {
            try await self.linkAndSyncManager.waitForBackupAndRestore(
                localIdentifiers: authedAccount.localIdentifiers,
                auth: authedAccount.chatServiceAuth,
                ephemeralBackupKey: ephemeralBackupKey,
                progress: linkNSyncProgress,
            )
        } catch {
            Logger.warn("Failed link'n'sync \(error)")
            throw .linkAndSyncError(LinkAndSyncError(
                error: error,
                ephemeralBackupKey: ephemeralBackupKey,
                authedAccount: authedAccount,
                progressViewModel: progressViewModel,
                undoAllPreviousSteps: undoAllPreviousSteps,
                provisioningCoordinator: self,
            ))
        }
    }

    // MARK: -

    private func completeProvisioning_nonReversibleSteps(
        authedAccount: AuthedAccount.Explicit,
        didLinkNSync: Bool,
    ) async throws(CompleteProvisioningError) {
        // Linked devices don't have SVR backups.
        let capabilities = AccountAttributes.Capabilities(hasSVRBackups: false)
        do {
            try await Service.makeUpdateSecondaryDeviceCapabilitiesRequest(
                capabilities: capabilities,
                auth: authedAccount.chatServiceAuth,
                networkManager: self.networkManager,
                tsAccountManager: self.tsAccountManager,
            )
        } catch {
            throw .genericError(error)
        }

        await self.db.awaitableWrite { tx in
            self.registrationStateChangeManager.didRegisterOrProvision(
                aci: authedAccount.aci,
                phoneNumber: authedAccount.phoneNumber,
                authToken: authedAccount.authPassword,
                deviceId: authedAccount.deviceId,
                tx: tx,
            )
        }

        await registrationWebSocketManager.releaseRestrictedWebSocket(isRegistered: true)

        return try await performNecessarySyncsAndRestores(
            authedAccount: authedAccount,
            didLinkNSync: didLinkNSync,
        )
    }

    private func performNecessarySyncsAndRestores(
        authedAccount: AuthedAccount.Explicit,
        didLinkNSync: Bool,
    ) async throws(CompleteProvisioningError) {
        func doSyncsAndRestores() async throws(CompleteProvisioningError) {
            try await performInitialStorageServiceRestore(authedAccount: .explicit(authedAccount))
            try await performInitialContactSync(didLinkNSync: didLinkNSync)
        }

        if didLinkNSync {
            // Because link'n'sync gives us basic contact info, we don't
            // block on a contact sync after doing one. We still do the
            // contact sync in the background to get contact avatars.
            Task {
                do {
                    try await doSyncsAndRestores()
                } catch {
                    Logger.error("Failed to complete link&sync: \(error)")
                }
            }
        } else {
            try await doSyncsAndRestores()
        }
    }

    private func performInitialStorageServiceRestore(
        authedAccount: AuthedAccount,
    ) async throws(CompleteProvisioningError) {
        do {
            try await self.storageServiceManager
                .restoreOrCreateManifestIfNecessary(authedAccount: authedAccount, masterKeySource: .implicit)
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
        aciPreKeyBundle: RegistrationPreKeyUploadBundle,
        pniPreKeyBundle: RegistrationPreKeyUploadBundle,
        aciRegistrationId: UInt32,
        pniRegistrationId: UInt32,
        encryptedDeviceName: Data,
        apnRegistrationId: RegistrationRequestFactory.ApnRegistrationId?,
    ) async throws(CompleteProvisioningError) -> AuthedAccount.Explicit {
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
            aci: provisionMessage.aci,
            aciPreKeyBundle: aciPreKeyBundle,
            pniPreKeyBundle: pniPreKeyBundle,
            authPassword: serverAuthToken,
            accountAttributes: accountAttributes,
            apnRegistrationId: apnRegistrationId,
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
        if provisionMessage.phoneNumberState.phoneNumber.pni != verifyDeviceResponse.pni {
            throw .genericError(OWSAssertionError("PNI from primary is out of sync with the server!"))
        }
        if verifyDeviceResponse.deviceId.isPrimary {
            throw .genericError(OWSAssertionError("Server is trying to link device as primary!"))
        }

        return AuthedAccount.Explicit(
            aci: provisionMessage.aci,
            phoneNumber: provisionMessage.phoneNumberState.phoneNumber,
            deviceId: verifyDeviceResponse.deviceId,
            authPassword: serverAuthToken,
        )
    }

    private func undoVerifyAndLinkOnServer(authedAccount: AuthedAccount.Explicit) async throws(CompleteProvisioningError) {
        do {
            try await registrationStateChangeManager.unlinkLocalDevice(
                localDeviceId: .valid(authedAccount.deviceId),
                auth: authedAccount.chatServiceAuth,
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

        let aep = accountKeyStore.getAccountEntropyPool(tx: tx)

        let registrationRecoveryPassword = aep?.getMasterKey().deriveRegistrationRecoveryPassword()

        let encryptedDeviceName = encryptedDeviceNameRaw.base64EncodedString()

        let phoneNumberDiscoverability = tsAccountManager.phoneNumberDiscoverability(tx: tx)

        // Linked devices don't have SVR backups.
        let capabilities = AccountAttributes.Capabilities(hasSVRBackups: false)

        return AccountAttributes(
            isManualMessageFetchEnabled: isManualMessageFetchEnabled,
            registrationId: aciRegistrationId,
            pniRegistrationId: pniRegistrationId,
            unidentifiedAccessKey: udAccessKey,
            unrestrictedUnidentifiedAccess: allowUnrestrictedUD,
            reglockToken: reglockToken,
            registrationRecoveryPassword: registrationRecoveryPassword?.canonicalStringRepresentation,
            encryptedDeviceName: encryptedDeviceName,
            discoverableByPhoneNumber: phoneNumberDiscoverability,
            capabilities: capabilities,
        )
    }

    private func generateServerAuthToken() -> String {
        return Randomness.generateRandomBytes(16).hexadecimalString
    }
}
