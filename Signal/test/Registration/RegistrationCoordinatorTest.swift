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
    private var stubs = Stubs()

    private var date: Date { self.stubs.date }
    private var dateProvider: DateProvider!

    private var appExpiry: AppExpiry!
    private var changeNumberPniManager: ChangePhoneNumberPniManagerMock!
    private var contactsStore: RegistrationCoordinatorImpl.TestMocks.ContactsStore!
    private var db: (any DB)!
    private var experienceManager: RegistrationCoordinatorImpl.TestMocks.ExperienceManager!
    private var featureFlags: RegistrationCoordinatorImpl.TestMocks.FeatureFlags!
    private var accountKeyStore: AccountKeyStore!
    private var localUsernameManagerMock: MockLocalUsernameManager!
    private var mockMessagePipelineSupervisor: RegistrationCoordinatorImpl.TestMocks.MessagePipelineSupervisor!
    private var mockMessageProcessor: RegistrationCoordinatorImpl.TestMocks.MessageProcessor!
    private var mockURLSession: TSRequestOWSURLSessionMock!
    private var ows2FAManagerMock: RegistrationCoordinatorImpl.TestMocks.OWS2FAManager!
    private var phoneNumberDiscoverabilityManagerMock: MockPhoneNumberDiscoverabilityManager!
    private var preKeyManagerMock: RegistrationCoordinatorImpl.TestMocks.PreKeyManager!
    private var profileManagerMock: RegistrationCoordinatorImpl.TestMocks.ProfileManager!
    private var pushRegistrationManagerMock: RegistrationCoordinatorImpl.TestMocks.PushRegistrationManager!
    private var receiptManagerMock: RegistrationCoordinatorImpl.TestMocks.ReceiptManager!
    private var registrationCoordinatorLoader: RegistrationCoordinatorLoaderImpl!
    private var registrationStateChangeManagerMock: MockRegistrationStateChangeManager!
    private var sessionManager: RegistrationSessionManagerMock!
    private var storageServiceManagerMock: RegistrationCoordinatorImpl.TestMocks.StorageServiceManager!
    private var svr: SecureValueRecoveryMock!
    private var svrLocalStorageMock: SVRLocalStorageMock!
    private var svrAuthCredentialStore: SVRAuthCredentialStorageMock!
    private var timeoutProviderMock: RegistrationCoordinatorImpl.TestMocks.TimeoutProvider!
    private var tsAccountManagerMock: MockTSAccountManager!
    private var usernameApiClientMock: RegistrationCoordinatorImpl.TestMocks.UsernameApiClient!
    private var usernameLinkManagerMock: MockUsernameLinkManager!
    private var missingKeyGenerator: MissingKeyGenerator!

    class RegistrationTestRun {
        private(set) var recordedSteps = [TestStep]()
        func addObservedStep(_ step: TestStep) {
            recordedSteps.append(step)
        }
    }
    private var testRun = RegistrationTestRun()

    private class MissingKeyGenerator {
        var masterKey: () -> MasterKey = { fatalError("Default MasterKey not provided") }
        var accountEntropyPool: () -> SignalServiceKit.AccountEntropyPool = { fatalError("Default AccountEntropyPool not provided")  }
    }

    init() {
        dateProvider = { self.date }
        db = InMemoryDB()

        missingKeyGenerator = .init()

        appExpiry = .forUnitTests()
        changeNumberPniManager = ChangePhoneNumberPniManagerMock(
            mockKyberStore: KyberPreKeyStoreImpl(for: .pni, dateProvider: dateProvider)
        )
        contactsStore = RegistrationCoordinatorImpl.TestMocks.ContactsStore()
        experienceManager = RegistrationCoordinatorImpl.TestMocks.ExperienceManager()
        featureFlags = RegistrationCoordinatorImpl.TestMocks.FeatureFlags()
        accountKeyStore = AccountKeyStore(
            masterKeyGenerator: { self.missingKeyGenerator.masterKey() },
            accountEntropyPoolGenerator: { self.missingKeyGenerator.accountEntropyPool() }
        )
        localUsernameManagerMock = {
            let mock = MockLocalUsernameManager()
            // This should result in no username reclamation. Tests that want to
            // test reclamation should overwrite this.
            mock.startingUsernameState = .unset
            return mock
        }()
        svr = SecureValueRecoveryMock()
        svrAuthCredentialStore = SVRAuthCredentialStorageMock()
        mockMessagePipelineSupervisor = RegistrationCoordinatorImpl.TestMocks.MessagePipelineSupervisor()
        mockMessageProcessor = RegistrationCoordinatorImpl.TestMocks.MessageProcessor()
        ows2FAManagerMock = RegistrationCoordinatorImpl.TestMocks.OWS2FAManager()
        phoneNumberDiscoverabilityManagerMock = MockPhoneNumberDiscoverabilityManager()
        preKeyManagerMock = RegistrationCoordinatorImpl.TestMocks.PreKeyManager(run: testRun)
        profileManagerMock = RegistrationCoordinatorImpl.TestMocks.ProfileManager()
        pushRegistrationManagerMock = RegistrationCoordinatorImpl.TestMocks.PushRegistrationManager(run: testRun)
        receiptManagerMock = RegistrationCoordinatorImpl.TestMocks.ReceiptManager()
        registrationStateChangeManagerMock = MockRegistrationStateChangeManager()
        sessionManager = RegistrationSessionManagerMock()
        svrLocalStorageMock = SVRLocalStorageMock()
        storageServiceManagerMock = RegistrationCoordinatorImpl.TestMocks.StorageServiceManager(run: testRun)
        timeoutProviderMock = RegistrationCoordinatorImpl.TestMocks.TimeoutProvider()
        tsAccountManagerMock = MockTSAccountManager()
        usernameApiClientMock = RegistrationCoordinatorImpl.TestMocks.UsernameApiClient()
        usernameLinkManagerMock = MockUsernameLinkManager()

        let mockURLSession = TSRequestOWSURLSessionMock()
        self.mockURLSession = mockURLSession
        let mockSignalService = OWSSignalServiceMock()
        mockSignalService.mockUrlSessionBuilder = { _, _, _ in
            return mockURLSession
        }

        let dependencies = RegistrationCoordinatorDependencies(
            appExpiry: appExpiry,
            backupArchiveManager: BackupArchiveManagerMock(),
            backupKeyMaterial: BackupKeyMaterialMock(),
            changeNumberPniManager: changeNumberPniManager,
            contactsManager: RegistrationCoordinatorImpl.TestMocks.ContactsManager(),
            contactsStore: contactsStore,
            dateProvider: { self.dateProvider() },
            db: db,
            deviceTransferService: RegistrationCoordinatorImpl.TestMocks.DeviceTransferService(),
            experienceManager: experienceManager,
            featureFlags: featureFlags,
            accountKeyStore: accountKeyStore,
            identityManager: RegistrationCoordinatorImpl.TestMocks.IdentityManager(),
            localUsernameManager: localUsernameManagerMock,
            messagePipelineSupervisor: mockMessagePipelineSupervisor,
            messageProcessor: mockMessageProcessor,
            ows2FAManager: ows2FAManagerMock,
            phoneNumberDiscoverabilityManager: phoneNumberDiscoverabilityManagerMock,
            preKeyManager: preKeyManagerMock,
            profileManager: profileManagerMock,
            pushRegistrationManager: pushRegistrationManagerMock,
            quickRestoreManager: RegistrationCoordinatorImpl.TestMocks.QuickRestoreManager(),
            receiptManager: receiptManagerMock,
            registrationBackupErrorPresenter: RegistrationCoordinatorBackupErrorPresenterMock(),
            registrationStateChangeManager: registrationStateChangeManagerMock,
            sessionManager: sessionManager,
            signalService: mockSignalService,
            storageServiceRecordIkmCapabilityStore: StorageServiceRecordIkmCapabilityStoreImpl(),
            storageServiceManager: storageServiceManagerMock,
            svr: svr,
            svrAuthCredentialStore: svrAuthCredentialStore,
            timeoutProvider: timeoutProviderMock,
            tsAccountManager: tsAccountManagerMock,
            udManager: RegistrationCoordinatorImpl.TestMocks.UDManager(),
            usernameApiClient: usernameApiClientMock,
            usernameLinkManager: usernameLinkManagerMock
        )
        registrationCoordinatorLoader = RegistrationCoordinatorLoaderImpl(dependencies: dependencies)
    }

    enum KeyType: CustomDebugStringConvertible {
        case none
        case masterKey
        case accountEntropyPool

        var debugDescription: String {
            switch self {
            case .none: return "none"
            case .masterKey: return "masterKey"
            case .accountEntropyPool: return "AEP"
            }
        }

        static var testCases: [(old: Self, new: Self)] {
            return [
                (.masterKey, .accountEntropyPool),
                (.accountEntropyPool, .accountEntropyPool)
            ]
        }
    }

    static let testModes: [RegistrationMode] = [
        RegistrationMode.registering,
        RegistrationMode.reRegistering(.init(e164: Stubs.e164, aci: Stubs.aci))
    ]

    typealias TestCase = (mode: RegistrationMode, oldKey: KeyType, newKey: KeyType)

    static func onlyReRegisteringTestCases() -> [TestCase] {
        return buildTestCases(for: [RegistrationMode.reRegistering(.init(e164: Stubs.e164, aci: Stubs.aci))])
    }

    static func testCases() -> [TestCase] {
        return buildTestCases(for: testModes)
    }

    static func buildTestCases(for modes: [RegistrationMode]) -> [TestCase] {
        var results = [(mode: RegistrationMode, oldKey: KeyType, newKey: KeyType)]()
        for mode in modes {
            for keys in KeyType.testCases {
                results.append((mode, keys.old, keys.new))
            }
        }
        return results
    }

    func setupTest(_ testCase: TestCase) -> RegistrationCoordinatorImpl {
        return db.write {
            return registrationCoordinatorLoader.coordinator(
                forDesiredMode: testCase.mode,
                transaction: $0
            ) as! RegistrationCoordinatorImpl
        }
    }

    enum TestStep: String, Equatable, CustomDebugStringConvertible {
        case restoreKeys
        case requestPushToken
        case createPreKeys
        case createAccount
        case finalizePreKeys
        case rotateOneTimePreKeys
        case restoreStorageService
        case backupMasterKey
        case confirmReservedUsername
        case rotateManifest
        case updateAccountAttribute
        case failedRequest

        var debugDescription: String {
            switch self {
            case .restoreKeys: return "restoreKeys"
            case .requestPushToken: return "requestPushToken"
            case .createPreKeys: return "createPreKeys"
            case .createAccount: return "createAccount"
            case .finalizePreKeys: return "finalizePreKeys"
            case .rotateOneTimePreKeys: return "rotateOneTimePreKeys"
            case .restoreStorageService: return "restoreStorageService"
            case .backupMasterKey: return "backupMasterKey"
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
            #expect(await coordinator.nextStep().awaitable() == .registrationSplash)
            // Once we show it, don't show it again.
            #expect(await coordinator.continueFromSplash().awaitable() != .registrationSplash)
        case .reRegistering, .changingNumber:
            #expect(await coordinator.nextStep().awaitable() != .registrationSplash)
        }
    }

    @MainActor @Test(arguments: Self.testCases())
    func testOpeningPath_appExpired(testCase: TestCase) async {
        let coordinator = setupTest(testCase)

        self.stubs.date = .distantFuture

        setupDefaultAccountAttributes()

        // We should start with the banner.
        #expect(await coordinator.nextStep().awaitable() == .appUpdateBanner)
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
            #expect(await coordinator.nextStep().awaitable() == .registrationSplash)
            nextStep = await coordinator.continueFromSplash().awaitable()
        case .reRegistering, .changingNumber:
            // No splash for these.
            nextStep = await coordinator.nextStep().awaitable()
        }

        // Now we should show the permissions.
        #expect(nextStep == .permissions)
        // Doesn't change even if we try and proceed.
        #expect(await coordinator.nextStep().awaitable() == .permissions)

        // Once the state is updated we can proceed.
        nextStep = await coordinator.requestPermissions().awaitable()
        #expect(nextStep != .registrationSplash)
        #expect(nextStep != .permissions)
    }

    // MARK: - Reg Recovery Password Path

    @MainActor @Test(arguments: Self.testCases(), [true, false])
    func runRegRecoverPwPathTestHappyPath(testCase: TestCase, wasReglockEnabled: Bool) async throws {
        let coordinator = setupTest(testCase)
        let mode = testCase.mode

        // Set profile info so we skip those steps.
        setupDefaultAccountAttributes()

        ows2FAManagerMock.isReglockEnabledMock = { wasReglockEnabled }

        // Set a PIN on disk.
        ows2FAManagerMock.pinCodeMock = { Stubs.pinCode }

        let (initialMasterKey, finalMasterKey) = buildKeyDataMocks(testCase)

        // Give it the pin code, which should make it try and register.

        // It needs an apns token to register.
        pushRegistrationManagerMock.addRequestPushTokenMock({ .value(.success(Stubs.apnsRegistrationId)) })
        // It needs prekeys as well.
        preKeyManagerMock.addCreatePreKeysMock({ return .value(Stubs.prekeyBundles()) })
        // And will finalize prekeys after success.
        preKeyManagerMock.addFinalizePreKeyMock { didSucceed in
            #expect(didSucceed)
            return .value(())
        }

        let identityResponse = Stubs.accountIdentityResponse()
        var authPassword: String!
        let expectedRequest = createAccountWithRecoveryPw(initialMasterKey)
        mockURLSession.addResponse(TSRequestOWSURLSessionMock.Response(
            matcher: { request in
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
            bodyData: try JSONEncoder().encode(identityResponse)
        ))

        func expectedAuthedAccount() -> AuthedAccount {
            return .explicit(
                aci: identityResponse.aci,
                pni: identityResponse.pni,
                e164: Stubs.e164,
                deviceId: .primary,
                authPassword: authPassword
            )
        }

        // When registered, we should create pre-keys.
        preKeyManagerMock.addRotateOneTimePreKeyMock({ auth in
            #expect(auth == expectedAuthedAccount().chatServiceAuth)
            return .value(())
        })

        if wasReglockEnabled {
            // If we had reglock before registration, it should be re-enabled.
            let expectedReglockRequest = OWSRequestFactory.enableRegistrationLockV2Request(token: finalMasterKey.reglockToken)
            mockURLSession.addResponse(TSRequestOWSURLSessionMock.Response(
                matcher: { request in
                    #expect(finalMasterKey.reglockToken == request.parameters["registrationLock"] as! String)
                    return request.url == expectedReglockRequest.url
                },
                statusCode: 200,
                bodyData: nil
            ))
        }

        // We haven't done a SVR backup; that should happen now.
        svr.backupMasterKeyMock = { pin, masterKey, authMethod in
            #expect(pin == Stubs.pinCode)
            // We don't have a SVR auth credential, it should use chat server creds.
            #expect(masterKey.rawData == finalMasterKey.rawData)
            #expect(authMethod == .chatServerAuth(expectedAuthedAccount()))
            self.svr.hasMasterKey = true
            return .value(masterKey)
        }

        // Once we sync push tokens, we should restore from storage service.
        storageServiceManagerMock.addRestoreOrCreateManifestIfNecessaryMock({ auth, masterKeySource in
            #expect(auth.authedAccount == expectedAuthedAccount())
            switch masterKeySource {
            case .explicit(let explicitMasterKey):
                #expect(initialMasterKey.rawData == explicitMasterKey.rawData)
            default:
                Issue.record("Unexpected master key used in storage service operation.")
            }
            return .value(())
        })

        storageServiceManagerMock.addRotateManifestMock({ _, _ in return .value(()) })

        // Once we restore from storage service, we should attempt to reclaim
        // our username.
        let mockUsernameLink: Usernames.UsernameLink = .mocked
        localUsernameManagerMock.startingUsernameState = .available(username: "boba.42", usernameLink: mockUsernameLink)
        usernameApiClientMock.confirmReservedUsernameMocks = [{ _, _, chatServiceAuth in
            #expect(chatServiceAuth == .explicit(
                aci: identityResponse.aci,
                deviceId: .primary,
                password: authPassword
            ))
            return .value(.success(usernameLinkHandle: mockUsernameLink.handle))
        }]

        // Once we do the username reclamation,
        // we will sync account attributes and then we are finished!
        let expectedAttributesRequest = RegistrationRequestFactory.updatePrimaryDeviceAccountAttributesRequest(
            Stubs.accountAttributes(finalMasterKey),
            auth: .implicit() // doesn't matter for url matching
        )
        mockURLSession.addResponse(
            matcher: { request in
                return request.url == expectedAttributesRequest.url
            },
            statusCode: 200
        )

        // NOTE: We expect to skip opening path steps because
        // if we have a SVR master key locally, this _must_ be
        // a previously registered device, and we can skip intros.

        // We haven't set a phone number so it should ask for that.
        #expect(
            await coordinator.nextStep().awaitable() ==
                .phoneNumberEntry(stubs.phoneNumberEntryState(mode: mode))
        )

        // Give it a phone number, which should show the PIN entry step.
        // Now it should ask for the PIN to confirm the user knows it.
        #expect(
            await coordinator.submitE164(Stubs.e164).awaitable() ==
                .pinEntry(Stubs.pinEntryStateForRegRecoveryPath(mode: mode)))

        #expect(await coordinator.submitPINCode(Stubs.pinCode).awaitable() == .done)

        // Since we set profile info, we should have scheduled a reupload.
        #expect(profileManagerMock.didScheduleReuploadLocalProfile)
    }

    @MainActor @Test(arguments: Self.testCases())
    func testRegRecoveryPwPath_wrongPIN(testCase: TestCase) async throws {
        let coordinator = setupTest(testCase)
        let mode = testCase.mode

        // Set profile info so we skip those steps.
        setupDefaultAccountAttributes()

        let wrongPinCode = "ABCD"

        // Set a different PIN on disk.
        ows2FAManagerMock.pinCodeMock = { Stubs.pinCode }

        let (initialMasterKey, finalMasterKey) = buildKeyDataMocks(testCase)
        // NOTE: We expect to skip opening path steps because
        // if we have a SVR master key locally, this _must_ be
        // a previously registered device, and we can skip intros.

        // Give it the right pin code, which should make it try and register.

        // It needs an apns token to register.
        pushRegistrationManagerMock.addRequestPushTokenMock({ .value(.success(Stubs.apnsRegistrationId)) })
        // Every time we register we also ask for prekeys.
        preKeyManagerMock.addCreatePreKeysMock({ .value(Stubs.prekeyBundles()) })
        // And we finalize them after.
        preKeyManagerMock.addFinalizePreKeyMock { didSucceed in
            #expect(didSucceed)
            return .value(())
        }

        let identityResponse = Stubs.accountIdentityResponse()
        var authPassword: String!
        let expectedRequest = createAccountWithRecoveryPw(initialMasterKey)
        mockURLSession.addResponse(TSRequestOWSURLSessionMock.Response(
            matcher: { request in
                authPassword = request.authPassword
                let requestAttributes = Self.attributesFromCreateAccountRequest(request)
                let recoveryPw = initialMasterKey.regRecoveryPw
                #expect(recoveryPw == (request.parameters["recoveryPassword"] as? String) ?? "")
                #expect(recoveryPw == requestAttributes.registrationRecoveryPassword)
                #expect(requestAttributes.registrationLockToken == nil)
                return request.url == expectedRequest.url
            },
            statusCode: 200,
            bodyData: try JSONEncoder().encode(identityResponse)
        ))

        func expectedAuthedAccount() -> AuthedAccount {
            return .explicit(
                aci: identityResponse.aci,
                pni: identityResponse.pni,
                e164: Stubs.e164,
                deviceId: .primary,
                authPassword: authPassword
            )
        }

        // When registered, we should create pre-keys.
        preKeyManagerMock.addRotateOneTimePreKeyMock({ auth in
            #expect(auth == expectedAuthedAccount().chatServiceAuth)
            return .value(())
        })

        // We haven't done a SVR backup; that should happen now.
        svr.backupMasterKeyMock = { pin, masterKey, authMethod in
            #expect(pin == Stubs.pinCode)
            #expect(masterKey.rawData == finalMasterKey.rawData)
            // We don't have a SVR auth credential, it should use chat server creds.
            #expect(authMethod == .chatServerAuth(expectedAuthedAccount()))
            self.svr.hasMasterKey = true
            return .value(masterKey)
        }

        // Once we sync push tokens, we should restore from storage service.
        storageServiceManagerMock.addRestoreOrCreateManifestIfNecessaryMock({ auth, masterKeySource in
            #expect(auth.authedAccount == expectedAuthedAccount())
            switch masterKeySource {
            case .explicit(let explicitMasterKey):
                #expect(initialMasterKey.rawData == explicitMasterKey.rawData)
            default:
                Issue.record("Unexpected master key used in storage service operation.")
            }
            return .value(())
        })

        storageServiceManagerMock.addRotateManifestMock({ _, _ in return .value(()) })

        // Once we restore from storage service, we should attempt to reclaim
        // our username. For this test, let's have a corrupted username (and
        // skip reclamation). This should have no impact on the rest of
        // registration.
        localUsernameManagerMock.startingUsernameState = .usernameAndLinkCorrupted

        // Once we do the storage service restore,
        // we will sync account attributes and then we are finished!
        let expectedAttributesRequest = RegistrationRequestFactory.updatePrimaryDeviceAccountAttributesRequest(
            Stubs.accountAttributes(finalMasterKey),
            auth: .implicit() // // doesn't matter for url matching
        )
        mockURLSession.addResponse(
            matcher: { request in
                #expect(finalMasterKey.regRecoveryPw == (request.parameters["recoveryPassword"] as? String) ?? "")
                return request.url == expectedAttributesRequest.url
            },
            statusCode: 200
         )

        // We haven't set a phone number so it should ask for that.
        #expect(
            await coordinator.nextStep().awaitable() ==
                .phoneNumberEntry(stubs.phoneNumberEntryState(mode: mode))
        )

        // Give it a phone number, which should show the PIN entry step.

        // Now it should ask for the PIN to confirm the user knows it.
        #expect(
            await coordinator.submitE164(Stubs.e164).awaitable() ==
                .pinEntry(Stubs.pinEntryStateForRegRecoveryPath(mode: mode))
        )

        // Give it the wrong PIN, it should reject and give us the same step again.
        #expect(
            await coordinator.submitPINCode(wrongPinCode).awaitable() ==
                .pinEntry(Stubs.pinEntryStateForRegRecoveryPath(
                    mode: mode,
                    error: .wrongPin(wrongPin: wrongPinCode),
                    remainingAttempts: 9
                ))
        )

        #expect(await coordinator.submitPINCode(Stubs.pinCode).awaitable() == .done)

        // Since we set profile info, we should have scheduled a reupload.
        #expect(profileManagerMock.didScheduleReuploadLocalProfile)
    }

    @MainActor @Test(arguments: Self.testCases())
    func testRegRecoveryPwPath_wrongPassword(testCase: TestCase) async {
        let coordinator = setupTest(testCase)
        let mode = testCase.mode

        // Set profile info so we skip those steps.
        setupDefaultAccountAttributes()

        // Set a PIN on disk.
        ows2FAManagerMock.pinCodeMock = { Stubs.pinCode }

        // Make SVR give us back a reg recovery password.
        let masterKey = AccountEntropyPool().getMasterKey()
        await db.awaitableWrite { accountKeyStore.setMasterKey(masterKey, tx: $0) }
        svr.hasMasterKey = true

        // NOTE: We expect to skip opening path steps because
        // if we have a SVR master key locally, this _must_ be
        // a previously registered device, and we can skip intros.

        // Before registering, it should ask for push tokens to give the registration.
        // It will also ask again later when account creation fails and it needs
        // to create a new session.
        pushRegistrationManagerMock.addRequestPushTokenMock({ .value(.success(Stubs.apnsRegistrationId)) })
        pushRegistrationManagerMock.addRequestPushTokenMock({ .value(.success(Stubs.apnsRegistrationId)) })

        // Every time we register we also ask for prekeys.
        preKeyManagerMock.addCreatePreKeysMock({ .value(Stubs.prekeyBundles()) })
        preKeyManagerMock.addCreatePreKeysMock({ .value(Stubs.prekeyBundles()) })

        // And we finalize them after.
        // Set up a list of mocks that should be returned in order
        preKeyManagerMock.addFinalizePreKeyMock { didSucceed in
            #expect(didSucceed.negated)
            return .value(())
        }
        preKeyManagerMock.addFinalizePreKeyMock { didSucceed in
            #expect(didSucceed)
            return .value(())
        }

        // Fail the request; the reg recovery pw is invalid.
        let expectedRecoveryPwRequest = createAccountWithRecoveryPw(masterKey)
        let failResponse = TSRequestOWSURLSessionMock.Response(
            urlSuffix: expectedRecoveryPwRequest.url.absoluteString,
            statusCode: RegistrationServiceResponses.AccountCreationResponseCodes.unauthorized.rawValue
        )
        mockURLSession.addResponse(failResponse)

        // Once the first request fails, it should try an start a session. Resolve with a session.
        sessionManager.addBeginSessionResponseMock(.success(stubs.session()))

        // Before requesting a session, it should ask for push tokens to give the session.
        // This was set up above.

        // Then when it gets back the session, it should immediately ask for a verification code to be sent.

        // We'll ask for a push challenge, though we don't need to resolve it in this test.
        pushRegistrationManagerMock.addReceivePreAuthChallengeTokenMock({ .value("PUSH TOKEN") })

        // Resolve with an updated session.
        sessionManager.addRequestCodeResponseMock(.success(stubs.session(nextVerificationAttempt: 0)))

        // We haven't set a phone number so it should ask for that.
        #expect(
            await coordinator.nextStep().awaitable() ==
                .phoneNumberEntry(stubs.phoneNumberEntryState(mode: mode))
        )

        // Give it a phone number, which should show the PIN entry step.
        // Now it should ask for the PIN to confirm the user knows it.
        #expect(
            await coordinator.submitE164(Stubs.e164).awaitable() ==
                .pinEntry(Stubs.pinEntryStateForRegRecoveryPath(mode: mode))
        )

        // Check we have the master key now, to be safe.
        #expect(svr.hasMasterKey)

        // Give it the pin code, which should make it try and register.
        // Now we should expect to be at verification code entry since we already set the phone number.
        // No exit allowed since we've already started trying to create the account.
        #expect(
            await coordinator.submitPINCode(Stubs.pinCode).awaitable() ==
                .verificationCodeEntry(
                    stubs.verificationCodeEntryState(mode: mode, exitConfigOverride: .noExitAllowed)
                )
        )

        // We want to have kept the master key; we failed the reg recovery pw check
        // but that could happen even if the key is valid. Once we finish session based
        // re-registration we want to be able to recover the key.
        #expect(svr.hasMasterKey)
    }

    @MainActor @Test(arguments: Self.testCases())
    func testRegRecoveryPwPath_failedReglock(testCase: TestCase) async {
        let coordinator = setupTest(testCase)
        let mode = testCase.mode

        // Set profile info so we skip those steps.
        setupDefaultAccountAttributes()

        // Set a PIN on disk.
        ows2FAManagerMock.pinCodeMock = { Stubs.pinCode }

        // Make SVR give us back a reg recovery password.
        let masterKey = AccountEntropyPool().getMasterKey()
        db.write { accountKeyStore.setMasterKey(masterKey, tx: $0) }
        svr.hasMasterKey = true

        // NOTE: We expect to skip opening path steps because
        // if we have a SVR master key locally, this _must_ be
        // a previously registered device, and we can skip intros.

        // First we try and create an account with reg recovery
        // password; we will fail with reglock error.
        // First we get apns tokens, then prekeys, then register
        // then finalize prekeys (with failure) after.

        // Once we fail, we try again immediately with the reglock
        // token we fetch.
        // Same sequence as the first request.

        // When that fails, we try and create a session.
        // No prekey stuff this time, just apns token and session requests.

        pushRegistrationManagerMock.addRequestPushTokenMock({.value(.success(Stubs.apnsRegistrationId)) })
        pushRegistrationManagerMock.addRequestPushTokenMock({.value(.success(Stubs.apnsRegistrationId)) })
        pushRegistrationManagerMock.addRequestPushTokenMock({.value(.success(Stubs.apnsRegistrationId)) })
        pushRegistrationManagerMock.addRequestPushTokenMock({.value(.success(Stubs.apnsRegistrationId)) })

        preKeyManagerMock.addCreatePreKeysMock({ .value(Stubs.prekeyBundles()) })
        preKeyManagerMock.addCreatePreKeysMock({ .value(Stubs.prekeyBundles()) })
        preKeyManagerMock.addCreatePreKeysMock({ .value(Stubs.prekeyBundles()) })

        preKeyManagerMock.addFinalizePreKeyMock { didSucceed in
            #expect(didSucceed.negated)
            return .value(())
        }
        preKeyManagerMock.addFinalizePreKeyMock { didSucceed in
            #expect(didSucceed.negated)
            return .value(())
        }

        // Fail the first request; the reglock is invalid.
        let expectedRecoveryPwRequest = createAccountWithRecoveryPw(masterKey)
        let failResponse = TSRequestOWSURLSessionMock.Response(
            urlSuffix: expectedRecoveryPwRequest.url.absoluteString,
            statusCode: RegistrationServiceResponses.AccountCreationResponseCodes.reglockFailed.rawValue,
            bodyJson: EncodableRegistrationLockFailureResponse(
                timeRemainingMs: 10,
                svr2AuthCredential: Stubs.svr2AuthCredential
            )
        )
        mockURLSession.addResponse(failResponse)

        // Once the request fails, we should try again with the reglock
        // token, this time.
        mockURLSession.addResponse(failResponse)

        // Once the second request fails, it should try an start a session.

            // We'll ask for a push challenge, though we don't need to resolve it in this test.
        pushRegistrationManagerMock.addReceivePreAuthChallengeTokenMock({ Guarantee<String>.pending().0 })

        // Resolve with a session.
        sessionManager.addBeginSessionResponseMock(.success(stubs.session()))

        // Then when it gets back the session, it should immediately ask for
        // a verification code to be sent.

        // Resolve with an updated session.
        sessionManager.addRequestCodeResponseMock(.success(stubs.session(nextVerificationAttempt: 0)))

        // We haven't set a phone number so it should ask for that.
        #expect(
            await coordinator.nextStep().awaitable() ==
                .phoneNumberEntry(stubs.phoneNumberEntryState(mode: mode))
        )

        // Give it a phone number, which should show the PIN entry step.
        // Now it should ask for the PIN to confirm the user knows it.
        #expect(
            await coordinator.submitE164(Stubs.e164).awaitable() ==
                .pinEntry(Stubs.pinEntryStateForRegRecoveryPath(mode: mode))
        )

        #expect(svr.hasMasterKey)

        // Give it the pin code, which should make it try and register.
        // Now we should expect to be at verification code entry since we already set the phone number.
        // No exit allowed since we've already started trying to create the account.
        // We want to have wiped our master key; we failed reglock, which means the key itself is wrong
        #expect(
            await coordinator.submitPINCode(Stubs.pinCode).awaitable() ==
                .verificationCodeEntry(
                    stubs.verificationCodeEntryState(mode: mode, exitConfigOverride: .noExitAllowed)
                )
        )

        #expect(svr.hasMasterKey.negated)
    }

    @MainActor @Test(arguments: Self.testCases())
    func testRegRecoveryPwPath_retryNetworkError(testCase: TestCase) async throws {
        let coordinator = setupTest(testCase)
        let mode = testCase.mode

        // Set profile info so we skip those steps.
        setupDefaultAccountAttributes()

        // Set a PIN on disk.
    ows2FAManagerMock.pinCodeMock = { Stubs.pinCode }

        let (initialMasterKey, finalMasterKey) = buildKeyDataMocks(testCase)
        svr.hasMasterKey = true

        // NOTE: We expect to skip opening path steps because
        // if we have a SVR master key locally, this _must_ be
        // a previously registered device, and we can skip intros.

        // Before registering, it should ask for push tokens to give the registration.
        // When it retries, it will ask again.
        pushRegistrationManagerMock.addRequestPushTokenMock({ .value(.success(Stubs.apnsRegistrationId)) })
        pushRegistrationManagerMock.addRequestPushTokenMock({ .value(.success(Stubs.apnsRegistrationId)) })

        // Every time we register we also ask for prekeys.
        preKeyManagerMock.addCreatePreKeysMock({ return .value(Stubs.prekeyBundles()) })
        preKeyManagerMock.addCreatePreKeysMock({ return .value(Stubs.prekeyBundles()) })

        // And we finalize them after.
        preKeyManagerMock.addFinalizePreKeyMock { didSucceed in
            #expect(didSucceed.negated)
            return .value(())
        }
        preKeyManagerMock.addFinalizePreKeyMock { didSucceed in
            #expect(didSucceed)
            return .value(())
        }

        // Fail the request with a network error.
        let expectedRecoveryPwRequest = createAccountWithRecoveryPw(initialMasterKey)
        let failResponse = TSRequestOWSURLSessionMock.Response.networkError(
            matcher: { _ in
                self.testRun.addObservedStep(.failedRequest)
                return true
            },
            url: expectedRecoveryPwRequest.url
        )
        mockURLSession.addResponse(failResponse)

        let identityResponse = Stubs.accountIdentityResponse()
        var authPassword: String!

        // Once the first request fails, it should retry. Resolve with success
        let expectedRequest = createAccountWithRecoveryPw(initialMasterKey)
        mockURLSession.addResponse(
            TSRequestOWSURLSessionMock.Response(
                matcher: { request in
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
                bodyData: try! JSONEncoder().encode(identityResponse)
            )
        )

        func expectedAuthedAccount() -> AuthedAccount {
            return .explicit(
                aci: identityResponse.aci,
                pni: identityResponse.pni,
                e164: Stubs.e164,
                deviceId: .primary,
                authPassword: authPassword
            )
        }

        // When registered, it should try and sync pre-keys.
        preKeyManagerMock.addRotateOneTimePreKeyMock({ auth in
            #expect(auth == expectedAuthedAccount().chatServiceAuth)
            return .value(())
        })

        // We haven't done a SVR backup; that should happen.
        svr.backupMasterKeyMock = { pin, masterKey, authMethod in
            self.testRun.addObservedStep(.backupMasterKey)
            #expect(pin == Stubs.pinCode)
            #expect(masterKey.rawData == finalMasterKey.rawData)
            // We don't have a SVR auth credential, it should use chat server creds.
            #expect(authMethod == .chatServerAuth(expectedAuthedAccount()))
            self.svr.hasMasterKey = true
            return .value(masterKey)
        }

        // Once we back up to svr, we should restore from storage service.
        storageServiceManagerMock.addRestoreOrCreateManifestIfNecessaryMock({ auth, masterKeySource in
            #expect(auth.authedAccount == expectedAuthedAccount())
            switch masterKeySource {
            case .explicit(let explicitMasterKey):
                #expect(initialMasterKey.rawData == explicitMasterKey.rawData)
            default:
                Issue.record("Unexpected master key used in storage service operation.")
            }
            return .value(())
        })

        storageServiceManagerMock.addRestoreOrCreateManifestIfNecessaryMock({ auth, masterKeySource in
            #expect(auth.authedAccount == expectedAuthedAccount())
            switch masterKeySource {
            case .explicit(let explicitMasterKey):
                #expect(finalMasterKey.rawData == explicitMasterKey.rawData)
            default:
                Issue.record("Unexpected master key used in storage service operation.")
            }
            return .value(())
        })

        storageServiceManagerMock.addRotateManifestMock({ _, _ in return .value(()) })

        // Once we restore from storage service, we should attempt to reclaim our username.
        let mockUsernameLink: Usernames.UsernameLink = .mocked
        localUsernameManagerMock.startingUsernameState = .available(username: "boba.42", usernameLink: mockUsernameLink)
        usernameApiClientMock.confirmReservedUsernameMocks = [{ _, _, chatServiceAuth in
            self.testRun.addObservedStep(.confirmReservedUsername)
            #expect(chatServiceAuth == .explicit(
                aci: identityResponse.aci,
                deviceId: .primary,
                password: authPassword
            ))
            return .value(.success(usernameLinkHandle: mockUsernameLink.handle))
        }]

        // Once we do the storage service restore,
        // we will sync account attributes and then we are finished!
        let expectedAttributesRequest = RegistrationRequestFactory.updatePrimaryDeviceAccountAttributesRequest(
            Stubs.accountAttributes(finalMasterKey),
            auth: .implicit() // // doesn't matter for url matching
        )
        mockURLSession.addResponse(
            TSRequestOWSURLSessionMock.Response(
                matcher: { request in
                    if request.url == expectedAttributesRequest.url {
                        self.testRun.addObservedStep(.updateAccountAttribute)
                        return true
                    }
                    return false
                },
                statusCode: 200,
                bodyData: nil
            )
        )

        // We haven't set a phone number so it should ask for that.
        #expect(
            await coordinator.nextStep().awaitable() ==
                .phoneNumberEntry(stubs.phoneNumberEntryState(mode: mode))
        )

        // Give it a phone number, which should show the PIN entry step.
        // Now it should ask for the PIN to confirm the user knows it.
        #expect(
            await coordinator.submitE164(Stubs.e164).awaitable() ==
                .pinEntry(Stubs.pinEntryStateForRegRecoveryPath(mode: mode))
        )

        // Give it the pin code, which should make it try and register.
        #expect(await coordinator.submitPINCode(Stubs.pinCode).awaitable() == .done)

        var expectedSteps: [TestStep] = [
            .requestPushToken,
            .createPreKeys,
            .failedRequest,
            .finalizePreKeys,
            .requestPushToken,
            .createPreKeys,
            .createAccount,
            .finalizePreKeys,
            .rotateOneTimePreKeys,
            // .restoreStorageService, // If going from MasterKey -> AEP
            .backupMasterKey,
            // .restoreStorageService,
            .confirmReservedUsername,
            .rotateManifest,
            .updateAccountAttribute
        ]

        if testCase.newKey == .accountEntropyPool && testCase.oldKey != .accountEntropyPool {
            expectedSteps.insert(.restoreStorageService, at: 9)
        } else {
            expectedSteps.insert(.restoreStorageService, at: 10)
        }
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
    @MainActor @Test(arguments: Self.testCases())
    func testRegRecoveryPwPath_failedReglock2(testCase: TestCase) async {
        let coordinator = setupTest(testCase)
        let mode = testCase.mode

        // Set profile info so we skip those steps.
        setupDefaultAccountAttributes()

        // Set a PIN on disk.
        ows2FAManagerMock.pinCodeMock = { Stubs.pinCode }
        ows2FAManagerMock.isReglockEnabledMock = { true }

        // Make SVR give us back a reg recovery password.
        let masterKey = AccountEntropyPool().getMasterKey()
        db.write { accountKeyStore.setMasterKey(masterKey, tx: $0) }
        svr.hasMasterKey = true

        // NOTE: We expect to skip opening path steps because
        // if we have a SVR master key locally, this _must_ be
        // a previously registered device, and we can skip intros.

        // First we try and create an account with reg recovery
        // password; we will fail with reglock error.
        // First we get apns tokens, then prekeys, then register
        // then finalize prekeys (with failure) after.

        // Once we fail, we try again immediately with the reglock
        // token we fetch.
        // Same sequence as the first request.

        // When that fails, we try and create a session.
        // No prekey stuff this time, just apns token and session requests.

        pushRegistrationManagerMock.addRequestPushTokenMock({ .value(.success(Stubs.apnsRegistrationId))})
        pushRegistrationManagerMock.addRequestPushTokenMock({ .value(.success(Stubs.apnsRegistrationId))})
        pushRegistrationManagerMock.addRequestPushTokenMock({ .value(.success(Stubs.apnsRegistrationId))})
        pushRegistrationManagerMock.addRequestPushTokenMock({ .value(.success(Stubs.apnsRegistrationId))})

        preKeyManagerMock.addCreatePreKeysMock({ .value(Stubs.prekeyBundles()) })
        preKeyManagerMock.addCreatePreKeysMock({ .value(Stubs.prekeyBundles()) })

        preKeyManagerMock.addFinalizePreKeyMock({ _ in .value(()) })
        preKeyManagerMock.addFinalizePreKeyMock({ _ in .value(()) })

        // Fail the first request;
        let expectedRecoveryPwRequest = createAccountWithRecoveryPw(masterKey)
        mockURLSession.addResponse(TSRequestOWSURLSessionMock.Response(
            urlSuffix: expectedRecoveryPwRequest.url.absoluteString,
            statusCode: RegistrationServiceResponses.AccountCreationResponseCodes.regRecoveryPasswordRejected.rawValue,
            bodyJson: EncodableRegistrationLockFailureResponse(
                timeRemainingMs: 10,
                svr2AuthCredential: Stubs.svr2AuthCredential
            )
        ))

        // Once the first request fails, it should try an start a session.
        // We'll ask for a push challenge, though we don't need to resolve it in this test.
        pushRegistrationManagerMock.addReceivePreAuthChallengeTokenMock({ Guarantee<String>.pending().0 })

        // Resolve with a session.
        sessionManager.addBeginSessionResponseMock(.success(stubs.session()))

        // Then when it gets back the session, it should immediately ask for
        // a verification code to be sent.
        // Resolve with an updated session.

        sessionManager.addRequestCodeResponseMock(.success(stubs.session(nextVerificationAttempt: 0)))

        // Give back an valid session.
        sessionManager.addSubmitCodeResponseMock(.success(stubs.session(
            receivedDate: date,
            verified: true
        )))

        // Once the request fails, we should try again with the reglock
        // token, this time.
        let expectedRecoveryPwRequest2 = createAccountWithSession(masterKey)
        mockURLSession.addResponse(TSRequestOWSURLSessionMock.Response(
            urlSuffix: expectedRecoveryPwRequest2.url.absoluteString,
            statusCode: RegistrationServiceResponses.AccountCreationResponseCodes.reglockFailed.rawValue,
            bodyJson: EncodableRegistrationLockFailureResponse(
                timeRemainingMs: 10000,
                svr2AuthCredential: Stubs.svr2AuthCredential
            )
        ))

        #expect(svr.hasMasterKey)

        let acknowledgeAction: RegistrationReglockTimeoutAcknowledgeAction = switch testCase.mode {
        case .registering: .resetPhoneNumber
        case .changingNumber, .reRegistering: .none
        }

        // We haven't set a phone number so it should ask for that.
        #expect(
            await coordinator.nextStep().awaitable() ==
                .phoneNumberEntry(stubs.phoneNumberEntryState(mode: mode))
        )

        // Give it a phone number, which should show the PIN entry step.
        // Now it should ask for the PIN to confirm the user knows it.
        #expect(
            await coordinator.submitE164(Stubs.e164).awaitable() ==
                .pinEntry(Stubs.pinEntryStateForRegRecoveryPath(mode: mode))
        )

        // Give it the pin code, which should make it try and register.
        _ = await coordinator.submitPINCode(Stubs.pinCode).awaitable()

        #expect(await coordinator.submitVerificationCode(Stubs.pinCode).awaitable() ==
            .reglockTimeout(
                RegistrationReglockTimeoutState(
                    reglockExpirationDate: dateProvider().addingTimeInterval(TimeInterval(10)),
                    acknowledgeAction: acknowledgeAction
        )))

        // We want to have wiped our master key; we failed reglock, which means the key itself is wrong.
        #expect(svr.hasMasterKey)
    }

    // Test the path where a the local masterkey is no longer in sync with the one storedin SVR
    // This can happen a lot more often in an AEP enabled world, which means that during registration
    // we may need to go fetch the current key from SVR after failing the first registration attempt
    @MainActor @Test(arguments: Self.onlyReRegisteringTestCases())
    func testRegRecoveryPwPath_reglock_failedLocalCredentials(testCase: TestCase) async {
        let coordinator = setupTest(testCase)
        let mode = testCase.mode

        // Set profile info so we skip those steps.
        setupDefaultAccountAttributes()

        // Set a PIN on disk.
        ows2FAManagerMock.pinCodeMock = { Stubs.pinCode }
        ows2FAManagerMock.isReglockEnabledMock = { true }

        // Make SVR give us back a reg recovery password.
        let (masterKey, newMasterKey) = buildKeyDataMocks(testCase)
        let remoteMasterKey = MasterKey()
        // For non-AEP, we will replace the local key with the remote key.
        // For AEP, we'll rotate to a new AEP (or use the existing local AEP if it's present)
        let finalMasterKey = testCase.newKey == .masterKey ? remoteMasterKey : newMasterKey
        svr.hasMasterKey = true

        // Put some auth credentials in storage.
        let svr2CredentialCandidates: [SVR2AuthCredential] = [
            Stubs.svr2AuthCredential,
        ]
        svrAuthCredentialStore.svr2Dict = Dictionary(grouping: svr2CredentialCandidates, by: \.credential.username).mapValues { $0.first! }

        // Give it a phone number, which should cause it to check the auth credentials.
        // Match the main auth credential.
        let expectedSVR2CheckRequest = RegistrationRequestFactory.svr2AuthCredentialCheckRequest(
            e164: Stubs.e164,
            credentials: svr2CredentialCandidates
        )
        mockURLSession.addResponse(TSRequestOWSURLSessionMock.Response(
            urlSuffix: expectedSVR2CheckRequest.url.absoluteString,
            statusCode: 200,
            bodyJson: RegistrationServiceResponses.SVR2AuthCheckResponse(matches: [
                "\(Stubs.svr2AuthCredential.credential.username):\(Stubs.svr2AuthCredential.credential.password)": .match,
            ])
        ))

        // NOTE: We expect to skip opening path steps because
        // if we have a SVR master key locally, this _must_ be
        // a previously registered device, and we can skip intros.
        svr.restoreKeysMock = { pin, authMethod in
            #expect(pin == Stubs.pinCode)
            #expect(authMethod == .svrAuth(Stubs.svr2AuthCredential, backup: nil))
            self.svr.hasMasterKey = true
            return .value(.success(remoteMasterKey))
        }

        // First we try and create an account with reg recovery
        // password; we will fail with reglock error.
        // First we get apns tokens, then prekeys, then register
        // then finalize prekeys (with failure) after.

        // Once we fail, attempt to fetch the remote SVR credential and attempt RRP again
        // Same sequence as the first request.

        pushRegistrationManagerMock.addRequestPushTokenMock({ .value(.success(Stubs.apnsRegistrationId))})
        pushRegistrationManagerMock.addRequestPushTokenMock({ .value(.success(Stubs.apnsRegistrationId))})
        pushRegistrationManagerMock.addRequestPushTokenMock({ .value(.success(Stubs.apnsRegistrationId))})

        preKeyManagerMock.addCreatePreKeysMock({ .value(Stubs.prekeyBundles()) })
        preKeyManagerMock.addCreatePreKeysMock({ .value(Stubs.prekeyBundles()) })

        preKeyManagerMock.addFinalizePreKeyMock { didSucceed in
            #expect(didSucceed.negated)
            return .value(())
        }
        preKeyManagerMock.addFinalizePreKeyMock { didSucceed in
            #expect(didSucceed)
            return .value(())
        }

        // Fail the first request; the reglock is invalid.
        let expectedRecoveryPwRequest = createAccountWithRecoveryPw(masterKey)
        mockURLSession.addResponse(TSRequestOWSURLSessionMock.Response(
            urlSuffix: expectedRecoveryPwRequest.url.absoluteString,
            statusCode: RegistrationServiceResponses.AccountCreationResponseCodes.regRecoveryPasswordRejected.rawValue,
            bodyJson: EncodableRegistrationLockFailureResponse(
                timeRemainingMs: 10,
                svr2AuthCredential: Stubs.svr2AuthCredential
            )
        ))

        // Once the request fails, we should try again with the reglock
        // token, this time.
        let accountIdentityResponse = Stubs.accountIdentityResponse()
        var authPassword: String!
        let expectedRecoveryPwRequest2 = createAccountWithRecoveryPw(remoteMasterKey)
        mockURLSession.addResponse(TSRequestOWSURLSessionMock.Response(
            matcher: { request in
                authPassword = request.authPassword
                let requestAttributes = Self.attributesFromCreateAccountRequest(request)
                #expect((request.parameters["recoveryPassword"] as? String) == remoteMasterKey.regRecoveryPw)
                #expect(remoteMasterKey.reglockToken == requestAttributes.registrationLockToken)
                return request.url == expectedRecoveryPwRequest2.url
            },
            statusCode: 200,
            bodyJson: accountIdentityResponse
        ))

        func expectedAuthedAccount() -> AuthedAccount {
            return .explicit(
                aci: accountIdentityResponse.aci,
                pni: accountIdentityResponse.pni,
                e164: Stubs.e164,
                deviceId: .primary,
                authPassword: authPassword
            )
        }

        // When registered, we should create pre-keys.
        preKeyManagerMock.addRotateOneTimePreKeyMock({ auth in
            #expect(auth == expectedAuthedAccount().chatServiceAuth)
            return .value(())
        })

        // If we had reglock before registration, it should be re-enabled.
        let expectedReglockRequest = OWSRequestFactory.enableRegistrationLockV2Request(token: finalMasterKey.reglockToken)
        mockURLSession.addResponse(TSRequestOWSURLSessionMock.Response(
            matcher: { request in
                #expect(finalMasterKey.reglockToken == request.parameters["registrationLock"] as! String)
                return request.url == expectedReglockRequest.url
            },
            statusCode: 200,
            bodyData: nil
        ))

        // We haven't done a SVR backup; that should happen now.
        svr.backupMasterKeyMock = { pin, masterKey, authMethod in
            #expect(pin == Stubs.pinCode)
            // We don't have a SVR auth credential, it should use chat server creds.
            #expect(masterKey.rawData == finalMasterKey.rawData)
            #expect(authMethod == .svrAuth(
                Stubs.svr2AuthCredential,
                backup: .chatServerAuth(expectedAuthedAccount())
            ))
            self.svr.hasMasterKey = true
            return .value(masterKey)
        }

        // Once we sync push tokens, we should restore from storage service.
        storageServiceManagerMock.addRestoreOrCreateManifestIfNecessaryMock({ auth, masterKeySource in
            #expect(auth.authedAccount == expectedAuthedAccount())
            switch masterKeySource {
            case .explicit(let explicitMasterKey):
                #expect(remoteMasterKey.rawData == explicitMasterKey.rawData)
            default:
                Issue.record("Unexpected master key used in storage service operation.")
            }
            return .value(())
        })

        // Once we restore from storage service, we should attempt to reclaim
        // our username.
        let mockUsernameLink: Usernames.UsernameLink = .mocked
        localUsernameManagerMock.startingUsernameState = .available(username: "boba.42", usernameLink: mockUsernameLink)
        usernameApiClientMock.confirmReservedUsernameMocks = [{ _, _, chatServiceAuth in
            #expect(chatServiceAuth == .explicit(
                aci: accountIdentityResponse.aci,
                deviceId: .primary,
                password: authPassword
            ))
            return .value(.success(usernameLinkHandle: mockUsernameLink.handle))
        }]

        storageServiceManagerMock.addRotateManifestMock({ _, _ in return .value(()) })

        // Once we do the username reclamation,
        // we will sync account attributes and then we are finished!
        let expectedAttributesRequest = RegistrationRequestFactory.updatePrimaryDeviceAccountAttributesRequest(
            Stubs.accountAttributes(finalMasterKey),
            auth: .implicit() // doesn't matter for url matching
        )
        mockURLSession.addResponse(
            matcher: { request in
                return request.url == expectedAttributesRequest.url
            },
            statusCode: 200
        )

        // We haven't set a phone number so it should ask for that.
        #expect(
            await coordinator.nextStep().awaitable() ==
                .phoneNumberEntry(stubs.phoneNumberEntryState(mode: mode))
        )

        // Give it a phone number, which should show the PIN entry step.
        // Now it should ask for the PIN to confirm the user knows it.
        #expect(
            await coordinator.submitE164(Stubs.e164).awaitable() ==
                .pinEntry(Stubs.pinEntryStateForRegRecoveryPath(mode: mode))
        )

        #expect(svrAuthCredentialStore.svr2Dict[Stubs.svr2AuthCredential.credential.username] != nil)

        #expect(svr.hasMasterKey)

        // Give it the pin code, which should make it try and register.
        #expect(await coordinator.submitPINCode(Stubs.pinCode).awaitable() == .done)

        #expect(svr.hasMasterKey)
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
        let mode = testCase.mode

        // Set profile info so we skip those steps.
        setupDefaultAccountAttributes()

        // Set a PIN on disk.
        ows2FAManagerMock.pinCodeMock = { Stubs.pinCode }
        ows2FAManagerMock.isReglockEnabledMock = { true }

        // Make SVR give us back a reg recovery password.
        let (masterKey, _) = buildKeyDataMocks(testCase)
        let remoteMasterKey = MasterKey()
        // For non-AEP, we will replace the local key with the remote key.
        // For AEP, we'll rotate to a new AEP (or use the existing local AEP if it's present)
        svr.hasMasterKey = true

        // Put some auth credentials in storage.
        let svr2CredentialCandidates: [SVR2AuthCredential] = [
            Stubs.svr2AuthCredential,
        ]
        svrAuthCredentialStore.svr2Dict = Dictionary(grouping: svr2CredentialCandidates, by: \.credential.username).mapValues { $0.first! }

        // Give it a phone number, which should cause it to check the auth credentials.
        // Match the main auth credential.
        let expectedSVR2CheckRequest = RegistrationRequestFactory.svr2AuthCredentialCheckRequest(
            e164: Stubs.e164,
            credentials: svr2CredentialCandidates
        )
        mockURLSession.addResponse(TSRequestOWSURLSessionMock.Response(
            urlSuffix: expectedSVR2CheckRequest.url.absoluteString,
            statusCode: 200,
            bodyJson: RegistrationServiceResponses.SVR2AuthCheckResponse(matches: [
                "\(Stubs.svr2AuthCredential.credential.username):\(Stubs.svr2AuthCredential.credential.password)": .match,
            ])
        ))

        // NOTE: We expect to skip opening path steps because
        // if we have a SVR master key locally, this _must_ be
        // a previously registered device, and we can skip intros.

        svr.restoreKeysMock = { pin, authMethod in
            #expect(pin == Stubs.pinCode)
            #expect(authMethod == .svrAuth(Stubs.svr2AuthCredential, backup: nil))
            self.svr.hasMasterKey = true
            return .value(.success(remoteMasterKey))
        }

        // First we try and create an account with reg recovery
        // password; we will fail with reglock error.
        // First we get apns tokens, then prekeys, then register
        // then finalize prekeys (with failure) after.

        pushRegistrationManagerMock.addRequestPushTokenMock({ .value(.success(Stubs.apnsRegistrationId))})
        pushRegistrationManagerMock.addRequestPushTokenMock({ .value(.success(Stubs.apnsRegistrationId))})
        pushRegistrationManagerMock.addRequestPushTokenMock({ .value(.success(Stubs.apnsRegistrationId))})
        pushRegistrationManagerMock.addRequestPushTokenMock({ .value(.success(Stubs.apnsRegistrationId))})

        preKeyManagerMock.addCreatePreKeysMock({ .value(Stubs.prekeyBundles()) })
        preKeyManagerMock.addCreatePreKeysMock({ .value(Stubs.prekeyBundles()) })
        preKeyManagerMock.addCreatePreKeysMock({ .value(Stubs.prekeyBundles()) })

        preKeyManagerMock.addFinalizePreKeyMock({ _ in .value(()) })
        preKeyManagerMock.addFinalizePreKeyMock({ _ in .value(()) })
        preKeyManagerMock.addFinalizePreKeyMock({ _ in .value(()) })

        // Fail the first request; the local key is invalid.
        let expectedRecoveryPwRequest = createAccountWithRecoveryPw(masterKey)
        let failResponse = TSRequestOWSURLSessionMock.Response(
            urlSuffix: expectedRecoveryPwRequest.url.absoluteString,
            statusCode: RegistrationServiceResponses.AccountCreationResponseCodes.regRecoveryPasswordRejected.rawValue,
            bodyJson: EncodableRegistrationLockFailureResponse(
                timeRemainingMs: 10000,
                svr2AuthCredential: Stubs.svr2AuthCredential
            )
        )
        mockURLSession.addResponse(failResponse)
        mockURLSession.addResponse(failResponse)

        pushRegistrationManagerMock.addReceivePreAuthChallengeTokenMock({ Guarantee<String>.pending().0 })

        // Resolve with an updated session.
        sessionManager.addRequestCodeResponseMock(.success(stubs.session(nextVerificationAttempt: 0)))

        // Resolve with a session.
        sessionManager.addBeginSessionResponseMock(.success(stubs.session()))

        // Once the request fails, we should try again with the reglock
        // token, this time.
        // The third attempt should fall back to session using the remote key(?)
        let expectedRecoveryPwRequest3 = createAccountWithSession(remoteMasterKey)
        mockURLSession.addResponse(TSRequestOWSURLSessionMock.Response(
            urlSuffix: expectedRecoveryPwRequest3.url.absoluteString,
            statusCode: RegistrationServiceResponses.AccountCreationResponseCodes.reglockFailed.rawValue,
            bodyJson: EncodableRegistrationLockFailureResponse(
                timeRemainingMs: 10000,
                svr2AuthCredential: Stubs.svr2AuthCredential
            )
        ))

        // Give back a verified session.
        sessionManager.addSubmitCodeResponseMock(.success(stubs.session(verified: true)))

        let acknowledgeAction: RegistrationReglockTimeoutAcknowledgeAction = switch testCase.mode {
        case .registering: .resetPhoneNumber
        case .changingNumber, .reRegistering: .none
        }

        // We haven't set a phone number so it should ask for that.
        #expect(
            await coordinator.nextStep().awaitable() ==
                .phoneNumberEntry(stubs.phoneNumberEntryState(mode: mode))
        )

        // Give it a phone number, which should show the PIN entry step.
        // Now it should ask for the PIN to confirm the user knows it.
        #expect(
            await coordinator.submitE164(Stubs.e164).awaitable() ==
                .pinEntry(Stubs.pinEntryStateForRegRecoveryPath(mode: mode))
        )

        // Give it the pin code, which should make it try and register.
        #expect(
            await coordinator.submitPINCode(Stubs.pinCode).awaitable() ==
                .verificationCodeEntry(
                    stubs.verificationCodeEntryState(
                        mode: mode,
                        // TODO: [Refactor]: Is 'noExitAllowed' the correct value to expect here?
                        exitConfigOverride: .noExitAllowed
                    ))
        )

        #expect(svr.hasMasterKey)

        // Submit verification code
        #expect(await coordinator.submitVerificationCode(Stubs.verificationCode).awaitable() ==
            .reglockTimeout(
                RegistrationReglockTimeoutState(
                    reglockExpirationDate: dateProvider().addingTimeInterval(TimeInterval(10)),
                    acknowledgeAction: acknowledgeAction
        )))

        // We want to have wiped our master key; we failed reglock, which means the key itself is wrong.
        #expect(svr.hasMasterKey)
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
        await goThroughOpeningHappyPath(
            coordinator: coordinator,
            mode: mode,
            expectedNextStep: .phoneNumberEntry(stubs.phoneNumberEntryState(mode: mode))
        )

        let (initialMasterKey, finalMasterKey) = buildKeyDataMocks(testCase)

        // Resolve the key restoration from SVR and have it start returning the key.
        svr.restoreKeysMock = { pin, authMethod in
            self.testRun.addObservedStep(.restoreKeys)
            #expect(pin == Stubs.pinCode)
            #expect(authMethod == .svrAuth(Stubs.svr2AuthCredential, backup: nil))
            self.svr.hasMasterKey = true
            return .value(.success(initialMasterKey))
        }

        // Before registering, it should ask for push tokens to give the registration.
        pushRegistrationManagerMock.addRequestPushTokenMock({ .value(.success(Stubs.apnsRegistrationId)) })

        // Every time we register we also ask for prekeys.
        preKeyManagerMock.addCreatePreKeysMock({ .value(Stubs.prekeyBundles()) })

        // And we finalize them after.
        preKeyManagerMock.addFinalizePreKeyMock { didSucceed in
            #expect(didSucceed)
            return .value(())
        }

        // Now still at it should make a reg recovery pw request
        let accountIdentityResponse = Stubs.accountIdentityResponse()
        var authPassword: String!
        let expectedRegRecoveryPwRequest = createAccountWithRecoveryPw(initialMasterKey)
        mockURLSession.addResponse(
            TSRequestOWSURLSessionMock.Response(
                matcher: { request in
                    self.testRun.addObservedStep(.createAccount)
                    authPassword = request.authPassword
                    return request.url == expectedRegRecoveryPwRequest.url
                },
                statusCode: 200,
                bodyJson: accountIdentityResponse
            )
        )

        func expectedAuthedAccount() -> AuthedAccount {
            return .explicit(
                aci: accountIdentityResponse.aci,
                pni: accountIdentityResponse.pni,
                e164: Stubs.e164,
                deviceId: .primary,
                authPassword: authPassword
            )
        }

        // When registered, it should try and create pre-keys.
        preKeyManagerMock.addRotateOneTimePreKeyMock({ auth in
            #expect(auth == expectedAuthedAccount().chatServiceAuth)
            return .value(())
        })

        // Once we create pre-keys, we should back up to svr.
        svr.backupMasterKeyMock = { pin, masterKey, authMethod in
            self.testRun.addObservedStep(.backupMasterKey)
            #expect(pin == Stubs.pinCode)
            #expect(masterKey.rawData == finalMasterKey.rawData)
            #expect(authMethod == .svrAuth(
                Stubs.svr2AuthCredential,
                backup: .chatServerAuth(expectedAuthedAccount())
            ))
            return .value(masterKey)
        }

        // Once we back up to svr, we should restore from storage service.
        storageServiceManagerMock.addRestoreOrCreateManifestIfNecessaryMock({ auth, masterKeySource in
            #expect(auth.authedAccount == expectedAuthedAccount())
            switch masterKeySource {
            case .explicit(let explicitMasterKey):
                #expect(initialMasterKey.rawData == explicitMasterKey.rawData)
            default:
                Issue.record("Unexpected master key used in storage service operation.")
            }
            return .value(())
        })

        storageServiceManagerMock.addRestoreOrCreateManifestIfNecessaryMock({ auth, masterKeySource in
            switch masterKeySource {
            case .explicit(let explicitMasterKey):
                #expect(finalMasterKey.rawData == explicitMasterKey.rawData)
            default:
                Issue.record("Unexpected master key used in storage service operation.")
            }
            return .value(())
        })

        storageServiceManagerMock.addRotateManifestMock({ _, _ in return .value(()) })

        // Once we restore from storage service, we should attempt to reclaim our username.
        let mockUsernameLink: Usernames.UsernameLink = .mocked
        localUsernameManagerMock.startingUsernameState = .available(username: "boba.42", usernameLink: mockUsernameLink)
        usernameApiClientMock.confirmReservedUsernameMocks = [{ _, _, chatServiceAuth in
            self.testRun.addObservedStep(.confirmReservedUsername)
            #expect(chatServiceAuth == .explicit(
                aci: accountIdentityResponse.aci,
                deviceId: .primary,
                password: authPassword
            ))
            return .value(.success(usernameLinkHandle: mockUsernameLink.handle))
        }]

        // Once we do the storage service restore, we will sync account attributes and then we are finished!
        let expectedAttributesRequest = RegistrationRequestFactory.updatePrimaryDeviceAccountAttributesRequest(
            Stubs.accountAttributes(finalMasterKey),
            auth: .implicit() // doesn't matter for url matching
        )
        mockURLSession.addResponse(
            matcher: { request in
                self.testRun.addObservedStep(.updateAccountAttribute)
                return request.url == expectedAttributesRequest.url
            },
            statusCode: 200
        )

        // At this point, we should be asking for PIN entry so we can use the credential
        // to recover the SVR master key.
        #expect(
            await coordinator.submitE164(Stubs.e164).awaitable() ==
                .pinEntry(Stubs.pinEntryStateForSVRAuthCredentialPath(mode: mode))
            )

        // We should have wiped the invalid and unknown credentials.
        let remainingCredentials = svrAuthCredentialStore.svr2Dict
        #expect(remainingCredentials[Stubs.svr2AuthCredential.credential.username] != nil)
        #expect(remainingCredentials["aaaa"] != nil)
        #expect(remainingCredentials["zzzz"] == nil)
        #expect(remainingCredentials["0000"] == nil)
        // SVR should be untouched.
        #expect(svrAuthCredentialStore.svr2Dict[Stubs.svr2AuthCredential.credential.username] != nil)

        // Enter the PIN, which should try and recover from SVR.
        // Once we do that, it should follow the Reg Recovery Password Path.
        #expect(await coordinator.submitPINCode(Stubs.pinCode).awaitable() == .done)

        var expectedSteps: [TestStep] = [
            .restoreKeys,
            .requestPushToken,
            .createPreKeys,
            .createAccount,
            .finalizePreKeys,
            .rotateOneTimePreKeys,
            //            "restoreStorageService",
            .backupMasterKey,
            //            "restoreStorageService",
            .confirmReservedUsername,
            .rotateManifest,
            .updateAccountAttribute
        ]

        if testCase.newKey == .accountEntropyPool {
            expectedSteps.insert(.restoreStorageService, at: 6)
        } else {
            expectedSteps.insert(.restoreStorageService, at: 7)
        }

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
        await goThroughOpeningHappyPath(
            coordinator: coordinator,
            mode: mode,
            expectedNextStep: .phoneNumberEntry(stubs.phoneNumberEntryState(mode: mode))
        )

        // Once the first request fails, it should try an start a session.
        // We'll ask for a push challenge, though we don't need to resolve it in this test.
        pushRegistrationManagerMock.addReceivePreAuthChallengeTokenMock({
            return Guarantee<String>.pending().0
        })

        // Resolve with a session.
        sessionManager.addBeginSessionResponseMock(.success(stubs.session()))

        // Then when it gets back the session, it should immediately ask for
        // a verification code to be sent.
        // Resolve with an updated session.
        sessionManager.addRequestCodeResponseMock(.success(stubs.session(nextVerificationAttempt: 0)))

        pushRegistrationManagerMock.addRequestPushTokenMock({ .value(.success(Stubs.apnsRegistrationId)) })

        // Give it a phone number, which should cause it to check the auth credentials.
        // Now we should expect to be at verification code entry since we already set the phone number.
        #expect(
            await coordinator.submitE164(Stubs.e164).awaitable() ==
            .verificationCodeEntry(stubs.verificationCodeEntryState(mode: mode))
       )

        // We should have wipted the invalid and unknown credentials.
        let remainingCredentials = svrAuthCredentialStore.svr2Dict
        #expect(remainingCredentials[Stubs.svr2AuthCredential.credential.username] != nil)
        #expect(remainingCredentials["aaaa"] != nil)
        #expect(remainingCredentials["zzzz"] == nil)
        #expect(remainingCredentials["0000"] == nil)
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
        let credentialCandidates: [SVR2AuthCredential] = [ Stubs.svr2AuthCredential ]
        svrAuthCredentialStore.svr2Dict = Dictionary(grouping: credentialCandidates, by: \.credential.username).mapValues { $0.first! }

        // Get past the opening.
        await goThroughOpeningHappyPath(
            coordinator: coordinator,
            mode: mode,
            expectedNextStep: .phoneNumberEntry(stubs.phoneNumberEntryState(mode: mode))
        )

        // Don't give back any matches, which means we will want to create a session as a fallback.
        var expectedSVRCheckRequest = RegistrationRequestFactory.svr2AuthCredentialCheckRequest(
            e164: originalE164,
            credentials: credentialCandidates
        )
        mockURLSession.addResponse(
            TSRequestOWSURLSessionMock.Response(
                urlSuffix: expectedSVRCheckRequest.url.absoluteString,
                statusCode: 200,
                bodyJson: RegistrationServiceResponses.SVR2AuthCheckResponse(matches: [
                    "\(Stubs.svr2AuthCredential.credential.username):\(Stubs.svr2AuthCredential.credential.password)": .notMatch
                ])
            )
        )

        // Once the first request fails, it should try an start a session.
        // We'll ask for a push challenge, though we don't need to resolve it in this test.
        pushRegistrationManagerMock.addReceivePreAuthChallengeTokenMock({
            return Guarantee<String>.pending().0
        })

        // Resolve with a session.
        sessionManager.addBeginSessionResponseMock(.success(stubs.session(e164: originalE164)))

        // Then when it gets back the session, it should immediately ask for a verification code to be sent.
        // Resolve with an updated session.
        sessionManager.addRequestCodeResponseMock(.success(stubs.session(nextVerificationAttempt: 0)))

        pushRegistrationManagerMock.addRequestPushTokenMock({ .value(.success(Stubs.apnsRegistrationId)) })

         // Give a match, so it registers via SVR auth credential.
        expectedSVRCheckRequest = RegistrationRequestFactory.svr2AuthCredentialCheckRequest(
            e164: changedE164,
            credentials: credentialCandidates
        )
        mockURLSession.addResponse(
            TSRequestOWSURLSessionMock.Response(
                urlSuffix: expectedSVRCheckRequest.url.absoluteString,
                statusCode: 200,
                bodyJson: RegistrationServiceResponses.SVR2AuthCheckResponse(matches: [
                    "\(Stubs.svr2AuthCredential.credential.username):\(Stubs.svr2AuthCredential.credential.password)": .match
                ])
            )
        )

        // Give it a phone number, which should cause it to check the auth credentials.
        // Now we should expect to be at verification code entry since we already set the phone number.
        #expect(
            await coordinator.submitE164(originalE164).awaitable() ==
                .verificationCodeEntry(stubs.verificationCodeEntryState(mode: mode))
        )

        // We should have wiped the invalid and unknown credentials.
        #expect(svrAuthCredentialStore.svr2Dict[Stubs.svr2AuthCredential.credential.username] != nil)

        // Now change the phone number; this should take us back to phone number entry.
        #expect(
            await coordinator.requestChangeE164().awaitable() ==
                .phoneNumberEntry(stubs.phoneNumberEntryState(mode: mode))
        )

        // Now it should ask for PIN entry; we are on the SVR auth credential path.
        #expect(
            await coordinator.submitE164(changedE164).awaitable() ==
                .pinEntry(Stubs.pinEntryStateForSVRAuthCredentialPath(mode: mode))
        )
    }

    // MARK: - Session Path

    @MainActor @Test(arguments: Self.testCases())
    func testSessionPath_happyPath(testCase: TestCase) async {
        let coordinator = setupTest(testCase)
        let mode = testCase.mode
        var authPassword: String!

        let accountEntropyPool = AccountEntropyPool()
        let newMasterKey = accountEntropyPool.getMasterKey()
        if testCase.newKey == .accountEntropyPool {
            missingKeyGenerator.accountEntropyPool = { accountEntropyPool }
        } else {
            missingKeyGenerator.masterKey = { newMasterKey }
        }
        await createSessionAndRequestFirstCode(coordinator: coordinator, mode: mode)

        // Give back a verified session.
        sessionManager.addSubmitCodeResponseMock(.success(stubs.session(verified: true)))

        let accountIdentityResponse = Stubs.accountIdentityResponse()

        // That means it should try and register with the verified session;
        // Before registering, it should ask for push tokens to give the registration.
        pushRegistrationManagerMock.addRequestPushTokenMock({ .value(.success(Stubs.apnsRegistrationId)) })

        // It should also fetch the prekeys for account creation
        preKeyManagerMock.addCreatePreKeysMock({ .value(Stubs.prekeyBundles()) })

        let expectedRequest = createAccountWithSession(newMasterKey)
        mockURLSession.addResponse(
            TSRequestOWSURLSessionMock.Response(
                matcher: { request in
                    authPassword = request.authPassword
                    return request.url == expectedRequest.url
                },
                statusCode: 200,
                bodyJson: accountIdentityResponse
            )
        )

        func expectedAuthedAccount() -> AuthedAccount {
            return .explicit(
                aci: accountIdentityResponse.aci,
                pni: accountIdentityResponse.pni,
                e164: Stubs.e164,
                deviceId: .primary,
                authPassword: authPassword
            )
        }

        // Once we are registered, we should finalize prekeys.
        preKeyManagerMock.addFinalizePreKeyMock { didSucceed in
            #expect(didSucceed)
            return .value(())
        }

        // Then we should try and create one time pre-keys
        // with the credentials we got in the identity response.
        preKeyManagerMock.addRotateOneTimePreKeyMock({ auth in
            #expect(auth == expectedAuthedAccount().chatServiceAuth)
            return .value(())
        })

        // Finish the validation.
        svr.backupMasterKeyMock = { pin, masterKey, authMethod in
            #expect(pin == Stubs.pinCode)
            #expect(masterKey.rawData == newMasterKey.rawData)
            #expect(authMethod == .chatServerAuth(expectedAuthedAccount()))
            return .value(masterKey)
        }

        // Once we sync push tokens, we should restore from storage service.
        storageServiceManagerMock.addRestoreOrCreateManifestIfNecessaryMock({ auth, masterKeySource in
            #expect(auth.authedAccount == expectedAuthedAccount())
            switch masterKeySource {
            case .explicit(let explicitMasterKey):
                #expect(newMasterKey.rawData == explicitMasterKey.rawData)
            default:
                Issue.record("Unexpected master key used in storage service operation.")
            }
            return .value(())
        })

        // Once we restore from storage service, we should attempt to reclaim
        // our username. For this test, let's fail. This should have
        // no different impact on the rest of registration.
        let mockUsernameLink: Usernames.UsernameLink = .mocked
        localUsernameManagerMock.startingUsernameState = .available(username: "boba.42", usernameLink: mockUsernameLink)
        usernameApiClientMock.confirmReservedUsernameMocks = [{ _, _, chatServiceAuth in
            #expect(chatServiceAuth == .explicit(
                aci: accountIdentityResponse.aci,
                deviceId: .primary,
                password: authPassword
            ))
            return Promise(error: OWSGenericError("Something went wrong :("))
        }]

        // And once we do the storage service restore,
        // we will sync account attributes and then we are finished!
        let expectedAttributesRequest = RegistrationRequestFactory.updatePrimaryDeviceAccountAttributesRequest(
            Stubs.accountAttributes(newMasterKey),
            auth: .implicit() // doesn't matter for url matching
        )
        mockURLSession.addResponse(
            matcher: { $0.url == expectedAttributesRequest.url },
            statusCode: 200
        )

        storageServiceManagerMock.addRotateManifestMock({ _, _ in return .value(()) })

        // Submit a code.
        // Now we should ask to create a PIN.
        // No exit allowed since we've already started trying to create the account.
        #expect(
            await coordinator.submitVerificationCode(Stubs.pinCode).awaitable() ==
                .pinEntry(Stubs.pinEntryStateForPostRegCreate(mode: mode, exitConfigOverride: .noExitAllowed))
        )

        // Confirm the pin first.
        // No exit allowed since we've already started trying to create the account.
        #expect(
            await coordinator.setPINCodeForConfirmation(.stub()).awaitable() ==
                .pinEntry(Stubs.pinEntryStateForPostRegConfirm(mode: mode, exitConfigOverride: .noExitAllowed))
        )

        // When we submit the pin, it should backup with SVR.
        #expect(await coordinator.submitPINCode(Stubs.pinCode).awaitable() == .done)

        // Since we set profile info, we should have scheduled a reupload.
        #expect(profileManagerMock.didScheduleReuploadLocalProfile)
    }

    @MainActor @Test(arguments: Self.testCases())
    func testSessionPath_invalidE164(testCase: TestCase) async {
        let coordinator = setupTest(testCase)
        let mode = testCase.mode
        let badE164 = E164("+15555555555")!

        switch mode {
        case .registering, .changingNumber:
            break
        case .reRegistering:
            // no changing the number when reregistering
            return
        }

        await setUpSessionPath(coordinator: coordinator, mode: mode)

        // Reject for invalid argument (the e164).
        sessionManager.addBeginSessionResponseMock(.invalidArgument)

        // Give it a phone number, which should cause it to start a session.
        // It should put us on the phone number entry screen again
        // with an error.
        #expect(
            await coordinator.submitE164(badE164).awaitable() ==
                .phoneNumberEntry(
                    stubs.phoneNumberEntryState(
                        mode: mode,
                        previouslyEnteredE164: badE164,
                        withValidationErrorFor: .invalidArgument
                    )
                )
        )
    }

    @MainActor @Test(arguments: Self.testCases())
    func testSessionPath_rateLimitSessionCreation(testCase: TestCase) async {
        let coordinator = setupTest(testCase)
        let mode = testCase.mode

        await setUpSessionPath(coordinator: coordinator, mode: mode)

        let retryTimeInterval: TimeInterval = 5

        // Reject with a rate limit.
        sessionManager.addBeginSessionResponseMock(.retryAfter(retryTimeInterval))

        // Give it a phone number, which should cause it to start a session.
        // It should put us on the phone number entry screen again
        // with an error.
        #expect(
            await coordinator.submitE164(Stubs.e164).awaitable() ==
                .phoneNumberEntry(
                    stubs.phoneNumberEntryState(
                        mode: mode,
                        previouslyEnteredE164: Stubs.e164,
                        withValidationErrorFor: .retryAfter(retryTimeInterval)
                    )
                )
        )
    }

    @MainActor @Test(arguments: Self.testCases())
    func testSessionPath_cantSendFirstSMSCode(testCase: TestCase) async {
        let coordinator = setupTest(testCase)
        let mode = testCase.mode

        await setUpSessionPath(coordinator: coordinator, mode: mode)

        // Give back a session, but with SMS code rate limiting already.
        sessionManager.addBeginSessionResponseMock(.success(stubs.session(
            nextSMS: 10
        )))

        // Give it a phone number, which should cause it to start a session.
        // It should put us on the verification code entry screen with an error.
        #expect(
            await coordinator.submitE164(Stubs.e164).awaitable() ==
                .verificationCodeEntry(stubs.verificationCodeEntryState(
                    mode: mode,
                    nextSMS: 10,
                    nextVerificationAttempt: nil,
                    validationError: .smsResendTimeout
                ))
        )
    }

    @MainActor @Test(arguments: Self.testCases())
    func testSessionPath_landline(testCase: TestCase) async {
        let coordinator = setupTest(testCase)
        let mode = testCase.mode

        await setUpSessionPath(coordinator: coordinator, mode: mode)

        // Give back a session that's ready to go.
        sessionManager.addBeginSessionResponseMock(.success(stubs.session(
            nextCall: nil, /* initially calling unavailable */
        )))

        // Once we get that session, we should try and send a code.
        // Resolve with a transport error
        // and no next verification attempt on the session,
        // so it counts as transport failure with no code sent.
        sessionManager.addRequestCodeResponseMock(.transportError(stubs.session(
            nextSMS: nil /* now sms unavailable but calling is */
        )))

        // If we resend via voice, that should put us in a happy path. Resolve with a success.
        sessionManager.didRequestCode = false
        sessionManager.addRequestCodeResponseMock(.success(stubs.session(nextVerificationAttempt: 0)))

        // Give it a phone number, which should cause it to start a session.
        // We should get back the code entry step, with a validation error for the sms transport.
        #expect(
            await coordinator.submitE164(Stubs.e164).awaitable() ==
                .verificationCodeEntry(stubs.verificationCodeEntryState(
                    mode: mode,
                    nextSMS: nil,
                    nextVerificationAttempt: nil,
                    validationError: .failedInitialTransport(failedTransport: .sms)
                ))
        )

        // We should get back the code entry step.
        #expect(
            await coordinator.requestVoiceCode().awaitable() ==
                .verificationCodeEntry(stubs.verificationCodeEntryState(mode: mode)))
        #expect(sessionManager.didRequestCode)
    }

    @MainActor @Test(arguments: Self.testCases())
    func testSessionPath_landline_submitCodeWithNoneSentYet(testCase: TestCase) async {
        let coordinator = setupTest(testCase)
        let mode = testCase.mode

        await setUpSessionPath(coordinator: coordinator, mode: mode)

        // Give back a session that's ready to go.
        sessionManager.addBeginSessionResponseMock(.success(stubs.session()))

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
        #expect(await coordinator.submitE164(Stubs.e164).awaitable() ==
            .verificationCodeEntry(stubs.verificationCodeEntryState(
                mode: mode,
                nextVerificationAttempt: nil,
                validationError: .failedInitialTransport(failedTransport: .sms)
            ))
        )

        // The server says no code is available to submit. We know
        // we never sent a code, so show a unique error for that
        // but keep the user on the code entry screen so they can
        // retry sending a code with a transport method of their choice.

        #expect(
            await coordinator.submitVerificationCode(Stubs.verificationCode).awaitable() ==
                .showErrorSheet(.submittingVerificationCodeBeforeAnyCodeSent)
       )

        #expect(
            await coordinator.nextStep().awaitable() ==
                .verificationCodeEntry(stubs.verificationCodeEntryState(
                    mode: mode,
                    nextVerificationAttempt: nil,
                    validationError: .failedInitialTransport(failedTransport: .sms)
                ))
        )
    }

    @MainActor @Test(arguments: Self.testCases())
    func testSessionPath_rateLimitFirstSMSCode(testCase: TestCase) async {
        let coordinator = setupTest(testCase)
        let mode = testCase.mode

        await setUpSessionPath(coordinator: coordinator, mode: mode)

        // We'll ask for a push challenge, though we won't resolve it in this test.
        pushRegistrationManagerMock.addReceivePreAuthChallengeTokenMock({
            return Guarantee<String>.pending().0
        })

        // Give back a session that's ready to go.
        sessionManager.addBeginSessionResponseMock(.success(stubs.session(
            receivedDate: self.date
        )))

        // Once we get that session, we should try and send a code.

        // Reject with a timeout.
        sessionManager.addRequestCodeResponseMock(.retryAfterTimeout(stubs.session(
            receivedDate: self.date,
            nextSMS: 10
        )))

        // Give it a phone number, which should cause it to start a session.
        // It should put us on the phone number entry screen again
        // with an error.
        let step = await coordinator.submitE164(Stubs.e164).awaitable()
        #expect(
            step ==
                .phoneNumberEntry(
                    stubs.phoneNumberEntryState(
                        mode: mode,
                        previouslyEnteredE164: Stubs.e164,
                        withValidationErrorFor: .retryAfter(10)
                    )
                )
        )
    }

    @MainActor @Test(arguments: Self.testCases())
    func testSessionPath_changeE164(testCase: TestCase) async {
        let coordinator = setupTest(testCase)
        let mode = testCase.mode

        await setUpSessionPath(coordinator: coordinator, mode: mode)

        let originalE164 = E164("+17875550100")!
        let changedE164 = E164("+17875550101")!

        // We'll ask for a push challenge, though we won't resolve it in this test.
        pushRegistrationManagerMock.addReceivePreAuthChallengeTokenMock({
            return Guarantee<String>.pending().0
        })

        // Give back a session that's ready to go.
        sessionManager.addBeginSessionResponseMock(.success(stubs.session(
            e164: originalE164
        )))

        // Once we get that session, we should try and send a code.
        // Give back a session with a sent code.
        sessionManager.addRequestCodeResponseMock(.success(stubs.session(
            e164: originalE164,
            nextVerificationAttempt: 0,
        )))

        // These mocks are removed after each use, so set up another
        pushRegistrationManagerMock.addRequestPushTokenMock({ .value(.success(Stubs.apnsRegistrationId)) })

        // We'll ask for a push challenge, though we won't resolve it in this test.
        pushRegistrationManagerMock.addReceivePreAuthChallengeTokenMock({ Guarantee<String>.pending().0 })

        // Give back a session that's ready to go.
        // TODO: allow mocking multiple responses
        sessionManager.addBeginSessionResponseMock(.success(stubs.session(
            e164: changedE164
        )))

        // Once we get that session, we should try and send a code.
        // Give back a session with a sent code.
        sessionManager.addRequestCodeResponseMock(.success(stubs.session(
            e164: changedE164,
            nextVerificationAttempt: 0
        )))

        // Give it a phone number, which should cause it to start a session.
        // We should be on the verification code entry screen.
        #expect(
            await coordinator.submitE164(originalE164).awaitable() ==
                .verificationCodeEntry(
                    stubs.verificationCodeEntryState(mode: mode, e164: originalE164)
                )
        )

        // Ask to change the number; this should put us back on phone number entry.
        #expect(
            await coordinator.requestChangeE164().awaitable() ==
                .phoneNumberEntry(stubs.phoneNumberEntryState(mode: mode))
        )

        // Give it the new phone number, which should cause it to start a session.
        // We should be on the verification code entry screen.
        // TODO: Missing a 'requestPushToken'?
        #expect(
            await coordinator.submitE164(changedE164).awaitable() ==
                .verificationCodeEntry(
                    stubs.verificationCodeEntryState(mode: mode, e164: changedE164)
                )
        )
    }

    @MainActor @Test(arguments: Self.testCases())
    func testSessionPath_captchaChallenge(testCase: TestCase) async {
        let coordinator = setupTest(testCase)
        let mode = testCase.mode

        await setUpSessionPath(coordinator: coordinator, mode: mode)

        // Give back a session with a captcha challenge.
        sessionManager.addBeginSessionResponseMock(.success(stubs.session(
            allowedToRequestCode: false,
            requestedInformation: [.captcha],
        )))

        // Give back a session without the challenge.
        sessionManager.addFulfillChallengeResponseMock(.success(stubs.session()))

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
        sessionManager.addFulfillChallengeResponseMock(.success(stubs.session(
            nextVerificationAttempt: 0,
        )))

        // Give it a phone number, which should cause it to start a session.
        // Once we get that session, we should get a captcha step back.
        #expect(await coordinator.submitE164(Stubs.e164).awaitable() == .captchaChallenge)

        // We should get back the code entry step. Submit a captcha challenge.
        #expect(
            await coordinator.submitCaptcha(Stubs.captchaToken).awaitable() ==
                .verificationCodeEntry(stubs.verificationCodeEntryState(mode: mode))
        )

        // Now try and resend a code, which should hit us with the captcha challenge immediately.
        #expect(await coordinator.requestSMSCode().awaitable() == .captchaChallenge)

        // This means when we fulfill the challenge, it should
        // immediately try and send the code that couldn't be sent before because
        // of the challenge.
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
        #expect(
            await coordinator.submitCaptcha(Stubs.captchaToken).awaitable() ==
                .verificationCodeEntry(stubs.verificationCodeEntryState(mode: mode))
        )
    }

    @MainActor @Test(arguments: Self.testCases())
    func testSessionPath_pushChallenge(testCase: TestCase) async {
        let coordinator = setupTest(testCase)
        let mode = testCase.mode

        await setUpSessionPath(coordinator: coordinator, mode: mode)

        pushRegistrationManagerMock.addRequestPushTokenMock({ .value(.success(Stubs.apnsRegistrationId)) })

        // Prepare to provide the challenge token.
        let (challengeTokenPromise, challengeTokenFuture) = Guarantee<String>.pending()
        pushRegistrationManagerMock.addReceivePreAuthChallengeTokenMock({
            return challengeTokenPromise
        })

        // Give back a session with a push challenge.
        sessionManager.addBeginSessionResponseMock(.success(stubs.session(
            allowedToRequestCode: false,
            requestedInformation: [.pushChallenge],
        )))

        sessionManager.addFulfillChallengeResponseMock(.success(stubs.session(
            nextVerificationAttempt: 0,
        )))

        sessionManager.addRequestCodeResponseMock(.success(stubs.session(
            nextVerificationAttempt: 0,
            allowedToRequestCode: false,
            requestedInformation: [.pushChallenge],
        )))

        // Give the push challenge token. Also prepare to handle its usage, and the
        // resulting request for another SMS code.

        Task {
            // TODO: Need coordnator to be able to run async/disconnected whilw
            // setting up and fulfilling the challenge
            // Not sure a Task is the best way to get this, but works for now while we
            // have promises doing timeouts internal to RegCoordinator
            challengeTokenFuture.resolve("a pre-auth challenge token")
        }

        // Give it a phone number, which should cause it to start a session.
        _ = await coordinator.submitE164(Stubs.e164).awaitable()

        // We should still be waiting.
        #expect(
            await coordinator.nextStep().awaitable() ==
                .verificationCodeEntry(stubs.verificationCodeEntryState(mode: mode))
        )
        #expect(
            sessionManager.latestChallengeFulfillment ==
                .pushChallenge("a pre-auth challenge token")
        )
    }

    @MainActor @Test(arguments: Self.testCases())
    func testSessionPath_pushChallengeTimeoutAfterResolutionThatTakesTooLong(testCase: TestCase) async {
        let coordinator = setupTest(testCase)
        let mode = testCase.mode

        // Set profile info so we skip those steps.
        setupDefaultAccountAttributes()

        // Get past the opening.
        await goThroughOpeningHappyPath(
            coordinator: coordinator,
            mode: mode,
            expectedNextStep: .phoneNumberEntry(stubs.phoneNumberEntryState(mode: mode))
        )

        pushRegistrationManagerMock.addRequestPushTokenMock({ .value(.success(Stubs.apnsRegistrationId)) })

        // Prepare to provide the challenge token.
        let (challengeTokenPromise, _) = Guarantee<String>.pending()
        var receivePreAuthChallengeTokenCount = 0

        pushRegistrationManagerMock.addReceivePreAuthChallengeTokenMock {
            receivePreAuthChallengeTokenCount += 1
            return challengeTokenPromise
        }
        pushRegistrationManagerMock.addReceivePreAuthChallengeTokenMock {
            receivePreAuthChallengeTokenCount += 1
            return challengeTokenPromise
        }
        pushRegistrationManagerMock.addReceivePreAuthChallengeTokenMock {
            receivePreAuthChallengeTokenCount += 1
            return challengeTokenPromise
        }

        // Give back a session with a push challenge.
        sessionManager.addBeginSessionResponseMock(.success(stubs.session(
            allowedToRequestCode: false,
            requestedInformation: [.pushChallenge],
        )))

        // Take too long to resolve with the challenge token.
        timeoutProviderMock.pushTokenMinWaitTime = 0.5
        timeoutProviderMock.pushTokenTimeout = 2

        // Give it a phone number, which should cause it to start a session.
        let nextStep = await coordinator.submitE164(Stubs.e164).awaitable()
        #expect(nextStep == .showErrorSheet(.sessionInvalidated))

        // One time to set up, one time for the min wait time, one time
        // for the full timeout.
        #expect(receivePreAuthChallengeTokenCount == 3)
    }

    @MainActor @Test(arguments: Self.testCases())
    func testSessionPath_pushChallengeTimeoutAfterNoResolution(testCase: TestCase) async {
        let coordinator = setupTest(testCase)
        let mode = testCase.mode

        // Set profile info so we skip those steps.
        setupDefaultAccountAttributes()

        // Get past the opening.
        await goThroughOpeningHappyPath(
            coordinator: coordinator,
            mode: mode,
            expectedNextStep: .phoneNumberEntry(stubs.phoneNumberEntryState(mode: mode))
        )

        pushRegistrationManagerMock.addRequestPushTokenMock({ .value(.success(Stubs.apnsRegistrationId)) })

        // We'll never provide a challenge token and will just leave it around forever.
        let (challengeTokenPromise, _) = Guarantee<String>.pending()
        var receivePreAuthChallengeTokenCount = 0
        pushRegistrationManagerMock.addReceivePreAuthChallengeTokenMock({
            receivePreAuthChallengeTokenCount += 1
            return challengeTokenPromise
        })
        pushRegistrationManagerMock.addReceivePreAuthChallengeTokenMock({
            receivePreAuthChallengeTokenCount += 1
            return challengeTokenPromise
        })
        pushRegistrationManagerMock.addReceivePreAuthChallengeTokenMock({
            receivePreAuthChallengeTokenCount += 1
            return challengeTokenPromise
        })

        // Give back a session with a push challenge.
        sessionManager.addBeginSessionResponseMock(.success(stubs.session(
            allowedToRequestCode: false,
            requestedInformation: [.pushChallenge]
        )))

        timeoutProviderMock.pushTokenMinWaitTime = 0.5
        timeoutProviderMock.pushTokenTimeout = 2

        // Give it a phone number, which should cause it to start a session.
        let nextStep = await coordinator.submitE164(Stubs.e164).awaitable()
        #expect(nextStep == .showErrorSheet(.sessionInvalidated))

        // One time to set up, one time for the min wait time, one time
        // for the full timeout.
        #expect(receivePreAuthChallengeTokenCount == 3)
    }

    @MainActor @Test(arguments: Self.testCases())
    func testSessionPath_pushChallengeWithoutPushNotificationsAvailable(testCase: TestCase) async {
        let coordinator = setupTest(testCase)
        let mode = testCase.mode

        // Set profile info so we skip those steps.
        setupDefaultAccountAttributes()
        pushRegistrationManagerMock.addRequestPushTokenMock({ .value(.pushUnsupported(description: "")) })
        pushRegistrationManagerMock.addReceivePreAuthChallengeTokenMock({ .pending().0 })

        // Get past the opening.
        await goThroughOpeningHappyPath(
            coordinator: coordinator,
            mode: mode,
            expectedNextStep: .phoneNumberEntry(stubs.phoneNumberEntryState(mode: mode))
        )

        // Require a push challenge, which we won't be able to answer.
        sessionManager.addBeginSessionResponseMock(.success(stubs.session(
            allowedToRequestCode: false,
            requestedInformation: [.pushChallenge],
        )))

        // Give it a phone number, which should cause it to start a session.
        #expect(
            await coordinator.submitE164(Stubs.e164).awaitable() ==
                .phoneNumberEntry(stubs.phoneNumberEntryState(
                    mode: mode,
                    previouslyEnteredE164: Stubs.e164
                ))
        )
        #expect(sessionManager.latestChallengeFulfillment == nil)
    }

    @MainActor @Test(arguments: Self.testCases())
    func testSessionPath_preferPushChallengesIfWeCanAnswerThemImmediately(testCase: TestCase) async {
        let coordinator = setupTest(testCase)
        let mode = testCase.mode

        await setUpSessionPath(coordinator: coordinator, mode: mode)

        pushRegistrationManagerMock.addRequestPushTokenMock({ .value(.success(Stubs.apnsRegistrationId)) })

        // Be ready to provide the push challenge token as soon as it's needed.
        pushRegistrationManagerMock.addReceivePreAuthChallengeTokenMock({ .value("a pre-auth challenge token") })

        // Give back a session with multiple challenges.
        sessionManager.addBeginSessionResponseMock(.success(stubs.session(
            allowedToRequestCode: false,
            requestedInformation: [.captcha, .pushChallenge],
        )))

        // Be ready to handle push challenges as soon as we can.
        sessionManager.addFulfillChallengeResponseMock(.success(stubs.session(
            nextVerificationAttempt: 0,
        )))

        sessionManager.addRequestCodeResponseMock(.success(stubs.session(
            nextVerificationAttempt: 0,
        )))

        // Give it a phone number, which should cause it to start a session.
        #expect(
            await coordinator.submitE164(Stubs.e164).awaitable() ==
                .verificationCodeEntry(stubs.verificationCodeEntryState(mode: mode))
        )
        #expect(
            sessionManager.latestChallengeFulfillment ==
                .pushChallenge("a pre-auth challenge token")
        )
    }

    @MainActor @Test(arguments: Self.testCases())
    func testSessionPath_prefersCaptchaChallengesIfWeCannotAnswerPushChallengeQuickly(testCase: TestCase) async {
        let coordinator = setupTest(testCase)
        let mode = testCase.mode

        await setUpSessionPath(coordinator: coordinator, mode: mode)

        pushRegistrationManagerMock.addRequestPushTokenMock({ .value(.success(Stubs.apnsRegistrationId)) })

        // Prepare to provide the challenge token.
        let (challengeTokenPromise, _) = Guarantee<String>.pending()
        pushRegistrationManagerMock.addReceivePreAuthChallengeTokenMock({ challengeTokenPromise })

        // Give back a session with multiple challenges.
        sessionManager.addBeginSessionResponseMock(.success(stubs.session(
            allowedToRequestCode: false,
            requestedInformation: [.pushChallenge, .captcha],
        )))

        timeoutProviderMock.pushTokenMinWaitTime = 0.5
        timeoutProviderMock.pushTokenTimeout = 2

        // Give it a phone number, which should cause it to start a session.
        let nextStep = await coordinator.submitE164(Stubs.e164).awaitable()

        // After that, we should get a captcha step back, because we haven't
        // yet received the push challenge token.
        #expect(nextStep == .captchaChallenge)
    }

    @MainActor @Test(arguments: Self.testCases())
    func testSessionPath_pushChallengeFastResolution(testCase: TestCase) async {
        let coordinator = setupTest(testCase)
        let mode = testCase.mode

        await setUpSessionPath(coordinator: coordinator, mode: mode)

        pushRegistrationManagerMock.addRequestPushTokenMock({ .value(.success(Stubs.apnsRegistrationId)) })

        // Prepare to provide the challenge token.
        let (challengeTokenPromise, challengeTokenFuture) = Guarantee<String>.pending()
        pushRegistrationManagerMock.addReceivePreAuthChallengeTokenMock({ challengeTokenPromise })
        pushRegistrationManagerMock.addReceivePreAuthChallengeTokenMock({ challengeTokenPromise })

        // Give back a session with multiple challenges.
        sessionManager.addBeginSessionResponseMock(.success(stubs.session(
            allowedToRequestCode: false,
            requestedInformation: [.pushChallenge, .captcha],
        )))

        // Also prep for the token's submission.
        sessionManager.addFulfillChallengeResponseMock(.success(stubs.session(
            nextVerificationAttempt: 0,
        )))

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
        #expect(
            await coordinator.submitE164(Stubs.e164).awaitable() ==
                .verificationCodeEntry(stubs.verificationCodeEntryState(mode: mode))
        )
    }

    @MainActor @Test(arguments: Self.testCases())
    func testSessionPath_ignoresPushChallengesIfWeCannotEverAnswerThem(testCase: TestCase) async {
        let coordinator = setupTest(testCase)
        let mode = testCase.mode

        // Set profile info so we skip those steps.
        setupDefaultAccountAttributes()

        pushRegistrationManagerMock.addRequestPushTokenMock({ .value(.pushUnsupported(description: "")) })
        pushRegistrationManagerMock.addReceivePreAuthChallengeTokenMock({ .pending().0 })

        // No other setup; no auth credentials, SVR keys, etc in storage
        // so that we immediately go to the session flow.

        // Get past the opening.
        await goThroughOpeningHappyPath(
            coordinator: coordinator,
            mode: mode,
            expectedNextStep: .phoneNumberEntry(stubs.phoneNumberEntryState(mode: mode))
        )

        // Give back a session with multiple challenges.
        sessionManager.addBeginSessionResponseMock(.success(stubs.session(
            allowedToRequestCode: false,
            requestedInformation: [.captcha, .pushChallenge],
        )))

        // Give it a phone number, which should cause it to start a session.
        #expect(await coordinator.submitE164(Stubs.e164).awaitable() == .captchaChallenge)
        #expect(sessionManager.latestChallengeFulfillment == nil)
    }

    @MainActor @Test(arguments: Self.testCases())
    func testSessionPath_unknownChallenge(testCase: TestCase) async {
        let coordinator = setupTest(testCase)
        let mode = testCase.mode

        await setUpSessionPath(coordinator: coordinator, mode: mode)

        // Give back a session with a captcha challenge and an unknown challenge.
        sessionManager.addBeginSessionResponseMock(.success(stubs.session(
            allowedToRequestCode: false,
            requestedInformation: [.captcha],
            hasUnknownChallengeRequiringAppUpdate: true,
        )))

        // Give back a session without the captcha but still with the unknown challenge
        sessionManager.addFulfillChallengeResponseMock(.success(stubs.session(
            allowedToRequestCode: false,
            hasUnknownChallengeRequiringAppUpdate: true,
        )))

        // Once we get that session, we should get a captcha step back.
        // We have an unknown challenge, but we should do known challenges first!
        // Give it a phone number, which should cause it to start a session.
        #expect(await coordinator.submitE164(Stubs.e164).awaitable() == .captchaChallenge)

        // This means we should get the app update banner.
        #expect(await coordinator.submitCaptcha(Stubs.captchaToken).awaitable() == .appUpdateBanner)
    }

    @MainActor @Test(arguments: Self.testCases())
    func testSessionPath_wrongVerificationCode(testCase: TestCase) async {
        let coordinator = setupTest(testCase)
        let mode = testCase.mode

        await createSessionAndRequestFirstCode(coordinator: coordinator, mode: mode)

        // Give back a rejected argument response, its the wrong code.
        sessionManager.addSubmitCodeResponseMock(.rejectedArgument(stubs.session(
            nextVerificationAttempt: 0
        )))

        // Now try and send the wrong code.
        let badCode = "garbage"
        #expect(
            await coordinator.submitVerificationCode(badCode).awaitable() ==
                .verificationCodeEntry(stubs.verificationCodeEntryState(
                    mode: mode,
                    validationError: .invalidVerificationCode(invalidCode: badCode)
                ))
        )
    }

    @MainActor @Test(arguments: Self.testCases())
    func testSessionPath_verificationCodeTimeouts(testCase: TestCase) async {
        let coordinator = setupTest(testCase)
        let mode = testCase.mode

        await createSessionAndRequestFirstCode(coordinator: coordinator, mode: mode)

        // Give back a retry response.
        sessionManager.addSubmitCodeResponseMock(.retryAfterTimeout(stubs.session(
            nextVerificationAttempt: 10,
        )))

        // Resend an sms code, time that out too.
        sessionManager.addRequestCodeResponseMock(.retryAfterTimeout(stubs.session(
            nextSMS: 7,
            nextCall: 0,
            nextVerificationAttempt: 9,
        )))

        // Resend an voice code, time that out too
        // Make the timeout SO short that it retries
        sessionManager.didRequestCode = false
        sessionManager.addRequestCodeResponseMock(.retryAfterTimeout(stubs.session(
            nextSMS: 6,
            nextCall: 0.1,
            nextVerificationAttempt: 8,
        )))

        // Be ready for the retry. Ensure we called it the first time.
        sessionManager.addRequestCodeResponseMock(.retryAfterTimeout(stubs.session(
            nextSMS: 5,
            nextCall: 4,
            nextVerificationAttempt: 8,
        )))

        #expect(
            await coordinator.submitVerificationCode(Stubs.verificationCode).awaitable() ==
            .verificationCodeEntry(stubs.verificationCodeEntryState(
                mode: mode,
                nextVerificationAttempt: 10,
                validationError: .submitCodeTimeout
            ))
        )

        #expect(
            await coordinator.requestSMSCode().awaitable() ==
                .verificationCodeEntry(stubs.verificationCodeEntryState(
                    mode: mode,
                    nextSMS: 7,
                    nextVerificationAttempt: 9,
                    validationError: .smsResendTimeout
                ))
        )

        #expect(
            await coordinator.requestVoiceCode().awaitable() ==
                .verificationCodeEntry(stubs.verificationCodeEntryState(
                    mode: mode,
                    nextSMS: 5,
                    nextCall: 4,
                    nextVerificationAttempt: 8,
                    validationError: .voiceResendTimeout
                ))
        )

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
        #expect(
            await coordinator.submitVerificationCode(Stubs.verificationCode).awaitable() ==
                .showErrorSheet(.verificationCodeSubmissionUnavailable)
        )

        #expect(
            await coordinator.nextStep().awaitable() ==
                .verificationCodeEntry(stubs.verificationCodeEntryState(
                    mode: mode,
                    nextVerificationAttempt: nil
                ))
        )
    }

    @MainActor @Test(arguments: Self.testCases())
    func testSessionPath_timedOutVerificationCodeWithoutRetries(testCase: TestCase) async {
        let coordinator = setupTest(testCase)
        let mode = testCase.mode

        await createSessionAndRequestFirstCode(coordinator: coordinator, mode: mode)

        // Give back a retry response when submitting a code,
        // but with no ability to resubmit.
        sessionManager.addSubmitCodeResponseMock(.retryAfterTimeout(stubs.session()))

        #expect(
            await coordinator.submitVerificationCode(Stubs.verificationCode).awaitable() ==
                .showErrorSheet(.verificationCodeSubmissionUnavailable)
        )

        #expect(
            await coordinator.nextStep().awaitable() ==
            .verificationCodeEntry(stubs.verificationCodeEntryState(
                mode: mode,
                nextVerificationAttempt: nil
            ))
        )
    }

    @MainActor @Test(arguments: Self.testCases())
    func testSessionPath_expiredSession(testCase: TestCase) async {
        let coordinator = setupTest(testCase)
        let mode = testCase.mode

        await setUpSessionPath(coordinator: coordinator, mode: mode)

        // Give back a session thats ready to go.
        sessionManager.addBeginSessionResponseMock(.success(stubs.session()))

        // Once we get that session, we should try and send a verification code.
        // Have that ready to go.
        // We'll ask for a push challenge, though we won't resolve it.
        pushRegistrationManagerMock.addReceivePreAuthChallengeTokenMock({ .pending().0 })

        // Resolve with a session
        sessionManager.addRequestCodeResponseMock(.success(stubs.session(
            nextVerificationAttempt: 0,
        )))

        // Give back an expired session.
        sessionManager.addSubmitCodeResponseMock(.invalidSession)

        // Give it a phone number, which should cause it to start a session.
        // Now we should expect to be at verification code entry since we sent the code.
        #expect(
            await coordinator.submitE164(Stubs.e164).awaitable() ==
                .verificationCodeEntry(stubs.verificationCodeEntryState(mode: mode))
        )

        #expect(
            await coordinator.submitVerificationCode(Stubs.pinCode).awaitable() ==
                .showErrorSheet(.sessionInvalidated)
        )

        #expect(
            await coordinator.nextStep().awaitable() ==
                .phoneNumberEntry(stubs.phoneNumberEntryState(
                    mode: mode,
                    previouslyEnteredE164: Stubs.e164
                ))
       )
    }

    @MainActor @Test(arguments: Self.testCases())
    func testSessionPath_skipPINCode(testCase: TestCase) async {
        let coordinator = setupTest(testCase)
        let mode = testCase.mode

        await createSessionAndRequestFirstCode(coordinator: coordinator, mode: mode)

        let accountEntropyPool = AccountEntropyPool()
        let newMasterKey = accountEntropyPool.getMasterKey()
        if testCase.newKey == .accountEntropyPool {
            missingKeyGenerator.accountEntropyPool = { accountEntropyPool }
        } else {
            missingKeyGenerator.masterKey = { newMasterKey }
        }

        // Give back a verified session.
        sessionManager.addSubmitCodeResponseMock(.success(stubs.session(
            receivedDate: date,
            verified: true
        )))

        let accountIdentityResponse = Stubs.accountIdentityResponse()
        var authPassword: String!

        // That means it should try and register with the verified
        // session; be ready for that.

        // Before registering, it should ask for push tokens to give the registration.
        pushRegistrationManagerMock.addRequestPushTokenMock({
            .value(.success(Stubs.apnsRegistrationId))
        })

        // It should also fetch the prekeys for account creation
        preKeyManagerMock.addCreatePreKeysMock({
            return .value(Stubs.prekeyBundles())
        })

        let expectedRequest = createAccountWithSession(newMasterKey)
        mockURLSession.addResponse(
            TSRequestOWSURLSessionMock.Response(
                matcher: { request in
                    authPassword = request.authPassword
                    let requestAttributes = Self.attributesFromCreateAccountRequest(request)
                    // These should be empty if sessionId is sent
                    #expect((request.parameters["recoveryPassword"] as? String) == nil)
                    #expect(requestAttributes.registrationRecoveryPassword == nil)
                    return request.url == expectedRequest.url
                },
                statusCode: 200,
                bodyJson: accountIdentityResponse
            ),
        )

        func expectedAuthedAccount() -> AuthedAccount {
            return .explicit(
                aci: accountIdentityResponse.aci,
                pni: accountIdentityResponse.pni,
                e164: Stubs.e164,
                deviceId: .primary,
                authPassword: authPassword
            )
        }

        // Once we are registered, we should finalize prekeys.
        preKeyManagerMock.addFinalizePreKeyMock { didSucceed in
            #expect(didSucceed)
            return .value(())
        }

        // Then we should try and create one time pre-keys
        // with the credentials we got in the identity response.
        preKeyManagerMock.addRotateOneTimePreKeyMock({ auth in
            #expect(auth == expectedAuthedAccount().chatServiceAuth)
            return .value(())
        })

        // When we skip the pin, it should skip any SVR backups.
        svr.backupMasterKeyMock = { _, masterKey, _ in
            Issue.record("Shouldn't talk to SVR with skipped PIN!")
            return .value(masterKey)
        }

        storageServiceManagerMock.addRestoreOrCreateManifestIfNecessaryMock({ _, _ in
            return .value(())
        })

        // Once we skip the storage service restore,
        // we will sync account attributes and then we are finished!
        let expectedAttributesRequest = RegistrationRequestFactory.updatePrimaryDeviceAccountAttributesRequest(
            Stubs.accountAttributes(newMasterKey),
            auth: .implicit() // doesn't matter for url matching
        )
        mockURLSession.addResponse(
            matcher: { request in
                return request.url == expectedAttributesRequest.url
            },
            statusCode: 200
        )

        var didSetLocalAccountEntropyPool = false
        svr.useDeviceLocalAccountEntropyPoolMock = { _ in
            #expect(self.svr.hasAccountEntropyPool == false)
            didSetLocalAccountEntropyPool = true
        }

        var didSetLocalMasterKey = false
        svr.useDeviceLocalMasterKeyMock = { _ in
            #expect(self.svr.hasMasterKey == false)
            didSetLocalMasterKey = true
        }

        // Once we sync push tokens, we should restore from storage service.
        storageServiceManagerMock.addRestoreOrCreateManifestIfNecessaryMock({ auth, masterKeySource in
            #expect(auth.authedAccount == expectedAuthedAccount())
            switch masterKeySource {
            case .explicit(let explicitMasterKey):
                #expect(newMasterKey.rawData == explicitMasterKey.rawData)
            default:
                Issue.record("Unexpected master key used in storage service operation.")
            }
            return .value(())
        })

        storageServiceManagerMock.addRotateManifestMock({ _, _ in
            // TODO: Really should make this explicit credentials
            return .value(())
        })

        // Now we should ask to create a PIN.
        // No exit allowed since we've already started trying to create the account.
        #expect(
            await coordinator.submitVerificationCode(Stubs.pinCode).awaitable() ==
                .pinEntry(
                    Stubs.pinEntryStateForPostRegCreate(mode: mode, exitConfigOverride: .noExitAllowed)
                )
        )

        // At this point we should have no master key.
        #expect(svr.hasMasterKey == false)
        #expect(svr.hasAccountEntropyPool == false)

        // Skip the PIN code.
        #expect(await coordinator.skipPINCode().awaitable() == .done)

        if testCase.newKey == .accountEntropyPool {
            #expect(didSetLocalAccountEntropyPool)
        } else {
            #expect(didSetLocalMasterKey)
        }

        // Since we set profile info, we should have scheduled a reupload.
        #expect(profileManagerMock.didScheduleReuploadLocalProfile)
    }

    @MainActor @Test(arguments: Self.testCases())
    func testSessionPath_skipPINRestore_createNewPIN(testCase: TestCase) async {
        let coordinator = setupTest(testCase)
        let mode = testCase.mode

        switch mode {
        case .registering:
            break
        case .reRegistering, .changingNumber:
            // Test only applies to registering scenarios.
            return
        }

        await createSessionAndRequestFirstCode(coordinator: coordinator, mode: mode)

        let accountEntropyPool = AccountEntropyPool()
        let newMasterKey = accountEntropyPool.getMasterKey()
        if testCase.newKey == .accountEntropyPool {
            missingKeyGenerator.accountEntropyPool = { accountEntropyPool }
        } else {
            missingKeyGenerator.masterKey = { newMasterKey }
        }

        // Give back a verified session.
        sessionManager.addSubmitCodeResponseMock(.success(stubs.session(
            receivedDate: date,
            verified: true
        )))

        // Previously used SVR so we first ask to restore.
        let accountIdentityResponse = Stubs.accountIdentityResponse(hasPreviouslyUsedSVR: true)
        var authPassword: String!

        // Try and register with the verified session
        // Before registering, it should ask for push tokens to give the registration.
        pushRegistrationManagerMock.addRequestPushTokenMock({ .value(.success(Stubs.apnsRegistrationId)) })

        // It should also fetch the prekeys for account creation
        preKeyManagerMock.addCreatePreKeysMock({ .value(Stubs.prekeyBundles())})

        let expectedRequest = createAccountWithSession(newMasterKey)
        mockURLSession.addResponse(
            TSRequestOWSURLSessionMock.Response(
                matcher: { request in
                    authPassword = request.authPassword
                    return request.url == expectedRequest.url
                },
                statusCode: 200,
                bodyJson: accountIdentityResponse
            )
        )

        func expectedAuthedAccount() -> AuthedAccount {
            return .explicit(
                aci: accountIdentityResponse.aci,
                pni: accountIdentityResponse.pni,
                e164: Stubs.e164,
                deviceId: .primary,
                authPassword: authPassword
            )
        }

        // Once we are registered, we should finalize prekeys.
        preKeyManagerMock.addFinalizePreKeyMock { didSucceed in
            #expect(didSucceed)
            return .value(())
        }

        // Then we should try and create one time pre-keys
        // with the credentials we got in the identity response.
        preKeyManagerMock.addRotateOneTimePreKeyMock({ auth in
            #expect(auth == expectedAuthedAccount().chatServiceAuth)
            return .value(())
        })

        // When we skip the pin, it should skip any SVR backups.
        svr.backupMasterKeyMock = { _, masterKey, _ in
            Issue.record("Shouldn't talk to SVR with skipped PIN!")
            return .value(masterKey)

        }

        storageServiceManagerMock.addRestoreOrCreateManifestIfNecessaryMock({ auth, masterKeySource in
            #expect(auth.authedAccount == expectedAuthedAccount())
            switch masterKeySource {
            case .explicit(let explicitMasterKey):
                #expect(newMasterKey.rawData == explicitMasterKey.rawData)
            default:
                Issue.record("Unexpected master key used in storage service operation.")
            }
            return .value(())
        })

        storageServiceManagerMock.addRotateManifestMock({ _, _ in return .value(()) })

        // Once we skip the storage service restore,
        // we will sync account attributes and then we are finished!
        let expectedAttributesRequest = RegistrationRequestFactory.updatePrimaryDeviceAccountAttributesRequest(
            Stubs.accountAttributes(newMasterKey),
            auth: .implicit() // doesn't matter for url matching
        )
        mockURLSession.addResponse(
            matcher: { request in
                return request.url == expectedAttributesRequest.url
            },
            statusCode: 200
        )

        var didSetLocalAccountEntropyPool = false
        svr.useDeviceLocalAccountEntropyPoolMock = { _ in
            #expect(self.svr.hasAccountEntropyPool == false)
            didSetLocalAccountEntropyPool = true
        }

        var didSetLocalMasterKey = false
        svr.useDeviceLocalMasterKeyMock = { _ in
            #expect(self.svr.hasMasterKey == false)
            didSetLocalMasterKey = true
        }

        // Now we should ask to restore the PIN.
        #expect(
            await coordinator.submitVerificationCode(Stubs.pinCode).awaitable() ==
            .pinEntry(
                Stubs.pinEntryStateForPostRegRestore(mode: mode)
            )
        )

        // Skip the PIN code and create a new one instead.
        // When we skip, we should be asked to _create_ the PIN.
        #expect(
            await coordinator.skipAndCreateNewPINCode().awaitable() ==
            .pinEntry(
                Stubs.pinEntryStateForPostRegCreate(mode: mode, exitConfigOverride: .noExitAllowed)
            )
        )

        // At this point we should have no master key.
        #expect(svr.hasMasterKey.negated)

        // Skip this PIN code, too.
        #expect(await coordinator.skipPINCode().awaitable() == .done)

        if testCase.newKey == .accountEntropyPool {
            #expect(didSetLocalAccountEntropyPool)
        } else {
            #expect(didSetLocalMasterKey)
        }

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
            ReglockState.none
        )

        // Serialized ReglockState.reglocked(
        //     credential: KBSAuthCredential(credential: RemoteAttestation.Auth(username: "abcd", password: "xyz"),
        //     expirationDate: reglockExpirationDate
        // )
        let reglockStateReglockedData = "7b227265676c6f636b6564223a7b2265787069726174696f6e44617465223a2d3937383239373230302c2263726564656e7469616c223a7b2263726564656e7469616c223a7b22757365726e616d65223a2261626364222c2270617373776f7264223a2278797a227d7d7d7d"
        #expect(
            try decoder.decode(ReglockState.self, from: Data.data(fromHex: reglockStateReglockedData)!) ==
            ReglockState.reglocked(credential: .testOnly(svr2: nil), expirationDate: reglockExpirationDate)
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
            ReglockState.reglocked(credential: .init(svr2: Stubs.svr2AuthCredential), expirationDate: reglockExpirationDate)
        )

        // Serialized ReglockState.waitingTimeout(expirationDate: reglockExpirationDate)
        let reglockStateWaitingTimeoutData = "7b2277616974696e6754696d656f7574223a7b2265787069726174696f6e44617465223a2d3937383239373230307d7d"
        #expect(
            try decoder.decode(ReglockState.self, from: Data.data(fromHex: reglockStateWaitingTimeoutData)!) ==
            ReglockState.waitingTimeout(expirationDate: reglockExpirationDate)
        )
    }

    // MARK: Happy Path Setups

    private func createAccountWithSession(
        _ masterKey: MasterKey
    ) -> TSRequest {
        return RegistrationRequestFactory.createAccountRequest(
            verificationMethod: .sessionId(Stubs.sessionId),
            e164: Stubs.e164,
            authPassword: "", // Doesn't matter for request generation.
            accountAttributes: Stubs.accountAttributes(masterKey),
            skipDeviceTransfer: true,
            apnRegistrationId: Stubs.apnsRegistrationId,
            prekeyBundles: Stubs.prekeyBundles()
        )
    }

    private func createAccountWithRecoveryPw(
        _ masterKey: MasterKey
    ) -> TSRequest {
        return RegistrationRequestFactory.createAccountRequest(
            verificationMethod: .recoveryPassword(masterKey.regRecoveryPw),
            e164: Stubs.e164,
            authPassword: "", // Doesn't matter for request generation.
            accountAttributes: Stubs.accountAttributes(masterKey),
            skipDeviceTransfer: true,
            apnRegistrationId: Stubs.apnsRegistrationId,
            prekeyBundles: Stubs.prekeyBundles()
        )
    }

    @MainActor
    private func goThroughOpeningHappyPath(
        coordinator: any RegistrationCoordinator,
        mode: RegistrationMode,
        expectedNextStep: RegistrationStep
    ) async {
        contactsStore.doesNeedContactsAuthorization = true
        pushRegistrationManagerMock.doesNeedNotificationAuthorization = true

        switch mode {
        case .registering:
            // Gotta get the splash out of the way.
            #expect(await coordinator.nextStep().awaitable() == .registrationSplash)
        case .reRegistering, .changingNumber:
            break
        }

        // Now we should show the permissions.
        #expect(await coordinator.continueFromSplash().awaitable() == .permissions)

        // Once the state is updated we can proceed.
        #expect(await coordinator.requestPermissions().awaitable() == expectedNextStep)
    }

    @MainActor
    private func setUpSessionPath(coordinator: any RegistrationCoordinator, mode: RegistrationMode) async {
        // Set profile info so we skip those steps.
        setupDefaultAccountAttributes()

        pushRegistrationManagerMock.addRequestPushTokenMock({ .value(.success(Stubs.apnsRegistrationId)) })

        pushRegistrationManagerMock.addReceivePreAuthChallengeTokenMock({ .pending().0 })

        // No other setup; no auth credentials, SVR keys, etc in storage
        // so that we immediately go to the session flow.

        // Get past the opening.
        await goThroughOpeningHappyPath(
            coordinator: coordinator,
            mode: mode,
            expectedNextStep: .phoneNumberEntry(stubs.phoneNumberEntryState(mode: mode))
        )
    }

    @MainActor
    private func createSessionAndRequestFirstCode(coordinator: any RegistrationCoordinator, mode: RegistrationMode) async {
        await setUpSessionPath(coordinator: coordinator, mode: mode)

        // Give it a phone number, which should cause it to start a session.

        // We'll ask for a push challenge, though we won't resolve it.
        pushRegistrationManagerMock.addReceivePreAuthChallengeTokenMock({ Guarantee<String>.pending().0 })

        // Give back a session that's ready to go.
        sessionManager.addBeginSessionResponseMock(.success(stubs.session()))

        // Once we get that session, we should try and send a code.
        // Resolve with a session thats ready for code submission.
        sessionManager.addRequestCodeResponseMock(.success(stubs.session(nextVerificationAttempt: 0)))

        // We should get back the code entry step.
        #expect(
            await coordinator.submitE164(Stubs.e164).awaitable() ==
                .verificationCodeEntry(stubs.verificationCodeEntryState(mode: mode))
        )
    }

    // MARK: - Helpers

    private func setupDefaultAccountAttributes() {
        ows2FAManagerMock.pinCodeMock = { nil }
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
                isPhoneNumberShared: false
            )
        }
    }

    private static func attributesFromCreateAccountRequest(
        _ request: TSRequest
    ) -> AccountAttributes {
        let accountAttributesData = try! JSONSerialization.data(
            withJSONObject: request.parameters["accountAttributes"]!,
            options: .fragmentsAllowed
        )
        return try! JSONDecoder().decode(
            AccountAttributes.self,
            from: accountAttributesData
        )
    }

    // MARK: - Helpers

    func buildKeyDataMocks(_ testCase: TestCase) -> (MasterKey, MasterKey) {
        let newAccountEntropyPool = AccountEntropyPool()
        let newMasterKey = newAccountEntropyPool.getMasterKey()
        let oldAccountEntropyPool = AccountEntropyPool()
        let oldMasterKey = oldAccountEntropyPool.getMasterKey()
        switch (testCase.oldKey, testCase.newKey) {
        case (.accountEntropyPool, .accountEntropyPool):
            // on re-registration, make the AEP be present
            db.write { accountKeyStore.setAccountEntropyPool(oldAccountEntropyPool, tx: $0) }
            return (oldMasterKey, oldMasterKey)
        case (.masterKey, .masterKey):
            db.write { accountKeyStore.setMasterKey(oldMasterKey, tx: $0) }
            return (oldMasterKey, oldMasterKey)
        case (.masterKey, .accountEntropyPool):
            // If this is a reregistration from an non-AEP client,
            // AEP is only available after calling getOrGenerateAEP()
            db.write { accountKeyStore.setMasterKey(oldMasterKey, tx: $0) }
            missingKeyGenerator.accountEntropyPool = {
                return newAccountEntropyPool
            }
            return (oldMasterKey, newMasterKey)
        case (.none, .masterKey):
            missingKeyGenerator.masterKey = { newMasterKey }
            return (newMasterKey, newMasterKey)
        case (.none, .accountEntropyPool):
            missingKeyGenerator.accountEntropyPool = {
                newAccountEntropyPool
            }
            return (newMasterKey, newMasterKey)
        case (.accountEntropyPool, .masterKey):
            fatalError("Migrating to masterkey from AEP not supported")
        case (_, .none):
            fatalError("Registration requires a destination key")
        }
    }

    func mockSVRCredentials(isMatch: Bool) {
        // Put some auth credentials in storage.
        let svr2CredentialCandidates: [SVR2AuthCredential] = [
            Stubs.svr2AuthCredential,
            SVR2AuthCredential(credential: RemoteAttestation.Auth(username: "aaaa", password: "abc")),
            SVR2AuthCredential(credential: RemoteAttestation.Auth(username: "zzzz", password: "xyz")),
            SVR2AuthCredential(credential: RemoteAttestation.Auth(username: "0000", password: "123"))
        ]
        svrAuthCredentialStore.svr2Dict = Dictionary(grouping: svr2CredentialCandidates, by: \.credential.username).mapValues { $0.first! }

        // Give it a phone number, which should cause it to check the auth credentials.
        // Match the main auth credential.
        let expectedSVR2CheckRequest = RegistrationRequestFactory.svr2AuthCredentialCheckRequest(
            e164: Stubs.e164,
            credentials: svr2CredentialCandidates
        )
        mockURLSession.addResponse(TSRequestOWSURLSessionMock.Response(
            urlSuffix: expectedSVR2CheckRequest.url.absoluteString,
            statusCode: 200,
            bodyJson: RegistrationServiceResponses.SVR2AuthCheckResponse(matches: [
                "\(Stubs.svr2AuthCredential.credential.username):\(Stubs.svr2AuthCredential.credential.password)": isMatch ? .match : .notMatch,
                "aaaa:abc": .notMatch,
                "zzzz:xyz": .invalid,
                "0000:123": .unknown
            ])
        ))
    }

    // MARK: - Stubs

    private struct Stubs {

        static let e164 = E164("+17875550100")!
        static let aci = Aci.randomForTesting()
        static let pinCode = "1234"

        static let svr2AuthCredential = SVR2AuthCredential(credential: RemoteAttestation.Auth(username: "xxx", password: "yyy"))

        static let captchaToken = "captchaToken"
        static let apnsToken = "apnsToken"
        static let apnsRegistrationId = RegistrationRequestFactory.ApnRegistrationId(apnsToken: Stubs.apnsToken)

        static let authUsername = "username_jdhfsalkjfhd"
        static let authPassword = "password_dskafjasldkfjasf"

        static let sessionId = UUID().uuidString
        static let verificationCode = "8888"

        var date: Date = Date()

        static func accountAttributes(_ masterKey: MasterKey? = nil) -> AccountAttributes {
            return AccountAttributes(
                isManualMessageFetchEnabled: false,
                registrationId: 0,
                pniRegistrationId: 0,
                unidentifiedAccessKey: "",
                unrestrictedUnidentifiedAccess: false,
                twofaMode: .none,
                registrationRecoveryPassword: masterKey?.regRecoveryPw,
                encryptedDeviceName: nil,
                discoverableByPhoneNumber: .nobody,
                hasSVRBackups: true
            )
        }

        static func accountIdentityResponse(
            hasPreviouslyUsedSVR: Bool = false
        ) -> RegistrationServiceResponses.AccountIdentityResponse {
            return RegistrationServiceResponses.AccountIdentityResponse(
                aci: Stubs.aci,
                pni: Pni.randomForTesting(),
                e164: Stubs.e164,
                username: nil,
                hasPreviouslyUsedSVR: hasPreviouslyUsedSVR
            )
        }

        static func prekeyBundles() -> RegistrationPreKeyUploadBundles {
            return RegistrationPreKeyUploadBundles(
                aci: preKeyBundle(identity: .aci),
                pni: preKeyBundle(identity: .pni)
            )
        }

        static func preKeyBundle(identity: OWSIdentity) -> RegistrationPreKeyUploadBundle {
            let identityKeyPair = ECKeyPair.generateKeyPair()
            return RegistrationPreKeyUploadBundle(
                identity: identity,
                identityKeyPair: identityKeyPair,
                signedPreKey: SignedPreKeyStoreImpl.generateSignedPreKey(signedBy: identityKeyPair),
                lastResortPreKey: {
                    let keyPair = KEMKeyPair.generate()
                    let signature = identityKeyPair.keyPair.privateKey.generateSignature(message: keyPair.publicKey.serialize())

                    let record = SignalServiceKit.KyberPreKeyRecord(
                        0,
                        keyPair: keyPair,
                        signature: signature,
                        generatedAt: Date(),
                        replacedAt: nil,
                        isLastResort: true
                    )
                    return record
                }()
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
            verified: Bool = false
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
                verified: verified
            )
        }

        // MARK: Step States

        static func pinEntryStateForRegRecoveryPath(
            mode: RegistrationMode,
            error: RegistrationPinValidationError? = nil,
            remainingAttempts: UInt? = nil
        ) -> RegistrationPinState {
            return RegistrationPinState(
                operation: .enteringExistingPin(
                    skippability: .canSkip,
                    remainingAttempts: remainingAttempts
                ),
                error: error,
                contactSupportMode: .v2WithUnknownReglockState,
                exitConfiguration: mode.pinExitConfig
            )
        }

        static func pinEntryStateForSVRAuthCredentialPath(
            mode: RegistrationMode,
            error: RegistrationPinValidationError? = nil
        ) -> RegistrationPinState {
            return RegistrationPinState(
                operation: .enteringExistingPin(skippability: .canSkip, remainingAttempts: nil),
                error: error,
                contactSupportMode: .v2WithUnknownReglockState,
                exitConfiguration: mode.pinExitConfig
            )
        }

        func phoneNumberEntryState(
            mode: RegistrationMode,
            previouslyEnteredE164: E164? = nil,
            withValidationErrorFor response: Registration.BeginSessionResponse? = nil
        ) -> RegistrationPhoneNumberViewState {
            let response = response ?? .success(session())
            let validationError: RegistrationPhoneNumberViewState.ValidationError?
            switch response {
            case .success:
                validationError = nil
            case .invalidArgument:
                validationError = .invalidE164(.init(invalidE164: previouslyEnteredE164 ?? Stubs.e164))
            case .retryAfter(let timeInterval):
                validationError = .rateLimited(.init(
                    expiration: date.addingTimeInterval(timeInterval),
                    e164: previouslyEnteredE164 ?? Stubs.e164
                ))
            case .networkFailure, .genericError:
                Issue.record("Should not be generating phone number state for error responses.")
                validationError = nil
            }

            switch mode {
            case .registering:
                return .registration(.initialRegistration(.init(
                    previouslyEnteredE164: previouslyEnteredE164,
                    validationError: validationError,
                    canExitRegistration: true
                )))
            case .reRegistering(let params):
                return .registration(.reregistration(.init(
                    e164: params.e164,
                    validationError: validationError,
                    canExitRegistration: true
                )))
            case .changingNumber(let changeNumberParams):
                switch validationError {
                case .none:
                    if let newE164 = previouslyEnteredE164 {
                        return .changingNumber(.confirmation(.init(
                            oldE164: changeNumberParams.oldE164,
                            newE164: newE164,
                            rateLimitedError: nil
                        )))
                    } else {
                        return .changingNumber(.initialEntry(.init(
                            oldE164: changeNumberParams.oldE164,
                            newE164: nil,
                            hasConfirmed: false,
                            invalidE164Error: nil
                        )))
                    }
                case .rateLimited(let error):
                    return .changingNumber(.confirmation(.init(
                        oldE164: changeNumberParams.oldE164,
                        newE164: previouslyEnteredE164!,
                        rateLimitedError: error
                    )))
                case .invalidInput:
                    owsFail("Can't happen.")
                case .invalidE164(let error):
                    return .changingNumber(.initialEntry(.init(
                        oldE164: changeNumberParams.oldE164,
                        newE164: previouslyEnteredE164,
                        hasConfirmed: previouslyEnteredE164 != nil,
                        invalidE164Error: error
                    )))
                }
            }
        }

        func verificationCodeEntryState(
            mode: RegistrationMode,
            e164: E164 = Stubs.e164,
            nextSMS: TimeInterval? = 0,
            nextCall: TimeInterval? = 0,
            showHelpText: Bool = false,
            nextVerificationAttempt: TimeInterval? = 0,
            validationError: RegistrationVerificationValidationError? = nil,
            exitConfigOverride: RegistrationVerificationState.ExitConfiguration? = nil
        ) -> RegistrationVerificationState {

            let canChangeE164: Bool
            switch mode {
            case .reRegistering:
                canChangeE164 = false
            case .registering, .changingNumber:
                canChangeE164 = true
            }

            return RegistrationVerificationState(
                e164: e164,
                nextSMSDate: nextSMS.map { date.addingTimeInterval($0) },
                nextCallDate: nextCall.map { date.addingTimeInterval($0) },
                nextVerificationAttemptDate: nextVerificationAttempt.map { date.addingTimeInterval($0) },
                canChangeE164: canChangeE164,
                showHelpText: showHelpText,
                validationError: validationError,
                exitConfiguration: exitConfigOverride ?? mode.verificationExitConfig
            )
        }

        static func pinEntryStateForSessionPathReglock(
            mode: RegistrationMode,
            error: RegistrationPinValidationError? = nil
        ) -> RegistrationPinState {
            return RegistrationPinState(
                operation: .enteringExistingPin(skippability: .unskippable, remainingAttempts: nil),
                error: error,
                contactSupportMode: .v2WithReglock,
                exitConfiguration: mode.pinExitConfig
            )
        }

        static func pinEntryStateForPostRegRestore(
            mode: RegistrationMode,
            exitConfigOverride: RegistrationPinState.ExitConfiguration? = nil,
            error: RegistrationPinValidationError? = nil
        ) -> RegistrationPinState {
            return RegistrationPinState(
                operation: .enteringExistingPin(
                    skippability: .canSkipAndCreateNew,
                    remainingAttempts: nil
                ),
                error: error,
                contactSupportMode: .v2NoReglock,
                exitConfiguration: exitConfigOverride ?? mode.pinExitConfig
            )
        }

        static func pinEntryStateForPostRegCreate(
            mode: RegistrationMode,
            exitConfigOverride: RegistrationPinState.ExitConfiguration? = nil
        ) -> RegistrationPinState {
            return RegistrationPinState(
                operation: .creatingNewPin,
                error: nil,
                contactSupportMode: .v2NoReglock,
                exitConfiguration: exitConfigOverride ?? mode.pinExitConfig
            )
        }

        static func pinEntryStateForPostRegConfirm(
            mode: RegistrationMode,
            error: RegistrationPinValidationError? = nil,
            exitConfigOverride: RegistrationPinState.ExitConfiguration? = nil
        ) -> RegistrationPinState {
            return RegistrationPinState(
                operation: .confirmingNewPin(.stub()),
                error: error,
                contactSupportMode: .v2NoReglock,
                exitConfiguration: exitConfigOverride ?? mode.pinExitConfig
            )
        }
    }
}

