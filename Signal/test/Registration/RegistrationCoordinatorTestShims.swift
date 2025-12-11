//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import LibSignalClient
@testable public import SignalServiceKit
@testable public import Signal

extension RegistrationCoordinatorImpl {

    public enum TestMocks {
        public typealias ContactsManager = _RegistrationCoordinator_ContactsManagerMock
        public typealias ContactsStore = _RegistrationCoordinator_CNContactsStoreMock
        public typealias ExperienceManager = _RegistrationCoordinator_ExperienceManagerMock
        public typealias IdentityManager = _RegistrationCoordinator_IdentityManagerMock
        public typealias MessagePipelineSupervisor = _RegistrationCoordinator_MessagePipelineSupervisorMock
        public typealias MessageProcessor = _RegistrationCoordinator_MessageProcessorMock
        public typealias OWS2FAManager = _RegistrationCoordinator_OWS2FAManagerMock
        public typealias PreKeyManager = _RegistrationCoordinator_PreKeyManagerMock
        public typealias ProfileManager = _RegistrationCoordinator_ProfileManagerMock
        public typealias PushRegistrationManager = _RegistrationCoordinator_PushRegistrationManagerMock
        public typealias ReceiptManager = _RegistrationCoordinator_ReceiptManagerMock
        public typealias StorageServiceManager = _RegistrationCoordinator_StorageServiceManagerMock
        public typealias TimeoutProvider = _RegistrationCoordinator_TimeoutProviderMock
        public typealias UDManager = _RegistrationCoordinator_UDManagerMock
        public typealias UsernameApiClient = _RegistrationCoordinator_UsernameApiClientMock
    }
}

// MARK: - ContactsManager

public class _RegistrationCoordinator_ContactsManagerMock: _RegistrationCoordinator_ContactsManagerShim {

    public init() {}

    public func fetchSystemContactsOnceIfAlreadyAuthorized() {
        // TODO[Registration]: test that this gets called.
    }

    public func setIsPrimaryDevice() {
        // TODO[Registration]: test that this gets called.
    }
}

// MARK: - CNContacts

public class _RegistrationCoordinator_CNContactsStoreMock: _RegistrationCoordinator_CNContactsStoreShim {

    public init() {}

    public var doesNeedContactsAuthorization = false

    public func needsContactsAuthorization() -> Bool {
        return doesNeedContactsAuthorization
    }

    public func requestContactsAuthorization() async {
        doesNeedContactsAuthorization = false
    }
}

// MARK: - ExperienceUpgradeManager

public class _RegistrationCoordinator_ExperienceManagerMock: _RegistrationCoordinator_ExperienceManagerShim {

    public init() {}

    public var didClearIntroducingPinsExperience: Bool = false
    public var clearIntroducingPinsExperienceMock: (() -> Void)?

    public func clearIntroducingPinsExperience(_ tx: DBWriteTransaction) {
        didClearIntroducingPinsExperience = true
        clearIntroducingPinsExperienceMock?()
    }

    public var didEnableAllGetStartedCards: Bool = false
    public var enableAllGetStartedCardsMock: (() -> Void)?

    public func enableAllGetStartedCards(_ tx: DBWriteTransaction) {
        didEnableAllGetStartedCards = true
        enableAllGetStartedCardsMock?()
    }
}

// MARK: - IdentityManager

public class _RegistrationCoordinator_IdentityManagerMock: _RegistrationCoordinator_IdentityManagerShim {
    public init() {}

    public func setIdentityKeyPair(_ keyPair: ECKeyPair?, for identity: OWSIdentity, tx: DBWriteTransaction) { }
}

// MARK: - MessagePipelineSupervisor

public class _RegistrationCoordinator_MessagePipelineSupervisorMock: _RegistrationCoordinator_MessagePipelineSupervisorShim {

    public init() {}

    public var suspensions = Set<MessagePipelineSupervisor.Suspension>()

    public func suspendMessageProcessingWithoutHandle(for suspension: MessagePipelineSupervisor.Suspension) {
        suspensions.insert(suspension)
    }

    public func unsuspendMessageProcessing(for suspension: MessagePipelineSupervisor.Suspension) {
        suspensions.remove(suspension)
    }
}

