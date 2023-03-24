//
// Copyright 2021 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import SignalMessaging

@objc
public class PaymentsViewUtils: NSObject {

    @available(*, unavailable, message: "Do not instantiate this class.")
    private override init() {}

    public static func buildMemoLabel(memoMessage: String?) -> UIView? {
        guard let memoMessage = memoMessage?.ows_stripped().nilIfEmpty else {
            return nil
        }

        let label = UILabel()
        label.text = memoMessage
        label.textColor = Theme.primaryTextColor
        label.font = UIFont.ows_dynamicTypeBody2Clamped
        label.textAlignment = .center
        label.numberOfLines = 0
        label.lineBreakMode = .byWordWrapping

        let stack = UIStackView(arrangedSubviews: [label])
        stack.axis = .vertical
        stack.layoutMargins = UIEdgeInsets(hMargin: 16, vMargin: 8)
        stack.isLayoutMarginsRelativeArrangement = true

        let backgroundView = OWSLayerView.pillView()
        backgroundView.backgroundColor = Theme.secondaryBackgroundColor
        stack.addSubview(backgroundView)
        backgroundView.autoPinEdgesToSuperviewEdges()
        stack.sendSubviewToBack(backgroundView)

        return stack
    }

    static func buildUnidentifiedTransactionAvatar(avatarSize: UInt) -> UIView {
        let circleView = OWSLayerView.circleView()
        circleView.backgroundColor = (Theme.isDarkThemeEnabled ? .ows_gray75 : .ows_gray02)
        circleView.autoSetDimensions(to: .square(CGFloat(avatarSize)))

        let iconColor: UIColor = (Theme.isDarkThemeEnabled ? .ows_gray05 : .ows_gray75)
        let iconView = UIImageView.withTemplateImageName("mobilecoin-24",
                                                         tintColor: iconColor)
        circleView.addSubview(iconView)
        iconView.autoCenterInSuperview()
        iconView.autoSetDimensions(to: .square(CGFloat(avatarSize) * 20.0 / 36.0))

        return circleView
    }

    static func buildUnidentifiedTransactionString(paymentModel: TSPaymentModel) -> String {
        owsAssertDebug(paymentModel.isUnidentified)
        return (paymentModel.isIncoming
                    ? NSLocalizedString("PAYMENTS_UNIDENTIFIED_PAYMENT_INCOMING",
                                        comment: "Indicator for unidentified incoming payments.")
                    : NSLocalizedString("PAYMENTS_UNIDENTIFIED_PAYMENT_OUTGOING",
                                        comment: "Indicator for unidentified outgoing payments."))
    }

    // MARK: -

    @objc
    static func addUnreadBadge(toView: UIView) {
        let avatarBadge = OWSLayerView.circleView(size: 12)
        avatarBadge.backgroundColor = Theme.accentBlueColor
        avatarBadge.layer.borderColor = UIColor.ows_white.cgColor
        avatarBadge.layer.borderWidth = 1
        toView.addSubview(avatarBadge)
        avatarBadge.autoPinEdge(toSuperviewEdge: .top, withInset: -3)
        avatarBadge.autoPinEdge(toSuperviewEdge: .trailing, withInset: -3)
    }

    static func markPaymentAsReadWithSneakyTransaction(_ paymentModel: TSPaymentModel) {
        owsAssertDebug(paymentModel.isUnread)

        databaseStorage.write { transaction in
            paymentModel.update(withIsUnread: false, transaction: transaction)
        }
    }

    static func markAllUnreadPaymentsAsReadWithSneakyTransaction() {
        databaseStorage.write { transaction in
            for paymentModel in PaymentFinder.allUnreadPaymentModels(transaction: transaction) {
                owsAssertDebug(paymentModel.isUnread)
                paymentModel.update(withIsUnread: false, transaction: transaction)
            }
        }
    }

