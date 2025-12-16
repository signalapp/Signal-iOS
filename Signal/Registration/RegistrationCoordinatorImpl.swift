//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Contacts
import Foundation
import LibSignalClient
public import SignalServiceKit

public protocol RegistrationCoordinatorLoaderDelegate: AnyObject {
    func clearPersistedMode(transaction: DBWriteTransaction)

    func savePendingChangeNumber(
        oldState: RegistrationCoordinatorLoaderImpl.Mode.ChangeNumberState,
        pniState: RegistrationCoordinatorLoaderImpl.Mode.ChangeNumberState.PendingPniState?,
        transaction: DBWriteTransaction
    ) throws -> RegistrationCoordinatorLoaderImpl.Mode.ChangeNumberState
}

public class RegistrationCoordinatorImpl: RegistrationCoordinator {

    /// Only `RegistrationCoordinatorLoaderImpl` can create a nested `Mode` instance,
    /// so only it can create this class. If you want an instance, use `RegistrationCoordinatorLoaderImpl`.
    public init(
        mode: RegistrationCoordinatorLoaderImpl.Mode,
        loader: RegistrationCoordinatorLoaderDelegate,
        dependencies: RegistrationCoordinatorDependencies
    ) {
        self._unsafeToModify_mode = mode
        self.kvStore = KeyValueStore(collection: "RegistrationCoordinator")
        self.loader = loader
        self.deps = dependencies
    }

    // MARK: - Public API

    public func switchToSecondaryDeviceLinking() -> Bool {
        Logger.info("")

        switch mode {
        case .registering:
            if persistedState.hasShownSplash {
                return false
            } else {
                self.db.write { tx in
                    self.wipePersistedState(tx)
                }
                return true
            }
        case .reRegistering, .changingNumber:
            return false
        }
    }

    public func exitRegistration() -> Bool {
        Logger.info("")

        switch canExitRegistrationFlow() {
        case .notAllowed:
            Logger.warn("User can't exit registration now")
            return false
        case .allowed(let shouldWipeState):
            if shouldWipeState {
                // Wipe in progress state; presumably the user decided not
                // to proceed and should
                // a) not be sent here by default next app launch
                // b) start again from scratch if they do opt to return
                self.db.write { tx in
                    self.wipePersistedState(tx)
                }
            }
            return true
        }
    }

    @MainActor
    public func nextStep() async -> RegistrationStep {
        if deps.appExpiry.isExpired(now: deps.dateProvider()) {
            return .appUpdateBanner
        }

        // Always start by restoring state.
        await restoreStateIfNeeded()
        return await nextStep(pathway: getPathway())
    }

    public func continueFromSplash() -> Guarantee<RegistrationStep> {
        Logger.info("")

        db.write { tx in
            self.updatePersistedState(tx) {
                $0.hasShownSplash = true
            }
        }
        return Guarantee.wrapAsync { await self.nextStep() }
    }

    public func requestPermissions() -> Guarantee<RegistrationStep> {
        Logger.info("")

        return Guarantee.wrapAsync { @MainActor in
            // Notifications first, then contacts if needed.
            await self.deps.pushRegistrationManager.registerUserNotificationSettings()
            await self.deps.contactsStore.requestContactsAuthorization()
            self.inMemoryState.needsSomePermissions = false
            return await self.nextStep()
        }
    }

    public func submitProspectiveChangeNumberE164(_ e164: E164) -> Guarantee<RegistrationStep> {
        Logger.info("")
        self.inMemoryState.changeNumberProspectiveE164 = e164
        return Guarantee.wrapAsync { await self.nextStep() }
    }

    public func submitE164(_ e164: E164) -> Guarantee<RegistrationStep> {
        Logger.info("")

        var e164 = e164
        switch mode {
        case .reRegistering(let reregState):
            if e164 != reregState.e164 {
                Logger.debug("Tried to submit a changed e164 during rereg; ignoring and submitting the fixed e164 instead.")
                e164 = reregState.e164
            }
        case .registering, .changingNumber:
            break
        }

        let pathway = getPathway()
        db.write { tx in
            updatePersistedState(tx) {
                $0.e164 = e164
            }
            switch pathway {
            case .session(let session):
                guard session.e164 == e164 else {
                    resetSession(tx)
                    return
                }
                if
                    let sessionState = self.persistedState.sessionState,
                    sessionState.sessionId == session.id
                {
                    switch sessionState.initialCodeRequestState {
                    case
                            .smsTransportFailed,
                            .transientProviderFailure,
                            .permanentProviderFailure,
                            .failedToRequest,
                            .exhaustedCodeAttempts:
                        // Reset state so we try again.
                        self.updatePersistedSessionState(session: session, tx) {
                            $0.initialCodeRequestState = .neverRequested
                        }
                    case .requested, .neverRequested:
                        break
                    }
                }
            case
                    .opening,
                    .quickRestore,
                    .manualRestore,
                    .svrAuthCredential,
                    .svrAuthCredentialCandidates,
                    .registrationRecoveryPassword,
                    .profileSetup:
                break
            }
        }
        inMemoryState.hasEnteredE164 = true

        return Guarantee.wrapAsync { await self.nextStep() }
    }

    public func requestChangeE164() -> Guarantee<RegistrationStep> {
        Logger.info("")
        db.write { tx in
            updatePersistedState(tx) {
                $0.e164 = nil
            }
            // Reset the session; it is e164 dependent.
            resetSession(tx)
            // Reload auth credential candidates; we might not have
            // had a credential for the old e164 but might have one for
            // the new e164!
            loadSVRAuthCredentialCandidates(tx)
        }
        inMemoryState.hasEnteredE164 = false
        inMemoryState.changeNumberProspectiveE164 = nil
        return Guarantee.wrapAsync { await self.nextStep() }
    }

    public func requestSMSCode() -> Guarantee<RegistrationStep> {
        Logger.info("")
        switch getPathway() {
        case
                .opening,
                .quickRestore,
                .manualRestore,
                .registrationRecoveryPassword,
                .svrAuthCredential,
                .svrAuthCredentialCandidates,
                .profileSetup:
            owsFailBeta("Shouldn't be resending SMS from non session paths.")
            return Guarantee.wrapAsync { await self.nextStep() }
        case .session:
            inMemoryState.pendingCodeTransport = .sms
            return Guarantee.wrapAsync { await self.nextStep() }
        }
    }

    public func requestVoiceCode() -> Guarantee<RegistrationStep> {
        Logger.info("")
        switch getPathway() {
        case
                .opening,
                .quickRestore,
                .manualRestore,
                .registrationRecoveryPassword,
                .svrAuthCredential,
                .svrAuthCredentialCandidates,
                .profileSetup:
            owsFailBeta("Shouldn't be sending voice code from non session paths.")
            return Guarantee.wrapAsync { await self.nextStep() }
        case .session:
            inMemoryState.pendingCodeTransport = .voice
            return Guarantee.wrapAsync { await self.nextStep() }
        }
    }

    public func submitVerificationCode(_ code: String) -> Guarantee<RegistrationStep> {
        Logger.info("")
        switch getPathway() {
        case
                .opening,
                .quickRestore,
                .manualRestore,
                .registrationRecoveryPassword,
                .svrAuthCredential,
                .svrAuthCredentialCandidates,
                .profileSetup:
            owsFailBeta("Shouldn't be submitting verification code from non session paths.")
            return Guarantee.wrapAsync { await self.nextStep() }
        case .session(let session):
            return Guarantee.wrapAsync { await self.submitSessionCode(session: session, code: code, failureCount: 0) }
        }
    }

    /// Note: This method does _not_ report the restore method back to the old device.
    /// This is due to the fact we either lack the necessary information (e.g. - device transfer info)
    /// and/or the user hasn't fully committed to the restore method yet (e.g. - they hit cancel on restore from
    /// backup and choose device transfer instead).
    public func updateRestoreMethod(method: RegistrationRestoreMethod) -> Guarantee<RegistrationStep> {
        switch method {
        case .declined:
            inMemoryState.hasSkippedRestoreFromMessageBackup = true
            inMemoryState.needsToAskForDeviceTransfer = false
            deps.db.write { tx in
                updatePersistedState(tx) {
                    $0.hasDeclinedTransfer = true
                    $0.restoreMethod = .declined
                }
            }
        case .deviceTransfer:
            inMemoryState.hasSkippedRestoreFromMessageBackup = true
            inMemoryState.needsToAskForDeviceTransfer = false
            deps.db.write { tx in
                updatePersistedState(tx) {
                    $0.hasDeclinedTransfer = false
                    $0.restoreMethod = .deviceTransfer
                }
            }
        case .remote:
            inMemoryState.hasSkippedRestoreFromMessageBackup = false
            inMemoryState.needsToAskForDeviceTransfer = false
            deps.db.write { tx in
                updatePersistedState(tx) {
                    $0.hasDeclinedTransfer = true
                    $0.restoreMethod = .remoteBackup
                }
            }
        case .local:
            // TODO: [Backups] - When local backup support is added, the associated 'fileURL'
            // will need to be persisted to inMemoryState
            inMemoryState.hasSkippedRestoreFromMessageBackup = false
            inMemoryState.needsToAskForDeviceTransfer = false
            deps.db.write { tx in
                updatePersistedState(tx) {
                    $0.hasDeclinedTransfer = true
                    $0.restoreMethod = .localBackup
                }
            }
        }
        return Guarantee.wrapAsync { await self.nextStep() }
    }

    public func updateAccountEntropyPool(_ accountEntropyPool: SignalServiceKit.AccountEntropyPool) -> Guarantee<RegistrationStep> {
        inMemoryState.accountEntropyPool = accountEntropyPool
        inMemoryState.shouldRestoreSVRMasterKeyAfterRegistration = false
        inMemoryState.askForPinDuringReregistration = false

        // If the master key has already been restored from SVR, this can mean two things
        // 1) The user has gone through the basic restore flow that may ask for the PIN before prompting
        //    the restore method.
        // 2) The user previously entered an AEP, but attempting to use the AEP derived master key resulted
        //    in a RRP failure from the server, which usually means a prior registration rotated the
        //    AEP and/or the MasterKey. In this case, we'll restore the MasterKey from SVR and won't overwrite
        //    the value with any further AEP derived keys. This should be fine in regular use since SVR
        //    should always contain the most recent MasterKey, and, in the case of reglock, the most recent
        //    reglock token.
        if !persistedState.hasRestoredFromSVR {
            deps.db.write { tx in
                updateMasterKeyAndLocalState(masterKey: accountEntropyPool.getMasterKey(), tx: tx)
            }
        }
        return Guarantee.wrapAsync { await self.nextStep() }
    }

    public func restoreFromRegistrationMessage(message: RegistrationProvisioningMessage) -> Guarantee<RegistrationStep> {
        inMemoryState.accountEntropyPool = message.accountEntropyPool
        inMemoryState.registrationMessage = message
        inMemoryState.pinFromUser = message.pin
        inMemoryState.pinFromDisk = message.pin
        inMemoryState.askForPinDuringReregistration = false

        deps.db.write { tx in
            updatePersistedState(tx) {
                $0.e164 = message.phoneNumber
            }
            updateMasterKeyAndLocalState(masterKey: message.accountEntropyPool.getMasterKey(), tx: tx)
        }
        // TODO: Display prompt for restore method selection
        return Guarantee.wrapAsync { await self.nextStep() }
    }

    public func submitCaptcha(_ token: String) -> Guarantee<RegistrationStep> {
        Logger.info("")
        switch getPathway() {
        case
                .opening,
                .quickRestore,
                .manualRestore,
                .registrationRecoveryPassword,
                .svrAuthCredential,
                .svrAuthCredentialCandidates,
                .profileSetup:
            owsFailBeta("Shouldn't be submitting captcha from non session paths.")
            return Guarantee.wrapAsync { await self.nextStep() }
        case .session(let session):
            return Guarantee.wrapAsync {
                return await self.submit(challengeFulfillment: .captcha(token), for: session, failureCount: 0)
            }
        }
    }

    public func setHasOldDevice(_ hasOldDevice: Bool) -> Guarantee<RegistrationStep> {
        deps.db.write { tx in
            updatePersistedState(tx) {
                $0.hasShownSplash = true
                $0.restoreMode = hasOldDevice ? .quickRestore : .manualRestore
            }
        }
        return Guarantee.wrapAsync { await self.nextStep() }
    }

    public func setPINCodeForConfirmation(_ blob: RegistrationPinConfirmationBlob) -> Guarantee<RegistrationStep> {
        Logger.info("")
        inMemoryState.unconfirmedPinBlob = blob
        return Guarantee.wrapAsync { await self.nextStep() }
    }

    public func resetUnconfirmedPINCode() -> Guarantee<RegistrationStep> {
        Logger.info("")
        inMemoryState.unconfirmedPinBlob = nil
        return Guarantee.wrapAsync { await self.nextStep() }
    }

    public func submitPINCode(_ code: String) -> Guarantee<RegistrationStep> {
        Logger.info("")
        switch getPathway() {
        case .registrationRecoveryPassword:
            if
                let pinFromDisk = inMemoryState.pinFromDisk,
                pinFromDisk != code
            {
                let numberOfWrongGuesses = persistedState.numLocalPinGuesses + 1
                db.write { tx in
                    updatePersistedState(tx) {
                        $0.numLocalPinGuesses = numberOfWrongGuesses
                    }
                }
                if numberOfWrongGuesses >= Constants.maxLocalPINGuesses {
                    // "Skip" PIN entry, which will make us stop trying to register via registration
                    // recovery password.
                    db.write { tx in
                        updatePersistedState(tx) {
                            $0.hasSkippedPinEntry = true
                        }
                        switch self.mode {
                        case .changingNumber:
                            break
                        case .registering, .reRegistering:
                            deps.svr.clearKeys(transaction: tx)
                            deps.ows2FAManager.clearLocalPinCode(tx)
                        }
                    }
                    inMemoryState.pinFromUser = nil
                    inMemoryState.pinFromDisk = nil
                    self.wipeInMemoryStateToPreventSVRPathAttempts()
                    return .value(.pinAttemptsExhaustedWithoutReglock(
                        .init(mode: .restoringRegistrationRecoveryPassword)
                    ))
                } else {
                    let remainingAttempts = Constants.maxLocalPINGuesses - numberOfWrongGuesses
                    return .value(.pinEntry(RegistrationPinState(
                        operation: .enteringExistingPin(
                            skippability: .canSkip,
                            remainingAttempts: remainingAttempts
                        ),
                        error: .wrongPin(wrongPin: code),
                        contactSupportMode: contactSupportRegistrationPINMode(),
                        exitConfiguration: pinCodeEntryExitConfiguration()
                    )))
                }
            }
        case .opening, .quickRestore, .manualRestore, .svrAuthCredential, .svrAuthCredentialCandidates, .profileSetup, .session:
            // We aren't checking against any local state, rely on the request.
            break
        }
        self.inMemoryState.pinFromUser = code
        // Individual pathway's steps should handle whatever needs to be done with the pin,
        // depending on the current pathway.
        return Guarantee.wrapAsync { await self.nextStep() }
    }

    public func skipPINCode() -> Guarantee<RegistrationStep> {
        Logger.info("")
        let shouldGiveUpTryingToRestoreWithSVR: Bool = {
            switch getPathway() {
            case
                    .opening,
                    .quickRestore,
                    .manualRestore,
                    .registrationRecoveryPassword,
                    .svrAuthCredential,
                    .svrAuthCredentialCandidates,
                    .session:
                return false
            case .profileSetup:
                return true
            }
        }()
        db.write { tx in
            updatePersistedState(tx) {
                $0.hasSkippedPinEntry = true
                if shouldGiveUpTryingToRestoreWithSVR {
                    $0.hasGivenUpTryingToRestoreWithSVR = true
                }
            }
            switch self.mode {
            case .changingNumber:
                break
            case .registering, .reRegistering:
                // Whenever we do this, wipe the keys we've got.
                // We don't want to have them and use then implicitly later.
                deps.svr.clearKeys(transaction: tx)
                deps.ows2FAManager.clearLocalPinCode(tx)
            }
        }
        inMemoryState.pinFromUser = nil
        self.wipeInMemoryStateToPreventSVRPathAttempts()
        return Guarantee.wrapAsync { await self.nextStep() }
    }

    public func skipAndCreateNewPINCode() -> Guarantee<RegistrationStep> {
        Logger.info("")
        switch getPathway() {
        case
                .opening,
                .quickRestore,
                .manualRestore,
                .registrationRecoveryPassword,
                .svrAuthCredentialCandidates,
                .session:
            Logger.error("Invalid state from which to skip!")
            return Guarantee.wrapAsync { await self.nextStep() }
        case
                .svrAuthCredential,
                .profileSetup:
            break
        }
        db.write { tx in
            updatePersistedState(tx) {
                // We are NOT skipping PIN entry; just restoring, which
                // means we will create a new PIN.
                $0.hasSkippedPinEntry = false
                $0.hasGivenUpTryingToRestoreWithSVR = true
            }
            switch self.mode {
            case .changingNumber:
                break
            case .registering, .reRegistering:
                // Whenever we do this, wipe the keys we've got.
                // We don't want to have them and use them implicitly later.
                deps.svr.clearKeys(transaction: tx)
                deps.ows2FAManager.clearLocalPinCode(tx)
            }
        }
        inMemoryState.pinFromUser = nil
        self.wipeInMemoryStateToPreventSVRPathAttempts()
        return Guarantee.wrapAsync { await self.nextStep() }
    }

    public func skipRestoreFromBackup() -> Guarantee<RegistrationStep> {
        Logger.info("")
        inMemoryState.hasSkippedRestoreFromMessageBackup = true

        inMemoryState.needsToAskForDeviceTransfer = false
        deps.db.write { tx in
            updatePersistedState(tx) {
                $0.hasDeclinedTransfer = true
                $0.restoreMethod = .declined
            }
        }
        return Guarantee.wrapAsync { await self.nextStep() }
    }

    public func resetRestoreMode() -> Guarantee<RegistrationStep> {
        inMemoryState.registrationMessage = nil
        inMemoryState.accountEntropyPool = nil
        db.write { tx in
            self.updatePersistedState(tx) {
                $0.shouldSkipRegistrationSplash = false
                $0.hasShownSplash = false
                $0.restoreMode = nil
            }
        }
        return resetRestoreMethodChoice()
    }

    public func cancelRecoveryKeyEntry() -> Guarantee<RegistrationStep> {
        inMemoryState.accountEntropyPool = nil
        return resetRestoreMethodChoice()
    }

    public func resetRestoreMethodChoice() -> Guarantee<RegistrationStep> {
        inMemoryState.needsToAskForDeviceTransfer = true
        inMemoryState.restoreFromBackupProgressSink = nil
        deps.db.write { tx in
            updatePersistedState(tx) {
                $0.hasDeclinedTransfer = false
                $0.restoreMethod = nil
            }
        }
        return Guarantee.wrapAsync { await self.nextStep() }
    }

    public func confirmRestoreFromBackup(
        progress: OWSSequentialProgressRootSink<BackupRestoreProgressPhase>
    ) -> Guarantee<RegistrationStep> {
        inMemoryState.restoreFromBackupProgressSink = progress
        return Guarantee.wrapAsync { await self.nextStep() }
    }

    private func restoreFromMessageBackup(
        type: PersistedState.RestoreMethod.BackupType,
        accountEntropyPool: SignalServiceKit.AccountEntropyPool,
        identity: AccountIdentity,
        progress: OWSSequentialProgressRootSink<BackupRestoreProgressPhase>?,
    ) async {
        Logger.info("")
        return await _doBackupRestoreStep {
            let downloadProgress = await progress?.child(for: .downloadingBackup).addChild(
                withLabel: "",
                unitCount: 100
            )
            let importProgress = await progress?.child(for: .importingBackup).addChild(
                withLabel: "",
                unitCount: 100
            )

            let backupKey = try MessageRootBackupKey(accountEntropyPool: accountEntropyPool, aci: identity.aci)
            let fileUrl: URL
            switch type {
            case .local:
                // TODO: [Backups] This is currently unsupported, so log and return
                throw OWSAssertionError("Local backups not supported.")
            case .remote:
                let backupServiceAuth = try await self.fetchBackupServiceAuth(
                    accountEntropyPool: accountEntropyPool,
                    accountIdentity: identity
                )
                fileUrl = try await self.deps.backupArchiveManager.downloadEncryptedBackup(
                    backupKey: backupKey,
                    backupAuth: backupServiceAuth,
                    progress: downloadProgress,
                )
            }

            // The recovery key has been derived, the backup file has been sourced,
            // so this is the last possible point before we commit to importing the backup.
            // At this point, persist the recovery key so if the app restarts after this point
            // we remember the key that was used during restore.
            await self.db.awaitableWrite { tx in
                self.updatePersistedState(tx) {
                    $0.backupKeyAccountEntropyPool = accountEntropyPool
                }
            }

            let nonceSource: BackupImportSource.NonceMetadataSource
            if let lastBackupForwardSecrecyToken = self.inMemoryState.registrationMessage?.lastBackupForwardSecrecyToken {
                nonceSource = .provisioningMessage(lastBackupForwardSecrecyToken)
                if let nextBackupSecretData = self.inMemoryState.registrationMessage?.nextBackupSecretData {
                    // Set the next secret metadata immediately; we won't use
                    // it until we next create a backup and it will ensure that
                    // when we do, this previous backup remains decryptable
                    // if that next backups fails at the upload to cdn step.
                    // It is ok if the restore process fails after this point,
                    // either we try again and overwrite this, or we skip
                    // and then the next time we make a backup we still use
                    // this key which is at worst as good as a random starting point.
                    await self.db.awaitableWrite { tx in
                        self.deps.backupNonceStore.setNextSecretMetadata(
                            nextBackupSecretData,
                            for: backupKey,
                            tx: tx
                        )
                    }
                }
            } else if let metadataHeader = self.inMemoryState.backupMetadataHeader {
                nonceSource = .svrB(header: metadataHeader, auth: identity.chatServiceAuth)
            } else {
                Logger.info("Missing metadata header; refetching from cdn")
                let backupServiceAuth = try await self.fetchBackupServiceAuth(
                    accountEntropyPool: accountEntropyPool,
                    accountIdentity: identity
                )
                let metadataHeader = try await self.deps.backupArchiveManager.backupCdnInfo(
                    backupKey: backupKey,
                    backupAuth: backupServiceAuth
                ).metadataHeader
                self.inMemoryState.backupMetadataHeader = metadataHeader
                nonceSource = .svrB(header: metadataHeader, auth: identity.chatServiceAuth)
            }

            try await self.deps.backupArchiveManager.importEncryptedBackup(
                fileUrl: fileUrl,
                localIdentifiers: identity.localIdentifiers,
                isPrimaryDevice: true,
                source: .remote(key: backupKey, nonceSource: nonceSource),
                progress: importProgress
            )
        }
    }

