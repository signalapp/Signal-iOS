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

        self.svr = SecureValueRecovery2Impl(
            clientWrapper: mockClientWrapper,
            connectionFactory: mockConnectionFactory,
            credentialStorage: credentialStorage,
            db: db,
            keyValueStoreFactory: InMemoryKeyValueStoreFactory(),
            schedulers: Schedulers(queue),
            storageServiceManager: FakeStorageServiceManager(),
            syncManager: OWSMockSyncManager(),
            tsAccountManager: SVR.TestMocks.TSAccountManager(),
            twoFAManager: SVR.TestMocks.OWS2FAManager()
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
        svr.generateAndBackupKeys(pin: "1234", authMethod: .implicit, rotateMasterKey: true).observe(on: SyncScheduler()) { _ in
            firstBackupExpectation.fulfill()
        }

        // Let the first backup succeed and start the expose, then make the second request.
        firstBackupFuture.resolve(backupResponse())
        wait(for: [
            madeRequestExpectations[0],
            madeRequestExpectations[1]
        ], timeout: 10, enforceOrder: true)

        let secondBackupExpectation = self.expectation(description: "second backup")
        svr.generateAndBackupKeys(pin: "abcd", authMethod: .implicit, rotateMasterKey: true).observe(on: SyncScheduler()) { _ in
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
        svr.generateAndBackupKeys(pin: "1234", authMethod: .implicit, rotateMasterKey: true).observe(on: SyncScheduler()) { _ in
            firstBackupExpectation.fulfill()
        }
        let secondBackupExpectation = self.expectation(description: "first backup")
        svr.generateAndBackupKeys(pin: "abcd", authMethod: .implicit, rotateMasterKey: true).observe(on: SyncScheduler()) { _ in
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

        private let queue: DispatchQueue

        init(_ queue: DispatchQueue) {
            self.queue = queue
        }

        func async(_ work: @escaping () -> Void) {
            queue.async {
                work()
            }
        }

        func sync(_ work: @escaping () -> Void) {
            queue.sync {
                work()
            }
        }

        func sync<T>(_ work: @escaping () -> T) -> T {
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
