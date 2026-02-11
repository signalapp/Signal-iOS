//
// Copyright 2020 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

public import SignalServiceKit
public import SignalUI

public class CVComponentFooter: CVComponentBase, CVComponent {

    public var componentKey: CVComponentKey { .footer }

    struct StatusIndicator: Equatable {
        let imageName: String
        let isAnimated: Bool

        static var size: CGSize { .init(width: 18, height: 12) }
    }

    public enum TapForMoreState {
        case none
        case tapForMore
        case undownloadableLongText

        var shouldShowFooter: Bool {
            switch self {
            case .none:
                return false
            case .tapForMore:
                return true
            case .undownloadableLongText:
                return true
            }
        }
    }

    struct State: Equatable {
        let timestampText: String
        let statusIndicator: StatusIndicator?
        let accessibilityLabel: String?
        let tapForMoreState: TapForMoreState
        let displayEditedLabel: Bool
        let isPinnedMessage: Bool

        struct Expiration: Equatable {
            let expirationTimestamp: UInt64
            let expiresInSeconds: UInt32
        }

        let expiration: Expiration?

    }

    private let footerState: State

    public var timestampText: String {
        footerState.timestampText
    }

    public var footerAccessibilityLabel: String? {
        footerState.accessibilityLabel
    }

    private var statusIndicator: StatusIndicator? {
        footerState.statusIndicator
    }

    public var tapForMoreState: TapForMoreState {
        footerState.tapForMoreState
    }

    public var displayEditedLabel: Bool {
        footerState.displayEditedLabel
    }

    private var expiration: State.Expiration? {
        footerState.expiration
    }

    private var isPinnedMessage: Bool {
        footerState.isPinnedMessage
    }

    let isOverlayingMedia: Bool
    private let isOutsideBubble: Bool

    init(
        itemModel: CVItemModel,
        footerState: State,
        isOverlayingMedia: Bool,
        isOutsideBubble: Bool,
    ) {

        self.footerState = footerState
        self.isOverlayingMedia = isOverlayingMedia
        self.isOutsideBubble = isOutsideBubble

        super.init(itemModel: itemModel)
    }

    public func buildComponentView(componentDelegate: CVComponentDelegate) -> CVComponentView {
        CVComponentViewFooter()
    }

    override public func updateScrollingContent(componentView: CVComponentView) {
        super.updateScrollingContent(componentView: componentView)

        guard let componentView = componentView as? CVComponentViewFooter else {
            owsFailDebug("Unexpected componentView.")
            return
        }
        componentView.chatColorView.updateAppearance()
    }

    public static let textViewVSpacing: CGFloat = 2
    public static let bodyMediaQuotedReplyVSpacing: CGFloat = 6
    public static let quotedReplyTopMargin: CGFloat = 6

