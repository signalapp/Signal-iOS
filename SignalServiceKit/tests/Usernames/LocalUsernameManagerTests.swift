//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import LibSignalClient
import XCTest

@testable import SignalServiceKit

class LocalUsernameManagerTests: XCTestCase {
    private var mockDB: MockDB!
    private var testScheduler: TestScheduler!

    private var mockStorageServiceManager: MockStorageServiceManager!
    private var mockUsernameApiClient: MockUsernameApiClient!
    private var mockUsernameLinkManager: MockUsernameLinkManager!

    private var kvStoreFactory: KeyValueStoreFactory!
    private var kvStore: KeyValueStore!

    private var localUsernameManager: LocalUsernameManager!

    override func setUp() {
        mockDB = MockDB()
        testScheduler = TestScheduler()

        mockStorageServiceManager = MockStorageServiceManager()
        mockUsernameApiClient = MockUsernameApiClient()
        mockUsernameLinkManager = MockUsernameLinkManager()

        kvStoreFactory = InMemoryKeyValueStoreFactory()
        kvStore = kvStoreFactory.keyValueStore(collection: "localUsernameManager")

        localUsernameManager = LocalUsernameManagerImpl(
            db: mockDB,
            kvStoreFactory: kvStoreFactory,
            schedulers: TestSchedulers(scheduler: testScheduler),
            storageServiceManager: mockStorageServiceManager,
            usernameApiClient: mockUsernameApiClient,
            usernameLinkManager: mockUsernameLinkManager
        )
    }

    override func tearDown() {
        mockUsernameApiClient.confirmationResult.ensureUnset()
        mockUsernameApiClient.deletionResult.ensureUnset()
        mockUsernameApiClient.setLinkResult.ensureUnset()
        XCTAssertNil(mockUsernameLinkManager.entropyToGenerate)
    }

    // MARK: Local state changes

    func testLocalUsernameStateChanges() {
        let linkHandle = UUID()

        XCTAssertEqual(usernameState(), .unset)

        mockDB.write { tx in
            localUsernameManager.setLocalUsername(
                username: "boba-fett",
                usernameLink: .mock(handle: linkHandle),
                tx: tx
            )
        }

        XCTAssertEqual(
            usernameState(),
            .available(username: "boba-fett", usernameLink: .mock(handle: linkHandle))
        )

        mockDB.write { tx in
            localUsernameManager.setLocalUsernameWithCorruptedLink(
                username: "boba-fett",
                tx: tx
            )
        }

        XCTAssertEqual(usernameState(), .linkCorrupted(username: "boba-fett"))

        mockDB.write { tx in
            localUsernameManager.clearLocalUsername(tx: tx)
        }

        XCTAssertEqual(usernameState(), .unset)
    }

    func testUsernameQRCodeColorChanges() {
        func color() -> Usernames.QRCodeColor {
            return mockDB.read { tx in
                return localUsernameManager.usernameLinkQRCodeColor(tx: tx)
            }
        }

        XCTAssertEqual(color(), .unknown)

        mockDB.write { tx in
            localUsernameManager.setUsernameLinkQRCodeColor(
                color: .olive,
                tx: tx
            )
        }

        XCTAssertEqual(color(), .olive)
    }

    // MARK: Confirmation

    func testConfirmUsernameHappyPath() {
        let linkHandle = UUID()
        let username = "boba_fett.42"

        mockUsernameLinkManager.entropyToGenerate = .success(.mockEntropy)
        mockUsernameApiClient.confirmationResult = .value(.success(
            usernameLinkHandle: linkHandle
        ))

        XCTAssertEqual(usernameState(), .unset)

        let promise = mockDB.write { tx in
            localUsernameManager.confirmUsername(
                reservedUsername: .mock(username),
                tx: tx
            )
        }

        testScheduler.runUntilIdle()

        XCTAssertEqual(
            promise.value,
            .success(username: username, usernameLink: .mock(handle: linkHandle))
        )
        XCTAssertEqual(
            usernameState(),
            .available(username: username, usernameLink: .mock(handle: linkHandle))
        )
        XCTAssertTrue(mockStorageServiceManager.didRecordPendingLocalAccountUpdates)
    }

