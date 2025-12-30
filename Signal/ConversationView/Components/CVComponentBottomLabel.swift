//
// Copyright 2020 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import SignalServiceKit
public import SignalUI

public class CVComponentBottomLabel: CVComponentBase, CVComponent {
    public var componentKey: CVComponentKey { .bottomLabel }
    private let bottomLabelState: String

    init(itemModel: CVItemModel, bottomLabelState: String) {
        self.bottomLabelState = bottomLabelState

        super.init(itemModel: itemModel)
    }

    private static let measurementKey_stackView = "CVComponentBottomLabel.measurementKey_stackView"

    private var stackConfig: CVStackViewConfig {
        CVStackViewConfig(
            axis: .horizontal,
            alignment: .center,
            spacing: 0,
            layoutMargins: .init(top: 0, leading: 0, bottom: 24, trailing: 0),
        )
    }

    var bottomLabelConfig: CVLabelConfig {
        return CVLabelConfig.unstyledText(
            bottomLabelState,
            font: UIFont.dynamicTypeFootnote,
            textColor: conversationStyle.bubbleTextColor(isIncoming: isIncoming),
            numberOfLines: 0,
            lineBreakMode: .byWordWrapping,
            textAlignment: .center,
        )
    }

    public func buildComponentView(componentDelegate: CVComponentDelegate) -> CVComponentView {
        CVComponentViewBottomLabel()
    }

    public func configureForRendering(
        componentView componentViewParam: CVComponentView,
        cellMeasurement: CVCellMeasurement,
        componentDelegate: CVComponentDelegate,
    ) {
        guard let componentView = componentViewParam as? CVComponentViewBottomLabel else {
            owsFailDebug("Unexpected componentView.")
            componentViewParam.reset()
            return
        }

        componentView.reset()

        let label = CVLabel()
        bottomLabelConfig.applyForRendering(label: label)

        let stackView = componentView.stackView
        stackView.reset()
        stackView.configure(
            config: stackConfig,
            cellMeasurement: cellMeasurement,
            measurementKey: Self.measurementKey_stackView,
            subviews: [label],
        )
    }

    public func measure(maxWidth: CGFloat, measurementBuilder: CVCellMeasurement.Builder) -> CGSize {
        owsAssertDebug(maxWidth > 0)

        let bottomLabelSize = CVText.measureLabel(
            config: bottomLabelConfig,
            maxWidth: maxWidth,
        )
        let stackMeasurement = ManualStackView.measure(
            config: stackConfig,
            measurementBuilder: measurementBuilder,
            measurementKey: Self.measurementKey_stackView,
            subviewInfos: [bottomLabelSize.asManualSubviewInfo],
            maxWidth: maxWidth,
        )

        return stackMeasurement.measuredSize
    }

    private class CVComponentViewBottomLabel: NSObject, CVComponentView {

        let stackView = ManualStackView(name: "bottomLabel")

        var isDedicatedCellView = false

        var rootView: UIView {
            stackView
        }

        func setIsCellVisible(_ isCellVisible: Bool) {}

        func reset() {
            stackView.reset()
        }
    }
}
