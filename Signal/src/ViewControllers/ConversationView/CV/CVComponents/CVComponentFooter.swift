//
// Copyright 2020 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import SignalMessaging
import SignalServiceKit
import SignalUI

public class CVComponentFooter: CVComponentBase, CVComponent {

    public var componentKey: CVComponentKey { .footer }

    struct StatusIndicator: Equatable {
        let imageName: String
        let imageSize: CGSize
        let isAnimated: Bool
    }

    struct State: Equatable {
        let timestampText: String
        let statusIndicator: StatusIndicator?
        let accessibilityLabel: String?
        let hasTapForMore: Bool
        let displayEditedLabel: Bool

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
    private var statusIndicator: StatusIndicator? {
        footerState.statusIndicator
    }
    public var hasTapForMore: Bool {
        footerState.hasTapForMore
    }
    public var displayEditedLabel: Bool {
        footerState.displayEditedLabel
    }
    private var expiration: State.Expiration? {
        footerState.expiration
    }

    let isOverlayingMedia: Bool
    private let isOutsideBubble: Bool

    init(itemModel: CVItemModel,
         footerState: State,
         isOverlayingMedia: Bool,
         isOutsideBubble: Bool) {

        self.footerState = footerState
        self.isOverlayingMedia = isOverlayingMedia
        self.isOutsideBubble = isOutsideBubble

        super.init(itemModel: itemModel)
    }

    public func buildComponentView(componentDelegate: CVComponentDelegate) -> CVComponentView {
        CVComponentViewFooter()
    }

