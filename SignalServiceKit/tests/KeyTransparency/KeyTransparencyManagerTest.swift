//
// Copyright 2026 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import LibSignalClient
import SignalRingRTC
import Testing

@testable import SignalServiceKit

struct KeyTransparencyManagerTest {
    private static let checkFailure = OWSGenericError("Mock check failure.")

    private let localIdentifiers = LocalIdentifiers.forUnitTests

    private let apiClient = MockKeyTransparencyApiClient()
    private let db = InMemoryDB()
    private let identityManager: MockIdentityManager
    /// A week, deliberately distinct from the 24h interval used to retry after
    /// a failure. The cadence tests below assume this value.
    private let keyTransparencyStore = KeyTransparencyStore(selfCheckCronInterval: .week)
    private let localUsernameManager = MockLocalUsernameManager()
    private let recipientDatabaseTable = RecipientDatabaseTable()
    private let tsAccountManager = MockTSAccountManager()
    private let udManager = OWSMockUDManager()

    private let clock = AtomicValue(Date(), lock: .init())

    init() {
        let recipientFetcher = RecipientFetcher(
            recipientDatabaseTable: recipientDatabaseTable,
            searchableNameIndexer: MockSearchableNameIndexer(),
        )
        let identityManager = MockIdentityManager(recipientIdFinder: RecipientIdFinder(
            recipientDatabaseTable: recipientDatabaseTable,
            recipientFetcher: recipientFetcher,
        ))
        identityManager.recipientIdentities = [:]
        identityManager.identityKeyPairs[.aci] = ECKeyPair.generateKeyPair()
        self.identityManager = identityManager

        localUsernameManager.startingUsernameState = .unset

        let localIdentifiers = self.localIdentifiers
        tsAccountManager.localIdentifiersMock = { localIdentifiers }

        udManager.udAccessKeyMock = { _ in
            return SMKUDAccessKey(profileKey: Aes256Key(data: Data(count: Int(Aes256Key.keyByteLength)))!)
        }
    }

    // MARK: - Helpers

    private func buildManager(isConservativeSelfCheck: Bool = true) -> KeyTransparencyManager {
        let clock = self.clock
        return KeyTransparencyManager(
            apiClient: apiClient,
            dateProvider: { clock.get() },
            db: db,
            identityManager: identityManager,
            isConservativeSelfCheck: isConservativeSelfCheck,
            keyTransparencyStore: keyTransparencyStore,
            localUsernameManager: localUsernameManager,
            messageProcessor: MockMessageProcessor(),
            recipientDatabaseTable: recipientDatabaseTable,
            storageServiceManager: MockStorageServiceManager(),
            tsAccountManager: tsAccountManager,
            udManager: udManager,
        )
    }

    private var now: Date {
        clock.get()
    }

    private func advanceClock(by interval: TimeInterval) {
        clock.update { $0 += interval }
    }

    private func enqueueFailingCheck() {
        apiClient.checkMocks.append { _, _ in throw Self.checkFailure }
    }

    private func enqueueSucceedingCheck() {
        apiClient.checkMocks.append { _, _ in }
    }

    private var selfCheckState: KeyTransparencyStore.SelfCheckState? {
        db.read { keyTransparencyStore.selfCheckState(tx: $0) }
    }

    private var shouldWarnSelfCheckFailed: Bool {
        db.read { keyTransparencyStore.shouldWarnSelfCheckFailed(tx: $0) }
    }

    private func isTimeForSelfCheck(at date: Date) -> Bool {
        db.read { keyTransparencyStore.getIsTimeForSelfCheckCronJob(now: date, tx: $0) }
    }

    private func setWarnedSelfCheckFailed() {
        db.write { keyTransparencyStore.setWarnedSelfCheckFailed(tx: $0) }
    }

    // MARK: - Self-check