    static func buildPassphraseGrid(passphrase: PaymentsPassphrase,
                                    footerButton: UIView? = nil) -> UIView {

        struct WordAndIndex {
            let word: String
            let index: Int
        }

        let wordsAndIndices = passphrase.words.enumerated().map { (index, word) in
            WordAndIndex(word: word, index: index)
        }

        func buildVStack(words: [WordAndIndex]) -> UIStackView {
            let stack = UIStackView()
            stack.axis = .vertical
            stack.alignment = .fill
            stack.spacing = 10

            for wordAndIndex in words {
                let attributedText = NSMutableAttributedString()
                attributedText.append(OWSFormat.formatInt(wordAndIndex.index + 1),
                                      attributes: [
                                        .font: UIFont.ows_dynamicTypeBodyClamped,
                                        .foregroundColor: Theme.secondaryTextAndIconColor
                                      ])
                attributedText.append(":",
                                      attributes: [
                                        .font: UIFont.ows_dynamicTypeBodyClamped,
                                        .foregroundColor: Theme.secondaryTextAndIconColor
                                      ])
                attributedText.append(" ",
                                      attributes: [
                                        .font: UIFont.ows_dynamicTypeBodyClamped,
                                        .foregroundColor: Theme.secondaryTextAndIconColor
                                      ])
                attributedText.append(wordAndIndex.word,
                                      attributes: [
                                        .font: UIFont.ows_dynamicTypeBodyClamped.ows_semibold,
                                        .foregroundColor: Theme.primaryTextColor
                                      ])
                let wordLabel = UILabel()
                wordLabel.attributedText = attributedText
                stack.addArrangedSubview(wordLabel)
            }

            return stack
        }

        // Half the words on the each side. If there's an odd number,
        // we want more on the left.
        let pivotIndex = wordsAndIndices.count - (wordsAndIndices.count / 2)
        let leftWords = Array(wordsAndIndices.prefix(pivotIndex))
        let rightWords = Array(wordsAndIndices.suffix(from: pivotIndex))
        let leftWordsStack = buildVStack(words: leftWords)
        let rightWordsStack = buildVStack(words: rightWords)
        let allWordStack = UIStackView(arrangedSubviews: [ leftWordsStack, rightWordsStack ])
        allWordStack.axis = .horizontal
        allWordStack.alignment = .center
        allWordStack.distribution = .fillEqually
        allWordStack.spacing = 20

        let stack = UIStackView(arrangedSubviews: [ allWordStack ])
        stack.axis = .vertical
        stack.alignment = .fill
        stack.spacing = 24
        stack.isLayoutMarginsRelativeArrangement = true
        stack.layoutMargins = UIEdgeInsets(hMargin: 20, vMargin: 24)
        let backgroundColor = OWSTableViewController2.cellBackgroundColor(isUsingPresentedStyle: true)
        stack.addBackgroundView(withBackgroundColor: backgroundColor,
                                cornerRadius: 10)

        if let footerButton = footerButton {
            let footerButtonStack = UIStackView(arrangedSubviews: [ footerButton ])
            footerButtonStack.axis = .vertical
            footerButtonStack.alignment = .center
            stack.addArrangedSubview(footerButtonStack)
        }

        return stack
    }

    static func buildTextWithLearnMoreLinkTextView(text: String,
                                                   font: UIFont,
                                                   learnMoreUrl: String) -> UITextView {
        let textView = LinkingTextView()
        textView.backgroundColor = OWSTableViewController2.tableBackgroundColor(isUsingPresentedStyle: true)
        textView.textColor = (Theme.isDarkThemeEnabled
                                ? UIColor.ows_gray05
                                : UIColor.ows_gray90)
        textView.font = UIFont.ows_dynamicTypeBodyClamped.ows_semibold
        textView.textContainerInset = .zero

        textView.attributedText = NSAttributedString.composed(of: [
            text,
            " ",
            CommonStrings.learnMore.styled(
                with: .link(URL(string: learnMoreUrl)!)
            )
        ]).styled(
            with: .font(font),
            .color(Theme.secondaryTextAndIconColor)
        )
        textView.linkTextAttributes = [
            .foregroundColor: Theme.primaryTextColor,
            NSAttributedString.Key.underlineColor: UIColor.clear,
            NSAttributedString.Key.underlineStyle: NSUnderlineStyle.single.rawValue
        ]
        return textView
    }
}

// MARK: -

@objc
public extension TSPaymentModel {

