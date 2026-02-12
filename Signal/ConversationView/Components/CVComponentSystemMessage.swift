//
// Copyright 2020 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import LibSignalClient
import SignalServiceKit
public import SignalUI

public class CVComponentSystemMessage: CVComponentBase, CVRootComponent {

    public var componentKey: CVComponentKey { .systemMessage }

    public var cellReuseIdentifier: CVCellReuseIdentifier {
        CVCellReuseIdentifier.systemMessage
    }

    public let isDedicatedCell = true

    private let systemMessage: CVComponentState.SystemMessage

    typealias Action = CVMessageAction
    fileprivate var action: Action? { systemMessage.action }
    fileprivate var expiration: CVComponentState.SystemMessage.Expiration? { systemMessage.expiration }

    init(itemModel: CVItemModel, systemMessage: CVComponentState.SystemMessage) {
        self.systemMessage = systemMessage

        super.init(itemModel: itemModel)
    }

    public func configureCellRootComponent(
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

    private var bubbleBackgroundColor: UIColor {
        Theme.backgroundColor
    }

    private var outerHStackConfig: CVStackViewConfig {
        let cellLayoutMargins = UIEdgeInsets(
            top: 0,
            leading: conversationStyle.fullWidthGutterLeading,
            bottom: 0,
            trailing: conversationStyle.fullWidthGutterTrailing,
        )
        return CVStackViewConfig(
            axis: .horizontal,
            alignment: .fill,
            spacing: ConversationStyle.messageStackSpacing,
            layoutMargins: cellLayoutMargins,
        )
    }

    private var innerHStackConfig: CVStackViewConfig {
        return CVStackViewConfig(
            axis: .horizontal,
            alignment: .center,
            spacing: 4,
            layoutMargins: .zero,
        )
    }

    private var innerVStackConfig: CVStackViewConfig {

        let layoutMargins: UIEdgeInsets
        if itemModel.itemViewState.isFirstInCluster {
            layoutMargins = UIEdgeInsets(hMargin: 10, vMargin: 10)
        } else {
            layoutMargins = UIEdgeInsets(top: 0, left: 10, bottom: 10, right: 10)
        }

        return CVStackViewConfig(
            axis: .vertical,
            alignment: .center,
            spacing: 12,
            layoutMargins: layoutMargins,
        )
    }

    private var outerVStackConfig: CVStackViewConfig {
        return CVStackViewConfig(
            axis: .vertical,
            alignment: .center,
            spacing: 0,
            layoutMargins: .zero,
        )
    }

    override public func wallpaperBlurView(componentView: CVComponentView) -> CVWallpaperBlurView? {
        guard let componentView = componentView as? CVComponentViewSystemMessage else {
            owsFailDebug("Unexpected componentView.")
            return nil
        }
        return componentView.wallpaperBlurView
    }

    public func buildComponentView(componentDelegate: CVComponentDelegate) -> CVComponentView {
        CVComponentViewSystemMessage()
    }

    public func configureForRendering(
        componentView: CVComponentView,
        cellMeasurement: CVCellMeasurement,
        componentDelegate: CVComponentDelegate,
    ) {
        guard let componentView = componentView as? CVComponentViewSystemMessage else {
            owsFailDebug("Unexpected componentView.")
            return
        }

        let themeHasChanged = conversationStyle.isDarkThemeEnabled != componentView.isDarkThemeEnabled
        let hasWallpaper = conversationStyle.hasWallpaper
        let wallpaperModeHasChanged = hasWallpaper != componentView.hasWallpaper
        let isFirstInCluster = itemModel.itemViewState.isFirstInCluster
        let isLastInCluster = itemModel.itemViewState.isLastInCluster
        let hasClusteringChanges = (
            componentView.isFirstInCluster != isFirstInCluster ||
                componentView.isLastInCluster != isLastInCluster,
        )
        let hasSelectionChanges = (
            componentView.isShowingSelectionUI != isShowingSelectionUI ||
                componentView.wasShowingSelectionUI != wasShowingSelectionUI,
        )
        var hasActionButton = false
        if
            nil != action,
            !itemViewState.shouldCollapseSystemMessageAction,
            nil != cellMeasurement.size(key: Self.measurementKey_buttonSize)
        {
            hasActionButton = true
        }

        let isReusing = (
            componentView.rootView.superview != nil &&
                !themeHasChanged &&
                !wallpaperModeHasChanged &&
                !hasClusteringChanges &&
                !hasSelectionChanges &&
                !hasActionButton &&
                !componentView.hasActionButton,
        )
        if !isReusing {
            componentView.reset(resetReusableState: true)
        }

        componentView.isDarkThemeEnabled = conversationStyle.isDarkThemeEnabled
        componentView.hasWallpaper = hasWallpaper
        componentView.isFirstInCluster = isFirstInCluster
        componentView.isLastInCluster = isLastInCluster
        componentView.isShowingSelectionUI = isShowingSelectionUI
        componentView.wasShowingSelectionUI = wasShowingSelectionUI
        componentView.hasActionButton = hasActionButton

        let innerHStack = componentView.innerHStack
        let outerHStack = componentView.outerHStack
        let innerVStack = componentView.innerVStack
        let outerVStack = componentView.outerVStack
        let selectionView = componentView.selectionView
        let textLabel = componentView.textLabel
        let messageTimerView = componentView.messageTimerView

        // Configuring the text label should happen in both reuse and non-reuse
        // scenarios
        textLabel.configureForRendering(config: textLabelConfig, spoilerAnimationManager: componentDelegate.spoilerState.animationManager)
        componentView.innerHStack.accessibilityLabel = textLabelConfig.text.accessibilityDescription
        componentView.innerHStack.isAccessibilityElement = true

        if let expiration {
            messageTimerView.configure(
                expirationTimestampMs: expiration.expirationTimestamp,
                disappearingMessageInterval: expiration.expiresInSeconds,
                tintColor: systemMessage.titleColor,
            )
        }

        if isReusing {
            innerHStack.configureForReuse(
                config: innerHStackConfig,
                cellMeasurement: cellMeasurement,
                measurementKey: Self.measurementKey_innerHStack,
            )
            innerVStack.configureForReuse(
                config: innerVStackConfig,
                cellMeasurement: cellMeasurement,
                measurementKey: Self.measurementKey_innerVStack,
            )
            outerVStack.configureForReuse(
                config: outerVStackConfig,
                cellMeasurement: cellMeasurement,
                measurementKey: Self.measurementKey_outerVStack,
            )
            outerHStack.configureForReuse(
                config: outerHStackConfig,
                cellMeasurement: cellMeasurement,
                measurementKey: Self.measurementKey_outerHStack,
            )

            if
                hasWallpaper,
                let wallpaperBlurView = componentView.wallpaperBlurView
            {
                wallpaperBlurView.applyLayout()
                wallpaperBlurView.updateIfNecessary()
            }
        } else {
            var innerHStackViews: [UIView] = [
                textLabel.view,
            ]

            if expiration != nil {
                innerHStackViews.append(messageTimerView)
            }

            var innerVStackViews: [UIView] = [
                innerHStack,
            ]
            let outerVStackViews = [
                innerVStack,
            ]
            var outerHStackViews = [UIView]()
            if isShowingSelectionUI || wasShowingSelectionUI {
                // System messages cannot be partially selected.
                selectionView.isSelected = componentDelegate.selectionState.hasAnySelection(interaction: interaction)
                selectionView.updateStyle(conversationStyle: conversationStyle)
                outerHStackViews.append(selectionView)
            }
            outerHStackViews.append(contentsOf: [
                UIView.transparentSpacer(),
                outerVStack,
                UIView.transparentSpacer(),
            ])

            if
                let action,
                !itemViewState.shouldCollapseSystemMessageAction,
                let actionButtonSize = cellMeasurement.size(key: Self.measurementKey_buttonSize)
            {

                let buttonLabelConfig = self.buttonLabelConfig(action: action)
                let button = OWSButton(title: action.title) {}
                componentView.button = button
                button.accessibilityIdentifier = action.accessibilityIdentifier
                button.titleLabel?.textAlignment = .center
                button.titleLabel?.font = buttonLabelConfig.font
                button.setTitleColor(buttonLabelConfig.textColor, for: .normal)
                if interaction is OWSGroupCallMessage {
                    button.backgroundColor = UIColor.ows_accentGreen
                } else {
                    if isDarkThemeEnabled, hasWallpaper {
                        button.backgroundColor = .ows_gray65
                    } else {
                        button.backgroundColor = Theme.conversationButtonBackgroundColor
                    }

                    switch action.action {
                    case .didTapActivatePayments, .didTapSendPayment:
                        button.layer.borderColor = UIColor.Signal.opaqueSeparator.cgColor
                        button.layer.borderWidth = 1.5
                    default: break
                    }
                }
                button.ows_contentEdgeInsets = buttonContentEdgeInsets
                button.layer.cornerRadius = actionButtonSize.height / 2
                button.isUserInteractionEnabled = false
                innerVStackViews.append(button)
            }

            innerHStack.configure(
                config: innerHStackConfig,
                cellMeasurement: cellMeasurement,
                measurementKey: Self.measurementKey_innerHStack,
                subviews: innerHStackViews,
            )
            innerVStack.configure(
                config: innerVStackConfig,
                cellMeasurement: cellMeasurement,
                measurementKey: Self.measurementKey_innerVStack,
                subviews: innerVStackViews,
            )
            outerVStack.configure(
                config: outerVStackConfig,
                cellMeasurement: cellMeasurement,
                measurementKey: Self.measurementKey_outerVStack,
                subviews: outerVStackViews,
            )
            outerHStack.configure(
                config: outerHStackConfig,
                cellMeasurement: cellMeasurement,
                measurementKey: Self.measurementKey_outerHStack,
                subviews: outerHStackViews,
            )

            let bubbleView: UIView

            if hasWallpaper {
                let wallpaperBlurView = componentView.ensureWallpaperBlurView()
                configureWallpaperBlurView(
                    wallpaperBlurView: wallpaperBlurView,
                    componentDelegate: componentDelegate,
                )
                bubbleView = wallpaperBlurView
            } else {
                let backgroundView = UIView()
                backgroundView.backgroundColor = Theme.backgroundColor
                componentView.backgroundView = backgroundView
                bubbleView = backgroundView
            }

            if isFirstInCluster, isLastInCluster {
                innerVStack.addSubviewToFillSuperviewEdges(bubbleView)
                innerVStack.sendSubviewToBack(bubbleView)

                bubbleView.layer.cornerRadius = 8
                bubbleView.layer.maskedCorners = .all
                bubbleView.clipsToBounds = true
            } else {
                outerVStack.addSubviewToFillSuperviewEdges(bubbleView)
                outerVStack.sendSubviewToBack(bubbleView)

                if isFirstInCluster {
                    bubbleView.layer.cornerRadius = 12
                    bubbleView.layer.maskedCorners = [.layerMaxXMinYCorner, .layerMinXMinYCorner]
                    bubbleView.clipsToBounds = true
                } else if isLastInCluster {
                    bubbleView.layer.cornerRadius = 12
                    bubbleView.layer.maskedCorners = [.layerMaxXMaxYCorner, .layerMinXMaxYCorner]
                    bubbleView.clipsToBounds = true
                }
            }
        }

        // Configure hOuterStack/hInnerStack animations animations
        if isShowingSelectionUI || wasShowingSelectionUI {
            // Configure selection animations
            let selectionViewWidth = ConversationStyle.selectionViewWidth
            let layoutMargins = CurrentAppContext().isRTL ? outerHStackConfig.layoutMargins.right : outerHStackConfig.layoutMargins.left
            let selectionOffset = -(layoutMargins + selectionViewWidth)
            let outerVStackOffset = -(outerHStackConfig.spacing + selectionViewWidth - layoutMargins)
            if isShowingSelectionUI, !wasShowingSelectionUI { // Animate in
                selectionView.addTransformBlock { view in
                    let animation = CABasicAnimation(keyPath: "transform.translation.x")
                    animation.fromValue = selectionOffset
                    animation.toValue = 0
                    animation.duration = CVComponentMessage.selectionAnimationDuration
                    animation.timingFunction = CAMediaTimingFunction(name: CAMediaTimingFunctionName.easeInEaseOut)
                    view.layer.add(animation, forKey: "insert")
                }

                outerVStack.addTransformBlock { view in
                    let animation = CABasicAnimation(keyPath: "transform.translation.x")
                    animation.fromValue = outerVStackOffset
                    animation.toValue = 0
                    animation.duration = CVComponentMessage.selectionAnimationDuration
                    animation.timingFunction = CAMediaTimingFunction(name: CAMediaTimingFunctionName.easeInEaseOut)
                    view.layer.add(animation, forKey: "insert")
                }
            } else if !isShowingSelectionUI, wasShowingSelectionUI { // Animate out
                selectionView.addTransformBlock { view in
                    let animation = CABasicAnimation(keyPath: "transform.translation.x")
                    animation.fromValue = 0
                    animation.toValue = selectionOffset
                    animation.duration = CVComponentMessage.selectionAnimationDuration
                    animation.isRemovedOnCompletion = false
                    animation.repeatCount = 0
                    animation.fillMode = CAMediaTimingFillMode.forwards
                    animation.timingFunction = CAMediaTimingFunction(name: CAMediaTimingFunctionName.easeInEaseOut)
                    view.layer.add(animation, forKey: "remove")
                }

                outerVStack.addTransformBlock { view in
                    let animation = CABasicAnimation(keyPath: "transform.translation.x")
                    animation.fromValue = 0
                    animation.toValue = outerVStackOffset
                    animation.duration = CVComponentMessage.selectionAnimationDuration
                    animation.isRemovedOnCompletion = false
                    animation.repeatCount = 0
                    animation.fillMode = CAMediaTimingFillMode.forwards
                    animation.timingFunction = CAMediaTimingFunction(name: CAMediaTimingFunctionName.easeInEaseOut)
                    view.layer.add(animation, forKey: "remove")
                }
            }
        } else {
            // Remove outstanding animations if needed
            let selectionView = componentView.selectionView
            selectionView.invalidateTransformBlocks()
            outerVStack.invalidateTransformBlocks()
        }

        outerHStack.applyTransformBlocks()
    }

    private var textLabelConfig: CVTextLabel.Config {
        let selectionStyling: [NSAttributedString.Key: Any] = [
            .backgroundColor: systemMessage.titleSelectionBackgroundColor,
        ]

        return CVTextLabel.Config(
            text: .attributedText(systemMessage.title),
            displayConfig: .forUnstyledText(font: Self.textLabelFont, textColor: systemMessage.titleColor),
            font: Self.textLabelFont,
            textColor: systemMessage.titleColor,
            selectionStyling: selectionStyling,
            textAlignment: .center,
            lineBreakMode: .byWordWrapping,
            items: systemMessage.namesInTitle.map { .referencedUser(referencedUserItem: $0) },
            linkifyStyle: .underlined(bodyTextColor: systemMessage.titleColor),
        )
    }

    private func buttonLabelConfig(action: Action) -> CVLabelConfig {
        let textColor: UIColor
        if interaction is OWSGroupCallMessage {
            textColor = Theme.isDarkThemeEnabled ? .ows_whiteAlpha90 : .white
        } else {
            textColor = Theme.conversationButtonTextColor
        }
        return CVLabelConfig.unstyledText(
            action.title,
            font: UIFont.dynamicTypeFootnote.semibold(),
            textColor: textColor,
            textAlignment: .center,
        )
    }

    private var buttonContentEdgeInsets: UIEdgeInsets {
        UIEdgeInsets(hMargin: 12, vMargin: 6)
    }

    private static var textLabelFont: UIFont {
        UIFont.dynamicTypeFootnote
    }

    private static let measurementKey_innerHStack = "CVComponentSystemMessage.measurementKey_innerHStack"
    private static let measurementKey_outerHStack = "CVComponentSystemMessage.measurementKey_outerHStack"
    private static let measurementKey_innerVStack = "CVComponentSystemMessage.measurementKey_innerVStack"
    private static let measurementKey_outerVStack = "CVComponentSystemMessage.measurementKey_outerVStack"
    private static let measurementKey_buttonSize = "CVComponentSystemMessage.measurementKey_buttonSize"

    public func measure(maxWidth: CGFloat, measurementBuilder: CVCellMeasurement.Builder) -> CGSize {
        owsAssertDebug(maxWidth > 0)

        var maxContentWidth = (
            maxWidth -
                (
                    outerHStackConfig.layoutMargins.totalWidth +
                        outerVStackConfig.layoutMargins.totalWidth +
                        innerVStackConfig.layoutMargins.totalWidth
                ),
        )

        let selectionViewSize = CGSize(width: ConversationStyle.selectionViewWidth, height: 0)
        if isShowingSelectionUI || wasShowingSelectionUI {
            // Account for selection UI when doing measurement.
            maxContentWidth -= selectionViewSize.width + outerHStackConfig.spacing
        }

        // Padding around the outerVStack (leading and trailing side)
        maxContentWidth -= (outerHStackConfig.spacing + minBubbleHMargin) * 2

        maxContentWidth = max(0, maxContentWidth)

        let textSize = CVTextLabel.measureSize(
            config: textLabelConfig,
            maxWidth: maxContentWidth,
        )

        var innerHStackSubviewInfos = [ManualStackSubviewInfo]()
        innerHStackSubviewInfos.append(textSize.size.asManualSubviewInfo)

        if let infoMessage = interaction as? TSInfoMessage, infoMessage.hasPerConversationExpiration {
            let timerSize = MessageTimerView.measureSize
            innerHStackSubviewInfos.append(timerSize.asManualSubviewInfo(hasFixedWidth: true))
        }

        let innerHStackMeasurement = ManualStackView.measure(
            config: innerHStackConfig,
            measurementBuilder: measurementBuilder,
            measurementKey: Self.measurementKey_innerHStack,
            subviewInfos: innerHStackSubviewInfos,
        )

        var innerVStackSubviewInfos = [ManualStackSubviewInfo]()
        innerVStackSubviewInfos.append(innerHStackMeasurement.measuredSize.asManualSubviewInfo)
        if let action, !itemViewState.shouldCollapseSystemMessageAction {
            let buttonLabelConfig = self.buttonLabelConfig(action: action)
            let actionButtonSize = (
                CVText.measureLabel(
                    config: buttonLabelConfig,
                    maxWidth: maxContentWidth,
                ) +
                    buttonContentEdgeInsets.asSize,
            )
            measurementBuilder.setSize(key: Self.measurementKey_buttonSize, size: actionButtonSize)
            innerVStackSubviewInfos.append(actionButtonSize.asManualSubviewInfo(hasFixedSize: true))
        }
        let innerVStackMeasurement = ManualStackView.measure(
            config: innerVStackConfig,
            measurementBuilder: measurementBuilder,
            measurementKey: Self.measurementKey_innerVStack,
            subviewInfos: innerVStackSubviewInfos,
        )

        let outerVStackSubviewInfos: [ManualStackSubviewInfo] = [
            innerVStackMeasurement.measuredSize.asManualSubviewInfo,
        ]
        let outerVStackMeasurement = ManualStackView.measure(
            config: outerVStackConfig,
            measurementBuilder: measurementBuilder,
            measurementKey: Self.measurementKey_outerVStack,
            subviewInfos: outerVStackSubviewInfos,
        )

        var outerHStackSubviewInfos = [ManualStackSubviewInfo]()
        if isShowingSelectionUI || wasShowingSelectionUI {
            outerHStackSubviewInfos.append(selectionViewSize.asManualSubviewInfo(hasFixedWidth: true))
        }
        outerHStackSubviewInfos.append(contentsOf: [
            CGSize(width: minBubbleHMargin, height: 0).asManualSubviewInfo(hasFixedWidth: true),
            outerVStackMeasurement.measuredSize.asManualSubviewInfo,
            CGSize(width: minBubbleHMargin, height: 0).asManualSubviewInfo(hasFixedWidth: true),
        ])
        let outerHStackMeasurement = ManualStackView.measure(
            config: outerHStackConfig,
            measurementBuilder: measurementBuilder,
            measurementKey: Self.measurementKey_outerHStack,
            subviewInfos: outerHStackSubviewInfos,
            maxWidth: maxWidth,
        )
        return outerHStackMeasurement.measuredSize
    }

    private let minBubbleHMargin: CGFloat = 4

    // MARK: - Events

    override public func handleTap(
        sender: UIGestureRecognizer,
        componentDelegate: CVComponentDelegate,
        componentView: CVComponentView,
        renderItem: CVRenderItem,
    ) -> Bool {

        guard let componentView = componentView as? CVComponentViewSystemMessage else {
            owsFailDebug("Unexpected componentView.")
            return false
        }

        if isShowingSelectionUI {
            let selectionView = componentView.selectionView
            // System messages cannot be partially selected.
            let selectionState = componentDelegate.selectionState
            if selectionState.hasAnySelection(interaction: interaction) {
                selectionView.isSelected = false
                selectionState.remove(interaction: interaction, hasRenderableContent: true, selectionType: .allContent)
            } else {
                selectionView.isSelected = true
                selectionState.add(interaction: interaction, hasRenderableContent: true, selectionType: .allContent)
            }
            // Suppress other tap handling during selection mode.
            return true
        }

        if
            let action = systemMessage.action,
            let actionButton = componentView.button,
            actionButton.containsGestureLocation(sender)
        {
            action.action.perform(delegate: componentDelegate)
            return true
        }

        if let item = componentView.textLabel.itemForGesture(sender: sender) {
            componentView.textLabel.animate(selectedItem: item)
            componentDelegate.didTapSystemMessageItem(item)
            return true
        }

        return false
    }

    override public func findLongPressHandler(
        sender: UIGestureRecognizer,
        componentDelegate: CVComponentDelegate,
        componentView: CVComponentView,
        renderItem: CVRenderItem,
    ) -> CVLongPressHandler? {
        return CVLongPressHandler(
            delegate: componentDelegate,
            renderItem: renderItem,
            gestureLocation: .systemMessage,
        )
    }

    // MARK: -

    // Used for rendering some portion of an Conversation View item.
    // It could be the entire item or some part thereof.
    public class CVComponentViewSystemMessage: NSObject, CVComponentView {

        fileprivate let innerHStack = ManualStackView(name: "systemMessage.innerHStack")
        fileprivate let outerHStack = ManualStackView(name: "systemMessage.outerHStack")
        fileprivate let innerVStack = ManualStackView(name: "systemMessage.innerVStack")
        fileprivate let outerVStack = ManualStackView(name: "systemMessage.outerVStack")
        fileprivate let selectionView = MessageSelectionView()
        fileprivate let messageTimerView = MessageTimerView()

        fileprivate var wallpaperBlurView: CVWallpaperBlurView?
        fileprivate func ensureWallpaperBlurView() -> CVWallpaperBlurView {
            if let wallpaperBlurView = self.wallpaperBlurView {
                return wallpaperBlurView
            }
            let wallpaperBlurView = CVWallpaperBlurView()
            self.wallpaperBlurView = wallpaperBlurView
            return wallpaperBlurView
        }

        fileprivate var backgroundView: UIView?

        public let textLabel = CVTextLabel()
        public fileprivate(set) var button: OWSButton?

        fileprivate var hasWallpaper = false
        fileprivate var isDarkThemeEnabled = false
        fileprivate var isFirstInCluster = false
        fileprivate var isLastInCluster = false

        public var isDedicatedCellView = false

        public var isShowingSelectionUI = false
        public var wasShowingSelectionUI = false
        public var hasActionButton = false

        public var rootView: UIView {
            outerHStack
        }

        // MARK: -

        public func setIsCellVisible(_ isCellVisible: Bool) {}

        public func reset() {
            reset(resetReusableState: false)
        }

        public func reset(resetReusableState: Bool) {
            owsAssertDebug(isDedicatedCellView)

            if resetReusableState {
                outerHStack.reset()
                innerVStack.reset()
                outerVStack.reset()
                innerHStack.reset()
                textLabel.reset()

                messageTimerView.prepareForReuse()
                messageTimerView.removeFromSuperview()

                wallpaperBlurView?.removeFromSuperview()
                wallpaperBlurView = nil

                backgroundView?.removeFromSuperview()
                backgroundView = nil

                hasWallpaper = false
                isDarkThemeEnabled = false
                isFirstInCluster = false
                isLastInCluster = false
                isShowingSelectionUI = false
                wasShowingSelectionUI = false
                hasActionButton = false
            }

            button?.removeFromSuperview()
            button = nil
        }
    }
}

// MARK: -

extension CVComponentSystemMessage {

