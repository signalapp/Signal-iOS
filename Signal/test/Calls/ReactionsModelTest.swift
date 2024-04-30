//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import LibSignalClient
import XCTest

@testable import Signal

final class ReactionsModelTest: XCTestCase {
    private func changesMatchExpected(
        changes: ReactionsModel.ReactionChangeSet?,
        expectedToAdd: [Reaction],
        expectedToMove: [Reaction],
        expectedSlotsToMove: Int,
        expectedToRemove: [Reaction]
    ) -> Bool {
        guard let changes else {
            return false
        }
        let uuidsAdded = changes.reactionsToAdd.map { $0.uuid }
        let uuidsMoved = changes.reactionsToMove.map { $0.uuid }
        let uuidsRemoved = changes.reactionsToRemove.map { $0.uuid }

        let uuidsExpectedToAdd = expectedToAdd.map { $0.uuid }
        let uuidsExpectedToMove = expectedToMove.map { $0.uuid }
        let uuidsExpectedToRemove = expectedToRemove.map { $0.uuid }

        return uuidsAdded == uuidsExpectedToAdd && uuidsMoved == uuidsExpectedToMove && uuidsRemoved == uuidsExpectedToRemove && changes.slotsToMove == expectedSlotsToMove
    }

    func testChanges() {
        // No changes, from empty.
        let model = ReactionsModel()
        XCTAssert(model.changesSinceLastDiff() == nil)

        // Add one.
        let r1 = Reaction(emoji: "🤣", name: "Much LOL", aci: Aci(fromUUID: UUID()), timestamp: Date.timeIntervalSinceReferenceDate)
        model.add(reactions: [r1])
        XCTAssert(
            changesMatchExpected(
                changes: model.changesSinceLastDiff(),
                expectedToAdd: [r1],
                expectedToMove: [],
                expectedSlotsToMove: 0,
                expectedToRemove: []
            )
        )

        // Add two together.
        let r2 = Reaction(emoji: "🫠", name: "Monsieur Melty Face", aci: Aci(fromUUID: UUID()), timestamp: Date.timeIntervalSinceReferenceDate)
        let r3 = Reaction(emoji: "🤮", name: "Blehhh", aci: Aci(fromUUID: UUID()), timestamp: Date.timeIntervalSinceReferenceDate)
        model.add(reactions: [r2, r3])
        XCTAssert(
            changesMatchExpected(
                changes: model.changesSinceLastDiff(),
                expectedToAdd: [r2, r3],
                expectedToMove: [r1],
                expectedSlotsToMove: 2,
                expectedToRemove: []
            )
        )

        // Make no changes and make sure we register no changes.
        XCTAssert(model.changesSinceLastDiff() == nil)

        // Add more reactions than the max (5).
        let r4 = Reaction(emoji: "🙈", name: "Monkey See Monkey Do", aci: Aci(fromUUID: UUID()), timestamp: Date.timeIntervalSinceReferenceDate)
        let r5 = Reaction(emoji: "😠", name: "Grumpy", aci: Aci(fromUUID: UUID()), timestamp: Date.timeIntervalSinceReferenceDate)
        let r6 = Reaction(emoji: "🤧", name: "Sneezy", aci: Aci(fromUUID: UUID()), timestamp: Date.timeIntervalSinceReferenceDate)
        let r7 = Reaction(emoji: "🥸", name: "Incognito", aci: Aci(fromUUID: UUID()), timestamp: Date.timeIntervalSinceReferenceDate)
        let r8 = Reaction(emoji: "🥺", name: "Dawwwww", aci: Aci(fromUUID: UUID()), timestamp: Date.timeIntervalSinceReferenceDate)
        let r9 = Reaction(emoji: "🥳", name: "Par-tay", aci: Aci(fromUUID: UUID()), timestamp: Date.timeIntervalSinceReferenceDate)
        model.add(reactions: [r4, r5, r6, r7, r8, r9])
        XCTAssert(
            changesMatchExpected(
                changes: model.changesSinceLastDiff(),
                expectedToAdd: [r5, r6, r7, r8, r9], // drop all but last 5
                expectedToMove: [],
                expectedSlotsToMove: 0,
                expectedToRemove: [r1, r2, r3]
            )
        )

        // Add a couple more to get changes in all categories.
        let r10 = Reaction(emoji: "😩", name: "No compile", aci: Aci(fromUUID: UUID()), timestamp: Date.timeIntervalSinceReferenceDate)
        let r11 = Reaction(emoji: "👽", name: "Outta this world", aci: Aci(fromUUID: UUID()), timestamp: Date.timeIntervalSinceReferenceDate)
        model.add(reactions: [r10, r11])
        XCTAssert(
            changesMatchExpected(
                changes: model.changesSinceLastDiff(),
                expectedToAdd: [r10, r11],
                expectedToMove: [r7, r8, r9],
                expectedSlotsToMove: 2,
                expectedToRemove: [r5, r6]
            )
        )

        // Make separate adds/removes and make sure the changeset coalesces all changes.
        model.remove(uuids: [r7.uuid])
        let r12 = Reaction(emoji: "🍀", name: "Lucky", aci: Aci(fromUUID: UUID()), timestamp: Date.timeIntervalSinceReferenceDate)
        model.add(reactions: [r12])
        model.remove(uuids: [r8.uuid])
        model.remove(uuids: [r9.uuid])
        XCTAssert(
            changesMatchExpected(
                changes: model.changesSinceLastDiff(),
                expectedToAdd: [r12],
                expectedToMove: [r10, r11],
                expectedSlotsToMove: 1,
                expectedToRemove: [r7, r8, r9]
            )
        )
    }
}
