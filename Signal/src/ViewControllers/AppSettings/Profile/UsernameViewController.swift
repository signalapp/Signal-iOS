//
// Copyright 2021 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import BonMot
import Foundation
import SignalMessaging
import UIKit

@objc
class UsernameViewController: OWSTableViewController2 {
    private let usernameTextField = OWSTextField()
    private let originalUsername: String?

    private static let minimumUsernameLength = 4
    private static let maximumUsernameLength: Int = 26

    private enum ValidationState {
        case valid
        case tooShort
        case invalidCharacters
        case inUse
        case startsWithNumber
    }
    private var validationState: ValidationState = .valid {
        didSet {
            let didChange = oldValue != validationState
            if didChange, isViewLoaded {
                updateTableContents()
            }
        }
    }

    required init(username: String?) {
        self.originalUsername = username

        super.init()

        self.usernameTextField.text = username

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

    private var normalizedUsername: String? {
        let normalizedName = usernameTextField.text?.stripped.lowercased()
        if normalizedName?.isEmpty == true { return nil }
        return normalizedName
    }

    private var hasUnsavedChanges: Bool {
        normalizedUsername != originalUsername
    }
    // Don't allow interactive dismiss when there are unsaved changes.
    override var isModalInPresentation: Bool {
        get { hasUnsavedChanges }
        set {}
    }

    private func updateNavigation() {
        title = NSLocalizedString("USERNAME_TITLE", comment: "The title for the username view.")

        navigationItem.leftBarButtonItem = UIBarButtonItem(
            barButtonSystemItem: .cancel,
            target: self,
            action: #selector(didTapCancel),
            accessibilityIdentifier: "cancel_button"
        )

        if hasUnsavedChanges {
            navigationItem.rightBarButtonItem = UIBarButtonItem(
                title: CommonStrings.setButton,
                style: .done,
                target: self,
                action: #selector(didTapDone),
                accessibilityIdentifier: "set_button"
            )
        } else {
            navigationItem.rightBarButtonItem = nil
        }
    }

    public override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)

