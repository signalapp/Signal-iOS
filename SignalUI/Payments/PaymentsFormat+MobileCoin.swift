//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import MobileCoin
public import SignalServiceKit

public extension PaymentsFormat {

    static func formatInChatSuccess(
        paymentAmount: TSPaymentAmount
    ) -> NSAttributedString {
        formatInChat(
            paymentAmount: paymentAmount,
            amountBuilder: inChatSuccessAmountBuilder(_:)
        )
    }

    static func formatInChatFailure(
        paymentAmount: TSPaymentAmount
    ) -> NSAttributedString {
        formatInChat(
            paymentAmount: paymentAmount,
            amountBuilder: inChatFailureAmountBuilder(_:)
        )
    }

    static func inChatSuccessAmountBuilder(_ amount: String) -> NSAttributedString {
        let firstAttributes: [NSAttributedString.Key: Any] = [.font: UIFont.dynamicTypeLargeTitle1Clamped.withSize(32)]

        let startingFont = UIFont.dynamicTypeLargeTitle1Clamped.withSize(32)
        let traits = [UIFontDescriptor.TraitKey.weight: UIFont.Weight.thin]
        let thinFontDescriptor = startingFont.fontDescriptor.addingAttributes(
            [UIFontDescriptor.AttributeName.traits: traits]
        )

        let newThinFont = UIFont(descriptor: thinFontDescriptor, size: startingFont.pointSize)
        let secondAttributes: [NSAttributedString.Key: Any] = [.font: newThinFont]

        let firstString = NSMutableAttributedString(string: amount, attributes: firstAttributes)
        let secondString = NSMutableAttributedString(string: " MOB", attributes: secondAttributes)

        // NOTE: not RTL-friendly. Maybe fix this if it comes up.
        firstString.append(secondString)
        return firstString
    }

    static func inChatFailureAmountBuilder(_ amount: String) -> NSAttributedString {
        let firstAttributes: [NSAttributedString.Key: Any] = [.font: UIFont.dynamicTypeLargeTitle1Clamped.withSize(17)]

        let startingFont = UIFont.dynamicTypeLargeTitle1Clamped.withSize(15)
        let traits = [UIFontDescriptor.TraitKey.weight: UIFont.Weight.light]
        let lightFontDescriptor = startingFont.fontDescriptor.addingAttributes([UIFontDescriptor.AttributeName.traits: traits])

        let newLightFont = UIFont(descriptor: lightFontDescriptor, size: startingFont.pointSize)
        let secondAttributes: [NSAttributedString.Key: Any] = [.font: newLightFont]

        let template = OWSLocalizedString(
            "PAYMENTS_IN_CHAT_FAILURE_MESSAGE_TOP",
            comment: "Payments in-chat message shown if a payment fails to send, top part. Embeds {{ number, amount of MOB coin not sent }}"
        )
        let topPart = String(format: template, amount)

        let bottomPart = OWSLocalizedString(
            "PAYMENTS_IN_CHAT_FAILURE_MESSAGE_BOTTOM",
            comment: "Payments in-chat message shown if a payment fails to send, bottom half.")

        // NOTE: not RTL-friendly. Maybe fix this if it comes up.
        let firstString = NSMutableAttributedString(string: topPart, attributes: firstAttributes)
        let secondString = NSAttributedString(string: bottomPart, attributes: secondAttributes)

        firstString.append("\n")
        firstString.append(secondString)

        return firstString
    }

    static func attributedFormat(paymentAmount: TSPaymentAmount,
                                 isShortForm: Bool,
                                 paymentType: TSPaymentType? = nil,
                                 withSpace: Bool = false) -> NSAttributedString {
        guard paymentAmount.currency == .mobileCoin else {
            owsFailDebug("Unknown currency.")
            return NSAttributedString(string: OWSLocalizedString("PAYMENTS_CURRENCY_UNKNOWN",
                                                                comment: "Indicator for unknown currency."))
        }

        return attributedFormat(mobileCoinString: format(paymentAmount: paymentAmount,
                                                         isShortForm: isShortForm,
                                                         withPaymentType: paymentType),
                                withSpace: withSpace)
    }

    static func attributedFormat(mobileCoinString: String,
                                 withSpace: Bool = false) -> NSAttributedString {
        attributedFormat(currencyString: mobileCoinString,
                         currencyCode: PaymentsConstants.mobileCoinCurrencyIdentifier,
                         withSpace: withSpace)
    }

    static func attributedFormat(fiatCurrencyAmount: Double,
                                 currencyCode: String,
                                 withSpace: Bool = false) -> NSAttributedString? {
        guard let currencyString = format(fiatCurrencyAmount: fiatCurrencyAmount) else {
            owsFailDebug("Invalid fiatCurrencyAmount.")
            return nil
        }
        return attributedFormat(currencyString: currencyString,
                                currencyCode: currencyCode,
                                withSpace: withSpace)
    }

    static func attributedFormat(currencyString: String,
                                 currencyCode: String,
                                 withSpace: Bool = false) -> NSAttributedString {
        let text = NSMutableAttributedString()

        text.append(currencyString.ows_stripped(),
                    attributes: [
                        .foregroundColor: Theme.primaryTextColor
                    ])

        if withSpace {
            text.append(" ", attributes: [:])
        }

        text.append(currencyCode.ows_stripped(),
                    attributes: [
                        .foregroundColor: Theme.secondaryTextAndIconColor
                    ])

        return text
    }

    @objc
    static func paymentPreviewText(
        paymentMessage: OWSPaymentMessage,
        type: OWSInteractionType,
        transaction: SDSAnyReadTransaction
    ) -> String? {
        // Shared
        guard
            let receipt = paymentMessage.paymentNotification?.mcReceiptData
        else {
            return nil
        }

        return paymentPreviewText(
            receipt: receipt,
            transaction: transaction,
            type: type)
    }

    static func paymentPreviewText(
        receipt: Data,
        transaction: SDSAnyReadTransaction,
        type: OWSInteractionType
    ) -> String? {
        // Payment Amount
        guard let amount: UInt64 = {
            switch type {
            case .incomingMessage:
                return SUIEnvironment.shared.paymentsImplRef.unmaskReceiptAmount(data: receipt)?.value
            case .outgoingMessage:
                guard let paymentModel = PaymentFinder.paymentModels(
                    forMcReceiptData: receipt,
                    transaction: transaction
                ).first else {
                    return nil
                }

                return paymentModel.paymentAmount?.picoMob
            default:
                return nil
            }
        }() else {
            return nil
        }

        return paymentPreviewText(amount: amount, transaction: transaction, type: type)
    }

    static func paymentPreviewText(
        amount: UInt64,
        transaction: SDSAnyReadTransaction,
        type: OWSInteractionType
    ) -> String? {
        // Formatted Payment Amount
        guard let formattedAmount = PaymentsFormat.format(picoMob: amount, isShortForm: true) else {
            return OWSLocalizedString(
                "PAYMENTS_PREVIEW_TEXT_UNKNOWN",
                comment: "Payments Preview Text shown in quoted replies, for unknown payments.")
        }

        // Preview Text
        let template = OWSLocalizedString(
            "PAYMENTS_PREVIEW_TEXT_QUOTED_REPLY",
            comment: "Payments Preview Text shown in quoted replies, for payments. Embeds {{ Amount sent (number), Currency (e.g. 'MOB') }}")
        let currencyName = TokenId.MOB.name
        return String(format: template, formattedAmount, currencyName)
    }
}