    func testNoCorruptionIfFailToGenerateLink() {
        mockUsernameLinkManager.entropyToGenerate = .failure(OWSGenericError("A Sarlacc"))

        let stateBeforeConfirm = setUsername(username: "boba_fett.42")

        let promise = mockDB.write { tx in
            localUsernameManager.confirmUsername(
                reservedUsername: .mock("boba_fett.43"),
                tx: tx
            )
        }

        XCTAssertNil(promise.value)
        XCTAssertEqual(usernameState(), stateBeforeConfirm)
        XCTAssertFalse(mockStorageServiceManager.didRecordPendingLocalAccountUpdates)
    }

    func testCorruptionIfErrorWhileConfirming() {
        mockUsernameLinkManager.entropyToGenerate = .success(.mockEntropy)
        mockUsernameApiClient.confirmationResult = .error()

        XCTAssertEqual(usernameState(), .unset)

        let promise = mockDB.write { tx in
            localUsernameManager.confirmUsername(
                reservedUsername: .mock("boba_fett.42"),
                tx: tx
            )
        }

        testScheduler.runUntilIdle()

        XCTAssertNil(promise.value)
        XCTAssertEqual(usernameState(), .usernameAndLinkCorrupted)
        XCTAssertFalse(mockStorageServiceManager.didRecordPendingLocalAccountUpdates)
    }

    func testNoCorruptionIfRejectedWhileConfirming() {
        mockUsernameLinkManager.entropyToGenerate = .success(.mockEntropy)
        mockUsernameApiClient.confirmationResult = .value(.rejected)

        let stateBeforeConfirm = setUsername(username: "boba_fett.42")

        let promise = mockDB.write { tx in
            localUsernameManager.confirmUsername(
                reservedUsername: .mock("boba_fett.43"),
                tx: tx
            )
        }

        testScheduler.runUntilIdle()

        XCTAssertEqual(promise.value, .rejected)
        XCTAssertEqual(usernameState(), stateBeforeConfirm)
        XCTAssertFalse(mockStorageServiceManager.didRecordPendingLocalAccountUpdates)
    }

    func testNoCorruptionIfRateLimitedWhileConfirming() {
        mockUsernameLinkManager.entropyToGenerate = .success(.mockEntropy)
        mockUsernameApiClient.confirmationResult = .value(.rateLimited)

        let stateBeforeConfirm = setUsername(username: "boba_fett.42")

        let promise = mockDB.write { tx in
            localUsernameManager.confirmUsername(
                reservedUsername: .mock("boba_fett.43"),
                tx: tx
            )
        }

        testScheduler.runUntilIdle()

        XCTAssertEqual(promise.value, .rateLimited)
        XCTAssertEqual(usernameState(), stateBeforeConfirm)
        XCTAssertFalse(mockStorageServiceManager.didRecordPendingLocalAccountUpdates)
    }

    func testSuccessfulConfirmationClearsLinkCorruption() {
        let newHandle = UUID()

        mockUsernameLinkManager.entropyToGenerate = .success(.mockEntropy)
        mockUsernameApiClient.confirmationResult = .value(.success(usernameLinkHandle: newHandle))

        mockDB.write { tx in
            localUsernameManager.setLocalUsernameWithCorruptedLink(
                username: "boba_fett.42",
                tx: tx
            )
        }

        XCTAssertEqual(usernameState(), .linkCorrupted(username: "boba_fett.42"))

        let promise = mockDB.write { tx in
            localUsernameManager.confirmUsername(
                reservedUsername: try! Usernames.HashedUsername(forUsername: "boba_fett.43"),
                tx: tx
            )
        }

        testScheduler.runUntilIdle()

        let expectedNewLink = Usernames.UsernameLink(handle: newHandle, entropy: .mockEntropy)!

        XCTAssertEqual(
            promise.value,
            .success(username: "boba_fett.43", usernameLink: expectedNewLink)
        )
        XCTAssertEqual(
            usernameState(),
            .available(username: "boba_fett.43", usernameLink: expectedNewLink)
        )
        XCTAssertTrue(mockStorageServiceManager.didRecordPendingLocalAccountUpdates)
    }

