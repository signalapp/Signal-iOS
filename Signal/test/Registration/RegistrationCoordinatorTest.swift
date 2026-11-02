//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import LibSignalClient
import Testing

@testable import Signal
@testable import SignalServiceKit

public class RegistrationCoordinatorTest {
    // Default to the SSK AEP.
    typealias AccountEntropyPool = SignalServiceKit.AccountEntropyPool

    private var stubs = Stubs()

    private var date: Date { self.stubs.date }

    private var appExpiry: AppExpiry!
    private var changeNumberPniManager: ChangePhoneNumberPniManagerMock!
    private var contactsStore: RegistrationCoordinatorImpl.TestMocks.ContactsStore!
    private var dateProvider: DateProvider!
    private var db: (any DB)!
    private var experienceManager: RegistrationCoordinatorImpl.TestMocks.ExperienceManager!
    private var accountKeyStore: AccountKeyStore!
    private var localUsernameManagerMock: MockLocalUsernameManager!
    private var mockIdentityManager: OWSIdentityManager!
    private var mockMessagePipelineSupervisor: RegistrationCoordinatorImpl.TestMocks.MessagePipelineSupervisor!
    private var mockMessageProcessor: RegistrationCoordinatorImpl.TestMocks.MessageProcessor!
    private var mockUsernamesService: MockUsernamesService!
    private var networkManagerMock: MockNetworkManager!
    private var ows2FAManagerMock: RegistrationCoordinatorImpl.TestMocks.OWS2FAManager!
    private var phoneNumberDiscoverabilityManagerMock: MockPhoneNumberDiscoverabilityManager!
    private var preKeyManagerMock: RegistrationCoordinatorImpl.TestMocks.PreKeyManager!
    private var profileManagerMock: RegistrationCoordinatorImpl.TestMocks.ProfileManager!
    private var pushRegistrationManagerMock: RegistrationCoordinatorImpl.TestMocks.PushRegistrationManager!
    private var quickRestoreManager: QuickRestoreManager!
    private var receiptManagerMock: RegistrationCoordinatorImpl.TestMocks.ReceiptManager!
    private var registrationCoordinatorLoader: RegistrationCoordinatorLoaderImpl!
    private var registrationStateChangeManagerMock: MockRegistrationStateChangeManager!
    private var sessionManager: RegistrationSessionManagerMock!
    private var storageServiceManagerMock: RegistrationCoordinatorImpl.TestMocks.StorageServiceManager!
    private var svr: SecureValueRecoveryMock!
    private var svrAuthCredentialManager: SVRAuthCredentialManager!
    private var timeoutProviderMock: RegistrationCoordinatorImpl.TestMocks.TimeoutProvider!
    private var tsAccountManagerMock: MockTSAccountManager!
    private var localFileBackupManager: LocalFileBackupManager!

    class RegistrationTestRun {
        private(set) var recordedSteps = [TestStep]()
        func addObservedStep(_ step: TestStep) {
            recordedSteps.append(step)
        }
    }

    private var testRun = RegistrationTestRun()

    init() {
        dateProvider = { self.date }
        db = InMemoryDB()

        appExpiry = .forUnitTests()
        accountKeyStore = AccountKeyStore(backupSettingsStore: BackupSettingsStore())
        let preKeyStore = PreKeyStore()
        changeNumberPniManager = ChangePhoneNumberPniManagerMock(
            mockKyberStore: KyberPreKeyStoreImpl(for: .pni, dateProvider: dateProvider, preKeyStore: preKeyStore),
        )
        contactsStore = RegistrationCoordinatorImpl.TestMocks.ContactsStore()
        experienceManager = RegistrationCoordinatorImpl.TestMocks.ExperienceManager()
        localUsernameManagerMock = {
            let mock = MockLocalUsernameManager()
            // This should result in no username reclamation. Tests that want to
            // test reclamation should overwrite this.
            mock.startingUsernameState = .unset
            return mock
        }()
        svr = SecureValueRecoveryMock()
        svrAuthCredentialManager = SVRAuthCredentialManager.mock()
        mockMessagePipelineSupervisor = RegistrationCoordinatorImpl.TestMocks.MessagePipelineSupervisor()
        mockMessageProcessor = RegistrationCoordinatorImpl.TestMocks.MessageProcessor()
        mockUsernamesService = MockUsernamesService()
        networkManagerMock = MockNetworkManager()
        ows2FAManagerMock = RegistrationCoordinatorImpl.TestMocks.OWS2FAManager()
        phoneNumberDiscoverabilityManagerMock = MockPhoneNumberDiscoverabilityManager()
        preKeyManagerMock = RegistrationCoordinatorImpl.TestMocks.PreKeyManager(run: testRun)
        profileManagerMock = RegistrationCoordinatorImpl.TestMocks.ProfileManager()
        pushRegistrationManagerMock = RegistrationCoordinatorImpl.TestMocks.PushRegistrationManager(run: testRun)
        receiptManagerMock = RegistrationCoordinatorImpl.TestMocks.ReceiptManager()
        registrationStateChangeManagerMock = MockRegistrationStateChangeManager()
        sessionManager = RegistrationSessionManagerMock()
        storageServiceManagerMock = RegistrationCoordinatorImpl.TestMocks.StorageServiceManager(run: testRun)
        timeoutProviderMock = RegistrationCoordinatorImpl.TestMocks.TimeoutProvider()
        tsAccountManagerMock = MockTSAccountManager()

        let recipientDbTable = RecipientDatabaseTable()
        let recipientFetcher = RecipientFetcher(
            recipientDatabaseTable: recipientDbTable,
            searchableNameIndexer: MockSearchableNameIndexer(),
        )
        let recipientIdFinder = RecipientIdFinder(
            recipientDatabaseTable: recipientDbTable,
            recipientFetcher: recipientFetcher,
        )
        mockIdentityManager = MockIdentityManager(recipientIdFinder: recipientIdFinder)

        quickRestoreManager = QuickRestoreManager(
            accountKeyStore: accountKeyStore,
            backupNonceStore: BackupNonceMetadataStore(),
            backupSettingsStore: BackupSettingsStore(),
            db: db,
            deviceProvisioningService: DeviceProvisioningServiceImpl(networkManager: networkManagerMock),
            identityManager: mockIdentityManager,
            networkManager: networkManagerMock,
            tsAccountManager: tsAccountManagerMock,
        )

        let localFileBackupManager = LocalFileBackupManager(
            appReadiness: AppReadinessMock(),
            db: db,
            dateProvider: { Date() },
            attachmentStore: AttachmentStore(),
            attachmentValidator: AttachmentContentValidatorMock(),
            orphanedAttachmentCleaner: OrphanedAttachmentCleanerImpl(dateProvider: { Date() }, db: db),
            localFileBackupAttachmentMetadataStore: LocalFileBackupAttachmentMetadataStore(),
            localFileBackupStore: LocalFileBackupStore(),
            securityScopedBookmarkAccess: SecurityScopedBookmarkAccessMock(hasAccess: true, url: nil),
            restoreProgress: LocalFileBackupAttachmentRestoreProgress(),
        )

        let dependencies = RegistrationCoordinatorDependencies(
            appExpiry: appExpiry,
            accountEntropyPoolGenerator: { Stubs.accountEntropyPoolToGenerate },
            accountKeyStore: accountKeyStore,
            backupArchiveManager: BackupArchiveManagerMock(),
            backupIdService: MockBackupIdService(),
            backupNonceStore: BackupNonceMetadataStore(),
            backupRequestManager: BackupRequestManagerMock(),
            changeNumberPniManager: changeNumberPniManager,
            contactsManager: RegistrationCoordinatorImpl.TestMocks.ContactsManager(),
            contactsStore: contactsStore,
            dateProvider: { self.dateProvider() },
            db: db,
            deviceSleepManager: DeviceSleepManagerMock(),
            deviceTransferRestore: DeviceTransferRestoreMock(),
            experienceManager: experienceManager,
            identityManager: RegistrationCoordinatorImpl.TestMocks.IdentityManager(),
            localFileBackupManager: localFileBackupManager,
            localUsernameManager: localUsernameManagerMock,
            messagePipelineSupervisor: mockMessagePipelineSupervisor,
            messageProcessor: mockMessageProcessor,
            networkManager: networkManagerMock,
            ows2FAManager: ows2FAManagerMock,
            phoneNumberDiscoverabilityManager: phoneNumberDiscoverabilityManagerMock,
            preKeyManager: preKeyManagerMock,
            profileManager: profileManagerMock,
            pushRegistrationManager: pushRegistrationManagerMock,
            quickRestoreManager: quickRestoreManager,
            receiptManager: receiptManagerMock,
            registrationBackupErrorPresenter: RegistrationCoordinatorBackupErrorPresenterMock(),
            registrationStateChangeManager: registrationStateChangeManagerMock,
            registrationWebSocketManager: MockRegistrationWebSocketManager(),
            remoteConfigManager: StubbableRemoteConfigManager(),
            securityScopedBookmarkAccess: SecurityScopedBookmarkAccessMock(hasAccess: true, url: nil),
            serviceProvider: MockServiceProvider(mockServices: [mockUsernamesService!]),
            sessionManager: sessionManager,
            signalService: OWSSignalServiceMock(),
            storageServiceManager: storageServiceManagerMock,
            svr: svr,
            svrLocalStorage: SVRLocalStorage(),
            svrAuthCredentialManager: svrAuthCredentialManager,
            timeoutProvider: timeoutProviderMock,
            tsAccountManager: tsAccountManagerMock,
            udManager: RegistrationCoordinatorImpl.TestMocks.UDManager(),
        )
        registrationCoordinatorLoader = RegistrationCoordinatorLoaderImpl(dependencies: dependencies)
    }

    static let testModes: [RegistrationMode] = [
        RegistrationMode.registering,
        RegistrationMode.reRegistering(.phoneNumberfull(phoneNumber: Stubs.e164.stringValue, aci: Stubs.aci)),
    ]

    struct TestCase {
        var mode: RegistrationMode
    }

    static func onlyReRegisteringTestCases() -> [TestCase] {
        return buildTestCases(for: [
            RegistrationMode.reRegistering(.phoneNumberfull(phoneNumber: Stubs.e164.stringValue, aci: Stubs.aci)),
        ])
    }

    static func testCases() -> [TestCase] {
        return buildTestCases(for: testModes)
    }

    static func buildTestCases(for modes: [RegistrationMode]) -> [TestCase] {
        var results = [TestCase]()
        for mode in modes {
            results.append(TestCase(mode: mode))
        }
        return results
    }

    func setupTest(_ testCase: TestCase) -> RegistrationCoordinatorImpl {
        return setUpTest(forMode: testCase.mode)
    }

    private func setUpTest(forMode mode: RegistrationMode) -> RegistrationCoordinatorImpl {
        return db.write {
            return registrationCoordinatorLoader.coordinator(
                forDesiredMode: mode,
                transaction: $0,
                logger: .empty(),
            ) as! RegistrationCoordinatorImpl
        }
    }

    enum TestStep: String, Equatable, CustomDebugStringConvertible {
        case restoreKeys
        case requestPushToken
        case createPreKeys
        case resetOneTimePreKeyTimestamp
        case createAccount
        case finalizePreKeys
        case restoreStorageService
        case markPinEnabled
        case confirmReservedUsername
        case rotateManifest
        case updateAccountAttribute
        case failedRequest

        var debugDescription: String {
            switch self {
            case .restoreKeys: return "restoreKeys"
            case .requestPushToken: return "requestPushToken"
            case .createPreKeys: return "createPreKeys"
            case .resetOneTimePreKeyTimestamp: return "resetOneTimePreKeyTimestamp"
            case .createAccount: return "createAccount"
            case .finalizePreKeys: return "finalizePreKeys"
            case .restoreStorageService: return "restoreStorageService"
            case .markPinEnabled: return "markPinEnabled"
            case .confirmReservedUsername: return "confirmReservedUsername"
            case .rotateManifest: return "rotateManifest"
            case .updateAccountAttribute: return "updateAccountAttribute"
            case .failedRequest: return "failedRequest"
            }
        }
    }

    // MARK: - Opening Path

    @MainActor @Test(arguments: Self.testCases())
    func testOpeningPath_splash(testCase: TestCase) async {
        let coordinator = setupTest(testCase)
        let mode = testCase.mode

        setupDefaultAccountAttributes()

        switch mode {
        case .registering:
            // With no state set up, should show the splash.
            #expect(await coordinator.nextStep().isRegistrationSplash)
            // Once we show it, don't show it again.
            coordinator.continueFromSplash()
            #expect(await !coordinator.nextStep().isRegistrationSplash)
        case .reRegistering, .changingNumber:
            #expect(await !coordinator.nextStep().isRegistrationSplash)
        }
    }

    @MainActor @Test(arguments: Self.testCases())
    func testOpeningPath_appExpired(testCase: TestCase) async {
        let coordinator = setupTest(testCase)

        self.stubs.date = .distantFuture

        setupDefaultAccountAttributes()

        // We should start with the banner.
        #expect(await coordinator.nextStep().isAppUpdateBanner)
    }

    @MainActor @Test(arguments: Self.testCases())
    func testOpeningPath_permissions(testCase: TestCase) async {
        let coordinator = setupTest(testCase)
        let mode = testCase.mode

        setupDefaultAccountAttributes()

        contactsStore.doesNeedContactsAuthorization = true
        pushRegistrationManagerMock.doesNeedNotificationAuthorization = true

        var nextStep: RegistrationStep
        switch mode {
        case .registering:
            // Gotta get the splash out of the way.
            #expect(await coordinator.nextStep().isRegistrationSplash)
            coordinator.continueFromSplash()
            nextStep = await coordinator.nextStep()
        case .reRegistering, .changingNumber:
            // No splash for these.
            nextStep = await coordinator.nextStep()
        }

        // Now we should show the permissions.
        #expect(nextStep.isPermissions)
        // Doesn't change even if we try and proceed.
        #expect(await coordinator.nextStep().isPermissions)

        // Once the state is updated we can proceed.
        nextStep = await coordinator.requestPermissions().awaitable()
        #expect(!nextStep.isRegistrationSplash)
        #expect(!nextStep.isPermissions)
    }

    // MARK: - Reg Recovery Password Path

    @MainActor @Test(arguments: Self.testCases(), [true, false])
    func runRegRecoverPwPathTestHappyPath(testCase: TestCase, wasReglockEnabled: Bool) async throws {
        let coordinator = setupTest(testCase)

        // Set profile info so we skip those steps.
        setupDefaultAccountAttributes()

        ows2FAManagerMock.isReglockEnabledMock = { wasReglockEnabled }

        // Set a PIN on disk.
        ows2FAManagerMock.pinCodeMock = { Stubs.pinCode }
        ows2FAManagerMock.shouldMasterKeyBeBackedUpMock = { true }

        let aep = buildKeyDataMocks(testCase)
        let initialMasterKey = aep.getMasterKey()

        // Give it the pin code, which should make it try and register.

        // It needs an apns token to register.
        pushRegistrationManagerMock.addRequestPushTokenMock({ .success(Stubs.apnsRegistrationId) })
        // It needs prekeys as well.
        preKeyManagerMock.addCreatePreKeysMock(Stubs.preKeyBundle(identity:))
        preKeyManagerMock.addCreatePreKeysMock(Stubs.preKeyBundle(identity:))
        // And will finalize prekeys after success.
        preKeyManagerMock.addFinalizePreKeyBundleMock { _ in }
        preKeyManagerMock.addFinalizePreKeyBundleMock { _ in }

        let identityResponse = Stubs.accountIdentityResponse()
        var authPassword: String!
        let expectedRequest = createAccountWithRecoveryPw(initialMasterKey.deriveRegistrationRecoveryPassword())
        networkManagerMock.asyncRequestHandlers.append(MockNetworkManager.mockResponse(
            matchingRequest: { request in
                // The password is generated internally by RegistrationCoordinator.
                // Extract it so we can check that the same password sent to the server
                // to register is used later for other requests.
                authPassword = request.authPassword
                let requestAttributes = Self.attributesFromCreateAccountRequest(request)
                let recoveryPw = initialMasterKey.regRecoveryPw
                #expect(recoveryPw == (request.parameters["recoveryPassword"] as? String) ?? "")
                #expect(recoveryPw == requestAttributes.registrationRecoveryPassword)
                if wasReglockEnabled {
                    #expect(initialMasterKey.reglockToken == requestAttributes.registrationLockToken)
                } else {
                    #expect(requestAttributes.registrationLockToken == nil)
                }
                return request.url == expectedRequest.url
            },
            statusCode: 200,
            bodyJson: identityResponse,
        ))

        func expectedAuth() -> ChatServiceAuth {
            return ChatServiceAuth.explicit(
                aci: identityResponse.localIdentifiers.aci,
                deviceId: .primary,
                password: authPassword,
            )
        }

        var didMarkReglockEnabled = false
        ows2FAManagerMock.didMarkRegistrationLockEnabled = { didMarkReglockEnabled = true }

        // We haven't marked the PIN enabled; that should happen now.
        var didMarkPinEnabled = false
        ows2FAManagerMock.didMarkPinEnabled = { pin in
            #expect(pin == Stubs.pinCode)
            didMarkPinEnabled = true
        }

        // Once we sync push tokens, we should restore from storage service.
        storageServiceManagerMock.addRestoreOrCreateManifestIfNecessaryMock({ auth, masterKeySource in
            #expect(auth.chatServiceAuth == expectedAuth())
            switch masterKeySource {
            case .explicit(let explicitMasterKey):
                #expect(initialMasterKey.rawData == explicitMasterKey.rawData)
            default:
                Issue.record("Unexpected master key used in storage service operation.")
            }
        })

        storageServiceManagerMock.addRotateManifestMock({ _, _ in return .value(()) })

        // Once we restore from storage service, we should attempt to reclaim
        // our username.
        let mockUsernameLink: Usernames.UsernameLink = .mocked
        localUsernameManagerMock.startingUsernameState = .available(username: "boba.42", usernameLink: mockUsernameLink)
        mockUsernamesService.confirmUsernameMocks.set([{ _, _ in
            return mockUsernameLink.handle
        }])

        // Once we do the username reclamation,
        // then we are finished!

        // NOTE: We expect to skip opening path steps because
        // if we have a SVR master key locally, this _must_ be
        // a previously registered device, and we can skip intros.

        // We haven't set a phone number so it should ask for that.
        guard case .phoneNumberEntry = await coordinator.nextStep() else {
            Issue.record("must be phoneNumberEntry")
            return
        }

        // Give it a phone number, which should show the PIN entry step.
        coordinator.submitE164(Stubs.e164)
        // Now it should ask for the PIN to confirm the user knows it.
        guard case .pinEntry(let pinState) = await coordinator.nextStep() else {
            Issue.record("must be pinEntry")
            return
        }
        guard case .enteringExistingPin(skippability: .canSkip, remainingAttempts: _) = pinState.operation else {
            Issue.record("must be enteringExistingPin with skippability")
            return
        }

        #expect(await coordinator.submitPINCode(Stubs.pinCode).awaitable().isDone)

        // Since we set profile info, we should have scheduled a reupload.
        #expect(profileManagerMock.didScheduleReuploadLocalProfile)

        // If we had reglock before registration, it should be re-enabled.
        #expect(wasReglockEnabled == didMarkReglockEnabled)

        #expect(didMarkPinEnabled)
    }