    @Test
    func testSelfCheckChecksLocalAciAsSelf() async throws {
        let keyTransparencyManager = buildManager()

        let localIdentifiers = self.localIdentifiers
        apiClient.checkMocks.append { mode, aciInfo in
            #expect(mode == .self(isE164Discoverable: true))
            #expect(aciInfo.aci == localIdentifiers.aci)
        }

        try await keyTransparencyManager.performSelfCheckOnDemand()

        #expect(selfCheckState == .succeeded)
        #expect(apiClient.checkMocks.isEmpty)
    }

    // MARK: - Failure ladder

    @Test
    func testHealsAfterSingleFailure() async throws {
        let keyTransparencyManager = buildManager()

        enqueueFailingCheck()
        await #expect(throws: OWSGenericError.self) {
            try await keyTransparencyManager.performSelfCheckOnDemand()
        }
        #expect(selfCheckState == .failedOnce)
        #expect(!shouldWarnSelfCheckFailed)

        advanceClock(by: 26 * .hour)

        enqueueSucceedingCheck()
        try await keyTransparencyManager.performSelfCheckOnDemand()
        #expect(selfCheckState == .succeeded)
        #expect(!shouldWarnSelfCheckFailed)
        #expect(apiClient.checkMocks.isEmpty)
    }

    @Test
    func testSecondFailureWarnsThenHeals() async throws {
        let keyTransparencyManager = buildManager()

        enqueueFailingCheck()
        await #expect(throws: OWSGenericError.self) {
            try await keyTransparencyManager.performSelfCheckOnDemand()
        }
        #expect(selfCheckState == .failedOnce)
        #expect(!shouldWarnSelfCheckFailed)

        advanceClock(by: 26 * .hour)

        enqueueFailingCheck()
        await #expect(throws: OWSGenericError.self) {
            try await keyTransparencyManager.performSelfCheckOnDemand()
        }
        #expect(selfCheckState == .failedRepeatedly)
        #expect(shouldWarnSelfCheckFailed)

        setWarnedSelfCheckFailed()
        #expect(selfCheckState == .failedRepeatedlyAndWarned)
        #expect(!shouldWarnSelfCheckFailed)

        enqueueSucceedingCheck()
        try await keyTransparencyManager.performSelfCheckOnDemand()
        #expect(selfCheckState == .succeeded)
        #expect(!shouldWarnSelfCheckFailed)
        #expect(apiClient.checkMocks.isEmpty)
    }

    /// A conservative build re-arms the warning after we've warned, so we warn
    /// again about continued failures.
    @Test
    func testConservativeBuildWarnsRepeatedly() async {
        let keyTransparencyManager = buildManager(isConservativeSelfCheck: true)

        enqueueFailingCheck()
        await #expect(throws: OWSGenericError.self) {
            try await keyTransparencyManager.performSelfCheckOnDemand()
        }
        #expect(selfCheckState == .failedOnce)
        #expect(!shouldWarnSelfCheckFailed)

        enqueueFailingCheck()
        await #expect(throws: OWSGenericError.self) {
            try await keyTransparencyManager.performSelfCheckOnDemand()
        }
        #expect(selfCheckState == .failedRepeatedly)
        #expect(shouldWarnSelfCheckFailed)

        // Until we warn, continued failures hold at `.failedRepeatedly`.
        enqueueFailingCheck()
        await #expect(throws: OWSGenericError.self) {
            try await keyTransparencyManager.performSelfCheckOnDemand()
        }
        #expect(selfCheckState == .failedRepeatedly)
        #expect(shouldWarnSelfCheckFailed)

        setWarnedSelfCheckFailed()
        #expect(selfCheckState == .failedRepeatedlyAndWarned)
        #expect(!shouldWarnSelfCheckFailed)

        enqueueFailingCheck()
        await #expect(throws: OWSGenericError.self) {
            try await keyTransparencyManager.performSelfCheckOnDemand()
        }
        #expect(selfCheckState == .failedRepeatedly)
        #expect(shouldWarnSelfCheckFailed)
    }

    /// A non-conservative build warns once, then stays quiet about continued
    /// failures.
    @Test
    func testNonConservativeBuildWarnsOnce() async {
        let keyTransparencyManager = buildManager(isConservativeSelfCheck: false)

        enqueueFailingCheck()
        await #expect(throws: OWSGenericError.self) {
            try await keyTransparencyManager.performSelfCheckOnDemand()
        }
        #expect(selfCheckState == .failedOnce)
        #expect(!shouldWarnSelfCheckFailed)

        enqueueFailingCheck()
        await #expect(throws: OWSGenericError.self) {
            try await keyTransparencyManager.performSelfCheckOnDemand()
        }
        #expect(selfCheckState == .failedRepeatedly)
        #expect(shouldWarnSelfCheckFailed)

        // Until we warn, continued failures hold at `.failedRepeatedly`.
        enqueueFailingCheck()
        await #expect(throws: OWSGenericError.self) {
            try await keyTransparencyManager.performSelfCheckOnDemand()
        }
        #expect(selfCheckState == .failedRepeatedly)
        #expect(shouldWarnSelfCheckFailed)

        setWarnedSelfCheckFailed()
        #expect(selfCheckState == .failedRepeatedlyAndWarned)
        #expect(!shouldWarnSelfCheckFailed)

        enqueueFailingCheck()
        await #expect(throws: OWSGenericError.self) {
            try await keyTransparencyManager.performSelfCheckOnDemand()
        }
        #expect(selfCheckState == .failedRepeatedlyAndWarned)
        #expect(!shouldWarnSelfCheckFailed)
    }

    // MARK: - Cadence

    /// A first failure schedules the next self-check ~24h out, rather than at
    /// the Cron interval.
    ///
    /// Cadence dates carry jitter of `± interval / Cron.jitterFactor`, or ±72m
    /// for a 24h interval, so assert with margin.
    @Test
    func testFirstFailureRetriesAfterADay() async {
        let keyTransparencyManager = buildManager()

        let failedAt = now

        enqueueFailingCheck()
        await #expect(throws: OWSGenericError.self) {
            try await keyTransparencyManager.performSelfCheckOnDemand()
        }

        #expect(!isTimeForSelfCheck(at: failedAt + 22 * .hour))
        #expect(isTimeForSelfCheck(at: failedAt + 26 * .hour))
    }

    /// Jitter on the Cron interval is `.week / Cron.jitterFactor`, or ~8.4h, so
    /// assert with margin.
    @Test
    func testSuccessSchedulesAtCronInterval() async throws {
        let keyTransparencyManager = buildManager()

        let succeededAt = now

        enqueueSucceedingCheck()
        try await keyTransparencyManager.performSelfCheckOnDemand()

        #expect(!isTimeForSelfCheck(at: succeededAt + 5 * .day))
        #expect(isTimeForSelfCheck(at: succeededAt + 8 * .day))
    }

    /// Healing restores the Cron interval, rather than leaving us on the 24h
    /// post-failure cadence.
    @Test
    func testHealingRestoresCronInterval() async throws {
        let keyTransparencyManager = buildManager()

        enqueueFailingCheck()
        await #expect(throws: OWSGenericError.self) {
            try await keyTransparencyManager.performSelfCheckOnDemand()
        }

        advanceClock(by: 26 * .hour)
        let healedAt = now

        enqueueSucceedingCheck()
        try await keyTransparencyManager.performSelfCheckOnDemand()

        #expect(!isTimeForSelfCheck(at: healedAt + 26 * .hour))
        #expect(!isTimeForSelfCheck(at: healedAt + 5 * .day))
        #expect(isTimeForSelfCheck(at: healedAt + 8 * .day))
    }

    // MARK: - Checking others

    @Test
    func testCannotCheckOtherWithFailedSelfCheck() async throws {
        let keyTransparencyManager = buildManager()

        let otherAci = Aci.constantForTesting("00000000-0000-4000-8000-0000000000a1")
        let otherIdentityKey = IdentityKeyPair.generate()
        db.write { tx in
            let recipient = try! SignalRecipient.insertRecord(
                aci: otherAci,
                phoneNumber: E164("+16505550101")!,
                tx: tx,
            )
            identityManager.recipientIdentities[recipient.uniqueId] = OWSRecipientIdentity(
                uniqueId: recipient.uniqueId,
                identityKey: otherIdentityKey.identityKey.publicKey.keyBytes,
                isFirstKnownKey: true,
                createdAt: now,
                verificationState: .default,
            )
        }

        enqueueFailingCheck()
        await #expect(throws: OWSGenericError.self) {
            try await keyTransparencyManager.performSelfCheckOnDemand()
        }
        #expect(selfCheckState == .failedOnce)

        let checkParams = try #require(db.read { tx in
            keyTransparencyManager.prepareCheck(
                aci: otherAci,
                localIdentifiers: localIdentifiers,
                tx: tx,
            )
        })

        enqueueSucceedingCheck()
        await #expect(throws: OWSGenericError.self) {
            try await keyTransparencyManager.performCheck(params: checkParams)
        }
        // We should have bailed before making a request for the other user.
        #expect(apiClient.checkMocks.count == 1)
    }
}

