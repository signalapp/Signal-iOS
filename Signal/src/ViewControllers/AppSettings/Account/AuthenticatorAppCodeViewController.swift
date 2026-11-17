//
// Copyright 2026 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import LibSignalClient
import SignalServiceKit
import SignalUI

/// The last step of setting up an authenticator app: entering a code from the
/// app to confirm it was set up correctly.
class AuthenticatorAppCodeViewController: OWSTableViewController2 {

    private let digitCount: Int32
    private let validateCode: (Int32) async throws -> ConfirmedMfaKey?
    private let onVerified: (ConfirmedMfaKey) -> Void

    init(
        digitCount: Int32,
        validateCode: @escaping (Int32) async throws -> ConfirmedMfaKey?,
        onVerified: @escaping (ConfirmedMfaKey) -> Void,
    ) {
        self.digitCount = digitCount
        self.validateCode = validateCode
        self.onVerified = onVerified
        super.init()
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        title = OWSLocalizedString(
            "AUTHENTICATOR_APP_CODE_TITLE",
            comment: "Title for screen where user confirms their TOTP code from their authenticator app.",
        )

        shouldAvoidKeyboard = true

        let section = OWSTableSection()
        section.add(.textFieldItem(codeTextField))
        section.footerTitle = OWSLocalizedString(
            "AUTHENTICATOR_APP_CODE_FOOTER",
            comment: "Instructions for screen where user confirms their TOTP code from their authenticator app.",
        )
        contents = OWSTableContents(sections: [section])

        updateContinueButton()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        codeTextField.becomeFirstResponder()
    }

    // MARK: Views

    private lazy var codeTextField: UITextField = {
        let textField = UITextField()
        textField.font = .dynamicTypeTitle2
        textField.textAlignment = .center
        textField.keyboardType = .numberPad
        textField.textContentType = .oneTimeCode
        textField.isSecureTextEntry = true
        textField.accessibilityLabel = OWSLocalizedString(
            "AUTHENTICATOR_APP_CODE_FIELD_LABEL",
            comment: "Accessibility label for screen where user confirms their TOTP code from their authenticator app.",
        )
        textField.addAction(UIAction { [weak self] _ in
            self?.codeDidChange()
        }, for: .editingChanged)
        return textField
    }()

    private lazy var continueButton = UIButton(
        configuration: .largePrimary(title: CommonStrings.continueButton),
        primaryAction: UIAction { [weak self] _ in
            self?.didTapContinue()
        },
    )

    private lazy var bottomFooterContainer: UIView = {
        let stackView = UIStackView.verticalButtonStack(buttons: [continueButton])
        let view = UIView()
        view.preservesSuperviewLayoutMargins = true
        view.addSubview(stackView)
        stackView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            stackView.topAnchor.constraint(equalTo: view.topAnchor),
            stackView.leadingAnchor.constraint(equalTo: view.layoutMarginsGuide.leadingAnchor),
            stackView.trailingAnchor.constraint(equalTo: view.layoutMarginsGuide.trailingAnchor),
            stackView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
        return view
    }()

    override func bottomFooter() -> UIView? { bottomFooterContainer }

    // MARK: Events

    private var code: String { codeTextField.text ?? "" }

    private func codeDidChange() {
        // Pasted or autofilled codes may carry spaces or other separators.
        let sanitized = String(code.asciiDigitsOnly.prefix(Int(digitCount)))
        if sanitized != code {
            codeTextField.text = sanitized
        }
        updateContinueButton()
    }

    private func updateContinueButton() {
        continueButton.isEnabled = code.count == digitCount
    }

    private func didTapContinue() {
        Task {
            guard
                code.count == digitCount,
                let intValue = Int32(code),
                let method = try? await validateCode(intValue) // TODO[#less]: catch this error to show a better error to the user
            else {
                codeTextField.text = ""
                updateContinueButton()
                OWSActionSheets.showActionSheet(
                    title: OWSLocalizedString(
                        "AUTHENTICATOR_APP_CODE_INCORRECT_TITLE",
                        comment: "Title of the error sheet shown when the TOTP code is wrong.",
                    ),
                    message: OWSLocalizedString(
                        "AUTHENTICATOR_APP_CODE_INCORRECT_MESSAGE",
                        comment: "Message for the error sheet shown when the TOTP code is wrong.",
                    ),
                    fromViewController: self,
                )
                return
            }
            onVerified(method)
        }
    }
}

// MARK: -

#if DEBUG

@available(iOS 17, *)
#Preview {
    OWSNavigationController(rootViewController: AuthenticatorAppCodeViewController(
        digitCount: 6,
        validateCode: { _ in return nil },
        onVerified: { _ in print("verified") },
    ))
}

#endif
