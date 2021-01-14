//
//  Copyright (c) 2020 Open Whisper Systems. All rights reserved.
//

import Foundation

@objc
public class CVComponentFooter: CVComponentBase, CVComponent {

    struct State: Equatable {
        let timestampText: String
        let isFailedOutgoingMessage: Bool
        let statusIndicatorImageName: String?
        let isStatusIndicatorAnimated: Bool
        let accessibilityLabel: String?
        let hasTapForMore: Bool

        struct Expiration: Equatable {
            let expirationTimestamp: UInt64
            let expiresInSeconds: UInt32
        }
        let expiration: Expiration?

    }
    private let footerState: State

    private var timestampText: String {
        footerState.timestampText
    }
    private var isFailedOutgoingMessage: Bool {
        footerState.isFailedOutgoingMessage
    }
    private var statusIndicatorImageName: String? {
        footerState.statusIndicatorImageName
    }
    private var isStatusIndicatorAnimated: Bool {
        footerState.isStatusIndicatorAnimated
    }
    private var hasStatusIndicator: Bool {
        statusIndicatorImageName != nil
    }
    public var hasTapForMore: Bool {
        footerState.hasTapForMore
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
        outerStack.apply(config: outerStackConfig)
        innerStack.apply(config: innerStackConfig)

        var outerViews = [UIView]()
        var innerViews = [UIView]()

        if let tapForMoreLabelConfig = self.tapForMoreLabelConfig {
            let tapForMoreLabel = componentView.tapForMoreLabel
            tapForMoreLabelConfig.applyForRendering(label: tapForMoreLabel)
            let tapForMoreHeight = tapForMoreLabelConfig.font.lineHeight * tapForMoreHeightFactor
            componentView.constraints.append(tapForMoreLabel.autoSetDimension(.height, toSize: tapForMoreHeight))
            outerViews.append(tapForMoreLabel)
        }

        // We always use a stretching spacer.
        outerViews.append(UIView.hStretchingSpacer())
        outerViews.append(innerStack)

        let timestampLabel = componentView.timestampLabel
        let textColor: UIColor
        if wasRemotelyDeleted {
            owsAssertDebug(!isOverlayingMedia)
            textColor = Theme.primaryTextColor
        } else if isOverlayingMedia {
            textColor = .ows_white
        } else if isOutsideBubble {
            textColor = Theme.secondaryTextAndIconColor
        } else {
            textColor = conversationStyle.bubbleSecondaryTextColor(isIncoming: isIncoming)
        }
        timestampLabelConfig(textColor: textColor).applyForRendering(label: componentView.timestampLabel)
        innerViews.append(timestampLabel)

        if let expiration = expiration {
            let messageTimerView = componentView.messageTimerView
            messageTimerView.configure(withExpirationTimestamp: expiration.expirationTimestamp,
                                       initialDurationSeconds: expiration.expiresInSeconds,
                                       tintColor: textColor)
            innerViews.append(messageTimerView)
        }

        if let statusIndicatorImageName = self.statusIndicatorImageName {
            if let icon = UIImage(named: statusIndicatorImageName) {
                let statusIndicatorImageView = componentView.statusIndicatorImageView
                owsAssertDebug(icon.size.width <= CVComponentFooter.maxImageWidth)
                statusIndicatorImageView.image = icon.withRenderingMode(.alwaysTemplate)
                statusIndicatorImageView.tintColor = textColor
                innerViews.append(statusIndicatorImageView)

                if isStatusIndicatorAnimated {
                    componentView.animateSpinningIcon()
                }
            } else {
                owsFailDebug("Missing statusIndicatorImage.")
            }
        }

        outerStack.addArrangedSubviews(outerViews, reverseOrder: isIncoming)
        innerStack.addArrangedSubviews(innerViews)

        componentView.rootView.accessibilityLabel = footerState.accessibilityLabel
    }

    static func buildState(interaction: TSInteraction,
                           hasTapForMore: Bool) -> State {

        let isFailedOutgoingMessage: Bool = {
            guard let outgoingMessage = interaction as? TSOutgoingMessage else {
                return false
            }
            let messageStatus = MessageRecipientStatusUtils.recipientStatus(outgoingMessage: outgoingMessage)
            return messageStatus == .failed
        }()
        let wasSentToAnyRecipient: Bool = {
            guard let outgoingMessage = interaction as? TSOutgoingMessage else {
                return false
            }
            return outgoingMessage.wasSentToAnyRecipient
        }()

        let timestampText: String
        if isFailedOutgoingMessage {
            timestampText = (wasSentToAnyRecipient
                                ? NSLocalizedString(
                                    "MESSAGE_STATUS_PARTIALLY_SENT",
                                    comment: "Label indicating that a message was only sent to some recipients.")
                                : NSLocalizedString("MESSAGE_STATUS_SEND_FAILED",
                                                    comment: "Label indicating that a message failed to send."))
        } else {
            timestampText = DateUtil.formatMessageTimestamp(interaction.timestamp)
        }

        var statusIndicatorImageName: String?
        var isStatusIndicatorAnimated: Bool = false
        var accessibilityLabel: String?
        if let outgoingMessage = interaction as? TSOutgoingMessage {
            let messageStatus = MessageRecipientStatusUtils.recipientStatus(outgoingMessage: outgoingMessage)
            accessibilityLabel = MessageRecipientStatusUtils.receiptMessage(outgoingMessage: outgoingMessage)
            switch messageStatus {
            case .uploading, .sending:
                statusIndicatorImageName = "message_status_sending"
                isStatusIndicatorAnimated = true
            case .sent, .skipped:
                statusIndicatorImageName = "message_status_sent"
            case .delivered:
                statusIndicatorImageName = "message_status_delivered"
            case .read:
                statusIndicatorImageName = "message_status_read"
            case .failed:
                // No status indicator icon.
                break
            }

            if outgoingMessage.wasRemotelyDeleted {
                statusIndicatorImageName = nil
            }
        }

        var expiration: State.Expiration?
        if let message = interaction as? TSMessage,
           message.hasPerConversationExpiration {
            expiration = State.Expiration(expirationTimestamp: message.expiresAt,
                                          expiresInSeconds: message.expiresInSeconds)
        }

        return State(timestampText: timestampText,
                     isFailedOutgoingMessage: isFailedOutgoingMessage,
                     statusIndicatorImageName: statusIndicatorImageName,
                     isStatusIndicatorAnimated: isStatusIndicatorAnimated,
                     accessibilityLabel: accessibilityLabel,
                     hasTapForMore: hasTapForMore,
                     expiration: expiration)
    }

