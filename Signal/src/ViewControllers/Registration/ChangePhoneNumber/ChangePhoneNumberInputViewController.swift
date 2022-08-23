//
//  Copyright (c) 2022 Open Whisper Systems. All rights reserved.
//

import Foundation
import SignalServiceKit

class ChangePhoneNumberInputViewController: OWSTableViewController2 {

    private let changePhoneNumberController: ChangePhoneNumberController
    private let oldValueViews: ChangePhoneNumberValueViews
    private let newValueViews: ChangePhoneNumberValueViews

    public init(changePhoneNumberController: ChangePhoneNumberController) {
        self.changePhoneNumberController = changePhoneNumberController

        self.oldValueViews = ChangePhoneNumberValueViews(.oldValue,
                                                         changePhoneNumberController: changePhoneNumberController)
        self.newValueViews = ChangePhoneNumberValueViews(.newValue,
                                                         changePhoneNumberController: changePhoneNumberController)

        super.init()

        oldValueViews.delegate = self
        newValueViews.delegate = self
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        title = NSLocalizedString("SETTINGS_CHANGE_PHONE_NUMBER_VIEW_TITLE",
                                  comment: "Title for the 'change phone number' views in settings.")

        navigationItem.leftBarButtonItem = UIBarButtonItem(
            barButtonSystemItem: .cancel,
            target: self,
            action: #selector(didPressCancel)
        )

        updateTableContents()
    }

    fileprivate func updateNavigationBar() {
        let doneItem = UIBarButtonItem(
            barButtonSystemItem: .done,
            target: self,
            action: #selector(didTapContinue)
        )
        navigationItem.rightBarButtonItem = doneItem
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)

