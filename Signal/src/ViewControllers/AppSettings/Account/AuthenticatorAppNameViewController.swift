//
// Copyright 2026 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import SignalServiceKit
import SignalUI

/// The first step of setting up an authenticator app for two-factor
/// authentication: naming it, so the user can tell it apart from others later.
class AuthenticatorAppNameViewController: OWSTableViewController2 {

    private let onContinue: (String) -> Void
    private let onCancel: () -> Void

    init(
        onContinue: @escaping (String) -> Void,
        onCancel: @escaping () -> Void,
    ) {
        self.onContinue = onContinue
        self.onCancel = onCancel
        super.init()
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        title = OWSLocalizedString(
            "AUTHENTICATOR_APP_NAME_TITLE",
            comment: "Title for the screen where the user names an authenticator app for two-factor authentication.",
        )
        navigationItem.rightBarButtonItem = .closeButton { [weak self] in
            self?.onCancel()
        }

        shouldAvoidKeyboard = true

        let section = OWSTableSection()
        section.add(.textFieldItem(nameTextField))
        section.footerTitle = OWSLocalizedString(
            "AUTHENTICATOR_APP_NAME_FOOTER",
            comment: "Explains why the user should name an authenticator app for two-factor authentication.",
        )
        contents = OWSTableContents(sections: [section])

        updateContinueButton()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        nameTextField.becomeFirstResponder()
    }

    // MARK: Views

    private lazy var nameTextField: UITextField = {
        let textField = UITextField()
        textField.font = .dynamicTypeBody
        textField.placeholder = OWSLocalizedString(
            "SETTINGS_TWO_FACTOR_METHODS_NAME_PLACEHOLDER",
            comment: "Placeholder for the field where the user names a two-factor authentication method.",
        )
        textField.autocapitalizationType = .words
        textField.autocorrectionType = .no
        textField.returnKeyType = .continue
        textField.clearButtonMode = .whileEditing
        textField.addAction(UIAction { [weak self] _ in
            self?.updateContinueButton()
        }, for: .editingChanged)
        textField.addAction(UIAction { [weak self] _ in
            self?.didTapContinue()
        }, for: .editingDidEndOnExit)
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

    private var trimmedName: String {
        (nameTextField.text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func updateContinueButton() {
        continueButton.isEnabled = !trimmedName.isEmpty
    }

    private func didTapContinue() {
        let name = trimmedName
        guard !name.isEmpty else { return }
        onContinue(name)
    }
}

// MARK: -

#if DEBUG

@available(iOS 17, *)
#Preview {
    OWSNavigationController(rootViewController: AuthenticatorAppNameViewController(
        onContinue: { print("name: \($0)") },
        onCancel: {},
    ))
}

#endif