// MARK: - MessageProcessor

public class _RegistrationCoordinator_MessageProcessorMock: _RegistrationCoordinator_MessageProcessorShim {

    public init() {}

    public var waitForFetchingAndProcessingMock: (() -> Guarantee<Void>)?

    public func waitForFetchingAndProcessing() -> Guarantee<Void> {
        return waitForFetchingAndProcessingMock!()
    }
}

// MARK: - OWS2FAManager

public class _RegistrationCoordinator_OWS2FAManagerMock: _RegistrationCoordinator_OWS2FAManagerShim {

    public init() {}

    public var pinCodeMock: (() -> String?)?

    public func pinCode(_ tx: SignalServiceKit.DBReadTransaction) -> String? {
        return pinCodeMock!()
    }

    public var clearLocalPinCodeMock: (() -> Void)?

    public func clearLocalPinCode(_ tx: SignalServiceKit.DBWriteTransaction) {
        clearLocalPinCodeMock?()
    }

    public var isReglockEnabledMock: (() -> Bool)?

    public func isReglockEnabled(_ tx: SignalServiceKit.DBReadTransaction) -> Bool {
        return isReglockEnabledMock!()
    }

    public var didMarkPinEnabled: ((String) -> Void)?

    public func markPinEnabled(pin: String, resetReminderInterval: Bool, tx: SignalServiceKit.DBWriteTransaction) {
        didMarkPinEnabled?(pin)
    }

    public var didMarkRegistrationLockEnabled: (() -> Void)?

    public func markRegistrationLockEnabled(_ tx: SignalServiceKit.DBWriteTransaction) {
        didMarkRegistrationLockEnabled?()
    }
}

// MARK: - PreKeyManager

public class _RegistrationCoordinator_PreKeyManagerMock: PreKeyManager {
    var run: RegistrationCoordinatorTest.RegistrationTestRun
    init(run: RegistrationCoordinatorTest.RegistrationTestRun) {
        self.run = run
    }

    public func isAppLockedDueToPreKeyUpdateFailures(tx: DBReadTransaction) -> Bool { fatalError() }
    public func checkPreKeysIfNecessary(tx: DBReadTransaction) { fatalError() }
    public func rotatePreKeysOnUpgradeIfNecessary(for identity: OWSIdentity) async throws { fatalError() }
    public func createPreKeysForProvisioning(aciIdentityKeyPair: ECKeyPair, pniIdentityKeyPair: ECKeyPair) -> Task<RegistrationPreKeyUploadBundles, any Error> { fatalError() }
    public func rotateSignedPreKeysIfNeeded() -> Task<Void, any Error> { fatalError() }
    public func refreshOneTimePreKeys(forIdentity identity: OWSIdentity, alsoRefreshSignedPreKey shouldRefreshSignedPreKey: Bool) { fatalError() }

    public typealias CreatePreKeysMock = (() -> Task<RegistrationPreKeyUploadBundles, any Error>)
    private var createPreKeysMocks = [CreatePreKeysMock]()
    public func addCreatePreKeysMock(_ mock: @escaping CreatePreKeysMock) { createPreKeysMocks.append(mock) }
    public func createPreKeysForRegistration() -> Task<RegistrationPreKeyUploadBundles, any Error> {
        run.addObservedStep(.createPreKeys)
        return createPreKeysMocks.removeFirst()()
    }

    public typealias FinalizePreKeysMock = ((Bool) -> Task<Void, any Error>)
    private var finalizePreKeysMocks = [FinalizePreKeysMock]()
    public func addFinalizePreKeyMock(_ mock: @escaping FinalizePreKeysMock) { finalizePreKeysMocks.append(mock) }
    public func finalizeRegistrationPreKeys(_ bundles: RegistrationPreKeyUploadBundles, uploadDidSucceed: Bool) -> Task<Void, any Error> {
        run.addObservedStep(.finalizePreKeys)
        return finalizePreKeysMocks.removeFirst()(uploadDidSucceed)
    }

