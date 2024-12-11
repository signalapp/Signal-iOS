//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import SignalServiceKit
import SignalUI

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

        if let invalidNumberError = state.invalidE164Error {
            showInvalidPhoneNumberAlertIfNecessary(for: invalidNumberError)
        }
    }

    private var previousInvalidNumber: RegistrationPhoneNumberViewState.ValidationError.InvalidE164?

    private func showInvalidPhoneNumberAlertIfNecessary(for invalidNumber: RegistrationPhoneNumberViewState.ValidationError.InvalidE164) {
        let shouldShowAlert = invalidNumber != previousInvalidNumber
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

        previousInvalidNumber = invalidNumber
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        title = OWSLocalizedString(
            "SETTINGS_CHANGE_PHONE_NUMBER_VIEW_TITLE",
            comment: "Title for the 'change phone number' views in settings."
        )

        navigationItem.leftBarButtonItem = .cancelButton { [weak self] in
            self?.presenter?.exitRegistration()
        }

        updateTableContents()
    }

    fileprivate func updateNavigationBar() {
        navigationItem.rightBarButtonItem = .doneButton { [weak self] in
            self?.tryToContinue()
        }
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

        contents.add(buildTableSection(valueViews: oldValueViews))
        contents.add(buildTableSection(valueViews: newValueViews))

        self.contents = contents

        updateNavigationBar()
    }

    fileprivate func buildTableSection(valueViews: ChangePhoneNumberValueViews) -> OWSTableSection {
        let section = OWSTableSection()
        section.headerTitle = valueViews.sectionHeaderTitle

        let countryCodeFormat = OWSLocalizedString(
            "SETTINGS_CHANGE_PHONE_NUMBER_COUNTRY_CODE_FORMAT",
            comment: "Format for the 'country code' in the 'change phone number' settings. Embeds: {{ %1$@ the numeric country code prefix, %2$@ the country code abbreviation }}."
        )
        let countryCodeFormatted = String(format: countryCodeFormat, valueViews.plusPrefixedCallingCode, valueViews.countryCode)
        section.add(.item(
            name: OWSLocalizedString("SETTINGS_CHANGE_PHONE_NUMBER_COUNTRY_CODE_FIELD", comment: "Label for the 'country code' row in the 'change phone number' settings."),
            textColor: Theme.primaryTextColor,
            accessoryText: countryCodeFormatted,
            accessoryType: .disclosureIndicator,
            actionBlock: { [weak self] in self?.showCountryCodePicker(valueViews: valueViews) }
        ))
        section.add(.item(
            name: OWSLocalizedString("SETTINGS_CHANGE_PHONE_NUMBER_PHONE_NUMBER_FIELD", comment: "Label for the 'phone number' row in the 'change phone number' settings."),
            textColor: Theme.primaryTextColor,
            accessoryContentView: valueViews.nationalNumberTextField
        ))

        switch valueViews.type {
        case .newNumber:
            if
                let e164 = self.state.newE164,
                let invalidE164Error = state.invalidE164Error,
                !invalidE164Error.canSubmit(e164: e164)
            {
                section.add(.init(customCellBlock: {
                    let cell = OWSTableItem.buildCell(
                        itemName: invalidE164Error.warningLabelText(),
                        textColor: .ows_accentRed
                    )
                    cell.isUserInteractionEnabled = false
                    return cell
                }))
            }
        case .oldNumber:
            break
        }

        section.footerTitle = TextFieldFormatting.exampleNationalNumber(
            forCountryCode: valueViews.countryCode,
            includeExampleLabel: true
        )

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

        guard state.invalidE164Error?.canSubmit(e164: newE164) != false else {
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

        oldValueViews.nationalNumberTextField.resignFirstResponder()
        newValueViews.nationalNumberTextField.resignFirstResponder()

        presenter?.submitProspectiveChangeNumberE164(newE164: newE164)
    }

    private func showInvalidPhoneNumberAlert(isOldValue: Bool) {
        let message = (isOldValue
                       ? OWSLocalizedString(
                        "CHANGE_PHONE_NUMBER_INVALID_PHONE_NUMBER_ALERT_MESSAGE_OLD",
                        comment: "Error indicating that the user's old phone number is not valid.")
                       : OWSLocalizedString(
                        "CHANGE_PHONE_NUMBER_INVALID_PHONE_NUMBER_ALERT_MESSAGE_NEW",
                        comment: "Error indicating that the user's new phone number is not valid."))
        OWSActionSheets.showActionSheet(title: nil, message: message)
    }

    private func showIncorrectOldPhoneNumberAlert() {
        let message = OWSLocalizedString(
                        "CHANGE_PHONE_NUMBER_INCORRECT_OLD_PHONE_NUMBER_ALERT_MESSAGE",
                        comment: "Error indicating that the user's old phone number was not entered correctly.")
        OWSActionSheets.showActionSheet(title: nil, message: message)
    }

    private func showIdenticalPhoneNumbersAlert() {
        let message = OWSLocalizedString(
                        "CHANGE_PHONE_NUMBER_IDENTICAL_PHONE_NUMBERS_ALERT_MESSAGE",
                        comment: "Error indicating that the user's old and new phone numbers are identical.")
        OWSActionSheets.showActionSheet(title: nil, message: message)
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

    enum `Type` {
        case oldNumber
        case newNumber
    }

    fileprivate let type: `Type`

    public init(e164: E164?, type: `Type`) {
        let phoneNumber = e164.flatMap({ RegistrationPhoneNumberParser(phoneNumberUtil: SSKEnvironment.shared.phoneNumberUtilRef).parseE164($0) })
        self.country = phoneNumber?.country ?? .defaultValue
        self.type = type

        super.init()

        nationalNumberTextField.delegate = self
        nationalNumberTextField.addTarget(self, action: #selector(textFieldDidChange), for: .editingChanged)
        nationalNumberTextField.addTarget(self, action: #selector(textFieldDidChange), for: .editingDidBegin)
        nationalNumberTextField.addTarget(self, action: #selector(textFieldDidChange), for: .editingDidEnd)

        nationalNumber = phoneNumber?.nationalNumber ?? ""
    }

    var country: PhoneNumberCountry
    var plusPrefixedCallingCode: String { country.plusPrefixedCallingCode }
    var countryCode: String { country.countryCode }

    private enum InlineError {
        case invalidNumber
        case rateLimit(expiration: Date)
    }

    private var phoneNumberError: InlineError?

    var nationalNumber: String? {
        get { nationalNumberTextField.text }
        set {
            nationalNumberTextField.text = newValue
            applyPhoneNumberFormatting()
        }
    }

    fileprivate let nationalNumberTextField: UITextField = {
        let field = UITextField()
        field.font = UIFont.dynamicTypeBodyClamped
        field.textColor = Theme.primaryTextColor
        field.textAlignment = (CurrentAppContext().isRTL ? .left : .right)
        field.textContentType = .telephoneNumber

        // There's a bug in iOS 13 where predictions aren't provided for .numberPad
        // keyboard types. Leaving as number pad for now, but if we want to support
        // autofill at the expense of a less appropriate keyboard, here's where it'd
        // be done. See Wisors comment here:
        // https://developer.apple.com/forums/thread/120703
        field.keyboardType = .numberPad

        field.placeholder = OWSLocalizedString(
            "ONBOARDING_PHONE_NUMBER_PLACEHOLDER",
            comment: "Placeholder string for phone number field during registration")

        return field
    }()

    private func applyPhoneNumberFormatting() {
        AssertIsOnMainThread()
        TextFieldFormatting.reformatPhoneNumberTextField(nationalNumberTextField, plusPrefixedCallingCode: plusPrefixedCallingCode)
    }

    var sectionHeaderTitle: String {
        switch type {
        case .oldNumber:
            return OWSLocalizedString("SETTINGS_CHANGE_PHONE_NUMBER_OLD_PHONE_NUMBER_SECTION_TITLE",
                                     comment: "Title for the 'old phone number' section in the 'change phone number' settings.")
        case .newNumber:
            return OWSLocalizedString("SETTINGS_CHANGE_PHONE_NUMBER_NEW_PHONE_NUMBER_SECTION_TITLE",
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

    enum ParsedValue {
        case noNumber
        case invalidNumber
        case validNumber(e164: E164)
    }

    func tryToParse() -> ParsedValue {
        guard var nationalNumber = nationalNumber?.strippedOrNil else {
            return .noNumber
        }

        nationalNumber = nationalNumber.asciiDigitsOnly

        let phoneNumberUtil = SSKEnvironment.shared.phoneNumberUtilRef
        guard
            let phoneNumber = E164(phoneNumberUtil.parsePhoneNumber(countryCode: country.countryCode, nationalNumber: nationalNumber)?.e164),
            PhoneNumberValidator().isValidForRegistration(phoneNumber: phoneNumber)
        else {
            return .invalidNumber
        }

        return .validNumber(e164: phoneNumber)
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
            let result = TextFieldFormatting.phoneNumberTextField(
                textField,
                shouldChangeCharactersIn: range,
                replacementString: string,
                plusPrefixedCallingCode: plusPrefixedCallingCode
            )

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
    public func countryCodeViewController(_ vc: CountryCodeViewController, didSelectCountry country: PhoneNumberCountry) {
        self.country = country
        delegate?.valueDidUpdateCountryState(valueViews: self)
    }
}
