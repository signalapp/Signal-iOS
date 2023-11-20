//
// Copyright 2022 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import AuthenticationServices
import SignalMessaging
import SignalUI

class DonationPaymentDetailsViewController: OWSTableViewController2 {
    enum PaymentMethod {
        case card
        case sepa(mandate: Stripe.PaymentMethod.Mandate)
        case ideal(mandate: Stripe.PaymentMethod.Mandate)

        fileprivate var stripePaymentMethod: OWSRequestFactory.StripePaymentMethod {
            switch self {
            case .card:
                return .card
            case .sepa, .ideal:
                return .bankTransfer(.sepa)
            }
        }
    }

    let donationAmount: FiatMoney
    let donationMode: DonationMode
    let paymentMethod: PaymentMethod
    let onFinished: (Error?) -> Void
    var threeDSecureAuthenticationSession: ASWebAuthenticationSession?

    public override var preferredNavigationBarStyle: OWSNavigationBarStyle { .solid }
    public override var navbarBackgroundColorOverride: UIColor? { .clear }

    init(
        donationAmount: FiatMoney,
        donationMode: DonationMode,
        paymentMethod: PaymentMethod,
        onFinished: @escaping (Error?) -> Void
    ) {
        self.donationAmount = donationAmount
        self.donationMode = donationMode
        self.paymentMethod = paymentMethod
        self.onFinished = onFinished

        super.init()

        switch paymentMethod {
        case .card:
            title = OWSLocalizedString(
                "PAYMENT_DETAILS_CARD_TITLE",
                comment: "Header title for card payment details screen")
        case .sepa, .ideal:
            title = OWSLocalizedString(
                "PAYMENT_DETAILS_BANK_TITLE",
                comment: "Header title for bank payment details screen")
        }
    }

    deinit {
        threeDSecureAuthenticationSession?.cancel()
    }

    // MARK: - View callbacks

    public override func viewDidLoad() {
        shouldAvoidKeyboard = true

        super.viewDidLoad()

        render()

        let sections = [donationAmountSection] + formSections()
        contents = OWSTableContents(sections: sections)
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
        // TODO: Dismiss keyboard?
        switch formState {
        case .invalid, .potentiallyValid:
            owsFailDebug("[Donations] It should be impossible to submit the form without a fully-valid card. Is the submit button properly disabled?")
        case let .fullyValid(validForm):
            switch donationMode {
            case .oneTime:
                oneTimeDonation(with: validForm)
            case let .monthly(
                subscriptionLevel,
                subscriberID,
                _,
                currentSubscriptionLevel
            ):
                monthlyDonation(
                    with: validForm,
                    newSubscriptionLevel: subscriptionLevel,
                    priorSubscriptionLevel: currentSubscriptionLevel,
                    subscriberID: subscriberID
                )
            case let .gift(thread, messageText):
                switch validForm {
                case let .card(creditOrDebitCard):
                    giftDonation(with: creditOrDebitCard, in: thread, messageText: messageText)
                case .sepa, .ideal:
                    owsFailDebug("Gift badges do not support bank transfers")
                }
            }
        }
    }

    // MARK: - Rendering

