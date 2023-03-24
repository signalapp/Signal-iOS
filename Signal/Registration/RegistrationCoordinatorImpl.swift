//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Contacts
import Foundation

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
        self.kvStore = dependencies.keyValueStoreFactory.keyValueStore(collection: "RegistrationCoordinator")
        self.loader = loader
        self.deps = dependencies
    }

    // MARK: - Public API

    public func exitRegistration() -> Bool {
        guard canExitRegistrationFlow() else {
            return false
        }
        switch mode {
        case .registering, .reRegistering:
            // Preserve all state so they can come back and pick up
            // where they left off, probably on next app launch.
            break
        case .changingNumber:
            // Wipe in progress state; presumably the user decided not
            // to change number.
            self.wipePersistedState()
        }
        return true
    }

    public func nextStep() -> Guarantee<RegistrationStep> {
        AssertIsOnMainThread()

        if deps.appExpiry.isExpired {
            return .value(.appUpdateBanner)
        }

        // Always start by restoring state.
        return restoreStateIfNeeded().then(on: schedulers.main) { [weak self] () -> Guarantee<RegistrationStep> in
            guard let self = self else {
                owsFailBeta("Unretained self lost")
                return .value(.splash)
            }
            return self.nextStep(pathway: self.getPathway())
        }
    }

    public func continueFromSplash() -> Guarantee<RegistrationStep> {
        db.write { tx in
            self.updatePersistedState(tx) {
                $0.hasShownSplash = true
            }
        }
        return nextStep()
    }

    public func requestPermissions() -> Guarantee<RegistrationStep> {
        // Notifications first, then contacts if needed.
        return deps.pushRegistrationManager.registerUserNotificationSettings()
            .then(on: schedulers.main) { [weak self] in
                guard let self else {
                    owsFailBeta("Unretained self lost")
                    return .value(())
                }
                return self.deps.contactsStore.requestContactsAuthorization()
            }
            .then(on: schedulers.main) { [weak self] in
                guard let self else {
                    owsFailBeta("Unretained self lost")
                    return .value(.splash)
                }
                self.inMemoryState.needsSomePermissions = false
                return self.nextStep()
            }
    }

    public func submitProspectiveChangeNumberE164(_ e164: E164) -> Guarantee<RegistrationStep> {
        self.inMemoryState.changeNumberProspectiveE164 = e164
        return nextStep()
    }

    public func submitE164(_ e164: E164) -> Guarantee<RegistrationStep> {
        db.write { tx in
            updatePersistedState(tx) {
                $0.e164 = e164
            }
        }
        inMemoryState.hasEnteredE164 = true
        return nextStep()
    }

    public func requestChangeE164() -> Guarantee<RegistrationStep> {
        db.write { tx in
            updatePersistedState(tx) {
                $0.e164 = nil
            }
            // Reset the session; it is e164 dependent.
            resetSession(tx)
            // Reload auth credential candidates; we might not have
            // had a credential for the old e164 but might have one for
            // the new e164!
            loadkbsAuthCredentialCandidates(tx)
        }
        inMemoryState.hasEnteredE164 = false
        inMemoryState.changeNumberProspectiveE164 = nil
        return nextStep()
    }

    public func requestSMSCode() -> Guarantee<RegistrationStep> {
        switch getPathway() {
        case
                .opening,
                .registrationRecoveryPassword,
                .kbsAuthCredential,
                .kbsAuthCredentialCandidates,
                .profileSetup:
            owsFailBeta("Shouldn't be resending SMS from non session paths.")
            return nextStep()
        case .session:
            inMemoryState.pendingCodeTransport = .sms
            return nextStep()
        }
    }

    public func requestVoiceCode() -> Guarantee<RegistrationStep> {
        switch getPathway() {
        case
                .opening,
                .registrationRecoveryPassword,
                .kbsAuthCredential,
                .kbsAuthCredentialCandidates,
                .profileSetup:
            owsFailBeta("Shouldn't be sending voice code from non session paths.")
            return nextStep()
        case .session:
            inMemoryState.pendingCodeTransport = .voice
            return nextStep()
        }
    }

    public func submitVerificationCode(_ code: String) -> Guarantee<RegistrationStep> {
        switch getPathway() {
        case
                .opening,
                .registrationRecoveryPassword,
                .kbsAuthCredential,
                .kbsAuthCredentialCandidates,
                .profileSetup:
            owsFailBeta("Shouldn't be submitting verification code from non session paths.")
            return nextStep()
        case .session(let session):
            return submitSessionCode(session: session, code: code)
        }
    }

    public func submitCaptcha(_ token: String) -> Guarantee<RegistrationStep> {
        switch getPathway() {
        case
                .opening,
                .registrationRecoveryPassword,
                .kbsAuthCredential,
                .kbsAuthCredentialCandidates,
                .profileSetup:
            owsFailBeta("Shouldn't be submitting captcha from non session paths.")
            return nextStep()
        case .session(let session):
            return submit(challengeFulfillment: .captcha(token), for: session)
        }
    }

    public func setPINCodeForConfirmation(_ blob: RegistrationPinConfirmationBlob) -> Guarantee<RegistrationStep> {
        inMemoryState.unconfirmedPinBlob = blob
        return nextStep()
    }

    public func resetUnconfirmedPINCode() -> Guarantee<RegistrationStep> {
        inMemoryState.unconfirmedPinBlob = nil
        return nextStep()
    }

    public func submitPINCode(_ code: String) -> Guarantee<RegistrationStep> {
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
                        deps.kbs.clearKeys(transaction: tx)
                    }
                    self.wipeInMemoryStateToPreventKBSPathAttempts()
                    return .value(.showErrorSheet(.pinGuessesExhausted))
                } else {
                    let remainingAttempts = Constants.maxLocalPINGuesses - numberOfWrongGuesses
                    return .value(.pinEntry(RegistrationPinState(
                        operation: .enteringExistingPin(
                            canSkip: true,
                            remainingAttempts: remainingAttempts
                        ),
                        error: .wrongPin(wrongPin: code),
                        exitConfiguration: pinCodeEntryExitConfiguration()
                    )))
                }
            }
        case .opening, .kbsAuthCredential, .kbsAuthCredentialCandidates, .profileSetup, .session:
            // We aren't checking against any local state, rely on the request.
            break
        }
        self.inMemoryState.pinFromUser = code
        // Individual pathway's steps should handle whatever needs to be done with the pin,
        // depending on the current pathway.
        return nextStep()
    }

    public func skipPINCode() -> Guarantee<RegistrationStep> {
        db.write { tx in
            updatePersistedState(tx) {
                $0.hasSkippedPinEntry = true
            }
            // Whenever we do this, wipe the keys we've got.
            // We don't want to have them and use then implicitly later.
            deps.kbs.clearKeys(transaction: tx)
        }
        self.wipeInMemoryStateToPreventKBSPathAttempts()
        return nextStep()
    }

    public func skipDeviceTransfer() -> Guarantee<RegistrationStep> {
        db.write { tx in
            updatePersistedState(tx) {
                $0.hasDeclinedTransfer = true
            }
        }
        return self.nextStep()
    }

    public func setPhoneNumberDiscoverability(_ isDiscoverable: Bool) -> Guarantee<RegistrationStep> {
        guard let accountIdentity = persistedState.accountIdentity else {
            owsFailBeta("Shouldn't be setting phone number discoverability prior to registration.")
            return .value(.showErrorSheet(.genericError))
        }

        updatePhoneNumberDiscoverability(
            accountIdentity: accountIdentity,
            isDiscoverable: isDiscoverable
        )

        return self.nextStep()
    }

    public func setProfileInfo(
        givenName: String,
        familyName: String?,
        avatarData: Data?,
        isDiscoverableByPhoneNumber: Bool
    ) -> Guarantee<RegistrationStep> {
        guard let accountIdentity = persistedState.accountIdentity else {
            owsFailBeta("Shouldn't be setting phone number discoverability prior to registration.")
            return .value(.showErrorSheet(.genericError))
        }
        inMemoryState.pendingProfileInfo = (givenName: givenName, familyName: familyName, avatarData: avatarData)

        updatePhoneNumberDiscoverability(
            accountIdentity: accountIdentity,
            isDiscoverable: isDiscoverableByPhoneNumber
        )

        return self.nextStep()
    }

    public func acknowledgeReglockTimeout() -> Guarantee<RegistrationStep> {
        switch reglockTimeoutAcknowledgeAction {
        case .resetPhoneNumber:
            db.write { transaction in
                self.resetSession(transaction)
                self.updatePersistedState(transaction) { $0.e164 = nil }
            }
            return nextStep()
        case .close:
            // TODO[Registration] Do mode-specific cleanup.
            return .value(.done)
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
    private var db: DB { deps.db }
    private var schedulers: Schedulers { deps.schedulers }

    // MARK: - In Memory State

    /// This is state that only exists for an in-memory registration attempt;
    /// it is wiped if the app is evicted from memory or registration is completed.
    private struct InMemoryState {
        var hasRestoredState = false

        // Whether some system permissions (contacts, APNS) are needed.
        var needsSomePermissions = false

        // We persist the entered e164. But in addition we need to
        // know whether its been entered during this app launch; if it
        // hasn't we want to explicitly ask the user for it before
        // sending an SMS. But if we have (e.g. we asked for it to try
        // some KBS recovery that failed) we should auto-send an SMS if
        // we get to that step without asking again.
        var hasEnteredE164 = false

        // When changing number, we ask the user to confirm old number and
        // enter the new number before confirming the new number.
        // This tracks that first check before the confirm.
        var changeNumberProspectiveE164: E164?

        var shouldRestoreKBSMasterKeyAfterRegistration = false
        // base64 encoded data
        var regRecoveryPw: String?
        // hexadecimal encoded data
        var reglockToken: String?

        // candidate credentials, which may not
        // be valid, or may not correspond with the current e164.
        var kbsAuthCredentialCandidates: [KBSAuthCredential]?
        // A credential we know to be valid and useable for
        // the current e164.
        var kbsAuthCredential: KBSAuthCredential?
        // If we had kbs backups before registration even began.
        var didHaveKbsBackupsPriorToReg = false

        // We always require the user to enter the PIN
        // during the in memory app session even if we
        // have it on disk.
        // This is a way to double check they know the PIN.
        var pinFromUser: String?
        var pinFromDisk: String?
        // A really old user might be on v1 2fa; they have a PIN,
        // but no kbs backups. We will encourage backing up
        // to kbs but the user may skip it.
        var isV12faUser: Bool = false
        var unconfirmedPinBlob: RegistrationPinConfirmationBlob?

        // Wehn we try to register, if we get a response from the server
        // telling us device transfer is possible, we set this to true
        // so the user can explicitly opt out if desired and we retry.
        var needsToAskForDeviceTransfer = false

        var session: RegistrationSession?

        // If we try and resend a code (NOT the original SMS code automatically sent
        // at the start of every session), but hit a challenge, we write this var
        // so that when we complete the challenge we send the code right away.
        var pendingCodeTransport: Registration.CodeTransport?

        // Once we register with the server we have to set
        // up contacts manager for syncs (letting it know this
        // is the primary device). Do this again if we relaunch.
        var hasSetUpContactsManager = false

        // Every time we go through registration, we should back up our KBS master
        // secret's random bytes to KBS. Its safer to do this more than it is to do
        // it less, so keeping this state in memory.
        var hasBackedUpToKBS = false
        var didSkipKBSBackup = false
        var shouldBackUpToKBS: Bool {
            return hasBackedUpToKBS.negated && didSkipKBSBackup.negated
        }

        // OWS2FAManager state
        // If we are re-registering or changing number and
        // reglock was enabled, we should enable it again when done.
        var wasReglockEnabled = false
        var hasSetReglock = false

        var pendingProfileInfo: (givenName: String, familyName: String?, avatarData: Data?)?

        // TSAccountManager state
        var registrationId: UInt32!
        var pniRegistrationId: UInt32!
        var isManualMessageFetchEnabled = false
        var hasDefinedIsDiscoverableByPhoneNumber = false
        var isDiscoverableByPhoneNumber = false

        // OWSProfileManager state
        var profileKey: OWSAES256Key!
        var udAccessKey: SMKUDAccessKey!
        var allowUnrestrictedUD = false
        var hasProfileName = false

        // Once we have our kbs master key locally,
        // we can restore profile info from storage service.
        var hasRestoredFromStorageService = false
        var hasSkippedRestoreFromStorageService = false
    }

    private var inMemoryState = InMemoryState()

    // MARK: - Persisted State

    /// This state is kept across launches of registration. Whatever is set
    /// here must be explicitly wiped between sessions if desired.
    /// Note: We don't persist RegistrationSession because RegistrationSessionManager
    /// handles that; we restore it to InMemoryState instead.
    /// Note: `mode` is kept separate; it has a different lifecycle than the rest
    /// of PersistedState even though it is also persisted to disk.
    private struct PersistedState: Codable {
        /// We only ever want to show the splash once.
        var hasShownSplash = false
        var shouldSkipRegistrationSplash = false

        /// When re-registering, just before completing the actual create account
        /// request, we wipe our local state for re-registration. We only do this once,
        /// and once we do, there is no turning back.
        var hasResetForReRegistration = false

        /// The e164 the user has entered for this attempt at registration.
        /// Initially the e164 in the UI may be pre-populated (e.g. in re-reg)
        /// but this value is not set until the user accepts it or enters their own value.
        var e164: E164?

        /// How many times the user has tried making guesses against the PIN
        /// we have locally? This happens when we have a local KBS master key
        /// and want to confirm the user knows their PIN before using it to register.
        var numLocalPinGuesses: UInt = 0

        /// There are a few times we ask for the PIN that are skippable:
        ///
        /// * Registration recovery password path: we have your KBS master key locally, ask for PIN,
        ///   user skips, we stop trying to use the local master key and fall back to session-based
        ///   registration.
        ///
        /// * KBS Auth Credential path(s): we try and recover the KBS master secret from backups,
        ///   ask for PIN, user skips, we stop trying to recover the backup and fall back to
        ///   session-based registration.
        ///
        /// * Post-registration, if reglock was not enabled but there are KBS backups, we try and
        ///   recover them. If the user skips, we don't bother recovering.
        ///
        /// In a single flow, the user might hit more than one of these cases (and probably will;
        /// if they have KBS backups and skip in favor of session-based reg, we will see that
        /// they have backups post-registration). This skip applies to _all_ of these; if they
        /// skipped the PIN early on, we won't ask for it again for recovery purposes later.
        var hasSkippedPinEntry = false

        struct SessionState: Codable {
            let sessionId: String

            enum ReglockState: Codable {
                /// No reglock known of preventing registration.
                case none
                /// We tried to register and got reglocked; we have to
                /// recover from KBS with the credential given.
                case reglocked(credential: KBSAuthCredential, expirationDate: Date)
                /// We couldn't recover credentials from KBS (probably
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
            }

            var pushChallengeState: PushChallengeState = .notRequested
        }

        var sessionState: SessionState?

        /// Once we get an account identity response from the server
        /// for registering, re-registering, or changing phone number,
        /// we remember it so we don't re-register when we quit the app
        /// before finishing post-registration steps.
        var accountIdentity: AccountIdentity?

        /// Once per registration we want to sync push tokens up to
        /// the server. This might fail non-transiently because the device
        /// doesn't support push. We'd mark this as true and move on.
        var didSyncPushTokens: Bool = false

        /// Once per registration we sync prekeys (and the signed prekey)
        /// up to the server. We can't proceed until this succeeds.
        var didSyncPrekeys: Bool = false

        /// When we try and register, the server gives us an error if its possible
        /// to execute a device-to-device transfer. The user can decline; if they
        /// do, this will get set so we try force a re-register.
        /// Note if we are re-registering on the same primary device (based on mode),
        /// we ignore this field and always skip asking for device transfer.
        var hasDeclinedTransfer: Bool = false

        init() {}
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
    ///   e.g. we ask KeyBackupService for any KBS data so we know whether to attempt registration
    ///   via registration recovery password (if present) or via SMS (if not).
    ///   We don't want to check this on the fly because if we went down the SMS path we'd eventually
    ///   recover our KBS data, but we'd want to stick to the SMS registration path and NOT revert to
    ///   the registration recovery password path, which would cause us to repeat work. So we only
    ///   grab a snapshot at the start and use that exclusively for state determination.
    private func restoreStateIfNeeded() -> Guarantee<Void> {
        if inMemoryState.hasRestoredState {
            return .value(())
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
            self.loadLocalMasterKey(tx)
            inMemoryState.pinFromDisk = deps.ows2FAManager.pinCode(tx)
            if
                inMemoryState.pinFromDisk != nil,
                deps.kbs.hasBackedUpMasterKey(transaction: tx).negated
            {
                // If we had a pin but no kbs backups, we must be a v1 2fa user.
                inMemoryState.isV12faUser = true
            }

            loadkbsAuthCredentialCandidates(tx)
            inMemoryState.isManualMessageFetchEnabled = deps.tsAccountManager.isManualMessageFetchEnabled(tx)
            inMemoryState.registrationId = deps.tsAccountManager.getOrGenerateRegistrationId(tx)
            inMemoryState.pniRegistrationId = deps.tsAccountManager.getOrGeneratePniRegistrationId(tx)

            inMemoryState.allowUnrestrictedUD = deps.udManager.shouldAllowUnrestrictedAccessLocal(transaction: tx)

            inMemoryState.wasReglockEnabled = deps.ows2FAManager.isReglockEnabled(tx)
        }

        let sessionGuarantee: Guarantee<Void> = deps.sessionManager.restoreSession()
            .map(on: schedulers.main) { [weak self] session in
                self?.db.write { self?.processSession(session, $0) }
            }

        let permissionsGuarantee: Guarantee<Void> = requiresSystemPermissions()
            .map(on: schedulers.main) { [weak self] needsPermissions in
                self?.inMemoryState.needsSomePermissions = needsPermissions
            }

        return Guarantee.when(resolved: sessionGuarantee, permissionsGuarantee).asVoid()
            .done(on: schedulers.main) { [weak self] in
                self?.inMemoryState.hasRestoredState = true
            }
    }

    /// Once registration is complete, we need to take our internal state and write it out to
    /// external classes so that the rest of the app has all our updated information.
    /// Once this is done, we can wipe the internal state of this class so that we get a fresh
    /// registration if we ever re-register while in the same app session.
    private func exportAndWipeState(accountIdentity: AccountIdentity) -> Guarantee<RegistrationStep> {

        func finalizeRegistration(_ tx: DBWriteTransaction) {
            if inMemoryState.hasBackedUpToKBS {
                // No need to show the experience if we made the pin
                // and backed up.
                deps.experienceManager.clearIntroducingPinsExperience(tx)
            }

            deps.tsAccountManager.didRegister(
                e164: accountIdentity.e164,
                aci: accountIdentity.aci,
                pni: accountIdentity.pni,
                authToken: accountIdentity.authPassword,
                tx
            )
            deps.tsAccountManager.setIsOnboarded(tx)
        }

        func setupContactsAndFinish() -> Guarantee<RegistrationStep> {
            // Start syncing system contacts now that we have set up tsAccountManager.
            deps.contactsManager.fetchSystemContactsOnceIfAlreadyAuthorized(authedAccount: accountIdentity.authedAccount)

            // Update the account attributes once, now, at the end.
            return updateAccountAttributesAndFinish(accountIdentity: accountIdentity)
        }

        switch mode {
        case .registering:
            db.write { tx in
                // For new users, read receipts are on by default.
                deps.receiptManager.setAreReadReceiptsEnabled(true, tx)
                deps.receiptManager.setAreStoryViewedReceiptsEnabled(true, tx)
                // New users also have the onboarding banner cards enabled
                deps.experienceManager.enableAllGetStartedCards(tx)
                finalizeRegistration(tx)
            }
            return setupContactsAndFinish()

        case .reRegistering:
            db.write(block: finalizeRegistration)
            return setupContactsAndFinish()

        case .changingNumber(let changeNumberState):
            if let pniState = changeNumberState.pniState {
                return finalizeChangeNumberPniState(
                    changeNumberState: changeNumberState,
                    pniState: pniState,
                    accountIdentity: accountIdentity
                ).then(on: schedulers.main) { [weak self] result in
                    guard let self else {
                        return unretainedSelfError()
                    }
                    switch result {
                    case .success:
                        return self.updateAccountAttributesAndFinish(accountIdentity: accountIdentity)
                    case .unretainedSelf:
                        return unretainedSelfError()
                    case .genericError:
                        return .value(.showErrorSheet(.genericError))
                    }
                }
            } else {
                return updateAccountAttributesAndFinish(accountIdentity: accountIdentity)
            }
        }

    }

    private func updateAccountAttributesAndFinish(
        accountIdentity: AccountIdentity,
        retriesLeft: Int = Constants.networkErrorRetries
    ) -> Guarantee<RegistrationStep> {
        updateAccountAttributes(accountIdentity)
            .then(on: schedulers.main) { [weak self] error -> Guarantee<RegistrationStep> in
                guard let self else {
                    return unretainedSelfError()
                }
                if
                    let error,
                    error.isNetworkConnectivityFailure,
                    retriesLeft > 0
                {
                    return self.updateAccountAttributesAndFinish(
                        accountIdentity: accountIdentity,
                        retriesLeft: retriesLeft - 1
                    )
                }
                if let error {
                    Logger.warn("Failed account attributes update, finishing registration anyway: \(error)")
                }
                // We are done! Wipe everything
                self.inMemoryState = InMemoryState()
                self.wipePersistedState()
                // Do any storage service backups we have pending.
                self.deps.storageServiceManager.backupPendingChanges(authedAccount: accountIdentity.authedAccount)
                return .value(.done)
            }
    }

    private func wipePersistedState() {
        self.db.write { tx in
            self.kvStore.removeValue(forKey: Constants.persistedStateKey, transaction: tx)
            self.loader.clearPersistedMode(transaction: tx)
        }
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
        /// Attempting to register using the reg recovery password
        /// derived from the KBS master key.
        case registrationRecoveryPassword(password: String)
        /// Attempting to recover from KBS auth credentials
        /// which let us talk to KBS server, recover the master key,
        /// and swap to the registrationRecoveryPassword path.
        case kbsAuthCredential(KBSAuthCredential)
        /// We might have un-verified KBS auth credentials
        /// synced from another device; first we need to check them
        /// with the server and then potentially go to the kbsAuthCredential path.
        case kbsAuthCredentialCandidates([KBSAuthCredential])
        /// Verifying via SMS code using a `RegistrationSession`.
        /// Used as a fallback if the above paths are unavailable or fail.
        case session(RegistrationSession)
        /// After registration is done, all the steps involving setting up
        /// profile state (which may not be needed). Profile name,
        /// setting up a PIN, etc.
        case profileSetup(AccountIdentity)
    }

    private func getPathway() -> Pathway {
        if splashStepToShow() != nil || inMemoryState.needsSomePermissions {
            return .opening
        }
        if let session = inMemoryState.session {
            // If we have a session, always use that. We might have obtained kbs
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
            if let credential = inMemoryState.kbsAuthCredential {
                // If we have a validated kbs auth credential, try using that
                // to recover the KBS master key to register.
                // Once again, to get off this path and fall back to session (if it fails)
                // or proceed to reg recovery pw (if it succeeds) we must wipe this state.
                return .kbsAuthCredential(credential)
            }
            if let credentialCandidates = inMemoryState.kbsAuthCredentialCandidates,
               credentialCandidates.isEmpty.negated {
                // If we have un-vetted candidates, try checking those first
                // and then going to the kbsAuthCredential path if one is valid.
                return .kbsAuthCredentialCandidates(credentialCandidates)
            }
        }

        // If we have no state to pull from whatsoever, go to the opening.
        return .opening

    }

    private func nextStep(pathway: Pathway) -> Guarantee<RegistrationStep> {
        switch pathway {
        case .opening:
            return nextStepForOpeningPath()
        case .registrationRecoveryPassword(let password):
            return nextStepForRegRecoveryPasswordPath(regRecoveryPw: password)
        case .kbsAuthCredential(let credential):
            return nextStepForKBSAuthCredentialPath(kbsAuthCredential: credential)
        case .kbsAuthCredentialCandidates(let candidates):
            return nextStepForKBSAuthCredentialCandidatesPath(kbsAuthCredentialCandidates: candidates)
        case .session(let session):
            return nextStepForSessionPath(session)
        case .profileSetup(let accountIdentity):
            return nextStepForProfileSetup(accountIdentity)
        }
    }

    // MARK: - Opening Pathway

    private func nextStepForOpeningPath() -> Guarantee<RegistrationStep> {
        if let splashStep = splashStepToShow() {
            return .value(splashStep)
        }
        if inMemoryState.needsSomePermissions {
            // This class is only used for primary device registration
            // which always needs contacts permissions.
            return .value(.permissions(RegistrationPermissionsState(shouldRequestAccessToContacts: true)))
        }
        if inMemoryState.hasEnteredE164, let e164 = persistedState.e164 {
            return self.startSession(e164: e164)
        }
        return .value(.phoneNumberEntry(phoneNumberEntryState()))
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
            return .splash
        case .changingNumber:
            return .changeNumberSplash
        case .reRegistering:
            return nil
        }
    }

    // MARK: - Registration Recovery Password Pathway

    /// If we have the KBS master key saved locally (e.g. this is re-registration), we can generate the
    /// "Registration Recovery Password" from it, which we can use as an alternative to a verified SMS code session
    /// to register. This path returns the steps to complete that flow.
    private func nextStepForRegRecoveryPasswordPath(regRecoveryPw: String) -> Guarantee<RegistrationStep> {
        // We need a phone number to proceed; ask the user if unavailable.
        guard let e164 = persistedState.e164 else {
            return .value(.phoneNumberEntry(phoneNumberEntryState()))
        }

        guard let pinFromUser = inMemoryState.pinFromUser else {
            // We need the user to confirm their pin.
            return .value(.pinEntry(RegistrationPinState(
                // We can skip which will stop trying to use reg recovery.
                operation: .enteringExistingPin(canSkip: true, remainingAttempts: nil),
                error: nil,
                exitConfiguration: pinCodeEntryExitConfiguration()
            )))
        }

        if
            let pinFromDisk = inMemoryState.pinFromDisk,
            pinFromDisk != pinFromUser
        {
            Logger.warn("PIN mismatch; should be prevented at submission time.")
            return .value(.pinEntry(RegistrationPinState(
                operation: .enteringExistingPin(canSkip: true, remainingAttempts: nil),
                error: .wrongPin(wrongPin: pinFromUser),
                exitConfiguration: pinCodeEntryExitConfiguration()
            )))
        }

        if inMemoryState.needsToAskForDeviceTransfer && !persistedState.hasDeclinedTransfer {
            return .value(.transferSelection)
        }

        // Attempt to register right away with the password.
        return registerForRegRecoveryPwPath(
            regRecoveryPw: regRecoveryPw,
            e164: e164,
            pinFromUser: pinFromUser
        )
    }

    private func registerForRegRecoveryPwPath(
        regRecoveryPw: String,
        e164: E164,
        pinFromUser: String,
        retriesLeft: Int = Constants.networkErrorRetries
    ) -> Guarantee<RegistrationStep> {
        return self.makeRegisterOrChangeNumberRequest(
            .recoveryPassword(regRecoveryPw),
            e164: e164,
            responseHandler: { [weak self] accountResponse in
                return self?.handleCreateAccountResponseFromRegRecoveryPassword(
                    accountResponse,
                    regRecoveryPw: regRecoveryPw,
                    e164: e164,
                    pinFromUser: pinFromUser,
                    retriesLeft: retriesLeft
                ) ?? unretainedSelfError()
            }
        )
    }

    private func handleCreateAccountResponseFromRegRecoveryPassword(
        _ response: AccountResponse,
        regRecoveryPw: String,
        e164: E164,
        pinFromUser: String,
        retriesLeft: Int
    ) -> Guarantee<RegistrationStep> {
        // TODO[Registration] handle error case for rejected e164.
        switch response {
        case .success(let identityResponse):
            // We have succeeded! Set the account identity response
            // so nextStep() will take us to the profile setup path.
            db.write { tx in
                updatePersistedState(tx) {
                    $0.accountIdentity = identityResponse
                }
            }
            return nextStep()

        case .reglockFailure(let reglockFailure):
            // Both the reglock and the reg recovery password are derived from the KBS master key.
            // Its weird that we'd get this response implying the recovery password is right
            // but the reglock token is wrong, but lets assume our kbs master secret is just
            // wrong entirely and reset _all_ KBS state so we go through sms verification.
            db.write { tx in
                // Store it and wipe it so we also overwrite any existing credential for the same user.
                // We want to wipe the credential on disk too; we don't want to retry it on next app launch.
                deps.kbsAuthCredentialStore.storeAuthCredentialForCurrentUsername(reglockFailure.kbsAuthCredential, tx)
                deps.kbsAuthCredentialStore.deleteInvalidCredentials([reglockFailure.kbsAuthCredential], tx)
                // Clear the KBS master key locally; we failed reglock so we know its wrong
                // and useless anyway.
                deps.kbs.clearKeys(transaction: tx)
            }
            wipeInMemoryStateToPreventKBSPathAttempts()

            // Start a session so we go down that path to recovery, challenging
            // the reglock we just failed so we can eventually get in.
            return startSession(e164: e164)

        case .rejectedVerificationMethod:
            // The reg recovery password was wrong. This can happen for two reasons:
            // 1) We have the wrong KBS master key
            // 2) We have been reglock challenged, forcing us to re-register via session
            // If it were just the former case, we'd wipe our known-wrong KBS master key.
            // But the latter case means we want to go through session path registration,
            // and re-upload our local KBS master secret, so we don't want to wipe it.
            // (If we wiped it and our KBS server guesses were consumed by the reglock-challenger,
            // we'd be outta luck and have no way to recover).
            db.write { tx in
                // We do want to clear out any credentials permanently; we know we
                // have to use the session path so credentials aren't helpful.
                deps.kbsAuthCredentialStore.deleteInvalidCredentials([inMemoryState.kbsAuthCredential].compacted(), tx)
            }
            // Wipe our in memory KBS state; its now useless.
            wipeInMemoryStateToPreventKBSPathAttempts()

            // Now we have to start a session; its the only way to recover.
            return self.startSession(e164: e164)

        case .retryAfter(let timeInterval):
            if timeInterval < Constants.autoRetryInterval {
                return Guarantee
                    .after(on: self.schedulers.sharedBackground, seconds: timeInterval)
                    .then(on: self.schedulers.sync) { [weak self] in
                        guard let self else {
                            return unretainedSelfError()
                        }
                        return self.registerForRegRecoveryPwPath(
                            regRecoveryPw: regRecoveryPw,
                            e164: e164,
                            pinFromUser: pinFromUser
                        )
                    }
            }
            return .value(.showErrorSheet(.todo))

        case .deviceTransferPossible:
            // Device transfer can happen, let the user pick.
            inMemoryState.needsToAskForDeviceTransfer = true
            return nextStep()

        case .networkError:
            if retriesLeft > 0 {
                return registerForRegRecoveryPwPath(
                    regRecoveryPw: regRecoveryPw,
                    e164: e164,
                    pinFromUser: pinFromUser,
                    retriesLeft: retriesLeft - 1
                )
            }
            return .value(.showErrorSheet(.networkError))

        case .genericError:
            return .value(.showErrorSheet(.genericError))
        }
    }

    private func loadkbsAuthCredentialCandidates(_ tx: DBReadTransaction) {
        let kbsAuthCredentialCandidates = deps.kbsAuthCredentialStore.getAuthCredentials(tx)
        if kbsAuthCredentialCandidates.isEmpty.negated {
            inMemoryState.kbsAuthCredentialCandidates = kbsAuthCredentialCandidates
        }
    }

    private func wipeInMemoryStateToPreventKBSPathAttempts() {
        inMemoryState.reglockToken = nil
        inMemoryState.regRecoveryPw = nil
        inMemoryState.shouldRestoreKBSMasterKeyAfterRegistration = true
        // Wiping auth credential state too; if we failed with the local
        // kbs master key we don't expect the backed up master key to work
        // either so we shouldn't bother trying.
        inMemoryState.kbsAuthCredential = nil
        inMemoryState.kbsAuthCredentialCandidates = nil
    }

    // MARK: - KBS Auth Credential Pathway

    /// If we don't have the KBS master key saved locally but we do have a KBS auth credential,
    /// we can use it to talk to the KBS server and, together with the user-entered PIN, recover the
    /// full KBS master key. Then we use the Registration Recovery Password registration flow.
    /// (If we had the KBS master key saved locally to begin with, we would have just used it right away.)
    private func nextStepForKBSAuthCredentialPath(
        kbsAuthCredential: KBSAuthCredential
    ) -> Guarantee<RegistrationStep> {
        guard let pin = inMemoryState.pinFromUser else {
            // We don't have a pin at all, ask the user for it.
            return .value(.pinEntry(RegistrationPinState(
                operation: .enteringExistingPin(canSkip: true, remainingAttempts: nil),
                error: nil,
                exitConfiguration: pinCodeEntryExitConfiguration()
            )))
        }

        return restoreKBSMasterSecretForAuthCredentialPath(
            pin: pin,
            credential: kbsAuthCredential
        )
    }

    private func restoreKBSMasterSecretForAuthCredentialPath(
        pin: String,
        credential: KBSAuthCredential,
        retriesLeft: Int = Constants.networkErrorRetries
    ) -> Guarantee<RegistrationStep> {
        deps.kbs.restoreKeysAndBackup(pin: pin, authMethod: .kbsAuth(credential, backup: nil))
            .then(on: schedulers.main) { [weak self] result -> Guarantee<RegistrationStep> in
                guard let self = self else {
                    return unretainedSelfError()
                }
                switch result {
                case .success:
                    // This step also backs up, no need to do that again later.
                    self.inMemoryState.hasBackedUpToKBS = true
                    self.db.write { self.loadLocalMasterKey($0) }
                    return self.nextStep()
                case let .invalidPin(remainingAttempts):
                    return .value(.pinEntry(RegistrationPinState(
                        operation: .enteringExistingPin(
                            canSkip: true,
                            remainingAttempts: UInt(remainingAttempts)
                        ),
                        error: .wrongPin(wrongPin: pin),
                        exitConfiguration: self.pinCodeEntryExitConfiguration()
                    )))
                case .backupMissing:
                    // If we are unable to talk to KBS, it got wiped and we can't
                    // recover. Give it all up and wipe our KBS info.
                    self.wipeInMemoryStateToPreventKBSPathAttempts()
                    // "Skip" PIN entry, we can't use it anymore.
                    self.db.write { tx in
                        self.updatePersistedState(tx) {
                            $0.hasSkippedPinEntry = true
                        }
                    }
                    return .value(.showErrorSheet(.pinGuessesExhausted))
                case .networkError:
                    if retriesLeft > 0 {
                        return self.restoreKBSMasterSecretForAuthCredentialPath(
                            pin: pin,
                            credential: credential,
                            retriesLeft: retriesLeft - 1
                        )
                    }
                    return .value(.showErrorSheet(.networkError))
                case .genericError:
                    return .value(.showErrorSheet(.genericError))
                }
            }
    }

    private func loadLocalMasterKey(_ tx: DBWriteTransaction) {
        // The hex vs base64 different here is intentional.
        let regRecoveryPw = deps.kbs.data(for: .registrationRecoveryPassword, transaction: tx)?.base64EncodedString()
        inMemoryState.regRecoveryPw = regRecoveryPw
        if regRecoveryPw != nil {
            updatePersistedState(tx) { $0.shouldSkipRegistrationSplash = true }
        }
        inMemoryState.reglockToken = deps.kbs.data(for: .registrationLock, transaction: tx)?.hexadecimalString
        // If we have a local master key, theres no need to restore after registration.
        // (we will still back up though)
        inMemoryState.shouldRestoreKBSMasterKeyAfterRegistration = !deps.kbs.hasMasterKey(transaction: tx)
        inMemoryState.didHaveKbsBackupsPriorToReg = deps.kbs.hasBackedUpMasterKey(transaction: tx)
    }

    // MARK: - KBS Auth Credential Candidates Pathway

    private func nextStepForKBSAuthCredentialCandidatesPath(
        kbsAuthCredentialCandidates: [KBSAuthCredential]
    ) -> Guarantee<RegistrationStep> {
        guard let e164 = persistedState.e164 else {
            // If we haven't entered a phone number but we have auth
            // credential candidates to check, enter it now.
            return .value(.phoneNumberEntry(phoneNumberEntryState()))
        }
        // Check the candidates.
        return makeKBSAuthCredentialCheckRequest(
            kbsAuthCredentialCandidates: kbsAuthCredentialCandidates,
            e164: e164
        )
    }

    private func makeKBSAuthCredentialCheckRequest(
        kbsAuthCredentialCandidates: [KBSAuthCredential],
        e164: E164,
        retriesLeft: Int = Constants.networkErrorRetries
    ) -> Guarantee<RegistrationStep> {
        return Service.makeKBSAuthCheckRequest(
            e164: e164,
            candidateCredentials: kbsAuthCredentialCandidates,
            signalService: deps.signalService,
            schedulers: schedulers
        ).then(on: schedulers.main) { [weak self] response in
            guard let self else {
                return unretainedSelfError()
            }
            return self.handleKBSAuthCredentialCheckResponse(
                response,
                kbsAuthCredentialCandidates: kbsAuthCredentialCandidates,
                e164: e164,
                retriesLeft: retriesLeft
            )
        }
    }

    private func handleKBSAuthCredentialCheckResponse(
        _ response: Service.KBSAuthCheckResponse,
        kbsAuthCredentialCandidates: [KBSAuthCredential],
        e164: E164,
        retriesLeft: Int
    ) -> Guarantee<RegistrationStep> {
        var matchedCredential: KBSAuthCredential?
        var credentialsToDelete = [KBSAuthCredential]()
        switch response {
        case .networkError:
            if retriesLeft > 0 {
                return makeKBSAuthCredentialCheckRequest(
                    kbsAuthCredentialCandidates: kbsAuthCredentialCandidates,
                    e164: e164,
                    retriesLeft: retriesLeft - 1
                )
            }
            self.inMemoryState.kbsAuthCredentialCandidates = nil
            return self.nextStep()
        case .genericError:
            // If we failed to verify, wipe the candidates so we don't try again
            // and keep going.
            self.inMemoryState.kbsAuthCredentialCandidates = nil
            return self.nextStep()
        case .success(let response):
            for candidate in kbsAuthCredentialCandidates {
                let result: RegistrationServiceResponses.KBSAuthCheckResponse.Result? = response.result(for: candidate)
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
        self.inMemoryState.kbsAuthCredentialCandidates = nil
        // If this is nil, the next time we call `nextStepForKBSAuthCredentialPath`
        // will just return an empty promise.
        self.inMemoryState.kbsAuthCredential = matchedCredential
        self.db.write { tx in
            self.deps.kbsAuthCredentialStore.deleteInvalidCredentials(credentialsToDelete, tx)
        }
        return self.nextStep()
    }

    // MARK: - RegistrationSession Pathway

    private func nextStepForSessionPath(_ session: RegistrationSession) -> Guarantee<RegistrationStep> {
        if session.verified {
            // We have to complete registration.
            return self.makeRegisterOrChangeNumberRequestFromSession(session)
        }

        if inMemoryState.needsToAskForDeviceTransfer {
            return .value(.transferSelection)
        }

        switch persistedState.sessionState?.reglockState ?? .none {
        case .none:
            break
        case let .reglocked(kbsAuthCredential, reglockExpirationDate):
            if let pinFromUser = inMemoryState.pinFromUser {
                return restoreKBSMasterSecretForSessionPathReglock(
                    session: session,
                    pin: pinFromUser,
                    kbsAuthCredential: kbsAuthCredential,
                    reglockExpirationDate: reglockExpirationDate
                )
            } else {
                return .value(.pinEntry(RegistrationPinState(
                    operation: .enteringExistingPin(canSkip: false, remainingAttempts: nil),
                    error: .none,
                    exitConfiguration: pinCodeEntryExitConfiguration()
                )))
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
                return self.nextStep()
            }
            return .value(.reglockTimeout(RegistrationReglockTimeoutState(
                reglockExpirationDate: reglockExpirationDate,
                acknowledgeAction: self.reglockTimeoutAcknowledgeAction
            )))
        }

        if inMemoryState.needsToAskForDeviceTransfer && !persistedState.hasDeclinedTransfer {
            return .value(.transferSelection)
        }

        if session.verified {
            // We have to complete registration.
            return self.makeRegisterOrChangeNumberRequestFromSession(session)
        }

        if let pendingCodeTransport = inMemoryState.pendingCodeTransport {
            guard session.allowedToRequestCode else {
                return attemptToFulfillAvailableChallengesWaitingIfNeeded(for: session)
            }

            // If we have pending transport and can send, send.
            if session.allowedToRequestCode {
                switch pendingCodeTransport {
                case .sms:
                    if let nextSMSDate = session.nextSMSDate, nextSMSDate <= deps.dateProvider() {
                        return requestSessionCode(session: session, transport: pendingCodeTransport)
                    } else if let nextVerificationAttemptDate = session.nextVerificationAttemptDate {
                        return .value(.verificationCodeEntry(self.verificationCodeEntryState(
                            session: session,
                            nextVerificationAttemptDate: nextVerificationAttemptDate,
                            validationError: .smsResendTimeout
                        )))
                    } else if let nextSMSDate = session.nextSMSDate {
                        return .value(.phoneNumberEntry(phoneNumberEntryState(
                            validationError: .rateLimited(.init(expiration: nextSMSDate))
                        )))
                    } else {
                        return .value(.showErrorSheet(.verificationCodeSubmissionUnavailable))
                    }
                case .voice:
                    if let nextCallDate = session.nextCallDate, nextCallDate <= deps.dateProvider() {
                        return requestSessionCode(session: session, transport: pendingCodeTransport)
                    } else if let nextVerificationAttemptDate = session.nextVerificationAttemptDate {
                        return .value(.verificationCodeEntry(self.verificationCodeEntryState(
                            session: session,
                            nextVerificationAttemptDate: nextVerificationAttemptDate,
                            validationError: .voiceResendTimeout
                        )))
                    } else if let nextSMSDate = session.nextSMSDate {
                        return .value(.phoneNumberEntry(phoneNumberEntryState(
                            validationError: .rateLimited(.init(expiration: nextSMSDate))
                        )))
                    } else {
                        return .value(.showErrorSheet(.verificationCodeSubmissionUnavailable))
                    }
                }
            }
        }

        if let nextVerificationAttemptDate = session.nextVerificationAttemptDate {
            return .value(.verificationCodeEntry(self.verificationCodeEntryState(
                session: session,
                nextVerificationAttemptDate: nextVerificationAttemptDate
            )))
        }

        // Otherwise we have no code awaiting submission and aren't
        // trying to send one yet, so just go to phone number entry.
        return .value(.phoneNumberEntry(phoneNumberEntryState()))
    }

    private func processSession(_ session: RegistrationSession?, _ transaction: DBWriteTransaction) {
        if session == nil || persistedState.sessionState?.sessionId != session?.id {
            self.updatePersistedState(transaction) {
                $0.sessionState = session.map { .init(sessionId: $0.id) }
            }
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

    private func makeRegisterOrChangeNumberRequestFromSession(
        _ session: RegistrationSession,
        retriesLeft: Int = Constants.networkErrorRetries
    ) -> Guarantee<RegistrationStep> {
        return self.makeRegisterOrChangeNumberRequest(
            .sessionId(session.id),
            e164: session.e164,
            responseHandler: { [weak self] accountResponse in
                return self?.handleCreateAccountResponseFromSession(
                    accountResponse,
                    sessionFromBeforeRequest: session,
                    retriesLeft: retriesLeft
                ) ?? unretainedSelfError()
            }
        )
    }

    private func handleCreateAccountResponseFromSession(
        _ response: AccountResponse,
        sessionFromBeforeRequest: RegistrationSession,
        retriesLeft: Int
    ) -> Guarantee<RegistrationStep> {
        switch response {
        case .success(let identityResponse):
            inMemoryState.session = nil
            db.write { tx in
                // We can clear the session now!
                deps.sessionManager.clearPersistedSession(tx)
                updatePersistedState(tx) {
                    $0.accountIdentity = identityResponse
                    $0.sessionState = nil
                }
            }
            // Should take us to the profile setup flow since
            // the identity response is set.
            return nextStep()
        case .reglockFailure(let reglockFailure):
            // We need the user to enter their PIN so we can get through reglock.
            // So we set up the state we need (the KBS credential)
            // and go to the next step which should look at the state and take us to the right place.
            db.write { tx in
                deps.kbsAuthCredentialStore.storeAuthCredentialForCurrentUsername(reglockFailure.kbsAuthCredential, tx)
                let reglockExpirationDate = self.deps.dateProvider().addingTimeInterval(TimeInterval(reglockFailure.timeRemainingMs / 1000))
                self.updatePersistedSessionState(session: sessionFromBeforeRequest, tx) {
                    $0.reglockState = .reglocked(credential: reglockFailure.kbsAuthCredential, expirationDate: reglockExpirationDate)
                }
            }
            return nextStep()

        case .rejectedVerificationMethod:
            // The session is invalid; we have to wipe it and potentially start again.
            db.write { self.resetSession($0) }
            return nextStep()

        case .retryAfter(let timeInterval):
            if timeInterval < Constants.autoRetryInterval {
                return Guarantee
                    .after(on: schedulers.sharedBackground, seconds: timeInterval)
                    .then(on: schedulers.sync) { [weak self] in
                        guard let self else {
                            return unretainedSelfError()
                        }
                        return self.makeRegisterOrChangeNumberRequestFromSession(
                            sessionFromBeforeRequest
                        )
                    }
            }
            // TODO[Registration] bubble up the error to the ui properly.
            return .value(.showErrorSheet(.todo))
        case .deviceTransferPossible:
            inMemoryState.needsToAskForDeviceTransfer = true
            return .value(.transferSelection)
        case .networkError:
            if retriesLeft > 0 {
                return makeRegisterOrChangeNumberRequestFromSession(
                    sessionFromBeforeRequest,
                    retriesLeft: retriesLeft - 1
                )
            }
            return .value(.showErrorSheet(.networkError))
        case .genericError:
            return .value(.showErrorSheet(.genericError))
        }
    }

    private func startSession(
        e164: E164,
        retriesLeft: Int = Constants.networkErrorRetries
    ) -> Guarantee<RegistrationStep> {
        return deps.pushRegistrationManager.requestPushToken()
            .then(on: schedulers.sharedBackground) { [weak self] apnsToken -> Guarantee<RegistrationStep> in
                guard let strongSelf = self else {
                    return unretainedSelfError()
                }
                return strongSelf.deps.sessionManager.beginOrRestoreSession(
                    e164: e164,
                    apnsToken: apnsToken
                ).then(on: strongSelf.schedulers.main) { [weak self] response -> Guarantee<RegistrationStep> in
                    guard let strongSelf = self else {
                        return unretainedSelfError()
                    }
                    switch response {
                    case .success(let session):
                        strongSelf.db.write { transaction in
                            strongSelf.processSession(session, transaction)

                            if apnsToken == nil {
                                strongSelf.noPreAuthChallengeTokenWillArrive(
                                    session: session,
                                    transaction: transaction
                                )
                            } else {
                                strongSelf.prepareToReceivePreAuthChallengeToken(
                                    session: session,
                                    transaction: transaction
                                )
                            }
                        }

                        // When we get a new session, an SMS code is sent immediately.
                        strongSelf.inMemoryState.pendingCodeTransport = .sms

                        return strongSelf.nextStep()
                    case .invalidArgument:
                        return .value(.phoneNumberEntry(strongSelf.phoneNumberEntryState(
                            validationError: .invalidNumber(.init(invalidE164: e164))
                        )))
                    case .retryAfter(let timeInterval):
                        if timeInterval < Constants.autoRetryInterval {
                            return Guarantee
                                .after(on: strongSelf.schedulers.sharedBackground, seconds: timeInterval)
                                .then(on: strongSelf.schedulers.sync) { [weak self] in
                                    guard let self else {
                                        return unretainedSelfError()
                                    }
                                    return self.startSession(
                                        e164: e164
                                    )
                                }
                        }
                        return .value(.phoneNumberEntry(strongSelf.phoneNumberEntryState(
                            validationError: .rateLimited(.init(
                                expiration: strongSelf.deps.dateProvider().addingTimeInterval(timeInterval))
                            )
                        )))
                    case .networkFailure:
                        if retriesLeft > 0 {
                            return strongSelf.startSession(
                                e164: e164,
                                retriesLeft: retriesLeft - 1
                            )
                        }
                        return .value(.showErrorSheet(.networkError))
                    case .genericError:
                        return .value(.showErrorSheet(.genericError))
                    }
                }
            }
    }

    private func requestSessionCode(
        session: RegistrationSession,
        transport: Registration.CodeTransport,
        retriesLeft: Int = Constants.networkErrorRetries
    ) -> Guarantee<RegistrationStep> {
        return deps.sessionManager.requestVerificationCode(
            for: session,
            transport: transport
        ).then(on: schedulers.main) { [weak self] (result: Registration.UpdateSessionResponse) -> Guarantee<RegistrationStep> in
            guard let self else {
                return unretainedSelfError()
            }
            switch result {
            case .success(let session):
                self.inMemoryState.pendingCodeTransport = nil
                self.db.write { self.processSession(session, $0) }
                return self.nextStep()
            case .rejectedArgument(let session):
                Logger.error("Should never get rejected argument error from requesting code. E164 already set on session.")
                // Wipe the pending code request, so we don't retry.
                self.inMemoryState.pendingCodeTransport = nil
                self.db.write { self.processSession(session, $0) }
                return self.nextStep()
            case .disallowed(let session):
                // Whatever caused this should be represented on the session itself,
                // and once we unblock we should retry sending so don't clear the pending
                // code transport.
                self.db.write { self.processSession(session, $0) }
                return self.nextStep()
            case .invalidSession:
                self.inMemoryState.pendingCodeTransport = nil
                self.db.write { self.resetSession($0) }
                return .value(.showErrorSheet(.sessionInvalidated))
            case .serverFailure(let failureResponse):
                self.inMemoryState.pendingCodeTransport = nil
                if failureResponse.isPermanent {
                    self.db.write { self.resetSession($0) }
                }
                return .value(.showErrorSheet(.genericError))
            case .retryAfterTimeout(let session):
                self.db.write { self.processSession(session, $0) }

                let timeInterval: TimeInterval?
                switch transport {
                case .sms:
                    timeInterval = session.nextSMS
                case .voice:
                    timeInterval = session.nextCall
                }
                if let timeInterval, timeInterval < Constants.autoRetryInterval {
                    return Guarantee
                        .after(on: self.schedulers.sharedBackground, seconds: timeInterval)
                        .then(on: self.schedulers.sync) { [weak self] in
                            guard let self else {
                                return unretainedSelfError()
                            }
                            return self.requestSessionCode(
                                session: session,
                                transport: transport
                            )
                        }
                } else {
                    self.inMemoryState.pendingCodeTransport = nil
                    if let nextVerificationAttemptDate = session.nextVerificationAttemptDate {
                        // Show an error on the verification code entry screen.
                        return .value(.verificationCodeEntry(self.verificationCodeEntryState(
                            session: session,
                            nextVerificationAttemptDate: nextVerificationAttemptDate,
                            validationError: {
                                switch transport {
                                case .sms: return .smsResendTimeout
                                case .voice: return .voiceResendTimeout
                                }
                            }()
                        )))
                    } else if let timeInterval {
                        // We were trying to resend from the phone number screen.
                        return .value(.phoneNumberEntry(self.phoneNumberEntryState(
                            validationError: .rateLimited(.init(
                                expiration: self.deps.dateProvider().addingTimeInterval(timeInterval)
                            )
                        ))))
                    } else {
                        // Can't send a code, session is useless.
                        self.db.write { self.resetSession($0) }
                        return .value(.showErrorSheet(.sessionInvalidated))
                    }
                }
            case .networkFailure:
                if retriesLeft > 0 {
                    return self.requestSessionCode(
                        session: session,
                        transport: transport,
                        retriesLeft: retriesLeft - 1
                    )
                }
                return .value(.showErrorSheet(.networkError))
            case .genericError:
                self.inMemoryState.pendingCodeTransport = nil
                return .value(.showErrorSheet(.genericError))
            }
        }
    }

    private func noPreAuthChallengeTokenWillArrive(
        session: RegistrationSession,
        transaction: DBWriteTransaction
    ) {
        switch persistedState.sessionState?.pushChallengeState {
        case nil, .notRequested, .waitingForPush:
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
        case nil, .notRequested, .ineligible:
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
        deps.pushRegistrationManager.receivePreAuthChallengeToken().done(on: schedulers.main) { [weak self] token in
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
        Logger.info("Received a push challenge token")
        updatePersistedSessionState(session: session, transaction) {
            $0.pushChallengeState = .unfulfilledPush(challengeToken: pushChallengeToken)
        }
    }

    private func attemptToFulfillAvailableChallengesWaitingIfNeeded(
        for session: RegistrationSession
    ) -> Guarantee<RegistrationStep> {
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
            case nil, .notRequested, .ineligible, .waitingForPush, .fulfilled:
                return nil
            case let .unfulfilledPush(challengeToken):
                return challengeToken
            }
        }()
        if requestsPushChallenge, let unfulfilledPushChallengeToken {
            Logger.info("Attempting to fulfill push challenge with a token we already have")
            return submit(
                challengeFulfillment: .pushChallenge(unfulfilledPushChallengeToken),
                for: session
            )
        }

        func waitForPushTokenChallenge(
            timeout: TimeInterval,
            failChallengeIfTimedOut: Bool
        ) -> Guarantee<RegistrationStep> {
            Logger.info("Attempting to fulfill push challenge with a token we don't have yet")
            return deps.pushRegistrationManager
                .receivePreAuthChallengeToken()
                .map { $0 }
                .nilTimeout(on: schedulers.sharedBackground, seconds: timeout)
                .then(on: schedulers.sharedBackground) { [weak self] (challengeToken: String?) -> Guarantee<RegistrationStep> in
                    guard let self else {
                        return unretainedSelfError()
                    }

                    if let challengeToken {
                        self.db.write { transaction in
                            self.didReceive(
                                pushChallengeToken: challengeToken,
                                for: session,
                                transaction: transaction
                            )
                        }
                        return self.submit(
                            challengeFulfillment: .pushChallenge(challengeToken),
                            for: session
                        )
                    } else if failChallengeIfTimedOut {
                        Logger.warn("No challenge token received in time. Resetting")
                        self.db.write { self.resetSession($0) }
                        return .value(.showErrorSheet(.sessionInvalidated))
                    } else {
                        Logger.warn("No challenge token received in time, falling back to next challenge")
                        return tryNonImmediatePushChallenge()
                    }
                }
        }

        func tryNonImmediatePushChallenge() -> Guarantee<RegistrationStep> {
            // Our third choice: a captcha challenge
            if requestsCaptchaChallenge {
                Logger.info("Showing the CAPTCHA challenge to the user")
                return .value(.captchaChallenge)
            }

            // Our fourth choice: a push challenge where we're still waiting for the challenge token.
            if
                requestsPushChallenge,
                let timeToWaitUntil = pushChallengeRequestDate?.addingTimeInterval(Constants.pushTokenTimeout),
                deps.dateProvider() < timeToWaitUntil
            {
                let timeout = timeToWaitUntil.timeIntervalSince(deps.dateProvider())
                return waitForPushTokenChallenge(
                    timeout: timeout,
                    failChallengeIfTimedOut: true
                )
            }

            // We're out of luck.
            if session.hasUnknownChallengeRequiringAppUpdate {
                Logger.warn("An unknown challenge was found")
                inMemoryState.pendingCodeTransport = nil
                return .value(.appUpdateBanner)
            } else {
                Logger.warn("Couldn't fulfill any challenges. Resetting the session")
                db.write { resetSession($0) }
                return nextStep()
            }
        }

        // Our second choice: a very recent push challenge.
        let pushChallengeRequestDate: Date? = {
            switch persistedState.sessionState?.pushChallengeState {
            case nil, .notRequested, .ineligible, .unfulfilledPush, .fulfilled:
                return nil
            case let .waitingForPush(requestedAt):
                return requestedAt
            }
        }()
        if
            requestsPushChallenge,
            let timeToWaitUntil = pushChallengeRequestDate?.addingTimeInterval(Constants.pushTokenMinWaitTime),
            deps.dateProvider() < timeToWaitUntil
        {
            let timeout = timeToWaitUntil.timeIntervalSince(deps.dateProvider())
            return waitForPushTokenChallenge(timeout: timeout, failChallengeIfTimedOut: false)
        }

        // Try the next choices.
        return tryNonImmediatePushChallenge()
    }

    private func submit(
        challengeFulfillment fulfillment: Registration.ChallengeFulfillment,
        for session: RegistrationSession,
        retriesLeft: Int = Constants.networkErrorRetries
    ) -> Guarantee<RegistrationStep> {
        return deps.sessionManager.fulfillChallenge(
            for: session,
            fulfillment: fulfillment
        ).then(on: schedulers.main) { [weak self] (result: Registration.UpdateSessionResponse) -> Guarantee<RegistrationStep> in
            guard let self else {
                return unretainedSelfError()
            }
            switch result {
            case .success(let session):
                self.db.write { tx in
                    self.processSession(session, tx)
                    switch fulfillment {
                    case .captcha: break
                    case .pushChallenge:
                        self.updatePersistedSessionState(session: session, tx) {
                            $0.pushChallengeState = .fulfilled
                        }
                    }
                }
                return self.nextStep()
            case .rejectedArgument(let session):
                // TODO[Registration] invalid captcha token; show error
                self.db.write { self.processSession(session, $0) }
                return self.nextStep()
            case .disallowed(let session):
                Logger.warn("Disallowed to complete a challenge which should be impossible.")
                // Don't keep trying to send a code.
                self.inMemoryState.pendingCodeTransport = nil
                self.db.write { self.processSession(session, $0) }
                return .value(.showErrorSheet(.todo))
            case .invalidSession:
                self.db.write { self.resetSession($0) }
                return .value(.showErrorSheet(.sessionInvalidated))
            case .serverFailure(let failureResponse):
                if failureResponse.isPermanent {
                    // TODO[Registration] show something special here.
                    return .value(.showErrorSheet(.todo))
                } else {
                    // TODO[Registration] show some particular error here.
                    return .value(.showErrorSheet(.todo))
                }
            case .retryAfterTimeout(let session):
                Logger.error("Should not have to retry a captcha challenge request")
                // Clear the pending code; we want the user to press again
                // once the timeout expires.
                self.inMemoryState.pendingCodeTransport = nil
                self.db.write { self.processSession(session, $0) }
                return self.nextStep()
            case .networkFailure:
                if retriesLeft > 0 {
                    return self.submit(
                        challengeFulfillment: fulfillment,
                        for: session,
                        retriesLeft: retriesLeft - 1
                    )
                }
                return .value(.showErrorSheet(.networkError))
            case .genericError:
                return .value(.showErrorSheet(.genericError))
            }
        }
    }

    private func submitSessionCode(
        session: RegistrationSession,
        code: String,
        retriesLeft: Int = Constants.networkErrorRetries
    ) -> Guarantee<RegistrationStep> {
        return deps.sessionManager.submitVerificationCode(
            for: session,
            code: code
        ).then(on: schedulers.main) { [weak self] (result: Registration.UpdateSessionResponse) -> Guarantee<RegistrationStep> in
            guard let self else {
                return unretainedSelfError()
            }
            switch result {
            case .success(let session):
                if !session.verified {
                    // The code must have been wrong.
                    fallthrough
                }
                self.db.write { self.processSession(session, $0) }
                return self.nextStep()
            case .rejectedArgument(let session):
                self.db.write { self.processSession(session, $0) }
                if let nextVerificationAttemptDate = session.nextVerificationAttemptDate {
                    return .value(.verificationCodeEntry(self.verificationCodeEntryState(
                        session: session,
                        nextVerificationAttemptDate: nextVerificationAttemptDate,
                        validationError: .invalidVerificationCode(invalidCode: code)
                    )))
                } else {
                    // Something went wrong, we can't submit again.
                    return .value(.showErrorSheet(.verificationCodeSubmissionUnavailable))
                }
            case .disallowed(let session):
                // This state means the session state is updated
                // such that what comes next has changed, e.g. we can't send a verification
                // code and will kick the user back to sending an sms code.
                self.db.write { self.processSession(session, $0) }
                return .value(.showErrorSheet(.verificationCodeSubmissionUnavailable))
            case .invalidSession:
                self.db.write { self.resetSession($0) }
                return .value(.showErrorSheet(.sessionInvalidated))
            case .serverFailure(let failureResponse):
                if failureResponse.isPermanent {
                    // TODO[Registration] show something special here.
                    return .value(.showErrorSheet(.todo))
                } else {
                    // TODO[Registration] show some particular error here.
                    return .value(.showErrorSheet(.todo))
                }
            case .retryAfterTimeout(let session):
                self.db.write { self.processSession(session, $0) }
                if let timeInterval = session.nextVerificationAttempt, timeInterval < Constants.autoRetryInterval {
                    return Guarantee
                        .after(on: self.schedulers.sharedBackground, seconds: timeInterval)
                        .then(on: self.schedulers.sync) { [weak self] in
                            guard let self else {
                                return unretainedSelfError()
                            }
                            return self.submitSessionCode(
                                session: session,
                                code: code
                            )
                        }
                }
                if let nextVerificationAttemptDate = session.nextVerificationAttemptDate {
                    return .value(.verificationCodeEntry(self.verificationCodeEntryState(
                        session: session,
                        nextVerificationAttemptDate: nextVerificationAttemptDate,
                        validationError: .submitCodeTimeout
                    )))
                } else {
                    // Something went wrong, we can't submit again.
                    return .value(.showErrorSheet(.verificationCodeSubmissionUnavailable))
                }
            case .networkFailure:
                if retriesLeft > 0 {
                    return self.submitSessionCode(
                        session: session,
                        code: code,
                        retriesLeft: retriesLeft - 1
                    )
                }
                return .value(.showErrorSheet(.networkError))
            case .genericError:
                return .value(.showErrorSheet(.genericError))
            }
        }
    }

    private func restoreKBSMasterSecretForSessionPathReglock(
        session: RegistrationSession,
        pin: String,
        kbsAuthCredential: KBSAuthCredential,
        reglockExpirationDate: Date,
        retriesLeft: Int = Constants.networkErrorRetries
    ) -> Guarantee<RegistrationStep> {
        return deps.kbs.restoreKeysAndBackup(
            pin: pin,
            authMethod: .kbsAuth(kbsAuthCredential, backup: nil)
        )
            .then(on: schedulers.main) { [weak self] result -> Guarantee<RegistrationStep> in
                guard let self else {
                    return unretainedSelfError()
                }
                switch result {
                case .success:
                    // This step also backs up, no need to do that again later.
                    self.inMemoryState.hasBackedUpToKBS = true
                    self.db.write { tx in
                        self.loadLocalMasterKey(tx)
                        self.updatePersistedSessionState(session: session, tx) {
                            // Now we have the state we need to get past reglock.
                            $0.reglockState = .none
                        }
                    }
                    return self.nextStep()
                case let .invalidPin(remainingAttempts):
                    return .value(.pinEntry(RegistrationPinState(
                        operation: .enteringExistingPin(
                            canSkip: false,
                            remainingAttempts: UInt(remainingAttempts)
                        ),
                        error: .wrongPin(wrongPin: pin),
                        exitConfiguration: self.pinCodeEntryExitConfiguration()
                    )))
                case .backupMissing:
                    // If we are unable to talk to KBS, it got wiped, probably
                    // because we used up our guesses. We can't get past reglock.
                    self.db.write { tx in
                        self.updatePersistedSessionState(session: session, tx) {
                            $0.reglockState = .waitingTimeout(expirationDate: reglockExpirationDate)
                        }
                    }
                    return .value(.showErrorSheet(.pinGuessesExhausted))
                case .networkError:
                    if retriesLeft > 0 {
                        return self.restoreKBSMasterSecretForSessionPathReglock(
                            session: session,
                            pin: pin,
                            kbsAuthCredential: kbsAuthCredential,
                            reglockExpirationDate: reglockExpirationDate,
                            retriesLeft: retriesLeft - 1
                        )
                    }
                    return .value(.showErrorSheet(.networkError))
                case .genericError:
                    return .value(.showErrorSheet(.genericError))
                }
            }
    }

    // MARK: - Profile Setup Pathway

    /// Returns the next step the user needs to go through _after_ the actual account
    /// registration or change number is complete (e.g. profile setup).
    private func nextStepForProfileSetup(
        _ accountIdentity: AccountIdentity
    ) -> Guarantee<RegistrationStep> {
        switch mode {
        case .registering, .reRegistering:
            break
        case .changingNumber:
            // Change number is different; we do a limited number of operations and then finalize.
            if !persistedState.didSyncPushTokens {
                return syncPushTokens(accountIdentity)
            }

            if let stepGuarantee = performKBSBackupStepsIfNeeded(accountIdentity: accountIdentity) {
                return stepGuarantee
            }

            return exportAndWipeState(accountIdentity: accountIdentity)
        }

        if !inMemoryState.hasSetUpContactsManager {
            // This sets up the contact provider as the primary device one (system contacts).
            // Without this, subsequent operations will fail as no contact provider is set
            // and tsAccountManager isn't set up yet.
            deps.contactsManager.setIsPrimaryDevice()
            inMemoryState.hasSetUpContactsManager = true
        }

        // We _must_ do these steps first. The created account starts out
        // disabled and other endpoints won't work until we:
        // 1. sync push tokens OR set isManualMessageFetchEnabled=true and sync account attributes
        // 2. create prekeys and register them with the server
        // then we can do other stuff (fetch kbs backups, set profile info, etc)
        if !persistedState.didSyncPushTokens {
            return syncPushTokens(accountIdentity)
        }

        if shouldSyncPreKeys() {
            return deps.preKeyManager
                .createPreKeys(auth: accountIdentity.chatServiceAuth)
                .then(on: schedulers.main) { [weak self] () -> Guarantee<RegistrationStep> in
                    guard let self else {
                        return unretainedSelfError()
                    }
                    self.db.write { tx in
                        self.updatePersistedState(tx) {
                            $0.didSyncPrekeys = true
                        }
                    }
                    return self.nextStep()
                }
                .recover(on: schedulers.main) { _ -> Guarantee<RegistrationStep> in
                    // TODO[Registration]: things just fail here? What do we do?
                    return .value(.showErrorSheet(.todo))
                }
        }

        if let stepGuarantee = performKBSBackupStepsIfNeeded(accountIdentity: accountIdentity) {
            return stepGuarantee
        }

        if shouldRestoreFromStorageService() {
            return deps.accountManager.performInitialStorageServiceRestore(authedAccount: accountIdentity.authedAccount)
                .map(on: schedulers.main) { [weak self] in
                    self?.inMemoryState.hasRestoredFromStorageService = true
                    return ()
                }
                .recover(on: schedulers.main) { [weak self] _ in
                    self?.inMemoryState.hasSkippedRestoreFromStorageService = true
                    return .value(())
                }
                .then(on: schedulers.sync) { [weak self] in
                    guard let self else {
                        return unretainedSelfError()
                    }
                    self.loadProfileState()
                    return self.nextStep()
                }
        }

        if !inMemoryState.hasProfileName {
            if let profileInfo = inMemoryState.pendingProfileInfo {
                return deps.profileManager.updateLocalProfile(
                    givenName: profileInfo.givenName,
                    familyName: profileInfo.familyName,
                    avatarData: profileInfo.avatarData,
                    authedAccount: accountIdentity.authedAccount
                )
                    .map(on: schedulers.sync) { return nil }
                    .recover(on: schedulers.sync) { (error) -> Guarantee<Error?> in
                        return .value(error)
                    }
                    .then(on: schedulers.main) { [weak self] (error) -> Guarantee<RegistrationStep> in
                        guard let self else {
                            return unretainedSelfError()
                        }
                        guard error == nil else {
                            // TODO[Registration]: should we differentiate errors?
                            return .value(.showErrorSheet(.todo))
                        }
                        self.inMemoryState.hasProfileName = true
                        self.inMemoryState.pendingProfileInfo = nil
                        return self.nextStep()
                    }
            }

            return .value(.setupProfile(RegistrationProfileState(
                e164: accountIdentity.e164,
                isDiscoverableByPhoneNumber: inMemoryState.isDiscoverableByPhoneNumber
            )))
        }

        if !inMemoryState.hasDefinedIsDiscoverableByPhoneNumber, FeatureFlags.phoneNumberDiscoverability {
            return .value(.phoneNumberDiscoverability(RegistrationPhoneNumberDiscoverabilityState(
                e164: accountIdentity.e164,
                isDiscoverableByPhoneNumber: inMemoryState.isDiscoverableByPhoneNumber
            )))
        }

        // We are ready to finish! Export all state and wipe things
        // so we can re-register later if desired.
        return exportAndWipeState(accountIdentity: accountIdentity)
    }

    private func syncPushTokens(
        _ accountIdentity: AccountIdentity,
        retriesLeft: Int = Constants.networkErrorRetries
    ) -> Guarantee<RegistrationStep> {
        return deps.pushRegistrationManager
            .syncPushTokensForcingUpload(
                auth: accountIdentity.authedAccount.chatServiceAuth
            )
            .then(on: schedulers.main) { [weak self] result in
                guard let strongSelf = self else {
                    return unretainedSelfError()
                }
                switch result {
                case .success:
                    strongSelf.db.write { tx in
                        strongSelf.updatePersistedState(tx) {
                            $0.didSyncPushTokens = true
                        }
                    }
                    return strongSelf.nextStep()
                case .pushUnsupported(let description):
                    // This can happen with:
                    // - simulators, none of which support receiving push notifications
                    // - on iOS11 devices which have disabled "Allow Notifications" and disabled "Enable Background Refresh" in the system settings.
                    // In these cases, mark the sync as done, but enable manual message fetch and sync that state to the server.
                    // If we don't, the account will be in a "disabled" state and future requests won't work.
                     Logger.info("Recovered push registration error. Registering for manual message fetcher because push not supported: \(description)")
                    strongSelf.inMemoryState.isManualMessageFetchEnabled = true
                    return strongSelf.updateAccountAttributes(accountIdentity)
                        .then(on: strongSelf.schedulers.main) { [weak self] maybeError -> Guarantee<RegistrationStep> in
                            guard let strongSelf = self else {
                                return unretainedSelfError()
                            }
                            guard maybeError == nil else {
                                Logger.error("Unable to update account attributes for manual message fetch with error: \(String(describing: maybeError))")
                                return .value(.showErrorSheet(.todo))
                            }
                            strongSelf.db.write { tx in
                                strongSelf.deps.tsAccountManager.setIsManualMessageFetchEnabled(true, tx)
                                strongSelf.updatePersistedState(tx) {
                                    // Say that we synced push tokens so that we skip this step hereafter.
                                    $0.didSyncPushTokens = true
                                }
                            }
                            return strongSelf.nextStep()
                        }
                case .networkError:
                    if retriesLeft > 0 {
                        return strongSelf.syncPushTokens(
                            accountIdentity,
                            retriesLeft: retriesLeft - 1
                        )
                    }
                    return .value(.showErrorSheet(.networkError))
                case .genericError:
                    return .value(.showErrorSheet(.genericError))
                }
            }
    }

    // returns nil if no steps needed.
    private func performKBSBackupStepsIfNeeded(accountIdentity: AccountIdentity) -> Guarantee<RegistrationStep>? {
        let isRestoringPinBackup = accountIdentity.hasPreviouslyUsedKBS

        if !persistedState.hasSkippedPinEntry {
            guard let pin = inMemoryState.pinFromUser ?? inMemoryState.pinFromDisk else {
                if isRestoringPinBackup {
                    return .value(.pinEntry(RegistrationPinState(
                        operation: .enteringExistingPin(canSkip: true, remainingAttempts: nil),
                        error: nil,
                        exitConfiguration: pinCodeEntryExitConfiguration()
                    )))
                } else if let blob = inMemoryState.unconfirmedPinBlob {
                    return .value(.pinEntry(RegistrationPinState(
                        operation: .confirmingNewPin(blob),
                        error: nil,
                        exitConfiguration: pinCodeEntryExitConfiguration()
                    )))
                } else {
                    return .value(.pinEntry(RegistrationPinState(
                        operation: .creatingNewPin,
                        error: nil,
                        exitConfiguration: pinCodeEntryExitConfiguration()
                    )))
                }
            }
            if inMemoryState.shouldBackUpToKBS {
                // If we have no kbs data, fetch it.
                if isRestoringPinBackup, inMemoryState.shouldRestoreKBSMasterKeyAfterRegistration {
                    return restoreKBSBackupPostRegistration(pin: pin, accountIdentity: accountIdentity)
                } else {
                    // If we haven't backed up, do so now.
                    return backupToKBS(pin: pin, accountIdentity: accountIdentity)
                }
            }

            if inMemoryState.wasReglockEnabled && inMemoryState.hasSetReglock.negated {
                return enableReglockIfNeeded()
            }
        }
        return nil
    }

    private func restoreKBSBackupPostRegistration(
        pin: String,
        accountIdentity: AccountIdentity,
        retriesLeft: Int = Constants.networkErrorRetries
    ) -> Guarantee<RegistrationStep> {
        let backupAuthMethod = KBS.AuthMethod.chatServerAuth(accountIdentity.authedAccount)
        let authMethod: KBS.AuthMethod
        if let kbsAuthCredential = inMemoryState.kbsAuthCredential {
            authMethod = .kbsAuth(kbsAuthCredential, backup: backupAuthMethod)
        } else {
            authMethod = backupAuthMethod
        }
        return deps.kbs
            .restoreKeysAndBackup(
                pin: pin,
                authMethod: authMethod
            )
            .then(on: schedulers.main) { [weak self] result -> Guarantee<RegistrationStep> in
                guard let self else {
                    return unretainedSelfError()
                }
                switch result {
                case .success:
                    self.inMemoryState.shouldRestoreKBSMasterKeyAfterRegistration = false
                    // This backs up too, no need to do that again after.
                    self.inMemoryState.hasBackedUpToKBS = true
                    return self.nextStep()
                case let .invalidPin(remainingAttempts):
                    return .value(.pinEntry(RegistrationPinState(
                        operation: .enteringExistingPin(
                            canSkip: true,
                            remainingAttempts: UInt(remainingAttempts)
                        ),
                        error: .wrongPin(wrongPin: pin),
                        exitConfiguration: self.pinCodeEntryExitConfiguration()
                    )))
                case .backupMissing:
                    // If we are unable to talk to KBS, it got wiped and we can't
                    // recover. Keep going like if nothing happened.
                    self.inMemoryState.shouldRestoreKBSMasterKeyAfterRegistration = false
                    return .value(.showErrorSheet(.pinGuessesExhausted))
                case .networkError:
                    if retriesLeft > 0 {
                        return self.restoreKBSBackupPostRegistration(
                            pin: pin,
                            accountIdentity: accountIdentity,
                            retriesLeft: retriesLeft - 1
                        )
                    }
                    return .value(.showErrorSheet(.networkError))
                case .genericError:
                    return .value(.showErrorSheet(.genericError))
                }
            }
    }

    private func backupToKBS(
        pin: String,
        accountIdentity: AccountIdentity,
        retriesLeft: Int = Constants.networkErrorRetries
    ) -> Guarantee<RegistrationStep> {
        let authMethod: KBS.AuthMethod
        let backupAuthMethod = KBS.AuthMethod.chatServerAuth(accountIdentity.authedAccount)
        if let kbsAuthCredential = inMemoryState.kbsAuthCredential {
            authMethod = .kbsAuth(kbsAuthCredential, backup: backupAuthMethod)
        } else {
            authMethod = backupAuthMethod
        }
        return deps.kbs
            .generateAndBackupKeys(
                pin: pin,
                authMethod: authMethod,
                rotateMasterKey: false
            )
            .then(on: schedulers.main) { [weak self] () -> Guarantee<RegistrationStep>  in
                guard let strongSelf = self else {
                    return unretainedSelfError()
                }
                strongSelf.inMemoryState.hasBackedUpToKBS = true
                strongSelf.db.write { tx in
                    strongSelf.deps.ows2FAManager.markPinEnabled(pin, tx)
                }
                return strongSelf.deps.accountManager.performInitialStorageServiceRestore(authedAccount: accountIdentity.authedAccount)
                    .map(on: strongSelf.schedulers.main) { [weak self] in
                        self?.inMemoryState.hasRestoredFromStorageService = true
                    }
                    // Ignore errors. This matches the legacy registration flow.
                    .recover(on: strongSelf.schedulers.sync) { _ in return .value(()) }
                    .then(on: strongSelf.schedulers.sync) { [weak self] in
                        return self?.nextStep() ?? unretainedSelfError()
                    }
            }
            .recover(on: schedulers.main) { [weak self] error -> Guarantee<RegistrationStep> in
                guard let self else {
                    return unretainedSelfError()
                }
                if error.isNetworkConnectivityFailure {
                    if retriesLeft > 0 {
                        return self.backupToKBS(
                            pin: pin,
                            accountIdentity: accountIdentity,
                            retriesLeft: retriesLeft - 1
                        )
                    }
                    return .value(.showErrorSheet(.networkError))
                }
                Logger.error("Failed to back up to KBS with error: \(error)")
                // We want to let people get through registration even if backups
                // go wrong. Show an error but let the user continue when they try the next step.
                self.inMemoryState.didSkipKBSBackup = true
                return .value(.showErrorSheet(.todo))
            }
    }

    private func enableReglockIfNeeded() -> Guarantee<RegistrationStep> {
        guard inMemoryState.wasReglockEnabled, inMemoryState.hasSetReglock.negated else {
            // Don't auto-enable reglock unless it was enabled to begin with.
            return nextStep()
        }
        let reglockToken: String?
        if let token = inMemoryState.reglockToken {
            reglockToken = token
        } else {
            // Try loading from KBS.
            db.write { tx in
                loadLocalMasterKey(tx)
            }
            reglockToken = inMemoryState.reglockToken
        }
        guard let reglockToken else {
            owsFailDebug("Unable to generate reglock token when we have a master key.")
            // Let the user keep going, they still have their old reglock.
            inMemoryState.hasSetReglock = true
            return nextStep()
        }
        return Service.makeEnableReglockRequest(
            reglockToken: reglockToken,
            signalService: deps.signalService,
            schedulers: schedulers
        ).recover(on: schedulers.sync) { _ -> Guarantee<Void> in
            // This isn't immediately catastrophic; this user already had reglock
            // enabled, so while it may now be out of date, its still there and
            // preventing others from getting in. We defer updating this until
            // later (when we update account attributes).
            // This matches legacy registration behavior.
            Logger.error("Unable to set reglock, so old reglock password will remain enforced.")
            return .value(())
        }.then(on: schedulers.main) { [weak self] () -> Guarantee<RegistrationStep> in
            guard let self else {
                return unretainedSelfError()
            }
            self.inMemoryState.hasSetReglock = true
            self.inMemoryState.wasReglockEnabled = true
            self.db.write { tx in
                self.deps.ows2FAManager.markRegistrationLockEnabled(tx)
            }
            return self.nextStep()
        }
    }

    private func loadProfileState() {
        let profileKey = deps.profileManager.localProfileKey
        inMemoryState.profileKey = profileKey
        let udAccessKey: SMKUDAccessKey
        do {
            udAccessKey = try SMKUDAccessKey(profileKey: profileKey.keyData)
            if udAccessKey.keyData.count < 1 {
                owsFail("Could not determine UD access key, empty key generated.")
            }
        } catch {
            // Crash app if UD cannot be enabled.
            owsFail("Could not determine UD access key: \(error).")
        }
        inMemoryState.udAccessKey = udAccessKey
        inMemoryState.hasProfileName = deps.profileManager.hasProfileName
        db.read { tx in
            inMemoryState.hasDefinedIsDiscoverableByPhoneNumber = deps.tsAccountManager.hasDefinedIsDiscoverableByPhoneNumber(tx)
            inMemoryState.isDiscoverableByPhoneNumber = deps.tsAccountManager.isDiscoverableByPhoneNumber(tx)
        }
    }

    private func updateAccountAttributes(_ accountIdentity: AccountIdentity) -> Guarantee<Error?> {
        return Service
            .makeUpdateAccountAttributesRequest(
                makeAccountAttributes(),
                auth: accountIdentity.chatServiceAuth,
                signalService: deps.signalService,
                schedulers: schedulers
            )
    }

    private func updatePhoneNumberDiscoverability(accountIdentity: AccountIdentity, isDiscoverable: Bool) {
        self.inMemoryState.hasDefinedIsDiscoverableByPhoneNumber = true
        self.inMemoryState.isDiscoverableByPhoneNumber = isDiscoverable

        db.write { tx in
            // We will update storage service at the end of registration.
            deps.tsAccountManager.setIsDiscoverableByPhoneNumber(
                true,
                updateStorageService: false,
                authedAccount: accountIdentity.authedAccount,
                tx
            )
        }
    }

    private enum FinalizeChangeNumberResult {
        case success
        case unretainedSelf
        case genericError
    }

    private func finalizeChangeNumberPniState(
        changeNumberState: Mode.ChangeNumberState,
        pniState: Mode.ChangeNumberState.PendingPniState,
        accountIdentity: AccountIdentity
    ) -> Guarantee<FinalizeChangeNumberResult> {
        // Creating a high strust signal recipient for oneself
        // must happen in a transaction initiated off the main thread.
        return firstly(on: schedulers.sharedBackground) { [weak self] () -> FinalizeChangeNumberResult in
            guard let strongSelf = self else {
                return .unretainedSelf
            }
            do {
                try strongSelf.db.write { tx in
                    strongSelf.deps.changeNumberPniManager.finalizePniIdentity(
                        withPendingState: pniState.asPniState(),
                        transaction: tx
                    )
                    strongSelf._unsafeToModify_mode = .changingNumber(try strongSelf.loader.savePendingChangeNumber(
                        oldState: changeNumberState,
                        pniState: nil,
                        transaction: tx
                    ))

                    Logger.info(
                        """
                        Recording new phone number
                        localAci: \(changeNumberState.localAci.uuidString),
                        localE164: \(changeNumberState.oldE164.stringValue),
                        serviceAci: \(accountIdentity.aci),
                        servicePni: \(accountIdentity.pni),
                        serviceE164: \(accountIdentity.e164.stringValue)")
                        """
                    )

                    // We do these here, and not in export state, so that we don't risk
                    // syncing out-of-date state to storage service.
                    strongSelf.deps.signalRecipientShim.createHighTrustRecipient(
                        aci: accountIdentity.aci,
                        e164: accountIdentity.e164,
                        transaction: tx
                    )
                    strongSelf.deps.tsAccountManager.updateLocalPhoneNumber(
                        e164: accountIdentity.e164,
                        aci: accountIdentity.aci,
                        pni: accountIdentity.pni,
                        tx
                    )
                    // Make sure we update our local account.
                    strongSelf.deps.storageServiceManager.recordPendingLocalAccountUpdates()
                }
                return .success
            } catch {
                Logger.error("Failed to finalize change number state: \(error)")
                return .genericError
            }
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

    private func requiresSystemPermissions() -> Guarantee<Bool> {
        let contacts = deps.contactsStore.needsContactsAuthorization()
        let notifications = deps.pushRegistrationManager.needsNotificationAuthorization()
        return Guarantee.when(fulfilled: [contacts, notifications])
            .map { results in
                return results.allSatisfy({ $0 })
            }
            .recover { _ in return .value(true) }
    }

    // MARK: - Register/Change Number Requests

    private func makeRegisterOrChangeNumberRequest(
        _ method: RegistrationRequestFactory.VerificationMethod,
        e164: E164,
        responseHandler: @escaping (AccountResponse) -> Guarantee<RegistrationStep>
    ) -> Guarantee<RegistrationStep> {
        switch mode {
        case .reRegistering(let state):
            if persistedState.hasResetForReRegistration.negated {
                db.write { tx in
                    deps.tsAccountManager.resetForReregistration(
                        e164: state.e164,
                        aci: state.aci,
                        tx
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
            let accountAttributes = makeAccountAttributes()
            return Service
                .makeCreateAccountRequest(
                    method,
                    e164: e164,
                    authPassword: authToken,
                    accountAttributes: accountAttributes,
                    skipDeviceTransfer: shouldSkipDeviceTransfer(),
                    signalService: deps.signalService,
                    schedulers: schedulers
                )
                .then(on: schedulers.main) { accountResponse in
                    return responseHandler(accountResponse)
                }

        case .changingNumber(let changeNumberState):
            if let pniState = changeNumberState.pniState {
                // We had an in flight change number that was interrupted, recover.
                return recoverPendingPniChangeNumberState(
                    changeNumberState: changeNumberState,
                    pniState: pniState
                )
            }
            return self.generatePniStateAndMakeChangeNumberRequest(
                e164: e164,
                verificationMethod: method,
                changeNumberState: changeNumberState
            ).then(on: schedulers.main) { accountResponse in
                return responseHandler(accountResponse)
            }

        }
    }

    private func generatePniStateAndMakeChangeNumberRequest(
        e164: E164,
        verificationMethod: RegistrationRequestFactory.VerificationMethod,
        changeNumberState: RegistrationCoordinatorLoaderImpl.Mode.ChangeNumberState
    ) -> Guarantee<AccountResponse> {
        return deps.changeNumberPniManager
            .generatePniIdentity(
                forNewE164: e164,
                localAci: ServiceId(changeNumberState.localAci),
                localAccountId: changeNumberState.localAccountId,
                localDeviceId: changeNumberState.localDeviceId,
                localUserAllDeviceIds: changeNumberState.localUserAllDeviceIds
            )
            .then(on: schedulers.sharedBackground) { [weak self] pniResult -> Guarantee<AccountResponse> in
                guard let strongSelf = self else {
                    return .value(.genericError)
                }
                switch pniResult {
                case .failure:
                    return .value(.genericError)
                case .success(let pniParams, let pniPendingState):
                    return strongSelf.makeChangeNumberRequest(
                        e164: e164,
                        verificationMethod: verificationMethod,
                        changeNumberState: changeNumberState,
                        pniPendingState: pniPendingState,
                        pniParams: pniParams
                    )

                }
            }
    }

    private func makeChangeNumberRequest(
        e164: E164,
        verificationMethod: RegistrationRequestFactory.VerificationMethod,
        changeNumberState: RegistrationCoordinatorLoaderImpl.Mode.ChangeNumberState,
        pniPendingState: ChangePhoneNumberPni.PendingState,
        pniParams: ChangePhoneNumberPni.Parameters
    ) -> Guarantee<AccountResponse> {
        // Process all messages first.
        return deps.messageProcessor.waitForProcessingCompleteAndThenSuspend(for: .pendingChangeNumber)
            .then(on: schedulers.main) { [weak self] in
                guard let strongSelf = self else {
                    return .value(.genericError)
                }
                do {
                    try strongSelf.db.write { tx in
                        strongSelf._unsafeToModify_mode = .changingNumber(try strongSelf.loader.savePendingChangeNumber(
                            oldState: changeNumberState,
                            pniState: pniPendingState.asRegPniState(),
                            transaction: tx
                        ))
                    }
                } catch {
                    return .value(.genericError)
                }
                return Service
                    .makeChangeNumberRequest(
                        verificationMethod,
                        e164: e164,
                        reglockToken: strongSelf.inMemoryState.reglockToken,
                        authPassword: changeNumberState.oldAuthToken,
                        pniChangeNumberParameters: pniParams,
                        signalService: strongSelf.deps.signalService,
                        schedulers: strongSelf.schedulers
                    )
            }
    }

    private func recoverPendingPniChangeNumberState(
        changeNumberState: Mode.ChangeNumberState,
        pniState: Mode.ChangeNumberState.PendingPniState
    ) -> Guarantee<RegistrationStep> {
        return Service
            .makeWhoAmIRequest(
                auth: ChatServiceAuth.explicit(
                    aci: changeNumberState.localAci,
                    password: changeNumberState.oldAuthToken
                ),
                signalService: deps.signalService,
                schedulers: schedulers
            )
            .then(on: schedulers.main) { [weak self] whoAmIResult -> Guarantee<RegistrationStep> in
                guard let strongSelf = self else {
                    return unretainedSelfError()
                }
                switch whoAmIResult {
                case .networkError, .genericError:
                    return .value(.showErrorSheet(.genericError))
                case .success(let whoAmIResponse):
                    if whoAmIResponse.e164 == pniState.newE164 {
                        // Success! Fake us getting the success response.
                        strongSelf.db.write { tx in
                            strongSelf.handleSuccessfulAccountResponse(
                                identity: AccountIdentity(
                                    aci: whoAmIResponse.aci,
                                    pni: whoAmIResponse.pni,
                                    e164: whoAmIResponse.e164,
                                    hasPreviouslyUsedKBS: strongSelf.inMemoryState.didHaveKbsBackupsPriorToReg,
                                    authPassword: changeNumberState.oldAuthToken
                                ),
                                tx
                            )
                        }
                        return strongSelf.nextStep()
                    } else {
                        // We had an in progress change number, but we arent on that number now.
                        // pretend it never happened.
                        do {
                            try strongSelf.db.write { tx in
                                strongSelf._unsafeToModify_mode = .changingNumber(try strongSelf.loader.savePendingChangeNumber(
                                    oldState: changeNumberState,
                                    pniState: nil,
                                    transaction: tx
                                ))
                            }
                        } catch {
                            return .value(.showErrorSheet(.genericError))
                        }
                        return strongSelf.nextStep()
                    }
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

    // MARK: - Account objects

    private func makeAccountAttributes() -> AccountAttributes {
        let twoFAMode: AccountAttributes.TwoFactorAuthMode
        if inMemoryState.wasReglockEnabled, let reglockToken = inMemoryState.reglockToken {
            twoFAMode = .v2(reglockToken: reglockToken)
        } else if
            let pinCode = inMemoryState.pinFromDisk,
            inMemoryState.isV12faUser
        {
            twoFAMode = .v1(pinCode: pinCode)
        } else {
            twoFAMode = .none
        }
        return AccountAttributes(
            isManualMessageFetchEnabled: inMemoryState.isManualMessageFetchEnabled,
            registrationId: inMemoryState.registrationId,
            pniRegistrationId: inMemoryState.pniRegistrationId,
            unidentifiedAccessKey: inMemoryState.udAccessKey.keyData.base64EncodedString(),
            unrestrictedUnidentifiedAccess: inMemoryState.allowUnrestrictedUD,
            twofaMode: twoFAMode,
            registrationRecoveryPassword: inMemoryState.regRecoveryPw,
            encryptedDeviceName: nil, // This class only deals in primary devices, which have no name
            discoverableByPhoneNumber: inMemoryState.isDiscoverableByPhoneNumber,
            canReceiveGiftBadges: deps.remoteConfig.canReceiveGiftBadges,
            hasKBSBackups: true // Always true when registering from this class.
        )
    }

    private func generateServerAuthToken() -> String {
        return Cryptography.generateRandomBytes(16).hexadecimalString
    }

    struct AccountIdentity: Codable {
        let aci: UUID
        let pni: UUID
        let e164: E164
        let hasPreviouslyUsedKBS: Bool

        /// The auth token used to communicate with the server.
        /// We create this locally and include it in the create account request,
        /// then use it to authenticate subsequent requests.
        let authPassword: String

        var authUsername: String {
            return aci.uuidString
        }

        var authedAccount: AuthedAccount {
            return AuthedAccount.explicit(aci: aci, e164: e164, authPassword: authPassword)
        }

        var chatServiceAuth: ChatServiceAuth {
            return ChatServiceAuth.explicit(aci: aci, password: authPassword)
        }
    }

    enum AccountResponse {
        case success(AccountIdentity)
        case reglockFailure(RegistrationServiceResponses.RegistrationLockFailureResponse)
        /// The verification method attempted was rejected.
        /// Either the session was invalid/expired or the registration recovery password was wrong.
        case rejectedVerificationMethod
        case deviceTransferPossible
        case retryAfter(TimeInterval)
        case networkError
        case genericError
    }

    // MARK: - Step State Generation Helpers

    private func phoneNumberEntryState(
        validationError: RegistrationPhoneNumberViewState.ValidationError? = nil
    ) -> RegistrationPhoneNumberViewState {
        switch mode {
        case .registering:
            return .registration(.initialRegistration(.init(
                previouslyEnteredE164: persistedState.e164,
                validationError: validationError
            )))
        case .reRegistering(let state):
            return .registration(.reregistration(.init(
                e164: state.e164,
                validationError: validationError
            )))
        case .changingNumber(let state):
            var rateLimitedError: RegistrationPhoneNumberViewState.ValidationError.RateLimited?
            switch validationError {
            case .none:
                break
            case .rateLimited(let error):
                rateLimitedError = error
            case .invalidNumber(let invalidNumberError):
                return .changingNumber(.initialEntry(.init(
                    oldE164: state.oldE164,
                    newE164: inMemoryState.changeNumberProspectiveE164,
                    hasConfirmed: inMemoryState.changeNumberProspectiveE164 != nil,
                    invalidNumberError: invalidNumberError
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
                    invalidNumberError: nil
                )))
            }
        }
    }

    private func verificationCodeEntryState(
        session: RegistrationSession,
        nextVerificationAttemptDate: Date,
        validationError: RegistrationVerificationValidationError? = nil
    ) -> RegistrationVerificationState {
        let exitConfiguration: RegistrationVerificationState.ExitConfiguration
        if canExitRegistrationFlow() {
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
        return RegistrationVerificationState(
            e164: session.e164,
            nextSMSDate: session.nextSMSDate,
            nextCallDate: session.nextCallDate,
            nextVerificationAttemptDate: nextVerificationAttemptDate,
            validationError: validationError,
            exitConfiguration: exitConfiguration
        )
    }

    private func pinCodeEntryExitConfiguration() -> RegistrationPinState.ExitConfiguration {
        guard canExitRegistrationFlow() else {
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

    private var reglockTimeoutAcknowledgeAction: RegistrationReglockTimeoutAcknowledgeAction {
        switch mode {
        case .registering: return .resetPhoneNumber
        case .reRegistering, .changingNumber: return .close
        }
    }

    private func shouldRestoreFromStorageService() -> Bool {
        switch mode {
        case .registering, .reRegistering:
            return !inMemoryState.hasRestoredFromStorageService
                && !inMemoryState.hasSkippedRestoreFromStorageService
        case .changingNumber:
            return false
        }
    }

    private func shouldSyncPreKeys() -> Bool {
        switch mode {
        case .registering, .reRegistering:
            return !persistedState.didSyncPrekeys
        case .changingNumber:
            return false
        }
    }

    // MARK: - Exit

    private func canExitRegistrationFlow() -> Bool {
        switch mode {
        case .registering:
            return false
        case .reRegistering:
            return persistedState.hasResetForReRegistration.negated
        case .changingNumber(let state):
            return state.pniState == nil
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

        // If we have a PIN and KBS master key locally (only possible for re-registration)
        // then we reuse it to register. We make the user guess the PIN before proceeding,
        // though. This is how many tries they have before we wipe our local state and make
        // them go through re-registration.
        static let maxLocalPINGuesses: UInt = 10

        /// How long we wait for a push challenge to the exclusion of all else after requesting one.
        /// Even if we have another challenge to fulfill, we will wait this long before proceeding.
        static let pushTokenMinWaitTime: TimeInterval = 3
        /// How long we block waiting for a push challenge after requesting one.
        /// We might still fulfill the challenge after this, but we won't opportunistically block proceeding.
        static let pushTokenTimeout: TimeInterval = 30
    }
}

private func unretainedSelfError() -> Guarantee<RegistrationStep> {
    return .value(unretainedSelfErrorStep())
}

private func unretainedSelfErrorStep() -> RegistrationStep {
    Logger.warn("Registration coordinator reference lost. Showing generic error")
    return .showErrorSheet(.genericError)
}
