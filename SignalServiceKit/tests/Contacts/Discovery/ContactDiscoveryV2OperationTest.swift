//
// Copyright 2022 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import LibSignalClient
import XCTest

@testable import SignalServiceKit

final class ContactDiscoveryV2OperationTest: XCTestCase {

    // MARK: - Mocks

    private class MockUDManager: ContactDiscoveryV2Operation.Shims.UDManager {
        func fetchAllAciUakPairsWithSneakyTransaction() -> [Aci: SMKUDAccessKey] { return [:] }
    }

    private class MockContactDiscoveryV2PersistentState: ContactDiscoveryV2PersistentState {
        var token: Data?
        var prevE164s = Set<E164>()

        func load() -> (token: Data, e164s: ContactDiscoveryE164Collection<Set<E164>>)? {
            if let token {
                return (token, ContactDiscoveryE164Collection(prevE164s))
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
    private lazy var connectionFactory = MockSgxWebsocketConnectionFactory()

    /// In .oneOffUserRequest mode, we should disregard tokens entirely.
    func testOneOffRequest() throws {
        let aci = Aci.randomForTesting()
        let pni = Pni.randomForTesting()

        let operation = ContactDiscoveryV2Operation(
            e164sToLookup: [try XCTUnwrap(E164("+16505550100"))],
            tryToReturnAcisWithoutUaks: true,
            persistentState: nil,
            udManager: MockUDManager(),
            connectionFactory: connectionFactory
        )

        // Prepare the server's responses to the client's request.
        let connection = MockSgxWebsocketConnection<ContactDiscoveryV2WebsocketConfigurator>()
        var newE164s: Data?
        connection.onSendRequestAndReadResponse = { request in
            XCTAssertEqual(request.token, Data())
            XCTAssertEqual(request.prevE164S, Data())
            XCTAssertEqual(request.newE164S.count, 8)
            newE164s = request.newE164S

            var response = CDSI_ClientResponse()
            response.token = Cryptography.generateRandomBytes(65)
            return .value(response)
        }
        connection.onSendRequestAndReadAllResponses = { request in
            XCTAssertTrue(request.tokenAck)

            var response = CDSI_ClientResponse()
            response.e164PniAciTriples = newE164s! + pni.rawUUID.data + aci.rawUUID.data
            return .value([response])
        }
        connectionFactory.setOnConnectAndPerformHandshake({ _ in
            return .value(connection)
        })

        // Run the discovery operation.
        var operationResults: [ContactDiscoveryV2Operation.DiscoveryResult]?
        let operationExpectation = expectation(description: "Waiting for operation.")
        operation.perform(on: DispatchQueue.main).done { results in
            operationResults = results
            operationExpectation.fulfill()
        }.cauterize()
        waitForExpectations(timeout: 10)

        // Make sure we got back the result we expected.
        XCTAssertEqual(operationResults?.count, 1)
        XCTAssertEqual(operationResults?.first?.e164.stringValue, "+16505550100")
        XCTAssertEqual(operationResults?.first?.pni, pni)
        XCTAssertEqual(operationResults?.first?.aci, aci)
    }

    func testNotDiscoverable() throws {
        let operation = ContactDiscoveryV2Operation(
            e164sToLookup: [try XCTUnwrap(E164("+16505550100"))],
            tryToReturnAcisWithoutUaks: true,
            persistentState: nil,
            udManager: MockUDManager(),
            connectionFactory: connectionFactory
        )

        // Prepare the server's responses to the client's request.
        let connection = MockSgxWebsocketConnection<ContactDiscoveryV2WebsocketConfigurator>()
        connection.onSendRequestAndReadResponse = { _ in
            var response = CDSI_ClientResponse()
            response.token = Cryptography.generateRandomBytes(65)
            return .value(response)
        }
        connection.onSendRequestAndReadAllResponses = { _ in
            var response = CDSI_ClientResponse()
            response.e164PniAciTriples = Data(count: 40)
            return .value([response])
        }
        connectionFactory.setOnConnectAndPerformHandshake({ _ in
            return .value(connection)
        })

        // Run the discovery operation.
        var operationResults: [ContactDiscoveryV2Operation.DiscoveryResult]?
        let operationExpectation = expectation(description: "Waiting for operation.")
        operation.perform(on: DispatchQueue.main).done { results in
            operationResults = results
            operationExpectation.fulfill()
        }.cauterize()
        waitForExpectations(timeout: 10)

        // Make sure we got back the result we expected.
        XCTAssertEqual(operationResults?.count, 0)
    }

    /// If the server reports a rate limit, we should parse "retry after".
    func testRateLimitError() throws {
        let operation = ContactDiscoveryV2Operation(
            e164sToLookup: [try XCTUnwrap(E164("+16505550100"))],
            tryToReturnAcisWithoutUaks: true,
            persistentState: persistentState,
            udManager: MockUDManager(),
            connectionFactory: connectionFactory
        )

        // Establish the initial state.
        let initialToken = Cryptography.generateRandomBytes(65)
        persistentState.token = initialToken
        let initialPrevE164s: Set<E164> = [try XCTUnwrap(E164("+16505550199"))]
        persistentState.prevE164s = initialPrevE164s

        // Prepare the server's responses to the client's request.
        let connection = MockSgxWebsocketConnection<ContactDiscoveryV2WebsocketConfigurator>()
        connection.onSendRequestAndReadResponse = { requestData in
            return Promise(error: WebSocketError.closeError(
                statusCode: 4008,
                closeReason: #"{"retry_after": 1234}"#.data(using: .utf8)!
            ))
        }
        connectionFactory.setOnConnectAndPerformHandshake({ _ in
            return .value(connection)
        })

        // Run the discovery operation.
        var operationError: Error?
        let operationExpectation = expectation(description: "Waiting for operation.")
        operation.perform(on: DispatchQueue.main).catch { error in
            operationError = error
            operationExpectation.fulfill()
        }.cauterize()
        waitForExpectations(timeout: 10)

        // Make sure the local state wasn't modified.
        XCTAssertEqual(persistentState.token, initialToken)
        XCTAssertEqual(persistentState.prevE164s, initialPrevE164s)

        let contactDiscoveryError = try XCTUnwrap(operationError as? ContactDiscoveryError)
        XCTAssertEqual(contactDiscoveryError.kind, .rateLimit)
        XCTAssertEqual(try XCTUnwrap(contactDiscoveryError.retryAfterDate?.timeIntervalSinceNow), 1234, accuracy: 10)
    }

    /// If the server reports an invalid token, we should clear the token.
    func testInvalidTokenError() throws {
        let operation = ContactDiscoveryV2Operation(
            e164sToLookup: [try XCTUnwrap(E164("+16505550100"))],
            tryToReturnAcisWithoutUaks: true,
            persistentState: persistentState,
            udManager: MockUDManager(),
            connectionFactory: connectionFactory
        )

        // Establish the initial state.
        persistentState.token = Cryptography.generateRandomBytes(65)

        // Prepare the server's responses to the client's request.
        let connection = MockSgxWebsocketConnection<ContactDiscoveryV2WebsocketConfigurator>()
        connection.onSendRequestAndReadResponse = { requestData in
            return Promise(error: WebSocketError.closeError(statusCode: 4101, closeReason: nil))
        }
        connectionFactory.setOnConnectAndPerformHandshake({ _ in
            return .value(connection)
        })

        // Run the discovery operation.
        let operationExpectation = expectation(description: "Waiting for operation.")
        operation.perform(on: DispatchQueue.main).catch { error in
            operationExpectation.fulfill()
        }.cauterize()
        waitForExpectations(timeout: 10)

        // Make sure the local state was cleared.
        XCTAssertNil(persistentState.token)
    }
}
