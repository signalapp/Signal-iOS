//
// Copyright 2022 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

//
//  Copyright (c) 2022 Open Whisper Systems. All rights reserved.
//

import Foundation
import SignalCoreKit
import SignalServiceKit
import SignalUI

@objc
public class CVComponentPaymentAttachment: CVComponentBase, CVComponent {

    public var componentKey: CVComponentKey { .paymentAttachment }

    private let paymentAttachment: CVComponentState.PaymentAttachment
    private let paymentModel: TSPaymentModel?
    private let paymentAmount: UInt64?
    private let contactName: String
    private let messageStatus: MessageReceiptStatus

    init(
        itemModel: CVItemModel,
        paymentAttachment: CVComponentState.PaymentAttachment,
        paymentModel: TSPaymentModel?,
        contactName: String,
        paymentAmount: UInt64?,
        messageStatus: MessageReceiptStatus?
    ) {
        self.paymentAttachment = paymentAttachment
        self.paymentModel = paymentModel
        self.contactName = contactName
        self.paymentAmount = paymentAmount

        // If no messageStatus have different defaults for incoming vs outgoing
        switch (messageStatus, itemModel.interaction.interactionType) {
        case (nil, .incomingMessage):
            // Use .sent as default for "incoming" so debug UI shows up correct
            self.messageStatus = .sent
        case (.some(let messageStatus), _):
            self.messageStatus = messageStatus
        default:
            // Default to .failed for all other cases where `messageStatus == nil`
            self.messageStatus = .failed
        }

        super.init(itemModel: itemModel)
    }

    public func buildComponentView(componentDelegate: CVComponentDelegate) -> CVComponentView {
        CVComponentViewPaymentAttachment()
    }

    public func configureForRendering(
        componentView componentViewParam: CVComponentView,
        cellMeasurement: CVCellMeasurement,
        componentDelegate: CVComponentDelegate
    ) {
        guard let componentView = componentViewParam as? CVComponentViewPaymentAttachment else {
            owsFailDebug("Unexpected componentView.")
            componentViewParam.reset()
            return
        }

        let bigAmountLabel = componentView.bigAmountLabel
        bigAmountLabelConfig.applyForRendering(label: bigAmountLabel)
        bigAmountLabel.alpha = messageStatus.bigAmountLabelAlpha
        bigAmountLabel.numberOfLines = messageStatus.bigAmountLabelNumberOfLines

        let topLabel = componentView.topLabel
        topLabelConfig.applyForRendering(label: topLabel)

        let hStackView = componentView.hStackView
        hStackView.addBlurBackgroundExactlyOnce(isIncoming: isIncoming)

        // Reset left space for status
        componentView.leftSpace.removeAllSubviews()

        let hInnerSubviews: [UIView]
        switch messageStatus {
        case .sending:
            componentView.leftSpace.addSubview(self.createLoadingSpinner())
            hInnerSubviews = [
                componentView.leftSpace,
                componentView.bigAmountLabel,
                componentView.rightSpace
            ]
        case .failed:
            componentView.leftSpace.addSubview(self.createFailureIcon())
            hInnerSubviews = [
                componentView.leftSpace,
                componentView.bigAmountLabel
            ]
        default:
            hInnerSubviews = [
                componentView.leftSpace,
                componentView.bigAmountLabel,
                componentView.rightSpace
            ]
        }

        hStackView.configure(
            config: hStackConfig,
            cellMeasurement: cellMeasurement,
            measurementKey: .measurementKey_hStack,
            subviews: hInnerSubviews
        )

        let vStackView = componentView.vStackView

        let vInnerSubviews: [UIView]
        if paymentAttachment.notification.memoMessage != nil {
            noteLabelConfig.applyForRendering(label: componentView.noteLabel)
            vInnerSubviews = [topLabel, hStackView, componentView.noteLabel]
        } else {
            vInnerSubviews = [topLabel, hStackView]
        }

        vStackView.configure(
            config: vStackConfig,
            cellMeasurement: cellMeasurement,
            measurementKey: .measurementKey_vStack,
            subviews: vInnerSubviews
        )
    }

    private func createLoadingSpinner() -> CustomView {
        // Recreate each time in-case theme changes
        let animationName = (isIncoming && !isDarkThemeEnabled
                             ? "indeterminate_spinner_blue"
                             : "indeterminate_spinner_white")

        let animationView = mediaCache.buildLottieAnimationView(name: animationName)
        owsAssertDebug(animationView.animation != nil)
        animationView.backgroundBehavior = .pauseAndRestore
        animationView.loopMode = .loop
        animationView.contentMode = .scaleAspectFit
        animationView.play()

        return CustomView.wrapperFor(view: animationView, dimension: .spinnerSquareDimension)
    }