    static func buildComponentState(
        title: NSAttributedString,
        action: Action?,
        expiration: CVComponentState.SystemMessage.Expiration?,
        titleColor: UIColor? = nil,
        titleSelectionBackgroundColor: UIColor? = nil,
    ) -> CVComponentState.SystemMessage {
        return CVComponentState.SystemMessage(
            title: title,
            titleColor: titleColor ?? defaultTextColor,
            titleSelectionBackgroundColor: titleSelectionBackgroundColor ?? defaultSelectionBackgroundColor,
            action: action,
            expiration: expiration,
        )
    }

    static func buildComponentState(
        interaction: TSInteraction,
        threadViewModel: ThreadViewModel,
        currentGroupThreadCallGroupId: GroupIdentifier?,
        transaction: DBReadTransaction,
    ) -> CVComponentState.SystemMessage {

        let title = Self.title(forInteraction: interaction, transaction: transaction)
        let maybeOverrideTitleColor = Self.overrideTextColor(forInteraction: interaction)
        let action = Self.action(
            forInteraction: interaction,
            threadViewModel: threadViewModel,
            currentGroupThreadCallGroupId: currentGroupThreadCallGroupId,
            transaction: transaction,
        )
        let expiration = Self.expiration(forInteraction: interaction, transaction: transaction)

        return buildComponentState(title: title, action: action, expiration: expiration, titleColor: maybeOverrideTitleColor)
    }