        updateNavigation()
    }

    public override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)

        updateNavigation()

        usernameTextField.becomeFirstResponder()
    }

    private func createViews() {
        usernameTextField.returnKeyType = .done
        usernameTextField.autocorrectionType = .no
        usernameTextField.spellCheckingType = .no
        usernameTextField.placeholder = NSLocalizedString(
            "USERNAME_PLACEHOLDER",
            comment: "The placeholder for the username text entry in the username view."
        )
        usernameTextField.delegate = self
        usernameTextField.accessibilityIdentifier = "username_textfield"
        usernameTextField.addTarget(self, action: #selector(textFieldDidChange), for: .editingChanged)
    }

    private static let bioButtonHeight: CGFloat = 28

    private func updateTableContents() {
        let contents = OWSTableContents()

        let section = OWSTableSection()

        var footerComponents = [Composable]()

        if let errorText = errorText {
            footerComponents.append(errorText.styled(with: .color(.ows_accentRed)))
            footerComponents.append("\n\n")
        }

        footerComponents.append(NSLocalizedString(
            "USERNAME_DESCRIPTION",
            comment: "An explanation of how usernames work on the username view."
        ))

        section.footerAttributedTitle = NSAttributedString.composed(of: footerComponents).styled(
            with: .font(.ows_dynamicTypeCaption1Clamped),
            .color(Theme.secondaryTextAndIconColor)
        )

        section.add(.init(customCellBlock: { [weak self] in
            guard let self = self else { return UITableViewCell() }
            return self.nameCell(textField: self.usernameTextField)
        },
            actionBlock: { [weak self] in
                self?.usernameTextField.becomeFirstResponder()
            }
        ))
        contents.addSection(section)

        let wasFirstResponder = usernameTextField.isFirstResponder

        self.contents = contents

        if wasFirstResponder {
            usernameTextField.becomeFirstResponder()
        }
    }

    override func themeDidChange() {
        super.themeDidChange()
        updateTableContents()
    }

    private var errorText: String? {
        switch validationState {
        case .valid:
            return nil
        case .tooShort:
            return NSLocalizedString(
                "USERNAME_TOO_SHORT_ERROR",
                comment: "An error indicating that the supplied username is too short."
            )
        case .invalidCharacters:
            return NSLocalizedString(
                "USERNAME_INVALID_CHARACTERS_ERROR",
                comment: "An error indicating that the supplied username contains disallowed characters."
            )
        case .inUse:
            let unavailableErrorFormat = NSLocalizedString(
                "USERNAME_UNAVAIALBE_ERROR_FORMAT",
                comment: "An error indicating that the supplied username is in use by another user. Embeds {{requested username}}."
            )

            return String(format: unavailableErrorFormat, normalizedUsername ?? "")
        case .startsWithNumber:
            return NSLocalizedString(
                "USERNAME_STARTS_WITH_NUMBER_ERROR",
                comment: "An error indicating that the supplied username cannot start with a number."
            )
        }
    }

    private func nameCell(textField: UITextField) -> UITableViewCell {
        let cell = OWSTableItem.newCell()

        cell.selectionStyle = .none

        textField.font = .ows_dynamicTypeBodyClamped
        textField.textColor = Theme.primaryTextColor

        cell.addSubview(textField)
        textField.autoPinEdgesToSuperviewMargins()

        return cell
    }

    @objc
    func didTapCancel() {
        guard hasUnsavedChanges else { return usernameSavedOrCanceled() }

        OWSActionSheets.showPendingChangesActionSheet(discardAction: { [weak self] in
            self?.usernameSavedOrCanceled()
        })
    }

    @objc
    func didTapDone() {
        // If we're trying to save, but we have nothing to save, just dismiss immediately.
        guard hasUnsavedChanges else { return usernameSavedOrCanceled() }

        guard usernameIsValid() else { return }

        var usernameToUse: String? = normalizedUsername
        if usernameToUse?.isEmpty == true { usernameToUse = nil }

        ModalActivityIndicatorViewController.present(fromViewController: self, canCancel: false) { modalView in
            let usernameRequest: TSRequest
            if let usernameToUse = usernameToUse {
                usernameRequest = OWSRequestFactory.usernameSetRequest(usernameToUse)
            } else {
                usernameRequest = OWSRequestFactory.usernameDeleteRequest()
            }

            firstly(on: .global()) {
                Self.networkManager.makePromise(request: usernameRequest)
            }.done(on: .main) { _ in
                self.databaseStorage.write { transaction in
                    Self.profileManagerImpl.updateLocalUsername(usernameToUse,
                                                                userProfileWriter: .localUser,
                                                                transaction: transaction)
                }
                modalView.dismiss {
                    self.usernameSavedOrCanceled()
                }
            }.catch { error in
                if error.httpStatusCode == 409 {
                    modalView.dismiss { self.validationState = .inUse }
                    return
                }

                owsFailDebug("Unexpected username update error \(error)")

                modalView.dismiss {
                    OWSActionSheets.showErrorAlert(message: NSLocalizedString("USERNAME_VIEW_ERROR_UPDATE_FAILED",
                                                                        comment: "Error message shown when a username update fails."))
                }
            }
        }
    }

    func usernameIsValid() -> Bool {
        // We allow empty usernames, as this is how you delete your username
        guard let normalizedUsername = normalizedUsername, !normalizedUsername.isEmpty else {
            return true
        }

        guard normalizedUsername.count >= UsernameViewController.minimumUsernameLength else {
            validationState = .tooShort
            return false
        }

        // Usernames only allow a-z, 0-9, and underscore
        let validUsernameRegex = try! NSRegularExpression(pattern: "^[a-z0-9_]+$", options: [])
        guard validUsernameRegex.hasMatch(input: normalizedUsername) else {
            validationState = .invalidCharacters
            return false
        }

        let startsWithNumberRegex = try! NSRegularExpression(pattern: "^[0-9]+", options: [])
        guard !startsWithNumberRegex.hasMatch(input: normalizedUsername) else {
            validationState = .startsWithNumber
            return false
        }

        return true
    }

    func usernameSavedOrCanceled() {
        usernameTextField.resignFirstResponder()

        dismiss(animated: true)
    }
}

// MARK: -

extension UsernameViewController: UITextFieldDelegate {
    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        didTapDone()
        return false
    }

    func textField(_ textField: UITextField,
                   shouldChangeCharactersIn range: NSRange,
                   replacementString string: String) -> Bool {
        TextFieldHelper.textField(
            textField,
            shouldChangeCharactersInRange: range,
            replacementString: string,
            maxByteCount: UsernameViewController.maximumUsernameLength
        )
    }

    @objc
    func textFieldDidChange() {
        validationState = .valid
        updateNavigation()
    }
}
