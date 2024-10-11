//
// Copyright 2019 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

public import SignalServiceKit

public protocol FindByPhoneNumberDelegate: AnyObject {
    func findByPhoneNumber(_ findByPhoneNumber: FindByPhoneNumberViewController,
                           didSelectAddress address: SignalServiceAddress)
}

public class FindByPhoneNumberViewController: OWSTableViewController2 {
    weak var findByPhoneNumberDelegate: FindByPhoneNumberDelegate?
    let buttonText: String?
    let requiresRegisteredNumber: Bool

    var callingCode: String = "+1"
    let countryCodeLabel = UILabel()
    private lazy var phoneNumberTextField = OWSTextField(
        keyboardType: .numberPad,
        returnKeyType: .done,
        autocorrectionType: .no,
        delegate: self
    )
    let countryRowTitleLabel = UILabel()
    let phoneNumberRowTitleLabel = UILabel()

    public init(delegate: FindByPhoneNumberDelegate, buttonText: String?, requiresRegisteredNumber: Bool) {
        self.findByPhoneNumberDelegate = delegate
        self.buttonText = buttonText
        self.requiresRegisteredNumber = requiresRegisteredNumber
        super.init()
    }

    private var titleAttributes: [NSAttributedString.Key: Any] {
        [
            .font: UIFont.dynamicTypeBodyClamped.semibold(),
            .foregroundColor: Theme.primaryTextColor,
        ]
    }

    private var countryTitle: NSAttributedString {
        NSAttributedString(
            string: OWSLocalizedString(
                "REGISTRATION_DEFAULT_COUNTRY_NAME",
                comment: "Label for the country code field"
            ),
            attributes: titleAttributes
        )
    }

    private var phoneNumberTitle: NSAttributedString {
        NSAttributedString(
            string: OWSLocalizedString(
                "REGISTRATION_PHONENUMBER_BUTTON",
                comment: "Label for the phone number textfield"
            ),
            attributes: titleAttributes
        )
    }

    private var phoneNumberPlaceholder: NSAttributedString {
        NSAttributedString(
            string: OWSLocalizedString(
                "REGISTRATION_ENTERNUMBER_DEFAULT_TEXT",
                comment: "Placeholder text for the phone number textfield"
            ),
            attributes: [
                .font: UIFont.dynamicTypeBodyClamped,
            ]
        )
    }

    override public func viewDidLoad() {
        super.viewDidLoad()
        loadTableContents()
    }

    private func loadTableContents() {
        let section = OWSTableSection()

        let content = OWSTableContents(
            title: OWSLocalizedString(
                "NEW_NONCONTACT_CONVERSATION_VIEW_TITLE",
                comment: "Title for the 'new non-contact conversation' view."
            ),
            sections: [section]
        )

        let titleWidth: CGFloat = 138
        let useInlineTitles: Bool = {
            [countryTitle, phoneNumberTitle].allSatisfy { string in
                string.size().width <= titleWidth
            }
        }()

        let countryCell = OWSTableItem.newCell()
        countryCell.accessoryType = .disclosureIndicator

        let countryStack = UIStackView()
        countryCell.addSubview(countryStack)
        countryStack.autoPinEdgesToSuperviewMargins()
        countryStack.axis = useInlineTitles ? .horizontal : .vertical
        countryStack.spacing = useInlineTitles ? 10 : 0

        countryRowTitleLabel.attributedText = countryTitle
        countryRowTitleLabel.accessibilityIdentifier =
            UIView.accessibilityIdentifier(in: self, name: "countryRowTitleLabel")

        countryStack.addArrangedSubview(countryRowTitleLabel)

        if useInlineTitles {
            countryRowTitleLabel.autoSetDimension(.width, toSize: titleWidth)
        }

        countryCodeLabel.font = UIFont.dynamicTypeBodyClamped
        countryCodeLabel.accessibilityIdentifier =
            UIView.accessibilityIdentifier(in: self, name: "countryCodeLabel")

        countryStack.addArrangedSubview(countryCodeLabel)

        section.add(.init(customCellBlock: {
            countryCell
        }, actionBlock: { [weak self] in
            self?.didTapCountryRow()
        }))

        // Phone Number row

        let phoneNumberCell = OWSTableItem.newCell()

        let phoneNumberStack = UIStackView()
        phoneNumberCell.contentView.addSubview(phoneNumberStack)
        phoneNumberStack.autoPinEdgesToSuperviewMargins()
        phoneNumberStack.axis = useInlineTitles ? .horizontal : .vertical
        phoneNumberStack.spacing = useInlineTitles ? 10 : 0

        phoneNumberRowTitleLabel.attributedText = phoneNumberTitle
        phoneNumberRowTitleLabel.accessibilityIdentifier =
            UIView.accessibilityIdentifier(in: self, name: "phoneNumberRowTitleLabel")

        phoneNumberStack.addArrangedSubview(phoneNumberRowTitleLabel)

        if useInlineTitles {
            phoneNumberRowTitleLabel.autoSetDimension(.width, toSize: titleWidth)
        }

        phoneNumberTextField.becomeFirstResponder()

        phoneNumberStack.addArrangedSubview(phoneNumberTextField)

        section.add(.init(customCellBlock: { phoneNumberCell }))

        self.contents = content

        populateDefaultCountryCode()

        navigationItem.rightBarButtonItem = UIBarButtonItem(
            title: CommonStrings.nextButton,
            style: .done,
            target: self,
            action: #selector(tryToSelectPhoneNumber),
            accessibilityIdentifier: UIView.accessibilityIdentifier(in: self, name: "button")
        )
        navigationItem.rightBarButtonItem?.isEnabled = false

        applyTheme()
    }

