//
// Copyright 2022 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import AuthenticationServices
import SignalMessaging
import SignalUI

class CreditOrDebitCardDonationViewController: OWSTableViewController2 {
    let donationAmount: FiatMoney
    let donationMode: DonationMode
    let onFinished: () -> Void
    var threeDSecureAuthenticationSession: ASWebAuthenticationSession?

    public override var preferredNavigationBarStyle: OWSNavigationBarStyle { .solid }
    public override var navbarBackgroundColorOverride: UIColor? { .clear }

    init(
        donationAmount: FiatMoney,
        donationMode: DonationMode,
        onFinished: @escaping () -> Void
    ) {
        self.donationAmount = donationAmount
        self.donationMode = donationMode
        self.onFinished = onFinished

        super.init()

        self.defaultSpacingBetweenSections = 0
    }

    deinit {
        threeDSecureAuthenticationSession?.cancel()
    }

    // MARK: - View callbacks

    public override func viewDidLoad() {
        shouldAvoidKeyboard = true

        super.viewDidLoad()

        render()

        contents = OWSTableContents(sections: [donationAmountSection, formSection])
    }

    public override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)

        cardNumberView.becomeFirstResponder()
    }

    public override func themeDidChange() {
        super.themeDidChange()

        render()
    }

    // MARK: - Events

    private func didSubmit() {
        switch formState {
        case .invalid, .potentiallyValid:
            owsFail("[Donations] It should be impossible to submit the form without a fully-valid card. Is the submit button properly disabled?")
        case let .fullyValid(creditOrDebitCard):
            switch donationMode {
            case .oneTime:
                oneTimeDonation(with: creditOrDebitCard)
            case let .monthly(
                subscriptionLevel,
                subscriberID,
                _,
                currentSubscriptionLevel
            ):
                monthlyDonation(
                    with: creditOrDebitCard,
                    newSubscriptionLevel: subscriptionLevel,
                    priorSubscriptionLevel: currentSubscriptionLevel,
                    subscriberID: subscriberID
                )
            case let .gift(thread, messageText):
                giftDonation(with: creditOrDebitCard, in: thread, messageText: messageText)
            }
        }
    }

    func didFailDonation(error: Error) {
        DonationViewsUtil.presentDonationErrorSheet(
            from: self,
            error: error,
            paymentMethod: .creditOrDebitCard,
            currentSubscription: {
                switch donationMode {
                case .oneTime, .gift: return nil
                case let .monthly(_, _, currentSubscription, _): return currentSubscription
                }
            }()
        )
    }

    // MARK: - Rendering

    private func render() {
        // We'd like a link that doesn't go anywhere, because we'd like to
        // handle the tapping ourselves. We use a "fake" URL because BonMot
        // needs one.
        let linkPart = StringStyle.Part.link(SupportConstants.subscriptionFAQURL)

        subheaderTextView.attributedText = .composed(of: [
            NSLocalizedString(
                "CARD_DONATION_SUBHEADER_TEXT",
                comment: "On the credit/debit card donation screen, a small amount of information text is shown. This is that text. It should (1) instruct users to enter their credit/debit card information (2) tell them that Signal does not collect or store their personal information."
            ),
            " ",
            NSLocalizedString(
                "CARD_DONATION_SUBHEADER_LEARN_MORE",
                comment: "On the credit/debit card donation screen, a small amount of information text is shown. Users can click this link to learn more information."
            ).styled(with: linkPart)
        ]).styled(with: .color(Theme.primaryTextColor), .font(.dynamicTypeBody))
        subheaderTextView.linkTextAttributes = [
            .foregroundColor: Theme.accentBlueColor,
            .underlineColor: UIColor.clear,
            .underlineStyle: NSUnderlineStyle.single.rawValue
        ]
        subheaderTextView.textAlignment = .center

        // Only change the placeholder when enough digits are entered.
        // Helps avoid a jittery UI as you type/delete.
        let rawNumber = cardNumberView.text
        let cardType = CreditAndDebitCards.cardType(ofNumber: rawNumber)
        if rawNumber.count >= 2 {
            cvvView.placeholder = String("1234".prefix(cardType.cvvCount))
        }

        let invalidFields: Set<FormField>
        switch formState {
        case let .invalid(fields):
            invalidFields = fields
            submitButton.isEnabled = false
        case .potentiallyValid:
            invalidFields = []
            submitButton.isEnabled = false
        case .fullyValid:
            invalidFields = []
            submitButton.isEnabled = true
        }

        cardNumberView.render(errorMessage: {
            guard invalidFields.contains(.cardNumber) else { return nil }
            return NSLocalizedString(
                "CARD_DONATION_CARD_NUMBER_GENERIC_ERROR",
                comment: "Users can donate to Signal with a credit or debit card. If their card number is invalid, this generic error message will be shown. Try to use a short string to make space in the UI."
            )
        }())
        expirationView.render(errorMessage: {
            guard invalidFields.contains(.expirationDate) else { return nil }
            return NSLocalizedString(
                "CARD_DONATION_EXPIRATION_DATE_GENERIC_ERROR",
                comment: "Users can donate to Signal with a credit or debit card. If their expiration date is invalid, this generic error message will be shown. Try to use a short string to make space in the UI."
            )
        }())
        cvvView.render(errorMessage: {
            guard invalidFields.contains(.cvv) else { return nil }
            if cvvView.text.count > cardType.cvvCount {
                return NSLocalizedString(
                    "CARD_DONATION_CVV_TOO_LONG_ERROR",
                    comment: "Users can donate to Signal with a credit or debit card. If their card verification code (CVV) is too long, this error will be shown. Try to use a short string to make space in the UI."
                )
            } else {
                return NSLocalizedString(
                    "CARD_DONATION_CVV_GENERIC_ERROR",
                    comment: "Users can donate to Signal with a credit or debit card. If their card verification code (CVV) is invalid for reasons we cannot determine, this generic error message will be shown. Try to use a short string to make space in the UI."
                )
            }
        }())

        bottomFooterStackView.layer.backgroundColor = self.tableBackgroundColor.cgColor
    }

    // MARK: - Donation amount section

    private lazy var subheaderTextView: LinkingTextView = {
        let result = LinkingTextView()
        result.delegate = self
        return result
    }()

    private lazy var donationAmountSection: OWSTableSection = {
        let result = OWSTableSection(
            items: [.init(
                customCellBlock: { [weak self] in
                    let cell = OWSTableItem.newCell()
                    cell.selectionStyle = .none

                    guard let self else { return cell }

                    let headerLabel = UILabel()
                    headerLabel.text = {
                        let amountString = DonationUtilities.format(money: self.donationAmount)
                        let format = NSLocalizedString(
                            "CARD_DONATION_HEADER",
                            comment: "Users can donate to Signal with a credit or debit card. This is the heading on that screen, telling them how much they'll donate. Embeds {{formatted amount of money}}, such as \"$20\"."
                        )
                        return String(format: format, amountString)
                    }()
                    headerLabel.font = .dynamicTypeTitle3.semibold()
                    headerLabel.textAlignment = .center
                    headerLabel.numberOfLines = 0
                    headerLabel.lineBreakMode = .byWordWrapping

                    let stackView = UIStackView(arrangedSubviews: [
                        headerLabel,
                        self.subheaderTextView
                    ])
                    cell.contentView.addSubview(stackView)
                    stackView.axis = .vertical
                    stackView.spacing = 4
                    stackView.autoPinEdgesToSuperviewMargins()

                    return cell
                }
            )]
        )
        result.hasBackground = false
        return result
    }()

    // MARK: - Card form

    private var formState: FormState {
        Self.formState(
            cardNumber: cardNumberView.text,
            isCardNumberFieldFocused: cardNumberView.isFirstResponder,
            expirationDate: expirationView.text,
            cvv: cvvView.text
        )
    }

    private lazy var formSection: OWSTableSection = {
        let result = OWSTableSection()
        result.hasBackground = false

        result.add(items: [.init(customCellBlock: { [weak self] in
            let cell = OWSTableItem.newCell()
            cell.selectionStyle = .none

            guard let self else { return cell }

            let expirationAndCvvStackView = UIStackView(arrangedSubviews: [
                self.expirationView,
                self.cvvView
            ])
            expirationAndCvvStackView.spacing = 16

            let outerStackView = UIStackView(arrangedSubviews: [
                self.cardNumberView,
                expirationAndCvvStackView
            ])
            self.cardNumberView.autoPinWidthToSuperviewMargins()
            expirationAndCvvStackView.autoPinWidthToSuperviewMargins()
            outerStackView.axis = .vertical
            outerStackView.spacing = 16
            cell.contentView.addSubview(outerStackView)
            outerStackView.autoPinEdgesToSuperviewMargins()

            return cell
        })])

        return result
    }()

    // MARK: Card number

    static func formatCardNumber(unformatted: String) -> String {
        var gaps: Set<Int>
        switch CreditAndDebitCards.cardType(ofNumber: unformatted) {
        case .americanExpress: gaps = [4, 10]
        case .unionPay, .other: gaps = [4, 8, 12]
        }

        var result = [Character]()
        for (i, character) in unformatted.enumerated() {
            if gaps.contains(i) {
                result.append(" ")
            }
            result.append(character)
        }
        if gaps.contains(unformatted.count) {
            result.append(" ")
        }
        return String(result)
    }

    private lazy var cardNumberView: FormFieldView = {
        let result = FormFieldView(
            title: NSLocalizedString(
                "CARD_DONATION_CARD_NUMBER_LABEL",
                comment: "Users can donate to Signal with a credit or debit card. This is the label for the card number field on that screen."
            ),
            placeholder: Self.formatCardNumber(unformatted: "0000000000000000"),
            maxDigits: 19,
            format: Self.formatCardNumber,
            textContentType: .creditCardNumber
        )
        result.delegate = self
        return result
    }()

    // MARK: Expiration date

    static func formatExpirationDate(unformatted: String) -> String {
        switch unformatted.count {
        case 0:
            return unformatted
        case 1:
            let firstDigit = unformatted.first!
            switch firstDigit {
            case "0", "1": return unformatted
            default: return unformatted + "/"
            }
        case 2:
            if (UInt8(unformatted) ?? 0).isValidAsMonth {
                return unformatted + "/"
            } else {
                return "\(unformatted.prefix(1))/\(unformatted.suffix(1))"
            }
        default:
            let firstTwo = unformatted.prefix(2)
            let firstTwoAsMonth = UInt8(String(firstTwo)) ?? 0
            let monthCount = firstTwoAsMonth.isValidAsMonth ? 2 : 1
            let month = unformatted.prefix(monthCount)
            let year = unformatted.suffix(unformatted.count - monthCount)
            return "\(month)/\(year)"
        }
    }

    private lazy var expirationView: FormFieldView = {
        let result = FormFieldView(
            title: NSLocalizedString(
                "CARD_DONATION_EXPIRATION_DATE_LABEL",
                comment: "Users can donate to Signal with a credit or debit card. This is the label for the expiration date field on that screen. Try to use a short string to make space in the UI. (For example, the English text uses \"Exp. Date\" instead of \"Expiration Date\")."
            ),
            placeholder: NSLocalizedString(
                "CARD_DONATION_EXPIRATION_DATE_PLACEHOLDER",
                comment: "Users can donate to Signal with a credit or debit card. This is the label for the card expiration date field on that screen."
            ),
            maxDigits: 4,
            format: Self.formatExpirationDate
        )
        result.delegate = self
        return result
    }()

    // MARK: CVV

    private lazy var cvvView: FormFieldView = {
        let result = FormFieldView(
            title: NSLocalizedString(
                "CARD_DONATION_CVV_LABEL",
                comment: "Users can donate to Signal with a credit or debit card. This is the label for the card verification code (CVV) field on that screen."
            ),
            placeholder: "123",
            maxDigits: 4,
            format: { $0 }
        )
        result.delegate = self
        return result
    }()

    // MARK: - Submit button, footer

    private lazy var submitButton: OWSButton = {
        let title = NSLocalizedString(
            "CARD_DONATION_DONATE_BUTTON",
            comment: "Users can donate to Signal with a credit or debit card. This is the text on the \"Donate\" button."
        )
        let result = OWSButton(title: title) { [weak self] in
            self?.didSubmit()
        }
        result.dimsWhenHighlighted = true
        result.dimsWhenDisabled = true
        result.layer.cornerRadius = 8
        result.backgroundColor = .ows_accentBlue
        result.titleLabel?.font = .dynamicTypeBody.semibold()
        result.autoSetDimension(.height, toSize: 48, relation: .greaterThanOrEqual)
        return result
    }()

    private lazy var bottomFooterStackView: UIStackView = {
        let result = UIStackView(arrangedSubviews: [submitButton])

        result.axis = .vertical
        result.alignment = .fill
        result.spacing = 16
        result.isLayoutMarginsRelativeArrangement = true
        result.preservesSuperviewLayoutMargins = true
        result.layoutMargins = .init(hMargin: 16, vMargin: 10)

        return result
    }()

    open override var bottomFooter: UIView? {
        get { bottomFooterStackView }
        set {}
    }
}

// MARK: - UITextViewDelegate

extension CreditOrDebitCardDonationViewController: UITextViewDelegate {
    func textView(
        _ textView: UITextView,
        shouldInteractWith URL: URL,
        in characterRange: NSRange,
        interaction: UITextItemInteraction
    ) -> Bool {
        if textView == subheaderTextView {
            present(CreditOrDebitCardReadMoreSheetViewController(), animated: true)
        }
        return false
    }
}

// MARK: - CreditOrDebitCardDonationFormViewDelegate

extension CreditOrDebitCardDonationViewController: CreditOrDebitCardDonationFormViewDelegate {
    func didSomethingChange() { render() }
}

// MARK: - Utilities

fileprivate extension UInt8 {
    var isValidAsMonth: Bool { self >= 1 && self <= 12 }
}