    private static func title(
        forInteraction interaction: TSInteraction,
        transaction: DBReadTransaction,
    ) -> NSAttributedString {

        let font = Self.textLabelFont
        let labelText = NSMutableAttributedString()

        func applyParagraphStyling() {
            let paragraphStyle = NSMutableParagraphStyle()
            paragraphStyle.paragraphSpacing = 12
            paragraphStyle.alignment = .center
            labelText.addAttributeToEntireString(.paragraphStyle, value: paragraphStyle)
        }

        if
            let infoMessage = interaction as? TSInfoMessage,
            infoMessage.messageType == .typeGroupUpdate,
            let localIdentifiers = DependenciesBridge.shared.tsAccountManager.localIdentifiers(
                tx: transaction,
            ),
            let displayableGroupUpdates = infoMessage.displayableGroupUpdateItems(
                localIdentifiers: localIdentifiers,
                tx: transaction,
            ),
            !displayableGroupUpdates.isEmpty
        {

            for (index, updateItem) in displayableGroupUpdates.enumerated() {
                labelText.appendTemplatedImage(
                    named: Self.iconName(displayableGroupUpdateItem: updateItem),
                    font: font,
                    heightReference: ImageAttachmentHeightReference.lineHeight,
                )

                labelText.append("  ", attributes: [:])
                labelText.append(updateItem.localizedText)

                let isLast = index == displayableGroupUpdates.count - 1
                if !isLast {
                    labelText.append("\n", attributes: [:])
                }
            }

            if displayableGroupUpdates.count > 1 {
                applyParagraphStyling()
            }

            return labelText
        }

        if let icon = icon(forInteraction: interaction) {
            labelText.appendImage(
                icon.withRenderingMode(.alwaysTemplate),
                font: font,
                heightReference: ImageAttachmentHeightReference.lineHeight,
            )
            labelText.append("  ", attributes: [:])
        }

        let systemMessageText = Self.systemMessageText(
            forInteraction: interaction,
            transaction: transaction,
        )

        owsAssertDebug(!systemMessageText.isEmpty)
        labelText.append(systemMessageText)

        let shouldShowTimestamp = interaction.interactionType == .call
        if shouldShowTimestamp {
            labelText.append(LocalizationNotNeeded(" · "))
            labelText.append(DateUtil.formatTimestampAsTime(interaction.timestamp))
        }

        return labelText
    }

