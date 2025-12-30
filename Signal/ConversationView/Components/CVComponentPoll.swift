//
// Copyright 2025 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import SignalServiceKit
public import SignalUI

public class CVComponentPoll: CVComponentBase, CVComponent {
    public var componentKey: CVComponentKey { .poll }
    private let poll: CVComponentState.Poll

    init(
        itemModel: CVItemModel,
        poll: CVComponentState.Poll,
    ) {
        self.poll = poll
        super.init(itemModel: itemModel)
    }

    public func buildComponentView(componentDelegate: any CVComponentDelegate) -> any CVComponentView {
        CVComponentViewPoll(componentDelegate: componentDelegate)
    }

    public func configureForRendering(
        componentView: any CVComponentView,
        cellMeasurement: SignalUI.CVCellMeasurement,
        componentDelegate: any CVComponentDelegate,
    ) {
        guard let componentViewPoll = componentView as? CVComponentViewPoll else {
            owsFailDebug("Unexpected componentView.")
            componentView.reset()
            return
        }

        componentViewPoll.pollView.configureForRendering(
            state: poll.state,
            previousPollState: poll.prevPollState,
            cellMeasurement: cellMeasurement,
            componentDelegate: componentDelegate,
            accessibilitySummary: buildAccessibilityLabel(),
        )
    }

    public func measure(maxWidth: CGFloat, measurementBuilder: SignalUI.CVCellMeasurement.Builder) -> CGSize {
        owsAssertDebug(maxWidth > 0)

        let maxWidth = min(maxWidth, conversationStyle.maxMessageWidth)
        return CVPollView.measure(maxWidth: maxWidth, measurementBuilder: measurementBuilder, state: poll.state)
    }

    // Builds an accessibility label for the entire poll.
    // This label uses basic punctuation which might be used by
    // VoiceOver for pauses/timing.
    //
    // Example: Lilia sent: a poll, what should we have for dinner?
    // Example: You sent: a poll, where should we go on vacation?
    private func buildAccessibilityLabel() -> String {
        var elements = [String]()
        if isIncoming {
            if let accessibilityAuthorName = itemViewState.accessibilityAuthorName {
                let senderFormat = OWSLocalizedString(
                    "CONVERSATION_VIEW_CELL_ACCESSIBILITY_SENDER_FORMAT",
                    comment: "Format for sender info for accessibility label for message. Embeds {{ the sender name }}.",
                )
                elements.append(String(format: senderFormat, accessibilityAuthorName))
            } else {
                owsFailDebug("Missing accessibilityAuthorName.")
            }
        } else if isOutgoing {
            elements.append(OWSLocalizedString(
                "CONVERSATION_VIEW_CELL_ACCESSIBILITY_SENDER_LOCAL_USER",
                comment: "Format for sender info for outgoing messages.",
            ))
        }

        let formatQuestion = OWSLocalizedString(
            "POLL_ACCESSIBILITY_LABEL",
            comment: "Accessibility label for poll message. Embeds {{ poll question }}.",
        )
        elements.append(String(format: formatQuestion, poll.state.poll.question))

        let result = elements.joined(separator: " ")
        return result
    }

    // MARK: -

    // Used for rendering some portion of an Conversation View item.
    // It could be the entire item or some part thereof.
    public class CVComponentViewPoll: NSObject, CVComponentView {

        fileprivate var pollView = CVPollView(name: "CVPollView")

        private weak var componentDelegate: CVComponentDelegate?

        public var isDedicatedCellView = false

        public var rootView: UIView {
            pollView
        }

        init(componentDelegate: CVComponentDelegate) {
            self.componentDelegate = componentDelegate
        }

        public func setIsCellVisible(_ isCellVisible: Bool) {}

        public func reset() {
            pollView.reset()
        }
    }
}