    private func finalizeRestoreFromMessageBackup(
        identity: AccountIdentity
    ) async {
        Logger.info("")
        return await _doBackupRestoreStep {
            try await self.deps.backupArchiveManager.finalizeBackupImport(progress: nil)
        }
    }

    @MainActor
    private func _doBackupRestoreStep(
        _ block: @escaping () async throws -> Void
    ) async {
        do {
            try await block()

            self.inMemoryState.backupRestoreState = self.db.read { tx in
                self.deps.backupArchiveManager.backupRestoreState(tx: tx)
            }
            switch self.inMemoryState.backupRestoreState {
            case .none, .unfinalized:
                throw OWSAssertionError("Hasn't restored despite no thrown error!")
            case .finalized:
                Logger.info("Finished restore")
                return
            }
        } catch {
            let errorType = self.deps.registrationBackupErrorPresenter.mapToRegistrationError(error: error)
            let result = await self.deps.registrationBackupErrorPresenter.presentError(
                error: errorType,
                isQuickRestore: false
            )

            switch result {
            case .restartQuickRestore, .none:
                owsFailDebug("Invalid option returned from handlinge of registration error.")
                fallthrough
            case .rateLimited:
                // Can't currently restore, so show an error and return to the restore confirm screen
                inMemoryState.restoreFromBackupProgressSink = nil
                return
            case .incorrectRecoveryKey, .skipRestore:
                // By this point, it's really too late to do anything but skip the backup and continue
                await db.awaitableWrite { tx in
                    updatePersistedState(tx) {
                        $0.restoreMethod = .declined
                        $0.backupKeyAccountEntropyPool = nil
                    }
                }
                return
            case .tryAgain:
                // retry the backup restore
                return await _doBackupRestoreStep(block)
            }
        }
    }

    public func setPhoneNumberDiscoverability(_ phoneNumberDiscoverability: PhoneNumberDiscoverability) -> Guarantee<RegistrationStep> {
        Logger.info("")
        guard let accountIdentity = persistedState.accountIdentity else {
            owsFailBeta("Shouldn't be setting phone number discoverability prior to registration.")
            return .value(.showErrorSheet(.genericError))
        }

        updatePhoneNumberDiscoverability(
            accountIdentity: accountIdentity,
            phoneNumberDiscoverability: phoneNumberDiscoverability
        )

        return Guarantee.wrapAsync { await self.nextStep() }
    }

    public func setProfileInfo(
        givenName: OWSUserProfile.NameComponent,
        familyName: OWSUserProfile.NameComponent?,
        avatarData: Data?,
        phoneNumberDiscoverability: PhoneNumberDiscoverability
    ) -> Guarantee<RegistrationStep> {
        Logger.info("")

        guard let accountIdentity = persistedState.accountIdentity else {
            owsFailBeta("Shouldn't be setting phone number discoverability prior to registration.")
            return .value(.showErrorSheet(.genericError))
        }

        inMemoryState.pendingProfileInfo = (givenName: givenName, familyName: familyName, avatarData: avatarData)

        updatePhoneNumberDiscoverability(
            accountIdentity: accountIdentity,
            phoneNumberDiscoverability: phoneNumberDiscoverability
        )

        return Guarantee.wrapAsync { await self.nextStep() }
    }

    public func acknowledgeReglockTimeout() -> AcknowledgeReglockResult {
        Logger.info("")

        switch reglockTimeoutAcknowledgeAction {
        case .resetPhoneNumber:
            db.write { transaction in
                self.resetSession(transaction)
                self.updatePersistedState(transaction) { $0.e164 = nil }
            }
            return .restartRegistration(Guarantee.wrapAsync { await self.nextStep() })
        case .close:
            guard exitRegistration() else {
                return .cannotExit
            }
            return .exitRegistration
        case .none:
            return .cannotExit
        }
    }

    // MARK: - Internal

    typealias Mode = RegistrationCoordinatorLoaderImpl.Mode

    /// Does not change from one mode to another in the course of registration; you must finish a registration for a mode
    /// before registering in a different mode. (The metadata within a mode may change, e.g. changingNumber has state
    /// that changes as operations are completed. These updates go through RegistrationCoordinatorLoader.)
    /// Persisted on RegistrationCoordinatorLoader.
    private var mode: Mode { return _unsafeToModify_mode }

    private var _unsafeToModify_mode: Mode

    private let loader: RegistrationCoordinatorLoaderDelegate
    private let deps: RegistrationCoordinatorDependencies
    private let kvStore: KeyValueStore

    // Shortcuts for the commonly used ones.
    private var db: any DB { deps.db }

    // MARK: - In Memory State

    /// This is state that only exists for an in-memory registration attempt;
    /// it is wiped if the app is evicted from memory or registration is completed.
    private struct InMemoryState {
        var hasRestoredState = false

        var tsRegistrationState: TSRegistrationState?

        // Whether some system permissions (contacts, APNS) are needed.
        var needsSomePermissions = false

        // We persist the entered e164. But in addition we need to
        // know whether its been entered during this app launch; if it
        // hasn't we want to explicitly ask the user for it before
        // sending an SMS. But if we have (e.g. we asked for it to try
        // some SVR recovery that failed) we should auto-send an SMS if
        // we get to that step without asking again.
        var hasEnteredE164 = false

        // When changing number, we ask the user to confirm old number and
        // enter the new number before confirming the new number.
        // This tracks that first check before the confirm.
        var changeNumberProspectiveE164: E164?

        var shouldRestoreSVRMasterKeyAfterRegistration = false
        // base64 encoded data
        var regRecoveryPw: String?
        // hexadecimal encoded data
        var reglockToken: String?

        // candidate credentials, which may not
        // be valid, or may not correspond with the current e164.
        var svr2AuthCredentialCandidates: [SVR2AuthCredential]?
        var svrAuthCredential: SVRAuthCredential?

        // If we had SVR backups before registration even began.
        var didHaveSVRBackupsPriorToReg = false

        // We always require the user to enter the PIN
        // during the in memory app session even if we
        // have it on disk.
        // This is a way to double check they know the PIN.
        var pinFromUser: String?
        var pinFromDisk: String?
        var unconfirmedPinBlob: RegistrationPinConfirmationBlob?

        // State to track if we should prompt the user to enter their PIN
        // For the manual restore path, we will ask for AEP which means we
        // don't need the users PIN to restore the master key. Instead, after
        // registration prompt the user to create a new PIN.
        var askForPinDuringReregistration = true

        // When we try to register, if we get a response from the server
        // telling us device transfer is possible, we set this to true
        // so the user can explicitly opt out if desired and we retry.
        var needsToAskForDeviceTransfer = false

        var session: RegistrationSession?

        // If we try and resend a code (NOT the original SMS code automatically sent
        // at the start of every session), but hit a challenge, we write this var
        // so that when we complete the challenge we send the code right away.
        var pendingCodeTransport: Registration.CodeTransport?

        // Every time we go through registration, we should back up our SVR master
        // secret's random bytes to SVR. Its safer to do this more than it is to do
        // it less, so keeping this state in memory.
        var hasBackedUpToSVR = false
        var didSkipSVRBackup = false
        var shouldBackUpToSVR: Bool {
            return hasBackedUpToSVR.negated && didSkipSVRBackup.negated
        }
        var backupMetadataHeader: BackupNonce.MetadataHeader?
        var restoreFromBackupProgressSink: OWSSequentialProgressRootSink<BackupRestoreProgressPhase>?
        var hasConfirmedRestoreFromBackup: Bool {
            restoreFromBackupProgressSink != nil
        }

        // OWS2FAManager state
        // If we are re-registering or changing number and
        // reglock was enabled, we should enable it again when done.
        var wasReglockEnabledBeforeStarting = false
        var hasSetReglock = false

        var pendingProfileInfo: (givenName: OWSUserProfile.NameComponent, familyName: OWSUserProfile.NameComponent?, avatarData: Data?)?

        // TSAccountManager state
        var isManualMessageFetchEnabled = false
        var phoneNumberDiscoverability: PhoneNumberDiscoverability?

        // OWSProfileManager state
        var profileKey: Aes256Key!
        var udAccessKey: SMKUDAccessKey!
        var allowUnrestrictedUD = false
        var hasProfileName = false

        // Message Backup state
        var backupRestoreState: BackupRestoreState = .none
        var hasSkippedRestoreFromMessageBackup = false

        // Once we have our SVR master key locally,
        // we can restore profile info from storage service.
        var hasRestoredFromStorageService = false
        var hasSkippedRestoreFromStorageService = false

        /// Root key entered or generated during registration.  This value should be persisted at
        /// the end of registration
        var accountEntropyPool: SignalServiceKit.AccountEntropyPool?

        /// RegistrationProvisioningMessage provided by the device that scanned
        /// the displayed QR code
        var registrationMessage: RegistrationProvisioningMessage?

        /// Tracks the state of "username reclamation" following Storage Service
        /// restore during registration. See ``attemptToReclaimUsername()`` for
        /// more details.
        enum UsernameReclamationState {
            case localUsernameStateNotLoaded
            case localUsernameStateLoaded(Usernames.LocalUsernameState)
            case reclamationAttempted
        }
        var usernameReclamationState: UsernameReclamationState = .localUsernameStateNotLoaded

        var hasOpenedConnection = false
    }

    private var inMemoryState = InMemoryState()

    // MARK: - Persisted State

    /// This state is kept across launches of registration. Whatever is set
    /// here must be explicitly wiped between sessions if desired.
    /// Note: We don't persist RegistrationSession because RegistrationSessionManager
    /// handles that; we restore it to InMemoryState instead.
    /// Note: `mode` is kept separate; it has a different lifecycle than the rest
    /// of PersistedState even though it is also persisted to disk.
    internal struct PersistedState: Codable {
        var hasShownSplash = false
        var shouldSkipRegistrationSplash = false

        var restoreMode: RestoreMode?
        enum RestoreMode: String, Codable {
            case quickRestore
            case manualRestore
        }

        /// When re-registering, just before completing the actual create account
        /// request, we wipe our local state for re-registration. We only do this once,
        /// and once we do, there is no turning back, because we will have wiped
        /// state thats needed to use the app outside of registration.
        var hasResetForReRegistration = false

        /// The e164 the user has entered for this attempt at registration.
        /// Initially the e164 in the UI may be pre-populated (e.g. in re-reg)
        /// but this value is not set until the user accepts it or enters their own value.
        var e164: E164?

        var aciRegistrationId: UInt32!
        var pniRegistrationId: UInt32!

        /// If we ever get a response from a server where we failed reglock,
        /// we know the e164 the request was for has reglock enabled.
        /// Note that so we always include the reglock token in requests.
        /// (Note that we can't blindly include it because if it wasn't enabled
        /// and we sent it up, that would enable reglock.)
        var e164WithKnownReglockEnabled: E164?

        /// How many times the user has tried making guesses against the PIN
        /// we have locally? This happens when we have a local SVR master key
        /// and want to confirm the user knows their PIN before using it to register.
        var numLocalPinGuesses: UInt = 0

        /// There are a few times we ask for the PIN that are skippable:
        ///
        /// * Registration recovery password path: we have your SVR master key locally, ask for PIN,
        ///   user skips, we stop trying to use the local master key and fall back to session-based
        ///   registration.
        ///
        /// * SVR Auth Credential path(s): we try and recover the SVR master secret from backups,
        ///   ask for PIN, user skips, we stop trying to recover the backup and fall back to
        ///   session-based registration.
        ///
        /// * Post-registration, if reglock was not enabled but there are SVR backups, we try and
        ///   recover them. If the user skips, we don't bother recovering.
        ///
        /// In a single flow, the user might hit more than one of these cases (and probably will;
        /// if they have SVR backups and skip in favor of session-based reg, we will see that
        /// they have backups post-registration). This skip applies to _all_ of these; if they
        /// skipped the PIN early on, we won't ask for it again for recovery purposes later.
        var hasSkippedPinEntry = false

        /// Have we given up trying to restore with SVR? This can happen if you blow through your
        /// PIN guesses or decide to give up before exhausting them.
        var hasGivenUpTryingToRestoreWithSVR = false

        /// Have we restored the pin form SVR already?  This serves as a hint to the registration
        /// flow that it doesn't need to fetch from SVR in the case of an error and can move on
        /// to alternate registration paths (e.g. falling back to session based registration)
        var hasRestoredFromSVR = false

        /// Restored SVR master key. This value will be used to restore a session and allow the user
        /// to register and recover storage service, but should never be persisted.  If this value is missing
        /// and `accountEntropyPool` is present, it can be used to derive an SVR master key for
        /// use in registration
        var recoveredSVRMasterKey: MasterKey?

        /// The AEP used to restore the backup, and the key that should be used for any remaining post-restore
        /// operations.  This key persisted in case the app quits in between a successful backup restore and the
        /// finalization of the restore (and registration).  The goal here is to prevent the possibility of a different
        /// AEP being entered by the user after a backup restore has already succeeded.
        var backupKeyAccountEntropyPool: SignalServiceKit.AccountEntropyPool?

        struct SessionState: Codable {
            let sessionId: String

            enum InitialCodeRequestState: Codable {
                /// We have never requested a code and should request one when we can.
                case neverRequested
                /// We have already requested a code at least once; further requests
                /// are user driven and not automatic
                case requested
                /// We asked for a code but got some generic failure. User action needed.
                case failedToRequest
                /// We sent a code, but submission attempts were exhausted so we should
                /// send a new code on user input.
                case exhaustedCodeAttempts

                /// We requested an sms code, but transport failed.
                /// User action needed, by selecting another transport.
                case smsTransportFailed
                // A 3p provider failed to send a message,
                // either permanently or transiently.
                case permanentProviderFailure
                case transientProviderFailure
            }

            var initialCodeRequestState: InitialCodeRequestState = .neverRequested

            enum ReglockState: Codable, Equatable {
                /// No reglock known of preventing registration.
                case none

                /// We tried to register and got reglocked; we have to
                /// recover from SVR2 with the credential given.
                case reglocked(credential: SVRAuthCredential, expirationDate: Date)

                struct SVRAuthCredential: Codable, Equatable {
                    /// In a prior life, this object could contain either a KBS(SVR1) credential or an SVR2 credential.
                    /// For backwards compatibility, therefore, the SVR2 credential might be nil.
                    let svr2: SVR2AuthCredential?

                    private init(svr2: SVR2AuthCredential?) {
                        self.svr2 = svr2
                    }

                    init(svr2: SVR2AuthCredential) {
                        self.svr2 = svr2
                    }

                    #if TESTABLE_BUILD
                    static func testOnly(svr2: SVR2AuthCredential?) -> Self {
                        return .init(svr2: svr2)
                    }
                    #endif

                    init(from decoder: Decoder) throws {
                        let container = try decoder.container(keyedBy: CodingKeys.self)
                        self.svr2 = try container.decodeIfPresent(SVR2AuthCredential.self, forKey: .svr2)
                    }
                }

                /// We couldn't recover credentials from SVR (probably
                /// because PIN guesses were exhausted) and so waiting
                /// out the reglock is the only option.
                case waitingTimeout(expirationDate: Date)
            }

            var reglockState: ReglockState = .none

            enum PushChallengeState: Codable, Equatable {
                /// We've never requested a push challenge token.
                case notRequested
                /// We don't expect to receive a push challenge token, likely because the user disabled
                /// push notifications.
                case ineligible
                /// We are waiting to receive a push challenge token. Make sure to check the associated
                /// `requestedAt` date to see if it's been too long.
                case waitingForPush(requestedAt: Date)
                /// We've received a push challenge token that we haven't fulfilled.
                case unfulfilledPush(challengeToken: String)
                /// We've sucessfully submitted a push challenge token.
                case fulfilled
                case rejected
            }

            var pushChallengeState: PushChallengeState = .notRequested

            /// The number of times we have attempted to submit a verification code.
            var numVerificationCodeSubmissions: UInt = 0

            /// If non-nil, we created an account with the session but got rate limited
            /// and can retry at the provided time.
            var createAccountTimeout: Date?
        }

        var sessionState: SessionState?

        /// Once we get an account identity response from the server
        /// for registering, re-registering, or changing phone number,
        /// we remember it so we don't re-register when we quit the app
        /// before finishing post-registration steps.
        var accountIdentity: AccountIdentity?

        /// After registration is complete, we generate and sync
        /// one time prekeys (signed prekeys are included in the registration
        /// request). We do not proceed until this succeeds.
        var didRefreshOneTimePreKeys: Bool = false

        /// When we try and register, the server gives us an error if its possible
        /// to execute a device-to-device transfer. The user can decline; if they
        /// do, this will get set so we try force a re-register.
        /// Note if we are re-registering on the same primary device (based on mode),
        /// we ignore this field and always skip asking for device transfer.
        var hasDeclinedTransfer: Bool = false

        // The restore method selected by the user.
        var restoreMethod: RestoreMethod?

        enum RestoreMethod: Codable, Equatable {
            case remoteBackup
            case localBackup
            case deviceTransfer
            case declined

            enum BackupType {
                case remote
                case local
            }

            var backupType: BackupType? {
                switch self {
                case .remoteBackup: return .remote
                case .localBackup: return .local
                case .declined, .deviceTransfer: return nil
                }
            }

            var isBackup: Bool {
                switch self {
                case .localBackup, .remoteBackup: return true
                case .declined, .deviceTransfer: return false
                }
            }
        }

        init() {}

        enum CodingKeys: String, CodingKey {
            case hasShownSplash
            case shouldSkipRegistrationSplash
            case hasResetForReRegistration
            case e164
            case aciRegistrationId
            case pniRegistrationId
            case e164WithKnownReglockEnabled
            case numLocalPinGuesses
            case hasSkippedPinEntry
            // Legacy naming
            case hasGivenUpTryingToRestoreWithSVR = "hasGivenUpTryingToRestoreWithKBS"
            case hasRestoredFromSVR
            case sessionState
            case accountIdentity
            case didRefreshOneTimePreKeys
            case hasDeclinedTransfer
            case restoreMethod
            case restoreMode
            case recoveredSVRMasterKey
            case backupKeyAccountEntropyPool
        }
    }

    private var _persistedState: PersistedState?
    private var persistedState: PersistedState { return _persistedState ?? PersistedState() }

    private func updatePersistedState(_ transaction: DBWriteTransaction, _ update: (inout PersistedState) -> Void) {
        var state: PersistedState = persistedState
        update(&state)
        self._persistedState = state
        try? self.kvStore.setCodable(state, key: Constants.persistedStateKey, transaction: transaction)
    }

    private func updatePersistedSessionState(
        session: RegistrationSession,
        _ transaction: DBWriteTransaction,
        _ update: (inout PersistedState.SessionState) -> Void
    ) {
        updatePersistedState(transaction) {
            var sessionState = $0.sessionState ?? .init(sessionId: session.id)
            if sessionState.sessionId != session.id {
                self.resetSession(transaction)
                sessionState = .init(sessionId: session.id)
            }
            update(&sessionState)
            $0.sessionState = sessionState
        }
    }

    /// Once per in memory instantiation of this class, we need to do a few things:
    ///
    /// * Reload any persisted state from the key value store (from then on we can just use our
    ///   in memory copy because its internal to this class and therefore can't change on disk any other way)
    ///
    /// * Pull in any "in memory" state so we get a one-time snapshot of this state at the start of registration.
    ///   e.g. we ask KeyBackupService for any SVR data so we know whether to attempt registration
    ///   via registration recovery password (if present) or via SMS (if not).
    ///   We don't want to check this on the fly because if we went down the SMS path we'd eventually
    ///   recover our SVR data, but we'd want to stick to the SMS registration path and NOT revert to
    ///   the registration recovery password path, which would cause us to repeat work. So we only
    ///   grab a snapshot at the start and use that exclusively for state determination.
    @MainActor
    private func restoreStateIfNeeded() async {
        if inMemoryState.hasRestoredState {
            return
        }

        // This is best effort; if we fail to parse the consequences will be a restarted
        // registration, which is recoverable by the user (but annoying because they have
        // to repeat some steps).
        _persistedState = db.read {
            try? self.kvStore.getCodableValue(forKey: Constants.persistedStateKey, transaction: $0)
        }

        // Ideally this would be in the below transaction, but OWSProfileManager
        // isn't set up to do that and its a mess to untangle.
        self.loadProfileState()

        db.write { tx in

            var initialMasterKey: MasterKey?
            if let aep = deps.accountKeyStore.getAccountEntropyPool(tx: tx) {
                inMemoryState.accountEntropyPool = aep
                initialMasterKey = aep.getMasterKey()
            } else if let masterKey = deps.accountKeyStore.getMasterKey(tx: tx) {
                updatePersistedState(tx) {
                    $0.recoveredSVRMasterKey = masterKey
                }
                initialMasterKey = masterKey
            }

            // Generate new registration ids every time we register; until we set these on the server
            // in the registration request, they are meaningless and can be swapped out. But, for
            // simplicity, generate these once at the start of registration and persist that value
            // through registration. The registration IDs are set at the time of the registration call,
            // but these values aren't persisted to their final destination until the very end of
            // registration, so persiting the these values once at the start is the easiest way to
            // avoid problems.
            // Note: We should not reuse existing registration ids if we are reregistering
            updatePersistedState(tx) {
                if $0.aciRegistrationId == nil {
                    $0.aciRegistrationId = RegistrationIdGenerator.generate()
                }
                if $0.pniRegistrationId == nil {
                    $0.pniRegistrationId = RegistrationIdGenerator.generate()
                }
            }

            self.updateMasterKeyAndLocalState(masterKey: initialMasterKey, tx: tx)
            inMemoryState.tsRegistrationState = deps.tsAccountManager.registrationState(tx: tx)
            if let quickRestorePin = inMemoryState.registrationMessage?.pin {
                inMemoryState.pinFromDisk = quickRestorePin
                inMemoryState.pinFromUser = quickRestorePin
            } else {
                inMemoryState.pinFromDisk = deps.ows2FAManager.pinCode(tx)
            }

            loadSVRAuthCredentialCandidates(tx)
            inMemoryState.isManualMessageFetchEnabled = deps.tsAccountManager.isManualMessageFetchEnabled(tx: tx)

            inMemoryState.allowUnrestrictedUD = deps.udManager.shouldAllowUnrestrictedAccessLocal(transaction: tx)

            inMemoryState.wasReglockEnabledBeforeStarting = deps.ows2FAManager.isReglockEnabled(tx)

            inMemoryState.backupRestoreState = deps.backupArchiveManager.backupRestoreState(tx: tx)
        }

        switch mode {
        case .reRegistering(let reregState):
            if let persistedE164 = persistedState.e164, reregState.e164 != persistedE164 {
                // This exists to catch a bug released in version 6.19, where
                // the phone number view controller would incorrectly inject a
                // leading 0 into phone numbers from certain national codes.
                // That new number would then be written to persisted state.
                // To recover these users, we wipe their entire persisted state
                // and restart registration from scratch with fresh state.
                db.write { tx in
                    self.resetSession(tx)
                    self.wipePersistedState(tx)
                }
                return await restoreStateIfNeeded()
            }
        case .registering, .changingNumber:
            break
        }

        await withTaskGroup { group in
            group.addTask {
                let session = await self.deps.sessionManager.restoreSession()
                await self.db.awaitableWrite { self.processSession(session, $0) }
            }
            group.addTask {
                let needsPermissions = await self.requiresSystemPermissions()
                self.inMemoryState.needsSomePermissions = needsPermissions
            }
            await group.waitForAll()
        }
        inMemoryState.hasRestoredState = true
    }