    public override func updateScrollingContent(componentView: CVComponentView) {
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

    public func configureForRendering(componentView componentViewParam: CVComponentView,
                                      cellMeasurement: CVCellMeasurement,
                                      componentDelegate: CVComponentDelegate) {
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

        if isBorderless && conversationStyle.hasWallpaper {
            let chatColorView = componentView.chatColorView
            chatColorView.configure(value: conversationStyle.bubbleChatColor(isIncoming: isIncoming),
                                    referenceView: componentDelegate.view,
                                    hasPillRounding: true)
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
        if wasRemotelyDeleted && !conversationStyle.hasWallpaper {
            owsAssertDebug(!isOverlayingMedia)
            textColor = Theme.primaryTextColor
        } else if isOverlayingMedia {
            textColor = .ows_white
        } else if isOutsideBubble && !conversationStyle.hasWallpaper {
            textColor = Theme.secondaryTextAndIconColor
        } else {
            textColor = conversationStyle.bubbleSecondaryTextColor(isIncoming: isIncoming)
        }

        if displayEditedLabel {
            let editedLabel = componentView.editedLabel
            editedLabelConfig(textColor: textColor).applyForRendering(label: editedLabel)
            innerViews.append(editedLabel)
        }

        timestampLabelConfig(textColor: textColor).applyForRendering(label: timestampLabel)
        innerViews.append(timestampLabel)

        if let expiration = expiration {
            let messageTimerView = componentView.messageTimerView
            messageTimerView.configure(expirationTimestamp: expiration.expirationTimestamp,
                                       initialDurationSeconds: expiration.expiresInSeconds,
                                       tintColor: textColor)
            innerViews.append(messageTimerView)
        }

        if let statusIndicator = self.statusIndicator {
            if let icon = UIImage(named: statusIndicator.imageName) {
                let statusIndicatorImageView = componentView.statusIndicatorImageView
                owsAssertDebug(icon.size == statusIndicator.imageSize)
                statusIndicatorImageView.image = icon.withRenderingMode(.alwaysTemplate)
                statusIndicatorImageView.tintColor = textColor
                innerViews.append(statusIndicatorImageView)

                if statusIndicator.isAnimated {
                    componentView.animateSpinningIcon()
                }
            } else {
                owsFailDebug("Missing statusIndicatorImage.")
            }
        }

        innerStack.configure(config: innerStackConfig,
                             cellMeasurement: cellMeasurement,
                             measurementKey: Self.measurementKey_innerStack,
                             subviews: innerViews)
        outerStack.configure(config: outerStackConfig,
                             cellMeasurement: cellMeasurement,
                             measurementKey: Self.measurementKey_outerStack,
                             subviews: outerViews)
    }

    static func isPendingOutgoingMessage(interaction: TSInteraction) -> Bool {
        guard let outgoingMessage = interaction as? TSOutgoingMessage else {
            return false
        }
        let messageStatus = MessageRecipientStatusUtils.recipientStatus(outgoingMessage: outgoingMessage)
        return messageStatus == .pending
    }

    static func isFailedOutgoingMessage(interaction: TSInteraction) -> Bool {
        guard let outgoingMessage = interaction as? TSOutgoingMessage else {
            return false
        }
        let messageStatus = MessageRecipientStatusUtils.recipientStatus(outgoingMessage: outgoingMessage)
        return messageStatus == .failed
    }

    public static func timestampText(forInteraction interaction: TSInteraction,
                                     shouldUseLongFormat: Bool) -> String {

        let isPendingOutgoingMessage = Self.isPendingOutgoingMessage(interaction: interaction)
        let isFailedOutgoingMessage = Self.isFailedOutgoingMessage(interaction: interaction)
        let wasSentToAnyRecipient: Bool = {
            guard let outgoingMessage = interaction as? TSOutgoingMessage else {
                return false
            }
            return outgoingMessage.wasSentToAnyRecipient
        }()

        if isPendingOutgoingMessage {
            return OWSLocalizedString("MESSAGE_STATUS_PENDING",
                                     comment: "Label indicating that a message send was paused.")
        } else if isFailedOutgoingMessage {
            if wasSentToAnyRecipient {
                return OWSLocalizedString("MESSAGE_STATUS_PARTIALLY_SENT",
                                         comment: "Label indicating that a message was only sent to some recipients.")
            } else {
                return OWSLocalizedString("MESSAGE_STATUS_SEND_FAILED",
                                         comment: "Label indicating that a message failed to send.")
            }
        } else {
            return DateUtil.formatMessageTimestampForCVC(interaction.timestamp,
                                                         shouldUseLongFormat: shouldUseLongFormat)
        }
    }

    static func buildPaymentState(
        interaction: TSInteraction,
        paymentNotification: TSPaymentNotification?,
        hasTapForMore: Bool,
        transaction: SDSAnyReadTransaction
    ) -> State {

        guard
            let receiptData = paymentNotification?.mcReceiptData,
            let paymentModel = PaymentFinder.paymentModels(
                forMcReceiptData: receiptData,
                transaction: transaction).first
        else {
            let timestampText = Self.timestampText(
                forInteraction: interaction,
                shouldUseLongFormat: false
            )
            return State(
                timestampText: timestampText,
                statusIndicator: nil,
                accessibilityLabel: nil,
                hasTapForMore: hasTapForMore,
                displayEditedLabel: false,
                expiration: nil
            )
        }

        let timestampText = Self.paymentMessageTimestampText(
            forInteraction: interaction,
            paymentState: paymentModel.paymentState,
            shouldUseLongFormat: false
        )

        var statusIndicator: StatusIndicator?
        var accessibilityLabel: String?
        if let outgoingMessage = interaction as? TSOutgoingMessage {

            let messageStatus = MessageRecipientStatusUtils.recipientStatus(
                outgoingMessage: outgoingMessage,
                paymentModel: paymentModel
            )
            accessibilityLabel = MessageRecipientStatusUtils.receiptMessage(
                outgoingMessage: outgoingMessage,
                paymentModel: paymentModel
            )

            switch messageStatus {
            case .uploading, .sending:
                statusIndicator = StatusIndicator(
                    imageName: "message_status_sending",
                    imageSize: .square(12),
                    isAnimated: true
                )
            case .pending:
                statusIndicator = StatusIndicator(
                    imageName: "message_status_sending",
                    imageSize: .square(12),
                    isAnimated: false
                )
            case .sent, .skipped:
                statusIndicator = StatusIndicator(
                    imageName: "message_status_sent",
                    imageSize: .square(12),
                    isAnimated: false
                )
            case .delivered:
                statusIndicator = StatusIndicator(
                    imageName: "message_status_delivered",
                    imageSize: .init(width: 18, height: 12),
                    isAnimated: false
                )
            case .read, .viewed:
                statusIndicator = StatusIndicator(
                    imageName: "message_status_read",
                    imageSize: .init(width: 18, height: 12),
                    isAnimated: false
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
        if let message = interaction as? TSMessage,
           message.hasPerConversationExpiration {
            expiration = State.Expiration(
                expirationTimestamp: message.expiresAt,
                expiresInSeconds: message.expiresInSeconds
            )
        }

        return State(
            timestampText: timestampText,
            statusIndicator: statusIndicator,
            accessibilityLabel: accessibilityLabel,
            hasTapForMore: hasTapForMore,
            displayEditedLabel: false,
            expiration: expiration
        )
    }

    public static func paymentMessageTimestampText(
        forInteraction interaction: TSInteraction,
        paymentState: TSPaymentState,
        shouldUseLongFormat: Bool
    ) -> String {

        switch paymentState.messageReceiptStatus {
        case .pending:
            return OWSLocalizedString(
                "MESSAGE_STATUS_PENDING",
                comment: "Label indicating that a message send was paused."
            )
        case .failed:
            return OWSLocalizedString(
                "MESSAGE_STATUS_SEND_FAILED",
                comment: "Label indicating that a message failed to send."
            )
        default:
            return DateUtil.formatMessageTimestampForCVC(
                interaction.timestamp,
                shouldUseLongFormat: shouldUseLongFormat
            )
        }
    }

    static func buildState(interaction: TSInteraction, hasTapForMore: Bool) -> State {

        let timestampText = Self.timestampText(forInteraction: interaction,
                                               shouldUseLongFormat: false)

        var statusIndicator: StatusIndicator?
        var accessibilityLabel: String?
        if let outgoingMessage = interaction as? TSOutgoingMessage {
            let messageStatus = MessageRecipientStatusUtils.recipientStatus(outgoingMessage: outgoingMessage)
            accessibilityLabel = MessageRecipientStatusUtils.receiptMessage(outgoingMessage: outgoingMessage)

            switch messageStatus {
            case .uploading, .sending:
                statusIndicator = StatusIndicator(imageName: "message_status_sending",
                                                  imageSize: .square(12),
                                                  isAnimated: true)
            case .pending:
                statusIndicator = StatusIndicator(imageName: "message_status_sending",
                                                  imageSize: .square(12),
                                                  isAnimated: false)
            case .sent, .skipped:
                statusIndicator = StatusIndicator(imageName: "message_status_sent",
                                                  imageSize: .square(12),
                                                  isAnimated: false)
            case .delivered:
                statusIndicator = StatusIndicator(imageName: "message_status_delivered",
                                                  imageSize: .init(width: 18, height: 12),
                                                  isAnimated: false)
            case .read, .viewed:
                statusIndicator = StatusIndicator(imageName: "message_status_read",
                                                  imageSize: .init(width: 18, height: 12),
                                                  isAnimated: false)
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
                    expiresInSeconds: message.expiresInSeconds
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
            hasTapForMore: hasTapForMore,
            displayEditedLabel: displayEditedLabel,
            expiration: expiration
        )
    }

    private func editedLabelConfig(textColor: UIColor) -> CVLabelConfig {
        let text = OWSLocalizedString(
            "MESSAGE_STATUS_EDITED",
            comment: "status meesage for edited messages"
        )

        return CVLabelConfig.unstyledText(
            text,
            font: .dynamicTypeCaption1,
            textColor: textColor
        )
    }

    private func timestampLabelConfig(textColor: UIColor) -> CVLabelConfig {
        return CVLabelConfig.unstyledText(
            timestampText,
            font: .dynamicTypeCaption1,
            textColor: textColor
        )
    }

    private var tapForMoreLabelConfig: CVLabelConfig? {
        guard hasTapForMore, !wasRemotelyDeleted else {
            return nil
        }
        guard let message = interaction as? TSMessage else {
            owsFailDebug("Invalid interaction.")
            return nil
        }
        let text = OWSLocalizedString("CONVERSATION_VIEW_OVERSIZE_TEXT_TAP_FOR_MORE",
                                     comment: "Indicator on truncated text messages that they can be tapped to see the entire text message.")
        return CVLabelConfig.unstyledText(
            text,
            font: UIFont.dynamicTypeSubheadlineClamped.semibold(),
            textColor: conversationStyle.bubbleReadMoreTextColor(message: message),
            textAlignment: .trailing
        )
    }

    private let tapForMoreHeightFactor: CGFloat = 1.25

    private var outerStackConfig: CVStackViewConfig {
        CVStackViewConfig(axis: .horizontal,
                          alignment: .bottom,
                          spacing: CVComponentFooter.hSpacing,
                          layoutMargins: .zero)
    }

    private var innerStackConfig: CVStackViewConfig {
        let layoutMargins = isBorderless ? UIEdgeInsets(hMargin: 12, vMargin: 3) : .zero
        return CVStackViewConfig(axis: .horizontal,
                                 alignment: .center,
                                 spacing: CVComponentFooter.hSpacing,
                                 layoutMargins: layoutMargins)
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
            var tapForMoreSize = CVText.measureLabel(config: tapForMoreLabelConfig,
                                                     maxWidth: maxWidth)
            tapForMoreSize.height *= tapForMoreHeightFactor
            outerSubviewInfos.append(tapForMoreSize.asManualSubviewInfo(hasFixedWidth: true))
        }

        // We always use a stretching spacer.
        outerSubviewInfos.append(ManualStackSubviewInfo.empty)

        if displayEditedLabel {
            let editedLabelConfig = self.editedLabelConfig(textColor: .black)
            let editedLabelSize = CVText.measureLabel(config: editedLabelConfig, maxWidth: maxWidth)
            innerSubviewInfos.append(editedLabelSize.asManualSubviewInfo(hasFixedWidth: true))
        }

        // The color doesn't matter for measurement.
        let timestampLabelConfig = self.timestampLabelConfig(textColor: UIColor.black)
        let timestampLabelSize = CVText.measureLabel(config: timestampLabelConfig,
                                                     maxWidth: maxWidth)
        innerSubviewInfos.append(timestampLabelSize.asManualSubviewInfo(hasFixedWidth: true))

        if hasPerConversationExpiration,
           nil != interaction as? TSMessage {
            let timerSize = MessageTimerView.measureSize
            innerSubviewInfos.append(timerSize.asManualSubviewInfo(hasFixedWidth: true))
        }

        if let statusIndicator = self.statusIndicator {
            let statusSize = statusIndicator.imageSize
            innerSubviewInfos.append(statusSize.asManualSubviewInfo(hasFixedWidth: true))
        }

        let innerStackMeasurement = ManualStackView.measure(config: innerStackConfig,
                                                            measurementBuilder: measurementBuilder,
                                                            measurementKey: Self.measurementKey_innerStack,
                                                            subviewInfos: innerSubviewInfos)
        outerSubviewInfos.append(innerStackMeasurement.measuredSize.asManualSubviewInfo(hasFixedWidth: true))
        let outerStackMeasurement = ManualStackView.measure(config: outerStackConfig,
                                                            measurementBuilder: measurementBuilder,
                                                            measurementKey: Self.measurementKey_outerStack,
                                                            subviewInfos: outerSubviewInfos,
                                                            maxWidth: maxWidth)
        return outerStackMeasurement.measuredSize
    }

    private static let hSpacing: CGFloat = 4

    // MARK: - Events

    public override func handleTap(sender: UITapGestureRecognizer,
                                   componentDelegate: CVComponentDelegate,
                                   componentView: CVComponentView,
                                   renderItem: CVRenderItem) -> Bool {

        guard let componentView = componentView as? CVComponentViewFooter else {
            owsFailDebug("Unexpected componentView.")
            return false
        }

        if hasTapForMore {
            let readMoreLabel = componentView.tapForMoreLabel
            let location = sender.location(in: readMoreLabel)
            if readMoreLabel.bounds.contains(location) {
                let itemViewModel = CVItemViewModelImpl(renderItem: renderItem)
                componentDelegate.didTapTruncatedTextMessage(itemViewModel)
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
        fileprivate let chatColorView = CVColorOrGradientView()

        public var isDedicatedCellView = false

        public var rootView: UIView {
            outerStack
        }

        override required init() {
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
            chatColorView.reset()
            chatColorView.removeFromSuperview()
        }

        fileprivate func animateSpinningIcon() {
            let animation = CABasicAnimation.init(keyPath: "transform.rotation.z")
            animation.toValue = CGFloat.pi * 2
            animation.duration = kSecondInterval * 1
            animation.isCumulative = true
            animation.repeatCount = .greatestFiniteMagnitude
            statusIndicatorImageView.layer.add(animation, forKey: "animation")
        }
    }
}
