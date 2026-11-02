//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
public import XCTest
@testable import SignalServiceKit

public class RegistrationSessionManagerTest: XCTestCase {

    private var registrationSessionManager: RegistrationSessionManagerImpl!

    private var date = Date()

    private var db: InMemoryDB!
    private var kvStore: KeyValueStore!
    private var networkManager: MockNetworkManager!

    override public func setUp() {
        db = InMemoryDB()

        kvStore = KeyValueStore(
            collection: RegistrationSessionManagerImpl.KvStore.collectionName,
        )

        networkManager = MockNetworkManager()

        registrationSessionManager = RegistrationSessionManagerImpl(
            dateProvider: { self.date },
            db: db,
            networkManager: networkManager,
        )
    }

    public func testParseRegistrationSession() async throws {
        let code = "1234"
        let oldSession = stubSession()
        let expectedRequest = RegistrationRequestFactory.submitVerificationCodeRequest(
            sessionId: oldSession.id,
            code: code,
            logger: .empty(),
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

        networkManager.asyncRequestHandlers.append(MockNetworkManager.mockResponse(
            matchingRequest: { $0.url == expectedRequest.url },
            statusCode: RegistrationServiceResponses.SubmitVerificationCodeResponseCodes.success.rawValue,
            bodyData: responseJSON.data(using: .utf8),
        ))

        do {
            let result = await registrationSessionManager.requestVerificationCode(
                for: oldSession,
                transport: [Registration.CodeTransport.sms, .voice].randomElement()!,
                logger: .empty(),
            )

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
                verified: false,
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

        networkManager.asyncRequestHandlers.append(MockNetworkManager.mockResponse(
            matchingRequest: { $0.url == expectedRequest.url },
            statusCode: RegistrationServiceResponses.SubmitVerificationCodeResponseCodes.success.rawValue,
            bodyData: responseJSON.data(using: .utf8),
        ))

        do {
            let result = await registrationSessionManager.requestVerificationCode(
                for: oldSession,
                transport: [Registration.CodeTransport.sms, .voice].randomElement()!,
                logger: .empty(),
            )

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
                verified: false,
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

        networkManager.asyncRequestHandlers.append(MockNetworkManager.mockResponse(
            matchingRequest: { $0.url == expectedRequest.url },
            statusCode: RegistrationServiceResponses.SubmitVerificationCodeResponseCodes.success.rawValue,
            bodyData: responseJSON.data(using: .utf8),
        ))

        do {
            let result = await registrationSessionManager.requestVerificationCode(
                for: oldSession,
                transport: [Registration.CodeTransport.sms, .voice].randomElement()!,
                logger: .empty(),
            )

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
                verified: false,
            )))
        }
    }

