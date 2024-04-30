//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import LibSignalClient
@testable import Signal
import XCTest

class ReactionBurstManagerTests: XCTestCase {
    func testBasicTriggerBurst() {
        var bursts = [[String]]()
        let mockBurstDelegate = MockBurstDelegate { rawEmojis in
            bursts.append(rawEmojis)
        }
        let manager = ReactionBurstManager(burstDelegate: mockBurstDelegate)
        let reaction0 = Reaction(emoji: "🙈", name: "", aci: Aci(fromUUID: UUID()), timestamp: 1)
        let reaction1 = Reaction(emoji: "🙈", name: "", aci: Aci(fromUUID: UUID()), timestamp: 2)
        let reaction2 = Reaction(emoji: "🙈", name: "", aci: Aci(fromUUID: UUID()), timestamp: 3)
        manager.add(reaction: reaction0)
        manager.add(reaction: reaction1)
        manager.add(reaction: reaction2)
        XCTAssert(bursts == [["🙈", "🙈", "🙈"]])

        bursts.removeAll()
        // Should not trigger burst because recent reactions queue was cleared after bursting.
        let reaction3 = Reaction(emoji: "🙈", name: "", aci: Aci(fromUUID: UUID()), timestamp: 4)
        manager.add(reaction: reaction3)
        XCTAssert(bursts == [])
    }

    func testTooSlowToTriggerBurst() {
        var bursts = [[String]]()
        let mockBurstDelegate = MockBurstDelegate { rawEmojis in
            bursts.append(rawEmojis)
        }
        let manager = ReactionBurstManager(burstDelegate: mockBurstDelegate)
        let reaction0 = Reaction(emoji: "🙈", name: "", aci: Aci(fromUUID: UUID()), timestamp: 1)
        let reaction1 = Reaction(emoji: "🙈", name: "", aci: Aci(fromUUID: UUID()), timestamp: 3)
        let reaction2 = Reaction(emoji: "🙈", name: "", aci: Aci(fromUUID: UUID()), timestamp: 6)
        manager.add(reaction: reaction0)
        manager.add(reaction: reaction1)
        manager.add(reaction: reaction2)
        XCTAssert(bursts == [])

        let reaction4 = Reaction(emoji: "🙈", name: "", aci: Aci(fromUUID: UUID()), timestamp: 7)
        manager.add(reaction: reaction4)
        XCTAssert(bursts == [["🙈", "🙈", "🙈"]])
    }

    func testTriggerWhenDifferentSkintones() {
        var bursts = [[String]]()
        let mockBurstDelegate = MockBurstDelegate { rawEmojis in
            bursts.append(rawEmojis)
        }
        let manager = ReactionBurstManager(burstDelegate: mockBurstDelegate)
        let reaction0 = Reaction(emoji: "👍", name: "", aci: Aci(fromUUID: UUID()), timestamp: 1)
        let reaction1 = Reaction(emoji: "👍🏿", name: "", aci: Aci(fromUUID: UUID()), timestamp: 2)
        let reaction2 = Reaction(emoji: "👍🏼", name: "", aci: Aci(fromUUID: UUID()), timestamp: 3)
        manager.add(reaction: reaction0)
        manager.add(reaction: reaction1)
        manager.add(reaction: reaction2)
        XCTAssert(bursts == [["👍", "👍🏿", "👍🏼"]])
    }

    func testCooloff() {
        var bursts = [[String]]()
        let mockBurstDelegate = MockBurstDelegate { rawEmojis in
            bursts.append(rawEmojis)
        }
        let manager = ReactionBurstManager(burstDelegate: mockBurstDelegate)
        let reactions = [
            Reaction(emoji: "🙈", name: "", aci: Aci(fromUUID: UUID()), timestamp: 1),
            Reaction(emoji: "🙈", name: "", aci: Aci(fromUUID: UUID()), timestamp: 1.1),
            Reaction(emoji: "🙈", name: "", aci: Aci(fromUUID: UUID()), timestamp: 1.2),
            Reaction(emoji: "🙈", name: "", aci: Aci(fromUUID: UUID()), timestamp: 1.3),
            Reaction(emoji: "🙈", name: "", aci: Aci(fromUUID: UUID()), timestamp: 1.4),
            Reaction(emoji: "🙈", name: "", aci: Aci(fromUUID: UUID()), timestamp: 1.5),
            Reaction(emoji: "🙈", name: "", aci: Aci(fromUUID: UUID()), timestamp: 1.6),
            Reaction(emoji: "🙈", name: "", aci: Aci(fromUUID: UUID()), timestamp: 1.7),
            Reaction(emoji: "🙈", name: "", aci: Aci(fromUUID: UUID()), timestamp: 1.8)
        ]
        reactions.forEach {
            manager.add(reaction: $0)
        }
        XCTAssert(bursts == [["🙈", "🙈", "🙈"]])
    }