    public override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)

        applyTheme()
    }

    public override func contentSizeCategoryDidChange() {
        super.contentSizeCategoryDidChange()
        loadTableContents()
    }

    public override func themeDidChange() {
        super.themeDidChange()
        applyTheme()
    }

    private func applyTheme() {
        countryRowTitleLabel.attributedText = countryTitle
        countryCodeLabel.textColor = .placeholderText
        phoneNumberRowTitleLabel.attributedText = phoneNumberTitle
        phoneNumberTextField.attributedPlaceholder = phoneNumberPlaceholder
        phoneNumberTextField.textColor = Theme.primaryTextColor
    }

    func updateButtonState() {
        navigationItem.rightBarButtonItem?.isEnabled = hasValidPhoneNumber()
    }

    func validPhoneNumber() -> String? {
        guard let localNumber = DependenciesBridge.shared.tsAccountManager.localIdentifiersWithMaybeSneakyTransaction?.phoneNumber else {
            owsFailDebug("local number unexpectedly nil")
            return nil
        }
        guard let userSpecifiedText = phoneNumberTextField.text else {
            return nil
        }
        let possiblePhoneNumbers = SSKEnvironment.shared.phoneNumberUtilRef.parsePhoneNumbers(
            userSpecifiedText: callingCode + userSpecifiedText,
            localPhoneNumber: localNumber
        )
        let possibleValidPhoneNumbers = possiblePhoneNumbers.map { $0.e164 }.filter { !$0.isEmpty }

        // There should only be one phone number, since we're explicitly specifying
        // a country code and therefore parsing a number in e164 format.
        owsAssertDebug(possibleValidPhoneNumbers.count <= 1)

        return possibleValidPhoneNumbers.first
    }

    func hasValidPhoneNumber() -> Bool {
        // It'd be nice to use [PhoneNumber isValid] but it always returns false
        // for some countries (like Afghanistan), and there doesn't seem to be a
        // good way to determine beforehand which countries it can validate without
        // forking libPhoneNumber. Instead, we consider it valid if we can convert
        // it to a non-empty e164 (which is the same validation we use when the
        // user submits the number).
        return validPhoneNumber() != nil
    }

    @objc
    private func tryToSelectPhoneNumber() {
        guard let phoneNumber = validPhoneNumber() else {
            return
        }

        phoneNumberTextField.resignFirstResponder()

        if requiresRegisteredNumber {
            ModalActivityIndicatorViewController.present(fromViewController: self, canCancel: true) { modal in
                firstly { () -> Promise<Set<SignalRecipient>> in
                    SSKEnvironment.shared.contactDiscoveryManagerRef.lookUp(phoneNumbers: [phoneNumber], mode: .oneOffUserRequest)
                }.done(on: DispatchQueue.main) { [weak self] recipients in
                    modal.dismissIfNotCanceled {
                        guard let self = self else { return }
                        guard let recipient = recipients.first else {
                            return OWSActionSheets.showErrorAlert(
                                message: MessageSenderNoSuchSignalRecipientError().userErrorDescription,
                                dismissalDelegate: self
                            )
                        }
                        self.findByPhoneNumberDelegate?.findByPhoneNumber(self, didSelectAddress: recipient.address)
                    }
                }.catch(on: DispatchQueue.main) { error in
                    modal.dismissIfNotCanceled {
                        OWSActionSheets.showErrorAlert(
                            message: error.userErrorDescription,
                            dismissalDelegate: self
                        )
                    }
                }
            }
        } else {
            findByPhoneNumberDelegate?.findByPhoneNumber(self, didSelectAddress: SignalServiceAddress(phoneNumber: phoneNumber))
        }
    }
}

