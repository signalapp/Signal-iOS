//
//  Copyright (c) 2020 Open Whisper Systems. All rights reserved.
//

import Foundation

@objc
class UsernameViewController: OWSViewController {

    @objc
    public var modalPresentation = false {
        didSet {
            guard isViewLoaded else { return }
            owsFailDebug("modalPresentation may only be set before the view has loaded.")
        }
    }

    private static let minimumUsernameLength = 4
    private static let maximumUsernameLength: UInt = 26

    private let usernameTextField = OWSTextField()
    private var hasPendingChanges: Bool {
        return pendingUsername != (OWSProfileManager.shared().localUsername() ?? "")
    }

    private var pendingUsername: String {
        return usernameTextField.text?.stripped.lowercased() ?? ""
    }

    private var errorLabel = UILabel()
    private var errorRow = UIView()

    private enum ValidationState {
        case valid
        case tooShort
        case invalidCharacters
        case inUse
        case startsWithNumber
    }
    private var validationState: ValidationState = .valid {
        didSet { updateValidationError() }
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        view.backgroundColor = Theme.backgroundColor

        title = NSLocalizedString("USERNAME_TITLE", comment: "The title for the username view.")

        if modalPresentation {
            navigationItem.leftBarButtonItem = UIBarButtonItem(title: CommonStrings.cancelButton,
                                                               style: .plain,
                                                               target: self,
                                                               action: #selector(didTapCancel))
        } else {
            navigationItem.leftBarButtonItem = createOWSBackButton()
        }

        let stackView = UIStackView()
        stackView.axis = .vertical
        stackView.spacing = 0
        view.addSubview(stackView)
        stackView.autoPinWidthToSuperview()
        stackView.autoPinTopToSuperviewMargin(withInset: 35)

        let topLine = UIView()
        let bottomLine = UIView()
        for line in [topLine, bottomLine] {
            stackView.addArrangedSubview(line)
            line.backgroundColor = Theme.cellSeparatorColor
            line.autoSetDimension(.height, toSize: CGHairlineWidth())
        }

        // Username

        let usernameRow = UIView()
        stackView.insertArrangedSubview(usernameRow, at: 1)
        usernameRow.layoutMargins = UIEdgeInsets(top: 10, leading: 18, bottom: 10, trailing: 18)

        let titleLabel = UILabel()
        titleLabel.text = NSLocalizedString("USERNAME_FIELD", comment: "Label for the username field in the username view.")
        titleLabel.textColor = Theme.primaryTextColor
        titleLabel.font = UIFont.ows_dynamicTypeBodyClamped.ows_semibold

        usernameRow.addSubview(titleLabel)
        titleLabel.autoPinLeadingToSuperviewMargin()
        titleLabel.autoPinHeightToSuperviewMargins()

        usernameTextField.font = .ows_dynamicTypeBodyClamped
        usernameTextField.textColor = Theme.primaryTextColor
        usernameTextField.autocorrectionType = .no
        usernameTextField.autocapitalizationType = .none
        usernameTextField.placeholder = NSLocalizedString("USERNAME_PLACEHOLDER",
                                                          comment: "The placeholder for the username text entry in the username view.")
        usernameTextField.text = OWSProfileManager.shared().localUsername()
        usernameTextField.textAlignment = .right
        usernameTextField.delegate = self
        usernameTextField.returnKeyType = .done
        usernameTextField.addTarget(self, action: #selector(textFieldDidChange), for: .editingChanged)
        usernameTextField.becomeFirstResponder()

        usernameRow.addSubview(usernameTextField)
        usernameTextField.autoPinLeading(toTrailingEdgeOf: titleLabel, offset: 10)
        usernameTextField.autoPinTrailingToSuperviewMargin()
        usernameTextField.autoVCenterInSuperview()

        // Error

        stackView.addArrangedSubview(errorRow)
        errorRow.isHidden = true

        errorLabel.textColor = .ows_accentRed
        errorLabel.textAlignment = .center
        errorLabel.numberOfLines = 0
        errorLabel.lineBreakMode = .byWordWrapping
        errorLabel.font = .ows_dynamicTypeCaption1Clamped

        errorRow.addSubview(errorLabel)
        errorLabel.autoPinWidthToSuperview(withMargin: 18)
        errorLabel.autoPinHeightToSuperview(withMargin: 5)

        // Info

        let infoRow = UIView()
        stackView.addArrangedSubview(infoRow)

        let infoLabel = UILabel()
        infoLabel.textColor = Theme.secondaryTextAndIconColor
        infoLabel.text = NSLocalizedString("USERNAME_DESCRIPTION", comment: "An explanation of how usernames work on the username view.")
        infoLabel.font = .ows_dynamicTypeCaption1Clamped
        infoLabel.numberOfLines = 0
        infoLabel.lineBreakMode = .byWordWrapping

        infoRow.addSubview(infoLabel)
        infoLabel.autoPinWidthToSuperview(withMargin: 18)
        infoLabel.autoPinHeightToSuperview(withMargin: 10)
    }

    func updateSaveButton() {
        guard hasPendingChanges else {
            navigationItem.rightBarButtonItem = nil
            return
        }

        navigationItem.rightBarButtonItem = UIBarButtonItem(barButtonSystemItem: .save, target: self, action: #selector(didTapSave))
    }

    func updateValidationError() {

        switch validationState {
        case .valid:
            errorRow.isHidden = true
        case .tooShort:
            errorRow.isHidden = false
            errorLabel.text = NSLocalizedString("USERNAME_TOO_SHORT_ERROR",
                                                comment: "An error indicating that the supplied username is too short.")
        case .invalidCharacters:
            errorRow.isHidden = false
            errorLabel.text = NSLocalizedString("USERNAME_INVALID_CHARACTERS_ERROR",
                                                comment: "An error indicating that the supplied username contains disallowed characters.")
        case .inUse:
            errorRow.isHidden = false

            let unavailableErrorFormat = NSLocalizedString("USERNAME_UNAVAIALBE_ERROR_FORMAT",
                                                           comment: "An error indicating that the supplied username is in use by another user. Embeds {{requested username}}.")

            errorLabel.text = String(format: unavailableErrorFormat, pendingUsername)
        case .startsWithNumber:
            errorRow.isHidden = false
            errorLabel.text = NSLocalizedString("USERNAME_STARTS_WITH_NUMBER_ERROR",
                                                comment: "An error indicating that the supplied username cannot start with a number.")
        }
    }

    func saveUsername() {
        // If we're trying to save, but we have nothing to save, just dismiss immediately.
        guard hasPendingChanges else { return usernameSavedOrCanceled() }

        guard usernameIsValid() else { return }

        var usernameToUse: String? = pendingUsername
        if usernameToUse?.isEmpty == true {
            usernameToUse = nil
        }

        ModalActivityIndicatorViewController.present(fromViewController: self, canCancel: false) { modalView in
            let usernameRequest: TSRequest
            if let usernameToUse = usernameToUse {
                usernameRequest = OWSRequestFactory.usernameSetRequest(usernameToUse)
            } else {
                usernameRequest = OWSRequestFactory.usernameDeleteRequest()
            }

            SSKEnvironment.shared.networkManager.makePromise(request: usernameRequest).done { _ in
                self.databaseStorage.write { transaction in
                    OWSProfileManager.shared().updateLocalUsername(usernameToUse, transaction: transaction)
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
                                                                        comment: "Error moessage shown when a username update fails."))
                }
            }
        }
    }

    func usernameIsValid() -> Bool {
        // We allow empty usernames, as this is how you delete your username
        guard !pendingUsername.isEmpty else {
            return true
        }

        guard pendingUsername.count >= UsernameViewController.minimumUsernameLength else {
            validationState = .tooShort
            return false
        }

        // Usernames only allow a-z, 0-9, and underscore
        let validUsernameRegex = try! NSRegularExpression(pattern: "^[a-z0-9_]+$", options: [])
        guard validUsernameRegex.hasMatch(input: pendingUsername) else {
            validationState = .invalidCharacters
            return false
        }

        let startsWithNumberRegex = try! NSRegularExpression(pattern: "^[0-9]+", options: [])
        guard !startsWithNumberRegex.hasMatch(input: pendingUsername) else {
            validationState = .startsWithNumber
            return false
        }

        return true
    }

    func usernameSavedOrCanceled() {
        usernameTextField.resignFirstResponder()

        if modalPresentation {
            dismiss(animated: true, completion: nil)
        } else {
            navigationController?.popViewController(animated: true)
        }
    }

    // MARK: -

    @objc func backButtonPressed(_ sender: UIBarButtonItem) {
        guard hasPendingChanges else {
            return usernameSavedOrCanceled()
        }

        OWSActionSheets.showPendingChangesActionSheet { [weak self] in self?.usernameSavedOrCanceled() }
    }

    @objc func didTapCancel() {
        guard hasPendingChanges else {
            return usernameSavedOrCanceled()
        }

        OWSActionSheets.showPendingChangesActionSheet { [weak self] in self?.usernameSavedOrCanceled() }
    }

    @objc func didTapSave() {
        saveUsername()
    }

    @objc func textFieldDidChange() {
        // Clear validation errors when the user starts typing again.
        validationState = .valid
        updateSaveButton()
    }
}

// MARK: -

extension UsernameViewController: UITextFieldDelegate {
    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        usernameTextField.resignFirstResponder()
        return false
    }

    func textField(_ textField: UITextField, shouldChangeCharactersIn range: NSRange, replacementString string: String) -> Bool {
        return TextFieldHelper.textField(
            textField,
            shouldChangeCharactersInRange: range,
            replacementString: string,
            byteLimit: UsernameViewController.maximumUsernameLength
        )
    }
}
