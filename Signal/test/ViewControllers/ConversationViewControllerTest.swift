//
// Copyright 2020 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import XCTest

@testable import Signal
@testable import SignalServiceKit

class ConversationViewControllerTest: SignalBaseTest {

    func testCVCBottomViewType() {
        XCTAssertEqual(CVCBottomViewType.none, CVCBottomViewType.none)
        XCTAssertNotEqual(CVCBottomViewType.none, CVCBottomViewType.inputToolbar)
        XCTAssertEqual(CVCBottomViewType.inputToolbar, CVCBottomViewType.inputToolbar)
        XCTAssertNotEqual(CVCBottomViewType.none, CVCBottomViewType.memberRequestView)
        XCTAssertNotEqual(
            CVCBottomViewType.memberRequestView,
            CVCBottomViewType.messageRequestView(
                messageRequestType: MessageRequestType(
                    isGroupV1Thread: true,
                    isGroupV2Thread: true,
                    isThreadBlocked: true,
                    hasSentMessages: true,
                    isThreadFromHiddenRecipient: false,
                    hasReportedSpam: false,
                    isLocalUserInvitedMember: false,
                    showReviewRequestsCarefullyWarning: false,
                ),
            ),
        )
        XCTAssertEqual(
            CVCBottomViewType.messageRequestView(
                messageRequestType: MessageRequestType(
                    isGroupV1Thread: true,
                    isGroupV2Thread: true,
                    isThreadBlocked: true,
                    hasSentMessages: true,
                    isThreadFromHiddenRecipient: false,
                    hasReportedSpam: false,
                    isLocalUserInvitedMember: false,
                    showReviewRequestsCarefullyWarning: false,
                ),
            ),
            CVCBottomViewType.messageRequestView(
                messageRequestType: MessageRequestType(
                    isGroupV1Thread: true,
                    isGroupV2Thread: true,
                    isThreadBlocked: true,
                    hasSentMessages: true,
                    isThreadFromHiddenRecipient: false,
                    hasReportedSpam: false,
                    isLocalUserInvitedMember: false,
                    showReviewRequestsCarefullyWarning: false,
                ),
            ),
        )
        XCTAssertNotEqual(
            CVCBottomViewType.messageRequestView(
                messageRequestType: MessageRequestType(
                    isGroupV1Thread: true,
                    isGroupV2Thread: true,
                    isThreadBlocked: true,
                    hasSentMessages: true,
                    isThreadFromHiddenRecipient: false,
                    hasReportedSpam: false,
                    isLocalUserInvitedMember: false,
                    showReviewRequestsCarefullyWarning: false,
                ),
            ),
            CVCBottomViewType.messageRequestView(
                messageRequestType: MessageRequestType(
                    isGroupV1Thread: true,
                    isGroupV2Thread: false,
                    isThreadBlocked: true,
                    hasSentMessages: true,
                    isThreadFromHiddenRecipient: false,
                    hasReportedSpam: false,
                    isLocalUserInvitedMember: false,
                    showReviewRequestsCarefullyWarning: false,
                ),
            ),
        )
        XCTAssertEqual(
            CVCBottomViewType.messageRequestView(
                messageRequestType: MessageRequestType(
                    isGroupV1Thread: true,
                    isGroupV2Thread: false,
                    isThreadBlocked: true,
                    hasSentMessages: true,
                    isThreadFromHiddenRecipient: false,
                    hasReportedSpam: false,
                    isLocalUserInvitedMember: false,
                    showReviewRequestsCarefullyWarning: false,
                ),
            ),
            CVCBottomViewType.messageRequestView(
                messageRequestType: MessageRequestType(
                    isGroupV1Thread: true,
                    isGroupV2Thread: false,
                    isThreadBlocked: true,
                    hasSentMessages: true,
                    isThreadFromHiddenRecipient: false,
                    hasReportedSpam: false,
                    isLocalUserInvitedMember: false,
                    showReviewRequestsCarefullyWarning: false,
                ),
            ),
        )
        XCTAssertNotEqual(
            CVCBottomViewType.messageRequestView(
                messageRequestType: MessageRequestType(
                    isGroupV1Thread: true,
                    isGroupV2Thread: true,
                    isThreadBlocked: true,
                    hasSentMessages: false,
                    isThreadFromHiddenRecipient: false,
                    hasReportedSpam: false,
                    isLocalUserInvitedMember: false,
                    showReviewRequestsCarefullyWarning: false,
                ),
            ),
            CVCBottomViewType.messageRequestView(
                messageRequestType: MessageRequestType(
                    isGroupV1Thread: true,
                    isGroupV2Thread: false,
                    isThreadBlocked: true,
                    hasSentMessages: true,
                    isThreadFromHiddenRecipient: false,
                    hasReportedSpam: false,
                    isLocalUserInvitedMember: false,
                    showReviewRequestsCarefullyWarning: false,
                ),
            ),
        )
    }
}

