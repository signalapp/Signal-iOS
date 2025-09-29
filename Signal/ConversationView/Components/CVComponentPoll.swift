//
// Copyright 2025 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import SignalServiceKit
public import SignalUI

final public class CVComponentPoll: CVComponentBase, CVComponent {
    public var componentKey: CVComponentKey { .poll }
    private let poll: CVComponentState.Poll

    init(
        itemModel: CVItemModel,
        poll: CVComponentState.Poll
    ) {
        self.poll = poll
        super.init(itemModel: itemModel)
    }

    public func buildComponentView(componentDelegate: any CVComponentDelegate) -> any CVComponentView {
        CVComponentViewPoll()
    }

    public func configureForRendering(
        componentView: any CVComponentView,
        cellMeasurement: SignalUI.CVCellMeasurement,
        componentDelegate: any CVComponentDelegate
    ) {
        guard let componentViewPoll = componentView as? CVComponentViewPoll else {
            owsFailDebug("Unexpected componentView.")
            componentView.reset()
            return
        }

        componentViewPoll.pollView.configureForRendering(state: poll.state, cellMeasurement: cellMeasurement, componentDelegate: componentDelegate)
    }

    public func measure(maxWidth: CGFloat, measurementBuilder: SignalUI.CVCellMeasurement.Builder) -> CGSize {
        owsAssertDebug(maxWidth > 0)

        let maxWidth = min(maxWidth, conversationStyle.maxMediaMessageWidth)
        return CVPollView.measure(maxWidth: maxWidth, measurementBuilder: measurementBuilder, state: poll.state)
    }

    // MARK: -

    // Used for rendering some portion of an Conversation View item.
    // It could be the entire item or some part thereof.
    public class CVComponentViewPoll: NSObject, CVComponentView {

        fileprivate let pollView = CVPollView(name: "CVPollView")

        public var isDedicatedCellView = false

        public var rootView: UIView {
            pollView
        }

        public func setIsCellVisible(_ isCellVisible: Bool) {}

        public func reset() {
            pollView.reset()
        }
    }

}
