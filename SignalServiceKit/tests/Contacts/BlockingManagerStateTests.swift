//
// Copyright 2022 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import LibSignalClient
import XCTest

@testable import SignalServiceKit

class BlockingManagerStateTests: SSKBaseTest {
    var dut = BlockingManager.State._testing_createEmpty()

    override func setUp() {
        super.setUp()
        SSKEnvironment.shared.databaseStorageRef.read { dut.reloadIfNecessary(blockedRecipientStore: BlockedRecipientStoreImpl(), tx: $0) }
        assertInitalState(dut)
    }

    // MARK: Mutations

    func testAddBlockedItems() {
        // Setup
        let originalChangeToken = dut.changeToken
        let blockedGroup = generateRandomGroupModel()
        let blockedRecipientId = generateRecipientId()

        // Test
        // We add everthing twice, only the first pass should return true (i.e. didChange)
        XCTAssertTrue(dut.addBlockedGroup(blockedGroup))
        XCTAssertTrue(dut.addBlockedRecipientId(blockedRecipientId))

        XCTAssertFalse(dut.addBlockedGroup(blockedGroup))
        XCTAssertFalse(dut.addBlockedRecipientId(blockedRecipientId))

        // Verify — All added addresses are contained in each set
        XCTAssertEqual(dut.blockedGroupMap[blockedGroup.groupId], blockedGroup)
        XCTAssertTrue(dut.blockedRecipientIds.contains(blockedRecipientId))
        XCTAssertTrue(dut.isDirty, "Mutations should mark the state as dirty")
        XCTAssertTrue(dut.changeToken == originalChangeToken, "Change tokens shouldn't update until we persist")
    }

    func testRemoveBlockedItems() {
        // Setup
        let originalChangeToken = dut.changeToken

        let victimRecipientId = generateRecipientId()
        let victimGroup = generateRandomGroupModel()
        dut.addBlockedRecipientId(victimRecipientId)
        dut.addBlockedGroup(victimGroup)

        for _ in 0..<3 {
            dut.addBlockedGroup(generateRandomGroupModel())
            dut.addBlockedRecipientId(generateRecipientId())
        }

        let initialBlockedGroupCount = dut.blockedGroupMap.count
        let initialBlockedRecipientCount = dut.blockedRecipientIds.count

        // Test
        // Remove both a known entry and a (likely) non-entry
        XCTAssertNotNil(dut.removeBlockedGroup(victimGroup.groupId))
        XCTAssertTrue(dut.removeBlockedRecipientId(victimRecipientId))
        XCTAssertNil(dut.removeBlockedGroup(TSGroupModel.generateRandomGroupId(.V2)))
        XCTAssertFalse(dut.removeBlockedRecipientId(generateRecipientId()))

        // Verify — One and only one item in each set should have been removed
        XCTAssertEqual(dut.blockedGroupMap.count + 1, initialBlockedGroupCount)
        XCTAssertEqual(dut.blockedRecipientIds.count + 1, initialBlockedRecipientCount)
        XCTAssertTrue(dut.isDirty, "Mutations should mark the state as dirty")
        XCTAssertTrue(dut.changeToken == originalChangeToken, "Change tokens shouldn't update until we persist")
    }

