//
// Copyright 2020 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

public class CVComponentSenderName: CVComponentBase, CVComponent {

    public var componentKey: CVComponentKey { .senderName }

    private let state: CVComponentState.SenderName
    private var senderName: NSAttributedString { state.senderName }
    private var senderNameColor: UIColor { state.senderNameColor }

    init(itemModel: CVItemModel, senderNameState: CVComponentState.SenderName) {
        self.state = senderNameState

        super.init(itemModel: itemModel)
    }

    public func buildComponentView(componentDelegate: CVComponentDelegate) -> CVComponentView {
        CVComponentViewSenderName()
    }

    private var bodyTextColor: UIColor {
        guard let message = interaction as? TSMessage else {
            return .black
        }
        return conversationStyle.bubbleTextColor(message: message)
    }

    public func configureForRendering(componentView componentViewParam: CVComponentView,
                                      cellMeasurement: CVCellMeasurement,
                                      componentDelegate: CVComponentDelegate) {
        guard let componentView = componentViewParam as? CVComponentViewSenderName else {
            owsFailDebug("Unexpected componentView.")
            componentViewParam.reset()
            return
        }

        let outerStack = componentView.outerStack
        let innerStack = componentView.innerStack
        let label = componentView.label

        outerStack.reset()
        innerStack.reset()

        if isBorderlessWithWallpaper {
            owsAssertDebug(isIncoming)
            let backgroundView = OWSLayerView.pillView()
            backgroundView.backgroundColor = itemModel.conversationStyle.bubbleColorIncoming
            innerStack.addSubviewToFillSuperviewEdges(backgroundView)
        }

        labelConfig.applyForRendering(label: label)

        innerStack.configure(config: innerStackConfig,
                            cellMeasurement: cellMeasurement,
                            measurementKey: Self.measurementKey_innerStack,
                            subviews: [ label ])
        outerStack.configure(config: outerStackConfig,
                            cellMeasurement: cellMeasurement,
                            measurementKey: Self.measurementKey_outerStack,
                            subviews: [ innerStack ])
    }

    private var isBorderlessWithWallpaper: Bool {
        return isBorderless && conversationStyle.hasWallpaper
    }

    private var labelConfig: CVLabelConfig {
        CVLabelConfig(attributedText: senderName,
                      font: UIFont.dynamicTypeFootnote.semibold(),
                      textColor: senderNameColor,
                      numberOfLines: 0,
                      lineBreakMode: .byWordWrapping)
    }

    private var outerStackConfig: CVStackViewConfig {
        CVStackViewConfig(axis: .vertical,
                          alignment: .leading,
                          spacing: 0,
                          layoutMargins: .zero)
    }

    private var innerStackConfig: CVStackViewConfig {
        let layoutMargins: UIEdgeInsets = (isBorderlessWithWallpaper
                                            ? UIEdgeInsets(hMargin: 12, vMargin: 3)
                                            : .zero)
        return CVStackViewConfig(axis: .vertical,
                                 alignment: .center,
                                 spacing: 0,
                                 layoutMargins: layoutMargins)
    }

    private static let measurementKey_outerStack = "CVComponentSenderName.measurementKey_outerStack"
    private static let measurementKey_innerStack = "CVComponentSenderName.measurementKey_innerStack"

    public func measure(maxWidth: CGFloat, measurementBuilder: CVCellMeasurement.Builder) -> CGSize {
        owsAssertDebug(maxWidth > 0)

        let maxWidth = maxWidth - (outerStackConfig.layoutMargins.totalWidth +
                                    innerStackConfig.layoutMargins.totalWidth)
        let labelSize = CVText.measureLabel(config: labelConfig, maxWidth: maxWidth)
        let labelInfo = labelSize.asManualSubviewInfo
        let innerStackMeasurement = ManualStackView.measure(config: innerStackConfig,
                                                       measurementBuilder: measurementBuilder,
                                                       measurementKey: Self.measurementKey_innerStack,
                                                       subviewInfos: [ labelInfo ])
        let innerStackInfo = innerStackMeasurement.measuredSize.asManualSubviewInfo
        let outerStackMeasurement = ManualStackView.measure(config: outerStackConfig,
                                                       measurementBuilder: measurementBuilder,
                                                       measurementKey: Self.measurementKey_outerStack,
                                                       subviewInfos: [ innerStackInfo ],
                                                       maxWidth: maxWidth)
        return outerStackMeasurement.measuredSize
    }

    // MARK: -

    // Used for rendering some portion of an Conversation View item.
    // It could be the entire item or some part thereof.
    public class CVComponentViewSenderName: NSObject, CVComponentView {

        fileprivate let label = CVLabel()

        fileprivate let outerStack = ManualStackView(name: "CVComponentViewSenderName.outerStack")
        fileprivate let innerStack = ManualStackView(name: "CVComponentViewSenderName.innerStack")

        public var isDedicatedCellView = false

        public var rootView: UIView {
            outerStack
        }

        public func setIsCellVisible(_ isCellVisible: Bool) {}

        public func reset() {
            outerStack.reset()
            innerStack.reset()

            label.text = nil
        }

    }
}
