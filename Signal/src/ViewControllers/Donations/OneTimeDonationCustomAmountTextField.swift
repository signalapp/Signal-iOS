//
// Copyright 2022 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import SignalMessaging

protocol OneTimeDonationCustomAmountTextFieldDelegate: AnyObject {
    func oneTimeDonationCustomAmountTextFieldStateDidChange(_ textField: OneTimeDonationCustomAmountTextField)
}

class OneTimeDonationCustomAmountTextField: UIView {
    private let placeholderLabel = UILabel()
    private let symbolLabel = UILabel()
    private let textField = UITextField()
    private let stackView = UIStackView()

    weak var delegate: OneTimeDonationCustomAmountTextFieldDelegate?

    @discardableResult
    override func becomeFirstResponder() -> Bool { textField.becomeFirstResponder() }

    @discardableResult
    override func resignFirstResponder() -> Bool { textField.resignFirstResponder() }

    override var canBecomeFirstResponder: Bool { textField.canBecomeFirstResponder }
    override var canResignFirstResponder: Bool { textField.canResignFirstResponder }
    override var isFirstResponder: Bool { textField.isFirstResponder }

    init() {
        super.init(frame: .zero)
        textField.autocorrectionType = .no
        textField.spellCheckingType = .no
        textField.keyboardType = .decimalPad
        textField.textAlignment = .center
        textField.delegate = self

        symbolLabel.textAlignment = .center
        placeholderLabel.textAlignment = .center

        stackView.axis = .horizontal

        stackView.addArrangedSubview(placeholderLabel)
        stackView.addArrangedSubview(textField)

        addSubview(stackView)
        stackView.autoPinHeightToSuperview()
        stackView.autoMatch(.width, to: .width, of: self, withMultiplier: 1, relation: .lessThanOrEqual)
        stackView.autoHCenterInSuperview()
        stackView.autoSetDimension(.height, toSize: 48, relation: .greaterThanOrEqual)

        updateVisibility()
        setCurrencyCode(currencyCode)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    var text: String? {
        get { textField.text }
        set {
            textField.text = newValue
            updateVisibility()
        }
    }

    var decimalNumber: Decimal? {
        guard
            let string = valueString(for: text),
            let result = Decimal(string: string, locale: Locale.current),
            result.isFinite
        else {
            return nil
        }
        return result
    }

    var font: UIFont? {
        get { textField.font }
        set {
            textField.font = newValue
            placeholderLabel.font = newValue
            symbolLabel.font = newValue
        }
    }

    var textColor: UIColor? {
        get { textField.textColor }
        set {
            textField.textColor = newValue
            placeholderLabel.textColor = newValue
            symbolLabel.textColor = newValue
        }
    }

    var placeholder: String? {
        get { placeholderLabel.text }
        set { placeholderLabel.text = newValue }
    }

    private lazy var currencyCode = Stripe.defaultCurrencyCode

    func setCurrencyCode(_ currencyCode: Currency.Code) {
        self.currencyCode = currencyCode

        symbolLabel.removeFromSuperview()

        switch DonationUtilities.Symbol.for(currencyCode: currencyCode) {
        case .before(let symbol):
            symbolLabel.text = symbol
            stackView.insertArrangedSubview(symbolLabel, at: 0)
        case .after(let symbol):
            symbolLabel.text = symbol
            stackView.addArrangedSubview(symbolLabel)
        case .currencyCode:
            symbolLabel.text = currencyCode + " "
            stackView.insertArrangedSubview(symbolLabel, at: 0)
        }
    }

    func updateVisibility() {
        let shouldShowPlaceholder = text.isEmptyOrNil && !isFirstResponder
        placeholderLabel.isHiddenInStackView = !shouldShowPlaceholder
        symbolLabel.isHiddenInStackView = shouldShowPlaceholder
        textField.isHiddenInStackView = shouldShowPlaceholder
    }
}

extension OneTimeDonationCustomAmountTextField: UITextFieldDelegate {
    func textFieldDidBeginEditing(_ textField: UITextField) {
        updateVisibility()
        delegate?.oneTimeDonationCustomAmountTextFieldStateDidChange(self)
    }

    func textFieldDidEndEditing(_ textField: UITextField) {
        updateVisibility()
    }

    func textField(_ textField: UITextField, shouldChangeCharactersIn editingRange: NSRange, replacementString: String) -> Bool {
        let existingString = textField.text ?? ""

        let newString = (existingString as NSString).replacingCharacters(in: editingRange, with: replacementString)
        if let numberString = self.valueString(for: newString) {
            textField.text = numberString
            // Make a best effort to preserve cursor position
            if let newPosition = textField.position(
                from: textField.beginningOfDocument,
                offset: editingRange.location + max(0, numberString.count - existingString.count)
            ) {
                textField.selectedTextRange = textField.textRange(from: newPosition, to: newPosition)
            }
        } else {
            textField.text = ""
        }

        updateVisibility()
        delegate?.oneTimeDonationCustomAmountTextFieldStateDidChange(self)

        return false
    }

    /// Converts an arbitrary string into a string representing a valid value
    /// for the current currency. If no valid value is represented, returns nil
    func valueString(for string: String?) -> String? {
        guard let string = string else { return nil }

        let isZeroDecimalCurrency = Stripe.zeroDecimalCurrencyCodes.contains(currencyCode)
        guard !isZeroDecimalCurrency else { return string.digitsOnly }

        let decimalSeparator = Locale.current.decimalSeparator ?? "."
        let components = string.components(separatedBy: decimalSeparator).compactMap { $0.digitsOnly.nilIfEmpty }

        guard let integralString = components.first else {
            if string.contains(decimalSeparator) {
                return "0" + decimalSeparator
            } else {
                return nil
            }
        }

        if let decimalString = components.dropFirst().joined().nilIfEmpty {
            return integralString + decimalSeparator + decimalString
        } else if string.starts(with: decimalSeparator) {
            return "0" + decimalSeparator + integralString
        } else if string.contains(decimalSeparator) {
            return integralString + decimalSeparator
        } else {
            return integralString
        }
    }
}
