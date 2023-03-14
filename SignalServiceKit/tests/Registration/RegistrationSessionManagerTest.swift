//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
@testable import SignalServiceKit
import XCTest

public class RegistrationSessionManagerTest: XCTestCase {

    private var registrationSessionManager: RegistrationSessionManagerImpl!

    private var date = Date()

    private var db: MockDB!
    private var kvStore: InMemoryKeyValueStore!
    private var mockURLSession: TSRequestOWSURLSessionMock!
    private var scheduler: TestScheduler!

    public override func setUp() {
        db = MockDB()

        let mockURLSession = TSRequestOWSURLSessionMock()
        self.mockURLSession = mockURLSession
        let mockSignalService = OWSSignalServiceMock()
        mockSignalService.mockUrlSessionBuilder = { _, _, _ in
            return mockURLSession
        }

        let kvStoreFactory = InMemoryKeyValueStoreFactory()
        kvStore = kvStoreFactory.keyValueStore(
            collection: RegistrationSessionManagerImpl.KvStore.collectionName
        ) as? InMemoryKeyValueStore

        scheduler = TestScheduler()
        // Don't care about time in these tests, just run everything sync.
        scheduler.start()

        registrationSessionManager = RegistrationSessionManagerImpl(
            dateProvider: { self.date },
            db: db,
            keyValueStoreFactory: kvStoreFactory,
            schedulers: TestSchedulers(scheduler: scheduler),
            signalService: mockSignalService
        )
    }

    public func testParseRegistrationSession() {
        let code = "1234"
        let oldSession = stubSession()
        let expectedRequest = RegistrationRequestFactory.submitVerificationCodeRequest(
            sessionId: oldSession.id,
            code: code
        )

        // A standard response
        var responseJSON = """
        {
            "id": "abcd",
            "nextSms": 1,
            "nextCall": 2,
            "nextVerificationAttempt": 3,
            "allowedToRequestCode": true,
            "requestedInformation": ["captcha", "pushChallenge"],
            "verified": false,
        }
        """

        mockURLSession.addResponse(TSRequestOWSURLSessionMock.Response(
            matcher: {  $0.url == expectedRequest.url },
            statusCode: RegistrationServiceResponses.SubmitVerificationCodeResponseCodes.success.rawValue,
            bodyData: responseJSON.data(using: .utf8)
        ))

        registrationSessionManager.requestVerificationCode(
            for: oldSession,
            transport: [Registration.CodeTransport.sms, .voice].randomElement()!
        ).done(on: scheduler) { result in
            XCTAssertEqual(result, .success(RegistrationSession(
                id: "abcd",
                e164: oldSession.e164,
                receivedDate: self.date,
                nextSMS: 1,
                nextCall: 2,
                nextVerificationAttempt: 3,
                allowedToRequestCode: true,
                requestedInformation: [.captcha, .pushChallenge],
                hasUnknownChallengeRequiringAppUpdate: false,
                verified: false
            )))
        }

        // Try empty time durations
        responseJSON = """
        {
            "id": "abcd",
            "allowedToRequestCode": true,
            "requestedInformation": ["captcha", "pushChallenge"],
            "verified": false,
        }
        """

        mockURLSession.addResponse(TSRequestOWSURLSessionMock.Response(
            matcher: {  $0.url == expectedRequest.url },
            statusCode: RegistrationServiceResponses.SubmitVerificationCodeResponseCodes.success.rawValue,
            bodyData: responseJSON.data(using: .utf8)
        ))

        registrationSessionManager.requestVerificationCode(
            for: oldSession,
            transport: [Registration.CodeTransport.sms, .voice].randomElement()!
        ).done(on: scheduler) { result in
            XCTAssertEqual(result, .success(RegistrationSession(
                id: "abcd",
                e164: oldSession.e164,
                receivedDate: self.date,
                nextSMS: nil,
                nextCall: nil,
                nextVerificationAttempt: nil,
                allowedToRequestCode: true,
                requestedInformation: [.captcha, .pushChallenge],
                hasUnknownChallengeRequiringAppUpdate: false,
                verified: false
            )))
        }

        // Try requested info we don't know how to parse.
        responseJSON = """
        {
            "id": "abcd",
            "nextSms": 1,
            "nextCall": 2,
            "nextVerificationAttempt": 3,
            "allowedToRequestCode": true,
            "requestedInformation": ["someRandomGarbage", "captcha", "pushChallenge"],
            "verified": false,
        }
        """

        mockURLSession.addResponse(TSRequestOWSURLSessionMock.Response(
            matcher: {  $0.url == expectedRequest.url },
            statusCode: RegistrationServiceResponses.SubmitVerificationCodeResponseCodes.success.rawValue,
            bodyData: responseJSON.data(using: .utf8)
        ))

        registrationSessionManager.requestVerificationCode(
            for: oldSession,
            transport: [Registration.CodeTransport.sms, .voice].randomElement()!
        ).done(on: scheduler) { result in
            XCTAssertEqual(result, .success(RegistrationSession(
                id: "abcd",
                e164: oldSession.e164,
                receivedDate: self.date,
                nextSMS: 1,
                nextCall: 2,
                nextVerificationAttempt: 3,
                allowedToRequestCode: true,
                requestedInformation: [.captcha, .pushChallenge],
                // We saw unknown challenges
                hasUnknownChallengeRequiringAppUpdate: true,
                verified: false
            )))
        }
    }

