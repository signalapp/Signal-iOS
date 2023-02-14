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

    private var contactsStore: RegistrationCoordinatorImpl.TestMocks.ContactsStore!
    private var kbs: KeyBackupServiceMock!
    private var kbsAuthCredentialStore: KBSAuthCredentialStorageMock!
    private var mockURLSession: TSRequestOWSURLSessionMock!
    private var ows2FAManagerMock: RegistrationCoordinatorImpl.TestMocks.OWS2FAManager!
    private var profileManagerMock: RegistrationCoordinatorImpl.TestMocks.ProfileManager!
    private var pushRegistrationManagerMock: RegistrationCoordinatorImpl.TestMocks.PushRegistrationManager!
    private var sessionManager: RegistrationSessionManagerMock!
    private var tsAccountManagerMock: RegistrationCoordinatorImpl.TestMocks.TSAccountManager!

    public override func setUp() {
        super.setUp()

        Stubs.date = date

        contactsStore = RegistrationCoordinatorImpl.TestMocks.ContactsStore()
        kbs = KeyBackupServiceMock()
        kbsAuthCredentialStore = KBSAuthCredentialStorageMock()
        ows2FAManagerMock = RegistrationCoordinatorImpl.TestMocks.OWS2FAManager()
        profileManagerMock = RegistrationCoordinatorImpl.TestMocks.ProfileManager()
        pushRegistrationManagerMock = RegistrationCoordinatorImpl.TestMocks.PushRegistrationManager()
        sessionManager = RegistrationSessionManagerMock()
        tsAccountManagerMock = RegistrationCoordinatorImpl.TestMocks.TSAccountManager()

        let mockURLSession = TSRequestOWSURLSessionMock()
        self.mockURLSession = mockURLSession
        let mockSignalService = OWSSignalServiceMock()
        mockSignalService.mockUrlSessionBuilder = { _, _, _ in
            return mockURLSession
        }

        scheduler = TestScheduler()

        coordinator = RegistrationCoordinatorImpl(
            contactsStore: contactsStore,
            dateProvider: { self.date },
            db: MockDB(),
            kbs: kbs,
            kbsAuthCredentialStore: kbsAuthCredentialStore,
            keyValueStoreFactory: InMemoryKeyValueStoreFactory(),
            ows2FAManager: ows2FAManagerMock,
            profileManager: profileManagerMock,
            pushRegistrationManager: pushRegistrationManagerMock,
            schedulers: TestSchedulers(scheduler: scheduler),
            sessionManager: sessionManager,
            signalService: mockSignalService,
            tsAccountManager: tsAccountManagerMock
        )
    }

    // MARK: - Opening Path

    func testOpeningPath_splash() {
        // Don't care about timing, just start it.
        scheduler.start()

        // With no state set up, should show the splash.
        XCTAssertEqual(coordinator.nextStep().value, .splash)
        // Once we show it, don't show it again.
        XCTAssertNotEqual(coordinator.nextStep().value, .splash)
    }

    func testOpeningPath_contacts() {
        // Don't care about timing, just start it.
        scheduler.start()

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

    func testRegRecoveryPwPath_happyPath() {
        // Don't care about timing, just start it.
        scheduler.start()

        // Set profile info so we skip those steps.
        self.setAllProfileInfo()

        // Set a PIN on disk.
        ows2FAManagerMock.pinCode = Stubs.pinCode

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

        mockURLSession.addResponse(TSRequestOWSURLSessionMock.Response(
            urlSuffix: expectedRequest.url!.absoluteString,
            statusCode: 200,
            bodyJson: Stubs.accountIdentityResponse()
        ))

        nextStep = coordinator.submitPINCode(Stubs.pinCode).value
        XCTAssertEqual(nextStep, .done)
    }

    func testRegRecoveryPwPath_wrongPIN() {
        // Don't care about timing, just start it.
        scheduler.start()

        let wrongPinCode = "ABCD"

        // Set a different PIN on disk.
        ows2FAManagerMock.pinCode = Stubs.pinCode

        // Set profile info so we skip those steps.
        self.setAllProfileInfo()

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

        mockURLSession.addResponse(TSRequestOWSURLSessionMock.Response(
            urlSuffix: expectedRequest.url!.absoluteString,
            statusCode: 200,
            bodyJson: Stubs.accountIdentityResponse()
        ))

        nextStep = coordinator.submitPINCode(Stubs.pinCode).value
        XCTAssertEqual(nextStep, .done)
    }

    func testRegRecoveryPwPath_wrongPassword() {
        // Set profile info so we skip those steps.
        self.setAllProfileInfo()

        // Set a PIN on disk.
        ows2FAManagerMock.pinCode = Stubs.pinCode

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
                resolvingWith: .success(Stubs.session()),
                atTime: 3
            )
        }

        // Then when it gets back the session at t=3, it should immediately ask for
        // a verification code to be sent.
        scheduler.run(atTime: 3) {
            // Resolve with an updated session at time 4.
            self.sessionManager.requestCodeResponse = self.scheduler.guarantee(
                resolvingWith: .success(Stubs.session(lastCodeRequestDate: self.date)),
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
        self.setAllProfileInfo()

        // Set a PIN on disk.
        ows2FAManagerMock.pinCode = Stubs.pinCode

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
                resolvingWith: .success(Stubs.session()),
                atTime: 3
            )
        }

        // Then when it gets back the session at t=3, it should immediately ask for
        // a verification code to be sent.
        scheduler.run(atTime: 3) {
            // Resolve with an updated session at time 4.
            self.sessionManager.requestCodeResponse = self.scheduler.guarantee(
                resolvingWith: .success(Stubs.session(lastCodeRequestDate: self.date)),
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
        // Don't care about timing, just start it.
        scheduler.start()

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

        // At t=2, resolve the key restoration from kbs and have it start returning the key.
        scheduler.run(atTime: 2) {
            self.kbs.dataGenerator = {
                switch $0 {
                case .registrationRecoveryPassword:
                    return Stubs.regRecoveryPwData
                case .registrationLock:
                    return Stubs.reglockData
                default:
                    return nil
                }
            }
            self.kbs.hasMasterKey = true
        }
        kbs.restoreKeysAndBackupPromise = scheduler.promise(resolvingWith: (), atTime: 2)

        // At t=3, resolve the reg recovery pw request.
        scheduler.run(atTime: 1) {
            let expectedRegRecoveryPwRequest = RegistrationRequestFactory.createAccountRequest(
                verificationMethod: .recoveryPassword(Stubs.regRecoveryPw),
                e164: Stubs.e164,
                accountAttributes: Stubs.accountAttributes(),
                skipDeviceTransfer: true
            )
            self.mockURLSession.addResponse(
                TSRequestOWSURLSessionMock.Response(
                    urlSuffix: expectedRegRecoveryPwRequest.url!.absoluteString,
                    statusCode: 200,
                    bodyJson: Stubs.accountIdentityResponse()
                ),
                atTime: 3,
                on: self.scheduler
            )
        }

        for i in 0...2 {
            scheduler.run(atTime: i) {
                XCTAssertNil(nextStepPromise.value)
            }
        }

        scheduler.advance(to: 3)

        XCTAssertEqual(nextStepPromise.value, .done)
    }

    func testKBSAuthCredentialPath_noMatchingCredentials() {
        // Don't care about timing, just start it.
        scheduler.start()

        // Set profile info so we skip those steps.
        self.setAllProfileInfo()

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
                resolvingWith: .success(Stubs.session()),
                atTime: 3
            )
        }

        // Then when it gets back the session at t=3, it should immediately ask for
        // a verification code to be sent.
        scheduler.run(atTime: 3) {
            // Resolve with an updated session at time 4.
            self.sessionManager.requestCodeResponse = self.scheduler.guarantee(
                resolvingWith: .success(Stubs.session(lastCodeRequestDate: self.date)),
                atTime: 4
            )
        }

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
                nextVerificationAttempt: 0,
                allowedToRequestCode: true,
                lastCodeRequestDate: nil,
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
                    lastCodeRequestDate: self.date,
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
                nextVerificationAttempt: 0,
                allowedToRequestCode: true,
                lastCodeRequestDate: date,
                requestedInformation: [],
                hasUnknownChallengeRequiringAppUpdate: false,
                verified: true
            )),
            atTime: 7
        )

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
                    urlSuffix: expectedRequest.url!.absoluteString,
                    statusCode: 200,
                    bodyJson: Stubs.accountIdentityResponse()
                ),
                atTime: 8,
                on: self.scheduler
            )
        }

        scheduler.runUntilIdle()
        XCTAssertEqual(scheduler.currentTime, 8)

        // Now we should ask for the PIN to recover our KBS data.
        XCTAssertEqual(nextStep.value, .pinEntry)

        // TODO[Registration]: test entering the PIN and pulling data from KBS.
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
                nextVerificationAttempt: 0,
                allowedToRequestCode: false,
                lastCodeRequestDate: nil,
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
                nextVerificationAttempt: 0,
                allowedToRequestCode: true,
                lastCodeRequestDate: nil,
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
                    lastCodeRequestDate: self.date,
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
                lastCodeRequestDate: self.date,
                requestedInformation: [],
                hasUnknownChallengeRequiringAppUpdate: false,
                verified: false
            )),
            atTime: 10
        )

        // This means at t=10 when we fulfill the challenge, it should
        // immediately try and send the that couldn't be sent before because
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
                    lastCodeRequestDate: secondCodeDate,
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
                nextVerificationAttempt: 0,
                allowedToRequestCode: false,
                lastCodeRequestDate: nil,
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
                nextVerificationAttempt: 0,
                allowedToRequestCode: false,
                lastCodeRequestDate: nil,
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
                nextVerificationAttempt: 0,
                allowedToRequestCode: true,
                lastCodeRequestDate: nil,
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
                    lastCodeRequestDate: self.date,
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

    private func setAllProfileInfo() {
        tsAccountManagerMock.doesHaveDefinedIsDiscoverableByPhoneNumber = true
        profileManagerMock.hasProfileName = true
    }

    private func setUpSessionPath() {
        // Don't care about timing, just start it.
        scheduler.start()

        // Set profile info so we skip those steps.
        self.setAllProfileInfo()

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

        static func session(
            lastCodeRequestDate: Date? = nil
        ) -> RegistrationSession {
            return RegistrationSession(
                id: UUID().uuidString,
                e164: e164,
                receivedDate: date,
                nextSMS: 0,
                nextCall: 0,
                nextVerificationAttempt: 0,
                allowedToRequestCode: true,
                lastCodeRequestDate: lastCodeRequestDate,
                requestedInformation: [],
                hasUnknownChallengeRequiringAppUpdate: false,
                verified: false
            )
        }
    }
}
