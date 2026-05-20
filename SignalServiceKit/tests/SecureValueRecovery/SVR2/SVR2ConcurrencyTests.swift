//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import LibSignalClient
import Testing

@testable import SignalServiceKit

struct SVR2ConcurrencyTests {

    private let db: InMemoryDB
    private let svr: SecureValueRecovery2Impl

    private let credentialStorage: SVRAuthCredentialStorageMock
    private let mockConnectionFactory: MockSgxWebsocketConnectionFactory
    private let mockConnection: MockSgxWebsocketConnection<SVR2WebsocketConfigurator>

    init() {
        self.db = InMemoryDB()
        self.credentialStorage = SVRAuthCredentialStorageMock()

        mockConnection = MockSgxWebsocketConnection<SVR2WebsocketConfigurator>()
        mockConnection.mockEnclave = TSConstants.shared.svr2Enclave
        mockConnection.mockAuth = RemoteAttestation.Auth(username: "username", password: "password")
        mockConnectionFactory = MockSgxWebsocketConnectionFactory()

        let accountKeyStore = AccountKeyStore(
            backupSettingsStore: BackupSettingsStore(),
        )
        let localStorage = SVRLocalStorageImpl()

        self.svr = SecureValueRecovery2Impl(
            appContext: SVR2.Mocks.AppContext(),
            appReadiness: AppReadinessMock(),
            appVersion: MockAppVerion(),
            connectionFactory: mockConnectionFactory,
            credentialStorage: credentialStorage,
            db: db,
            accountKeyStore: accountKeyStore,
            pinHasher: MockPinHasher(),
            storageServiceManager: FakeStorageServiceManager(),
            svrLocalStorage: localStorage,
            tsAccountManager: MockTSAccountManager(),
            tsConstants: TSConstants.shared,
            twoFAManager: SVR2.TestMocks.OWS2FAManager(),
        )
    }

    @Test
    func testConcurrentRequestsOnSameEnclave_startSecondAfterFirstSendsExpose() async throws {
        let (firstBackupPromise, firstBackupFuture) = Promise<SVR2Proto_Response>.pending()
        let (firstExposePromise, firstExposeFuture) = Promise<SVR2Proto_Response>.pending()
        let (secondBackupPromise, secondBackupFuture) = Promise<SVR2Proto_Response>.pending()
        let (secondExposePromise, secondExposeFuture) = Promise<SVR2Proto_Response>.pending()

        var requestCount = 0
        let madeRequestContinuations = (0..<4).map { i in
            return CancellableContinuation<Void>()
        }
        let onSendRequestAndReadResponse = { (request: SVR2Proto_Request) -> Promise<SVR2Proto_Response> in
            defer {
                madeRequestContinuations[requestCount].resume(with: .success(()))
                requestCount += 1
            }
            switch requestCount {
            case 0:
                // First backup.
                #expect(request.hasBackup)
                return firstBackupPromise
            case 1:
                // First expose
                #expect(request.hasExpose)
                return firstExposePromise
            case 2:
                // Second backup
                #expect(request.hasBackup)
                return secondBackupPromise
            case 3:
                // Second expose
                #expect(request.hasExpose)
                return secondExposePromise
            default:
                Issue.record("Unexpected request")
                return .init(error: OWSAssertionError(""))
            }
        }

        mockConnectionFactory.setOnConnectAndPerformHandshake { (_: SVR2WebsocketConfigurator) in
            let mockConnection = MockSgxWebsocketConnection<SVR2WebsocketConfigurator>()
            mockConnection.mockEnclave = TSConstants.shared.svr2Enclave
            mockConnection.mockAuth = RemoteAttestation.Auth(username: "username", password: "password")
            mockConnection.onSendRequestAndReadResponse = onSendRequestAndReadResponse
            return mockConnection
        }

        let firstMasterKey = MasterKey()
        async let firstBackupResult = svr.backupMasterKey(pin: "1234", masterKey: firstMasterKey, authMethod: .implicit)

        // Let the first backup succeed and start the expose, then make the second request.
        firstBackupFuture.resolve(backupResponse())

        try await madeRequestContinuations[0].wait()
        try await madeRequestContinuations[1].wait()

        let secondMasterKey = MasterKey()
        async let secondBackupResult = svr.backupMasterKey(pin: "abcd", masterKey: secondMasterKey, authMethod: .implicit)

        firstExposeFuture.resolve(exposeResponse())
        secondBackupFuture.resolve(backupResponse())
        secondExposeFuture.resolve(exposeResponse())

        _ = try await firstBackupResult

        try await madeRequestContinuations[2].wait()
        try await madeRequestContinuations[3].wait()

        _ = try await secondBackupResult
    }