    @MainActor @Test(arguments: Self.testCases())
    func testRegRecoveryPwPath_wrongPIN(testCase: TestCase) async throws {
        let coordinator = setupTest(testCase)

        // Set profile info so we skip those steps.
        setupDefaultAccountAttributes()

        let wrongPinCode = "ABCD"

        // Set a different PIN on disk.
        ows2FAManagerMock.pinCodeMock = { Stubs.pinCode }
        ows2FAManagerMock.shouldMasterKeyBeBackedUpMock = { true }

        let aep = buildKeyDataMocks(testCase)
        let initialMasterKey = aep.getMasterKey()

        // NOTE: We expect to skip opening path steps because
        // if we have a SVR master key locally, this _must_ be
        // a previously registered device, and we can skip intros.

        // Give it the right pin code, which should make it try and register.

        // It needs an apns token to register.
        pushRegistrationManagerMock.addRequestPushTokenMock({ .success(Stubs.apnsRegistrationId) })
        // Every time we register we also ask for prekeys.
        preKeyManagerMock.addCreatePreKeysMock(Stubs.preKeyBundle(identity:))
        preKeyManagerMock.addCreatePreKeysMock(Stubs.preKeyBundle(identity:))
        // And we finalize them after.
        preKeyManagerMock.addFinalizePreKeyBundleMock { _ in }
        preKeyManagerMock.addFinalizePreKeyBundleMock { _ in }

        let identityResponse = Stubs.accountIdentityResponse()
        var authPassword: String!
        let expectedRequest = createAccountWithRecoveryPw(initialMasterKey.deriveRegistrationRecoveryPassword())
        networkManagerMock.asyncRequestHandlers.append(MockNetworkManager.mockResponse(
            matchingRequest: { request in
                authPassword = request.authPassword
                let requestAttributes = Self.attributesFromCreateAccountRequest(request)
                let recoveryPw = initialMasterKey.regRecoveryPw
                #expect(recoveryPw == (request.parameters["recoveryPassword"] as? String) ?? "")
                #expect(recoveryPw == requestAttributes.registrationRecoveryPassword)
                #expect(requestAttributes.registrationLockToken == nil)
                return request.url == expectedRequest.url
            },
            statusCode: 200,
            bodyJson: identityResponse,
        ))

        func expectedAuth() -> ChatServiceAuth {
            return ChatServiceAuth.explicit(
                aci: identityResponse.localIdentifiers.aci,
                deviceId: .primary,
                password: authPassword,
            )
        }

        // We haven't marked the PIN enabled; that should happen now.
        var didMarkPinEnabled = false
        ows2FAManagerMock.didMarkPinEnabled = { pin in
            #expect(pin == Stubs.pinCode)
            didMarkPinEnabled = true
        }

        // Once we sync push tokens, we should restore from storage service.
        storageServiceManagerMock.addRestoreOrCreateManifestIfNecessaryMock({ auth, masterKeySource in
            #expect(auth.chatServiceAuth == expectedAuth())
            switch masterKeySource {
            case .explicit(let explicitMasterKey):
                #expect(initialMasterKey.rawData == explicitMasterKey.rawData)
            default:
                Issue.record("Unexpected master key used in storage service operation.")
            }
        })

        storageServiceManagerMock.addRotateManifestMock({ _, _ in return .value(()) })

        // Once we restore from storage service, we should attempt to reclaim
        // our username. For this test, let's have a corrupted username (and
        // skip reclamation). This should have no impact on the rest of
        // registration.
        localUsernameManagerMock.startingUsernameState = .usernameAndLinkCorrupted

        // Once we do the storage service restore,
        // then we are finished!

        var nextStep = await coordinator.nextStep()

        // We haven't set a phone number so it should ask for that.
        guard case .phoneNumberEntry = nextStep else {
            Issue.record("must be phoneNumberEntry")
            return
        }

        // Give it a phone number, which should show the PIN entry step.
        coordinator.submitE164(Stubs.e164)
        // Now it should ask for the PIN to confirm the user knows it.
        nextStep = await coordinator.nextStep()
        do {
            guard case .pinEntry(let pinState) = nextStep else {
                Issue.record("must be pinEntry")
                return
            }
            guard case .enteringExistingPin(skippability: .canSkip, remainingAttempts: _) = pinState.operation else {
                Issue.record("must be enteringExistingPin with skippability")
                return
            }
        }

        // Give it the wrong PIN, it should reject and give us the same step again.
        nextStep = await coordinator.submitPINCode(wrongPinCode).awaitable()
        do {
            guard case .pinEntry(let pinState) = nextStep else {
                Issue.record("must be pinEntry")
                return
            }
            guard case .enteringExistingPin(skippability: .canSkip, remainingAttempts: 9) = pinState.operation else {
                Issue.record("must be enteringExistingPin with skippability")
                return
            }
        }

        #expect(await coordinator.submitPINCode(Stubs.pinCode).awaitable().isDone)

        // Since we set profile info, we should have scheduled a reupload.
        #expect(profileManagerMock.didScheduleReuploadLocalProfile)

        #expect(didMarkPinEnabled)
    }

    @MainActor @Test(arguments: Self.onlyReRegisteringTestCases())
    func testRegRecoveryPwPath_wrongPassword(testCase: TestCase) async {
        let coordinator = setupTest(testCase)

        // Set profile info so we skip those steps.
        setupDefaultAccountAttributes()

        // Set a PIN on disk.
        ows2FAManagerMock.pinCodeMock = { Stubs.pinCode }
        ows2FAManagerMock.shouldMasterKeyBeBackedUpMock = { true }
        var didClearPinCode = false
        ows2FAManagerMock.clearLocalPinCodeMock = { didClearPinCode = true }

        // Make SVR give us back a reg recovery password.
        let aep = buildKeyDataMocks(testCase)

        // NOTE: We expect to skip opening path steps. If we have an AEP locally,
        // this must be a previously registered device.

        // Before registering, it should ask for push tokens to give the registration.
        // It will also ask again later when account creation fails and it needs
        // to create a new session.
        pushRegistrationManagerMock.addRequestPushTokenMock({ .success(Stubs.apnsRegistrationId) })
        pushRegistrationManagerMock.addRequestPushTokenMock({ .success(Stubs.apnsRegistrationId) })

        // Every time we register we also ask for prekeys.
        preKeyManagerMock.addCreatePreKeysMock(Stubs.preKeyBundle(identity:))
        preKeyManagerMock.addCreatePreKeysMock(Stubs.preKeyBundle(identity:))
        preKeyManagerMock.addCreatePreKeysMock(Stubs.preKeyBundle(identity:))
        preKeyManagerMock.addCreatePreKeysMock(Stubs.preKeyBundle(identity:))

        // And we finalize them after.
        // Set up a list of mocks that should be returned in order
        preKeyManagerMock.addFinalizePreKeyBundleMock { _ in }
        preKeyManagerMock.addFinalizePreKeyBundleMock { _ in }

        // Fail the request; the reg recovery pw is invalid.
        let expectedRecoveryPwRequest = createAccountWithRecoveryPw(aep.getMasterKey().deriveRegistrationRecoveryPassword())
        networkManagerMock.asyncRequestHandlers.append(MockNetworkManager.mockResponse(
            matchingRequest: { $0.url == expectedRecoveryPwRequest.url },
            statusCode: 401,
        ))

        // Once the first request fails, it should try an start a session. Resolve with a session.
        let expectedSession = stubs.session()
        sessionManager.addBeginSessionResponseMock({ expectedSession })

        // Before requesting a session, it should ask for push tokens to give the session.
        // This was set up above.

        // Then when it gets back the session, it should immediately ask for a verification code to be sent.

        // We'll ask for a push challenge, though we don't need to resolve it in this test.
        pushRegistrationManagerMock.setReceivePreAuthChallengeTokenMock({ "PUSH TOKEN" })

        // Resolve with an updated session.
        sessionManager.addRequestCodeResponseMock(.success(stubs.session(nextVerificationAttempt: 0)))

        var nextStep = await coordinator.nextStep()

        // We haven't set a phone number so it should ask for that.
        guard case .phoneNumberEntry = nextStep else {
            Issue.record("must be phoneNumberEntry")
            return
        }

        // Give it a phone number, which should show the PIN entry step.
        coordinator.submitE164(Stubs.e164)
        // Now it should ask for the PIN to confirm the user knows it.
        nextStep = await coordinator.nextStep()
        guard case .pinEntry(let pinState) = nextStep else {
            Issue.record("must be pinEntry")
            return
        }
        guard case .enteringExistingPin(skippability: .canSkip, remainingAttempts: _) = pinState.operation else {
            Issue.record("must be enteringExistingPin with skippability")
            return
        }

        // Check we have the master key now, to be safe.
        #expect(!didClearPinCode)

        // Give it the pin code, which should make it try and register.
        nextStep = await coordinator.submitPINCode(Stubs.pinCode).awaitable()
        // Now we should expect to be at verification code entry since we already set the phone number.
        guard case .verificationCodeEntry(let codeState) = nextStep else {
            Issue.record("must be verificationCodeEntry")
            return
        }
        #expect(codeState.validationError == nil)

        // We want to have kept the master key; we failed the reg recovery pw check
        // but that could happen even if the key is valid. Once we finish session based
        // re-registration we want to be able to recover the key.
        #expect(!didClearPinCode)
    }

    @MainActor @Test(arguments: Self.onlyReRegisteringTestCases())
    func testRegRecoveryPwPath_failedReglock(testCase: TestCase) async {
        let coordinator = setupTest(testCase)

        // Set profile info so we skip those steps.
        setupDefaultAccountAttributes()

        // Set a PIN on disk.
        ows2FAManagerMock.pinCodeMock = { Stubs.pinCode }
        ows2FAManagerMock.shouldMasterKeyBeBackedUpMock = { true }
        var didClearPinCode = false
        ows2FAManagerMock.clearLocalPinCodeMock = { didClearPinCode = true }

        // Make SVR give us back a reg recovery password.
        let aep = buildKeyDataMocks(testCase)

        // NOTE: We expect to skip opening path steps. If we have an AEP locally,
        // this must be a previously registered device.

        // First we try and create an account with reg recovery
        // password; we will fail with reglock error.
        // First we get apns tokens, then prekeys, then register
        // then finalize prekeys (with failure) after.

        // Once we fail, we try again immediately with the reglock
        // token we fetch.
        // Same sequence as the first request.

        // When that fails, we try and create a session.
        // No prekey stuff this time, just apns token and session requests.

        pushRegistrationManagerMock.addRequestPushTokenMock({ .success(Stubs.apnsRegistrationId) })
        pushRegistrationManagerMock.addRequestPushTokenMock({ .success(Stubs.apnsRegistrationId) })
        pushRegistrationManagerMock.addRequestPushTokenMock({ .success(Stubs.apnsRegistrationId) })
        pushRegistrationManagerMock.addRequestPushTokenMock({ .success(Stubs.apnsRegistrationId) })

        preKeyManagerMock.addCreatePreKeysMock(Stubs.preKeyBundle(identity:))
        preKeyManagerMock.addCreatePreKeysMock(Stubs.preKeyBundle(identity:))
        preKeyManagerMock.addCreatePreKeysMock(Stubs.preKeyBundle(identity:))
        preKeyManagerMock.addCreatePreKeysMock(Stubs.preKeyBundle(identity:))
        preKeyManagerMock.addCreatePreKeysMock(Stubs.preKeyBundle(identity:))
        preKeyManagerMock.addCreatePreKeysMock(Stubs.preKeyBundle(identity:))

        // Fail the first request; the reglock is invalid.
        let expectedRecoveryPwRequest = createAccountWithRecoveryPw(aep.getMasterKey().deriveRegistrationRecoveryPassword())
        let failResponse = MockNetworkManager.mockResponse(
            matchingRequest: { $0.url == expectedRecoveryPwRequest.url },
            statusCode: 423,
            bodyJson: EncodableRegistrationLockFailureResponse(
                timeRemainingMs: 10,
                svr2AuthCredential: Stubs.svr2AuthCredential,
            ),
        )
        networkManagerMock.asyncRequestHandlers.append(failResponse)

        // Once the request fails, we should try again with the reglock
        // token, this time.
        networkManagerMock.asyncRequestHandlers.append(failResponse)

        // Once the second request fails, it should try an start a session.

        // We'll ask for a push challenge, though we don't need to resolve it in this test.
        pushRegistrationManagerMock.setReceivePreAuthChallengeTokenMock({
            try! await Task.sleep(nanoseconds: TimeInterval.infinity.clampedNanoseconds)
            fatalError()
        })

        // Resolve with a session.
        let expectedSession = stubs.session()
        sessionManager.addBeginSessionResponseMock({ expectedSession })

        // Then when it gets back the session, it should immediately ask for
        // a verification code to be sent.

        // Resolve with an updated session.
        sessionManager.addRequestCodeResponseMock(.success(stubs.session(nextVerificationAttempt: 0)))

        var nextStep = await coordinator.nextStep()

        // We haven't set a phone number so it should ask for that.
        guard case .phoneNumberEntry = nextStep else {
            Issue.record("must be phoneNumberEntry")
            return
        }

        // Give it a phone number, which should show the PIN entry step.
        coordinator.submitE164(Stubs.e164)
        // Now it should ask for the PIN to confirm the user knows it.
        nextStep = await coordinator.nextStep()
        guard case .pinEntry(let pinState) = nextStep else {
            Issue.record("must be pinEntry")
            return
        }
        guard case .enteringExistingPin(skippability: .canSkip, remainingAttempts: _) = pinState.operation else {
            Issue.record("must be enteringExistingPin with skippability")
            return
        }
        #expect(!didClearPinCode)

        // Give it the pin code, which should make it try and register.
        nextStep = await coordinator.submitPINCode(Stubs.pinCode).awaitable()
        guard case .verificationCodeEntry(let codeState) = nextStep else {
            Issue.record("must be verificationCodeEntry")
            return
        }
        #expect(codeState.validationError == nil)
        // We want to have wiped our master key; we failed reglock, which means the key itself is wrong
        #expect(didClearPinCode)
    }

