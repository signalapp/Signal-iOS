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
    private lazy var givenNameTextField = OWSTextField(
        placeholder: OWSLocalizedString(
            "PROFILE_VIEW_GIVEN_NAME_DEFAULT_TEXT",
            comment: "Default text for the given name field of the profile view."
        ),
        returnKeyType: .next,
        spellCheckingType: .no,
        autocorrectionType: .no,
        delegate: self,
        editingChanged: { [weak self] in
            self?.textFieldDidChange()
        }
    )
    private lazy var familyNameTextField = OWSTextField(
        placeholder: OWSLocalizedString(
            "PROFILE_VIEW_FAMILY_NAME_DEFAULT_TEXT",
            comment: "Default text for the family name field of the profile view."
        ),
        returnKeyType: .done,
        spellCheckingType: .no,
        autocorrectionType: .no,
        delegate: self,
        editingChanged: { [weak self] in
            self?.textFieldDidChange()
        }
    )

    private let originalGivenName: String?
    private let originalFamilyName: String?

    private weak var profileDelegate: ProfileNameViewControllerDelegate?

    init(
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
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        updateNavigation()
        updateTableContents()
    }

    private func givenNameComponent() -> ProfileName.NameComponent? {
        givenNameTextField.text.flatMap(OWSUserProfile.NameComponent.parse(truncating:))?.nameComponent
    }

    private func familyNameComponent() -> ProfileName.NameComponent? {
        familyNameTextField.text.flatMap(OWSUserProfile.NameComponent.parse(truncating:))?.nameComponent
    }

    private var hasUnsavedChanges: Bool {
        givenNameComponent()?.stringValue.rawValue != originalGivenName
        || familyNameComponent()?.stringValue.rawValue != originalFamilyName
    }

    // Don't allow interactive dismiss when there are unsaved changes.
    override var isModalInPresentation: Bool {
        get { hasUnsavedChanges }
        set {}
    }

    private func updateNavigation() {
        title = OWSLocalizedString("PROFILE_NAME_VIEW_TITLE", comment: "Title for the profile name view.")

        navigationItem.leftBarButtonItem = .cancelButton(
            dismissingFrom: self,
            hasUnsavedChanges: { [weak self] in self?.hasUnsavedChanges }
        )

        if hasUnsavedChanges {
            navigationItem.rightBarButtonItem = .doneButton { [weak self] in
                self?.didTapDone()
            }
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

    private static let bioButtonHeight: CGFloat = 28

    func updateTableContents() {
        let contents = OWSTableContents()

        let givenNameTextField = self.givenNameTextField
        let familyNameTextField = self.familyNameTextField

        let namesSection = OWSTableSection()
        func addTextField(_ textField: UITextField) {
            namesSection.add(.textFieldItem(textField))
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

    private func didTapDone() {
        switch ProfileName.createNameFrom(
            givenName: givenNameTextField.text,
            familyName: familyNameTextField.text
        ) {
        case .failure(.givenNameTooLong):
            OWSActionSheets.showErrorAlert(message: OWSLocalizedString(
                "PROFILE_VIEW_ERROR_GIVEN_NAME_TOO_LONG",
                comment: "Error message shown when user tries to update profile with a given name that is too long."
            ))
        case .failure(.familyNameTooLong):
            OWSActionSheets.showErrorAlert(message: OWSLocalizedString(
                "PROFILE_VIEW_ERROR_FAMILY_NAME_TOO_LONG",
                comment: "Error message shown when user tries to update profile with a family name that is too long."
            ))
        case let .success(profileName):
            guard let givenName = profileName.givenNameComponent else { fallthrough }
            profileDelegate?.profileNameViewDidComplete(
                givenName: givenName,
                familyName: profileName.familyNameComponent
            )
            dismiss(animated: true)
        case .failure(.nameEmpty):
            OWSActionSheets.showErrorAlert(message: OWSLocalizedString(
                "PROFILE_VIEW_ERROR_GIVEN_NAME_REQUIRED",
                comment: "Error message shown when user tries to update profile without a given name"
            ))
        }
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

    func textFieldDidChange() {
        updateNavigation()
    }

    func textField(_ textField: UITextField, shouldChangeCharactersIn range: NSRange, replacementString string: String) -> Bool {
        TextFieldHelper.textField(
            textField,
            shouldChangeCharactersInRange: range,
            replacementString: string,
            maxByteCount: OWSUserProfile.Constants.maxNameLengthBytes,
            maxGlyphCount: OWSUserProfile.Constants.maxNameLengthGlyphs
        )
    }
}