    /// Once registration is complete, we need to take our internal state and write it out to
    /// external classes so that the rest of the app has all our updated information.
    /// Once this is done, we can wipe the internal state of this class so that we get a fresh
    /// registration if we ever re-register while in the same app session.
    @MainActor
    private func exportAndWipeState(
        accountEntropyPool: SignalServiceKit.AccountEntropyPool,
        accountIdentity: AccountIdentity
    ) async -> RegistrationStep {
        Logger.info("")

        switch mode {
        case .registering:
            return await self.finalize(
                accountEntropyPool: accountEntropyPool,
                accountIdentity: accountIdentity
            ) { tx in
                /// For new registrations, we want to force-set some state.
                if self.persistedState.restoreMethod?.backupType == nil {
                    /// Read receipts should be on by default.
                    self.deps.receiptManager.setAreReadReceiptsEnabled(true, tx)
                    self.deps.receiptManager.setAreStoryViewedReceiptsEnabled(true, tx)

                    /// Enable the onboarding banner cards.
                    self.deps.experienceManager.enableAllGetStartedCards(tx)
                }
            }

        case .reRegistering:
            return await finalize(
                accountEntropyPool: accountEntropyPool,
                accountIdentity: accountIdentity
            )

        case .changingNumber(let changeNumberState):
            if let pniState = changeNumberState.pniState {
                let result = await finalizeChangeNumberPniState(
                    changeNumberState: changeNumberState,
                    pniState: pniState,
                    accountIdentity: accountIdentity
                )
                switch result {
                case .success:
                    break
                case .genericError:
                    return .showErrorSheet(.genericError)
                }
            }
            return await updateAccountAttributesAndFinish(accountIdentity: accountIdentity, failureCount: 0)
        }
    }

    // Need this just to work around the structured concurrency friction with `Guarantee<T>?`
    func needsToRestoreBackup() -> Bool {
        switch inMemoryState.backupRestoreState {
        case .finalized:
            return false
        case .unfinalized:
            return true
        case .none:
            return persistedState.restoreMethod?.isBackup == true
        }
    }

    func restoreBackupIfNecessary(
        accountEntropyPool: SignalServiceKit.AccountEntropyPool,
        accountIdentity: AccountIdentity,
        progress: OWSSequentialProgressRootSink<BackupRestoreProgressPhase>?
    ) async {
        switch inMemoryState.backupRestoreState {
        case .finalized:
            break
        case .unfinalized:
            // Unconditionally finalize
            return await finalizeRestoreFromMessageBackup(
                identity: accountIdentity
            )
        case .none:
            if let backupType = persistedState.restoreMethod?.backupType {
                return await restoreFromMessageBackup(
                    type: backupType,
                    accountEntropyPool: accountEntropyPool,
                    identity: accountIdentity,
                    progress: progress
                )
            }
        }
    }

    @MainActor
    private func finalize(
        accountEntropyPool: SignalServiceKit.AccountEntropyPool,
        accountIdentity: AccountIdentity,
        block: ((DBWriteTransaction) -> Void)? = nil
    ) async -> RegistrationStep {
        await db.awaitableWrite { tx in
            if needsToScheduleRestoreFromSVRB() {
                deps.backupArchiveManager.scheduleRestoreFromSVRBBeforeNextExport(tx: tx)
            }

            if
                inMemoryState.hasBackedUpToSVR
                    || inMemoryState.didHaveSVRBackupsPriorToReg
                    || inMemoryState.backupRestoreState == .finalized
            {
                // No need to show the experience if we made the pin
                // and backed up.
                deps.experienceManager.clearIntroducingPinsExperience(tx)
            }

            // Persist the AEP. RegCoordinator manages all necessary side
            // effects, like updating Account Attributes and rotating the
            // Storage Service manifest.
            deps.accountKeyStore.setAccountEntropyPool(
                accountEntropyPool,
                tx: tx
            )

            deps.tsAccountManager.setRegistrationId(persistedState.aciRegistrationId, for: .aci, tx: tx)
            deps.tsAccountManager.setRegistrationId(persistedState.pniRegistrationId, for: .pni, tx: tx)

            block?(tx)

            deps.registrationStateChangeManager.didRegisterPrimary(
                e164: accountIdentity.e164,
                aci: accountIdentity.aci,
                pni: accountIdentity.pni,
                authToken: accountIdentity.authPassword,
                tx: tx
            )
            deps.tsAccountManager.setIsManualMessageFetchEnabled(inMemoryState.isManualMessageFetchEnabled, tx: tx)
        }

        await deps.registrationWebSocketManager.releaseRestrictedWebSocket(isRegistered: true)

        do {
            // releaseRestrictedWebSocket needs to be called before this happens.
            try await deps.remoteConfigManager.refreshIfNeeded()
        } catch {
            Logger.warn("Failed to fetch remote config: \(error)")
        }

        // Start syncing system contacts now that we have set up tsAccountManager.
        deps.contactsManager.fetchSystemContactsOnceIfAlreadyAuthorized()

        try? await deps.storageServiceManager.rotateManifest(
            mode: .preservingRecordsIfPossible,
            authedDevice: accountIdentity.authedDevice
        )

        // Update the account attributes once, now, at the end.
        return await updateAccountAttributesAndFinish(accountIdentity: accountIdentity, failureCount: 0)
    }

    private func fetchBackupCdnInfo(
        accountEntropyPool: SignalServiceKit.AccountEntropyPool,
        accountIdentity: AccountIdentity
    ) async -> RegistrationStep {
        Logger.info("")

        do {
            // For manual restore, fetch the backup info
            let backupKey = try MessageRootBackupKey(accountEntropyPool: accountEntropyPool, aci: accountIdentity.aci)
            let backupServiceAuth = try await self.fetchBackupServiceAuth(
                accountEntropyPool: accountEntropyPool,
                accountIdentity: accountIdentity
            )
            let cdnInfo = try await self.deps.backupArchiveManager.backupCdnInfo(
                backupKey: backupKey,
                backupAuth: backupServiceAuth,
            )
            self.inMemoryState.backupMetadataHeader = cdnInfo.metadataHeader
            return .confirmRestoreFromBackup(
                RegistrationRestoreFromBackupConfirmationState(
                    mode: .manual,
                    tier: .free,
                    lastBackupDate: cdnInfo.fileInfo.lastModified,
                    lastBackupSizeBytes: cdnInfo.fileInfo.contentLength
                )
            )
        } catch {
            let errorType = self.deps.registrationBackupErrorPresenter.mapToRegistrationError(error: error)
            Logger.error("Can't fetch backup info: \(error.localizedDescription)")
            let step = await self.deps.registrationBackupErrorPresenter.presentError(
                error: errorType,
                isQuickRestore: self.persistedState.restoreMode == .quickRestore
            )

            switch step {
            case .incorrectRecoveryKey, .rateLimited:
                return .enterRecoveryKey(
                    RegistrationEnterAccountEntropyPoolState(
                        canShowBackButton: persistedState.accountIdentity == nil,
                        canShowNoKeyHelpButton: true
                    ))
            case .skipRestore:
                return await updateRestoreMethod(method: .declined).awaitable()
            case .tryAgain, .restartQuickRestore, .none:
                return await nextStep()
            }
        }
    }

    /// It is possible that, in the time between the last backup and this restore,
    /// the user has registered without restoring. This can result in the AEP being
    /// rotated and a new ACI+AEP backupId being registered. If this happens,
    /// fetching auth credentials  using the original AEP will fail.
    /// The good news is this may be recoverable by re-registering the passed in ACI+AEP
    /// backupId as the current backupId. Once that is done, silently retry fetching credentials.
    /// If the fetch still fails, throw an error.
    private func fetchBackupServiceAuth(
        accountEntropyPool: SignalServiceKit.AccountEntropyPool,
        accountIdentity: AccountIdentity
    ) async throws -> BackupServiceAuth {
        let backupKey = try MessageRootBackupKey(accountEntropyPool: accountEntropyPool, aci: accountIdentity.aci)

        func fetchBackupServiceAuth() async throws -> BackupServiceAuth {
            return try await self.deps.backupRequestManager.fetchBackupServiceAuthForRegistration(
                key: backupKey,
                localAci: accountIdentity.aci,
                chatServiceAuth: accountIdentity.chatServiceAuth
            )
        }

        do {
            return try await fetchBackupServiceAuth()
        } catch SignalError.verificationFailed {
            try await self.deps.backupIdService.updateMessageBackupIdForRegistration(
                key: backupKey,
                auth: accountIdentity.chatServiceAuth
            )
            return try await fetchBackupServiceAuth()
        }
    }

    @MainActor
    private func updateAccountAttributesAndFinish(
        accountIdentity: AccountIdentity,
        failureCount: Int,
    ) async -> RegistrationStep {
        let maxAutomaticRetries = Constants.networkErrorRetries

        Logger.info("")

        let error = await self.updateAccountAttributes(accountIdentity)

        if let error, failureCount < maxAutomaticRetries, error.isNetworkFailureOrTimeout {
            let minimumBackoff = OWSOperation.retryIntervalForExponentialBackoff(failureCount: failureCount + 1)
            try? await Task.sleep(nanoseconds: minimumBackoff.clampedNanoseconds)
            return await updateAccountAttributesAndFinish(
                accountIdentity: accountIdentity,
                failureCount: failureCount + 1,
            )
        }
        // If we have a deregistration error, it doesn't matter. We are finished
        // and cleaning up anyway; the main app will discover the issue.
        if let error {
            Logger.warn("Failed account attributes update, finishing registration anyway: \(error)")
        }
        // We are done! Wipe everything
        self.inMemoryState = InMemoryState()
        self.db.write { tx in
            self.wipePersistedState(tx)
        }
        // Do any storage service backups we have pending.
        self.deps.storageServiceManager.backupPendingChanges(
            authedDevice: accountIdentity.authedDevice
        )
        return .done
    }

    private func wipePersistedState(_ tx: DBWriteTransaction) {
        Logger.info("")

        self.kvStore.removeValue(forKey: Constants.persistedStateKey, transaction: tx)
        self.loader.clearPersistedMode(transaction: tx)
    }

    // MARK: - Pathway

    /// A pathway is a (internal to this class) way of splitting up the distinct sections
    /// of registration to make this class a little more modular. Different pathways
    /// still share state and interact with each other in subtle ways, but for the most
    /// part are independent sequences.
    private enum Pathway {
        /// The first few screens before we try and register.
        /// (basically, the splash and systems permissions screens)
        case opening
        /// The user has their old device, so display the Quick Restore flow
        /// to allow the user to transfer registration information from the old device
        /// to the new device.
        case quickRestore
        /// The user does not have their old device, but the users intent is to restore
        /// from backup, so move the user into the restore choice/recovery key entry
        /// sooner than would happen in the default registration flow.
        case manualRestore
        /// Attempting to register using the reg recovery password
        /// derived from the SVR master key.
        case registrationRecoveryPassword(password: String)
        /// Attempting to recover from SVR auth credentials
        /// which let us talk to SVR server, recover the master key,
        /// and swap to the registrationRecoveryPassword path.
        case svrAuthCredential(SVRAuthCredential)
        /// We might have un-verified SVR auth credentials
        /// synced from another device; first we need to check them
        /// with the server and then potentially go to the svrAuthCredential path.
        case svrAuthCredentialCandidates([SVR2AuthCredential])
        /// Verifying via SMS code using a `RegistrationSession`.
        /// Used as a fallback if the above paths are unavailable or fail.
        case session(RegistrationSession)
        /// After registration is done, all the steps involving setting up
        /// profile state (which may not be needed). Profile name,
        /// setting up a PIN, etc.
        case profileSetup(AccountIdentity)

        var logSafeString: String {
            switch self {
            case .opening: return "opening"
            case .quickRestore: return "quickRestore"
            case .manualRestore: return "manualRestore"
            case .registrationRecoveryPassword: return "registrationRecoveryPassword"
            case .svrAuthCredential: return "svrAuthCredential"
            case .svrAuthCredentialCandidates: return "svrAuthCredentialCandidates"
            case .session: return "session"
            case .profileSetup: return "profileSetup"
            }
        }
    }

    private func getPathway() -> Pathway {
        if
            splashStepToShow() != nil
            || inMemoryState.needsSomePermissions
        {
            return .opening
        }
        if case .registering = mode {
            switch persistedState.restoreMode {
            case .quickRestore:
                if persistedState.restoreMethod == nil {
                    return .quickRestore
                } else if case .deviceTransfer = persistedState.restoreMethod {
                    return .quickRestore
                } else if
                    persistedState.restoreMethod?.isBackup == true,
                    !inMemoryState.hasConfirmedRestoreFromBackup
                {
                    return .quickRestore
                }
            case .manualRestore:
                if persistedState.restoreMethod == nil {
                    // If the restore method is nil, we need to ask for it,
                    // regardless of if the AEP is present or not.
                    return .manualRestore
                } else if
                    inMemoryState.accountEntropyPool == nil,
                    persistedState.restoreMethod != .declined
                {
                    // If the restore method is anything but declined, we need
                    // to ensure the AEP is present.
                    // (Otherwise, if the user has selected the normal registration
                    // path (restoreMethod == .declined), the AEP isn't necessarily required.
                    // If present, the AEP _can_ be used, otherwise PIN or SMS
                    // based registration will happen. 
                    return .manualRestore
                }
            case .none:
                if case .deviceTransfer = persistedState.restoreMethod {
                    return .quickRestore
                }
            }
        }
        if let session = inMemoryState.session {
            // If we have a session, always use that. We might have obtained SVR
            // credentials midway through a session (if we failed reglock when
            // trying to create the account with the session) so we don't want
            // their presence to override the session path.

            // Conversely, to get off the session path and keep going
            // to e.g. the profile setup, we _must_ clear out the session.
            return .session(session)
        }
        if let accountIdentity = persistedState.accountIdentity {
            // If we have an account identity, that means we already registered
            // or changed number, and we may need to do profile setup.
            // That path may finish right away if we have nothing to set up.
            return .profileSetup(accountIdentity)
        }
        // These paths are only available if the user knows their PIN.
        // If they skipped because they don't know it (or exhausted their guesses),
        // don't bother with them.
        if !persistedState.hasSkippedPinEntry {
            if let password = inMemoryState.regRecoveryPw {
                // If we have a reg recover password (but no session), try using that
                // to register.
                // Once again, to get off this path and fall back to session (if it fails)
                // or proceed to profile setup (if it succeeds) we must wipe this state.
                return .registrationRecoveryPassword(password: password)
            }
            if let credential = inMemoryState.svrAuthCredential {
                // If we have a validated SVR auth credential, try using that
                // to recover the SVR master key to register.
                // Once again, to get off this path and fall back to session (if it fails)
                // or proceed to reg recovery pw (if it succeeds) we must wipe this state.
                return .svrAuthCredential(credential)
            }
            if
                let svr2AuthCredentialCandidates = inMemoryState.svr2AuthCredentialCandidates,
                !svr2AuthCredentialCandidates.isEmpty
            {
                // If we have un-vetted candidates, try checking those first
                // and then going to the svrAuthCredential path if one is valid.
                return .svrAuthCredentialCandidates(
                    svr2AuthCredentialCandidates
                )
            }
        }

        // If we have no state to pull from whatsoever, go to the opening.
        return .opening

    }

    @MainActor
    private func nextStep(pathway: Pathway) async -> RegistrationStep {
        Logger.info("Going to next step for \(pathway.logSafeString) pathway")

        switch pathway {
        case .opening:
            return await nextStepForOpeningPath()
        case .quickRestore:
            return nextStepForQuickRestore()
        case .manualRestore:
            return nextStepForManualRestore()
        case .registrationRecoveryPassword(let password):
            return await nextStepForRegRecoveryPasswordPath(regRecoveryPw: password)
        case .svrAuthCredential(let credential):
            return await nextStepForSVRAuthCredentialPath(svrAuthCredential: credential)
        case .svrAuthCredentialCandidates(let svr2Candidates):
            return await nextStepForSVRAuthCredentialCandidatesPath(
                svr2AuthCredentialCandidates: svr2Candidates
            )
        case .session(let session):
            return await nextStepForSessionPath(session)
        case .profileSetup(let accountIdentity):
            return await nextStepForProfileSetup(accountIdentity)
        }
    }

    // MARK: - Opening Pathway

    @MainActor
    private func nextStepForOpeningPath() async -> RegistrationStep {
        if let splashStep = splashStepToShow() {
            return splashStep
        }
        if inMemoryState.needsSomePermissions {
            // This class is only used for primary device registration
            // which always needs contacts permissions.
            return .permissions
        }
        if inMemoryState.hasEnteredE164, let e164 = persistedState.e164 {
            return await startSession(e164: e164, failureCount: 0)
        }
        return .phoneNumberEntry(phoneNumberEntryState())
    }

    @MainActor
    private func nextStepForQuickRestore() -> RegistrationStep {
        guard
            inMemoryState.accountEntropyPool != nil,
            let registrationMessage = inMemoryState.registrationMessage
        else {
            return .scanQuickRegistrationQrCode
        }

        let backupTier: RegistrationStep.RestorePath.BackupTier? = switch registrationMessage.tier {
        case .free: .free
        case .paid: .paid
        case .none: nil
        }

        let platform: RegistrationStep.RestorePath.Platform = switch registrationMessage.platform {
        case .ios: .ios
        case .android: .android
        }

        switch persistedState.restoreMethod {
        case .deviceTransfer:
            if let restoreToken = registrationMessage.restoreMethodToken {
                let deviceTransferCoordinator = DeviceTransferCoordinator(
                    deviceTransferService: deps.deviceTransferService,
                    quickRestoreManager: deps.quickRestoreManager,
                    restoreMethodToken: restoreToken,
                    restoreMode: .primary
                )
                return .deviceTransfer(deviceTransferCoordinator)
            } else {
                return .scanQuickRegistrationQrCode
            }
        case .remoteBackup, .localBackup:
            // if backup, show the confirmation screen
            return .confirmRestoreFromBackup(
                RegistrationRestoreFromBackupConfirmationState(
                    mode: .quickRestore,
                    tier: registrationMessage.tier ?? .free,
                    lastBackupDate: registrationMessage.backupTimestamp.map(Date.init(millisecondsSince1970:)),
                    lastBackupSizeBytes: registrationMessage.backupSizeBytes.map(UInt.init)
                ))
        case .declined:
            // We shouldn't get back into the QuickRestore pathway after declining, so warn about it
            owsFailDebug("Quick restore declined, but attempting to ask for restore method again.")
            fallthrough
        case .none:
            return .chooseRestoreMethod(.quickRestore(backupTier, platform))
        }
    }

    @MainActor
    private func nextStepForManualRestore() -> RegistrationStep {
        if
            case .manualRestore = persistedState.restoreMode,
            persistedState.restoreMethod == nil
        {
            return .chooseRestoreMethod(.manualRestore)
        }

        // We need a phone number to proceed; ask the user if unavailable.
        if persistedState.e164 == nil {
            return .phoneNumberEntry(phoneNumberEntryState())
        }

        return .enterRecoveryKey(
            RegistrationEnterAccountEntropyPoolState(
                canShowBackButton: persistedState.accountIdentity == nil,
                canShowNoKeyHelpButton: true
            ))
    }

    private func splashStepToShow() -> RegistrationStep? {
        if persistedState.hasShownSplash {
            return nil
        }
        switch mode {
        case .registering:
            if persistedState.shouldSkipRegistrationSplash {
                return nil
            }
            return .registrationSplash
        case .changingNumber:
            return .changeNumberSplash
        case .reRegistering:
            return nil
        }
    }

    // MARK: - Registration Recovery Password Pathway

    /// If we have the SVR master key saved locally (e.g. this is re-registration), we can generate the
    /// "Registration Recovery Password" from it, which we can use as an alternative to a verified SMS code session
    /// to register. This path returns the steps to complete that flow.
    @MainActor
    private func nextStepForRegRecoveryPasswordPath(regRecoveryPw: String) async -> RegistrationStep {
        // We need a phone number to proceed; ask the user if unavailable.
        guard let e164 = persistedState.e164 else {
            return .phoneNumberEntry(phoneNumberEntryState())
        }

        if let askForPinStep = askForUserPINIfNeeded() {
            return askForPinStep
        }

        if inMemoryState.needsToAskForDeviceTransfer && persistedState.restoreMethod == nil {
            return .chooseRestoreMethod(.unspecified)
        } else if
            persistedState.restoreMethod?.isBackup == true,
            inMemoryState.accountEntropyPool == nil
        {
            // If the user chose 'restore from backup', ask them
            // for the AEP before continuing with registration
            return .enterRecoveryKey(
                RegistrationEnterAccountEntropyPoolState(
                    canShowBackButton: persistedState.accountIdentity == nil,
                    canShowNoKeyHelpButton: true
                ))
        }

        // Attempt to register right away with the password.
        return await registerForRegRecoveryPwPath(
            regRecoveryPw: regRecoveryPw,
            e164: e164
        )
    }

    private func askForUserPINIfNeeded() -> RegistrationStep? {
        // Don't bother with gathering the PIN if now if we already have an AEP
        // and we're going through a restore path
        guard inMemoryState.askForPinDuringReregistration else { return nil }

        guard let pinFromUser = inMemoryState.pinFromUser else {
            // We need the user to confirm their pin.
            return .pinEntry(RegistrationPinState(
                // We can skip which will stop trying to use reg recovery.
                operation: .enteringExistingPin(skippability: .canSkip, remainingAttempts: nil),
                error: nil,
                contactSupportMode: self.contactSupportRegistrationPINMode(),
                exitConfiguration: pinCodeEntryExitConfiguration()
            ))
        }

        if
            let pinFromDisk = inMemoryState.pinFromDisk,
            pinFromDisk != pinFromUser
        {
            Logger.warn("PIN mismatch; should be prevented at submission time.")
            return .pinEntry(RegistrationPinState(
                operation: .enteringExistingPin(skippability: .canSkip, remainingAttempts: nil),
                error: .wrongPin(wrongPin: pinFromUser),
                contactSupportMode: self.contactSupportRegistrationPINMode(),
                exitConfiguration: pinCodeEntryExitConfiguration()
            ))
        }
        return nil
    }

