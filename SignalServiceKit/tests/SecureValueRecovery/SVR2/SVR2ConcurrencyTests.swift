//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import XCTest
import LibSignalClient

@testable import SignalServiceKit

class SVR2ConcurrencyTests: XCTestCase {

    private var db: MockDB!
    private var svr: SecureValueRecovery2Impl!

    private var credentialStorage: SVRAuthCredentialStorageMock!
    private let queue = DispatchQueue(label: "SVR2ConcurrencyTestsQueue")
    private var mockConnectionFactory: MockSgxWebsocketConnectionFactory!
    private var mockConnection: MockSgxWebsocketConnection<SVR2WebsocketConfigurator>!

    override func setUp() {
        self.db = MockDB()
        self.credentialStorage = SVRAuthCredentialStorageMock()

        mockConnection = MockSgxWebsocketConnection<SVR2WebsocketConfigurator>()
        mockConnection.mockAuth = RemoteAttestation.Auth(username: "username", password: "password")
        mockConnectionFactory = MockSgxWebsocketConnectionFactory()

        let mockClientWrapper = MockSVR2ClientWrapper()

        let kvStore = InMemoryKeyValueStoreFactory()
        let localStorage = SVRLocalStorageImpl(keyValueStoreFactory: kvStore)

        self.svr = SecureValueRecovery2Impl(
            accountAttributesUpdater: MockAccountAttributesUpdater(),
            appReadiness: SVR2.Mocks.AppReadiness(),
            appVersion: MockAppVerion(),
            clientWrapper: mockClientWrapper,
            connectionFactory: mockConnectionFactory,
            credentialStorage: credentialStorage,
            db: db,
            keyValueStoreFactory: kvStore,
            schedulers: Schedulers(queue),
            storageServiceManager: FakeStorageServiceManager(),
            svrLocalStorage: localStorage,
            syncManager: OWSMockSyncManager(),
            tsAccountManager: MockTSAccountManager(),
            tsConstants: TSConstants.shared,
            twoFAManager: SVR2.TestMocks.OWS2FAManager()
        )
    }

    func testConcurrentRequestsOnSameEnclave_startSecondAfterFirstSendsExpose() {
        var hasOpenedConnection = false
        mockConnectionFactory.setOnConnectAndPerformHandshake { (_: SVR2WebsocketConfigurator) in
            XCTAssertFalse(hasOpenedConnection)
            hasOpenedConnection = true
            return .value(self.mockConnection)
        }

        let closeExpectation = self.expectation(description: "close websocket")
        mockConnection.onDisconnect = {
            closeExpectation.fulfill()
        }

        let (firstBackupPromise, firstBackupFuture) = Promise<SVR2Proto_Response>.pending()
        let (firstExposePromise, firstExposeFuture) = Promise<SVR2Proto_Response>.pending()
        let (secondBackupPromise, secondBackupFuture) = Promise<SVR2Proto_Response>.pending()
        let (secondExposePromise, secondExposeFuture) = Promise<SVR2Proto_Response>.pending()

        var requestCount = 0
        let madeRequestExpectations = (0..<4).map { i in
            return self.expectation(description: "request \(i)")
        }
        mockConnection.onSendRequestAndReadResponse = { request in
            defer {
                madeRequestExpectations[requestCount].fulfill()
                requestCount += 1
            }
            switch requestCount {
            case 0:
                // First backup.
                XCTAssert(request.hasBackup)
                return firstBackupPromise
            case 1:
                // First expose
                XCTAssert(request.hasExpose)
                return firstExposePromise
            case 2:
                // Second backup
                XCTAssert(request.hasBackup)
                return secondBackupPromise
            case 3:
                // Second expose
                XCTAssert(request.hasExpose)
                return secondExposePromise
            default:
                XCTFail("Unexpected request")
                return .init(error: OWSAssertionError(""))
            }
        }

        let firstBackupExpectation = self.expectation(description: "first backup")
        svr.generateAndBackupKeys(pin: "1234", authMethod: .implicit, rotateMasterKey: true).observe(on: SyncScheduler()) { (_: Result<Void, Error>) in
            firstBackupExpectation.fulfill()
        }

        // Let the first backup succeed and start the expose, then make the second request.
        firstBackupFuture.resolve(backupResponse())
        wait(for: [
            madeRequestExpectations[0],
            madeRequestExpectations[1]
        ], timeout: 10, enforceOrder: true)

        let secondBackupExpectation = self.expectation(description: "second backup")
        svr.generateAndBackupKeys(pin: "abcd", authMethod: .implicit, rotateMasterKey: true).observe(on: SyncScheduler()) { (_: Result<Void, Error>) in
            secondBackupExpectation.fulfill()
        }

        firstExposeFuture.resolve(exposeResponse())
        secondBackupFuture.resolve(backupResponse())
        secondExposeFuture.resolve(exposeResponse())
        wait(for: [firstBackupExpectation], timeout: 10)
        wait(for: [
            madeRequestExpectations[2], // second backup
            madeRequestExpectations[3], // second expose
            secondBackupExpectation,
            closeExpectation
        ], timeout: 10, enforceOrder: true)
    }