    func testIncomingSyncReplaces() {
        // Setup
        var replacementRecipientIds = (0..<2).map { _ in generateRecipientId() }
        var replacementGroups = generateGroupMap(count: 2)

        func replaceWithCurrentValues() {
            dut.replace(
                blockedRecipientIds: Set(replacementRecipientIds),
                blockedGroups: replacementGroups
            )
        }

        // Test
        dut.replace(blockedRecipientIds: Set(), blockedGroups: Dictionary())
        let replaceEmptyWithEmpty = dut.isDirty
        dut._testingOnly_resetDirtyBit()

        replaceWithCurrentValues()
        let replaceEmptyWithFull = dut.isDirty
        dut._testingOnly_resetDirtyBit()

        replaceWithCurrentValues()
        let replaceFullWithFull = dut.isDirty
        dut._testingOnly_resetDirtyBit()

        replacementRecipientIds.append(generateRecipientId())
        replaceWithCurrentValues()
        let replaceFullWithAnExtraAddress = dut.isDirty
        dut._testingOnly_resetDirtyBit()

        let newGroup = generateRandomGroupModel()
        replacementGroups[newGroup.groupId] = newGroup
        replaceWithCurrentValues()
        let replaceFullWithAnExtraGroup = dut.isDirty
        dut._testingOnly_resetDirtyBit()

        replacementRecipientIds.append(generateRecipientId())
        replaceWithCurrentValues()
        replaceWithCurrentValues()
        let replaceFullWithTheSameAddressesTwice = dut.isDirty
        dut._testingOnly_resetDirtyBit()

        // Verify
        XCTAssertFalse(replaceEmptyWithEmpty)
        XCTAssertTrue(replaceEmptyWithFull)
        XCTAssertFalse(replaceFullWithFull)
        XCTAssertTrue(replaceFullWithAnExtraAddress)
        XCTAssertTrue(replaceFullWithAnExtraGroup)
        XCTAssertTrue(replaceFullWithTheSameAddressesTwice)
    }

    func testDirtyBitUpdates() {
        // Setup
        // We apply a sequence of mutations, one after the other, and verify it updates the dirty bit
        // as expected
        let victimRecipientId = generateRecipientId()
        let victimGroup = generateRandomGroupModel()
        [
            // Insert and remove a bunch of random addresses. Inserts should always mutate. Removes should never mutate.
            (generateRecipientId(), false, false),
            (generateRecipientId(), true, true),
            (generateRecipientId(), true, true),
            (generateRecipientId(), false, false),
            (generateRandomGroupModel(), false, false),
            (generateRandomGroupModel(), true, true),
            (generateRandomGroupModel(), true, true),
            (generateRecipientId(), false, false),

            // Insert and remove the same address/group. Only the first insert or remove should mutate.
            (victimRecipientId, false, false),
            (victimRecipientId, true, true),
            (victimRecipientId, true, false),
            (victimRecipientId, true, false),
            (victimRecipientId, false, true),
            (victimRecipientId, false, false),

            (victimGroup, false, false),
            (victimGroup, true, true),
            (victimGroup, true, false),
            (victimGroup, true, false),
            (victimGroup, false, true),
            (victimGroup, false, false)

        ].forEach { (changedObject: Any, isInsertion: Bool, expectDirtyBit: Bool) in
            // Force reset the dirty bit to test the effect of this single insert/remove
            dut._testingOnly_resetDirtyBit()

            // Test
            let didChange: Bool = {
                switch (isInsertion, changedObject) {
                case (true, let changedObject as SignalRecipient.RowId):
                    return dut.addBlockedRecipientId(changedObject)
                case (false, let changedObject as SignalRecipient.RowId):
                    return dut.removeBlockedRecipientId(changedObject)
                case (true, let changedObject as TSGroupModel):
                    return dut.addBlockedGroup(changedObject)
                case (false, let changedObject as TSGroupModel):
                    return dut.removeBlockedGroup(changedObject.groupId) != nil
                default:
                    XCTFail("This case should be impossible")
                    return false
                }
            }()

            // Verify
            XCTAssertEqual(dut.isDirty, expectDirtyBit)
            XCTAssertEqual(didChange, expectDirtyBit)
        }
    }

    // MARK: Persistence and Migrations

    func testFreshInstall() {
        SSKEnvironment.shared.databaseStorageRef.read {
            dut.reloadIfNecessary(blockedRecipientStore: BlockedRecipientStoreImpl(), tx: $0)
            XCTAssertFalse(dut.needsSync(transaction: $0), "Fresh installs shouldn't need to implicitly sync")
        }
    }