    private func registerForRegRecoveryPwPath(
        regRecoveryPw: String,
        e164: E164,
        failureCount: Int = 0,
    ) async -> RegistrationStep {
        let reglockToken = self.reglockToken(for: e164)
        return await makeRegisterOrChangeNumberRequest(
            .recoveryPassword(regRecoveryPw),
            e164: e164,
            reglockToken: reglockToken,
            responseHandler: { accountResponse in
                return await self.handleCreateAccountResponseFromRegRecoveryPassword(
                    accountResponse,
                    regRecoveryPw: regRecoveryPw,
                    e164: e164,
                    reglockToken: reglockToken,
                    failureCount: failureCount,
                )
            }
        )
    }

    @MainActor
    private func handleCreateAccountResponseFromRegRecoveryPassword(
        _ response: AccountResponse,
        regRecoveryPw: String,
        e164: E164,
        reglockToken: String?,
        failureCount: Int,
    ) async -> RegistrationStep {
        let maxAutomaticRetries = Constants.networkErrorRetries

        // NOTE: it is not possible for our e164 to be rejected here; the entire request
        // may be rejected for being malformed, but if the e164 is invalidly formatted
        // that will just look to the server like our reg recovery password is incorrect.
        // This shouldn't be possible in practice; we get here either by having had an
        // e164 from a previously registered account on this device, or by getting
        // confirmation from the auth credential check endpoint that the e164 was good.
        switch response {
        case .success(let identityResponse):
            // We have succeeded! Set the account identity response
            // so nextStep() will take us to the profile setup path.
            db.write { tx in
                updatePersistedState(tx) {
                    $0.accountIdentity = identityResponse
                }
            }
            return await nextStep()

        case .reglockFailure:
            if reglockToken == nil {
                // We failed reglock because we didn't even try it!
                // Try again with reglock included this time.
                db.write { tx in
                    self.updatePersistedState(tx) {
                        $0.e164WithKnownReglockEnabled = e164
                    }
                }
                return await nextStep()
            } else {
                // We tried our reglock token and it failed.
                switch mode {
                case .registering, .reRegistering:
                    // Both the reglock and the reg recovery password are derived from the SVR master key.
                    // Its weird that we'd get this response implying the recovery password is right
                    // but the reglock token is wrong, but lets assume our SVR master secret is just
                    // wrong entirely and reset _all_ SVR state so we go through sms verification.
                    db.write { tx in
                        // We want to wipe credentials on disk too; we don't want to retry it on next app launch.
                        // Its possible we tried svr2 and kbs has the right info, or vice versa, but this is all
                        // best effort anyway; just fall back to session-based registration.
                        deps.svrAuthCredentialStore.removeSVR2CredentialsForCurrentUser(tx)
                        // Clear the SVR master key locally; we failed reglock so we know its wrong
                        // and useless anyway.
                        deps.svr.clearKeys(transaction: tx)
                        deps.ows2FAManager.clearLocalPinCode(tx)
                        self.updatePersistedState(tx) {
                            $0.e164WithKnownReglockEnabled = e164
                        }
                    }
                case .changingNumber:
                    db.write { tx in
                        // If changing number we don't wanna wipe our SVR data;
                        // its still good for the previous number. just note the reglock
                        // and keep going.
                        self.updatePersistedState(tx) {
                            $0.e164WithKnownReglockEnabled = e164
                        }
                    }
                }
                // If changing number, we never want to wipe local our SVR secret.
                // Just pretend we don't have it by wiping

                wipeInMemoryStateToPreventSVRPathAttempts()

                // Start a session so we go down that path to recovery, challenging
                // the reglock we just failed so we can eventually get in.
                return await startSession(e164: e164, failureCount: 0)
            }

        case .rejectedVerificationMethod:
            // If the user attempted to register the account using an incorrect AEP (sourced either
            // from a QuickRestore registration message or manual entry), present an error, reset some
            // state, and route the user back to the key entry method used to get here.
            if
                let restoreMode = persistedState.restoreMode,
                inMemoryState.accountEntropyPool != nil
            {
                let result = await self.deps.registrationBackupErrorPresenter.presentError(
                    error: .incorrectRecoveryKey,
                    isQuickRestore: (restoreMode == .quickRestore)
                )
                switch result {
                case .skipRestore, .none:
                    owsFailDebug("Encountered unexpected recovery path for incorrect recovery key.")
                    fallthrough
                case .incorrectRecoveryKey, .tryAgain:
                    // If the user entered an incorrect key, remember the restore method and only
                    // prompt them to correct the key.  If they want to change the restore method,
                    // they should be able to hit 'back' here to return to the restore method selection.
                    return .enterRecoveryKey(.init(canShowBackButton: true, canShowNoKeyHelpButton: true))
                case .restartQuickRestore, .rateLimited:
                    // If restarting the QuickRestore flow, allow the user a chance to
                    // to choose the restore method again.
                    db.write { tx in
                        updatePersistedState(tx) {
                            $0.restoreMethod = nil
                        }
                    }
                    return .scanQuickRegistrationQrCode
                }
            }

            // The reg recovery password was wrong. This can happen for two reasons:
            // 1) We have the wrong SVR master key locally
            // 2) We have been reglock challenged, forcing us to re-register via session
            // If it were just the former case, we'd wipe our known-wrong SVR master key.
            // But the latter case means we want to go through session path registration,
            // and re-upload our local SVR master secret, so we don't want to wipe it.
            // (If we wiped it and our SVR server guesses were consumed by the reglock-challenger,
            // we'd be outta luck and have no way to recover).
            //
            // Because the master key can be much more fluid in an AEP world, there is a
            // much more common case that the SVR master key is wrong, but we can still fetch a
            // valid master key from SVR. To that point, don't clear out the SVR auth credentials here.
            // Instead, clear out just the piece of information we now know to be invalid to inform
            // the state machine to bypass any RRP attempts and fall back to fetching from SVR (or
            // restoring to starting a session from scratch)
            //
            // However, we should only attempt to restore from SVR once. If we successfully restore
            // from SVR, and still encounter this error, we
            // (a) have already restored so don't need the svrCredentials any longer, and
            // (b) should revert back to session based registration.
            if persistedState.hasRestoredFromSVR {
                db.write { tx in
                    // We do want to clear out any credentials permanently; we know we
                    // have to use the session path so credentials aren't helpful.
                    if let svr2Credential = inMemoryState.svrAuthCredential {
                        deps.svrAuthCredentialStore.deleteInvalidCredentials([svr2Credential], tx)
                    }
                }
                wipeInMemoryStateToPreventSVRPathAttempts()
            } else {
                inMemoryState.regRecoveryPw = nil
            }

            // Instead of moving directly to starting a session, like we do in the .reglockFailed case above,
            // let the state machine determine next steps.  It may be the user had a bad
            // local key, and can still fetch from SVR.  If we attempt to refetch SVR credentials and fail,
            // we'll implicitly end up in the startSession() state anyway.
            return await nextStep()

        case .retryAfter(let timeInterval):
            if failureCount < maxAutomaticRetries, let timeInterval, timeInterval < Constants.autoRetryInterval {
                let minimumBackoff = OWSOperation.retryIntervalForExponentialBackoff(failureCount: failureCount + 1)
                try? await Task.sleep(nanoseconds: max(timeInterval, minimumBackoff).clampedNanoseconds)
                return await registerForRegRecoveryPwPath(
                    regRecoveryPw: regRecoveryPw,
                    e164: e164,
                    failureCount: failureCount + 1,
                )
            }
            // If we get a long/infinite timeout, just give up and fall back to the
            // session path. Reg recovery password based recovery is best effort
            // anyway. Besides since this is always our first attempt at registering,
            // this lockout should never happen.
            Logger.error("Rate limited when registering via recovery password; falling back to session.")
            wipeInMemoryStateToPreventSVRPathAttempts()
            return await startSession(e164: e164, failureCount: 0)

        case .deviceTransferPossible:
            // Device transfer can happen, let the user pick.
            inMemoryState.needsToAskForDeviceTransfer = true
            return await nextStep()

        case .networkError:
            if failureCount < maxAutomaticRetries {
                let minimumBackoff = OWSOperation.retryIntervalForExponentialBackoff(failureCount: failureCount + 1)
                try? await Task.sleep(nanoseconds: minimumBackoff.clampedNanoseconds)
                return await registerForRegRecoveryPwPath(
                    regRecoveryPw: regRecoveryPw,
                    e164: e164,
                    failureCount: failureCount + 1,
                )
            }
            return .showErrorSheet(.networkError)

        case .genericError:
            return .showErrorSheet(.genericError)
        }
    }

    private func loadSVRAuthCredentialCandidates(_ tx: DBReadTransaction) {
        let svr2AuthCredentialCandidates: [SVR2AuthCredential] = deps.svrAuthCredentialStore.getAuthCredentials(tx)
        if svr2AuthCredentialCandidates.isEmpty.negated {
            inMemoryState.svr2AuthCredentialCandidates = svr2AuthCredentialCandidates
        }
    }

    private func wipeInMemoryStateToPreventSVRPathAttempts() {
        inMemoryState.regRecoveryPw = nil
        inMemoryState.shouldRestoreSVRMasterKeyAfterRegistration = true
        // Wiping auth credential state too. It's possible that the remote master key is current
        // even if our local one is outdated, so we'll make a note to restore the remote one after
        // registration. For the time being, we can move forward without the master key.
        inMemoryState.svrAuthCredential = nil
        inMemoryState.svr2AuthCredentialCandidates = nil
    }

    // MARK: - SVR Auth Credential Pathway

    /// If we don't have the SVR master key saved locally but we do have a SVR auth credential,
    /// we can use it to talk to the SVR server and, together with the user-entered PIN, recover the
    /// full SVR master key. Then we use the Registration Recovery Password registration flow.
    /// (If we had the SVR master key saved locally to begin with, we would have just used it right away.)
    @MainActor
    private func nextStepForSVRAuthCredentialPath(
        svrAuthCredential: SVRAuthCredential
    ) async -> RegistrationStep {
        guard let pin = inMemoryState.pinFromUser else {
            // We don't have a pin at all, ask the user for it.
            return .pinEntry(RegistrationPinState(
                operation: .enteringExistingPin(skippability: .canSkip, remainingAttempts: nil),
                error: nil,
                contactSupportMode: contactSupportRegistrationPINMode(),
                exitConfiguration: pinCodeEntryExitConfiguration()
            ))
        }

        return await restoreSVRMasterSecretForAuthCredentialPath(
            pin: pin,
            credential: svrAuthCredential,
            failureCount: 0,
        )
    }

    @MainActor
    private func restoreSVRMasterSecretForAuthCredentialPath(
        pin: String,
        credential: SVRAuthCredential,
        failureCount: Int,
    ) async -> RegistrationStep {
        let maxAutomaticRetries = Constants.networkErrorRetries

        let result = await deps.svr.restoreKeys(pin: pin, authMethod: .svrAuth(credential, backup: nil)).awaitable()

        switch result {
        case .success(let masterKey):
            db.write {
                updatePersistedState($0) { state in
                    state.recoveredSVRMasterKey = masterKey
                    state.hasRestoredFromSVR = true
                }
                updateMasterKeyAndLocalState(masterKey: masterKey, tx: $0)
            }
            return await nextStep()
        case let .invalidPin(remainingAttempts):
            return .pinEntry(RegistrationPinState(
                operation: .enteringExistingPin(
                    skippability: .canSkip,
                    remainingAttempts: UInt(remainingAttempts)
                ),
                error: .wrongPin(wrongPin: pin),
                contactSupportMode: contactSupportRegistrationPINMode(),
                exitConfiguration: pinCodeEntryExitConfiguration()
            ))
        case .backupMissing:
            // If we are unable to talk to SVR, it got wiped and we can't
            // recover. Give it all up and wipe our SVR info.
            wipeInMemoryStateToPreventSVRPathAttempts()
            inMemoryState.pinFromUser = nil
            db.write { tx in
                self.updatePersistedState(tx) {
                    $0.hasGivenUpTryingToRestoreWithSVR = true
                }
            }
            return .pinAttemptsExhaustedWithoutReglock(
                .init(mode: .restoringRegistrationRecoveryPassword)
            )

        case .networkError:
            if failureCount < maxAutomaticRetries {
                let minimumBackoff = OWSOperation.retryIntervalForExponentialBackoff(failureCount: failureCount + 1)
                try? await Task.sleep(nanoseconds: minimumBackoff.clampedNanoseconds)
                return await restoreSVRMasterSecretForAuthCredentialPath(
                    pin: pin,
                    credential: credential,
                    failureCount: failureCount + 1,
                )
            }
            return .showErrorSheet(.networkError)
        case .genericError:
            if failureCount < maxAutomaticRetries {
                let minimumBackoff = OWSOperation.retryIntervalForExponentialBackoff(failureCount: failureCount + 1)
                try? await Task.sleep(nanoseconds: minimumBackoff.clampedNanoseconds)
                return await restoreSVRMasterSecretForAuthCredentialPath(
                    pin: pin,
                    credential: credential,
                    failureCount: failureCount + 1,
                )
            } else {
                inMemoryState.pinFromUser = nil
                return .pinEntry(RegistrationPinState(
                    operation: .enteringExistingPin(skippability: .canSkip, remainingAttempts: nil),
                    error: .serverError,
                    contactSupportMode: contactSupportRegistrationPINMode(),
                    exitConfiguration: pinCodeEntryExitConfiguration()
                ))
            }
        }
    }

    private func updateMasterKeyAndLocalState(masterKey: MasterKey?, tx: DBWriteTransaction) {
        let localMasterKey = masterKey
        let regRecoveryPw = localMasterKey?.data(
            for: .registrationRecoveryPassword
        ).canonicalStringRepresentation
        inMemoryState.regRecoveryPw = regRecoveryPw
        if regRecoveryPw != nil {
            updatePersistedState(tx) { $0.shouldSkipRegistrationSplash = true }
        }
        inMemoryState.reglockToken = localMasterKey?.data(
            for: .registrationLock
        ).canonicalStringRepresentation
        // If we have a local master key, theres no need to restore after registration.
        // (we will still back up though)
        inMemoryState.shouldRestoreSVRMasterKeyAfterRegistration = localMasterKey == nil
        inMemoryState.didHaveSVRBackupsPriorToReg = deps.svr.hasBackedUpMasterKey(transaction: tx)
    }

    // MARK: - SVR Auth Credential Candidates Pathway

    @MainActor
    private func nextStepForSVRAuthCredentialCandidatesPath(
        svr2AuthCredentialCandidates: [SVR2AuthCredential]
    ) async -> RegistrationStep {
        guard let e164 = persistedState.e164 else {
            // If we haven't entered a phone number but we have auth
            // credential candidates to check, enter it now.
            return .phoneNumberEntry(phoneNumberEntryState())
        }
        return await makeSVR2AuthCredentialCheckRequest(
            svr2AuthCredentialCandidates: svr2AuthCredentialCandidates,
            e164: e164,
            failureCount: 0,
        )
    }

    @MainActor
    private func makeSVR2AuthCredentialCheckRequest(
        svr2AuthCredentialCandidates: [SVR2AuthCredential],
        e164: E164,
        failureCount: Int,
    ) async -> RegistrationStep {
        let response = await Service.makeSVR2AuthCheckRequest(
            e164: e164,
            candidateCredentials: svr2AuthCredentialCandidates,
            signalService: deps.signalService,
        )
        return await self.handleSVR2AuthCredentialCheckResponse(
            response,
            svr2AuthCredentialCandidates: svr2AuthCredentialCandidates,
            e164: e164,
            failureCount: failureCount,
        )
    }

    @MainActor
    private func handleSVR2AuthCredentialCheckResponse(
        _ response: Service.SVR2AuthCheckResponse,
        svr2AuthCredentialCandidates: [SVR2AuthCredential],
        e164: E164,
        failureCount: Int,
    ) async -> RegistrationStep {
        let maxAutomaticRetries = Constants.networkErrorRetries

        var matchedCredential: SVR2AuthCredential?
        var credentialsToDelete = [SVR2AuthCredential]()
        switch response {
        case .networkError:
            if failureCount < maxAutomaticRetries {
                let minimumBackoff = OWSOperation.retryIntervalForExponentialBackoff(failureCount: failureCount + 1)
                try? await Task.sleep(nanoseconds: minimumBackoff.clampedNanoseconds)
                return await makeSVR2AuthCredentialCheckRequest(
                    svr2AuthCredentialCandidates: svr2AuthCredentialCandidates,
                    e164: e164,
                    failureCount: failureCount + 1,
                )
            }
            self.inMemoryState.svr2AuthCredentialCandidates = nil
            return await nextStep()
        case .genericError:
            // If we failed to verify, wipe the candidates so we don't try again
            // and keep going.
            self.inMemoryState.svr2AuthCredentialCandidates = nil
            return await nextStep()
        case .success(let response):
            for candidate in svr2AuthCredentialCandidates {
                let result: RegistrationServiceResponses.SVR2AuthCheckResponse.Result? = response.result(for: candidate)
                switch result {
                case .match:
                    matchedCredential = candidate
                case .notMatch:
                    // Still valid, keep it around but don't use it.
                    continue
                case .invalid, .none:
                    credentialsToDelete.append(candidate)
                }
            }
        }
        // Wipe the candidates so we don't re-check them.
        self.inMemoryState.svr2AuthCredentialCandidates = nil
        // If this is nil, the next time we call `nextStepForSVRAuthCredentialPath`
        // will just return an empty promise.

        self.inMemoryState.svrAuthCredential = matchedCredential
        self.db.write { tx in
            self.deps.svrAuthCredentialStore.deleteInvalidCredentials(credentialsToDelete, tx)
        }
        return await nextStep()
    }

    // MARK: - RegistrationSession Pathway

    @MainActor
    private func nextStepForSessionPath(_ session: RegistrationSession) async -> RegistrationStep {
        switch persistedState.sessionState?.reglockState ?? .none {
        case .none:
            break
        case let .reglocked(svrAuthCredential, reglockExpirationDate):
            guard let svrAuthCredential = svrAuthCredential.svr2 else {
                // If we don't have a useable credential, we are stuck.
                db.write { tx in
                    self.updatePersistedSessionState(session: session, tx) {
                        $0.reglockState = .waitingTimeout(expirationDate: reglockExpirationDate)
                    }
                }
                return await nextStep()
            }

            // If the user has already supplied an AEP, this should be possible to use
            if let aep = inMemoryState.accountEntropyPool {
                self.db.write { tx in
                    let masterKey = aep.getMasterKey()
                    self.updatePersistedState(tx) {
                        $0.recoveredSVRMasterKey = masterKey
                        $0.hasGivenUpTryingToRestoreWithSVR = true
                    }
                    self.updatePersistedSessionState(session: session, tx) {
                        // Now we have the state we need to get past reglock.
                        $0.reglockState = .none
                    }
                }
                return await nextStep()
            } else if let pinFromUser = inMemoryState.pinFromUser {
                // Otherwise, if the user has a PIN, restore the master key from SVR
                return await restoreSVRMasterSecretForSessionPathReglock(
                    session: session,
                    pin: pinFromUser,
                    svrAuthCredential: svrAuthCredential,
                    reglockExpirationDate: reglockExpirationDate,
                    failureCount: 0,
                )
            } else {
                // And, if none of the above is true, go ahead and prompt for the users PIN
                return .pinEntry(RegistrationPinState(
                    operation: .enteringExistingPin(
                        skippability: .unskippable,
                        remainingAttempts: nil
                    ),
                    error: .none,
                    contactSupportMode: contactSupportRegistrationPINMode(),
                    exitConfiguration: pinCodeEntryExitConfiguration()
                ))
            }
        case .waitingTimeout(let reglockExpirationDate):
            if deps.dateProvider() >= reglockExpirationDate {
                // We've passed the time needed and reglock should be expired.
                // Wipe our state and proceed.
                db.write { tx in
                    self.updatePersistedSessionState(session: session, tx) {
                        $0.reglockState = .none
                    }
                }
                return await nextStep()
            }
            return .reglockTimeout(RegistrationReglockTimeoutState(
                reglockExpirationDate: reglockExpirationDate,
                acknowledgeAction: reglockTimeoutAcknowledgeAction
            ))
        }

        if inMemoryState.needsToAskForDeviceTransfer && !persistedState.hasDeclinedTransfer {
            return .chooseRestoreMethod(.unspecified)
        }

        if session.verified {
            // We have to complete registration.
            return await makeRegisterOrChangeNumberRequestFromSession(session, failureCount: 0)
        }

        // We show the code entry screen if we've ever tried sending
        // a verification code, even if that send failed.
        // Note we will re-emit validation errors on every `nextStep()` call,
        // and it is up to the view controller to ignore duplicates.
        let shouldShowCodeEntryStep: Bool
        let codeEntryValidationError: RegistrationVerificationValidationError?
        var pendingCodeTransport = inMemoryState.pendingCodeTransport

        switch persistedState.sessionState?.initialCodeRequestState {
        case .none:
            shouldShowCodeEntryStep = false
            codeEntryValidationError = nil

        case .neverRequested:
            shouldShowCodeEntryStep = false
            codeEntryValidationError = nil
            if pendingCodeTransport == nil {
                // If we've never requested a code before, and aren't about to,
                // we should automatically request an sms code.
                pendingCodeTransport = .sms
            }

        case .requested:
            shouldShowCodeEntryStep = true
            codeEntryValidationError = nil

        case .smsTransportFailed:
            shouldShowCodeEntryStep = true
            codeEntryValidationError = .failedInitialTransport(failedTransport: .sms)
        case .transientProviderFailure:
            shouldShowCodeEntryStep = true
            codeEntryValidationError = .providerFailure(isPermanent: false)
        case .permanentProviderFailure:
            shouldShowCodeEntryStep = true
            codeEntryValidationError = .providerFailure(isPermanent: true)
        case .exhaustedCodeAttempts:
            shouldShowCodeEntryStep = true
            codeEntryValidationError = .submitCodeTimeout
        case .failedToRequest:
            shouldShowCodeEntryStep = true
            codeEntryValidationError = .genericCodeRequestError(isNetworkError: false)
        }

        // If we have a pending transport to which we want to send a code,
        // try and do that, regardless of other state.
        if let pendingCodeTransport {
            guard session.allowedToRequestCode else {
                return await attemptToFulfillAvailableChallengesWaitingIfNeeded(for: session)
            }

            // If we have pending transport and can send, send.
            switch pendingCodeTransport {
            case .sms:
                if let nextSMSDate = session.nextSMSDate, nextSMSDate <= deps.dateProvider() {
                    return await requestSessionCode(session: session, transport: pendingCodeTransport, failureCount: 0)
                } else {
                    // Inability to send puts on the verification entry screen, so the
                    // user can try the alternate transport manually.
                    return .verificationCodeEntry(verificationCodeEntryState(
                        session: session,
                        validationError: .smsResendTimeout
                    ))
                }
            case .voice:
                if let nextCallDate = session.nextCallDate, nextCallDate <= deps.dateProvider() {
                    return await requestSessionCode(session: session, transport: pendingCodeTransport, failureCount: 0)
                } else {
                    // Inability to send puts on the verification entry screen, so the
                    // user can try the alternate transport manually.
                    return .verificationCodeEntry(verificationCodeEntryState(
                        session: session,
                        validationError: .voiceResendTimeout
                    ))
                }
            }
        }

        if shouldShowCodeEntryStep {
            return .verificationCodeEntry(verificationCodeEntryState(
                session: session,
                validationError: codeEntryValidationError
            ))
        }

        // Otherwise we have no code awaiting submission and aren't
        // trying to send one yet, so just go to phone number entry.
        return .phoneNumberEntry(phoneNumberEntryState())
    }

