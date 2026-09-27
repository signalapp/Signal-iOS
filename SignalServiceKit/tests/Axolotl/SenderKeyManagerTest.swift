//
// Copyright 2026 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import LibSignalClient
import SignalRingRTC
import Testing

@testable import SignalServiceKit

struct SenderKeyManagerTest {
    let localIdentifiers = LocalIdentifiers.forUnitTests
    let localDeviceId = DeviceId.primary

    let db: InMemoryDB
    let identityStore: any LibSignalClient.IdentityKeyStore
    let recipientManager: SignalRecipientManagerImpl
    let recipientStore: RecipientDatabaseTable
    let sessionStore: any LibSignalClient.SessionStore
    let senderKeyManager: SenderKeyManager
    let senderKeySendingManager: SenderKeySendingManager
    let senderKeyReceivingManager: SenderKeyReceivingManager
    let threadUniqueId = UUID().uuidString

    let _now: TSMutex<Date>
    var now: Date { _now.withLock { $0 } }

    init() {
        self.db = InMemoryDB()
        self.identityStore = InMemorySignalProtocolStore()
        let sessionStore = SessionStore()
        self.recipientStore = RecipientDatabaseTable()
        let recipientFetcher = RecipientFetcher(
            recipientDatabaseTable: self.recipientStore,
            searchableNameIndexer: MockSearchableNameIndexer(),
        )
        let recipientIdFinder = RecipientIdFinder(
            recipientDatabaseTable: self.recipientStore,
            recipientFetcher: recipientFetcher,
        )
        self.sessionStore = SessionManagerForIdentity(
            identity: .aci,
            recipientIdFinder: recipientIdFinder,
            sessionStore: sessionStore,
        )
        self.senderKeyManager = SenderKeyManager(
            oldSenderKeyStore: OldSenderKeyStore(),
            recipientFetcher: recipientFetcher,
            recipientStore: self.recipientStore,
            senderKeyStore: SenderKeyStore(),
            sessionStore: sessionStore,
        )
        let now = TSMutex(initialState: Date())
        self.senderKeySendingManager = SenderKeySendingManager(
            senderKeyManager: self.senderKeyManager,
            dateProvider: { now.withLock({ $0 }) },
        )
        self.senderKeyReceivingManager = SenderKeyReceivingManager(
            senderKeyManager: self.senderKeyManager,
            shouldUpdateInsertedAtDate: false,
        )
        self.recipientManager = SignalRecipientManagerImpl(
            phoneNumberVisibilityFetcher: MockPhoneNumberVisibilityFetcher(),
            recipientDatabaseTable: self.recipientStore,
            storageServiceManager: MockStorageServiceManager(),
        )
        self._now = now
    }

    @Test(.enabled(if: BuildFlags.decodeOldSenderKeys))
    func testReceivingMigration() throws {
        let otherAci = Aci.randomForTesting()
        let otherAddress = ProtocolAddress(otherAci, deviceId: .primary)
        let distributionId = UUID()
        let oldStore = KeyValueStore(collection: "SenderKeyStore_KeyMetadata")
        let senderKey = KeyMetadata(
            record: try MockSenderKeyStore.randomReceivingKey(
                aci: otherAci,
                deviceId: otherAddress.deviceIdObj,
                distributionId: distributionId,
            ),
            senderAci: otherAci,
            senderDeviceId: otherAddress.deviceIdObj,
            localIdentifiers: self.localIdentifiers,
            localDeviceId: .valid(self.localDeviceId),
            distributionId: distributionId,
        )
        let oldKeyId = OldSenderKeyStore.buildKeyId(authorAci: otherAci, distributionId: distributionId)
        try db.write { tx in
            try oldStore.setCodable(senderKey, key: oldKeyId, transaction: tx)
        }
        try db.write { tx in
            let senderKeyRecord = try senderKeyReceivingManager.loadSenderKey(
                from: otherAddress,
                distributionId: distributionId,
                context: tx,
            )
            let senderKeyRecord2 = try #require(senderKeyRecord)
            try senderKeyReceivingManager.storeSenderKey(
                from: otherAddress,
                distributionId: distributionId,
                record: senderKeyRecord2,
                context: tx,
            )
        }
        db.read { tx in
            #expect(oldStore.allKeys(transaction: tx) == [])
            #expect(try! SignalRecipient.fetchCount(tx.database) >= 1)
            #expect(try! SignalServiceKit.SenderKeyRecord.fetchCount(tx.database) == 1)
        }
    }

