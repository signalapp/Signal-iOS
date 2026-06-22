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

    override func wallpaperBlurView(componentView: CVComponentView) -> CVWallpaperBlurView? {
        guard let componentView = componentView as? CVComponentViewCollapseSet else {
            owsFailDebug("Unexpected componentView.")
            return nil
        }
        return componentView.wallpaperBlurView
    }

    func configureForRendering(
        componentView: CVComponentView,
        cellMeasurement: CVCellMeasurement,
        componentDelegate: CVComponentDelegate,
    ) {
        guard let componentView = componentView as? CVComponentViewCollapseSet else {
            owsFailDebug("Unexpected componentView.")
            componentView.reset()
            return
        }

        let hasWallpaper = conversationStyle.hasWallpaper
        let wallpaperModeHasChanged = hasWallpaper != componentView.hasWallpaper
        let isReusing = componentView.rootView.superview != nil
            && componentView.innerStack.superview != nil
            && !wallpaperModeHasChanged

        if !isReusing {
            componentView.reset()
        }

        componentView.hasWallpaper = hasWallpaper

        labelConfig.applyForRendering(label: componentView.label)
        chevronConfig.applyForRendering(label: componentView.chevronLabel)

        if isReusing {
            componentView.innerStack.configureForReuse(
                config: innerStackConfig,
                cellMeasurement: cellMeasurement,
                measurementKey: Self.measurementKey_innerStack,
            )
            componentView.outerStack.configureForReuse(
                config: outerStackConfig,
                cellMeasurement: cellMeasurement,
                measurementKey: Self.measurementKey_outerStack,
            )
        } else {
            componentView.innerStack.configure(
                config: innerStackConfig,
                cellMeasurement: cellMeasurement,
                measurementKey: Self.measurementKey_innerStack,
                subviews: [componentView.label, componentView.chevronContainer],
            )

            componentView.outerStack.configure(
                config: outerStackConfig,
                cellMeasurement: cellMeasurement,
                measurementKey: Self.measurementKey_outerStack,
                subviews: [componentView.innerStack],
            )

            let bubbleView: UIView
            if hasWallpaper {
                let wallpaperBlurView = componentView.ensureWallpaperBlurView()
                configureWallpaperBlurView(
                    wallpaperBlurView: wallpaperBlurView,
                    componentDelegate: componentDelegate,
                    bubbleConfig: BubbleConfiguration(
                        corners: .capsule(maxRadius: 16),
                        stroke: ConversationStyle.bubbleStroke(isDarkThemeEnabled: isDarkThemeEnabled),
                    ),
                )
                bubbleView = wallpaperBlurView
            } else {
                let solidBackgroundView = componentView.solidBackgroundView
                solidBackgroundView.layer.cornerRadius = 16
                solidBackgroundView.backgroundColor = .Signal.secondaryFill
                bubbleView = solidBackgroundView
            }
            componentView.outerStack.addSubview(bubbleView)
            componentView.outerStack.sendSubviewToBack(bubbleView)
            componentView.outerStack.addLayoutBlock { [innerStack = componentView.innerStack] _ in
                bubbleView.frame = innerStack.frame.inset(by: Self.backgroundLayoutInsets)
            }
            componentView.innerStack.addLayoutBlock { [chevronContainer = componentView.chevronContainer, chevronLabel = componentView.chevronLabel] _ in
                chevronLabel.bounds.size = chevronContainer.bounds.size
                chevronLabel.center = CGPoint(x: chevronContainer.bounds.midX, y: chevronContainer.bounds.midY)
            }
        }

        componentView.isShowingExpanded = collapseSet.isExpanded
        componentView.chevronLabel.transform = collapseSet.isExpanded
            ? CGAffineTransform(rotationAngle: -.pi)
            : .identity

        if
            hasWallpaper,
            let wallpaperBlurView = componentView.wallpaperBlurView
        {
            wallpaperBlurView.applyLayout()
            wallpaperBlurView.updateIfNecessary()
        }

        componentView.outerStack.isAccessibilityElement = true
        componentView.outerStack.accessibilityLabel = titleString
        componentView.outerStack.accessibilityTraits = .button
        componentView.outerStack.accessibilityHint = accessibilityHint(isExpanded: collapseSet.isExpanded)
    }

    // MARK: - Events

    override func handleTap(
        sender: UIGestureRecognizer,
        componentDelegate: CVComponentDelegate,
        componentView: CVComponentView,
        renderItem: CVRenderItem,
    ) -> Bool {
        if let componentView = componentView as? CVComponentViewCollapseSet {
            let wasExpanded = componentView.isShowingExpanded
            let willBeExpanded = !wasExpanded
            let expandedRotation: CGFloat = -.pi
            let isRTL = componentView.chevronLabel.effectiveUserInterfaceLayoutDirection == .rightToLeft

            let fromAngle: CGFloat
            let toAngle: CGFloat
            if willBeExpanded {
                fromAngle = 0
                toAngle = isRTL ? CGFloat.pi : -CGFloat.pi
            } else {
                fromAngle = expandedRotation
                toAngle = isRTL ? -2 * CGFloat.pi : 0
            }

            componentView.isShowingExpanded = willBeExpanded
            componentView.chevronLabel.transform = willBeExpanded
                ? CGAffineTransform(rotationAngle: expandedRotation)
                : .identity
            componentView.outerStack.accessibilityHint = accessibilityHint(isExpanded: willBeExpanded)

            let animation = CABasicAnimation(keyPath: "transform.rotation.z")
            animation.fromValue = fromAngle
            animation.toValue = toAngle
            animation.duration = 0.2
            animation.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            componentView.chevronLabel.layer.add(animation, forKey: "chevronRotation")
        }
        componentDelegate.didTapCollapseSet(collapseSetId: interaction.uniqueId)
        return true
    }

    // MARK: - Measurement

    fileprivate static let measurementKey_outerStack = "CVComponentCollapseSet.outerStack"
    fileprivate static let measurementKey_innerStack = "CVComponentCollapseSet.innerStack"

    func measure(maxWidth: CGFloat, measurementBuilder: CVCellMeasurement.Builder) -> CGSize {
        owsAssertDebug(maxWidth > 0)
        let availableWidth = max(
            0,
            maxWidth - outerStackConfig.layoutMargins.totalWidth,
        )
        let chevronSize = CVText.measureLabel(config: chevronConfig, maxWidth: availableWidth)
        let labelMaxWidth = max(0, availableWidth - chevronSize.width - innerStackConfig.spacing)
        let labelSize = CVText.measureLabel(config: labelConfig, maxWidth: labelMaxWidth)
        let innerMeasurement = ManualStackView.measure(
            config: innerStackConfig,
            measurementBuilder: measurementBuilder,
            measurementKey: Self.measurementKey_innerStack,
            subviewInfos: [
                labelSize.asManualSubviewInfo(hasFixedWidth: true),
                chevronSize.asManualSubviewInfo(hasFixedSize: true),
            ],
        )
        let outerMeasurement = ManualStackView.measure(
            config: outerStackConfig,
            measurementBuilder: measurementBuilder,
            measurementKey: Self.measurementKey_outerStack,
            subviewInfos: [innerMeasurement.measuredSize.asManualSubviewInfo(hasFixedWidth: true)],
        )
        return outerMeasurement.measuredSize
    }

    // MARK: - Layout

    private var innerStackConfig: CVStackViewConfig {
        CVStackViewConfig(
            axis: .horizontal,
            alignment: .center,
            spacing: 4,
            layoutMargins: .zero,
        )
    }

    private var outerStackConfig: CVStackViewConfig {
        CVStackViewConfig(
            axis: .vertical,
            alignment: .center,
            spacing: 0,
            layoutMargins: UIEdgeInsets(
                top: 4 + Self.labelContentInsets.top,
                leading: conversationStyle.fullWidthGutterLeading + Self.labelContentInsets.leading,
                bottom: 4 + Self.labelContentInsets.bottom,
                trailing: conversationStyle.fullWidthGutterTrailing + Self.labelContentInsets.trailing,
            ),
        )
    }

    private static var backgroundLayoutInsets: UIEdgeInsets {
        UIEdgeInsets(
            top: -labelContentInsets.top,
            leading: -labelContentInsets.leading,
            bottom: -labelContentInsets.bottom,
            trailing: -labelContentInsets.trailing,
        )
    }

    // MARK: - Content

    private var labelFont: UIFont { .dynamicTypeFootnote.medium() }

    private static var labelContentInsets: NSDirectionalEdgeInsets {
        NSDirectionalEdgeInsets(hMargin: 14, vMargin: 5)
    }

    private var leadingIcon: SignalSymbol {
        switch collapseSet.collapseSetType {
        case .chatUpdates: return itemModel.thread.isGroupThread ? .group : .thread
        case .callEvents: return .phone
        case .timerChanges: return .timer
        }
    }

    private var labelConfig: CVLabelConfig {
        CVLabelConfig(
            text: .attributedText(titleAttributedString),
            displayConfig: .forUnstyledText(font: labelFont, textColor: .Signal.label),
            font: labelFont,
            textColor: .Signal.label,
            numberOfLines: 0,
            lineBreakMode: .byWordWrapping,
            textAlignment: .center,
        )
    }

    private var titleAttributedString: NSAttributedString {
        let labelText = summaryLabel(
            count: collapseSet.collapsedInteractions.count,
            type: collapseSet.collapseSetType,
            finalTimerDescription: collapseSet.finalTimerDescription,
        )

        let nbsp = SignalSymbol.LeadingCharacter.nonBreakingSpace.rawValue

        let result = NSMutableAttributedString()
        result.append(leadingIcon.attributedString(
            for: .footnote,
            clamped: false,
            attributes: [.foregroundColor: UIColor.Signal.label],
        ))
        result.append(NSAttributedString(
            string: "\(nbsp)\(labelText)",
            attributes: [
                .font: labelFont,
                .foregroundColor: UIColor.Signal.label,
            ],
        ))
        return result
    }

    private var chevronConfig: CVLabelConfig {
        CVLabelConfig(
            text: .attributedText(chevronAttributedString),
            displayConfig: .forUnstyledText(font: labelFont, textColor: .Signal.label),
            font: labelFont,
            textColor: .Signal.label,
            numberOfLines: 1,
            lineBreakMode: .byClipping,
            textAlignment: .center,
        )
    }

    private var chevronAttributedString: NSAttributedString {
        SignalSymbol.chevronDown.attributedString(
            for: .footnote,
            clamped: false,
            attributes: [.foregroundColor: UIColor.Signal.label],
        )
    }

    private var titleString: String {
        summaryLabel(
            count: collapseSet.collapsedInteractions.count,
            type: collapseSet.collapseSetType,
            finalTimerDescription: collapseSet.finalTimerDescription,
        )
    }

    private func accessibilityHint(isExpanded: Bool) -> String {
        isExpanded
            ? OWSLocalizedString(
                "COLLAPSE_SET_ACCESSIBILITY_HINT_COLLAPSE",
                comment: "VoiceOver hint for an expanded collapse set button.",
            )
            : OWSLocalizedString(
                "COLLAPSE_SET_ACCESSIBILITY_HINT_EXPAND",
                comment: "VoiceOver hint for a collapsed collapse set button.",
            )
    }

    private func summaryLabel(
        count: Int,
        type: CollapseSetInteraction.MessagesType,
        finalTimerDescription: String? = nil,
    ) -> String {
        switch type {
        case .chatUpdates where itemModel.thread.isGroupThread:
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
            let finalTimer: String
            if let finalTimerDescription {
                finalTimer = finalTimerDescription
            } else {
                owsFailDebug("disappearing message timer collapse set does not have final timer description")
                finalTimer = ""
            }
            return String(
                format: OWSLocalizedString(
                    "COLLAPSE_SET_TIMER_CHANGES_WITH_FINAL_TIMER_%d",
                    tableName: "PluralAware",
                    comment: "Label for collapsed disappearing message timer changes showing the final timer value. Embeds {{number of events}} and {{timer description}}.",
                ),
                count,
                finalTimer,
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
        fileprivate let innerStack = ManualStackView(name: "collapseSet.innerStack")
        fileprivate let label = CVLabel()
        fileprivate let chevronContainer = UIView()
        fileprivate let chevronLabel = CVLabel()
        fileprivate let solidBackgroundView = UIView()

        fileprivate var isShowingExpanded = false

        fileprivate var wallpaperBlurView: CVWallpaperBlurView?
        fileprivate func ensureWallpaperBlurView() -> CVWallpaperBlurView {
            if let wallpaperBlurView = self.wallpaperBlurView {
                return wallpaperBlurView
            }
            let wallpaperBlurView = CVWallpaperBlurView()
            self.wallpaperBlurView = wallpaperBlurView
            return wallpaperBlurView
        }

        fileprivate var hasWallpaper = false

        var isDedicatedCellView = false

        var rootView: UIView { outerStack }

        override init() {
            super.init()
            chevronContainer.addSubview(chevronLabel)
        }

        func setIsCellVisible(_ isCellVisible: Bool) {}

        func reset() {
            label.reset()
            chevronLabel.reset()
            chevronLabel.transform = .identity
            chevronLabel.layer.removeAnimation(forKey: "chevronRotation")
            isShowingExpanded = false
            solidBackgroundView.backgroundColor = nil
            wallpaperBlurView?.removeFromSuperview()
            wallpaperBlurView = nil
            hasWallpaper = false
            innerStack.reset()
            outerStack.reset()
        }
    }
}
