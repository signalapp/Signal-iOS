//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import SignalServiceKit
import SignalUI

protocol RegistrationPhoneNumberInputViewDelegate: AnyObject {
    func present(_ countryCodeViewController: CountryCodeViewController)
    func didChange()
    func didPressReturn()
}

final class RegistrationPhoneNumberInputView: UIStackView {
    public weak var delegate: RegistrationPhoneNumberInputViewDelegate?

    // We impose a limit on the number of digits. This is much higher than what a valid E164 allows
    // and is just here for safety.
    private let maxNationalNumberDigits = 50

    init(initialPhoneNumber: RegistrationPhoneNumber) {
        self.country = initialPhoneNumber.country

        super.init(frame: .zero)

        axis = .horizontal
        distribution = .fillProportionally
        spacing = 16
        layoutMargins = .init(hMargin: 16, vMargin: 14)
        isLayoutMarginsRelativeArrangement = true
        autoSetDimension(.height, toSize: 50, relation: .greaterThanOrEqual)

        insertSubview(backgroundView, at: 0)
        backgroundView.autoPinEdgesToSuperviewEdges()

        addArrangedSubview(countryCodeView)

        addArrangedSubview(dividerView)

        nationalNumberView.text = formatNationalNumber(input: initialPhoneNumber.nationalNumber)
        addArrangedSubview(nationalNumberView)

        render()
    }

    @available(*, unavailable, message: "use other constructor")
    required init(coder: NSCoder) {
        owsFail("init(coder:) has not been implemented")
    }

    // MARK: - Data

    public private(set) var country: PhoneNumberCountry {
        didSet { render() }
    }

    public var nationalNumber: String { nationalNumberView.text?.asciiDigitsOnly ?? "" }

    public var phoneNumber: RegistrationPhoneNumber {
        return RegistrationPhoneNumber(country: country, nationalNumber: nationalNumber)
    }

    public var isEnabled: Bool = true {
        didSet {
            if !isEnabled {
                nationalNumberView.resignFirstResponder()
            }
            render()
        }
    }

    // MARK: - Rendering

    private let backgroundView: UIView = {
        let result = UIView()
        result.layer.cornerRadius = 10
        return result
    }()

    private lazy var countryCodeLabel: UILabel = {
        let result = UILabel()
        result.font = .dynamicTypeBody
        result.textAlignment = .center
        result.setCompressionResistanceHigh()
        result.setContentHuggingHorizontalHigh()
        return result
    }()

    private lazy var countryCodeChevron: UIImageView = {
        let result = UIImageView(image: UIImage(imageLiteralResourceName: "chevron-down-extra-small"))
        result.autoSetDimensions(to: .square(12))
        result.setCompressionResistanceHigh()
        return result
    }()

    private lazy var countryCodeView: UIView = {
        let result = UIStackView(arrangedSubviews: [countryCodeLabel, countryCodeChevron])
        result.distribution = .fill
        result.alignment = .center
        result.spacing = 9
        result.setCompressionResistanceHigh()
        result.setContentHuggingHorizontalHigh()
        result.accessibilityIdentifier = "registration.phonenumber.countryCode"

        result.isUserInteractionEnabled = true
        result.addGestureRecognizer(UITapGestureRecognizer(
            target: self,
            action: #selector(didTapCountryCode)
        ))

        return result
    }()

    private let dividerView: UIView = {
        let result = UIView()
        result.autoSetDimension(.width, toSize: .hairlineWidth)
        result.setContentHuggingHorizontalHigh()
        return result
    }()

    private lazy var nationalNumberView: UITextField = {
        let result = UITextField()
        result.font = UIFont.dynamicTypeBodyClamped
        result.textAlignment = .left
        result.textContentType = .telephoneNumber
        result.keyboardType = .phonePad
        result.placeholder = OWSLocalizedString(
            "ONBOARDING_PHONE_NUMBER_PLACEHOLDER",
            comment: "Placeholder string for phone number field during registration"
        )

        result.delegate = self

        result.addTarget(delegate, action: #selector(didChange), for: .valueChanged)

        return result
    }()

    public func render() {
        backgroundView.backgroundColor = Theme.secondaryBackgroundColor

        countryCodeLabel.textColor = Theme.primaryTextColor
        countryCodeChevron.tintColor = Theme.primaryIconColor
        dividerView.backgroundColor = Theme.primaryIconColor
        nationalNumberView.textColor = Theme.primaryTextColor

        countryCodeLabel.text = country.plusPrefixedCallingCode
        nationalNumberView.isEnabled = isEnabled
    }

    // MARK: - Events

    @objc
    private func didTapCountryCode(sender: UIGestureRecognizer) {
        guard isEnabled, sender.state == .recognized, let delegate else { return }

        let countryCodeViewController = CountryCodeViewController(delegate: self)
        countryCodeViewController.interfaceOrientationMask = UIDevice.current.isIPad ? .all : .portrait

        delegate.present(countryCodeViewController)
    }

    // MARK: - Responder pass-through

    public override var isFirstResponder: Bool { nationalNumberView.isFirstResponder }

    public override var canBecomeFirstResponder: Bool { nationalNumberView.canBecomeFirstResponder }

    @discardableResult
    public override func becomeFirstResponder() -> Bool { nationalNumberView.becomeFirstResponder() }

    @discardableResult
    public override func resignFirstResponder() -> Bool { nationalNumberView.resignFirstResponder() }
}

// MARK: - UITextFieldDelegate

extension RegistrationPhoneNumberInputView: UITextFieldDelegate {
    func textField(
        _ textField: UITextField,
        shouldChangeCharactersIn range: NSRange,
        replacementString: String
    ) -> Bool {
        let wasEmpty = textField.text.isEmptyOrNil
        var replacementString = replacementString

        if
            textField.text.isEmptyOrNil,
            let fullE164 = E164(replacementString.removeCharacters(characterSet: CharacterSet(charactersIn: " -()"))),
            let phoneNumber = RegistrationPhoneNumberParser(phoneNumberUtil: SSKEnvironment.shared.phoneNumberUtilRef).parseE164(fullE164)
        {
            // If we got a full e164, it was probably from system autofill.
            // Split out the country code portion.
            self.country = phoneNumber.country
            replacementString = phoneNumber.nationalNumber
        }

        let result = FormattedNumberField.textField(
            textField,
            shouldChangeCharactersIn: range,
            replacementString: replacementString,
            allowedCharacters: .numbers,
            maxCharacters: maxNationalNumberDigits,
            format: formatNationalNumber
        )

        if wasEmpty {
            DispatchQueue.main.async {
                // Move the cursor back to the end.
                textField.selectedTextRange = textField.textRange(
                    from: textField.endOfDocument,
                    to: textField.endOfDocument
                )
            }
        }

        return result
    }

    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        delegate?.didPressReturn()
        return false
    }

    private func formatNationalNumber(input: String) -> String {
        return PhoneNumber.bestEffortFormatPartialUserSpecifiedTextToLookLikeAPhoneNumber(input, plusPrefixedCallingCode: country.plusPrefixedCallingCode)
    }
}

// MARK: - CountryCodeViewControllerDelegate

extension RegistrationPhoneNumberInputView: CountryCodeViewControllerDelegate {
    func countryCodeViewController(
        _ vc: CountryCodeViewController,
        didSelectCountry country: PhoneNumberCountry
    ) {
        self.country = country

        nationalNumberView.text = PhoneNumber.bestEffortFormatPartialUserSpecifiedTextToLookLikeAPhoneNumber(nationalNumber, plusPrefixedCallingCode: country.plusPrefixedCallingCode)

        delegate?.didChange()
    }
}