extension RegistrationMode {

    var testDescription: String {
        switch self {
        case .registering:
            return "registering"
        case .reRegistering:
            return "re-registering"
        case .changingNumber:
            return "changing number"
        }
    }

    var pinExitConfig: RegistrationPinState.ExitConfiguration {
        switch self {
        case .registering:
            return .noExitAllowed
        case .reRegistering:
            return .exitReRegistration
        case .changingNumber:
            // TODO[Registration]: test change number properly
            return .exitChangeNumber
        }
    }

    var verificationExitConfig: RegistrationVerificationState.ExitConfiguration {
        switch self {
        case .registering:
            return .noExitAllowed
        case .reRegistering:
            return .exitReRegistration
        case .changingNumber:
            // TODO[Registration]: test change number properly
            return .exitChangeNumber
        }
    }
}

private extension MasterKey {
    var regRecoveryPw: String { data(for: .registrationRecoveryPassword).rawData.base64EncodedString() }
    var reglockToken: String { data(for: .registrationLock).rawData.hexadecimalString }
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

private extension Usernames.UsernameLink {
    static var mocked: Usernames.UsernameLink {
        return Usernames.UsernameLink(
            handle: UUID(),
            entropy: Data(repeating: 8, count: 32)
        )!
    }
}

private extension TSRequest {
    var authPassword: String {
        var httpHeaders = HttpHeaders()
        applyAuth(to: &httpHeaders, willSendViaWebSocket: false)
        let authHeader = httpHeaders.value(forHeader: "Authorization")!
        owsPrecondition(authHeader.hasPrefix("Basic "))
        let authValue = String(data: Data(base64Encoded: String(authHeader.dropFirst(6)))!, encoding: .utf8)!
        return String(authValue.split(separator: ":").dropFirst().first!)
    }
}