    @MainActor @Test(arguments: Self.testCases())
    func testRegRecoveryPwPath_retryNetworkError(testCase: TestCase) async throws {
        let coordinator = setupTest(testCase)

        // Set profile info so we skip those steps.
        setupDefaultAccountAttributes()

        // Set a PIN on disk.
        ows2FAManagerMock.pinCodeMock = { Stubs.pinCode }
        ows2FAManagerMock.shouldMasterKeyBeBackedUpMock = { true }

        let aep = buildKeyDataMocks(testCase)
        let initialMasterKey = aep.getMasterKey()
        let finalMasterKey = aep.getMasterKey()

        // Before registering, it should ask for push tokens to give the registration.
        // When it retries, it will ask again.
        pushRegistrationManagerMock.addRequestPushTokenMock({ .success(Stubs.apnsRegistrationId) })
        pushRegistrationManagerMock.addRequestPushTokenMock({ .success(Stubs.apnsRegistrationId) })

        // Every time we register we also ask for prekeys.
        preKeyManagerMock.addCreatePreKeysMock(Stubs.preKeyBundle(identity:))
        preKeyManagerMock.addCreatePreKeysMock(Stubs.preKeyBundle(identity:))
        preKeyManagerMock.addCreatePreKeysMock(Stubs.preKeyBundle(identity:))
        preKeyManagerMock.addCreatePreKeysMock(Stubs.preKeyBundle(identity:))

        // And we finalize them after.
        preKeyManagerMock.addFinalizePreKeyBundleMock { _ in }
        preKeyManagerMock.addFinalizePreKeyBundleMock { _ in }

        // Fail the request with a network error.
        networkManagerMock.asyncRequestHandlers.append({ _, _ in
            self.testRun.addObservedStep(.failedRequest)
            throw OWSHTTPError.networkFailure(.unknownNetworkFailure)
        })

        let identityResponse = Stubs.accountIdentityResponse()
        var authPassword: String!

        // Once the first request fails, it should retry. Resolve with success
        let expectedRequest = createAccountWithRecoveryPw(initialMasterKey.deriveRegistrationRecoveryPassword())
        networkManagerMock.asyncRequestHandlers.append(MockNetworkManager.mockResponse(
            matchingRequest: { request in
                if request.url == expectedRequest.url {
                    self.testRun.addObservedStep(.createAccount)
                    // The password is generated internally by RegistrationCoordinator.
                    // Extract it so we can check that the same password sent to the server
                    // to register is used later for other requests.
                    authPassword = request.authPassword
                    return true
                }
                return false
            },
            statusCode: 200,
            bodyJson: identityResponse,
        ))

        func expectedAuth() -> ChatServiceAuth {
            return ChatServiceAuth.explicit(
                aci: identityResponse.localIdentifiers.aci,
                deviceId: .primary,
                password: authPassword,
            )
        }

        // We haven't marked the PIN enabled; that should happen.
        ows2FAManagerMock.didMarkPinEnabled = { pin in
            self.testRun.addObservedStep(.markPinEnabled)
            #expect(pin == Stubs.pinCode)
        }

        // Once we back up to svr, we should restore from storage service.
        storageServiceManagerMock.addRestoreOrCreateManifestIfNecessaryMock({ auth, masterKeySource in
            #expect(auth.chatServiceAuth == expectedAuth())
            switch masterKeySource {
            case .explicit(let explicitMasterKey):
                #expect(initialMasterKey.rawData == explicitMasterKey.rawData)
            default:
                Issue.record("Unexpected master key used in storage service operation.")
            }
        })

        storageServiceManagerMock.addRestoreOrCreateManifestIfNecessaryMock({ auth, masterKeySource in
            #expect(auth.chatServiceAuth == expectedAuth())
            switch masterKeySource {
            case .explicit(let explicitMasterKey):
                #expect(finalMasterKey.rawData == explicitMasterKey.rawData)
            default:
                Issue.record("Unexpected master key used in storage service operation.")
            }
        })

        storageServiceManagerMock.addRotateManifestMock({ _, _ in return .value(()) })

        // Once we restore from storage service, we should attempt to reclaim our username.
        let mockUsernameLink: Usernames.UsernameLink = .mocked
        localUsernameManagerMock.startingUsernameState = .available(username: "boba.42", usernameLink: mockUsernameLink)
        mockUsernamesService.confirmUsernameMocks.set([{ _, _ in
            self.testRun.addObservedStep(.confirmReservedUsername)
            return mockUsernameLink.handle
        }])

        // Once we do the storage service restore,
        // then we are finished!

        var nextStep = await coordinator.nextStep()

        // We haven't set a phone number so it should ask for that.
        guard case .phoneNumberEntry = nextStep else {
            Issue.record("must be phoneNumberEntry")
            return
        }

        // Give it a phone number, which should show the PIN entry step.
        coordinator.submitE164(Stubs.e164)
        // Now it should ask for the PIN to confirm the user knows it.
        nextStep = await coordinator.nextStep()
        guard case .pinEntry(let pinState) = nextStep else {
            Issue.record("must be pinEntry")
            return
        }
        guard case .enteringExistingPin(skippability: .canSkip, remainingAttempts: _) = pinState.operation else {
            Issue.record("must be enteringExistingPin with skippability")
            return
        }

        // Give it the pin code, which should make it try and register.
        nextStep = await coordinator.submitPINCode(Stubs.pinCode).awaitable()
        #expect(nextStep.isDone)

        let expectedSteps: [TestStep] = [
            .requestPushToken,
            .createPreKeys,
            .createPreKeys,
            .failedRequest,
            .requestPushToken,
            .createPreKeys,
            .createPreKeys,
            .createAccount,
            .finalizePreKeys,
            .finalizePreKeys,
            .markPinEnabled,
            .restoreStorageService,
            .confirmReservedUsername,
            .resetOneTimePreKeyTimestamp,
            .rotateManifest,
        ]

        #expect(testRun.recordedSteps == expectedSteps)

        // Since we set profile info, we should have scheduled a reupload.
        #expect(profileManagerMock.didScheduleReuploadLocalProfile)
    }

    // Test the reglock path when a user has a local password
    // Tests a similar path to testRegRecoveryPwPath_failedReglock above,
    // but returns a `regRecoveryPasswordRejected` error in the first
    // createAccount attempt, since this is the path that happens in the app.
    // Keeping 'testRegRecoveryPwPath_failedReglock' around since it's still
    // technically a possible path and should still be validated.
    @MainActor @Test(arguments: Self.onlyReRegisteringTestCases())
    func testRegRecoveryPwPath_failedReglock2(testCase: TestCase) async {
        let coordinator = setupTest(testCase)

        // Set profile info so we skip those steps.
        setupDefaultAccountAttributes()

        // Set a PIN on disk.
        ows2FAManagerMock.pinCodeMock = { Stubs.pinCode }
        ows2FAManagerMock.shouldMasterKeyBeBackedUpMock = { true }
        var didClearPinCode = false
        ows2FAManagerMock.clearLocalPinCodeMock = { didClearPinCode = true }
        ows2FAManagerMock.isReglockEnabledMock = { true }

        // Make SVR give us back a reg recovery password.
        let aep = buildKeyDataMocks(testCase)

        // NOTE: We expect to skip opening path steps. If we have an AEP locally,
        // this must be a previously registered device.

        // First we try and create an account with reg recovery
        // password; we will fail with reglock error.
        // First we get apns tokens, then prekeys, then register
        // then finalize prekeys (with failure) after.

        // Once we fail, we try again immediately with the reglock
        // token we fetch.
        // Same sequence as the first request.

        // When that fails, we try and create a session.
        // No prekey stuff this time, just apns token and session requests.

        pushRegistrationManagerMock.addRequestPushTokenMock({ .success(Stubs.apnsRegistrationId) })
        pushRegistrationManagerMock.addRequestPushTokenMock({ .success(Stubs.apnsRegistrationId) })
        pushRegistrationManagerMock.addRequestPushTokenMock({ .success(Stubs.apnsRegistrationId) })
        pushRegistrationManagerMock.addRequestPushTokenMock({ .success(Stubs.apnsRegistrationId) })

        preKeyManagerMock.addCreatePreKeysMock(Stubs.preKeyBundle(identity:))
        preKeyManagerMock.addCreatePreKeysMock(Stubs.preKeyBundle(identity:))
        preKeyManagerMock.addCreatePreKeysMock(Stubs.preKeyBundle(identity:))
        preKeyManagerMock.addCreatePreKeysMock(Stubs.preKeyBundle(identity:))

        // Fail the first request;
        let expectedRecoveryPwRequest = createAccountWithRecoveryPw(aep.getMasterKey().deriveRegistrationRecoveryPassword())
        networkManagerMock.asyncRequestHandlers.append(MockNetworkManager.mockResponse(
            matchingRequest: { $0.url == expectedRecoveryPwRequest.url },
            statusCode: 403,
        ))

        // Once the first request fails, it should try an start a session.
        // We'll ask for a push challenge, though we don't need to resolve it in this test.
        pushRegistrationManagerMock.setReceivePreAuthChallengeTokenMock({
            try! await Task.sleep(nanoseconds: TimeInterval.infinity.clampedNanoseconds)
            fatalError()
        })

        // Resolve with a session.
        let expectedSession = stubs.session()
        sessionManager.addBeginSessionResponseMock({ expectedSession })

        // Then when it gets back the session, it should immediately ask for
        // a verification code to be sent.
        // Resolve with an updated session.

        sessionManager.addRequestCodeResponseMock(.success(stubs.session(nextVerificationAttempt: 0)))

        // Give back an valid session.
        sessionManager.addSubmitCodeResponseMock(.success(stubs.session(
            receivedDate: date,
            verified: true,
        )))

        // Once the request fails, we should try again with the reglock
        // token, this time.
        let expectedRecoveryPwRequest2 = createAccountWithSession(recoveryPassword: aep.getMasterKey().deriveRegistrationRecoveryPassword())
        networkManagerMock.asyncRequestHandlers.append(MockNetworkManager.mockResponse(
            matchingRequest: { $0.url == expectedRecoveryPwRequest2.url },
            statusCode: 423,
            bodyJson: EncodableRegistrationLockFailureResponse(
                timeRemainingMs: 10000,
                svr2AuthCredential: Stubs.svr2AuthCredential,
            ),
        ))

        #expect(!didClearPinCode)

        var nextStep = await coordinator.nextStep()

        // We haven't set a phone number so it should ask for that.
        guard case .phoneNumberEntry = nextStep else {
            Issue.record("must be phoneNumberEntry")
            return
        }

        // Give it a phone number, which should show the PIN entry step.
        coordinator.submitE164(Stubs.e164)
        // Now it should ask for the PIN to confirm the user knows it.
        nextStep = await coordinator.nextStep()
        guard case .pinEntry(let pinState) = nextStep else {
            Issue.record("must be pinEntry")
            return
        }
        guard case .enteringExistingPin(skippability: .canSkip, remainingAttempts: _) = pinState.operation else {
            Issue.record("must be enteringExistingPin with skippability")
            return
        }

        // Give it the pin code, which should make it try and register.
        _ = await coordinator.submitPINCode(Stubs.pinCode).awaitable()

        nextStep = await coordinator.submitVerificationCode(Stubs.pinCode).awaitable()
        guard case .enterRecoveryKey(let recoveryKeyState) = nextStep else {
            Issue.record("must be enterRecoveryKey")
            return
        }
        #expect(!recoveryKeyState.canShowBackButton)
        #expect(!recoveryKeyState.canShowNoKeyHelpButton)

        // We want to have wiped our master key; we failed reglock, which means the key itself is wrong.
        #expect(!didClearPinCode)
    }

    // Test the path where a the local masterkey is no longer in sync with the one storedin SVR
    // This can happen a lot more often in an AEP enabled world, which means that during registration
    // we may need to go fetch the current key from SVR after failing the first registration attempt
    @MainActor @Test(arguments: Self.onlyReRegisteringTestCases())
    func testRegRecoveryPwPath_reglock_failedLocalCredentials(testCase: TestCase) async {
        let coordinator = setupTest(testCase)

        // Set profile info so we skip those steps.
        setupDefaultAccountAttributes()

        // Set a PIN on disk.
        ows2FAManagerMock.pinCodeMock = { Stubs.pinCode }
        ows2FAManagerMock.shouldMasterKeyBeBackedUpMock = { true }
        var didClearPinCode = false
        ows2FAManagerMock.clearLocalPinCodeMock = { didClearPinCode = true }
        ows2FAManagerMock.isReglockEnabledMock = { true }

        // Make SVR give us back a reg recovery password.
        let aep = buildKeyDataMocks(testCase)
        let masterKey = aep.getMasterKey()
        let remoteMasterKey = MasterKey()
        // For non-AEP, we will replace the local key with the remote key.
        // For AEP, we'll rotate to a new AEP (or use the existing local AEP if it's present)

        // Put some auth credentials in storage.
        let svr2CredentialCandidates: [SVR2AuthCredential] = [
            Stubs.svr2AuthCredential,
        ]
        storeSvrCredentials(svr2CredentialCandidates)

        // NOTE: We expect to skip opening path steps because
        // if we have a SVR master key locally, this _must_ be
        // a previously registered device, and we can skip intros.
        svr.restoreKeysMock = { pin, authMethod in
            #expect(pin == Stubs.pinCode)
            if case .svrAuth(Stubs.svr2AuthCredential, backup: nil) = authMethod {
            } else {
                Issue.record("wrong authMethod: \(authMethod)")
            }
            return .value(.success(remoteMasterKey))
        }

        // First we try and create an account with reg recovery
        // password; we will fail with reglock error.
        // First we get apns tokens, then prekeys, then register
        // then finalize prekeys (with failure) after.

        // Once we fail, attempt to fetch the remote SVR credential and attempt RRP again
        // Same sequence as the first request.

        pushRegistrationManagerMock.addRequestPushTokenMock({ .success(Stubs.apnsRegistrationId) })
        pushRegistrationManagerMock.addRequestPushTokenMock({ .success(Stubs.apnsRegistrationId) })
        pushRegistrationManagerMock.addRequestPushTokenMock({ .success(Stubs.apnsRegistrationId) })

        preKeyManagerMock.addCreatePreKeysMock(Stubs.preKeyBundle(identity:))
        preKeyManagerMock.addCreatePreKeysMock(Stubs.preKeyBundle(identity:))
        preKeyManagerMock.addCreatePreKeysMock(Stubs.preKeyBundle(identity:))
        preKeyManagerMock.addCreatePreKeysMock(Stubs.preKeyBundle(identity:))

        preKeyManagerMock.addFinalizePreKeyBundleMock { _ in }
        preKeyManagerMock.addFinalizePreKeyBundleMock { _ in }

        // Fail the first request; the reglock is invalid.
        let expectedRecoveryPwRequest = createAccountWithRecoveryPw(masterKey.deriveRegistrationRecoveryPassword())
        networkManagerMock.asyncRequestHandlers.append(MockNetworkManager.mockResponse(
            matchingRequest: { $0.url == expectedRecoveryPwRequest.url },
            statusCode: 403,
        ))

        let expectedSVR2CheckRequest = RegistrationRequestFactory.svr2AuthCredentialCheckRequest(
            e164: Stubs.e164,
            credentials: svr2CredentialCandidates,
            logger: .empty(),
        )
        networkManagerMock.asyncRequestHandlers.append(MockNetworkManager.mockResponse(
            matchingRequest: { $0.url.relativeString.hasSuffix(expectedSVR2CheckRequest.url.absoluteString) },
            statusCode: 200,
            bodyJson: RegistrationServiceResponses.SVR2AuthCheckResponse(matches: [
                "\(Stubs.svr2AuthCredential.credential.username):\(Stubs.svr2AuthCredential.credential.password)": .match,
            ]),
        ))

        // Once the request fails, we should try again with the reglock
        // token, this time.
        let accountIdentityResponse = Stubs.accountIdentityResponse()
        var authPassword: String!
        let expectedRecoveryPwRequest2 = createAccountWithRecoveryPw(remoteMasterKey.deriveRegistrationRecoveryPassword())
        networkManagerMock.asyncRequestHandlers.append(MockNetworkManager.mockResponse(
            matchingRequest: { request in
                authPassword = request.authPassword
                let requestAttributes = Self.attributesFromCreateAccountRequest(request)
                #expect((request.parameters["recoveryPassword"] as? String) == remoteMasterKey.regRecoveryPw)
                #expect(remoteMasterKey.reglockToken == requestAttributes.registrationLockToken)
                return request.url == expectedRecoveryPwRequest2.url
            },
            statusCode: 200,
            bodyJson: accountIdentityResponse,
        ))

        func expectedAuth() -> ChatServiceAuth {
            return ChatServiceAuth.explicit(
                aci: accountIdentityResponse.localIdentifiers.aci,
                deviceId: .primary,
                password: authPassword,
            )
        }

        var didMarkReglockEnabled = false
        ows2FAManagerMock.didMarkRegistrationLockEnabled = { didMarkReglockEnabled = true }

        // We haven't marked the PIN enabled; that should happen now.
        var didMarkPinEnabled = false
        ows2FAManagerMock.didMarkPinEnabled = { pin in
            #expect(pin == Stubs.pinCode)
            didMarkPinEnabled = true
        }

        // Once we sync push tokens, we should restore from storage service.
        storageServiceManagerMock.addRestoreOrCreateManifestIfNecessaryMock({ auth, masterKeySource in
            #expect(auth.chatServiceAuth == expectedAuth())
            switch masterKeySource {
            case .explicit(let explicitMasterKey):
                #expect(remoteMasterKey.rawData == explicitMasterKey.rawData)
            default:
                Issue.record("Unexpected master key used in storage service operation.")
            }
        })

        // Once we restore from storage service, we should attempt to reclaim
        // our username.
        let mockUsernameLink: Usernames.UsernameLink = .mocked
        localUsernameManagerMock.startingUsernameState = .available(username: "boba.42", usernameLink: mockUsernameLink)
        mockUsernamesService.confirmUsernameMocks.set([{ _, _ in
            return mockUsernameLink.handle
        }])

        storageServiceManagerMock.addRotateManifestMock({ _, _ in return .value(()) })

        // Once we do the username reclamation,
        // then we are finished!

        var nextStep = await coordinator.nextStep()

        // We haven't set a phone number so it should ask for that.
        guard case .phoneNumberEntry = nextStep else {
            Issue.record("must be phoneNumberEntry")
            return
        }

        // Give it a phone number, which should show the PIN entry step.
        coordinator.submitE164(Stubs.e164)
        // Now it should ask for the PIN to confirm the user knows it.
        nextStep = await coordinator.nextStep()
        guard case .pinEntry(let pinState) = nextStep else {
            Issue.record("must be pinEntry")
            return
        }
        guard case .enteringExistingPin(skippability: .canSkip, remainingAttempts: _) = pinState.operation else {
            Issue.record("must be enteringExistingPin with skippability")
            return
        }

        #expect(getSvrCredentialUsernames() == [Stubs.svr2AuthCredential.credential.username])

        #expect(!didClearPinCode)

        // Give it the pin code, which should make it try and register.
        #expect(await coordinator.submitPINCode(Stubs.pinCode).awaitable().isDone)

        #expect(!didClearPinCode)

        // If we had reglock before registration, it should be re-enabled.
        #expect(didMarkReglockEnabled)

        #expect(didMarkPinEnabled)
    }