    private static func systemMessageText(
        forInteraction interaction: TSInteraction,
        transaction: DBReadTransaction,
    ) -> String {
        if let errorMessage = interaction as? TSErrorMessage {
            return errorMessage.previewText(transaction: transaction)
        } else if let verificationMessage = interaction as? OWSVerificationStateChangeMessage {
            let format = switch (verificationMessage.isLocalChange, verificationMessage.isVerified()) {
            case (true, true):
                OWSLocalizedString(
                    "VERIFICATION_STATE_CHANGE_FORMAT_VERIFIED_LOCAL",
                    comment: "Format for info message indicating that the verification state was verified on this device. Embeds {{user's name or phone number}}.",
                )
            case (true, false):
                OWSLocalizedString(
                    "VERIFICATION_STATE_CHANGE_FORMAT_NOT_VERIFIED_LOCAL",
                    comment: "Format for info message indicating that the verification state was unverified on this device. Embeds {{user's name or phone number}}.",
                )
            case (false, true):
                OWSLocalizedString(
                    "VERIFICATION_STATE_CHANGE_FORMAT_VERIFIED_OTHER_DEVICE",
                    comment: "Format for info message indicating that the verification state was verified on another device. Embeds {{user's name or phone number}}.",
                )
            case (false, false):
                OWSLocalizedString(
                    "VERIFICATION_STATE_CHANGE_FORMAT_NOT_VERIFIED_OTHER_DEVICE",
                    comment: "Format for info message indicating that the verification state was unverified on another device. Embeds {{user's name or phone number}}.",
                )
            }

            let displayName = SSKEnvironment.shared.contactManagerRef.displayName(for: verificationMessage.recipientAddress, tx: transaction).resolvedValue()
            return String(format: format, displayName)
        } else if let infoMessage = interaction as? TSInfoMessage {
            return infoMessage.conversationSystemMessageComponentText(with: transaction)
        } else if let call = interaction as? TSCall {
            return call.previewText(transaction: transaction)
        } else if let groupCall = interaction as? OWSGroupCallMessage {
            return groupCall.systemText(tx: transaction)
        } else {
            owsFailDebug("Not a system message.")
            return ""
        }
    }

