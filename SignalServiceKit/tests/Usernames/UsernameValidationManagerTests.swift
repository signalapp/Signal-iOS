//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import GRDB
import LibSignalClient
import XCTest

@testable import SignalServiceKit

final class UsernameValidationManagerTest: XCTestCase {
    typealias UntypedServiceId = SignalServiceKit.UntypedServiceId
    typealias Username = String

    private var mockAccountServiceClient: MockAccountServiceClient!
    private var mockContext: UsernameValidationManagerImpl.Context!
    private var mockDB: DB!
    private var mockScheduler: TestScheduler!
    private var mockStorageServiceManager: StorageServiceManagerMock!
    private var mockURLSession: TSRequestOWSURLSessionMock!
    private var mockUsernameLookupManager: UsernameLookupManagerMock!

    func setupContext(
        localAci: FutureAci,
        localUsername: String?,
        remoteUsername: String?,
        mockDeleteRequest: Bool = false
    ) {
        let mockAccountManager = MockAccountManager(aci: localAci)

        var remoteUserHash: String?
        if let remoteUsername = remoteUsername {
            remoteUserHash = try! Usernames.HashedUsername(forUsername: remoteUsername).hashString
        }
        mockAccountServiceClient = MockAccountServiceClient(
            aci: localAci,
            pni: FuturePni.randomForTesting(),
            e164: E164("+16125550101")!,
            usernameHash: remoteUserHash
        )
        mockURLSession = TSRequestOWSURLSessionMock()
        mockStorageServiceManager = StorageServiceManagerMock()
        mockScheduler = TestScheduler()
        mockUsernameLookupManager = UsernameLookupManagerMock(username: localUsername)
        mockDB = MockDB()
        let mockNetworkManager = UsernameFakeNetworkManager(mockURLSession: mockURLSession)

        mockContext = .init(
            accountManager: mockAccountManager,
            accountServiceClient: mockAccountServiceClient,
            database: mockDB,
            keyValueStoreFactory: InMemoryKeyValueStoreFactory(),
            messageProcessor: MessageProcessorMock(),
            networkManager: mockNetworkManager,
            schedulers: TestSchedulers(scheduler: mockScheduler),
            storageServiceManager: mockStorageServiceManager,
            usernameLookupManager: mockUsernameLookupManager
        )

        if mockDeleteRequest {
            mockURLSession.addResponse(.init(
                matcher: {
                    if
                        $0.httpMethod == "DELETE",
                        $0.url?.path.hasPrefix("v1/accounts/username_hash") ?? false
                    {
                        return true
                    }
                    return false
                },
                statusCode: 204,
                bodyData: nil
            ))
        }
    }

    func testSuccessfulValidation() {
        let localAci = FutureAci.randomForTesting()
        let localUsername = "testUsername.42"
        let remoteUsername = localUsername

        setupContext(
            localAci: localAci,
            localUsername: localUsername,
            remoteUsername: remoteUsername
        )

        let manager = UsernameValidationManagerImpl(context: mockContext)
        mockDB.read { transaction in
            manager.validateUsernameIfNecessary(transaction)
        }
        mockScheduler.runUntilIdle()

        mockDB.read { transaction in
            XCTAssertNotNil(manager.lastValidationDate(transaction))
            XCTAssertFalse(manager.hasUsernameFailedValidation(transaction))
            XCTAssertFalse(mockStorageServiceManager.didRecordPendingLocalAccountUpdates)
        }
    }

    func testFailedValidation() {
        let localAci = FutureAci.randomForTesting()
        let localUsername = "testUsername.42"
        let remoteUsername = "testUsername.43"

        setupContext(
            localAci: localAci,
            localUsername: localUsername,
            remoteUsername: remoteUsername,
            mockDeleteRequest: true
        )

        let manager = UsernameValidationManagerImpl(context: mockContext)
        mockDB.read { transaction in
            manager.validateUsernameIfNecessary(transaction)
        }
        mockScheduler.runUntilIdle()

        mockDB.read { transaction in
            XCTAssertNil(manager.lastValidationDate(transaction))
            XCTAssertTrue(manager.hasUsernameFailedValidation(transaction))
        }

        XCTAssertNil(mockUsernameLookupManager.currentlySetUsername)
        XCTAssertTrue(mockStorageServiceManager.didRecordPendingLocalAccountUpdates)
    }