    public func testBeginOrRestoreSession() async throws {
        let e164 = E164("+17875550100")!
        let apnsToken = "1234"
        let beginSessionRequest = RegistrationRequestFactory.beginSessionRequest(
            e164: e164,
            pushToken: apnsToken,
            mcc: nil,
            mnc: nil,
            logger: .empty(),
        )

        // Without any setup, we should try and begin a new session.

        var responseBody = stubWireSession()
        var responseSession = sessionConverter(responseBody)

        networkManager.asyncRequestHandlers.append(MockNetworkManager.mockResponse(
            matchingRequest: { $0.url.relativeString.hasSuffix(beginSessionRequest.url.relativeString) },
            bodyJson: responseBody,
        ))
        do {
            let result = try await registrationSessionManager.beginOrRestoreSession(
                e164: e164,
                apnsToken: apnsToken,
                logger: .empty(),
            )
            XCTAssertEqual(result, responseSession)
        }

        // The session should be in storage.
        var savedSession = try db.read { transaction in
            let session: RegistrationSession? = try kvStore.getCodableValue(
                forKey: RegistrationSessionManagerImpl.KvStore.sessionKey,
                transaction: transaction,
            )
            return session
        }
        XCTAssertEqual(savedSession, responseSession)

        // Now we should get back the same session if we try again, with a request
        // only to check its validity.
        var fetchSessionRequest = RegistrationRequestFactory.fetchSessionRequest(
            sessionId: responseSession.id,
            logger: .empty(),
        )

        // Make a new instance, which shuffles the id
        responseBody = stubWireSession()
        responseSession = sessionConverter(responseBody)

        networkManager.asyncRequestHandlers.append(MockNetworkManager.mockResponse(
            matchingRequest: { $0.url.relativeString.hasSuffix(fetchSessionRequest.url.relativeString) },
            bodyJson: responseBody,
        ))
        do {
            let result = try await registrationSessionManager.beginOrRestoreSession(
                e164: e164,
                apnsToken: apnsToken,
                logger: .empty(),
            )
            XCTAssertEqual(result, responseSession)
        }

        // The new (shuffled id) session should be in storage.
        savedSession = try db.read { transaction in
            let session: RegistrationSession? = try kvStore.getCodableValue(
                forKey: RegistrationSessionManagerImpl.KvStore.sessionKey,
                transaction: transaction,
            )
            return session
        }
        XCTAssertEqual(savedSession, responseSession)

        // If we have the service respond that the session is invalid, we should get a fresh
        // session.
        fetchSessionRequest = RegistrationRequestFactory.fetchSessionRequest(
            sessionId: responseSession.id,
            logger: .empty(),
        )

        // Make a new instance, which shuffles the id
        responseBody = stubWireSession()
        responseSession = sessionConverter(responseBody)

        networkManager.asyncRequestHandlers.append(MockNetworkManager.mockResponse(
            matchingRequest: { $0.url.relativeString.hasSuffix(fetchSessionRequest.url.absoluteString) },
            statusCode: RegistrationServiceResponses.FetchSessionResponseCodes.missingSession.rawValue,
        ))
        networkManager.asyncRequestHandlers.append(MockNetworkManager.mockResponse(
            matchingRequest: { $0.url.relativeString.hasSuffix(beginSessionRequest.url.relativeString) },
            bodyJson: responseBody,
        ))
        do {
            let result = try await registrationSessionManager.beginOrRestoreSession(
                e164: e164,
                apnsToken: apnsToken,
                logger: .empty(),
            )
            XCTAssertEqual(result, responseSession)
        }

        // The new (shuffled id) session should be in storage.
        savedSession = try db.read { transaction in
            let session: RegistrationSession? = try kvStore.getCodableValue(
                forKey: RegistrationSessionManagerImpl.KvStore.sessionKey,
                transaction: transaction,
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
                transaction: transaction,
            )
            return session
        }
        XCTAssertNil(savedSession)

        responseBody = stubWireSession()
        responseSession = sessionConverter(responseBody)

        networkManager.asyncRequestHandlers.append(MockNetworkManager.mockResponse(
            matchingRequest: { $0.url.relativeString.hasSuffix(beginSessionRequest.url.relativeString) },
            bodyJson: responseBody,
        ))
        do {
            let result = try await registrationSessionManager.beginOrRestoreSession(
                e164: e164,
                apnsToken: apnsToken,
                logger: .empty(),
            )
            XCTAssertEqual(result, responseSession)
        }

        // The session should be in storage.
        savedSession = try db.read { transaction in
            let session: RegistrationSession? = try kvStore.getCodableValue(
                forKey: RegistrationSessionManagerImpl.KvStore.sessionKey,
                transaction: transaction,
            )
            return session
        }
        XCTAssertEqual(savedSession, responseSession)

        // If we try and request with a different e164 it should also get a new session and wipe the old one.
        let newE164 = E164("+17875550101")!
        responseBody = stubWireSession()
        responseSession = sessionConverter(responseBody, e164: newE164)

        networkManager.asyncRequestHandlers.append(MockNetworkManager.mockResponse(
            matchingRequest: { $0.url.relativeString.hasSuffix(beginSessionRequest.url.relativeString) },
            bodyJson: responseBody,
        ))
        do {
            let result = try await registrationSessionManager.beginOrRestoreSession(
                e164: newE164,
                apnsToken: apnsToken,
                logger: .empty(),
            )
            XCTAssertEqual(result, responseSession)
        }

        // The session should be in storage.
        savedSession = try db.read { transaction in
            let session: RegistrationSession? = try kvStore.getCodableValue(
                forKey: RegistrationSessionManagerImpl.KvStore.sessionKey,
                transaction: transaction,
            )
            return session
        }
        XCTAssertEqual(savedSession, responseSession)
    }