    func testMaxBursting() {
        var bursts = [[String]]()
        let mockBurstDelegate = MockBurstDelegate { rawEmojis in
            bursts.append(rawEmojis)
        }
        let manager = ReactionBurstManager(burstDelegate: mockBurstDelegate)
        let reactions = [
            Reaction(emoji: "🙈", name: "", aci: Aci(fromUUID: UUID()), timestamp: 1),
            Reaction(emoji: "🙈", name: "", aci: Aci(fromUUID: UUID()), timestamp: 1.1),
            Reaction(emoji: "🙈", name: "", aci: Aci(fromUUID: UUID()), timestamp: 1.2),
            Reaction(emoji: "🐞", name: "", aci: Aci(fromUUID: UUID()), timestamp: 1.3),
            Reaction(emoji: "🐞", name: "", aci: Aci(fromUUID: UUID()), timestamp: 1.4),
            Reaction(emoji: "🐞", name: "", aci: Aci(fromUUID: UUID()), timestamp: 1.5),
            Reaction(emoji: "💜", name: "", aci: Aci(fromUUID: UUID()), timestamp: 1.6),
            Reaction(emoji: "💜", name: "", aci: Aci(fromUUID: UUID()), timestamp: 1.7),
            Reaction(emoji: "💜", name: "", aci: Aci(fromUUID: UUID()), timestamp: 1.8),
            Reaction(emoji: "☎️", name: "", aci: Aci(fromUUID: UUID()), timestamp: 1.6),
            Reaction(emoji: "☎️", name: "", aci: Aci(fromUUID: UUID()), timestamp: 1.7),
            Reaction(emoji: "☎️", name: "", aci: Aci(fromUUID: UUID()), timestamp: 1.8)
        ]
        reactions.forEach {
            manager.add(reaction: $0)
        }
        XCTAssert(bursts == [
            ["🙈", "🙈", "🙈"],
            ["🐞", "🐞", "🐞"],
            ["💜", "💜", "💜"]
        ])
    }

    func testRequireDistinctAcis() {
        var bursts = [[String]]()
        let mockBurstDelegate = MockBurstDelegate { rawEmojis in
            bursts.append(rawEmojis)
        }
        let aci = Aci(fromUUID: UUID())
        let manager = ReactionBurstManager(burstDelegate: mockBurstDelegate)
        // Same ACI sends these. If the ACIs were different, we'd have a burst.
        let reaction0 = Reaction(emoji: "🙈", name: "", aci: aci, timestamp: 1)
        let reaction1 = Reaction(emoji: "🙈", name: "", aci: aci, timestamp: 2)
        let reaction2 = Reaction(emoji: "🙈", name: "", aci: aci, timestamp: 3)
        manager.add(reaction: reaction0)
        manager.add(reaction: reaction1)
        manager.add(reaction: reaction2)
        XCTAssert(bursts == [])

        let reaction3 = Reaction(emoji: "🙈", name: "", aci: Aci(fromUUID: UUID()), timestamp: 4)
        let reaction4 = Reaction(emoji: "🙈", name: "", aci: Aci(fromUUID: UUID()), timestamp: 5)
        manager.add(reaction: reaction3)
        manager.add(reaction: reaction4)
        XCTAssert(bursts == [["🙈", "🙈", "🙈"]])

    }
}

private class MockBurstDelegate: ReactionBurstDelegate {
    private var handleReactions: ([String]) -> Void

    init(handleReactions: @escaping ([String]) -> Void) {
        self.handleReactions = handleReactions
    }

    func burst(reactions: [Signal.Reaction]) {
        let rawEmojis = reactions.map {
            $0.emoji
        }
        self.handleReactions(rawEmojis)
    }
}