    func testMissingRemoteHashValidation() {
        let localAci = FutureAci.randomForTesting()
        let localUsername = "testUsername.42"
        let remoteUsername: String? = nil

        setupContext(
            localAci: localAci,
            localUsername: localUsername,
            remoteUsername: remoteUsername,
            mockDeleteRequest: true
        )

        let manager = UsernameValidationManagerImpl(context: mockContext)
        mockDB.read { transaction in
            manager.validateUsernameIfNecessary(transaction)
        }
        mockScheduler.runUntilIdle()

        mockDB.read { transaction in
            XCTAssertNil(manager.lastValidationDate(transaction))
            XCTAssertTrue(manager.hasUsernameFailedValidation(transaction))
        }

        XCTAssertNil(mockUsernameLookupManager.currentlySetUsername)
        XCTAssertTrue(mockStorageServiceManager.didRecordPendingLocalAccountUpdates)
    }

    func testValidationAfterTimeout() {
        let localAci = FutureAci.randomForTesting()
        let localUsername = "testUsername.42"
        let remoteUsername = localUsername

        setupContext(
            localAci: localAci,
            localUsername: localUsername,
            remoteUsername: remoteUsername
        )

        let lastValidationDate = Date().addingTimeInterval(-12 * kHourInterval - 1)
        let manager = UsernameValidationManagerImpl(context: mockContext)

        mockDB.write { transaction in
            manager.setLastValidation(date: lastValidationDate, transaction)
        }

        mockDB.read { transaction in
            manager.validateUsernameIfNecessary(transaction)
        }
        mockScheduler.runUntilIdle()

        mockDB.read { transaction in
            XCTAssertNotNil(manager.lastValidationDate(transaction))
            XCTAssertNotEqual(manager.lastValidationDate(transaction), lastValidationDate)
            XCTAssertFalse(manager.hasUsernameFailedValidation(transaction))
        }
        XCTAssertFalse(mockStorageServiceManager.didRecordPendingLocalAccountUpdates)
    }

    func testFailValidationAfterTimeout() {
        let localAci = FutureAci.randomForTesting()
        let localUsername = "testUsername.42"
        let remoteUsername = "testUsername.43"

        setupContext(
            localAci: localAci,
            localUsername: localUsername,
            remoteUsername: remoteUsername,
            mockDeleteRequest: true
        )

        let lastValidationDate = Date().addingTimeInterval(-12 * kHourInterval - 1)
        let manager = UsernameValidationManagerImpl(context: mockContext)

        mockDB.write { transaction in
            manager.setLastValidation(date: lastValidationDate, transaction)
        }

        mockDB.read { transaction in
            manager.validateUsernameIfNecessary(transaction)
        }

        mockScheduler.runUntilIdle()

        mockDB.read { transaction in
            XCTAssertNil(manager.lastValidationDate(transaction))
            XCTAssertTrue(manager.hasUsernameFailedValidation(transaction))
        }
        XCTAssertNil(mockUsernameLookupManager.currentlySetUsername)
        XCTAssertTrue(mockStorageServiceManager.didRecordPendingLocalAccountUpdates)
    }

    func testSkipValidation() {
        let localAci = FutureAci.randomForTesting()
        let localUsername = "testUsername.42"
        let remoteUsername = "testUsername.43"

        setupContext(
            localAci: localAci,
            localUsername: localUsername,
            remoteUsername: remoteUsername,
            mockDeleteRequest: true
        )

        let manager = UsernameValidationManagerImpl(context: mockContext)

        let lastValidationDate = Date().addingTimeInterval(-5 * kHourInterval)
        mockDB.write { transaction in
            manager.setLastValidation(date: lastValidationDate, transaction)
        }

        mockDB.read { transaction in
            manager.validateUsernameIfNecessary(transaction)
        }
        mockScheduler.runUntilIdle()

        mockDB.read { transaction in
            XCTAssertEqual(manager.lastValidationDate(transaction), lastValidationDate)
            XCTAssertFalse(manager.hasUsernameFailedValidation(transaction))
        }
        XCTAssertFalse(mockStorageServiceManager.didRecordPendingLocalAccountUpdates)
    }

