//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Contacts
import Foundation

public class RegistrationCoordinatorImpl: RegistrationCoordinator {

    private let accountManager: RegistrationCoordinatorImpl.Shims.AccountManager
    private let contactsManager: RegistrationCoordinatorImpl.Shims.ContactsManager
    private let contactsStore: RegistrationCoordinatorImpl.Shims.ContactsStore
    private let dateProvider: DateProvider
    private let db: DB
    private let experienceManager: RegistrationCoordinatorImpl.Shims.ExperienceManager
    private let kbs: KeyBackupServiceProtocol
    private let kbsAuthCredentialStore: KBSAuthCredentialStorage
    private let kvStore: KeyValueStoreProtocol
    private let ows2FAManager: RegistrationCoordinatorImpl.Shims.OWS2FAManager
    private let preKeyManager: RegistrationCoordinatorImpl.Shims.PreKeyManager
    private let profileManager: RegistrationCoordinatorImpl.Shims.ProfileManager
    private let pushRegistrationManager: RegistrationCoordinatorImpl.Shims.PushRegistrationManager
    private let receiptManager: RegistrationCoordinatorImpl.Shims.ReceiptManager
    private let remoteConfig: RegistrationCoordinatorImpl.Shims.RemoteConfig
    private let schedulers: Schedulers
    private let sessionManager: RegistrationSessionManager
    private let signalService: OWSSignalServiceProtocol
    private let storageServiceManager: StorageServiceManagerProtocol
    private let tsAccountManager: RegistrationCoordinatorImpl.Shims.TSAccountManager
    private let udManager: RegistrationCoordinatorImpl.Shims.UDManager

    public init(
        accountManager: RegistrationCoordinatorImpl.Shims.AccountManager,
        contactsManager: RegistrationCoordinatorImpl.Shims.ContactsManager,
        contactsStore: RegistrationCoordinatorImpl.Shims.ContactsStore,
        dateProvider: @escaping DateProvider,
        db: DB,
        experienceManager: RegistrationCoordinatorImpl.Shims.ExperienceManager,
        kbs: KeyBackupServiceProtocol,
        kbsAuthCredentialStore: KBSAuthCredentialStorage,
        keyValueStoreFactory: KeyValueStoreFactory,
        ows2FAManager: RegistrationCoordinatorImpl.Shims.OWS2FAManager,
        preKeyManager: RegistrationCoordinatorImpl.Shims.PreKeyManager,
        profileManager: RegistrationCoordinatorImpl.Shims.ProfileManager,
        pushRegistrationManager: RegistrationCoordinatorImpl.Shims.PushRegistrationManager,
        receiptManager: RegistrationCoordinatorImpl.Shims.ReceiptManager,
        remoteConfig: RegistrationCoordinatorImpl.Shims.RemoteConfig,
        schedulers: Schedulers,
        sessionManager: RegistrationSessionManager,
        signalService: OWSSignalServiceProtocol,
        storageServiceManager: StorageServiceManagerProtocol,
        tsAccountManager: RegistrationCoordinatorImpl.Shims.TSAccountManager,
        udManager: RegistrationCoordinatorImpl.Shims.UDManager
    ) {
        self.accountManager = accountManager
        self.contactsManager = contactsManager
        self.contactsStore = contactsStore
        self.dateProvider = dateProvider
        self.db = db
        self.experienceManager = experienceManager
        self.kbs = kbs
        self.kbsAuthCredentialStore = kbsAuthCredentialStore
        self.kvStore = keyValueStoreFactory.keyValueStore(collection: "RegistrationCoordinator")
        self.ows2FAManager = ows2FAManager
        self.preKeyManager = preKeyManager
        self.profileManager = profileManager
        self.pushRegistrationManager = pushRegistrationManager
        self.receiptManager = receiptManager
        self.remoteConfig = remoteConfig
        self.schedulers = schedulers
        self.sessionManager = sessionManager
        self.signalService = signalService
        self.storageServiceManager = storageServiceManager
        self.tsAccountManager = tsAccountManager
        self.udManager = udManager
    }

    // MARK: - Public API