    func testConcurrentRequestsOnSameEnclave_startSecondImmediately() {
        var hasOpenedConnection = false
        mockConnectionFactory.setOnConnectAndPerformHandshake { (_: SVR2WebsocketConfigurator) in
            XCTAssertFalse(hasOpenedConnection)
            hasOpenedConnection = true
            return .value(self.mockConnection)
        }

        let closeExpectation = self.expectation(description: "close websocket")
        mockConnection.onDisconnect = {
            closeExpectation.fulfill()
        }

        let (firstBackupPromise, firstBackupFuture) = Promise<SVR2Proto_Response>.pending()
        // We won't make a first expose request; it will get cancelled because of the second
        // overwriting it.
        let (secondBackupPromise, secondBackupFuture) = Promise<SVR2Proto_Response>.pending()
        let (secondExposePromise, secondExposeFuture) = Promise<SVR2Proto_Response>.pending()

        var requestCount = 0
        let madeRequestExpectations = (0..<3).map { i in
            return self.expectation(description: "request \(i)")
        }
        mockConnection.onSendRequestAndReadResponse = { request in
            defer {
                madeRequestExpectations[requestCount].fulfill()
                requestCount += 1
            }
            switch requestCount {
            case 0:
                // First backup.
                XCTAssert(request.hasBackup)
                return firstBackupPromise
            case 1:
                // Second backup
                XCTAssert(request.hasBackup)
                return secondBackupPromise
            case 2:
                // Second expose
                XCTAssert(request.hasExpose)
                return secondExposePromise
            default:
                XCTFail("Unexpected request")
                return .init(error: OWSAssertionError(""))
            }
        }

        let firstBackupExpectation = self.expectation(description: "first backup")
        svr.generateAndBackupKeys(pin: "1234", authMethod: .implicit, rotateMasterKey: true).observe(on: SyncScheduler()) { (_: Result<Void, Error>) in
            firstBackupExpectation.fulfill()
        }
        let secondBackupExpectation = self.expectation(description: "first backup")
        svr.generateAndBackupKeys(pin: "abcd", authMethod: .implicit, rotateMasterKey: true).observe(on: SyncScheduler()) { (_: Result<Void, Error>) in
            secondBackupExpectation.fulfill()
        }

        firstBackupFuture.resolve(backupResponse())
        secondBackupFuture.resolve(backupResponse())
        secondExposeFuture.resolve(exposeResponse())
        wait(for: [
            madeRequestExpectations[0], // first backup
            firstBackupExpectation
        ], timeout: 10, enforceOrder: true)
        wait(for: [
            madeRequestExpectations[1], // second backup
            madeRequestExpectations[2], // second expose
            secondBackupExpectation,
            closeExpectation
        ], timeout: 10, enforceOrder: true)
    }

