//
// Copyright 2021 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import SignalServiceKit
import SignalUI

@MainActor
struct PaymentsUI {
    static func buildMemoLabel(memoMessage: String?) -> UIView? {
        guard let memoMessage = memoMessage?.ows_stripped().nilIfEmpty else {
            return nil
        }

        let label = UILabel()
        label.text = memoMessage
        label.textColor = .Signal.label
        label.font = .dynamicTypeSubheadlineClamped
        label.textAlignment = .center
        label.numberOfLines = 0
        label.lineBreakMode = .byWordWrapping

        let labelContainer = UIView()
        labelContainer.backgroundColor = .Signal.secondaryGroupedBackground
        labelContainer.directionalLayoutMargins = .init(
            hMargin: OWSTableViewController2.cellHInnerMargin,
            vMargin: OWSTableViewController2.cellVInnerMargin,
        )
        if #available(iOS 26, *) {
            labelContainer.cornerConfiguration = .capsule(maximumRadius: 26)
        } else {
            labelContainer.layer.cornerRadius = 10
        }
        labelContainer.addSubview(label)
        label.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            label.topAnchor.constraint(equalTo: labelContainer.layoutMarginsGuide.topAnchor),
            label.leadingAnchor.constraint(equalTo: labelContainer.layoutMarginsGuide.leadingAnchor),
            label.trailingAnchor.constraint(equalTo: labelContainer.layoutMarginsGuide.trailingAnchor),
            label.bottomAnchor.constraint(equalTo: labelContainer.layoutMarginsGuide.bottomAnchor),
        ])

        return labelContainer
    }

    static func buildUnidentifiedTransactionAvatar(avatarSize: UInt) -> UIView {
        let circleView = OWSLayerView.circleView()
        circleView.backgroundColor = (Theme.isDarkThemeEnabled ? .ows_gray75 : .ows_gray02)
        circleView.autoSetDimensions(to: .square(CGFloat(avatarSize)))

        let iconColor: UIColor = (Theme.isDarkThemeEnabled ? .ows_gray05 : .ows_gray75)
        let iconView = UIImageView.withTemplateImageName(
            "mobilecoin-24",
            tintColor: iconColor,
        )
        circleView.addSubview(iconView)
        iconView.autoCenterInSuperview()
        iconView.autoSetDimensions(to: .square(CGFloat(avatarSize) * 20.0 / 36.0))

        return circleView
    }

    static func buildUnidentifiedTransactionString(paymentModel: TSPaymentModel) -> String {
        owsAssertDebug(paymentModel.isUnidentified)
        return paymentModel.isIncoming
            ? OWSLocalizedString(
                "PAYMENTS_UNIDENTIFIED_PAYMENT_INCOMING",
                comment: "Indicator for unidentified incoming payments.",
            )
            : OWSLocalizedString(
                "PAYMENTS_UNIDENTIFIED_PAYMENT_OUTGOING",
                comment: "Indicator for unidentified outgoing payments.",
            )
    }

    static func buildPassphraseGrid(
        passphrase: PaymentsPassphrase,
        footerButton: UIView? = nil,
    ) -> UIView {

        struct WordAndIndex {
            let word: String
            let index: Int
        }

        let wordsAndIndices = passphrase.words.enumerated().map { index, word in
            WordAndIndex(word: word, index: index)
        }

        func buildVStack(words: [WordAndIndex]) -> UIStackView {
            let stack = UIStackView()
            stack.axis = .vertical
            stack.alignment = .fill
            stack.spacing = 10

            let attributes: [NSAttributedString.Key: Any] = [
                .font: UIFont.dynamicTypeBodyClamped,
                .foregroundColor: UIColor.Signal.secondaryLabel,
            ]

            for wordAndIndex in words {
                let attributedText = NSMutableAttributedString()
                attributedText.append(
                    OWSFormat.formatInt(wordAndIndex.index + 1),
                    attributes: attributes,
                )
                attributedText.append(
                    ": ",
                    attributes: attributes,
                )
                attributedText.append(
                    wordAndIndex.word,
                    attributes: [
                        .font: UIFont.dynamicTypeHeadlineClamped,
                        .foregroundColor: UIColor.Signal.label,
                    ],
                )
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
        let allWordStack = UIStackView(arrangedSubviews: [leftWordsStack, rightWordsStack])
        allWordStack.axis = .horizontal
        allWordStack.alignment = .center
        allWordStack.distribution = .fillEqually
        allWordStack.spacing = 20

        let stack = UIStackView(arrangedSubviews: [allWordStack])
        stack.axis = .vertical
        stack.alignment = .fill
        stack.spacing = 24

        if let footerButton {
            let footerButtonContainer = UIView.container()
            footerButtonContainer.addSubview(footerButton)
            footerButton.translatesAutoresizingMaskIntoConstraints = false
            NSLayoutConstraint.activate([
                footerButton.topAnchor.constraint(equalTo: footerButtonContainer.topAnchor),
                footerButton.leadingAnchor.constraint(greaterThanOrEqualTo: footerButtonContainer.leadingAnchor),
                footerButton.centerXAnchor.constraint(equalTo: footerButtonContainer.centerXAnchor),
                footerButton.bottomAnchor.constraint(equalTo: footerButtonContainer.bottomAnchor),
            ])
            stack.addArrangedSubview(footerButtonContainer)
        }

        return stack
    }

    static func buildTextWithLearnMoreLinkTextView(
        text: String,
        font: UIFont,
        learnMoreUrl: URL,
    ) -> UIView {
        let textView = LinkingTextView()
        textView.backgroundColor = .clear
        textView.attributedText = NSAttributedString.composed(of: [
            text,
            " ",
            CommonStrings.learnMore.styled(
                with: .link(learnMoreUrl),
            ),
        ]).styled(
            with: .font(font),
            .color(.Signal.secondaryLabel),
        )
        textView.linkTextAttributes = [.foregroundColor: UIColor.Signal.label]
        textView.textAlignment = .center
        return textView
    }
}

enum PaymentUtils {
    static func markPaymentAsRead(_ paymentModel: TSPaymentModel, transaction: DBWriteTransaction) {
        owsAssertDebug(paymentModel.isUnread)
        paymentModel.update(withIsUnread: false, transaction: transaction)
    }

    static func markAllUnreadPaymentsAsReadWithSneakyTransaction() {
        SSKEnvironment.shared.databaseStorageRef.write { transaction in
            for paymentModel in PaymentFinder.allUnreadPaymentModels(transaction: transaction) {
                owsAssertDebug(paymentModel.isUnread)
                paymentModel.update(withIsUnread: false, transaction: transaction)
            }
        }
    }
}

// MARK: -

extension TSPaymentModel {

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
                result = (
                    isLongForm
                        ? OWSLocalizedString(
                            "PAYMENTS_PAYMENT_STATUS_LONG_OUTGOING_COMPLETE",
                            comment: "Status indicator for outgoing payments which are complete.",
                        )
                        : OWSLocalizedString(
                            "PAYMENTS_PAYMENT_STATUS_SHORT_OUTGOING_COMPLETE",
                            comment: "Status indicator for outgoing payments which are complete.",
                        ),
                )
            } else {
                result = (
                    isLongForm
                        ? OWSLocalizedString(
                            "PAYMENTS_PAYMENT_STATUS_LONG_INCOMING_COMPLETE",
                            comment: "Status indicator for incoming payments which are complete.",
                        )
                        : OWSLocalizedString(
                            "PAYMENTS_PAYMENT_STATUS_SHORT_INCOMING_COMPLETE",
                            comment: "Status indicator for incoming payments which are complete.",
                        ),
                )
            }
        } else {
            switch paymentState {
            case .outgoingUnsubmitted:
                result = (
                    isLongForm
                        ? OWSLocalizedString(
                            "PAYMENTS_PAYMENT_STATUS_LONG_OUTGOING_UNSUBMITTED",
                            comment: "Status indicator for outgoing payments which have not yet been submitted.",
                        )
                        : OWSLocalizedString(
                            "PAYMENTS_PAYMENT_STATUS_SHORT_OUTGOING_UNSUBMITTED",
                            comment: "Status indicator for outgoing payments which have not yet been submitted.",
                        ),
                )
            case .outgoingUnverified:
                result = (
                    isLongForm
                        ? OWSLocalizedString(
                            "PAYMENTS_PAYMENT_STATUS_LONG_OUTGOING_UNVERIFIED",
                            comment: "Status indicator for outgoing payments which have been submitted but not yet verified.",
                        )
                        : OWSLocalizedString(
                            "PAYMENTS_PAYMENT_STATUS_SHORT_OUTGOING_UNVERIFIED",
                            comment: "Status indicator for outgoing payments which have been submitted but not yet verified.",
                        ),
                )
            case .outgoingVerified:
                result = (
                    isLongForm
                        ? OWSLocalizedString(
                            "PAYMENTS_PAYMENT_STATUS_LONG_OUTGOING_VERIFIED",
                            comment: "Status indicator for outgoing payments which have been verified but not yet sent.",
                        )
                        : OWSLocalizedString(
                            "PAYMENTS_PAYMENT_STATUS_SHORT_OUTGOING_VERIFIED",
                            comment: "Status indicator for outgoing payments which have been verified but not yet sent.",
                        ),
                )
            case .outgoingSending:
                result = (
                    isLongForm
                        ? OWSLocalizedString(
                            "PAYMENTS_PAYMENT_STATUS_LONG_OUTGOING_SENDING",
                            comment: "Status indicator for outgoing payments which are being sent.",
                        )
                        : OWSLocalizedString(
                            "PAYMENTS_PAYMENT_STATUS_SHORT_OUTGOING_SENDING",
                            comment: "Status indicator for outgoing payments which are being sent.",
                        ),
                )
            case .outgoingSent,
                 .outgoingComplete:
                result = (
                    isLongForm
                        ? OWSLocalizedString(
                            "PAYMENTS_PAYMENT_STATUS_LONG_OUTGOING_SENT",
                            comment: "Status indicator for outgoing payments which have been sent.",
                        )
                        : OWSLocalizedString(
                            "PAYMENTS_PAYMENT_STATUS_SHORT_OUTGOING_SENT",
                            comment: "Status indicator for outgoing payments which have been sent.",
                        ),
                )
            case .outgoingFailed:
                result = Self.description(forFailure: paymentFailure, isIncoming: false, isLongForm: isLongForm)
            case .incomingUnverified:
                result = (
                    isLongForm
                        ? OWSLocalizedString(
                            "PAYMENTS_PAYMENT_STATUS_LONG_INCOMING_UNVERIFIED",
                            comment: "Status indicator for incoming payments which have not yet been verified.",
                        )
                        : OWSLocalizedString(
                            "PAYMENTS_PAYMENT_STATUS_SHORT_INCOMING_UNVERIFIED",
                            comment: "Status indicator for incoming payments which have not yet been verified.",
                        ),
                )
            case .incomingVerified,
                 .incomingComplete:
                result = (
                    isLongForm
                        ? OWSLocalizedString(
                            "PAYMENTS_PAYMENT_STATUS_LONG_INCOMING_VERIFIED",
                            comment: "Status indicator for incoming payments which have been verified.",
                        )
                        : OWSLocalizedString(
                            "PAYMENTS_PAYMENT_STATUS_SHORT_INCOMING_VERIFIED",
                            comment: "Status indicator for incoming payments which have been verified.",
                        ),
                )
            case .incomingFailed:
                result = Self.description(forFailure: paymentFailure, isIncoming: true, isLongForm: isLongForm)
            @unknown default:
                result = (
                    isLongForm
                        ? OWSLocalizedString(
                            "PAYMENTS_PAYMENT_STATUS_LONG_UNKNOWN",
                            comment: "Status indicator for payments which had an unknown failure.",
                        )
                        : OWSLocalizedString(
                            "PAYMENTS_PAYMENT_STATUS_SHORT_UNKNOWN",
                            comment: "Status indicator for payments which had an unknown failure.",
                        ),
                )
            }
        }
        result.append(" ")
        result.append(Self.formatDate(sortDate, isLongForm: isLongForm))

        return result
    }

    func statusDescriptionForAccessibility(isLongForm: Bool) -> String {
        var result = statusDescription(isLongForm: isLongForm)
        // Replace the appended date with the accessibility-friendly version.
        result = String(result.dropLast(Self.formatDate(sortDate, isLongForm: isLongForm).count + 1))
        result.append(" ")
        result.append(Self.formatDateForAccessibility(sortDate, isLongForm: isLongForm))
        return result
    }

    static func formatDate(_ date: Date, isLongForm: Bool) -> String {
        if isLongForm {
            return statusDateTimeLongFormatter.string(from: date)
        } else {
            return statusDateShortFormatter.string(from: date)
        }
    }

    static func formatDateForAccessibility(_ date: Date, isLongForm: Bool) -> String {
        if isLongForm {
            // Replace only the time portion with the spoken form; keep the date portion visual.
            let datePart = DateFormatter.localizedString(from: date, dateStyle: .medium, timeStyle: .none)
            let timePart = DateUtil.formatDateAsTimeForAccessibility(date)
            return "\(datePart) \(timePart)"
        } else {
            return statusDateShortFormatter.string(from: date)
        }
    }

    private static func description(
        forFailure failure: TSPaymentFailure,
        isIncoming: Bool,
        isLongForm: Bool,
    ) -> String {

        let defaultDescription = (
            isIncoming
                ? OWSLocalizedString(
                    "PAYMENTS_FAILURE_INCOMING_FAILED",
                    comment: "Status indicator for incoming payments which failed.",
                )
                : OWSLocalizedString(
                    "PAYMENTS_FAILURE_OUTGOING_FAILED",
                    comment: "Status indicator for outgoing payments which failed.",
                ),
        )

        switch failure {
        case .none:
            owsFailDebug("Unexpected failure type: \(failure.rawValue)")
            return defaultDescription
        case .unknown:
            owsFailDebug("Unexpected failure type: \(failure.rawValue)")
            return defaultDescription
        case .insufficientFunds:
            owsAssertDebug(!isIncoming)
            return OWSLocalizedString(
                "PAYMENTS_FAILURE_OUTGOING_INSUFFICIENT_FUNDS",
                comment: "Status indicator for outgoing payments which failed due to insufficient funds.",
            )
        case .validationFailed:
            return isIncoming
                ? OWSLocalizedString(
                    "PAYMENTS_FAILURE_INCOMING_VALIDATION_FAILED",
                    comment: "Status indicator for incoming payments which failed to verify.",
                )
                : OWSLocalizedString(
                    "PAYMENTS_FAILURE_OUTGOING_VALIDATION_FAILED",
                    comment: "Status indicator for outgoing payments which failed to verify.",
                )
        case .notificationSendFailed:
            owsAssertDebug(!isIncoming)
            return OWSLocalizedString(
                "PAYMENTS_FAILURE_OUTGOING_NOTIFICATION_SEND_FAILED",
                comment: "Status indicator for outgoing payments for which the notification could not be sent.",
            )
        case .invalid, .expired:
            return OWSLocalizedString(
                "PAYMENTS_FAILURE_INVALID",
                comment: "Status indicator for invalid payments which could not be processed.",
            )
        @unknown default:
            owsFailDebug("Unknown failure type: \(failure.rawValue)")
            return defaultDescription
        }
    }
}

