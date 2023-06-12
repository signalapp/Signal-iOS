//
// Copyright 2019 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import UIKit

@objc
public protocol FindByPhoneNumberDelegate: AnyObject {
    func findByPhoneNumber(_ findByPhoneNumber: FindByPhoneNumberViewController,
                           didSelectAddress address: SignalServiceAddress)
}

public class FindByPhoneNumberViewController: OWSViewController, OWSNavigationChildController {
    weak var delegate: FindByPhoneNumberDelegate?
    let buttonText: String?
    let requiresRegisteredNumber: Bool

    var callingCode: String = "+1"
    let countryCodeLabel = UILabel()
    let phoneNumberTextField = OWSTextField()
    let exampleLabel = UILabel()
    let button = OWSFlatButton()
    let countryRowTitleLabel = UILabel()
    let phoneNumberRowTitleLabel = UILabel()

    @objc
    public init(delegate: FindByPhoneNumberDelegate, buttonText: String?, requiresRegisteredNumber: Bool) {
        self.delegate = delegate
        self.buttonText = buttonText
        self.requiresRegisteredNumber = requiresRegisteredNumber
        super.init()
    }

    var backgroundColor: UIColor {
        presentingViewController == nil ? Theme.backgroundColor : Theme.tableView2PresentedBackgroundColor
    }

    public var preferredNavigationBarStyle: OWSNavigationBarStyle {
        return .solid
    }

    public var navbarBackgroundColorOverride: UIColor? {
        return backgroundColor
    }

    override public func viewDidLoad() {
        super.viewDidLoad()

        title = OWSLocalizedString("NEW_NONCONTACT_CONVERSATION_VIEW_TITLE",
                                  comment: "Title for the 'new non-contact conversation' view.")

        let stackView = UIStackView()
        stackView.axis = .vertical
        stackView.isLayoutMarginsRelativeArrangement = true
        stackView.layoutMargins = UIEdgeInsets(top: 10, leading: 18, bottom: 10, trailing: 18)
        stackView.spacing = 15

        view.addSubview(stackView)
        stackView.autoPinWidthToSuperviewMargins()
        stackView.autoPin(toTopLayoutGuideOf: self, withInset: 0)

        // Country Row
        let countryRow = UIView.container()
        countryRow.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(didTapCountryRow)))
        stackView.addArrangedSubview(countryRow)

        countryRowTitleLabel.text = OWSLocalizedString("REGISTRATION_DEFAULT_COUNTRY_NAME", comment: "Label for the country code field")
        countryRowTitleLabel.font = UIFont.dynamicTypeBodyClamped.semibold()
        countryRowTitleLabel.accessibilityIdentifier =
            UIView.accessibilityIdentifier(in: self, name: "countryRowTitleLabel")

        countryRow.addSubview(countryRowTitleLabel)
        countryRowTitleLabel.autoPinLeadingToSuperviewMargin()
        countryRowTitleLabel.autoPinHeightToSuperviewMargins()

        countryCodeLabel.textColor = Theme.accentBlueColor
        countryCodeLabel.font = UIFont.dynamicTypeBodyClamped.semibold()
        countryCodeLabel.textAlignment = .right
        countryCodeLabel.accessibilityIdentifier =
            UIView.accessibilityIdentifier(in: self, name: "countryCodeLabel")

        countryRow.addSubview(countryCodeLabel)
        countryCodeLabel.autoPinLeading(toTrailingEdgeOf: countryRowTitleLabel, offset: 10)
        countryCodeLabel.autoPinTrailingToSuperviewMargin()
        countryCodeLabel.autoVCenterInSuperview()

        // Phone Number row

        let phoneNumberRow = UIView.container()
        stackView.addArrangedSubview(phoneNumberRow)

        phoneNumberRowTitleLabel.text = OWSLocalizedString("REGISTRATION_PHONENUMBER_BUTTON",
                                                          comment: "Label for the phone number textfield")
        phoneNumberRowTitleLabel.font = UIFont.dynamicTypeBodyClamped.semibold()
        phoneNumberRowTitleLabel.accessibilityIdentifier =
            UIView.accessibilityIdentifier(in: self, name: "phoneNumberRowTitleLabel")

        phoneNumberRow.addSubview(phoneNumberRowTitleLabel)
        phoneNumberRowTitleLabel.autoPinLeadingToSuperviewMargin()
        phoneNumberRowTitleLabel.autoPinHeightToSuperviewMargins()

        phoneNumberTextField.font = .dynamicTypeBodyClamped
        phoneNumberTextField.textColor = Theme.accentBlueColor
        phoneNumberTextField.autocorrectionType = .no
        phoneNumberTextField.autocapitalizationType = .none
        phoneNumberTextField.placeholder = OWSLocalizedString("REGISTRATION_ENTERNUMBER_DEFAULT_TEXT",
                                                             comment: "Placeholder text for the phone number textfield")
        phoneNumberTextField.accessibilityIdentifier =
            UIView.accessibilityIdentifier(in: self, name: "phoneNumberTextField")

        phoneNumberTextField.textAlignment = .right
        phoneNumberTextField.keyboardType = .numberPad
        phoneNumberTextField.delegate = self
        phoneNumberTextField.returnKeyType = .done
        phoneNumberTextField.becomeFirstResponder()

        phoneNumberRow.addSubview(phoneNumberTextField)
        phoneNumberTextField.autoPinLeading(toTrailingEdgeOf: phoneNumberRowTitleLabel, offset: 10)
        phoneNumberTextField.autoPinTrailingToSuperviewMargin()
        phoneNumberTextField.autoVCenterInSuperview()

        // Example row

        stackView.addArrangedSubview(exampleLabel)

        exampleLabel.font = .dynamicTypeFootnoteClamped
        exampleLabel.textAlignment = .right

        populateDefaultCountryCode()

        // Button row

        let buttonHeight: CGFloat = 47
        let buttonTitle = buttonText ?? OWSLocalizedString("NEW_NONCONTACT_CONVERSATION_VIEW_BUTTON",
                                                          comment: "A label for the 'add by phone number' button in the 'new non-contact conversation' view")

        stackView.addArrangedSubview(button)
        button.useDefaultCornerRadius()
        button.autoSetDimension(.height, toSize: buttonHeight)
        button.setTitle(title: buttonTitle, font: OWSFlatButton.fontForHeight(buttonHeight), titleColor: .white)
        button.setBackgroundColors(upColor: .ows_accentBlue)
        button.addTarget(target: self, selector: #selector(tryToSelectPhoneNumber))
        button.setEnabled(false)
        button.accessibilityIdentifier =
            UIView.accessibilityIdentifier(in: self, name: "button")

        applyTheme()
    }

    public override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)

        applyTheme()
    }

    public override func themeDidChange() {
        super.themeDidChange()
        applyTheme()
    }

    private func applyTheme() {
        view.backgroundColor = backgroundColor
        countryRowTitleLabel.textColor = Theme.primaryTextColor
        phoneNumberRowTitleLabel.textColor = Theme.primaryTextColor
        exampleLabel.textColor = Theme.secondaryTextAndIconColor

        if let navigationBar = navigationController?.navigationBar as? OWSNavigationBar {
            navigationBar.navbarBackgroundColorOverride = backgroundColor
        }
    }

    func updateButtonState() {
        button.setEnabled(hasValidPhoneNumber())
    }

    func validPhoneNumber() -> String? {
        guard let localNumber = TSAccountManager.localNumber else {
            owsFailDebug("local number unexpectedly nil")
            return nil
        }
        guard let userSpecifiedText = phoneNumberTextField.text else {
            return nil
        }
        let possiblePhoneNumbers = PhoneNumber.tryParsePhoneNumbers(
            fromUserSpecifiedText: callingCode + userSpecifiedText,
            clientPhoneNumber: localNumber
        )
        let possibleValidPhoneNumbers = possiblePhoneNumbers.map { $0.toE164() }.filter { !$0.isEmpty }

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
                    Self.contactDiscoveryManager.lookUp(phoneNumbers: [phoneNumber], mode: .oneOffUserRequest)
                }.done(on: DispatchQueue.main) { [weak self] recipients in
                    modal.dismissIfNotCanceled {
                        guard let self = self else { return }
                        guard let recipient = recipients.first else {
                            return OWSActionSheets.showErrorAlert(message: MessageSenderNoSuchSignalRecipientError().userErrorDescription)
                        }
                        self.delegate?.findByPhoneNumber(self, didSelectAddress: recipient.address)
                    }
                }.catch(on: DispatchQueue.main) { error in
                    modal.dismissIfNotCanceled {
                        OWSActionSheets.showErrorAlert(message: error.userErrorDescription)
                    }
                }
            }
        } else {
            delegate?.findByPhoneNumber(self, didSelectAddress: SignalServiceAddress(phoneNumber: phoneNumber))
        }
    }
}