    private static var statusDateShortFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .none
        return formatter
    }()

    private static var statusDateTimeLongFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter
    }()

    func statusDescription(isLongForm: Bool) -> String {

        var result: String

        if !isIdentifiedPayment {
            if isOutgoing {
                result = (isLongForm
                            ? NSLocalizedString("PAYMENTS_PAYMENT_STATUS_LONG_OUTGOING_COMPLETE",
                                                comment: "Status indicator for outgoing payments which are complete.")
                            : NSLocalizedString("PAYMENTS_PAYMENT_STATUS_SHORT_OUTGOING_COMPLETE",
                                                comment: "Status indicator for outgoing payments which are complete."))
            } else {
                result = (isLongForm
                            ? NSLocalizedString("PAYMENTS_PAYMENT_STATUS_LONG_INCOMING_COMPLETE",
                                                comment: "Status indicator for incoming payments which are complete.")
                            : NSLocalizedString("PAYMENTS_PAYMENT_STATUS_SHORT_INCOMING_COMPLETE",
                                                comment: "Status indicator for incoming payments which are complete."))
            }
        } else {
            switch paymentState {
            case .outgoingUnsubmitted:
                result = (isLongForm
                            ? NSLocalizedString("PAYMENTS_PAYMENT_STATUS_LONG_OUTGOING_UNSUBMITTED",
                                                comment: "Status indicator for outgoing payments which have not yet been submitted.")
                            : NSLocalizedString("PAYMENTS_PAYMENT_STATUS_SHORT_OUTGOING_UNSUBMITTED",
                                                comment: "Status indicator for outgoing payments which have not yet been submitted."))
            case .outgoingUnverified:
                result = (isLongForm
                            ? NSLocalizedString("PAYMENTS_PAYMENT_STATUS_LONG_OUTGOING_UNVERIFIED",
                                                comment: "Status indicator for outgoing payments which have been submitted but not yet verified.")
                            : NSLocalizedString("PAYMENTS_PAYMENT_STATUS_SHORT_OUTGOING_UNVERIFIED",
                                                comment: "Status indicator for outgoing payments which have been submitted but not yet verified."))
            case .outgoingVerified:
                result = (isLongForm
                            ? NSLocalizedString("PAYMENTS_PAYMENT_STATUS_LONG_OUTGOING_VERIFIED",
                                                comment: "Status indicator for outgoing payments which have been verified but not yet sent.")
                            : NSLocalizedString("PAYMENTS_PAYMENT_STATUS_SHORT_OUTGOING_VERIFIED",
                                                comment: "Status indicator for outgoing payments which have been verified but not yet sent."))
            case .outgoingSending:
                result = (isLongForm
                            ? NSLocalizedString("PAYMENTS_PAYMENT_STATUS_LONG_OUTGOING_SENDING",
                                                comment: "Status indicator for outgoing payments which are being sent.")
                            : NSLocalizedString("PAYMENTS_PAYMENT_STATUS_SHORT_OUTGOING_SENDING",
                                                comment: "Status indicator for outgoing payments which are being sent."))
            case .outgoingSent,
                 .outgoingComplete:
                result = (isLongForm
                            ? NSLocalizedString("PAYMENTS_PAYMENT_STATUS_LONG_OUTGOING_SENT",
                                                comment: "Status indicator for outgoing payments which have been sent.")
                            : NSLocalizedString("PAYMENTS_PAYMENT_STATUS_SHORT_OUTGOING_SENT",
                                                comment: "Status indicator for outgoing payments which have been sent."))
            case .outgoingFailed:
                result = Self.description(forFailure: paymentFailure, isIncoming: false, isLongForm: isLongForm)
            case .incomingUnverified:
                result = (isLongForm
                            ? NSLocalizedString("PAYMENTS_PAYMENT_STATUS_LONG_INCOMING_UNVERIFIED",
                                                comment: "Status indicator for incoming payments which have not yet been verified.")
                            : NSLocalizedString("PAYMENTS_PAYMENT_STATUS_SHORT_INCOMING_UNVERIFIED",
                                                comment: "Status indicator for incoming payments which have not yet been verified."))
            case .incomingVerified,
                 .incomingComplete:
                result = (isLongForm
                            ? NSLocalizedString("PAYMENTS_PAYMENT_STATUS_LONG_INCOMING_VERIFIED",
                                                comment: "Status indicator for incoming payments which have been verified.")
                            : NSLocalizedString("PAYMENTS_PAYMENT_STATUS_SHORT_INCOMING_VERIFIED",
                                                comment: "Status indicator for incoming payments which have been verified."))
            case .incomingFailed:
                result = Self.description(forFailure: paymentFailure, isIncoming: true, isLongForm: isLongForm)
            @unknown default:
                result = (isLongForm
                            ? NSLocalizedString("PAYMENTS_PAYMENT_STATUS_LONG_UNKNOWN",
                                                comment: "Status indicator for payments which had an unknown failure.")
                            : NSLocalizedString("PAYMENTS_PAYMENT_STATUS_SHORT_UNKNOWN",
                                                comment: "Status indicator for payments which had an unknown failure."))
            }
        }
        result.append(" ")
        result.append(Self.formatDate(sortDate, isLongForm: isLongForm))

        return result
    }

    static func formatDate(_ date: Date, isLongForm: Bool) -> String {
        if isLongForm {
            return statusDateTimeLongFormatter.string(from: date)
        } else {
            return statusDateShortFormatter.string(from: date)
        }
    }

    private static func description(forFailure failure: TSPaymentFailure,
                                    isIncoming: Bool,
                                    isLongForm: Bool) -> String {

        let defaultDescription = (isIncoming
                                    ? NSLocalizedString("PAYMENTS_FAILURE_INCOMING_FAILED",
                                                        comment: "Status indicator for incoming payments which failed.")
                                    : NSLocalizedString("PAYMENTS_FAILURE_OUTGOING_FAILED",
                                                        comment: "Status indicator for outgoing payments which failed."))

        switch failure {
        case .none:
            if DebugFlags.paymentsIgnoreBadData.get() {
                Logger.warn("Unexpected failure type: \(failure.rawValue)")
            } else {
                owsFailDebug("Unexpected failure type: \(failure.rawValue)")
            }
            return defaultDescription
        case .unknown:
            owsFailDebug("Unexpected failure type: \(failure.rawValue)")
            return defaultDescription
        case .insufficientFunds:
            owsAssertDebug(!isIncoming)
            return NSLocalizedString("PAYMENTS_FAILURE_OUTGOING_INSUFFICIENT_FUNDS",
                                     comment: "Status indicator for outgoing payments which failed due to insufficient funds.")
        case .validationFailed:
            return (isIncoming
                        ? NSLocalizedString("PAYMENTS_FAILURE_INCOMING_VALIDATION_FAILED",
                                            comment: "Status indicator for incoming payments which failed to verify.")
                        : NSLocalizedString("PAYMENTS_FAILURE_OUTGOING_VALIDATION_FAILED",
                                            comment: "Status indicator for outgoing payments which failed to verify."))
        case .notificationSendFailed:
            owsAssertDebug(!isIncoming)
            return NSLocalizedString("PAYMENTS_FAILURE_OUTGOING_NOTIFICATION_SEND_FAILED",
                                     comment: "Status indicator for outgoing payments for which the notification could not be sent.")
        case .invalid, .expired:
            return NSLocalizedString("PAYMENTS_FAILURE_INVALID",
                                     comment: "Status indicator for invalid payments which could not be processed.")
        @unknown default:
            owsFailDebug("Unknown failure type: \(failure.rawValue)")
            return defaultDescription
        }
    }
}

