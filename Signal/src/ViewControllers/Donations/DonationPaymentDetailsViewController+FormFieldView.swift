//
// Copyright 2022 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import SignalUI

// MARK: - Delegate

protocol CreditOrDebitCardDonationFormViewDelegate: AnyObject {
    func didSomethingChange()
}

// MARK: - FormFieldView

extension DonationPaymentDetailsViewController {
    /// A wrapper view for a form field.
    ///
    /// Contains the title (e.g., "Exp. Date"), the text input, and the validation error.
    class FormFieldView: UIView, UITextFieldDelegate {

        // MARK: Supporting types

        enum TitleLayout {
            /// Display the title inline with the text field.
            case inline(width: CGFloat)
            /// Display the title above the text field.
            /// For compact size classes.
            case compact
        }

        enum Style {
            case formatted(
                format: (String) -> String,
                allowedCharacters: FormattedNumberField.AllowedCharacters,
                maxDigits: Int
            )
            case plain(keyboardType: UIKeyboardType)

            var keyboardType: UIKeyboardType {
                switch self {
                case let .formatted(_, allowedCharacters, _):
                    return allowedCharacters.keyboardType
                case let .plain(keyboardType):
                    return keyboardType
                }
            }
        }

        // MARK: Properties

        private let style: Style

        weak var delegate: CreditOrDebitCardDonationFormViewDelegate?

        private lazy var textField: UITextField = {
            let result = OWSTextField()

            result.font = Self.textFieldFont
            result.textColor = Theme.primaryTextColor
            result.autocorrectionType = .no
            result.spellCheckingType = .no
            result.keyboardType = style.keyboardType

            result.delegate = self
            result.addTarget(self, action: #selector(textFieldDidChange), for: .editingChanged)

            return result
        }()

        private lazy var errorLabel: UILabel = {
            let result = UILabel()
            result.font = .dynamicTypeCaption1
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

        @discardableResult
        override func resignFirstResponder() -> Bool { textField.resignFirstResponder() }

        // MARK: Initializers

        init(
            title: String,
            titleLayout: TitleLayout,
            placeholder: String,
            style: Style,
            textContentType: UITextContentType?,
            delegate: CreditOrDebitCardDonationFormViewDelegate?
        ) {
            self.style = style
            self.delegate = delegate

            super.init(frame: .zero)

            let titleView = Self.titleView(title)

            textField.textContentType = textContentType
            self.placeholder = placeholder

            self.render(errorMessage: nil)

            switch titleLayout {
            case .inline(let width):
                let titleContainer = UIView()
                titleContainer.layoutMargins = .init(top: 0, leading: 0, bottom: 0, trailing: Self.titleSpacing)
                titleContainer.addSubview(titleView)
                titleView.autoPinEdgesToSuperviewMargins()

                let textAndErrorVStack = UIStackView(arrangedSubviews: [textField, errorLabel])
                textAndErrorVStack.axis = .vertical

                let titleAndTextFieldHStack = UIStackView(arrangedSubviews: [titleContainer, textAndErrorVStack])
                titleAndTextFieldHStack.axis = .horizontal

                // Keep the title label aligned with the text field
                titleAndTextFieldHStack.alignment = .top
                textField.setCompressionResistanceVerticalHigh()
                textField.autoPinHeight(toHeightOf: titleContainer)

                titleContainer.autoSetDimension(.width, toSize: width + Self.titleSpacing)

                self.addSubview(titleAndTextFieldHStack)
                titleAndTextFieldHStack.autoPinEdgesToSuperviewEdges()
            case .compact:
                let stackView = UIStackView(arrangedSubviews: [titleView, textField, errorLabel])
                stackView.axis = .vertical
                self.addSubview(stackView)
                stackView.autoPinEdgesToSuperviewEdges()
            }
        }

        required init(coder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }

        func render(errorMessage: String?) {
            textField.textColor = Theme.primaryTextColor
            errorLabel.text = errorMessage
        }

        // MARK: Static

        static let textFieldFont = UIFont.dynamicTypeBodyClamped

        static let titleSpacing: CGFloat = 10

        static func titleAttributedString(_ title: String) -> NSAttributedString {
            NSAttributedString(string: title, attributes: [.font: UIFont.dynamicTypeHeadlineClamped])
        }

        private class func titleView(_ title: String) -> UIView {
            let result = UILabel()
            result.numberOfLines = 0
            result.attributedText = titleAttributedString(title)

            return result
        }

        // MARK: - UITextFieldDelegate

        // Not technically part of UITextFieldDelegate, but added as as a
        // target to handle the 'editingChanged' control event.
        @objc
        func textFieldDidChange() {
            delegate?.didSomethingChange()
        }

        func textFieldDidBeginEditing(_ textField: UITextField) {
            delegate?.didSomethingChange()
        }

        func textField(
            _ textField: UITextField,
            shouldChangeCharactersIn range: NSRange,
            replacementString: String
        ) -> Bool {
            defer {
                delegate?.didSomethingChange()
            }

            switch style {
            case let .formatted(format, allowedCharacters, maxDigits):
                return FormattedNumberField.textField(
                    textField,
                    shouldChangeCharactersIn: range,
                    replacementString: replacementString,
                    allowedCharacters: allowedCharacters,
                    maxCharacters: maxDigits,
                    format: format
                )
            case .plain:
                return true
            }
        }

        func textFieldDidEndEditing(_ textField: UITextField) {
            delegate?.didSomethingChange()
        }
    }
}
