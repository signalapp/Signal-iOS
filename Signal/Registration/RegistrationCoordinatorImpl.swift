//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Contacts
import Foundation

public class RegistrationCoordinatorImpl: RegistrationCoordinator {

    private let contactsStore: RegistrationCoordinatorImpl.Shims.ContactsStore
    private let dateProvider: DateProvider
    private let db: DB
    private let kbs: KeyBackupServiceProtocol
    private let kbsAuthCredentialStore: KBSAuthCredentialStorage
    private let kvStore: KeyValueStoreProtocol
    private let ows2FAManager: RegistrationCoordinatorImpl.Shims.OWS2FAManager
    private let profileManager: RegistrationCoordinatorImpl.Shims.ProfileManager
    private let pushRegistrationManager: RegistrationCoordinatorImpl.Shims.PushRegistrationManager
    private let schedulers: Schedulers
    private let sessionManager: RegistrationSessionManager
    private let signalService: OWSSignalServiceProtocol
    private let tsAccountManager: RegistrationCoordinatorImpl.Shims.TSAccountManager

    public init(
        contactsStore: RegistrationCoordinatorImpl.Shims.ContactsStore,
        dateProvider: @escaping DateProvider,
        db: DB,
        kbs: KeyBackupServiceProtocol,
        kbsAuthCredentialStore: KBSAuthCredentialStorage,
        keyValueStoreFactory: KeyValueStoreFactory,
        ows2FAManager: RegistrationCoordinatorImpl.Shims.OWS2FAManager,
        profileManager: RegistrationCoordinatorImpl.Shims.ProfileManager,
        pushRegistrationManager: RegistrationCoordinatorImpl.Shims.PushRegistrationManager,
        schedulers: Schedulers,
        sessionManager: RegistrationSessionManager,
        signalService: OWSSignalServiceProtocol,
        tsAccountManager: RegistrationCoordinatorImpl.Shims.TSAccountManager
    ) {
        self.contactsStore = contactsStore
        self.dateProvider = dateProvider
        self.db = db
        self.kbs = kbs
        self.kbsAuthCredentialStore = kbsAuthCredentialStore
        self.kvStore = keyValueStoreFactory.keyValueStore(collection: "RegistrationCoordinator")
        self.ows2FAManager = ows2FAManager
        self.profileManager = profileManager
        self.pushRegistrationManager = pushRegistrationManager
        self.schedulers = schedulers
        self.sessionManager = sessionManager
        self.signalService = signalService
        self.tsAccountManager = tsAccountManager
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
            return self.registerForRegRecoveryPwPath(regRecoveryPw: password, e164: e164)
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
            return submitCaptchaChallengeFulfillment(session: session, token: token)
        }
    }

    public func submitPINCode(_ code: String) -> Guarantee<RegistrationStep> {
        // TODO[Registration]: should we reject the pin code right here and now if it differs
        // from what we had on disk?
        self.inMemoryState.pinFromUser = code
        // TODO[Registration]: if we get the pin code after registered, we should
        // pull down backups from KBS.
        return nextStep()
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

        // Wehn we try to register, if we get a response from the server
        // telling us device transfer is possible, we set this to true
        // so the user can explicitly opt out if desired and we retry.
        var needsToAskForDeviceTransfer = false

        var session: RegistrationSession?

        // If we try and resend a code (NOT the original SMS code automatically sent
        // at the start of every session), but hit a challenge, we write this var
        // so that when we complete the challenge we send the code right away.
        var pendingCodeTransport: Registration.CodeTransport?
    }

    private var inMemoryState = InMemoryState()

    // MARK: - Persisted State

    private typealias AccountIdentity = RegistrationServiceResponses.AccountIdentityResponse

    enum Mode: Codable {
        case registering
        case reRegistering
        case changingNumber
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

        /// Once we get an account identity response from the server
        /// for registering, re-registering, or changing phone number,
        /// we remember it so we don't re-register when we quit the app
        /// before finishing post-registration steps.
        var accountIdentity: AccountIdentity?

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

        self.loadLocalMasterKey()
        inMemoryState.pinFromDisk = ows2FAManager.pinCode

        db.read { tx in
            let kbsAuthCredentialCandidates = kbsAuthCredentialStore.getAuthCredentials(tx)
            if kbsAuthCredentialCandidates.isEmpty.negated {
                inMemoryState.kbsAuthCredentialCandidates = kbsAuthCredentialCandidates
            }
        }

        let sessionGuarantee: Guarantee<Void> = sessionManager.restoreSession()
            .map(on: schedulers.main) { [weak self] session in
                self?.processSession(session)
                self?.inMemoryState.hasRestoredState = true
            }

        let permissionsGuarantee: Guarantee<Void> = requiresSystemPermissions()
            .map(on: schedulers.main) { [weak self] needsPermissions in
                self?.inMemoryState.needsSomePermissions = needsPermissions
            }

        return Guarantee.when(resolved: sessionGuarantee, permissionsGuarantee).asVoid()
            .done(on: schedulers.main) { [weak self] in
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
            // We don't need to show it again.
            db.write { tx in
                self.updatePersistedState(tx) {
                    $0.hasShownSplash = true
                }
            }
            return .value(.splash)
        }
        if inMemoryState.needsSomePermissions {
            return .value(.permissions)
        }
        if inMemoryState.hasEnteredE164, let e164 = persistedState.e164 {
            return self.startSession(e164: e164)
        }
        return .value(.phoneNumberEntry)
    }

    // MARK: - Registration Recovery Password Pathway

    /// If we have the KBS master key saved locally (e.g. this is re-registration), we can generate the
    /// "Registration Recovery Password" from it, which we can use as an alternative to a verified SMS code session
    /// to register. This path returns the steps to complete that flow.
    private func nextStepForRegRecoveryPasswordPath(regRecoveryPw: String) -> Guarantee<RegistrationStep> {
        // We need a phone number to proceed; ask the user if unavailable.
        guard let e164 = persistedState.e164 else {
            return .value(.phoneNumberEntry)
        }

        if inMemoryState.pinFromUser == nil {
            // We need the user to confirm their pin.
            return .value(.pinEntry)
        } else if
            let pinFromDisk = inMemoryState.pinFromDisk,
            pinFromDisk != inMemoryState.pinFromUser
        {
            Logger.warn("PIN mismatch; should be prevented by the view controller")
            // TODO[Registration]: set state that tells the pin entry controller
            // that it failed against what we have on disk.
            return .value(.pinEntry)
        }

        if inMemoryState.needsToAskForDeviceTransfer {
            return .value(.transferSelection)
        }

        // Attempt to register right away with the password.
        return registerForRegRecoveryPwPath(
            regRecoveryPw: regRecoveryPw,
            e164: e164
        )
    }

    private func registerForRegRecoveryPwPath(regRecoveryPw: String, e164: String) -> Guarantee<RegistrationStep> {
        if inMemoryState.pinFromUser == nil {
            // We need the user to confirm their pin.
            // TODO[Registration]: set state that tells the pin entry controller
            // that it should verify against what we have on disk.
            return .value(.pinEntry)
        }

        return self.makeRegisterOrChangeNumberRequest(
            .recoveryPassword(regRecoveryPw),
            e164: e164,
            reglockToken: inMemoryState.reglockToken
        ).then(on: schedulers.main) { [weak self] accountResponse in
            return self?.handleCreateAccountResponseFromRegRecoveryPassword(
                accountResponse,
                e164: e164
            ) ?? .value(.showGenericError)
        }
    }

    private func handleCreateAccountResponseFromRegRecoveryPassword(
        _ response: Service.AccountResponse,
        e164: String
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

        case .retryAfter:
            // TODO[Registration] handle retries, possibly automatically if short enough.
            return .value(.showGenericError)

        case .deviceTransferPossible:
            // Device transfer can happen, let the user pick.
            inMemoryState.needsToAskForDeviceTransfer = true
            return nextStep()

        case .genericError:
            return .value(.showGenericError)
        }
    }

    private func wipeInMemoryStateToPreventKBSPathAttempts() {
        inMemoryState.reglockToken = nil
        inMemoryState.regRecoveryPw = nil
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
        let pin: String
        if let pinFromUser = inMemoryState.pinFromUser {
            guard inMemoryState.pinFromDisk == nil || inMemoryState.pinFromDisk == pinFromUser else {
                Logger.warn("Have user pin and disk pin that differ; this should be prevented in the view controller.")
                return .value(.pinEntry)
            }
            pin = pinFromUser
        } else if let pinFromUser = inMemoryState.pinFromUser {
            pin = pinFromUser
        } else {
            // We don't have a pin at all, ask the user for it.
            return .value(.pinEntry)
        }

        return restoreKBSMasterSecret(
            pin: pin,
            credential: kbsAuthCredential
        )
    }

    private func restoreKBSMasterSecret(
        pin: String,
        credential: KBSAuthCredential
    ) -> Guarantee<RegistrationStep> {
        kbs.restoreKeysAndBackup(with: pin, and: credential)
            .then(on: schedulers.main) { [weak self] () -> Guarantee<RegistrationStep> in
                guard let self = self else {
                    return .value(.showGenericError)
                }
                // We don't need to use the credential anymore, wipe it.
                self.inMemoryState.kbsAuthCredential = nil
                self.loadLocalMasterKey()
                return self.nextStep()
            }
            .recover(on: schedulers.main) { _ in
                // TODO[Registration] build in some retry logic, and differentiate
                // KBS errors (invalid PIN vs invalid credential, etc).
                return .value(.pinEntry)
            }
    }

    private func loadLocalMasterKey() {
        // TODO[Registration]: this should take a transaction and pass it to these.
        // The hex vs base64 different here is intentional.
        inMemoryState.regRecoveryPw = kbs.data(for: .registrationRecoveryPassword)?.base64EncodedString()
        inMemoryState.reglockToken = kbs.data(for: .registrationLock)?.hexadecimalString
    }

    // MARK: - KBS Auth Credential Candidates Pathway

    private func nextStepForKBSAuthCredentialCandidatesPath(
        kbsAuthCredentialCandidates: [KBSAuthCredential]
    ) -> Guarantee<RegistrationStep> {
        guard let e164 = persistedState.e164 else {
            // If we haven't entered a phone number but we have auth
            // credential candidates to check, enter it now.
            return .value(.phoneNumberEntry)
        }
        // Check the candidates.
        return Service.makeKBSAuthCheckRequest(
            e164: e164,
            candidateCredentials: kbsAuthCredentialCandidates,
            signalService: signalService,
            schedulers: schedulers
        ).then(on: schedulers.main) { [weak self] response in
            guard let self else {
                return .value(.showGenericError)
            }
            return self.handleKBSAuthCredentialCheckResponse(
                response,
                kbsAuthCredentialCandidates: kbsAuthCredentialCandidates,
                e164: e164
            )
        }
    }

    private func handleKBSAuthCredentialCheckResponse(
        _ response: RegistrationServiceResponses.KBSAuthCheckResponse?,
        kbsAuthCredentialCandidates: [KBSAuthCredential],
        e164: String
    ) -> Guarantee<RegistrationStep> {
        var matchedCredential: KBSAuthCredential?
        var credentialsToDelete = [KBSAuthCredential]()
        guard let response else {
            // TODO[Registration] build in some retry logic

            // If we failed to verify, wipe the candidates so we don't try again
            // and keep going.
            self.inMemoryState.kbsAuthCredentialCandidates = nil
            return self.nextStep()
        }
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
            return self.makeRegisterOrChangeNumberRequest(
                .sessionId(session.id),
                e164: session.e164,
                reglockToken: inMemoryState.reglockToken
            ).then(on: schedulers.main) { [weak self] response in
                guard let self = self else {
                    return .value(.showGenericError)
                }
                return self.handleCreateAccountResponseFromSession(response)
            }
        }

        if inMemoryState.needsToAskForDeviceTransfer {
            return .value(.transferSelection)
        }

        if let pendingCodeTransport = inMemoryState.pendingCodeTransport {
            // If we have pending transport and can send, send.
            if session.allowedToRequestCode {
                switch pendingCodeTransport {
                case .sms:
                    if let nextSMSDate = session.nextSMSDate, nextSMSDate <= dateProvider() {
                        return requestSessionCode(session: session, transport: pendingCodeTransport)
                    }
                case .voice:
                    if let nextCallDate = session.nextCallDate, nextCallDate <= dateProvider() {
                        return requestSessionCode(session: session, transport: pendingCodeTransport)
                    }
                }
            }
        } else if
            let lastCodeDate = session.lastCodeRequestDate,
            dateProvider().timeIntervalSince(lastCodeDate) <= Constants.codeResendTimeout
        {
            return .value(.verificationCodeEntry)
        }

        guard session.allowedToRequestCode else {
            // Check for challenges.
            switch session.requestedInformation.first {
            case .none:
                if session.hasUnknownChallengeRequiringAppUpdate {
                    inMemoryState.pendingCodeTransport = nil
                    return .value(.appUpdateBanner)
                } else {
                    // We want to reset the whole session.
                    self.resetSession()
                    return self.nextStep()
                }
            case .captcha:
                return .value(.captchaChallenge)
            case .pushChallenge:
                // TODO[Registration]: complete push challenge.
                return .value(.splash)
            }
        }

        if
            session.lastCodeRequestDate == nil,
            let nextSMSDate = session.nextSMSDate,
            nextSMSDate <= dateProvider()
        {
            // If we've _never_ asked for a code, issue a code
            // request right away.
            return requestSessionCode(session: session, transport: .sms)
        }

        // Otherwise we've sent a code, but it was a long time ago.
        // We don't want to automatically send a code, so take the user
        // to the phone number entry step from which they can tap to send
        // the code.
        return .value(.phoneNumberEntry)
    }

    private func processSession(_ session: RegistrationSession?) {
        if session?.verified == true {
            // Any verified session is good and we should keep it.
            inMemoryState.session = session
            return
        }
        if session?.nextVerificationAttempt == nil {
            // If we can't ever submit a verification code,
            // this session is useless.
            resetSession()
            return
        }
        inMemoryState.session = session
    }

    private func resetSession() {
        inMemoryState.session = nil
        inMemoryState.pendingCodeTransport = nil
        // Force the user to enter an e164 again
        // when making a new session.
        inMemoryState.hasEnteredE164 = false
        // TODO[Registration]: update the name of this method;
        // its used when a session completes successfully but also
        // when we invalidate one.
        self.sessionManager.completeSession()
    }

    private func handleCreateAccountResponseFromSession(
        _ response: Service.AccountResponse
    ) -> Guarantee<RegistrationStep> {
        switch response {
        case .success(let identityResponse):
            // We can clear the session now!
            sessionManager.completeSession()
            inMemoryState.session = nil
            db.write { tx in
                updatePersistedState(tx) {
                    $0.accountIdentity = identityResponse
                }
            }
            // Should take us to the profile setup flow since
            // the identity response is set.
            return nextStep()
        case .reglockFailure(let reglockFailure):
            // We need the user to enter their PIN so we can get through reglock.
            // We might have it already! So we set up the state we need (the kbs credential)
            // and go to the next step which should look at the state and take us to the right place.
            db.write { tx in
                kbsAuthCredentialStore.storeAuthCredentialForCurrentUsername(reglockFailure.kbsAuthCredential, tx)
            }
            self.inMemoryState.kbsAuthCredential = reglockFailure.kbsAuthCredential
            return nextStep()

        case .rejectedVerificationMethod:
            // The session is invalid; we have to wipe it and potentially start again.
            resetSession()
            return nextStep()

        case .retryAfter:
            // TODO[Registration] handle retries, possibly automatically if short enough.
            return .value(.showGenericError)
        case .deviceTransferPossible:
            inMemoryState.needsToAskForDeviceTransfer = true
            return .value(.transferSelection)
        case .genericError:
            return .value(.showGenericError)
        }
    }

    private func startSession(
        e164: String
    ) -> Guarantee<RegistrationStep> {
        return pushRegistrationManager.requestPushToken()
            .then(on: schedulers.sharedBackground) { [weak self] apnsToken -> Guarantee<RegistrationStep> in
                guard let strongSelf = self else {
                    return .value(.showGenericError)
                }
                return strongSelf.sessionManager.beginOrRestoreSession(
                    e164: e164,
                    apnsToken: apnsToken
                ).then(on: strongSelf.schedulers.main) { [weak self] response -> Guarantee<RegistrationStep> in
                    guard let strongSelf = self else {
                        return .value(.showGenericError)
                    }
                    switch response {
                    case .success(let session):
                        strongSelf.processSession(session)
                        return strongSelf.nextStep()
                    case .invalidArgument:
                        // TODO[Registration] populate error state for phone number entry.
                        return .value(.phoneNumberEntry)
                    case .retryAfter:
                        // TODO[Registration] handle retries, possibly automatically if short enough.
                        return .value(.phoneNumberEntry)
                    case .genericError:
                        return .value(.showGenericError)
                    }
                }
            }
    }

    private func requestSessionCode(
        session: RegistrationSession,
        transport: Registration.CodeTransport
    ) -> Guarantee<RegistrationStep> {
        return sessionManager.requestVerificationCode(
            for: session,
            transport: transport
        ).then(on: schedulers.main) { [weak self] (result: Registration.UpdateSessionResponse) -> Guarantee<RegistrationStep> in
            guard let self else {
                return .value(.showGenericError)
            }
            switch result {
            case
                    .success(let session),
                    .invalidArgument(let session),
                    .retryAfterTimeout(let session):
                self.inMemoryState.pendingCodeTransport = nil
                // TODO[Registration] handle invalid e164 differently to show error
                self.processSession(session)
                return self.nextStep()
            case .challengeRequired(let session):
                // Don't clear any pending code transport, so we resend once
                // the user completes the challenge.
                self.processSession(session)
                return self.nextStep()
            case .invalidSession:
                self.inMemoryState.pendingCodeTransport = nil
                self.resetSession()
                return self.nextStep()
            case .serverFailure(let failureResponse):
                self.inMemoryState.pendingCodeTransport = nil
                if failureResponse.isPermanent {
                    // TODO[Registration] show something special here.
                    return .value(.showGenericError)
                } else {
                    // TODO[Registration] show some particular error here.
                    return .value(.showGenericError)
                }
            case .genericError:
                self.inMemoryState.pendingCodeTransport = nil
                return .value(.showGenericError)
            }
        }
    }

    private func submitCaptchaChallengeFulfillment(
        session: RegistrationSession,
        token: String
    ) -> Guarantee<RegistrationStep> {
        return sessionManager.fulfillChallenge(
            for: session,
            fulfillment: .captcha(token)
        ).then(on: schedulers.main) { [weak self] (result: Registration.UpdateSessionResponse) -> Guarantee<RegistrationStep> in
            guard let self else {
                return .value(.showGenericError)
            }
            switch result {
            case
                    .success(let session),
                    .challengeRequired(let session),
                    .invalidArgument(let session),
                    .retryAfterTimeout(let session):
                // TODO[Registration] handle invalid captcha token differently to show error
                self.processSession(session)
                return self.nextStep()
            case .invalidSession:
                self.resetSession()
                return self.nextStep()
            case .serverFailure(let failureResponse):
                if failureResponse.isPermanent {
                    // TODO[Registration] show something special here.
                    return .value(.showGenericError)
                } else {
                    // TODO[Registration] show some particular error here.
                    return .value(.showGenericError)
                }
            case .genericError:
                return .value(.showGenericError)
            }
        }
    }

    private func submitSessionCode(
        session: RegistrationSession,
        code: String
    ) -> Guarantee<RegistrationStep> {
        return sessionManager.submitVerificationCode(
            for: session,
            code: code
        ).then(on: schedulers.main) { [weak self] (result: Registration.UpdateSessionResponse) -> Guarantee<RegistrationStep> in
            guard let self else {
                return .value(.showGenericError)
            }
            switch result {
            case
                    .success(let session),
                    .challengeRequired(let session),
                    .invalidArgument(let session),
                    .retryAfterTimeout(let session):
                // TODO[Registration] handle invalid code differently to show error
                // than other errors.
                self.processSession(session)
                return self.nextStep()
            case .invalidSession:
                self.resetSession()
                return self.nextStep()
            case .serverFailure(let failureResponse):
                if failureResponse.isPermanent {
                    // TODO[Registration] show something special here.
                    return .value(.showGenericError)
                } else {
                    // TODO[Registration] show some particular error here.
                    return .value(.showGenericError)
                }
            case .genericError:
                return .value(.showGenericError)
            }
        }
    }

    // MARK: - Profile Setup Pathway

    /// Returns the next step the user needs to go through _after_ the actual account
    /// registration or change number is complete (e.g. profile setup).
    private func nextStepForProfileSetup(
        _ accountIdentity: RegistrationServiceResponses.AccountIdentityResponse
    ) -> Guarantee<RegistrationStep> {
        if inMemoryState.pinFromUser == nil {
            // Need to enter the pin.
            if inMemoryState.pinFromDisk == nil {
                // TODO[Registration] this should specify that its first time
                // pin entry
                return .value(.pinEntry)
            } else {
                // TODO[Registration] this should specify that its just pin
                // confirmation for a PIN we already know.
                return .value(.pinEntry)
            }
        }
        if !tsAccountManager.hasDefinedIsDiscoverableByPhoneNumber() {
            return .value(.phoneNumberDiscoverability)
        }
        if !profileManager.hasProfileName {
            return .value(.setupProfile)
        }
        // TODO[Registration]: at this point we should write all external state
        // as needed (e.g. to TSAccountManager) and should back up to KBS.
        return .value(.done)
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
        e164: String,
        reglockToken: String?
    ) -> Guarantee<Service.AccountResponse> {
        switch persistedState.mode {
        case .registering, .reRegistering:
            // TODO[Registration]: actually pull in this information.
            // Check OWSRequestFactory.m for where we made this before.
            let accountAttributes = RegistrationRequestFactory.AccountAttributes(
                authKey: "",
                isManualMessageFetchEnabled: false,
                registrationId: 0,
                pniRegistrationId: 0,
                unidentifiedAccessKey: nil,
                unrestrictedUnidentifiedAccess: false,
                registrationLockToken: reglockToken,
                encryptedDeviceName: nil,
                discoverableByPhoneNumber: false,
                canReceiveGiftBadges: false
            )
            return Service.makeCreateAccountRequest(
                method,
                e164: e164,
                accountAttributes: accountAttributes,
                skipDeviceTransfer: shouldSkipDeviceTransfer(),
                signalService: signalService,
                schedulers: schedulers
            )

        case .changingNumber:
            return Service.makeChangeNumberRequest(
                method,
                e164: e164,
                reglockToken: reglockToken,
                signalService: signalService,
                schedulers: schedulers
            )
        }
    }

    // MARK: - Constants

    enum Constants {
        static let persistedStateKey = "state"

        /// If we last sent a verification code more than this long ago,
        /// we'd default to letting the user send a new code by going
        /// back to the phone number entry screen. This is so we
        /// avoid sending too many or too few SMS codes.
        static let codeResendTimeout: TimeInterval = 60 * 20 // 20 mins
    }
}