    /// If the Sender Key has expired, no recipients are ready.
    @Test
    func testExpirationAfterDelay() throws {
        try db.write { tx in
            let recipients = [OtherRecipient(), OtherRecipient()]
            let registrationId1: UInt32 = 123
            let registrationId2: UInt32 = 124
            _now.withLock {
                $0 = Date(timeIntervalSince1970: 1783530000)
            }
            _ = try recipients.map { try insertRecipient($0, tx: tx) }
            let senderKeyId = try buildSenderKeyDistributionMessage(tx: tx)
            let sentSenderKey1 = try sendSenderKeys(for: recipients[0], deviceAndRegistrationIds: [(.primary, registrationId1)], tx: tx)
            let sentSenderKey2 = try sendSenderKeys(for: recipients[1], deviceAndRegistrationIds: [(.primary, registrationId2)], tx: tx)
            senderKeySendingManager.recordSentSenderKeys([sentSenderKey1, sentSenderKey2], forSenderKeyId: senderKeyId, tx: tx)
            let initialRecipients = readyRecipients(attemptRecipients: recipients, acceptableRecipients: recipients, tx: tx)
            #expect(initialRecipients == [
                recipients[0].aci: [SenderKeySentToDevice(deviceId: .primary, registrationId: registrationId1)],
                recipients[1].aci: [SenderKeySentToDevice(deviceId: .primary, registrationId: registrationId2)],
            ])
            _now.withLock {
                $0 = Date(timeIntervalSince1970: 1783530120)
            }
            let expiredRecipients = readyRecipients(attemptRecipients: recipients, acceptableRecipients: recipients, maxSenderKeyAge: .minute, tx: tx)
            #expect(expiredRecipients == [:])
        }
    }

    /// If there's a new device, the recipient isn't ready.
    @Test
    func testExpirationNewDevice() throws {
        try db.write { tx in
            let recipients = [OtherRecipient(), OtherRecipient()]
            let registrationId1: UInt32 = 123
            let registrationId2: UInt32 = 124
            _now.withLock {
                $0 = Date(timeIntervalSince1970: 1783530000)
            }
            var signalRecipients = try recipients.map { try insertRecipient($0, tx: tx) }
            let senderKeyId = try buildSenderKeyDistributionMessage(tx: tx)
            let sentSenderKey1 = try sendSenderKeys(for: recipients[0], deviceAndRegistrationIds: [(.primary, registrationId1)], tx: tx)
            let sentSenderKey2 = try sendSenderKeys(for: recipients[1], deviceAndRegistrationIds: [(.primary, registrationId2)], tx: tx)
            senderKeySendingManager.recordSentSenderKeys([sentSenderKey1, sentSenderKey2], forSenderKeyId: senderKeyId, tx: tx)
            let initialRecipients = readyRecipients(attemptRecipients: recipients, acceptableRecipients: recipients, tx: tx)
            #expect(initialRecipients == [
                recipients[0].aci: [SenderKeySentToDevice(deviceId: .primary, registrationId: registrationId1)],
                recipients[1].aci: [SenderKeySentToDevice(deviceId: .primary, registrationId: registrationId2)],
            ])
            recipientManager.setDeviceIds([.primary, DeviceId(validating: 2)!], for: &signalRecipients[0], shouldUpdateStorageService: false)
            recipientStore.updateRecipient(signalRecipients[0], transaction: tx)
            let expiredRecipients = readyRecipients(attemptRecipients: recipients, acceptableRecipients: recipients, tx: tx)
            #expect(expiredRecipients == [
                recipients[1].aci: [SenderKeySentToDevice(deviceId: .primary, registrationId: registrationId2)],
            ])
        }
    }

    /// If there's a new registration ID, the recipient isn't ready.
    @Test
    func testExpirationNewRegistrationId() throws {
        try db.write { tx in
            let recipients = [OtherRecipient(), OtherRecipient()]
            let registrationId1: UInt32 = 123
            let registrationId2: UInt32 = 124
            _now.withLock {
                $0 = Date(timeIntervalSince1970: 1783530000)
            }
            _ = try recipients.map { try insertRecipient($0, tx: tx) }
            let senderKeyId = try buildSenderKeyDistributionMessage(tx: tx)
            let sentSenderKey1 = try sendSenderKeys(for: recipients[0], deviceAndRegistrationIds: [(.primary, registrationId1)], tx: tx)
            let sentSenderKey2 = try sendSenderKeys(for: recipients[1], deviceAndRegistrationIds: [(.primary, registrationId2)], tx: tx)
            senderKeySendingManager.recordSentSenderKeys([sentSenderKey1, sentSenderKey2], forSenderKeyId: senderKeyId, tx: tx)
            let initialRecipients = readyRecipients(attemptRecipients: recipients, acceptableRecipients: recipients, tx: tx)
            #expect(initialRecipients == [
                recipients[0].aci: [SenderKeySentToDevice(deviceId: .primary, registrationId: registrationId1)],
                recipients[1].aci: [SenderKeySentToDevice(deviceId: .primary, registrationId: registrationId2)],
            ])
            _ = try sendSenderKeys(for: recipients[0], deviceAndRegistrationIds: [(.primary, 1234)], tx: tx)
            let expiredRecipients = readyRecipients(attemptRecipients: recipients, acceptableRecipients: recipients, tx: tx)
            #expect(expiredRecipients == [
                recipients[1].aci: [SenderKeySentToDevice(deviceId: .primary, registrationId: registrationId2)],
            ])
        }
    }

    /// If somebody is removed, we have to generate a new Sender Key.
    @Test
    func testExpirationRemovedRecipient() throws {
        try db.write { tx in
            let recipients = [OtherRecipient(), OtherRecipient()]
            let registrationId1: UInt32 = 123
            let registrationId2: UInt32 = 124
            _now.withLock {
                $0 = Date(timeIntervalSince1970: 1783530000)
            }
            _ = try recipients.map { try insertRecipient($0, tx: tx) }
            let senderKeyId = try buildSenderKeyDistributionMessage(tx: tx)
            let sentSenderKey1 = try sendSenderKeys(for: recipients[0], deviceAndRegistrationIds: [(.primary, registrationId1)], tx: tx)
            let sentSenderKey2 = try sendSenderKeys(for: recipients[1], deviceAndRegistrationIds: [(.primary, registrationId2)], tx: tx)
            senderKeySendingManager.recordSentSenderKeys([sentSenderKey1, sentSenderKey2], forSenderKeyId: senderKeyId, tx: tx)
            let initialRecipients = readyRecipients(attemptRecipients: recipients, acceptableRecipients: recipients, tx: tx)
            #expect(initialRecipients == [
                recipients[0].aci: [SenderKeySentToDevice(deviceId: .primary, registrationId: registrationId1)],
                recipients[1].aci: [SenderKeySentToDevice(deviceId: .primary, registrationId: registrationId2)],
            ])
            _ = try sendSenderKeys(for: recipients[0], deviceAndRegistrationIds: [(.primary, 1234)], tx: tx)
            let expiredRecipients = readyRecipients(attemptRecipients: Array(recipients.dropFirst()), acceptableRecipients: Array(recipients.dropFirst()), tx: tx)
            #expect(expiredRecipients == [:])
        }
    }

    struct OtherRecipient {
        var aci = Aci.randomForTesting()
        var identityKey = IdentityKeyPair.generate()
    }

    private func buildSenderKeyDistributionMessage(tx: DBWriteTransaction) throws -> SignalServiceKit.SenderKeyRecord.RowId {
        _ = try senderKeySendingManager.buildSenderKeyDistributionMessage(
            forThreadUniqueId: threadUniqueId,
            localAci: localIdentifiers.aci,
            localDeviceId: localDeviceId,
            tx: tx,
        )
        return try #require(senderKeySendingManager.fetchSenderKeyId(
            forThreadUniqueId: threadUniqueId,
            localAci: localIdentifiers.aci,
            localDeviceId: localDeviceId,
            tx: tx,
        ))
    }

    private func insertRecipient(_ recipient: OtherRecipient, deviceIds: [DeviceId] = [.primary], tx: DBWriteTransaction) throws -> SignalRecipient {
        return try SignalRecipient.insertRecord(aci: recipient.aci, deviceIds: deviceIds, tx: tx)
    }

    private func sendSenderKeys(for recipient: OtherRecipient, deviceAndRegistrationIds: [(DeviceId, UInt32)] = [(.primary, 123)], tx: DBWriteTransaction) throws -> SentSenderKey {
        var sentMessages = [SentDeviceMessage]()
        for (deviceId, registrationId) in deviceAndRegistrationIds {
            try MockSessionStore.processPreKeyBundle(
                localAddress: ProtocolAddress(localIdentifiers.aci, deviceId: localDeviceId),
                theirAddress: ProtocolAddress(recipient.aci, deviceId: deviceId),
                theirIdentityKey: recipient.identityKey,
                theirRegistrationId: registrationId,
                now: self.now,
                sessionStore: self.sessionStore,
                identityStore: self.identityStore,
                context: tx,
            )
            sentMessages.append(SentDeviceMessage(destinationDeviceId: deviceId, destinationRegistrationId: registrationId))
        }
        return SentSenderKey(recipient: recipient.aci, messages: sentMessages)
    }

    private func readyRecipients(
        attemptRecipients: [OtherRecipient],
        acceptableRecipients: [OtherRecipient],
        maxSenderKeyAge: TimeInterval = .infinity,
        tx: DBWriteTransaction,
    ) -> [ServiceId: [SenderKeySentToDevice]] {
        return senderKeySendingManager.readyRecipients(
            forThreadUniqueId: threadUniqueId,
            attemptServiceIds: Set(attemptRecipients.map(\.aci)),
            acceptableServiceIds: Set(acceptableRecipients.map(\.aci)),
            maxSenderKeyAge: maxSenderKeyAge,
            now: self.now,
            localAci: self.localIdentifiers.aci,
            localDeviceId: self.localDeviceId,
            tx: tx,
        )
    }
}

