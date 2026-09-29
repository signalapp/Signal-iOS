//
// Copyright 2026 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Combine
import LibSignalClient
import SignalServiceKit
import SignalUI

class SignalLoginView:
    UIView,
    TextViewWithPlaceholderDelegate,
    UITextFieldDelegate
{
    private enum Constants {
        static let layoutMargins = UIEdgeInsets(hMargin: 16, vMargin: 16)
        static let cornerRadius: CGFloat = 26
        static let rowSpacing: CGFloat = 12
        static let buttonImageSize: CGFloat = 28
        static let lineSpacing: CGFloat = 8
    }

    private var aciTextField: UITextField
    private var aepTextField: UITextField
    private var aepTextView: TextViewWithPlaceholder
    private let stackView: UIStackView
    private var aepToggleButton: UIButton

    /// Invoked after the recovery key row switches between the single-line secure field
    /// and the multi-line text view, which changes this view's height.
    ///
    /// The constraint changes have already been applied; the owner is responsible for
    /// flushing layout, and must do so on a view that encloses everything that moves.
    /// Flushing on this view alone animates its `bounds` while its `position` is set in
    /// a separate, unanimated transaction, so the layer scales about an already-final
    /// center and the top edge swings by half the height delta before snapping back.
    var didToggleRecoveryKeyView: ((_ animated: Bool) -> Void)?

    enum FormValue<T> {
        case valid(T)
        case partial(String)
    }

    private let aciSubject = CurrentValueSubject<FormValue<Aci>, Never>(.partial(""))
    private let aepSubject = CurrentValueSubject<FormValue<SignalServiceKit.AccountEntropyPool>, Never>(.partial(""))

    private(set) lazy var signalLoginValuePublisher: AnyPublisher<(FormValue<Aci>, FormValue<SignalServiceKit.AccountEntropyPool>), Never> = {
        Publishers.CombineLatest(
            aciSubject,
            aepSubject,
        )
        .eraseToAnyPublisher()
    }()

    var currentLoginValues: (FormValue<Aci>, FormValue<SignalServiceKit.AccountEntropyPool>) {
        (aciSubject.value, aepSubject.value)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    init(
        aci: Aci?,
        displayableAEP: DisplayableAccountEntropyPool?,
    ) {
        stackView = UIStackView()
        aciTextField = UITextField()
        aepTextField = UITextField()

        let aepTextView = TextViewWithPlaceholder()
        self.aepTextView = aepTextView

        let button = UIButton()
        aepToggleButton = button

        super.init(frame: .zero)

        layoutMargins = Constants.layoutMargins
        layer.cornerRadius = Constants.cornerRadius
        backgroundColor = UIColor.Signal.tertiaryGroupedBackground

        addSubview(stackView)
        stackView.translatesAutoresizingMaskIntoConstraints = false
        stackView.axis = .vertical
        stackView.distribution = .fill
        stackView.spacing = Constants.rowSpacing
        NSLayoutConstraint.activate([
            stackView.topAnchor.constraint(equalTo: layoutMarginsGuide.topAnchor),
            stackView.bottomAnchor.constraint(equalTo: layoutMarginsGuide.bottomAnchor),
            stackView.trailingAnchor.constraint(equalTo: layoutMarginsGuide.trailingAnchor),
            stackView.leadingAnchor.constraint(equalTo: layoutMarginsGuide.leadingAnchor),
        ])

        // ACI entry field

        aciTextField.translatesAutoresizingMaskIntoConstraints = false
        aciTextField.spellCheckingType = .no
        aciTextField.autocorrectionType = .no
        aciTextField.keyboardType = .asciiCapable
        aciTextField.textColor = .Signal.label

        stackView.addArrangedSubview(aciTextField)
        aciTextField.delegate = self
        aciTextField.text = aci?.serviceIdUppercaseString

        let divider = UIView()
        addSubview(divider)
        divider.translatesAutoresizingMaskIntoConstraints = false
        divider.backgroundColor = UIColor.Signal.opaqueSeparator
        stackView.addArrangedSubview(divider)
        NSLayoutConstraint.activate([
            divider.heightAnchor.constraint(equalToConstant: divider.hairlineWidth),
        ])

        let recoveryKeyRow = UIView()
        recoveryKeyRow.clipsToBounds = true

        let recoveryKeyPlaceholderText = OWSLocalizedString(
            "SIGNAL_LOGIN_RECOVERY_KEY_PLACEHOLDER_TITLE",
            comment: "Placeholder of the 'Recovery Key' password field.",
        )

        aepTextField.translatesAutoresizingMaskIntoConstraints = false
        aepTextField.isSecureTextEntry = true
        aepTextField.spellCheckingType = .no
        aepTextField.autocorrectionType = .no
        aepTextField.keyboardType = .asciiCapable
        aepTextField.placeholder = recoveryKeyPlaceholderText
        recoveryKeyRow.addSubview(aepTextField)
        aepTextField.delegate = self

        // Recovery Key entry field

        configure(textView: aepTextView)
        aepTextView.placeholderText = recoveryKeyPlaceholderText
        recoveryKeyRow.addSubview(aepTextView)
        aepTextView.delegate = self
        aepTextView.text = displayableAEP?.displayString

        aepTextField.font = aepTextView.editorFont
        aepTextField.adjustsFontForContentSizeCategory = true
        aepTextField.text = displayableAEP?.displayString

        // Image Button

        button.translatesAutoresizingMaskIntoConstraints = false
        button.tintColor = .Signal.label
        recoveryKeyRow.addSubview(button)
        button.configurationUpdateHandler = { [weak self] button in
            guard let self else { return }
            var config = UIButton.Configuration.plain()
            config.image = if self.aepTextField.isHidden {
                UIImage(resource: .visible)
            } else {
                UIImage(resource: .visibleSlash)
            }
            button.configuration = config
        }
        button.isHidden = aepTextField.text?.isEmpty == true

        NSLayoutConstraint.activate([
            aepTextField.topAnchor.constraint(equalTo: recoveryKeyRow.topAnchor),
            aepTextField.leadingAnchor.constraint(equalTo: recoveryKeyRow.leadingAnchor),
            aepTextField.trailingAnchor.constraint(equalTo: button.leadingAnchor, constant: -8),
        ])
        let aepPasswordBottomConstraints = [
            aepTextField.bottomAnchor.constraint(equalTo: recoveryKeyRow.bottomAnchor),
        ]

        NSLayoutConstraint.activate([
            aepTextView.topAnchor.constraint(equalTo: recoveryKeyRow.topAnchor),
            aepTextView.leadingAnchor.constraint(equalTo: recoveryKeyRow.leadingAnchor),
            aepTextView.trailingAnchor.constraint(equalTo: button.leadingAnchor, constant: -8),
        ])
        let aepTextViewBottomConstraints = [
            aepTextView.bottomAnchor.constraint(equalTo: recoveryKeyRow.bottomAnchor),
        ]

        NSLayoutConstraint.deactivate(aepTextViewBottomConstraints)
        NSLayoutConstraint.activate(aepPasswordBottomConstraints)

        NSLayoutConstraint.activate([
            recoveryKeyRow.heightAnchor.constraint(greaterThanOrEqualTo: button.heightAnchor),
        ])

        NSLayoutConstraint.activate([
            button.topAnchor.constraint(equalTo: recoveryKeyRow.topAnchor),
            button.trailingAnchor.constraint(equalTo: recoveryKeyRow.trailingAnchor),
            button.heightAnchor.constraint(equalToConstant: Constants.buttonImageSize),
            button.widthAnchor.constraint(equalToConstant: Constants.buttonImageSize),
        ])

        stackView.addArrangedSubview(recoveryKeyRow)

        func setPasswordFieldActive(_ isFieldActive: Bool, animated: Bool) {
            // The visible field is the source of truth; hand its contents (and
            // focus) to the other field only when switching.
            let wasEditing = aepTextField.isFirstResponder || aepTextView.isFirstResponder
            if isFieldActive {
                aepTextField.text = aepTextView.text?.filter { !$0.isWhitespace }
            } else {
                // Setting `text` reformats it into display chunks.
                aepTextView.text = aepTextField.text
            }

            aepTextField.isHidden = !isFieldActive
            aepTextView.isHidden = isFieldActive

            button.setNeedsUpdateConfiguration()

            if isFieldActive {
                NSLayoutConstraint.deactivate(aepTextViewBottomConstraints)
                NSLayoutConstraint.activate(aepPasswordBottomConstraints)
            } else {
                NSLayoutConstraint.deactivate(aepPasswordBottomConstraints)
                NSLayoutConstraint.activate(aepTextViewBottomConstraints)
            }

            if wasEditing {
                if isFieldActive {
                    aepTextField.becomeFirstResponder()
                } else {
                    aepTextView.becomeFirstResponder()
                }
            }

            self.setNeedsLayout()

            if let didToggleRecoveryKeyView = self.didToggleRecoveryKeyView {
                // The owner flushes layout on the right ancestor, animated or not.
                didToggleRecoveryKeyView(animated)
            } else if animated {
                // No owner wired up (e.g. a standalone preview). Fall back to the
                // nearest ancestor, which at least keeps origin and size in one
                // transaction.
                let ancestor = self.superview ?? self
                UIView.animate(withDuration: 0.2) {
                    ancestor.layoutIfNeeded()
                }
            }
        }

        setPasswordFieldActive(true, animated: false)
        button.addAction(
            UIAction { [weak self] _ in
                guard let self else { return }
                setPasswordFieldActive(self.aepTextField.isHidden, animated: true)
            },
            for: .primaryActionTriggered,
        )

        aepSubject.value = displayableAEP.map { .valid($0.rawValue) } ?? .partial("")
        aciSubject.value = aci.map { .valid($0) } ?? .partial("")

        updateFonts()

        // Only block the AEP in screenshots
        ScreenshotBlocking.setBlocksScreenshots(true, of: recoveryKeyRow)
    }

    @discardableResult
    override func becomeFirstResponder() -> Bool {
        let result = aciTextField.becomeFirstResponder()
        let end = aciTextField.endOfDocument
        aciTextField.selectedTextRange = aciTextField.textRange(from: end, to: end)
        return result
    }

    // MARK: - Layout Utils

    private func configure(textView: TextViewWithPlaceholder) {
        textView.translatesAutoresizingMaskIntoConstraints = false
        textView.spellCheckingType = .no
        textView.autocorrectionType = .no
        textView.textContainerInset = .zero
        textView.keyboardType = .asciiCapable
    }

    private func updateFonts() {
        let font = UIFont.monospacedSystemFont(ofSize: 17.0, weight: .regular)

        aepTextView.editorFont = font
        aciTextField.font = font
        aepTextField.font = font

        aepTextView.placeholderFont = UIFont.dynamicTypeSubheadline

        aepTextField.attributedPlaceholder = NSAttributedString(
            string: OWSLocalizedString(
                "SIGNAL_LOGIN_RECOVERY_KEY_PLACEHOLDER_TITLE",
                comment: "Placeholder of the 'Recovery Key' password field.",
            ),
            attributes: [
                .font: UIFont.dynamicTypeSubheadline,
            ],
        )

        aciTextField.attributedPlaceholder = NSAttributedString(
            string: OWSLocalizedString(
                "SIGNAL_LOGIN_ACCOUNT_ID_PLACEHOLDER_TITLE",
                comment: "Placeholder of the 'Account ID' username field.",
            ),
            attributes: [
                .font: UIFont.dynamicTypeSubheadline,
            ],
        )
    }

    // MARK: - TextViewWithPlaceholderDelegate

    func textViewDidUpdateText(_ textView: TextViewWithPlaceholder) {
        guard textView == self.aepTextView else { return }
        AccountEntropyPoolTextView.Utils.textViewDidUpdateText(textView)
    }

    func textView(
        _ textView: TextViewWithPlaceholder,
        uiTextView: UITextView,
        shouldChangeTextIn range: NSRange,
        replacementText text: String,
    ) -> Bool {
        defer {
            // This isn't called when this function returns false, but
            // we need it to to show and hide the placeholder text
            textView.textViewDidChange(uiTextView)
        }

        if textView == self.aepTextView {
            AccountEntropyPoolTextView.Utils.textViewShouldChangeTextIn(
                uiTextView: uiTextView,
                shouldChangeTextIn: range,
                replacementText: text,
                font: textView.editorFont,
                lineSpacing: Constants.lineSpacing,
            )
            if
                let text = textView.text?.removeCharacters(characterSet: .whitespaces),
                let aep = try? DisplayableAccountEntropyPool(displayString: text)
            {
                aepSubject.value = .valid(aep.rawValue)
            } else {
                aepSubject.value = .partial(textView.text ?? "")
            }
        }
        return false
    }

    // MARK: - UITextFieldDelegate

    func textField(
        _ textField: UITextField,
        shouldChangeCharactersIn range: NSRange,
        replacementString string: String,
    ) -> Bool {
        if textField == aciTextField {
            let value = FormattedNumberField.textField(
                textField,
                shouldChangeCharactersIn: range,
                replacementString: string,
                allowedCharacters: FormattedNumberField.AllowedCharacters(
                    keyboardType: .asciiCapable,
                    stringFilter: \.isHexDigit,
                ),
                maxCharacters: 32,
                format: { unformatted in
                    return Self.formatAciForTextDisplay(inputText: unformatted)
                },
            )

            if
                let text = textField.text,
                let aci = Aci.parseFrom(aciString: text)
            {
                aciSubject.value = .valid(aci)
            } else {
                aciSubject.value = .partial(textField.text ?? "")
            }

            return value
        }
        if textField == aepTextField {
            // Apply the edit ourselves rather than letting UIKit do it. A secure
            // field whose text was set programmatically (e.g. a prefilled key, or
            // one carried over from the multi-line view) replaces its entire
            // contents on the next user edit; the range passed here is still the
            // one the user intended, so applying it directly avoids the wipe.
            // The key is kept unformatted here, since spaces would render as dots.
            let value = FormattedNumberField.textField(
                textField,
                shouldChangeCharactersIn: range,
                replacementString: string,
                allowedCharacters: DisplayableAccountEntropyPool.allowedCharacters,
                maxCharacters: AccountEntropyPool.Constants.byteLength,
                format: { $0 },
            )

            if
                let text = textField.text?.removeCharacters(characterSet: .whitespaces),
                let aep = try? DisplayableAccountEntropyPool(displayString: text)
            {
                aepSubject.value = .valid(aep.rawValue)
            } else {
                aepSubject.value = .partial(textField.text ?? "")
            }

            return value
        }
        return true
    }

    func textFieldDidChangeSelection(_ textField: UITextField) {
        if textField == aepTextField {
            aepToggleButton.isHidden = (textField.text?.isEmpty == true)
        }
    }

    // MARK: - Static Utils

    static func formatAciForTextDisplay(inputText: String) -> String {
        var groupCount = 0
        let result = inputText
            .uppercased()
            .enumerated()
            .map { index, char -> String in
                switch groupCount {
                case 0:
                    if index == 8 {
                        groupCount += 1
                        return "-" + String(char)
                    }
                    return String(char)
                case 1...3:
                    if index == (8 + (groupCount * 4)) {
                        groupCount += 1
                        return "-" + String(char)
                    }
                    return String(char)
                default:
                    return String(char)
                }
            }
            .joined()
        return result
    }
}
