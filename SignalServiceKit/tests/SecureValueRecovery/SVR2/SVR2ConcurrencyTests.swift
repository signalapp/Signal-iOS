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
    private let queue = DispatchQueue(label: "SVR2ConcurrencyTestsQueue")
    private let mockConnectionFactory: MockSgxWebsocketConnectionFactory
    private let mockConnection: MockSgxWebsocketConnection<SVR2WebsocketConfigurator>

    init() {
        self.db = InMemoryDB()
        self.credentialStorage = SVRAuthCredentialStorageMock()

        mockConnection = MockSgxWebsocketConnection<SVR2WebsocketConfigurator>()
        mockConnection.mockAuth = RemoteAttestation.Auth(username: "username", password: "password")
        mockConnectionFactory = MockSgxWebsocketConnectionFactory()

        let mockClientWrapper = MockSVR2ClientWrapper()

        let accountKeyStore = AccountKeyStore(
            backupSettingsStore: BackupSettingsStore(),
        )
        let localStorage = SVRLocalStorageImpl()

        self.svr = SecureValueRecovery2Impl(
            appContext: SVR2.Mocks.AppContext(),
            appReadiness: AppReadinessMock(),
            appVersion: MockAppVerion(),
            clientWrapper: mockClientWrapper,
            connectionFactory: mockConnectionFactory,
            credentialStorage: credentialStorage,
            db: db,
            accountKeyStore: accountKeyStore,
            scheduler: queue,
            storageServiceManager: FakeStorageServiceManager(),
            svrLocalStorage: localStorage,
            tsAccountManager: MockTSAccountManager(),
            tsConstants: TSConstants.shared,
            twoFAManager: SVR2.TestMocks.OWS2FAManager(),
        )
    }

    @Test
    func testConcurrentRequestsOnSameEnclave_startSecondAfterFirstSendsExpose() async throws {
        var hasOpenedConnection = false
        mockConnectionFactory.setOnConnectAndPerformHandshake { (_: SVR2WebsocketConfigurator) in
            #expect(!hasOpenedConnection)
            hasOpenedConnection = true
            return .value(self.mockConnection)
        }

        let closeContinuation = CancellableContinuation<Void>()
        mockConnection.onDisconnect = {
            closeContinuation.resume(with: .success(()))
        }

        let (firstBackupPromise, firstBackupFuture) = Promise<SVR2Proto_Response>.pending()
        let (firstExposePromise, firstExposeFuture) = Promise<SVR2Proto_Response>.pending()
        let (secondBackupPromise, secondBackupFuture) = Promise<SVR2Proto_Response>.pending()
        let (secondExposePromise, secondExposeFuture) = Promise<SVR2Proto_Response>.pending()

        var requestCount = 0
        let madeRequestContinuations = (0..<4).map { i in
            return CancellableContinuation<Void>()
        }
        mockConnection.onSendRequestAndReadResponse = { request in
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

        let firstMasterKey = MasterKey()
        async let firstBackupResult = svr.backupMasterKey(pin: "1234", masterKey: firstMasterKey, authMethod: .implicit).awaitable()

        // Let the first backup succeed and start the expose, then make the second request.
        firstBackupFuture.resolve(backupResponse())

        try await madeRequestContinuations[0].wait()
        try await madeRequestContinuations[1].wait()

        let secondMasterKey = MasterKey()
        async let secondBackupResult = svr.backupMasterKey(pin: "abcd", masterKey: secondMasterKey, authMethod: .implicit).awaitable()

        // There is a race condition here because the connection closes itself
        // after 100ms of inactivity. If the second `backupMasterKey` call is
        // delayed more than 100ms in requesting the connection/scheduling its
        // requests, the connection may close prematurely, causing the second
        // backup to open a new connection. We can reduce the likelihood of hitting
        // this race condition by pausing temporarily here; note that we already
        // wait for 100ms at the end of the test for the connection to close.
        try await Task.sleep(nanoseconds: 3.clampedNanoseconds)

        firstExposeFuture.resolve(exposeResponse())
        secondBackupFuture.resolve(backupResponse())
        secondExposeFuture.resolve(exposeResponse())

        _ = try await firstBackupResult

        try await madeRequestContinuations[2].wait()
        try await madeRequestContinuations[3].wait()

        _ = try await secondBackupResult

        try await closeContinuation.wait()
    }

    @Test
    func testConcurrentRequestsOnSameEnclave_startSecondImmediately() async throws {
        var hasOpenedConnection = false
        mockConnectionFactory.setOnConnectAndPerformHandshake { (_: SVR2WebsocketConfigurator) in
            #expect(!hasOpenedConnection)
            hasOpenedConnection = true
            return .value(self.mockConnection)
        }

        let closeContinuation = CancellableContinuation<Void>()
        mockConnection.onDisconnect = {
            closeContinuation.resume(with: .success(()))
        }

        let (firstBackupPromise, firstBackupFuture) = Promise<SVR2Proto_Response>.pending()
        // We won't make a first expose request; it will get cancelled because of the second
        // overwriting it.
        let (secondBackupPromise, secondBackupFuture) = Promise<SVR2Proto_Response>.pending()
        let (secondExposePromise, secondExposeFuture) = Promise<SVR2Proto_Response>.pending()

        var requestCount = 0
        let madeRequestContinuations = (0..<3).map { i in
            return CancellableContinuation<Void>()
        }
        mockConnection.onSendRequestAndReadResponse = { request in
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
                // Second backup
                #expect(request.hasBackup)
                return secondBackupPromise
            case 2:
                // Second expose
                #expect(request.hasExpose)
                return secondExposePromise
            default:
                Issue.record("Unexpected request")
                return .init(error: OWSAssertionError(""))
            }
        }

        let firstMasterKey = MasterKey()
        async let firstBackupResult = svr.backupMasterKey(pin: "1234", masterKey: firstMasterKey, authMethod: .implicit).awaitable()

        let secondMasterKey = MasterKey()
        async let secondBackupResult = svr.backupMasterKey(pin: "abcd", masterKey: secondMasterKey, authMethod: .implicit).awaitable()

        // In addition to the race condition described above related to the 100ms
        // disconnection timeout, there is non-determinism and another race
        // condition in this flow specifically.
        //
        // The two `backupMasterKey` calls above may execute in either order (they
        // are asynchronous and concurrent). This is fine because they are
        // interchangeable. The test itself wants to ensure that only one of them
        // issues an expose, and it should be the second one, but it can't confirm
        // which that is because of the non-determinism.
        //
        // Additionally, the following lines must wait until both of the above
        // requests have queued up their backup requests to ensure both of those
        // run before either of them issues an expose.
        try await Task.sleep(nanoseconds: 3.clampedNanoseconds)

        firstBackupFuture.resolve(backupResponse())
        secondBackupFuture.resolve(backupResponse())
        secondExposeFuture.resolve(exposeResponse())

        try await madeRequestContinuations[0].wait()
        try await madeRequestContinuations[1].wait()
        try await madeRequestContinuations[2].wait()

        // We don't know which of these will arrive "first" or "second", so we have
        // to wait for all of the madeRequestContinuations before we can wait for
        // either of these.
        _ = try await firstBackupResult
        _ = try await secondBackupResult

        try await closeContinuation.wait()
    }

    @Test
    func testWebsocketConnectionFailure() async throws {

        let firstMockConnection = MockSgxWebsocketConnection<SVR2WebsocketConfigurator>()
        firstMockConnection.mockAuth = RemoteAttestation.Auth(username: "username", password: "password")

        let secondMockConnection = MockSgxWebsocketConnection<SVR2WebsocketConfigurator>()
        secondMockConnection.mockAuth = RemoteAttestation.Auth(username: "username2", password: "password2")

        var numOpenedConnections = 0
        mockConnectionFactory.setOnConnectAndPerformHandshake { (_: SVR2WebsocketConfigurator) in
            numOpenedConnections += 1
            switch numOpenedConnections {
            case 1:
                return .value(firstMockConnection)
            case 2:
                return .value(secondMockConnection)
            default:
                Issue.record("Unexpected number of opened connections")
                return .init(error: OWSAssertionError(""))
            }
        }

        let firstCloseContinuation = CancellableContinuation<Void>()
        firstMockConnection.onDisconnect = {
            firstCloseContinuation.resume(with: .success(()))
        }

        let (firstBackupPromise, firstBackupFuture) = Promise<SVR2Proto_Response>.pending()
        // We won't make a first expose request; it will get cancelled because of the failure.
        // We also won't make a second backup or expose request.

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
        async let firstBackupResult = svr.backupMasterKey(pin: "1234", masterKey: firstMasterKey, authMethod: .implicit).awaitable()

        let secondMasterKey = MasterKey()
        async let secondBackupResult = svr.backupMasterKey(pin: "abcd", masterKey: secondMasterKey, authMethod: .implicit).awaitable()

        // See above. In this case, we want both `backupMasterKey` calls to acquire
        // the same shared connection so they see the same errors.
        try await Task.sleep(nanoseconds: 3.clampedNanoseconds)

        let firstBackupError = WebSocketError.closeError(statusCode: 400, closeReason: nil)
        firstBackupFuture.reject(firstBackupError)

        try await madeRequestContinuations[0].wait()

        do {
            _ = try await firstBackupResult
            Issue.record("Expected error on first backup.")
        } catch {}

        do {
            _ = try await secondBackupResult
            Issue.record("Expected error on second backup.")
        } catch {}

        try await firstCloseContinuation.wait()

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

        let thirdMasterKey = MasterKey()
        _ = try await svr.backupMasterKey(pin: "zzzz", masterKey: thirdMasterKey, authMethod: .implicit).awaitable()

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