// MARK: - Country

extension FindByPhoneNumberViewController: CountryCodeViewControllerDelegate {
    public func countryCodeViewController(_ vc: CountryCodeViewController,
                                          didSelectCountry countryState: RegistrationCountryState) {
        updateCountry(callingCode: countryState.callingCode,
                      countryCode: countryState.countryCode)
    }

    @objc
    private func didTapCountryRow() {
        let countryCodeController = CountryCodeViewController()
        countryCodeController.countryCodeDelegate = self
        presentFormSheet(OWSNavigationController(rootViewController: countryCodeController), animated: true)
    }

    func populateDefaultCountryCode() {
        guard let localNumber = TSAccountManager.localNumber else {
            return owsFailDebug("Local number unexpectedly nil")
        }

        var callingCodeInt: Int?
        var countryCode: String?

        if let localE164 = PhoneNumber(fromE164: localNumber), let localCountryCode = localE164.getCountryCode()?.intValue {
            callingCodeInt = localCountryCode
        } else {
            callingCodeInt = phoneNumberUtil.getCountryCode(forRegion: PhoneNumber.defaultCountryCode()).intValue
        }

        var callingCode: String?
        if let callingCodeInt = callingCodeInt {
            callingCode = COUNTRY_CODE_PREFIX + "\(callingCodeInt)"
            countryCode = phoneNumberUtil.probableCountryCode(forCallingCode: callingCode!)
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
        exampleLabel.text = TextFieldFormatting.examplePhoneNumber(forCountryCode: countryCode, callingCode: callingCode, includeExampleLabel: true)
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