    private func processSession(
        _ session: RegistrationSession?,
        initialCodeRequestState: PersistedState.SessionState.InitialCodeRequestState? = nil,
        _ transaction: DBWriteTransaction
    ) {
        if session == nil || persistedState.sessionState?.sessionId != session?.id {
            self.updatePersistedState(transaction) {
                $0.sessionState = session.map { .init(sessionId: $0.id) }
            }
        }
        var newInitialCodeRequestState = initialCodeRequestState
        if session?.nextVerificationAttempt != nil {
            // If we can submit a code, we must have requested
            // at least once.
            newInitialCodeRequestState = .requested
        }
        let oldInitialCodeRequestState = persistedState.sessionState?.initialCodeRequestState
        switch (oldInitialCodeRequestState, newInitialCodeRequestState) {
        case
                (.none, _),
                (.smsTransportFailed, _),
                (.transientProviderFailure, _),
                (.permanentProviderFailure, _),
                (.failedToRequest, _),
                (.neverRequested, _),
                (.exhaustedCodeAttempts, _),
                (.requested, .exhaustedCodeAttempts):
            if let newInitialCodeRequestState, newInitialCodeRequestState != persistedState.sessionState?.initialCodeRequestState {
                self.updatePersistedState(transaction) {
                    var sessionState = $0.sessionState
                    sessionState?.initialCodeRequestState = newInitialCodeRequestState
                    $0.sessionState = sessionState
                }
            }
        case (.requested, _):
            // Don't overwrite already requested state under any circumstances.
            break
        }

        if session?.verified == true {
            // Any verified session is good and we should keep it.
            inMemoryState.session = session
            return
        }

        if
            let session,
            // If we can't submit a code...
            session.nextVerificationAttempt == nil,
            // Can't request a code (and can't do any challenges to move on)...
            (!session.allowedToRequestCode && session.requestedInformation.isEmpty),
            // And have exhausted our ability to request codes...
            session.nextSMS == nil,
            session.nextCall == nil
        {
            // Then this session is incapable of being verified, and we should
            // discard it.

            // UNLESS it has an unknown challenge type on it.
            // In this case, the session might still be good, and we want to
            // alert the user instead of discarding.
            if session.hasUnknownChallengeRequiringAppUpdate {
                inMemoryState.session = session
                return
            } else {
                self.resetSession(transaction)
                return
            }
        }
        inMemoryState.session = session
    }

    private func resetSession(_ transaction: DBWriteTransaction) {
        inMemoryState.session = nil
        inMemoryState.pendingCodeTransport = nil
        // Force the user to enter an e164 again
        // when making a new session.
        inMemoryState.hasEnteredE164 = false
        self.updatePersistedState(transaction) {
            $0.sessionState = nil
        }
        self.deps.sessionManager.clearPersistedSession(transaction)
    }

    @MainActor
    private func makeRegisterOrChangeNumberRequestFromSession(
        _ session: RegistrationSession,
        failureCount: Int,
    ) async -> RegistrationStep {
        if
            let timeoutDate = persistedState.sessionState?.createAccountTimeout,
            deps.dateProvider() < timeoutDate
        {
            return .phoneNumberEntry(phoneNumberEntryState(
                validationError: .rateLimited(.init(
                    expiration: timeoutDate,
                    e164: session.e164
                ))
            ))
        }
        let reglockToken = reglockToken(for: session.e164)
        return await makeRegisterOrChangeNumberRequest(
            .sessionId(session.id),
            e164: session.e164,
            reglockToken: reglockToken,
            responseHandler: { accountResponse in
                return await self.handleCreateAccountResponseFromSession(
                    accountResponse,
                    sessionFromBeforeRequest: session,
                    reglockTokenUsedInRequest: reglockToken,
                    failureCount: failureCount,
                )
            }
        )
    }

    @MainActor
    private func handleCreateAccountResponseFromSession(
        _ response: AccountResponse,
        sessionFromBeforeRequest: RegistrationSession,
        reglockTokenUsedInRequest: String?,
        failureCount: Int,
    ) async -> RegistrationStep {
        let maxAutomaticRetries = Constants.networkErrorRetries

        switch response {
        case .success(let identityResponse):
            inMemoryState.session = nil
            db.write { tx in
                // We can clear the session now!
                deps.sessionManager.clearPersistedSession(tx)
                updatePersistedState(tx) {
                    $0.accountIdentity = identityResponse
                    $0.sessionState = nil
                    // If PIN entry was skipped before registering,
                    // reset this to false so the user is asked to create a
                    // PIN, or disable PINs entirely
                    $0.hasSkippedPinEntry = false
                }
            }
            // Should take us to the profile setup flow since
            // the identity response is set.
            return await nextStep()
        case .reglockFailure(let reglockFailure):
            let reglockExpirationDate = self.deps.dateProvider().addingTimeInterval(TimeInterval(reglockFailure.timeRemainingMs / 1000))
            guard persistedState.hasGivenUpTryingToRestoreWithSVR.negated else {
                // If we have already exhausted our SVR backup attempts, we are stuck.
                db.write { tx in
                    // May as well store credentials, anyway.
                    deps.svrAuthCredentialStore.storeAuthCredentialForCurrentUsername(
                        reglockFailure.svr2AuthCredential,
                        tx
                    )
                    self.updatePersistedSessionState(session: sessionFromBeforeRequest, tx) {
                        $0.reglockState = .waitingTimeout(expirationDate: reglockExpirationDate)
                    }
                    self.updatePersistedState(tx) {
                        $0.e164WithKnownReglockEnabled = sessionFromBeforeRequest.e164
                    }
                }
                return await nextStep()
            }
            // We need the user to enter their PIN so we can get through reglock.
            // So we set up the state we need (the SVR credential)
            // and go to the next step which should look at the state and take us to the right place.
            if reglockTokenUsedInRequest != nil {
                // We were already trying reglock, and the token was wrong.
                // that means the whole thing is stuck. wait out the reglock.
                db.write { tx in
                    // May as well store credentials, anyway.
                    deps.svrAuthCredentialStore.storeAuthCredentialForCurrentUsername(
                        reglockFailure.svr2AuthCredential,
                        tx
                    )
                    self.updatePersistedSessionState(session: sessionFromBeforeRequest, tx) {
                        $0.reglockState = .waitingTimeout(expirationDate: reglockExpirationDate)
                    }
                    self.updatePersistedState(tx) {
                        $0.e164WithKnownReglockEnabled = sessionFromBeforeRequest.e164
                    }
                }
                return await nextStep()
            } else {
                let persistedCredential = PersistedState.SessionState.ReglockState.SVRAuthCredential(
                    svr2: reglockFailure.svr2AuthCredential
                )
                db.write { tx in
                    deps.svrAuthCredentialStore.storeAuthCredentialForCurrentUsername(reglockFailure.svr2AuthCredential, tx)
                    self.updatePersistedSessionState(session: sessionFromBeforeRequest, tx) {
                        $0.reglockState = .reglocked(
                            credential: persistedCredential,
                            expirationDate: reglockExpirationDate
                        )
                    }
                    self.updatePersistedState(tx) {
                        $0.e164WithKnownReglockEnabled = sessionFromBeforeRequest.e164
                        // If we skipped for reg recovery, unskip now.
                        $0.hasSkippedPinEntry = false
                    }
                }
                return await nextStep()
            }

        case .rejectedVerificationMethod:
            // The session is invalid; we have to wipe it and potentially start again.
            db.write { self.resetSession($0) }
            return await nextStep()

        case .retryAfter(let timeInterval):
            if failureCount < maxAutomaticRetries, let timeInterval, timeInterval < Constants.autoRetryInterval {
                let minimumBackoff = OWSOperation.retryIntervalForExponentialBackoff(failureCount: failureCount + 1)
                try? await Task.sleep(nanoseconds: max(timeInterval, minimumBackoff).clampedNanoseconds)
                return await self.makeRegisterOrChangeNumberRequestFromSession(
                    sessionFromBeforeRequest,
                    failureCount: failureCount + 1,
                )
            }
            if let timeInterval {
                let timeoutDate = self.deps.dateProvider().addingTimeInterval(max(timeInterval, 15))
                self.db.write { tx in
                    self.updatePersistedSessionState(session: sessionFromBeforeRequest, tx) {
                        $0.createAccountTimeout = timeoutDate
                    }
                }
            } else {
                db.write { self.resetSession($0) }
            }
            return await nextStep()
        case .deviceTransferPossible:
            inMemoryState.needsToAskForDeviceTransfer = true
            return .chooseRestoreMethod(.unspecified)
        case .networkError:
            if failureCount < maxAutomaticRetries {
                let minimumBackoff = OWSOperation.retryIntervalForExponentialBackoff(failureCount: failureCount + 1)
                try? await Task.sleep(nanoseconds: minimumBackoff.clampedNanoseconds)
                return await self.makeRegisterOrChangeNumberRequestFromSession(
                    sessionFromBeforeRequest,
                    failureCount: failureCount + 1,
                )
            }
            return .showErrorSheet(.networkError)
        case .genericError:
            return .showErrorSheet(.genericError)
        }
    }

    @MainActor
    private func startSession(
        e164: E164,
        failureCount: Int,
    ) async -> RegistrationStep {
        let maxAutomaticRetries = Constants.networkErrorRetries

        let tokenResult = await deps.pushRegistrationManager.requestPushToken()
        let apnsToken: String?
        switch tokenResult {
        case .success(let tokens):
            apnsToken = tokens.apnsToken
        case .pushUnsupported, .timeout, .genericError:
            apnsToken = nil
        }
        let response = await deps.sessionManager.beginOrRestoreSession(
            e164: e164,
            apnsToken: apnsToken
        )

        switch response {
        case .success(let session):
            db.write { transaction in
                self.processSession(session, transaction)

                if apnsToken == nil {
                    self.noPreAuthChallengeTokenWillArrive(
                        session: session,
                        transaction: transaction
                    )
                } else {
                    self.prepareToReceivePreAuthChallengeToken(
                        session: session,
                        transaction: transaction
                    )
                }
            }

            return await nextStep()
        case .invalidArgument:
            return .phoneNumberEntry(phoneNumberEntryState(
                validationError: .invalidE164(.init(invalidE164: e164))
            ))
        case .retryAfter(let timeInterval):
            if failureCount < maxAutomaticRetries, let timeInterval, timeInterval < Constants.autoRetryInterval {
                let minimumBackoff = OWSOperation.retryIntervalForExponentialBackoff(failureCount: failureCount + 1)
                try? await Task.sleep(nanoseconds: max(timeInterval, minimumBackoff).clampedNanoseconds)
                return await startSession(e164: e164, failureCount: failureCount + 1)
            }
            return .phoneNumberEntry(phoneNumberEntryState(
                validationError: .rateLimited(.init(
                    expiration: deps.dateProvider().addingTimeInterval(max(timeInterval ?? 15, 15)),
                    e164: e164
                )),
            ))
        case .networkFailure:
            if failureCount < maxAutomaticRetries {
                let minimumBackoff = OWSOperation.retryIntervalForExponentialBackoff(failureCount: failureCount + 1)
                try? await Task.sleep(nanoseconds: minimumBackoff.clampedNanoseconds)
                return await startSession(e164: e164, failureCount: failureCount + 1)
            }
            return .showErrorSheet(.networkError)
        case .genericError:
            return .showErrorSheet(.genericError)
        }
    }

    @MainActor
    private func requestSessionCode(
        session: RegistrationSession,
        transport: Registration.CodeTransport,
        failureCount: Int,
    ) async -> RegistrationStep {
        let maxAutomaticRetries = Constants.networkErrorRetries

        let result = await self.deps.sessionManager.requestVerificationCode(
            for: session,
            transport: transport
        )

        switch result {
        case .success(let session):
            inMemoryState.pendingCodeTransport = nil
            db.write {
                self.processSession(session, initialCodeRequestState: .requested, $0)
            }
            return await nextStep()
        case .rejectedArgument(let session):
            Logger.error("Should never get rejected argument error from requesting code. E164 already set on session.")
            // Wipe the pending code request, so we don't retry.
            inMemoryState.pendingCodeTransport = nil
            db.write {
                self.processSession(session, initialCodeRequestState: .failedToRequest, $0)
            }
            return await nextStep()
        case .disallowed(let session):
            // Whatever caused this should be represented on the session itself,
            // and once we unblock we should retry sending so don't clear the pending
            // code transport.
            db.write { self.processSession(session, $0) }
            return await nextStep()
        case .transportError(let session):
            // We failed with the current transport, but another transport
            // might work.
            db.write { self.processSession(session, initialCodeRequestState: .smsTransportFailed, $0) }
            // Wipe the pending code request, so we don't auto-retry.
            inMemoryState.pendingCodeTransport = nil
            return await nextStep()
        case .invalidSession:
            self.inMemoryState.pendingCodeTransport = nil
            self.db.write { self.resetSession($0) }
            return .showErrorSheet(.sessionInvalidated)
        case .serverFailure(let failureResponse):
            db.write { tx in
                self.processSession(
                    session,
                    initialCodeRequestState: failureResponse.isPermanent
                    ? .permanentProviderFailure
                    : .transientProviderFailure,
                    tx
                )
            }
            // Wipe the pending code request, so we don't auto-retry.
            inMemoryState.pendingCodeTransport = nil
            return await nextStep()
        case .retryAfterTimeout(let session, let retryAfterHeader):
            let timeInterval: TimeInterval?
            switch transport {
            case .sms:
                timeInterval = session.nextSMS
            case .voice:
                timeInterval = session.nextCall
            }
            if
                failureCount < maxAutomaticRetries,
                session.allowedToRequestCode,
                let timeInterval,
                timeInterval < Constants.autoRetryInterval,
                let retryAfterHeader,
                retryAfterHeader < Constants.autoRetryInterval
            {
                self.db.write { self.processSession(session, $0) }
                let minimumBackoff = OWSOperation.retryIntervalForExponentialBackoff(failureCount: failureCount + 1)
                try? await Task.sleep(nanoseconds: max(timeInterval, retryAfterHeader, minimumBackoff).clampedNanoseconds)
                return await requestSessionCode(
                    session: session,
                    transport: transport,
                    failureCount: failureCount + 1,
                )
            } else {
                inMemoryState.pendingCodeTransport = nil
                if session.nextVerificationAttemptDate != nil {
                    db.write {
                        self.processSession(session, initialCodeRequestState: .requested, $0)
                    }
                    // Show an error on the verification code entry screen.
                    return .verificationCodeEntry(verificationCodeEntryState(
                        session: session,
                        validationError: {
                            switch transport {
                            case .sms: return .smsResendTimeout
                            case .voice: return .voiceResendTimeout
                            }
                        }()
                    ))
                } else if session.allowedToRequestCode, let timeInterval {
                    db.write {
                        self.processSession(session, initialCodeRequestState: .failedToRequest, $0)
                    }
                    // We were trying to resend from the phone number screen.
                    return .phoneNumberEntry(self.phoneNumberEntryState(
                        validationError: .rateLimited(.init(
                            expiration: self.deps.dateProvider().addingTimeInterval(max(timeInterval, 15)),
                            e164: session.e164
                        )),
                    ))
                } else {
                    // Can't send a code, session is useless.
                    db.write { self.resetSession($0) }
                    return .showErrorSheet(.sessionInvalidated)
                }
            }
        case .networkFailure:
            if failureCount < maxAutomaticRetries {
                let minimumBackoff = OWSOperation.retryIntervalForExponentialBackoff(failureCount: failureCount + 1)
                try? await Task.sleep(nanoseconds: minimumBackoff.clampedNanoseconds)
                return await requestSessionCode(
                    session: session,
                    transport: transport,
                    failureCount: failureCount + 1,
                )
            }
            inMemoryState.pendingCodeTransport = nil
            db.write {
                self.processSession(session, initialCodeRequestState: .failedToRequest, $0)
            }
            return .showErrorSheet(.networkError)
        case .genericError:
            inMemoryState.pendingCodeTransport = nil
            db.write {
                self.processSession(session, initialCodeRequestState: .failedToRequest, $0)
            }
            return .showErrorSheet(.genericError)
        }
    }

    private func noPreAuthChallengeTokenWillArrive(
        session: RegistrationSession,
        transaction: DBWriteTransaction
    ) {
        switch persistedState.sessionState?.pushChallengeState {
        case nil, .notRequested, .waitingForPush, .rejected:
            Logger.info("No pre-auth challenge token will arrive. Noting that")
            updatePersistedSessionState(session: session, transaction) {
                $0.pushChallengeState = .ineligible
            }
        case .ineligible, .unfulfilledPush, .fulfilled:
            Logger.info("No pre-auth challenge token will arrive, but we don't need to update our state")
        }
    }

    private func prepareToReceivePreAuthChallengeToken(
        session: RegistrationSession,
        transaction: DBWriteTransaction
    ) {
        switch persistedState.sessionState?.pushChallengeState {
        case nil, .notRequested, .ineligible, .rejected:
            // It's unlikely but possible to go from ineligible -> waiting if the user denied
            // notification permissions, closed the app, re-enabled them in settings, and then
            // relaunched. It's much more likely that we'd be in the "not requested" state.
            Logger.info("Started waiting for a pre-auth challenge token")
            self.updatePersistedSessionState(session: session, transaction) {
                $0.pushChallengeState = .waitingForPush(requestedAt: deps.dateProvider())
            }
        case .waitingForPush, .unfulfilledPush, .fulfilled:
            Logger.info("Already waiting for a pre-auth challenge token, presumably from a prior launch")
        }

        // There is no timeout on this promise. That's deliberate. If we get a push challenge token
        // at some point, we'd like to hold onto it, even if it took awhile to arrive. Other spots
        // in the code may handle a timeout.
        Guarantee.wrapAsync { await self.deps.pushRegistrationManager.receivePreAuthChallengeToken() }
            .done(on: DispatchQueue.main) { [weak self] token in
                guard let self else { return }
                self.db.write { transaction in
                    self.didReceive(pushChallengeToken: token, for: session, transaction: transaction)
                }
            }
    }

    private func didReceive(
        pushChallengeToken: String,
        for session: RegistrationSession,
        transaction: DBWriteTransaction
    ) {
        deps.pushRegistrationManager.clearPreAuthChallengeToken()
        Logger.info("Received a push challenge token")
        updatePersistedSessionState(session: session, transaction) {
            $0.pushChallengeState = .unfulfilledPush(challengeToken: pushChallengeToken)
        }
    }

    @MainActor
    private func attemptToFulfillAvailableChallengesWaitingIfNeeded(
        for session: RegistrationSession
    ) async -> RegistrationStep {
        Logger.info("Found \(session.requestedInformation.count) challenge(s)")

        var requestsPushChallenge = false
        var requestsCaptchaChallenge = false
        for challenge in session.requestedInformation {
            switch challenge {
            case .pushChallenge: requestsPushChallenge = true
            case .captcha: requestsCaptchaChallenge = true
            }
        }

        // Our first choice: a push challenge for which we already have the challenge token.
        let unfulfilledPushChallengeToken: String? = {
            switch persistedState.sessionState?.pushChallengeState {
            case nil, .notRequested, .ineligible, .waitingForPush, .fulfilled, .rejected:
                return nil
            case let .unfulfilledPush(challengeToken):
                return challengeToken
            }
        }()

        if requestsPushChallenge, let unfulfilledPushChallengeToken {
            Logger.info("Attempting to fulfill push challenge with a token we already have")
            return await submit(
                challengeFulfillment: .pushChallenge(unfulfilledPushChallengeToken),
                for: session,
                failureCount: 0,
            )
        }

        @MainActor
        func waitForPushTokenChallenge(
            timeout: TimeInterval,
            failChallengeIfTimedOut: Bool
        ) async -> RegistrationStep {
            Logger.info("Attempting to fulfill push challenge with a token we don't have yet")
            do {
                let challengeToken = try await withUncooperativeTimeout(seconds: timeout) {
                    return await self.deps.pushRegistrationManager.receivePreAuthChallengeToken()
                }
                db.write { transaction in
                    self.didReceive(
                        pushChallengeToken: challengeToken,
                        for: session,
                        transaction: transaction
                    )
                }
                return await submit(
                    challengeFulfillment: .pushChallenge(challengeToken),
                    for: session,
                    failureCount: 0,
                )
            } catch {
                switch error {
                case is UncooperativeTimeoutError where failChallengeIfTimedOut:
                    Logger.warn("No challenge token received in time. Resetting")
                    db.write { self.resetSession($0) }
                    return .showErrorSheet(.sessionInvalidated)
                default:
                    Logger.warn("No challenge token received in time, falling back to next challenge")
                    return await tryNonImmediatePushChallenge()
                }
            }
        }

        @MainActor
        func tryNonImmediatePushChallenge() async -> RegistrationStep {
            // Our third choice: a captcha challenge
            if requestsCaptchaChallenge {
                Logger.info("Showing the CAPTCHA challenge to the user")
                db.write { transaction in
                    SupportKeyValueStore().setLastChallengeDate(value: Date(), transaction: transaction)
                }
                return .captchaChallenge
            }

            // Our fourth choice: a push challenge where we're still waiting for the challenge token.
            if
                requestsPushChallenge,
                let timeToWaitUntil = pushChallengeRequestDate?.addingTimeInterval(deps.timeoutProvider.pushTokenTimeout),
                deps.dateProvider() < timeToWaitUntil
            {
                let timeout = timeToWaitUntil.timeIntervalSince(deps.dateProvider())
                return await waitForPushTokenChallenge(
                    timeout: timeout,
                    failChallengeIfTimedOut: true
                )
            }

            // We're out of luck.
            if session.hasUnknownChallengeRequiringAppUpdate {
                Logger.warn("An unknown challenge was found")
                inMemoryState.pendingCodeTransport = nil
                db.write { tx in
                    self.processSession(session, initialCodeRequestState: .failedToRequest, tx)
                }
                return .appUpdateBanner
            } else {
                Logger.warn("Couldn't fulfill any challenges. Resetting the session")
                db.write { resetSession($0) }
                return await nextStep()
            }
        }

        // Our second choice: a very recent push challenge.
        let pushChallengeRequestDate: Date? = {
            switch persistedState.sessionState?.pushChallengeState {
            case nil, .notRequested, .ineligible, .unfulfilledPush, .fulfilled, .rejected:
                return nil
            case let .waitingForPush(requestedAt):
                return requestedAt
            }
        }()

        if
            requestsPushChallenge,
            let timeToWaitUntil = pushChallengeRequestDate?.addingTimeInterval(deps.timeoutProvider.pushTokenMinWaitTime),
            deps.dateProvider() < timeToWaitUntil
        {
            let timeout = timeToWaitUntil.timeIntervalSince(deps.dateProvider())
            return await waitForPushTokenChallenge(timeout: timeout, failChallengeIfTimedOut: false)
        }

        // Try the next choices.
        return await tryNonImmediatePushChallenge()
    }

