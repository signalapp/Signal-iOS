//
// Copyright 2020 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import SignalServiceKit
import SignalUI

public class CVComponentReactions: CVComponentBase, CVComponent, CVAccessibilityComponent {

    public var componentKey: CVComponentKey { .reactions }

    private let reactions: CVComponentState.Reactions
    private var reactionState: InteractionReactionState {
        reactions.reactionState
    }
    private var viewState: CVReactionCountsView.State {
        reactions.viewState
    }

    init(itemModel: CVItemModel,
         reactions: CVComponentState.Reactions) {
        self.reactions = reactions

        super.init(itemModel: itemModel)
    }

    public func buildComponentView(componentDelegate: CVComponentDelegate) -> CVComponentView {
        CVComponentViewReactions()
    }

    public func configureForRendering(componentView componentViewParam: CVComponentView,
                                      cellMeasurement: CVCellMeasurement,
                                      componentDelegate: CVComponentDelegate) {
        guard let componentView = componentViewParam as? CVComponentViewReactions else {
            owsFailDebug("Unexpected componentView.")
            componentViewParam.reset()
            return
        }

        let reactionCountsView = componentView.reactionCountsView
        reactionCountsView.configure(state: viewState,
                                     cellMeasurement: cellMeasurement)
    }

    public func measure(maxWidth: CGFloat, measurementBuilder: CVCellMeasurement.Builder) -> CGSize {
        owsAssertDebug(maxWidth > 0)

        return CVReactionCountsView.measure(state: viewState,
                                            measurementBuilder: measurementBuilder)
    }

    // MARK: - Events

    public override func handleTap(sender: UITapGestureRecognizer,
                                   componentDelegate: CVComponentDelegate,
                                   componentView: CVComponentView,
                                   renderItem: CVRenderItem) -> Bool {

        guard let message = interaction as? TSMessage else {
            owsFailDebug("Invalid interaction.")
            return false
        }
        componentDelegate.didTapReactions(reactionState: reactionState, message: message)
        return true
    }

    // MARK: - Accessibility

    public var accessibilityDescription: String {
        var fullString = ""
        let pills = [viewState.pill1, viewState.pill2, viewState.pill3].compactMap{ $0 }

        for pill in pills {
            let string: String
            switch pill {
            case .emoji(let emoji, let count, _):
                string = String(
                    format: OWSLocalizedString(
                        "MESSAGE_REACTIONS_ACCESSIBILITY_LABEL_%d",
                        tableName: "PluralAware",
                        comment: "Accessibility label reading out a reaction to a message and its count. Embeds {{ count }} and {{ emoji name }}."
                    ),
                    count,
                    emoji
                )
            case .moreCount(let count, _):
                string = String(
                    format: OWSLocalizedString(
                        "OVERFLOW_REACTIONS_ACCESSIBILITY_LABEL_%d",
                        tableName: "PluralAware",
                        comment: "Accessibility label stating that there are additional reactions to a message that couldn't be displayed. Embeds {{ count of additional reactions }}"
                    ),
                    count
                )
            }
            fullString.append(string)
            fullString.append(" ")
        }

        return fullString
    }

    // MARK: -

    // Used for rendering some portion of an Conversation View item.
    // It could be the entire item or some part thereof.
    public class CVComponentViewReactions: NSObject, CVComponentView {

        fileprivate let reactionCountsView = CVReactionCountsView()

        public var isDedicatedCellView = false

        public var rootView: UIView {
            reactionCountsView
        }

        public func setIsCellVisible(_ isCellVisible: Bool) {}

        public func reset() {
            reactionCountsView.reset()
        }

    }
}
