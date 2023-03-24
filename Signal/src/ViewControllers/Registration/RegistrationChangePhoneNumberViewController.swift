//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import SignalServiceKit

// MARK: - RegistrationChangePhoneNumberPresenter

protocol RegistrationChangePhoneNumberPresenter: AnyObject {

    func submitProspectiveChangeNumberE164(newE164: E164)

    func exitRegistration()
}

// MARK: - RegistrationChangePhoneNumberViewController

class RegistrationChangePhoneNumberViewController: OWSTableViewController2 {

    private var state: RegistrationPhoneNumberViewState.ChangeNumberInitialEntry
    private weak var presenter: RegistrationChangePhoneNumberPresenter?

    private let oldValueViews: ChangePhoneNumberValueViews
    private let newValueViews: ChangePhoneNumberValueViews

    public init(
        state: RegistrationPhoneNumberViewState.ChangeNumberInitialEntry,
        presenter: RegistrationChangePhoneNumberPresenter
    ) {
        self.state = state
        self.presenter = presenter
        if state.hasConfirmed {
            self.oldValueViews = ChangePhoneNumberValueViews(e164: state.oldE164, type: .oldNumber)
            self.newValueViews = ChangePhoneNumberValueViews(e164: state.newE164, type: .newNumber)
        } else {
            self.oldValueViews = ChangePhoneNumberValueViews(e164: nil, type: .oldNumber)
            self.newValueViews = ChangePhoneNumberValueViews(e164: nil, type: .newNumber)
        }

        super.init()

        oldValueViews.delegate = self
        newValueViews.delegate = self
    }

    public func updateState(_ newState: RegistrationPhoneNumberViewState.ChangeNumberInitialEntry) {
        self.state = newState
        updateTableContents()

        if let invalidNumberError = state.invalidNumberError {
            showInvalidPhoneNumberAlertIfNecessary(for: invalidNumberError.invalidE164.stringValue)
        }
    }

    private var previousInvalidE164: String?

    private func showInvalidPhoneNumberAlertIfNecessary(for e164: String) {
        let shouldShowAlert = e164 != previousInvalidE164
        if shouldShowAlert {
            OWSActionSheets.showActionSheet(
                title: OWSLocalizedString(
                    "REGISTRATION_VIEW_INVALID_PHONE_NUMBER_ALERT_TITLE",
                    comment: "Title of alert indicating that users needs to enter a valid phone number to register."
                ),
                message: OWSLocalizedString(
                    "REGISTRATION_VIEW_INVALID_PHONE_NUMBER_ALERT_MESSAGE",
                    comment: "Message of alert indicating that users needs to enter a valid phone number to register."
                )
            )
        }

        previousInvalidE164 = e164
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

    public override func themeDidChange() {
        super.themeDidChange()

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
                                                  comment: "Label for the 'phone number' row in the 'change phone number' settings."),
                          textColor: Theme.primaryTextColor,
                          accessoryView: valueViews.phoneNumberTextField,
                          accessibilityIdentifier: valueViews.accessibilityIdentifier_CountryCode))

        switch valueViews.type {
        case .newNumber:
            if let invalidNumberError = state.invalidNumberError {
                section.add(.init(customCellBlock: {
                    let cell = OWSTableItem.buildCellWithAccessoryLabel(
                        itemName: invalidNumberError.warningLabelText,
                        textColor: .ows_accentRed,
                        accessoryType: .none
                    )
                    cell.isUserInteractionEnabled = false
                    return cell
                }))
            }
        case .oldNumber:
            break
        }

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

    private func tryToParseNewE164() -> E164? {
        func tryToParse(
            _ valueViews: ChangePhoneNumberValueViews,
            isOldValue: Bool
        ) -> E164? {
            switch valueViews.tryToParse() {
            case .noNumber:
                showInvalidPhoneNumberAlert(isOldValue: isOldValue)
                return nil
            case .invalidNumber:
                showInvalidPhoneNumberAlert(isOldValue: isOldValue)
                return nil
            case .validNumber(let e164):

                return e164
            }
        }

        guard let oldE164 = tryToParse(oldValueViews, isOldValue: true) else {
            return nil
        }
        guard let newE164 = tryToParse(newValueViews, isOldValue: false) else {
            return nil
        }

        guard oldE164 == state.oldE164 else {
            showIncorrectOldPhoneNumberAlert()
            return nil
        }

        guard newE164 != state.oldE164 else {
            showIdenticalPhoneNumbersAlert()
            return nil
        }

        guard state.invalidNumberError?.canSubmit(e164: newE164) != false else {
            showInvalidPhoneNumberAlert(isOldValue: false)
            return nil
        }

        return newE164
    }

    private func tryToContinue() {
        AssertIsOnMainThread()

        guard let newE164 = tryToParseNewE164() else {
            return
        }

        oldValueViews.phoneNumberTextField.resignFirstResponder()
        newValueViews.phoneNumberTextField.resignFirstResponder()

        presenter?.submitProspectiveChangeNumberE164(newE164: newE164)
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

        presenter?.exitRegistration()
    }

    @objc
    private func didTapContinue() {
        AssertIsOnMainThread()

        tryToContinue()
    }
}