    @MainActor
    private func submit(
        challengeFulfillment fulfillment: Registration.ChallengeFulfillment,
        for session: RegistrationSession,
        failureCount: Int,
    ) async -> RegistrationStep {
        let maxAutomaticRetries = Constants.networkErrorRetries

        switch fulfillment {
        case .captcha:
            Logger.info("Submitting CAPTCHA challenge fulfillment")
        case .pushChallenge:
            Logger.info("Submitting push challenge fulfillment")
        }

        let result = await deps.sessionManager.fulfillChallenge(
            for: session,
            fulfillment: fulfillment
        )

        switch result {
        case .success(let session):
            db.write { tx in
                processSession(session, tx)
                switch fulfillment {
                case .captcha: break
                case .pushChallenge:
                    updatePersistedSessionState(session: session, tx) {
                        $0.pushChallengeState = .fulfilled
                    }
                }
            }
            return await nextStep()
        case .rejectedArgument(let session):
            db.write { tx in
                self.processSession(session, tx)
                self.updatePersistedSessionState(session: session, tx) {
                    $0.pushChallengeState = .rejected
                }
            }
            return .showErrorSheet(.genericError)
        case .disallowed(let session):
            Logger.warn("Disallowed to complete a challenge which should be impossible.")
            // Don't keep trying to send a code.
            inMemoryState.pendingCodeTransport = nil
            db.write { self.processSession(session, initialCodeRequestState: .failedToRequest, $0) }
            return .showErrorSheet(.genericError)
        case .invalidSession:
            db.write { self.resetSession($0) }
            return .showErrorSheet(.sessionInvalidated)
        case .serverFailure(let failureResponse):
            if failureResponse.isPermanent {
                return .showErrorSheet(.genericError)
            } else {
                return .showErrorSheet(.networkError)
            }
        case .retryAfterTimeout(let session, retryAfterHeader: _):
            Logger.error("Should not have to retry a captcha challenge request")
            // Clear the pending code; we want the user to press again
            // once the timeout expires.
            inMemoryState.pendingCodeTransport = nil
            db.write { self.processSession(session, initialCodeRequestState: .failedToRequest, $0) }
            db.write { self.processSession(session, $0) }
            return await nextStep()
        case .networkFailure:
            if failureCount < maxAutomaticRetries {
                return await submit(
                    challengeFulfillment: fulfillment,
                    for: session,
                    failureCount: failureCount + 1,
                )
            }
            return .showErrorSheet(.networkError)
        case .transportError(let session):
            Logger.error("Should not get a transport error for a challenge request")
            // Clear the pending code; we want the user to press again
            // once the timeout expires.
            inMemoryState.pendingCodeTransport = nil
            db.write { self.processSession(session, initialCodeRequestState: .failedToRequest, $0) }
            return await nextStep()
        case .genericError:
            return .showErrorSheet(.genericError)
        }
    }

    @MainActor
    private func submitSessionCode(
        session: RegistrationSession,
        code: String,
        failureCount: Int,
    ) async -> RegistrationStep {
        let maxAutomaticRetries = Constants.networkErrorRetries

        Logger.info("")

        db.write { tx in
            self.updatePersistedSessionState(session: session, tx) {
                $0.numVerificationCodeSubmissions += 1
            }
        }

        let result = await deps.sessionManager.submitVerificationCode(
            for: session,
            code: code
        )

        switch result {
        case .success(let session):
            if !session.verified {
                // The code must have been wrong.
                fallthrough
            }
            db.write { self.processSession(session, $0) }
            return await nextStep()
        case .rejectedArgument(let session):
            if session.nextVerificationAttemptDate != nil {
                db.write { self.processSession(session, $0) }
                return .verificationCodeEntry(self.verificationCodeEntryState(
                    session: session,
                    validationError: .invalidVerificationCode(invalidCode: code)
                ))
            } else {
                // Something went wrong, we can't submit again.
                db.write { self.processSession(session, initialCodeRequestState: .exhaustedCodeAttempts, $0) }
                return verificationCodeSubmissionRejectedError
            }
        case .disallowed(let session):
            // This state means the session state is updated
            // such that what comes next has changed, e.g. we can't send a verification
            // code and will kick the user back to sending an sms code.
            db.write { self.processSession(session, $0) }
            return verificationCodeSubmissionRejectedError
        case .invalidSession:
            db.write { self.resetSession($0) }
            return .showErrorSheet(.sessionInvalidated)
        case .serverFailure(let failureResponse):
            if failureResponse.isPermanent {
                return .showErrorSheet(.genericError)
            } else {
                return .showErrorSheet(.networkError)
            }
        case .retryAfterTimeout(let session, let retryAfterHeader):
            db.write { self.processSession(session, $0) }
            if
                failureCount < maxAutomaticRetries,
                let timeInterval = session.nextVerificationAttempt,
                timeInterval < Constants.autoRetryInterval,
                let retryAfterHeader,
                retryAfterHeader < Constants.autoRetryInterval
            {
                let minimumBackoff = OWSOperation.retryIntervalForExponentialBackoff(failureCount: failureCount + 1)
                try? await Task.sleep(nanoseconds: max(timeInterval, retryAfterHeader, minimumBackoff).clampedNanoseconds)
                return await self.submitSessionCode(
                    session: session,
                    code: code,
                    failureCount: failureCount + 1,
                )
            }
            if session.nextVerificationAttemptDate != nil {
                return .verificationCodeEntry(verificationCodeEntryState(
                    session: session,
                    validationError: .submitCodeTimeout,
                ))
            } else {
                // Something went wrong, we can't submit again.
                return verificationCodeSubmissionRejectedError
            }
        case .networkFailure:
            if failureCount < maxAutomaticRetries {
                let minimumBackoff = OWSOperation.retryIntervalForExponentialBackoff(failureCount: failureCount + 1)
                try? await Task.sleep(nanoseconds: minimumBackoff.clampedNanoseconds)
                return await submitSessionCode(
                    session: session,
                    code: code,
                    failureCount: failureCount + 1,
                )
            }
            return .showErrorSheet(.networkError)
        case .transportError(let session):
            Logger.error("Should not get transport error when submitting verification code")
            db.write { self.processSession(session, $0) }
            return .showErrorSheet(.genericError)
        case .genericError:
            return .showErrorSheet(.genericError)
        }
    }

    @MainActor
    private func restoreSVRMasterSecretForSessionPathReglock(
        session: RegistrationSession,
        pin: String,
        svrAuthCredential: SVRAuthCredential,
        reglockExpirationDate: Date,
        failureCount: Int,
    ) async -> RegistrationStep {
        let maxAutomaticRetries = Constants.networkErrorRetries

        Logger.info("")

        let result = await deps.svr.restoreKeys(
            pin: pin,
            authMethod: .svrAuth(svrAuthCredential, backup: nil)
        ).awaitable()

        switch result {
        case .success(let masterKey):
            self.db.write { tx in
                self.updateMasterKeyAndLocalState(masterKey: masterKey, tx: tx)
                self.updatePersistedState(tx) {
                    $0.recoveredSVRMasterKey = masterKey
                    $0.hasRestoredFromSVR = true
                }
                self.updatePersistedSessionState(session: session, tx) {
                    // Now we have the state we need to get past reglock.
                    $0.reglockState = .none
                }
            }
            return await nextStep()
        case let .invalidPin(remainingAttempts):
            return .pinEntry(RegistrationPinState(
                operation: .enteringExistingPin(
                    skippability: .unskippable,
                    remainingAttempts: UInt(remainingAttempts)
                ),
                error: .wrongPin(wrongPin: pin),
                contactSupportMode: contactSupportRegistrationPINMode(),
                exitConfiguration: pinCodeEntryExitConfiguration()
            ))
        case .backupMissing:
            // If we are unable to talk to SVR, it got wiped, probably
            // because we used up our guesses. We can't get past reglock.
            inMemoryState.pinFromUser = nil
            inMemoryState.shouldRestoreSVRMasterKeyAfterRegistration = false
            db.write { tx in
                self.updatePersistedState(tx) {
                    $0.hasGivenUpTryingToRestoreWithSVR = true
                }
                self.updatePersistedSessionState(session: session, tx) {
                    $0.reglockState = .waitingTimeout(expirationDate: reglockExpirationDate)
                }
            }
            return await nextStep()
        case .networkError:
            if failureCount < maxAutomaticRetries {
                let minimumBackoff = OWSOperation.retryIntervalForExponentialBackoff(failureCount: failureCount + 1)
                try? await Task.sleep(nanoseconds: minimumBackoff.clampedNanoseconds)
                return await restoreSVRMasterSecretForSessionPathReglock(
                    session: session,
                    pin: pin,
                    svrAuthCredential: svrAuthCredential,
                    reglockExpirationDate: reglockExpirationDate,
                    failureCount: failureCount + 1,
                )
            }
            return .showErrorSheet(.networkError)
        case .genericError:
            return .showErrorSheet(.genericError)
        }
    }

    // MARK: - Profile Setup Pathway

    /// Returns the next step the user needs to go through _after_ the actual account
    /// registration or change number is complete (e.g. profile setup).
    @MainActor
    private func nextStepForProfileSetup(
        _ accountIdentity: AccountIdentity
    ) async -> RegistrationStep {
        switch mode {
        case .registering, .reRegistering:
            if !inMemoryState.hasOpenedConnection {
                await deps.registrationWebSocketManager.acquireRestrictedWebSocket(chatServiceAuth: accountIdentity.chatServiceAuth)
                inMemoryState.hasOpenedConnection = true
            }

        case .changingNumber:
            // Change number is different; we do a limited number of operations and then finalize.
            if let restoreStepNextStep = await performSVRRestoreStepsIfNeeded(accountIdentity: accountIdentity) {
                return restoreStepNextStep
            }

            let accountEntropyPool = getOrGenerateAccountEntropyPool()

            if let backupStepGuarantee = await performSVRBackupStepsIfNeeded(
                resetPINReminderInterval: false,
                accountEntropyPool: accountEntropyPool,
                accountIdentity: accountIdentity
            ) {
                return backupStepGuarantee
            }

            return await exportAndWipeState(
                accountEntropyPool: accountEntropyPool,
                accountIdentity: accountIdentity
            )
        }

        // We _must_ do these steps first.
        if shouldRefreshOneTimePreKeys() {
            // After atomic account creation, our account is ready to go from the start.
            // But we should still upload one-time prekeys, as that is not part
            // of account creation.
            do {
                try await deps.preKeyManager.rotateOneTimePreKeysForRegistration(auth: accountIdentity.chatServiceAuth).value
                self.db.write { tx in
                    self.updatePersistedState(tx) {
                        // No harm marking both down as done even though
                        // we only did one or the other.
                        $0.didRefreshOneTimePreKeys = true
                    }
                }
                return await nextStep()
            } catch {
                if error.isPostRegDeregisteredError {
                    return await becameDeregisteredBeforeCompleting(accountIdentity: accountIdentity)
                }
                Logger.error("Failed to create prekeys: \(error)")
                // Note this is undismissable; the user will be on whatever
                // screen they were on but with the error sheet atop which retries
                // via `nextStep()` when tapped.
                return .showErrorSheet(.genericError)
            }
        }

        if
            shouldRestoreFromStorageServiceBeforeUpdatingSVR(),
            let restoredKey = persistedState.recoveredSVRMasterKey
        {
            // Need to preserve the key recovered by registration and use this for storage service restore
            // If already restored due to AEP change, this step will be skipped
            return await restoreFromStorageService(
                accountIdentity: accountIdentity,
                masterKeySource: .explicit(restoredKey)
            )
        }

        let isBackup = persistedState.restoreMethod?.isBackup == true

        // This step is here to attempt to restore the PIN after an SMS-based registration, and then possibly
        // restore from storage service. If the user is attempting a backup restore, skip restoring from
        // SVR. We will either have a restored SVR master key from registration, or we will be using
        // the entered/generated AEP.
        // (See comment below for more details)
        if !isBackup {
            if let restoreStepNextStep = await performSVRRestoreStepsIfNeeded(accountIdentity: accountIdentity) {
                return restoreStepNextStep
            }
        }

        let accountEntropyPool: SignalServiceKit.AccountEntropyPool
        if let aep = persistedState.backupKeyAccountEntropyPool {
            accountEntropyPool = aep
        } else if let aep = inMemoryState.accountEntropyPool {
            accountEntropyPool = aep
        } else {
            if isBackup {
                // If the user want's to restore from backup, ask for the key
                return .enterRecoveryKey(RegistrationEnterAccountEntropyPoolState(
                    canShowBackButton: false,
                    canShowNoKeyHelpButton: true
                ))
            } else {
                // If the AccountEntropyPool doesn't exist yet, create one.
                accountEntropyPool = getOrGenerateAccountEntropyPool()
            }
        }

        // ***************
        // After this point, there should be an AEP present, so the AEP should no longer
        // be sourced from InMemoryState
        // ***************

        // The user may have registered with a master key that differs from the AEP-derived master key
        // (e.g. - they previously backed up, but have done a PIN-based registratin in the interim, resulting
        // in a rotated AEP/masterKey. Because of that, if the user is restoring from backups, postpone
        // SVR backup until after registration completes. This accomplishes two things:
        // 1. Allows delaying PIN entry to post-restore in some flows, streamlining the
        //    recovery key entry -> restore confirmation -> backup restore path.
        // 2. (and more importantly) Backup restore can be a fairly long and complicated part of
        //    completing a registration. If the user quit before completion and/or otherwise abandons
        //    the registration before completing the restore, we want to make sure that SVR still holds
        //    the master key / reglock token that was used for registration.
        if !isBackup {
            if let backupStepNextStep = await performSVRBackupStepsIfNeeded(
                resetPINReminderInterval: true,
                accountEntropyPool: accountEntropyPool,
                accountIdentity: accountIdentity
            ) {
                return backupStepNextStep
            }
        }

        // This will restore after backup, _or_ it will rotate to the new AEP derived key
        if shouldRestoreFromStorageService() {
            return await restoreFromStorageService(
                accountIdentity: accountIdentity,
                masterKeySource: .explicit(accountEntropyPool.getMasterKey())
            )
        }

        if
            !inMemoryState.hasProfileName,
            persistedState.restoreMethod?.backupType == nil
        {
            if let profileInfo = inMemoryState.pendingProfileInfo {
                let updatePromise = db.write { tx in
                    deps.profileManager.updateLocalProfile(
                        givenName: profileInfo.givenName,
                        familyName: profileInfo.familyName,
                        avatarData: profileInfo.avatarData,
                        authedAccount: accountIdentity.authedAccount,
                        tx: tx
                    )
                }
                do {
                    _ = try await updatePromise.awaitable()
                    self.inMemoryState.hasProfileName = true
                    self.inMemoryState.pendingProfileInfo = nil
                    return await nextStep()
                } catch {
                    if error.isPostRegDeregisteredError {
                        return await becameDeregisteredBeforeCompleting(accountIdentity: accountIdentity)
                    }
                    return .showErrorSheet(
                        error.isNetworkFailureOrTimeout ? .networkError : .genericError
                    )
                }
            } else {
                return .setupProfile(RegistrationProfileState(
                    e164: accountIdentity.e164,
                    phoneNumberDiscoverability: inMemoryState.phoneNumberDiscoverability.orDefault
                ))
            }
        }

        if
            inMemoryState.phoneNumberDiscoverability == nil,
            persistedState.restoreMethod?.backupType == nil
        {
            return .phoneNumberDiscoverability(RegistrationPhoneNumberDiscoverabilityState(
                e164: accountIdentity.e164,
                phoneNumberDiscoverability: inMemoryState.phoneNumberDiscoverability.orDefault
            ))
        }

        let finalizeProgress: OWSProgressSource?
        switch await self.confirmAndRestoreFromBackupIfNeeded(
            accountEntropyPool: accountEntropyPool,
            accountIdentity: accountIdentity
        ) {
        case .restored:
            finalizeProgress = await inMemoryState.restoreFromBackupProgressSink?
                .child(for: .finishing)
                .addSource(withLabel: "", unitCount: 100)
            loadProfileState()
        case .stepRequired(let stepGuarantee):
            return stepGuarantee
        case .skipped:
            finalizeProgress = nil
        }

        if let localUsernameState = shouldAttemptToReclaimUsername() {
            return await attemptToReclaimUsername(
                accountIdentity: accountIdentity,
                localUsernameState: localUsernameState
            )
        }

        // We are ready to finish! Export all state and wipe things
        // so we can re-register later if desired.
        let finalStep = {
            await self.exportAndWipeState(
                accountEntropyPool: accountEntropyPool,
                accountIdentity: accountIdentity
            )
        }

        if let finalizeProgress {
            return await finalizeProgress.updatePeriodically(
                estimatedTimeToCompletion: 5,
                work: finalStep
            )
        } else {
            return await finalStep()
        }
    }

    private enum BackupResult {
        case restored
        case stepRequired(RegistrationStep)
        case skipped
    }

    private func confirmAndRestoreFromBackupIfNeeded(
        accountEntropyPool: SignalServiceKit.AccountEntropyPool,
        accountIdentity: AccountIdentity
    ) async -> BackupResult {

        if
            persistedState.restoreMethod?.isBackup == true,
            !inMemoryState.hasConfirmedRestoreFromBackup
        {
            let step = await fetchBackupCdnInfo(
                accountEntropyPool: accountEntropyPool,
                accountIdentity: accountIdentity
            )
            return .stepRequired(step)
        }

        if needsToRestoreBackup() {
            await self.restoreBackupIfNecessary(
                accountEntropyPool: accountEntropyPool,
                accountIdentity: accountIdentity,
                progress: inMemoryState.restoreFromBackupProgressSink,
            )

            return .restored
        }

        if
            persistedState.restoreMethod?.isBackup == true {
            // If restoring from backup, and the PIN hasn't been set,
            // read the restored PIN and skip prompting the user.
            if inMemoryState.pinFromUser == nil && inMemoryState.pinFromDisk == nil {
                deps.db.read { tx in
                    inMemoryState.pinFromDisk = deps.ows2FAManager.pinCode(tx)
                    inMemoryState.pinFromUser = inMemoryState.pinFromDisk
                }
            }
        }

        if let step = await performSVRBackupStepsIfNeeded(
            resetPINReminderInterval: false,
            accountEntropyPool: accountEntropyPool,
            accountIdentity: accountIdentity
        ) {
            return .stepRequired(step)
        }

        return .skipped
    }

    @MainActor
    private func getOrGenerateAccountEntropyPool() -> SignalServiceKit.AccountEntropyPool {
        // If the AccountEntropyPool doesn't exist yet, create one.
        return db.write { tx in
            let accountEntropyPool: SignalServiceKit.AccountEntropyPool
            if let _accountEntropyPool = deps.accountKeyStore.getAccountEntropyPool(tx: tx) {
                accountEntropyPool = _accountEntropyPool
            } else {
                accountEntropyPool = deps.accountEntropyPoolGenerator()
            }

            inMemoryState.accountEntropyPool = accountEntropyPool
            let newMasterKey = accountEntropyPool.getMasterKey()
            updateMasterKeyAndLocalState(masterKey: newMasterKey, tx: tx)
            return accountEntropyPool
        }
    }

    // returns nil if no steps performed.
    private func showPinEntryIfNeeded(
        accountIdentity: AccountIdentity
    ) -> RegistrationStep? {
        Logger.info("")

        let isRestoringPinBackup: Bool = (
            accountIdentity.hasPreviouslyUsedSVR &&
            !persistedState.hasGivenUpTryingToRestoreWithSVR &&
            persistedState.restoreMethod?.isBackup != true
        )

        if !persistedState.hasSkippedPinEntry {
            if isRestoringPinBackup {
                return .pinEntry(RegistrationPinState(
                    operation: .enteringExistingPin(
                        skippability: .canSkipAndCreateNew,
                        remainingAttempts: nil
                    ),
                    error: nil,
                    contactSupportMode: self.contactSupportRegistrationPINMode(),
                    exitConfiguration: pinCodeEntryExitConfiguration()
                ))
            } else if let blob = inMemoryState.unconfirmedPinBlob {
                return .pinEntry(RegistrationPinState(
                    operation: .confirmingNewPin(blob),
                    error: nil,
                    contactSupportMode: self.contactSupportRegistrationPINMode(),
                    exitConfiguration: pinCodeEntryExitConfiguration()
                ))
            } else {
                return .pinEntry(RegistrationPinState(
                    operation: .creatingNewPin,
                    error: nil,
                    contactSupportMode: self.contactSupportRegistrationPINMode(),
                    exitConfiguration: pinCodeEntryExitConfiguration()
                ))
            }
        }
        return nil
    }

    // returns nil if no steps performed.
    private func performSVRRestoreStepsIfNeeded(
        accountIdentity: AccountIdentity
    ) async -> RegistrationStep? {
        guard inMemoryState.shouldRestoreSVRMasterKeyAfterRegistration else {
            return nil
        }

        Logger.info("")
        guard let pin = inMemoryState.pinFromUser ?? inMemoryState.pinFromDisk else {
            return showPinEntryIfNeeded(accountIdentity: accountIdentity)
        }

        if
            !persistedState.hasSkippedPinEntry,
            accountIdentity.hasPreviouslyUsedSVR,
            !persistedState.hasGivenUpTryingToRestoreWithSVR
        {
            // If we have no SVR data, fetch it.
            return await self.restoreSVRBackupPostRegistration(pin: pin, accountIdentity: accountIdentity, failureCount: 0)
        }
        return nil
    }