        updateTableContents()
    }

    public override func applyTheme() {
        super.applyTheme()

        updateTableContents()
    }

    func updateTableContents() {
        let contents = OWSTableContents()

        contents.addSection(buildTableSection(valueViews: oldValueViews))
        contents.addSection(buildTableSection(valueViews: newValueViews))

        self.contents = contents

        updateNavigationBar()
    }

    fileprivate func buildTableSection(valueViews: ChangePhoneNumberValueViews) -> OWSTableSection {
        let section = OWSTableSection()
        section.headerTitle = valueViews.sectionHeaderTitle

        let countryCodeFormat = NSLocalizedString("SETTINGS_CHANGE_PHONE_NUMBER_COUNTRY_CODE_FORMAT",
                                                  comment: "Format for the 'country code' in the 'change phone number' settings. Embeds: {{ %1$@ the numeric country code prefix, %2$@ the country code abbreviation }}.")
        let countryCodeFormatted = String(format: countryCodeFormat, valueViews.callingCode, valueViews.countryCode)
        section.add(.item(name: NSLocalizedString("SETTINGS_CHANGE_PHONE_NUMBER_COUNTRY_CODE_FIELD",
                                                  comment: "Label for the 'country code' row in the 'change phone number' settings."),
                          textColor: Theme.primaryTextColor,
                          accessoryText: countryCodeFormatted,
                          accessoryType: .disclosureIndicator,
                          accessibilityIdentifier: valueViews.accessibilityIdentifier_PhoneNumber) { [weak self] in
            self?.showCountryCodePicker(valueViews: valueViews)
        })
        section.add(.item(name: NSLocalizedString("SETTINGS_CHANGE_PHONE_NUMBER_PHONE_NUMBER_FIELD",
                                                  comment: "Label for the 'country code' row in the 'change phone number' settings."),
                          textColor: Theme.primaryTextColor,
                          accessoryView: valueViews.phoneNumberTextField,
                          accessibilityIdentifier: valueViews.accessibilityIdentifier_CountryCode))

        // The purpose of the example phone number is to indicate to the user that they should enter
        // their phone number _without_ a country calling code (e.g. +1 or +44) but _with_ area code, etc.
        func tryToFormatPhoneNumber(_ phoneNumber: String) -> String? {
            guard let formatted = PhoneNumber.bestEffortFormatPartialUserSpecifiedText(toLookLikeAPhoneNumber: phoneNumber,
                                                                                       withSpecifiedCountryCodeString: valueViews.countryCode).nilIfEmpty else {
                owsFailDebug("Invalid phone number. phoneNumber: \(phoneNumber), callingCode: \(valueViews.callingCode).")
                return nil
            }
            // Remove the "country calling code".
            guard formatted.hasPrefix(valueViews.callingCode) else {
                owsFailDebug("Example phone number missing calling code. phoneNumber: \(phoneNumber), callingCode: \(valueViews.callingCode).")
                return nil
            }
            guard let formattedWithoutCallingCode = formatted.substring(from: valueViews.callingCode.count).nilIfEmpty else {
                owsFailDebug("Invalid phone number. phoneNumber: \(phoneNumber), callingCode: \(valueViews.callingCode).")
                return nil
            }
            return formattedWithoutCallingCode
        }
        if let examplePhoneNumber = phoneNumberUtil.examplePhoneNumber(forCountryCode: valueViews.countryCode),
           let formattedPhoneNumber = tryToFormatPhoneNumber(examplePhoneNumber) {
            let exampleFormat = NSLocalizedString("SETTINGS_CHANGE_PHONE_NUMBER_EXAMPLE_PHONE_NUMBER_FORMAT",
                                                      comment: "Format for 'example phone numbers' in the 'change phone number' settings. Embeds: {{ the example phone number }}")
            section.footerTitle = String(format: exampleFormat, formattedPhoneNumber)
        }

        return section
    }

    fileprivate func showCountryCodePicker(valueViews: ChangePhoneNumberValueViews) {
        let countryCodeController = CountryCodeViewController()
        countryCodeController.countryCodeDelegate = valueViews
        countryCodeController.interfaceOrientationMask = UIDevice.current.isIPad ? .all : .portrait
        let navigationController = OWSNavigationController(rootViewController: countryCodeController)
        self.present(navigationController, animated: true, completion: nil)
    }

    // MARK: -

    private struct PhoneNumbers {
        let oldPhoneNumber: PhoneNumber
        let newPhoneNumber: PhoneNumber
    }

    private func tryToParse() -> PhoneNumbers? {
        func tryToParse(_ valueViews: ChangePhoneNumberValueViews,
                        isOldValue: Bool) -> PhoneNumber? {
            switch valueViews.tryToParse() {
            case .noNumber:
                showInvalidPhoneNumberAlert(isOldValue: isOldValue)
                return nil
            case .invalidNumber:
                showInvalidPhoneNumberAlert(isOldValue: isOldValue)
                return nil
            case .validNumber(let phoneNumber):
                return phoneNumber
            }
        }

        guard let oldPhoneNumber = tryToParse(oldValueViews, isOldValue: true) else {
            return nil
        }
        guard let newPhoneNumber = tryToParse(newValueViews, isOldValue: false) else {
            return nil
        }

        guard oldPhoneNumber.toE164() == tsAccountManager.localNumber else {
            showIncorrectOldPhoneNumberAlert()
            return nil
        }

        guard oldPhoneNumber.toE164() != newPhoneNumber.toE164() else {
            showIdenticalPhoneNumbersAlert()
            return nil
        }

        Logger.verbose("oldPhoneNumber: \(oldPhoneNumber.toE164())")
        Logger.verbose("newPhoneNumber: \(newPhoneNumber.toE164())")

        return PhoneNumbers(oldPhoneNumber: oldPhoneNumber, newPhoneNumber: newPhoneNumber)
    }

    private func tryToContinue() {
        AssertIsOnMainThread()

        guard let phoneNumbers = tryToParse() else {
            return
        }

        oldValueViews.phoneNumberTextField.resignFirstResponder()
        newValueViews.phoneNumberTextField.resignFirstResponder()

        let vc = ChangePhoneNumberConfirmViewController(changePhoneNumberController: changePhoneNumberController,
                                                        oldPhoneNumber: phoneNumbers.oldPhoneNumber,
                                                        newPhoneNumber: phoneNumbers.newPhoneNumber)
        self.navigationController?.pushViewController(vc, animated: true)
    }

    private func showInvalidPhoneNumberAlert(isOldValue: Bool) {
        let message = (isOldValue
                       ? NSLocalizedString(
                        "CHANGE_PHONE_NUMBER_INVALID_PHONE_NUMBER_ALERT_MESSAGE_OLD",
                        comment: "Error indicating that the user's old phone number is not valid.")
                       : NSLocalizedString(
                        "CHANGE_PHONE_NUMBER_INVALID_PHONE_NUMBER_ALERT_MESSAGE_NEW",
                        comment: "Error indicating that the user's new phone number is not valid."))
        OWSActionSheets.showActionSheet(title: nil, message: message)
    }

    private func showIncorrectOldPhoneNumberAlert() {
        let message = NSLocalizedString(
                        "CHANGE_PHONE_NUMBER_INCORRECT_OLD_PHONE_NUMBER_ALERT_MESSAGE",
                        comment: "Error indicating that the user's old phone number was not entered correctly.")
        OWSActionSheets.showActionSheet(title: nil, message: message)
    }

    private func showIdenticalPhoneNumbersAlert() {
        let message = NSLocalizedString(
                        "CHANGE_PHONE_NUMBER_IDENTICAL_PHONE_NUMBERS_ALERT_MESSAGE",
                        comment: "Error indicating that the user's old and new phone numbers are identical.")
        OWSActionSheets.showActionSheet(title: nil, message: message)
    }

    // MARK: - Events

    @objc
    private func didPressCancel() {
        AssertIsOnMainThread()

        changePhoneNumberController.cancelFlow(viewController: self)
    }

    @objc
    private func didTapContinue() {
        AssertIsOnMainThread()

        tryToContinue()
    }
}