    func testSuccessfulConfirmationClearsUsernameCorruption() {
        let newHandle = UUID()

        mockUsernameLinkManager.entropyToGenerate = .success(.mockEntropy)
        mockUsernameApiClient.confirmationResult = .value(.success(usernameLinkHandle: newHandle))

        mockDB.write { tx in
            localUsernameManager.setLocalUsernameCorrupted(tx: tx)
        }

        XCTAssertEqual(usernameState(), .usernameAndLinkCorrupted)

        let promise = mockDB.write { tx in
            localUsernameManager.confirmUsername(
                reservedUsername: try! Usernames.HashedUsername(forUsername: "boba_fett.43"),
                tx: tx
            )
        }

        testScheduler.runUntilIdle()

        let expectedNewLink = Usernames.UsernameLink(handle: newHandle, entropy: .mockEntropy)!

        XCTAssertEqual(
            promise.value,
            .success(username: "boba_fett.43", usernameLink: expectedNewLink)
        )
        XCTAssertEqual(
            usernameState(),
            .available(username: "boba_fett.43", usernameLink: expectedNewLink)
        )
        XCTAssertTrue(mockStorageServiceManager.didRecordPendingLocalAccountUpdates)
    }

    // MARK: Deletion

    func testDeletionHappyPath() {
        mockUsernameApiClient.deletionResult = .value(())

        _ = setUsername(username: "boba_fett.42")

        let promise = mockDB.write { tx in
            localUsernameManager.deleteUsername(tx: tx)
        }

        testScheduler.runUntilIdle()

        XCTAssertNotNil(promise.value)
        XCTAssertEqual(usernameState(), .unset)
        XCTAssertTrue(mockStorageServiceManager.didRecordPendingLocalAccountUpdates)
    }

    func testCorruptionIfErrorWhileDeleting() {
        mockUsernameApiClient.deletionResult = .error()

        _ = setUsername(username: "boba_fett.42")

        let promise = mockDB.write { tx in
            localUsernameManager.deleteUsername(tx: tx)
        }

        testScheduler.runUntilIdle()

        XCTAssertNil(promise.value)
        XCTAssertEqual(usernameState(), .usernameAndLinkCorrupted)
        XCTAssertFalse(mockStorageServiceManager.didRecordPendingLocalAccountUpdates)
    }

    func testDeletionClearsCorruption() {
        mockUsernameApiClient.deletionResult = .value(())

        mockDB.write { tx in
            localUsernameManager.setLocalUsernameCorrupted(tx: tx)
        }

        XCTAssertEqual(usernameState(), .usernameAndLinkCorrupted)

        let promise = mockDB.write { tx in
            localUsernameManager.deleteUsername(tx: tx)
        }

        testScheduler.runUntilIdle()

        XCTAssertNotNil(promise.value)
        XCTAssertEqual(usernameState(), .unset)
        XCTAssertTrue(mockStorageServiceManager.didRecordPendingLocalAccountUpdates)
    }

    func testDeletionClearsLinkCorruption() {
        mockUsernameApiClient.deletionResult = .value(())

        mockDB.write { tx in
            localUsernameManager.setLocalUsernameWithCorruptedLink(
                username: "boba_fett.42",
                tx: tx
            )
        }

        XCTAssertEqual(usernameState(), .linkCorrupted(username: "boba_fett.42"))

        let promise = mockDB.write { tx in
            localUsernameManager.deleteUsername(tx: tx)
        }

        testScheduler.runUntilIdle()

        XCTAssertNotNil(promise.value)
        XCTAssertEqual(usernameState(), .unset)
        XCTAssertTrue(mockStorageServiceManager.didRecordPendingLocalAccountUpdates)
    }