    // returns nil if no steps performed.
    private func performSVRBackupStepsIfNeeded(
        resetPINReminderInterval: Bool,
        accountEntropyPool: SignalServiceKit.AccountEntropyPool,
        accountIdentity: AccountIdentity
    ) async -> RegistrationStep? {
        Logger.info("")

        guard let pin = inMemoryState.pinFromUser ?? inMemoryState.pinFromDisk else {
            return showPinEntryIfNeeded(accountIdentity: accountIdentity)
        }

        if !persistedState.hasSkippedPinEntry {
            if inMemoryState.shouldBackUpToSVR {
                // If we haven't backed up, do so now.
                return await backupToSVR(
                    pin: pin,
                    resetPINReminderInterval: resetPINReminderInterval,
                    accountEntropyPool: accountEntropyPool,
                    accountIdentity: accountIdentity,
                    failureCount: 0,
                )
            }

            if let reglockToken = self.reglockToken(for: accountIdentity.e164) {
                if inMemoryState.hasSetReglock.negated {
                    return await self.enableReglock(accountIdentity: accountIdentity, reglockToken: reglockToken)
                }
            } else {
                Logger.info("Not enabling reglock because it wasn't enabled to begin with")
            }
        }
        return nil
    }

    @MainActor
    private func restoreSVRBackupPostRegistration(
        pin: String,
        accountIdentity: AccountIdentity,
        failureCount: Int,
    ) async -> RegistrationStep {
        let maxAutomaticRetries = Constants.networkErrorRetries

        Logger.info("")

        let backupAuthMethod = SVR.AuthMethod.chatServerAuth(accountIdentity.authedAccount)
        let authMethod: SVR.AuthMethod
        if let svrAuthCredential = inMemoryState.svrAuthCredential {
            authMethod = .svrAuth(svrAuthCredential, backup: backupAuthMethod)
        } else {
            authMethod = backupAuthMethod
        }
        let result = await deps.svr.restoreKeys(
            pin: pin,
            authMethod: authMethod
        ).awaitable()

        switch result {
        case .success(let masterKey):
            inMemoryState.shouldRestoreSVRMasterKeyAfterRegistration = false
            await db.awaitableWrite { tx in
                updatePersistedState(tx) { $0.recoveredSVRMasterKey = masterKey }
            }
            return await nextStep()
        case let .invalidPin(remainingAttempts):
            return .pinEntry(RegistrationPinState(
                operation: .enteringExistingPin(
                    skippability: .canSkipAndCreateNew,
                    remainingAttempts: UInt(remainingAttempts)
                ),
                error: .wrongPin(wrongPin: pin),
                contactSupportMode: contactSupportRegistrationPINMode(),
                exitConfiguration: pinCodeEntryExitConfiguration()
            ))
        case .backupMissing:
            // If we are unable to talk to SVR, it got wiped and we can't
            // recover. Keep going like if nothing happened.
            inMemoryState.pinFromUser = nil
            inMemoryState.shouldRestoreSVRMasterKeyAfterRegistration = false
            await db.awaitableWrite { tx in
                updatePersistedState(tx) { $0.hasGivenUpTryingToRestoreWithSVR = true }
            }
            return .pinAttemptsExhaustedWithoutReglock(
                .init(mode: .restoringBackup)
            )
        case .networkError:
            if failureCount < maxAutomaticRetries {
                let minimumBackoff = OWSOperation.retryIntervalForExponentialBackoff(failureCount: failureCount + 1)
                try? await Task.sleep(nanoseconds: minimumBackoff.clampedNanoseconds)
                return await restoreSVRBackupPostRegistration(
                    pin: pin,
                    accountIdentity: accountIdentity,
                    failureCount: failureCount + 1,
                )
            }
            return .showErrorSheet(.networkError)
        case .genericError(let error):
            if error.isPostRegDeregisteredError {
                return await becameDeregisteredBeforeCompleting(accountIdentity: accountIdentity)
            } else if failureCount < maxAutomaticRetries {
                let minimumBackoff = OWSOperation.retryIntervalForExponentialBackoff(failureCount: failureCount + 1)
                try? await Task.sleep(nanoseconds: minimumBackoff.clampedNanoseconds)
                return await restoreSVRBackupPostRegistration(
                    pin: pin,
                    accountIdentity: accountIdentity,
                    failureCount: failureCount + 1,
                )
            } else {
                self.inMemoryState.pinFromUser = nil
                return .pinEntry(RegistrationPinState(
                    operation: .enteringExistingPin(
                        skippability: .canSkipAndCreateNew,
                        remainingAttempts: nil
                    ),
                    error: .serverError,
                    contactSupportMode: self.contactSupportRegistrationPINMode(),
                    exitConfiguration: self.pinCodeEntryExitConfiguration()
                ))
            }
        }
    }

    @MainActor
    private func backupToSVR(
        pin: String,
        resetPINReminderInterval: Bool,
        accountEntropyPool: SignalServiceKit.AccountEntropyPool,
        accountIdentity: AccountIdentity,
        failureCount: Int,
    ) async -> RegistrationStep {
        let maxAutomaticRetries = Constants.networkErrorRetries

        Logger.info("")

        let authMethod: SVR.AuthMethod
        let backupAuthMethod = SVR.AuthMethod.chatServerAuth(accountIdentity.authedAccount)
        if let svrAuthCredential = inMemoryState.svrAuthCredential {
            authMethod = .svrAuth(svrAuthCredential, backup: backupAuthMethod)
        } else {
            authMethod = backupAuthMethod
        }

        let masterKey = accountEntropyPool.getMasterKey()
        do {
            let backedUpMasterKey = try await deps.svr.backupMasterKey(
                pin: pin,
                masterKey: masterKey,
                authMethod: authMethod
            ).awaitable()

            inMemoryState.hasBackedUpToSVR = true
            await db.awaitableWrite { tx in
                Logger.info("Setting pin code after SVR backup")
                updateMasterKeyAndLocalState(
                    masterKey: backedUpMasterKey,
                    tx: tx
                )
                deps.ows2FAManager.markPinEnabled(
                    pin: pin,
                    resetReminderInterval: resetPINReminderInterval,
                    tx: tx
                )
            }

            return await nextStep()
        } catch {
            if error.isNetworkFailureOrTimeout {
                if failureCount < maxAutomaticRetries {
                    let minimumBackoff = OWSOperation.retryIntervalForExponentialBackoff(failureCount: failureCount + 1)
                    try? await Task.sleep(nanoseconds: minimumBackoff.clampedNanoseconds)
                    return await backupToSVR(
                        pin: pin,
                        resetPINReminderInterval: resetPINReminderInterval,
                        accountEntropyPool: accountEntropyPool,
                        accountIdentity: accountIdentity,
                        failureCount: failureCount + 1,
                    )
                }
                return .showErrorSheet(.networkError)
            }
            Logger.error("Failed to back up to SVR with error: \(error)")
            // We want to let people get through registration even if backups
            // go wrong. Show an error but let the user continue when they try the next step.
            inMemoryState.didSkipSVRBackup = true
            return .showErrorSheet(.genericError)
        }
    }

    @MainActor
    private func restoreFromStorageService(
        accountIdentity: AccountIdentity,
        masterKeySource: StorageService.MasterKeySource
    ) async -> RegistrationStep {
        db.write { tx in
            switch mode {
            case .registering, .reRegistering:
                break
            case .changingNumber:
                owsFailDebug("Unexpectedly restoring from Storage Service while changing number, rather than during (re)registration! Bailing.")
                return
            }
        }

        do {
            try await withUncooperativeTimeout(seconds: 120) {
                try await self.deps.storageServiceManager.restoreOrCreateManifestIfNecessary(
                    authedDevice: accountIdentity.authedDevice,
                    masterKeySource: masterKeySource
                ).awaitable()
            }
            loadProfileState()
            if inMemoryState.hasProfileName {
                scheduleReuploadProfileStateAsync(accountIdentity: accountIdentity)
            }
            inMemoryState.hasRestoredFromStorageService = true
        } catch {
            if error.isPostRegDeregisteredError {
                return await becameDeregisteredBeforeCompleting(accountIdentity: accountIdentity)
            }
            inMemoryState.hasSkippedRestoreFromStorageService = true
        }
        return await nextStep()
    }

    /// If we have a username/username link during registration – which we would
    /// have restored from Storage Service – attempts to "reclaim" it.
    ///
    /// When we call `POST /v1/registration` and an account already exists with
    /// our phone number, and the account has a username, the server will move
    /// the username to a "reserved" state. That gives us an opportunity to
    /// reclaim that username and have it re-added to our account, which we do
    /// by sending a "confirm username" request.
    ///
    /// In making that request we use the username we have locally (which we
    /// expect to be reserved), and the same username-link-entropy we had
    /// locally. The server will notice that we're attempting to confirm a
    /// username it moved from confirmed -> reserved, and will not rotate the
    /// username-link-handle. The end result should therefore be that we get our
    /// username back, and our username link is unaffected.
    ///
    /// - Note
    /// This method will automatically retry the "confirm username" request on
    /// network errors.
    ///
    /// - Note
    /// If the reclamation attempt fails for a non-network reason, or exhausts
    /// network retries, we will simply move on. Any further recovery will
    /// happen via the username validation job and interactive recovery flows.
    @MainActor
    private func attemptToReclaimUsername(
        accountIdentity: AccountIdentity,
        localUsernameState: Usernames.LocalUsernameState,
        remainingNetworkErrorRetries: UInt = 2
    ) async -> RegistrationStep {
        @MainActor
        func attemptComplete() async -> RegistrationStep {
            inMemoryState.usernameReclamationState = .reclamationAttempted
            return await nextStep()
        }

        let logger = PrefixedLogger(prefix: "UsernameReclamation")

        let localUsername: String
        let localUsernameLink: Usernames.UsernameLink

        switch localUsernameState {
        case .unset, .linkCorrupted, .usernameAndLinkCorrupted:
            return await attemptComplete()
        case .available(let username, let usernameLink):
            localUsername = username
            localUsernameLink = usernameLink
        }

        let hashedLocalUsername: Usernames.HashedUsername
        let encryptedUsernameForLink: Data

        do {
            hashedLocalUsername = try Usernames.HashedUsername(forUsername: localUsername)
            (_, encryptedUsernameForLink) = try deps.usernameLinkManager.generateEncryptedUsername(
                username: localUsername,
                existingEntropy: localUsernameLink.entropy
            )
        } catch let error {
            logger.error("Failed to reclaim username: error while generating params! \(error)")
            return await attemptComplete()
        }

        do {
            let confirmationResult = try await deps.usernameApiClient.confirmReservedUsername(
                reservedUsername: hashedLocalUsername,
                encryptedUsernameForLink: encryptedUsernameForLink,
                chatServiceAuth: accountIdentity.chatServiceAuth
            )
            switch confirmationResult {
            case .success(let usernameLinkHandle):
                if localUsernameLink.handle != usernameLinkHandle {
                    logger.error("Username link handle rotated during reclamation! Our local username link is now broken.")
                } else {
                    logger.info("Successfully reclaimed username during registration.")
                }
            case .rejected, .rateLimited:
                logger.error("Unexpectedly failed to confirm .username! \(confirmationResult)")
            }

            return await attemptComplete()
        } catch {
            if error.isNetworkFailureOrTimeout, remainingNetworkErrorRetries > 0 {
                return await self.attemptToReclaimUsername(
                    accountIdentity: accountIdentity,
                    localUsernameState: localUsernameState,
                    remainingNetworkErrorRetries: remainingNetworkErrorRetries - 1
                )
            } else if error.isNetworkFailureOrTimeout {
                logger.error("Failed to reclaim username: network error!")
            } else {
                logger.error("Failed to reclaim username: unknown error!")
            }

            return await attemptComplete()
        }
    }

    @MainActor
    private func enableReglock(
        accountIdentity: AccountIdentity,
        reglockToken: String
    ) async -> RegistrationStep {
        Logger.info("Attempting to enable reglock")

        do {
            try await Service.makeEnableReglockRequest(
                reglockToken: reglockToken,
                auth: accountIdentity.chatServiceAuth,
                networkManager: deps.networkManager,
            )
        } catch {
            // This isn't immediately catastrophic; this user already had reglock
            // enabled, so while it may now be out of date, its still there and
            // preventing others from getting in. We defer updating this until
            // later (when we update account attributes).
            // This matches legacy registration behavior.
            Logger.error("Unable to set reglock, so old reglock password will remain enforced.")
        }

        self.inMemoryState.hasSetReglock = true
        self.inMemoryState.wasReglockEnabledBeforeStarting = true
        self.db.write { tx in
            self.deps.ows2FAManager.markRegistrationLockEnabled(tx)
        }
        return await nextStep()
    }

    private func scheduleReuploadProfileStateAsync(accountIdentity: AccountIdentity) {
        Logger.debug("restored local profile name. Uploading...")
        // if we don't have a `localGivenName`, there's nothing to upload, and trying
        // to upload would fail.

        // Note we *don't* block on the update. There's no need to block registration on
        // it completing, and if there are any errors, it's durable.
        self.deps.profileManager
            .scheduleReuploadLocalProfile(authedAccount: accountIdentity.authedAccount)
    }

    private func loadProfileState() {
        Logger.info("")

        db.read { tx in
            let localProfile = deps.profileManager.localUserProfile(tx: tx)
            inMemoryState.hasProfileName = localProfile?.hasNonEmptyFilteredGivenName == true
            inMemoryState.profileKey = localProfile?.profileKey

            inMemoryState.phoneNumberDiscoverability =
                deps.phoneNumberDiscoverabilityManager.phoneNumberDiscoverability(tx: tx)

            inMemoryState.usernameReclamationState =
                .localUsernameStateLoaded(deps.localUsernameManager.usernameState(tx: tx))
        }
        let udAccessKey = SMKUDAccessKey(profileKey: inMemoryState.profileKey)
        inMemoryState.udAccessKey = udAccessKey
    }

    private func updateAccountAttributes(_ accountIdentity: AccountIdentity) async -> Error? {
        Logger.info("")
        do {
            try await Service.makeUpdateAccountAttributesRequest(
                makeAccountAttributes(
                    isManualMessageFetchEnabled: inMemoryState.isManualMessageFetchEnabled,
                    reglockToken: self.reglockToken(for: accountIdentity.e164),
                ),
                auth: accountIdentity.chatServiceAuth,
                networkManager: deps.networkManager,
            )
            return nil
        } catch {
            return error
        }
    }

    private func updatePhoneNumberDiscoverability(accountIdentity: AccountIdentity, phoneNumberDiscoverability: PhoneNumberDiscoverability) {
        Logger.info("")

        self.inMemoryState.phoneNumberDiscoverability = phoneNumberDiscoverability

        db.write { tx in
            // We will update attributes & storage service at the end of registration.
            deps.phoneNumberDiscoverabilityManager.setPhoneNumberDiscoverability(
                phoneNumberDiscoverability,
                updateAccountAttributes: false,
                updateStorageService: false,
                authedAccount: accountIdentity.authedAccount,
                tx: tx
            )
        }
    }

    private enum FinalizeChangeNumberResult {
        case success
        case genericError
    }

    private func finalizeChangeNumberPniState(
        changeNumberState: Mode.ChangeNumberState,
        pniState: Mode.ChangeNumberState.PendingPniState,
        accountIdentity: AccountIdentity
    ) async -> FinalizeChangeNumberResult {
        Logger.info("")

        do {
            try await self.db.awaitableWrite { tx in
                try self.deps.changeNumberPniManager.finalizePniIdentity(
                    identityKey: pniState.pniIdentityKeyPair,
                    signedPreKey: pniState.localDevicePniSignedPreKeyRecord,
                    lastResortPreKey: pniState.localDevicePniPqLastResortPreKeyRecord,
                    registrationId: pniState.localDevicePniRegistrationId,
                    tx: tx,
                )
                self._unsafeToModify_mode = .changingNumber(try self.loader.savePendingChangeNumber(
                    oldState: changeNumberState,
                    pniState: nil,
                    transaction: tx
                ))

                Logger.info(
                    """
                    Recording new phone number
                    localAci: \(changeNumberState.localAci),
                    localE164: \(changeNumberState.oldE164.stringValue),
                    serviceAci: \(accountIdentity.aci),
                    servicePni: \(accountIdentity.pni),
                    serviceE164: \(accountIdentity.e164.stringValue)")
                    """
                )

                // We do these here, and not in export state, so that we don't risk
                // syncing out-of-date state to storage service.
                self.deps.registrationStateChangeManager.didUpdateLocalPhoneNumber(
                    accountIdentity.e164,
                    aci: accountIdentity.aci,
                    pni: accountIdentity.pni,
                    tx: tx
                )
                // Make sure we update our local account.
                self.deps.storageServiceManager.recordPendingLocalAccountUpdates()
            }
            return .success
        } catch {
            Logger.error("Failed to finalize change number state: \(error)")
            return .genericError
        }
    }

    // MARK: Device Transfer

    private func shouldSkipDeviceTransfer() -> Bool {
        switch mode {
        case .registering:
            return persistedState.hasDeclinedTransfer
        case .reRegistering, .changingNumber:
            // Always skip device transfer in these modes.
            return true
        }
    }

    // MARK: - Permissions

    private func requiresSystemPermissions() async -> Bool {
        let needsContactAuthorization = deps.contactsStore.needsContactsAuthorization()
        let needsNotificationAuthorization = await deps.pushRegistrationManager.needsNotificationAuthorization()
        return needsContactAuthorization || needsNotificationAuthorization
    }

    // MARK: - Register/Change Number Requests

    @MainActor
    private func makeRegisterOrChangeNumberRequest(
        _ method: RegistrationRequestFactory.VerificationMethod,
        e164: E164,
        reglockToken: String?,
        responseHandler: @escaping @MainActor (AccountResponse) async -> RegistrationStep
    ) async -> RegistrationStep {
        Logger.info("")

        switch mode {
        case .reRegistering(let state):
            if persistedState.hasResetForReRegistration.negated {
                db.write { tx in
                    let isPrimaryDevice = deps.tsAccountManager.registrationState(tx: tx).isPrimaryDevice ?? true
                    let discoverability = deps.phoneNumberDiscoverabilityManager.phoneNumberDiscoverability(tx: tx)
                    deps.registrationStateChangeManager.resetForReregistration(
                        localPhoneNumber: state.e164,
                        localAci: state.aci,
                        discoverability: discoverability,
                        wasPrimaryDevice: isPrimaryDevice,
                        tx: tx
                    )
                    updatePersistedState(tx) {
                        $0.hasResetForReRegistration = true
                    }
                }
            }
            fallthrough
        case .registering:
            // The auth token we use going forwards for chat server auth headers
            // is generated by the client. We do that here and put it on the
            // AccountIdentity we generate after success so that we eventually
            // write it to TSAccountManager when all is said and done, and use
            // it for requests we need to make between now and then.
            let authToken = generateServerAuthToken()
            let apnResult = await fetchApnRegistrationId()

            // Either manual message fetch is true, or apns tokens are set.
            // Otherwise the request will fail.
            let isManualMessageFetchEnabled: Bool
            let apnRegistrationId: RegistrationRequestFactory.ApnRegistrationId?
            switch apnResult {
            case .success(let tokens):
                isManualMessageFetchEnabled = false
                apnRegistrationId = tokens
            case .pushUnsupported:
                Logger.info("Push unsupported; enabling manual message fetch.")
                isManualMessageFetchEnabled = true
                apnRegistrationId = nil
            case .timeout:
                Logger.error("Timed out waiting for apns token")
                return .showErrorSheet(.genericError)
            case .genericError:
                return .showErrorSheet(.genericError)
            }
            inMemoryState.isManualMessageFetchEnabled = isManualMessageFetchEnabled
            if isManualMessageFetchEnabled {
                db.write { tx in
                    self.deps.tsAccountManager.setIsManualMessageFetchEnabled(true, tx: tx)
                }
            }
            let accountAttributes = makeAccountAttributes(
                isManualMessageFetchEnabled: isManualMessageFetchEnabled,
                reglockToken: reglockToken,
            )

            do {
                try await sendRestoreMethodIfNecessary()
                return await makeCreateAccountRequestAndFinalizePreKeys(
                    method: method,
                    e164: e164,
                    authPassword: authToken,
                    accountAttributes: accountAttributes,
                    skipDeviceTransfer: shouldSkipDeviceTransfer(),
                    apnRegistrationId: apnRegistrationId,
                    responseHandler: responseHandler
                )
            } catch {
                return .showErrorSheet(.genericError)
            }

        case .changingNumber(let changeNumberState):
            if let pniState = changeNumberState.pniState {
                // We had an in flight change number that was interrupted, recover.
                return await recoverPendingPniChangeNumberState(
                    changeNumberState: changeNumberState,
                    pniState: pniState
                )
            }
            let changeNumberResult = await generatePniStateAndMakeChangeNumberRequest(
                e164: e164,
                verificationMethod: method,
                reglockToken: reglockToken,
                changeNumberState: changeNumberState
            )
            switch changeNumberResult {
            case .pniStateError:
                return .showErrorSheet(.genericError)
            case .serviceResponse(let accountResponse):
                switch accountResponse {
                case .success:
                    // Pni state will get finalized and cleaned up later in
                    // the normal course of action.
                    break
                case .reglockFailure, .rejectedVerificationMethod, .retryAfter:
                    // Explicit rejection by the server, we can safely
                    // wipe our local PNI state and regenerate when we retry.
                    do {
                        try db.write { tx in
                            self._unsafeToModify_mode = .changingNumber(try loader.savePendingChangeNumber(
                                oldState: changeNumberState,
                                pniState: nil,
                                transaction: tx
                            ))
                        }
                    } catch {
                        return .showErrorSheet(.genericError)
                    }
                case .deviceTransferPossible:
                    owsFailBeta("Should't get device transfer response on change number request.")
                case .networkError, .genericError:
                    // We don't know what went wrong, so PNI state
                    // may be set server side. Don't wipe PNI state
                    // so we try and recover.
                    Logger.error("Unknown error when changing number; preserving pni state")
                }
                return await responseHandler(accountResponse)
            }
        }
    }

    /// Send the restore method back to the other device in non-transfer restore scenarios.
    /// Device transfer is handled outside the registration flow, so sending that
    /// method is intentionally skipped here.
    @MainActor
    private func sendRestoreMethodIfNecessary() async throws {
        let restoreMethod: QuickRestoreManager.RestoreMethodType? = switch persistedState.restoreMethod {
        case .declined: .decline
        case .localBackup: .localBackup
        case .remoteBackup: .remoteBackup
        case .deviceTransfer: nil
        case .none: nil
        }

        if
            let restoreMethod,
            let restoreMethodToken = self.inMemoryState.registrationMessage?.restoreMethodToken
        {
            try await self.deps.quickRestoreManager.reportRestoreMethodChoice(
                method: restoreMethod,
                restoreMethodToken: restoreMethodToken
            )
        }
    }

