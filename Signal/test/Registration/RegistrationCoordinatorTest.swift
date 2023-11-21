//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import LibSignalClient
import XCTest

@testable import Signal
@testable import SignalServiceKit

public class RegistrationCoordinatorTest: XCTestCase {

    // If we just use the force unwrap optional, switches are forced
    // to handle the none case.
    private var _mode: RegistrationMode!

    var mode: RegistrationMode {
        return self._mode
    }

    private var date = Date() {
        didSet {
            Stubs.date = date
        }
    }
    private var dateProvider: DateProvider!

    private var scheduler: TestScheduler!

    private var coordinator: RegistrationCoordinatorImpl!

    private var accountManagerMock: RegistrationCoordinatorImpl.TestMocks.AccountManager!
    private var appExpiryMock: MockAppExpiry!
    private var changeNumberPniManager: ChangePhoneNumberPniManagerMock!
    private var contactsStore: RegistrationCoordinatorImpl.TestMocks.ContactsStore!
    private var experienceManager: RegistrationCoordinatorImpl.TestMocks.ExperienceManager!
    private var mockMessagePipelineSupervisor: RegistrationCoordinatorImpl.TestMocks.MessagePipelineSupervisor!
    private var mockMessageProcessor: RegistrationCoordinatorImpl.TestMocks.MessageProcessor!
    private var mockURLSession: TSRequestOWSURLSessionMock!
    private var ows2FAManagerMock: RegistrationCoordinatorImpl.TestMocks.OWS2FAManager!
    private var phoneNumberDiscoverabilityManagerMock: MockPhoneNumberDiscoverabilityManager!
    private var preKeyManagerMock: RegistrationCoordinatorImpl.TestMocks.PreKeyManager!
    private var profileManagerMock: RegistrationCoordinatorImpl.TestMocks.ProfileManager!
    private var pushRegistrationManagerMock: RegistrationCoordinatorImpl.TestMocks.PushRegistrationManager!
    private var receiptManagerMock: RegistrationCoordinatorImpl.TestMocks.ReceiptManager!
    private var registrationStateChangeManagerMock: MockRegistrationStateChangeManager!
    private var sessionManager: RegistrationSessionManagerMock!
    private var storageServiceManagerMock: FakeStorageServiceManager!
    private var svr: SecureValueRecoveryMock!
    private var svrAuthCredentialStore: SVRAuthCredentialStorageMock!
    private var tsAccountManagerMock: MockTSAccountManager!

    public override func setUp() {
        super.setUp()

        Stubs.date = date
        dateProvider = { self.date }

        let db = MockDB()

        accountManagerMock = RegistrationCoordinatorImpl.TestMocks.AccountManager()
        appExpiryMock = MockAppExpiry()
        changeNumberPniManager = ChangePhoneNumberPniManagerMock(
            mockKyberStore: MockKyberPreKeyStore(dateProvider: Date.provider)
        )
        contactsStore = RegistrationCoordinatorImpl.TestMocks.ContactsStore()
        experienceManager = RegistrationCoordinatorImpl.TestMocks.ExperienceManager()
        svr = SecureValueRecoveryMock()
        svrAuthCredentialStore = SVRAuthCredentialStorageMock()
        mockMessagePipelineSupervisor = RegistrationCoordinatorImpl.TestMocks.MessagePipelineSupervisor()
        mockMessageProcessor = RegistrationCoordinatorImpl.TestMocks.MessageProcessor()
        ows2FAManagerMock = RegistrationCoordinatorImpl.TestMocks.OWS2FAManager()
        phoneNumberDiscoverabilityManagerMock = MockPhoneNumberDiscoverabilityManager()
        preKeyManagerMock = RegistrationCoordinatorImpl.TestMocks.PreKeyManager()
        profileManagerMock = RegistrationCoordinatorImpl.TestMocks.ProfileManager()
        pushRegistrationManagerMock = RegistrationCoordinatorImpl.TestMocks.PushRegistrationManager()
        receiptManagerMock = RegistrationCoordinatorImpl.TestMocks.ReceiptManager()
        registrationStateChangeManagerMock = MockRegistrationStateChangeManager()
        sessionManager = RegistrationSessionManagerMock()
        storageServiceManagerMock = FakeStorageServiceManager()
        tsAccountManagerMock = MockTSAccountManager(dateProvider: dateProvider)

        let mockURLSession = TSRequestOWSURLSessionMock()
        self.mockURLSession = mockURLSession
        let mockSignalService = OWSSignalServiceMock()
        mockSignalService.mockUrlSessionBuilder = { _, _, _ in
            return mockURLSession
        }

        scheduler = TestScheduler()

        let dependencies = RegistrationCoordinatorDependencies(
            accountManager: accountManagerMock,
            appExpiry: appExpiryMock,
            changeNumberPniManager: changeNumberPniManager,
            contactsManager: RegistrationCoordinatorImpl.TestMocks.ContactsManager(),
            contactsStore: contactsStore,
            dateProvider: { self.dateProvider() },
            db: db,
            experienceManager: experienceManager,
            keyValueStoreFactory: InMemoryKeyValueStoreFactory(),
            messagePipelineSupervisor: mockMessagePipelineSupervisor,
            messageProcessor: mockMessageProcessor,
            ows2FAManager: ows2FAManagerMock,
            phoneNumberDiscoverabilityManager: phoneNumberDiscoverabilityManagerMock,
            preKeyManager: preKeyManagerMock,
            profileManager: profileManagerMock,
            pushRegistrationManager: pushRegistrationManagerMock,
            receiptManager: receiptManagerMock,
            registrationStateChangeManager: registrationStateChangeManagerMock,
            schedulers: TestSchedulers(scheduler: scheduler),
            sessionManager: sessionManager,
            signalService: mockSignalService,
            storageServiceManager: storageServiceManagerMock,
            svr: svr,
            svrAuthCredentialStore: svrAuthCredentialStore,
            tsAccountManager: tsAccountManagerMock,
            udManager: RegistrationCoordinatorImpl.TestMocks.UDManager()
        )
        let loader = RegistrationCoordinatorLoaderImpl(dependencies: dependencies)
        coordinator = db.write {
            return loader.coordinator(
                forDesiredMode: mode,
                transaction: $0
            ) as! RegistrationCoordinatorImpl
        }
    }

    public override class var defaultTestSuite: XCTestSuite {
        let testSuite = XCTestSuite(name: NSStringFromClass(self))
        addTests(to: testSuite, mode: .registering)
        addTests(to: testSuite, mode: .reRegistering(.init(e164: Stubs.e164, aci: Stubs.aci)))
        return testSuite
    }

    private class func addTests(
        to testSuite: XCTestSuite,
        mode: RegistrationMode
    ) {
        testInvocations.forEach { invocation in
            let testCase = RegistrationCoordinatorTest(invocation: invocation)
            testCase._mode = mode
            testSuite.addTest(testCase)
        }
    }

    private func executeTest(_ block: () -> Void) {
        XCTContext.runActivity(named: "\(self.name), mode:\(mode.testDescription)", block: { _ in
            block()
        })
    }

    private func executeTest(_ block: () throws -> Void) throws {
        try XCTContext.runActivity(named: "\(self.name), mode:\(mode.testDescription)", block: { _ in
            try block()
        })
    }

    // MARK: - Opening Path

    func testOpeningPath_splash() {
        executeTest {
            // Don't care about timing, just start it.
            scheduler.start()

            setupDefaultAccountAttributes()

            switch mode {
            case .registering:
                // With no state set up, should show the splash.
                XCTAssertEqual(coordinator.nextStep().value, .registrationSplash)
                // Once we show it, don't show it again.
                XCTAssertNotEqual(coordinator.continueFromSplash().value, .registrationSplash)
            case .reRegistering, .changingNumber:
                XCTAssertNotEqual(coordinator.nextStep().value, .registrationSplash)
            }
        }
    }

    func testOpeningPath_appExpired() {
        executeTest {
            // Don't care about timing, just start it.
            scheduler.start()

            appExpiryMock.expirationDate = .distantPast

            setupDefaultAccountAttributes()

            // We should start with the banner.
            XCTAssertEqual(coordinator.nextStep().value, .appUpdateBanner)
        }
    }

    func testOpeningPath_permissions() {
        executeTest {
            // Don't care about timing, just start it.
            scheduler.start()

            setupDefaultAccountAttributes()

            contactsStore.doesNeedContactsAuthorization = true
            pushRegistrationManagerMock.doesNeedNotificationAuthorization = true

            var nextStep: Guarantee<RegistrationStep>
            switch mode {
            case .registering:
                // Gotta get the splash out of the way.
                XCTAssertEqual(coordinator.nextStep().value, .registrationSplash)
                nextStep = coordinator.continueFromSplash()
            case .reRegistering, .changingNumber:
                // No splash for these.
                nextStep = coordinator.nextStep()
            }

            // Now we should show the permissions.
            XCTAssertEqual(nextStep.value, .permissions(Stubs.permissionsState()))
            // Doesn't change even if we try and proceed.
            XCTAssertEqual(coordinator.nextStep().value, .permissions(Stubs.permissionsState()))

            // Once the state is updated we can proceed.
            nextStep = coordinator.requestPermissions()
            XCTAssertNotNil(nextStep.value)
            XCTAssertNotEqual(nextStep.value, .registrationSplash)
            XCTAssertNotEqual(nextStep.value, .permissions(Stubs.permissionsState()))
        }
    }

    // MARK: - Reg Recovery Password Path

    func testRegRecoveryPwPath_happyPath() throws {
        try executeTest {
            try _runRegRecoverPwPathTestHappyPath(wasReglockEnabled: false)
        }
    }

    func testRegRecoveryPwPath_happyPathWithReglock() throws {
        try executeTest {
            try _runRegRecoverPwPathTestHappyPath(wasReglockEnabled: true)
        }
    }