    public typealias RotateOneTimePreKeysMock = ((ChatServiceAuth) -> Task<Void, any Error>)
    private var rotateOneTimePreKeysMocks = [RotateOneTimePreKeysMock]()
    public func addRotateOneTimePreKeyMock(_ mock: @escaping RotateOneTimePreKeysMock) { rotateOneTimePreKeysMocks.append(mock) }
    public func rotateOneTimePreKeysForRegistration(auth: ChatServiceAuth) -> Task<Void, any Error> {
        run.addObservedStep(.rotateOneTimePreKeys)
        return rotateOneTimePreKeysMocks.removeFirst()(auth)
    }

    public func setIsChangingNumber(_ isChangingNumber: Bool) {
    }
}

// MARK: - ProfileManager

public class _RegistrationCoordinator_ProfileManagerMock: _RegistrationCoordinator_ProfileManagerShim {

    public init() {}

    public var localUserProfileMock: (_ tx: DBReadTransaction) -> OWSUserProfile? = { _ in nil }

    public func localUserProfile(tx: DBReadTransaction) -> OWSUserProfile? {
        localUserProfileMock(tx)
    }

    public var updateLocalProfileMock: ((
        _ givenName: OWSUserProfile.NameComponent,
        _ familyName: OWSUserProfile.NameComponent?,
        _ avatarData: Data?,
        _ authedAccount: AuthedAccount,
        _ tx: DBWriteTransaction
    ) -> Promise<Void>)?

    public func updateLocalProfile(
        givenName: OWSUserProfile.NameComponent,
        familyName: OWSUserProfile.NameComponent?,
        avatarData: Data?,
        authedAccount: AuthedAccount,
        tx: DBWriteTransaction
    ) -> Promise<Void> {
        return updateLocalProfileMock!(givenName, familyName, avatarData, authedAccount, tx)
    }

    public var didScheduleReuploadLocalProfile = false

    public func scheduleReuploadLocalProfile(authedAccount: AuthedAccount) {
        didScheduleReuploadLocalProfile = true
    }
}

// MARK: - PushRegistrationManager

public class _RegistrationCoordinator_PushRegistrationManagerMock: _RegistrationCoordinator_PushRegistrationManagerShim {

    var run: RegistrationCoordinatorTest.RegistrationTestRun
    init(run: RegistrationCoordinatorTest.RegistrationTestRun) {
        self.run = run
    }

    public var doesNeedNotificationAuthorization = false

    public func needsNotificationAuthorization() async -> Bool {
        return doesNeedNotificationAuthorization
    }

    public func registerUserNotificationSettings() async {
        doesNeedNotificationAuthorization = true
    }

    public typealias RequestPushTokenMock = (() async -> Registration.RequestPushTokensResult)
    private var requestPushTokenMocks = [RequestPushTokenMock]()
    public func addRequestPushTokenMock(_ mock: @escaping RequestPushTokenMock) {
        requestPushTokenMocks.append(mock)
    }
    public func requestPushToken() async -> Registration.RequestPushTokensResult {
        run.addObservedStep(.requestPushToken)
        return await requestPushTokenMocks.removeFirst()()
    }

    public typealias ReceivePreAuthChallengeTokenMock = (() async -> String)
    private var receivePreAuthChallengeTokenMock: ReceivePreAuthChallengeTokenMock!
    public func setReceivePreAuthChallengeTokenMock(_ mock: @escaping ReceivePreAuthChallengeTokenMock) {
        receivePreAuthChallengeTokenMock = mock
    }
    public func receivePreAuthChallengeToken() async -> String {
        return await receivePreAuthChallengeTokenMock()
    }

    public var didClearPreAuthChallengeToken = false

    public func clearPreAuthChallengeToken() {
        didClearPreAuthChallengeToken = true
    }
}

// MARK: - ReceiptManager

public class _RegistrationCoordinator_ReceiptManagerMock: _RegistrationCoordinator_ReceiptManagerShim {

    public init() {}

    public var didSetAreReadReceiptsEnabled = false
    public var setAreReadReceiptsEnabledMock: ((Bool) -> Void)?

    public func setAreReadReceiptsEnabled(_ areEnabled: Bool, _ tx: DBWriteTransaction) {
        didSetAreReadReceiptsEnabled = true
        setAreReadReceiptsEnabledMock?(areEnabled)
    }