// MARK: -

private class MockStorageServiceManager: StorageServiceManager {
    func setLocalIdentifiers(_ localIdentifiers: LocalIdentifiers) {}
    func registerForCron(_ cron: Cron) {}
    func currentManifestVersion(tx: DBReadTransaction) -> UInt64 { 0 }
    func currentManifestHasRecordIkm(tx: DBReadTransaction) -> Bool { false }
    func recordPendingUpdates(updatedRecipientUniqueIds: [RecipientUniqueId]) {}
    func recordPendingUpdates(updatedAddresses: [SignalServiceAddress]) {}
    func recordPendingUpdates(updatedGroupV2MasterKeys: [GroupMasterKey]) {}
    func recordPendingInsertions(forGroupMasterKeys groupMasterKeys: [GroupMasterKey]) {}
    func recordPendingUpdates(updatedStoryDistributionListIds: [Data]) {}
    func recordPendingUpdates(callLinkRootKeys: [CallLinkRootKey]) {}
    func recordPendingLocalAccountUpdates() {}
    func backupPendingChanges(authedAccount: AuthedAccount) {}
    func resetLocalData(transaction: DBWriteTransaction) {}
    func restoreOrCreateManifestIfNecessary(authedAccount: AuthedAccount, masterKeySource: StorageService.MasterKeySource) -> Promise<Void> { Promise<Void>(error: OWSGenericError("Not implemented.")) }
    func rotateManifest(mode: ManifestRotationMode, authedAccount: AuthedAccount) async throws { throw OWSGenericError("Not implemented.") }
    func waitForPendingRestores() async throws { throw OWSGenericError("Not implemented.") }
    func waitForSteadyState() async throws(CancellationError) { fatalError("Not implemented.") }
}
