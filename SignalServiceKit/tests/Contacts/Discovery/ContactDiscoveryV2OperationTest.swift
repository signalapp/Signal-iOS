//
// Copyright 2022 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import XCTest
@testable import SignalServiceKit

final class ContactDiscoveryV2OperationTest: XCTestCase {

    // MARK: - Mocks

    private class MockContactDiscoveryV2ConnectionFactory: ContactDiscoveryV2ConnectionFactory {
        var onConnectAndPerformHandshake: ((DispatchQueue) -> Promise<ContactDiscoveryV2Connection>)?
        func connectAndPerformHandshake(on queue: DispatchQueue) -> Promise<ContactDiscoveryV2Connection> {
            onConnectAndPerformHandshake!(queue)
        }
    }

    private class MockContactDiscoveryV2Connection: ContactDiscoveryV2Connection {
        var onSendRequestAndReadResponse: ((Data) -> Promise<Data>)?
        func sendRequestAndReadResponse(_ request: Data) -> Promise<Data> {
            onSendRequestAndReadResponse!(request)
        }

        var onSendRequestAndReadAllResponses: ((Data) -> Promise<[Data]>)?
        func sendRequestAndReadAllResponses(_ request: Data) -> Promise<[Data]> {
            onSendRequestAndReadAllResponses!(request)
        }

        func disconnect() {
        }
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
    private lazy var connectionFactory = MockContactDiscoveryV2ConnectionFactory()

    /// In .oneOffUserRequest mode, we should disregard tokens entirely.
    func testOneOffRequest() throws {
        let aci = UUID()
        let pni = UUID()

        let operation = ContactDiscoveryV2Operation(
            e164sToLookup: [try XCTUnwrap(E164("+16505550100"))],
            compatibilityMode: .fetchAllACIs,
            persistentState: nil,
            connectionFactory: connectionFactory
        )

        // Prepare the server's responses to the client's request.
        let connection = MockContactDiscoveryV2Connection()
        var newE164s: Data?
        connection.onSendRequestAndReadResponse = { requestData in
            let request = try! CDSI_ClientRequest(serializedData: requestData)
            XCTAssertEqual(request.token, Data())
            XCTAssertEqual(request.prevE164S, Data())
            XCTAssertEqual(request.newE164S.count, 8)
            newE164s = request.newE164S

            var response = CDSI_ClientResponse()
            response.token = Cryptography.generateRandomBytes(65)
            return .value(try! response.serializedData())
        }
        connection.onSendRequestAndReadAllResponses = { requestData in
            let request = try! CDSI_ClientRequest(serializedData: requestData)
            XCTAssertTrue(request.tokenAck)

            var response = CDSI_ClientResponse()
            response.e164PniAciTriples = newE164s! + pni.data + aci.data
            return .value([try! response.serializedData()])
        }
        connectionFactory.onConnectAndPerformHandshake = { queue in
            return .value(connection)
        }

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
            compatibilityMode: .fetchAllACIs,
            persistentState: nil,
            connectionFactory: connectionFactory
        )

        // Prepare the server's responses to the client's request.
        let connection = MockContactDiscoveryV2Connection()
        connection.onSendRequestAndReadResponse = { _ in
            var response = CDSI_ClientResponse()
            response.token = Cryptography.generateRandomBytes(65)
            return .value(try! response.serializedData())
        }
        connection.onSendRequestAndReadAllResponses = { _ in
            var response = CDSI_ClientResponse()
            response.e164PniAciTriples = Data(count: 40)
            return .value([try! response.serializedData()])
        }
        connectionFactory.onConnectAndPerformHandshake = { queue in
            return .value(connection)
        }

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
            compatibilityMode: .fetchAllACIs,
            persistentState: persistentState,
            connectionFactory: connectionFactory
        )

        // Establish the initial state.
        let initialToken = Cryptography.generateRandomBytes(65)
        persistentState.token = initialToken
        let initialPrevE164s: Set<E164> = [try XCTUnwrap(E164("+16505550199"))]
        persistentState.prevE164s = initialPrevE164s

        // Prepare the server's responses to the client's request.
        let connection = MockContactDiscoveryV2Connection()
        connection.onSendRequestAndReadResponse = { requestData in
            return Promise(error: WebSocketError.closeError(
                statusCode: 4008,
                closeReason: #"{"retry_after": 1234}"#.data(using: .utf8)!
            ))
        }
        connectionFactory.onConnectAndPerformHandshake = { queue in
            return .value(connection)
        }

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
            compatibilityMode: .fetchAllACIs,
            persistentState: persistentState,
            connectionFactory: connectionFactory
        )

        // Establish the initial state.
        persistentState.token = Cryptography.generateRandomBytes(65)

        // Prepare the server's responses to the client's request.
        let connection = MockContactDiscoveryV2Connection()
        connection.onSendRequestAndReadResponse = { requestData in
            return Promise(error: WebSocketError.closeError(statusCode: 4101, closeReason: nil))
        }
        connectionFactory.onConnectAndPerformHandshake = { queue in
            return .value(connection)
        }

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