    /// Test the path where both local and remote RRP are rejected due to a reglock challenge
    /// This should result in the following high level flow:
    /// 1. Fail with local master key RRP.  This can be from th remote key being rotated, or a reglock challenge
    /// 2. Fetch the remote master key from SVR
    /// 3. Fail with the remote master key RRP.  This is usually from a reglock challenge
    /// 4. Clear SVR state and attempt to register via session
    /// 5. Fail due to reglock
    /// This should result in the app being in a reglock timeout
    @MainActor @Test(arguments: Self.onlyReRegisteringTestCases())
    func testRegRecoveryPwPath_reglock_localAndRemoteKeysRejected(testCase: TestCase) async {
        let coordinator = setupTest(testCase)

        // Set profile info so we skip those steps.
        setupDefaultAccountAttributes()

        // Set a PIN on disk.
        ows2FAManagerMock.pinCodeMock = { Stubs.pinCode }
        ows2FAManagerMock.shouldMasterKeyBeBackedUpMock = { true }
        var didClearPinCode = false
        ows2FAManagerMock.clearLocalPinCodeMock = { didClearPinCode = true }
        ows2FAManagerMock.isReglockEnabledMock = { true }

        // Make SVR give us back a reg recovery password.
        let aep = buildKeyDataMocks(testCase)
        let masterKey = aep.getMasterKey()
        let remoteMasterKey = MasterKey()
        // For non-AEP, we will replace the local key with the remote key.
        // For AEP, we'll rotate to a new AEP (or use the existing local AEP if it's present)

        // Put some auth credentials in storage.
        let svr2CredentialCandidates: [SVR2AuthCredential] = [
            Stubs.svr2AuthCredential,
        ]
        storeSvrCredentials(svr2CredentialCandidates)

        // NOTE: We expect to skip opening path steps because
        // if we have a SVR master key locally, this _must_ be
        // a previously registered device, and we can skip intros.

        svr.restoreKeysMock = { pin, authMethod in
            #expect(pin == Stubs.pinCode)
            if case .svrAuth(Stubs.svr2AuthCredential, backup: nil) = authMethod {
            } else {
                Issue.record("wrong authMethod: \(authMethod)")
            }
            return .value(.success(remoteMasterKey))
        }

        // First we try and create an account with reg recovery
        // password; we will fail with reglock error.
        // First we get apns tokens, then prekeys, then register
        // then finalize prekeys (with failure) after.

        pushRegistrationManagerMock.addRequestPushTokenMock({ .success(Stubs.apnsRegistrationId) })
        pushRegistrationManagerMock.addRequestPushTokenMock({ .success(Stubs.apnsRegistrationId) })
        pushRegistrationManagerMock.addRequestPushTokenMock({ .success(Stubs.apnsRegistrationId) })
        pushRegistrationManagerMock.addRequestPushTokenMock({ .success(Stubs.apnsRegistrationId) })

        preKeyManagerMock.addCreatePreKeysMock(Stubs.preKeyBundle(identity:))
        preKeyManagerMock.addCreatePreKeysMock(Stubs.preKeyBundle(identity:))
        preKeyManagerMock.addCreatePreKeysMock(Stubs.preKeyBundle(identity:))
        preKeyManagerMock.addCreatePreKeysMock(Stubs.preKeyBundle(identity:))
        preKeyManagerMock.addCreatePreKeysMock(Stubs.preKeyBundle(identity:))
        preKeyManagerMock.addCreatePreKeysMock(Stubs.preKeyBundle(identity:))

        // Fail the first request; the local key is invalid.
        let expectedRecoveryPwRequest = createAccountWithRecoveryPw(masterKey.deriveRegistrationRecoveryPassword())
        let failResponse = MockNetworkManager.mockResponse(
            matchingRequest: { $0.url == expectedRecoveryPwRequest.url },
            statusCode: 403,
        )
        networkManagerMock.asyncRequestHandlers.append(failResponse)

        let expectedSVR2CheckRequest = RegistrationRequestFactory.svr2AuthCredentialCheckRequest(
            e164: Stubs.e164,
            credentials: svr2CredentialCandidates,
            logger: .empty(),
        )
        networkManagerMock.asyncRequestHandlers.append(MockNetworkManager.mockResponse(
            matchingRequest: { $0.url.relativeString.hasSuffix(expectedSVR2CheckRequest.url.absoluteString) },
            statusCode: 200,
            bodyJson: RegistrationServiceResponses.SVR2AuthCheckResponse(matches: [
                "\(Stubs.svr2AuthCredential.credential.username):\(Stubs.svr2AuthCredential.credential.password)": .match,
            ]),
        ))

        networkManagerMock.asyncRequestHandlers.append(failResponse)

        pushRegistrationManagerMock.setReceivePreAuthChallengeTokenMock({
            try! await Task.sleep(nanoseconds: TimeInterval.infinity.clampedNanoseconds)
            fatalError()
        })

        // Resolve with an updated session.
        sessionManager.addRequestCodeResponseMock(.success(stubs.session(nextVerificationAttempt: 0)))

        // Resolve with a session.
        let expectedSession = stubs.session()
        sessionManager.addBeginSessionResponseMock({ expectedSession })

        // Once the request fails, we should try again with the reglock
        // token, this time.
        // The third attempt should fall back to session using the remote key(?)
        let expectedRecoveryPwRequest3 = createAccountWithSession(recoveryPassword: remoteMasterKey.deriveRegistrationRecoveryPassword())
        networkManagerMock.asyncRequestHandlers.append(MockNetworkManager.mockResponse(
            matchingRequest: { $0.url == expectedRecoveryPwRequest3.url },
            statusCode: 423,
            bodyJson: EncodableRegistrationLockFailureResponse(
                timeRemainingMs: 10000,
                svr2AuthCredential: Stubs.svr2AuthCredential,
            ),
        ))

        // Give back a verified session.
        sessionManager.addSubmitCodeResponseMock(.success(stubs.session(verified: true)))

        var nextStep = await coordinator.nextStep()

        // We haven't set a phone number so it should ask for that.
        guard case .phoneNumberEntry = nextStep else {
            Issue.record("must be phoneNumberEntry")
            return
        }
        // Give it a phone number, which should show the PIN entry step.
        coordinator.submitE164(Stubs.e164)
        // Now it should ask for the PIN to confirm the user knows it.
        nextStep = await coordinator.nextStep()
        guard case .pinEntry(let pinState) = nextStep else {
            Issue.record("must be pinEntry")
            return
        }
        guard case .enteringExistingPin(skippability: .canSkip, remainingAttempts: _) = pinState.operation else {
            Issue.record("must be enteringExistingPin with skippability")
            return
        }

        // Give it the pin code, which should make it try and register.
        nextStep = await coordinator.submitPINCode(Stubs.pinCode).awaitable()
        guard case .verificationCodeEntry = nextStep else {
            Issue.record("must be verificationCodeEntry")
            return
        }
        #expect(!didClearPinCode)

        // Submit verification code
        nextStep = await coordinator.submitVerificationCode(Stubs.verificationCode).awaitable()
        guard case .reglockTimeout(let reglockState) = nextStep else {
            Issue.record("must be reglockTimeout")
            return
        }
        let acknowledgeAction: RegistrationReglockTimeoutAcknowledgeAction
        switch testCase.mode {
        case .registering:
            acknowledgeAction = .resetPhoneNumber
        case .reRegistering:
            acknowledgeAction = .close
        case .changingNumber:
            acknowledgeAction = .none
        }
        #expect(reglockState.acknowledgeAction == acknowledgeAction)
        #expect(reglockState.reglockExpirationDate == dateProvider().addingTimeInterval(10))

        // We want to have wiped our master key; we failed reglock, which means the key itself is wrong.
        #expect(!didClearPinCode)
    }

    // MARK: - SVR Auth Credential Path

    @MainActor @Test(arguments: Self.testCases())
    func testSVRAuthCredentialPath_happyPath(testCase: TestCase) async {
        let coordinator = setupTest(testCase)
        let mode = testCase.mode

        setupDefaultAccountAttributes()

        // Set profile info so we skip those steps.
        setAllProfileInfo()

        mockSVRCredentials(isMatch: true)

        // Get past the opening.
        await goThroughOpeningHappyPath(coordinator: coordinator, mode: mode)

        let aep = buildKeyDataMocks(testCase)
        let initialMasterKey = aep.getMasterKey()
        let finalMasterKey = aep.getMasterKey()

        // Resolve the key restoration from SVR and have it start returning the key.
        svr.restoreKeysMock = { pin, authMethod in
            self.testRun.addObservedStep(.restoreKeys)
            #expect(pin == Stubs.pinCode)
            if case .svrAuth(Stubs.svr2AuthCredential, backup: nil) = authMethod {
            } else {
                Issue.record("wrong authMethod: \(authMethod)")
            }
            return .value(.success(initialMasterKey))
        }

        // Before registering, it should ask for push tokens to give the registration.
        pushRegistrationManagerMock.addRequestPushTokenMock({ .success(Stubs.apnsRegistrationId) })

        // Every time we register we also ask for prekeys.
        preKeyManagerMock.addCreatePreKeysMock(Stubs.preKeyBundle(identity:))
        preKeyManagerMock.addCreatePreKeysMock(Stubs.preKeyBundle(identity:))

        // And we finalize them after.
        preKeyManagerMock.addFinalizePreKeyBundleMock { _ in }
        preKeyManagerMock.addFinalizePreKeyBundleMock { _ in }

        // Now still at it should make a reg recovery pw request
        let accountIdentityResponse = Stubs.accountIdentityResponse()
        var authPassword: String!
        let expectedRegRecoveryPwRequest = createAccountWithRecoveryPw(initialMasterKey.deriveRegistrationRecoveryPassword())
        networkManagerMock.asyncRequestHandlers.append(MockNetworkManager.mockResponse(
            matchingRequest: { request in
                self.testRun.addObservedStep(.createAccount)
                authPassword = request.authPassword
                return request.url == expectedRegRecoveryPwRequest.url
            },
            statusCode: 200,
            bodyJson: accountIdentityResponse,
        ))

        func expectedAuth() -> ChatServiceAuth {
            return ChatServiceAuth.explicit(
                aci: accountIdentityResponse.localIdentifiers.aci,
                deviceId: .primary,
                password: authPassword,
            )
        }

        // Once we create pre-keys, we mark the PIN enabled.
        ows2FAManagerMock.didMarkPinEnabled = { pin in
            self.testRun.addObservedStep(.markPinEnabled)
            #expect(pin == Stubs.pinCode)
        }

        // Once we back up to svr, we should restore from storage service.
        storageServiceManagerMock.addRestoreOrCreateManifestIfNecessaryMock({ auth, masterKeySource in
            #expect(auth.chatServiceAuth == expectedAuth())
            switch masterKeySource {
            case .explicit(let explicitMasterKey):
                #expect(initialMasterKey.rawData == explicitMasterKey.rawData)
            default:
                Issue.record("Unexpected master key used in storage service operation.")
            }
        })

        storageServiceManagerMock.addRestoreOrCreateManifestIfNecessaryMock({ auth, masterKeySource in
            switch masterKeySource {
            case .explicit(let explicitMasterKey):
                #expect(finalMasterKey.rawData == explicitMasterKey.rawData)
            default:
                Issue.record("Unexpected master key used in storage service operation.")
            }
        })

        storageServiceManagerMock.addRotateManifestMock({ _, _ in return .value(()) })

        // Once we restore from storage service, we should attempt to reclaim our username.
        let mockUsernameLink: Usernames.UsernameLink = .mocked
        localUsernameManagerMock.startingUsernameState = .available(username: "boba.42", usernameLink: mockUsernameLink)
        mockUsernamesService.confirmUsernameMocks.set([{ _, _ in
            self.testRun.addObservedStep(.confirmReservedUsername)
            return mockUsernameLink.handle
        }])

        // Once we do the storage service restore, then we are finished!

        // At this point, we should be asking for PIN entry so we can use the credential
        // to recover the SVR master key.
        coordinator.submitE164(Stubs.e164)
        var nextStep = await coordinator.nextStep()
        guard case .pinEntry(let pinState) = nextStep else {
            Issue.record("must be pinEntry")
            return
        }
        guard case .enteringExistingPin(skippability: .canSkip, remainingAttempts: _) = pinState.operation else {
            Issue.record("must be enteringExistingPin with skippability")
            return
        }

        // We should have wiped the invalid and unknown credentials.
        #expect(getSvrCredentialUsernames() == [Stubs.svr2AuthCredential.credential.username, "aaaa"])

        // Enter the PIN, which should try and recover from SVR.
        // Once we do that, it should follow the Reg Recovery Password Path.
        nextStep = await coordinator.submitPINCode(Stubs.pinCode).awaitable()
        #expect(nextStep.isDone)

        let expectedSteps: [TestStep] = [
            .restoreKeys,
            .requestPushToken,
            .createPreKeys,
            .createPreKeys,
            .createAccount,
            .finalizePreKeys,
            .finalizePreKeys,
            .restoreStorageService,
            .markPinEnabled,
            .confirmReservedUsername,
            .resetOneTimePreKeyTimestamp,
            .rotateManifest,
        ]

        #expect(testRun.recordedSteps == expectedSteps)

        // Since we set profile info, we should have scheduled a reupload.
        #expect(profileManagerMock.didScheduleReuploadLocalProfile)
    }

    @MainActor @Test(arguments: Self.testCases())
    func testSVRAuthCredentialPath_noMatchingCredentials(testCase: TestCase) async {
        let coordinator = setupTest(testCase)
        let mode = testCase.mode

        // Set profile info so we skip those steps.
        setupDefaultAccountAttributes()

        // Put some auth credentials in storage.
        mockSVRCredentials(isMatch: false)

        // Get past the opening.
        await goThroughOpeningHappyPath(coordinator: coordinator, mode: mode)

        // Once the first request fails, it should try an start a session.
        // We'll ask for a push challenge, though we don't need to resolve it in this test.
        pushRegistrationManagerMock.setReceivePreAuthChallengeTokenMock({
            try! await Task.sleep(nanoseconds: TimeInterval.infinity.clampedNanoseconds)
            fatalError()
        })

        // Resolve with a session.
        let expectedSession = stubs.session()
        sessionManager.addBeginSessionResponseMock({ expectedSession })

        // Then when it gets back the session, it should immediately ask for
        // a verification code to be sent.
        // Resolve with an updated session.
        sessionManager.addRequestCodeResponseMock(.success(stubs.session(nextVerificationAttempt: 0)))

        pushRegistrationManagerMock.addRequestPushTokenMock({ .success(Stubs.apnsRegistrationId) })

        // Give it a phone number, which should cause it to check the auth credentials.
        // Now we should expect to be at verification code entry since we already set the phone number.
        coordinator.submitE164(Stubs.e164)
        let nextStep = await coordinator.nextStep()
        guard case .verificationCodeEntry = nextStep else {
            Issue.record("must be verificationCodeEntry")
            return
        }

        // We should have wiped the invalid and unknown credentials.
        #expect(getSvrCredentialUsernames() == [Stubs.svr2AuthCredential.credential.username, "aaaa"])
    }

    @MainActor @Test(arguments: Self.testCases())
    func testSVRAuthCredentialPath_noMatchingCredentialsThenChangeNumber(testCase: TestCase) async {
        let coordinator = setupTest(testCase)
        let mode = testCase.mode

        let originalE164 = E164("+17875550100")!
        let changedE164 = E164("+17875550101")!

        // Set profile info so we skip those steps.
        setupDefaultAccountAttributes()

        // Put some auth credentials in storage.
        let credentialCandidates: [SVR2AuthCredential] = [Stubs.svr2AuthCredential]
        storeSvrCredentials(credentialCandidates)

        // Get past the opening.
        await goThroughOpeningHappyPath(coordinator: coordinator, mode: mode)

        // Don't give back any matches, which means we will want to create a session as a fallback.
        var expectedSVRCheckRequest = RegistrationRequestFactory.svr2AuthCredentialCheckRequest(
            e164: originalE164,
            credentials: credentialCandidates,
            logger: .empty(),
        )
        networkManagerMock.asyncRequestHandlers.append(MockNetworkManager.mockResponse(
            matchingRequest: { $0.url.relativeString.hasSuffix(expectedSVRCheckRequest.url.absoluteString) },
            statusCode: 200,
            bodyJson: RegistrationServiceResponses.SVR2AuthCheckResponse(matches: [
                "\(Stubs.svr2AuthCredential.credential.username):\(Stubs.svr2AuthCredential.credential.password)": .notMatch,
            ]),
        ))

        // Once the first request fails, it should try an start a session.
        // We'll ask for a push challenge, though we don't need to resolve it in this test.
        pushRegistrationManagerMock.setReceivePreAuthChallengeTokenMock({
            try! await Task.sleep(nanoseconds: TimeInterval.infinity.clampedNanoseconds)
            fatalError()
        })

        // Resolve with a session.
        let expectedSession = stubs.session(e164: originalE164)
        sessionManager.addBeginSessionResponseMock({ expectedSession })

        // Then when it gets back the session, it should immediately ask for a verification code to be sent.
        // Resolve with an updated session.
        sessionManager.addRequestCodeResponseMock(.success(stubs.session(nextVerificationAttempt: 0)))

        pushRegistrationManagerMock.addRequestPushTokenMock({ .success(Stubs.apnsRegistrationId) })

        // Give a match, so it registers via SVR auth credential.
        expectedSVRCheckRequest = RegistrationRequestFactory.svr2AuthCredentialCheckRequest(
            e164: changedE164,
            credentials: credentialCandidates,
            logger: .empty(),
        )
        networkManagerMock.asyncRequestHandlers.append(MockNetworkManager.mockResponse(
            matchingRequest: { $0.url.relativeString.hasSuffix(expectedSVRCheckRequest.url.absoluteString) },
            statusCode: 200,
            bodyJson: RegistrationServiceResponses.SVR2AuthCheckResponse(matches: [
                "\(Stubs.svr2AuthCredential.credential.username):\(Stubs.svr2AuthCredential.credential.password)": .match,
            ]),
        ))

        // Give it a phone number, which should cause it to check the auth credentials.
        // Now we should expect to be at verification code entry since we already set the phone number.
        coordinator.submitE164(originalE164)
        var nextStep = await coordinator.nextStep()
        guard case .verificationCodeEntry = nextStep else {
            Issue.record("must be verificationCodeEntry")
            return
        }

        // We should have wiped the invalid and unknown credentials.
        #expect(getSvrCredentialUsernames() == [Stubs.svr2AuthCredential.credential.username])

        // Now change the phone number; this should take us back to phone number entry.
        coordinator.requestChangeE164()
        nextStep = await coordinator.nextStep()
        guard case .phoneNumberEntry = nextStep else {
            Issue.record("must be phoneNumberEntry")
            return
        }

        // Now it should ask for PIN entry; we are on the SVR auth credential path.
        coordinator.submitE164(changedE164)
        nextStep = await coordinator.nextStep()
        guard case .pinEntry(let pinState) = nextStep else {
            Issue.record("must be pinEntry")
            return
        }
        guard case .enteringExistingPin(skippability: .canSkip, remainingAttempts: _) = pinState.operation else {
            Issue.record("must be enteringExistingPin with skippability")
            return
        }
    }

