//
// Copyright 2022 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import XCTest

@testable import SignalServiceKit

class BlockingManagerStateTests: SSKBaseTestSwift {
    var dut = BlockingManager.State._testing_createEmpty()

    override func setUp() {
        super.setUp()
        databaseStorage.read { dut.reloadIfNecessary($0) }
        assertInitalState(dut)
    }

    // MARK: Mutations

    func testAddBlockedItems() {
        // Setup
        let originalChangeToken = dut.changeToken
        let blockedGroup = generateRandomGroupModel()
        let blockedAci = CommonGenerator.address(hasAci: true, hasPhoneNumber: false)
        let blockedPhoneNumber = CommonGenerator.address(hasAci: false, hasPhoneNumber: true)
        let blockedBoth = CommonGenerator.address(hasAci: true, hasPhoneNumber: true)

        // Test
        // We add everthing twice, only the first pass should return true (i.e. didChange)
        XCTAssertTrue(dut.addBlockedGroup(blockedGroup))
        XCTAssertTrue(dut.addBlockedAddress(blockedAci))
        XCTAssertTrue(dut.addBlockedAddress(blockedPhoneNumber))
        XCTAssertTrue(dut.addBlockedAddress(blockedBoth))

        XCTAssertFalse(dut.addBlockedGroup(blockedGroup))
        XCTAssertFalse(dut.addBlockedAddress(blockedAci))
        XCTAssertFalse(dut.addBlockedAddress(blockedPhoneNumber))
        XCTAssertFalse(dut.addBlockedAddress(blockedBoth))

        // Verify — All added addresses are contained in each set
        XCTAssertEqual(dut.blockedGroupMap[blockedGroup.groupId], blockedGroup)
        XCTAssertTrue(dut.blockedAcis.contains(blockedAci.aci!))
        XCTAssertTrue(dut.blockedAcis.contains(blockedBoth.aci!))
        XCTAssertTrue(dut.blockedPhoneNumbers.contains(blockedPhoneNumber.phoneNumber!))
        XCTAssertTrue(dut.blockedPhoneNumbers.contains(blockedBoth.phoneNumber!))
        XCTAssertTrue(dut.isDirty, "Mutations should mark the state as dirty")
        XCTAssertTrue(dut.changeToken == originalChangeToken, "Change tokens shouldn't update until we persist")
    }

    func testRemoveBlockedItems() {
        // Setup
        let originalChangeToken = dut.changeToken

        let victimAddress = CommonGenerator.address()
        let victimGroup = generateRandomGroupModel()
        dut.addBlockedAddress(victimAddress)
        dut.addBlockedGroup(victimGroup)

        for _ in 0..<100 {
            dut.addBlockedGroup(generateRandomGroupModel())
            dut.addBlockedAddress(CommonGenerator.address(hasAci: true, hasPhoneNumber: false))
            dut.addBlockedAddress(CommonGenerator.address(hasAci: false, hasPhoneNumber: true))
            dut.addBlockedAddress(CommonGenerator.address(hasAci: true, hasPhoneNumber: true))
        }

        let initialBlockedGroupCount = dut.blockedGroupMap.count
        let initialPhoneNumberBlockCount = dut.blockedPhoneNumbers.count
        let initialAciBlockCount = dut.blockedAcis.count

        // Test
        // Remove both a known entry and a known non-entry
        XCTAssertNotNil(dut.removeBlockedGroup(victimGroup.groupId))
        XCTAssertTrue(dut.removeBlockedAddress(victimAddress))
        XCTAssertNil(dut.removeBlockedGroup(TSGroupModel.generateRandomV1GroupId()))
        XCTAssertFalse(dut.removeBlockedAddress(CommonGenerator.address()))

        // Verify — One and only one item in each set should have been removed
        XCTAssertEqual(dut.blockedGroupMap.count + 1, initialBlockedGroupCount)
        XCTAssertEqual(dut.blockedAcis.count + 1, initialAciBlockCount)
        XCTAssertEqual(dut.blockedPhoneNumbers.count + 1, initialPhoneNumberBlockCount)
        XCTAssertTrue(dut.isDirty, "Mutations should mark the state as dirty")
        XCTAssertTrue(dut.changeToken == originalChangeToken, "Change tokens shouldn't update until we persist")
    }