    private static var defaultTextColor: UIColor { Theme.secondaryTextAndIconColor }
    private static var defaultSelectionBackgroundColor: UIColor {
        Theme.isDarkThemeEnabled ? .ows_gray80 : .ows_gray05
    }

    private static func overrideTextColor(forInteraction interaction: TSInteraction) -> UIColor? {
        if let call = interaction as? TSCall {
            switch call.callType {
            case .incomingMissed,
                 .incomingMissedBecauseOfChangedIdentity,
                 .incomingMissedBecauseOfDoNotDisturb,
                 .incomingBusyElsewhere:
                // We use a custom red here, as we consider changing
                // our red everywhere for better accessibility
                return UIColor(rgbHex: 0xE51D0E)
            default:
                return nil
            }
        } else {
            return nil
        }
    }

    private static func icon(forInteraction interaction: TSInteraction) -> UIImage? {
        if let errorMessage = interaction as? TSErrorMessage {
            switch errorMessage.errorType {
            case .nonBlockingIdentityChange,
                 .wrongTrustedIdentityKey:
                return Theme.iconImage(.safetyNumber16)
            case .sessionRefresh:
                return Theme.iconImage(.refresh16)
            case .decryptionFailure:
                return Theme.iconImage(.error16)
            case .invalidKeyException,
                 .missingKeyId,
                 .noSession,
                 .invalidMessage,
                 .duplicateMessage,
                 .invalidVersion,
                 .unknownContactBlockOffer,
                 .groupCreationFailed:
                return nil
            }
        } else if let infoMessage = interaction as? TSInfoMessage {
            switch infoMessage.messageType {
            case .userNotRegistered,
                 .typeLocalUserEndedSession,
                 .typeRemoteUserEndedSession,
                 .typeUnsupportedMessage,
                 .addToContactsOffer,
                 .addUserToProfileWhitelistOffer,
                 .addGroupToProfileWhitelistOffer:
                return nil
            case .typeGroupUpdate,
                 .typeGroupQuit:
                return Theme.iconImage(.group16)
            case .unknownProtocolVersion:
                guard let message = interaction as? OWSUnknownProtocolVersionMessage else {
                    owsFailDebug("Invalid interaction.")
                    return nil
                }
                return Theme.iconImage(message.isProtocolVersionUnknown ? .error16 : .check16)
            case .typeDisappearingMessagesUpdate:
                guard let message = interaction as? OWSDisappearingConfigurationUpdateInfoMessage else {
                    owsFailDebug("Invalid interaction.")
                    return nil
                }
                let areDisappearingMessagesEnabled = message.configurationIsEnabled
                return Theme.iconImage(areDisappearingMessagesEnabled ? .timer16 : .timerDisabled16)
            case .verificationStateChange:
                guard let message = interaction as? OWSVerificationStateChangeMessage else {
                    owsFailDebug("Invalid interaction.")
                    return nil
                }
                if message.isVerified() {
                    return Theme.iconImage(.safetyNumber16)
                } else {
                    return nil
                }
            case .userJoinedSignal:
                return Theme.iconImage(.heart16)
            case .syncedThread:
                return Theme.iconImage(.info16)
            case .profileUpdate:
                return Theme.iconImage(.profile16)
            case .phoneNumberChange:
                return Theme.iconImage(.phone16)
            case .recipientHidden:
                return Theme.iconImage(.info16)
            case .paymentsActivationRequest, .paymentsActivated:
                return Theme.iconImage(.settingsPayments)
            case .threadMerge:
                return Theme.iconImage(.merge16)
            case .sessionSwitchover:
                return Theme.iconImage(.info16)
            case .reportedSpam:
                return Theme.iconImage(.spam)
            case .learnedProfileName:
                return Theme.iconImage(.threadCompact)
            case .blockedOtherUser:
                return Theme.iconImage(.chatSettingsBlock)
            case .blockedGroup:
                return Theme.iconImage(.chatSettingsBlock)
            case .unblockedOtherUser:
                return Theme.iconImage(.threadCompact)
            case .unblockedGroup:
                return Theme.iconImage(.threadCompact)
            case .acceptedMessageRequest:
                return Theme.iconImage(.threadCompact)
            case .typeEndPoll:
                return Theme.iconImage(.poll)
            case .typePinnedMessage:
                return Theme.iconImage(.pin)
            }
        } else if let call = interaction as? TSCall {
            switch call.offerType {
            case .audio:
                return Theme.iconImage(.phone16)
            case .video:
                return Theme.iconImage(.video16)
            }
        } else if interaction is OWSGroupCallMessage {
            return Theme.iconImage(.video16)
        } else {
            owsFailDebug("Unknown interaction type: \(type(of: interaction))")
            return nil
        }
    }