    func testMigrationFromOldKeys() {
        typealias Key = BlockingManager.State.PersistenceKey
        let storage = BlockingManager.State.keyValueStore
        SSKEnvironment.shared.databaseStorageRef.write {
            storage.setObject("", key: Key.Legacy.syncedBlockedPhoneNumbersKey.rawValue, transaction: $0.asV2Write)
        }

        SSKEnvironment.shared.databaseStorageRef.read {
            // Test
            // We first reset our test object to ensure that it doesn't reuse any cached state.
            // A reload would only occur if the change token was updated, which we're not testing here.
            dut = BlockingManager.State._testing_createEmpty()
            dut.reloadIfNecessary(blockedRecipientStore: BlockedRecipientStoreImpl(), tx: $0)

            // Verify
            XCTAssertTrue(dut.needsSync(transaction: $0), "Block state requires a sync on first migration")
        }
    }

    func testPersistAndLoad() {
        // Setup
        let testRecipientId = generateRecipientId()
        let testGroup = generateRandomGroupModel()
        let initialChangeToken: UInt64 = SSKEnvironment.shared.databaseStorageRef.read {
            dut.reloadIfNecessary(blockedRecipientStore: BlockedRecipientStoreImpl(), tx: $0)
            return dut.changeToken
        }

        // Test — Add blocked items, persist, reset our local state to force a reload
        let changeTokenAfterUpdate: UInt64 = SSKEnvironment.shared.databaseStorageRef.write {
            dut.addBlockedRecipientId(testRecipientId)
            dut.addBlockedGroup(testGroup)

            // Double persist, only the first should be necessary. Dirty bit should be unset.
            XCTAssertTrue(dut.isDirty)
            XCTAssertTrue(dut.persistIfNecessary(blockedRecipientStore: BlockedRecipientStoreImpl(), tx: $0))
            XCTAssertFalse(dut.persistIfNecessary(blockedRecipientStore: BlockedRecipientStoreImpl(), tx: $0))
            XCTAssertFalse(dut.isDirty)

            return dut.changeToken
        }
        dut = BlockingManager.State._testing_createEmpty()

        // Verify
        SSKEnvironment.shared.databaseStorageRef.read {
            dut.reloadIfNecessary(blockedRecipientStore: BlockedRecipientStoreImpl(), tx: $0)

            XCTAssertEqual(dut.blockedRecipientIds, Set([testRecipientId]))
            XCTAssertEqual(dut.blockedGroupMap[testGroup.groupId], testGroup)

            XCTAssertEqual(dut.changeToken, changeTokenAfterUpdate)
            XCTAssertNotEqual(dut.changeToken, initialChangeToken)
            XCTAssertTrue(dut.needsSync(transaction: $0))
        }
    }

    func testSimulatedSyncMessage() {
        let recipientId = generateRecipientId()
        SSKEnvironment.shared.databaseStorageRef.write {
            // Setup
            dut.reloadIfNecessary(blockedRecipientStore: BlockedRecipientStoreImpl(), tx: $0)
            XCTAssertFalse(dut.needsSync(transaction: $0))

            dut.addBlockedRecipientId(recipientId)
            XCTAssertTrue(dut.persistIfNecessary(blockedRecipientStore: BlockedRecipientStoreImpl(), tx: $0))

            // Test
            let needsSyncBefore = dut.needsSync(transaction: $0)
            BlockingManager.State.setLastSyncedChangeToken(dut.changeToken, transaction: $0)
            let needsSyncAfter = dut.needsSync(transaction: $0)

            // Verify
            XCTAssertTrue(needsSyncBefore)
            XCTAssertFalse(needsSyncAfter)
        }
    }