    // MARK: - Session Path

    @MainActor @Test(arguments: Self.testCases())
    func testSessionPath_happyPath(testCase: TestCase) async {
        let coordinator = setupTest(testCase)
        let mode = testCase.mode
        let newMasterKey = Stubs.accountEntropyPoolToGenerate.getMasterKey()
        var authPassword: String!

        await createSessionAndRequestFirstCode(coordinator: coordinator, mode: mode)

        // Give back a verified session.
        sessionManager.addSubmitCodeResponseMock(.success(stubs.session(verified: true)))

        let accountIdentityResponse = Stubs.accountIdentityResponse()

        // That means it should try and register with the verified session;
        // Before registering, it should ask for push tokens to give the registration.
        pushRegistrationManagerMock.addRequestPushTokenMock({ .success(Stubs.apnsRegistrationId) })

        // It should also fetch the prekeys for account creation
        preKeyManagerMock.addCreatePreKeysMock(Stubs.preKeyBundle(identity:))
        preKeyManagerMock.addCreatePreKeysMock(Stubs.preKeyBundle(identity:))

        let expectedRequest = createAccountWithSession(recoveryPassword: newMasterKey.deriveRegistrationRecoveryPassword())
        networkManagerMock.asyncRequestHandlers.append(MockNetworkManager.mockResponse(
            matchingRequest: { request in
                authPassword = request.authPassword
                return request.url == expectedRequest.url
            },
            statusCode: 200,
            bodyJson: accountIdentityResponse,
        ))

        func expectedAuth() -> ChatServiceAuth {
            return ChatServiceAuth.explicit(
                aci: accountIdentityResponse.localIdentifiers.aci,
                deviceId: .primary,
                password: authPassword,
            )
        }

        // Once we are registered, we should finalize prekeys.
        preKeyManagerMock.addFinalizePreKeyBundleMock { _ in }
        preKeyManagerMock.addFinalizePreKeyBundleMock { _ in }

        // Finish the validation.
        var didMarkPinEnabled = false
        ows2FAManagerMock.didMarkPinEnabled = { pin in
            #expect(pin == Stubs.pinCode)
            didMarkPinEnabled = true
        }

        // Once we sync push tokens, we should restore from storage service.
        storageServiceManagerMock.addRestoreOrCreateManifestIfNecessaryMock({ auth, masterKeySource in
            #expect(auth.chatServiceAuth == expectedAuth())
            switch masterKeySource {
            case .explicit(let explicitMasterKey):
                #expect(newMasterKey.rawData == explicitMasterKey.rawData)
            default:
                Issue.record("Unexpected master key used in storage service operation.")
            }
        })

        // Once we restore from storage service, we should attempt to reclaim
        // our username. For this test, let's fail. This should have
        // no different impact on the rest of registration.
        let mockUsernameLink: Usernames.UsernameLink = .mocked
        localUsernameManagerMock.startingUsernameState = .available(username: "boba.42", usernameLink: mockUsernameLink)
        mockUsernamesService.confirmUsernameMocks.set([{ _, _ in
            throw OWSGenericError("Something went wrong :(")
        }])

        // And once we do the storage service restore,
        // then we are finished!

        storageServiceManagerMock.addRotateManifestMock({ _, _ in return .value(()) })

        // Submit a code.
        var nextStep = await coordinator.submitVerificationCode(Stubs.pinCode).awaitable()
        do {
            // Now we should ask to create a PIN.
            guard case .pinEntry(let pinState) = nextStep else {
                Issue.record("must be pinEntry")
                return
            }
            // No exit allowed since we've already started trying to create the account.
            #expect(pinState.exitConfiguration == .noExitAllowed)
            guard case .creatingNewPin = pinState.operation else {
                Issue.record("must be creatingNewPin")
                return
            }
        }

        // Confirm the pin first.
        coordinator.setPINCodeForConfirmation(.stub())
        nextStep = await coordinator.nextStep()
        do {
            guard case .pinEntry(let pinState) = nextStep else {
                Issue.record("must be pinEntry")
                return
            }
            // No exit allowed since we've already started trying to create the account.
            #expect(pinState.exitConfiguration == .noExitAllowed)
            guard case .confirmingNewPin(let confirmState) = pinState.operation else {
                Issue.record("must be creatingNewPin")
                return
            }
            #expect(confirmState.pinToConfirm == Stubs.pinCode)
        }

        // When we submit the pin, it should backup with SVR.
        #expect(await coordinator.submitPINCode(Stubs.pinCode).awaitable().isDone)

        // Since we set profile info, we should have scheduled a reupload.
        #expect(profileManagerMock.didScheduleReuploadLocalProfile)

        #expect(didMarkPinEnabled)
    }

    @MainActor @Test
    func testSessionPath_invalidE164() async {
        let coordinator = setUpTest(forMode: .registering)
        let badE164 = E164("+15555555555")!

        await setUpSessionPath(coordinator: coordinator, mode: .registering)

        // Reject for invalid argument (the e164).
        sessionManager.addBeginSessionResponseMock({
            throw HTTPResponse(
                requestUrl: URL(string: "v1/verification/session")!,
                status: 422,
            ).asError()
        })

        // Give it a phone number, which should cause it to start a session.
        // It should put us on the phone number entry screen again
        // with an error.
        coordinator.submitE164(badE164)
        let nextStep = await coordinator.nextStep()
        guard case .phoneNumberEntry(.registration(.initialRegistration(let entryState))) = nextStep else {
            Issue.record("must be phoneNumberEntry(registration(initialRegistration(...)))")
            return
        }
        guard case .invalidE164(let invalidE164) = entryState.validationError else {
            Issue.record("must be invalidE164")
            return
        }
        #expect(entryState.previouslyEnteredE164 == badE164)
        #expect(invalidE164.invalidE164 == badE164)
    }

    @MainActor @Test(arguments: Self.testCases())
    func testSessionPath_rateLimitSessionCreation(testCase: TestCase) async {
        let coordinator = setupTest(testCase)
        let mode = testCase.mode

        await setUpSessionPath(coordinator: coordinator, mode: mode)

        let retryTimeInterval: TimeInterval = 5

        // Reject with a rate limit.
        sessionManager.addBeginSessionResponseMock({
            throw HTTPResponse(
                requestUrl: URL(string: "v1/verification/session")!,
                status: 429,
                headers: ["Retry-After": "\(retryTimeInterval)"],
            ).asError()
        })

        // Give it a phone number, which should cause it to start a session.
        // It should put us on the phone number entry screen again
        // with an error.
        coordinator.submitE164(Stubs.e164)
        let nextStep = await coordinator.nextStep()
        guard case .phoneNumberEntry(let state) = nextStep else {
            Issue.record("must be phoneNumberEntry")
            return
        }
        let validationError: RegistrationPhoneNumberViewState.ValidationError?
        switch state {
        case .registration(.initialRegistration(let state)):
            validationError = state.validationError
        case .registration(.reregistration(let state)):
            validationError = state.validationError
        case .changingNumber:
            validationError = nil
        }
        guard case .rateLimited(let rateLimitedState) = validationError else {
            Issue.record("must be rateLimited")
            return
        }
        #expect(rateLimitedState.expiration == dateProvider().addingTimeInterval(15))
    }

    @MainActor @Test(arguments: Self.testCases())
    func testSessionPath_cantSendFirstSMSCode(testCase: TestCase) async {
        let coordinator = setupTest(testCase)
        let mode = testCase.mode

        await setUpSessionPath(coordinator: coordinator, mode: mode)

        // Give back a session, but with SMS code rate limiting already.
        let expectedSession = stubs.session(nextSMS: 10)
        sessionManager.addBeginSessionResponseMock({ expectedSession })

        // Give it a phone number, which should cause it to start a session.
        // It should put us on the verification code entry screen with an error.
        coordinator.submitE164(Stubs.e164)
        let nextStep = await coordinator.nextStep()
        guard case .verificationCodeEntry(let state) = nextStep else {
            Issue.record("must be verificationCodeEntry")
            return
        }
        #expect(state.validationError == .smsResendTimeout)
        #expect(state.nextSMSDate == dateProvider().addingTimeInterval(10))
        #expect(state.nextVerificationAttemptDate == nil)
    }

    @MainActor @Test(arguments: Self.testCases())
    func testSessionPath_landline(testCase: TestCase) async {
        let coordinator = setupTest(testCase)
        let mode = testCase.mode

        await setUpSessionPath(coordinator: coordinator, mode: mode)

        // Give back a session that's ready to go.
        let expectedSession = stubs.session(
            nextCall: nil, /* initially calling unavailable */
        )
        sessionManager.addBeginSessionResponseMock({ expectedSession })

        // Once we get that session, we should try and send a code.
        // Resolve with a transport error
        // and no next verification attempt on the session,
        // so it counts as transport failure with no code sent.
        sessionManager.addRequestCodeResponseMock(.transportError(stubs.session(
            nextSMS: nil, /* now sms unavailable but calling is */
        )))

        // If we resend via voice, that should put us in a happy path. Resolve with a success.
        sessionManager.didRequestCode = false
        sessionManager.addRequestCodeResponseMock(.success(stubs.session(nextVerificationAttempt: 0)))

        // Give it a phone number, which should cause it to start a session.
        // We should get back the code entry step, with a validation error for the sms transport.
        coordinator.submitE164(Stubs.e164)
        do {
            let nextStep = await coordinator.nextStep()
            guard case .verificationCodeEntry(let state) = nextStep else {
                Issue.record("must be verificationCodeEntry")
                return
            }
            guard case .failedInitialTransport(failedTransport: .sms) = state.validationError else {
                Issue.record("must be failedInitialTransport(sms)")
                return
            }
        }

        // We should get back the code entry step.
        coordinator.requestVoiceCode()
        do {
            let nextStep = await coordinator.nextStep()
            guard case .verificationCodeEntry(let state) = nextStep else {
                Issue.record("must be verificationCodeEntry")
                return
            }
            #expect(state.validationError == nil)
        }
        #expect(sessionManager.didRequestCode)
    }

    @MainActor @Test(arguments: Self.testCases())
    func testSessionPath_landline_submitCodeWithNoneSentYet(testCase: TestCase) async {
        let coordinator = setupTest(testCase)
        let mode = testCase.mode

        await setUpSessionPath(coordinator: coordinator, mode: mode)

        // Give back a session that's ready to go.
        let expectedSession = stubs.session()
        sessionManager.addBeginSessionResponseMock({ expectedSession })

        // Once we get that session, we should try and send a code.

        // Resolve with a transport error,
        // and no next verification attempt on the session,
        // so it counts as transport failure with no code sent.
        sessionManager.addRequestCodeResponseMock(.transportError(stubs.session()))

        // If we try and submit a code, we should get an error sheet
        // because a code never got sent in the first place.
        // (If the server rejects the submission, which it obviously should).
        sessionManager.addSubmitCodeResponseMock(.disallowed(stubs.session()))

        // Give it a phone number, which should cause it to start a session.
        // We should get back the code entry step,
        // with a validation error for the sms transport.
        coordinator.submitE164(Stubs.e164)
        do {
            let nextStep = await coordinator.nextStep()
            guard case .verificationCodeEntry(let state) = nextStep else {
                Issue.record("must be verificationCodeEntry")
                return
            }
            guard case .failedInitialTransport(failedTransport: .sms) = state.validationError else {
                Issue.record("must be failedInitialTransport(sms)")
                return
            }
        }

        // The server says no code is available to submit. We know
        // we never sent a code, so show a unique error for that
        // but keep the user on the code entry screen so they can
        // retry sending a code with a transport method of their choice.

        do {
            let nextStep = await coordinator.submitVerificationCode(Stubs.verificationCode).awaitable()
            guard case .showErrorSheet(.submittingVerificationCodeBeforeAnyCodeSent) = nextStep else {
                Issue.record("must be showErrorSheet(submittingVerificationCodeBeforeAnyCodeSent)")
                return
            }
        }

        do {
            let nextStep = await coordinator.nextStep()
            guard case .verificationCodeEntry(let state) = nextStep else {
                Issue.record("must be verificationCodeEntry")
                return
            }
            guard case .failedInitialTransport(failedTransport: .sms) = state.validationError else {
                Issue.record("must be failedInitialTransport(sms)")
                return
            }
        }
    }

    @MainActor @Test(arguments: Self.testCases())
    func testSessionPath_rateLimitFirstSMSCode(testCase: TestCase) async {
        let coordinator = setupTest(testCase)
        let mode = testCase.mode

        await setUpSessionPath(coordinator: coordinator, mode: mode)

        // We'll ask for a push challenge, though we won't resolve it in this test.
        pushRegistrationManagerMock.setReceivePreAuthChallengeTokenMock({
            try! await Task.sleep(nanoseconds: TimeInterval.infinity.clampedNanoseconds)
            fatalError()
        })

        // Give back a session that's ready to go.
        let expectedSession = stubs.session(receivedDate: self.date)
        sessionManager.addBeginSessionResponseMock({ expectedSession })

        // Once we get that session, we should try and send a code.

        // Reject with a timeout.
        sessionManager.addRequestCodeResponseMock(.retryAfterTimeout(
            stubs.session(receivedDate: self.date, nextSMS: 10),
            retryAfterHeader: nil,
        ))

        // Give it a phone number, which should cause it to start a session.
        // It should put us on the phone number entry screen again
        // with an error.
        coordinator.submitE164(Stubs.e164)
        let nextStep = await coordinator.nextStep()
        guard case .phoneNumberEntry(let state) = nextStep else {
            Issue.record("must be phoneNumberEntry")
            return
        }
        let validationError: RegistrationPhoneNumberViewState.ValidationError?
        switch state {
        case .registration(.initialRegistration(let state)):
            validationError = state.validationError
        case .registration(.reregistration(let state)):
            validationError = state.validationError
        case .changingNumber:
            validationError = nil
        }
        guard case .rateLimited(let rateLimitedState) = validationError else {
            Issue.record("must be rateLimited")
            return
        }
        #expect(rateLimitedState.expiration == dateProvider().addingTimeInterval(15))
    }