// MARK: -

extension ChangePhoneNumberInputViewController: ChangePhoneNumberValueViewsDelegate {
    fileprivate func valueDidChange(valueViews: ChangePhoneNumberValueViews) {
        AssertIsOnMainThread()

        updateNavigationBar()
    }

    fileprivate func valueDidPressEnter(valueViews: ChangePhoneNumberValueViews) {
    }

    fileprivate func valueDidUpdateCountryState(valueViews: ChangePhoneNumberValueViews) {
        updateTableContents()
    }
}

// MARK: -

private protocol ChangePhoneNumberValueViewsDelegate: AnyObject {
    func valueDidChange(valueViews: ChangePhoneNumberValueViews)
    func valueDidPressEnter(valueViews: ChangePhoneNumberValueViews)
    func valueDidUpdateCountryState(valueViews: ChangePhoneNumberValueViews)
}

// MARK: -

private class ChangePhoneNumberValueViews: NSObject {

    weak var delegate: ChangePhoneNumberValueViewsDelegate?

    enum Value {
        case oldValue
        case newValue
    }
    let value: Value

    private let changePhoneNumberController: ChangePhoneNumberController

    public init(_ value: Value, changePhoneNumberController: ChangePhoneNumberController) {
        self.value = value
        self.changePhoneNumberController = changePhoneNumberController

        super.init()

        phoneNumberTextField.accessibilityIdentifier = self.accessibilityIdentifier_PhoneNumberTextfield
        phoneNumberTextField.delegate = self
        phoneNumberTextField.addTarget(self, action: #selector(textFieldDidChange), for: .editingChanged)
        phoneNumberTextField.addTarget(self, action: #selector(textFieldDidChange), for: .editingDidBegin)
        phoneNumberTextField.addTarget(self, action: #selector(textFieldDidChange), for: .editingDidEnd)

        phoneNumberString = phoneNumber?.withoutCountryCallingCode
    }

    var countryState: RegistrationCountryState {
        get {
            switch value {
            case .oldValue:
                return changePhoneNumberController.oldCountryState
            case .newValue:
                return changePhoneNumberController.newCountryState
            }
        }
        set {
            switch value {
            case .oldValue:
                changePhoneNumberController.oldCountryState = newValue
            case .newValue:
                changePhoneNumberController.newCountryState = newValue
            }
        }
    }

    var phoneNumber: RegistrationPhoneNumber? {
        get {
            switch value {
            case .oldValue:
                return changePhoneNumberController.oldPhoneNumber
            case .newValue:
                return changePhoneNumberController.newPhoneNumber
            }
        }
        set {
            switch value {
            case .oldValue:
                changePhoneNumberController.oldPhoneNumber = newValue
            case .newValue:
                changePhoneNumberController.newPhoneNumber = newValue
            }
        }
    }

    var countryName: String { countryState.countryName }
    var callingCode: String { countryState.callingCode }
    var countryCode: String { countryState.countryCode }

    private enum InlineError {
        case invalidNumber
        case rateLimit(expiration: Date)
    }

    private var phoneNumberError: InlineError?

    var phoneNumberString: String? {
        get { phoneNumberTextField.text }
        set {
            phoneNumberTextField.text = newValue
            applyPhoneNumberFormatting()
        }
    }

    let phoneNumberTextField: UITextField = {
        let field = UITextField()
        field.font = UIFont.ows_dynamicTypeBodyClamped
        field.textColor = Theme.primaryTextColor
        field.textAlignment = (CurrentAppContext().isRTL
                               ? .left
                               : .right)
        field.textContentType = .telephoneNumber

        // There's a bug in iOS 13 where predictions aren't provided for .numberPad
        // keyboard types. Leaving as number pad for now, but if we want to support
        // autofill at the expense of a less appropriate keyboard, here's where it'd
        // be done. See Wisors comment here:
        // https://developer.apple.com/forums/thread/120703
        if #available(iOS 14, *) {
            field.keyboardType = .numberPad
        } else if #available(iOS 13, *) {
            field.keyboardType = .numberPad // .numbersAndPunctuation
        } else {
            field.keyboardType = .numberPad
        }

        field.placeholder = NSLocalizedString(
            "ONBOARDING_PHONE_NUMBER_PLACEHOLDER",
            comment: "Placeholder string for phone number field during registration")

        return field
    }()

    private func applyPhoneNumberFormatting() {
        AssertIsOnMainThread()
        ViewControllerUtils.reformatPhoneNumber(phoneNumberTextField, callingCode: callingCode)
    }

    var sectionHeaderTitle: String {
        switch value {
        case .oldValue:
            return NSLocalizedString("SETTINGS_CHANGE_PHONE_NUMBER_OLD_PHONE_NUMBER_SECTION_TITLE",
                                     comment: "Title for the 'old phone number' section in the 'change phone number' settings.")
        case .newValue:
            return NSLocalizedString("SETTINGS_CHANGE_PHONE_NUMBER_NEW_PHONE_NUMBER_SECTION_TITLE",
                                     comment: "Title for the 'new phone number' section in the 'change phone number' settings.")
        }
    }

    var accessibilityIdentifierPrefix: String {
        switch value {
        case .oldValue:
            return "old"
        case .newValue:
            return "new"
        }
    }

    var accessibilityIdentifier_PhoneNumberTextfield: String {
        accessibilityIdentifierPrefix + "_phone_number_textfield"
    }

    var accessibilityIdentifier_PhoneNumber: String {
        accessibilityIdentifierPrefix + "_phone_number"
    }

    var accessibilityIdentifier_CountryCode: String {
        accessibilityIdentifierPrefix + "_country_code"
    }

    enum ParsedValue {
        case noNumber
        case invalidNumber
        case validNumber(phoneNumber: PhoneNumber)
    }

    func tryToParse() -> ParsedValue {
        guard let phoneNumberWithoutCallingCode = phoneNumberString?.strippedOrNil else {
            self.phoneNumber = nil
            return .noNumber
        }

        guard let phoneNumber = PhoneNumber.tryParsePhoneNumber(fromUserSpecifiedText: phoneNumberWithoutCallingCode,
                                                                callingCode: callingCode),
              let e164 = phoneNumber.toE164().strippedOrNil,
              PhoneNumberValidator().isValidForRegistration(phoneNumber: phoneNumber) else {
                  self.phoneNumber = nil
                  return .invalidNumber
              }

        self.phoneNumber = RegistrationPhoneNumber(e164: e164, userInput: phoneNumberWithoutCallingCode)
        return .validNumber(phoneNumber: phoneNumber)
    }
}

// MARK: -

extension ChangePhoneNumberValueViews: UITextFieldDelegate {
    public func textField(
        _ textField: UITextField,
        shouldChangeCharactersIn range: NSRange,
        replacementString string: String) -> Bool {

            if case .invalidNumber = phoneNumberError {
                phoneNumberError = nil
            }

            // If ViewControllerUtils applied the edit on our behalf, inform UIKit
            // so the edit isn't applied twice.
            let result = ViewControllerUtils.phoneNumber(
                textField,
                shouldChangeCharactersIn: range,
                replacementString: string,
                callingCode: callingCode)

            textFieldDidChange(textField)

            return result
        }

    @objc
    private func textFieldDidChange(_ textField: UITextField) {
        applyPhoneNumberFormatting()
        delegate?.valueDidChange(valueViews: self)
    }

    public func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        delegate?.valueDidPressEnter(valueViews: self)
        return false
    }
}

// MARK: -

extension ChangePhoneNumberValueViews: CountryCodeViewControllerDelegate {
    public func countryCodeViewController(_ vc: CountryCodeViewController,
                                          didSelectCountry countryState: RegistrationCountryState) {
        self.countryState = countryState
        delegate?.valueDidUpdateCountryState(valueViews: self)
    }
}

// MARK: -

extension RegistrationPhoneNumber {

    var withoutCountryCallingCode: String? {
        guard let countryState = RegistrationCountryState.countryState(forE164: e164) else {
            owsFailDebug("Missing countryState.")
            return nil
        }
        let prefix = countryState.callingCode
        guard e164.hasPrefix(prefix) else {
            owsFailDebug("Unexpected callingCode: \(prefix) for e164: \(e164).")
            return nil
        }
        guard let result = String(e164.dropFirst(prefix.count)).strippedOrNil else {
            owsFailDebug("Could not remove callingCode: \(prefix) from e164: \(e164).")
            return nil
        }
        return result
    }
}
