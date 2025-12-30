//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import LibSignalClient
import SignalRingRTC
import XCTest

@testable import SignalServiceKit

class LocalUsernameManagerTests: XCTestCase {
    private var mockDB: InMemoryDB!

    private var mockReachabilityManager: MockReachabilityManager!
    private var mockStorageServiceManager: MockStorageServiceManager!
    private var mockUsernameApiClient: MockUsernameApiClient!
    private var mockUsernameLinkManager: MockUsernameLinkManager!

    private var kvStore: KeyValueStore!

    private var localUsernameManager: LocalUsernameManager!

    override func setUp() {
        mockDB = InMemoryDB()

        mockReachabilityManager = MockReachabilityManager()
        mockStorageServiceManager = MockStorageServiceManager()
        mockUsernameApiClient = MockUsernameApiClient()
        mockUsernameLinkManager = MockUsernameLinkManager()

        kvStore = KeyValueStore(collection: "localUsernameManager")

        setLocalUsernameManager(maxNetworkRequestRetries: 0)
    }

    private func setLocalUsernameManager(maxNetworkRequestRetries: Int) {
        localUsernameManager = LocalUsernameManagerImpl(
            db: mockDB,
            reachabilityManager: mockReachabilityManager,
            storageServiceManager: mockStorageServiceManager,
            usernameApiClient: mockUsernameApiClient,
            usernameLinkManager: mockUsernameLinkManager,
            maxNetworkRequestRetries: maxNetworkRequestRetries,
        )
    }

