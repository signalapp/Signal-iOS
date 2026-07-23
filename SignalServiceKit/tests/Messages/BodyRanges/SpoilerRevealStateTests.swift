//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import LibSignalClient
public import XCTest

@testable import SignalServiceKit

public class SpoilerRevealStateTests: XCTestCase {

    // Test that exists to _try_ and prevent a change being made to spoiler state
    // such that snapshots are no longer copy operations on structs but end up
    // copying some value by reference. Can't possibly cover every case, but covers some.
    func testSpoilerRevealSnapshotMakesCopy() {
        let identifierA = InteractionSnapshotIdentifier(timestamp: 0, authorAci: Aci.randomForTesting())
        let revealedIdA1 = MessageBodyRanges.MergedSingleStyle(style: .spoiler, mergedRange: NSRange(location: 1, length: 1)).id
        let revealedIdA2 = MessageBodyRanges.MergedSingleStyle(style: .spoiler, mergedRange: NSRange(location: 2, length: 1)).id

        let identifierB = InteractionSnapshotIdentifier(timestamp: 1, authorAci: Aci.randomForTesting())
        let revealedIdB1 = MessageBodyRanges.MergedSingleStyle(style: .spoiler, mergedRange: NSRange(location: 3, length: 1)).id

        let spoilerRevealState = SpoilerRevealState()
        spoilerRevealState.setSpoilerRevealed(withID: revealedIdA1, interactionIdentifier: identifierA)
        spoilerRevealState.setSpoilerRevealed(withID: revealedIdB1, interactionIdentifier: identifierB)

        XCTAssertEqual(
            spoilerRevealState.revealedSpoilerIds(interactionIdentifier: identifierA),
            Set([revealedIdA1]),
        )
        XCTAssertEqual(
            spoilerRevealState.revealedSpoilerIds(interactionIdentifier: identifierB),
            Set([revealedIdB1]),
        )

        var snapshot = spoilerRevealState.snapshot()

        XCTAssertEqual(
            snapshot[identifierA],
            Set([revealedIdA1]),
        )
        XCTAssertEqual(
            snapshot[identifierB],
            Set([revealedIdB1]),
        )

        snapshot[identifierA] = Set([revealedIdA1, revealedIdA2])
        snapshot[identifierB] = nil

        // The original should be unchanged despite changes to the snapshot.
        XCTAssertEqual(
            spoilerRevealState.revealedSpoilerIds(interactionIdentifier: identifierA),
            Set([revealedIdA1]),
        )
        XCTAssertEqual(
            spoilerRevealState.revealedSpoilerIds(interactionIdentifier: identifierB),
            Set([revealedIdB1]),
        )
        // Snapshot should be updated though.
        XCTAssertEqual(
            snapshot[identifierA],
            Set([revealedIdA1, revealedIdA2]),
        )
        XCTAssertNil(snapshot[identifierB])

        // Take a new snapshot.
        snapshot = spoilerRevealState.snapshot()

        XCTAssertEqual(
            snapshot[identifierA],
            Set([revealedIdA1]),
        )
        XCTAssertEqual(
            snapshot[identifierB],
            Set([revealedIdB1]),
        )

        // Update the original.
        spoilerRevealState.setSpoilerRevealed(withID: revealedIdA2, interactionIdentifier: identifierA)

        // The original should be updated.
        XCTAssertEqual(
            spoilerRevealState.revealedSpoilerIds(interactionIdentifier: identifierA),
            Set([revealedIdA1, revealedIdA2]),
        )
        // The snapshot should be unchanged.
        XCTAssertEqual(
            snapshot[identifierA],
            Set([revealedIdA1]),
        )
        XCTAssertEqual(
            snapshot[identifierB],
            Set([revealedIdB1]),
        )
    }
}