    @MainActor @Test(arguments: Self.testCases())
    func testSessionPath_changeE164(testCase: TestCase) async {
        let coordinator = setupTest(testCase)
        let mode = testCase.mode

        await setUpSessionPath(coordinator: coordinator, mode: mode)

        let originalE164 = E164("+17875550100")!
        let changedE164 = E164("+17875550101")!

        // We'll ask for a push challenge, though we won't resolve it in this test.
        pushRegistrationManagerMock.setReceivePreAuthChallengeTokenMock({
            try! await Task.sleep(nanoseconds: TimeInterval.infinity.clampedNanoseconds)
            fatalError()
        })

        // Give back a session that's ready to go.
        let expectedSession = stubs.session(e164: originalE164)
        sessionManager.addBeginSessionResponseMock({ expectedSession })

        // Once we get that session, we should try and send a code.
        // Give back a session with a sent code.
        sessionManager.addRequestCodeResponseMock(.success(stubs.session(
            e164: originalE164,
            nextVerificationAttempt: 0,
        )))

        // These mocks are removed after each use, so set up another
        pushRegistrationManagerMock.addRequestPushTokenMock({ .success(Stubs.apnsRegistrationId) })

        // We'll ask for a push challenge, though we won't resolve it in this test.
        pushRegistrationManagerMock.setReceivePreAuthChallengeTokenMock({
            try! await Task.sleep(nanoseconds: TimeInterval.infinity.clampedNanoseconds)
            fatalError()
        })

        // Give back a session that's ready to go.
        // TODO: allow mocking multiple responses
        let expectedSession2 = stubs.session(e164: changedE164)
        sessionManager.addBeginSessionResponseMock({ expectedSession2 })

        // Once we get that session, we should try and send a code.
        // Give back a session with a sent code.
        sessionManager.addRequestCodeResponseMock(.success(stubs.session(
            e164: changedE164,
            nextVerificationAttempt: 0,
        )))

        // Give it a phone number, which should cause it to start a session.
        coordinator.submitE164(originalE164)
        do {
            let nextStep = await coordinator.nextStep()
            // We should be on the verification code entry screen.
            guard case .verificationCodeEntry(let state) = nextStep else {
                Issue.record("must be verificationCodeEntry")
                return
            }
            #expect(state.e164 == originalE164)
            #expect(state.validationError == nil)
        }

        // Ask to change the number; this should put us back on phone number entry.
        coordinator.requestChangeE164()
        let nextStep = await coordinator.nextStep()
        guard case .phoneNumberEntry = nextStep else {
            Issue.record("must be phoneNumberEntry")
            return
        }

        // Give it the new phone number, which should cause it to start a session.
        // TODO: Missing a 'requestPushToken'?
        coordinator.submitE164(changedE164)
        do {
            let nextStep = await coordinator.nextStep()
            // We should be on the verification code entry screen.
            guard case .verificationCodeEntry(let state) = nextStep else {
                Issue.record("must be verificationCodeEntry")
                return
            }
            #expect(state.e164 == changedE164)
            #expect(state.validationError == nil)
        }
    }

    @MainActor @Test(arguments: Self.testCases())
    func testSessionPath_captchaChallenge(testCase: TestCase) async {
        let coordinator = setupTest(testCase)
        let mode = testCase.mode

        await setUpSessionPath(coordinator: coordinator, mode: mode)

        // Give back a session with a captcha challenge.
        let expectedSession = stubs.session(
            allowedToRequestCode: false,
            requestedInformation: [.captcha],
        )
        sessionManager.addBeginSessionResponseMock({ expectedSession })

        // Give back a session without the challenge.
        let expectedSession2 = stubs.session()
        sessionManager.addFulfillChallengeResponseMock({ session, _ in session = expectedSession2 })

        // That means it should try and send a code;
        // Resolve with a session.
        // The session has a sent code, but requires a challenge to send
        // a code again. That should be ignored until we ask to send another code.
        sessionManager.addRequestCodeResponseMock(.success(stubs.session(
            nextVerificationAttempt: 0,
            allowedToRequestCode: false,
            requestedInformation: [.captcha],
        )))

        // Give back a session without the challenge.
        let expectedSession3 = stubs.session(nextVerificationAttempt: 0)
        sessionManager.addFulfillChallengeResponseMock({ session, _ in session = expectedSession3 })

        // Give it a phone number, which should cause it to start a session.
        coordinator.submitE164(Stubs.e164)
        var nextStep = await coordinator.nextStep()
        // Once we get that session, we should get a captcha step back.
        guard case .captchaChallenge = nextStep else {
            Issue.record("must be captchaChallenge")
            return
        }

        // We should get back the code entry step. Submit a captcha challenge.
        nextStep = await coordinator.submitCaptcha(Stubs.captchaToken).awaitable()
        guard case .verificationCodeEntry = nextStep else {
            Issue.record("must be verificationCodeEntry")
            return
        }

        // Now try and resend a code, which should hit us with the captcha
        // challenge immediately.
        coordinator.requestSMSCode()
        nextStep = await coordinator.nextStep()
        guard case .captchaChallenge = nextStep else {
            Issue.record("must be captchaChallenge")
            return
        }

        // This means when we fulfill the challenge, it should immediately try and
        // send the code that couldn't be sent before because of the challenge.
        stubs.date = date.addingTimeInterval(10)
        let secondCodeDate = date

        sessionManager.addRequestCodeResponseMock(.success(stubs.session(
            receivedDate: secondCodeDate,
            nextVerificationAttempt: 0,
        )))

        // Submit a captcha challenge.
        // Once all is done, we should have a new code and be back on the code
        // entry screen.
        // TODO[Registration]: test that the "next SMS code" state is properly set
        // given the new sms code date above.
        nextStep = await coordinator.submitCaptcha(Stubs.captchaToken).awaitable()
        guard case .verificationCodeEntry = nextStep else {
            Issue.record("must be verificationCodeEntry")
            return
        }
    }

    @MainActor @Test(arguments: Self.testCases())
    func testSessionPath_pushChallenge(testCase: TestCase) async {
        let coordinator = setupTest(testCase)
        let mode = testCase.mode

        await setUpSessionPath(coordinator: coordinator, mode: mode)

        pushRegistrationManagerMock.addRequestPushTokenMock({ .success(Stubs.apnsRegistrationId) })

        pushRegistrationManagerMock.setReceivePreAuthChallengeTokenMock({ "a pre-auth challenge token" })

        // Give back a session with a push challenge.
        let expectedSession = stubs.session(
            allowedToRequestCode: false,
            requestedInformation: [.pushChallenge],
        )
        sessionManager.addBeginSessionResponseMock({ expectedSession })

        let expectedSession2 = stubs.session(nextVerificationAttempt: 0)
        var latestChallengeFulfillment: Registration.ChallengeFulfillment?
        sessionManager.addFulfillChallengeResponseMock({ session, fulfillment in
            session = expectedSession2
            latestChallengeFulfillment = fulfillment
        })

        sessionManager.addRequestCodeResponseMock(.success(stubs.session(
            nextVerificationAttempt: 0,
            allowedToRequestCode: false,
            requestedInformation: [.pushChallenge],
        )))

        // Give the push challenge token. Also prepare to handle its usage, and the
        // resulting request for another SMS code.

        // Give it a phone number, which should cause it to start a session.
        coordinator.submitE164(Stubs.e164)
        _ = await coordinator.nextStep()

        // We should still be waiting.
        let nextStep = await coordinator.nextStep()
        guard case .verificationCodeEntry = nextStep else {
            Issue.record("must be verificationCodeEntry")
            return
        }
        #expect(latestChallengeFulfillment == .pushChallenge("a pre-auth challenge token"))
    }

    @MainActor @Test(arguments: Self.testCases())
    func testSessionPath_pushChallengeTimeoutAfterResolutionThatTakesTooLong(testCase: TestCase) async {
        let coordinator = setupTest(testCase)
        let mode = testCase.mode

        // Set profile info so we skip those steps.
        setupDefaultAccountAttributes()

        // Get past the opening.
        await goThroughOpeningHappyPath(coordinator: coordinator, mode: mode)

        pushRegistrationManagerMock.addRequestPushTokenMock({ .success(Stubs.apnsRegistrationId) })

        // Prepare to provide the challenge token.
        let (challengeTokenPromise, _) = Guarantee<String>.pending()
        let receivePreAuthChallengeTokenCount = AtomicUInt(lock: .init())

        pushRegistrationManagerMock.setReceivePreAuthChallengeTokenMock {
            receivePreAuthChallengeTokenCount.increment()
            return await challengeTokenPromise.awaitable()
        }

        // Give back a session with a push challenge.
        let expectedSession = stubs.session(
            allowedToRequestCode: false,
            requestedInformation: [.pushChallenge],
        )
        sessionManager.addBeginSessionResponseMock({ expectedSession })

        // Take too long to resolve with the challenge token.
        timeoutProviderMock.pushTokenMinWaitTime = 0.5
        timeoutProviderMock.pushTokenTimeout = 2

        // Give it a phone number, which should cause it to start a session.
        coordinator.submitE164(Stubs.e164)
        let nextStep = await coordinator.nextStep()
        guard case .showErrorSheet(.sessionInvalidated) = nextStep else {
            Issue.record("must be showErrorSheet(sessionInvalidated)")
            return
        }

        // One time to set up, one time for the min wait time, one time
        // for the full timeout.
        #expect(receivePreAuthChallengeTokenCount.get() == 3)
    }

    @MainActor @Test(arguments: Self.testCases())
    func testSessionPath_pushChallengeTimeoutAfterNoResolution(testCase: TestCase) async {
        let coordinator = setupTest(testCase)
        let mode = testCase.mode

        // Set profile info so we skip those steps.
        setupDefaultAccountAttributes()

        // Get past the opening.
        await goThroughOpeningHappyPath(coordinator: coordinator, mode: mode)

        pushRegistrationManagerMock.addRequestPushTokenMock({ .success(Stubs.apnsRegistrationId) })

        // We'll never provide a challenge token and will just leave it around forever.
        let (challengeTokenPromise, _) = Guarantee<String>.pending()
        let receivePreAuthChallengeTokenCount = AtomicUInt(lock: .init())
        pushRegistrationManagerMock.setReceivePreAuthChallengeTokenMock({
            receivePreAuthChallengeTokenCount.increment()
            return await challengeTokenPromise.awaitable()
        })

        // Give back a session with a push challenge.
        let expectedSession = stubs.session(
            allowedToRequestCode: false,
            requestedInformation: [.pushChallenge],
        )
        sessionManager.addBeginSessionResponseMock({ expectedSession })

        timeoutProviderMock.pushTokenMinWaitTime = 0.5
        timeoutProviderMock.pushTokenTimeout = 2

        // Give it a phone number, which should cause it to start a session.
        coordinator.submitE164(Stubs.e164)
        let nextStep = await coordinator.nextStep()
        guard case .showErrorSheet(.sessionInvalidated) = nextStep else {
            Issue.record("must be showErrorSheet(sessionInvalidated)")
            return
        }

        // One time to set up, one time for the min wait time, one time
        // for the full timeout.
        #expect(receivePreAuthChallengeTokenCount.get() == 3)
    }

    @MainActor @Test(arguments: Self.testCases())
    func testSessionPath_pushChallengeWithoutPushNotificationsAvailable(testCase: TestCase) async {
        let coordinator = setupTest(testCase)
        let mode = testCase.mode

        // Set profile info so we skip those steps.
        setupDefaultAccountAttributes()
        pushRegistrationManagerMock.addRequestPushTokenMock({ .pushUnsupported(description: "") })

        // Get past the opening.
        await goThroughOpeningHappyPath(coordinator: coordinator, mode: mode)

        // Require a push challenge, which we won't be able to answer.
        let expectedSession = stubs.session(
            allowedToRequestCode: false,
            requestedInformation: [.pushChallenge],
        )
        sessionManager.addBeginSessionResponseMock({ expectedSession })

        // Give it a phone number, which should cause it to start a session.
        coordinator.submitE164(Stubs.e164)
        let nextStep = await coordinator.nextStep()
        guard case .phoneNumberEntry = nextStep else {
            Issue.record("must be phoneNumberEntry")
            return
        }
    }

    @MainActor @Test(arguments: Self.testCases())
    func testSessionPath_preferPushChallengesIfWeCanAnswerThemImmediately(testCase: TestCase) async {
        let coordinator = setupTest(testCase)
        let mode = testCase.mode

        await setUpSessionPath(coordinator: coordinator, mode: mode)

        pushRegistrationManagerMock.addRequestPushTokenMock({ .success(Stubs.apnsRegistrationId) })

        // Be ready to provide the push challenge token as soon as it's needed.
        pushRegistrationManagerMock.setReceivePreAuthChallengeTokenMock({ "a pre-auth challenge token" })

        // Give back a session with multiple challenges.
        let expectedSession = stubs.session(
            allowedToRequestCode: false,
            requestedInformation: [.captcha, .pushChallenge],
        )
        sessionManager.addBeginSessionResponseMock({ expectedSession })

        // Be ready to handle push challenges as soon as we can.
        let expectedSession2 = stubs.session(nextVerificationAttempt: 0)
        var latestChallengeFulfillment: Registration.ChallengeFulfillment?
        sessionManager.addFulfillChallengeResponseMock({ session, fulfillment in
            session = expectedSession2
            latestChallengeFulfillment = fulfillment
        })

        sessionManager.addRequestCodeResponseMock(.success(stubs.session(
            nextVerificationAttempt: 0,
        )))

        // Give it a phone number, which should cause it to start a session.
        coordinator.submitE164(Stubs.e164)
        let nextStep = await coordinator.nextStep()
        guard case .verificationCodeEntry = nextStep else {
            Issue.record("must be verificationCodeEntry")
            return
        }
        #expect(latestChallengeFulfillment == .pushChallenge("a pre-auth challenge token"))
    }

    @MainActor @Test(arguments: Self.testCases())
    func testSessionPath_prefersCaptchaChallengesIfWeCannotAnswerPushChallengeQuickly(testCase: TestCase) async {
        let coordinator = setupTest(testCase)
        let mode = testCase.mode

        await setUpSessionPath(coordinator: coordinator, mode: mode)

        pushRegistrationManagerMock.addRequestPushTokenMock({ .success(Stubs.apnsRegistrationId) })

        // Prepare to provide the challenge token.
        pushRegistrationManagerMock.setReceivePreAuthChallengeTokenMock({
            try! await Task.sleep(nanoseconds: TimeInterval.infinity.clampedNanoseconds)
            fatalError()
        })

        // Give back a session with multiple challenges.
        let expectedSession = stubs.session(
            allowedToRequestCode: false,
            requestedInformation: [.pushChallenge, .captcha],
        )
        sessionManager.addBeginSessionResponseMock({ expectedSession })

        timeoutProviderMock.pushTokenMinWaitTime = 0.5
        timeoutProviderMock.pushTokenTimeout = 2

        // Give it a phone number, which should cause it to start a session.
        coordinator.submitE164(Stubs.e164)

        // After that, we should get a captcha step back, because we haven't
        // yet received the push challenge token.
        let nextStep = await coordinator.nextStep()
        guard case .captchaChallenge = nextStep else {
            Issue.record("must be captchaChallenge")
            return
        }
    }

    @MainActor @Test(arguments: Self.testCases())
    func testSessionPath_pushChallengeFastResolution(testCase: TestCase) async {
        let coordinator = setupTest(testCase)
        let mode = testCase.mode

        await setUpSessionPath(coordinator: coordinator, mode: mode)

        pushRegistrationManagerMock.addRequestPushTokenMock({ .success(Stubs.apnsRegistrationId) })

        // Prepare to provide the challenge token.
        let (challengeTokenPromise, challengeTokenFuture) = Guarantee<String>.pending()
        pushRegistrationManagerMock.setReceivePreAuthChallengeTokenMock({ await challengeTokenPromise.awaitable() })

        // Give back a session with multiple challenges.
        let expectedSession = stubs.session(
            allowedToRequestCode: false,
            requestedInformation: [.pushChallenge, .captcha],
        )
        sessionManager.addBeginSessionResponseMock({ expectedSession })

        // Also prep for the token's submission.
        let expectedSession2 = stubs.session(nextVerificationAttempt: 0)
        sessionManager.addFulfillChallengeResponseMock({ session, _ in session = expectedSession2 })

        sessionManager.addRequestCodeResponseMock(.success(stubs.session(
            nextVerificationAttempt: 0,
            allowedToRequestCode: false,
            requestedInformation: [.pushChallenge],
        )))

        timeoutProviderMock.pushTokenTimeout = 5
        Task {
            // Don't resolve the captcha token immediately, but quickly enough.
            try? await Task.sleep(nanoseconds: 1 * NSEC_PER_SEC)
            challengeTokenFuture.resolve("challenge token")
        }

        // Give it a phone number, which should cause it to start a session.
        // Once we get that session, we should wait a short time for the
        // push challenge token and fulfill it.
        coordinator.submitE164(Stubs.e164)
        let nextStep = await coordinator.nextStep()
        guard case .verificationCodeEntry = nextStep else {
            Issue.record("must be verificationCodeEntry")
            return
        }
    }

    @MainActor @Test(arguments: Self.testCases())
    func testSessionPath_ignoresPushChallengesIfWeCannotEverAnswerThem(testCase: TestCase) async {
        let coordinator = setupTest(testCase)
        let mode = testCase.mode

        // Set profile info so we skip those steps.
        setupDefaultAccountAttributes()

        pushRegistrationManagerMock.addRequestPushTokenMock({ .pushUnsupported(description: "") })

        // No other setup; no auth credentials, SVR keys, etc in storage
        // so that we immediately go to the session flow.

        // Get past the opening.
        await goThroughOpeningHappyPath(coordinator: coordinator, mode: mode)

        // Give back a session with multiple challenges.
        let expectedSession = stubs.session(
            allowedToRequestCode: false,
            requestedInformation: [.captcha, .pushChallenge],
        )
        sessionManager.addBeginSessionResponseMock({ expectedSession })

        // Give it a phone number, which should cause it to start a session.
        coordinator.submitE164(Stubs.e164)
        let nextStep = await coordinator.nextStep()
        guard case .captchaChallenge = nextStep else {
            Issue.record("must be captchaChallenge")
            return
        }
    }