    private static func iconName(displayableGroupUpdateItem: DisplayableGroupUpdateItem) -> String {
        switch displayableGroupUpdateItem {
        case
            .localUserLeft,
            .otherUserLeft:
            return Theme.iconName(.leave16)
        case
            .localUserRemoved,
            .localUserRemovedByUnknownUser,
            .otherUserRemovedByLocalUser,
            .otherUserRemoved,
            .otherUserRemovedByUnknownUser:
            return Theme.iconName(.memberRemove16)
        case
            .unnamedUsersWereInvitedByLocalUser,
            .unnamedUsersWereInvitedByOtherUser,
            .unnamedUsersWereInvitedByUnknownUser,
            .localUserWasInvitedByLocalUser,
            .localUserWasInvitedByOtherUser,
            .localUserWasInvitedByUnknownUser,
            .otherUserWasInvitedByLocalUser,
            .localUserAddedByLocalUser,
            .localUserAddedByOtherUser,
            .localUserAddedByUnknownUser,
            .localUserAcceptedInviteFromUnknownUser,
            .localUserAcceptedInviteFromInviter,
            .localUserJoined,
            .localUserJoinedViaInviteLink,
            .localUserRequestApproved,
            .localUserRequestApprovedByUnknownUser,
            .otherUserAddedByLocalUser,
            .otherUserAddedByOtherUser,
            .otherUserAddedByUnknownUser,
            .otherUserAcceptedInviteFromLocalUser,
            .otherUserAcceptedInviteFromInviter,
            .otherUserAcceptedInviteFromUnknownUser,
            .otherUserJoined,
            .otherUserJoinedViaInviteLink,
            .otherUserRequestApprovedByLocalUser,
            .otherUserRequestApproved,
            .otherUserRequestApprovedByUnknownUser:
            return Theme.iconName(.memberAdded16)
        case
            .createdByLocalUser,
            .createdByOtherUser,
            .createdByUnknownUser,
            .genericUpdateByLocalUser,
            .genericUpdateByOtherUser,
            .genericUpdateByUnknownUser,
            .localUserRequestedToJoin,
            .localUserRequestCanceledByLocalUser,
            .localUserRequestRejectedByUnknownUser,
            .otherUserRequestedToJoin,
            .otherUserRequestCanceledByOtherUser,
            .otherUserRequestRejectedByLocalUser,
            .otherUserRequestRejectedByOtherUser,
            .otherUserRequestRejectedByUnknownUser,
            .sequenceOfInviteLinkRequestAndCancels,
            .inviteLinkResetByLocalUser,
            .inviteLinkResetByOtherUser,
            .inviteLinkResetByUnknownUser,
            .inviteLinkDisabledByLocalUser,
            .inviteLinkDisabledByOtherUser,
            .inviteLinkDisabledByUnknownUser,
            .inviteLinkEnabledWithApprovalByLocalUser,
            .inviteLinkEnabledWithApprovalByOtherUser,
            .inviteLinkEnabledWithApprovalByUnknownUser,
            .inviteLinkEnabledWithoutApprovalByLocalUser,
            .inviteLinkEnabledWithoutApprovalByOtherUser,
            .inviteLinkEnabledWithoutApprovalByUnknownUser,
            .inviteLinkApprovalEnabledByLocalUser,
            .inviteLinkApprovalEnabledByOtherUser,
            .inviteLinkApprovalEnabledByUnknownUser,
            .inviteLinkApprovalDisabledByLocalUser,
            .inviteLinkApprovalDisabledByOtherUser,
            .inviteLinkApprovalDisabledByUnknownUser,
            .inviteFriendsToNewlyCreatedGroup:
            return Theme.iconName(.group16)
        case
            .unnamedUserInvitesWereRevokedByLocalUser,
            .unnamedUserInvitesWereRevokedByOtherUser,
            .unnamedUserInvitesWereRevokedByUnknownUser,
            .localUserDeclinedInviteFromInviter,
            .localUserDeclinedInviteFromUnknownUser,
            .localUserInviteRevoked,
            .localUserInviteRevokedByUnknownUser,
            .otherUserDeclinedInviteFromLocalUser,
            .otherUserDeclinedInviteFromInviter,
            .otherUserDeclinedInviteFromUnknownUser,
            .otherUserInviteRevokedByLocalUser:
            return Theme.iconName(.memberDeclined16)
        case
            .wasMigrated,
            .localUserInvitedAfterMigration,
            .otherUsersInvitedAfterMigration,
            .otherUsersDroppedAfterMigration,
            .attributesAccessChangedByLocalUser,
            .attributesAccessChangedByOtherUser,
            .attributesAccessChangedByUnknownUser,
            .membersAccessChangedByLocalUser,
            .membersAccessChangedByOtherUser,
            .membersAccessChangedByUnknownUser,
            .localUserWasGrantedAdministratorByLocalUser,
            .localUserWasGrantedAdministratorByOtherUser,
            .localUserWasGrantedAdministratorByUnknownUser,
            .localUserWasRevokedAdministratorByLocalUser,
            .localUserWasRevokedAdministratorByOtherUser,
            .localUserWasRevokedAdministratorByUnknownUser,
            .otherUserWasGrantedAdministratorByLocalUser,
            .otherUserWasGrantedAdministratorByOtherUser,
            .otherUserWasGrantedAdministratorByUnknownUser,
            .otherUserWasRevokedAdministratorByLocalUser,
            .otherUserWasRevokedAdministratorByOtherUser,
            .otherUserWasRevokedAdministratorByUnknownUser,
            .announcementOnlyEnabledByLocalUser,
            .announcementOnlyEnabledByOtherUser,
            .announcementOnlyEnabledByUnknownUser,
            .announcementOnlyDisabledByLocalUser,
            .announcementOnlyDisabledByOtherUser,
            .announcementOnlyDisabledByUnknownUser:
            return Theme.iconName(.megaphone16)
        case
            .nameChangedByLocalUser,
            .nameChangedByOtherUser,
            .nameChangedByUnknownUser,
            .nameRemovedByLocalUser,
            .nameRemovedByOtherUser,
            .nameRemovedByUnknownUser,
            .descriptionChangedByLocalUser,
            .descriptionChangedByOtherUser,
            .descriptionChangedByUnknownUser,
            .descriptionRemovedByLocalUser,
            .descriptionRemovedByOtherUser,
            .descriptionRemovedByUnknownUser:
            return Theme.iconName(.compose16)
        case
            .avatarChangedByLocalUser,
            .avatarChangedByOtherUser,
            .avatarChangedByUnknownUser,
            .avatarRemovedByLocalUser,
            .avatarRemovedByOtherUser,
            .avatarRemovedByUnknownUser:
            return Theme.iconName(.photo16)
        case
            .disappearingMessagesEnabledByLocalUser,
            .disappearingMessagesEnabledByOtherUser,
            .disappearingMessagesEnabledByUnknownUser:
            return Theme.iconName(.timer16)
        case
            .disappearingMessagesDisabledByLocalUser,
            .disappearingMessagesDisabledByOtherUser,
            .disappearingMessagesDisabledByUnknownUser:
            return Theme.iconName(.timerDisabled16)
        }
    }

    // MARK: - Default Disappearing Message Timer

    static func buildDefaultDisappearingMessageTimerState(
        interaction: TSInteraction,
        threadViewModel: ThreadViewModel,
        transaction tx: DBReadTransaction,
    ) -> CVComponentState.SystemMessage {
        let dmConfigurationStore = DependenciesBridge.shared.disappearingMessagesConfigurationStore
        let configuration = dmConfigurationStore.fetchOrBuildDefault(for: .universal, tx: tx)

        let labelText = NSMutableAttributedString()
        labelText.appendImage(
            Theme.iconImage(.timer16).withRenderingMode(.alwaysTemplate),
            font: Self.textLabelFont,
            heightReference: ImageAttachmentHeightReference.lineHeight,
        )
        labelText.append("  ", attributes: [:])

        let titleFormat = OWSLocalizedString(
            "SYSTEM_MESSAGE_DEFAULT_DISAPPEARING_MESSAGE_TIMER_FORMAT",
            comment: "Indicator that the default disappearing message timer will be applied when you send a message. Embeds {default disappearing message time}",
        )
        labelText.append(String(format: titleFormat, configuration.durationString()))

        return buildComponentState(title: labelText, action: nil, expiration: nil)
    }

    // MARK: - Actions

    static func action(
        forInteraction interaction: TSInteraction,
        threadViewModel: ThreadViewModel,
        currentGroupThreadCallGroupId: GroupIdentifier?,
        transaction: DBReadTransaction,
    ) -> Action? {
        if let errorMessage = interaction as? TSErrorMessage {
            return action(forErrorMessage: errorMessage)
        } else if let infoMessage = interaction as? TSInfoMessage {
            return action(forInfoMessage: infoMessage, transaction: transaction)
        } else if let call = interaction as? TSCall {
            return action(forCall: call, threadViewModel: threadViewModel)
        } else if let groupCall = interaction as? OWSGroupCallMessage {
            return action(
                forGroupCall: groupCall,
                threadViewModel: threadViewModel,
                currentGroupThreadCallGroupId: currentGroupThreadCallGroupId,
            )
        } else {
            owsFailDebug("Invalid interaction.")
            return nil
        }
    }