    private func createFailureIcon() -> CustomView {
        let tintColor = conversationStyle.bubbleTextColor(isIncoming: isIncoming)
        return CustomView.wrapperFor(
            view: UIImageView.createFailureIcon(tintColor: tintColor),
            dimension: .failureIconDimension)
    }

    private func formatPaymentAmount(status: MessageReceiptStatus) -> NSAttributedString {
        guard let mob = paymentAmount else {
            let text = OWSLocalizedString(
                "PAYMENTS_INFO_UNAVAILABLE_MESSAGE",
                comment: "Status indicator for invalid payments which could not be processed."
            )
            return NSAttributedString(string: text)
        }

        let amount = TSPaymentAmount(currency: .mobileCoin, picoMob: mob)
        switch status {
        case .failed:
            return PaymentsFormat.formatInChatFailure(paymentAmount: amount)
        default:
            return PaymentsFormat.formatInChatSuccess(paymentAmount: amount)
        }
    }

    private var hStackConfig: CVStackViewConfig {
        CVStackViewConfig(
            axis: .horizontal,
            alignment: .center,
            spacing: .innerHStackSpacing,
            layoutMargins: UIEdgeInsets(top: 25, leading: 8, bottom: 25, trailing: 16)
        )
    }

    private var vStackConfig: CVStackViewConfig {
        CVStackViewConfig(
            axis: .vertical,
            alignment: .leading,
            spacing: 8,
            layoutMargins: UIEdgeInsets(top: 5, leading: 0, bottom: 0, trailing: 0)
        )
    }

    private var bigAmountLabelConfig: CVLabelConfig {
        let font = UIFont.dynamicTypeLargeTitle1Clamped.withSize(28)
        return CVLabelConfig(
            text: .attributedText(formatPaymentAmount(status: messageStatus)),
            displayConfig: .forUnstyledText(
                font: font,
                textColor: conversationStyle.bubbleTextColor(isIncoming: isIncoming)
            ),
            font: font,
            textColor: conversationStyle.bubbleTextColor(isIncoming: isIncoming),
            numberOfLines: messageStatus.bigAmountLabelNumberOfLines,
            lineBreakMode: .byWordWrapping,
            textAlignment: messageStatus.bigAmountLabelTextAlignment
        )
    }

    private var topLabelConfig: CVLabelConfig {
        let text: String
        let paymentType = paymentModel?.paymentType
        let interactionType = itemModel.interaction.interactionType
        switch (paymentType, interactionType, messageStatus) {
        case (_, _, .sending):
            text = OWSLocalizedString(
                "PAYMENTS_PAYMENT_STATUS_IN_CHAT_PROCESSING",
                comment: "Payment status context while sending"
            )
        case (_, .incomingMessage, _),
            (.incomingPayment, _, _),
            (.incomingUnidentified, _, _):
            let format = OWSLocalizedString(
                "PAYMENTS_PAYMENT_STATUS_IN_CHAT_SENT_YOU",
                comment: "Payment status context with contact name, incoming. Embeds {{ Name of sending contact }}"
            )
            text = String(format: format, contactName)
        case (_, .outgoingMessage, .failed):
            let format = OWSLocalizedString(
                "PAYMENTS_PAYMENT_STATUS_IN_CHAT_PAYMENT_TO",
                comment: "Payment status context with contact name, failed. Embeds {{ Name of receiving contact }}"
            )
            text = String(format: format, contactName)
        case (_, .outgoingMessage, _):
            let format = OWSLocalizedString(
                "PAYMENTS_PAYMENT_STATUS_IN_CHAT_YOU_SENT",
                comment: "Payment status context with contact name, sent. Embeds {{ Name of receiving contact }}"
            )
            text = String(format: format, contactName)
        default:
            // default to failed text because it doesn't imply success
            let format = OWSLocalizedString(
                "PAYMENTS_PAYMENT_STATUS_IN_CHAT_PAYMENT_TO",
                comment: "Payment status context with contact name, failed. Embeds {{ Name of receiving contact }}"
            )
            text = String(format: format, contactName)
        }

        return CVLabelConfig(
            text: .text(text),
            displayConfig: .forUnstyledText(
                font: .dynamicTypeBody,
                textColor: conversationStyle.bubbleTextColor(isIncoming: isIncoming)
            ),
            font: UIFont.dynamicTypeBody,
            textColor: conversationStyle.bubbleTextColor(isIncoming: isIncoming),
            lineBreakMode: .byTruncatingMiddle
        )
    }