    public func configureForRendering(
        componentView componentViewParam: CVComponentView,
        cellMeasurement: CVCellMeasurement,
        componentDelegate: CVComponentDelegate,
    ) {
        guard let componentView = componentViewParam as? CVComponentViewFooter else {
            owsFailDebug("Unexpected componentView.")
            componentViewParam.reset()
            return
        }

        let outerStack = componentView.outerStack
        let innerStack = componentView.innerStack
        innerStack.reset()
        outerStack.reset()

        var outerViews = [UIView]()
        var innerViews = [UIView]()

        if isBorderless, conversationStyle.hasWallpaper {
            let chatColorView = componentView.chatColorView
            chatColorView.configure(
                value: conversationStyle.bubbleChatColor(isIncoming: isIncoming),
                referenceView: componentDelegate.view,
                hasPillRounding: true,
            )
            innerStack.addSubviewToFillSuperviewEdges(chatColorView)
        }

        if let tapForMoreLabelConfig = self.tapForMoreLabelConfig {
            let tapForMoreLabel = componentView.tapForMoreLabel
            tapForMoreLabelConfig.applyForRendering(label: tapForMoreLabel)
            outerViews.append(tapForMoreLabel)
        }

        // We always use a stretching spacer.
        outerViews.append(UIView.hStretchingSpacer())
        outerViews.append(innerStack)

        let timestampLabel = componentView.timestampLabel
        let textColor: UIColor
        if wasRemotelyDeleted, !conversationStyle.hasWallpaper {
            owsAssertDebug(!isOverlayingMedia)
            textColor = Theme.primaryTextColor
        } else if isOverlayingMedia {
            textColor = .ows_white
        } else if isOutsideBubble, !conversationStyle.hasWallpaper {
            textColor = Theme.secondaryTextAndIconColor
        } else {
            textColor = conversationStyle.bubbleSecondaryTextColor(isIncoming: isIncoming)
        }

        if isPinnedMessage {
            let pinIconView = componentView.pinnedImageView
            pinIconView.configure(tintColor: textColor)
            innerViews.append(pinIconView)
        }

        if displayEditedLabel {
            let editedLabel = componentView.editedLabel
            editedLabelConfig(textColor: textColor).applyForRendering(label: editedLabel)
            innerViews.append(editedLabel)
        }

        timestampLabelConfig(textColor: textColor).applyForRendering(label: timestampLabel)
        innerViews.append(timestampLabel)

        if let expiration {
            let messageTimerView = componentView.messageTimerView
            messageTimerView.configure(
                expirationTimestampMs: expiration.expirationTimestamp,
                disappearingMessageInterval: expiration.expiresInSeconds,
                tintColor: textColor,
            )
            innerViews.append(messageTimerView)
        }

        if isRepresentingSmsMessageRestoredFromBackup {
            let smsLockIconView = componentView.smsLockIconView
            smsLockIconView.configure(tintColor: textColor)
            innerViews.append(smsLockIconView)
        }

        if let statusIndicator {
            if let icon = UIImage(named: statusIndicator.imageName) {
                let iconSize = icon.size
                let statusIndicatorAreaSize = StatusIndicator.size

                owsAssertDebug(iconSize.width <= statusIndicatorAreaSize.width)
                owsAssertDebug(iconSize.height == statusIndicatorAreaSize.height)

                let statusIndicatorImageView = componentView.statusIndicatorImageView
                statusIndicatorImageView.image = icon.withRenderingMode(.alwaysTemplate)
                statusIndicatorImageView.tintColor = textColor

                // We need exactly the same amount of space for all status indicator images.
                // Can't bake the space into icons because some icons are animated.
                // The solution is to use a container view.
                let statusIndicatorImageViewContainer = UIView(frame: CGRect(origin: .zero, size: statusIndicatorAreaSize))
                statusIndicatorImageViewContainer.addSubview(statusIndicatorImageView)
                statusIndicatorImageView.frame = CGRect(origin: .zero, size: iconSize)
                if CurrentAppContext().isRTL {
                    statusIndicatorImageView.frame.origin.x = statusIndicatorAreaSize.width - iconSize.width
                }
                innerViews.append(statusIndicatorImageViewContainer)

                if statusIndicator.isAnimated {
                    componentView.animateSpinningIcon()
                }
            } else {
                owsFailDebug("Missing statusIndicatorImage.")
            }
        }

        innerStack.configure(
            config: innerStackConfig,
            cellMeasurement: cellMeasurement,
            measurementKey: Self.measurementKey_innerStack,
            subviews: innerViews,
        )
        outerStack.configure(
            config: outerStackConfig,
            cellMeasurement: cellMeasurement,
            measurementKey: Self.measurementKey_outerStack,
            subviews: outerViews,
        )
    }

    static func outgoingMessageStatus(interaction: TSInteraction, hasBodyAttachments: Bool) -> MessageReceiptStatus? {
        guard let outgoingMessage = interaction as? TSOutgoingMessage else {
            return nil
        }
        return MessageRecipientStatusUtils.recipientStatus(outgoingMessage: outgoingMessage, hasBodyAttachments: hasBodyAttachments)
    }

    public static func timestampText(
        forInteraction interaction: TSInteraction,
        shouldUseLongFormat: Bool,
        hasBodyAttachments: Bool,
    ) -> String {

        let status = Self.outgoingMessageStatus(interaction: interaction, hasBodyAttachments: hasBodyAttachments)
        let isPendingOutgoingMessage = status == .pending
        let isFailedOutgoingMessage = status == .failed
        let wasSentToAnyRecipient: Bool = {
            guard let outgoingMessage = interaction as? TSOutgoingMessage else {
                return false
            }
            return outgoingMessage.wasSentToAnyRecipient
        }()

        if isPendingOutgoingMessage {
            return OWSLocalizedString(
                "MESSAGE_STATUS_PENDING",
                comment: "Label indicating that a message send was paused.",
            )
        } else if isFailedOutgoingMessage {
            if wasSentToAnyRecipient {
                return OWSLocalizedString(
                    "MESSAGE_STATUS_PARTIALLY_SENT",
                    comment: "Label indicating that a message was only sent to some recipients.",
                )
            } else {
                return OWSLocalizedString(
                    "MESSAGE_STATUS_SEND_FAILED",
                    comment: "Label indicating that a message failed to send.",
                )
            }
        } else {
            return DateUtil.formatMessageTimestampForCVC(
                interaction.timestamp,
                shouldUseLongFormat: shouldUseLongFormat,
            )
        }
    }

