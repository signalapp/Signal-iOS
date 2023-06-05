//
// Copyright 2020 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import SignalUI

public class CVComponentBottomButtons: CVComponentBase, CVComponent {

    public var componentKey: CVComponentKey { .bottomButtons }

    private let bottomButtonsState: CVComponentState.BottomButtons

    typealias Action = CVMessageAction
    fileprivate var actions: [Action] { bottomButtonsState.actions }

    required init(itemModel: CVItemModel, bottomButtonsState: CVComponentState.BottomButtons) {
        self.bottomButtonsState = bottomButtonsState

        super.init(itemModel: itemModel)
    }

    public func buildComponentView(componentDelegate: CVComponentDelegate) -> CVComponentView {
        CVComponentViewBottomButtons()
    }

    public func configureForRendering(componentView componentViewParam: CVComponentView,
                                      cellMeasurement: CVCellMeasurement,
                                      componentDelegate: CVComponentDelegate) {
        guard let componentView = componentViewParam as? CVComponentViewBottomButtons else {
            owsFailDebug("Unexpected componentView.")
            componentViewParam.reset()
            return
        }

        componentView.reset()

        var subviews = [UIView]()
        for action in actions {
            let buttonView = CVMessageActionButton(action: action)
            buttonView.backgroundColor = Theme.conversationButtonBackgroundColor
            subviews.append(buttonView)
            componentView.buttonViews.append(buttonView)
        }

        let stackView = componentView.stackView
        stackView.reset()
        stackView.configure(config: stackConfig,
                            cellMeasurement: cellMeasurement,
                            measurementKey: Self.measurementKey_stackView,
                            subviews: subviews)
    }

    private var stackConfig: CVStackViewConfig {
        CVStackViewConfig(axis: .vertical, alignment: .fill, spacing: Self.buttonSpacing, layoutMargins: .zero)
    }

    fileprivate static var buttonHeight: CGFloat { CVMessageActionButton.buttonHeight }
    fileprivate static let buttonSpacing: CGFloat = 1

    private static let measurementKey_stackView = "CVComponentBottomButtons.measurementKey_stackView"

    public func measure(maxWidth: CGFloat, measurementBuilder: CVCellMeasurement.Builder) -> CGSize {
        owsAssertDebug(maxWidth > 0)

        let subviewSize = CGSize(width: maxWidth, height: Self.buttonHeight)
        var subviewInfos = [ManualStackSubviewInfo]()
        for _ in 0 ..< actions.count {
            subviewInfos.append(subviewSize.asManualSubviewInfo)
        }
        let stackMeasurement = ManualStackView.measure(config: stackConfig,
                                                       measurementBuilder: measurementBuilder,
                                                       measurementKey: Self.measurementKey_stackView,
                                                       subviewInfos: subviewInfos,
                                                       maxWidth: maxWidth)
        return stackMeasurement.measuredSize
    }

    // MARK: - Events

    public override func handleTap(sender: UITapGestureRecognizer,
                                   componentDelegate: CVComponentDelegate,
                                   componentView: CVComponentView,
                                   renderItem: CVRenderItem) -> Bool {

        guard let componentView = componentView as? CVComponentViewBottomButtons else {
            owsFailDebug("Unexpected componentView.")
            return false
        }

        for buttonView in componentView.buttonViews {
            let location = sender.location(in: buttonView)
            guard buttonView.bounds.contains(location) else {
                continue
            }
            buttonView.action.perform(delegate: componentDelegate)
            return true
        }
        return false
    }

    // MARK: -

    // Used for rendering some portion of an Conversation View item.
    // It could be the entire item or some part thereof.
    public class CVComponentViewBottomButtons: NSObject, CVComponentView {

        fileprivate let stackView = ManualStackView(name: "bottomButtons")
        fileprivate var buttonViews = [CVMessageActionButton]()

        public var isDedicatedCellView = false

        public var rootView: UIView {
            stackView
        }

        public func setIsCellVisible(_ isCellVisible: Bool) {}

        public func reset() {
            stackView.reset()

            buttonViews.removeAll()
        }

    }
}