    private func render() {
        // We'd like a link that doesn't go anywhere, because we'd like to
        // handle the tapping ourselves. We use a "fake" URL because BonMot
        // needs one.
        let linkPart = StringStyle.Part.link(SupportConstants.subscriptionFAQURL)

        let subheaderText: String
        switch self.paymentMethod {
        case .card:
            subheaderText = OWSLocalizedString(
                "CARD_DONATION_SUBHEADER_TEXT",
                comment: "On the credit/debit card donation screen, a small amount of information text is shown. This is that text. It should (1) instruct users to enter their credit/debit card information (2) tell them that Signal does not collect or store their personal information."
            )
        case .sepa, .ideal:
            subheaderText = OWSLocalizedString(
                "BANK_DONATION_SUBHEADER_TEXT",
                comment: "On the bank transfer donation screen, a small amount of information text is shown. This is that text. It should (1) instruct users to enter their bank information (2) tell them that Signal does not collect or store their personal information."
            )
        }

        subheaderTextView.attributedText = .composed(of: [
            subheaderText,
            " ",
            OWSLocalizedString(
                "CARD_DONATION_SUBHEADER_LEARN_MORE",
                comment: "On the credit/debit card donation screen, a small amount of information text is shown. Users can click this link to learn more information."
            ).styled(with: linkPart)
        ]).styled(with: .color(Theme.secondaryTextAndIconColor), .font(.dynamicTypeFootnoteClamped))
        subheaderTextView.linkTextAttributes = [
            .foregroundColor: Theme.primaryTextColor,
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

        let invalidFields: Set<InvalidFormField>
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

        tableView.beginUpdates()
        cardNumberView.render(errorMessage: {
            guard invalidFields.contains(.cardNumber) else { return nil }
            return OWSLocalizedString(
                "CARD_DONATION_CARD_NUMBER_GENERIC_ERROR",
                comment: "Users can donate to Signal with a credit or debit card. If their card number is invalid, this generic error message will be shown. Try to use a short string to make space in the UI."
            )
        }())
        expirationView.render(errorMessage: {
            guard invalidFields.contains(.expirationDate) else { return nil }
            return OWSLocalizedString(
                "CARD_DONATION_EXPIRATION_DATE_GENERIC_ERROR",
                comment: "Users can donate to Signal with a credit or debit card. If their expiration date is invalid, this generic error message will be shown. Try to use a short string to make space in the UI."
            )
        }())
        cvvView.render(errorMessage: {
            guard invalidFields.contains(.cvv) else { return nil }
            if cvvView.text.count > cardType.cvvCount {
                return OWSLocalizedString(
                    "CARD_DONATION_CVV_TOO_LONG_ERROR",
                    comment: "Users can donate to Signal with a credit or debit card. If their card verification code (CVV) is too long, this error will be shown. Try to use a short string to make space in the UI."
                )
            } else {
                return OWSLocalizedString(
                    "CARD_DONATION_CVV_GENERIC_ERROR",
                    comment: "Users can donate to Signal with a credit or debit card. If their card verification code (CVV) is invalid for reasons we cannot determine, this generic error message will be shown. Try to use a short string to make space in the UI."
                )
            }
        }())
        ibanView.render(errorMessage: ibanErrorMessage(invalidFields: invalidFields))
        // Currently, name and email can only be valid or potentially
        // valid. There is no invalid state for either.
        tableView.endUpdates()

        bottomFooterStackView.layer.backgroundColor = self.tableBackgroundColor.cgColor
    }

    private func ibanErrorMessage(invalidFields: Set<InvalidFormField>) -> String? {
        invalidFields.lazy
            .compactMap { field -> SEPABankAccounts.IBANInvalidity? in
                guard case let .iban(invalidity) = field else { return nil }
                return invalidity
            }
            .first
            .map { invalidity in
                switch invalidity {
                case .invalidCharacters:
                    return OWSLocalizedString(
                        "SEPA_DONATION_IBAN_INVALID_CHARACTERS_ERROR",
                        comment: "Users can donate to Signal with a bank account. If their internation bank account number (IBAN) contains characters other than letters and numbers, this error will be shown. Try to use a short string to make space in the UI."
                    )
                case .invalidCheck:
                    return OWSLocalizedString(
                        "SEPA_DONATION_IBAN_INVALID_CHECK_ERROR",
                        comment: "Users can donate to Signal with a bank account. If their internation bank account number (IBAN) does not pass validation, this error will be shown. Try to use a short string to make space in the UI."
                    )
                case .invalidCountry:
                    return OWSLocalizedString(
                        "SEPA_DONATION_IBAN_INVALID_COUNTRY_ERROR",
                        comment: "Users can donate to Signal with a bank account. If their internation bank account number (IBAN) has an unsupported country code, this error will be shown. Try to use a short string to make space in the UI."
                    )
                case .tooLong:
                    return OWSLocalizedString(
                        "SEPA_DONATION_IBAN_TOO_LONG_ERROR",
                        comment: "Users can donate to Signal with a bank account. If their internation bank account number (IBAN) is too long, this error will be shown. Try to use a short string to make space in the UI."
                    )
                case .tooShort:
                    return OWSLocalizedString(
                        "SEPA_DONATION_IBAN_TOO_SHORT_ERROR",
                        comment: "Users can donate to Signal with a bank account. If their internation bank account number (IBAN) is too long, this error will be shown. Try to use a short string to make space in the UI."
                    )
                }
            }
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
                    cell.contentView.addSubview(self.subheaderTextView)
                    self.subheaderTextView.autoPinEdgesToSuperviewMargins()
                    return cell
                }
            )]
        )
        result.hasBackground = false
        return result
    }()

    // MARK: - Form

    private var formState: FormState {
        switch self.paymentMethod {
        case .card:
            return Self.formState(
                cardNumber: cardNumberView.text,
                isCardNumberFieldFocused: cardNumberView.isFirstResponder,
                expirationDate: expirationView.text,
                cvv: cvvView.text
            )
        case let .sepa(mandate: mandate):
            return Self.formState(
                mandate: mandate,
                iban: ibanView.text,
                isIBANFieldFocused: ibanView.isFirstResponder,
                name: nameView.text,
                email: emailView.text,
                isEmailFieldFocused: emailView.isFirstResponder
            )
        case let .ideal(mandate: mandate):
            return Self.formState(
                mandate: mandate,
                iDEALBank: iDEALBank,
                name: nameView.text,
                email: emailView.text,
                isEmailFieldFocused: emailView.isFirstResponder
            )
        }
    }

    private func formSections() -> [OWSTableSection] {
        switch self.paymentMethod {
        case .card:
            return [creditCardFormSection]
        case .sepa:
            return [sepaFormSection]
        case .ideal:
            return idealFormSections()
        }
    }

    private static func cell(for formFieldView: FormFieldView) -> OWSTableItem {
        .init(customCellBlock: { [weak formFieldView] in
            let cell = OWSTableItem.newCell()
            cell.selectionStyle = .none
            guard let formFieldView else { return cell }
            cell.contentView.addSubview(formFieldView)
            formFieldView.autoPinEdgesToSuperviewMargins()
            return cell
        })
    }

    // MARK: Form field title strings

    private static let cardNumberTitle = OWSLocalizedString(
        "CARD_DONATION_CARD_NUMBER_LABEL",
        comment: "Users can donate to Signal with a credit or debit card. This is the label for the card number field on that screen."
    )

    private static let cardNumberPlaceholder = "0000000000000000"

    private static let expirationTitle = OWSLocalizedString(
        "CARD_DONATION_EXPIRATION_DATE_LABEL",
        comment: "Users can donate to Signal with a credit or debit card. This is the label for the expiration date field on that screen. Try to use a short string to make space in the UI. (For example, the English text uses \"Exp. Date\" instead of \"Expiration Date\")."
    )

    private static let cvvTitle = OWSLocalizedString(
        "CARD_DONATION_CVV_LABEL",
        comment: "Users can donate to Signal with a credit or debit card. This is the label for the card verification code (CVV) field on that screen."
    )

    private static let ibanTitle = OWSLocalizedString(
        "SEPA_DONATION_IBAN_LABEL",
        comment: "Users can donate to Signal with a bank account. This is the label for IBAN (internation bank account number) field on that screen."
    )

    private static let ibanPlaceholder = "DE00000000000000000000"

    private static let nameTitle = OWSLocalizedString(
        "SEPA_DONATION_NAME_LABEL",
        comment: "Users can donate to Signal with a bank account. This is the label for name field on that screen."
    )

    private static let emailTitle = OWSLocalizedString(
        "SEPA_DONATION_EMAIL_LABEL",
        comment: "Users can donate to Signal with a bank account. This is the label for email field on that screen."
    )

    // MARK: Form field title styles

    private lazy var cardFormTitleLayout: FormFieldView.TitleLayout = titleLayout(
        for: [
            Self.cardNumberTitle,
            Self.expirationTitle,
            Self.cvvTitle,
        ],
        titleWidth: 120,
        placeholder: Self.formatCardNumber(unformatted: Self.cardNumberPlaceholder)
    )

    private lazy var sepaFormTitleLayout: FormFieldView.TitleLayout = titleLayout(
        for: [
            Self.ibanTitle,
            Self.nameTitle,
            Self.emailTitle,
        ],
        titleWidth: 60,
        placeholder: Self.formatIBAN(unformatted: Self.ibanPlaceholder)
    )

    private func titleLayout(for titles: [String], titleWidth: CGFloat, placeholder: String) -> FormFieldView.TitleLayout {
        guard
            Self.canTitlesFitInWidth(titles: titles, width: titleWidth),
            self.canPlaceholderFitInAvailableWidth(
                placeholder: placeholder,
                headerWidth: titleWidth
            )
        else { return .compact }

        return .inline(width: titleWidth)
    }

    private static func canTitlesFitInWidth(titles: [String], width: CGFloat) -> Bool {
        titles.allSatisfy { title in
            FormFieldView.titleAttributedString(title).size().width <= width
        }
    }

    private func canPlaceholderFitInAvailableWidth(placeholder: String, headerWidth: CGFloat) -> Bool {
        let placeholderTextWidth = NSAttributedString(string: placeholder, attributes: [.font: FormFieldView.textFieldFont]).size().width
        let insets = self.cellOuterInsets.totalWidth + Self.cellHInnerMargin * 2
        let totalWidth = placeholderTextWidth + insets + headerWidth + FormFieldView.titleSpacing
        return totalWidth <= self.view.width
    }

    // MARK: - Card form

    private lazy var creditCardFormSection = OWSTableSection(items: [
        Self.cell(for: self.cardNumberView),
        Self.cell(for: self.expirationView),
        Self.cell(for: self.cvvView),
    ])

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

    private lazy var cardNumberView = FormFieldView(
        title: Self.cardNumberTitle,
        titleLayout: self.cardFormTitleLayout,
        placeholder: Self.formatCardNumber(unformatted: Self.cardNumberPlaceholder),
        style: .formatted(
            format: Self.formatCardNumber(unformatted:),
            allowedCharacters: .numbers,
            maxDigits: 19
        ),
        textContentType: .creditCardNumber,
        delegate: self
    )

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

    private lazy var expirationView = FormFieldView(
        title: Self.expirationTitle,
        titleLayout: self.cardFormTitleLayout,
        placeholder: OWSLocalizedString(
            "CARD_DONATION_EXPIRATION_DATE_PLACEHOLDER",
            comment: "Users can donate to Signal with a credit or debit card. This is the label for the card expiration date field on that screen."
        ),
        style: .formatted(
            format: Self.formatExpirationDate(unformatted:),
            allowedCharacters: .numbers,
            maxDigits: 4
        ),
        textContentType: nil, // TODO: Add content type for iOS 17
        delegate: self
    )

    // MARK: CVV

    private lazy var cvvView = FormFieldView(
        title: Self.cvvTitle,
        titleLayout: self.cardFormTitleLayout,
        placeholder: "123",
        style: .formatted(
            format: { $0 },
            allowedCharacters: .numbers,
            maxDigits: 4
        ),
        textContentType: nil, // TODO: Add content type for iOS 17,
        delegate: self
    )

    // MARK: - SEPA form

    private lazy var sepaFormSection = {
        let section = OWSTableSection(items: [
            Self.cell(for: self.ibanView),
            Self.cell(for: self.nameView),
            Self.cell(for: self.emailView),
        ])

        let label = LinkingTextView()
        let linkPart = StringStyle.Part.link(SupportConstants.subscriptionFAQURL)
        label.attributedText = OWSLocalizedString(
            "BANK_DONATION_FOOTER_FIND_ACCOUNT_INFO",
            comment: "On the bank donation screen, show a link below the input form to show help about finding account info."
        )
        .styled(with: linkPart)
        .styled(with: .color(Theme.primaryTextColor), .font(.dynamicTypeBody))
        label.linkTextAttributes = [
            .foregroundColor: Theme.accentBlueColor,
            .underlineColor: UIColor.clear,
            .underlineStyle: NSUnderlineStyle.single.rawValue
        ]
        label.textAlignment = .center
        label.delegate = self
        label.textContainerInset = .init(margin: 20)
        section.customFooterView = label

        return section
    }()

    // MARK: IBAN

    static func formatIBAN(unformatted: String) -> String {
        let gaps: Set<Int> = [4, 8, 12, 16, 20, 24, 28, 32]

        var result = unformatted.enumerated().reduce(into: [Character]()) { (partialResult, item) in
            let (i, character) = item
            if gaps.contains(i) {
                partialResult.append(" ")
            }
            partialResult.append(character)
        }
        if gaps.contains(unformatted.count) {
            result.append(" ")
        }
        return String(result)
    }

    private lazy var ibanView: FormFieldView = FormFieldView(
        title: Self.ibanTitle,
        titleLayout: self.sepaFormTitleLayout,
        placeholder: Self.formatIBAN(unformatted: Self.ibanPlaceholder),
        style: .formatted(
            format: Self.formatIBAN(unformatted:),
            allowedCharacters: .alphanumeric,
            maxDigits: 34
        ),
        textContentType: nil,
        delegate: self
    )

    // MARK: iDEAL

    private func idealFormSections() -> [OWSTableSection] {
        return [
            OWSTableSection(items: [
                OWSTableItem(customCellBlock: { [weak self] in
                    if let bank = self?.iDEALBank {
                        return OWSTableItem.buildImageCell(
                            image: bank.image,
                            itemName: bank.displayName,
                            accessoryType: .disclosureIndicator
                        )
                    } else {
                        return OWSTableItem.buildImageCell(
                            image: UIImage(named: "building")?.withRenderingMode(.alwaysTemplate),
                            itemName: OWSLocalizedString(
                                "IDEAL_DONATION_CHOOSE_YOUR_BANK_LABEL",
                                comment: "Label for both bank chooser header and the bank form field on the iDEAL payment detail page."
                            ),
                            accessoryType: .disclosureIndicator
                        )
                    }
                }, actionBlock: { [weak self] in
                    let bankSelectionVC = DonationPaymentDetailsSelectIdealBankViewController()
                    bankSelectionVC.bankSelectionDelegate = self
                    self?.navigationController?.pushViewController(bankSelectionVC, animated: true)
                })
            ]),
            OWSTableSection(items: [
                Self.cell(for: self.nameView),
                Self.cell(for: self.emailView),
            ])
        ]
    }

    // MARK: Name & Email

    private var iDEALBank: Stripe.PaymentMethod.IDEALBank?

    private lazy var nameView = FormFieldView(
        title: Self.nameTitle,
        titleLayout: self.sepaFormTitleLayout,
        placeholder: OWSLocalizedString(
            "SEPA_DONATION_NAME_PLACEHOLDER",
            comment: "Users can donate to Signal with a bank account. This is placeholder text for the name field before the user starts typing."
        ),
        style: .plain(keyboardType: .default),
        textContentType: .name,
        delegate: self
    )

    private lazy var emailView = FormFieldView(
        title: Self.emailTitle,
        titleLayout: self.sepaFormTitleLayout,
        placeholder: OWSLocalizedString(
            "SEPA_DONATION_EMAIL_PLACEHOLDER",
            comment: "Users can donate to Signal with a bank account. This is placeholder text for the email field before the user starts typing."
        ),
        style: .plain(keyboardType: .emailAddress),
        textContentType: .emailAddress,
        delegate: self
    )

    // MARK: - Submit button, footer

    private lazy var submitButton: OWSButton = {
        let title = {
            let amountString = DonationUtilities.format(money: self.donationAmount)
            let format: String
            switch self.donationMode {
            case .oneTime, .gift:
                format = OWSLocalizedString(
                    "DONATE_BUTTON",
                    comment: "Users can donate to Signal with a credit or debit card. This is the heading on that screen, telling them how much they'll donate. Embeds {{formatted amount of money}}, such as \"$20\"."
                )
            case .monthly:
                format = OWSLocalizedString(
                    "DONATE_BUTTON_MONTHLY",
                    comment: "Users can donate to Signal with a credit or debit card. This is the heading on that screen, telling them how much they'll donate every month. Embeds {{formatted amount of money}}, such as \"$20\"."
                )
            }
            return String(format: format, amountString)
        }()

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

extension DonationPaymentDetailsViewController: UITextViewDelegate {
    func textView(
        _ textView: UITextView,
        shouldInteractWith URL: URL,
        in characterRange: NSRange,
        interaction: UITextItemInteraction
    ) -> Bool {
        if textView == subheaderTextView {
            present(DonationPaymentDetailsReadMoreSheetViewController(), animated: true)
        } else {
            present(DonationPaymentDetailsFindAccountInfoSheetViewController(), animated: true)
        }
        return false
    }
}

// MARK: - CreditOrDebitCardDonationFormViewDelegate

extension DonationPaymentDetailsViewController: CreditOrDebitCardDonationFormViewDelegate {
    func didSomethingChange() { render() }
}

// MARK: - DonationPaymentDetailsSelectIdealBankDelegate

extension DonationPaymentDetailsViewController: DonationPaymentDetailsSelectIdealBankDelegate {
    func viewController(
        _ viewController: DonationPaymentDetailsSelectIdealBankViewController,
        didSelect iDEALBank: SignalMessaging.Stripe.PaymentMethod.IDEALBank
    ) {
        self.iDEALBank = iDEALBank
        let sections = [donationAmountSection] + formSections()
        contents = OWSTableContents(sections: sections)
        viewController.navigationController?.popViewController(animated: true)
        render()
    }
}

// MARK: - Utilities

fileprivate extension UInt8 {
    var isValidAsMonth: Bool { self >= 1 && self <= 12 }
}
