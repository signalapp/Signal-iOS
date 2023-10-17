//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Contacts
import Foundation
import LibSignalClient
import SignalServiceKit

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

    public func switchToSecondaryDeviceLinking() -> Bool {
        Logger.info("")

        switch mode {
        case .registering:
            if persistedState.hasShownSplash {
                // Once we are past the splash, no going back.
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

        guard canExitRegistrationFlow() else {
            Logger.warn("User can't exit registration now")
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
            self.db.write { tx in
                self.wipePersistedState(tx)
            }
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
                return .value(.registrationSplash)
            }
            return self.nextStep(pathway: self.getPathway())
        }
    }

    public func continueFromSplash() -> Guarantee<RegistrationStep> {
        Logger.info("")

        db.write { tx in
            self.updatePersistedState(tx) {
                $0.hasShownSplash = true
            }
        }
        return nextStep()
    }

    public func requestPermissions() -> Guarantee<RegistrationStep> {
        Logger.info("")

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
                    return .value(.registrationSplash)
                }
                self.inMemoryState.needsSomePermissions = false
                return self.nextStep()
            }
    }

    public func submitProspectiveChangeNumberE164(_ e164: E164) -> Guarantee<RegistrationStep> {
        Logger.info("")
        self.inMemoryState.changeNumberProspectiveE164 = e164
        return nextStep()
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
                    .svrAuthCredential,
                    .svrAuthCredentialCandidates,
                    .registrationRecoveryPassword,
                    .profileSetup:
                break
            }
        }
        inMemoryState.hasEnteredE164 = true

        return nextStep()
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
        return nextStep()
    }

    public func requestSMSCode() -> Guarantee<RegistrationStep> {
        Logger.info("")
        switch getPathway() {
        case
                .opening,
                .registrationRecoveryPassword,
                .svrAuthCredential,
                .svrAuthCredentialCandidates,
                .profileSetup:
            owsFailBeta("Shouldn't be resending SMS from non session paths.")
            return nextStep()
        case .session:
            inMemoryState.pendingCodeTransport = .sms
            return nextStep()
        }
    }

    public func requestVoiceCode() -> Guarantee<RegistrationStep> {
        Logger.info("")
        switch getPathway() {
        case
                .opening,
                .registrationRecoveryPassword,
                .svrAuthCredential,
                .svrAuthCredentialCandidates,
                .profileSetup:
            owsFailBeta("Shouldn't be sending voice code from non session paths.")
            return nextStep()
        case .session:
            inMemoryState.pendingCodeTransport = .voice
            return nextStep()
        }
    }

    public func submitVerificationCode(_ code: String) -> Guarantee<RegistrationStep> {
        Logger.info("")
        switch getPathway() {
        case
                .opening,
                .registrationRecoveryPassword,
                .svrAuthCredential,
                .svrAuthCredentialCandidates,
                .profileSetup:
            owsFailBeta("Shouldn't be submitting verification code from non session paths.")
            return nextStep()
        case .session(let session):
            return submitSessionCode(session: session, code: code)
        }
    }

    public func submitCaptcha(_ token: String) -> Guarantee<RegistrationStep> {
        Logger.info("")
        switch getPathway() {
        case
                .opening,
                .registrationRecoveryPassword,
                .svrAuthCredential,
                .svrAuthCredentialCandidates,
                .profileSetup:
            owsFailBeta("Shouldn't be submitting captcha from non session paths.")
            return nextStep()
        case .session(let session):
            return submit(challengeFulfillment: .captcha(token), for: session)
        }
    }

    public func setPINCodeForConfirmation(_ blob: RegistrationPinConfirmationBlob) -> Guarantee<RegistrationStep> {
        Logger.info("")
        inMemoryState.unconfirmedPinBlob = blob
        return nextStep()
    }

    public func resetUnconfirmedPINCode() -> Guarantee<RegistrationStep> {
        Logger.info("")
        inMemoryState.unconfirmedPinBlob = nil
        return nextStep()
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
        case .opening, .svrAuthCredential, .svrAuthCredentialCandidates, .profileSetup, .session:
            // We aren't checking against any local state, rely on the request.
            break
        }
        self.inMemoryState.pinFromUser = code
        // Individual pathway's steps should handle whatever needs to be done with the pin,
        // depending on the current pathway.
        return nextStep()
    }

    public func skipPINCode() -> Guarantee<RegistrationStep> {
        Logger.info("")
        let shouldGiveUpTryingToRestoreWithSVR: Bool = {
            switch getPathway() {
            case
                    .opening,
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
        return nextStep()
    }

    public func skipDeviceTransfer() -> Guarantee<RegistrationStep> {
        Logger.info("")
        db.write { tx in
            updatePersistedState(tx) {
                $0.hasDeclinedTransfer = true
            }
        }
        return self.nextStep()
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

        return self.nextStep()
    }

    public func setProfileInfo(
        givenName: String,
        familyName: String?,
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

        return self.nextStep()
    }

    public func acknowledgeReglockTimeout() -> AcknowledgeReglockResult {
        Logger.info("")

        switch reglockTimeoutAcknowledgeAction {
        case .resetPhoneNumber:
            db.write { transaction in
                self.resetSession(transaction)
                self.updatePersistedState(transaction) { $0.e164 = nil }
            }
            return .restartRegistration(nextStep())
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
        // A really old user might be on v1 2fa; they have a PIN,
        // but no SVR backups. We will encourage backing up
        // to SVR but the user may skip it.
        var isV12faUser: Bool = false
        var unconfirmedPinBlob: RegistrationPinConfirmationBlob?

        // When we try to register, if we get a response from the server
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

        // Every time we go through registration, we should back up our SVR master
        // secret's random bytes to SVR. Its safer to do this more than it is to do
        // it less, so keeping this state in memory.
        var hasBackedUpToSVR = false
        var didSkipSVRBackup = false
        var shouldBackUpToSVR: Bool {
            return hasBackedUpToSVR.negated && didSkipSVRBackup.negated
        }

        // OWS2FAManager state
        // If we are re-registering or changing number and
        // reglock was enabled, we should enable it again when done.
        var wasReglockEnabledBeforeStarting = false
        var hasSetReglock = false

        var pendingProfileInfo: (givenName: String, familyName: String?, avatarData: Data?)?

        // TSAccountManager state
        var registrationId: UInt32!
        var pniRegistrationId: UInt32!
        var isManualMessageFetchEnabled = false
        var phoneNumberDiscoverability: PhoneNumberDiscoverability?

        // OWSProfileManager state
        var profileKey: OWSAES256Key!
        var udAccessKey: SMKUDAccessKey!
        var allowUnrestrictedUD = false
        var hasProfileName = false

        // Once we have our SVR master key locally,
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
    internal struct PersistedState: Codable {
        /// We only ever want to show the splash once.
        var hasShownSplash = false
        var shouldSkipRegistrationSplash = false

        /// When re-registering, just before completing the actual create account
        /// request, we wipe our local state for re-registration. We only do this once,
        /// and once we do, there is no turning back, because we will have wiped
        /// state thats needed to use the app outside of registration.
        var hasResetForReRegistration = false

        /// The e164 the user has entered for this attempt at registration.
        /// Initially the e164 in the UI may be pre-populated (e.g. in re-reg)
        /// but this value is not set until the user accepts it or enters their own value.
        var e164: E164?

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

        /// After atomic account creation, we include push tokens (if any) in
        /// the account creation request, and this field is useless. We set it
        /// to true immediately.
        /// Before atomic account creation, we would have to follow up after
        /// account creation and sync push tokens with the server. This
        /// tracked whether we had done that (or discovered we have no token).
        var legacy_didSyncPushTokens: Bool = false

        /// Prior to the introduction of atomic account creation, we would
        /// create and sync signed as well as one time prekeys as a follow-up
        /// to account creation. Users may still have local persisted state
        /// from prior to atomic account creation.
        var legacy_didCreateAllPrekeys: Bool = false

        /// After registration is complete, we generate and sync
        /// one time prekeys (signed prekeys are included in the registration
        /// request). We do not proceed until this succeeds.
        var shouldRefreshOneTimePreKeys: Bool?
        var didRefreshOneTimePreKeys: Bool?

        /// When we try and register, the server gives us an error if its possible
        /// to execute a device-to-device transfer. The user can decline; if they
        /// do, this will get set so we try force a re-register.
        /// Note if we are re-registering on the same primary device (based on mode),
        /// we ignore this field and always skip asking for device transfer.
        var hasDeclinedTransfer: Bool = false

        init() {}

        enum CodingKeys: String, CodingKey {
            case hasShownSplash
            case shouldSkipRegistrationSplash
            case hasResetForReRegistration
            case e164
            case e164WithKnownReglockEnabled
            case numLocalPinGuesses
            case hasSkippedPinEntry
            // Legacy naming
            case hasGivenUpTryingToRestoreWithSVR = "hasGivenUpTryingToRestoreWithKBS"
            case sessionState
            case accountIdentity
            case legacy_didSyncPushTokens = "didSyncPushTokens"
            case legacy_didCreateAllPrekeys = "didSyncPrekeys"
            case shouldRefreshOneTimePreKeys
            case didRefreshOneTimePreKeys
            case hasDeclinedTransfer
        }
    }

    private var _persistedState: PersistedState?
    private var persistedState: PersistedState { return _persistedState ?? PersistedState() }

    private func updatePersistedState(_ transaction: DBWriteTransaction, _ update: (inout PersistedState) -> Void) {
        var state: PersistedState = persistedState
        update(&state)
        // Field is optional for backwards compatibility; write
        // into it so we can eventually make it required.
        if state.shouldRefreshOneTimePreKeys == nil {
            state.shouldRefreshOneTimePreKeys = false
        }
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
            self.loadLocalMasterKeyAndUpdateState(tx)
            inMemoryState.pinFromDisk = deps.ows2FAManager.pinCode(tx)
            if
                inMemoryState.pinFromDisk != nil,
                deps.svr.hasBackedUpMasterKey(transaction: tx).negated
            {
                // If we had a pin but no SVR backups, we must be a v1 2fa user.
                inMemoryState.isV12faUser = true
            }

            loadSVRAuthCredentialCandidates(tx)
            inMemoryState.isManualMessageFetchEnabled = deps.tsAccountManager.isManualMessageFetchEnabled(tx: tx)
            inMemoryState.registrationId = deps.tsAccountManager.getOrGenerateAciRegistrationId(tx: tx)
            inMemoryState.pniRegistrationId = deps.tsAccountManager.getOrGeneratePniRegistrationId(tx: tx)

            inMemoryState.allowUnrestrictedUD = deps.udManager.shouldAllowUnrestrictedAccessLocal(transaction: tx)

            inMemoryState.wasReglockEnabledBeforeStarting = deps.ows2FAManager.isReglockEnabled(tx)
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
                return self.restoreStateIfNeeded()
            }
        case .registering, .changingNumber:
            break
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
        Logger.info("")

        func finalizeRegistration(_ tx: DBWriteTransaction) {
            if inMemoryState.hasBackedUpToSVR || inMemoryState.didHaveSVRBackupsPriorToReg {
                // No need to show the experience if we made the pin
                // and backed up.
                deps.experienceManager.clearIntroducingPinsExperience(tx)
            }

            deps.registrationStateChangeManager.didRegisterPrimary(
                e164: accountIdentity.e164,
                aci: accountIdentity.aci,
                pni: accountIdentity.pni,
                authToken: accountIdentity.authPassword,
                tx: tx
            )
            deps.tsAccountManager.setIsManualMessageFetchEnabled(inMemoryState.isManualMessageFetchEnabled, tx: tx)
        }

        func setupContactsAndFinish() -> Guarantee<RegistrationStep> {
            // Start syncing system contacts now that we have set up tsAccountManager.
            deps.contactsManager.fetchSystemContactsOnceIfAlreadyAuthorized()

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
        Logger.info("")

        return updateAccountAttributes(accountIdentity)
            .then(on: schedulers.main) { [weak self] error -> Guarantee<RegistrationStep> in
                guard let self else {
                    return unretainedSelfError()
                }
                if
                    let error,
                    error.isNetworkFailureOrTimeout,
                    retriesLeft > 0
                {
                    return self.updateAccountAttributesAndFinish(
                        accountIdentity: accountIdentity,
                        retriesLeft: retriesLeft - 1
                    )
                }
                // If we have a deregistration erorr, it doesn't matter. we are finished
                // and cleaning up anyway, the main app will discover the issue.
                if let error {
                    Logger.warn("Failed account attributes update, finishing registration anyway: \(error)")
                }
                // We are done! Wipe everything
                self.inMemoryState = InMemoryState()
                self.db.write { tx in
                    self.wipePersistedState(tx)
                }
                // Do any storage service backups we have pending.
                self.deps.storageServiceManager.backupPendingChanges(authedAccount: accountIdentity.authedAccount)
                return .value(.done)
            }
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
            case .registrationRecoveryPassword: return "registrationRecoveryPassword"
            case .svrAuthCredential: return "svrAuthCredential"
            case .svrAuthCredentialCandidates: return "svrAuthCredentialCandidates"
            case .session: return "session"
            case .profileSetup: return "profileSetup"
            }
        }
    }

    private func getPathway() -> Pathway {
        if splashStepToShow() != nil || inMemoryState.needsSomePermissions {
            return .opening
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

    private func nextStep(pathway: Pathway) -> Guarantee<RegistrationStep> {
        Logger.info("Going to next step for \(pathway.logSafeString) pathway")

        switch pathway {
        case .opening:
            return nextStepForOpeningPath()
        case .registrationRecoveryPassword(let password):
            return nextStepForRegRecoveryPasswordPath(regRecoveryPw: password)
        case .svrAuthCredential(let credential):
            return nextStepForSVRAuthCredentialPath(svrAuthCredential: credential)
        case .svrAuthCredentialCandidates(let svr2Candidates):
            return nextStepForSVRAuthCredentialCandidatesPath(
                svr2AuthCredentialCandidates: svr2Candidates
            )
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
    private func nextStepForRegRecoveryPasswordPath(regRecoveryPw: String) -> Guarantee<RegistrationStep> {
        // We need a phone number to proceed; ask the user if unavailable.
        guard let e164 = persistedState.e164 else {
            return .value(.phoneNumberEntry(phoneNumberEntryState()))
        }

        guard let pinFromUser = inMemoryState.pinFromUser else {
            // We need the user to confirm their pin.
            return .value(.pinEntry(RegistrationPinState(
                // We can skip which will stop trying to use reg recovery.
                operation: .enteringExistingPin(skippability: .canSkip, remainingAttempts: nil),
                error: nil,
                contactSupportMode: self.contactSupportRegistrationPINMode(),
                exitConfiguration: pinCodeEntryExitConfiguration()
            )))
        }

        if
            let pinFromDisk = inMemoryState.pinFromDisk,
            pinFromDisk != pinFromUser
        {
            Logger.warn("PIN mismatch; should be prevented at submission time.")
            return .value(.pinEntry(RegistrationPinState(
                operation: .enteringExistingPin(skippability: .canSkip, remainingAttempts: nil),
                error: .wrongPin(wrongPin: pinFromUser),
                contactSupportMode: self.contactSupportRegistrationPINMode(),
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
        let twoFAMode = self.attributes2FAMode(e164: e164)
        return self.makeRegisterOrChangeNumberRequest(
            .recoveryPassword(regRecoveryPw),
            e164: e164,
            twoFAMode: twoFAMode,
            responseHandler: { [weak self] accountResponse in
                return self?.handleCreateAccountResponseFromRegRecoveryPassword(
                    accountResponse,
                    regRecoveryPw: regRecoveryPw,
                    e164: e164,
                    pinFromUser: pinFromUser,
                    twoFaModeUsedInRequest: twoFAMode,
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
        twoFaModeUsedInRequest: AccountAttributes.TwoFactorAuthMode,
        retriesLeft: Int
    ) -> Guarantee<RegistrationStep> {
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
            return nextStep()

        case .reglockFailure:
            switch twoFaModeUsedInRequest {
            case .none, .v1:
                // We failed reglock because we didn't even try it!
                // Try again with reglock included this time.
                db.write { tx in
                    self.updatePersistedState(tx) {
                        $0.e164WithKnownReglockEnabled = e164
                    }
                }
                return nextStep()
            case .v2:
                // We tried our reglock token and it failed.
                switch self.mode {
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
                return startSession(e164: e164)
            }

        case .rejectedVerificationMethod:
            // The reg recovery password was wrong. This can happen for two reasons:
            // 1) We have the wrong SVR master key
            // 2) We have been reglock challenged, forcing us to re-register via session
            // If it were just the former case, we'd wipe our known-wrong SVR master key.
            // But the latter case means we want to go through session path registration,
            // and re-upload our local SVR master secret, so we don't want to wipe it.
            // (If we wiped it and our SVR server guesses were consumed by the reglock-challenger,
            // we'd be outta luck and have no way to recover).
            db.write { tx in
                // We do want to clear out any credentials permanently; we know we
                // have to use the session path so credentials aren't helpful.
                if let svr2Credential = inMemoryState.svrAuthCredential {
                    deps.svrAuthCredentialStore.deleteInvalidCredentials([svr2Credential], tx)
                }
            }
            // Wipe our in memory SVR state; its now useless.
            wipeInMemoryStateToPreventSVRPathAttempts()

            // Now we have to start a session; its the only way to recover.
            return self.startSession(e164: e164)

        case .retryAfter(let timeInterval):
            if timeInterval < Constants.autoRetryInterval {
                return Guarantee
                    .after(on: self.schedulers.global(), seconds: timeInterval)
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
            // If we get a long timeout, just give up and fall back to the session
            // path. Reg recovery password based recovery is best effort anyway.
            // Besides since this is always our first attempt at registering,
            // this lockout should never happen.
            Logger.error("Rate limited when registering via recovery password; falling back to session.")
            wipeInMemoryStateToPreventSVRPathAttempts()
            return self.startSession(e164: e164)

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

    private func loadSVRAuthCredentialCandidates(_ tx: DBReadTransaction) {
        let svr2AuthCredentialCandidates: [SVR2AuthCredential] = deps.svrAuthCredentialStore.getAuthCredentials(tx)
        if svr2AuthCredentialCandidates.isEmpty.negated {
            inMemoryState.svr2AuthCredentialCandidates = svr2AuthCredentialCandidates
        }
    }

    private func wipeInMemoryStateToPreventSVRPathAttempts() {
        inMemoryState.regRecoveryPw = nil
        inMemoryState.shouldRestoreSVRMasterKeyAfterRegistration = true
        // Wiping auth credential state too; if we failed with the local
        // SVR master key we don't expect the backed up master key to work
        // either so we shouldn't bother trying.
        inMemoryState.svrAuthCredential = nil
        inMemoryState.svr2AuthCredentialCandidates = nil
    }

    // MARK: - SVR Auth Credential Pathway

    /// If we don't have the SVR master key saved locally but we do have a SVR auth credential,
    /// we can use it to talk to the SVR server and, together with the user-entered PIN, recover the
    /// full SVR master key. Then we use the Registration Recovery Password registration flow.
    /// (If we had the SVR master key saved locally to begin with, we would have just used it right away.)
    private func nextStepForSVRAuthCredentialPath(
        svrAuthCredential: SVRAuthCredential
    ) -> Guarantee<RegistrationStep> {
        guard let pin = inMemoryState.pinFromUser else {
            // We don't have a pin at all, ask the user for it.
            return .value(.pinEntry(RegistrationPinState(
                operation: .enteringExistingPin(skippability: .canSkip, remainingAttempts: nil),
                error: nil,
                contactSupportMode: self.contactSupportRegistrationPINMode(),
                exitConfiguration: pinCodeEntryExitConfiguration()
            )))
        }

        return restoreSVRMasterSecretForAuthCredentialPath(
            pin: pin,
            credential: svrAuthCredential
        )
    }

    private func restoreSVRMasterSecretForAuthCredentialPath(
        pin: String,
        credential: SVRAuthCredential,
        retriesLeft: Int = Constants.networkErrorRetries
    ) -> Guarantee<RegistrationStep> {
        deps.svr.restoreKeys(pin: pin, authMethod: .svrAuth(credential, backup: nil))
            .then(on: schedulers.main) { [weak self] result -> Guarantee<RegistrationStep> in
                guard let self = self else {
                    return unretainedSelfError()
                }
                switch result {
                case .success:
                    self.db.write { self.loadLocalMasterKeyAndUpdateState($0) }
                    return self.nextStep()
                case let .invalidPin(remainingAttempts):
                    return .value(.pinEntry(RegistrationPinState(
                        operation: .enteringExistingPin(
                            skippability: .canSkip,
                            remainingAttempts: UInt(remainingAttempts)
                        ),
                        error: .wrongPin(wrongPin: pin),
                        contactSupportMode: self.contactSupportRegistrationPINMode(),
                        exitConfiguration: self.pinCodeEntryExitConfiguration()
                    )))
                case .backupMissing:
                    // If we are unable to talk to SVR, it got wiped and we can't
                    // recover. Give it all up and wipe our SVR info.
                    self.wipeInMemoryStateToPreventSVRPathAttempts()
                    self.inMemoryState.pinFromUser = nil
                    self.db.write { tx in
                        self.updatePersistedState(tx) {
                            $0.hasGivenUpTryingToRestoreWithSVR = true
                        }
                    }
                    return .value(.pinAttemptsExhaustedWithoutReglock(
                        .init(mode: .restoringRegistrationRecoveryPassword)
                    ))

                case .networkError:
                    if retriesLeft > 0 {
                        return self.restoreSVRMasterSecretForAuthCredentialPath(
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

    private func loadLocalMasterKeyAndUpdateState(_ tx: DBWriteTransaction) {
        let regRecoveryPw = deps.svr.data(
            for: .registrationRecoveryPassword,
            transaction: tx
        )?.canonicalStringRepresentation
        inMemoryState.regRecoveryPw = regRecoveryPw
        if regRecoveryPw != nil {
            updatePersistedState(tx) { $0.shouldSkipRegistrationSplash = true }
        }
        inMemoryState.reglockToken = deps.svr.data(
            for: .registrationLock,
            transaction: tx
        )?.canonicalStringRepresentation
        // If we have a local master key, theres no need to restore after registration.
        // (we will still back up though)
        inMemoryState.shouldRestoreSVRMasterKeyAfterRegistration = !deps.svr.hasMasterKey(transaction: tx)
        inMemoryState.didHaveSVRBackupsPriorToReg = deps.svr.hasBackedUpMasterKey(transaction: tx)
    }

    // MARK: - SVR Auth Credential Candidates Pathway

    private func nextStepForSVRAuthCredentialCandidatesPath(
        svr2AuthCredentialCandidates: [SVR2AuthCredential]
    ) -> Guarantee<RegistrationStep> {
        guard let e164 = persistedState.e164 else {
            // If we haven't entered a phone number but we have auth
            // credential candidates to check, enter it now.
            return .value(.phoneNumberEntry(phoneNumberEntryState()))
        }
        return makeSVR2AuthCredentialCheckRequest(
            svr2AuthCredentialCandidates: svr2AuthCredentialCandidates,
            e164: e164
        )
    }

    private func makeSVR2AuthCredentialCheckRequest(
        svr2AuthCredentialCandidates: [SVR2AuthCredential],
        e164: E164,
        retriesLeft: Int = Constants.networkErrorRetries
    ) -> Guarantee<RegistrationStep> {
        return Service.makeSVR2AuthCheckRequest(
            e164: e164,
            candidateCredentials: svr2AuthCredentialCandidates,
            signalService: deps.signalService,
            schedulers: schedulers
        ).then(on: schedulers.main) { [weak self] response in
            guard let self else {
                return unretainedSelfError()
            }
            return self.handleSVR2AuthCredentialCheckResponse(
                response,
                svr2AuthCredentialCandidates: svr2AuthCredentialCandidates,
                e164: e164,
                retriesLeft: retriesLeft
            )
        }
    }

    private func handleSVR2AuthCredentialCheckResponse(
        _ response: Service.SVR2AuthCheckResponse,
        svr2AuthCredentialCandidates: [SVR2AuthCredential],
        e164: E164,
        retriesLeft: Int
    ) -> Guarantee<RegistrationStep> {
        var matchedCredential: SVR2AuthCredential?
        var credentialsToDelete = [SVR2AuthCredential]()
        switch response {
        case .networkError:
            if retriesLeft > 0 {
                return makeSVR2AuthCredentialCheckRequest(
                    svr2AuthCredentialCandidates: svr2AuthCredentialCandidates,
                    e164: e164,
                    retriesLeft: retriesLeft - 1
                )
            }
            self.inMemoryState.svr2AuthCredentialCandidates = nil
            return self.nextStep()
        case .genericError:
            // If we failed to verify, wipe the candidates so we don't try again
            // and keep going.
            self.inMemoryState.svr2AuthCredentialCandidates = nil
            return self.nextStep()
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
        return self.nextStep()
    }

    // MARK: - RegistrationSession Pathway

    private func nextStepForSessionPath(_ session: RegistrationSession) -> Guarantee<RegistrationStep> {
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
                return self.nextStep()
            }
            if let pinFromUser = inMemoryState.pinFromUser {
                return restoreSVRMasterSecretForSessionPathReglock(
                    session: session,
                    pin: pinFromUser,
                    svrAuthCredential: svrAuthCredential,
                    reglockExpirationDate: reglockExpirationDate
                )
            } else {
                return .value(.pinEntry(RegistrationPinState(
                    operation: .enteringExistingPin(
                        skippability: .unskippable,
                        remainingAttempts: nil
                    ),
                    error: .none,
                    contactSupportMode: self.contactSupportRegistrationPINMode(),
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
                return attemptToFulfillAvailableChallengesWaitingIfNeeded(for: session)
            }

            // If we have pending transport and can send, send.
            switch pendingCodeTransport {
            case .sms:
                if let nextSMSDate = session.nextSMSDate, nextSMSDate <= deps.dateProvider() {
                    return requestSessionCode(session: session, transport: pendingCodeTransport)
                } else {
                    // Inability to send puts on the verification entry screen, so the
                    // user can try the alternate transport manually.
                    return .value(.verificationCodeEntry(self.verificationCodeEntryState(
                        session: session,
                        validationError: .smsResendTimeout
                    )))
                }
            case .voice:
                if let nextCallDate = session.nextCallDate, nextCallDate <= deps.dateProvider() {
                    return requestSessionCode(session: session, transport: pendingCodeTransport)
                } else {
                    // Inability to send puts on the verification entry screen, so the
                    // user can try the alternate transport manually.
                    return .value(.verificationCodeEntry(self.verificationCodeEntryState(
                        session: session,
                        validationError: .voiceResendTimeout
                    )))
                }
            }
        }

        if shouldShowCodeEntryStep {
            return .value(.verificationCodeEntry(self.verificationCodeEntryState(
                session: session,
                validationError: codeEntryValidationError
            )))
        }

        // Otherwise we have no code awaiting submission and aren't
        // trying to send one yet, so just go to phone number entry.
        return .value(.phoneNumberEntry(phoneNumberEntryState()))
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

    private func makeRegisterOrChangeNumberRequestFromSession(
        _ session: RegistrationSession,
        retriesLeft: Int = Constants.networkErrorRetries
    ) -> Guarantee<RegistrationStep> {
        if
            let timeoutDate = persistedState.sessionState?.createAccountTimeout,
            deps.dateProvider() < timeoutDate
        {
            return .value(.phoneNumberEntry(phoneNumberEntryState(
                validationError: .rateLimited(.init(
                    expiration: timeoutDate,
                    e164: session.e164
                ))
            )))
        }
        let twoFAMode = self.attributes2FAMode(e164: session.e164)
        return self.makeRegisterOrChangeNumberRequest(
            .sessionId(session.id),
            e164: session.e164,
            twoFAMode: twoFAMode,
            responseHandler: { [weak self] accountResponse in
                return self?.handleCreateAccountResponseFromSession(
                    accountResponse,
                    sessionFromBeforeRequest: session,
                    twoFAModeUsedInRequest: twoFAMode,
                    retriesLeft: retriesLeft
                ) ?? unretainedSelfError()
            }
        )
    }

    private func handleCreateAccountResponseFromSession(
        _ response: AccountResponse,
        sessionFromBeforeRequest: RegistrationSession,
        twoFAModeUsedInRequest: AccountAttributes.TwoFactorAuthMode,
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
                return nextStep()
            }
            // We need the user to enter their PIN so we can get through reglock.
            // So we set up the state we need (the SVR credential)
            // and go to the next step which should look at the state and take us to the right place.
            switch twoFAModeUsedInRequest {
            case .v2:
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
                return nextStep()

            case .none, .v1:
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
                return nextStep()
            }

        case .rejectedVerificationMethod:
            // The session is invalid; we have to wipe it and potentially start again.
            db.write { self.resetSession($0) }
            return nextStep()

        case .retryAfter(let timeInterval):
            if timeInterval < Constants.autoRetryInterval {
                return Guarantee
                    .after(on: schedulers.global(), seconds: timeInterval)
                    .then(on: schedulers.sync) { [weak self] in
                        guard let self else {
                            return unretainedSelfError()
                        }
                        return self.makeRegisterOrChangeNumberRequestFromSession(
                            sessionFromBeforeRequest
                        )
                    }
            }
            let timeoutDate = self.deps.dateProvider().addingTimeInterval(timeInterval)
            self.db.write { tx in
                self.updatePersistedSessionState(session: sessionFromBeforeRequest, tx) {
                    $0.createAccountTimeout = timeoutDate
                }
            }
            return nextStep()
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
            .then(on: schedulers.global()) { [weak self] tokenResult -> Guarantee<RegistrationStep> in
                guard let strongSelf = self else {
                    return unretainedSelfError()
                }
                let apnsToken: String?
                switch tokenResult {
                case .success(let tokens):
                    apnsToken = tokens.apnsToken
                case .pushUnsupported, .timeout, .genericError:
                    apnsToken = nil
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

                        return strongSelf.nextStep()
                    case .invalidArgument:
                        return .value(.phoneNumberEntry(strongSelf.phoneNumberEntryState(
                            validationError: .invalidNumber(.init(invalidE164: e164))
                        )))
                    case .retryAfter(let timeInterval):
                        if timeInterval < Constants.autoRetryInterval {
                            return Guarantee
                                .after(on: strongSelf.schedulers.global(), seconds: timeInterval)
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
                                expiration: strongSelf.deps.dateProvider().addingTimeInterval(timeInterval),
                                e164: e164
                            ))
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
                self.db.write {
                    self.processSession(session, initialCodeRequestState: .requested, $0)
                }
                return self.nextStep()
            case .rejectedArgument(let session):
                Logger.error("Should never get rejected argument error from requesting code. E164 already set on session.")
                // Wipe the pending code request, so we don't retry.
                self.inMemoryState.pendingCodeTransport = nil
                self.db.write {
                    self.processSession(session, initialCodeRequestState: .failedToRequest, $0)
                }
                return self.nextStep()
            case .disallowed(let session):
                // Whatever caused this should be represented on the session itself,
                // and once we unblock we should retry sending so don't clear the pending
                // code transport.
                self.db.write { self.processSession(session, $0) }
                return self.nextStep()
            case .transportError(let session):
                // We failed with the current transport, but another transport
                // might work.
                self.db.write { self.processSession(session, initialCodeRequestState: .smsTransportFailed, $0) }
                // Wipe the pending code request, so we don't auto-retry.
                self.inMemoryState.pendingCodeTransport = nil
                return self.nextStep()
            case .invalidSession:
                self.inMemoryState.pendingCodeTransport = nil
                self.db.write { self.resetSession($0) }
                return .value(.showErrorSheet(.sessionInvalidated))
            case .serverFailure(let failureResponse):
                self.db.write { tx in
                    self.processSession(
                        session,
                        initialCodeRequestState: failureResponse.isPermanent
                            ? .permanentProviderFailure
                            : .transientProviderFailure,
                        tx
                    )
                }
                // Wipe the pending code request, so we don't auto-retry.
                self.inMemoryState.pendingCodeTransport = nil
                return self.nextStep()
            case .retryAfterTimeout(let session):
                let timeInterval: TimeInterval?
                switch transport {
                case .sms:
                    timeInterval = session.nextSMS
                case .voice:
                    timeInterval = session.nextCall
                }
                if let timeInterval, timeInterval < Constants.autoRetryInterval {
                    self.db.write { self.processSession(session, $0) }
                    return Guarantee
                        .after(on: self.schedulers.global(), seconds: timeInterval)
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
                    if session.nextVerificationAttemptDate != nil {
                        self.db.write {
                            self.processSession(session, initialCodeRequestState: .requested, $0)
                        }
                        // Show an error on the verification code entry screen.
                        return .value(.verificationCodeEntry(self.verificationCodeEntryState(
                            session: session,
                            validationError: {
                                switch transport {
                                case .sms: return .smsResendTimeout
                                case .voice: return .voiceResendTimeout
                                }
                            }()
                        )))
                    } else if let timeInterval {
                        self.db.write {
                            self.processSession(session, initialCodeRequestState: .failedToRequest, $0)
                        }
                        // We were trying to resend from the phone number screen.
                        return .value(.phoneNumberEntry(self.phoneNumberEntryState(
                            validationError: .rateLimited(.init(
                                expiration: self.deps.dateProvider().addingTimeInterval(timeInterval),
                                e164: session.e164
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
                self.inMemoryState.pendingCodeTransport = nil
                self.db.write {
                    self.processSession(session, initialCodeRequestState: .failedToRequest, $0)
                }
                return .value(.showErrorSheet(.networkError))
            case .genericError:
                self.inMemoryState.pendingCodeTransport = nil
                self.db.write {
                    self.processSession(session, initialCodeRequestState: .failedToRequest, $0)
                }
                return .value(.showErrorSheet(.genericError))
            }
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
        deps.pushRegistrationManager.clearPreAuthChallengeToken()
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
            case nil, .notRequested, .ineligible, .waitingForPush, .fulfilled, .rejected:
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
                .nilTimeout(on: schedulers.global(), seconds: timeout)
                .then(on: schedulers.global()) { [weak self] (challengeToken: String?) -> Guarantee<RegistrationStep> in
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
                db.write { tx in
                    self.processSession(session, initialCodeRequestState: .failedToRequest, tx)
                }
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
            case nil, .notRequested, .ineligible, .unfulfilledPush, .fulfilled, .rejected:
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
        switch fulfillment {
        case .captcha:
            Logger.info("Submitting CAPTCHA challenge fulfillment")
        case .pushChallenge:
            Logger.info("Submitting push challenge fulfillment")
        }

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
                self.db.write { tx in
                    self.processSession(session, tx)
                    self.updatePersistedSessionState(session: session, tx) {
                        $0.pushChallengeState = .rejected
                    }
                }
                return .value(.showErrorSheet(.genericError))
            case .disallowed(let session):
                Logger.warn("Disallowed to complete a challenge which should be impossible.")
                // Don't keep trying to send a code.
                self.inMemoryState.pendingCodeTransport = nil
                self.db.write { self.processSession(session, initialCodeRequestState: .failedToRequest, $0) }
                return .value(.showErrorSheet(.genericError))
            case .invalidSession:
                self.db.write { self.resetSession($0) }
                return .value(.showErrorSheet(.sessionInvalidated))
            case .serverFailure(let failureResponse):
                if failureResponse.isPermanent {
                    return .value(.showErrorSheet(.genericError))
                } else {
                    return .value(.showErrorSheet(.networkError))
                }
            case .retryAfterTimeout(let session):
                Logger.error("Should not have to retry a captcha challenge request")
                // Clear the pending code; we want the user to press again
                // once the timeout expires.
                self.inMemoryState.pendingCodeTransport = nil
                self.db.write { self.processSession(session, initialCodeRequestState: .failedToRequest, $0) }
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
            case .transportError(let session):
                Logger.error("Should not get a transport error for a challenge request")
                // Clear the pending code; we want the user to press again
                // once the timeout expires.
                self.inMemoryState.pendingCodeTransport = nil
                self.db.write { self.processSession(session, initialCodeRequestState: .failedToRequest, $0) }
                return self.nextStep()
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
        Logger.info("")

        db.write { tx in
            self.updatePersistedSessionState(session: session, tx) {
                $0.numVerificationCodeSubmissions += 1
            }
        }

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
                if session.nextVerificationAttemptDate != nil {
                    self.db.write { self.processSession(session, $0) }
                    return .value(.verificationCodeEntry(self.verificationCodeEntryState(
                        session: session,
                        validationError: .invalidVerificationCode(invalidCode: code)
                    )))
                } else {
                    // Something went wrong, we can't submit again.
                    self.db.write { self.processSession(session, initialCodeRequestState: .exhaustedCodeAttempts, $0) }
                    return .value(self.verificationCodeSubmissionRejectedError)
                }
            case .disallowed(let session):
                // This state means the session state is updated
                // such that what comes next has changed, e.g. we can't send a verification
                // code and will kick the user back to sending an sms code.
                self.db.write { self.processSession(session, $0) }
                return .value(self.verificationCodeSubmissionRejectedError)
            case .invalidSession:
                self.db.write { self.resetSession($0) }
                return .value(.showErrorSheet(.sessionInvalidated))
            case .serverFailure(let failureResponse):
                if failureResponse.isPermanent {
                    return .value(.showErrorSheet(.genericError))
                } else {
                    return .value(.showErrorSheet(.networkError))
                }
            case .retryAfterTimeout(let session):
                self.db.write { self.processSession(session, $0) }
                if let timeInterval = session.nextVerificationAttempt, timeInterval < Constants.autoRetryInterval {
                    return Guarantee
                        .after(on: self.schedulers.global(), seconds: timeInterval)
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
                if session.nextVerificationAttemptDate != nil {
                    return .value(.verificationCodeEntry(self.verificationCodeEntryState(
                        session: session,
                        validationError: .submitCodeTimeout
                    )))
                } else {
                    // Something went wrong, we can't submit again.
                    return .value(self.verificationCodeSubmissionRejectedError)
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
            case .transportError(let session):
                Logger.error("Should not get transport error when submitting verification code")
                self.db.write { self.processSession(session, $0) }
                return .value(.showErrorSheet(.genericError))
            case .genericError:
                return .value(.showErrorSheet(.genericError))
            }
        }
    }

    private func restoreSVRMasterSecretForSessionPathReglock(
        session: RegistrationSession,
        pin: String,
        svrAuthCredential: SVRAuthCredential,
        reglockExpirationDate: Date,
        retriesLeft: Int = Constants.networkErrorRetries
    ) -> Guarantee<RegistrationStep> {
        Logger.info("")

        return deps.svr.restoreKeys(
            pin: pin,
            authMethod: .svrAuth(svrAuthCredential, backup: nil)
        )
            .then(on: schedulers.main) { [weak self] result -> Guarantee<RegistrationStep> in
                guard let self else {
                    return unretainedSelfError()
                }
                switch result {
                case .success:
                    self.db.write { tx in
                        self.loadLocalMasterKeyAndUpdateState(tx)
                        self.updatePersistedSessionState(session: session, tx) {
                            // Now we have the state we need to get past reglock.
                            $0.reglockState = .none
                        }
                    }
                    return self.nextStep()
                case let .invalidPin(remainingAttempts):
                    return .value(.pinEntry(RegistrationPinState(
                        operation: .enteringExistingPin(
                            skippability: .unskippable,
                            remainingAttempts: UInt(remainingAttempts)
                        ),
                        error: .wrongPin(wrongPin: pin),
                        contactSupportMode: self.contactSupportRegistrationPINMode(),
                        exitConfiguration: self.pinCodeEntryExitConfiguration()
                    )))
                case .backupMissing:
                    // If we are unable to talk to SVR, it got wiped, probably
                    // because we used up our guesses. We can't get past reglock.
                    self.inMemoryState.pinFromUser = nil
                    self.inMemoryState.shouldRestoreSVRMasterKeyAfterRegistration = false
                    self.db.write { tx in
                        self.updatePersistedState(tx) {
                            $0.hasGivenUpTryingToRestoreWithSVR = true
                        }
                        self.updatePersistedSessionState(session: session, tx) {
                            $0.reglockState = .waitingTimeout(expirationDate: reglockExpirationDate)
                        }
                    }
                    return self.nextStep()
                case .networkError:
                    if retriesLeft > 0 {
                        return self.restoreSVRMasterSecretForSessionPathReglock(
                            session: session,
                            pin: pin,
                            svrAuthCredential: svrAuthCredential,
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
            if let stepGuarantee = performSVRBackupStepsIfNeeded(accountIdentity: accountIdentity) {
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

        // We _must_ do these steps first.
        // Before atomic creation, the created account starts out
        // disabled and other endpoints won't work until we:
        // 1. sync push tokens OR set isManualMessageFetchEnabled=true and sync account attributes
        // 2. create prekeys and register them with the server
        // then we can do other stuff (fetch SVR backups, set profile info, etc)
        // If we did use atomic account creation, legacy_didSyncPushTokens should be true,
        // and legacy_shouldCreateAllPreKeys() should be false.
        if !persistedState.legacy_didSyncPushTokens {
            return syncPushTokens(accountIdentity)
        }
        var preKeysPromise: Promise<Void>?
        if legacy_shouldCreateAllPreKeys() {
            // Prior to atomic account creation, the created account starts out
            // disabled and other endpoints won't work until we create prekeys
            // and register them with the server then we can do other stuff
            // (fetch SVR backups, set profile info, etc).
            preKeysPromise = self.deps.preKeyManager.legacy_createPreKeys(auth: accountIdentity.chatServiceAuth)
        } else if shouldRefreshOneTimePreKeys() {
            // After atomic account creation, our account is ready to go from the start.
            // But we should still upload one-time prekeys, as that is not part
            // of account creation.
            preKeysPromise = self.deps.preKeyManager.rotateOneTimePreKeysForRegistration(auth: accountIdentity.chatServiceAuth)
        }
        if let preKeysPromise {
            return preKeysPromise
                .then(on: schedulers.main) { [weak self] () -> Guarantee<RegistrationStep> in
                    guard let self else {
                        return unretainedSelfError()
                    }
                    self.db.write { tx in
                        self.updatePersistedState(tx) {
                            // No harm marking both down as done even though
                            // we only did one or the other.
                            $0.didRefreshOneTimePreKeys = true
                            $0.legacy_didCreateAllPrekeys = true
                        }
                    }
                    return self.nextStep()
                }
                .recover(on: schedulers.main) { [weak self] error -> Guarantee<RegistrationStep> in
                    guard let self else {
                        return unretainedSelfError()
                    }
                    if error.isPostRegDeregisteredError {
                        return self.becameDeregisteredBeforeCompleting(accountIdentity: accountIdentity)
                    }
                    Logger.error("Failed to create prekeys: \(error)")
                    // Note this is undismissable; the user will be on whatever
                    // screen they were on but with the error sheet atop which retries
                    // via `nextStep()` when tapped.
                    return .value(.showErrorSheet(.genericError))
                }
        }

        if let stepGuarantee = performSVRBackupStepsIfNeeded(accountIdentity: accountIdentity) {
            return stepGuarantee
        }

        if shouldRestoreFromStorageService() {
            return restoreFromStorageService(accountIdentity: accountIdentity)
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
                        if let error {
                            if error.isPostRegDeregisteredError {
                                return self.becameDeregisteredBeforeCompleting(accountIdentity: accountIdentity)
                            }
                            return .value(.showErrorSheet(
                                error.isNetworkFailureOrTimeout ? .networkError : .genericError
                            ))
                        }
                        self.inMemoryState.hasProfileName = true
                        self.inMemoryState.pendingProfileInfo = nil
                        return self.nextStep()
                    }
            }

            return .value(.setupProfile(RegistrationProfileState(
                e164: accountIdentity.e164,
                phoneNumberDiscoverability: inMemoryState.phoneNumberDiscoverability.orDefault
            )))
        }

        if inMemoryState.phoneNumberDiscoverability == nil, FeatureFlags.phoneNumberPrivacy {
            return .value(.phoneNumberDiscoverability(RegistrationPhoneNumberDiscoverabilityState(
                e164: accountIdentity.e164,
                phoneNumberDiscoverability: inMemoryState.phoneNumberDiscoverability.orDefault
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
        Logger.info("")

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
                            $0.legacy_didSyncPushTokens = true
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
                                return .value(.showErrorSheet(.genericError))
                            }
                            strongSelf.db.write { tx in
                                strongSelf.deps.tsAccountManager.setIsManualMessageFetchEnabled(true, tx: tx)
                                strongSelf.updatePersistedState(tx) {
                                    // Say that we synced push tokens so that we skip this step hereafter.
                                    $0.legacy_didSyncPushTokens = true
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
                case .genericError(let error):
                    if error.isPostRegDeregisteredError {
                        return strongSelf.becameDeregisteredBeforeCompleting(accountIdentity: accountIdentity)
                    }
                    return .value(.showErrorSheet(.genericError))
                }
            }
    }

    // returns nil if no steps needed.
    private func performSVRBackupStepsIfNeeded(
        accountIdentity: AccountIdentity
    ) -> Guarantee<RegistrationStep>? {
        Logger.info("")

        let isRestoringPinBackup: Bool = (
            accountIdentity.hasPreviouslyUsedSVR &&
            !persistedState.hasGivenUpTryingToRestoreWithSVR
        )

        if !persistedState.hasSkippedPinEntry {
            guard let pin = inMemoryState.pinFromUser ?? inMemoryState.pinFromDisk else {
                if isRestoringPinBackup {
                    return .value(.pinEntry(RegistrationPinState(
                        operation: .enteringExistingPin(
                            skippability: .canSkip,
                            remainingAttempts: nil
                        ),
                        error: nil,
                        contactSupportMode: self.contactSupportRegistrationPINMode(),
                        exitConfiguration: pinCodeEntryExitConfiguration()
                    )))
                } else if let blob = inMemoryState.unconfirmedPinBlob {
                    return .value(.pinEntry(RegistrationPinState(
                        operation: .confirmingNewPin(blob),
                        error: nil,
                        contactSupportMode: self.contactSupportRegistrationPINMode(),
                        exitConfiguration: pinCodeEntryExitConfiguration()
                    )))
                } else {
                    return .value(.pinEntry(RegistrationPinState(
                        operation: .creatingNewPin,
                        error: nil,
                        contactSupportMode: self.contactSupportRegistrationPINMode(),
                        exitConfiguration: pinCodeEntryExitConfiguration()
                    )))
                }
            }
            if inMemoryState.shouldBackUpToSVR {
                // If we have no SVR data, fetch it.
                if isRestoringPinBackup, inMemoryState.shouldRestoreSVRMasterKeyAfterRegistration {
                    return restoreSVRBackupPostRegistration(pin: pin, accountIdentity: accountIdentity)
                } else {
                    // If we haven't backed up, do so now.
                    return backupToSVR(pin: pin, accountIdentity: accountIdentity)
                }
            }

            switch attributes2FAMode(e164: accountIdentity.e164) {
            case .none, .v1:
                Logger.info("Not enabling reglock because it wasn't enabled to begin with")
            case .v2(let reglockToken):
                guard inMemoryState.hasSetReglock.negated else {
                    break
                }
                return enableReglock(accountIdentity: accountIdentity, reglockToken: reglockToken)
            }
        }
        return nil
    }

    private func restoreSVRBackupPostRegistration(
        pin: String,
        accountIdentity: AccountIdentity,
        retriesLeft: Int = Constants.networkErrorRetries
    ) -> Guarantee<RegistrationStep> {
        Logger.info("")

        let backupAuthMethod = SVR.AuthMethod.chatServerAuth(accountIdentity.authedAccount)
        let authMethod: SVR.AuthMethod
        if let svrAuthCredential = inMemoryState.svrAuthCredential {
            authMethod = .svrAuth(svrAuthCredential, backup: backupAuthMethod)
        } else {
            authMethod = backupAuthMethod
        }
        return deps.svr
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
                    self.inMemoryState.shouldRestoreSVRMasterKeyAfterRegistration = false
                    self.inMemoryState.hasBackedUpToSVR = true
                    return self.nextStep()
                case let .invalidPin(remainingAttempts):
                    return .value(.pinEntry(RegistrationPinState(
                        operation: .enteringExistingPin(
                            skippability: .canSkipAndCreateNew,
                            remainingAttempts: UInt(remainingAttempts)
                        ),
                        error: .wrongPin(wrongPin: pin),
                        contactSupportMode: self.contactSupportRegistrationPINMode(),
                        exitConfiguration: self.pinCodeEntryExitConfiguration()
                    )))
                case .backupMissing:
                    // If we are unable to talk to SVR, it got wiped and we can't
                    // recover. Keep going like if nothing happened.
                    self.inMemoryState.pinFromUser = nil
                    self.inMemoryState.shouldRestoreSVRMasterKeyAfterRegistration = false
                    self.db.write { tx in
                        self.updatePersistedState(tx) { $0.hasGivenUpTryingToRestoreWithSVR = true }
                    }
                    return .value(.pinAttemptsExhaustedWithoutReglock(
                        .init(mode: .restoringBackup)
                    ))
                case .networkError:
                    if retriesLeft > 0 {
                        return self.restoreSVRBackupPostRegistration(
                            pin: pin,
                            accountIdentity: accountIdentity,
                            retriesLeft: retriesLeft - 1
                        )
                    }
                    return .value(.showErrorSheet(.networkError))
                case .genericError(let error):
                    if error.isPostRegDeregisteredError {
                        return self.becameDeregisteredBeforeCompleting(accountIdentity: accountIdentity)
                    }
                    return .value(.showErrorSheet(.genericError))
                }
            }
    }

    private func backupToSVR(
        pin: String,
        accountIdentity: AccountIdentity,
        retriesLeft: Int = Constants.networkErrorRetries
    ) -> Guarantee<RegistrationStep> {
        Logger.info("")

        let authMethod: SVR.AuthMethod
        let backupAuthMethod = SVR.AuthMethod.chatServerAuth(accountIdentity.authedAccount)
        if let svrAuthCredential = inMemoryState.svrAuthCredential {
            authMethod = .svrAuth(svrAuthCredential, backup: backupAuthMethod)
        } else {
            authMethod = backupAuthMethod
        }
        return deps.svr
            .generateAndBackupKeys(
                pin: pin,
                authMethod: authMethod,
                rotateMasterKey: false
            )
            .then(on: schedulers.main) { [weak self] () -> Guarantee<RegistrationStep>  in
                guard let strongSelf = self else {
                    return unretainedSelfError()
                }
                strongSelf.inMemoryState.hasBackedUpToSVR = true
                strongSelf.db.write { tx in
                    strongSelf.deps.ows2FAManager.markPinEnabled(pin, tx)
                }
                return strongSelf.restoreFromStorageService(accountIdentity: accountIdentity)
            }
            .recover(on: schedulers.main) { [weak self] error -> Guarantee<RegistrationStep> in
                guard let self else {
                    return unretainedSelfError()
                }
                if error.isNetworkFailureOrTimeout {
                    if retriesLeft > 0 {
                        return self.backupToSVR(
                            pin: pin,
                            accountIdentity: accountIdentity,
                            retriesLeft: retriesLeft - 1
                        )
                    }
                    return .value(.showErrorSheet(.networkError))
                }
                Logger.error("Failed to back up to SVR with error: \(error)")
                // We want to let people get through registration even if backups
                // go wrong. Show an error but let the user continue when they try the next step.
                self.inMemoryState.didSkipSVRBackup = true
                return .value(.showErrorSheet(.genericError))
            }
    }

    private func restoreFromStorageService(
        accountIdentity: AccountIdentity
    ) -> Guarantee<RegistrationStep> {
        return deps.accountManager.performInitialStorageServiceRestore(authedAccount: accountIdentity.authedAccount)
            .then(on: schedulers.sync) { [weak self] in
                guard let self else {
                    return unretainedSelfError()
                }
                self.loadProfileState()
                self.inMemoryState.hasRestoredFromStorageService = true
                return self.nextStep()
            }
            .recover(on: schedulers.main) { [weak self] error in
                guard let self else {
                    return unretainedSelfError()
                }
                if error.isPostRegDeregisteredError {
                    return self.becameDeregisteredBeforeCompleting(accountIdentity: accountIdentity)
                }
                self.inMemoryState.hasSkippedRestoreFromStorageService = true
                return self.nextStep()
            }
    }

    private func enableReglock(
        accountIdentity: AccountIdentity,
        reglockToken: String
    ) -> Guarantee<RegistrationStep> {
        Logger.info("Attempting to enable reglock")

        return Service.makeEnableReglockRequest(
            reglockToken: reglockToken,
            auth: accountIdentity.chatServiceAuth,
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
            self.inMemoryState.wasReglockEnabledBeforeStarting = true
            self.db.write { tx in
                self.deps.ows2FAManager.markRegistrationLockEnabled(tx)
            }
            return self.nextStep()
        }
    }

    private func loadProfileState() {
        Logger.info("")

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
            inMemoryState.phoneNumberDiscoverability =
                deps.phoneNumberDiscoverabilityManager.phoneNumberDiscoverability(tx: tx)
        }
    }

    private func updateAccountAttributes(_ accountIdentity: AccountIdentity) -> Guarantee<Error?> {
        Logger.info("")
        return Service
            .makeUpdateAccountAttributesRequest(
                makeAccountAttributes(
                    isManualMessageFetchEnabled: inMemoryState.isManualMessageFetchEnabled,
                    twoFAMode: self.attributes2FAMode(e164: accountIdentity.e164)
                ),
                auth: accountIdentity.chatServiceAuth,
                signalService: deps.signalService,
                schedulers: schedulers
            )
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
        case unretainedSelf
        case genericError
    }

    private func finalizeChangeNumberPniState(
        changeNumberState: Mode.ChangeNumberState,
        pniState: Mode.ChangeNumberState.PendingPniState,
        accountIdentity: AccountIdentity
    ) -> Guarantee<FinalizeChangeNumberResult> {
        Logger.info("")

        // Creating a high strust signal recipient for oneself
        // must happen in a transaction initiated off the main thread.
        return firstly(on: schedulers.global()) { [weak self] () -> FinalizeChangeNumberResult in
            guard let strongSelf = self else {
                return .unretainedSelf
            }
            do {
                try strongSelf.db.write { tx in
                    try strongSelf.deps.changeNumberPniManager.finalizePniIdentity(
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
                        localAci: \(changeNumberState.localAci),
                        localE164: \(changeNumberState.oldE164.stringValue),
                        serviceAci: \(accountIdentity.aci),
                        servicePni: \(accountIdentity.pni),
                        serviceE164: \(accountIdentity.e164.stringValue)")
                        """
                    )

                    // We do these here, and not in export state, so that we don't risk
                    // syncing out-of-date state to storage service.
                    strongSelf.deps.registrationStateChangeManager.didUpdateLocalPhoneNumber(
                        accountIdentity.e164,
                        aci: accountIdentity.aci,
                        pni: accountIdentity.pni,
                        tx: tx
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
        twoFAMode: AccountAttributes.TwoFactorAuthMode,
        responseHandler: @escaping (AccountResponse) -> Guarantee<RegistrationStep>
    ) -> Guarantee<RegistrationStep> {
        Logger.info("")

        switch mode {
        case .reRegistering(let state):
            if persistedState.hasResetForReRegistration.negated {
                db.write { tx in
                    let isPrimaryDevice = deps.tsAccountManager.registrationState(tx: tx).isPrimaryDevice ?? true
                    deps.registrationStateChangeManager.resetForReregistration(
                        localPhoneNumber: state.e164,
                        localAci: state.aci,
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
            return fetchApnRegistrationId().then(on: schedulers.main) { [weak self] apnResult in
                guard let self else {
                    return unretainedSelfError()
                }
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
                    return .value(.showErrorSheet(.genericError))
                case .genericError:
                    return .value(.showErrorSheet(.genericError))
                }
                self.inMemoryState.isManualMessageFetchEnabled = isManualMessageFetchEnabled
                if isManualMessageFetchEnabled {
                    self.db.write { tx in
                        self.deps.tsAccountManager.setIsManualMessageFetchEnabled(true, tx: tx)
                    }
                }
                let accountAttributes = self.makeAccountAttributes(
                    isManualMessageFetchEnabled: isManualMessageFetchEnabled,
                    twoFAMode: twoFAMode
                )
                return self.makeCreateAccountRequestAndFinalizePreKeys(
                    method: method,
                    e164: e164,
                    authPassword: authToken,
                    accountAttributes: accountAttributes,
                    skipDeviceTransfer: self.shouldSkipDeviceTransfer(),
                    apnRegistrationId: apnRegistrationId,
                    responseHandler: responseHandler
                )
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
                twoFAMode: twoFAMode,
                changeNumberState: changeNumberState
            ).then(on: schedulers.main) { [weak self] changeNumberResult in
                switch changeNumberResult {
                case .unretainedSelf:
                    return unretainedSelfError()
                case .pniStateError:
                    return .value(.showErrorSheet(.genericError))
                case .serviceResponse(let accountResponse):
                    switch accountResponse {
                    case .success:
                        // Pni state will get finalized and cleaned up later in
                        // the normal course of action.
                        break
                    case .reglockFailure, .rejectedVerificationMethod, .retryAfter:
                        // Explicit rejection by the server, we can safely
                        // wipe our local PNI state and regenerate when we retry.
                        guard let self else {
                            return unretainedSelfError()
                        }
                        do {
                            try self.db.write { tx in
                                self._unsafeToModify_mode = .changingNumber(try self.loader.savePendingChangeNumber(
                                    oldState: changeNumberState,
                                    pniState: nil,
                                    transaction: tx
                                ))
                            }
                        } catch {
                            return .value(.showErrorSheet(.genericError))
                        }
                    case .deviceTransferPossible:
                        owsFailBeta("Should't get device transfer response on change number request.")
                    case .networkError, .genericError:
                        // We don't know what went wrong, so PNI state
                        // may be set server side. Don't wipe PNI state
                        // so we try and recover.
                        Logger.error("Unknown error when changing number; preserving pni state")
                    }
                    return responseHandler(accountResponse)
                }
            }

        }
    }

    private func makeCreateAccountRequestAndFinalizePreKeys(
        method: RegistrationRequestFactory.VerificationMethod,
        e164: E164,
        authPassword: String,
        accountAttributes: AccountAttributes,
        skipDeviceTransfer: Bool,
        apnRegistrationId: RegistrationRequestFactory.ApnRegistrationId?,
        responseHandler: @escaping (AccountResponse) -> Guarantee<RegistrationStep>
    ) -> Guarantee<RegistrationStep> {
        db.write { tx in
            self.updatePersistedState(tx) {
                // We are doing atomic account creation, so we should
                // refresh the one time keys when done (as opposed to
                // creating _all_ keys as was done prior to atomic creation)
                $0.shouldRefreshOneTimePreKeys = true
            }
        }
        return self.deps.preKeyManager.createPreKeysForRegistration()
            .map(on: self.schedulers.sync) { (bundles: RegistrationPreKeyUploadBundles) -> RegistrationPreKeyUploadBundles? in
                return bundles
            }.recover(on: self.schedulers.sync) {
                Logger.error("Unable to generate prekeys: \($0)")
                return .value(nil)
            }
            .then(on: self.schedulers.main) { [weak self] (prekeyBundles: RegistrationPreKeyUploadBundles?) in
                guard let self else {
                    return unretainedSelfError()
                }
                guard let prekeyBundles else {
                    return .value(.showErrorSheet(.genericError))
                }
                return Service
                    .makeCreateAccountRequest(
                        method,
                        e164: e164,
                        authPassword: authPassword,
                        accountAttributes: accountAttributes,
                        skipDeviceTransfer: self.shouldSkipDeviceTransfer(),
                        apnRegistrationId: apnRegistrationId,
                        prekeyBundles: prekeyBundles,
                        signalService: self.deps.signalService,
                        schedulers: self.schedulers
                    )
                    .then(on: self.schedulers.main) { [weak self] (accountResponse: AccountResponse) -> Guarantee<RegistrationStep> in
                        guard let self else {
                            return unretainedSelfError()
                        }
                        // Mark it down as having synced push tokens, which we did
                        // as part of atomic account creation. This avoids us taking
                        // the legacy code path later and re-syncing.
                        self.db.write { tx in
                            self.updatePersistedState(tx) {
                                $0.legacy_didSyncPushTokens = true
                            }
                        }
                        let isPrekeyUploadSuccess: Bool
                        switch accountResponse {
                        case .success:
                            isPrekeyUploadSuccess = true
                        case
                                .retryAfter,
                                .rejectedVerificationMethod,
                                .reglockFailure,
                                .networkError,
                                .genericError,
                                .deviceTransferPossible:
                            isPrekeyUploadSuccess = false
                        }
                        return self.deps.preKeyManager
                            .finalizeRegistrationPreKeys(
                                prekeyBundles,
                                uploadDidSucceed: isPrekeyUploadSuccess
                            ).recover(on: self.schedulers.sync) { error in
                                // Finalizing is best effort.
                                Logger.error("Unable to finalize prekeys, ignoring and continuing")
                                return .value(())
                            }
                            .then(on: self.schedulers.main) { () -> Guarantee<RegistrationStep> in
                                return responseHandler(accountResponse)
                            }
                    }
            }
    }

    private enum ChangeNumberResult {
        case serviceResponse(AccountResponse)
        case pniStateError
        case unretainedSelf
    }

    private func generatePniStateAndMakeChangeNumberRequest(
        e164: E164,
        verificationMethod: RegistrationRequestFactory.VerificationMethod,
        twoFAMode: AccountAttributes.TwoFactorAuthMode,
        changeNumberState: RegistrationCoordinatorLoaderImpl.Mode.ChangeNumberState
    ) -> Guarantee<ChangeNumberResult> {
        Logger.info("")

        return deps.changeNumberPniManager
            .generatePniIdentity(
                forNewE164: e164,
                localAci: changeNumberState.localAci,
                localAccountId: changeNumberState.localAccountId,
                localDeviceId: changeNumberState.localDeviceId,
                localUserAllDeviceIds: changeNumberState.localUserAllDeviceIds
            )
            .then(on: schedulers.global()) { [weak self] pniResult -> Guarantee<ChangeNumberResult> in
                guard let strongSelf = self else {
                    return .value(.unretainedSelf)
                }
                switch pniResult {
                case .failure:
                    return .value(.pniStateError)
                case .success(let pniParams, let pniPendingState):
                    return strongSelf.makeChangeNumberRequest(
                        e164: e164,
                        verificationMethod: verificationMethod,
                        twoFAMode: twoFAMode,
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
        twoFAMode: AccountAttributes.TwoFactorAuthMode,
        changeNumberState: RegistrationCoordinatorLoaderImpl.Mode.ChangeNumberState,
        pniPendingState: ChangePhoneNumberPni.PendingState,
        pniParams: PniDistribution.Parameters
    ) -> Guarantee<ChangeNumberResult> {
        Logger.info("")

        // Process all messages first.
        return deps.messageProcessor.waitForProcessingCompleteAndThenSuspend(for: .pendingChangeNumber)
            .then(on: schedulers.main) { [weak self] in
                guard let strongSelf = self else {
                    return .value(.unretainedSelf)
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
                    return .value(.pniStateError)
                }
                let reglockToken: String?
                switch twoFAMode {
                case .v2(let token):
                    reglockToken = token
                case .v1, .none:
                    reglockToken = nil
                }
                return Service
                    .makeChangeNumberRequest(
                        verificationMethod,
                        e164: e164,
                        reglockToken: reglockToken,
                        authPassword: changeNumberState.oldAuthToken,
                        pniChangeNumberParameters: pniParams,
                        signalService: strongSelf.deps.signalService,
                        schedulers: strongSelf.schedulers
                    )
                    .map(on: strongSelf.schedulers.sync) { .serviceResponse($0) }
            }
    }

    private func recoverPendingPniChangeNumberState(
        changeNumberState: Mode.ChangeNumberState,
        pniState: Mode.ChangeNumberState.PendingPniState
    ) -> Guarantee<RegistrationStep> {
        Logger.info("")

        return Service
            .makeWhoAmIRequest(
                auth: ChatServiceAuth.explicit(
                    aci: AciObjC(changeNumberState.localAci),
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
                                    hasPreviouslyUsedSVR: strongSelf.inMemoryState.didHaveSVRBackupsPriorToReg,
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

    // MARK: - Becoming deregistered while registering

    private func becameDeregisteredBeforeCompleting(
        accountIdentity: AccountIdentity
    ) -> Guarantee<RegistrationStep> {
        Logger.info("")

        let kickBackToReRegistration: () -> Guarantee<RegistrationStep> = { [weak self] in
            guard let self else {
                return unretainedSelfError()
            }
            Logger.warn("Got deregistered while completing registration; starting over with re-registration.")
            self.db.write { tx in
                self.wipePersistedState(tx)
            }
            return .value(.showErrorSheet(.becameDeregistered(reregParams: .init(
                e164: accountIdentity.e164,
                aci: accountIdentity.aci
            ))))
        }

        switch mode {
        case .registering, .reRegistering:
            return kickBackToReRegistration()
        case .changingNumber(let changeNumberState):
            if let pniState = changeNumberState.pniState {
                return finalizeChangeNumberPniState(
                    changeNumberState: changeNumberState,
                    pniState: pniState,
                    accountIdentity: accountIdentity
                ).then(on: schedulers.main) { result in
                    return kickBackToReRegistration()
                }
            } else {
                return kickBackToReRegistration()
            }
        }
    }

    // MARK: - Account objects

    private func attributes2FAMode(e164: E164) -> AccountAttributes.TwoFactorAuthMode {
        if
            (
                inMemoryState.wasReglockEnabledBeforeStarting
                || persistedState.e164WithKnownReglockEnabled == e164
            ),
            let reglockToken = inMemoryState.reglockToken
        {
            return .v2(reglockToken: reglockToken)
        } else if
            let pinCode = inMemoryState.pinFromDisk,
            inMemoryState.isV12faUser
        {
            return .v1(pinCode: pinCode)
        } else {
            return .none
        }
    }

    private func makeAccountAttributes(
        isManualMessageFetchEnabled: Bool,
        twoFAMode: AccountAttributes.TwoFactorAuthMode
    ) -> AccountAttributes {
        let hasSVRBackups: Bool
        switch getPathway() {
        case
                .opening,
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
            registrationId: inMemoryState.registrationId,
            pniRegistrationId: inMemoryState.pniRegistrationId,
            unidentifiedAccessKey: inMemoryState.udAccessKey.keyData.base64EncodedString(),
            unrestrictedUnidentifiedAccess: inMemoryState.allowUnrestrictedUD,
            twofaMode: twoFAMode,
            registrationRecoveryPassword: inMemoryState.regRecoveryPw,
            encryptedDeviceName: nil, // This class only deals in primary devices, which have no name
            discoverableByPhoneNumber: inMemoryState.phoneNumberDiscoverability,
            hasSVRBackups: hasSVRBackups
        )
    }

    private func fetchApnRegistrationId() -> Guarantee<Registration.RequestPushTokensResult> {
        guard !inMemoryState.isManualMessageFetchEnabled else {
            return .value(.pushUnsupported(description: "Manual fetch pre-enabled"))
        }
        return deps.pushRegistrationManager.requestPushToken()
    }

    private func generateServerAuthToken() -> String {
        return Cryptography.generateRandomBytes(16).hexadecimalString
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
            return AuthedAccount.explicit(aci: aci, pni: pni, e164: e164, authPassword: authPassword)
        }

        var chatServiceAuth: ChatServiceAuth {
            return ChatServiceAuth.explicit(aci: AciObjC(aci), password: authPassword)
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

    private func contactSupportRegistrationPINMode() -> ContactSupportRegistrationPINMode {
        switch getPathway() {
        case .opening:
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
            if inMemoryState.isV12faUser {
                return .v1
            } else {
                // If they are in profile setup that means they
                // would have gotten past reglock already.
                return .v2NoReglock
            }
        }
    }

    private var reglockTimeoutAcknowledgeAction: RegistrationReglockTimeoutAcknowledgeAction {
        switch mode {
        case .registering: return .resetPhoneNumber
        case .reRegistering, .changingNumber:
            if canExitRegistrationFlow() {
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

    private func shouldRestoreFromStorageService() -> Bool {
        switch mode {
        case .registering, .reRegistering:
            return !inMemoryState.hasRestoredFromStorageService
                && !inMemoryState.hasSkippedRestoreFromStorageService
        case .changingNumber:
            return false
        }
    }

    private func legacy_shouldCreateAllPreKeys() -> Bool {
        if persistedState.shouldRefreshOneTimePreKeys == true {
            return false
        }
        switch mode {
        case .registering, .reRegistering:
            return !persistedState.legacy_didCreateAllPrekeys
        case .changingNumber:
            return false
        }
    }

    private func shouldRefreshOneTimePreKeys() -> Bool {
        guard persistedState.shouldRefreshOneTimePreKeys == true else {
            return false
        }
        switch mode {
        case .registering, .reRegistering:
            return persistedState.didRefreshOneTimePreKeys != true
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

        // If we have a PIN and SVR master key locally (only possible for re-registration)
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

extension Error {

    fileprivate var isPostRegDeregisteredError: Bool {
        guard let statusCode = (self as? OWSHTTPError)?.responseStatusCode else {
            return false
        }
        // We only use REST during registration;
        // Websocket deregisters with a 403 but that doesn't matter.
        return statusCode == 401
    }
}