    public var didSetAreStoryViewedReceiptsEnabled = false
    public var setAreStoryViewedReceiptsEnabledMock: ((Bool) -> Void)?

    public func setAreStoryViewedReceiptsEnabled(_ areEnabled: Bool, _ tx: DBWriteTransaction) {
        didSetAreStoryViewedReceiptsEnabled = true
        setAreStoryViewedReceiptsEnabledMock?(areEnabled)
    }
}

// MARK: StorageService
public class _RegistrationCoordinator_StorageServiceManagerMock: _RegistrationCoordinator_StorageServiceManagerShim {
    var run: RegistrationCoordinatorTest.RegistrationTestRun
    init(run: RegistrationCoordinatorTest.RegistrationTestRun) {
        self.run = run
    }

    public typealias RotateManifestMock = (StorageServiceManagerManifestRotationMode, AuthedDevice) -> Promise<Void>
    private var rotateManifestMocks = [RotateManifestMock]()
    public func addRotateManifestMock(_ mock: @escaping RotateManifestMock) { rotateManifestMocks.append(mock) }
    public func rotateManifest(mode: StorageServiceManagerManifestRotationMode, authedDevice: AuthedDevice) async throws {
        run.addObservedStep(.rotateManifest)
        return try await rotateManifestMocks.removeFirst()(mode, authedDevice).awaitable()
    }

    public typealias RestoreOrCreateManifestIfNecessaryMock = (AuthedDevice, StorageService.MasterKeySource) -> Promise<Void>
    private var restoreOrCreateManifestIfNecessaryMocks = [RestoreOrCreateManifestIfNecessaryMock]()
    public func addRestoreOrCreateManifestIfNecessaryMock(_ mock: @escaping RestoreOrCreateManifestIfNecessaryMock) { restoreOrCreateManifestIfNecessaryMocks.append(mock) }
    public func restoreOrCreateManifestIfNecessary(authedDevice: AuthedDevice, masterKeySource: StorageService.MasterKeySource) -> Promise<Void> {
        run.addObservedStep(.restoreStorageService)
        return restoreOrCreateManifestIfNecessaryMocks.removeFirst()(authedDevice, masterKeySource)
    }

    public var backupPendingChangesMock: ((SignalServiceKit.AuthedDevice) -> Void) = { _ in }
    public func backupPendingChanges(authedDevice: SignalServiceKit.AuthedDevice) {
        return backupPendingChangesMock(authedDevice)
    }

    public func recordPendingLocalAccountUpdates() { }
}

// MARK: TimeoutProvider

public class _RegistrationCoordinator_TimeoutProviderMock: _RegistrationCoordinator_TimeoutProviderShim {
    public var pushTokenMinWaitTime: TimeInterval = RegistrationCoordinatorImpl.Wrappers.TimeoutProvider.Constants.pushTokenMinWaitTime
    public var pushTokenTimeout: TimeInterval = RegistrationCoordinatorImpl.Wrappers.TimeoutProvider.Constants.pushTokenTimeout
}

// MARK: UDManager

public class _RegistrationCoordinator_UDManagerMock: _RegistrationCoordinator_UDManagerShim {

    public init() {}

    public var shouldAllowUnrestrictedAccessLocalMock: (() -> Bool) = { true }

    public func shouldAllowUnrestrictedAccessLocal(transaction: DBReadTransaction) -> Bool {
        return shouldAllowUnrestrictedAccessLocalMock()
    }
}

// MARK: UsernameApiClient

public class _RegistrationCoordinator_UsernameApiClientMock: _RegistrationCoordinator_UsernameApiClientShim {
    public init() {}

    public var confirmReservedUsernameMocks = [(reservedUsername: Usernames.HashedUsername, encryptedUsernameForLink: Data, chatServiceAuth: ChatServiceAuth) async throws -> Usernames.ApiClientConfirmationResult]()
    public func confirmReservedUsername(reservedUsername: Usernames.HashedUsername, encryptedUsernameForLink: Data, chatServiceAuth: ChatServiceAuth) async throws -> Usernames.ApiClientConfirmationResult {
        return try await confirmReservedUsernameMocks.removeFirst()(reservedUsername, encryptedUsernameForLink, chatServiceAuth)
    }
}