    private func timestampLabelConfig(textColor: UIColor) -> CVLabelConfig {
        return CVLabelConfig(text: timestampText,
                             font: .ows_dynamicTypeCaption1,
                             textColor: textColor)
    }

    private var tapForMoreLabelConfig: CVLabelConfig? {
        guard hasTapForMore, !wasRemotelyDeleted else {
            return nil
        }
        guard let message = interaction as? TSMessage else {
            owsFailDebug("Invalid interaction.")
            return nil
        }
        let text = NSLocalizedString("CONVERSATION_VIEW_OVERSIZE_TEXT_TAP_FOR_MORE",
                                     comment: "Indicator on truncated text messages that they can be tapped to see the entire text message.")
        return CVLabelConfig(text: text,
                             font: UIFont.ows_dynamicTypeSubheadlineClamped.ows_semibold,
                             textColor: conversationStyle.bubbleReadMoreTextColor(message: message),
                             textAlignment: UIView.textAlignmentUnnatural())
    }

    private let tapForMoreHeightFactor: CGFloat = 1.25

    private var outerStackConfig: CVStackViewConfig {
        CVStackViewConfig(axis: .horizontal,
                          alignment: .bottom,
                          spacing: CVComponentFooter.hSpacing,
                          layoutMargins: .zero)
    }

    private var innerStackConfig: CVStackViewConfig {
        CVStackViewConfig(axis: .horizontal,
                          alignment: .center,
                          spacing: CVComponentFooter.hSpacing,
                          layoutMargins: .zero)
    }

    public func measure(maxWidth: CGFloat, measurementBuilder: CVCellMeasurement.Builder) -> CGSize {
        owsAssertDebug(maxWidth > 0)

        var subviewSizes = [CGSize]()

        if let tapForMoreLabelConfig = self.tapForMoreLabelConfig {
            var tapForMoreSize = CVText.measureLabel(config: tapForMoreLabelConfig,
                                                     maxWidth: maxWidth)
            tapForMoreSize.height *= tapForMoreHeightFactor
            subviewSizes.append(tapForMoreSize)
        }

        // We always use a stretching spacer.
        subviewSizes.append(.zero)

        // The color doesn't matter for measurement.
        let timestampLabelConfig = self.timestampLabelConfig(textColor: UIColor.black)
        subviewSizes.append(CVText.measureLabel(config: timestampLabelConfig,
                                                maxWidth: maxWidth))

        if hasPerConversationExpiration,
           nil != interaction as? TSMessage {
            subviewSizes.append(OWSMessageTimerView.measureSize())
        }

        if hasStatusIndicator {
            subviewSizes.append(CGSize(width: Self.maxImageWidth, height: 0))
        }

        return CVStackView.measure(config: innerStackConfig, subviewSizes: subviewSizes).ceil
    }

    private static let hSpacing: CGFloat = 4
    private static let maxImageWidth: CGFloat = 18
    private static let imageHeight: CGFloat = 12

    // MARK: - Events

    public override func handleTap(sender: UITapGestureRecognizer,
                                   componentDelegate: CVComponentDelegate,
                                   componentView: CVComponentView,
                                   renderItem: CVRenderItem) -> Bool {
        guard hasTapForMore else {
            return false
        }
        let itemViewModel = CVItemViewModelImpl(renderItem: renderItem)
        componentDelegate.cvc_didTapTruncatedTextMessage(itemViewModel)
        return true
    }

    // MARK: -

    // Used for rendering some portion of an Conversation View item.
    // It could be the entire item or some part thereof.
    @objc
    public class CVComponentViewFooter: NSObject, CVComponentView {

        fileprivate let outerStack = OWSStackView(name: "footer.outerStack")
        fileprivate let innerStack = OWSStackView(name: "footer.innerStack")
        fileprivate let tapForMoreLabel = UILabel()
        fileprivate let timestampLabel = UILabel()
        fileprivate let statusIndicatorImageView = UIImageView()
        fileprivate let messageTimerView = OWSMessageTimerView()

        fileprivate var constraints = [NSLayoutConstraint]()

        public var isDedicatedCellView = false

        public var rootView: UIView {
            outerStack
        }

        override required init() {
            timestampLabel.textAlignment = UIView.textAlignmentUnnatural()
        }

        public func setIsCellVisible(_ isCellVisible: Bool) {}

        public func reset() {
            outerStack.reset()
            innerStack.reset()

            tapForMoreLabel.text = nil
            timestampLabel.text = nil
            statusIndicatorImageView.image = nil

            statusIndicatorImageView.layer.removeAllAnimations()
            messageTimerView.prepareForReuse()

            NSLayoutConstraint.deactivate(constraints)
            constraints = []
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
