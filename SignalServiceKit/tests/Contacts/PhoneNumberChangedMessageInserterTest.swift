//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import XCTest

@testable import SignalServiceKit

class PhoneNumberChangedMessageInserterTest: XCTestCase {
    func testDidLearnAssociation() {
        let ssaCache = SignalServiceAddressCache()

        let myAci = ServiceId(uuidString: "00000000-0000-4000-8000-000000000000")!
        let myPhoneNumber1 = E164("+16505550111")!
        let myPhoneNumber2 = E164("+16505550122")!
        let myAddress1 = ssaCache.makeAddress(serviceId: myAci, phoneNumber: myPhoneNumber1)

        let aliceAci = ServiceId(uuidString: "00000000-0000-4000-8000-00000000000A")!
        let alicePhoneNumber1 = E164("+16505550133")!
        let alicePhoneNumber2 = E164("+16505550144")!
        let aliceAddress1 = ssaCache.makeAddress(serviceId: aliceAci, phoneNumber: alicePhoneNumber1)

        let bobAci = ServiceId(uuidString: "00000000-0000-4000-8000-00000000000B")!
        let bobPhoneNumber1: E164? = nil
        let bobPhoneNumber2 = E164("+16505550166")!
        let bobPhoneNumber3 = E164("+16505550177")!
        let bobAddress1 = ssaCache.makeAddress(serviceId: bobAci, phoneNumber: bobPhoneNumber1)

        let groupWithEveryone = TSGroupThread.forUnitTest(groupId: 1, groupMembers: [myAddress1, aliceAddress1, bobAddress1])
        let groupWithoutAlice = TSGroupThread.forUnitTest(groupId: 2, groupMembers: [myAddress1, bobAddress1])
        let groupArchived = TSGroupThread.forUnitTest(groupId: 3, groupMembers: [myAddress1, aliceAddress1, bobAddress1])

        let myThread = TSContactThread(contactAddress: myAddress1)
        myThread.shouldThreadBeVisible = true
        let aliceThread = TSContactThread(contactAddress: aliceAddress1)
        aliceThread.shouldThreadBeVisible = true

        let threadStore = MockThreadStore()
        threadStore.threads = [groupWithEveryone, groupWithoutAlice, groupArchived, myThread, aliceThread]

        let mockDB = MockDB()

        let groupMemberStore = MockGroupMemberStore()
        mockDB.write { tx in
            // Create group members for all of the full members.
            for thread in [groupWithEveryone, groupWithoutAlice, groupArchived] {
                for fullMemberAddress in thread.groupMembership.fullMembers {
                    groupMemberStore.insert(
                        fullGroupMember: TSGroupMember(
                            serviceId: fullMemberAddress.serviceId,
                            phoneNumber: fullMemberAddress.phoneNumber,
                            groupThreadId: thread.uniqueId,
                            lastInteractionTimestamp: 0),
                        tx: tx
                    )
                }
            }
        }

        let threadAssociatedDataStore = MockThreadAssociatedDataStore()
        threadAssociatedDataStore.values = Dictionary(uniqueKeysWithValues: threadStore.threads.map {
            ($0.uniqueId, ThreadAssociatedData(threadUniqueId: $0.uniqueId))
        })
        threadAssociatedDataStore.values[groupArchived.uniqueId] = ThreadAssociatedData(
            threadUniqueId: groupArchived.uniqueId,
            isArchived: true,
            isMarkedUnread: false,
            mutedUntilTimestamp: 0,
            audioPlaybackRate: 1
        )

        let interactionStore = MockInteractionStore()

        let mergeObserver = PhoneNumberChangedMessageInserter(
            groupMemberStore: groupMemberStore,
            interactionStore: interactionStore,
            threadAssociatedDataStore: threadAssociatedDataStore,
            threadStore: threadStore
        )

        // Alice changes her number.
        interactionStore.insertedInteractions = []
        mockDB.write { tx in
            mergeObserver.didLearnAssociation(
                mergedRecipient: makeRecipient(
                    serviceId: aliceAci,
                    oldPhoneNumber: alicePhoneNumber1,
                    newPhoneNumber: alicePhoneNumber2,
                    isLocalRecipient: false
                ),
                transaction: tx
            )

            let threadIds = interactionStore.insertedInteractions.map { $0.uniqueThreadId }
            XCTAssertEqual(Set(threadIds), [groupWithEveryone.uniqueId, aliceThread.uniqueId])
        }

        // Bob acquires a number for the first time.
        interactionStore.insertedInteractions = []
        mockDB.write { tx in
            mergeObserver.didLearnAssociation(
                mergedRecipient: makeRecipient(
                    serviceId: bobAci,
                    oldPhoneNumber: bobPhoneNumber1,
                    newPhoneNumber: bobPhoneNumber2,
                    isLocalRecipient: false
                ),
                transaction: tx
            )

            let threadIds = interactionStore.insertedInteractions.map { $0.uniqueThreadId }
            XCTAssertEqual(Set(threadIds), [])
        }

        // Bob changes his number.
        interactionStore.insertedInteractions = []
        mockDB.write { tx in
            mergeObserver.didLearnAssociation(
                mergedRecipient: makeRecipient(
                    serviceId: bobAci,
                    oldPhoneNumber: bobPhoneNumber2,
                    newPhoneNumber: bobPhoneNumber3,
                    isLocalRecipient: false
                ),
                transaction: tx
            )

            let threadIds = interactionStore.insertedInteractions.map { $0.uniqueThreadId }
            XCTAssertEqual(Set(threadIds), [groupWithEveryone.uniqueId, groupWithoutAlice.uniqueId])
        }

        // The local user changes their number.
        interactionStore.insertedInteractions = []
        mockDB.write { tx in
            mergeObserver.didLearnAssociation(
                mergedRecipient: makeRecipient(
                    serviceId: myAci,
                    oldPhoneNumber: myPhoneNumber1,
                    newPhoneNumber: myPhoneNumber2,
                    isLocalRecipient: true
                ),
                transaction: tx
            )

            let threadIds = interactionStore.insertedInteractions.map { $0.uniqueThreadId }
            XCTAssertEqual(Set(threadIds), [])
        }
    }

    private func makeRecipient(
        serviceId: ServiceId,
        oldPhoneNumber: E164?,
        newPhoneNumber: E164,
        isLocalRecipient: Bool
    ) -> MergedRecipient {
        MergedRecipient(
            serviceId: serviceId,
            oldPhoneNumber: oldPhoneNumber?.stringValue,
            newPhoneNumber: newPhoneNumber,
            isLocalRecipient: isLocalRecipient,
            signalRecipient: SignalRecipient(serviceId: ServiceIdObjC(serviceId), phoneNumber: E164ObjC(newPhoneNumber))
        )
    }

}