    static func buildPaymentState(
        interaction: TSInteraction,
        paymentNotification: TSPaymentNotification?,
        tapForMoreState: TapForMoreState,
        transaction: DBReadTransaction,
    ) -> State {

        guard
            let receiptData = paymentNotification?.mcReceiptData,
            let paymentModel = PaymentFinder.paymentModels(
                forMcReceiptData: receiptData,
                transaction: transaction,
            ).first
        else {
            let hasBodyAttachments = (interaction as? TSMessage)?.hasBodyAttachments(transaction: transaction) ?? false
            let timestampText = Self.timestampText(
                forInteraction: interaction,
                shouldUseLongFormat: false,
                hasBodyAttachments: hasBodyAttachments,
            )

            return State(
                timestampText: timestampText,
                statusIndicator: nil,
                accessibilityLabel: nil,
                tapForMoreState: tapForMoreState,
                displayEditedLabel: false,
                isPinnedMessage: false,
                expiration: nil,
            )
        }

        let timestampText = Self.paymentMessageTimestampText(
            forInteraction: interaction,
            paymentState: paymentModel.paymentState,
            shouldUseLongFormat: false,
        )

        var statusIndicator: StatusIndicator?
        var accessibilityLabel: String?
        if let outgoingMessage = interaction as? TSOutgoingMessage {

            let messageStatus = MessageRecipientStatusUtils.recipientStatus(
                outgoingMessage: outgoingMessage,
                paymentModel: paymentModel,
            )
            accessibilityLabel = MessageRecipientStatusUtils.receiptMessage(
                outgoingMessage: outgoingMessage,
                paymentModel: paymentModel,
            )

            switch messageStatus {
            case .uploading, .sending:
                statusIndicator = StatusIndicator(
                    imageName: "message_status_sending",
                    isAnimated: true,
                )
            case .pending:
                statusIndicator = StatusIndicator(
                    imageName: "message_status_sending",
                    isAnimated: false,
                )
            case .sent, .skipped:
                statusIndicator = StatusIndicator(
                    imageName: "message_status_sent",
                    isAnimated: false,
                )
            case .delivered:
                statusIndicator = StatusIndicator(
                    imageName: "message_status_delivered",
                    isAnimated: false,
                )
            case .read, .viewed:
                statusIndicator = StatusIndicator(
                    imageName: "message_status_read",
                    isAnimated: false,
                )
            case .failed:
                // No status indicator icon.
                break
            }

            if outgoingMessage.wasRemotelyDeleted {
                statusIndicator = nil
            }
        }

        var expiration: State.Expiration?
        if
            let message = interaction as? TSMessage,
            message.hasPerConversationExpiration
        {
            expiration = State.Expiration(
                expirationTimestamp: message.expiresAt,
                expiresInSeconds: message.expiresInSeconds,
            )
        }

        return State(
            timestampText: timestampText,
            statusIndicator: statusIndicator,
            accessibilityLabel: accessibilityLabel,
            tapForMoreState: tapForMoreState,
            displayEditedLabel: false,
            isPinnedMessage: false,
            expiration: expiration,
        )
    }

    public static func paymentMessageTimestampText(
        forInteraction interaction: TSInteraction,
        paymentState: TSPaymentState,
        shouldUseLongFormat: Bool,
    ) -> String {

        switch paymentState.messageReceiptStatus {
        case .pending:
            return OWSLocalizedString(
                "MESSAGE_STATUS_PENDING",
                comment: "Label indicating that a message send was paused.",
            )
        case .failed:
            return OWSLocalizedString(
                "MESSAGE_STATUS_SEND_FAILED",
                comment: "Label indicating that a message failed to send.",
            )
        default:
            return DateUtil.formatMessageTimestampForCVC(
                interaction.timestamp,
                shouldUseLongFormat: shouldUseLongFormat,
            )
        }
    }