extension OWSActionSheets {
    public static func showPaymentsOutdatedClientSheet(title: OutdatedTitleType) {

        OWSActionSheets.showConfirmationWithNotNowAlert(title: title.localizedTitle,
                                              message: NSLocalizedString("SETTINGS_PAYMENTS_PAYMENTS_OUTDATED_MESSAGE",
                                                                         comment: "Message for payments outdated sheet."),
                                              proceedTitle: NSLocalizedString("SETTINGS_PAYMENTS_PAYMENTS_OUTDATED_BUTTON",
                                                                              comment: "Button for payments outdated sheet."),
                                              proceedStyle: .default) { _ in
            let url = TSConstants.appStoreUrl
            UIApplication.shared.open(url, options: [:], completionHandler: nil)
        }
    }
}

public enum OutdatedTitleType {
    case cantSendPayment
    case updateRequired
}

extension OutdatedTitleType {
    var localizedTitle: String {
        switch self {
        case .cantSendPayment:
            return NSLocalizedString("SETTINGS_PAYMENTS_PAYMENTS_OUTDATED_TITLE_CANT_SEND",
                              comment: "Title for payments outdated sheet saying cant send.")
        case .updateRequired:
            return NSLocalizedString("SETTINGS_PAYMENTS_PAYMENTS_OUTDATED_TITLE_UPDATE",
                              comment: "Title for payments outdated sheet saying update required.")
        }
    }
}
