//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
@testable import Signal
@testable import SignalServiceKit
import XCTest

public class RegistrationCoordinatorTest: XCTestCase {

    private var date = Date() {
        didSet {
            Stubs.date = date
        }
    }
    private var scheduler: TestScheduler!

    private var coordinator: RegistrationCoordinatorImpl!

    private var accountManagerMock: RegistrationCoordinatorImpl.TestMocks.AccountManager!
    private var contactsStore: RegistrationCoordinatorImpl.TestMocks.ContactsStore!
    private var experienceManager: RegistrationCoordinatorImpl.TestMocks.ExperienceManager!
    private var kbs: KeyBackupServiceMock!
    private var kbsAuthCredentialStore: KBSAuthCredentialStorageMock!
    private var mockURLSession: TSRequestOWSURLSessionMock!
    private var ows2FAManagerMock: RegistrationCoordinatorImpl.TestMocks.OWS2FAManager!
    private var profileManagerMock: RegistrationCoordinatorImpl.TestMocks.ProfileManager!
    private var pushRegistrationManagerMock: RegistrationCoordinatorImpl.TestMocks.PushRegistrationManager!
    private var receiptManagerMock: RegistrationCoordinatorImpl.TestMocks.ReceiptManager!
    private var sessionManager: RegistrationSessionManagerMock!
    private var storageServiceManagerMock: FakeStorageServiceManager!
    private var tsAccountManagerMock: RegistrationCoordinatorImpl.TestMocks.TSAccountManager!

    public override func setUp() {
        super.setUp()

        Stubs.date = date

        accountManagerMock = RegistrationCoordinatorImpl.TestMocks.AccountManager()
        contactsStore = RegistrationCoordinatorImpl.TestMocks.ContactsStore()
        experienceManager = RegistrationCoordinatorImpl.TestMocks.ExperienceManager()
        kbs = KeyBackupServiceMock()
        kbsAuthCredentialStore = KBSAuthCredentialStorageMock()
        ows2FAManagerMock = RegistrationCoordinatorImpl.TestMocks.OWS2FAManager()
        profileManagerMock = RegistrationCoordinatorImpl.TestMocks.ProfileManager()
        pushRegistrationManagerMock = RegistrationCoordinatorImpl.TestMocks.PushRegistrationManager()
        receiptManagerMock = RegistrationCoordinatorImpl.TestMocks.ReceiptManager()
        sessionManager = RegistrationSessionManagerMock()
        storageServiceManagerMock = FakeStorageServiceManager()
        tsAccountManagerMock = RegistrationCoordinatorImpl.TestMocks.TSAccountManager()

        let mockURLSession = TSRequestOWSURLSessionMock()
        self.mockURLSession = mockURLSession
        let mockSignalService = OWSSignalServiceMock()
        mockSignalService.mockUrlSessionBuilder = { _, _, _ in
            return mockURLSession
        }

        scheduler = TestScheduler()

        coordinator = RegistrationCoordinatorImpl(
            accountManager: accountManagerMock,
            contactsStore: contactsStore,
            dateProvider: { self.date },
            db: MockDB(),
            experienceManager: experienceManager,
            kbs: kbs,
            kbsAuthCredentialStore: kbsAuthCredentialStore,
            keyValueStoreFactory: InMemoryKeyValueStoreFactory(),
            ows2FAManager: ows2FAManagerMock,
            profileManager: profileManagerMock,
            pushRegistrationManager: pushRegistrationManagerMock,
            receiptManager: receiptManagerMock,
            remoteConfig: RegistrationCoordinatorImpl.TestMocks.RemoteConfig(),
            schedulers: TestSchedulers(scheduler: scheduler),
            sessionManager: sessionManager,
            signalService: mockSignalService,
            storageServiceManager: storageServiceManagerMock,
            tsAccountManager: tsAccountManagerMock,
            udManager: RegistrationCoordinatorImpl.TestMocks.UDManager()
        )
    }

    // MARK: - Opening Path

    func testOpeningPath_splash() {
        // Don't care about timing, just start it.
        scheduler.start()

        setupDefaultAccountAttributes()

        // With no state set up, should show the splash.
        XCTAssertEqual(coordinator.nextStep().value, .splash)
        // Once we show it, don't show it again.
        XCTAssertNotEqual(coordinator.nextStep().value, .splash)
    }

    func testOpeningPath_contacts() {
        // Don't care about timing, just start it.
        scheduler.start()

        setupDefaultAccountAttributes()

        contactsStore.doesNeedContactsAuthorization = true
        pushRegistrationManagerMock.doesNeedNotificationAuthorization = true

        // Gotta get the splash out of the way.
        XCTAssertEqual(coordinator.nextStep().value, .splash)

        // Now we should show the permissions.
        XCTAssertEqual(coordinator.nextStep().value, .permissions)
        // Doesn't change even if we try and proceed.
        XCTAssertEqual(coordinator.nextStep().value, .permissions)

        // Once the state is updated we can proceed.
        let nextStep = coordinator.requestPermissions().value
        XCTAssertNotEqual(nextStep, .splash)
        XCTAssertNotEqual(nextStep, .permissions)
    }