    @MainActor @Test(arguments: Self.testCases())
    func testSessionPath_unknownChallenge(testCase: TestCase) async {
        let coordinator = setupTest(testCase)
        let mode = testCase.mode

        await setUpSessionPath(coordinator: coordinator, mode: mode)

        // Give back a session with a captcha challenge and an unknown challenge.
        let expectedSession = stubs.session(
            allowedToRequestCode: false,
            requestedInformation: [.captcha],
            hasUnknownChallengeRequiringAppUpdate: true,
        )
        sessionManager.addBeginSessionResponseMock({ expectedSession })

        // Give back a session without the captcha but still with the unknown challenge
        let expectedSession2 = stubs.session(
            allowedToRequestCode: false,
            hasUnknownChallengeRequiringAppUpdate: true,
        )
        sessionManager.addFulfillChallengeResponseMock({ session, _ in session = expectedSession2 })

        // Once we get that session, we should get a captcha step back.
        // We have an unknown challenge, but we should do known challenges first!
        // Give it a phone number, which should cause it to start a session.
        coordinator.submitE164(Stubs.e164)
        var nextStep = await coordinator.nextStep()
        guard case .captchaChallenge = nextStep else {
            Issue.record("must be captchaChallenge")
            return
        }

        // This means we should get the app update banner.
        nextStep = await coordinator.submitCaptcha(Stubs.captchaToken).awaitable()
        guard case .appUpdateBanner = nextStep else {
            Issue.record("must be appUpdateBanner")
            return
        }
    }

    @MainActor @Test(arguments: Self.testCases())
    func testSessionPath_wrongVerificationCode(testCase: TestCase) async {
        let coordinator = setupTest(testCase)
        let mode = testCase.mode

        await createSessionAndRequestFirstCode(coordinator: coordinator, mode: mode)

        // Give back a rejected argument response, its the wrong code.
        sessionManager.addSubmitCodeResponseMock(.rejectedArgument(stubs.session(
            nextVerificationAttempt: 0,
        )))

        // Now try and send the wrong code.
        let badCode = "garbage"
        let nextStep = await coordinator.submitVerificationCode(badCode).awaitable()
        guard case .verificationCodeEntry(let state) = nextStep else {
            Issue.record("must be verificationCodeEntry")
            return
        }
        guard case .invalidVerificationCode(invalidCode: badCode) = state.validationError else {
            Issue.record("must be invalidVerificationCode")
            return
        }
    }

    @MainActor @Test(arguments: Self.testCases())
    func testSessionPath_verificationCodeTimeouts(testCase: TestCase) async {
        let coordinator = setupTest(testCase)
        let mode = testCase.mode

        await createSessionAndRequestFirstCode(coordinator: coordinator, mode: mode)

        // Give back a retry response.
        sessionManager.addSubmitCodeResponseMock(.retryAfterTimeout(
            stubs.session(nextVerificationAttempt: 10),
            retryAfterHeader: 10,
        ))

        // Resend an sms code, time that out too.
        sessionManager.addRequestCodeResponseMock(.retryAfterTimeout(
            stubs.session(nextSMS: 7, nextCall: 0, nextVerificationAttempt: 9),
            retryAfterHeader: 7,
        ))

        // Resend an voice code, time that out too
        // Make the timeout SO short that it retries
        sessionManager.didRequestCode = false
        sessionManager.addRequestCodeResponseMock(.retryAfterTimeout(
            stubs.session(nextSMS: 6, nextCall: 0.1, nextVerificationAttempt: 8),
            retryAfterHeader: 0.1,
        ))

        // Be ready for the retry. Ensure we called it the first time.
        sessionManager.addRequestCodeResponseMock(.retryAfterTimeout(
            stubs.session(nextSMS: 5, nextCall: 4, nextVerificationAttempt: 8),
            retryAfterHeader: 4,
        ))

        var nextStep = await coordinator.submitVerificationCode(Stubs.verificationCode).awaitable()
        do {
            guard case .verificationCodeEntry(let state) = nextStep else {
                Issue.record("must be verificationCodeEntry")
                return
            }
            guard case .submitCodeTimeout = state.validationError else {
                Issue.record("must be submitCodeTimeout")
                return
            }
            #expect(state.nextCallDate == dateProvider())
            #expect(state.nextSMSDate == dateProvider())
            #expect(state.nextVerificationAttemptDate == dateProvider().addingTimeInterval(10))
        }

        coordinator.requestSMSCode()
        nextStep = await coordinator.nextStep()
        do {
            guard case .verificationCodeEntry(let state) = nextStep else {
                Issue.record("must be verificationCodeEntry")
                return
            }
            guard case .smsResendTimeout = state.validationError else {
                Issue.record("must be smsResendTimeout")
                return
            }
            #expect(state.nextCallDate == dateProvider())
            #expect(state.nextSMSDate == dateProvider().addingTimeInterval(7))
            #expect(state.nextVerificationAttemptDate == dateProvider().addingTimeInterval(9))
        }

        coordinator.requestVoiceCode()
        nextStep = await coordinator.nextStep()
        do {
            guard case .verificationCodeEntry(let state) = nextStep else {
                Issue.record("must be verificationCodeEntry")
                return
            }
            guard case .voiceResendTimeout = state.validationError else {
                Issue.record("must be voiceResendTimeout")
                return
            }
            #expect(state.nextCallDate == dateProvider().addingTimeInterval(4))
            #expect(state.nextSMSDate == dateProvider().addingTimeInterval(5))
            #expect(state.nextVerificationAttemptDate == dateProvider().addingTimeInterval(8))
        }

        #expect(sessionManager.didRequestCode)
    }

    @MainActor @Test(arguments: Self.testCases())
    func testSessionPath_disallowedVerificationCode(testCase: TestCase) async {
        let coordinator = setupTest(testCase)
        let mode = testCase.mode

        await createSessionAndRequestFirstCode(coordinator: coordinator, mode: mode)

        // Give back a disallowed response when submitting a code.
        // Make the session unverified. Together this will be interpreted
        // as meaning no code has been sent (via sms or voice) and one
        // must be requested.
        sessionManager.addSubmitCodeResponseMock(.disallowed(stubs.session()))

        // The server says no code is available to submit. But we think we tried
        // sending a code with local state. We want to be on the verification
        // code entry screen, with an error so the user retries sending a code.
        var nextStep = await coordinator.submitVerificationCode(Stubs.verificationCode).awaitable()
        guard case .showErrorSheet(.verificationCodeSubmissionUnavailable) = nextStep else {
            Issue.record("must be showErrorSheet(verificationCodeSubmissionUnavailable)")
            return
        }

        nextStep = await coordinator.nextStep()
        guard case .verificationCodeEntry(let state) = nextStep else {
            Issue.record("must be verificationCodeEntry")
            return
        }
        #expect(state.nextVerificationAttemptDate == nil)
    }

    @MainActor @Test(arguments: Self.testCases())
    func testSessionPath_timedOutVerificationCodeWithoutRetries(testCase: TestCase) async {
        let coordinator = setupTest(testCase)
        let mode = testCase.mode

        await createSessionAndRequestFirstCode(coordinator: coordinator, mode: mode)

        // Give back a retry response when submitting a code,
        // but with no ability to resubmit.
        sessionManager.addSubmitCodeResponseMock(.retryAfterTimeout(stubs.session(), retryAfterHeader: nil))

        var nextStep = await coordinator.submitVerificationCode(Stubs.verificationCode).awaitable()
        guard case .showErrorSheet(.verificationCodeSubmissionUnavailable) = nextStep else {
            Issue.record("must be showErrorSheet(verificationCodeSubmissionUnavailable)")
            return
        }

        nextStep = await coordinator.nextStep()
        guard case .verificationCodeEntry(let state) = nextStep else {
            Issue.record("must be verificationCodeEntry")
            return
        }
        #expect(state.nextVerificationAttemptDate == nil)
    }

    @MainActor @Test(arguments: Self.testCases())
    func testSessionPath_expiredSession(testCase: TestCase) async {
        let coordinator = setupTest(testCase)
        let mode = testCase.mode

        await setUpSessionPath(coordinator: coordinator, mode: mode)

        // Give back a session thats ready to go.
        let expectedSession = stubs.session()
        sessionManager.addBeginSessionResponseMock({ expectedSession })

        // Once we get that session, we should try and send a verification code.
        // Have that ready to go.

        // Resolve with a session
        sessionManager.addRequestCodeResponseMock(.success(stubs.session(
            nextVerificationAttempt: 0,
        )))

        // Give back an expired session.
        sessionManager.addSubmitCodeResponseMock(.invalidSession)

        // Give it a phone number, which should cause it to start a session.
        coordinator.submitE164(Stubs.e164)
        var nextStep = await coordinator.nextStep()
        // Now we should expect to be at verification code entry since we sent the code.
        guard case .verificationCodeEntry = nextStep else {
            Issue.record("must be verificationCodeEntry")
            return
        }

        nextStep = await coordinator.submitVerificationCode(Stubs.pinCode).awaitable()
        guard case .showErrorSheet(.sessionInvalidated) = nextStep else {
            Issue.record("must be showErrorSheet(sessionInvalidated)")
            return
        }

        nextStep = await coordinator.nextStep()
        guard case .phoneNumberEntry = nextStep else {
            Issue.record("must be phoneNumberEntry")
            return
        }
    }

    @MainActor @Test(arguments: Self.testCases())
    func testSessionPath_skipPINCode(testCase: TestCase) async {
        let coordinator = setupTest(testCase)
        let mode = testCase.mode
        let newMasterKey = Stubs.accountEntropyPoolToGenerate.getMasterKey()

        await createSessionAndRequestFirstCode(coordinator: coordinator, mode: mode)

        // Give back a verified session.
        sessionManager.addSubmitCodeResponseMock(.success(stubs.session(
            receivedDate: date,
            verified: true,
        )))

        let accountIdentityResponse = Stubs.accountIdentityResponse()
        var authPassword: String!

        // That means it should try and register with the verified
        // session; be ready for that.

        // Before registering, it should ask for push tokens to give the registration.
        pushRegistrationManagerMock.addRequestPushTokenMock({ .success(Stubs.apnsRegistrationId) })

        // It should also fetch the prekeys for account creation
        preKeyManagerMock.addCreatePreKeysMock(Stubs.preKeyBundle(identity:))
        preKeyManagerMock.addCreatePreKeysMock(Stubs.preKeyBundle(identity:))

        let expectedRequest = createAccountWithSession(recoveryPassword: newMasterKey.deriveRegistrationRecoveryPassword())
        networkManagerMock.asyncRequestHandlers.append(MockNetworkManager.mockResponse(
            matchingRequest: { request in
                authPassword = request.authPassword
                let requestAttributes = Self.attributesFromCreateAccountRequest(request)
                // These should be empty if sessionId is sent
                #expect((request.parameters["recoveryPassword"] as? String) == nil)
                #expect(requestAttributes.registrationRecoveryPassword == nil)
                return request.url == expectedRequest.url
            },
            statusCode: 200,
            bodyJson: accountIdentityResponse,
        ))

        func expectedAuth() -> ChatServiceAuth {
            return ChatServiceAuth.explicit(
                aci: accountIdentityResponse.localIdentifiers.aci,
                deviceId: .primary,
                password: authPassword,
            )
        }

        // Once we are registered, we should finalize prekeys.
        preKeyManagerMock.addFinalizePreKeyBundleMock { _ in }
        preKeyManagerMock.addFinalizePreKeyBundleMock { _ in }

        // When we skip the pin, it should skip any SVR backups.
        ows2FAManagerMock.didMarkPinEnabled = { _ in
            Issue.record("Shouldn't mark PIN enabled with skipped PIN!")
        }

        storageServiceManagerMock.addRestoreOrCreateManifestIfNecessaryMock({ _, _ in })

        // Once we skip the storage service restore,
        // then we are finished!

        // Once we sync push tokens, we should restore from storage service.
        storageServiceManagerMock.addRestoreOrCreateManifestIfNecessaryMock({ auth, masterKeySource in
            #expect(auth.chatServiceAuth == expectedAuth())
            switch masterKeySource {
            case .explicit(let explicitMasterKey):
                #expect(newMasterKey.rawData == explicitMasterKey.rawData)
            default:
                Issue.record("Unexpected master key used in storage service operation.")
            }
        })

        storageServiceManagerMock.addRotateManifestMock({ _, _ in
            // TODO: Really should make this explicit credentials
            return .value(())
        })

        var nextStep = await coordinator.submitVerificationCode(Stubs.pinCode).awaitable()
        // Now we should ask to create a PIN.
        guard case .pinEntry(let pinState) = nextStep else {
            Issue.record("must be pinEntry")
            return
        }
        // No exit allowed since we've already started trying to create the account.
        #expect(pinState.exitConfiguration == .noExitAllowed)
        guard case .creatingNewPin = pinState.operation else {
            Issue.record("must be creatingNewPin")
            return
        }

        // At this point we should not have set the AEP.
        #expect(db.read { accountKeyStore.getAccountEntropyPool(tx: $0) == nil })

        // Skip the PIN code.
        coordinator.skipPINCode()
        nextStep = await coordinator.nextStep()
        #expect(nextStep.isDone)

        // We should now have set the AEP.
        #expect(db.read { accountKeyStore.getAccountEntropyPool(tx: $0) != nil })

        // Since we set profile info, we should have scheduled a reupload.
        #expect(profileManagerMock.didScheduleReuploadLocalProfile)
    }

    @MainActor @Test
    func testSessionPath_skipPINRestore_createNewPIN() async {
        let coordinator = setUpTest(forMode: .registering)
        let newMasterKey = Stubs.accountEntropyPoolToGenerate.getMasterKey()

        await createSessionAndRequestFirstCode(coordinator: coordinator, mode: .registering)

        // Give back a verified session.
        sessionManager.addSubmitCodeResponseMock(.success(stubs.session(
            receivedDate: date,
            verified: true,
        )))

        // Previously used SVR so we first ask to restore.
        let accountIdentityResponse = Stubs.accountIdentityResponse(hasPreviouslyUsedSVR: true)
        var authPassword: String!

        // Try and register with the verified session
        // Before registering, it should ask for push tokens to give the registration.
        pushRegistrationManagerMock.addRequestPushTokenMock({ .success(Stubs.apnsRegistrationId) })

        // It should also fetch the prekeys for account creation
        preKeyManagerMock.addCreatePreKeysMock(Stubs.preKeyBundle(identity:))
        preKeyManagerMock.addCreatePreKeysMock(Stubs.preKeyBundle(identity:))

        let expectedRequest = createAccountWithSession(recoveryPassword: newMasterKey.deriveRegistrationRecoveryPassword())
        networkManagerMock.asyncRequestHandlers.append(MockNetworkManager.mockResponse(
            matchingRequest: { request in
                authPassword = request.authPassword
                return request.url == expectedRequest.url
            },
            statusCode: 200,
            bodyJson: accountIdentityResponse,
        ))

        func expectedAuth() -> ChatServiceAuth {
            return ChatServiceAuth.explicit(
                aci: accountIdentityResponse.localIdentifiers.aci,
                deviceId: .primary,
                password: authPassword,
            )
        }

        // Once we are registered, we should finalize prekeys.
        preKeyManagerMock.addFinalizePreKeyBundleMock { _ in }
        preKeyManagerMock.addFinalizePreKeyBundleMock { _ in }

        // When we skip the pin, it should skip any SVR backups.
        ows2FAManagerMock.didMarkPinEnabled = { _ in
            Issue.record("Shouldn't mark PIN enabled with skipped PIN!")
        }

        storageServiceManagerMock.addRestoreOrCreateManifestIfNecessaryMock({ auth, masterKeySource in
            #expect(auth.chatServiceAuth == expectedAuth())
            switch masterKeySource {
            case .explicit(let explicitMasterKey):
                #expect(newMasterKey.rawData == explicitMasterKey.rawData)
            default:
                Issue.record("Unexpected master key used in storage service operation.")
            }
        })

        storageServiceManagerMock.addRotateManifestMock({ _, _ in return .value(()) })

        // Once we skip the storage service restore,
        // then we are finished!

        // Now we should ask to restore the PIN.
        var nextStep = await coordinator.submitVerificationCode(Stubs.pinCode).awaitable()
        do {
            guard case .pinEntry(let state) = nextStep else {
                Issue.record("must be pinEntry")
                return
            }
            guard case .enteringExistingPin(skippability: .canSkipAndCreateNew, remainingAttempts: _) = state.operation else {
                Issue.record("must be enteringExistingPin with skip & create new")
                return
            }
        }

        // Skip the PIN code and create a new one instead.
        // When we skip, we should be asked to _create_ the PIN.
        coordinator.skipAndCreateNewPINCode()
        nextStep = await coordinator.nextStep()
        do {
            guard case .pinEntry(let state) = nextStep else {
                Issue.record("must be pinEntry")
                return
            }
            guard case .creatingNewPin = state.operation else {
                Issue.record("must be creatingNewPin")
                return
            }
        }

        // At this point we should not have set the AEP.
        #expect(db.read { accountKeyStore.getAccountEntropyPool(tx: $0) == nil })

        // Skip this PIN code, too.
        coordinator.skipPINCode()
        nextStep = await coordinator.nextStep()
        #expect(nextStep.isDone)

        // We should now have set the master key (i.e., the AEP).
        #expect(db.read { accountKeyStore.getAccountEntropyPool(tx: $0) != nil })

        // Since we set profile info, we should have scheduled a reupload.
        #expect(profileManagerMock.didScheduleReuploadLocalProfile)
    }

    // MARK: - Profile Setup Path

    // TODO[Registration]: test the profile setup steps.

    // MARK: - Persisted State backwards compatibility

    typealias ReglockState = RegistrationCoordinatorImpl.PersistedState.SessionState.ReglockState

    @MainActor @Test
    func testPersistedState_SVRCredentialCompat() throws {
        let reglockExpirationDate = Date(timeIntervalSince1970: 10000)
        let decoder = JSONDecoder()

        // Serialized ReglockState.none
        let reglockStateNoneData = "7b226e6f6e65223a7b7d7d"
        #expect(
            try decoder.decode(ReglockState.self, from: Data.data(fromHex: reglockStateNoneData)!) ==
                ReglockState.none,
        )

