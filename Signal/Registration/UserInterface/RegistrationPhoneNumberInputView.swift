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

class RegistrationPhoneNumberInputView: UIView {
    public weak var delegate: RegistrationPhoneNumberInputViewDelegate?

    // We impose a limit on the number of digits. This is much higher than what a valid E164 allows
    // and is just here for safety.
    private let maxNationalNumberDigits = 50

    init(initialPhoneNumber: RegistrationPhoneNumber) {
        self.country = initialPhoneNumber.country

        super.init(frame: .zero)

        layoutMargins = .init(hMargin: 16, vMargin: 9)

        // Background
        let backgroundView = UIView()
#if compiler(>=6.2)
        if #available(iOS 26, *) {
            backgroundView.cornerConfiguration = .capsule()
        } else {
            backgroundView.layer.cornerRadius = 10
        }
#else
        backgroundView.layer.cornerRadius = 10
#endif
        backgroundView.backgroundColor = .Signal.secondaryBackground
        addSubview(backgroundView)
        backgroundView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            backgroundView.topAnchor.constraint(equalTo: topAnchor),
            backgroundView.leadingAnchor.constraint(equalTo: leadingAnchor),
            backgroundView.bottomAnchor.constraint(equalTo: bottomAnchor),
            backgroundView.trailingAnchor.constraint(equalTo: trailingAnchor),
        ])

        // Content view (horizontal stack).
        let dividerView = UIView()
        dividerView.backgroundColor = .Signal.secondaryLabel

        let stackView = UIStackView(arrangedSubviews: [countryCodeView, dividerView, nationalNumberView])
        stackView.axis = .horizontal
        stackView.alignment = .center
        stackView.distribution = .fill
        stackView.spacing = 16
        addSubview(stackView)
        stackView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            dividerView.widthAnchor.constraint(equalToConstant: .hairlineWidth),
            dividerView.heightAnchor.constraint(equalTo: stackView.heightAnchor),

            stackView.heightAnchor.constraint(greaterThanOrEqualToConstant: 32),
            stackView.topAnchor.constraint(equalTo: layoutMarginsGuide.topAnchor),
            stackView.leadingAnchor.constraint(equalTo: layoutMarginsGuide.leadingAnchor),
            stackView.bottomAnchor.constraint(equalTo: layoutMarginsGuide.bottomAnchor),
            stackView.trailingAnchor.constraint(equalTo: layoutMarginsGuide.trailingAnchor),
        ])

        nationalNumberView.text = formatNationalNumber(input: initialPhoneNumber.nationalNumber)
        update()
    }

    @available(*, unavailable, message: "use other constructor")
    required init(coder: NSCoder) {
        owsFail("init(coder:) has not been implemented")
    }

    // MARK: - Data

    public private(set) var country: PhoneNumberCountry {
        didSet { update() }
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
            update()
        }
    }

    // MARK: - Rendering

    private lazy var countryCodeLabel: UILabel = {
        let result = UILabel()
        result.font = .dynamicTypeBodyClamped
        result.textAlignment = .center
        result.textColor = .Signal.label
        result.setCompressionResistanceHigh()
        result.setContentHuggingHorizontalHigh()
        return result
    }()

    private lazy var countryCodeView: UIView = {
        let container = UIView.container()

        container.addSubview(countryCodeLabel)
        countryCodeLabel.translatesAutoresizingMaskIntoConstraints = false

        var chevronIcon = UIImageView(image: UIImage(imageLiteralResourceName: "chevron-down-extra-small"))
        chevronIcon.tintColor = .Signal.secondaryLabel
        container.addSubview(chevronIcon)
        chevronIcon.translatesAutoresizingMaskIntoConstraints = false

        NSLayoutConstraint.activate([
            countryCodeLabel.topAnchor.constraint(greaterThanOrEqualTo: container.topAnchor),
            countryCodeLabel.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 4),
            countryCodeLabel.centerYAnchor.constraint(equalTo: container.centerYAnchor),

            chevronIcon.widthAnchor.constraint(equalToConstant: 12),
            chevronIcon.heightAnchor.constraint(equalToConstant: 12),
            chevronIcon.leadingAnchor.constraint(equalTo: countryCodeLabel.trailingAnchor, constant: 9),
            chevronIcon.centerYAnchor.constraint(equalTo: container.centerYAnchor),
            chevronIcon.trailingAnchor.constraint(equalTo: container.trailingAnchor),
        ])
        container.isUserInteractionEnabled = true
        container.addGestureRecognizer(UITapGestureRecognizer(
            target: self,
            action: #selector(didTapCountryCode)
        ))

        container.isAccessibilityElement = true
        container.accessibilityTraits = .button
        container.accessibilityIdentifier = "registration.phonenumber.countryCode"
        container.accessibilityLabel = OWSLocalizedString(
            "REGISTRATION_DEFAULT_COUNTRY_NAME",
            comment: "Label for the country code field"
        )

        return container
    }()

    private lazy var nationalNumberView: UITextField = {
        let result = UITextField()
        result.font = .dynamicTypeBodyClamped
        result.textAlignment = .left
        result.textColor = .Signal.label
        result.textContentType = .telephoneNumber
        result.keyboardType = .phonePad
        result.placeholder = OWSLocalizedString(
            "ONBOARDING_PHONE_NUMBER_PLACEHOLDER",
            comment: "Placeholder string for phone number field during registration"
        )
        result.delegate = self
        return result
    }()

    private func update() {
        countryCodeLabel.text = country.plusPrefixedCallingCode
        countryCodeView.accessibilityValue = countryCodeLabel.text
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

        let oldValue = textField.text!

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

        let newValue = textField.text!

        if newValue != oldValue {
            delegate?.didChange()
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