// MARK: -

private final class MockKeyTransparencyApiClient: KeyTransparencyApiClient {
    var checkMocks = [(KeyTransparency.CheckMode, KeyTransparency.AciInfo) async throws -> Void]()

    func check(
        for mode: KeyTransparency.CheckMode,
        aciInfo: KeyTransparency.AciInfo,
        e164Info: KeyTransparency.E164Info?,
        usernameHash: Data?,
    ) async throws {
        try await checkMocks.removeFirst()(mode, aciInfo)
    }
}

// MARK: -

private struct MockMessageProcessor: KeyTransparencyManager.Shims.MessageProcessor {
    func waitForFetchingAndProcessing() async throws(CancellationError) {}
}

// MARK: -

private class MockStorageServiceManager: StorageServiceManager {
    func recordPendingLocalAccountUpdates() {}
    func restoreOrCreateManifestIfNecessary(
        authedDevice: AuthedDevice,
        masterKeySource: StorageService.MasterKeySource,
    ) -> Promise<Void> {
        return .value(())
    }

    func waitForPendingRestores() async throws {}

    func setLocalIdentifiers(_ localIdentifiers: LocalIdentifiers) { owsFail("Not implemented!") }
    func registerForCron(_ cron: Cron) { owsFail("Not implemented!") }
    func currentManifestVersion(tx: DBReadTransaction) -> UInt64 { owsFail("Not implemented!") }
    func currentManifestHasRecordIkm(tx: DBReadTransaction) -> Bool { owsFail("Not implemented!") }
    func recordPendingUpdates(updatedRecipientUniqueIds: [RecipientUniqueId]) { owsFail("Not implemented!") }
    func recordPendingUpdates(updatedAddresses: [SignalServiceAddress]) { owsFail("Not implemented!") }
    func recordPendingUpdates(updatedGroupV2MasterKeys: [GroupMasterKey]) { owsFail("Not implemented!") }
    func recordPendingUpdates(updatedStoryDistributionListIds: [Data]) { owsFail("Not implemented!") }
    func recordPendingUpdates(callLinkRootKeys: [CallLinkRootKey]) { owsFail("Not implemented!") }
    func backupPendingChanges(authedDevice: AuthedDevice) { owsFail("Not implemented!") }
    func resetLocalData(transaction: DBWriteTransaction) { owsFail("Not implemented!") }
    func rotateManifest(mode: ManifestRotationMode, authedDevice: AuthedDevice) async throws { owsFail("Not implemented!") }
    func waitForSteadyState() async throws(CancellationError) { owsFail("Not implemented!") }
}