    @Test
    func testWebsocketConnectionFailure() async throws {

        let firstMockConnection = MockSgxWebsocketConnection<SVR2WebsocketConfigurator>()
        firstMockConnection.mockEnclave = TSConstants.shared.svr2Enclave
        firstMockConnection.mockAuth = RemoteAttestation.Auth(username: "username", password: "password")

        let secondMockConnection = MockSgxWebsocketConnection<SVR2WebsocketConfigurator>()
        secondMockConnection.mockEnclave = TSConstants.shared.svr2Enclave
        secondMockConnection.mockAuth = RemoteAttestation.Auth(username: "username2", password: "password2")

        var numOpenedConnections = 0
        mockConnectionFactory.setOnConnectAndPerformHandshake { (_: SVR2WebsocketConfigurator) in
            numOpenedConnections += 1
            switch numOpenedConnections {
            case 1:
                return firstMockConnection
            case 2:
                return secondMockConnection
            default:
                Issue.record("Unexpected number of opened connections")
                throw OWSAssertionError("")
            }
        }

        let (firstBackupPromise, firstBackupFuture) = Promise<SVR2Proto_Response>.pending()

        var firstConnectionRequestCount = 0
        let madeRequestContinuations = (0..<1).map { i in
            return CancellableContinuation<Void>()
        }
        firstMockConnection.onSendRequestAndReadResponse = { request in
            defer {
                madeRequestContinuations[firstConnectionRequestCount].resume(with: .success(()))
                firstConnectionRequestCount += 1
            }
            switch firstConnectionRequestCount {
            case 0:
                // First backup.
                #expect(request.hasBackup)
                return firstBackupPromise
            default:
                Issue.record("Unexpected request")
                return .init(error: OWSAssertionError(""))
            }
        }

        let firstMasterKey = MasterKey()
        async let firstBackupResult = svr.backupMasterKey(pin: "1234", masterKey: firstMasterKey, authMethod: .implicit)

        let backupError = WebSocketError.closeError(statusCode: 400, closeReason: nil)
        firstBackupFuture.reject(backupError)

        try await madeRequestContinuations[0].wait()

        do {
            _ = try await firstBackupResult
            Issue.record("Expected error on first backup.")
        } catch {}

        #expect(numOpenedConnections == 1)

        // If we do another backup, it should open a new connection.

        let backupResponse = self.backupResponse()
        let exposeResponse = self.exposeResponse()

        var secondConnectionRequestCount = 0
        secondMockConnection.onSendRequestAndReadResponse = { request in
            secondConnectionRequestCount += 1
            switch secondConnectionRequestCount {
            case 1:
                return .value(backupResponse)
            case 2:
                return .value(exposeResponse)
            default:
                return .init(error: OWSAssertionError(""))
            }
        }

        let secondMasterKey = MasterKey()
        _ = try await svr.backupMasterKey(pin: "zzzz", masterKey: secondMasterKey, authMethod: .implicit)

        #expect(numOpenedConnections == 2)
    }

    private func backupResponse() -> SVR2Proto_Response {
        var response = SVR2Proto_Response()
        var backup = SVR2Proto_BackupResponse()
        backup.status = .ok
        response.backup = backup
        return response
    }

    private func exposeResponse() -> SVR2Proto_Response {
        var response = SVR2Proto_Response()
        var expose = SVR2Proto_ExposeResponse()
        expose.status = .ok
        response.expose = expose
        return response
    }
}