// MARK: -

extension RegistrationChangePhoneNumberViewController: ChangePhoneNumberValueViewsDelegate {
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

    var phoneNumber: RegistrationPhoneNumber

    enum `Type` {
        case oldNumber
        case newNumber
    }

    fileprivate let type: `Type`

    public init(e164: E164?, type: `Type`) {
        if let e164, let number = RegistrationPhoneNumber(e164: e164) {
            self.phoneNumber = number
        } else {
            self.phoneNumber = RegistrationPhoneNumber(countryState: .defaultValue, nationalNumber: "")
        }
        self.type = type

        super.init()

        phoneNumberTextField.accessibilityIdentifier = self.accessibilityIdentifier_PhoneNumberTextfield
        phoneNumberTextField.delegate = self
        phoneNumberTextField.addTarget(self, action: #selector(textFieldDidChange), for: .editingChanged)
        phoneNumberTextField.addTarget(self, action: #selector(textFieldDidChange), for: .editingDidBegin)
        phoneNumberTextField.addTarget(self, action: #selector(textFieldDidChange), for: .editingDidEnd)

        phoneNumberString = phoneNumber.nationalNumber
    }

    var countryState: RegistrationCountryState {
        get {
            return phoneNumber.countryState
        }
        set {
            phoneNumber = RegistrationPhoneNumber(countryState: newValue, nationalNumber: phoneNumber.nationalNumber)
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
        switch type {
        case .oldNumber:
            return NSLocalizedString("SETTINGS_CHANGE_PHONE_NUMBER_OLD_PHONE_NUMBER_SECTION_TITLE",
                                     comment: "Title for the 'old phone number' section in the 'change phone number' settings.")
        case .newNumber:
            return NSLocalizedString("SETTINGS_CHANGE_PHONE_NUMBER_NEW_PHONE_NUMBER_SECTION_TITLE",
                                     comment: "Title for the 'new phone number' section in the 'change phone number' settings.")
        }
    }

    var accessibilityIdentifierPrefix: String {
        switch type {
        case .oldNumber:
            return "old"
        case .newNumber:
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
        case validNumber(e164: E164)
    }

    func tryToParse() -> ParsedValue {
        guard let phoneNumberWithoutCallingCode = phoneNumberString?.strippedOrNil else {
            return .noNumber
        }

        guard
            let phoneNumber = PhoneNumber.tryParsePhoneNumber(
                fromUserSpecifiedText: phoneNumberWithoutCallingCode,
                callingCode: callingCode
            ),
            let e164String = phoneNumber.toE164().strippedOrNil,
            let e164 = E164(e164String),
            PhoneNumberValidator().isValidForRegistration(phoneNumber: phoneNumber)
        else {
            return .invalidNumber
        }

        return .validNumber(e164: e164)
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