    private var noteLabelConfig: CVLabelConfig {
        CVLabelConfig(
            text: .text(paymentAttachment.notification.memoMessage ?? ""),
            displayConfig: .forUnstyledText(
                font: .dynamicTypeBody,
                textColor: conversationStyle.bubbleTextColor(isIncoming: isIncoming)
            ),
            font: UIFont.dynamicTypeBody,
            textColor: conversationStyle.bubbleTextColor(isIncoming: isIncoming),
            numberOfLines: 0,
            lineBreakMode: .byTruncatingMiddle
        )
    }

    public func measure(
        maxWidth: CGFloat,
        measurementBuilder: CVCellMeasurement.Builder
    ) -> CGSize {
        owsAssertDebug(maxWidth > 0)

        let maxLabelWidth = max(0, maxWidth - vStackConfig.layoutMargins.totalWidth)

        let maxBigLabelWidth: CGFloat = {
            let nonLabelWidth =
            (hStackConfig.layoutMargins.totalWidth
             + messageStatus.hStackCumulativeSpacing
             + vStackConfig.layoutMargins.totalWidth
             + messageStatus.spacersTotalWidth)

            return max(0, maxWidth - nonLabelWidth)
        }()

        let bigAmountLabelSize = CVText.measureLabel(
            config: bigAmountLabelConfig,
            maxWidth: maxBigLabelWidth
        )
        let statusIconSize = CGSize(square: messageStatus.statusIconDimension)

        var hSubviewInfos = [ManualStackSubviewInfo]()
        hSubviewInfos.append(statusIconSize.asManualSubviewInfo())
        hSubviewInfos.append(bigAmountLabelSize.asManualSubviewInfo())
        if messageStatus != .failed {
            hSubviewInfos.append(statusIconSize.asManualSubviewInfo())
        }
        let hStackMeasurement = ManualStackView.measure(
            config: hStackConfig,
            measurementBuilder: measurementBuilder,
            measurementKey: .measurementKey_hStack,
            subviewInfos: hSubviewInfos,
            maxWidth: maxWidth
        )

        let maxTopLabelWidth = min(maxLabelWidth, hStackMeasurement.measuredSize.width)
        let maxNoteLabelWidth = maxTopLabelWidth // Same for now
        let topLabelSize = CVText.measureLabel(config: topLabelConfig, maxWidth: maxTopLabelWidth)
        let noteLabelSize = CVText.measureLabel(
            config: noteLabelConfig,
            maxWidth: maxNoteLabelWidth
        )

        var vSubviewInfos = [ManualStackSubviewInfo]()
        vSubviewInfos.append(topLabelSize.asManualSubviewInfo())
        vSubviewInfos.append(hStackMeasurement.measuredSize.asManualSubviewInfo)

        if paymentAttachment.notification.memoMessage != nil {
            vSubviewInfos.append(noteLabelSize.asManualSubviewInfo())
        }

        let vStackMeasurement = ManualStackView.measure(
            config: vStackConfig,
            measurementBuilder: measurementBuilder,
            measurementKey: .measurementKey_vStack,
            subviewInfos: vSubviewInfos
        )

        return vStackMeasurement.measuredSize
    }

    // MARK: - CVComponentView

    // Used for rendering some portion of an Conversation View item.
    // It could be the entire item or some part thereof.
    public class CVComponentViewPaymentAttachment: NSObject, CVComponentView {

        fileprivate let hStackView = ManualStackView(name: "PaymentAttachment.hStackView")
        fileprivate let vStackView = ManualStackView(name: "PaymentAttachment.vStackView")

        fileprivate var leftSpace = UIView()
        fileprivate var rightSpace = UIView()

        fileprivate let bigAmountLabel = CVLabel()
        fileprivate let topLabel = CVLabel()
        fileprivate let noteLabel = CVLabel()

        public var isDedicatedCellView = true

        public var rootView: UIView {
            vStackView
        }

        public func setIsCellVisible(_ isCellVisible: Bool) {}

        public func reset() {
            hStackView.reset()
            vStackView.reset()

            bigAmountLabel.text = nil
            topLabel.text = nil
            noteLabel.text = nil

            leftSpace.removeAllSubviews()
            rightSpace.removeAllSubviews()
        }
    }

    public override func handleTap(
        sender: UITapGestureRecognizer,
        componentDelegate: CVComponentDelegate,
        componentView: CVComponentView,
        renderItem: CVRenderItem
    ) -> Bool {
        guard let paymentModel = paymentModel else { return false }
        componentDelegate.didTapPayment(paymentModel, displayName: contactName)
        return true
    }
}