    static func buildState(
        interaction: TSInteraction,
        tapForMoreState: TapForMoreState,
        isPinnedMessage: Bool,
        transaction: DBReadTransaction,
    ) -> State {

        let hasBodyAttachments = (interaction as? TSMessage)?.hasBodyAttachments(transaction: transaction) ?? false
        let timestampText = Self.timestampText(
            forInteraction: interaction,
            shouldUseLongFormat: false,
            hasBodyAttachments: hasBodyAttachments,
        )

        var statusIndicator: StatusIndicator?
        var accessibilityLabel: String?
        if let outgoingMessage = interaction as? TSOutgoingMessage {
            let (messageStatus, label) = MessageRecipientStatusUtils.receiptStatusAndMessage(
                outgoingMessage: outgoingMessage,
                transaction: transaction,
            )
            accessibilityLabel = label

            switch messageStatus {
            case .uploading, .sending:
                statusIndicator = StatusIndicator(
                    imageName: "message_status_sending",
                    isAnimated: true,
                )
            case .pending:
                statusIndicator = StatusIndicator(
                    imageName: "message_status_sending",
                    isAnimated: false,
                )
            case .sent, .skipped:
                statusIndicator = StatusIndicator(
                    imageName: "message_status_sent",
                    isAnimated: false,
                )
            case .delivered:
                statusIndicator = StatusIndicator(
                    imageName: "message_status_delivered",
                    isAnimated: false,
                )
            case .read, .viewed:
                statusIndicator = StatusIndicator(
                    imageName: "message_status_read",
                    isAnimated: false,
                )
            case .failed:
                // No status indicator icon.
                break
            }

            if outgoingMessage.wasRemotelyDeleted {
                statusIndicator = nil
            }
        }

        var expiration: State.Expiration?
        var displayEditedLabel: Bool = false
        if let message = interaction as? TSMessage {
            if message.hasPerConversationExpiration {
                expiration = State.Expiration(
                    expirationTimestamp: message.expiresAt,
                    expiresInSeconds: message.expiresInSeconds,
                )
            }

            if !message.wasRemotelyDeleted {
                switch message.editState {
                case .latestRevisionRead, .latestRevisionUnread:
                    displayEditedLabel = true
                case .none, .pastRevision:
                    displayEditedLabel = false
                }
            }
        }

        return State(
            timestampText: timestampText,
            statusIndicator: statusIndicator,
            accessibilityLabel: accessibilityLabel,
            tapForMoreState: tapForMoreState,
            displayEditedLabel: displayEditedLabel,
            isPinnedMessage: isPinnedMessage,
            expiration: expiration,
        )
    }

    private func editedLabelConfig(textColor: UIColor) -> CVLabelConfig {
        let text = OWSLocalizedString(
            "MESSAGE_STATUS_EDITED",
            comment: "status meesage for edited messages",
        )

        return CVLabelConfig.unstyledText(
            text,
            font: .dynamicTypeCaption1,
            textColor: textColor,
        )
    }

    private func timestampLabelConfig(textColor: UIColor) -> CVLabelConfig {
        return CVLabelConfig.unstyledText(
            timestampText,
            font: .dynamicTypeCaption1,
            textColor: textColor,
        )
    }

    private var tapForMoreLabelConfig: CVLabelConfig? {
        switch tapForMoreState {
        case .none:
            return nil
        case .tapForMore:
            guard !wasRemotelyDeleted else {
                return nil
            }
            guard let message = interaction as? TSMessage else {
                owsFailDebug("Invalid interaction.")
                return nil
            }
            let text = OWSLocalizedString(
                "CONVERSATION_VIEW_OVERSIZE_TEXT_TAP_FOR_MORE",
                comment: "Indicator on truncated text messages that they can be tapped to see the entire text message.",
            )
            return CVLabelConfig.unstyledText(
                text,
                font: UIFont.dynamicTypeSubheadlineClamped.semibold(),
                textColor: conversationStyle.bubbleReadMoreTextColor(message: message),
                textAlignment: .trailing,
            )
        case .undownloadableLongText:
            guard !wasRemotelyDeleted else {
                return nil
            }
            guard let message = interaction as? TSMessage else {
                owsFailDebug("Invalid interaction.")
                return nil
            }
            let font = UIFont.dynamicTypeFootnoteClamped.semibold()
            let textColor = conversationStyle.bubbleReadMoreTextColor(message: message)
            let attributedString = NSAttributedString.composed(of: [
                NSAttributedString.with(
                    image: UIImage(named: "error-circle-20")!,
                    font: font,
                ),
                " ",
                OWSLocalizedString(
                    "OVERSIZE_TEXT_UNAVAILABLE_FOOTER",
                    comment: "Footer for message cell for long text when it is expired and unavailable for download",
                ),
                " ",
                NSAttributedString.with(
                    image: UIImage(named: "chevron-right-20")!,
                    font: font,
                ),
            ])
            // TODO[AttachmentRendering]: have to render a horizontal line
            // above the text when showing undownloadable state.
            return CVLabelConfig(
                text: .attributedText(attributedString),
                displayConfig: .forUnstyledText(font: font, textColor: textColor),
                font: font,
                textColor: textColor,
                textAlignment: .trailing,
            )
        }
    }