extension OWSActionSheets {
    static func showPaymentsOutdatedClientSheet(title: OutdatedTitleType) {
        OWSActionSheets.showConfirmationWithNotNowAlert(
            title: title.localizedTitle,
            message: OWSLocalizedString(
                "SETTINGS_PAYMENTS_PAYMENTS_OUTDATED_MESSAGE",
                comment: "Message for payments outdated sheet.",
            ),
            proceedTitle: OWSLocalizedString(
                "SETTINGS_PAYMENTS_PAYMENTS_OUTDATED_BUTTON",
                comment: "Button for payments outdated sheet.",
            ),
            proceedStyle: .default,
        ) { _ in
            let url = TSConstants.appStoreUrl
            UIApplication.shared.open(url, options: [:], completionHandler: nil)
        }
    }
}

enum OutdatedTitleType {
    case cantSendPayment
    case updateRequired

    var localizedTitle: String {
        switch self {
        case .cantSendPayment:
            return OWSLocalizedString(
                "SETTINGS_PAYMENTS_PAYMENTS_OUTDATED_TITLE_CANT_SEND",
                comment: "Title for payments outdated sheet saying cant send.",
            )
        case .updateRequired:
            return OWSLocalizedString(
                "SETTINGS_PAYMENTS_PAYMENTS_OUTDATED_TITLE_UPDATE",
                comment: "Title for payments outdated sheet saying update required.",
            )
        }
    }
}
