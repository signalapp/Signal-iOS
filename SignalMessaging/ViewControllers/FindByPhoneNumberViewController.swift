//
//  Copyright (c) 2020 Open Whisper Systems. All rights reserved.
//

import Foundation
import PromiseKit

@objc
public protocol FindByPhoneNumberDelegate: class {
    func findByPhoneNumber(_ findByPhoneNumber: FindByPhoneNumberViewController,
                           didSelectAddress address: SignalServiceAddress)
}

@objc
public class FindByPhoneNumberViewController: OWSViewController {
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
    init(delegate: FindByPhoneNumberDelegate, buttonText: String?, requiresRegisteredNumber: Bool) {
        self.delegate = delegate
        self.buttonText = buttonText
        self.requiresRegisteredNumber = requiresRegisteredNumber
        super.init()
    }

    override public func viewDidLoad() {
        super.viewDidLoad()

        title = NSLocalizedString("NEW_NONCONTACT_CONVERSATION_VIEW_TITLE",
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

        countryRowTitleLabel.text = NSLocalizedString("REGISTRATION_DEFAULT_COUNTRY_NAME", comment: "Label for the country code field")
        countryRowTitleLabel.font = UIFont.ows_dynamicTypeBodyClamped.ows_semibold
        countryRowTitleLabel.accessibilityIdentifier =
            UIView.accessibilityIdentifier(in: self, name: "countryRowTitleLabel")

        countryRow.addSubview(countryRowTitleLabel)
        countryRowTitleLabel.autoPinLeadingToSuperviewMargin()
        countryRowTitleLabel.autoPinHeightToSuperviewMargins()

        countryCodeLabel.textColor = Theme.accentBlueColor
        countryCodeLabel.font = UIFont.ows_dynamicTypeBodyClamped.ows_semibold
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

        phoneNumberRowTitleLabel.text = NSLocalizedString("REGISTRATION_PHONENUMBER_BUTTON",
                                                          comment: "Label for the phone number textfield")
        phoneNumberRowTitleLabel.font = UIFont.ows_dynamicTypeBodyClamped.ows_semibold
        phoneNumberRowTitleLabel.accessibilityIdentifier =
            UIView.accessibilityIdentifier(in: self, name: "phoneNumberRowTitleLabel")

        phoneNumberRow.addSubview(phoneNumberRowTitleLabel)
        phoneNumberRowTitleLabel.autoPinLeadingToSuperviewMargin()
        phoneNumberRowTitleLabel.autoPinHeightToSuperviewMargins()

        phoneNumberTextField.font = .ows_dynamicTypeBodyClamped
        phoneNumberTextField.textColor = Theme.accentBlueColor
        phoneNumberTextField.autocorrectionType = .no
        phoneNumberTextField.autocapitalizationType = .none
        phoneNumberTextField.placeholder = NSLocalizedString("REGISTRATION_ENTERNUMBER_DEFAULT_TEXT",
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

        exampleLabel.font = .ows_dynamicTypeFootnoteClamped
        exampleLabel.textAlignment = .right

        populateDefaultCountryCode()

        // Button row

        let buttonHeight: CGFloat = 47
        let buttonTitle = buttonText ?? NSLocalizedString("NEW_NONCONTACT_CONVERSATION_VIEW_BUTTON",
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

    private func applyTheme() {
        view.backgroundColor = Theme.backgroundColor
        countryRowTitleLabel.textColor = Theme.primaryTextColor
        phoneNumberRowTitleLabel.textColor = Theme.primaryTextColor
        exampleLabel.textColor = Theme.secondaryTextAndIconColor
    }

    func updateButtonState() {
        button.setEnabled(hasValidPhoneNumber())
    }

    func possiblePhoneNumbers() -> [PhoneNumber] {
        guard let localNumber = TSAccountManager.localNumber else {
            owsFailDebug("local number unexpectedly nil")
            return []
        }
        guard let phoneNumberText = phoneNumberTextField.text else { return [] }
        let possiblePhoneNumber = callingCode + phoneNumberText
        return PhoneNumber.tryParsePhoneNumbers(fromUserSpecifiedText: possiblePhoneNumber, clientPhoneNumber: localNumber)
    }

    func hasValidPhoneNumber() -> Bool {
        let phoneNumbers = possiblePhoneNumbers()
        guard phoneNumbers.count > 0 else {
            return false
        }

        // It'd be nice to use [PhoneNumber isValid] but it always returns false for some countries
        // (like afghanistan) and there doesn't seem to be a good way to determine beforehand
        // which countries it can validate for without forking libPhoneNumber.
        return !phoneNumbers[0].toE164().isEmpty
    }

    @objc func tryToSelectPhoneNumber() {
        guard hasValidPhoneNumber() else { return }

        let phoneNumbers = possiblePhoneNumbers()
        guard phoneNumbers.count > 0 else { return owsFailDebug("unexpectedly found no numbers") }

        // There should only be one phone number, since we're explicitly specifying
        // a country code and therefore parsing a number in e164 format.
        assert(phoneNumbers.count == 1)

        phoneNumberTextField.resignFirstResponder()

        if requiresRegisteredNumber {
            ModalActivityIndicatorViewController.present(fromViewController: self, canCancel: true) { [weak self] modal in
                let discoverySet = Set(phoneNumbers.map { $0.toE164() })
                let discoveryTask = ContactDiscoveryTask(phoneNumbers: discoverySet)
                firstly { () -> Promise<Set<SignalRecipient>> in
                    discoveryTask.perform(at: .userInitiated)

                }.done(on: .main) { recipients in
                    AssertIsOnMainThread()

                    guard !modal.wasCancelled else { return }
                    guard let self = self else { return }

                    modal.dismiss {
                        guard let recipient = recipients.first else {
                            return OWSActionSheets.showErrorAlert(message: OWSErrorMakeNoSuchSignalRecipientError().localizedDescription)
                        }

                        self.delegate?.findByPhoneNumber(self, didSelectAddress: recipient.address)
                    }

                }.catch(on: .main) { error in
                    AssertIsOnMainThread()
                    guard !modal.wasCancelled else { return }

                    modal.dismiss {
                        OWSActionSheets.showErrorAlert(message: error.localizedDescription)
                    }
                }
            }
        } else {
            delegate?.findByPhoneNumber(self, didSelectAddress: SignalServiceAddress(phoneNumber: phoneNumbers[0].toE164()))
        }
    }
}

// MARK: - Country

extension FindByPhoneNumberViewController: CountryCodeViewControllerDelegate {
    public func countryCodeViewController(_ vc: CountryCodeViewController, didSelectCountryCode countryCode: String, countryName: String, callingCode: String) {
        updateCountry(callingCode: callingCode, countryCode: countryCode)
    }

    @objc func didTapCountryRow() {
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
            callingCodeInt = PhoneNumberUtil.sharedThreadLocal().nbPhoneNumberUtil.getCountryCode(
                forRegion: PhoneNumber.defaultCountryCode()
            )?.intValue
        }

        var callingCode: String?
        if let callingCodeInt = callingCodeInt {
            callingCode = COUNTRY_CODE_PREFIX + "\(callingCodeInt)"
            countryCode = PhoneNumberUtil.sharedThreadLocal().probableCountryCode(forCallingCode: callingCode!)
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
        exampleLabel.text = ViewControllerUtils.examplePhoneNumber(forCountryCode: countryCode, callingCode: callingCode)
    }
}

extension FindByPhoneNumberViewController: UITextFieldDelegate {
    public func textField(_ textField: UITextField, shouldChangeCharactersIn range: NSRange, replacementString string: String) -> Bool {
        ViewControllerUtils.phoneNumber(textField, shouldChangeCharactersIn: range, replacementString: string, callingCode: callingCode)
        updateButtonState()
        return false
    }

    public func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        tryToSelectPhoneNumber()
        return false
    }
}