    private let tapForMoreHeightFactor: CGFloat = 1.25

    private var outerStackConfig: CVStackViewConfig {
        CVStackViewConfig(
            axis: .horizontal,
            alignment: .bottom,
            spacing: CVComponentFooter.hSpacing,
            layoutMargins: .zero,
        )
    }

    private var innerStackConfig: CVStackViewConfig {
        let layoutMargins = isBorderless ? UIEdgeInsets(hMargin: 12, vMargin: 3) : .zero
        return CVStackViewConfig(
            axis: .horizontal,
            alignment: .center,
            spacing: CVComponentFooter.hSpacing,
            layoutMargins: layoutMargins,
        )
    }

    private static let measurementKey_outerStack = "CVComponentFooter.measurementKey_outerStack"
    private static let measurementKey_innerStack = "CVComponentFooter.measurementKey_innerStack"

    // Extract the overall measurement for this component.
    public static func footerMeasurement(measurementBuilder: CVCellMeasurement.Builder) -> CVCellMeasurement.Measurement? {
        measurementBuilder.getMeasurement(key: measurementKey_outerStack)
    }

    public func measure(maxWidth: CGFloat, measurementBuilder: CVCellMeasurement.Builder) -> CGSize {
        owsAssertDebug(maxWidth > 0)

        var outerSubviewInfos = [ManualStackSubviewInfo]()
        var innerSubviewInfos = [ManualStackSubviewInfo]()

        if let tapForMoreLabelConfig = self.tapForMoreLabelConfig {
            var tapForMoreSize = CVText.measureLabel(
                config: tapForMoreLabelConfig,
                maxWidth: maxWidth,
            )
            tapForMoreSize.height *= tapForMoreHeightFactor
            outerSubviewInfos.append(tapForMoreSize.asManualSubviewInfo(hasFixedWidth: true))
        }

        // We always use a stretching spacer.
        outerSubviewInfos.append(ManualStackSubviewInfo.empty)

        if footerState.isPinnedMessage {
            let pinIconSize = PinnedMessageIconView.size
            innerSubviewInfos.append(pinIconSize.asManualSubviewInfo(hasFixedWidth: true))
        }

        if displayEditedLabel {
            let editedLabelConfig = self.editedLabelConfig(textColor: .black)
            let editedLabelSize = CVText.measureLabel(config: editedLabelConfig, maxWidth: maxWidth)
            innerSubviewInfos.append(editedLabelSize.asManualSubviewInfo(hasFixedWidth: true))
        }

        // The color doesn't matter for measurement.
        let timestampLabelConfig = self.timestampLabelConfig(textColor: UIColor.black)
        let timestampLabelSize = CVText.measureLabel(
            config: timestampLabelConfig,
            maxWidth: maxWidth,
        )
        innerSubviewInfos.append(timestampLabelSize.asManualSubviewInfo(hasFixedWidth: true))

        if
            hasPerConversationExpiration,
            interaction is TSMessage
        {
            let timerSize = MessageTimerView.measureSize
            innerSubviewInfos.append(timerSize.asManualSubviewInfo(hasFixedWidth: true))
        }

        if isRepresentingSmsMessageRestoredFromBackup {
            let lockIconSize = SmsLockIconView.size
            innerSubviewInfos.append(lockIconSize.asManualSubviewInfo(hasFixedWidth: true))
        }

        if statusIndicator != nil {
            let statusSize = StatusIndicator.size
            innerSubviewInfos.append(statusSize.asManualSubviewInfo(hasFixedWidth: true))
        }

        let innerStackMeasurement = ManualStackView.measure(
            config: innerStackConfig,
            measurementBuilder: measurementBuilder,
            measurementKey: Self.measurementKey_innerStack,
            subviewInfos: innerSubviewInfos,
        )
        outerSubviewInfos.append(innerStackMeasurement.measuredSize.asManualSubviewInfo(hasFixedWidth: true))
        let outerStackMeasurement = ManualStackView.measure(
            config: outerStackConfig,
            measurementBuilder: measurementBuilder,
            measurementKey: Self.measurementKey_outerStack,
            subviewInfos: outerSubviewInfos,
            maxWidth: maxWidth,
        )
        return outerStackMeasurement.measuredSize
    }