    public func testFulfillChallenge() async throws {
        let captchaToken = "1234"
        let pushChallengeToken = "ABCD"
        let oldSession = stubSession()

        // will have a new id, which is fine cuz it lets us differentiate.
        let responseBody = stubWireSession()
        let responseSession = sessionConverter(responseBody)

        func mockResponse(statusCode: Int, hasSession: Bool) {
            networkManager.asyncRequestHandlers.append(MockNetworkManager.mockResponse(
                matchingRequest: { $0.method == "PATCH" && $0.url.relativeString.hasPrefix("v1/verification/session/") },
                statusCode: statusCode,
                bodyJson: hasSession ? responseBody : nil,
            ))
        }

        var session = oldSession
        func fulfillChallenge() async throws {
            session = oldSession
            try await registrationSessionManager.fulfillChallenge(
                for: &session,
                fulfillment: [
                    Registration.ChallengeFulfillment.captcha(captchaToken),
                    .pushChallenge(pushChallengeToken),
                ].randomElement()!,
                logger: .empty(),
            )
        }

        // Happy path
        do {
            mockResponse(statusCode: 200, hasSession: true)
            try await fulfillChallenge()
            XCTAssertEqual(session, responseSession)
        }

        // Throw an error if the server doesn't provide a body
        do {
            mockResponse(statusCode: 200, hasSession: false)
            try await fulfillChallenge()
            XCTFail("must throw error")
        } catch is Registration.MissingSessionError {
            XCTFail("must not throw this error")
        } catch {
            // OK
        }

        do {
            mockResponse(statusCode: 403, hasSession: true)
            try await fulfillChallenge()
            XCTFail("must throw error")
        } catch where error.httpStatusCode == Registration.challengeRejectedErrorCode {
            XCTAssertEqual(session, responseSession)
        }

        do {
            mockResponse(statusCode: 404, hasSession: true)
            try await fulfillChallenge()
            XCTFail("must throw error")
        } catch is Registration.MissingSessionError {
            // OK
        }

        do {
            mockResponse(statusCode: 400, hasSession: true)
            try await fulfillChallenge()
            XCTFail("must throw error")
        } catch is Registration.MissingSessionError {
            XCTFail("must not throw this error")
        } catch {
            // OK
        }
    }

    public func testRequestVerificationCode() async {
        let oldSession = stubSession()
        let expectedRequest = RegistrationRequestFactory.requestVerificationCodeRequest(
            sessionId: oldSession.id,
            languageCode: nil,
            countryCode: nil,
            transport: .sms,
            logger: .empty(),
        )

        // will have a new id, which is fine cuz it lets us differentiate.
        let responseBody = stubWireSession()

        let statusCodeResponsePairs: [(
            RegistrationServiceResponses.RequestVerificationCodeResponseCodes,
            Registration.UpdateSessionResponse,
            Bool, // expects session in response
        )] = [
            (.success, .success(sessionConverter(responseBody)), true),
            (.malformedRequest, .genericError, false),
            (.disallowed, .disallowed(sessionConverter(responseBody)), true),
            (.missingSession, .invalidSession, false),
            (.retry, .retryAfterTimeout(sessionConverter(responseBody), retryAfterHeader: nil), true),
            (.unexpectedError, .genericError, false),
        ]
        for (statusCode, expectedResponse, sessionInBody) in statusCodeResponsePairs {
            networkManager.asyncRequestHandlers.append(MockNetworkManager.mockResponse(
                matchingRequest: { $0.url.relativeString.hasSuffix(expectedRequest.url.relativeString) },
                statusCode: statusCode.rawValue,
                bodyJson: sessionInBody ? responseBody : nil,
            ))
            let result = await registrationSessionManager.requestVerificationCode(
                for: oldSession,
                transport: [Registration.CodeTransport.sms, .voice].randomElement()!,
                logger: .empty(),
            )
            XCTAssertEqual(result, expectedResponse)
        }
    }