    public func testBeginOrRestoreSession() throws {
        let e164 = "+17875550100"
        let apnsToken = "1234"
        let beginSessionRequest = RegistrationRequestFactory.beginSessionRequest(
            e164: e164,
            pushToken: apnsToken,
            mcc: nil,
            mnc: nil
        )

        // Without any setup, we should try and begin a new session.

        var responseBody = stubWireSession()
        var responseSession = sessionConverter(responseBody)

        mockURLSession.addResponse(
            forUrlSuffix: beginSessionRequest.url!.relativeString,
            bodyJson: responseBody
        )
        registrationSessionManager.beginOrRestoreSession(
            e164: e164,
            apnsToken: apnsToken
        ).done(on: scheduler) { result in
            XCTAssertEqual(result, .success(responseSession))
        }

        // The session should be in storage.
        var savedSession = try db.read { transaction in
            let session: RegistrationSession? = try kvStore.getCodableValue(
                forKey: RegistrationSessionManagerImpl.KvStore.sessionKey,
                transaction: transaction
            )
            return session
        }
        XCTAssertEqual(savedSession, responseSession)

        // Now we should get back the same session if we try again, with a request
        // only to check its validity.
        var fetchSessionRequest = RegistrationRequestFactory.fetchSessionRequest(sessionId: responseSession.id)

        // Make a new instance, which shuffles the id
        responseBody = stubWireSession()
        responseSession = sessionConverter(responseBody)

        mockURLSession.addResponse(
            forUrlSuffix: fetchSessionRequest.url!.relativeString,
            bodyJson: responseBody
        )
        registrationSessionManager.beginOrRestoreSession(
            e164: e164,
            apnsToken: apnsToken
        ).done(on: scheduler) { result in
            XCTAssertEqual(result, .success(responseSession))
        }

        // The new (shuffled id) session should be in storage.
        savedSession = try db.read { transaction in
            let session: RegistrationSession? = try kvStore.getCodableValue(
                forKey: RegistrationSessionManagerImpl.KvStore.sessionKey,
                transaction: transaction
            )
            return session
        }
        XCTAssertEqual(savedSession, responseSession)

        // If we have the service respond that the session is invalid, we should get a fresh
        // session.
        fetchSessionRequest = RegistrationRequestFactory.fetchSessionRequest(sessionId: responseSession.id)

        // Make a new instance, which shuffles the id
        responseBody = stubWireSession()
        responseSession = sessionConverter(responseBody)

        mockURLSession.addResponse(
            forUrlSuffix: fetchSessionRequest.url!.relativeString,
            statusCode: RegistrationServiceResponses.FetchSessionResponseCodes.missingSession.rawValue
        )
        mockURLSession.addResponse(
            forUrlSuffix: beginSessionRequest.url!.relativeString,
            bodyJson: responseBody
        )
        registrationSessionManager.beginOrRestoreSession(
            e164: e164,
            apnsToken: apnsToken
        ).done(on: scheduler) { result in
            XCTAssertEqual(result, .success(responseSession))
        }

        // The new (shuffled id) session should be in storage.
        savedSession = try db.read { transaction in
            let session: RegistrationSession? = try kvStore.getCodableValue(
                forKey: RegistrationSessionManagerImpl.KvStore.sessionKey,
                transaction: transaction
            )
            return session
        }
        XCTAssertEqual(savedSession, responseSession)

        // If we complete the session, that should reset everything and behave like the first time.

        db.write { registrationSessionManager.clearPersistedSession($0) }

        // Should have no saved session
        savedSession = try db.read { transaction in
            let session: RegistrationSession? = try kvStore.getCodableValue(
                forKey: RegistrationSessionManagerImpl.KvStore.sessionKey,
                transaction: transaction
            )
            return session
        }
        XCTAssertNil(savedSession)

        responseBody = stubWireSession()
        responseSession = sessionConverter(responseBody)

        mockURLSession.addResponse(
            forUrlSuffix: beginSessionRequest.url!.relativeString,
            bodyJson: responseBody
        )
        registrationSessionManager.beginOrRestoreSession(
            e164: e164,
            apnsToken: apnsToken
        ).done(on: scheduler) { result in
            XCTAssertEqual(result, .success(responseSession))
        }

        // The session should be in storage.
        savedSession = try db.read { transaction in
            let session: RegistrationSession? = try kvStore.getCodableValue(
                forKey: RegistrationSessionManagerImpl.KvStore.sessionKey,
                transaction: transaction
            )
            return session
        }
        XCTAssertEqual(savedSession, responseSession)

        // If we try and request with a different e164 it should also get a new session and wipe the old one.
        let newE164 = "+17875550101"
        responseBody = stubWireSession()
        responseSession = sessionConverter(responseBody, e164: newE164)

        mockURLSession.addResponse(
            forUrlSuffix: beginSessionRequest.url!.relativeString,
            bodyJson: responseBody
        )
        registrationSessionManager.beginOrRestoreSession(
            e164: newE164,
            apnsToken: apnsToken
        ).done(on: scheduler) { result in
            XCTAssertEqual(result, .success(responseSession))
        }

        // The session should be in storage.
        savedSession = try db.read { transaction in
            let session: RegistrationSession? = try kvStore.getCodableValue(
                forKey: RegistrationSessionManagerImpl.KvStore.sessionKey,
                transaction: transaction
            )
            return session
        }
        XCTAssertEqual(savedSession, responseSession)
    }