// MARK: - Constants & Utils

fileprivate extension String {
    static let measurementKey_hStack = "CVComponentPaymentAttachment.measurementKey_hStack"
    static let measurementKey_vStack = "CVComponentPaymentAttachment.measurementKey_vStack"
}

extension CVComponentPaymentAttachment: CVAccessibilityComponent {
    public var accessibilityDescription: String {
        return formatPaymentAmount(status: messageStatus).string
    }
}

fileprivate extension UIView {
    @discardableResult
    func addBlur(style: UIBlurEffect.Style = .extraLight) -> UIVisualEffectView {
        let blurEffect = UIBlurEffect(style: style)
        let blurBackground = UIVisualEffectView(effect: blurEffect)
        blurBackground.alpha = 0.3
        blurBackground.layer.cornerRadius = 18
        blurBackground.clipsToBounds = true
        blurBackground.frame = self.frame // your view that have any objects
        blurBackground.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        addSubview(blurBackground)
        return blurBackground
    }
}

private class CustomView: UIView {
    var dimension: CGFloat = .spinnerSquareDimension

    override var intrinsicContentSize: CGSize {
        CGSize(square: dimension)
    }

    static func wrapperFor(view: UIView, dimension: CGFloat) -> CustomView {
        let wrapper = CustomView()

        wrapper.contentMode = .center
        wrapper.dimension = dimension
        wrapper.addSubview(view)
        view.translatesAutoresizingMaskIntoConstraints = false
        view.contentMode = .scaleAspectFit

        view.centerXAnchor.constraint(equalTo: wrapper.centerXAnchor).isActive = true
        view.centerYAnchor.constraint(equalTo: wrapper.centerYAnchor).isActive = true
        view.heightAnchor.constraint(equalToConstant: dimension).isActive = true
        view.widthAnchor.constraint(equalToConstant: dimension).isActive = true

        wrapper.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            wrapper.heightAnchor.constraint(equalToConstant: dimension),
            wrapper.widthAnchor.constraint(equalTo: wrapper.heightAnchor, multiplier: 1)
        ])

        return wrapper
    }
}

extension CGFloat {
    fileprivate static let spinnerSquareDimension: CGFloat = 20
    fileprivate static let failureIconDimension: CGFloat = 22
    fileprivate static let innerHStackSpacing: CGFloat = 9
}

fileprivate extension MessageReceiptStatus {
    var bigAmountLabelAlpha: CGFloat {
        self == .sending ? 0.5 : 1
    }

    var bigAmountLabelNumberOfLines: Int {
        self == .failed ? 2 : 1
    }

    var bigAmountLabelTextAlignment: NSTextAlignment {
        self == .failed ? .left : .center
    }

    var statusIconDimension: CGFloat {
        self == .failed ? .failureIconDimension : .spinnerSquareDimension
    }

    var spacersTotalWidth: CGFloat {
        self == .failed ? .failureIconDimension : .spinnerSquareDimension * 2
    }

    var hStackCumulativeSpacing: CGFloat {
        self == .failed ? .innerHStackSpacing : .innerHStackSpacing * 2
    }
}

fileprivate extension ManualStackView {
    func addBlurBackgroundExactlyOnce(isIncoming: Bool) {
        var subviewsToCheck = self.subviews
        while let subviewToCheck = subviewsToCheck.popLast() {
            if subviewToCheck is UIVisualEffectView {
                // already exists
                return
            }
            subviewsToCheck = subviewToCheck.subviews + subviewsToCheck
        }

        let effect: UIBlurEffect.Style = {
            (Theme.isDarkThemeEnabled && isIncoming) ? .regular : .extraLight
        }()

        let blurBackground = self.addBlur(style: effect)
        blurBackground.alpha = {
            switch (Theme.isDarkThemeEnabled, isIncoming) {
            case (_, false):
                return 0.4
            case (true, true):
                return 1
            case (false, true):
                return 1
            }
        }()
    }
}

fileprivate extension UIImageView {
    static func createFailureIcon(tintColor: UIColor) -> UIImageView {
        let sendFailureBadge = UIImageView(frame: .zero)
        sendFailureBadge.contentMode = .center
        sendFailureBadge.setTemplateImageName("error-outline-24", tintColor: tintColor)
        sendFailureBadge.backgroundColor = UIColor.clear
        sendFailureBadge.layer.cornerRadius = .failureIconDimension / 2
        sendFailureBadge.clipsToBounds = true

        return sendFailureBadge
    }
}