class DoubleTapHeartReactionTest: SignalBaseTest {
    override func setUp() {
        super.setUp()
        write { tx in
            (DependenciesBridge.shared.registrationStateChangeManager as! RegistrationStateChangeManagerImpl).registerForTests(
                localIdentifiers: .forUnitTests,
                tx: tx,
            )
        }
    }

    func testAddsHeartAndMarksItRead() throws {
        try write { tx in
            let message = IncomingMessageFactory().create(transaction: tx)

            XCTAssertTrue(ConversationViewController.addDoubleTapHeartReaction(to: message.uniqueId, tx: tx))

            let reaction = try XCTUnwrap(message.reaction(for: LocalIdentifiers.forUnitTests.aci, tx: tx))
            XCTAssertEqual(reaction.emoji, "❤️")
            XCTAssertTrue(reaction.read)
        }
    }

    func testRepeatedDoubleTapKeepsTheSameReaction() throws {
        let message = IncomingMessageFactory().create()
        let firstReactionId = try write { tx in
            XCTAssertTrue(ConversationViewController.addDoubleTapHeartReaction(to: message.uniqueId, tx: tx))
            return try XCTUnwrap(message.reaction(for: LocalIdentifiers.forUnitTests.aci, tx: tx)).uniqueId
        }

        try write { tx in
            XCTAssertFalse(ConversationViewController.addDoubleTapHeartReaction(to: message.uniqueId, tx: tx))
            let reaction = try XCTUnwrap(message.reaction(for: LocalIdentifiers.forUnitTests.aci, tx: tx))
            XCTAssertEqual(reaction.uniqueId, firstReactionId)
            XCTAssertEqual(reaction.emoji, "❤️")
        }
    }

    func testReplacesAnotherReaction() throws {
        try write { tx in
            let message = IncomingMessageFactory().create(transaction: tx)
            message.recordReaction(
                for: LocalIdentifiers.forUnitTests.aci,
                emoji: "👍",
                sentAtTimestamp: 1,
                tx: tx,
            )

            XCTAssertTrue(ConversationViewController.addDoubleTapHeartReaction(to: message.uniqueId, tx: tx))
            let reaction = try XCTUnwrap(message.reaction(for: LocalIdentifiers.forUnitTests.aci, tx: tx))
            XCTAssertEqual(reaction.emoji, "❤️")
        }
    }

    func testRemotelyDeletedMessageDoesNotReceiveAReaction() {
        let message = IncomingMessageFactory().create()
        write { tx in
            message.updateWithRemotelyDeletedAndRemoveRenderableContent(with: tx)
        }

        write { tx in
            XCTAssertFalse(ConversationViewController.addDoubleTapHeartReaction(to: message.uniqueId, tx: tx))
            XCTAssertNil(message.reaction(for: LocalIdentifiers.forUnitTests.aci, tx: tx))
        }
    }

    func testMissingMessageDoesNotReceiveAReaction() {
        write { tx in
            XCTAssertFalse(ConversationViewController.addDoubleTapHeartReaction(to: UUID().uuidString, tx: tx))
        }
    }

    func testOutgoingMessageDoesNotReceiveAReaction() {
        write { tx in
            let message = OutgoingMessageFactory().create(transaction: tx)
            XCTAssertFalse(ConversationViewController.addDoubleTapHeartReaction(to: message.uniqueId, tx: tx))
            XCTAssertNil(message.reaction(for: LocalIdentifiers.forUnitTests.aci, tx: tx))
        }
    }
}
