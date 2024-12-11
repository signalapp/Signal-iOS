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

    private var country: PhoneNumberCountry!
    let countryCodeLabel = UILabel()
    private lazy var nationalNumberTextField = OWSTextField(
        keyboardType: .numberPad,
        returnKeyType: .done,
        autocorrectionType: .no,
        delegate: self
    )
    let countryRowTitleLabel = UILabel()
    let nationalNumberRowTitleLabel = UILabel()

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

    private var nationalNumberTitle: NSAttributedString {
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
        populateDefaultCountryCode()
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
            [countryTitle, nationalNumberTitle].allSatisfy { string in
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

        nationalNumberRowTitleLabel.attributedText = nationalNumberTitle

        phoneNumberStack.addArrangedSubview(nationalNumberRowTitleLabel)

        if useInlineTitles {
            nationalNumberRowTitleLabel.autoSetDimension(.width, toSize: titleWidth)
        }

        nationalNumberTextField.becomeFirstResponder()

        phoneNumberStack.addArrangedSubview(nationalNumberTextField)

        section.add(.init(customCellBlock: { phoneNumberCell }))

        self.contents = content

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
        nationalNumberRowTitleLabel.attributedText = nationalNumberTitle
        nationalNumberTextField.attributedPlaceholder = phoneNumberPlaceholder
        nationalNumberTextField.textColor = Theme.primaryTextColor
    }

    func updateButtonState() {
        navigationItem.rightBarButtonItem?.isEnabled = hasValidPhoneNumber()
    }

    func validPhoneNumber() -> String? {
        guard let nationalNumber = nationalNumberTextField.text else {
            return nil
        }
        let phoneNumberUtil = SSKEnvironment.shared.phoneNumberUtilRef
        return phoneNumberUtil.parsePhoneNumber(
            countryCode: country.countryCode,
            nationalNumber: nationalNumber
        )?.e164.nilIfEmpty
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

        nationalNumberTextField.resignFirstResponder()

        if requiresRegisteredNumber {
            ModalActivityIndicatorViewController.present(
                fromViewController: self,
                canCancel: true,
                asyncBlock: { modal in
                    do {
                        let recipients = try await SSKEnvironment.shared.contactDiscoveryManagerRef.lookUp(phoneNumbers: [phoneNumber], mode: .oneOffUserRequest)
                        modal.dismissIfNotCanceled {
                            guard let recipient = recipients.first else {
                                return OWSActionSheets.showErrorAlert(
                                    message: MessageSenderNoSuchSignalRecipientError().userErrorDescription,
                                    dismissalDelegate: self
                                )
                            }
                            self.findByPhoneNumberDelegate?.findByPhoneNumber(self, didSelectAddress: recipient.address)
                        }
                    } catch {
                        modal.dismissIfNotCanceled {
                            OWSActionSheets.showErrorAlert(
                                message: error.userErrorDescription,
                                dismissalDelegate: self
                            )
                        }
                    }
                }
            )
        } else {
            findByPhoneNumberDelegate?.findByPhoneNumber(self, didSelectAddress: SignalServiceAddress(phoneNumber: phoneNumber))
        }
    }
}

// MARK: - SheetDismissalDelegate

extension FindByPhoneNumberViewController: SheetDismissalDelegate {
    public func didDismissPresentedSheet() {
        nationalNumberTextField.becomeFirstResponder()
    }
}

// MARK: - Country

extension FindByPhoneNumberViewController: CountryCodeViewControllerDelegate {
    public func countryCodeViewController(_ vc: CountryCodeViewController, didSelectCountry country: PhoneNumberCountry) {
        updateCountry(country)
    }

    private func didTapCountryRow() {
        let countryCodeController = CountryCodeViewController()
        countryCodeController.countryCodeDelegate = self
        presentFormSheet(OWSNavigationController(rootViewController: countryCodeController), animated: true)
    }

    private func populateDefaultCountryCode() {
        let tsAccountManager = DependenciesBridge.shared.tsAccountManager
        let phoneNumberUtil = SSKEnvironment.shared.phoneNumberUtilRef
        let defaultCountry: PhoneNumberCountry
        if
            let localNumber = tsAccountManager.localIdentifiersWithMaybeSneakyTransaction?.phoneNumber,
            let localCountry = PhoneNumberCountry.buildCountry(forCountryCode: phoneNumberUtil.preferredCountryCode(forLocalNumber: localNumber))
        {
            defaultCountry = localCountry
        } else {
            owsFailDebug("Couldn't determine local country.")
            defaultCountry = .defaultValue
        }
        updateCountry(defaultCountry)
    }

    private func updateCountry(_ country: PhoneNumberCountry) {
        self.country = country
        let labelFormat = CurrentAppContext().isRTL ? "(%2$@) %1$@" : "%1$@ (%2$@)"
        countryCodeLabel.text = String(format: labelFormat, country.plusPrefixedCallingCode, country.countryCode.localizedUppercase)
    }
}

extension FindByPhoneNumberViewController: UITextFieldDelegate {
    public func textField(_ textField: UITextField, shouldChangeCharactersIn range: NSRange, replacementString string: String) -> Bool {
        TextFieldFormatting.phoneNumberTextField(textField, changeCharactersIn: range, replacementString: string, plusPrefixedCallingCode: country.plusPrefixedCallingCode)
        updateButtonState()
        return false
    }

    public func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        tryToSelectPhoneNumber()
        return false
    }
}