    private static func action(forErrorMessage message: TSErrorMessage) -> Action? {
        switch message.errorType {
        case .nonBlockingIdentityChange:
            guard let address = message.recipientAddress else {
                owsFailDebug("Missing address.")
                return nil
            }

            if message.wasIdentityVerified {
                return Action(
                    title: OWSLocalizedString(
                        "SYSTEM_MESSAGE_ACTION_VERIFY_SAFETY_NUMBER",
                        comment: "Label for button to verify a user's safety number.",
                    ),
                    accessibilityIdentifier: "verify_safety_number",
                    action: .didTapPreviouslyVerifiedIdentityChange(address: address),
                )
            } else {
                return Action(
                    title: CommonStrings.learnMore,
                    accessibilityIdentifier: "learn_more",
                    action: .didTapUnverifiedIdentityChange(address: address),
                )
            }
        case .wrongTrustedIdentityKey:
            return nil
        case .invalidKeyException,
             .missingKeyId,
             .noSession,
             .invalidMessage:
            return Action(
                title: OWSLocalizedString(
                    "FINGERPRINT_SHRED_KEYMATERIAL_BUTTON",
                    comment: "Label for button to reset a session.",
                ),
                accessibilityIdentifier: "reset_session",
                action: .didTapCorruptedMessage(errorMessage: message),
            )
        case .sessionRefresh:
            return Action(
                title: CommonStrings.learnMore,
                accessibilityIdentifier: "learn_more",
                action: .didTapSessionRefreshMessage(errorMessage: message),
            )
        case .decryptionFailure:
            return Action(
                title: CommonStrings.learnMore,
                accessibilityIdentifier: "learn_more",
                action: .didTapDeliveryIssueWarning(errorMessage: message),
            )
        case .duplicateMessage,
             .invalidVersion:
            return nil
        case .unknownContactBlockOffer:
            owsFailDebug("TSErrorMessageUnknownContactBlockOffer")
            return nil
        case .groupCreationFailed:
            return Action(
                title: CommonStrings.retryButton,
                accessibilityIdentifier: "retry_send_group",
                action: .didTapResendGroupUpdate(errorMessage: message),
            )
        }
    }

    private static func action(
        forInfoMessage infoMessage: TSInfoMessage,
        transaction: DBReadTransaction,
    ) -> Action? {

        switch infoMessage.messageType {
        case .userNotRegistered,
             .typeLocalUserEndedSession,
             .typeRemoteUserEndedSession:
            return nil
        case .typeUnsupportedMessage:
            // Unused.
            return nil
        case .addToContactsOffer:
            // Unused.
            owsFailDebug("TSInfoMessageAddToContactsOffer")
            return nil
        case .addUserToProfileWhitelistOffer:
            // Unused.
            owsFailDebug("TSInfoMessageAddUserToProfileWhitelistOffer")
            return nil
        case .addGroupToProfileWhitelistOffer:
            // Unused.
            owsFailDebug("TSInfoMessageAddGroupToProfileWhitelistOffer")
            return nil
        case .typeGroupUpdate:
            let thread = { infoMessage.thread(tx: transaction) as? TSGroupThread }
            guard
                let localIdentifiers = DependenciesBridge.shared.tsAccountManager
                    .localIdentifiers(tx: transaction),
                let items = infoMessage.computedGroupUpdateItems(
                    localIdentifiers: localIdentifiers,
                    tx: transaction,
                )
            else {
                return nil
            }
            return TSInfoMessage.PersistableGroupUpdateItem.cvComponentAction(
                items: items,
                groupThread: thread,
                contactsManager: SSKEnvironment.shared.contactManagerRef,
                tx: transaction,
            )
        case .typeGroupQuit:
            return nil
        case .unknownProtocolVersion:
            guard let message = infoMessage as? OWSUnknownProtocolVersionMessage else {
                owsFailDebug("Unexpected message type.")
                return nil
            }
            guard message.isProtocolVersionUnknown else {
                return nil
            }
            return Action(
                title: OWSLocalizedString(
                    "UNKNOWN_PROTOCOL_VERSION_UPGRADE_BUTTON",
                    comment: "Label for button that lets users upgrade the app.",
                ),
                accessibilityIdentifier: "show_upgrade_app_ui",
                action: .didTapShowUpgradeAppUI,
            )
        case .typeDisappearingMessagesUpdate,
             .verificationStateChange,
             .userJoinedSignal,
             .syncedThread,
             .recipientHidden:
            return nil
        case .profileUpdate:
            guard let profileChangeAddress = infoMessage.profileChangeAddress else {
                owsFailDebug("Missing profileChangeAddress.")
                return nil
            }
            // Don't show the button on linked devices -- they can't use it.
            guard SSKEnvironment.shared.contactManagerImplRef.isEditingAllowed else {
                return nil
            }
            guard let profileChangesNewNameComponents = infoMessage.profileChangesNewNameComponents else {
                return nil
            }
            guard let profileChangePhoneNumber = profileChangeAddress.phoneNumber else {
                return nil
            }
            let systemContactName = SSKEnvironment.shared.contactManagerRef.systemContactName(for: profileChangePhoneNumber, tx: transaction)
            guard let systemContactName else {
                return nil
            }
            let newProfileName = OWSFormat.formatNameComponents(profileChangesNewNameComponents)
            let currentProfileName = SSKEnvironment.shared.profileManagerRef.userProfile(for: profileChangeAddress, tx: transaction)?.filteredFullName

            // Only show the button if the address book contact's name is different
            // than the profile name.
            guard systemContactName.resolvedValue() != newProfileName else {
                return nil
            }

            // Only show the button if the new name is the latest(/current) profile
            // name we know about.
            guard currentProfileName == newProfileName else {
                return nil
            }

            return Action(
                title: OWSLocalizedString("UPDATE_CONTACT_ACTION", comment: "Action sheet item"),
                accessibilityIdentifier: "update_contact",
                action: .didTapUpdateSystemContact(address: profileChangeAddress, newNameComponents: profileChangesNewNameComponents),
            )
        case .phoneNumberChange:
            guard
                let phoneNumberChangeInfo = infoMessage.phoneNumberChangeInfo(),
                let phoneNumberOld = phoneNumberChangeInfo.oldNumber,
                let phoneNumberNew = phoneNumberChangeInfo.newNumber
            else {
                // This might be missing, for example on info messages coming
                // from a backup.
                return nil
            }

            // Don't show the button on linked devices -- they can't use it.
            guard SSKEnvironment.shared.contactManagerImplRef.isEditingAllowed else {
                return nil
            }

            // Only show the update contact action if this user was previously a contact.
            guard let existingCnContactId = SSKEnvironment.shared.contactManagerRef.cnContactId(for: phoneNumberOld) else {
                return nil
            }

            // Make sure the contact hasn't already had the new number added.
            guard SSKEnvironment.shared.contactManagerRef.cnContactId(for: phoneNumberNew) != existingCnContactId else {
                return nil
            }

            return Action(
                title: OWSLocalizedString("UPDATE_CONTACT_ACTION", comment: "Action sheet item"),
                accessibilityIdentifier: "update_contact",
                action: .didTapPhoneNumberChange(
                    aci: phoneNumberChangeInfo.aci,
                    phoneNumberOld: phoneNumberOld,
                    phoneNumberNew: phoneNumberNew,
                ),
            )
        case .paymentsActivationRequest:
            if
                infoMessage.isIncomingPaymentsActivationRequest(transaction),
                !SSKEnvironment.shared.paymentsHelperRef.arePaymentsEnabled(tx: transaction)
            {
                return CVMessageAction(
                    title: OWSLocalizedString(
                        "SETTINGS_PAYMENTS_OPT_IN_ACTIVATE_BUTTON",
                        comment: "Label for 'activate' button in the 'payments opt-in' view in the app settings.",
                    ),
                    accessibilityIdentifier: "activate_payments",
                    action: .didTapActivatePayments,
                )
            } else {
                return nil
            }
        case .paymentsActivated:
            if infoMessage.isIncomingPaymentsActivated(transaction) {
                return CVMessageAction(
                    title: OWSLocalizedString(
                        "SETTINGS_PAYMENTS_SEND_PAYMENT",
                        comment: "Label for 'send payment' button in the payment settings.",
                    ),
                    accessibilityIdentifier: "send_payment",
                    action: .didTapSendPayment,
                )
            } else {
                return nil
            }
        case .threadMerge:
            guard let phoneNumber = infoMessage.threadMergePhoneNumber else {
                return nil
            }
            return CVMessageAction(
                title: CommonStrings.learnMore,
                accessibilityIdentifier: "learn_more",
                action: .didTapThreadMergeLearnMore(phoneNumber: phoneNumber),
            )
        case .sessionSwitchover:
            return nil
        case .reportedSpam:
            return CVMessageAction(
                title: CommonStrings.learnMore,
                accessibilityIdentifier: "learn_more",
                action: .didTapReportSpamLearnMore,
            )
        case .learnedProfileName:
            return nil
        case .blockedOtherUser:
            return nil
        case .blockedGroup:
            return nil
        case .unblockedOtherUser:
            return nil
        case .unblockedGroup:
            return nil
        case .typePinnedMessage:
            guard let pinnedMessageUniqueId = infoMessage.pinnedMessageUniqueId(transaction: transaction) else {
                return nil
            }
            return CVMessageAction(
                title: OWSLocalizedString("BUTTON_VIEW", comment: "Label for the 'view' button."),
                accessibilityIdentifier: "view_button",
                action: .didTapViewPinnedMessage(pinnedMessageUniqueId: pinnedMessageUniqueId),
            )
        case .typeEndPoll:
            guard let pollInteractionUniqueId = infoMessage.pollInteractionUniqueId(transaction: transaction) else {
                return nil
            }
            return CVMessageAction(
                title: OWSLocalizedString("POLL_BUTTON_VIEW_POLL", comment: "Button to view a poll after its ended"),
                accessibilityIdentifier: "view_poll",
                action: .didTapViewPoll(pollInteractionUniqueId: pollInteractionUniqueId),
            )
        case .acceptedMessageRequest:
            return CVMessageAction(
                title: OWSLocalizedString(
                    "INFO_MESSAGE_ACCEPTED_MESSAGE_REQUEST_OPTIONS_BUTTON",
                    comment: "Title for a button shown alongside an info message indicating you accepted a message request.",
                ),
                accessibilityIdentifier: "options",
                action: .didTapMessageRequestAcceptedOptions,
            )
        }
    }