    public func testFulfillChallenge() {
        let captchaToken = "1234"
        let pushChallengeToken = "ABCD"
        let oldSession = stubSession()
        let expectedRequest = RegistrationRequestFactory.fulfillChallengeRequest(
            sessionId: oldSession.id,
            captchaToken: captchaToken, // Put both, doesn't matter cuz we just match the url.
            pushChallengeToken: pushChallengeToken
        )

        // will have a new id, which is fine cuz it lets us differentiate.
        let responseBody = stubWireSession()
        let responseSession = sessionConverter(responseBody)

        let statusCodeResponsePairs: [(
            RegistrationServiceResponses.FulfillChallengeResponseCodes,
            Registration.UpdateSessionResponse,
            Bool // expects session in response
        )] = [
            (.success, .success(responseSession), true),
            (.notAccepted, .rejectedArgument(responseSession), true),
            (.missingSession, .invalidSession, false),
            (.notAccepted, .rejectedArgument(responseSession), true),
            (.unexpectedError, .genericError, false)
        ]
        for (statusCode, expectedResponse, sessionInBody) in statusCodeResponsePairs {
            mockURLSession.addResponse(
                forUrlSuffix: expectedRequest.url!.relativeString,
                statusCode: statusCode.rawValue,
                bodyJson: sessionInBody ? responseBody : nil
            )
            registrationSessionManager.fulfillChallenge(
                for: oldSession,
                fulfillment: [
                    Registration.ChallengeFulfillment.captcha(captchaToken),
                    .pushChallenge(pushChallengeToken)
                ].randomElement()!
            ).done(on: scheduler) { result in
                XCTAssertEqual(result, expectedResponse)
            }
        }
    }