    func testIncomingSyncReplaces() {
        // Setup
        var replacementAddresses = generateAddresses(count: 50)
        var replacementGroups = generateGroupMap(count: 50)

        func replaceWithCurrentValues() {
            dut.replace(
                blockedPhoneNumbers: Set(replacementAddresses.compactMap({ $0.phoneNumber })),
                blockedAcis: Set(replacementAddresses.compactMap({ $0.aci })),
                blockedGroups: replacementGroups
            )
        }

        // Test
        dut.replace(blockedPhoneNumbers: Set(), blockedAcis: Set(), blockedGroups: Dictionary())
        let replaceEmptyWithEmpty = dut.isDirty
        dut._testingOnly_resetDirtyBit()

        replaceWithCurrentValues()
        let replaceEmptyWithFull = dut.isDirty
        dut._testingOnly_resetDirtyBit()

        replaceWithCurrentValues()
        let replaceFullWithFull = dut.isDirty
        dut._testingOnly_resetDirtyBit()

        replacementAddresses.insert(CommonGenerator.address())
        replaceWithCurrentValues()
        let replaceFullWithAnExtraAddress = dut.isDirty
        dut._testingOnly_resetDirtyBit()

        let newGroup = generateRandomGroupModel()
        replacementGroups[newGroup.groupId] = newGroup
        replaceWithCurrentValues()
        let replaceFullWithAnExtraGroup = dut.isDirty
        dut._testingOnly_resetDirtyBit()

        replacementAddresses.insert(CommonGenerator.address())
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
        let victimAddress = CommonGenerator.address()
        let victimGroup = generateRandomGroupModel()
        [
            // Insert and remove a bunch of random addresses. Inserts should always mutate. Removes should never mutate.
            (CommonGenerator.address(), false, false),
            (CommonGenerator.address(), true, true),
            (CommonGenerator.address(), true, true),
            (CommonGenerator.address(), false, false),
            (generateRandomGroupModel(), false, false),
            (generateRandomGroupModel(), true, true),
            (generateRandomGroupModel(), true, true),
            (CommonGenerator.address(), false, false),

            // Insert and remove the same address/group. Only the first insert or remove should mutate.
            (victimAddress, false, false),
            (victimAddress, true, true),
            (victimAddress, true, false),
            (victimAddress, true, false),
            (victimAddress, false, true),
            (victimAddress, false, false),

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
                case (true, let changedObject as SignalServiceAddress):
                    return dut.addBlockedAddress(changedObject)
                case (false, let changedObject as SignalServiceAddress):
                    return dut.removeBlockedAddress(changedObject)
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
        databaseStorage.read {
            dut.reloadIfNecessary($0)
            XCTAssertFalse(dut.needsSync(transaction: $0), "Fresh installs shouldn't need to implicitly sync")
        }
    }

    func testMigrationFromOldKeys() {
        // Setup — Simulate migration to the new format by throwing a bunch of fake data into the KVS container
        let oldAddresses = generateAddresses(count: 30)
        let oldPhoneNumberStrings = oldAddresses.compactMap { $0.phoneNumber }
        let oldAcis = oldAddresses.compactMap { $0.aci }
        let oldGroupMap = generateGroupMap(count: 30)

        typealias Key = BlockingManager.State.PersistenceKey
        let storage = BlockingManager.State.keyValueStore
        databaseStorage.write {
            storage.setObject(oldPhoneNumberStrings, key: Key.blockedPhoneNumbersKey.rawValue, transaction: $0)
            storage.setObject(oldPhoneNumberStrings, key: Key.Legacy.syncedBlockedPhoneNumbersKey.rawValue, transaction: $0)
            storage.setObject(oldAcis.map { $0.serviceIdUppercaseString }, key: Key.blockedAciStringsKey.rawValue, transaction: $0)
            storage.setObject(oldAcis.map { $0.serviceIdUppercaseString }, key: Key.Legacy.syncedBlockedUUIDsKey.rawValue, transaction: $0)
            storage.setObject(oldGroupMap, key: Key.blockedGroupMapKey.rawValue, transaction: $0)
            storage.setObject(Array(oldGroupMap.keys), key: Key.Legacy.syncedBlockedGroupIdsKey.rawValue, transaction: $0)
        }

        databaseStorage.read {
            // Test
            // We first reset our test object to ensure that it doesn't reuse any cached state.
            // A reload would only occur if the change token was updated, which we're not testing here.
            dut = BlockingManager.State._testing_createEmpty()
            dut.reloadIfNecessary($0)

            // Verify
            XCTAssertEqual(Set(oldPhoneNumberStrings), dut.blockedPhoneNumbers)
            XCTAssertEqual(Set(oldAcis), dut.blockedAcis)
            XCTAssertEqual(oldGroupMap, dut.blockedGroupMap)
            XCTAssertTrue(dut.needsSync(transaction: $0), "Block state requires a sync on first migration")
        }
    }

    func testPersistAndLoad() {
        // Setup
        let testAddress = CommonGenerator.address()
        let testGroup = generateRandomGroupModel()
        let initialChangeToken: UInt64 = databaseStorage.read {
            dut.reloadIfNecessary($0)
            return dut.changeToken
        }

        // Test — Add blocked items, persist, reset our local state to force a reload
        let changeTokenAfterUpdate: UInt64 = databaseStorage.write {
            dut.addBlockedAddress(testAddress)
            dut.addBlockedGroup(testGroup)

            // Double persist, only the first should be necessary. Dirty bit should be unset.
            XCTAssertTrue(dut.isDirty)
            XCTAssertTrue(dut.persistIfNecessary($0))
            XCTAssertFalse(dut.persistIfNecessary($0))
            XCTAssertFalse(dut.isDirty)

            return dut.changeToken
        }
        dut = BlockingManager.State._testing_createEmpty()

        // Verify
        databaseStorage.read {
            dut.reloadIfNecessary($0)

            XCTAssertEqual(dut.blockedPhoneNumbers, Set([testAddress.phoneNumber!]))
            XCTAssertEqual(dut.blockedAcis, Set([testAddress.aci!]))
            XCTAssertEqual(dut.blockedGroupMap[testGroup.groupId], testGroup)

            XCTAssertEqual(dut.changeToken, changeTokenAfterUpdate)
            XCTAssertNotEqual(dut.changeToken, initialChangeToken)
            XCTAssertTrue(dut.needsSync(transaction: $0))
        }
    }

    func testSimulatedSyncMessage() {
        databaseStorage.write {
            // Setup
            dut.reloadIfNecessary($0)
            XCTAssertFalse(dut.needsSync(transaction: $0))

            dut.addBlockedAddress(CommonGenerator.address())
            XCTAssertTrue(dut.persistIfNecessary($0))

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
        databaseStorage.read {
            dut.reloadIfNecessary($0)
            remoteState.reloadIfNecessary($0)
        }
        let blockedAddresses = generateAddresses(count: 3)
        let blockedGroups = generateGroupMap(count: 3)
        let removedBlock = blockedAddresses.randomElement()!

        // Test #1 — Add some items to one state. Ensure it gets reflected in the other state
        databaseStorage.write { writeTx in
            dut.reloadIfNecessary(writeTx)
            blockedAddresses.forEach { dut.addBlockedAddress($0) }
            blockedGroups.forEach { dut.addBlockedGroup($0.value) }
            XCTAssertTrue(dut.persistIfNecessary(writeTx))
        }
        databaseStorage.read { readTx in
            let oldChangeToken = remoteState.changeToken
            remoteState.reloadIfNecessary(readTx)

            // Verify #1
            XCTAssertNotEqual(oldChangeToken, remoteState.changeToken)
            XCTAssertEqual(remoteState.blockedPhoneNumbers, Set(blockedAddresses.compactMap { $0.phoneNumber }))
            XCTAssertEqual(remoteState.blockedAcis, Set(blockedAddresses.compactMap { $0.aci }))
            XCTAssertEqual(remoteState.blockedGroupMap, blockedGroups)
        }

        // Test #2 — In the opposite direction, remove an item and ensure it gets reflected on the other side
        databaseStorage.write { writeTx in
            remoteState.reloadIfNecessary(writeTx)
            remoteState.removeBlockedAddress(removedBlock)
            XCTAssertTrue(remoteState.persistIfNecessary(writeTx))
        }
        databaseStorage.read { readTx in
            let oldChangeToken = dut.changeToken
            dut.reloadIfNecessary(readTx)

            // Verify #2
            XCTAssertNotEqual(oldChangeToken, dut.changeToken)
            removedBlock.phoneNumber.map { XCTAssertFalse(dut.blockedPhoneNumbers.contains($0)) }
            removedBlock.aci.map { XCTAssertFalse(dut.blockedAcis.contains($0)) }
            XCTAssertEqual(dut.blockedGroupMap, blockedGroups)
        }
    }

    // MARK: Helpers

    func assertInitalState(_ state: BlockingManager.State) {
        XCTAssertEqual(dut.isDirty, false)
        XCTAssertEqual(dut.blockedPhoneNumbers.count, 0)
        XCTAssertEqual(dut.blockedAcis.count, 0)
        XCTAssertEqual(dut.blockedGroupMap.count, 0)
    }

    func generateAddresses(count: UInt) -> Set<SignalServiceAddress> {
        Set((0..<count).map { _ in
            let hasPhoneNumber = Int.random(in: 0...2) == 0
            let hasAci = !hasPhoneNumber || Bool.random()
            return CommonGenerator.address(hasAci: hasAci, hasPhoneNumber: hasPhoneNumber)
        })
    }

    func generateGroupMap(count: UInt) -> [Data: TSGroupModel] {
        Dictionary(uniqueKeysWithValues: (0..<count).map { _ in
            let fakeGroup = generateRandomGroupModel()
            return (fakeGroup.groupId, fakeGroup)
        })
    }

    func generateRandomGroupModel() -> TSGroupModel {
        GroupManager.fakeGroupModel(groupId: TSGroupModel.generateRandomV1GroupId())!
    }
}