        // Serialized ReglockState.reglocked(
        //     credential: KBSAuthCredential(credential: RemoteAttestation.Auth(username: "abcd", password: "xyz"),
        //     expirationDate: reglockExpirationDate
        // )
        let reglockStateReglockedData = "7b227265676c6f636b6564223a7b2265787069726174696f6e44617465223a2d3937383239373230302c2263726564656e7469616c223a7b2263726564656e7469616c223a7b22757365726e616d65223a2261626364222c2270617373776f7264223a2278797a227d7d7d7d"
        #expect(
            try decoder.decode(ReglockState.self, from: Data.data(fromHex: reglockStateReglockedData)!) ==
                ReglockState.reglocked(credential: .testOnly(svr2: nil), expirationDate: reglockExpirationDate),
        )

        // Serialized ReglockState.reglocked(
        //     credential: ReglockState.SVRAuthCredential(
        //         kbs: KBSAuthCredential(credential: RemoteAttestation.Auth(username: "abcd", password: "xyz"),
        //         svr2: SVR2AuthCredential(credential: RemoteAttestation.Auth(username: "xxx", password: "yyy"))
        //     ),
        //     expirationDate: reglockExpirationDate
        // )
        let reglockStateReglockedSVR2Data = "7b227265676c6f636b6564223a7b2265787069726174696f6e44617465223a2d3937383239373230302c2263726564656e7469616c223a7b226b6273223a7b2263726564656e7469616c223a7b22757365726e616d65223a2261626364222c2270617373776f7264223a2278797a227d7d2c2273767232223a7b2263726564656e7469616c223a7b22757365726e616d65223a22787878222c2270617373776f7264223a22797979227d7d7d7d7d"
        #expect(
            try decoder.decode(ReglockState.self, from: Data.data(fromHex: reglockStateReglockedSVR2Data)!) ==
                ReglockState.reglocked(credential: .init(svr2: Stubs.svr2AuthCredential), expirationDate: reglockExpirationDate),
        )

        // Serialized ReglockState.waitingTimeout(expirationDate: reglockExpirationDate)
        let reglockStateWaitingTimeoutData = "7b2277616974696e6754696d656f7574223a7b2265787069726174696f6e44617465223a2d3937383239373230307d7d"
        #expect(
            try decoder.decode(ReglockState.self, from: Data.data(fromHex: reglockStateWaitingTimeoutData)!) ==
                ReglockState.waitingTimeout(expirationDate: reglockExpirationDate),
        )
    }

    // MARK: Happy Path Setups

    private func createAccountWithSession(
        recoveryPassword: RegistrationRecoveryPassword,
    ) -> TSRequest {
        return RegistrationRequestFactory.createAccountRequest(
            verificationMethod: .sessionId(Stubs.e164, Stubs.sessionId),
            authPassword: "", // Doesn't matter for request generation.
            accountAttributes: Stubs.accountAttributes(registrationRecoveryPassword: recoveryPassword),
            skipDeviceTransfer: true,
            apnRegistrationId: Stubs.apnsRegistrationId,
            aciPreKeyBundle: Stubs.preKeyBundle(identity: .aci),
            pniPreKeyBundle: Stubs.preKeyBundle(identity: .pni),
            logger: .empty(),
        )
    }

    private func createAccountWithRecoveryPw(
        _ recoveryPassword: RegistrationRecoveryPassword,
    ) -> TSRequest {
        return RegistrationRequestFactory.createAccountRequest(
            verificationMethod: .recoveryPassword(.phoneNumber(Stubs.e164), recoveryPassword),
            authPassword: "", // Doesn't matter for request generation.
            accountAttributes: Stubs.accountAttributes(registrationRecoveryPassword: recoveryPassword),
            skipDeviceTransfer: true,
            apnRegistrationId: Stubs.apnsRegistrationId,
            aciPreKeyBundle: Stubs.preKeyBundle(identity: .aci),
            pniPreKeyBundle: Stubs.preKeyBundle(identity: .pni),
            logger: .empty(),
        )
    }

    @MainActor
    private func goThroughOpeningHappyPath(
        coordinator: any RegistrationCoordinator,
        mode: RegistrationMode,
    ) async {
        contactsStore.doesNeedContactsAuthorization = true
        pushRegistrationManagerMock.doesNeedNotificationAuthorization = true

        switch mode {
        case .registering:
            // Gotta get the splash out of the way.
            #expect(await coordinator.nextStep().isRegistrationSplash)
            coordinator.continueFromSplash()
        case .reRegistering, .changingNumber:
            break
        }

        // Now we should show the permissions.
        #expect(await coordinator.nextStep().isPermissions)

        // Once the state is updated we can proceed.
        let nextStep = await coordinator.requestPermissions().awaitable()
        guard case .phoneNumberEntry = nextStep else {
            Issue.record("must be phoneNumberEntry")
            return
        }
    }

    @MainActor
    private func setUpSessionPath(coordinator: any RegistrationCoordinator, mode: RegistrationMode) async {
        // Set profile info so we skip those steps.
        setupDefaultAccountAttributes()

        pushRegistrationManagerMock.addRequestPushTokenMock({ .success(Stubs.apnsRegistrationId) })

        pushRegistrationManagerMock.setReceivePreAuthChallengeTokenMock({
            try! await Task.sleep(nanoseconds: TimeInterval.infinity.clampedNanoseconds)
            fatalError()
        })

        // No other setup; no auth credentials, SVR keys, etc in storage
        // so that we immediately go to the session flow.

        // Get past the opening.
        await goThroughOpeningHappyPath(coordinator: coordinator, mode: mode)
    }

    @MainActor
    private func createSessionAndRequestFirstCode(coordinator: any RegistrationCoordinator, mode: RegistrationMode) async {
        await setUpSessionPath(coordinator: coordinator, mode: mode)

        // Give it a phone number, which should cause it to start a session.

        // We'll ask for a push challenge, though we won't resolve it.
        pushRegistrationManagerMock.setReceivePreAuthChallengeTokenMock({
            try! await Task.sleep(nanoseconds: TimeInterval.infinity.clampedNanoseconds)
            fatalError()
        })

        // Give back a session that's ready to go.
        let expectedSession = stubs.session()
        sessionManager.addBeginSessionResponseMock({ expectedSession })

        // Once we get that session, we should try and send a code.
        // Resolve with a session thats ready for code submission.
        sessionManager.addRequestCodeResponseMock(.success(stubs.session(nextVerificationAttempt: 0)))

        // We should get back the code entry step.
        coordinator.submitE164(Stubs.e164)
        let nextStep = await coordinator.nextStep()
        guard case .verificationCodeEntry(let codeState) = nextStep else {
            Issue.record("must be verificationCodeEntry")
            return
        }
        #expect(codeState.validationError == nil)
    }

    // MARK: - Helpers

    private func setupDefaultAccountAttributes() {
        ows2FAManagerMock.pinCodeMock = { nil }
        ows2FAManagerMock.shouldMasterKeyBeBackedUpMock = { false }
        ows2FAManagerMock.isReglockEnabledMock = { false }

        tsAccountManagerMock.isManualMessageFetchEnabledMock = { false }

        setAllProfileInfo()
    }

    private func setAllProfileInfo() {
        phoneNumberDiscoverabilityManagerMock.phoneNumberDiscoverabilityMock = { .everybody }
        profileManagerMock.localUserProfileMock = { _ in
            return OWSUserProfile(
                id: nil,
                uniqueId: "00000000-0000-4000-8000-000000000000",
                serviceIdString: nil,
                phoneNumber: nil,
                avatarFileName: nil,
                avatarUrlPath: nil,
                profileKey: Aes256Key(data: Data(count: 32))!,
                givenName: "Johnny",
                familyName: "McJohnface",
                bio: nil,
                bioEmoji: nil,
                badges: [],
                lastFetchDate: Date(timeIntervalSince1970: 1735689600),
                lastMessagingDate: nil,
                isPhoneNumberShared: false,
                hasPaymentAddress: false,
            )
        }
    }

    private static func attributesFromCreateAccountRequest(
        _ request: TSRequest,
    ) -> AccountAttributes {
        let accountAttributesData = try! JSONSerialization.data(
            withJSONObject: request.parameters["accountAttributes"]!,
            options: .fragmentsAllowed,
        )
        return try! JSONDecoder().decode(
            AccountAttributes.self,
            from: accountAttributesData,
        )
    }

    // MARK: - Helpers

    func buildKeyDataMocks(_ testCase: TestCase) -> AccountEntropyPool {
        let oldAep = AccountEntropyPool()
        // on re-registration, make the AEP be present
        db.write { accountKeyStore.setAccountEntropyPool(oldAep, tx: $0) }
        return oldAep
    }

    func storeSvrCredentials(_ svrCredentials: [SVR2AuthCredential]) {
        let invalidCredential = SVR2AuthCredential(credential: RemoteAttestationAuth(username: UUID().uuidString, password: "abc123"))
        db.write { tx in
            for credential in svrCredentials + [invalidCredential] {
                svrAuthCredentialManager.storeAuthCredentialForCurrentUsername(credential, tx)
            }
            svrAuthCredentialManager.deleteInvalidCredentials([invalidCredential], tx)
        }
    }

    func getSvrCredentialUsernames() -> Set<String> {
        return Set(db.read { tx in
            return svrAuthCredentialManager.getAuthCredentials(tx).map(\.credential.username)
        })
    }

    func mockSVRCredentials(isMatch: Bool) {
        // Put some auth credentials in storage.
        let svr2CredentialCandidates: [SVR2AuthCredential] = [
            Stubs.svr2AuthCredential,
            SVR2AuthCredential(credential: RemoteAttestationAuth(username: "aaaa", password: "abc")),
            SVR2AuthCredential(credential: RemoteAttestationAuth(username: "zzzz", password: "xyz")),
            SVR2AuthCredential(credential: RemoteAttestationAuth(username: "0000", password: "123")),
        ]
        storeSvrCredentials(svr2CredentialCandidates)

        // Give it a phone number, which should cause it to check the auth credentials.
        // Match the main auth credential.
        let expectedSVR2CheckRequest = RegistrationRequestFactory.svr2AuthCredentialCheckRequest(
            e164: Stubs.e164,
            credentials: svr2CredentialCandidates,
            logger: .empty(),
        )
        networkManagerMock.asyncRequestHandlers.append(MockNetworkManager.mockResponse(
            matchingRequest: { $0.url.relativeString.hasSuffix(expectedSVR2CheckRequest.url.absoluteString) },
            statusCode: 200,
            bodyJson: RegistrationServiceResponses.SVR2AuthCheckResponse(matches: [
                "\(Stubs.svr2AuthCredential.credential.username):\(Stubs.svr2AuthCredential.credential.password)": isMatch ? .match : .notMatch,
                "aaaa:abc": .notMatch,
                "zzzz:xyz": .invalid,
                "0000:123": .unknown,
            ]),
        ))
    }

    // MARK: - Stubs

    private struct Stubs {

        static let accountEntropyPoolToGenerate = AccountEntropyPool()
        static let e164 = E164("+17875550100")!
        static let aci = Aci.randomForTesting()
        static let pinCode = "1234"

        static let svr2AuthCredential = SVR2AuthCredential(credential: RemoteAttestationAuth(username: "xxx", password: "yyy"))

        static let captchaToken = "captchaToken"
        static let apnsToken = "apnsToken"
        static let apnsRegistrationId = RegistrationRequestFactory.ApnRegistrationId(apnsToken: Stubs.apnsToken)

        static let authUsername = "username_jdhfsalkjfhd"
        static let authPassword = "password_dskafjasldkfjasf"

        static let sessionId = UUID().uuidString
        static let verificationCode = "8888"

        var date: Date = Date()

        static func accountAttributes(registrationRecoveryPassword: RegistrationRecoveryPassword? = nil) -> AccountAttributes {
            return AccountAttributes(
                isManualMessageFetchEnabled: false,
                registrationId: 0,
                pniRegistrationId: 0,
                unidentifiedAccessKey: "",
                unrestrictedUnidentifiedAccess: false,
                reglockToken: nil,
                registrationRecoveryPassword: registrationRecoveryPassword?.rawData.base64EncodedString(),
                encryptedDeviceName: nil,
                discoverableByPhoneNumber: .nobody,
                capabilities: AccountAttributes.Capabilities(hasSVRBackups: true),
            )
        }

        static func accountIdentityResponse(
            hasPreviouslyUsedSVR: Bool = false,
        ) -> AccountIdentityResponse {
            return AccountIdentityResponse(
                localIdentifiers: LocalIdentifiers(
                    aci: Stubs.aci,
                    accountType: .phoneNumberfull(phoneNumber: Stubs.e164.stringValue, pni: .randomForTesting()),
                ),
                storageCapable: hasPreviouslyUsedSVR,
            )
        }

        static func preKeyBundle(identity: OWSIdentity) -> RegistrationPreKeyUploadBundle {
            let identityKeyPair = IdentityKeyPair.generate()
            return RegistrationPreKeyUploadBundle(
                identity: identity,
                identityKeyPair: identityKeyPair,
                signedPreKey: SignedPreKeyStoreImpl.generateSignedPreKey(keyId: PreKeyId.random(), signedBy: identityKeyPair.privateKey),
                lastResortPreKey: KyberPreKeyStoreImpl.generatePreKeyRecord(keyId: 0, now: Date(), signedBy: identityKeyPair.privateKey),
            )
        }

        func session(
            e164: E164 = Stubs.e164,
            receivedDate: Date? = nil,
            nextSMS: TimeInterval? = 0,
            nextCall: TimeInterval? = 0,
            nextVerificationAttempt: TimeInterval? = nil,
            allowedToRequestCode: Bool = true,
            requestedInformation: [RegistrationSession.Challenge] = [],
            hasUnknownChallengeRequiringAppUpdate: Bool = false,
            verified: Bool = false,
        ) -> RegistrationSession {
            let receivedDate = receivedDate ?? date
            return RegistrationSession(
                id: Stubs.sessionId,
                e164: e164,
                receivedDate: receivedDate,
                nextSMS: nextSMS,
                nextCall: nextCall,
                nextVerificationAttempt: nextVerificationAttempt,
                allowedToRequestCode: allowedToRequestCode,
                requestedInformation: requestedInformation,
                hasUnknownChallengeRequiringAppUpdate: hasUnknownChallengeRequiringAppUpdate,
                verified: verified,
            )
        }
    }
}

private extension MasterKey {
    var regRecoveryPw: String { deriveRegistrationRecoveryPassword().rawData.base64EncodedString() }
    var reglockToken: String { deriveRegistrationLock().rawData.hexadecimalString }
}

struct EncodableRegistrationLockFailureResponse: Codable {
    typealias ResponseType = RegistrationServiceResponses.RegistrationLockFailureResponse
    typealias CodingKeys = ResponseType.CodingKeys

    var response: ResponseType

    init(from decoder: any Decoder) throws {
        response = try ResponseType(from: decoder)
    }

    init(timeRemainingMs: Int, svr2AuthCredential: SVR2AuthCredential) {
        response = ResponseType(timeRemainingMs: timeRemainingMs, svr2AuthCredential: svr2AuthCredential)
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(response.timeRemainingMs, forKey: .timeRemainingMs)
        try container.encodeIfPresent(response.svr2AuthCredential.credential, forKey: .svr2AuthCredential)
    }
}

extension AccountIdentityResponse: @retroactive Encodable {
    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(self.localIdentifiers.aci.rawUUID, forKey: .aci)
        switch self.localIdentifiers.accountType {
        case .phoneNumberfull(let phoneNumber, let pni):
            try container.encode(phoneNumber, forKey: .number)
            try container.encode(pni?.rawUUID, forKey: .pni)
        case .phoneNumberless(let authCredentialSalt):
            try container.encode(authCredentialSalt, forKey: .authCredentialSalt)
        }
        try container.encodeIfPresent(self.usernameHash.map({ DataBase64Url($0) }), forKey: .usernameHash)
        try container.encodeIfPresent(self.usernameLinkHandle, forKey: .usernameLinkHandle)
        try container.encode(self.storageCapable, forKey: .storageCapable)
        // Omit entitlements because they're not needed here.
        struct FakeEntitlements: Encodable {
            var badges: [Int]
            var backup: Int?
        }
        try container.encode(FakeEntitlements(badges: [], backup: nil), forKey: .entitlements)
    }
}

private extension Usernames.UsernameLink {
    static var mocked: Usernames.UsernameLink {
        return UsernameLink(
            handle: UUID(),
            entropy: try! UsernameLink.Entropy(rawValue: Data(repeating: 8, count: 32)),
        )
    }
}

private extension TSRequest {
    var authPassword: String {
        var httpHeaders = HttpHeaders()
        try! applyAuth(to: &httpHeaders, socketAuth: nil)
        let authHeader = httpHeaders.value(forHeader: "Authorization")!
        owsPrecondition(authHeader.hasPrefix("Basic "))
        let authValue = String(data: Data(base64Encoded: String(authHeader.dropFirst(6)))!, encoding: .utf8)!
        return String(authValue.split(separator: ":").dropFirst().first!)
    }
}

private extension RegistrationStep {
    var isRegistrationSplash: Bool {
        if case .registrationSplash = self {
            return true
        }
        return false
    }

    var isAppUpdateBanner: Bool {
        if case .appUpdateBanner = self {
            return true
        }
        return false
    }

    var isPermissions: Bool {
        if case .permissions = self {
            return true
        }
        return false
    }

    var isDone: Bool {
        if case .done = self {
            return true
        }
        return false
    }
}