// MARK: - SheetDismissalDelegate

extension FindByPhoneNumberViewController: SheetDismissalDelegate {
    public func didDismissPresentedSheet() {
        phoneNumberTextField.becomeFirstResponder()
    }
}

// MARK: - Country

extension FindByPhoneNumberViewController: CountryCodeViewControllerDelegate {
    public func countryCodeViewController(_ vc: CountryCodeViewController,
                                          didSelectCountry countryState: RegistrationCountryState) {
        updateCountry(callingCode: countryState.callingCode,
                      countryCode: countryState.countryCode)
    }

    private func didTapCountryRow() {
        let countryCodeController = CountryCodeViewController()
        countryCodeController.countryCodeDelegate = self
        presentFormSheet(OWSNavigationController(rootViewController: countryCodeController), animated: true)
    }

    func populateDefaultCountryCode() {
        guard let localNumber = DependenciesBridge.shared.tsAccountManager.localIdentifiersWithMaybeSneakyTransaction?.phoneNumber else {
            return owsFailDebug("Local number unexpectedly nil")
        }

        var callingCodeInt: Int?
        var countryCode: String?

        if let localE164 = SSKEnvironment.shared.phoneNumberUtilRef.parseE164(localNumber), let localCallingCode = localE164.getCallingCode()?.intValue {
            callingCodeInt = localCallingCode
        } else {
            callingCodeInt = SSKEnvironment.shared.phoneNumberUtilRef.getCallingCode(forRegion: PhoneNumberUtil.defaultCountryCode()).intValue
        }

        var callingCode: String?
        if let callingCodeInt = callingCodeInt {
            callingCode = PhoneNumber.countryCodePrefix + "\(callingCodeInt)"
            countryCode = SSKEnvironment.shared.phoneNumberUtilRef.probableCountryCode(forCallingCode: callingCode!)
        }

        updateCountry(callingCode: callingCode, countryCode: countryCode)
    }

    func updateCountry(callingCode: String?, countryCode: String?) {
        guard let callingCode = callingCode, !callingCode.isEmpty, let countryCode = countryCode, !countryCode.isEmpty else {
            return owsFailDebug("missing calling code for selected country")
        }

        self.callingCode = callingCode
        let labelFormat = CurrentAppContext().isRTL ? "(%2$@) %1$@" : "%1$@ (%2$@)"
        countryCodeLabel.text = String(format: labelFormat, callingCode, countryCode.localizedUppercase)
    }
}

extension FindByPhoneNumberViewController: UITextFieldDelegate {
    public func textField(_ textField: UITextField, shouldChangeCharactersIn range: NSRange, replacementString string: String) -> Bool {
        TextFieldFormatting.phoneNumberTextField(textField, changeCharactersIn: range, replacementString: string, callingCode: callingCode)
        updateButtonState()
        return false
    }

    public func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        tryToSelectPhoneNumber()
        return false
    }
}