    private static let hSpacing: CGFloat = 4

    // MARK: - Events

    override public func handleTap(
        sender: UIGestureRecognizer,
        componentDelegate: CVComponentDelegate,
        componentView: CVComponentView,
        renderItem: CVRenderItem,
    ) -> Bool {

        guard let componentView = componentView as? CVComponentViewFooter else {
            owsFailDebug("Unexpected componentView.")
            return false
        }

        switch tapForMoreState {
        case .none:
            break
        case .tapForMore, .undownloadableLongText:
            let readMoreLabel = componentView.tapForMoreLabel
            let location = sender.location(in: readMoreLabel)
            if readMoreLabel.bounds.contains(location) {
                let itemViewModel = CVItemViewModelImpl(renderItem: renderItem)
                switch tapForMoreState {
                case .none:
                    break
                case .tapForMore:
                    componentDelegate.didTapTruncatedTextMessage(itemViewModel)
                case .undownloadableLongText:
                    componentDelegate.didTapUndownloadableOversizeText()
                }
                return true
            }
        }
        if displayEditedLabel {
            let editedLabel = componentView.editedLabel
            let location = sender.location(in: editedLabel)
            if editedLabel.bounds.contains(location) {
                let itemViewModel = CVItemViewModelImpl(renderItem: renderItem)
                componentDelegate.didTapShowEditHistory(itemViewModel)
                return true
            }
        }
        return false
    }

    // MARK: -

    // Used for rendering some portion of an Conversation View item.
    // It could be the entire item or some part thereof.
    public class CVComponentViewFooter: NSObject, CVComponentView {

        fileprivate let outerStack = ManualStackView(name: "footer.outerStack")
        fileprivate let innerStack = ManualStackViewWithLayer(name: "footer.innerStack")
        fileprivate let tapForMoreLabel = CVLabel()
        fileprivate let editedLabel = CVLabel()
        fileprivate let timestampLabel = CVLabel()
        fileprivate let statusIndicatorImageView = CVImageView()
        fileprivate let messageTimerView = MessageTimerView()
        fileprivate let smsLockIconView = SmsLockIconView()
        fileprivate let chatColorView = CVColorOrGradientView()
        fileprivate let pinnedImageView = PinnedMessageIconView()

        public var isDedicatedCellView = false

        public var rootView: UIView {
            outerStack
        }

        override init() {
            timestampLabel.textAlignment = .trailing
        }

        public func setIsCellVisible(_ isCellVisible: Bool) {}

        public func reset() {
            outerStack.reset()
            innerStack.reset()
            innerStack.backgroundColor = nil

            tapForMoreLabel.text = nil
            editedLabel.text = nil
            timestampLabel.text = nil
            statusIndicatorImageView.image = nil

            statusIndicatorImageView.layer.removeAllAnimations()

            messageTimerView.prepareForReuse()
            messageTimerView.removeFromSuperview()

            smsLockIconView.removeFromSuperview()
            pinnedImageView.removeFromSuperview()

            chatColorView.reset()
            chatColorView.removeFromSuperview()
        }

        fileprivate func animateSpinningIcon() {
            let animation = CABasicAnimation(keyPath: "transform.rotation.z")
            animation.toValue = CGFloat.pi * 2
            animation.duration = TimeInterval.second
            animation.isCumulative = true
            animation.repeatCount = .greatestFiniteMagnitude
            statusIndicatorImageView.layer.add(animation, forKey: "animation")
        }
    }
}

// MARK: -

private extension CVComponentFooter {
    /// Is this footer representing an SMS message we restored from a Backup?
    ///
    /// If so, we want to add some UI to indicate such, matching the UI for
    /// these on Android, where they originated.
    var isRepresentingSmsMessageRestoredFromBackup: Bool {
        if
            let message = interaction as? TSMessage,
            message.isSmsMessageRestoredFromBackup
        {
            return true
        }

        return false
    }
}