    public func testFulfillChallenge_sucessResponseWithoutBody() {
        let captchaToken = "1234"
        let oldSession = stubSession()
        let expectedRequest = RegistrationRequestFactory.fulfillChallengeRequest(
            sessionId: oldSession.id,
            captchaToken: captchaToken,
            pushChallengeToken: nil
        )

        mockURLSession.addResponse(
            forUrlSuffix: expectedRequest.url!.relativeString,
            statusCode: RegistrationServiceResponses.FulfillChallengeResponseCodes.success.rawValue,
            bodyJson: nil /* empty json */
        )
        registrationSessionManager.fulfillChallenge(
            for: oldSession,
            fulfillment: .captcha(captchaToken)
        ).done(on: scheduler) { result in
            XCTAssertEqual(result, Registration.UpdateSessionResponse.genericError)
        }
    }

    public func testRequestVerificationCode() {
        let oldSession = stubSession()
        let expectedRequest = RegistrationRequestFactory.requestVerificationCodeRequest(
            sessionId: oldSession.id,
            languageCode: nil,
            countryCode: nil,
            transport: .sms
        )

        // will have a new id, which is fine cuz it lets us differentiate.
        let responseBody = stubWireSession()

        let statusCodeResponsePairs: [(
            RegistrationServiceResponses.RequestVerificationCodeResponseCodes,
            Registration.UpdateSessionResponse,
            Bool // expects session in response
        )] = [
            (.success, .success(sessionConverter(responseBody)), true),
            (.malformedRequest, .genericError, false),
            (.disallowed, .disallowed(sessionConverter(responseBody)), true),
            (.missingSession, .invalidSession, false),
            (.retry, .retryAfterTimeout(sessionConverter(responseBody)), true),
            (.unexpectedError, .genericError, false)
        ]
        for (statusCode, expectedResponse, sessionInBody) in statusCodeResponsePairs {
            mockURLSession.addResponse(
                forUrlSuffix: expectedRequest.url!.relativeString,
                statusCode: statusCode.rawValue,
                bodyJson: sessionInBody ? responseBody : nil
            )
            registrationSessionManager.requestVerificationCode(
                for: oldSession,
                transport: [Registration.CodeTransport.sms, .voice].randomElement()!
            ).done(on: scheduler) { result in
                XCTAssertEqual(result, expectedResponse)
            }
        }
    }

    public func testRequestVerificationCodeServiceError() {
        let oldSession = stubSession()
        let expectedRequest = RegistrationRequestFactory.requestVerificationCodeRequest(
            sessionId: oldSession.id,
            languageCode: nil,
            countryCode: nil,
            transport: .sms
        )

        var errorResponseJSON = """
        {
            "permanentFailure": false,
            "reason": "providerRejected"
        }
        """

        mockURLSession.addResponse(TSRequestOWSURLSessionMock.Response(
            matcher: {  $0.url == expectedRequest.url },
            statusCode: RegistrationServiceResponses.RequestVerificationCodeResponseCodes.providerFailure.rawValue,
            bodyData: errorResponseJSON.data(using: .utf8)
        ))

        registrationSessionManager.requestVerificationCode(
            for: oldSession,
            transport: [Registration.CodeTransport.sms, .voice].randomElement()!
        ).done(on: scheduler) { result in
            XCTAssertEqual(result, .serverFailure(Registration.ServerFailureResponse(
                session: oldSession,
                isPermanent: false,
                reason: .providerRejected
            )))
        }

        errorResponseJSON = """
        {
            "permanentFailure": false,
            "reason": "someRandomValueTheClientCantParse"
        }
        """

        mockURLSession.addResponse(TSRequestOWSURLSessionMock.Response(
            matcher: {  $0.url == expectedRequest.url },
            statusCode: RegistrationServiceResponses.RequestVerificationCodeResponseCodes.providerFailure.rawValue,
            bodyData: errorResponseJSON.data(using: .utf8)
        ))

        registrationSessionManager.requestVerificationCode(
            for: oldSession,
            transport: [Registration.CodeTransport.sms, .voice].randomElement()!
        ).done(on: scheduler) { result in
            XCTAssertEqual(result, .serverFailure(Registration.ServerFailureResponse(
                session: oldSession,
                isPermanent: false,
                reason: nil
            )))
        }
    }