    // MARK: Rotate link

    func testRotationHappyPath() {
        let newHandle = UUID()

        mockUsernameLinkManager.entropyToGenerate = .success(.mockEntropy)
        mockUsernameApiClient.setLinkResult = .value(newHandle)

        _ = setUsername(username: "boba_fett.42")

        let promise = mockDB.write { tx in
            localUsernameManager.rotateUsernameLink(tx: tx)
        }

        testScheduler.runUntilIdle()

        let expectedNewLink = Usernames.UsernameLink(handle: newHandle, entropy: .mockEntropy)!

        XCTAssertEqual(promise.value, expectedNewLink)
        XCTAssertEqual(
            usernameState(),
            .available(username: "boba_fett.42", usernameLink: expectedNewLink)
        )
        XCTAssertTrue(mockStorageServiceManager.didRecordPendingLocalAccountUpdates)
    }

    func testNoCorruptionIfFailToGenerateNewLink() {
        mockUsernameLinkManager.entropyToGenerate = .failure(OWSGenericError("Jabba's Sudden But Inevitable Betrayal"))

        let stateBeforeRotate = setUsername(username: "boba_fett.42")

        let promise = mockDB.write { tx in
            localUsernameManager.rotateUsernameLink(tx: tx)
        }

        XCTAssertNil(promise.value)
        XCTAssertEqual(usernameState(), stateBeforeRotate)
        XCTAssertFalse(mockStorageServiceManager.didRecordPendingLocalAccountUpdates)
    }

    func testCorruptionIfErrorWhileRotatingLink() {
        mockUsernameLinkManager.entropyToGenerate = .success(.mockEntropy)
        mockUsernameApiClient.setLinkResult = .error()

        _ = setUsername(username: "boba_fett.42")

        let promise = mockDB.write { tx in
            localUsernameManager.rotateUsernameLink(tx: tx)
        }

        testScheduler.runUntilIdle()

        XCTAssertNil(promise.value)
        XCTAssertEqual(usernameState(), .linkCorrupted(username: "boba_fett.42"))
        XCTAssertFalse(mockStorageServiceManager.didRecordPendingLocalAccountUpdates)
    }

    func testSuccessfulRotationClearsCorruption() {
        let newHandle = UUID()

        mockUsernameLinkManager.entropyToGenerate = .success(.mockEntropy)
        mockUsernameApiClient.setLinkResult = .value(newHandle)

        mockDB.write { tx in
            localUsernameManager.setLocalUsernameWithCorruptedLink(
                username: "boba_fett.42",
                tx: tx
            )
        }

        XCTAssertEqual(usernameState(), .linkCorrupted(username: "boba_fett.42"))

        let promise = mockDB.write { tx in
            localUsernameManager.rotateUsernameLink(tx: tx)
        }

        testScheduler.runUntilIdle()

        let expectedNewLink = Usernames.UsernameLink(handle: newHandle, entropy: .mockEntropy)!

        XCTAssertEqual(promise.value, expectedNewLink)
        XCTAssertEqual(
            usernameState(),
            .available(username: "boba_fett.42", usernameLink: expectedNewLink)
        )
        XCTAssertTrue(mockStorageServiceManager.didRecordPendingLocalAccountUpdates)
    }

    // MARK: Utilities

    private func setUsername(username: String) -> Usernames.LocalUsernameState {
        return mockDB.write { tx in
            localUsernameManager.setLocalUsername(
                username: username,
                usernameLink: .mock(handle: UUID()),
                tx: tx
            )

            return localUsernameManager.usernameState(tx: tx)
        }
    }

    private func usernameState() -> Usernames.LocalUsernameState {
        return mockDB.read { tx in
            return localUsernameManager.usernameState(tx: tx)
        }
    }
}

private extension Usernames.HashedUsername {
    static func mock(_ username: String) -> Usernames.HashedUsername {
        try! Usernames.HashedUsername(forUsername: username)
    }
}