    func testInvalidLocalUsername() {
        let localAci = FutureAci.randomForTesting()
        let localUsername = "testUsername"
        let remoteUsername = "testUsername.43"

        setupContext(
            localAci: localAci,
            localUsername: localUsername,
            remoteUsername: remoteUsername,
            mockDeleteRequest: true
        )

        let manager = UsernameValidationManagerImpl(context: mockContext)
        mockDB.read { transaction in
            manager.validateUsernameIfNecessary(transaction)
        }
        mockScheduler.runUntilIdle()

        mockDB.read { transaction in
            XCTAssertNil(manager.lastValidationDate(transaction))
            XCTAssertTrue(manager.hasUsernameFailedValidation(transaction))
        }

        XCTAssertNil(mockUsernameLookupManager.currentlySetUsername)
        XCTAssertTrue(mockStorageServiceManager.didRecordPendingLocalAccountUpdates)
    }
}

// MARK: - Mocks

extension UsernameValidationManagerTest {
    private class MockAccountManager: Usernames.Validation.Shims.TSAccountManager {
        private let aci: FutureAci
        init(aci: FutureAci) { self.aci = aci }
        public func localAci(tx _: DBReadTransaction) -> FutureAci? { aci }
    }

    private class UsernameFakeNetworkManager: OWSFakeNetworkManager {
        let mockURLSession: TSRequestOWSURLSessionMock
        public init(mockURLSession: TSRequestOWSURLSessionMock) {
            self.mockURLSession = mockURLSession
        }

        override public func makePromise(
            request: TSRequest,
            canUseWebSocket: Bool = false) -> Promise<HTTPResponse> {
            return mockURLSession.promiseForTSRequest(request)
        }
    }

    private class UsernameLookupManagerMock: UsernameLookupManager {
        let username: UsernameLookupManager.Username?
        var currentlySetUsername: UsernameLookupManager.Username?

        init(username: UsernameLookupManager.Username?) {
            self.username = username
            self.currentlySetUsername = username
        }

        public func fetchUsername(forAci aci: UntypedServiceId, transaction: DBReadTransaction) -> UsernameLookupManager.Username? {
            return username
        }

        public func fetchUsernames(forAddresses addresses: AnySequence<SignalServiceAddress>, transaction: DBReadTransaction) -> [UsernameLookupManager.Username?] {
            return [username]
        }

        public func saveUsername(_ username: Username?, forAci aci: UntypedServiceId, transaction: DBWriteTransaction) {
            self.currentlySetUsername = username
        }
    }

    private class StorageServiceManagerMock: Usernames.Validation.Shims.StorageServiceManager {
        var didRecordPendingLocalAccountUpdates: Bool = false

        public func recordPendingLocalAccountUpdates() {
            didRecordPendingLocalAccountUpdates = true
        }

        public func waitForPendingRestores() -> Promise<Void> {
            return Promise<Void>.value(())
        }
    }

    private class MessageProcessorMock:
        Usernames.Validation.Shims.MessageProcessor {
        public func fetchingAndProcessingCompletePromise() -> Promise<Void> {
            return Promise<Void>.value(())
        }
    }

    private class MockAccountServiceClient: Usernames.Validation.Shims.AccountServiceClient {
        private let response: WhoAmIRequestFactory.Responses.WhoAmI
        init(aci: FutureAci, pni: FuturePni, e164: E164, usernameHash: String?) {
            response = WhoAmIRequestFactory.Responses.WhoAmI(
                aci: aci.uuidValue,
                pni: pni.uuidValue,
                e164: e164,
                usernameHash: usernameHash
            )
        }

        func getAccountWhoAmI() -> Promise<WhoAmIRequestFactory.Responses.WhoAmI> {
            return Promise<WhoAmIRequestFactory.Responses.WhoAmI>.value(response)
        }
    }
}
