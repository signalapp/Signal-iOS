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
            statusCode: 200,
            bodyData: responseJSON.data(using: .utf8),
        ))

        do {
            var session = oldSession
            try await registrationSessionManager.requestVerificationCode(
                for: &session,
                transport: [Registration.CodeTransport.sms, .voice].randomElement()!,
                logger: .empty(),
            )

            XCTAssertEqual(session, RegistrationSession(
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
            ))
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
            statusCode: 200,
            bodyData: responseJSON.data(using: .utf8),
        ))

        do {
            var session = oldSession
            try await registrationSessionManager.requestVerificationCode(
                for: &session,
                transport: [Registration.CodeTransport.sms, .voice].randomElement()!,
                logger: .empty(),
            )

            XCTAssertEqual(session, RegistrationSession(
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
            ))
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
            statusCode: 200,
            bodyData: responseJSON.data(using: .utf8),
        ))

        do {
            var session = oldSession
            try await registrationSessionManager.requestVerificationCode(
                for: &session,
                transport: [Registration.CodeTransport.sms, .voice].randomElement()!,
                logger: .empty(),
            )

            XCTAssertEqual(session, RegistrationSession(
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
            ))
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
            statusCode: 404,
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

    public func testRequestVerificationCode() async throws {
        let oldSession = stubSession()

        // will have a new id, which is fine cuz it lets us differentiate.
        let responseBody = stubWireSession()

        func mockResponse(statusCode: Int, hasSession: Bool) {
            networkManager.asyncRequestHandlers.append(MockNetworkManager.mockResponse(
                matchingRequest: { $0.method == "POST" && $0.url.relativeString.hasPrefix("v1/verification/session/") && $0.url.relativeString.hasSuffix("/code") },
                statusCode: statusCode,
                bodyJson: hasSession ? responseBody : nil,
            ))
        }

        var session = oldSession
        func requestVerificationCode() async throws {
            session = oldSession
            try await registrationSessionManager.requestVerificationCode(
                for: &session,
                transport: [Registration.CodeTransport.sms, .voice].randomElement()!,
                logger: .empty(),
            )
        }

        do {
            mockResponse(statusCode: 200, hasSession: true)
            try await requestVerificationCode()
            XCTAssertEqual(session, sessionConverter(responseBody))
        }

        do {
            mockResponse(statusCode: 400, hasSession: false)
            try await requestVerificationCode()
            XCTFail("must have error")
        } catch where error.httpStatusCode == 400 {
            XCTAssertNotEqual(session, sessionConverter(responseBody))
        }

        do {
            mockResponse(statusCode: 409, hasSession: true)
            try await requestVerificationCode()
            XCTFail("must have error")
        } catch where error.httpStatusCode == Registration.RequestVerificationCodeErrorCode.notYetAllowed.rawValue {
            XCTAssertEqual(session, sessionConverter(responseBody))
        }

        do {
            mockResponse(statusCode: 404, hasSession: true)
            try await requestVerificationCode()
            XCTFail("must have error")
        } catch is Registration.MissingSessionError {
            XCTAssertNotEqual(session, sessionConverter(responseBody))
        }

        do {
            mockResponse(statusCode: 429, hasSession: true)
            try await requestVerificationCode()
            XCTFail("must have error")
        } catch where error.httpStatusCode == Registration.RequestVerificationCodeErrorCode.rateLimited.rawValue {
            XCTAssertEqual(session, sessionConverter(responseBody))
        }
    }

    public func testRequestVerificationCodeServiceError() async throws {
        let oldSession = stubSession()

        var errorResponseJSON = """
        {
            "permanentFailure": false,
            "reason": "providerRejected"
        }
        """

        networkManager.asyncRequestHandlers.append(MockNetworkManager.mockResponse(
            matchingRequest: { $0.method == "POST" && $0.url.relativeString.hasPrefix("v1/verification/session/") && $0.url.relativeString.hasSuffix("/code") },
            statusCode: 440,
            bodyData: Data(errorResponseJSON.utf8),
        ))

        do {
            var session = oldSession
            try await registrationSessionManager.requestVerificationCode(
                for: &session,
                transport: [Registration.CodeTransport.sms, .voice].randomElement()!,
                logger: .empty(),
            )
        } catch let error as Registration.RequestRejectedByProviderError {
            XCTAssertEqual(error.failureResponse, Registration.ServerFailureResponse(
                isPermanent: false,
                reason: .providerRejected,
            ))
        }

        errorResponseJSON = """
        {
            "permanentFailure": false,
            "reason": "someRandomValueTheClientCantParse"
        }
        """

        networkManager.asyncRequestHandlers.append(MockNetworkManager.mockResponse(
            matchingRequest: { $0.method == "POST" && $0.url.relativeString.hasPrefix("v1/verification/session/") && $0.url.relativeString.hasSuffix("/code") },
            statusCode: 440,
            bodyData: Data(errorResponseJSON.utf8),
        ))

        do {
            var session = oldSession
            try await registrationSessionManager.requestVerificationCode(
                for: &session,
                transport: [Registration.CodeTransport.sms, .voice].randomElement()!,
                logger: .empty(),
            )
        } catch let error as Registration.RequestRejectedByProviderError {
            XCTAssertEqual(error.failureResponse, Registration.ServerFailureResponse(
                isPermanent: false,
                reason: nil,
            ))
        }
    }

    public func testSubmitVerificationCode() async throws {
        let code = "1234"
        let oldSession = stubSession()

        func mockResponse(statusCode: Int, session: RegistrationServiceResponses.RegistrationSession?) {
            networkManager.asyncRequestHandlers.append(MockNetworkManager.mockResponse(
                matchingRequest: { $0.method == "PUT" && $0.url.relativeString.hasPrefix("v1/verification/session/") && $0.url.relativeString.hasSuffix("/code") },
                statusCode: statusCode,
                bodyJson: session,
            ))
        }

        var session = oldSession
        func submitVerificationCode() async throws {
            session = oldSession
            try await registrationSessionManager.submitVerificationCode(
                for: &session,
                code: code,
                logger: .empty(),
            )
        }

        // will have a new ids, which is fine cuz it lets us differentiate.

        let verifiedResponseBody = stubWireSession(verified: true)
        do {
            mockResponse(statusCode: 200, session: verifiedResponseBody)
            try await submitVerificationCode()
            XCTAssertEqual(session, sessionConverter(verifiedResponseBody))
            XCTAssertEqual(session.verified, true)
        }

        let unVerifiedResponseBody = stubWireSession(verified: false)
        do {
            mockResponse(statusCode: 200, session: unVerifiedResponseBody)
            try await submitVerificationCode()
            XCTAssertEqual(session, sessionConverter(unVerifiedResponseBody))
            XCTAssertEqual(session.verified, false)
        }

        do {
            mockResponse(statusCode: 404, session: nil)
            try await submitVerificationCode()
        } catch is Registration.MissingSessionError {
            // OK
        }

        // A bit weird and probably not possible in practice
        do {
            mockResponse(statusCode: 409, session: verifiedResponseBody)
            try await submitVerificationCode()
            XCTAssertEqual(session, sessionConverter(verifiedResponseBody))
        }

        do {
            mockResponse(statusCode: 409, session: unVerifiedResponseBody)
            try await submitVerificationCode()
        } catch where error.httpStatusCode == Registration.SubmitVerificationCodeErrorCode.notAllowed.rawValue {
            XCTAssertEqual(session, sessionConverter(unVerifiedResponseBody))
        }

        let unVerifiedWithNoAttemptResponseBody = stubWireSession(verified: false, hasNextVerificationAttempt: false)
        do {
            mockResponse(statusCode: 409, session: unVerifiedWithNoAttemptResponseBody)
            try await submitVerificationCode()
        } catch where error.httpStatusCode == Registration.SubmitVerificationCodeErrorCode.notAllowed.rawValue {
            XCTAssertEqual(session, sessionConverter(unVerifiedWithNoAttemptResponseBody))
        }

        do {
            mockResponse(statusCode: 429, session: unVerifiedResponseBody)
            try await submitVerificationCode()
        } catch where error.httpStatusCode == Registration.SubmitVerificationCodeErrorCode.rateLimited.rawValue {
            XCTAssertEqual(session, sessionConverter(unVerifiedResponseBody))
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