    public func testSubmitVerificationCode() {
        let code = "1234"
        let oldSession = stubSession()
        let expectedRequest = RegistrationRequestFactory.submitVerificationCodeRequest(
            sessionId: oldSession.id,
            code: code
        )

        // will have a new ids, which is fine cuz it lets us differentiate.
        let verifiedResponseBody = stubWireSession(verified: true)
        let verifiedResponseSession = sessionConverter(verifiedResponseBody)
        let unVerifiedResponseBody = stubWireSession(verified: false)
        let unVerifiedResponseSession = sessionConverter(unVerifiedResponseBody)
        let unVerifiedWithNoAttemptResponseBody = stubWireSession(verified: false, hasNextVerificationAttempt: false)
        let unVerifiedWithNoAttemptResponseSession = sessionConverter(unVerifiedWithNoAttemptResponseBody)

        let statusCodeResponsePairs: [(
            RegistrationServiceResponses.SubmitVerificationCodeResponseCodes,
            Registration.UpdateSessionResponse,
            RegistrationServiceResponses.RegistrationSession?
        )] = [
            (.success, .success(verifiedResponseSession), verifiedResponseBody),
            (.success, .rejectedArgument(unVerifiedResponseSession), unVerifiedResponseBody),
            (.malformedRequest, .genericError, nil),
            (.missingSession, .invalidSession, nil),
            (.newCodeRequired, .success(verifiedResponseSession), verifiedResponseBody),
            (.newCodeRequired, .retryAfterTimeout(unVerifiedResponseSession), unVerifiedResponseBody),
            (.newCodeRequired, .disallowed(unVerifiedWithNoAttemptResponseSession), unVerifiedWithNoAttemptResponseBody),
            (.retry, .retryAfterTimeout(unVerifiedResponseSession), unVerifiedResponseBody),
            (.unexpectedError, .genericError, nil)
        ]
        for (statusCode, expectedResponse, sessionInBody) in statusCodeResponsePairs {
            mockURLSession.addResponse(
                forUrlSuffix: expectedRequest.url!.relativeString,
                statusCode: statusCode.rawValue,
                bodyJson: sessionInBody
            )
            registrationSessionManager.submitVerificationCode(
                for: oldSession,
                code: code
            ).done(on: scheduler) { result in
                XCTAssertEqual(result, expectedResponse)
            }
        }
    }

    // MARK: - Helpers

    // MARK: Stub objects

    private func stubSession() -> RegistrationSession {
        return RegistrationSession(
            id: UUID().uuidString,
            e164: "+17875550100", // For our purposes, can be fixed.
            receivedDate: date,
            nextSMS: 1,
            nextCall: 1,
            nextVerificationAttempt: nil,
            allowedToRequestCode: true,
            requestedInformation: [],
            hasUnknownChallengeRequiringAppUpdate: false,
            verified: false
        )
    }

    private func stubWireSession(
        verified: Bool = false,
        hasNextVerificationAttempt: Bool = true
    ) -> RegistrationServiceResponses.RegistrationSession {
        return RegistrationServiceResponses.RegistrationSession(
            id: UUID().uuidString,
            nextSms: (0...100).randomElement(),
            nextCall: (0...100).randomElement(),
            nextVerificationAttempt: hasNextVerificationAttempt ? (0...100).randomElement() : nil,
            allowedToRequestCode: false,
            requestedInformation: [.captcha, .pushChallenge],
            verified: verified
        )
    }

    // Keep this independent of the production code converter for an extra layer of durability.
    private func sessionConverter(
        _ wireSession: RegistrationServiceResponses.RegistrationSession,
        e164: String = "+17875550100"
    ) -> RegistrationSession {
        let requestedInformation: [RegistrationSession.Challenge] = wireSession.requestedInformation.compactMap {
            switch $0 {
            case .captcha: return .captcha
            case .pushChallenge: return .pushChallenge
            case .unknown:
                XCTFail("If you want to test wire conversion for real be explicit")
                return .captcha
            }
        }
        return RegistrationSession(
            id: wireSession.id,
            e164: e164,
            receivedDate: date,
            nextSMS: wireSession.nextSms.map { TimeInterval($0) },
            nextCall: wireSession.nextCall.map { TimeInterval($0) },
            nextVerificationAttempt: wireSession.nextVerificationAttempt.map { TimeInterval($0) },
            allowedToRequestCode: wireSession.allowedToRequestCode,
            requestedInformation: requestedInformation,
            hasUnknownChallengeRequiringAppUpdate: false,
            verified: wireSession.verified
        )
    }
}
