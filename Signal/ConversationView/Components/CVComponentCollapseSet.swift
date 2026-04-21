//
// Copyright 2026 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import SignalServiceKit
import SignalUI

class CVComponentCollapseSet: CVComponentBase, CVRootComponent {

    var componentKey: CVComponentKey { .collapseSet }

    var cellReuseIdentifier: CVCellReuseIdentifier { .collapseSet }

    let isDedicatedCell = true

    private let collapseSet: CVComponentState.CollapseSet

    init(itemModel: CVItemModel, collapseSet: CVComponentState.CollapseSet) {
        self.collapseSet = collapseSet
        super.init(itemModel: itemModel)
    }

    // MARK: - CVRootComponent

    func configureCellRootComponent(
        cellView: UIView,
        cellMeasurement: CVCellMeasurement,
        componentDelegate: CVComponentDelegate,
        messageSwipeActionState: CVMessageSwipeActionState,
        componentView: CVComponentView,
    ) {
        Self.configureCellRootComponent(
            rootComponent: self,
            cellView: cellView,
            cellMeasurement: cellMeasurement,
            componentDelegate: componentDelegate,
            componentView: componentView,
        )
    }

    func buildComponentView(componentDelegate: CVComponentDelegate) -> CVComponentView {
        CVComponentViewCollapseSet()
    }

    func configureForRendering(
        componentView: CVComponentView,
        cellMeasurement: CVCellMeasurement,
        componentDelegate: CVComponentDelegate,
    ) {
        guard let componentView = componentView as? CVComponentViewCollapseSet else {
            owsFailDebug("Unexpected componentView.")
            return
        }

        let isReusing = componentView.rootView.superview != nil
            && componentView.button.superview != nil

        if !isReusing {
            componentView.reset()
        }

        // TODO: Add icons

        var config = UIButton.Configuration.gray()
        config.title = buttonTitleString
        config.baseForegroundColor = .Signal.label
        config.baseBackgroundColor = conversationStyle.hasWallpaper
            ? .Signal.MaterialBase.button
            : .Signal.secondaryFill
        config.contentInsets = buttonContentInsets
        config.titleTextAttributesTransformer = .defaultFont(buttonFont)
        componentView.button.configuration = config
        componentView.button.isUserInteractionEnabled = false

        if let buttonSize = cellMeasurement.size(key: Self.measurementKey_button) {
            componentView.button.layer.cornerRadius = buttonSize.height / 2
        }

        if isReusing {
            componentView.outerStack.configureForReuse(
                config: outerStackConfig,
                cellMeasurement: cellMeasurement,
                measurementKey: Self.measurementKey_outerStack,
            )
        } else {
            componentView.outerStack.configure(
                config: outerStackConfig,
                cellMeasurement: cellMeasurement,
                measurementKey: Self.measurementKey_outerStack,
                subviews: [componentView.button],
            )
        }

        componentView.outerStack.isAccessibilityElement = true
        componentView.outerStack.accessibilityLabel = buttonTitleString
        componentView.outerStack.accessibilityTraits = .button
        componentView.outerStack.accessibilityHint = collapseSet.isExpanded
            ? OWSLocalizedString(
                "COLLAPSE_SET_ACCESSIBILITY_HINT_COLLAPSE",
                comment: "VoiceOver hint for an expanded collapse set button.",
            )
            : OWSLocalizedString(
                "COLLAPSE_SET_ACCESSIBILITY_HINT_EXPAND",
                comment: "VoiceOver hint for a collapsed collapse set button.",
            )
    }

    // MARK: - Events

    override func handleTap(
        sender: UIGestureRecognizer,
        componentDelegate: CVComponentDelegate,
        componentView: CVComponentView,
        renderItem: CVRenderItem,
    ) -> Bool {
        componentDelegate.didTapCollapseSet(collapseSetId: interaction.uniqueId)
        return true
    }

    // MARK: - Measurement

    fileprivate static let measurementKey_outerStack = "CVComponentCollapseSet.outerStack"
    fileprivate static let measurementKey_button = "CVComponentCollapseSet.button"