    func testWebsocketConnectionFailure() {

        let firstMockConnection = MockSgxWebsocketConnection<SVR2WebsocketConfigurator>()
        firstMockConnection.mockAuth = RemoteAttestation.Auth(username: "username", password: "password")

        let secondMockConnection = MockSgxWebsocketConnection<SVR2WebsocketConfigurator>()
        secondMockConnection.mockAuth = RemoteAttestation.Auth(username: "username2", password: "password2")
        let secondOpenExpectation = self.expectation(description: "open websocket 2")

        var numOpenedConnections = 0
        mockConnectionFactory.setOnConnectAndPerformHandshake { (_: SVR2WebsocketConfigurator) in
            numOpenedConnections += 1
            switch numOpenedConnections {
            case 1:
                return .value(firstMockConnection)
            case 2:
                secondOpenExpectation.fulfill()
                return .value(secondMockConnection)
            default:
                XCTFail("Unexpected number of opened connections")
                return .init(error: OWSAssertionError(""))
            }
        }

        let firstCloseExpectation = self.expectation(description: "close websocket 1")
        firstMockConnection.onDisconnect = {
            firstCloseExpectation.fulfill()
        }

        let (firstBackupPromise, firstBackupFuture) = Promise<SVR2Proto_Response>.pending()
        // We won't make a first expose request; it will get cancelled because of the failure.
        // We also won't make a second backup or expose request.

        var requestCount = 0
        let madeRequestExpectations = (0..<1).map { i in
            return self.expectation(description: "request \(i)")
        }
        firstMockConnection.onSendRequestAndReadResponse = { request in
            defer {
                madeRequestExpectations[requestCount].fulfill()
                requestCount += 1
            }
            switch requestCount {
            case 0:
                // First backup.
                XCTAssert(request.hasBackup)
                return firstBackupPromise
            default:
                XCTFail("Unexpected request")
                return .init(error: OWSAssertionError(""))
            }
        }

        let firstBackupError = WebSocketError.closeError(statusCode: 400, closeReason: nil)

        let firstBackupExpectation = self.expectation(description: "first backup")
        svr.generateAndBackupKeys(pin: "1234", authMethod: .implicit, rotateMasterKey: true).observe(on: SyncScheduler()) { (result: Result<Void, Error>) in
            switch result {
            case .success:
                XCTFail("Expected error on second backup.")
            case .failure:
                break
            }
            firstBackupExpectation.fulfill()
        }
        let secondBackupExpectation = self.expectation(description: "second backup")
        svr.generateAndBackupKeys(pin: "abcd", authMethod: .implicit, rotateMasterKey: true).observe(on: SyncScheduler()) { (result: Result<Void, Error>) in
            switch result {
            case .success:
                XCTFail("Expected error on second backup.")
            case .failure:
                break
            }
            secondBackupExpectation.fulfill()
        }

        firstBackupFuture.reject(firstBackupError)
        wait(for: [
            madeRequestExpectations[0], // first backup
            firstCloseExpectation,
            firstBackupExpectation,
            secondBackupExpectation
        ], timeout: 10, enforceOrder: true)

        XCTAssertEqual(numOpenedConnections, 1)

        // If we do another backup, it should open a new connection.

        secondMockConnection.onSendRequestAndReadResponse = { request in
            // Just leave it pending.
            return Promise<SVR2Proto_Response>.pending().0
        }

        let _: Promise<Void> = svr.generateAndBackupKeys(pin: "zzzz", authMethod: .implicit, rotateMasterKey: true)

        wait(for: [secondOpenExpectation], timeout: 10)
        XCTAssertEqual(numOpenedConnections, 2)
    }