    private func _runRegRecoverPwPathTestHappyPath(wasReglockEnabled: Bool) throws {
        // Don't care about timing, just start it.
        scheduler.start()

        // Set profile info so we skip those steps.
        setupDefaultAccountAttributes()

        ows2FAManagerMock.isReglockEnabledMock = { wasReglockEnabled }

        // Set a PIN on disk.
        ows2FAManagerMock.pinCodeMock = { Stubs.pinCode }

        // Make SVR give us back a reg recovery password.
        svr.dataGenerator = {
            switch $0 {
            case .registrationRecoveryPassword:
                return Stubs.regRecoveryPwData
            case .registrationLock:
                return Stubs.reglockData
            default:
                return nil
            }
        }

        // NOTE: We expect to skip opening path steps because
        // if we have a SVR master key locally, this _must_ be
        // a previously registered device, and we can skip intros.

        // We haven't set a phone number so it should ask for that.
        XCTAssertEqual(coordinator.nextStep().value, .phoneNumberEntry(Stubs.phoneNumberEntryState(mode: mode)))

        // Give it a phone number, which should show the PIN entry step.
        var nextStep = coordinator.submitE164(Stubs.e164).value
        // Now it should ask for the PIN to confirm the user knows it.
        XCTAssertEqual(nextStep, .pinEntry(Stubs.pinEntryStateForRegRecoveryPath(mode: self.mode)))

        // Give it the pin code, which should make it try and register.

        // It needs an apns token to register.
        pushRegistrationManagerMock.requestPushTokenMock = {
            return .value(.success(Stubs.apnsRegistrationId))
        }
        // It needs prekeys as well.
        preKeyManagerMock.createPreKeysMock = {
            return .value(Stubs.prekeyBundles())
        }
        // And will finalize prekeys after success.
        preKeyManagerMock.finalizePreKeysMock = { didSucceed in
            XCTAssert(didSucceed)
            return .value(())
        }

        let expectedRequest = RegistrationRequestFactory.createAccountRequest(
            verificationMethod: .recoveryPassword(Stubs.regRecoveryPw),
            e164: Stubs.e164,
            authPassword: "", // Doesn't matter for request generation.
            accountAttributes: Stubs.accountAttributes(),
            skipDeviceTransfer: true,
            apnRegistrationId: Stubs.apnsRegistrationId,
            prekeyBundles: Stubs.prekeyBundles()
        )
        let identityResponse = Stubs.accountIdentityResponse()
        var authPassword: String!
        mockURLSession.addResponse(TSRequestOWSURLSessionMock.Response(
            matcher: { request in
                // The password is generated internally by RegistrationCoordinator.
                // Extract it so we can check that the same password sent to the server
                // to register is used later for other requests.
                authPassword = request.authPassword
                let requestAttributes = Self.attributesFromCreateAccountRequest(request)
                if wasReglockEnabled {
                    XCTAssertEqual(Stubs.reglockData.hexadecimalString, requestAttributes.registrationLockToken)
                } else {
                    XCTAssertNil(requestAttributes.registrationLockToken)
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
        preKeyManagerMock.rotateOneTimePreKeysMock = { auth in
            XCTAssertEqual(auth, expectedAuthedAccount().chatServiceAuth)
            return .value(())
        }

        if wasReglockEnabled {
            // If we had reglock before registration, it should be re-enabled.
            let expectedReglockRequest = OWSRequestFactory.enableRegistrationLockV2Request(token: Stubs.reglockToken)
            mockURLSession.addResponse(TSRequestOWSURLSessionMock.Response(
                matcher: { request in
                    return request.url == expectedReglockRequest.url
                },
                statusCode: 200,
                bodyData: nil
            ))
        }

        // We haven't done a SVR backup; that should happen now.
        svr.generateAndBackupKeysMock = { pin, authMethod, rotateMasterKey in
            XCTAssertEqual(pin, Stubs.pinCode)
            // We don't have a SVR auth credential, it should use chat server creds.
            XCTAssertEqual(authMethod, .chatServerAuth(expectedAuthedAccount()))
            XCTAssertFalse(rotateMasterKey)
            self.svr.hasMasterKey = true
            return .value(())
        }

        // Once we sync push tokens, we should restore from storage service.
        accountManagerMock.performInitialStorageServiceRestoreMock = { auth in
            XCTAssertEqual(auth.authedAccount, expectedAuthedAccount())
            return .value(())
        }

        // Once we do the storage service restore,
        // we will sync account attributes and then we are finished!
        let expectedAttributesRequest = RegistrationRequestFactory.updatePrimaryDeviceAccountAttributesRequest(
            Stubs.accountAttributes(),
            auth: .implicit() // doesn't matter for url matching
        )
        self.mockURLSession.addResponse(
            matcher: { request in
                return request.url == expectedAttributesRequest.url
            },
            statusCode: 200
        )

        nextStep = coordinator.submitPINCode(Stubs.pinCode).value
        XCTAssertEqual(nextStep, .done)
    }

    func testRegRecoveryPwPath_wrongPIN() throws {
        try executeTest {
            // Don't care about timing, just start it.
            scheduler.start()

            // Set profile info so we skip those steps.
            setupDefaultAccountAttributes()

            let wrongPinCode = "ABCD"

            // Set a different PIN on disk.
            ows2FAManagerMock.pinCodeMock = { Stubs.pinCode }

            // Make SVR give us back a reg recovery password.
            svr.dataGenerator = {
                switch $0 {
                case .registrationRecoveryPassword:
                    return Stubs.regRecoveryPwData
                case .registrationLock:
                    return Stubs.reglockData
                default:
                    return nil
                }
            }

            // NOTE: We expect to skip opening path steps because
            // if we have a SVR master key locally, this _must_ be
            // a previously registered device, and we can skip intros.

            // We haven't set a phone number so it should ask for that.
            XCTAssertEqual(coordinator.nextStep().value, .phoneNumberEntry(Stubs.phoneNumberEntryState(mode: mode)))

            // Give it a phone number, which should show the PIN entry step.
            var nextStep = coordinator.submitE164(Stubs.e164).value
            // Now it should ask for the PIN to confirm the user knows it.
            XCTAssertEqual(nextStep, .pinEntry(Stubs.pinEntryStateForRegRecoveryPath(mode: self.mode)))

            // Give it the wrong PIN, it should reject and give us the same step again.
            nextStep = coordinator.submitPINCode(wrongPinCode).value
            XCTAssertEqual(
                nextStep,
                .pinEntry(Stubs.pinEntryStateForRegRecoveryPath(
                    mode: self.mode,
                    error: .wrongPin(wrongPin: wrongPinCode),
                    remainingAttempts: 9
                ))
            )

            // Give it the right pin code, which should make it try and register.

            // It needs an apns token to register.
            pushRegistrationManagerMock.requestPushTokenMock = {
                return .value(.success(Stubs.apnsRegistrationId))
            }
            // Every time we register we also ask for prekeys.
            preKeyManagerMock.createPreKeysMock = {
                return .value(Stubs.prekeyBundles())
            }
            // And we finalize them after.
            preKeyManagerMock.finalizePreKeysMock = { didSucceed in
                XCTAssertTrue(didSucceed)
                return .value(())
            }

            let expectedRequest = RegistrationRequestFactory.createAccountRequest(
                verificationMethod: .recoveryPassword(Stubs.regRecoveryPw),
                e164: Stubs.e164,
                authPassword: "", // Doesn't matter for request generation.
                accountAttributes: Stubs.accountAttributes(),
                skipDeviceTransfer: true,
                apnRegistrationId: Stubs.apnsRegistrationId,
                prekeyBundles: Stubs.prekeyBundles()
            )

            let identityResponse = Stubs.accountIdentityResponse()
            var authPassword: String!
            mockURLSession.addResponse(TSRequestOWSURLSessionMock.Response(
                matcher: { request in
                    authPassword = request.authPassword
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
            preKeyManagerMock.rotateOneTimePreKeysMock = { auth in
                XCTAssertEqual(auth, expectedAuthedAccount().chatServiceAuth)
                return .value(())
            }

            // We haven't done a SVR backup; that should happen now.
            svr.generateAndBackupKeysMock = { pin, authMethod, rotateMasterKey in
                XCTAssertEqual(pin, Stubs.pinCode)
                // We don't have a SVR auth credential, it should use chat server creds.
                XCTAssertEqual(authMethod, .chatServerAuth(expectedAuthedAccount()))
                XCTAssertFalse(rotateMasterKey)
                self.svr.hasMasterKey = true
                return .value(())
            }

            // Once we sync push tokens, we should restore from storage service.
            accountManagerMock.performInitialStorageServiceRestoreMock = { auth in
                XCTAssertEqual(auth.authedAccount, expectedAuthedAccount())
                return .value(())
            }

            // Once we do the storage service restore,
            // we will sync account attributes and then we are finished!
            let expectedAttributesRequest = RegistrationRequestFactory.updatePrimaryDeviceAccountAttributesRequest(
                Stubs.accountAttributes(),
                auth: .implicit() // // doesn't matter for url matching
            )
            self.mockURLSession.addResponse(
                matcher: { request in
                    return request.url == expectedAttributesRequest.url
                },
                statusCode: 200
            )

            nextStep = coordinator.submitPINCode(Stubs.pinCode).value
            XCTAssertEqual(nextStep, .done)
        }
    }

    func testRegRecoveryPwPath_wrongPassword() {
        executeTest {
            // Set profile info so we skip those steps.
            setupDefaultAccountAttributes()

            // Set a PIN on disk.
            ows2FAManagerMock.pinCodeMock = { Stubs.pinCode }

            // Make SVR give us back a reg recovery password.
            svr.dataGenerator = {
                switch $0 {
                case .registrationRecoveryPassword:

                    return Stubs.regRecoveryPwData
                case .registrationLock:
                    return Stubs.reglockData
                default:
                    return nil
                }
            }
            svr.hasMasterKey = true

            // Run the scheduler for a bit; we don't care about timing these bits.
            scheduler.start()

            // NOTE: We expect to skip opening path steps because
            // if we have a SVR master key locally, this _must_ be
            // a previously registered device, and we can skip intros.

            // We haven't set a phone number so it should ask for that.
            XCTAssertEqual(coordinator.nextStep().value, .phoneNumberEntry(Stubs.phoneNumberEntryState(mode: mode)))

            // Give it a phone number, which should show the PIN entry step.
            var nextStep = coordinator.submitE164(Stubs.e164)
            // Now it should ask for the PIN to confirm the user knows it.
            XCTAssertEqual(nextStep.value, .pinEntry(Stubs.pinEntryStateForRegRecoveryPath(mode: self.mode)))

            // Now we want to control timing so we can verify things happened in the right order.
            scheduler.stop()
            scheduler.adjustTime(to: 0)

            // Give it the pin code, which should make it try and register.
            nextStep = coordinator.submitPINCode(Stubs.pinCode)

            // Before registering at t=0, it should ask for push tokens to give the registration.
            // It will also ask again later at t=3 when account creation fails and it needs
            // to create a new session.
            pushRegistrationManagerMock.requestPushTokenMock = {
                switch self.scheduler.currentTime {
                case 0:
                    return self.scheduler.guarantee(resolvingWith: .success(Stubs.apnsRegistrationId), atTime: 1)
                case 3:
                    return .value(.success(Stubs.apnsRegistrationId))
                default:
                    XCTFail("Got unexpected push tokens request")
                    return .value(.timeout)
                }
            }
            // Every time we register we also ask for prekeys.
            preKeyManagerMock.createPreKeysMock = {
                switch self.scheduler.currentTime {
                case 1, 3:
                    return .value(Stubs.prekeyBundles())
                default:
                    XCTFail("Got unexpected push tokens request")
                    return .init(error: PreKeyError())
                }
            }
            // And we finalize them after.
            preKeyManagerMock.finalizePreKeysMock = { didSucceed in
                switch self.scheduler.currentTime {
                case 3:
                    XCTAssertFalse(didSucceed)
                    return .value(())
                case 4:
                    XCTAssertTrue(didSucceed)
                    return .value(())
                default:
                    XCTFail("Got unexpected push tokens request")
                    return .init(error: PreKeyError())
                }
            }

            let expectedRecoveryPwRequest = RegistrationRequestFactory.createAccountRequest(
                verificationMethod: .recoveryPassword(Stubs.regRecoveryPw),
                e164: Stubs.e164,
                authPassword: "", // Doesn't matter for request generation.
                accountAttributes: Stubs.accountAttributes(),
                skipDeviceTransfer: true,
                apnRegistrationId: Stubs.apnsRegistrationId,
                prekeyBundles: Stubs.prekeyBundles()
            )

            // Fail the request at t=3; the reg recovery pw is invalid.
            let failResponse = TSRequestOWSURLSessionMock.Response(
                urlSuffix: expectedRecoveryPwRequest.url!.absoluteString,
                statusCode: RegistrationServiceResponses.AccountCreationResponseCodes.unauthorized.rawValue
            )
            mockURLSession.addResponse(failResponse, atTime: 3, on: scheduler)

            // Once the first request fails, at t=3, it should try an start a session.
            scheduler.run(atTime: 2) {
                // Resolve with a session at time 4.
                self.sessionManager.beginSessionResponse = self.scheduler.guarantee(
                    resolvingWith: .success(Stubs.session(hasSentVerificationCode: false)),
                    atTime: 4
                )
            }

            // Before requesting a session at t=3, it should ask for push tokens to give the session.
            // This was set up above.

            // Then when it gets back the session at t=4, it should immediately ask for
            // a verification code to be sent.
            scheduler.run(atTime: 4) {
                // We'll ask for a push challenge, though we don't need to resolve it in this test.
                self.pushRegistrationManagerMock.receivePreAuthChallengeTokenMock = {
                    return Guarantee<String>.pending().0
                }

                // Resolve with an updated session at time 5.
                self.sessionManager.requestCodeResponse = self.scheduler.guarantee(
                    resolvingWith: .success(Stubs.session(hasSentVerificationCode: true)),
                    atTime: 5
                )
            }

            // Check we have the master key now, to be safe.
            XCTAssert(svr.hasMasterKey)
            scheduler.runUntilIdle()
            XCTAssertEqual(scheduler.currentTime, 5)

            // Now we should expect to be at verification code entry since we already set the phone number.
            // No exit allowed since we've already started trying to create the account.
            XCTAssertEqual(nextStep.value, .verificationCodeEntry(
                Stubs.verificationCodeEntryState(mode: self.mode, exitConfigOverride: .noExitAllowed)
            ))
            // We want to have kept the master key; we failed the reg recovery pw check
            // but that could happen even if the key is valid. Once we finish session based
            // re-registration we want to be able to recover the key.
            XCTAssert(svr.hasMasterKey)
        }
    }

    func testRegRecoveryPwPath_failedReglock() {
        executeTest {
            // Set profile info so we skip those steps.
            setupDefaultAccountAttributes()

            // Set a PIN on disk.
            ows2FAManagerMock.pinCodeMock = { Stubs.pinCode }

            // Make SVR give us back a reg recovery password.
            svr.dataGenerator = {
                switch $0 {
                case .registrationRecoveryPassword:
                    return Stubs.regRecoveryPwData
                case .registrationLock:
                    return Stubs.reglockData
                default:
                    return nil
                }
            }
            svr.hasMasterKey = true

            // Run the scheduler for a bit; we don't care about timing these bits.
            scheduler.start()

            // NOTE: We expect to skip opening path steps because
            // if we have a SVR master key locally, this _must_ be
            // a previously registered device, and we can skip intros.

            // We haven't set a phone number so it should ask for that.
            XCTAssertEqual(coordinator.nextStep().value, .phoneNumberEntry(Stubs.phoneNumberEntryState(mode: mode)))

            // Give it a phone number, which should show the PIN entry step.
            var nextStep = coordinator.submitE164(Stubs.e164)
            // Now it should ask for the PIN to confirm the user knows it.
            XCTAssertEqual(nextStep.value, .pinEntry(Stubs.pinEntryStateForRegRecoveryPath(mode: self.mode)))

            // Now we want to control timing so we can verify things happened in the right order.
            scheduler.stop()
            scheduler.adjustTime(to: 0)

            // Give it the pin code, which should make it try and register.
            nextStep = coordinator.submitPINCode(Stubs.pinCode)

            // First we try and create an account with reg recovery
            // password; we will fail with reglock error.
            // First we get apns tokens, then prekeys, then register
            // then finalize prekeys (with failure) after.
            let firstPushTokenTime = 0
            let firstPreKeyCreateTime = 1
            let firstRegistrationTime = 2
            let firstPreKeyFinalizeTime = 3

            // Once we fail, we try again immediately with the reglock
            // token we fetch.
            // Same sequence as the first request.
            let secondPushTokenTime = 4
            let secondPreKeyCreateTime = 5
            let secondRegistrationTime = 6
            let secondPreKeyFinalizeTime = 7

            // When that fails, we try and create a session.
            // No prekey stuff this time, just apns token and session requests.
            let thirdPushTokenTime = 8
            let sessionStartTime = 9
            let sendVerificationCodeTime = 10

            pushRegistrationManagerMock.requestPushTokenMock = {
                switch self.scheduler.currentTime {
                case firstPushTokenTime, secondPushTokenTime, thirdPushTokenTime:
                    return self.scheduler.guarantee(resolvingWith: .success(Stubs.apnsRegistrationId), atTime: self.scheduler.currentTime + 1)
                default:
                    XCTFail("Got unexpected push tokens request")
                    return .value(.timeout)
                }
            }
            preKeyManagerMock.createPreKeysMock = {
                switch self.scheduler.currentTime {
                case firstPreKeyCreateTime, secondPreKeyCreateTime:
                    return self.scheduler.promise(resolvingWith: Stubs.prekeyBundles(), atTime: self.scheduler.currentTime + 1)
                default:
                    XCTFail("Got unexpected prekeys request")
                    return .init(error: PreKeyError())
                }
            }
            preKeyManagerMock.finalizePreKeysMock = { didSucceed in
                switch self.scheduler.currentTime {
                case firstPreKeyFinalizeTime, secondPreKeyFinalizeTime:
                    XCTAssertFalse(didSucceed)
                    return self.scheduler.promise(resolvingWith: (), atTime: self.scheduler.currentTime + 1)
                default:
                    XCTFail("Got unexpected prekeys request")
                    return .init(error: PreKeyError())
                }
            }

            let expectedRecoveryPwRequest = RegistrationRequestFactory.createAccountRequest(
                verificationMethod: .recoveryPassword(Stubs.regRecoveryPw),
                e164: Stubs.e164,
                authPassword: "", // Doesn't matter for request generation.
                accountAttributes: Stubs.accountAttributes(),
                skipDeviceTransfer: true,
                apnRegistrationId: Stubs.apnsRegistrationId,
                prekeyBundles: Stubs.prekeyBundles()
            )

            // Fail the first request; the reglock is invalid.
            let failResponse = TSRequestOWSURLSessionMock.Response(
                urlSuffix: expectedRecoveryPwRequest.url!.absoluteString,
                statusCode: RegistrationServiceResponses.AccountCreationResponseCodes.reglockFailed.rawValue,
                bodyJson: RegistrationServiceResponses.RegistrationLockFailureResponse(
                    timeRemainingMs: 10,
                    svr2AuthCredential: Stubs.svr2AuthCredential
                )
            )
            mockURLSession.addResponse(failResponse, atTime: firstRegistrationTime + 1, on: scheduler)

            // Once the request fails, we should try again with the reglock
            // token, this time.
            mockURLSession.addResponse(failResponse, atTime: secondRegistrationTime + 1, on: scheduler)

            // Once the second request fails, it should try an start a session.
            scheduler.run(atTime: sessionStartTime - 1) {
                // We'll ask for a push challenge, though we don't need to resolve it in this test.
                self.pushRegistrationManagerMock.receivePreAuthChallengeTokenMock = {
                    return Guarantee<String>.pending().0
                }

                // Resolve with a session.
                self.sessionManager.beginSessionResponse = self.scheduler.guarantee(
                    resolvingWith: .success(Stubs.session(hasSentVerificationCode: false)),
                    atTime: sessionStartTime + 1
                )
            }

            // Then when it gets back the session, it should immediately ask for
            // a verification code to be sent.
            scheduler.run(atTime: sendVerificationCodeTime - 1) {
                // Resolve with an updated session.
                self.sessionManager.requestCodeResponse = self.scheduler.guarantee(
                    resolvingWith: .success(Stubs.session(hasSentVerificationCode: true)),
                    atTime: sendVerificationCodeTime + 1
                )
            }

            XCTAssert(svr.hasMasterKey)
            scheduler.runUntilIdle()
            XCTAssertEqual(scheduler.currentTime, sendVerificationCodeTime + 1)

            // Now we should expect to be at verification code entry since we already set the phone number.
            // No exit allowed since we've already started trying to create the account.
            XCTAssertEqual(nextStep.value, .verificationCodeEntry(
                Stubs.verificationCodeEntryState(mode: self.mode, exitConfigOverride: .noExitAllowed)
            ))
            // We want to have wiped our master key; we failed reglock, which means the key itself is
            // wrong.
            XCTAssertFalse(svr.hasMasterKey)
        }
    }

    func testRegRecoveryPwPath_retryNetworkError() throws {
        executeTest {
            // Set profile info so we skip those steps.
            setupDefaultAccountAttributes()

            // Set a PIN on disk.
            ows2FAManagerMock.pinCodeMock = { Stubs.pinCode }

            // Make SVR give us back a reg recovery password.
            svr.dataGenerator = {
                switch $0 {
                case .registrationRecoveryPassword:
                    return Stubs.regRecoveryPwData
                case .registrationLock:
                    return Stubs.reglockData
                default:
                    return nil
                }
            }
            svr.hasMasterKey = true

            // Run the scheduler for a bit; we don't care about timing these bits.
            scheduler.start()

            // NOTE: We expect to skip opening path steps because
            // if we have a SVR master key locally, this _must_ be
            // a previously registered device, and we can skip intros.

            // We haven't set a phone number so it should ask for that.
            XCTAssertEqual(coordinator.nextStep().value, .phoneNumberEntry(Stubs.phoneNumberEntryState(mode: mode)))

            // Give it a phone number, which should show the PIN entry step.
            var nextStep = coordinator.submitE164(Stubs.e164)
            // Now it should ask for the PIN to confirm the user knows it.
            XCTAssertEqual(nextStep.value, .pinEntry(Stubs.pinEntryStateForRegRecoveryPath(mode: self.mode)))

            // Now we want to control timing so we can verify things happened in the right order.
            scheduler.stop()
            scheduler.adjustTime(to: 0)

            // Give it the pin code, which should make it try and register.
            nextStep = coordinator.submitPINCode(Stubs.pinCode)

            // Before registering at t=0, it should ask for push tokens to give the registration.
            // When it retries at t=3, it will ask again.
            pushRegistrationManagerMock.requestPushTokenMock = {
                switch self.scheduler.currentTime {
                case 0:
                    return self.scheduler.guarantee(resolvingWith: .success(Stubs.apnsRegistrationId), atTime: 1)
                case 3:
                    return self.scheduler.guarantee(resolvingWith: .success(Stubs.apnsRegistrationId), atTime: 4)
                default:
                    XCTFail("Got unexpected push tokens request")
                    return .value(.timeout)
                }
            }
            // Every time we register we also ask for prekeys.
            preKeyManagerMock.createPreKeysMock = {
                switch self.scheduler.currentTime {
                case 1, 4:
                    return .value(Stubs.prekeyBundles())
                default:
                    XCTFail("Got unexpected push tokens request")
                    return .init(error: PreKeyError())
                }
            }
            // And we finalize them after.
            preKeyManagerMock.finalizePreKeysMock = { didSucceed in
                switch self.scheduler.currentTime {
                case 3:
                    XCTAssertFalse(didSucceed)
                    return .value(())
                case 5:
                    XCTAssertTrue(didSucceed)
                    return .value(())
                default:
                    XCTFail("Got unexpected push tokens request")
                    return .init(error: PreKeyError())
                }
            }

            let expectedRecoveryPwRequest = RegistrationRequestFactory.createAccountRequest(
                verificationMethod: .recoveryPassword(Stubs.regRecoveryPw),
                e164: Stubs.e164,
                authPassword: "", // Doesn't matter for request generation.
                accountAttributes: Stubs.accountAttributes(),
                skipDeviceTransfer: true,
                apnRegistrationId: Stubs.apnsRegistrationId,
                prekeyBundles: Stubs.prekeyBundles()
            )

            // Fail the request at t=3 with a network error.
            let failResponse = TSRequestOWSURLSessionMock.Response.networkError(url: expectedRecoveryPwRequest.url!)
            mockURLSession.addResponse(failResponse, atTime: 3, on: scheduler)

            let identityResponse = Stubs.accountIdentityResponse()
            var authPassword: String!

            // Once the first request fails, at t=3, it should retry.
            scheduler.run(atTime: 2) {
                // Resolve with success at t=5
                let expectedRequest = RegistrationRequestFactory.createAccountRequest(
                    verificationMethod: .recoveryPassword(Stubs.regRecoveryPw),
                    e164: Stubs.e164,
                    authPassword: "", // Doesn't matter for request generation.
                    accountAttributes: Stubs.accountAttributes(),
                    skipDeviceTransfer: true,
                    apnRegistrationId: Stubs.apnsRegistrationId,
                    prekeyBundles: Stubs.prekeyBundles()
                )

                self.mockURLSession.addResponse(
                    TSRequestOWSURLSessionMock.Response(
                        matcher: { request in
                            // The password is generated internally by RegistrationCoordinator.
                            // Extract it so we can check that the same password sent to the server
                            // to register is used later for other requests.
                            authPassword = request.authPassword
                            return request.url == expectedRequest.url
                        },
                        statusCode: 200,
                        bodyData: try! JSONEncoder().encode(identityResponse)
                    ),
                    atTime: 5,
                    on: self.scheduler
                )
            }

            func expectedAuthedAccount() -> AuthedAccount {
                return .explicit(
                    aci: identityResponse.aci,
                    pni: identityResponse.pni,
                    e164: Stubs.e164,
                    deviceId: .primary,
                    authPassword: authPassword
                )
            }

            // When registered at t=5, it should try and sync pre-keys. Succeed at t=6.
            preKeyManagerMock.rotateOneTimePreKeysMock = { auth in
                XCTAssertEqual(self.scheduler.currentTime, 5)
                XCTAssertEqual(auth, expectedAuthedAccount().chatServiceAuth)
                return self.scheduler.promise(resolvingWith: (), atTime: 6)
            }

            // We haven't done a SVR backup; that should happen at t=6. Succeed at t=7.
            svr.generateAndBackupKeysMock = { pin, authMethod, rotateMasterKey in
                XCTAssertEqual(self.scheduler.currentTime, 6)
                XCTAssertEqual(pin, Stubs.pinCode)
                // We don't have a SVR auth credential, it should use chat server creds.
                XCTAssertEqual(authMethod, .chatServerAuth(expectedAuthedAccount()))
                XCTAssertFalse(rotateMasterKey)
                self.svr.hasMasterKey = true
                return self.scheduler.promise(resolvingWith: (), atTime: 7)
            }

            // Once we back up to svr at t=7, we should restore from storage service.
            // Succeed at t=8.
            accountManagerMock.performInitialStorageServiceRestoreMock = { auth in
                XCTAssertEqual(self.scheduler.currentTime, 7)
                XCTAssertEqual(auth.authedAccount, expectedAuthedAccount())
                return self.scheduler.promise(resolvingWith: (), atTime: 8)
            }

            // Once we do the storage service restore at t=8,
            // we will sync account attributes and then we are finished!
            let expectedAttributesRequest = RegistrationRequestFactory.updatePrimaryDeviceAccountAttributesRequest(
                Stubs.accountAttributes(),
                auth: .implicit() // // doesn't matter for url matching
            )
            self.mockURLSession.addResponse(
                TSRequestOWSURLSessionMock.Response(
                    matcher: { request in
                        return request.url == expectedAttributesRequest.url
                    },
                    statusCode: 200,
                    bodyData: nil
                ),
                atTime: 9,
                on: scheduler
            )

            scheduler.runUntilIdle()
            XCTAssertEqual(scheduler.currentTime, 9)

            XCTAssertEqual(nextStep.value, .done)
        }
    }

    // MARK: - SVR Auth Credential Path

    func testSVRAuthCredentialPath_happyPath() {
        executeTest {
            // Run the scheduler for a bit; we don't care about timing these bits.
            scheduler.start()

            // Don't care about timing, just start it.
            setupDefaultAccountAttributes()

            // Set profile info so we skip those steps.
            self.setAllProfileInfo()

            // Put some auth credentials in storage.
            let svr2CredentialCandidates: [SVR2AuthCredential] = [
                Stubs.svr2AuthCredential,
                SVR2AuthCredential(credential: RemoteAttestation.Auth(username: "aaaa", password: "abc")),
                SVR2AuthCredential(credential: RemoteAttestation.Auth(username: "zzzz", password: "xyz")),
                SVR2AuthCredential(credential: RemoteAttestation.Auth(username: "0000", password: "123"))
            ]
            svrAuthCredentialStore.svr2Dict = Dictionary(grouping: svr2CredentialCandidates, by: \.credential.username).mapValues { $0.first! }

            // Get past the opening.
            goThroughOpeningHappyPath(expectedNextStep: .phoneNumberEntry(Stubs.phoneNumberEntryState(mode: mode)))

            // Give it a phone number, which should cause it to check the auth credentials.
            // Match the main auth credential.
            let expectedSVR2CheckRequest = RegistrationRequestFactory.svr2AuthCredentialCheckRequest(
                e164: Stubs.e164,
                credentials: svr2CredentialCandidates
            )
            mockURLSession.addResponse(TSRequestOWSURLSessionMock.Response(
                urlSuffix: expectedSVR2CheckRequest.url!.absoluteString,
                statusCode: 200,
                bodyJson: RegistrationServiceResponses.SVR2AuthCheckResponse(matches: [
                    "\(Stubs.svr2AuthCredential.credential.username):\(Stubs.svr2AuthCredential.credential.password)": .match,
                    "aaaa:abc": .notMatch,
                    "zzzz:xyz": .invalid,
                    "0000:123": .unknown
                ])
            ))

            let nextStep = coordinator.submitE164(Stubs.e164).value

            // At this point, we should be asking for PIN entry so we can use the credential
            // to recover the SVR master key.
            XCTAssertEqual(nextStep, .pinEntry(Stubs.pinEntryStateForSVRAuthCredentialPath(mode: self.mode)))
            // We should have wiped the invalid and unknown credentials.
            let remainingCredentials = svrAuthCredentialStore.svr2Dict
            XCTAssertNotNil(remainingCredentials[Stubs.svr2AuthCredential.credential.username])
            XCTAssertNotNil(remainingCredentials["aaaa"])
            XCTAssertNil(remainingCredentials["zzzz"])
            XCTAssertNil(remainingCredentials["0000"])
            // SVR should be untouched.
            XCTAssertNotNil(svrAuthCredentialStore.svr2Dict[Stubs.svr2AuthCredential.credential.username])

            scheduler.stop()
            scheduler.adjustTime(to: 0)

            // Enter the PIN, which should try and recover from SVR.
            // Once we do that, it should follow the Reg Recovery Password Path.
            let nextStepPromise = coordinator.submitPINCode(Stubs.pinCode)

            // At t=1, resolve the key restoration from SVR and have it start returning the key.
            svr.restoreKeysMock = { pin, authMethod in
                XCTAssertEqual(self.scheduler.currentTime, 0)
                XCTAssertEqual(pin, Stubs.pinCode)
                XCTAssertEqual(authMethod, .svrAuth(Stubs.svr2AuthCredential, backup: nil))
                self.svr.hasMasterKey = true
                return self.scheduler.guarantee(resolvingWith: .success, atTime: 1)
            }

            // At t=1 it should get the latest credentials from SVR.
            self.svr.dataGenerator = {
                XCTAssertEqual(self.scheduler.currentTime, 1)
                switch $0 {
                case .registrationRecoveryPassword:
                    return Stubs.regRecoveryPwData
                case .registrationLock:
                    return Stubs.reglockData
                default:
                    return nil
                }
            }

            // Before registering at t=1, it should ask for push tokens to give the registration.
            pushRegistrationManagerMock.requestPushTokenMock = {
                XCTAssertEqual(self.scheduler.currentTime, 1)
                return self.scheduler.guarantee(resolvingWith: .success(Stubs.apnsRegistrationId), atTime: 2)
            }
            // Every time we register we also ask for prekeys.
            preKeyManagerMock.createPreKeysMock = {
                switch self.scheduler.currentTime {
                case 2:
                    return .value(Stubs.prekeyBundles())
                default:
                    XCTFail("Got unexpected push tokens request")
                    return .init(error: PreKeyError())
                }
            }
            // And we finalize them after.
            preKeyManagerMock.finalizePreKeysMock = { didSucceed in
                switch self.scheduler.currentTime {
                case 3:
                    XCTAssert(didSucceed)
                    return .value(())
                default:
                    XCTFail("Got unexpected push tokens request")
                    return .init(error: PreKeyError())
                }
            }

            // Now still at t=2 it should make a reg recovery pw request, resolve it at t=3.
            let accountIdentityResponse = Stubs.accountIdentityResponse()
            var authPassword: String!
            let expectedRegRecoveryPwRequest = RegistrationRequestFactory.createAccountRequest(
                verificationMethod: .recoveryPassword(Stubs.regRecoveryPw),
                e164: Stubs.e164,
                authPassword: "", // Doesn't matter for request generation.
                accountAttributes: Stubs.accountAttributes(),
                skipDeviceTransfer: true,
                apnRegistrationId: Stubs.apnsRegistrationId,
                prekeyBundles: Stubs.prekeyBundles()
            )
            self.mockURLSession.addResponse(
                TSRequestOWSURLSessionMock.Response(
                    matcher: { request in
                        XCTAssertEqual(self.scheduler.currentTime, 2)
                        authPassword = request.authPassword
                        return request.url == expectedRegRecoveryPwRequest.url
                    },
                    statusCode: 200,
                    bodyJson: accountIdentityResponse
                ),
                atTime: 3,
                on: self.scheduler
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

            // When registered at t=3, it should try and create pre-keys.
            // Resolve at t=4.
            preKeyManagerMock.rotateOneTimePreKeysMock = { auth in
                XCTAssertEqual(self.scheduler.currentTime, 3)
                XCTAssertEqual(auth, expectedAuthedAccount().chatServiceAuth)
                return self.scheduler.promise(resolvingWith: (), atTime: 4)
            }

            // At t=4 once we create pre-keys, we should back up to svr.
            svr.generateAndBackupKeysMock = { (pin: String, authMethod: SVR.AuthMethod, rotateMasterKey: Bool) in
                XCTAssertEqual(self.scheduler.currentTime, 4)
                XCTAssertEqual(pin, Stubs.pinCode)
                XCTAssertEqual(authMethod, .svrAuth(
                    Stubs.svr2AuthCredential,
                    backup: .chatServerAuth(expectedAuthedAccount())
                ))
                XCTAssertFalse(rotateMasterKey)
                return self.scheduler.promise(resolvingWith: (), atTime: 5)
            }

            // At t=5 once we back up to svr, we should restore from storage service.
            accountManagerMock.performInitialStorageServiceRestoreMock = { auth in
                XCTAssertEqual(self.scheduler.currentTime, 5)
                XCTAssertEqual(auth.authedAccount, expectedAuthedAccount())
                return self.scheduler.promise(resolvingWith: (), atTime: 6)
            }

            // And at t=6 once we do the storage service restore,
            // we will sync account attributes and then we are finished!
            let expectedAttributesRequest = RegistrationRequestFactory.updatePrimaryDeviceAccountAttributesRequest(
                Stubs.accountAttributes(),
                auth: .implicit() // doesn't matter for url matching
            )
            self.mockURLSession.addResponse(
                matcher: { request in
                    XCTAssertEqual(self.scheduler.currentTime, 6)
                    return request.url == expectedAttributesRequest.url
                },
                statusCode: 200
            )

            for i in 0...5 {
                scheduler.run(atTime: i) {
                    XCTAssertNil(nextStepPromise.value)
                }
            }

            scheduler.runUntilIdle()
            XCTAssertEqual(scheduler.currentTime, 6)

            XCTAssertEqual(nextStepPromise.value, .done)
        }
    }

    func testSVRAuthCredentialPath_noMatchingCredentials() {
        executeTest {
            // Don't care about timing, just start it.
            scheduler.start()

            // Set profile info so we skip those steps.
            setupDefaultAccountAttributes()

            // Put some auth credentials in storage.
            let credentialCandidates: [SVR2AuthCredential] = [
                Stubs.svr2AuthCredential,
                SVR2AuthCredential(credential: RemoteAttestation.Auth(username: "aaaa", password: "abc")),
                SVR2AuthCredential(credential: RemoteAttestation.Auth(username: "zzzz", password: "xyz")),
                SVR2AuthCredential(credential: RemoteAttestation.Auth(username: "0000", password: "123"))
            ]
            svrAuthCredentialStore.svr2Dict = Dictionary(grouping: credentialCandidates, by: \.credential.username).mapValues { $0.first! }

            // Get past the opening.
            goThroughOpeningHappyPath(expectedNextStep: .phoneNumberEntry(Stubs.phoneNumberEntryState(mode: mode)))

            scheduler.stop()
            scheduler.adjustTime(to: 0)

            // Give it a phone number, which should cause it to check the auth credentials.
            let nextStep = coordinator.submitE164(Stubs.e164)

            // Don't give back any matches at t=2, which means we will want to create a session as a fallback.
            let expectedSVRCheckRequest = RegistrationRequestFactory.svr2AuthCredentialCheckRequest(
                e164: Stubs.e164,
                credentials: credentialCandidates
            )
            mockURLSession.addResponse(
                TSRequestOWSURLSessionMock.Response(
                    urlSuffix: expectedSVRCheckRequest.url!.absoluteString,
                    statusCode: 200,
                    bodyJson: RegistrationServiceResponses.SVR2AuthCheckResponse(matches: [
                        "\(Stubs.svr2AuthCredential.credential.username):\(Stubs.svr2AuthCredential.credential.password)": .notMatch,
                        "aaaa:abc": .notMatch,
                        "zzzz:xyz": .invalid,
                        "0000:123": .unknown
                    ])
                ),
                atTime: 2,
                on: scheduler
            )

            // Once the first request fails, at t=2, it should try an start a session.
            scheduler.run(atTime: 1) {
                // We'll ask for a push challenge, though we don't need to resolve it in this test.
                self.pushRegistrationManagerMock.receivePreAuthChallengeTokenMock = {
                    return Guarantee<String>.pending().0
                }

                // Resolve with a session at time 3.
                self.sessionManager.beginSessionResponse = self.scheduler.guarantee(
                    resolvingWith: .success(Stubs.session(hasSentVerificationCode: false)),
                    atTime: 3
                )
            }

            // Then when it gets back the session at t=3, it should immediately ask for
            // a verification code to be sent.
            scheduler.run(atTime: 3) {
                // Resolve with an updated session at time 4.
                self.sessionManager.requestCodeResponse = self.scheduler.guarantee(
                    resolvingWith: .success(Stubs.session(hasSentVerificationCode: true)),
                    atTime: 4
                )
            }

            pushRegistrationManagerMock.requestPushTokenMock = { .value(.success(Stubs.apnsRegistrationId))}

            scheduler.runUntilIdle()
            XCTAssertEqual(scheduler.currentTime, 4)

            // Now we should expect to be at verification code entry since we already set the phone number.
            XCTAssertEqual(nextStep.value, .verificationCodeEntry(Stubs.verificationCodeEntryState(mode: self.mode)))

            // We should have wipted the invalid and unknown credentials.
            let remainingCredentials = svrAuthCredentialStore.svr2Dict
            XCTAssertNotNil(remainingCredentials[Stubs.svr2AuthCredential.credential.username])
            XCTAssertNotNil(remainingCredentials["aaaa"])
            XCTAssertNil(remainingCredentials["zzzz"])
            XCTAssertNil(remainingCredentials["0000"])
        }
    }

    func testSVRAuthCredentialPath_noMatchingCredentialsThenChangeNumber() {
        executeTest {
            // Don't care about timing, just start it.
            scheduler.start()

            // Set profile info so we skip those steps.
            setupDefaultAccountAttributes()

            // Put some auth credentials in storage.
            let credentialCandidates: [SVR2AuthCredential] = [
                Stubs.svr2AuthCredential
            ]
            svrAuthCredentialStore.svr2Dict = Dictionary(grouping: credentialCandidates, by: \.credential.username).mapValues { $0.first! }

            // Get past the opening.
            goThroughOpeningHappyPath(expectedNextStep: .phoneNumberEntry(Stubs.phoneNumberEntryState(mode: mode)))

            scheduler.stop()
            scheduler.adjustTime(to: 0)

            let originalE164 = E164("+17875550100")!
            let changedE164 = E164("+17875550101")!

            // Give it a phone number, which should cause it to check the auth credentials.
            var nextStep = coordinator.submitE164(originalE164)

            // Don't give back any matches at t=2, which means we will want to create a session as a fallback.
            var expectedSVRCheckRequest = RegistrationRequestFactory.svr2AuthCredentialCheckRequest(
                e164: originalE164,
                credentials: credentialCandidates
            )
            mockURLSession.addResponse(
                TSRequestOWSURLSessionMock.Response(
                    urlSuffix: expectedSVRCheckRequest.url!.absoluteString,
                    statusCode: 200,
                    bodyJson: RegistrationServiceResponses.SVR2AuthCheckResponse(matches: [
                        "\(Stubs.svr2AuthCredential.credential.username):\(Stubs.svr2AuthCredential.credential.password)": .notMatch
                    ])
                ),
                atTime: 2,
                on: scheduler
            )

            // Once the first request fails, at t=2, it should try an start a session.
            scheduler.run(atTime: 1) {
                // We'll ask for a push challenge, though we don't need to resolve it in this test.
                self.pushRegistrationManagerMock.receivePreAuthChallengeTokenMock = {
                    return Guarantee<String>.pending().0
                }

                // Resolve with a session at time 3.
                self.sessionManager.beginSessionResponse = self.scheduler.guarantee(
                    resolvingWith: .success(Stubs.session(e164: originalE164, hasSentVerificationCode: false)),
                    atTime: 3
                )
            }

            // Then when it gets back the session at t=3, it should immediately ask for
            // a verification code to be sent.
            scheduler.run(atTime: 3) {
                // Resolve with an updated session at time 4.
                self.sessionManager.requestCodeResponse = self.scheduler.guarantee(
                    resolvingWith: .success(Stubs.session(hasSentVerificationCode: true)),
                    atTime: 4
                )
            }

            pushRegistrationManagerMock.requestPushTokenMock = { .value(.success(Stubs.apnsRegistrationId))}

            scheduler.runUntilIdle()
            XCTAssertEqual(scheduler.currentTime, 4)

            // Now we should expect to be at verification code entry since we already set the phone number.
            XCTAssertEqual(nextStep.value, .verificationCodeEntry(Stubs.verificationCodeEntryState(mode: self.mode)))

            // We should have wiped the invalid and unknown credentials.
            let remainingCredentials = svrAuthCredentialStore.svr2Dict
            XCTAssertNotNil(remainingCredentials[Stubs.svr2AuthCredential.credential.username])

            // Now change the phone number; this should take us back to phone number entry.
            nextStep = coordinator.requestChangeE164()
            scheduler.runUntilIdle()
            XCTAssertEqual(nextStep.value, .phoneNumberEntry(Stubs.phoneNumberEntryState(mode: mode)))

            // Give it a phone number, which should cause it to check the auth credentials again.
            nextStep = coordinator.submitE164(changedE164)

            // Give a match at t=5, so it registers via SVR auth credential.
            expectedSVRCheckRequest = RegistrationRequestFactory.svr2AuthCredentialCheckRequest(
                e164: changedE164,
                credentials: credentialCandidates
            )
            mockURLSession.addResponse(
                TSRequestOWSURLSessionMock.Response(
                    urlSuffix: expectedSVRCheckRequest.url!.absoluteString,
                    statusCode: 200,
                    bodyJson: RegistrationServiceResponses.SVR2AuthCheckResponse(matches: [
                        "\(Stubs.svr2AuthCredential.credential.username):\(Stubs.svr2AuthCredential.credential.password)": .match
                    ])
                ),
                atTime: 5,
                on: scheduler
            )

            // Now it should ask for PIN entry; we are on the SVR auth credential path.
            scheduler.runUntilIdle()
            XCTAssertEqual(nextStep.value, .pinEntry(Stubs.pinEntryStateForSVRAuthCredentialPath(mode: self.mode)))
        }
    }

    // MARK: - Session Path

    public func testSessionPath_happyPath() {
        executeTest {
            createSessionAndRequestFirstCode()

            scheduler.tick()

            var nextStep: Guarantee<RegistrationStep>!

            // Submit a code at t=5.
            scheduler.run(atTime: 5) {
                nextStep = self.coordinator.submitVerificationCode(Stubs.pinCode)
            }

            // At t=7, give back a verified session.
            self.sessionManager.submitCodeResponse = self.scheduler.guarantee(
                resolvingWith: .success(RegistrationSession(
                    id: Stubs.sessionId,
                    e164: Stubs.e164,
                    receivedDate: date,
                    nextSMS: 0,
                    nextCall: 0,
                    nextVerificationAttempt: nil,
                    allowedToRequestCode: true,
                    requestedInformation: [],
                    hasUnknownChallengeRequiringAppUpdate: false,
                    verified: true
                )),
                atTime: 7
            )

            let accountIdentityResponse = Stubs.accountIdentityResponse()
            var authPassword: String!

            // That means at t=7 it should try and register with the verified
            // session; be ready for that starting at t=6 (but not before).

            // Before registering at t=7, it should ask for push tokens to give the registration.
            pushRegistrationManagerMock.requestPushTokenMock = {
                XCTAssertEqual(self.scheduler.currentTime, 7)
                return self.scheduler.guarantee(resolvingWith: .success(Stubs.apnsRegistrationId), atTime: 8)
            }

            // It should also fetch the prekeys for account creation
            preKeyManagerMock.createPreKeysMock = {
                XCTAssertEqual(self.scheduler.currentTime, 8)
                return self.scheduler.promise(resolvingWith: Stubs.prekeyBundles(), atTime: 9)
            }

            scheduler.run(atTime: 8) {
                let expectedRequest = RegistrationRequestFactory.createAccountRequest(
                    verificationMethod: .sessionId(Stubs.sessionId),
                    e164: Stubs.e164,
                    authPassword: "", // Doesn't matter for request generation.
                    accountAttributes: Stubs.accountAttributes(),
                    skipDeviceTransfer: true,
                    apnRegistrationId: Stubs.apnsRegistrationId,
                    prekeyBundles: Stubs.prekeyBundles()
                )
                // Resolve it at t=10
                self.mockURLSession.addResponse(
                    TSRequestOWSURLSessionMock.Response(
                        matcher: { request in
                            authPassword = request.authPassword
                            return request.url == expectedRequest.url
                        },
                        statusCode: 200,
                        bodyJson: accountIdentityResponse
                    ),
                    atTime: 10,
                    on: self.scheduler
                )
            }

            func expectedAuthedAccount() -> AuthedAccount {
                return .explicit(
                    aci: accountIdentityResponse.aci,
                    pni: accountIdentityResponse.pni,
                    e164: Stubs.e164,
                    deviceId: .primary,
                    authPassword: authPassword
                )
            }

            // Once we are registered at t=10, we should finalize prekeys.
            preKeyManagerMock.finalizePreKeysMock = { didSucceed in
                XCTAssertEqual(self.scheduler.currentTime, 10)
                XCTAssert(didSucceed)
                return self.scheduler.promise(resolvingWith: (), atTime: 11)
            }

            // Then we should try and create one time pre-keys
            // with the credentials we got in the identity response.
            preKeyManagerMock.rotateOneTimePreKeysMock = { auth in
                XCTAssertEqual(self.scheduler.currentTime, 11)
                XCTAssertEqual(auth, expectedAuthedAccount().chatServiceAuth)
                return self.scheduler.promise(resolvingWith: (), atTime: 12)
            }

            scheduler.runUntilIdle()
            XCTAssertEqual(scheduler.currentTime, 12)

            // Now we should ask to create a PIN.
            // No exit allowed since we've already started trying to create the account.
            XCTAssertEqual(nextStep.value, .pinEntry(
                Stubs.pinEntryStateForPostRegCreate(mode: self.mode, exitConfigOverride: .noExitAllowed)
            ))

            // Confirm the pin first.
            nextStep = coordinator.setPINCodeForConfirmation(.stub())
            scheduler.runUntilIdle()
            // No exit allowed since we've already started trying to create the account.
            XCTAssertEqual(nextStep.value, .pinEntry(
                Stubs.pinEntryStateForPostRegConfirm(mode: self.mode, exitConfigOverride: .noExitAllowed)
            ))

            scheduler.adjustTime(to: 0)

            // When we submit the pin, it should backup with SVR.
            nextStep = coordinator.submitPINCode(Stubs.pinCode)

            // Finish the validation at t=1.
            svr.generateAndBackupKeysMock = { pin, authMethod, rotateMasterKey in
                XCTAssertEqual(self.scheduler.currentTime, 0)
                XCTAssertEqual(pin, Stubs.pinCode)
                XCTAssertEqual(authMethod, .chatServerAuth(expectedAuthedAccount()))
                XCTAssertFalse(rotateMasterKey)
                return self.scheduler.promise(resolvingWith: (), atTime: 1)
            }

            // At t=1 once we sync push tokens, we should restore from storage service.
            accountManagerMock.performInitialStorageServiceRestoreMock = { auth in
                XCTAssertEqual(self.scheduler.currentTime, 1)
                XCTAssertEqual(auth.authedAccount, expectedAuthedAccount())
                return self.scheduler.promise(resolvingWith: (), atTime: 2)
            }

            // When registered, we should create pre-keys.
            preKeyManagerMock.rotateOneTimePreKeysMock = { auth in
                XCTAssertEqual(auth, expectedAuthedAccount())
                return .value(())
            }

            // And at t=2 once we do the storage service restore,
            // we will sync account attributes and then we are finished!
            let expectedAttributesRequest = RegistrationRequestFactory.updatePrimaryDeviceAccountAttributesRequest(
                Stubs.accountAttributes(),
                auth: .implicit() // doesn't matter for url matching
            )
            self.mockURLSession.addResponse(
                matcher: { request in
                    XCTAssertEqual(self.scheduler.currentTime, 2)
                    return request.url == expectedAttributesRequest.url
                },
                statusCode: 200
            )

            scheduler.runUntilIdle()
            XCTAssertEqual(scheduler.currentTime, 2)

            XCTAssertEqual(nextStep.value, .done)
        }
    }

    public func testSessionPath_invalidE164() {
        executeTest {
            switch mode {
            case .registering, .changingNumber:
                break
            case .reRegistering:
                // no changing the number when reregistering
                return
            }

            setUpSessionPath()

            let badE164 = E164("+15555555555")!

            // Give it a phone number, which should cause it to start a session.
            let nextStep = coordinator.submitE164(badE164)

            // At t=2, reject for invalid argument (the e164).
            self.sessionManager.beginSessionResponse = self.scheduler.guarantee(
                resolvingWith: .invalidArgument,
                atTime: 2
            )

            scheduler.runUntilIdle()
            XCTAssertEqual(scheduler.currentTime, 2)

            // It should put us on the phone number entry screen again
            // with an error.
            XCTAssertEqual(
                nextStep.value,
                .phoneNumberEntry(
                    Stubs.phoneNumberEntryState(
                        mode: mode,
                        previouslyEnteredE164: badE164,
                        withValidationErrorFor: .invalidArgument
                    )
                )
            )
        }
    }

    public func testSessionPath_rateLimitSessionCreation() {
        executeTest {
            setUpSessionPath()

            let retryTimeInterval: TimeInterval = 5

            // Give it a phone number, which should cause it to start a session.
            let nextStep = coordinator.submitE164(Stubs.e164)

            // At t=2, reject with a rate limit.
            self.sessionManager.beginSessionResponse = self.scheduler.guarantee(
                resolvingWith: .retryAfter(retryTimeInterval),
                atTime: 2
            )

            scheduler.runUntilIdle()
            XCTAssertEqual(scheduler.currentTime, 2)

            // It should put us on the phone number entry screen again
            // with an error.
            XCTAssertEqual(
                nextStep.value,
                .phoneNumberEntry(
                    Stubs.phoneNumberEntryState(
                        mode: mode,
                        previouslyEnteredE164: Stubs.e164,
                        withValidationErrorFor: .retryAfter(retryTimeInterval)
                    )
                )
            )
        }
    }

    public func testSessionPath_cantSendFirstSMSCode() {
        executeTest {
            setUpSessionPath()

            // Give it a phone number, which should cause it to start a session.
            let nextStep = coordinator.submitE164(Stubs.e164)

            // At t=2, give back a session, but with SMS code rate limiting already.
            self.sessionManager.beginSessionResponse = self.scheduler.guarantee(
                resolvingWith: .success(RegistrationSession(
                    id: Stubs.sessionId,
                    e164: Stubs.e164,
                    receivedDate: date,
                    nextSMS: 10,
                    nextCall: 0,
                    nextVerificationAttempt: nil,
                    allowedToRequestCode: true,
                    requestedInformation: [],
                    hasUnknownChallengeRequiringAppUpdate: false,
                    verified: false
                )),
                atTime: 2
            )

            // It should put us on the verification code entry screen with an error.
            scheduler.runUntilIdle()
            XCTAssertEqual(scheduler.currentTime, 2)
            XCTAssertEqual(
                nextStep.value,
                .verificationCodeEntry(Stubs.verificationCodeEntryState(
                    mode: self.mode,
                    nextSMS: 10,
                    nextVerificationAttempt: nil,
                    validationError: .smsResendTimeout
                ))
            )
        }
    }

    public func testSessionPath_landline() {
        executeTest {
            setUpSessionPath()

            // Give it a phone number, which should cause it to start a session.
            var nextStep = coordinator.submitE164(Stubs.e164)

            // At t=2, give back a session that's ready to go.
            self.sessionManager.beginSessionResponse = self.scheduler.guarantee(
                resolvingWith: .success(RegistrationSession(
                    id: Stubs.sessionId,
                    e164: Stubs.e164,
                    receivedDate: date,
                    nextSMS: 0,
                    nextCall: nil, /* initially calling unavailable */
                    nextVerificationAttempt: nil,
                    allowedToRequestCode: true,
                    requestedInformation: [],
                    hasUnknownChallengeRequiringAppUpdate: false,
                    verified: false
                )),
                atTime: 2
            )

            // Once we get that session at t=2, we should try and send a code.
            // Be ready for that starting at t=1 (but not before).
            scheduler.run(atTime: 1) {
                // Resolve with a transport error at time 3,
                // and no next verification attempt on the session,
                // so it counts as transport failure with no code sent.
                self.sessionManager.requestCodeResponse = self.scheduler.guarantee(
                    resolvingWith: .transportError(RegistrationSession(
                        id: Stubs.sessionId,
                        e164: Stubs.e164,
                        receivedDate: self.date,
                        nextSMS: nil,
                        nextCall: 0, /* now sms unavailable but calling is */
                        nextVerificationAttempt: nil,
                        allowedToRequestCode: true,
                        requestedInformation: [],
                        hasUnknownChallengeRequiringAppUpdate: false,
                        verified: false
                    )),
                    atTime: 3
                )
            }

            // At t=3 we should get back the code entry step,
            // with a validation error for the sms transport.
            scheduler.runUntilIdle()
            XCTAssertEqual(scheduler.currentTime, 3)
            XCTAssertEqual(nextStep.value, .verificationCodeEntry(Stubs.verificationCodeEntryState(
                mode: self.mode,
                nextSMS: nil,
                nextVerificationAttempt: nil,
                validationError: .failedInitialTransport(failedTransport: .sms)
            )))

            // If we resend via voice, that should put us in a happy path.
            // Resolve with a success at t=4.
            self.sessionManager.didRequestCode = false
            self.sessionManager.requestCodeResponse = self.scheduler.guarantee(
                resolvingWith: .success(RegistrationSession(
                    id: Stubs.sessionId,
                    e164: Stubs.e164,
                    receivedDate: self.date,
                    nextSMS: 0,
                    nextCall: 0,
                    nextVerificationAttempt: 0,
                    allowedToRequestCode: true,
                    requestedInformation: [],
                    hasUnknownChallengeRequiringAppUpdate: false,
                    verified: false
                )),
                atTime: 4
            )

            nextStep = coordinator.requestVoiceCode()

            // At t=4 we should get back the code entry step.
            scheduler.runUntilIdle()
            XCTAssertEqual(scheduler.currentTime, 4)
            XCTAssert(sessionManager.didRequestCode)
            XCTAssertEqual(nextStep.value, .verificationCodeEntry(Stubs.verificationCodeEntryState(mode: self.mode)))
        }
    }

    public func testSessionPath_landline_submitCodeWithNoneSentYet() {
        executeTest {
            setUpSessionPath()

            // Give it a phone number, which should cause it to start a session.
            var nextStep = coordinator.submitE164(Stubs.e164)

            // At t=2, give back a session that's ready to go.
            self.sessionManager.beginSessionResponse = self.scheduler.guarantee(
                resolvingWith: .success(RegistrationSession(
                    id: Stubs.sessionId,
                    e164: Stubs.e164,
                    receivedDate: date,
                    nextSMS: 0,
                    nextCall: 0,
                    nextVerificationAttempt: nil,
                    allowedToRequestCode: true,
                    requestedInformation: [],
                    hasUnknownChallengeRequiringAppUpdate: false,
                    verified: false
                )),
                atTime: 2
            )

            // Once we get that session at t=2, we should try and send a code.
            // Be ready for that starting at t=1 (but not before).
            scheduler.run(atTime: 1) {
                // Resolve with a transport error at time 3,
                // and no next verification attempt on the session,
                // so it counts as transport failure with no code sent.
                self.sessionManager.requestCodeResponse = self.scheduler.guarantee(
                    resolvingWith: .transportError(RegistrationSession(
                        id: Stubs.sessionId,
                        e164: Stubs.e164,
                        receivedDate: self.date,
                        nextSMS: 0,
                        nextCall: 0,
                        nextVerificationAttempt: nil,
                        allowedToRequestCode: true,
                        requestedInformation: [],
                        hasUnknownChallengeRequiringAppUpdate: false,
                        verified: false
                    )),
                    atTime: 3
                )
            }

            // At t=3 we should get back the code entry step,
            // with a validation error for the sms transport.
            scheduler.runUntilIdle()
            XCTAssertEqual(scheduler.currentTime, 3)
            XCTAssertEqual(nextStep.value, .verificationCodeEntry(Stubs.verificationCodeEntryState(
                mode: self.mode,
                nextVerificationAttempt: nil,
                validationError: .failedInitialTransport(failedTransport: .sms)
            )))

            // If we try and submit a code, we should get an error sheet
            // because a code never got sent in the first place.
            // (If the server rejects the submission, which it obviously should).
            self.sessionManager.submitCodeResponse = self.scheduler.guarantee(
                resolvingWith: .disallowed(RegistrationSession(
                    id: Stubs.sessionId,
                    e164: Stubs.e164,
                    receivedDate: date,
                    nextSMS: 0,
                    nextCall: 0,
                    nextVerificationAttempt: nil,
                    allowedToRequestCode: true,
                    requestedInformation: [],
                    hasUnknownChallengeRequiringAppUpdate: false,
                    verified: false
                )),
                atTime: 4
            )

            nextStep = coordinator.submitVerificationCode(Stubs.verificationCode)

            scheduler.runUntilIdle()
            XCTAssertEqual(scheduler.currentTime, 4)

            // The server says no code is available to submit. We know
            // we never sent a code, so show a unique error for that
            // but keep the user on the code entry screen so they can
            // retry sending a code with a transport method of their choice.

            XCTAssertEqual(
                nextStep.value,
                .showErrorSheet(.submittingVerificationCodeBeforeAnyCodeSent)
            )
            nextStep = coordinator.nextStep()
            scheduler.runUntilIdle()
            XCTAssertEqual(
                nextStep.value,
                .verificationCodeEntry(Stubs.verificationCodeEntryState(
                    mode: self.mode,
                    nextVerificationAttempt: nil,
                    validationError: .failedInitialTransport(failedTransport: .sms)
                ))
            )
        }
    }

    public func testSessionPath_rateLimitFirstSMSCode() {
        executeTest {
            setUpSessionPath()

            // Give it a phone number, which should cause it to start a session.
            let nextStep = coordinator.submitE164(Stubs.e164)

            // We'll ask for a push challenge, though we won't resolve it in this test.
            self.pushRegistrationManagerMock.receivePreAuthChallengeTokenMock = {
                return Guarantee<String>.pending().0
            }

            // At t=2, give back a session that's ready to go.
            self.sessionManager.beginSessionResponse = self.scheduler.guarantee(
                resolvingWith: .success(RegistrationSession(
                    id: Stubs.sessionId,
                    e164: Stubs.e164,
                    receivedDate: date,
                    nextSMS: 0,
                    nextCall: 0,
                    nextVerificationAttempt: nil,
                    allowedToRequestCode: true,
                    requestedInformation: [],
                    hasUnknownChallengeRequiringAppUpdate: false,
                    verified: false
                )),
                atTime: 2
            )

            // Once we get that session at t=2, we should try and send a code.
            // Be ready for that starting at t=1 (but not before).
            scheduler.run(atTime: 1) {
                // Reject with a timeout.
                self.sessionManager.requestCodeResponse = self.scheduler.guarantee(
                    resolvingWith: .retryAfterTimeout(RegistrationSession(
                        id: Stubs.sessionId,
                        e164: Stubs.e164,
                        receivedDate: self.date,
                        nextSMS: 10,
                        nextCall: 0,
                        nextVerificationAttempt: nil,
                        allowedToRequestCode: true,
                        requestedInformation: [],
                        hasUnknownChallengeRequiringAppUpdate: false,
                        verified: false
                    )),
                    atTime: 3
                )
            }

            // It should put us on the phone number entry screen again
            // with an error.
            scheduler.runUntilIdle()
            XCTAssertEqual(scheduler.currentTime, 3)
            XCTAssertEqual(
                nextStep.value,
                .phoneNumberEntry(
                    Stubs.phoneNumberEntryState(
                        mode: mode,
                        previouslyEnteredE164: Stubs.e164,
                        withValidationErrorFor: .retryAfter(10)
                    )
                )
            )
        }
    }

    public func testSessionPath_changeE164() {
        executeTest {
            setUpSessionPath()

            let originalE164 = E164("+17875550100")!
            let changedE164 = E164("+17875550101")!

            // Give it a phone number, which should cause it to start a session.
            var nextStep = coordinator.submitE164(originalE164)

            // We'll ask for a push challenge, though we won't resolve it in this test.
            self.pushRegistrationManagerMock.receivePreAuthChallengeTokenMock = {
                return Guarantee<String>.pending().0
            }

            // At t=2, give back a session that's ready to go.
            self.sessionManager.beginSessionResponse = self.scheduler.guarantee(
                resolvingWith: .success(RegistrationSession(
                    id: Stubs.sessionId,
                    e164: originalE164,
                    receivedDate: date,
                    nextSMS: 0,
                    nextCall: 0,
                    nextVerificationAttempt: nil,
                    allowedToRequestCode: true,
                    requestedInformation: [],
                    hasUnknownChallengeRequiringAppUpdate: false,
                    verified: false
                )),
                atTime: 2
            )

            // Once we get that session at t=2, we should try and send a code.
            // Be ready for that starting at t=1 (but not before).
            scheduler.run(atTime: 1) {
                // Give back a session with a sent code.
                self.sessionManager.requestCodeResponse = self.scheduler.guarantee(
                    resolvingWith: .success(RegistrationSession(
                        id: Stubs.sessionId,
                        e164: originalE164,
                        receivedDate: self.date,
                        nextSMS: 0,
                        nextCall: 0,
                        nextVerificationAttempt: 0,
                        allowedToRequestCode: true,
                        requestedInformation: [],
                        hasUnknownChallengeRequiringAppUpdate: false,
                        verified: false
                    )),
                    atTime: 3
                )
            }

            // We should be on the verification code entry screen.
            scheduler.runUntilIdle()
            XCTAssertEqual(scheduler.currentTime, 3)
            XCTAssertEqual(
                nextStep.value,
                .verificationCodeEntry(
                    Stubs.verificationCodeEntryState(mode: self.mode, e164: originalE164)
                )
            )

            // Ask to change the number; this should put us back on phone number entry.
            nextStep = coordinator.requestChangeE164()
            scheduler.runUntilIdle()
            XCTAssertEqual(
                nextStep.value,
                .phoneNumberEntry(Stubs.phoneNumberEntryState(mode: mode))
            )

            // Give it the new phone number, which should cause it to start a session.
            nextStep = coordinator.submitE164(changedE164)

            // We'll ask for a push challenge, though we won't resolve it in this test.
            self.pushRegistrationManagerMock.receivePreAuthChallengeTokenMock = {
                return Guarantee<String>.pending().0
            }

            // At t=5, give back a session that's ready to go.
            self.sessionManager.beginSessionResponse = self.scheduler.guarantee(
                resolvingWith: .success(RegistrationSession(
                    id: Stubs.sessionId,
                    e164: changedE164,
                    receivedDate: date,
                    nextSMS: 0,
                    nextCall: 0,
                    nextVerificationAttempt: nil,
                    allowedToRequestCode: true,
                    requestedInformation: [],
                    hasUnknownChallengeRequiringAppUpdate: false,
                    verified: false
                )),
                atTime: 5
            )

            // Once we get that session at t=5, we should try and send a code.
            // Be ready for that starting at t=4 (but not before).
            scheduler.run(atTime: 4) {
                // Give back a session with a sent code.
                self.sessionManager.requestCodeResponse = self.scheduler.guarantee(
                    resolvingWith: .success(RegistrationSession(
                        id: Stubs.sessionId,
                        e164: changedE164,
                        receivedDate: self.date,
                        nextSMS: 0,
                        nextCall: 0,
                        nextVerificationAttempt: 0,
                        allowedToRequestCode: true,
                        requestedInformation: [],
                        hasUnknownChallengeRequiringAppUpdate: false,
                        verified: false
                    )),
                    atTime: 6
                )
            }

            // We should be on the verification code entry screen.
            scheduler.runUntilIdle()
            XCTAssertEqual(scheduler.currentTime, 6)
            XCTAssertEqual(
                nextStep.value,
                .verificationCodeEntry(
                    Stubs.verificationCodeEntryState(mode: self.mode, e164: changedE164)
                )
            )
        }
    }

    public func testSessionPath_captchaChallenge() {
        executeTest {
            setUpSessionPath()

            // Give it a phone number, which should cause it to start a session.
            var nextStep = coordinator.submitE164(Stubs.e164)

            // At t=2, give back a session with a captcha challenge.
            self.sessionManager.beginSessionResponse = self.scheduler.guarantee(
                resolvingWith: .success(RegistrationSession(
                    id: Stubs.sessionId,
                    e164: Stubs.e164,
                    receivedDate: date,
                    nextSMS: 0,
                    nextCall: 0,
                    nextVerificationAttempt: nil,
                    allowedToRequestCode: false,
                    requestedInformation: [.captcha],
                    hasUnknownChallengeRequiringAppUpdate: false,
                    verified: false
                )),
                atTime: 2
            )

            // Once we get that session at t=2, we should get a captcha step back.
            scheduler.runUntilIdle()
            XCTAssertEqual(scheduler.currentTime, 2)
            XCTAssertEqual(nextStep.value, .captchaChallenge)

            scheduler.tick()

            // Submit a captcha challenge at t=4.
            scheduler.run(atTime: 4) {
                nextStep = self.coordinator.submitCaptcha(Stubs.captchaToken)
            }

            // At t=6, give back a session without the challenge.
            self.sessionManager.fulfillChallengeResponse = self.scheduler.guarantee(
                resolvingWith: .success(RegistrationSession(
                    id: Stubs.sessionId,
                    e164: Stubs.e164,
                    receivedDate: date,
                    nextSMS: 0,
                    nextCall: 0,
                    nextVerificationAttempt: nil,
                    allowedToRequestCode: true,
                    requestedInformation: [],
                    hasUnknownChallengeRequiringAppUpdate: false,
                    verified: false
                )),
                atTime: 6
            )

            // That means at t=6 it should try and send a code;
            // be ready for that starting at t=5 (but not before).
            scheduler.run(atTime: 5) {
                // Resolve with a session at time 7.
                // The session has a sent code, but requires a challenge to send
                // a code again. That should be ignored until we ask to send another code.
                self.sessionManager.requestCodeResponse = self.scheduler.guarantee(
                    resolvingWith: .success(RegistrationSession(
                        id: Stubs.sessionId,
                        e164: Stubs.e164,
                        receivedDate: self.date,
                        nextSMS: 0,
                        nextCall: 0,
                        nextVerificationAttempt: 0,
                        allowedToRequestCode: false,
                        requestedInformation: [.captcha],
                        hasUnknownChallengeRequiringAppUpdate: false,
                        verified: false
                    )),
                    atTime: 7
                )
            }

            // At t=7, we should get back the code entry step.
            scheduler.runUntilIdle()
            XCTAssertEqual(scheduler.currentTime, 7)
            XCTAssertEqual(nextStep.value, .verificationCodeEntry(Stubs.verificationCodeEntryState(mode: self.mode)))

            // Now try and resend a code, which should hit us with the captcha challenge immediately.
            scheduler.start()
            XCTAssertEqual(coordinator.requestSMSCode().value, .captchaChallenge)
            scheduler.stop()

            // Submit a captcha challenge at t=8.
            scheduler.run(atTime: 8) {
                nextStep = self.coordinator.submitCaptcha(Stubs.captchaToken)
            }

            // At t=10, give back a session without the challenge.
            self.sessionManager.fulfillChallengeResponse = self.scheduler.guarantee(
                resolvingWith: .success(RegistrationSession(
                    id: Stubs.sessionId,
                    e164: Stubs.e164,
                    receivedDate: date,
                    nextSMS: 0,
                    nextCall: 0,
                    nextVerificationAttempt: 0,
                    allowedToRequestCode: true,
                    requestedInformation: [],
                    hasUnknownChallengeRequiringAppUpdate: false,
                    verified: false
                )),
                atTime: 10
            )

            // This means at t=10 when we fulfill the challenge, it should
            // immediately try and send the code that couldn't be sent before because
            // of the challenge.
            // Reply to this at t=12.
            self.date = date.addingTimeInterval(10)
            let secondCodeDate = date
            scheduler.run(atTime: 9) {
                self.sessionManager.requestCodeResponse = self.scheduler.guarantee(
                    resolvingWith: .success(RegistrationSession(
                        id: Stubs.sessionId,
                        e164: Stubs.e164,
                        receivedDate: secondCodeDate,
                        nextSMS: 0,
                        nextCall: 0,
                        nextVerificationAttempt: 0,
                        allowedToRequestCode: true,
                        requestedInformation: [],
                        hasUnknownChallengeRequiringAppUpdate: false,
                        verified: false
                    )),
                    atTime: 12
                )
            }

            // Ensure that at t=11, before we've gotten the request code response,
            // we don't have a result yet.
            scheduler.run(atTime: 11) {
                XCTAssertNil(nextStep.value)
            }

            // Once all is done, we should have a new code and be back on the code
            // entry screen.
            // TODO[Registration]: test that the "next SMS code" state is properly set
            // given the new sms code date above.
            scheduler.runUntilIdle()
            XCTAssertEqual(scheduler.currentTime, 12)
            XCTAssertEqual(nextStep.value, .verificationCodeEntry(Stubs.verificationCodeEntryState(mode: self.mode)))
        }
    }

    public func testSessionPath_pushChallenge() {
        executeTest {
            setUpSessionPath()

            pushRegistrationManagerMock.requestPushTokenMock = {
                XCTAssertEqual(self.scheduler.currentTime, 0)
                return .value(.success(Stubs.apnsRegistrationId))
            }

            // Give it a phone number, which should cause it to start a session.
            let nextStep = coordinator.submitE164(Stubs.e164)

            // Prepare to provide the challenge token.
            let (challengeTokenPromise, challengeTokenFuture) = Guarantee<String>.pending()
            pushRegistrationManagerMock.receivePreAuthChallengeTokenMock = {
                XCTAssertEqual(self.scheduler.currentTime, 2)
                return challengeTokenPromise
            }

            // At t=2, give back a session with a push challenge.
            self.sessionManager.beginSessionResponse = self.scheduler.guarantee(
                resolvingWith: .success(RegistrationSession(
                    id: Stubs.sessionId,
                    e164: Stubs.e164,
                    receivedDate: self.date,
                    nextSMS: 0,
                    nextCall: 0,
                    nextVerificationAttempt: nil,
                    allowedToRequestCode: false,
                    requestedInformation: [.pushChallenge],
                    hasUnknownChallengeRequiringAppUpdate: false,
                    verified: false
                )),
                atTime: 2
            )

            // At t=3, give the push challenge token. Also prepare to handle its usage, and the
            // resulting request for another SMS code.
            scheduler.run(atTime: 3) {
                challengeTokenFuture.resolve("a pre-auth challenge token")

                self.sessionManager.fulfillChallengeResponse = self.scheduler.guarantee(
                    resolvingWith: .success(RegistrationSession(
                        id: Stubs.sessionId,
                        e164: Stubs.e164,
                        receivedDate: self.date,
                        nextSMS: 0,
                        nextCall: 0,
                        nextVerificationAttempt: 0,
                        allowedToRequestCode: true,
                        requestedInformation: [],
                        hasUnknownChallengeRequiringAppUpdate: false,
                        verified: false
                    )),
                    atTime: 4
                )

                self.sessionManager.requestCodeResponse = self.scheduler.guarantee(
                    resolvingWith: .success(RegistrationSession(
                        id: Stubs.sessionId,
                        e164: Stubs.e164,
                        receivedDate: self.date,
                        nextSMS: 0,
                        nextCall: 0,
                        nextVerificationAttempt: 0,
                        allowedToRequestCode: false,
                        requestedInformation: [.pushChallenge],
                        hasUnknownChallengeRequiringAppUpdate: false,
                        verified: false
                    )),
                    atTime: 6
                )

                // We should still be waiting.
                XCTAssertNil(nextStep.value)
            }

            scheduler.runUntilIdle()
            XCTAssertEqual(scheduler.currentTime, 6)

            XCTAssertEqual(
                nextStep.value,
                .verificationCodeEntry(Stubs.verificationCodeEntryState(mode: self.mode))
            )
            XCTAssertEqual(
                sessionManager.latestChallengeFulfillment,
                .pushChallenge("a pre-auth challenge token")
            )
        }
    }

    public func testSessionPath_pushChallengeTimeoutAfterResolutionThatTakesTooLong() {
        executeTest {
            let sessionStartsAt = 2

            setUpSessionPath()

            dateProvider = { self.date.addingTimeInterval(TimeInterval(self.scheduler.currentTime)) }

            pushRegistrationManagerMock.requestPushTokenMock = {
                XCTAssertEqual(self.scheduler.currentTime, 0)
                return .value(.success(Stubs.apnsRegistrationId))
            }

            // Give it a phone number, which should cause it to start a session.
            let nextStep = coordinator.submitE164(Stubs.e164)

            // Prepare to provide the challenge token.
            let (challengeTokenPromise, challengeTokenFuture) = Guarantee<String>.pending()
            var receivePreAuthChallengeTokenCount = 0
            pushRegistrationManagerMock.receivePreAuthChallengeTokenMock = {
                switch receivePreAuthChallengeTokenCount {
                case 0, 1:
                    XCTAssertEqual(self.scheduler.currentTime, sessionStartsAt)
                case 2:
                    let minWaitTime = Int(RegistrationCoordinatorImpl.Constants.pushTokenMinWaitTime / self.scheduler.secondsPerTick)
                    XCTAssertEqual(self.scheduler.currentTime, sessionStartsAt + minWaitTime)
                default:
                    XCTFail("Calling preAuthChallengeToken too many times")
                }
                receivePreAuthChallengeTokenCount += 1
                return challengeTokenPromise
            }

            // At t=2, give back a session with a push challenge.
            self.sessionManager.beginSessionResponse = self.scheduler.guarantee(
                resolvingWith: .success(RegistrationSession(
                    id: Stubs.sessionId,
                    e164: Stubs.e164,
                    receivedDate: self.date,
                    nextSMS: 0,
                    nextCall: 0,
                    nextVerificationAttempt: nil,
                    allowedToRequestCode: false,
                    requestedInformation: [.pushChallenge],
                    hasUnknownChallengeRequiringAppUpdate: false,
                    verified: false
                )),
                atTime: sessionStartsAt
            )

            // Take too long to resolve with the challenge token.
            let pushChallengeTimeout = Int(RegistrationCoordinatorImpl.Constants.pushTokenTimeout / scheduler.secondsPerTick)
            let receiveChallengeTokenTime = sessionStartsAt + pushChallengeTimeout + 1
            scheduler.run(atTime: receiveChallengeTokenTime) {
                challengeTokenFuture.resolve("challenge token that should be ignored")
            }

            scheduler.advance(to: sessionStartsAt + pushChallengeTimeout - 1)
            XCTAssertNil(nextStep.value)

            scheduler.tick()
            XCTAssertEqual(nextStep.value, .showErrorSheet(.sessionInvalidated))

            scheduler.runUntilIdle()
            XCTAssertEqual(scheduler.currentTime, receiveChallengeTokenTime)

            // One time to set up, one time for the min wait time, one time
            // for the full timeout.
            XCTAssertEqual(receivePreAuthChallengeTokenCount, 3)
        }
    }

    public func testSessionPath_pushChallengeTimeoutAfterNoResolution() {
        executeTest {
            let pushChallengeMinTime = Int(RegistrationCoordinatorImpl.Constants.pushTokenMinWaitTime / scheduler.secondsPerTick)
            let pushChallengeTimeout = Int(RegistrationCoordinatorImpl.Constants.pushTokenTimeout / scheduler.secondsPerTick)

            let sessionStartsAt = 2
            setUpSessionPath()

            pushRegistrationManagerMock.requestPushTokenMock = {
                XCTAssertEqual(self.scheduler.currentTime, 0)
                return .value(.success(Stubs.apnsRegistrationId))
            }

            // Give it a phone number, which should cause it to start a session.
            let nextStep = coordinator.submitE164(Stubs.e164)

            // We'll never provide a challenge token and will just leave it around forever.
            let (challengeTokenPromise, _) = Guarantee<String>.pending()
            var receivePreAuthChallengeTokenCount = 0
            pushRegistrationManagerMock.receivePreAuthChallengeTokenMock = {
                switch receivePreAuthChallengeTokenCount {
                case 0, 1:
                    XCTAssertEqual(self.scheduler.currentTime, sessionStartsAt)
                case 2:
                    XCTAssertEqual(self.scheduler.currentTime, sessionStartsAt + pushChallengeMinTime)
                default:
                    XCTFail("Calling preAuthChallengeToken too many times")
                }
                receivePreAuthChallengeTokenCount += 1
                return challengeTokenPromise
            }

            // At t=2, give back a session with a push challenge.
            self.sessionManager.beginSessionResponse = self.scheduler.guarantee(
                resolvingWith: .success(RegistrationSession(
                    id: Stubs.sessionId,
                    e164: Stubs.e164,
                    receivedDate: self.date,
                    nextSMS: 0,
                    nextCall: 0,
                    nextVerificationAttempt: nil,
                    allowedToRequestCode: false,
                    requestedInformation: [.pushChallenge],
                    hasUnknownChallengeRequiringAppUpdate: false,
                    verified: false
                )),
                atTime: 2
            )

            scheduler.runUntilIdle()
            XCTAssertEqual(scheduler.currentTime, 2 + pushChallengeMinTime + pushChallengeTimeout)
            XCTAssertEqual(nextStep.value, .showErrorSheet(.sessionInvalidated))

            // One time to set up, one time for the min wait time, one time
            // for the full timeout.
            XCTAssertEqual(receivePreAuthChallengeTokenCount, 3)
        }
    }

    public func testSessionPath_pushChallengeWithoutPushNotificationsAvailable() {
        executeTest {
            setUpSessionPath()

            pushRegistrationManagerMock.requestPushTokenMock = {
                XCTAssertEqual(self.scheduler.currentTime, 0)
                return .value(.pushUnsupported(description: ""))
            }

            // Give it a phone number, which should cause it to start a session.
            let nextStep = coordinator.submitE164(Stubs.e164)

            // We'll ask for a push challenge, though we don't need to resolve it in this test.
            self.pushRegistrationManagerMock.receivePreAuthChallengeTokenMock = {
                XCTAssertEqual(self.scheduler.currentTime, 2)
                return Guarantee<String>.pending().0
            }

            // Require a push challenge, which we won't be able to answer.
            self.sessionManager.beginSessionResponse = self.scheduler.guarantee(
                resolvingWith: .success(RegistrationSession(
                    id: Stubs.sessionId,
                    e164: Stubs.e164,
                    receivedDate: self.date,
                    nextSMS: 0,
                    nextCall: 0,
                    nextVerificationAttempt: nil,
                    allowedToRequestCode: false,
                    requestedInformation: [.pushChallenge],
                    hasUnknownChallengeRequiringAppUpdate: false,
                    verified: false
                )),
                atTime: 2
            )

            scheduler.runUntilIdle()
            XCTAssertEqual(scheduler.currentTime, 2)
            XCTAssertEqual(
                nextStep.value,
                .phoneNumberEntry(Stubs.phoneNumberEntryState(
                    mode: mode,
                    previouslyEnteredE164: Stubs.e164
                ))
            )
            XCTAssertNil(sessionManager.latestChallengeFulfillment)
        }
    }

    public func testSessionPath_preferPushChallengesIfWeCanAnswerThemImmediately() {
        executeTest {
            setUpSessionPath()

            pushRegistrationManagerMock.requestPushTokenMock = {
                XCTAssertEqual(self.scheduler.currentTime, 0)
                return .value(.success(Stubs.apnsRegistrationId))
            }

            // Be ready to provide the push challenge token as soon as it's needed.
            pushRegistrationManagerMock.receivePreAuthChallengeTokenMock = {
                XCTAssertEqual(self.scheduler.currentTime, 2)
                return .value("a pre-auth challenge token")
            }

            // Give it a phone number, which should cause it to start a session.
            let nextStep = coordinator.submitE164(Stubs.e164)

            // At t=2, give back a session with multiple challenges.
            sessionManager.beginSessionResponse = self.scheduler.guarantee(
                resolvingWith: .success(RegistrationSession(
                    id: Stubs.sessionId,
                    e164: Stubs.e164,
                    receivedDate: self.date,
                    nextSMS: 0,
                    nextCall: 0,
                    nextVerificationAttempt: nil,
                    allowedToRequestCode: false,
                    requestedInformation: [.captcha, .pushChallenge],
                    hasUnknownChallengeRequiringAppUpdate: false,
                    verified: false
                )),
                atTime: 2
            )

            // Be ready to handle push challenges as soon as we can.
            scheduler.run(atTime: 2) {
                self.sessionManager.fulfillChallengeResponse = self.scheduler.guarantee(
                    resolvingWith: .success(RegistrationSession(
                        id: Stubs.sessionId,
                        e164: Stubs.e164,
                        receivedDate: self.date,
                        nextSMS: 0,
                        nextCall: 0,
                        nextVerificationAttempt: 0,
                        allowedToRequestCode: true,
                        requestedInformation: [],
                        hasUnknownChallengeRequiringAppUpdate: false,
                        verified: false
                    )),
                    atTime: 4
                )
                self.sessionManager.requestCodeResponse = self.scheduler.guarantee(
                    resolvingWith: .success(RegistrationSession(
                        id: Stubs.sessionId,
                        e164: Stubs.e164,
                        receivedDate: self.date,
                        nextSMS: 0,
                        nextCall: 0,
                        nextVerificationAttempt: 0,
                        allowedToRequestCode: true,
                        requestedInformation: [],
                        hasUnknownChallengeRequiringAppUpdate: false,
                        verified: false
                    )),
                    atTime: 5
                )
            }

            // We should still be waiting at t=4.
            scheduler.run(atTime: 4) {
                XCTAssertNil(nextStep.value)
            }

            scheduler.runUntilIdle()
            XCTAssertEqual(scheduler.currentTime, 5)

            XCTAssertEqual(
                nextStep.value,
                .verificationCodeEntry(Stubs.verificationCodeEntryState(mode: self.mode))
            )
            XCTAssertEqual(
                sessionManager.latestChallengeFulfillment,
                .pushChallenge("a pre-auth challenge token")
            )
        }
    }

    public func testSessionPath_prefersCaptchaChallengesIfWeCannotAnswerPushChallengeQuickly() {
        executeTest {
            setUpSessionPath()

            pushRegistrationManagerMock.requestPushTokenMock = {
                XCTAssertEqual(self.scheduler.currentTime, 0)
                return .value(.success(Stubs.apnsRegistrationId))
            }

            // Give it a phone number, which should cause it to start a session.
            let nextStep = coordinator.submitE164(Stubs.e164)

            // Prepare to provide the challenge token.
            let (challengeTokenPromise, challengeTokenFuture) = Guarantee<String>.pending()
            pushRegistrationManagerMock.receivePreAuthChallengeTokenMock = {
                XCTAssertEqual(self.scheduler.currentTime, 2)
                return challengeTokenPromise
            }

            // At t=2, give back a session with multiple challenges.
            self.sessionManager.beginSessionResponse = self.scheduler.guarantee(
                resolvingWith: .success(RegistrationSession(
                    id: Stubs.sessionId,
                    e164: Stubs.e164,
                    receivedDate: date,
                    nextSMS: 0,
                    nextCall: 0,
                    nextVerificationAttempt: nil,
                    allowedToRequestCode: false,
                    requestedInformation: [.pushChallenge, .captcha],
                    hasUnknownChallengeRequiringAppUpdate: false,
                    verified: false
                )),
                atTime: 2
            )

            // Take too long to resolve with the challenge token.
            let pushChallengeTimeout = Int(RegistrationCoordinatorImpl.Constants.pushTokenTimeout / scheduler.secondsPerTick)
            let receiveChallengeTokenTime = pushChallengeTimeout + 1
            scheduler.run(atTime: receiveChallengeTokenTime - 1) {
                self.date = self.date.addingTimeInterval(TimeInterval(receiveChallengeTokenTime))
            }
            scheduler.run(atTime: receiveChallengeTokenTime) {
                challengeTokenFuture.resolve("challenge token that should be ignored")
            }

            // Once we get that session at t=2, we should wait a short time for the
            // push challenge token.
            let pushChallengeMinTime = Int(RegistrationCoordinatorImpl.Constants.pushTokenMinWaitTime / scheduler.secondsPerTick)

            // After that, we should get a captcha step back, because we haven't
            // yet received the push challenge token.
            scheduler.advance(to: 2 + pushChallengeMinTime)
            XCTAssertEqual(nextStep.value, .captchaChallenge)

            scheduler.runUntilIdle()
            XCTAssertEqual(scheduler.currentTime, receiveChallengeTokenTime)
        }
    }

    public func testSessionPath_pushChallengeFastResolution() {
        executeTest {
            setUpSessionPath()

            pushRegistrationManagerMock.requestPushTokenMock = {
                XCTAssertEqual(self.scheduler.currentTime, 0)
                return .value(.success(Stubs.apnsRegistrationId))
            }

            // Give it a phone number, which should cause it to start a session.
            let nextStep = coordinator.submitE164(Stubs.e164)

            // Prepare to provide the challenge token.
            let pushChallengeMinTime = Int(RegistrationCoordinatorImpl.Constants.pushTokenMinWaitTime / scheduler.secondsPerTick)
            let receiveChallengeTokenTime = 2 + pushChallengeMinTime - 1

            let (challengeTokenPromise, challengeTokenFuture) = Guarantee<String>.pending()
            var receivePreAuthChallengeTokenCount = 0
            pushRegistrationManagerMock.receivePreAuthChallengeTokenMock = {
                switch receivePreAuthChallengeTokenCount {
                case 0, 1:
                    XCTAssertEqual(self.scheduler.currentTime, 2)
                default:
                    XCTFail("Calling preAuthChallengeToken too many times")
                }
                receivePreAuthChallengeTokenCount += 1
                return challengeTokenPromise
            }

            // At t=2, give back a session with multiple challenges.
            self.sessionManager.beginSessionResponse = self.scheduler.guarantee(
                resolvingWith: .success(RegistrationSession(
                    id: Stubs.sessionId,
                    e164: Stubs.e164,
                    receivedDate: date,
                    nextSMS: 0,
                    nextCall: 0,
                    nextVerificationAttempt: nil,
                    allowedToRequestCode: false,
                    requestedInformation: [.pushChallenge, .captcha],
                    hasUnknownChallengeRequiringAppUpdate: false,
                    verified: false
                )),
                atTime: 2
            )

            // Don't resolve the captcha token immediately, but quickly enough.
            scheduler.run(atTime: receiveChallengeTokenTime - 1) {
                self.date = self.date.addingTimeInterval(TimeInterval(pushChallengeMinTime - 1))
            }
            scheduler.run(atTime: receiveChallengeTokenTime) {
                // Also prep for the token's submission.
                self.sessionManager.fulfillChallengeResponse = self.scheduler.guarantee(
                    resolvingWith: .success(RegistrationSession(
                        id: Stubs.sessionId,
                        e164: Stubs.e164,
                        receivedDate: self.date,
                        nextSMS: 0,
                        nextCall: 0,
                        nextVerificationAttempt: 0,
                        allowedToRequestCode: true,
                        requestedInformation: [],
                        hasUnknownChallengeRequiringAppUpdate: false,
                        verified: false
                    )),
                    atTime: receiveChallengeTokenTime + 1
                )

                self.sessionManager.requestCodeResponse = self.scheduler.guarantee(
                    resolvingWith: .success(RegistrationSession(
                        id: Stubs.sessionId,
                        e164: Stubs.e164,
                        receivedDate: self.date,
                        nextSMS: 0,
                        nextCall: 0,
                        nextVerificationAttempt: 0,
                        allowedToRequestCode: false,
                        requestedInformation: [.pushChallenge],
                        hasUnknownChallengeRequiringAppUpdate: false,
                        verified: false
                    )),
                    atTime: receiveChallengeTokenTime + 2
                )

                challengeTokenFuture.resolve("challenge token")
            }

            // Once we get that session, we should wait a short time for the
            // push challenge token and fulfill it.
            scheduler.advance(to: receiveChallengeTokenTime + 2)
            XCTAssertEqual(nextStep.value, .verificationCodeEntry(Stubs.verificationCodeEntryState(mode: self.mode)))

            scheduler.runUntilIdle()
            XCTAssertEqual(scheduler.currentTime, receiveChallengeTokenTime + 2)

            XCTAssertEqual(receivePreAuthChallengeTokenCount, 2)
        }
    }

    public func testSessionPath_ignoresPushChallengesIfWeCannotEverAnswerThem() {
        executeTest {
            setUpSessionPath()

            pushRegistrationManagerMock.requestPushTokenMock = {
                XCTAssertEqual(self.scheduler.currentTime, 0)
                return .value(.pushUnsupported(description: ""))
            }

            // Give it a phone number, which should cause it to start a session.
            let nextStep = coordinator.submitE164(Stubs.e164)

            // At t=2, give back a session with multiple challenges.
            self.sessionManager.beginSessionResponse = self.scheduler.guarantee(
                resolvingWith: .success(RegistrationSession(
                    id: Stubs.sessionId,
                    e164: Stubs.e164,
                    receivedDate: self.date,
                    nextSMS: 0,
                    nextCall: 0,
                    nextVerificationAttempt: nil,
                    allowedToRequestCode: false,
                    requestedInformation: [.captcha, .pushChallenge],
                    hasUnknownChallengeRequiringAppUpdate: false,
                    verified: false
                )),
                atTime: 2
            )

            scheduler.runUntilIdle()
            XCTAssertEqual(scheduler.currentTime, 2)
            XCTAssertEqual(nextStep.value, .captchaChallenge)
            XCTAssertNil(sessionManager.latestChallengeFulfillment)
        }
    }

    public func testSessionPath_unknownChallenge() {
        executeTest {
            setUpSessionPath()

            // Give it a phone number, which should cause it to start a session.
            var nextStep = coordinator.submitE164(Stubs.e164)

            // At t=2, give back a session with a captcha challenge and an unknown challenge.
            self.sessionManager.beginSessionResponse = self.scheduler.guarantee(
                resolvingWith: .success(RegistrationSession(
                    id: Stubs.sessionId,
                    e164: Stubs.e164,
                    receivedDate: date,
                    nextSMS: 0,
                    nextCall: 0,
                    nextVerificationAttempt: nil,
                    allowedToRequestCode: false,
                    requestedInformation: [.captcha],
                    hasUnknownChallengeRequiringAppUpdate: true,
                    verified: false
                )),
                atTime: 2
            )

            // Once we get that session at t=2, we should get a captcha step back.
            // We have an unknown challenge, but we should do known challenges first!
            scheduler.runUntilIdle()
            XCTAssertEqual(scheduler.currentTime, 2)
            XCTAssertEqual(nextStep.value, .captchaChallenge)

            scheduler.tick()

            // Submit a captcha challenge at t=4.
            scheduler.run(atTime: 4) {
                nextStep = self.coordinator.submitCaptcha(Stubs.captchaToken)
            }

            // At t=6, give back a session without the captcha but still with the
            // unknown challenge
            self.sessionManager.fulfillChallengeResponse = self.scheduler.guarantee(
                resolvingWith: .success(RegistrationSession(
                    id: Stubs.sessionId,
                    e164: Stubs.e164,
                    receivedDate: date,
                    nextSMS: 0,
                    nextCall: 0,
                    nextVerificationAttempt: nil,
                    allowedToRequestCode: false,
                    requestedInformation: [],
                    hasUnknownChallengeRequiringAppUpdate: true,
                    verified: false
                )),
                atTime: 6
            )

            // This means at t=6 we should get the app update banner.
            scheduler.runUntilIdle()
            XCTAssertEqual(scheduler.currentTime, 6)
            XCTAssertEqual(nextStep.value, .appUpdateBanner)
        }
    }

    public func testSessionPath_wrongVerificationCode() {
        executeTest {
            createSessionAndRequestFirstCode()

            // Now try and send the wrong code.
            let badCode = "garbage"

            // At t=1, give back a rejected argument response, its the wrong code.
            self.sessionManager.submitCodeResponse = self.scheduler.guarantee(
                resolvingWith: .rejectedArgument(RegistrationSession(
                    id: Stubs.sessionId,
                    e164: Stubs.e164,
                    receivedDate: date,
                    nextSMS: 0,
                    nextCall: 0,
                    nextVerificationAttempt: 0,
                    allowedToRequestCode: true,
                    requestedInformation: [],
                    hasUnknownChallengeRequiringAppUpdate: false,
                    verified: false
                )),
                atTime: 1
            )

            let nextStep = coordinator.submitVerificationCode(badCode)

            scheduler.runUntilIdle()
            XCTAssertEqual(scheduler.currentTime, 1)
            XCTAssertEqual(
                nextStep.value,
                .verificationCodeEntry(Stubs.verificationCodeEntryState(
                    mode: self.mode,
                    validationError: .invalidVerificationCode(invalidCode: badCode)
                ))
            )
        }
    }

    public func testSessionPath_verificationCodeTimeouts() {
        executeTest {
            createSessionAndRequestFirstCode()

            // At t=1, give back a retry response.
            self.sessionManager.submitCodeResponse = self.scheduler.guarantee(
                resolvingWith: .retryAfterTimeout(RegistrationSession(
                    id: Stubs.sessionId,
                    e164: Stubs.e164,
                    receivedDate: date,
                    nextSMS: 0,
                    nextCall: 0,
                    nextVerificationAttempt: 10,
                    allowedToRequestCode: true,
                    requestedInformation: [],
                    hasUnknownChallengeRequiringAppUpdate: false,
                    verified: false
                )),
                atTime: 1
            )

            var nextStep = coordinator.submitVerificationCode(Stubs.verificationCode)

            scheduler.runUntilIdle()
            XCTAssertEqual(scheduler.currentTime, 1)
            XCTAssertEqual(
                nextStep.value,
                .verificationCodeEntry(Stubs.verificationCodeEntryState(
                    mode: self.mode,
                    nextVerificationAttempt: 10,
                    validationError: .submitCodeTimeout
                ))
            )

            // Resend an sms code, time that out too at t=2.
            self.sessionManager.requestCodeResponse = self.scheduler.guarantee(
                resolvingWith: .retryAfterTimeout(RegistrationSession(
                    id: Stubs.sessionId,
                    e164: Stubs.e164,
                    receivedDate: date,
                    nextSMS: 7,
                    nextCall: 0,
                    nextVerificationAttempt: 9,
                    allowedToRequestCode: true,
                    requestedInformation: [],
                    hasUnknownChallengeRequiringAppUpdate: false,
                    verified: false
                )),
                atTime: 2
            )

            nextStep = coordinator.requestSMSCode()

            scheduler.runUntilIdle()
            XCTAssertEqual(scheduler.currentTime, 2)
            XCTAssertEqual(
                nextStep.value,
                .verificationCodeEntry(Stubs.verificationCodeEntryState(
                    mode: self.mode,
                    nextSMS: 7,
                    nextVerificationAttempt: 9,
                    validationError: .smsResendTimeout
                ))
            )

            // Resend an voice code, time that out too at t=4.
            // Make the timeout SO short that it retries at t=4.
            self.sessionManager.didRequestCode = false
            self.sessionManager.requestCodeResponse = self.scheduler.guarantee(
                resolvingWith: .retryAfterTimeout(RegistrationSession(
                    id: Stubs.sessionId,
                    e164: Stubs.e164,
                    receivedDate: date,
                    nextSMS: 6,
                    nextCall: 0.1,
                    nextVerificationAttempt: 8,
                    allowedToRequestCode: true,
                    requestedInformation: [],
                    hasUnknownChallengeRequiringAppUpdate: false,
                    verified: false
                )),
                atTime: 4
            )

            // Be ready for the retry at t=4
            scheduler.run(atTime: 3) {
                // Ensure we called it the first time.
                XCTAssert(self.sessionManager.didRequestCode)
                self.sessionManager.requestCodeResponse = self.scheduler.guarantee(
                    resolvingWith: .retryAfterTimeout(RegistrationSession(
                        id: Stubs.sessionId,
                        e164: Stubs.e164,
                        receivedDate: self.date,
                        nextSMS: 5,
                        nextCall: 4,
                        nextVerificationAttempt: 8,
                        allowedToRequestCode: true,
                        requestedInformation: [],
                        hasUnknownChallengeRequiringAppUpdate: false,
                        verified: false
                    )),
                    atTime: 5
                )
            }

            nextStep = coordinator.requestVoiceCode()

            scheduler.runUntilIdle()
            XCTAssertEqual(scheduler.currentTime, 5)
            XCTAssertEqual(
                nextStep.value,
                .verificationCodeEntry(Stubs.verificationCodeEntryState(
                    mode: self.mode,
                    nextSMS: 5,
                    nextCall: 4,
                    nextVerificationAttempt: 8,
                    validationError: .voiceResendTimeout
                ))
            )
        }
    }

    public func testSessionPath_disallowedVerificationCode() {
        executeTest {
            createSessionAndRequestFirstCode()

            // At t=1, give back a disallowed response when submitting a code.
            // Make the session unverified. Together this will be interpreted
            // as meaning no code has been sent (via sms or voice) and one
            // must be requested.
            self.sessionManager.submitCodeResponse = self.scheduler.guarantee(
                resolvingWith: .disallowed(RegistrationSession(
                    id: Stubs.sessionId,
                    e164: Stubs.e164,
                    receivedDate: date,
                    nextSMS: 0,
                    nextCall: 0,
                    nextVerificationAttempt: nil,
                    allowedToRequestCode: true,
                    requestedInformation: [],
                    hasUnknownChallengeRequiringAppUpdate: false,
                    verified: false
                )),
                atTime: 1
            )

            var nextStep = coordinator.submitVerificationCode(Stubs.verificationCode)

            scheduler.runUntilIdle()
            XCTAssertEqual(scheduler.currentTime, 1)

            // The server says no code is available to submit. But we think we tried
            // sending a code with local state. We want to be on the verification
            // code entry screen, with an error so the user retries sending a code.

            XCTAssertEqual(
                nextStep.value,
                .showErrorSheet(.verificationCodeSubmissionUnavailable)
            )
            nextStep = coordinator.nextStep()
            scheduler.runUntilIdle()
            XCTAssertEqual(
                nextStep.value,
                .verificationCodeEntry(Stubs.verificationCodeEntryState(
                    mode: self.mode,
                    nextVerificationAttempt: nil
                ))
            )
        }
    }

    public func testSessionPath_timedOutVerificationCodeWithoutRetries() {
        executeTest {
            createSessionAndRequestFirstCode()

            // At t=1, give back a retry response when submitting a code,
            // but with no ability to resubmit.
            self.sessionManager.submitCodeResponse = self.scheduler.guarantee(
                resolvingWith: .retryAfterTimeout(RegistrationSession(
                    id: Stubs.sessionId,
                    e164: Stubs.e164,
                    receivedDate: date,
                    nextSMS: 0,
                    nextCall: 0,
                    nextVerificationAttempt: nil,
                    allowedToRequestCode: true,
                    requestedInformation: [],
                    hasUnknownChallengeRequiringAppUpdate: false,
                    verified: false
                )),
                atTime: 1
            )

            var nextStep = coordinator.submitVerificationCode(Stubs.verificationCode)

            scheduler.runUntilIdle()
            XCTAssertEqual(scheduler.currentTime, 1)
            XCTAssertEqual(
                nextStep.value,
                .showErrorSheet(.verificationCodeSubmissionUnavailable)
            )
            nextStep = coordinator.nextStep()
            scheduler.runUntilIdle()
            XCTAssertEqual(
                nextStep.value,
                .verificationCodeEntry(Stubs.verificationCodeEntryState(
                    mode: mode,
                    nextVerificationAttempt: nil
                ))
            )
        }
    }

    public func testSessionPath_expiredSession() {
        executeTest {
            setUpSessionPath()

            // Give it a phone number, which should cause it to start a session.
            var nextStep = coordinator.submitE164(Stubs.e164)

            // At t=2, give back a session thats ready to go.
            self.sessionManager.beginSessionResponse = self.scheduler.guarantee(
                resolvingWith: .success(RegistrationSession(
                    id: Stubs.sessionId,
                    e164: Stubs.e164,
                    receivedDate: date,
                    nextSMS: 0,
                    nextCall: 0,
                    nextVerificationAttempt: nil,
                    allowedToRequestCode: true,
                    requestedInformation: [],
                    hasUnknownChallengeRequiringAppUpdate: false,
                    verified: false
                )),
                atTime: 2
            )

            // Once we get that session at t=2, we should try and send a verification code.
            // Have that ready to go at t=1.
            scheduler.run(atTime: 1) {
                // We'll ask for a push challenge, though we won't resolve it.
                self.pushRegistrationManagerMock.receivePreAuthChallengeTokenMock = {
                    return Guarantee<String>.pending().0
                }

                // Resolve with a session at time 3.
                self.sessionManager.requestCodeResponse = self.scheduler.guarantee(
                    resolvingWith: .success(RegistrationSession(
                        id: Stubs.sessionId,
                        e164: Stubs.e164,
                        receivedDate: self.date,
                        nextSMS: 0,
                        nextCall: 0,
                        nextVerificationAttempt: 0,
                        allowedToRequestCode: true,
                        requestedInformation: [],
                        hasUnknownChallengeRequiringAppUpdate: false,
                        verified: false
                    )),
                    atTime: 3
                )
            }

            scheduler.runUntilIdle()
            XCTAssertEqual(scheduler.currentTime, 3)

            // Now we should expect to be at verification code entry since we sent the code.
            XCTAssertEqual(nextStep.value, .verificationCodeEntry(Stubs.verificationCodeEntryState(mode: self.mode)))

            scheduler.tick()

            // Submit a code at t=5.
            scheduler.run(atTime: 5) {
                nextStep = self.coordinator.submitVerificationCode(Stubs.pinCode)
            }

            // At t=7, give back an expired session.
            self.sessionManager.submitCodeResponse = self.scheduler.guarantee(
                resolvingWith: .invalidSession,
                atTime: 7
            )

            // That means at t=7 it should show an error, and then phone number entry.
            scheduler.runUntilIdle()
            XCTAssertEqual(scheduler.currentTime, 7)
            XCTAssertEqual(nextStep.value, .showErrorSheet(.sessionInvalidated))
            nextStep = coordinator.nextStep()
            scheduler.runUntilIdle()
            XCTAssertEqual(nextStep.value, .phoneNumberEntry(Stubs.phoneNumberEntryState(
                mode: mode,
                previouslyEnteredE164: Stubs.e164
            )))
        }
    }

    public func testSessionPath_skipPINCode() {
        executeTest {
            createSessionAndRequestFirstCode()

            scheduler.tick()

            var nextStep: Guarantee<RegistrationStep>!

            // Submit a code at t=5.
            scheduler.run(atTime: 5) {
                nextStep = self.coordinator.submitVerificationCode(Stubs.pinCode)
            }

            // At t=7, give back a verified session.
            self.sessionManager.submitCodeResponse = self.scheduler.guarantee(
                resolvingWith: .success(RegistrationSession(
                    id: Stubs.sessionId,
                    e164: Stubs.e164,
                    receivedDate: date,
                    nextSMS: 0,
                    nextCall: 0,
                    nextVerificationAttempt: nil,
                    allowedToRequestCode: true,
                    requestedInformation: [],
                    hasUnknownChallengeRequiringAppUpdate: false,
                    verified: true
                )),
                atTime: 7
            )

            let accountIdentityResponse = Stubs.accountIdentityResponse()
            var authPassword: String!

            // That means at t=7 it should try and register with the verified
            // session; be ready for that starting at t=6 (but not before).

            // Before registering at t=7, it should ask for push tokens to give the registration.
            pushRegistrationManagerMock.requestPushTokenMock = {
                XCTAssertEqual(self.scheduler.currentTime, 7)
                return self.scheduler.guarantee(resolvingWith: .success(Stubs.apnsRegistrationId), atTime: 8)
            }

            // It should also fetch the prekeys for account creation
            preKeyManagerMock.createPreKeysMock = {
                XCTAssertEqual(self.scheduler.currentTime, 8)
                return self.scheduler.promise(resolvingWith: Stubs.prekeyBundles(), atTime: 9)
            }

            scheduler.run(atTime: 8) {
                let expectedRequest = RegistrationRequestFactory.createAccountRequest(
                    verificationMethod: .sessionId(Stubs.sessionId),
                    e164: Stubs.e164,
                    authPassword: "", // Doesn't matter for request generation.
                    accountAttributes: Stubs.accountAttributes(),
                    skipDeviceTransfer: true,
                    apnRegistrationId: Stubs.apnsRegistrationId,
                    prekeyBundles: Stubs.prekeyBundles()
                )
                // Resolve it at t=10
                self.mockURLSession.addResponse(
                    TSRequestOWSURLSessionMock.Response(
                        matcher: { request in
                            authPassword = request.authPassword
                            return request.url == expectedRequest.url
                        },
                        statusCode: 200,
                        bodyJson: accountIdentityResponse
                    ),
                    atTime: 10,
                    on: self.scheduler
                )
            }

            func expectedAuthedAccount() -> AuthedAccount {
                return .explicit(
                    aci: accountIdentityResponse.aci,
                    pni: accountIdentityResponse.pni,
                    e164: Stubs.e164,
                    deviceId: .primary,
                    authPassword: authPassword
                )
            }

            // Once we are registered at t=10, we should finalize prekeys.
            preKeyManagerMock.finalizePreKeysMock = { didSucceed in
                XCTAssertEqual(self.scheduler.currentTime, 10)
                XCTAssert(didSucceed)
                return self.scheduler.promise(resolvingWith: (), atTime: 11)
            }

            // Then we should try and create one time pre-keys
            // with the credentials we got in the identity response.
            preKeyManagerMock.rotateOneTimePreKeysMock = { auth in
                XCTAssertEqual(self.scheduler.currentTime, 11)
                XCTAssertEqual(auth, expectedAuthedAccount().chatServiceAuth)
                return self.scheduler.promise(resolvingWith: (), atTime: 12)
            }

            scheduler.runUntilIdle()
            XCTAssertEqual(scheduler.currentTime, 12)

            // Now we should ask to create a PIN.
            // No exit allowed since we've already started trying to create the account.
            XCTAssertEqual(nextStep.value, .pinEntry(
                Stubs.pinEntryStateForPostRegCreate(mode: self.mode, exitConfigOverride: .noExitAllowed)
            ))

            scheduler.adjustTime(to: 0)

            // Skip the PIN code.
            nextStep = coordinator.skipPINCode()

            // When we skip the pin, it should skip any SVR backups.
            svr.generateAndBackupKeysMock = { _, _, _ in
                XCTFail("Shouldn't talk to SVR with skipped PIN!")
                return .value(())

            }
            accountManagerMock.performInitialStorageServiceRestoreMock = { _ in
                return .value(())
            }

            // When registered, we should create pre-keys.
            preKeyManagerMock.rotateOneTimePreKeysMock = { auth in
                XCTAssertEqual(auth, expectedAuthedAccount())
                return .value(())
            }

            // And at t=0 once we skip the storage service restore,
            // we will sync account attributes and then we are finished!
            let expectedAttributesRequest = RegistrationRequestFactory.updatePrimaryDeviceAccountAttributesRequest(
                Stubs.accountAttributes(),
                auth: .implicit() // doesn't matter for url matching
            )
            self.mockURLSession.addResponse(
                matcher: { request in
                    XCTAssertEqual(self.scheduler.currentTime, 0)
                    return request.url == expectedAttributesRequest.url
                },
                statusCode: 200
            )

            // At this point we should have no master key.
            XCTAssertFalse(svr.hasMasterKey)

            var didSetLocalMasterKey = false
            svr.useDeviceLocalMasterKeyMock = { [weak self] _ in
                XCTAssertFalse(self?.svr.hasMasterKey ?? true)
                didSetLocalMasterKey = true
            }

            scheduler.runUntilIdle()
            XCTAssertEqual(scheduler.currentTime, 0)

            XCTAssertEqual(nextStep.value, .done)

            XCTAssertTrue(didSetLocalMasterKey)
        }
    }

    // MARK: - Profile Setup Path

    // TODO[Registration]: test the profile setup steps.

    // MARK: - Persisted State backwards compatibility

    typealias ReglockState = RegistrationCoordinatorImpl.PersistedState.SessionState.ReglockState

    public func testPersistedState_SVRCredentialCompat() throws {
        let reglockExpirationDate = Date(timeIntervalSince1970: 10000)
        let decoder = JSONDecoder()

        // Serialized ReglockState.none
        let reglockStateNoneData = "7b226e6f6e65223a7b7d7d"
        XCTAssertEqual(
            ReglockState.none,
            try decoder.decode(ReglockState.self, from: Data.data(fromHex: reglockStateNoneData)!)
        )

        // Serialized ReglockState.reglocked(
        //     credential: KBSAuthCredential(credential: RemoteAttestation.Auth(username: "abcd", password: "xyz"),
        //     expirationDate: reglockExpirationDate
        // )
        let reglockStateReglockedData = "7b227265676c6f636b6564223a7b2265787069726174696f6e44617465223a2d3937383239373230302c2263726564656e7469616c223a7b2263726564656e7469616c223a7b22757365726e616d65223a2261626364222c2270617373776f7264223a2278797a227d7d7d7d"
        XCTAssertEqual(
            ReglockState.reglocked(credential: .testOnly(svr2: nil), expirationDate: reglockExpirationDate),
            try decoder.decode(ReglockState.self, from: Data.data(fromHex: reglockStateReglockedData)!)
        )

        // Serialized ReglockState.reglocked(
        //     credential: ReglockState.SVRAuthCredential(
        //         kbs: KBSAuthCredential(credential: RemoteAttestation.Auth(username: "abcd", password: "xyz"),
        //         svr2: SVR2AuthCredential(credential: RemoteAttestation.Auth(username: "xxx", password: "yyy"))
        //     ),
        //     expirationDate: reglockExpirationDate
        // )
        let reglockStateReglockedSVR2Data = "7b227265676c6f636b6564223a7b2265787069726174696f6e44617465223a2d3937383239373230302c2263726564656e7469616c223a7b226b6273223a7b2263726564656e7469616c223a7b22757365726e616d65223a2261626364222c2270617373776f7264223a2278797a227d7d2c2273767232223a7b2263726564656e7469616c223a7b22757365726e616d65223a22787878222c2270617373776f7264223a22797979227d7d7d7d7d"
        XCTAssertEqual(
            ReglockState.reglocked(credential: .init(svr2: Stubs.svr2AuthCredential), expirationDate: reglockExpirationDate),
            try decoder.decode(ReglockState.self, from: Data.data(fromHex: reglockStateReglockedSVR2Data)!)
        )

        // Serialized ReglockState.waitingTimeout(expirationDate: reglockExpirationDate)
        let reglockStateWaitingTimeoutData = "7b2277616974696e6754696d656f7574223a7b2265787069726174696f6e44617465223a2d3937383239373230307d7d"
        XCTAssertEqual(
            ReglockState.waitingTimeout(expirationDate: reglockExpirationDate),
            try decoder.decode(ReglockState.self, from: Data.data(fromHex: reglockStateWaitingTimeoutData)!)
        )
    }

    // MARK: Happy Path Setups

    private func preservingSchedulerState(_ block: () -> Void) {
        let startTime = scheduler.currentTime
        let wasRunning = scheduler.isRunning
        scheduler.stop()
        scheduler.adjustTime(to: 0)
        block()
        scheduler.adjustTime(to: startTime)
        if wasRunning {
            scheduler.start()
        }
    }

    private func goThroughOpeningHappyPath(expectedNextStep: RegistrationStep) {
        preservingSchedulerState {
            contactsStore.doesNeedContactsAuthorization = true
            pushRegistrationManagerMock.doesNeedNotificationAuthorization = true

            var nextStep: Guarantee<RegistrationStep>!
            switch mode {
            case .registering:
                // Gotta get the splash out of the way.
                nextStep = coordinator.nextStep()
                scheduler.runUntilIdle()
                XCTAssertEqual(nextStep.value, .registrationSplash)
            case .reRegistering, .changingNumber:
                break
            }

            // Now we should show the permissions.
            nextStep = coordinator.continueFromSplash()
            scheduler.runUntilIdle()
            XCTAssertEqual(nextStep.value, .permissions(Stubs.permissionsState()))

            // Once the state is updated we can proceed.
            nextStep = coordinator.requestPermissions()
            scheduler.runUntilIdle()
            XCTAssertEqual(nextStep.value, expectedNextStep)
        }
    }

    private func setUpSessionPath() {
        // Set profile info so we skip those steps.
        self.setupDefaultAccountAttributes()

        pushRegistrationManagerMock.requestPushTokenMock = { .value(.success(Stubs.apnsRegistrationId)) }

        pushRegistrationManagerMock.receivePreAuthChallengeTokenMock = { .pending().0 }

        // No other setup; no auth credentials, SVR keys, etc in storage
        // so that we immediately go to the session flow.

        // Get past the opening.
        goThroughOpeningHappyPath(expectedNextStep: .phoneNumberEntry(Stubs.phoneNumberEntryState(mode: mode)))
    }

    private func createSessionAndRequestFirstCode() {
        setUpSessionPath()

        preservingSchedulerState {
            // Give it a phone number, which should cause it to start a session.
            let nextStep = coordinator.submitE164(Stubs.e164)

            // We'll ask for a push challenge, though we won't resolve it.
            self.pushRegistrationManagerMock.receivePreAuthChallengeTokenMock = {
                return Guarantee<String>.pending().0
            }

            // At t=2, give back a session that's ready to go.
            self.sessionManager.beginSessionResponse = self.scheduler.guarantee(
                resolvingWith: .success(RegistrationSession(
                    id: Stubs.sessionId,
                    e164: Stubs.e164,
                    receivedDate: date,
                    nextSMS: 0,
                    nextCall: 0,
                    nextVerificationAttempt: nil,
                    allowedToRequestCode: true,
                    requestedInformation: [],
                    hasUnknownChallengeRequiringAppUpdate: false,
                    verified: false
                )),
                atTime: 2
            )

            // Once we get that session at t=2, we should try and send a code.
            // Be ready for that starting at t=1 (but not before).
            scheduler.run(atTime: 1) {
                // Resolve with a session thats ready for code submission at time 3.
                self.sessionManager.requestCodeResponse = self.scheduler.guarantee(
                    resolvingWith: .success(RegistrationSession(
                        id: Stubs.sessionId,
                        e164: Stubs.e164,
                        receivedDate: self.date,
                        nextSMS: 0,
                        nextCall: 0,
                        nextVerificationAttempt: 0,
                        allowedToRequestCode: true,
                        requestedInformation: [],
                        hasUnknownChallengeRequiringAppUpdate: false,
                        verified: false
                    )),
                    atTime: 3
                )
            }

            // At t=3 we should get back the code entry step.
            scheduler.runUntilIdle()
            XCTAssertEqual(scheduler.currentTime, 3)
            XCTAssertEqual(nextStep.value, .verificationCodeEntry(Stubs.verificationCodeEntryState(mode: self.mode)))
        }
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
        profileManagerMock.hasProfileNameMock = { true }
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

    // MARK: - Stubs

    private enum Stubs {

        static let e164 = E164("+17875550100")!
        static let aci = Aci.randomForTesting()
        static let pinCode = "1234"

        static let regRecoveryPwData = Data(repeating: 8, count: 8)
        static var regRecoveryPw: String { regRecoveryPwData.base64EncodedString() }

        static let reglockData = Data(repeating: 7, count: 8)
        static var reglockToken: String { reglockData.hexadecimalString }

        static let svr2AuthCredential = SVR2AuthCredential(credential: RemoteAttestation.Auth(username: "xxx", password: "yyy"))

        static let captchaToken = "captchaToken"
        static let apnsToken = "apnsToken"
        static let apnsRegistrationId = RegistrationRequestFactory.ApnRegistrationId(apnsToken: apnsToken, voipToken: nil)

        static let authUsername = "username_jdhfsalkjfhd"
        static let authPassword = "password_dskafjasldkfjasf"

        static let sessionId = UUID().uuidString
        static let verificationCode = "8888"

        static var date: Date!

        static func accountAttributes() -> AccountAttributes {
            return AccountAttributes(
                isManualMessageFetchEnabled: false,
                registrationId: 0,
                pniRegistrationId: 0,
                unidentifiedAccessKey: "",
                unrestrictedUnidentifiedAccess: false,
                twofaMode: .none,
                registrationRecoveryPassword: nil,
                encryptedDeviceName: nil,
                discoverableByPhoneNumber: .nobody,
                hasSVRBackups: true
            )
        }

        static func accountIdentityResponse() -> RegistrationServiceResponses.AccountIdentityResponse {
            return RegistrationServiceResponses.AccountIdentityResponse(
                aci: aci,
                pni: Pni.randomForTesting(),
                e164: e164,
                username: nil,
                hasPreviouslyUsedSVR: false
            )
        }

        static func session(
            e164: E164 = Stubs.e164,
            hasSentVerificationCode: Bool
        ) -> RegistrationSession {
            return RegistrationSession(
                id: UUID().uuidString,
                e164: e164,
                receivedDate: date,
                nextSMS: 0,
                nextCall: 0,
                nextVerificationAttempt: hasSentVerificationCode ? 0 : nil,
                allowedToRequestCode: true,
                requestedInformation: [],
                hasUnknownChallengeRequiringAppUpdate: false,
                verified: false
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
                signedPreKey: SSKSignedPreKeyStore.generateSignedPreKey(signedBy: identityKeyPair),
                lastResortPreKey: {
                    let keyPair = KEMKeyPair.generate()
                    let signature = Data(identityKeyPair.keyPair.privateKey.generateSignature(message: Data(keyPair.publicKey.serialize())))

                    let record = SignalServiceKit.KyberPreKeyRecord(
                        0,
                        keyPair: keyPair,
                        signature: signature,
                        generatedAt: Date(),
                        isLastResort: true
                    )
                    return record
                }()
            )
        }

        // MARK: Step States

        static func permissionsState() -> RegistrationPermissionsState {
            return RegistrationPermissionsState(shouldRequestAccessToContacts: true)
        }

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

        static func phoneNumberEntryState(
            mode: RegistrationMode,
            previouslyEnteredE164: E164? = nil,
            withValidationErrorFor response: Registration.BeginSessionResponse = .success(Stubs.session(hasSentVerificationCode: false))
        ) -> RegistrationPhoneNumberViewState {
            let validationError: RegistrationPhoneNumberViewState.ValidationError?
            switch response {
            case .success:
                validationError = nil
            case .invalidArgument:
                validationError = .invalidNumber(.init(invalidE164: previouslyEnteredE164 ?? Stubs.e164))
            case .retryAfter(let timeInterval):
                validationError = .rateLimited(.init(
                    expiration: self.date.addingTimeInterval(timeInterval),
                    e164: previouslyEnteredE164 ?? Stubs.e164
                ))
            case .networkFailure, .genericError:
                XCTFail("Should not be generating phone number state for error responses.")
                validationError = nil
            }

            switch mode {
            case .registering:
                return .registration(.initialRegistration(.init(
                    previouslyEnteredE164: previouslyEnteredE164,
                    validationError: validationError
                )))
            case .reRegistering(let params):
                return .registration(.reregistration(.init(e164: params.e164, validationError: validationError)))
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
                            invalidNumberError: nil
                        )))
                    }
                case .rateLimited(let error):
                    return .changingNumber(.confirmation(.init(
                        oldE164: changeNumberParams.oldE164,
                        newE164: previouslyEnteredE164!,
                        rateLimitedError: error
                    )))
                case .invalidNumber(let error):
                    return .changingNumber(.initialEntry(.init(
                        oldE164: changeNumberParams.oldE164,
                        newE164: previouslyEnteredE164,
                        hasConfirmed: previouslyEnteredE164 != nil,
                        invalidNumberError: error
                    )))
                }
            }
        }

        static func verificationCodeEntryState(
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
            error: RegistrationPinValidationError? = nil
        ) -> RegistrationPinState {
            return RegistrationPinState(
                operation: .enteringExistingPin(
                    skippability: .canSkipAndCreateNew,
                    remainingAttempts: nil
                ),
                error: error,
                contactSupportMode: .v2NoReglock,
                exitConfiguration: mode.pinExitConfig
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

private class PreKeyError: Error {
    init() {}
}

extension RegistrationServiceResponses.RegistrationLockFailureResponse: Encodable {
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(timeRemainingMs, forKey: .timeRemainingMs)
        try container.encodeIfPresent(svr2AuthCredential.credential, forKey: .svr2AuthCredential)
    }
}
