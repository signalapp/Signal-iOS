//
// Copyright 2022 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import LibSignalClient
import XCTest

@testable import SignalServiceKit

final class ContactDiscoveryV2OperationTest: XCTestCase {

    // MARK: - Mocks

    struct TokenResult: ContactDiscoveryTokenResult {
        var token: Data
    }

    private class MockContactDiscoveryConnection: ContactDiscoveryConnection {
        var onPerformRequest: ((ContactDiscoveryLookupRequest, Auth) throws -> TokenResult)!
        func performRequest(_ request: ContactDiscoveryLookupRequest, auth: Auth) async throws -> TokenResult {
            return try self.onPerformRequest(request, auth)
        }

        var onContinueRequest: ((TokenResult) -> [ContactDiscoveryResult])!
        func continueRequest(afterAckingToken tokenResult: TokenResult) async throws -> [ContactDiscoveryResult] {
            return self.onContinueRequest(tokenResult)
        }
    }

    private class MockRemoteAttestation: ContactDiscoveryV2Operation<MockContactDiscoveryConnection>.Shims.RemoteAttestation {
        func authForCDSI() async throws -> RemoteAttestation.Auth {
            return RemoteAttestation.Auth(username: "", password: "")
        }
    }

    private class MockUDManager: ContactDiscoveryV2Operation<MockContactDiscoveryConnection>.Shims.UDManager {
        func fetchAllAciUakPairsWithSneakyTransaction() -> [Aci: SMKUDAccessKey] { return [:] }
    }

    private class MockContactDiscoveryV2PersistentState: ContactDiscoveryV2PersistentState {
        var token: Data?
        var prevE164s = Set<E164>()

        func load() -> (token: Data, e164s: Set<E164>)? {
            if let token {
                return (token, prevE164s)
            }
            return nil
        }

        func save(newToken: Data, clearE164s: Bool, newE164s: Set<E164>) throws {
            token = newToken
            if clearE164s {
                prevE164s.removeAll()
            }
            prevE164s.formUnion(newE164s)
        }

        func reset() {
            token = nil
        }
    }

    // MARK: - Tests

    private lazy var persistentState = MockContactDiscoveryV2PersistentState()

    /// In .oneOffUserRequest mode, we should disregard tokens entirely.
    func testOneOffRequest() async throws {
        let aci = Aci.randomForTesting()
        let pni = Pni.randomForTesting()

        let connection = MockContactDiscoveryConnection()
        let operation = ContactDiscoveryV2Operation(
            e164sToLookup: [try XCTUnwrap(E164("+16505550100"))],
            mode: .oneOffUserRequest,
            udManager: MockUDManager(),
            connectionImpl: connection,
            remoteAttestation: MockRemoteAttestation()
        )

        // Prepare the server's responses to the client's request.
        var newE164s: Set<E164>?
        connection.onPerformRequest = { request, _ in
            XCTAssertEqual(request.token, nil)
            XCTAssertEqual(request.prevE164s, [])
            XCTAssertEqual(request.newE164s.count, 1)
            newE164s = request.newE164s

            return TokenResult(token: Randomness.generateRandomBytes(65))
        }
        connection.onContinueRequest = { tokenResult in
            XCTAssert(!tokenResult.token.isEmpty)
            return [ContactDiscoveryResult(e164: newE164s!.first!, pni: pni, aci: aci)]
        }

        // Run the discovery operation.
        let operationResults = try await operation.perform()

        // Make sure we got back the result we expected.
        XCTAssertEqual(operationResults.count, 1)
        XCTAssertEqual(operationResults.first?.e164.stringValue, "+16505550100")
        XCTAssertEqual(operationResults.first?.pni, pni)
        XCTAssertEqual(operationResults.first?.aci, aci)
    }

    func testNotDiscoverable() async throws {
        let connection = MockContactDiscoveryConnection()
        let operation = ContactDiscoveryV2Operation(
            e164sToLookup: [try XCTUnwrap(E164("+16505550100"))],
            persistentState: nil,
            udManager: MockUDManager(),
            connectionImpl: connection,
            remoteAttestation: MockRemoteAttestation()
        )

        // Prepare the server's responses to the client's request.
        connection.onPerformRequest = { _, _ in
            return TokenResult(token: Randomness.generateRandomBytes(65))
        }
        connection.onContinueRequest = { _ in
            return []
        }

        // Run the discovery operation.
        let operationResults = try await operation.perform()

        // Make sure we got back the result we expected.
        XCTAssertEqual(operationResults.count, 0)
    }

    /// If the server reports a rate limit, we should parse "retry after".
    func testRateLimitError() async throws {
        let connection = MockContactDiscoveryConnection()
        let operation = ContactDiscoveryV2Operation(
            e164sToLookup: [try XCTUnwrap(E164("+16505550100"))],
            persistentState: persistentState,
            udManager: MockUDManager(),
            connectionImpl: connection,
            remoteAttestation: MockRemoteAttestation()
        )

        // Establish the initial state.
        let initialToken = Randomness.generateRandomBytes(65)
        persistentState.token = initialToken
        let initialPrevE164s: Set<E164> = [try XCTUnwrap(E164("+16505550199"))]
        persistentState.prevE164s = initialPrevE164s

        // Prepare the server's responses to the client's request.
        connection.onPerformRequest = { request, _ in
            throw LibSignalClient.SignalError.rateLimitedError(retryAfter: 1234, message: "")
        }

        // Run the discovery operation.
        var operationError: Error?
        do {
            _ = try await operation.perform()
        } catch {
            operationError = error
        }

        // Make sure the local state wasn't modified.
        XCTAssertEqual(persistentState.token, initialToken)
        XCTAssertEqual(persistentState.prevE164s, initialPrevE164s)

        switch try XCTUnwrap(operationError as? ContactDiscoveryError) {
        case .invalidToken, .retryableError, .terminalError:
            XCTFail("Wrong type of error.")
        case .rateLimit(let retryAfter):
            XCTAssertEqual(retryAfter.timeIntervalSinceNow, 1234, accuracy: 10)
        }
    }

    /// If the server reports an invalid token, we should clear the token.
    func testInvalidTokenError() async throws {
        let connection = MockContactDiscoveryConnection()
        let operation = ContactDiscoveryV2Operation(
            e164sToLookup: [try XCTUnwrap(E164("+16505550100"))],
            persistentState: persistentState,
            udManager: MockUDManager(),
            connectionImpl: connection,
            remoteAttestation: MockRemoteAttestation()
        )

        // Establish the initial state.
        persistentState.token = Randomness.generateRandomBytes(65)

        // Prepare the server's responses to the client's request.
        connection.onPerformRequest = { _, _ in
            throw LibSignalClient.SignalError.cdsiInvalidToken("")
        }

        // Run the discovery operation.
        do {
            _ = try await operation.perform()
            XCTFail("Must throw error.")
        } catch is ContactDiscoveryError {
            // Ok.
        }

        // Make sure the local state was cleared.
        XCTAssertNil(persistentState.token)
    }
}