    public func nextStep() -> Guarantee<RegistrationStep> {
        AssertIsOnMainThread()
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
        return pushRegistrationManager.registerUserNotificationSettings()
            .then(on: schedulers.main) { [weak self] in
                guard let self else {
                    owsFailBeta("Unretained self lost")
                    return .value(())
                }
                return self.contactsStore.requestContactsAuthorization()
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

    public func submitE164(_ e164: String) -> Guarantee<RegistrationStep> {
        // TODO[Registration] do some validation on the e164 format?
        // maybe we trust the view controller to do that.
        db.write { tx in
            updatePersistedState(tx) {
                $0.e164 = e164
            }
        }
        inMemoryState.hasEnteredE164 = true
        switch getPathway() {
        case .opening:
            // Now we transition to the session path since
            // we are submitting an e164.
            return self.startSession(e164: e164)
        case .registrationRecoveryPassword(let password):
            return nextStepForRegRecoveryPasswordPath(regRecoveryPw: password)
        case .kbsAuthCredential:
            owsFailBeta("Shouldn't be submitting an e164 for a known valid kbs auth credential")
            return nextStep()
        case .kbsAuthCredentialCandidates:
            return nextStep()
        case .session:
            return self.startSession(e164: e164)
        case .profileSetup:
            owsFailBeta("Shouldn't be submitting an e164 in profile setup")
            return nextStep()
        }
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
                        kbs.clearKeys(transaction: tx)
                    }
                    self.wipeInMemoryStateToPreventKBSPathAttempts()
                    return .value(.showErrorSheet(.pinGuessesExhausted))
                } else {
                    return .value(.pinEntry(RegistrationPinState(
                        operation: .enteringExistingPin(canSkip: true),
                        error: .wrongPin(wrongPin: code)
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
            kbs.clearKeys(transaction: tx)
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
            return .value(.showErrorSheet(.todo))
        }
        self.inMemoryState.hasDefinedIsDiscoverableByPhoneNumber = true
        self.inMemoryState.isDiscoverableByPhoneNumber = isDiscoverable
        db.write { tx in
            // We will update storage service at the end of registration.
            tsAccountManager.setIsDiscoverableByPhoneNumber(
                true,
                updateStorageService: false,
                authedAccount: accountIdentity.authedAccount,
                tx
            )
        }

        return nextStep()
    }

    public func setProfileInfo(givenName: String, familyName: String?, avatarData: Data?) -> Guarantee<RegistrationStep> {
        inMemoryState.pendingProfileInfo = (givenName: givenName, familyName: familyName, avatarData: avatarData)
        return self.nextStep()
    }

    // MARK: - Internal

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

        // We always require the user to enter the PIN
        // during the in memory app session even if we
        // have it on disk.
        // This is a way to double check they know the PIN.
        var pinFromUser: String?
        var pinFromDisk: String?
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
        var shouldRestoreFromStorageService: Bool {
            return !hasRestoredFromStorageService && !hasSkippedRestoreFromStorageService
        }
    }

    private var inMemoryState = InMemoryState()

    // MARK: - Persisted State

    enum Mode: Codable, Equatable {
        case registering
        case reRegistering(e164: String)
        case changingNumber(oldE164: String, oldAuthToken: String)
    }

    /// This state is kept across launches of registration. Whatever is set
    /// here must be explicitly wiped between sessions if desired.
    /// Note: We don't persist RegistrationSession because RegistrationSessionManager
    /// handles that; we restore it to InMemoryState instead.
    private struct PersistedState: Codable {
        // TODO[Registration] allow setting this when kicking things off.
        var mode: Mode = .registering

        /// We only ever want to show the splash once, and only
        /// for flows possible from new devices.
        var hasShownSplash = false

        /// The e164 the user has entered for this attempt at registration.
        /// Initially the e164 in the UI may be pre-populated (e.g. in re-reg)
        /// but this value is not set until the user accepts it or enters their own value.
        var e164: String?

        /// How many times the user has tried making guesses against the PIN
        /// we have locally? This happens when we have a local KBS master key
        /// and want to confirm the user knows their PIN before using it to register.
        var numLocalPinGuesses = 0

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
            inMemoryState.pinFromDisk = ows2FAManager.pinCode(tx)

            let kbsAuthCredentialCandidates = kbsAuthCredentialStore.getAuthCredentials(tx)
            if kbsAuthCredentialCandidates.isEmpty.negated {
                inMemoryState.kbsAuthCredentialCandidates = kbsAuthCredentialCandidates
            }
            inMemoryState.isManualMessageFetchEnabled = tsAccountManager.isManualMessageFetchEnabled(tx)
            inMemoryState.registrationId = tsAccountManager.getOrGenerateRegistrationId(tx)
            inMemoryState.pniRegistrationId = tsAccountManager.getOrGeneratePniRegistrationId(tx)

            inMemoryState.allowUnrestrictedUD = udManager.shouldAllowUnrestrictedAccessLocal(transaction: tx)

            inMemoryState.wasReglockEnabled = ows2FAManager.isReglockEnabled(tx)
        }

        let sessionGuarantee: Guarantee<Void> = sessionManager.restoreSession()
            .map(on: schedulers.main) { [weak self] session in
                self?.db.write { self?.processSession(session, $0) }
            }

        let permissionsGuarantee: Guarantee<Void> = requiresSystemPermissions()
            .map(on: schedulers.main) { [weak self] needsPermissions in
                self?.inMemoryState.needsSomePermissions = needsPermissions
            }

        return Guarantee.when(resolved: sessionGuarantee, permissionsGuarantee).asVoid()
            .done(on: schedulers.main) { [weak self] in
                defer {
                    self?.inMemoryState.hasRestoredState = true
                }

                if self?.persistedState.hasShownSplash == false {
                    var showSplashIfUnshown: Bool
                    switch self?.persistedState.mode {
                    case .reRegistering, .changingNumber:
                        // For these flows starting from a registered client,
                        // don't show the splash.
                        showSplashIfUnshown = false
                    case .none, .registering:
                        showSplashIfUnshown = true
                    }
                    if self?.inMemoryState.regRecoveryPw != nil {
                        // If we have a reg recovery pw, it means either
                        // this is re-reg on a device that already had it,
                        // or we got past the splash already anyway.
                        showSplashIfUnshown = false
                    }
                    if !showSplashIfUnshown {
                        // If we won't show it, set it as "shown".
                        // It was "shown" on this device before we even
                        // started registration.
                        self?.db.write { tx in
                            self?.updatePersistedState(tx) {
                                $0.hasShownSplash = true
                            }
                        }
                    }
                }
            }
    }

    /// Once registration is complete, we need to take our internal state and write it out to
    /// external classes so that the rest of the app has all our updated information.
    /// Once this is done, we can wipe the internal state of this class so that we get a fresh
    /// registration if we ever re-register while in the same app session.
    private func exportAndWipeState(accountIdentity: AccountIdentity) -> Guarantee<RegistrationStep> {

        db.write { tx in
            if inMemoryState.hasBackedUpToKBS {
                // No need to show the experience if we made the pin
                // and backed up.
                experienceManager.clearIntroducingPinsExperience(tx)
            }

            switch persistedState.mode {
            case .reRegistering, .changingNumber:
                break
            case .registering:
                // For new users, read receipts are on by default.
                receiptManager.setAreReadReceiptsEnabled(true, tx)
                receiptManager.setAreStoryViewedReceiptsEnabled(true, tx)
                // New users also have the onboarding banner cards enabled
                experienceManager.enableAllGetStartedCards(tx)
            }

            // TODO[Registration]: should this happen after updating account attributes,
            // since that can fail?
            tsAccountManager.didRegister(accountIdentity.response, authToken: accountIdentity.authToken, tx)
            tsAccountManager.setIsOnboarded(tx)
        }

        // Start syncing system contacts now that we have set up tsAccountManager.
        contactsManager.fetchSystemContactsOnceIfAlreadyAuthorized(authedAccount: accountIdentity.authedAccount)

        // Update the account attributes once, now, at the end.
        return updateAccountAttributesAndFinish(accountIdentity: accountIdentity)
    }

    private func updateAccountAttributesAndFinish(
        accountIdentity: AccountIdentity,
        retriesLeft: Int = Constants.networkErrorRetries
    ) -> Guarantee<RegistrationStep> {
        updateAccountAttributes(accountIdentity)
            .then(on: schedulers.main) { [weak self] error -> Guarantee<RegistrationStep> in
                guard let self else {
                    return .value(.showErrorSheet(.todo))
                }
                guard let error else {
                    // We are done! Wipe everything
                    self.inMemoryState = InMemoryState()
                    self.db.write { tx in
                        try? self.kvStore.setCodable(PersistedState(), key: Constants.persistedStateKey, transaction: tx)
                    }
                    // Do any storage service backups we have pending.
                    self.storageServiceManager.backupPendingChanges(authedAccount: accountIdentity.authedAccount)
                    return .value(.done)
                }
                if error.isNetworkConnectivityFailure, retriesLeft > 0 {
                    return self.updateAccountAttributesAndFinish(
                        accountIdentity: accountIdentity,
                        retriesLeft: retriesLeft - 1
                    )
                }
                // TODO[Registration]: what should we do with a non-transient account attributes update error?
                Logger.error("Failed to register due to failed account attributes update: \(error)")
                return .value(.showErrorSheet(.todo))
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
        if !persistedState.hasShownSplash || inMemoryState.needsSomePermissions {
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
        if persistedState.hasShownSplash.negated {
            return .value(.splash)
        }
        if inMemoryState.needsSomePermissions {
            // This class is only used for primary device registration
            // which always needs contacts permissions.
            return .value(.permissions(RegistrationPermissionsState(shouldRequestAccessToContacts: true)))
        }
        if inMemoryState.hasEnteredE164, let e164 = persistedState.e164 {
            return self.startSession(e164: e164)
        }
        return .value(.phoneNumberEntry(RegistrationPhoneNumberState(
            mode: phoneNumberEntryStateMode(),
            validationError: nil
        )))
    }

    // MARK: - Registration Recovery Password Pathway

    /// If we have the KBS master key saved locally (e.g. this is re-registration), we can generate the
    /// "Registration Recovery Password" from it, which we can use as an alternative to a verified SMS code session
    /// to register. This path returns the steps to complete that flow.
    private func nextStepForRegRecoveryPasswordPath(regRecoveryPw: String) -> Guarantee<RegistrationStep> {
        // We need a phone number to proceed; ask the user if unavailable.
        guard let e164 = persistedState.e164 else {
            return .value(.phoneNumberEntry(RegistrationPhoneNumberState(
                mode: phoneNumberEntryStateMode(),
                validationError: nil
            )))
        }

        guard let pinFromUser = inMemoryState.pinFromUser else {
            // We need the user to confirm their pin.
            return .value(.pinEntry(RegistrationPinState(
                // We can skip which will stop trying to use reg recovery.
                operation: .enteringExistingPin(canSkip: true),
                error: nil
            )))
        }

        if
            let pinFromDisk = inMemoryState.pinFromDisk,
            pinFromDisk != pinFromUser
        {
            Logger.warn("PIN mismatch; should be prevented at submission time.")
            return .value(.pinEntry(RegistrationPinState(
                operation: .enteringExistingPin(canSkip: true),
                error: .wrongPin(wrongPin: pinFromUser)
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
        e164: String,
        pinFromUser: String,
        retriesLeft: Int = Constants.networkErrorRetries
    ) -> Guarantee<RegistrationStep> {
        return self.makeRegisterOrChangeNumberRequest(
            .recoveryPassword(regRecoveryPw),
            e164: e164
        ).then(on: schedulers.main) { [weak self] accountResponse in
            return self?.handleCreateAccountResponseFromRegRecoveryPassword(
                accountResponse,
                regRecoveryPw: regRecoveryPw,
                e164: e164,
                pinFromUser: pinFromUser,
                retriesLeft: retriesLeft
            ) ?? .value(.showErrorSheet(.todo))
        }
    }

    private func handleCreateAccountResponseFromRegRecoveryPassword(
        _ response: AccountResponse,
        regRecoveryPw: String,
        e164: String,
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
                kbsAuthCredentialStore.storeAuthCredentialForCurrentUsername(reglockFailure.kbsAuthCredential, tx)
                kbsAuthCredentialStore.deleteInvalidCredentials([reglockFailure.kbsAuthCredential], tx)
                // Clear the KBS master key locally; we failed reglock so we know its wrong
                // and useless anyway.
                kbs.clearKeys(transaction: tx)
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
                kbsAuthCredentialStore.deleteInvalidCredentials([inMemoryState.kbsAuthCredential].compacted(), tx)
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
                            return .value(.showErrorSheet(.todo))
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
            return .value(.showErrorSheet(.todo))

        case .genericError:
            return .value(.showErrorSheet(.todo))
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
                operation: .enteringExistingPin(canSkip: true),
                error: nil
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
        kbs.restoreKeysAndBackup(pin: pin, authMethod: .kbsAuth(credential, backup: nil))
            .then(on: schedulers.main) { [weak self] result -> Guarantee<RegistrationStep> in
                guard let self = self else {
                    return .value(.showErrorSheet(.todo))
                }
                switch result {
                case .success:
                    // This step also backs up, no need to do that again later.
                    self.inMemoryState.hasBackedUpToKBS = true
                    self.db.read { self.loadLocalMasterKey($0) }
                    return self.nextStep()
                case .invalidPin:
                    return .value(.pinEntry(RegistrationPinState(
                        operation: .enteringExistingPin(canSkip: true),
                        error: .wrongPin(wrongPin: pin)
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
                    return .value(.showErrorSheet(.todo))
                case .genericError:
                    return .value(.showErrorSheet(.todo))
                }
            }
    }

    private func loadLocalMasterKey(_ tx: DBReadTransaction) {
        // The hex vs base64 different here is intentional.
        inMemoryState.regRecoveryPw = kbs.data(for: .registrationRecoveryPassword, transaction: tx)?.base64EncodedString()
        inMemoryState.reglockToken = kbs.data(for: .registrationLock, transaction: tx)?.hexadecimalString
        // If we have a local master key, theres no need to restore after registration.
        // (we will still back up though)
        inMemoryState.shouldRestoreKBSMasterKeyAfterRegistration = !kbs.hasMasterKey(transaction: tx)
    }

    // MARK: - KBS Auth Credential Candidates Pathway

    private func nextStepForKBSAuthCredentialCandidatesPath(
        kbsAuthCredentialCandidates: [KBSAuthCredential]
    ) -> Guarantee<RegistrationStep> {
        guard let e164 = persistedState.e164 else {
            // If we haven't entered a phone number but we have auth
            // credential candidates to check, enter it now.
            return .value(.phoneNumberEntry(RegistrationPhoneNumberState(
                mode: phoneNumberEntryStateMode(),
                validationError: nil
            )))
        }
        // Check the candidates.
        return makeKBSAuthCredentialCheckRequest(
            kbsAuthCredentialCandidates: kbsAuthCredentialCandidates,
            e164: e164
        )
    }

    private func makeKBSAuthCredentialCheckRequest(
        kbsAuthCredentialCandidates: [KBSAuthCredential],
        e164: String,
        retriesLeft: Int = Constants.networkErrorRetries
    ) -> Guarantee<RegistrationStep> {
        return Service.makeKBSAuthCheckRequest(
            e164: e164,
            candidateCredentials: kbsAuthCredentialCandidates,
            signalService: signalService,
            schedulers: schedulers
        ).then(on: schedulers.main) { [weak self] response in
            guard let self else {
                return .value(.showErrorSheet(.todo))
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
        e164: String,
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
            self.kbsAuthCredentialStore.deleteInvalidCredentials(credentialsToDelete, tx)
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
                    operation: .enteringExistingPin(canSkip: false),
                    error: .none
                )))
            }
        case .waitingTimeout(let reglockExpirationDate):
            if dateProvider() >= reglockExpirationDate {
                // We've passed the time needed and reglock should be expired.
                // Wipe our state and proceed.
                db.write { tx in
                    self.updatePersistedSessionState(session: session, tx) {
                        $0.reglockState = .none
                    }
                }
                return self.nextStep()
            }
            // TODO[Registration]: provide reglock timeout state.
            return .value(.reglockTimeout)
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
                    if let nextSMSDate = session.nextSMSDate, nextSMSDate <= dateProvider() {
                        return requestSessionCode(session: session, transport: pendingCodeTransport)
                    } else if let nextVerificationAttemptDate = session.nextVerificationAttemptDate {
                        return .value(.verificationCodeEntry(self.verificationCodeEntryState(
                            session: session,
                            nextVerificationAttemptDate: nextVerificationAttemptDate,
                            validationError: .smsResendTimeout
                        )))
                    } else if let nextSMSDate = session.nextSMSDate {
                        return .value(.phoneNumberEntry(RegistrationPhoneNumberState(
                            mode: self.phoneNumberEntryStateMode(),
                            validationError: .rateLimited(expiration: nextSMSDate)
                        )))
                    } else {
                        return .value(.showErrorSheet(.verificationCodeSubmissionUnavailable))
                    }
                case .voice:
                    if let nextCallDate = session.nextCallDate, nextCallDate <= dateProvider() {
                        return requestSessionCode(session: session, transport: pendingCodeTransport)
                    } else if let nextVerificationAttemptDate = session.nextVerificationAttemptDate {
                        return .value(.verificationCodeEntry(self.verificationCodeEntryState(
                            session: session,
                            nextVerificationAttemptDate: nextVerificationAttemptDate,
                            validationError: .voiceResendTimeout
                        )))
                    } else if let nextSMSDate = session.nextSMSDate {
                        return .value(.phoneNumberEntry(RegistrationPhoneNumberState(
                            mode: self.phoneNumberEntryStateMode(),
                            validationError: .rateLimited(expiration: nextSMSDate)
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
        return .value(.phoneNumberEntry(RegistrationPhoneNumberState(
            mode: phoneNumberEntryStateMode(),
            validationError: nil
        )))
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
        self.sessionManager.clearPersistedSession(transaction)
    }

    private func makeRegisterOrChangeNumberRequestFromSession(
        _ session: RegistrationSession,
        retriesLeft: Int = Constants.networkErrorRetries
    ) -> Guarantee<RegistrationStep> {
        return self.makeRegisterOrChangeNumberRequest(
            .sessionId(session.id),
            e164: session.e164
        ).then(on: schedulers.main) { [weak self] response in
            guard let self = self else {
                return .value(.showErrorSheet(.todo))
            }
            return self.handleCreateAccountResponseFromSession(
                response,
                sessionFromBeforeRequest: session,
                retriesLeft: retriesLeft
            )
        }
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
                sessionManager.clearPersistedSession(tx)
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
                kbsAuthCredentialStore.storeAuthCredentialForCurrentUsername(reglockFailure.kbsAuthCredential, tx)
                let reglockExpirationDate = self.dateProvider().addingTimeInterval(TimeInterval(reglockFailure.timeRemainingMs / 1000))
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
                            return .value(.showErrorSheet(.todo))
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
            return .value(.showErrorSheet(.todo))
        case .genericError:
            return .value(.showErrorSheet(.todo))
        }
    }

    private func startSession(
        e164: String,
        retriesLeft: Int = Constants.networkErrorRetries
    ) -> Guarantee<RegistrationStep> {
        return pushRegistrationManager.requestPushToken()
            .then(on: schedulers.sharedBackground) { [weak self] apnsToken -> Guarantee<RegistrationStep> in
                guard let strongSelf = self else {
                    return .value(.showErrorSheet(.todo))
                }

                return strongSelf.sessionManager.beginOrRestoreSession(
                    e164: e164,
                    apnsToken: apnsToken
                ).then(on: strongSelf.schedulers.main) { [weak self] response -> Guarantee<RegistrationStep> in
                    guard let strongSelf = self else {
                        return .value(.showErrorSheet(.todo))
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
                        return .value(.phoneNumberEntry(RegistrationPhoneNumberState(
                            mode: strongSelf.phoneNumberEntryStateMode(),
                            validationError: .invalidNumber(invalidE164: e164)
                        )))
                    case .retryAfter(let timeInterval):
                        if timeInterval < Constants.autoRetryInterval {
                            return Guarantee
                                .after(on: strongSelf.schedulers.sharedBackground, seconds: timeInterval)
                                .then(on: strongSelf.schedulers.sync) { [weak self] in
                                    guard let self else {
                                        return .value(.showErrorSheet(.todo))
                                    }
                                    return self.startSession(
                                        e164: e164
                                    )
                                }
                        }
                        return .value(.phoneNumberEntry(RegistrationPhoneNumberState(
                            mode: strongSelf.phoneNumberEntryStateMode(),
                            validationError: .rateLimited(expiration: strongSelf.dateProvider().addingTimeInterval(timeInterval))
                        )))
                    case .networkFailure:
                        if retriesLeft > 0 {
                            return strongSelf.startSession(
                                e164: e164,
                                retriesLeft: retriesLeft - 1
                            )
                        }
                        return .value(.showErrorSheet(.todo))
                    case .genericError:
                        return .value(.showErrorSheet(.todo))
                    }
                }
            }
    }

    private func requestSessionCode(
        session: RegistrationSession,
        transport: Registration.CodeTransport,
        retriesLeft: Int = Constants.networkErrorRetries
    ) -> Guarantee<RegistrationStep> {
        return sessionManager.requestVerificationCode(
            for: session,
            transport: transport
        ).then(on: schedulers.main) { [weak self] (result: Registration.UpdateSessionResponse) -> Guarantee<RegistrationStep> in
            guard let self else {
                return .value(.showErrorSheet(.todo))
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
                    // TODO[Registration] show something special here.
                    return .value(.showErrorSheet(.todo))
                } else {
                    // TODO[Registration] show some particular error here.
                    return .value(.showErrorSheet(.todo))
                }
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
                                return .value(.showErrorSheet(.todo))
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
                        return .value(.phoneNumberEntry(RegistrationPhoneNumberState(
                            mode: self.phoneNumberEntryStateMode(),
                            validationError: .rateLimited(expiration: self.dateProvider().addingTimeInterval(timeInterval))
                        )))
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
                return .value(.showErrorSheet(.todo))
            case .genericError:
                self.inMemoryState.pendingCodeTransport = nil
                return .value(.showErrorSheet(.todo))
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
                $0.pushChallengeState = .waitingForPush(requestedAt: dateProvider())
            }
        case .waitingForPush, .unfulfilledPush, .fulfilled:
            Logger.info("Already waiting for a pre-auth challenge token, presumably from a prior launch")
        }

        // There is no timeout on this promise. That's deliberate. If we get a push challenge token
        // at some point, we'd like to hold onto it, even if it took awhile to arrive. Other spots
        // in the code may handle a timeout.
        pushRegistrationManager.receivePreAuthChallengeToken().done { [weak self] token in
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

        // Our second choice: a CAPTCHA challenge.
        if requestsCaptchaChallenge {
            Logger.info("Showing the CAPTCHA challenge to the user")
            return .value(.captchaChallenge)
        }

        // Our third choice: a push challenge where we're still waiting for the challenge token.
        let isWaitingForPushChallengeToken: Bool = {
            switch persistedState.sessionState?.pushChallengeState {
            case nil, .notRequested, .ineligible, .unfulfilledPush, .fulfilled:
                return false
            case let .waitingForPush(requestedAt):
                let deadline = requestedAt.addingTimeInterval(Constants.pushTokenTimeout)
                return dateProvider() < deadline
            }
        }()
        if requestsPushChallenge, isWaitingForPushChallengeToken {
            Logger.info("Attempting to fulfill push challenge with a token we don't have yet")
            return pushRegistrationManager
                .receivePreAuthChallengeToken()
                .map { $0 }
                .nilTimeout(on: schedulers.sharedBackground, seconds: Constants.pushTokenTimeout)
                .then(on: schedulers.sharedBackground) { [weak self] (challengeToken: String?) -> Guarantee<RegistrationStep> in
                    guard let self else {
                        return .value(.showErrorSheet(.todo))
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
                    }

                    Logger.warn("No challenge token received in time. Resetting")
                    self.db.write { self.resetSession($0) }
                    return .value(.showErrorSheet(.sessionInvalidated))
                }
                .recover(on: schedulers.sharedBackground) { error in
                    // We never expect to hit this code because no part of it should fail. In the
                    // long term, we should fix this by making `Guarantee#nilTimeout` return a
                    // `Guarantee`, not a `Promise`.
                    owsFailBeta("Unexpected error: \(error)")
                    self.db.write { self.resetSession($0) }
                    return .value(.showErrorSheet(.sessionInvalidated))
                }
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

    private func submit(
        challengeFulfillment fulfillment: Registration.ChallengeFulfillment,
        for session: RegistrationSession,
        retriesLeft: Int = Constants.networkErrorRetries
    ) -> Guarantee<RegistrationStep> {
        return sessionManager.fulfillChallenge(
            for: session,
            fulfillment: fulfillment
        ).then(on: schedulers.main) { [weak self] (result: Registration.UpdateSessionResponse) -> Guarantee<RegistrationStep> in
            guard let self else {
                return .value(.showErrorSheet(.todo))
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
                return .value(.showErrorSheet(.todo))
            case .genericError:
                return .value(.showErrorSheet(.todo))
            }
        }
    }

    private func submitSessionCode(
        session: RegistrationSession,
        code: String,
        retriesLeft: Int = Constants.networkErrorRetries
    ) -> Guarantee<RegistrationStep> {
        return sessionManager.submitVerificationCode(
            for: session,
            code: code
        ).then(on: schedulers.main) { [weak self] (result: Registration.UpdateSessionResponse) -> Guarantee<RegistrationStep> in
            guard let self else {
                return .value(.showErrorSheet(.todo))
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
                                return .value(.showErrorSheet(.todo))
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
                return .value(.showErrorSheet(.todo))
            case .genericError:
                return .value(.showErrorSheet(.todo))
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
        return kbs.restoreKeysAndBackup(
            pin: pin,
            authMethod: .kbsAuth(kbsAuthCredential, backup: nil)
        )
            .then(on: schedulers.main) { [weak self] result -> Guarantee<RegistrationStep> in
                guard let self else {
                    return .value(.showErrorSheet(.todo))
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
                case .invalidPin:
                    return .value(.pinEntry(RegistrationPinState(
                        operation: .enteringExistingPin(canSkip: false),
                        error: .wrongPin(wrongPin: pin)
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
                    return .value(.showErrorSheet(.todo))
                case .genericError:
                    return .value(.showErrorSheet(.todo))
                }
            }
    }

    // MARK: - Profile Setup Pathway

    /// Returns the next step the user needs to go through _after_ the actual account
    /// registration or change number is complete (e.g. profile setup).
    private func nextStepForProfileSetup(
        _ accountIdentity: AccountIdentity
    ) -> Guarantee<RegistrationStep> {
        if !inMemoryState.hasSetUpContactsManager {
            // This sets up the contact provider as the primary device one (system contacts).
            // Without this, subsequent operations will fail as no contact provider is set
            // and tsAccountManager isn't set up yet.
            contactsManager.setIsPrimaryDevice()
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

        if !persistedState.didSyncPrekeys {
            return preKeyManager
                .createPreKeys(auth: accountIdentity.chatServiceAuth)
                .then(on: schedulers.main) { [weak self] () -> Guarantee<RegistrationStep> in
                    guard let self else {
                        return .value(.showErrorSheet(.todo))
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

        let isRestoringPinBackup = accountIdentity.response.hasPreviouslyUsedKBS

        if !persistedState.hasSkippedPinEntry {
            guard let pin = inMemoryState.pinFromUser ?? inMemoryState.pinFromDisk else {
                if isRestoringPinBackup {
                    return .value(.pinEntry(RegistrationPinState(
                        operation: .enteringExistingPin(canSkip: true),
                        error: nil
                    )))
                } else if let blob = inMemoryState.unconfirmedPinBlob {
                    return .value(.pinEntry(RegistrationPinState(
                        operation: .confirmingNewPin(blob),
                        error: nil
                    )))
                } else {
                    return .value(.pinEntry(RegistrationPinState(
                        operation: .creatingNewPin,
                        error: nil
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

        if inMemoryState.shouldRestoreFromStorageService {
            return accountManager.performInitialStorageServiceRestore(authedAccount: accountIdentity.authedAccount)
                .map(on: schedulers.main) { [weak self] in
                    self?.inMemoryState.hasRestoredFromStorageService = true
                    return ()
                }
                .recover(on: schedulers.main) { [weak self] _ in
                    self?.inMemoryState.hasSkippedRestoreFromStorageService = true
                    return .value(())
                }
                .then(on: schedulers.sync) { [weak self] in
                    self?.loadProfileState()
                    return self?.nextStep() ?? .value(.showErrorSheet(.todo))
                }
        }

        if !inMemoryState.hasProfileName {
            if let profileInfo = inMemoryState.pendingProfileInfo {
                return profileManager.updateLocalProfile(
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
                            return .value(.showErrorSheet(.todo))
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

            return .value(.setupProfile)
        }

        if !inMemoryState.hasDefinedIsDiscoverableByPhoneNumber {
            return .value(.phoneNumberDiscoverability(RegistrationPhoneNumberDiscoverabilityState(e164: accountIdentity.response.e164.stringValue)))
        }
        if !inMemoryState.hasProfileName {
            return .value(.setupProfile)
        }

        // We are ready to finish! Export all state and wipe things
        // so we can re-register later if desired.
        return exportAndWipeState(accountIdentity: accountIdentity)
    }

    private func syncPushTokens(
        _ accountIdentity: AccountIdentity,
        retriesLeft: Int = Constants.networkErrorRetries
    ) -> Guarantee<RegistrationStep> {
        pushRegistrationManager
            .syncPushTokensForcingUpload(
                auth: accountIdentity.authedAccount.chatServiceAuth
            )
            .then(on: schedulers.main) { [weak self] result in
                guard let strongSelf = self else {
                    return .value(.showErrorSheet(.todo))
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
                            guard let strongSelf = self, maybeError == nil else {
                                Logger.error("Unable to update account attributes for manual message fetch with error: \(String(describing: maybeError))")
                                return .value(.showErrorSheet(.todo))
                            }
                            strongSelf.db.write { tx in
                                strongSelf.tsAccountManager.setIsManualMessageFetchEnabled(true, tx)
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
                    return .value(.showErrorSheet(.todo))
                case .genericError:
                    return .value(.showErrorSheet(.todo))
                }
            }
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
        return kbs
            .restoreKeysAndBackup(
                pin: pin,
                authMethod: authMethod
            )
            .then(on: schedulers.main) { [weak self] result -> Guarantee<RegistrationStep> in
                guard let self else {
                    return .value(.showErrorSheet(.todo))
                }
                switch result {
                case .success:
                    self.inMemoryState.shouldRestoreKBSMasterKeyAfterRegistration = false
                    // This backs up too, no need to do that again after.
                    self.inMemoryState.hasBackedUpToKBS = true
                    return self.nextStep()
                case .invalidPin:
                    return .value(.pinEntry(RegistrationPinState(
                        operation: .enteringExistingPin(canSkip: true),
                        error: .wrongPin(wrongPin: pin)
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
                    return .value(.showErrorSheet(.todo))
                case .genericError:
                    return .value(.showErrorSheet(.todo))
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
        return kbs
            .generateAndBackupKeys(
                pin: pin,
                authMethod: authMethod,
                rotateMasterKey: false
            )
            .then(on: schedulers.main) { [weak self] () -> Guarantee<RegistrationStep>  in
                guard let strongSelf = self else {
                    return .value(.showErrorSheet(.todo))
                }
                strongSelf.inMemoryState.hasBackedUpToKBS = true
                strongSelf.db.write { tx in
                    strongSelf.ows2FAManager.markPinEnabled(pin, tx)
                }
                return strongSelf.accountManager.performInitialStorageServiceRestore(authedAccount: accountIdentity.authedAccount)
                    .map(on: strongSelf.schedulers.main) { [weak self] in
                        self?.inMemoryState.hasRestoredFromStorageService = true
                    }
                    // Ignore errors. This matches the legacy registration flow.
                    .recover(on: strongSelf.schedulers.sync) { _ in return .value(()) }
                    .then(on: strongSelf.schedulers.sync) { [weak self] in
                        return self?.nextStep() ?? .value(.showErrorSheet(.todo))
                    }
            }
            .recover(on: schedulers.main) { [weak self] error -> Guarantee<RegistrationStep> in
                guard let self else {
                    return .value(.showErrorSheet(.todo))
                }
                if error.isNetworkConnectivityFailure {
                    if retriesLeft > 0 {
                        return self.backupToKBS(
                            pin: pin,
                            accountIdentity: accountIdentity,
                            retriesLeft: retriesLeft - 1
                        )
                    }
                    return .value(.showErrorSheet(.todo))
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
            db.read { tx in
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
            signalService: signalService,
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
                return .value(.showErrorSheet(.todo))
            }
            self.inMemoryState.hasSetReglock = true
            self.db.write { tx in
                self.ows2FAManager.markRegistrationLockEnabled(tx)
            }
            return self.nextStep()
        }
    }

    private func loadProfileState() {
        let profileKey = profileManager.localProfileKey
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
        inMemoryState.hasProfileName = profileManager.hasProfileName
        db.read { tx in
            inMemoryState.hasDefinedIsDiscoverableByPhoneNumber = tsAccountManager.hasDefinedIsDiscoverableByPhoneNumber(tx)
            inMemoryState.isDiscoverableByPhoneNumber = tsAccountManager.isDiscoverableByPhoneNumber(tx)
        }
    }

    private func updateAccountAttributes(_ accountIdentity: AccountIdentity) -> Guarantee<Error?> {
        return Service
            .makeUpdateAccountAttributesRequest(
                makeAccountAttributes(authToken: accountIdentity.authToken),
                auth: accountIdentity.chatServiceAuth,
                signalService: signalService,
                schedulers: schedulers
            )
    }

    // MARK: Device Transfer

    private func shouldSkipDeviceTransfer() -> Bool {
        switch persistedState.mode {
        case .registering:
            return persistedState.hasDeclinedTransfer
        case .reRegistering, .changingNumber:
            // Always skip device transfer in these modes.
            return false
        }
    }

    // MARK: - Permissions

    private func requiresSystemPermissions() -> Guarantee<Bool> {
        let contacts = contactsStore.needsContactsAuthorization()
        let notifications = pushRegistrationManager.needsNotificationAuthorization()
        return Guarantee.when(fulfilled: [contacts, notifications])
            .map { results in
                return results.allSatisfy({ $0 })
            }
            .recover { _ in return .value(true) }
    }

    // MARK: - Register/Change Number Requests

    private func makeRegisterOrChangeNumberRequest(
        _ method: RegistrationRequestFactory.VerificationMethod,
        e164: String
    ) -> Guarantee<AccountResponse> {
        switch persistedState.mode {
        case .registering, .reRegistering:
            // The auth token we use going forwards for chat server auth headers
            // is generated by the client. We do that here and put it on the
            // AccountIdentity we generate after success so that we eventually
            // write it to TSAccountManager when all is said and done, and use
            // it for requests we need to make between now and then.
            let authToken = generateServerAuthToken()
            let accountAttributes = makeAccountAttributes(authToken: authToken)
            return Service
                .makeCreateAccountRequest(
                    method,
                    e164: e164,
                    accountAttributes: accountAttributes,
                    skipDeviceTransfer: shouldSkipDeviceTransfer(),
                    signalService: signalService,
                    schedulers: schedulers
                )

        case .changingNumber(_, let oldAuthToken):
            return Service.makeChangeNumberRequest(
                method,
                e164: e164,
                reglockToken: inMemoryState.reglockToken,
                authToken: oldAuthToken,
                signalService: signalService,
                schedulers: schedulers
            )
        }
    }

    private func makeAccountAttributes(authToken: String) -> RegistrationRequestFactory.AccountAttributes {
        return RegistrationRequestFactory.AccountAttributes(
            authKey: authToken,
            isManualMessageFetchEnabled: inMemoryState.isManualMessageFetchEnabled,
            registrationId: inMemoryState.registrationId,
            pniRegistrationId: inMemoryState.pniRegistrationId,
            unidentifiedAccessKey: inMemoryState.udAccessKey.keyData.base64EncodedString(),
            unrestrictedUnidentifiedAccess: inMemoryState.allowUnrestrictedUD,
            registrationLockToken: inMemoryState.reglockToken,
            encryptedDeviceName: nil, // This class only deals in primary devices, which have no name
            discoverableByPhoneNumber: inMemoryState.isDiscoverableByPhoneNumber,
            canReceiveGiftBadges: remoteConfig.canReceiveGiftBadges
        )
    }

    private func generateServerAuthToken() -> String {
        return Cryptography.generateRandomBytes(16).hexadecimalString
    }

    struct AccountIdentity: Codable {
        let response: RegistrationServiceResponses.AccountIdentityResponse
        /// The auth token used to communicate with the server.
        /// We create this locally and include it in the create account request,
        /// then use it to authenticate subsequent requests.
        let authToken: String

        var authUsername: String {
            return response.aci.uuidString
        }
        var authPassword: String {
            return authToken
        }

        var authedAccount: AuthedAccount {
            return AuthedAccount.explicit(aci: response.aci, e164: response.e164, authPassword: authPassword)
        }

        var chatServiceAuth: ChatServiceAuth {
            return ChatServiceAuth.explicit(aci: response.aci, password: authPassword)
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

    private func phoneNumberEntryStateMode() -> RegistrationPhoneNumberState.RegistrationPhoneNumberMode {
        switch persistedState.mode {
        case .registering:
            return .initialRegistration(previouslyEnteredE164: persistedState.e164)
        case .reRegistering(let e164):
            return .reregistration(e164: e164)
        case .changingNumber(let oldE164, _):
            return .changingPhoneNumber(oldE164: oldE164)
        }
    }

    private func verificationCodeEntryState(
        session: RegistrationSession,
        nextVerificationAttemptDate: Date,
        validationError: RegistrationVerificationValidationError? = nil
    ) -> RegistrationVerificationState {
        return RegistrationVerificationState(
            e164: session.e164,
            nextSMSDate: session.nextSMSDate,
            nextCallDate: session.nextCallDate,
            nextVerificationAttemptDate: nextVerificationAttemptDate,
            validationError: validationError
        )
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
        static let maxLocalPINGuesses = 10

        /// How long we block waiting for a push challenge after requesting one.
        /// We might still fulfill the challenge after this, but we won't opportunistically block proceeding.
        static let pushTokenTimeout: TimeInterval = 30
    }
}