    private func persistRegistrationMessage(_ registrationMessage: RegistrationProvisioningMessage) {
        db.write { tx in
            deps.identityManager.setIdentityKeyPair(
                registrationMessage.aciIdentityKeyPair.asECKeyPair,
                for: .aci,
                tx: tx
            )
            deps.identityManager.setIdentityKeyPair(
                registrationMessage.pniIdentityKeyPair.asECKeyPair,
                for: .pni,
                tx: tx
            )
            deps.accountKeyStore.setAccountEntropyPool(
                registrationMessage.accountEntropyPool,
                tx: tx
            )
        }
    }

    @MainActor
    private func makeCreateAccountRequestAndFinalizePreKeys(
        method: RegistrationRequestFactory.VerificationMethod,
        e164: E164,
        authPassword: String,
        accountAttributes: AccountAttributes,
        skipDeviceTransfer: Bool,
        apnRegistrationId: RegistrationRequestFactory.ApnRegistrationId?,
        responseHandler: @escaping (AccountResponse) async -> RegistrationStep
    ) async -> RegistrationStep {
        // If there are identity keys, we have to persist them before generating prekeys
        if let registrationMessage = inMemoryState.registrationMessage {
            persistRegistrationMessage(registrationMessage)
        }

        let prekeyBundles: RegistrationPreKeyUploadBundles
        do {
            prekeyBundles = try await deps.preKeyManager.createPreKeysForRegistration().value
        } catch {
            return .showErrorSheet(.genericError)
        }

        let shouldSkipDeviceTransfer = self.shouldSkipDeviceTransfer()
        let signalService = self.deps.signalService
        let accountResponse = await Service.makeCreateAccountRequest(
            method,
            e164: e164,
            authPassword: authPassword,
            accountAttributes: accountAttributes,
            skipDeviceTransfer: shouldSkipDeviceTransfer,
            apnRegistrationId: apnRegistrationId,
            prekeyBundles: prekeyBundles,
            signalService: signalService,
        )
        let isPrekeyUploadSuccess = switch accountResponse {
        case .success: true
        case
                .retryAfter,
                .rejectedVerificationMethod,
                .reglockFailure,
                .networkError,
                .genericError,
                .deviceTransferPossible: false
        }
        do {
            try await deps.preKeyManager.finalizeRegistrationPreKeys(
                prekeyBundles,
                uploadDidSucceed: isPrekeyUploadSuccess
            ).value
        } catch {
            // Finalizing is best effort.
            Logger.error("Unable to finalize prekeys, ignoring and continuing")
        }
        return await responseHandler(accountResponse)
    }

    private enum ChangeNumberResult {
        case serviceResponse(AccountResponse)
        case pniStateError
    }

    private func generatePniStateAndMakeChangeNumberRequest(
        e164: E164,
        verificationMethod: RegistrationRequestFactory.VerificationMethod,
        reglockToken: String?,
        changeNumberState: RegistrationCoordinatorLoaderImpl.Mode.ChangeNumberState
    ) async -> ChangeNumberResult {
        Logger.info("")

        let pniResult = await deps.changeNumberPniManager.generatePniIdentity(
            forNewE164: e164,
            localAci: changeNumberState.localAci,
            localDeviceId: changeNumberState.localDeviceId,
        )

        switch pniResult {
        case .failure:
            return .pniStateError
        case .success(let pniParams, let pniPendingState):
            return await makeChangeNumberRequest(
                e164: e164,
                verificationMethod: verificationMethod,
                reglockToken: reglockToken,
                changeNumberState: changeNumberState,
                pniPendingState: pniPendingState,
                pniParams: pniParams
            )
        }
    }

    @MainActor
    private func makeChangeNumberRequest(
        e164: E164,
        verificationMethod: RegistrationRequestFactory.VerificationMethod,
        reglockToken: String?,
        changeNumberState: RegistrationCoordinatorLoaderImpl.Mode.ChangeNumberState,
        pniPendingState: ChangePhoneNumberPni.PendingState,
        pniParams: PniDistribution.Parameters
    ) async -> ChangeNumberResult {
        Logger.info("")

        // Process all messages first. The caller doesn't invoke this method when
        // "pniState" is set, and message processing is only suspended when
        // "pniState" is set. So it's safe to always wait here.
        await deps.messageProcessor.waitForFetchingAndProcessing().awaitable()

        do {
            try db.write { tx in
                self._unsafeToModify_mode = .changingNumber(try self.loader.savePendingChangeNumber(
                    oldState: changeNumberState,
                    pniState: pniPendingState.asRegPniState(),
                    transaction: tx
                ))
            }
        } catch {
            return .pniStateError
        }

        return .serviceResponse(await Service.makeChangeNumberRequest(
            verificationMethod,
            e164: e164,
            reglockToken: reglockToken,
            authPassword: changeNumberState.oldAuthToken,
            pniChangeNumberParameters: pniParams,
            networkManager: deps.networkManager,
        ))
    }

    @MainActor
    private func recoverPendingPniChangeNumberState(
        changeNumberState: Mode.ChangeNumberState,
        pniState: Mode.ChangeNumberState.PendingPniState
    ) async -> RegistrationStep {
        Logger.info("")

        let whoAmIResult = await Service.makeWhoAmIRequest(
            auth: ChatServiceAuth.explicit(
                aci: changeNumberState.localAci,
                deviceId: .primary,
                password: changeNumberState.oldAuthToken
            ),
            networkManager: deps.networkManager,
        )

        switch whoAmIResult {
        case .networkError, .genericError:
            return .showErrorSheet(.genericError)
        case .success(let whoAmIResponse):
            if whoAmIResponse.e164 == pniState.newE164 {
                // Success! Fake us getting the success response.
                db.write { tx in
                    handleSuccessfulAccountResponse(
                        identity: AccountIdentity(
                            aci: whoAmIResponse.aci,
                            pni: whoAmIResponse.pni,
                            e164: whoAmIResponse.e164,
                            hasPreviouslyUsedSVR: inMemoryState.didHaveSVRBackupsPriorToReg,
                            authPassword: changeNumberState.oldAuthToken
                        ),
                        tx
                    )
                }
                return await nextStep()
            } else {
                // We had an in progress change number, but we arent on that number now.
                // pretend it never happened.
                do {
                    try db.write { tx in
                        _unsafeToModify_mode = .changingNumber(try loader.savePendingChangeNumber(
                            oldState: changeNumberState,
                            pniState: nil,
                            transaction: tx
                        ))
                    }
                } catch {
                    return .showErrorSheet(.genericError)
                }
                return await nextStep()
            }
        }
    }

    private func handleSuccessfulAccountResponse(
        identity: AccountIdentity,
        _ transaction: DBWriteTransaction
    ) {
        inMemoryState.session = nil
        deps.sessionManager.clearPersistedSession(transaction)
        updatePersistedState(transaction) {
            $0.accountIdentity = identity
            $0.sessionState = nil
        }
    }

    // MARK: - Becoming deregistered while registering

    @MainActor
    private func becameDeregisteredBeforeCompleting(
        accountIdentity: AccountIdentity
    ) async -> RegistrationStep {
        Logger.info("")

        switch mode {
        case .registering, .reRegistering:
            break
        case .changingNumber(let changeNumberState):
            if let pniState = changeNumberState.pniState {
                _ = await finalizeChangeNumberPniState(
                    changeNumberState: changeNumberState,
                    pniState: pniState,
                    accountIdentity: accountIdentity
                )
            }
        }

        Logger.warn("Got deregistered while completing registration; starting over with re-registration.")
        db.write { tx in
            wipePersistedState(tx)
        }

        // We just registered but couldn't finish setting up our profile. The web
        // socket should already be closed, but we need to clean up its state.
        await deps.registrationWebSocketManager.releaseRestrictedWebSocket(isRegistered: false)
        inMemoryState.hasOpenedConnection = false

        return .showErrorSheet(.becameDeregistered(reregParams: .init(
            e164: accountIdentity.e164,
            aci: accountIdentity.aci
        )))
    }

    // MARK: - Account objects

    private func reglockToken(for e164: E164) -> String? {
        if
            (
                inMemoryState.wasReglockEnabledBeforeStarting
                || persistedState.e164WithKnownReglockEnabled == e164
            ),
            let reglockToken = inMemoryState.reglockToken
        {
            return reglockToken
        }

        return nil
    }

    private func makeAccountAttributes(
        isManualMessageFetchEnabled: Bool,
        reglockToken: String?,
    ) -> AccountAttributes {
        let hasSVRBackups: Bool
        switch getPathway() {
        case
                .opening,
                .quickRestore,
                .manualRestore,
                .registrationRecoveryPassword,
                .svrAuthCredential,
                .svrAuthCredentialCandidates,
                .session:
            hasSVRBackups = inMemoryState.didHaveSVRBackupsPriorToReg
        case .profileSetup:
            if inMemoryState.didHaveSVRBackupsPriorToReg && !inMemoryState.didSkipSVRBackup {
                hasSVRBackups = true
            } else if inMemoryState.hasRestoredFromStorageService {
                hasSVRBackups = true
            } else if inMemoryState.hasBackedUpToSVR {
                hasSVRBackups = true
            } else {
                hasSVRBackups = false
            }
        }
        return AccountAttributes(
            isManualMessageFetchEnabled: isManualMessageFetchEnabled,
            registrationId: persistedState.aciRegistrationId,
            pniRegistrationId: persistedState.pniRegistrationId,
            unidentifiedAccessKey: inMemoryState.udAccessKey.keyData.base64EncodedString(),
            unrestrictedUnidentifiedAccess: inMemoryState.allowUnrestrictedUD,
            reglockToken: reglockToken,
            registrationRecoveryPassword: inMemoryState.regRecoveryPw,
            encryptedDeviceName: nil, // This class only deals in primary devices, which have no name
            discoverableByPhoneNumber: inMemoryState.phoneNumberDiscoverability,
            capabilities: AccountAttributes.Capabilities(hasSVRBackups: hasSVRBackups),
        )
    }

    @MainActor
    private func fetchApnRegistrationId() async -> Registration.RequestPushTokensResult{
        guard !inMemoryState.isManualMessageFetchEnabled else {
            return .pushUnsupported(description: "Manual fetch pre-enabled")
        }
        return await self.deps.pushRegistrationManager.requestPushToken()
    }

    private func generateServerAuthToken() -> String {
        return Randomness.generateRandomBytes(16).hexadecimalString
    }

    struct AccountIdentity: Codable {
        @AciUuid var aci: Aci
        @PniUuid var pni: Pni
        let e164: E164
        let hasPreviouslyUsedSVR: Bool

        /// The auth token used to communicate with the server.
        /// We create this locally and include it in the create account request,
        /// then use it to authenticate subsequent requests.
        let authPassword: String

        var authUsername: String {
            return aci.serviceIdString
        }

        var authedAccount: AuthedAccount {
            return AuthedAccount.explicit(
                aci: aci,
                pni: pni,
                e164: e164,
                deviceId: .primary,
                authPassword: authPassword
            )
        }

        var authedDevice: AuthedDevice {
            return .explicit(AuthedDevice.Explicit(
                aci: aci,
                phoneNumber: e164,
                pni: pni,
                deviceId: .primary,
                authPassword: authPassword
            ))
        }

        var chatServiceAuth: ChatServiceAuth {
            return ChatServiceAuth.explicit(
                aci: aci,
                deviceId: .primary,
                password: authPassword
            )
        }

        var localIdentifiers: LocalIdentifiers {
            return AuthedDevice.Explicit(
                aci: aci,
                phoneNumber: e164,
                pni: pni,
                deviceId: .primary,
                authPassword: authPassword
            ).localIdentifiers
        }
    }

    enum AccountResponse {
        case success(AccountIdentity)
        case reglockFailure(RegistrationServiceResponses.RegistrationLockFailureResponse)
        /// The verification method attempted was rejected.
        /// Either the session was invalid/expired or the registration recovery password was wrong.
        case rejectedVerificationMethod
        case deviceTransferPossible
        case retryAfter(TimeInterval?)
        case networkError
        case genericError
    }

    // MARK: - Step State Generation Helpers

    private enum RemoteValidationError {
        case invalidE164(RegistrationPhoneNumberViewState.ValidationError.InvalidE164)
        case rateLimited(RegistrationPhoneNumberViewState.ValidationError.RateLimited)

        func asViewStateError() -> RegistrationPhoneNumberViewState.ValidationError {
            switch self {
            case let .invalidE164(error):
                return .invalidE164(error)
            case let .rateLimited(error):
                return .rateLimited(error)
            }
        }
    }

    private func phoneNumberEntryState(
        validationError: RemoteValidationError? = nil
    ) -> RegistrationPhoneNumberViewState {
        switch mode {
        case .registering:
            return .registration(.initialRegistration(.init(
                previouslyEnteredE164: persistedState.e164,
                validationError: validationError?.asViewStateError(),
                canExitRegistration: canExitRegistrationFlow().canExit
            )))
        case .reRegistering(let state):
            return .registration(.reregistration(.init(
                e164: state.e164,
                validationError: validationError?.asViewStateError(),
                canExitRegistration: canExitRegistrationFlow().canExit
            )))
        case .changingNumber(let state):
            var rateLimitedError: RegistrationPhoneNumberViewState.ValidationError.RateLimited?
            switch validationError {
            case .none:
                break
            case .rateLimited(let error):
                rateLimitedError = error
            case .invalidE164(let invalidE164Error):
                return .changingNumber(.initialEntry(.init(
                    oldE164: state.oldE164,
                    newE164: inMemoryState.changeNumberProspectiveE164,
                    hasConfirmed: inMemoryState.changeNumberProspectiveE164 != nil,
                    invalidE164Error: invalidE164Error
                )))
            }
            if let newE164 = inMemoryState.changeNumberProspectiveE164 {
                return .changingNumber(.confirmation(.init(
                    oldE164: state.oldE164,
                    newE164: newE164,
                    rateLimitedError: rateLimitedError
                )))
            } else {
                return .changingNumber(.initialEntry(.init(
                    oldE164: state.oldE164,
                    newE164: nil,
                    hasConfirmed: false,
                    invalidE164Error: nil
                )))
            }
        }
    }

    private func verificationCodeEntryState(
        session: RegistrationSession,
        validationError: RegistrationVerificationValidationError? = nil
    ) -> RegistrationVerificationState {
        let exitConfiguration: RegistrationVerificationState.ExitConfiguration
        if canExitRegistrationFlow().canExit {
            switch mode {
            case .registering:
                exitConfiguration = .noExitAllowed
            case .reRegistering:
                exitConfiguration = .exitReRegistration
            case .changingNumber:
                exitConfiguration = .exitChangeNumber
            }
        } else {
            exitConfiguration = .noExitAllowed
        }

        let canChangeE164: Bool
        switch mode {
        case .reRegistering:
            canChangeE164 = false
        case .registering, .changingNumber:
            canChangeE164 = true
        }

        return RegistrationVerificationState(
            e164: session.e164,
            nextSMSDate: session.nextSMSDate,
            nextCallDate: session.nextCallDate,
            nextVerificationAttemptDate: session.nextVerificationAttemptDate,
            canChangeE164: canChangeE164,
            // TODO[Registration]: pass up the number directly here, and test for it.
            showHelpText: (persistedState.sessionState?.numVerificationCodeSubmissions ?? 0) >= 3,
            validationError: validationError,
            exitConfiguration: exitConfiguration
        )
    }

    private func pinCodeEntryExitConfiguration() -> RegistrationPinState.ExitConfiguration {
        guard canExitRegistrationFlow().canExit else {
            return .noExitAllowed
        }
        switch mode {
        case .registering:
            return .noExitAllowed
        case .reRegistering:
            return .exitReRegistration
        case .changingNumber:
            return .exitChangeNumber
        }
    }

    private func contactSupportRegistrationPINMode() -> ContactSupportActionSheet.EmailFilter.RegistrationPINMode {
        switch getPathway() {
        case .opening, .quickRestore, .manualRestore:
            owsFailBeta("Should not be asking for PIN during opening path.")
            return .v2WithUnknownReglockState
        case .svrAuthCredential, .svrAuthCredentialCandidates, .registrationRecoveryPassword:
            if
                let e164 = persistedState.e164,
                e164 == persistedState.e164WithKnownReglockEnabled
            {
                return .v2WithReglock
            }
            return .v2WithUnknownReglockState
        case .session:
            return .v2WithReglock
        case .profileSetup:
            // If they are in profile setup that means they
            // would have gotten past reglock already.
            return .v2NoReglock
        }
    }

    private var reglockTimeoutAcknowledgeAction: RegistrationReglockTimeoutAcknowledgeAction {
        switch mode {
        case .registering: return .resetPhoneNumber
        case .reRegistering, .changingNumber:
            if canExitRegistrationFlow().canExit {
                return .close
            } else {
                return .none
            }
        }
    }

    private var verificationCodeSubmissionRejectedError: RegistrationStep {
        switch persistedState.sessionState?.initialCodeRequestState {
        case
                .none,
                .neverRequested,
                .failedToRequest,
                .permanentProviderFailure,
                .transientProviderFailure,
                .smsTransportFailed:
            return .showErrorSheet(.submittingVerificationCodeBeforeAnyCodeSent)
        case .exhaustedCodeAttempts, .requested:
            return .showErrorSheet(.verificationCodeSubmissionUnavailable)
        }
    }

    private func shouldAttemptToReclaimUsername() -> Usernames.LocalUsernameState? {
        switch mode {
        case .registering, .reRegistering:
            switch inMemoryState.usernameReclamationState {
            case .localUsernameStateNotLoaded, .reclamationAttempted:
                return nil
            case .localUsernameStateLoaded(let localUsernameState):
                return localUsernameState
            }
        case .changingNumber:
            return nil
        }
    }

    private func shouldRestoreFromMessageBackup() -> Bool {
        switch mode {
        case .registering:
            return
                inMemoryState.accountEntropyPool != nil
                && inMemoryState.hasBackedUpToSVR
                && inMemoryState.backupRestoreState == .none
                && !inMemoryState.hasSkippedRestoreFromMessageBackup
        case .changingNumber, .reRegistering:
            return false
        }
    }

    private func shouldRestoreFromStorageServiceBeforeUpdatingSVR() -> Bool {
        switch mode {
        case .registering, .reRegistering:
            return !inMemoryState.hasRestoredFromStorageService
                && !inMemoryState.hasSkippedRestoreFromStorageService
                && !inMemoryState.shouldRestoreSVRMasterKeyAfterRegistration
                && persistedState.restoreMethod?.backupType == nil
        case .changingNumber:
            return false
        }
    }

    private func shouldRestoreFromStorageService() -> Bool {
        switch mode {
        case .registering, .reRegistering:
            return !inMemoryState.hasRestoredFromStorageService
                && !inMemoryState.hasSkippedRestoreFromStorageService
                && persistedState.restoreMethod?.backupType == nil
        case .changingNumber:
            return false
        }
    }

    private func shouldRefreshOneTimePreKeys() -> Bool {
        switch mode {
        case .registering, .reRegistering:
            return !persistedState.didRefreshOneTimePreKeys
        case .changingNumber:
            return false
        }
    }

    /// Any path that results in registration with an old AEP that doesn't go
    /// through the backup restore needs to handle this. Note that the SVRB
    /// restore doesn't need to succeed here, but we do need to persist that a
    /// restore is needed to ensure the restore happens before the first backup.
    ///
    /// Registration paths to consider:
    /// | Registration path | SVRB action |
    /// |---|---|
    /// | re-registration | **Scheduled fetch needed** |
    /// | basic reg - backup restore | Fetched during restore |
    /// | basic reg - transfer | none |
    /// | basic reg - skip restore | New AEP, no fetch needed |
    /// | manual restore - backup restore | Fetched during restore |
    /// | manual restore - skip restore | **Scheduled fetch needed** |
    /// | quick restore - backup restore | Fetched during restore |
    /// | quick restore - transfer | none |
    /// | quick restore - skip restore | **Scheduled fetch needed** |
    private func needsToScheduleRestoreFromSVRB() -> Bool {
        switch mode {
        case .reRegistering:
            return true
        case .registering:
            return
                persistedState.restoreMode != nil &&
                persistedState.restoreMethod == .declined
        case .changingNumber:
            return false
        }
    }

    // MARK: - Exit

    private enum RegExitState {
        case allowed(shouldWipeState: Bool)
        case notAllowed

        var canExit: Bool {
            switch self {
            case .allowed:
                return true
            case .notAllowed:
                return false
            }
        }
    }

    private func canExitRegistrationFlow() -> RegExitState {
        switch mode {
        case .registering:
            if persistedState.hasResetForReRegistration {
                // Once you have reset its too late.
                return .notAllowed
            }
            // If we had a bug that puts you into the reg flow despite being registered,
            // we make that bug worse by keeping you in the reg flow forever. So allow
            // exiting only if the reg state was registered. Doing so should wipe your state.
            guard inMemoryState.tsRegistrationState?.isRegistered == true else {
                return .notAllowed
            }
            return .allowed(shouldWipeState: true)
        case .reRegistering:
            if persistedState.hasResetForReRegistration {
                // Once you have reset its too late.
                return .notAllowed
            }
            // Wipe if you were previously registered, so we don't send you here
            // on every app launch. If you were deregistered, we _want_ to send
            // you here by default and save your progress, so don't wipe state.
            return .allowed(shouldWipeState: inMemoryState.tsRegistrationState?.isRegistered == true)
        case .changingNumber(let state):
            return state.pniState == nil ? .allowed(shouldWipeState: true) : .notAllowed
        }
    }

    // MARK: - Constants

    enum Constants {
        static let persistedStateKey = "state"

        // how many times we will retry network errors.
        static let networkErrorRetries = 1

        // If a request that can be retried has a timeout below this
        // threshold, we will auto-retry it.
        // (e.g. you try sending an sms code and the nextSMS is less than this.)
        static let autoRetryInterval: TimeInterval = 0.5

        // If we have a PIN and SVR master key locally (only possible for re-registration)
        // then we reuse it to register. We make the user guess the PIN before proceeding,
        // though. This is how many tries they have before we wipe our local state and make
        // them go through re-registration.
        static let maxLocalPINGuesses: UInt = 10
    }
}

extension Error {

    fileprivate var isPostRegDeregisteredError: Bool {
        switch self {
        case is NotRegisteredError:
            return true
        case let error as OWSHTTPError where error.responseStatusCode == 401:
            return true
        default:
            return false
        }
    }
}