    // MARK: - Reg Recovery Password Path

    func testRegRecoveryPwPath_happyPath() throws {
        // Don't care about timing, just start it.
        scheduler.start()

        // Set profile info so we skip those steps.
        setupDefaultAccountAttributes()

        // Set a PIN on disk.
        ows2FAManagerMock.pinCodeMock = { Stubs.pinCode }

        // Make KBS give us back a reg recovery password.
        kbs.dataGenerator = {
            switch $0 {
            case .registrationRecoveryPassword:
                return Stubs.regRecoveryPwData
            case .registrationLock:
                return Stubs.reglockData
            default:
                return nil
            }
        }

        // We haven't set a phone number so it should ask for that.
        XCTAssertEqual(coordinator.nextStep().value, .phoneNumberEntry)

        // Give it a phone number, which should show the PIN entry step.
        var nextStep = coordinator.submitE164(Stubs.e164).value
        // Now it should ask for the PIN to confirm the user knows it.
        XCTAssertEqual(nextStep, .pinEntry)

        // Give it the pin code, which should make it try and register.
        let expectedRequest = RegistrationRequestFactory.createAccountRequest(
            verificationMethod: .recoveryPassword(Stubs.regRecoveryPw),
            e164: Stubs.e164,
            accountAttributes: Stubs.accountAttributes(),
            skipDeviceTransfer: true
        )
        let identityResponse = Stubs.accountIdentityResponse()
        let authUsername = identityResponse.aci.uuidString
        var authPassword: String!
        mockURLSession.addResponse(TSRequestOWSURLSessionMock.Response(
            matcher: { request in
                // The password is generated internally by RegistrationCoordinator.
                // Extract it so we can check that the same password sent to the server
                // to register is used later for other requests.
                authPassword = Self.attributesFromCreateAccountRequest(request).authKey
                return request.url == expectedRequest.url
            },
            statusCode: 200,
            bodyData: try JSONEncoder().encode(identityResponse)
        ))

        // When registered, it should try and sync push tokens.
        pushRegistrationManagerMock.syncPushTokensForcingUploadMock = { username, password in
            XCTAssertEqual(username, authUsername)
            XCTAssertEqual(password, authPassword)
            return .value(.success)
        }

        // We haven't done a kbs backup; that should happen now.
        kbs.generateAndBackupKeysMock = { pin, authMethod, rotateMasterKey in
            XCTAssertEqual(pin, Stubs.pinCode)
            // We don't have a kbs auth credential, it should use chat server creds.
            XCTAssertEqual(authMethod, .chatServerAuth(username: authUsername, password: authPassword))
            XCTAssertFalse(rotateMasterKey)
            self.kbs.hasMasterKey = true
            return .value(())
        }

        // Once we sync push tokens, we should restore from storage service.
        accountManagerMock.performInitialStorageServiceRestoreMock = {
            return .value(())
        }

        // Once we do the storage service restore,
        // we will sync account attributes and then we are finished!
        let expectedAttributesRequest = RegistrationRequestFactory.updatePrimaryDeviceAccountAttributesRequest(
            Stubs.accountAttributes(),
            authUsername: "", // doesn't matter for url matching
            authPassword: "" // doesn't matter for url matching
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
        // Don't care about timing, just start it.
        scheduler.start()

        // Set profile info so we skip those steps.
        setupDefaultAccountAttributes()

        let wrongPinCode = "ABCD"

        // Set a different PIN on disk.
        ows2FAManagerMock.pinCodeMock = { Stubs.pinCode }

        // Make KBS give us back a reg recovery password.
        kbs.dataGenerator = {
            switch $0 {
            case .registrationRecoveryPassword:
                return Stubs.regRecoveryPwData
            case .registrationLock:
                return Stubs.reglockData
            default:
                return nil
            }
        }

        // We haven't set a phone number so it should ask for that.
        XCTAssertEqual(coordinator.nextStep().value, .phoneNumberEntry)

        // Give it a phone number, which should show the PIN entry step.
        var nextStep = coordinator.submitE164(Stubs.e164).value
        // Now it should ask for the PIN to confirm the user knows it.
        XCTAssertEqual(nextStep, .pinEntry)

        // Give it the wrong PIN, it should reject and give us the same step again.
        nextStep = coordinator.submitPINCode(wrongPinCode).value
        XCTAssertEqual(nextStep, .pinEntry)

        // Give it the right pin code, which should make it try and register.
        let expectedRequest = RegistrationRequestFactory.createAccountRequest(
            verificationMethod: .recoveryPassword(Stubs.regRecoveryPw),
            e164: Stubs.e164,
            accountAttributes: Stubs.accountAttributes(),
            skipDeviceTransfer: true
        )

        let identityResponse = Stubs.accountIdentityResponse()
        let authUsername = identityResponse.aci.uuidString
        var authPassword: String!
        mockURLSession.addResponse(TSRequestOWSURLSessionMock.Response(
            matcher: { request in
                authPassword = Self.attributesFromCreateAccountRequest(request).authKey
                return request.url == expectedRequest.url
            },
            statusCode: 200,
            bodyData: try JSONEncoder().encode(identityResponse)
        ))

        // When registered, it should try and sync push tokens.
        pushRegistrationManagerMock.syncPushTokensForcingUploadMock = { username, password in
            XCTAssertEqual(username, authUsername)
            XCTAssertEqual(password, authPassword)
            return .value(.success)
        }

        // We haven't done a kbs backup; that should happen now.
        kbs.generateAndBackupKeysMock = { pin, authMethod, rotateMasterKey in
            XCTAssertEqual(pin, Stubs.pinCode)
            // We don't have a kbs auth credential, it should use chat server creds.
            XCTAssertEqual(authMethod, .chatServerAuth(username: authUsername, password: authPassword))
            XCTAssertFalse(rotateMasterKey)
            self.kbs.hasMasterKey = true
            return .value(())
        }

        // Once we sync push tokens, we should restore from storage service.
        accountManagerMock.performInitialStorageServiceRestoreMock = {
            return .value(())
        }

        // Once we do the storage service restore,
        // we will sync account attributes and then we are finished!
        let expectedAttributesRequest = RegistrationRequestFactory.updatePrimaryDeviceAccountAttributesRequest(
            Stubs.accountAttributes(),
            authUsername: "", // doesn't matter for url matching
            authPassword: "" // doesn't matter for url matching
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

    func testRegRecoveryPwPath_wrongPassword() {
        // Set profile info so we skip those steps.
        setupDefaultAccountAttributes()

        // Set a PIN on disk.
        ows2FAManagerMock.pinCodeMock = { Stubs.pinCode }

        // Make KBS give us back a reg recovery password.
        kbs.dataGenerator = {
            switch $0 {
            case .registrationRecoveryPassword:
                return Stubs.regRecoveryPwData
            case .registrationLock:
                return Stubs.reglockData
            default:
                return nil
            }
        }
        kbs.hasMasterKey = true

        // Run the scheduler for a bit; we don't care about timing these bits.
        scheduler.start()

        // We haven't set a phone number so it should ask for that.
        XCTAssertEqual(coordinator.nextStep().value, .phoneNumberEntry)

        // Give it a phone number, which should show the PIN entry step.
        var nextStep = coordinator.submitE164(Stubs.e164)
        // Now it should ask for the PIN to confirm the user knows it.
        XCTAssertEqual(nextStep.value, .pinEntry)

        // Now we want to control timing so we can verify things happened in the right order.
        scheduler.stop()
        scheduler.adjustTime(to: 0)

        // Give it the pin code, which should make it try and register.
        nextStep = coordinator.submitPINCode(Stubs.pinCode)

        let expectedRecoveryPwRequest = RegistrationRequestFactory.createAccountRequest(
            verificationMethod: .recoveryPassword(Stubs.regRecoveryPw),
            e164: Stubs.e164,
            accountAttributes: Stubs.accountAttributes(),
            skipDeviceTransfer: true
        )

        // Fail the request at t=2; the reg recovery pw is invalid.
        let failResponse = TSRequestOWSURLSessionMock.Response(
            urlSuffix: expectedRecoveryPwRequest.url!.absoluteString,
            statusCode: RegistrationServiceResponses.AccountCreationResponseCodes.unauthorized.rawValue
        )
        mockURLSession.addResponse(failResponse, atTime: 2, on: scheduler)

        // Once the first request fails, at t=2, it should try an start a session.
        scheduler.run(atTime: 1) {
            // Resolve with a session at time 3.
            self.sessionManager.beginSessionResponse = self.scheduler.guarantee(
                resolvingWith: .success(Stubs.session(hasSentVerificationCode: false)),
                atTime: 3
            )
        }

        // Before requesting a session at t=2, it should ask for push tokens to give the session.
        pushRegistrationManagerMock.requestPushTokenMock = {
            XCTAssertEqual(self.scheduler.currentTime, 2)
            return .value(Stubs.apnsToken)
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

        // Check we have the master key now, to be safe.
        XCTAssert(kbs.hasMasterKey)
        scheduler.runUntilIdle()
        XCTAssertEqual(scheduler.currentTime, 4)

        // Now we should expect to be at verification code entry since we already set the phone number.
        XCTAssertEqual(nextStep.value, .verificationCodeEntry)
        // We want to have kept the master key; we failed the reg recovery pw check
        // but that could happen even if the key is valid. Once we finish session based
        // re-registration we want to be able to recover the key.
        XCTAssert(kbs.hasMasterKey)
    }

    func testRegRecoveryPwPath_failedReglock() {
        // Set profile info so we skip those steps.
        setupDefaultAccountAttributes()

        // Set a PIN on disk.
        ows2FAManagerMock.pinCodeMock = { Stubs.pinCode }

        // Make KBS give us back a reg recovery password.
        kbs.dataGenerator = {
            switch $0 {
            case .registrationRecoveryPassword:
                return Stubs.regRecoveryPwData
            case .registrationLock:
                return Stubs.reglockData
            default:
                return nil
            }
        }
        kbs.hasMasterKey = true

        // Run the scheduler for a bit; we don't care about timing these bits.
        scheduler.start()

        // We haven't set a phone number so it should ask for that.
        XCTAssertEqual(coordinator.nextStep().value, .phoneNumberEntry)

        // Give it a phone number, which should show the PIN entry step.
        var nextStep = coordinator.submitE164(Stubs.e164)
        // Now it should ask for the PIN to confirm the user knows it.
        XCTAssertEqual(nextStep.value, .pinEntry)

        // Now we want to control timing so we can verify things happened in the right order.
        scheduler.stop()
        scheduler.adjustTime(to: 0)

        // Give it the pin code, which should make it try and register.
        nextStep = coordinator.submitPINCode(Stubs.pinCode)

        let expectedRecoveryPwRequest = RegistrationRequestFactory.createAccountRequest(
            verificationMethod: .recoveryPassword(Stubs.regRecoveryPw),
            e164: Stubs.e164,
            accountAttributes: Stubs.accountAttributes(),
            skipDeviceTransfer: true
        )

        // Fail the request at t=2; the reglock is invalid.
        let failResponse = TSRequestOWSURLSessionMock.Response(
            urlSuffix: expectedRecoveryPwRequest.url!.absoluteString,
            statusCode: RegistrationServiceResponses.AccountCreationResponseCodes.reglockFailed.rawValue,
            bodyJson: RegistrationServiceResponses.RegistrationLockFailureResponse(
                timeRemainingMs: 10,
                kbsAuthCredential: Stubs.kbsAuthCredential
            )
        )
        mockURLSession.addResponse(failResponse, atTime: 2, on: scheduler)

        // Once the first request fails, at t=2, it should try an start a session.
        scheduler.run(atTime: 1) {
            // Resolve with a session at time 3.
            self.sessionManager.beginSessionResponse = self.scheduler.guarantee(
                resolvingWith: .success(Stubs.session(hasSentVerificationCode: false)),
                atTime: 3
            )
        }

        // Before requesting a session at t=2, it should ask for push tokens to give the session.
        pushRegistrationManagerMock.requestPushTokenMock = {
            XCTAssertEqual(self.scheduler.currentTime, 2)
            return .value(Stubs.apnsToken)
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

        XCTAssert(kbs.hasMasterKey)
        scheduler.runUntilIdle()
        XCTAssertEqual(scheduler.currentTime, 4)

        // Now we should expect to be at verification code entry since we already set the phone number.
        XCTAssertEqual(nextStep.value, .verificationCodeEntry)
        // We want to have wiped our master key; we failed reglock, which means the key itself is
        // wrong.
        XCTAssertFalse(kbs.hasMasterKey)
    }

    // MARK: - KBS Auth Credential Path

    func testKBSAuthCredentialPath_happyPath() {
        // Run the scheduler for a bit; we don't care about timing these bits.
        scheduler.start()

        // Don't care about timing, just start it.
        setupDefaultAccountAttributes()

        // Set profile info so we skip those steps.
        self.setAllProfileInfo()

        contactsStore.doesNeedContactsAuthorization = true
        pushRegistrationManagerMock.doesNeedNotificationAuthorization = true

        // Put some auth credentials in storage.
        let credentialCandidates: [KBSAuthCredential] = [
            Stubs.kbsAuthCredential,
            KBSAuthCredential(credential: RemoteAttestation.Auth(username: "aaaa", password: "abc")),
            KBSAuthCredential(credential: RemoteAttestation.Auth(username: "zzzz", password: "xyz")),
            KBSAuthCredential(credential: RemoteAttestation.Auth(username: "0000", password: "123"))
        ]
        kbsAuthCredentialStore.dict = Dictionary(grouping: credentialCandidates, by: \.username).mapValues { $0.first! }

        // The very first thing should take us to the splash and permissions,
        // as this flow can start from a fresh device.
        XCTAssertEqual(coordinator.nextStep().value, .splash)
        XCTAssertEqual(coordinator.nextStep().value, .permissions)

        // Get past permissions.
        // We haven't set a phone number so it should ask for that next.
        XCTAssertEqual(coordinator.requestPermissions().value, .phoneNumberEntry)

        // Give it a phone number, which should cause it to check the auth credentials.
        // Match the main auth credential.
        let expectedKBSCheckRequest = RegistrationRequestFactory.kbsAuthCredentialCheckRequest(
            e164: Stubs.e164,
            credentials: credentialCandidates
        )
        mockURLSession.addResponse(TSRequestOWSURLSessionMock.Response(
            urlSuffix: expectedKBSCheckRequest.url!.absoluteString,
            statusCode: 200,
            bodyJson: RegistrationServiceResponses.KBSAuthCheckResponse(matches: [
                "\(Stubs.kbsAuthCredential.username):\(Stubs.kbsAuthCredential.credential.password)": .match,
                "aaaa:abc": .notMatch,
                "zzzz:xyz": .invalid,
                "0000:123": .unknown
            ])
        ))

        let nextStep = coordinator.submitE164(Stubs.e164).value

        // At this point, we should be asking for PIN entry so we can use the credential
        // to recover the KBS master key.
        XCTAssertEqual(nextStep, .pinEntry)
        // We should have wipted the invalid and unknown credentials.
        let remainingCredentials = kbsAuthCredentialStore.dict
        XCTAssertNotNil(remainingCredentials[Stubs.kbsAuthCredential.username])
        XCTAssertNotNil(remainingCredentials["aaaa"])
        XCTAssertNil(remainingCredentials["zzzz"])
        XCTAssertNil(remainingCredentials["0000"])

        scheduler.stop()
        scheduler.adjustTime(to: 0)

        // Enter the PIN, which should try and recover from KBS.
        // Once we do that, it should follow the Reg Recovery Password Path.
        let nextStepPromise = coordinator.submitPINCode(Stubs.pinCode)

        // At t=1, resolve the key restoration from kbs and have it start returning the key.
        kbs.restoreKeysAndBackupMock = { pin, authMethod in
            XCTAssertEqual(self.scheduler.currentTime, 0)
            XCTAssertEqual(pin, Stubs.pinCode)
            XCTAssertEqual(authMethod, .kbsAuth(Stubs.kbsAuthCredential, backup: nil))
            self.kbs.hasMasterKey = true
            return self.scheduler.guarantee(resolvingWith: .success, atTime: 1)
        }

        // At t=1 it should get the latest credentials from kbs.
        self.kbs.dataGenerator = {
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

        // Now still at t=1 it should make a reg recovery pw request, resolve it at t=2.
        let accountIdentityResponse = Stubs.accountIdentityResponse()
        let authUsername = accountIdentityResponse.aci.uuidString
        var authPassword: String!
        let expectedRegRecoveryPwRequest = RegistrationRequestFactory.createAccountRequest(
            verificationMethod: .recoveryPassword(Stubs.regRecoveryPw),
            e164: Stubs.e164,
            accountAttributes: Stubs.accountAttributes(),
            skipDeviceTransfer: true
        )
        self.mockURLSession.addResponse(
            TSRequestOWSURLSessionMock.Response(
                matcher: { request in
                    XCTAssertEqual(self.scheduler.currentTime, 1)
                    authPassword = Self.attributesFromCreateAccountRequest(request).authKey
                    return request.url == expectedRegRecoveryPwRequest.url
                },
                statusCode: 200,
                bodyJson: accountIdentityResponse
            ),
            atTime: 2,
            on: self.scheduler
        )

        // When registered at t=2, it should try and sync push tokens.
        // Resolve at t=3.
        pushRegistrationManagerMock.syncPushTokensForcingUploadMock = { username, password in
            XCTAssertEqual(self.scheduler.currentTime, 2)
            XCTAssertEqual(username, authUsername)
            XCTAssertEqual(password, authPassword)
            return self.scheduler.guarantee(resolvingWith: .success, atTime: 3)
        }

        // At t=3 once we sync push tokens, we should restore from storage service.
        accountManagerMock.performInitialStorageServiceRestoreMock = {
            XCTAssertEqual(self.scheduler.currentTime, 3)
            return self.scheduler.promise(resolvingWith: (), atTime: 4)
        }

        // And at t=4 once we do the storage service restore,
        // we will sync account attributes and then we are finished!
        let expectedAttributesRequest = RegistrationRequestFactory.updatePrimaryDeviceAccountAttributesRequest(
            Stubs.accountAttributes(),
            authUsername: "", // doesn't matter for url matching
            authPassword: "" // doesn't matter for url matching
        )
        self.mockURLSession.addResponse(
            matcher: { request in
                XCTAssertEqual(self.scheduler.currentTime, 4)
                return request.url == expectedAttributesRequest.url
            },
            statusCode: 200
        )

        for i in 0...2 {
            scheduler.run(atTime: i) {
                XCTAssertNil(nextStepPromise.value)
            }
        }

        scheduler.runUntilIdle()
        XCTAssertEqual(scheduler.currentTime, 4)

        XCTAssertEqual(nextStepPromise.value, .done)
    }

    func testKBSAuthCredentialPath_noMatchingCredentials() {
        // Don't care about timing, just start it.
        scheduler.start()

        // Set profile info so we skip those steps.
        setupDefaultAccountAttributes()

        contactsStore.doesNeedContactsAuthorization = false
        pushRegistrationManagerMock.doesNeedNotificationAuthorization = false

        // Put some auth credentials in storage.
        let credentialCandidates: [KBSAuthCredential] = [
            Stubs.kbsAuthCredential,
            KBSAuthCredential(credential: RemoteAttestation.Auth(username: "aaaa", password: "abc")),
            KBSAuthCredential(credential: RemoteAttestation.Auth(username: "zzzz", password: "xyz")),
            KBSAuthCredential(credential: RemoteAttestation.Auth(username: "0000", password: "123"))
        ]
        kbsAuthCredentialStore.dict = Dictionary(grouping: credentialCandidates, by: \.username).mapValues { $0.first! }

        // The very first thing should take us to the splash (we've granted permissions above),
        // as this flow can start from a fresh device.
        XCTAssertEqual(coordinator.nextStep().value, .splash)

        // We haven't set a phone number so it should ask for that next.
        XCTAssertEqual(coordinator.requestPermissions().value, .phoneNumberEntry)

        scheduler.stop()
        scheduler.adjustTime(to: 0)

        // Give it a phone number, which should cause it to check the auth credentials.
        let nextStep = coordinator.submitE164(Stubs.e164)

        // Don't give back any matches at t=2, which means we will want to create a session as a fallback.
        let expectedKBSCheckRequest = RegistrationRequestFactory.kbsAuthCredentialCheckRequest(
            e164: Stubs.e164,
            credentials: credentialCandidates
        )
        mockURLSession.addResponse(
            TSRequestOWSURLSessionMock.Response(
                urlSuffix: expectedKBSCheckRequest.url!.absoluteString,
                statusCode: 200,
                bodyJson: RegistrationServiceResponses.KBSAuthCheckResponse(matches: [
                    "\(Stubs.kbsAuthCredential.username):\(Stubs.kbsAuthCredential.credential.password)": .notMatch,
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

        pushRegistrationManagerMock.requestPushTokenMock = { .value(Stubs.apnsToken)}

        scheduler.runUntilIdle()
        XCTAssertEqual(scheduler.currentTime, 4)

        // Now we should expect to be at verification code entry since we already set the phone number.
        XCTAssertEqual(nextStep.value, .verificationCodeEntry)

        // We should have wipted the invalid and unknown credentials.
        let remainingCredentials = kbsAuthCredentialStore.dict
        XCTAssertNotNil(remainingCredentials[Stubs.kbsAuthCredential.username])
        XCTAssertNotNil(remainingCredentials["aaaa"])
        XCTAssertNil(remainingCredentials["zzzz"])
        XCTAssertNil(remainingCredentials["0000"])
    }

    // MARK: - Session Path

    public func testSessionPath_happyPath() {
        setUpSessionPath()

        // Give it a phone number, which should cause it to start a session.
        var nextStep = coordinator.submitE164(Stubs.e164)

        // At t=2, give back a session thats ready to go.
        let sessionId = UUID().uuidString
        self.sessionManager.beginSessionResponse = self.scheduler.guarantee(
            resolvingWith: .success(RegistrationSession(
                id: sessionId,
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
            // Resolve with a session at time 3.
            self.sessionManager.requestCodeResponse = self.scheduler.guarantee(
                resolvingWith: .success(RegistrationSession(
                    id: sessionId,
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
        XCTAssertEqual(nextStep.value, .verificationCodeEntry)

        scheduler.tick()

        // Submit a code at t=5.
        scheduler.run(atTime: 5) {
            nextStep = self.coordinator.submitVerificationCode(Stubs.pinCode)
        }

        // At t=7, give back a verified session.
        self.sessionManager.submitCodeResponse = self.scheduler.guarantee(
            resolvingWith: .success(RegistrationSession(
                id: sessionId,
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
        let authUsername = accountIdentityResponse.aci.uuidString
        var authPassword: String!

        // That means at t=7 it should try and register with the verified
        // session; be ready for that starting at t=6 (but not before).
        scheduler.run(atTime: 6) {
            let expectedRequest = RegistrationRequestFactory.createAccountRequest(
                verificationMethod: .sessionId(sessionId),
                e164: Stubs.e164,
                accountAttributes: Stubs.accountAttributes(),
                skipDeviceTransfer: true
            )
            // Resolve it at t=8
            self.mockURLSession.addResponse(
                TSRequestOWSURLSessionMock.Response(
                    matcher: { request in
                        authPassword = Self.attributesFromCreateAccountRequest(request).authKey
                        return request.url == expectedRequest.url
                    },
                    statusCode: 200,
                    bodyJson: accountIdentityResponse
                ),
                atTime: 8,
                on: self.scheduler
            )
        }

        // Once we are registered at t=8, we should try and sync push tokens
        // with the credentials we got in the identity response.
        pushRegistrationManagerMock.syncPushTokensForcingUploadMock = { username, password in
            XCTAssertEqual(self.scheduler.currentTime, 8)
            XCTAssertEqual(username, authUsername)
            XCTAssertEqual(password, authPassword)
            return self.scheduler.guarantee(resolvingWith: .success, atTime: 9)
        }

        scheduler.runUntilIdle()
        XCTAssertEqual(scheduler.currentTime, 9)

        // Now we should ask for the PIN to recover our KBS data.
        XCTAssertEqual(nextStep.value, .pinEntry)

        scheduler.adjustTime(to: 0)

        // When we submit the pin, it should backup with kbs.
        nextStep = coordinator.submitPINCode(Stubs.pinCode)

        // Finish the validation at t=1.
        kbs.generateAndBackupKeysMock = { pin, authMethod, rotateMasterKey in
            XCTAssertEqual(self.scheduler.currentTime, 0)
            XCTAssertEqual(pin, Stubs.pinCode)
            XCTAssertEqual(authMethod, .chatServerAuth(username: authUsername, password: authPassword))
            XCTAssertFalse(rotateMasterKey)
            return self.scheduler.promise(resolvingWith: (), atTime: 1)
        }

        // At t=1 once we sync push tokens, we should restore from storage service.
        accountManagerMock.performInitialStorageServiceRestoreMock = {
            XCTAssertEqual(self.scheduler.currentTime, 1)
            return self.scheduler.promise(resolvingWith: (), atTime: 2)
        }

        // And at t=2 once we do the storage service restore,
        // we will sync account attributes and then we are finished!
        let expectedAttributesRequest = RegistrationRequestFactory.updatePrimaryDeviceAccountAttributesRequest(
            Stubs.accountAttributes(),
            authUsername: authUsername,
            authPassword: authPassword
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

    public func testSessionPath_captchaChallenge() {
        setUpSessionPath()

        // Give it a phone number, which should cause it to start a session.
        var nextStep = coordinator.submitE164(Stubs.e164)

        // At t=2, give back a session with a captcha challenge.
        let sessionId = UUID().uuidString
        self.sessionManager.beginSessionResponse = self.scheduler.guarantee(
            resolvingWith: .success(RegistrationSession(
                id: sessionId,
                e164: Stubs.e164,
                receivedDate: date,
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
                id: sessionId,
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
                    id: sessionId,
                    e164: Stubs.e164,
                    receivedDate: self.date,
                    nextSMS: 0,
                    nextCall: 0,
                    nextVerificationAttempt: 0,
                    allowedToRequestCode: false,
                    requestedInformation: [.captcha, .pushChallenge],
                    hasUnknownChallengeRequiringAppUpdate: false,
                    verified: false
                )),
                atTime: 7
            )
        }

        // At t=7 we should get back the code entry step.
        scheduler.runUntilIdle()
        XCTAssertEqual(scheduler.currentTime, 7)
        XCTAssertEqual(nextStep.value, .verificationCodeEntry)

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
                id: sessionId,
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
        let secondCodeDate = date.addingTimeInterval(10)
        scheduler.run(atTime: 9) {
            self.sessionManager.requestCodeResponse = self.scheduler.guarantee(
                resolvingWith: .success(RegistrationSession(
                    id: sessionId,
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
        XCTAssertEqual(nextStep.value, .verificationCodeEntry)
    }

    public func testSessionPath_unknownChallenge() {
        setUpSessionPath()

        // Give it a phone number, which should cause it to start a session.
        var nextStep = coordinator.submitE164(Stubs.e164)

        // At t=2, give back a session with a captcha challenge and an unknown challenge.
        let sessionId = UUID().uuidString
        self.sessionManager.beginSessionResponse = self.scheduler.guarantee(
            resolvingWith: .success(RegistrationSession(
                id: sessionId,
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
                id: sessionId,
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

    // TODO[Registration]: test push notification challenge fulfillment.

    // TODO[Registration]: test timeouts, retries, and invalid arguments.
    // These must be representable in the RegistrationStep case associated values
    // before we can test against them.

    public func testSessionPath_expiredSession() {
       setUpSessionPath()

        // Give it a phone number, which should cause it to start a session.
        var nextStep = coordinator.submitE164(Stubs.e164)

        // At t=2, give back a session thats ready to go.
        let sessionId = UUID().uuidString
        self.sessionManager.beginSessionResponse = self.scheduler.guarantee(
            resolvingWith: .success(RegistrationSession(
                id: sessionId,
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
            // Resolve with a session at time 3.
            self.sessionManager.requestCodeResponse = self.scheduler.guarantee(
                resolvingWith: .success(RegistrationSession(
                    id: sessionId,
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
        XCTAssertEqual(nextStep.value, .verificationCodeEntry)

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

        // That means at t=7 it should fall all the way back to phone
        // number entry.
        scheduler.runUntilIdle()
        XCTAssertEqual(scheduler.currentTime, 7)
        // TODO[Registration]: test error state on the phone number entry screen.
        XCTAssertEqual(nextStep.value, .phoneNumberEntry)
    }

    // MARK: - Profile Setup Path

    // TODO[Registration]: test the profile setup steps.

    // MARK: - Helpers

    private func setupDefaultAccountAttributes() {
        ows2FAManagerMock.pinCodeMock = { nil }
        ows2FAManagerMock.isReglockEnabledMock = { false }

        tsAccountManagerMock.isManualMessageFetchEnabledMock = { false }

        setAllProfileInfo()
    }

    private func setAllProfileInfo() {
        tsAccountManagerMock.hasDefinedIsDiscoverableByPhoneNumberMock = { true }
        profileManagerMock.hasProfileNameMock = { true }
    }

    private func setUpSessionPath() {
        // Don't care about timing, just start it.
        scheduler.start()

        // Set profile info so we skip those steps.
        self.setupDefaultAccountAttributes()

        pushRegistrationManagerMock.requestPushTokenMock = { .value(Stubs.apnsToken)}

        contactsStore.doesNeedContactsAuthorization = true
        pushRegistrationManagerMock.doesNeedNotificationAuthorization = true

        // No other setup; no auth credentials, kbs keys, etc in storage
        // so that we immediately go to the session flow.

        // The very first thing should take us to the splash and permissions,
        // as this flow can start from a fresh device.
        XCTAssertEqual(coordinator.nextStep().value, .splash)
        XCTAssertEqual(coordinator.nextStep().value, .permissions)

        // Get past permissions.
        // We haven't set a phone number so it should ask for that next.
        XCTAssertEqual(coordinator.requestPermissions().value, .phoneNumberEntry)

        scheduler.stop()
        scheduler.adjustTime(to: 0)
    }

    private static func attributesFromCreateAccountRequest(
        _ request: TSRequest
    ) -> RegistrationRequestFactory.AccountAttributes {
        return request.parameters["accountAttributes"] as! RegistrationRequestFactory.AccountAttributes
    }

    // MARK: - Stubs

    private enum Stubs {

        static let e164 = "+17875550100"
        static let pinCode = "1234"

        static let regRecoveryPwData = Data(repeating: 8, count: 8)
        static var regRecoveryPw: String { regRecoveryPwData.base64EncodedString() }

        static let reglockData = Data(repeating: 7, count: 8)
        static var reglockToken: String { reglockData.hexadecimalString }

        static let kbsAuthCredential = KBSAuthCredential(credential: RemoteAttestation.Auth(username: "abcd", password: "1234"))

        static let captchaToken = "captchaToken"
        static let apnsToken = "apnsToken"

        static let authUsername = "username_jdhfsalkjfhd"
        static let authPassword = "password_dskafjasldkfjasf"

        static var date: Date!

        static func accountAttributes() -> RegistrationRequestFactory.AccountAttributes {
            return RegistrationRequestFactory.AccountAttributes(
                authKey: "",
                isManualMessageFetchEnabled: false,
                registrationId: 0,
                pniRegistrationId: 0,
                unidentifiedAccessKey: "",
                unrestrictedUnidentifiedAccess: false,
                registrationLockToken: nil,
                encryptedDeviceName: nil,
                discoverableByPhoneNumber: false,
                canReceiveGiftBadges: false
            )
        }

        static func accountIdentityResponse() -> RegistrationServiceResponses.AccountIdentityResponse {
            return RegistrationServiceResponses.AccountIdentityResponse(
                aci: UUID(),
                pni: UUID(),
                e164: e164,
                username: nil,
                hasPreviouslyUsedKBS: false
            )
        }

        static func session(hasSentVerificationCode: Bool) -> RegistrationSession {
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
    }
}