private extension Usernames.UsernameLink {
    static func mock(handle: UUID) -> Usernames.UsernameLink {
        Usernames.UsernameLink(
            handle: handle,
            entropy: .mockEntropy
        )!
    }
}

private extension Data {
    static let mockEntropy = Data(repeating: 12, count: 32)
}

// MARK: - Mocks

private class MockStorageServiceManager: StorageServiceManager {
    var didRecordPendingLocalAccountUpdates: Bool = false

    func recordPendingLocalAccountUpdates() {
        didRecordPendingLocalAccountUpdates = true
    }

    func waitForPendingRestores() -> AnyPromise {
        return AnyPromise(Promise<Void>.value(()))
    }

    func resetLocalData(transaction: DBWriteTransaction) { owsFail("Not implemented!") }
    func recordPendingDeletions(deletedGroupV1Ids: [Data]) { owsFail("Not implemented!") }
    func recordPendingUpdates(updatedAccountIds: [AccountId]) { owsFail("Not implemented!") }
    func recordPendingUpdates(updatedAddresses: [SignalServiceAddress]) { owsFail("Not implemented!") }
    func recordPendingUpdates(updatedGroupV1Ids: [Data]) { owsFail("Not implemented!") }
    func recordPendingUpdates(updatedGroupV2MasterKeys: [Data]) { owsFail("Not implemented!") }
    func recordPendingUpdates(updatedStoryDistributionListIds: [Data]) { owsFail("Not implemented!") }
    func recordPendingUpdates(groupModel: TSGroupModel) { owsFail("Not implemented!") }
    func setLocalIdentifiers(_ localIdentifiers: LocalIdentifiersObjC) { owsFail("Not implemented!") }
    func backupPendingChanges(authedAccount: AuthedAccount) { owsFail("Not implemented!") }
    func restoreOrCreateManifestIfNecessary(authedAccount: AuthedAccount) -> AnyPromise { owsFail("Not implemented!") }
}

private class MockUsernameApiClient: UsernameApiClient {

    // MARK: Confirm

    var confirmationResult: ConsumableMockPromise<Usernames.ApiClientConfirmationResult> = .unset

    func confirmReservedUsername(reservedUsername: Usernames.HashedUsername, encryptedUsernameForLink: Data) -> Promise<Usernames.ApiClientConfirmationResult> {
        return confirmationResult.consumeIntoPromise()
    }

    // MARK: Delete

    var deletionResult: ConsumableMockPromise<Void> = .unset

    func deleteCurrentUsername() -> Promise<Void> {
        return deletionResult.consumeIntoPromise()
    }

    // MARK: Set link

    var setLinkResult: ConsumableMockPromise<UUID> = .unset

    func setUsernameLink(encryptedUsername: Data) -> Promise<UUID> {
        return setLinkResult.consumeIntoPromise()
    }

    // MARK: Unimplemented

    func reserveUsernameCandidates(usernameCandidates: Usernames.HashedUsername.GeneratedCandidates) -> Promise<Usernames.ApiClientReservationResult> { owsFail("Not implemented!") }
    func lookupAci(forHashedUsername hashedUsername: Usernames.HashedUsername) -> Promise<Aci?> { owsFail("Not implemented!") }
    func getUsernameLink(handle: UUID) -> Promise<Data?> { owsFail("Not implemented!") }
}

private class MockUsernameLinkManager: UsernameLinkManager {
    var entropyToGenerate: Result<Data, Error>?

    func generateEncryptedUsername(username: String) throws -> (entropy: Data, encryptedUsername: Data) {
        guard let entropyToGenerate else {
            XCTFail("No mock set!")
            throw OWSGenericError("No mock set!")
        }

        self.entropyToGenerate = nil

        switch entropyToGenerate {
        case .success(let entropy):
            return (entropy, Data())
        case .failure(let error):
            throw error
        }
    }

    func decryptEncryptedLink(link: Usernames.UsernameLink) -> Promise<String?> {
        owsFail("Not implemented!")
    }
}