    func measure(maxWidth: CGFloat, measurementBuilder: CVCellMeasurement.Builder) -> CGSize {
        owsAssertDebug(maxWidth > 0)
        let availableWidth = max(
            0,
            maxWidth - outerStackConfig.layoutMargins.totalWidth,
        )
        let labelSize = CVText.measureLabel(config: buttonLabelConfig, maxWidth: availableWidth)
        let buttonSize = labelSize + buttonContentInsets.asSize
        measurementBuilder.setSize(key: Self.measurementKey_button, size: buttonSize)
        let outerMeasurement = ManualStackView.measure(
            config: outerStackConfig,
            measurementBuilder: measurementBuilder,
            measurementKey: Self.measurementKey_outerStack,
            subviewInfos: [buttonSize.asManualSubviewInfo(hasFixedWidth: true)],
        )
        return outerMeasurement.measuredSize
    }

    // MARK: - Layout

    private var outerStackConfig: CVStackViewConfig {
        CVStackViewConfig(
            axis: .vertical,
            alignment: .center,
            spacing: 0,
            layoutMargins: UIEdgeInsets(
                top: 4,
                leading: conversationStyle.fullWidthGutterLeading,
                bottom: 4,
                trailing: conversationStyle.fullWidthGutterTrailing,
            ),
        )
    }

    // MARK: - Content

    private var buttonFont: UIFont { .dynamicTypeFootnote.medium() }

    private var buttonContentInsets: NSDirectionalEdgeInsets {
        NSDirectionalEdgeInsets(hMargin: 10, vMargin: 5)
    }

    private var buttonLabelConfig: CVLabelConfig {
        CVLabelConfig.unstyledText(
            buttonTitleString,
            font: buttonFont,
            textColor: .Signal.label,
            textAlignment: .center,
        )
    }

    private var buttonTitleString: String {
        var label = summaryLabel(
            count: collapseSet.collapsedInteractions.count,
            type: collapseSet.collapseSetType,
        )
        // TODO: Localize this more rigorously
        if let timerDesc = collapseSet.finalTimerDescription {
            label += " · " + timerDesc
        }
        // TODO: Use proper symbols
        let chevron = collapseSet.isExpanded ? "\u{25B4}" : "\u{25BE}" // ▴ or ▾
        return label + " " + chevron
    }

    private func summaryLabel(
        count: Int,
        type: CollapseSetInteraction.MessagesType,
    ) -> String {
        switch type {
        case .groupUpdates:
            return String(
                format: OWSLocalizedString(
                    "COLLAPSE_SET_GROUP_UPDATES_%d",
                    tableName: "PluralAware",
                    comment: "Label for a collapsed group of group update events. Embeds {{number of events}}.",
                ),
                count,
            )
        case .chatUpdates:
            return String(
                format: OWSLocalizedString(
                    "COLLAPSE_SET_CHAT_UPDATES_%d",
                    tableName: "PluralAware",
                    comment: "Label for a collapsed group of chat update events. Embeds {{number of events}}.",
                ),
                count,
            )
        case .timerChanges:
            return String(
                format: OWSLocalizedString(
                    "COLLAPSE_SET_TIMER_CHANGES_%d",
                    tableName: "PluralAware",
                    comment: "Label for a collapsed group of disappearing message timer changes. Embeds {{number of events}}.",
                ),
                count,
            )
        case .callEvents:
            return String(
                format: OWSLocalizedString(
                    "COLLAPSE_SET_CALL_EVENTS_%d",
                    tableName: "PluralAware",
                    comment: "Label for a collapsed group of call events. Embeds {{number of events}}.",
                ),
                count,
            )
        }
    }

    // MARK: - CVComponentViewCollapseSet

    class CVComponentViewCollapseSet: NSObject, CVComponentView {

        fileprivate let outerStack = ManualStackView(name: "collapseSet.outerStack")
        fileprivate let button = UIButton(configuration: .gray())

        var isDedicatedCellView = false

        var rootView: UIView { outerStack }

        func setIsCellVisible(_ isCellVisible: Bool) {}

        func reset() {
            button.configuration?.title = nil
            outerStack.reset()
        }
    }
}
