//
// Copyright 2021 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import SignalServiceKit
import SignalUI

protocol ProfileNameViewControllerDelegate: AnyObject {
    func profileNameViewDidComplete(givenName: OWSUserProfile.NameComponent, familyName: OWSUserProfile.NameComponent?)
}

// MARK: -

class ProfileNameViewController: OWSTableViewController2 {
    private let givenNameTextField = OWSTextField()
    private let familyNameTextField = OWSTextField()

    private let originalGivenName: String?
    private let originalFamilyName: String?

    private weak var profileDelegate: ProfileNameViewControllerDelegate?

    required init(
        givenName: String?,
        familyName: String?,
        profileDelegate: ProfileNameViewControllerDelegate
    ) {
        self.originalGivenName = givenName
        self.originalFamilyName = familyName
        self.profileDelegate = profileDelegate

        super.init()

        self.givenNameTextField.text = givenName
        self.familyNameTextField.text = familyName

        self.shouldAvoidKeyboard = true
    }

    // MARK: -

    public override func loadView() {
        view = UIView()
        createViews()
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        updateNavigation()
        updateTableContents()
    }

    private func givenNameComponent() -> (value: OWSUserProfile.NameComponent, didTruncate: Bool)? {
        givenNameTextField.text.flatMap { OWSUserProfile.NameComponent.parse(truncating: $0) }
    }

    private func familyNameComponent() -> (value: OWSUserProfile.NameComponent, didTruncate: Bool)? {
        familyNameTextField.text.flatMap { OWSUserProfile.NameComponent.parse(truncating: $0) }
    }

    private var hasUnsavedChanges: Bool {
        return (
            givenNameComponent()?.value.stringValue.rawValue != originalGivenName
            || familyNameComponent()?.value.stringValue.rawValue != originalFamilyName
        )
    }

    // Don't allow interactive dismiss when there are unsaved changes.
    override var isModalInPresentation: Bool {
        get { hasUnsavedChanges }
        set {}
    }

    private func updateNavigation() {
        title = OWSLocalizedString("PROFILE_NAME_VIEW_TITLE", comment: "Title for the profile name view.")

        navigationItem.leftBarButtonItem = UIBarButtonItem(
            barButtonSystemItem: .cancel,
            target: self,
            action: #selector(didTapCancel),
            accessibilityIdentifier: "cancel_button"
        )

        if hasUnsavedChanges {
            navigationItem.rightBarButtonItem = UIBarButtonItem(
                barButtonSystemItem: .done,
                target: self,
                action: #selector(didTapDone),
                accessibilityIdentifier: "done_button"
            )
        } else {
            navigationItem.rightBarButtonItem = nil
        }
    }

    public override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)

        updateNavigation()

        firstTextField.becomeFirstResponder()
    }

    public override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)

        updateNavigation()

        // TODO: First responder
    }

    private func createViews() {
        givenNameTextField.returnKeyType = .next
        givenNameTextField.autocorrectionType = .no
        givenNameTextField.spellCheckingType = .no
        givenNameTextField.placeholder = OWSLocalizedString(
            "PROFILE_VIEW_GIVEN_NAME_DEFAULT_TEXT",
            comment: "Default text for the given name field of the profile view."
        )
        givenNameTextField.delegate = self
        givenNameTextField.addTarget(self, action: #selector(textFieldDidChange), for: .editingChanged)

        familyNameTextField.returnKeyType = .done
        familyNameTextField.autocorrectionType = .no
        familyNameTextField.spellCheckingType = .no
        familyNameTextField.placeholder = OWSLocalizedString(
            "PROFILE_VIEW_FAMILY_NAME_DEFAULT_TEXT",
            comment: "Default text for the family name field of the profile view."
        )
        familyNameTextField.delegate = self
        familyNameTextField.addTarget(self, action: #selector(textFieldDidChange), for: .editingChanged)
    }

    private static let bioButtonHeight: CGFloat = 28

    func updateTableContents() {
        let contents = OWSTableContents()

        let givenNameTextField = self.givenNameTextField
        let familyNameTextField = self.familyNameTextField

        let namesSection = OWSTableSection()
        func addTextField(_ textField: UITextField) {
            namesSection.add(.init(customCellBlock: { [weak self] in
                guard let self = self else { return UITableViewCell() }
                return self.nameCell(textField: textField)
            },
                actionBlock: {
                    textField.becomeFirstResponder()
                }
            ))
        }

        // For CJKV locales, display family name field first.
        if NSLocale.current.isCJKV {
            addTextField(familyNameTextField)
            addTextField(givenNameTextField)

        // Otherwise, display given name field first.
        } else {
            addTextField(givenNameTextField)
            addTextField(familyNameTextField)
        }

        contents.add(namesSection)

        self.contents = contents
    }

    private func nameCell(textField: UITextField) -> UITableViewCell {
        let cell = OWSTableItem.newCell()

        cell.selectionStyle = .none

        textField.font = .dynamicTypeBodyClamped
        textField.textColor = Theme.primaryTextColor

        cell.addSubview(textField)
        textField.autoPinEdgesToSuperviewMargins()

        return cell
    }

    @objc
    private func didTapCancel() {
        guard hasUnsavedChanges else {
            dismiss(animated: true)
            return
        }

        OWSActionSheets.showPendingChangesActionSheet(discardAction: { [weak self] in
            self?.dismiss(animated: true)
        })
    }

    @objc
    private func didTapDone() {
        guard let (givenName, didTruncateGivenName) = givenNameComponent() else {
            OWSActionSheets.showErrorAlert(message: OWSLocalizedString(
                "PROFILE_VIEW_ERROR_GIVEN_NAME_REQUIRED",
                comment: "Error message shown when user tries to update profile without a given name"
            ))
            return
        }

        if didTruncateGivenName {
            OWSActionSheets.showErrorAlert(message: OWSLocalizedString(
                "PROFILE_VIEW_ERROR_GIVEN_NAME_TOO_LONG",
                comment: "Error message shown when user tries to update profile with a given name that is too long."
            ))
            return
        }

        let familyNameComponent = self.familyNameComponent()
        if let familyNameComponent, familyNameComponent.didTruncate {
            OWSActionSheets.showErrorAlert(message: OWSLocalizedString(
                "PROFILE_VIEW_ERROR_FAMILY_NAME_TOO_LONG",
                comment: "Error message shown when user tries to update profile with a family name that is too long."
            ))
            return
        }

        profileDelegate?.profileNameViewDidComplete(givenName: givenName, familyName: familyNameComponent?.value)
        dismiss(animated: true)
    }
}

// MARK: -

extension ProfileNameViewController: UITextFieldDelegate {

    private var firstTextField: UITextField {
        NSLocale.current.isCJKV ? familyNameTextField : givenNameTextField
    }

    private var secondTextField: UITextField {
        NSLocale.current.isCJKV ? givenNameTextField : familyNameTextField
    }

    public func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        if textField === firstTextField {
            secondTextField.becomeFirstResponder()
        } else {
            didTapDone()
        }
        return false
    }

    @objc
    func textFieldDidChange(_ textField: UITextField) {
        updateNavigation()
    }
}