    public func testRequestVerificationCodeServiceError() async {
        let oldSession = stubSession()
        let expectedRequest = RegistrationRequestFactory.requestVerificationCodeRequest(
            sessionId: oldSession.id,
            languageCode: nil,
            countryCode: nil,
            transport: .sms,
            logger: .empty(),
        )

        var errorResponseJSON = """
        {
            "permanentFailure": false,
            "reason": "providerRejected"
        }
        """

        networkManager.asyncRequestHandlers.append(MockNetworkManager.mockResponse(
            matchingRequest: { $0.url == expectedRequest.url },
            statusCode: RegistrationServiceResponses.RequestVerificationCodeResponseCodes.providerFailure.rawValue,
            bodyData: errorResponseJSON.data(using: .utf8),
        ))

        do {
            let result = await registrationSessionManager.requestVerificationCode(
                for: oldSession,
                transport: [Registration.CodeTransport.sms, .voice].randomElement()!,
                logger: .empty(),
            )
            XCTAssertEqual(result, .serverFailure(Registration.ServerFailureResponse(
                session: oldSession,
                isPermanent: false,
                reason: .providerRejected,
            )))
        }

        errorResponseJSON = """
        {
            "permanentFailure": false,
            "reason": "someRandomValueTheClientCantParse"
        }
        """

        networkManager.asyncRequestHandlers.append(MockNetworkManager.mockResponse(
            matchingRequest: { $0.url == expectedRequest.url },
            statusCode: RegistrationServiceResponses.RequestVerificationCodeResponseCodes.providerFailure.rawValue,
            bodyData: errorResponseJSON.data(using: .utf8),
        ))

        do {
            let result = await registrationSessionManager.requestVerificationCode(
                for: oldSession,
                transport: [Registration.CodeTransport.sms, .voice].randomElement()!,
                logger: .empty(),
            )
            XCTAssertEqual(result, .serverFailure(Registration.ServerFailureResponse(
                session: oldSession,
                isPermanent: false,
                reason: nil,
            )))
        }
    }

    public func testSubmitVerificationCode() async {
        let code = "1234"
        let oldSession = stubSession()
        let expectedRequest = RegistrationRequestFactory.submitVerificationCodeRequest(
            sessionId: oldSession.id,
            code: code,
            logger: .empty(),
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
            RegistrationServiceResponses.RegistrationSession?,
        )] = [
            (.success, .success(verifiedResponseSession), verifiedResponseBody),
            (.success, .rejectedArgument(unVerifiedResponseSession), unVerifiedResponseBody),
            (.malformedRequest, .genericError, nil),
            (.missingSession, .invalidSession, nil),
            (.newCodeRequired, .success(verifiedResponseSession), verifiedResponseBody),
            (.newCodeRequired, .retryAfterTimeout(unVerifiedResponseSession, retryAfterHeader: nil), unVerifiedResponseBody),
            (.newCodeRequired, .disallowed(unVerifiedWithNoAttemptResponseSession), unVerifiedWithNoAttemptResponseBody),
            (.retry, .retryAfterTimeout(unVerifiedResponseSession, retryAfterHeader: nil), unVerifiedResponseBody),
            (.unexpectedError, .genericError, nil),
        ]
        for (statusCode, expectedResponse, sessionInBody) in statusCodeResponsePairs {
            networkManager.asyncRequestHandlers.append(MockNetworkManager.mockResponse(
                matchingRequest: { $0.url.relativeString.hasSuffix(expectedRequest.url.relativeString) },
                statusCode: statusCode.rawValue,
                bodyJson: sessionInBody,
            ))
            let result = await registrationSessionManager.submitVerificationCode(
                for: oldSession,
                code: code,
                logger: .empty(),
            )
            XCTAssertEqual(result, expectedResponse)
        }
    }

    // MARK: - Helpers

    // MARK: Stub objects

    private func stubSession() -> RegistrationSession {
        return RegistrationSession(
            id: UUID().uuidString,
            e164: E164("+17875550100")!, // For our purposes, can be fixed.
            receivedDate: date,
            nextSMS: 1,
            nextCall: 1,
            nextVerificationAttempt: nil,
            allowedToRequestCode: true,
            requestedInformation: [],
            hasUnknownChallengeRequiringAppUpdate: false,
            verified: false,
        )
    }

    private func stubWireSession(
        verified: Bool = false,
        hasNextVerificationAttempt: Bool = true,
    ) -> RegistrationServiceResponses.RegistrationSession {
        return RegistrationServiceResponses.RegistrationSession(
            id: UUID().uuidString,
            nextSms: (0...100).randomElement(),
            nextCall: (0...100).randomElement(),
            nextVerificationAttempt: hasNextVerificationAttempt ? (0...100).randomElement() : nil,
            allowedToRequestCode: false,
            requestedInformation: [.captcha, .pushChallenge],
            verified: verified,
        )
    }

    // Keep this independent of the production code converter for an extra layer of durability.
    private func sessionConverter(
        _ wireSession: RegistrationServiceResponses.RegistrationSession,
        e164: E164 = E164("+17875550100")!,
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
            verified: wireSession.verified,
        )
    }
}
