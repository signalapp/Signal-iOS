//
// Copyright 2020 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import SignalCoreKit
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
            if !isIncoming || isDarkThemeEnabled {
                buttonView.backgroundColor = UIColor(white: 1, alpha: 0.16)
            } else {
                buttonView.backgroundColor = UIColor(white: 1, alpha: 0.8)
            }
            buttonView.textColor = conversationStyle.bubbleTextColor(isIncoming: isIncoming)
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
        CVStackViewConfig(
            axis: .vertical,
            alignment: .fill,
            spacing: Self.buttonSpacing,
            layoutMargins: .init(top: 6, leading: 12, bottom: 12, trailing: 12)
        )
    }

    fileprivate static var buttonHeight: CGFloat { CVMessageActionButton.buttonHeight }
    fileprivate static let buttonSpacing: CGFloat = 4

    private static let measurementKey_stackView = "CVComponentBottomButtons.measurementKey_stackView"

    public func measure(maxWidth: CGFloat, measurementBuilder: CVCellMeasurement.Builder) -> CGSize {
        owsAssertDebug(maxWidth > 0)

        let subviewSize = CGSize(width: maxWidth - stackConfig.layoutMargins.totalWidth, height: Self.buttonHeight)
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

    private class CVMessageActionButton: CVLabel {

        let action: CVMessageAction

        required init(action: CVMessageAction) {
            self.action = action

            super.init(frame: .zero)

            configure()
        }

        required init?(coder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }

        private func configure() {
            layoutMargins = .zero
            layer.masksToBounds = true
            layer.cornerRadius = 16
            text = action.title
            font = Self.buttonFont
            textAlignment = .center
        }

        private static var buttonFont: UIFont { UIFont.dynamicTypeBody2Clamped.medium() }

        private static let buttonVMargin: CGFloat = 6

        static var buttonHeight: CGFloat {
            ceil(buttonFont.lineHeight + buttonVMargin * 2).clamp(32, 44)
        }
    }

    private class CVComponentViewBottomButtons: NSObject, CVComponentView {

        let stackView = ManualStackView(name: "bottomButtons")
        var buttonViews = [CVMessageActionButton]()

        var isDedicatedCellView = false

        var rootView: UIView {
            stackView
        }

        func setIsCellVisible(_ isCellVisible: Bool) {}

        func reset() {
            stackView.reset()

            buttonViews.removeAll()
        }
    }
}