    private static func action(forCall call: TSCall, threadViewModel: ThreadViewModel) -> Action? {
        owsAssertDebug(threadViewModel.threadRecord is TSContactThread)

        switch call.callType {
        case .incoming,
             .incomingMissed,
             .incomingMissedBecauseOfChangedIdentity,
             .incomingMissedBecauseOfDoNotDisturb,
             .incomingDeclined,
             .incomingAnsweredElsewhere,
             .incomingDeclinedElsewhere,
             .incomingBusyElsewhere:
            guard ConversationViewController.canCall(threadViewModel: threadViewModel) else {
                return nil
            }
            // TODO: cvc_didTapGroupCall?
            return Action(
                title: OWSLocalizedString("CALLBACK_BUTTON_TITLE", comment: "notification action"),
                accessibilityIdentifier: "call_back",
                action: .didTapIndividualCall(call: call),
            )
        case .outgoing,
             .outgoingMissed:
            guard ConversationViewController.canCall(threadViewModel: threadViewModel) else {
                return nil
            }
            // TODO: cvc_didTapGroupCall?
            return Action(
                title: OWSLocalizedString("CALL_AGAIN_BUTTON_TITLE", comment: "Label for button that lets users call a contact again."),
                accessibilityIdentifier: "call_again",
                action: .didTapIndividualCall(call: call),
            )
        case .incomingMissedBecauseBlockedSystemContact:
            if threadViewModel.isBlocked {
                return nil
            }
            return Action(
                title: CommonStrings.learnMore,
                accessibilityIdentifier: "learn_more_call_blocked_system_contact",
                action: .didTapLearnMoreMissedCallFromBlockedContact(call: call),
            )
        case .outgoingIncomplete,
             .incomingIncomplete:
            return nil
        @unknown default:
            owsFailDebug("Unknown value.")
            return nil
        }
    }

    private static func action(
        forGroupCall groupCallMessage: OWSGroupCallMessage,
        threadViewModel: ThreadViewModel,
        currentGroupThreadCallGroupId: GroupIdentifier?,
    ) -> Action? {
        guard let groupThread = threadViewModel.threadRecord as? TSGroupThread else {
            return nil
        }

        // Assume the current thread supports calling if we have no delegate. This ensures we always
        // overestimate cell measurement in cases where the current thread doesn't support calling.
        let isCallingSupported = ConversationViewController.canCall(threadViewModel: threadViewModel)
        let isCallActive = (!groupCallMessage.hasEnded && !groupCallMessage.joinedMemberAcis.isEmpty)

        guard isCallingSupported, isCallActive else {
            return nil
        }

        // TODO: We need to touch thread whenever current call changes.
        let isCurrentCallForThread = currentGroupThreadCallGroupId?.serialize() == groupThread.groupId

        let returnTitle = OWSLocalizedString("CALL_RETURN_BUTTON", comment: "Button to return to the current call")
        let title = isCurrentCallForThread ? returnTitle : CallStrings.joinGroupCall

        return Action(title: title, accessibilityIdentifier: "group_call_button", action: .didTapGroupCall)
    }

    // MARK: - Expiration

    static func expiration(
        forInteraction interaction: TSInteraction,
        transaction: DBReadTransaction,
    ) -> CVComponentState.SystemMessage.Expiration? {
        if let infoMessage = interaction as? TSInfoMessage {
            return expiration(forInfoMessage: infoMessage, transaction: transaction)
        } else {
            // Expiration state not supported.
            return nil
        }
    }

    private static func expiration(
        forInfoMessage infoMessage: TSInfoMessage,
        transaction: DBReadTransaction,
    ) -> CVComponentState.SystemMessage.Expiration? {
        guard infoMessage.expiresAt > 0, infoMessage.expiresInSeconds > 0 else {
            return nil
        }

        return CVComponentState.SystemMessage.Expiration(
            expirationTimestamp: infoMessage.expiresAt,
            expiresInSeconds: infoMessage.expiresInSeconds,
        )
    }
}