    func testSimulatedRemoteChange() {
        // Setup
        // We mutate two different instance of a state object. One lives as an ivar on the test class
        // the other lives within the scope of this test. Mutations to one should be reflected in the other
        dut = BlockingManager.State._testing_createEmpty()
        var remoteState = BlockingManager.State._testing_createEmpty()
        SSKEnvironment.shared.databaseStorageRef.read {
            dut.reloadIfNecessary(blockedRecipientStore: BlockedRecipientStoreImpl(), tx: $0)
            remoteState.reloadIfNecessary(blockedRecipientStore: BlockedRecipientStoreImpl(), tx: $0)
        }
        let blockedRecipientIds = (0..<3).map { _ in generateRecipientId() }
        let blockedGroups = generateGroupMap(count: 3)
        let removedBlock = blockedRecipientIds.randomElement()!

        // Test #1 — Add some items to one state. Ensure it gets reflected in the other state
        SSKEnvironment.shared.databaseStorageRef.write { writeTx in
            dut.reloadIfNecessary(blockedRecipientStore: BlockedRecipientStoreImpl(), tx: writeTx)
            blockedRecipientIds.forEach { dut.addBlockedRecipientId($0) }
            blockedGroups.forEach { dut.addBlockedGroup($0.value) }
            XCTAssertTrue(dut.persistIfNecessary(blockedRecipientStore: BlockedRecipientStoreImpl(), tx: writeTx))
        }
        SSKEnvironment.shared.databaseStorageRef.read { readTx in
            let oldChangeToken = remoteState.changeToken
            remoteState.reloadIfNecessary(blockedRecipientStore: BlockedRecipientStoreImpl(), tx: readTx)

            // Verify #1
            XCTAssertNotEqual(oldChangeToken, remoteState.changeToken)
            XCTAssertEqual(remoteState.blockedRecipientIds, Set(blockedRecipientIds))
            XCTAssertEqual(remoteState.blockedGroupMap, blockedGroups)
        }

        // Test #2 — In the opposite direction, remove an item and ensure it gets reflected on the other side
        SSKEnvironment.shared.databaseStorageRef.write { writeTx in
            remoteState.reloadIfNecessary(blockedRecipientStore: BlockedRecipientStoreImpl(), tx: writeTx)
            remoteState.removeBlockedRecipientId(removedBlock)
            XCTAssertTrue(remoteState.persistIfNecessary(blockedRecipientStore: BlockedRecipientStoreImpl(), tx: writeTx))
        }
        SSKEnvironment.shared.databaseStorageRef.read { readTx in
            let oldChangeToken = dut.changeToken
            dut.reloadIfNecessary(blockedRecipientStore: BlockedRecipientStoreImpl(), tx: readTx)

            // Verify #2
            XCTAssertNotEqual(oldChangeToken, dut.changeToken)
            XCTAssertFalse(dut.blockedRecipientIds.contains(removedBlock))
            XCTAssertEqual(dut.blockedGroupMap, blockedGroups)
        }
    }

    // MARK: Helpers

    func assertInitalState(_ state: BlockingManager.State) {
        XCTAssertEqual(dut.isDirty, false)
        XCTAssertEqual(dut.blockedRecipientIds, [])
        XCTAssertEqual(dut.blockedGroupMap, [:])
    }

    func generateRecipientId() -> SignalRecipient.RowId {
        return SSKEnvironment.shared.databaseStorageRef.write { tx in
            let recipientFetcher = DependenciesBridge.shared.recipientFetcher
            return recipientFetcher.fetchOrCreate(serviceId: Aci.randomForTesting(), tx: tx.asV2Write).id!
        }
    }

    func generateGroupMap(count: UInt) -> [Data: TSGroupModel] {
        Dictionary(uniqueKeysWithValues: (0..<count).map { _ in
            let fakeGroup = generateRandomGroupModel()
            return (fakeGroup.groupId, fakeGroup)
        })
    }

    func generateRandomGroupModel() -> TSGroupModel {
        GroupManager.fakeGroupModel(groupId: TSGroupModel.generateRandomGroupId(.V2))!
    }
}
