//
// Copyright 2022 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

protocol CreditOrDebitCardDonationFormViewDelegate: AnyObject {
    func didSomethingChange()
}

extension CreditOrDebitCardDonationViewController {
    /// A wrapper view for a form field.
    ///
    /// Contains the title (e.g., "Exp. Date"), the text input, and the validation error.
    class FormFieldView: UIStackView, UITextFieldDelegate {
        private let maxDigits: Int
        private let format: (String) -> String

        weak var delegate: CreditOrDebitCardDonationFormViewDelegate?

        private lazy var textField: UITextField = {
            let result = OWSTextField()

            result.font = .ows_dynamicTypeBodyClamped
            result.textColor = Theme.primaryTextColor
            result.autocorrectionType = .no
            result.spellCheckingType = .no
            result.keyboardType = .asciiCapableNumberPad

            result.delegate = self

            return result
        }()

        private lazy var textFieldWrapper: UIView = {
            // NOTE(evanhahn) This probably doesn't need to be a stack view, but
            // I couldn't figure out how to do this with a vanilla `UIView`.
            let result = UIStackView(arrangedSubviews: [textField])
            result.layer.cornerRadius = 10
            result.backgroundColor = Theme.tableCell2PresentedBackgroundColor
            result.layoutMargins = .init(hMargin: 16, vMargin: 14)
            result.isLayoutMarginsRelativeArrangement = true

            textField.autoPinWidthToSuperviewMargins()

            return result
        }()

        private lazy var errorLabel: UILabel = {
            let result = UILabel()
            result.font = .ows_dynamicTypeBody2
            result.textColor = .ows_accentRed
            result.numberOfLines = 1
            return result
        }()

        var text: String { textField.text ?? "" }

        var placeholder: String? {
            get { textField.placeholder }
            set { textField.placeholder = newValue }
        }

        override var isFirstResponder: Bool { textField.isFirstResponder }

        @discardableResult
        override func becomeFirstResponder() -> Bool { textField.becomeFirstResponder() }

        init(
            title: String,
            placeholder: String,
            maxDigits: Int,
            format: @escaping (String) -> String,
            textContentType: UITextContentType? = nil
        ) {
            self.maxDigits = maxDigits
            self.format = format

            super.init(frame: .zero)

            self.axis = .vertical

            let titleView = Self.titleView(title)

            textFieldWrapper.addGestureRecognizer(.init(target: self, action: #selector(didTap)))
            self.placeholder = placeholder

            self.render(errorMessage: nil)

            self.addArrangedSubviews([titleView, textFieldWrapper, errorLabel])

            self.setCustomSpacing(10, after: titleView)
            self.setCustomSpacing(4, after: textFieldWrapper)
        }

        required init(coder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }

        func render(errorMessage: String?) {
            textField.textColor = Theme.primaryTextColor

            textFieldWrapper.backgroundColor = Theme.tableCell2PresentedBackgroundColor

            if let errorMessage {
                errorLabel.text = errorMessage
            } else {
                // This ensures that the label takes up vertical space.
                errorLabel.text = " "
            }
        }

        private class func titleView(_ title: String) -> UIView {
            let result = UILabel()
            result.font = .ows_dynamicTypeBody2.ows_semibold
            result.numberOfLines = 0
            result.text = title

            return result
        }

        @objc
        private func didTap() {
            textField.becomeFirstResponder()
        }

        // MARK: - UITextFieldDelegate

        func textFieldDidBeginEditing(_ textField: UITextField) {
            delegate?.didSomethingChange()
        }

        func textField(
            _ textField: UITextField,
            shouldChangeCharactersIn range: NSRange,
            replacementString: String
        ) -> Bool {
            let result = FormattedNumberField.textField(
                textField,
                shouldChangeCharactersIn: range,
                replacementString: replacementString,
                maxDigits: maxDigits,
                format: format
            )

            delegate?.didSomethingChange()

            return result
        }

        func textFieldDidEndEditing(_ textField: UITextField) {
            delegate?.didSomethingChange()
        }
    }
}