    func testWebsocketFailure_Unretained() {
        let closeExpectation = self.expectation(description: "close websocket")
        // Never resolve the request future; deinitialization should reject all external promises.
        let (requestPromise, _) = Promise<SVR2Proto_Response>.pending()

        var firstBackupPromise: Promise<Void>!
        var secondBackupPromise: Promise<Void>!

        autoreleasepool {
            let mockConnection = MockSgxWebsocketConnection<SVR2WebsocketConfigurator>()
            mockConnection.mockAuth = RemoteAttestation.Auth(username: "username", password: "password")
            let mockConnectionFactory = MockSgxWebsocketConnectionFactory()

            mockConnection.onDisconnect = {
                closeExpectation.fulfill()
            }

            mockConnectionFactory.setOnConnectAndPerformHandshake { (_: SVR2WebsocketConfigurator) in
                return .value(mockConnection)
            }

            let sendRequestExpectation = self.expectation(description: "send request")
            mockConnection.onSendRequestAndReadResponse = { request in
                sendRequestExpectation.fulfill()
                return requestPromise
            }

            let kvStore = InMemoryKeyValueStoreFactory()
            let localStorage = SVRLocalStorageImpl(keyValueStoreFactory: kvStore)

            let svr = SecureValueRecovery2Impl(
                accountAttributesUpdater: MockAccountAttributesUpdater(),
                appReadiness: SVR2.Mocks.AppReadiness(),
                appVersion: MockAppVerion(),
                clientWrapper: MockSVR2ClientWrapper(),
                connectionFactory: mockConnectionFactory,
                credentialStorage: credentialStorage,
                db: db,
                keyValueStoreFactory: kvStore,
                schedulers: Schedulers(queue),
                storageServiceManager: FakeStorageServiceManager(),
                svrLocalStorage: localStorage,
                syncManager: OWSMockSyncManager(),
                tsAccountManager: MockTSAccountManager(),
                tsConstants: TSConstants.shared,
                twoFAManager: SVR2.TestMocks.OWS2FAManager()
            )
            firstBackupPromise = svr.generateAndBackupKeys(pin: "1234", authMethod: .implicit, rotateMasterKey: false)
            secondBackupPromise = svr.generateAndBackupKeys(pin: "1234", authMethod: .implicit, rotateMasterKey: false)

            wait(for: [sendRequestExpectation], timeout: 10)
        }

        let firstBackupExpectation = self.expectation(description: "backup 1")
        firstBackupPromise.observe(on: SyncScheduler()) { result in
            switch result {
            case .success:
                XCTFail("Expected failure")
            case .failure:
                break
            }
            firstBackupExpectation.fulfill()
        }

        let secondBackupExpectation = self.expectation(description: "backup 2")
        secondBackupPromise.observe(on: SyncScheduler()) { result in
            switch result {
            case .success:
                XCTFail("Expected failure")
            case .failure:
                break
            }
            secondBackupExpectation.fulfill()
        }

        wait(for: [
            closeExpectation,
            firstBackupExpectation,
            secondBackupExpectation
        ], timeout: 10)
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

    private class Schedulers: SignalServiceKit.Schedulers {

        let scheduler: AlwaysAsyncScheduler

        init(_ queue: DispatchQueue) {
            self.scheduler = AlwaysAsyncScheduler(queue)
        }

        var sync: SignalCoreKit.Scheduler { SyncScheduler() }

        var main: SignalCoreKit.Scheduler { scheduler }

        var sharedUserInteractive: SignalCoreKit.Scheduler { scheduler }

        var sharedUserInitiated: SignalCoreKit.Scheduler { scheduler }

        var sharedUtility: SignalCoreKit.Scheduler { scheduler }

        var sharedBackground: SignalCoreKit.Scheduler { scheduler }

        func sharedQueue(at qos: DispatchQoS) -> SignalCoreKit.Scheduler {
            return scheduler
        }

        func global(qos: DispatchQoS.QoSClass) -> SignalCoreKit.Scheduler {
            return scheduler
        }

        func queue(label: String, qos: DispatchQoS, attributes: DispatchQueue.Attributes, autoreleaseFrequency: DispatchQueue.AutoreleaseFrequency, target: DispatchQueue?) -> SignalCoreKit.Scheduler {
            return scheduler
        }
    }

    class AlwaysAsyncScheduler: Scheduler {

        private let queue: Scheduler

        init(_ queue: DispatchQueue) {
            self.queue = queue
        }

        func async(_ work: @escaping () -> Void) {
            queue.async {
                work()
            }
        }

        func sync(_ work: () -> Void) {
            queue.sync {
                work()
            }
        }

        func sync<T>(_ work: () throws -> T) rethrows -> T {
            try queue.sync {
                try work()
            }
        }

        func sync<T>(_ work: () -> T) -> T {
            queue.sync {
                work()
            }
        }

        func asyncAfter(deadline: DispatchTime, _ work: @escaping () -> Void) {
            queue.asyncAfter(deadline: deadline, work)
        }

        func asyncAfter(wallDeadline: DispatchWallTime, _ work: @escaping () -> Void) {
            queue.asyncAfter(wallDeadline: wallDeadline, work)
        }

        func asyncIfNecessary(execute work: @escaping () -> Void) {
            queue.async {
                work()
            }
        }

    }
}