    override func tearDown() {
        owsPrecondition(mockUsernameApiClient.confirmReservedUsernameMocks.isEmpty)
        owsPrecondition(mockUsernameApiClient.deleteCurrentUsernameMocks.isEmpty)
        owsPrecondition(mockUsernameApiClient.setUsernameLinkMocks.isEmpty)
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
                tx: tx,
            )
        }

        XCTAssertEqual(
            usernameState(),
            .available(username: "boba-fett", usernameLink: .mock(handle: linkHandle)),
        )

        mockDB.write { tx in
            localUsernameManager.setLocalUsernameWithCorruptedLink(
                username: "boba-fett",
                tx: tx,
            )
        }

        XCTAssertEqual(usernameState(), .linkCorrupted(username: "boba-fett"))

        mockDB.write { tx in
            localUsernameManager.clearLocalUsername(tx: tx)
        }

        XCTAssertEqual(usernameState(), .unset)
    }

    func testUsernameQRCodeColorChanges() {
        func color() -> QRCodeColor {
            return mockDB.read { tx in
                return localUsernameManager.usernameLinkQRCodeColor(tx: tx)
            }
        }

        XCTAssertEqual(color(), .unknown)

        mockDB.write { tx in
            localUsernameManager.setUsernameLinkQRCodeColor(
                color: .olive,
                tx: tx,
            )
        }

        XCTAssertEqual(color(), .olive)
    }

    // MARK: Confirmation

    func testConfirmUsernameHappyPath() async {
        let linkHandle = UUID()
        let username = "boba_fett.42"

        mockUsernameLinkManager.entropyToGenerate = .success(.mockEntropy)
        mockUsernameApiClient.confirmReservedUsernameMocks = [{ _, _, _ in .success(usernameLinkHandle: linkHandle) }]

        XCTAssertEqual(usernameState(), .unset)

        let value = await localUsernameManager.confirmUsername(reservedUsername: .mock(username))

        XCTAssertEqual(
            value,
            .success(.success(username: username, usernameLink: .mock(handle: linkHandle))),
        )
        XCTAssertEqual(
            usernameState(),
            .available(username: username, usernameLink: .mock(handle: linkHandle)),
        )
        XCTAssertTrue(mockStorageServiceManager.didRecordPendingLocalAccountUpdates)
    }

    func testConfirmBailsEarlyIfNotReachable() async {
        mockReachabilityManager.isReachable = false

        let stateBeforeConfirm = setUsername(username: "boba_fett.42")

        let value = await localUsernameManager.confirmUsername(reservedUsername: .mock("boba_fett.43"))

        XCTAssertEqual(value, .failure(.networkError))
        XCTAssertEqual(usernameState(), stateBeforeConfirm)
        XCTAssertFalse(mockStorageServiceManager.didRecordPendingLocalAccountUpdates)
    }

    func testNoCorruptionIfFailToGenerateLink() async {
        mockUsernameLinkManager.entropyToGenerate = .failure(OWSGenericError("A Sarlacc"))

        let stateBeforeConfirm = setUsername(username: "boba_fett.42")

        let value = await localUsernameManager.confirmUsername(reservedUsername: .mock("boba_fett.43"))

        XCTAssertEqual(value, .failure(.otherError))
        XCTAssertEqual(usernameState(), stateBeforeConfirm)
        XCTAssertFalse(mockStorageServiceManager.didRecordPendingLocalAccountUpdates)
    }

    func testCorruptionIfNetworkErrorWhileConfirming() async {
        mockUsernameLinkManager.entropyToGenerate = .success(.mockEntropy)
        mockUsernameApiClient.confirmReservedUsernameMocks = [{ _, _, _ in throw OWSHTTPError.mockNetworkFailure }]

        XCTAssertEqual(usernameState(), .unset)

        let value = await localUsernameManager.confirmUsername(reservedUsername: .mock("boba_fett.42"))

        XCTAssertEqual(value, .failure(.networkError))
        XCTAssertEqual(usernameState(), .usernameAndLinkCorrupted)
        XCTAssertFalse(mockStorageServiceManager.didRecordPendingLocalAccountUpdates)
    }

    func testCorruptionIfErrorWhileConfirming() async {
        mockUsernameLinkManager.entropyToGenerate = .success(.mockEntropy)
        mockUsernameApiClient.confirmReservedUsernameMocks = [{ _, _, _ in throw OWSGenericError("") }]

        XCTAssertEqual(usernameState(), .unset)

        let value = await localUsernameManager.confirmUsername(reservedUsername: .mock("boba_fett.42"))

        XCTAssertEqual(value, .failure(.otherError))
        XCTAssertEqual(usernameState(), .usernameAndLinkCorrupted)
        XCTAssertFalse(mockStorageServiceManager.didRecordPendingLocalAccountUpdates)
    }

    func testNoCorruptionIfRejectedWhileConfirming() async {
        mockUsernameLinkManager.entropyToGenerate = .success(.mockEntropy)
        mockUsernameApiClient.confirmReservedUsernameMocks = [{ _, _, _ in .rejected }]

        let stateBeforeConfirm = setUsername(username: "boba_fett.42")

        let value = await localUsernameManager.confirmUsername(reservedUsername: .mock("boba_fett.43"))

        XCTAssertEqual(value, .success(.rejected))
        XCTAssertEqual(usernameState(), stateBeforeConfirm)
        XCTAssertFalse(mockStorageServiceManager.didRecordPendingLocalAccountUpdates)
    }

    func testNoCorruptionIfRateLimitedWhileConfirming() async {
        mockUsernameLinkManager.entropyToGenerate = .success(.mockEntropy)
        mockUsernameApiClient.confirmReservedUsernameMocks = [{ _, _, _ in .rateLimited }]

        let stateBeforeConfirm = setUsername(username: "boba_fett.42")

        let value = await localUsernameManager.confirmUsername(reservedUsername: .mock("boba_fett.43"))

        XCTAssertEqual(value, .success(.rateLimited))
        XCTAssertEqual(usernameState(), stateBeforeConfirm)
        XCTAssertFalse(mockStorageServiceManager.didRecordPendingLocalAccountUpdates)
    }

    func testSuccessfulConfirmationClearsLinkCorruption() async {
        let newHandle = UUID()

        mockUsernameLinkManager.entropyToGenerate = .success(.mockEntropy)
        mockUsernameApiClient.confirmReservedUsernameMocks = [{ _, _, _ in .success(usernameLinkHandle: newHandle) }]

        mockDB.write { tx in
            localUsernameManager.setLocalUsernameWithCorruptedLink(
                username: "boba_fett.42",
                tx: tx,
            )
        }

        XCTAssertEqual(usernameState(), .linkCorrupted(username: "boba_fett.42"))

        let value = await localUsernameManager.confirmUsername(reservedUsername: try! Usernames.HashedUsername(forUsername: "boba_fett.43"))

        let expectedNewLink = Usernames.UsernameLink(handle: newHandle, entropy: .mockEntropy)!

        XCTAssertEqual(
            value,
            .success(.success(username: "boba_fett.43", usernameLink: expectedNewLink)),
        )
        XCTAssertEqual(
            usernameState(),
            .available(username: "boba_fett.43", usernameLink: expectedNewLink),
        )
        XCTAssertTrue(mockStorageServiceManager.didRecordPendingLocalAccountUpdates)
    }

    func testSuccessfulConfirmationClearsUsernameCorruption() async {
        let newHandle = UUID()

        mockUsernameLinkManager.entropyToGenerate = .success(.mockEntropy)
        mockUsernameApiClient.confirmReservedUsernameMocks = [{ _, _, _ in .success(usernameLinkHandle: newHandle) }]

        mockDB.write { tx in
            localUsernameManager.setLocalUsernameCorrupted(tx: tx)
        }

        XCTAssertEqual(usernameState(), .usernameAndLinkCorrupted)

        let value = await localUsernameManager.confirmUsername(reservedUsername: try! Usernames.HashedUsername(forUsername: "boba_fett.43"))

        let expectedNewLink = Usernames.UsernameLink(handle: newHandle, entropy: .mockEntropy)!

        XCTAssertEqual(
            value,
            .success(.success(username: "boba_fett.43", usernameLink: expectedNewLink)),
        )
        XCTAssertEqual(
            usernameState(),
            .available(username: "boba_fett.43", usernameLink: expectedNewLink),
        )
        XCTAssertTrue(mockStorageServiceManager.didRecordPendingLocalAccountUpdates)
    }

    // MARK: Deletion

    func testDeletionHappyPath() async {
        mockUsernameApiClient.deleteCurrentUsernameMocks = [{}]

        _ = setUsername(username: "boba_fett.42")

        let value = await localUsernameManager.deleteUsername()

        XCTAssertEqual(value.isSuccess, true)
        XCTAssertEqual(usernameState(), .unset)
        XCTAssertTrue(mockStorageServiceManager.didRecordPendingLocalAccountUpdates)
    }

    func testDeleteBailsEarlyIfNotReachable() async {
        mockReachabilityManager.isReachable = false

        let stateBeforeConfirm = setUsername(username: "boba_fett.42")

        let value = await localUsernameManager.deleteUsername()

        XCTAssertEqual(value.isNetworkError, true)
        XCTAssertEqual(usernameState(), stateBeforeConfirm)
        XCTAssertFalse(mockStorageServiceManager.didRecordPendingLocalAccountUpdates)
    }

    func testCorruptionIfNetworkErrorWhileDeleting() async {
        mockUsernameApiClient.deleteCurrentUsernameMocks = [{ throw OWSHTTPError.mockNetworkFailure }]

        _ = setUsername(username: "boba_fett.42")

        let value = await localUsernameManager.deleteUsername()

        XCTAssertEqual(value.isNetworkError, true)
        XCTAssertEqual(usernameState(), .usernameAndLinkCorrupted)
        XCTAssertFalse(mockStorageServiceManager.didRecordPendingLocalAccountUpdates)
    }

    func testCorruptionIfErrorWhileDeleting() async {
        mockUsernameApiClient.deleteCurrentUsernameMocks = [{ throw OWSGenericError("") }]

        _ = setUsername(username: "boba_fett.42")

        let value = await localUsernameManager.deleteUsername()

        XCTAssertEqual(value.isOtherError, true)
        XCTAssertEqual(usernameState(), .usernameAndLinkCorrupted)
        XCTAssertFalse(mockStorageServiceManager.didRecordPendingLocalAccountUpdates)
    }

    func testDeletionClearsCorruption() async {
        mockUsernameApiClient.deleteCurrentUsernameMocks = [{}]

        mockDB.write { tx in
            localUsernameManager.setLocalUsernameCorrupted(tx: tx)
        }

        XCTAssertEqual(usernameState(), .usernameAndLinkCorrupted)

        let value = await localUsernameManager.deleteUsername()

        XCTAssertEqual(value.isSuccess, true)
        XCTAssertEqual(usernameState(), .unset)
        XCTAssertTrue(mockStorageServiceManager.didRecordPendingLocalAccountUpdates)
    }

    func testDeletionClearsLinkCorruption() async {
        mockUsernameApiClient.deleteCurrentUsernameMocks = [{}]

        mockDB.write { tx in
            localUsernameManager.setLocalUsernameWithCorruptedLink(
                username: "boba_fett.42",
                tx: tx,
            )
        }

        XCTAssertEqual(usernameState(), .linkCorrupted(username: "boba_fett.42"))

        let value = await localUsernameManager.deleteUsername()

        XCTAssertEqual(value.isSuccess, true)
        XCTAssertEqual(usernameState(), .unset)
        XCTAssertTrue(mockStorageServiceManager.didRecordPendingLocalAccountUpdates)
    }

    // MARK: Rotate link

    func testRotationHappyPath() async {
        let newHandle = UUID()

        mockUsernameLinkManager.entropyToGenerate = .success(.mockEntropy)
        mockUsernameApiClient.setUsernameLinkMocks = [{ _, _ in newHandle }]

        _ = setUsername(username: "boba_fett.42")

        let value = await localUsernameManager.rotateUsernameLink()

        let expectedNewLink = Usernames.UsernameLink(handle: newHandle, entropy: .mockEntropy)!

        XCTAssertEqual(value, .success(expectedNewLink))
        XCTAssertEqual(
            usernameState(),
            .available(username: "boba_fett.42", usernameLink: expectedNewLink),
        )
        XCTAssertTrue(mockStorageServiceManager.didRecordPendingLocalAccountUpdates)
    }

    func testRotationBailsEarlyIfNotReachable() async {
        mockReachabilityManager.isReachable = false

        let stateBeforeConfirm = setUsername(username: "boba_fett.42")

        let value = await localUsernameManager.rotateUsernameLink()

        XCTAssertEqual(value, .failure(.networkError))
        XCTAssertEqual(usernameState(), stateBeforeConfirm)
        XCTAssertFalse(mockStorageServiceManager.didRecordPendingLocalAccountUpdates)
    }

    func testNoCorruptionIfFailToGenerateNewLink() async {
        mockUsernameLinkManager.entropyToGenerate = .failure(OWSGenericError("Jabba's Sudden But Inevitable Betrayal"))

        let stateBeforeRotate = setUsername(username: "boba_fett.42")

        let value = await localUsernameManager.rotateUsernameLink()

        XCTAssertEqual(value, .failure(.otherError))
        XCTAssertEqual(usernameState(), stateBeforeRotate)
        XCTAssertFalse(mockStorageServiceManager.didRecordPendingLocalAccountUpdates)
    }

    func testCorruptionIfNetworkErrorWhileRotatingLink() async {
        mockUsernameLinkManager.entropyToGenerate = .success(.mockEntropy)
        mockUsernameApiClient.setUsernameLinkMocks = [{ _, _ in throw OWSHTTPError.mockNetworkFailure }]

        _ = setUsername(username: "boba_fett.42")

        let value = await localUsernameManager.rotateUsernameLink()

        XCTAssertEqual(value, .failure(.networkError))
        XCTAssertEqual(usernameState(), .linkCorrupted(username: "boba_fett.42"))
        XCTAssertFalse(mockStorageServiceManager.didRecordPendingLocalAccountUpdates)
    }

    func testCorruptionIfErrorWhileRotatingLink() async {
        mockUsernameLinkManager.entropyToGenerate = .success(.mockEntropy)
        mockUsernameApiClient.setUsernameLinkMocks = [{ _, _ in throw OWSGenericError("") }]

        _ = setUsername(username: "boba_fett.42")

        let value = await localUsernameManager.rotateUsernameLink()

        XCTAssertEqual(value, .failure(.otherError))
        XCTAssertEqual(usernameState(), .linkCorrupted(username: "boba_fett.42"))
        XCTAssertFalse(mockStorageServiceManager.didRecordPendingLocalAccountUpdates)
    }

    func testSuccessfulRotationClearsCorruption() async {
        let newHandle = UUID()

        mockUsernameLinkManager.entropyToGenerate = .success(.mockEntropy)
        mockUsernameApiClient.setUsernameLinkMocks = [{ _, _ in newHandle }]

        mockDB.write { tx in
            localUsernameManager.setLocalUsernameWithCorruptedLink(
                username: "boba_fett.42",
                tx: tx,
            )
        }

        XCTAssertEqual(usernameState(), .linkCorrupted(username: "boba_fett.42"))

        let value = await localUsernameManager.rotateUsernameLink()

        let expectedNewLink = Usernames.UsernameLink(handle: newHandle, entropy: .mockEntropy)!

        XCTAssertEqual(value, .success(expectedNewLink))
        XCTAssertEqual(
            usernameState(),
            .available(username: "boba_fett.42", usernameLink: expectedNewLink),
        )
        XCTAssertTrue(mockStorageServiceManager.didRecordPendingLocalAccountUpdates)
    }

    func testUpdateVisibleCaseHappyPath() async {
        let linkHandle = UUID()

        mockUsernameApiClient.setUsernameLinkMocks = [{ _, keepLinkHandle in
            XCTAssertTrue(keepLinkHandle)
            return linkHandle
        }]

        let currentLink = setUsername(username: "boba_fett.42", linkHandle: linkHandle).usernameLink!

        let value = await localUsernameManager.updateVisibleCaseOfExistingUsername(newUsername: "BoBa_fEtT.42")

        XCTAssertEqual(value.isSuccess, true)
        XCTAssertEqual(
            usernameState(),
            .available(username: "BoBa_fEtT.42", usernameLink: currentLink),
        )
        XCTAssertTrue(mockStorageServiceManager.didRecordPendingLocalAccountUpdates)
    }

    func testUpdateVisibleCaseBailsEarlyIfNotReachable() async {
        mockReachabilityManager.isReachable = false

        let stateBeforeConfirm = setUsername(username: "boba_fett.42")

        let value = await localUsernameManager.updateVisibleCaseOfExistingUsername(newUsername: "BoBa_fEtT.42")

        XCTAssertEqual(value.isNetworkError, true)
        XCTAssertEqual(usernameState(), stateBeforeConfirm)
        XCTAssertFalse(mockStorageServiceManager.didRecordPendingLocalAccountUpdates)
    }

    func testUpdateVisibleCaseSetsLocalEvenIfNetworkError() async {
        let linkHandle = UUID()

        mockUsernameApiClient.setUsernameLinkMocks = [{ _, keepLinkHandle in
            XCTAssertTrue(keepLinkHandle)
            throw OWSHTTPError.mockNetworkFailure
        }]

        _ = setUsername(username: "boba_fett.42", linkHandle: linkHandle).usernameLink!

        let value = await localUsernameManager.updateVisibleCaseOfExistingUsername(newUsername: "BoBa_fEtT.42")

        XCTAssertEqual(value.isNetworkError, true)
        XCTAssertEqual(
            usernameState(),
            .linkCorrupted(username: "BoBa_fEtT.42"),
        )
        XCTAssertTrue(mockStorageServiceManager.didRecordPendingLocalAccountUpdates)
    }

    func testUpdateVisibleCaseSetsLocalEvenIfError() async {
        let linkHandle = UUID()

        mockUsernameApiClient.setUsernameLinkMocks = [{ _, keepLinkHandle in
            XCTAssertTrue(keepLinkHandle)
            throw OWSGenericError("oopsie")
        }]

        _ = setUsername(username: "boba_fett.42", linkHandle: linkHandle).usernameLink!

        let value = await localUsernameManager.updateVisibleCaseOfExistingUsername(newUsername: "BoBa_fEtT.42")

        XCTAssertEqual(value.isOtherError, true)
        XCTAssertEqual(
            usernameState(),
            .linkCorrupted(username: "BoBa_fEtT.42"),
        )
        XCTAssertTrue(mockStorageServiceManager.didRecordPendingLocalAccountUpdates)
    }

    // MARK: Network retries

    func testUpdateVisibleCaseWorkSecondTimeAfterNetworkError() async {
        setLocalUsernameManager(maxNetworkRequestRetries: 1)

        let linkHandle = UUID()

        mockUsernameApiClient.setUsernameLinkMocks = [
            { _, keepLinkHandle in
                XCTAssertTrue(keepLinkHandle)
                throw OWSHTTPError.mockNetworkFailure
            },
            { _, keepLinkHandle in
                XCTAssertTrue(keepLinkHandle)
                return linkHandle
            },
        ]

        let currentLink = setUsername(username: "boba_fett.42", linkHandle: linkHandle).usernameLink!

        let value = await localUsernameManager.updateVisibleCaseOfExistingUsername(newUsername: "BoBa_fEtT.42")

        XCTAssertEqual(value.isSuccess, true)
        XCTAssertEqual(
            usernameState(),
            .available(username: "BoBa_fEtT.42", usernameLink: currentLink),
        )
        XCTAssertTrue(mockStorageServiceManager.didRecordPendingLocalAccountUpdates)
    }

    // MARK: Utilities

    private func setUsername(
        username: String,
        linkHandle: UUID? = nil,
    ) -> Usernames.LocalUsernameState {
        return mockDB.write { tx in
            localUsernameManager.setLocalUsername(
                username: username,
                usernameLink: .mock(handle: linkHandle ?? UUID()),
                tx: tx,
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

private extension Usernames.RemoteMutationResult<Void> {
    var isSuccess: Bool {
        switch self {
        case .success: return true
        case .failure: return false
        }
    }

    var isNetworkError: Bool {
        switch self {
        case .failure(.networkError): return true
        case .success, .failure(.otherError): return false
        }
    }

    var isOtherError: Bool {
        switch self {
        case .failure(.otherError): return true
        case .success, .failure(.networkError): return false
        }
    }
}

// MARK: - Mocks

private extension OWSHTTPError {
    static var mockNetworkFailure: OWSHTTPError {
        return .networkFailure(.genericFailure)
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
            entropy: .mockEntropy,
        )!
    }
}

private extension Data {
    static let mockEntropy = Data(repeating: 12, count: 32)
}

private class MockReachabilityManager: SSKReachabilityManager {
    var isReachable: Bool = true
    func isReachable(via reachabilityType: ReachabilityType) -> Bool { owsFail("Not implemented!") }
}

private class MockStorageServiceManager: StorageServiceManager {
    var didRecordPendingLocalAccountUpdates: Bool = false

    func recordPendingLocalAccountUpdates() {
        didRecordPendingLocalAccountUpdates = true
    }

    func setLocalIdentifiers(_ localIdentifiers: LocalIdentifiers) { owsFail("Not implemented!") }
    func registerForCron(_ cron: Cron) { owsFail("Not implemented.") }
    func currentManifestVersion(tx: DBReadTransaction) -> UInt64 { owsFail("Not implemented") }
    func currentManifestHasRecordIkm(tx: DBReadTransaction) -> Bool { owsFail("Not implemented") }
    func waitForPendingRestores() async throws { owsFail("Not implemented") }
    func resetLocalData(transaction: DBWriteTransaction) { owsFail("Not implemented!") }
    func recordPendingUpdates(updatedRecipientUniqueIds: [RecipientUniqueId]) { owsFail("Not implemented!") }
    func recordPendingUpdates(updatedAddresses: [SignalServiceAddress]) { owsFail("Not implemented!") }
    func recordPendingUpdates(updatedGroupV2MasterKeys: [GroupMasterKey]) { owsFail("Not implemented!") }
    func recordPendingUpdates(updatedStoryDistributionListIds: [Data]) { owsFail("Not implemented!") }
    func recordPendingUpdates(callLinkRootKeys: [CallLinkRootKey]) { owsFail("Not implemented!") }
    func backupPendingChanges(authedDevice: AuthedDevice) { owsFail("Not implemented!") }
    func restoreOrCreateManifestIfNecessary(authedDevice: AuthedDevice, masterKeySource: StorageService.MasterKeySource) -> Promise<Void> { owsFail("Not implemented!") }
    func rotateManifest(mode: ManifestRotationMode, authedDevice: AuthedDevice) async throws { owsFail("Not implemented!") }
}
