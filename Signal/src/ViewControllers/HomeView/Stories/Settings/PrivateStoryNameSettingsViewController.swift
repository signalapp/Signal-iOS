//
// Copyright 2022 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import SignalServiceKit
import SignalUI

public class PrivateStoryNameSettingsViewController: OWSTableViewController2 {

    let thread: TSPrivateStoryThread
    let completionHandler: () -> Void

    var hasPendingChanges: Bool { nameTextField.text?.filterForDisplay != thread.name }

    required init(thread: TSPrivateStoryThread, completionHandler: @escaping () -> Void) {
        self.thread = thread
        self.completionHandler = completionHandler

        super.init()

        self.shouldAvoidKeyboard = true
    }

    // MARK: - View Lifecycle

    public override func viewDidLoad() {
        super.viewDidLoad()

        title = thread.name

        updateTableContents()
        updateNavigationBar()
    }

    public override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)

        nameTextField.becomeFirstResponder()
    }

    // MARK: -

    private lazy var nameTextField: UITextField = {
        let textField = UITextField()

        textField.text = thread.name
        textField.font = .dynamicTypeBody
        textField.backgroundColor = .clear
        textField.placeholder = OWSLocalizedString(
            "NEW_PRIVATE_STORY_NAME_PLACEHOLDER",
            comment: "Placeholder text for a new private story name"
        )
        textField.returnKeyType = .done
        textField.delegate = self
        textField.addTarget(self, action: #selector(textFieldDidChange), for: .editingChanged)

        return textField
    }()

    public override func themeDidChange() {
        super.themeDidChange()

        nameTextField.textColor = Theme.primaryTextColor
    }

    private func updateNavigationBar() {
        navigationItem.leftBarButtonItem = UIBarButtonItem(
            barButtonSystemItem: .cancel,
            target: self,
            action: #selector(didTapCancel)
        )

        navigationItem.rightBarButtonItem = UIBarButtonItem(
            barButtonSystemItem: .done,
            target: self,
            action: #selector(didTapDone)
        )
        navigationItem.rightBarButtonItem?.isEnabled = hasPendingChanges
    }

    private func updateTableContents() {
        let contents = OWSTableContents()

        let nameSection = OWSTableSection()
        nameSection.add(.init(
            customCellBlock: { [weak self] in
                let cell = OWSTableItem.newCell()
                cell.selectionStyle = .none
                guard let self = self else { return cell }

                cell.contentView.addSubview(self.nameTextField)
                self.nameTextField.autoPinEdgesToSuperviewMargins()

                return cell
            },
            actionBlock: {}
        ))
        contents.addSection(nameSection)

        self.contents = contents
    }

    // MARK: - Actions

    @objc
    private func didTapCancel() {
        AssertIsOnMainThread()

        if hasPendingChanges {
            OWSActionSheets.showPendingChangesActionSheet {
                self.dismiss(animated: true)
            }
        } else {
            dismiss(animated: true)
        }
    }

    @objc
    private func didTapDone() {
        AssertIsOnMainThread()

        guard let name = nameTextField.text?.nilIfEmpty?.filterForDisplay else {
            return showMissingNameAlert()
        }
        databaseStorage.asyncWrite { transaction in
            self.thread.updateWithName(name, updateStorageService: true, transaction: transaction)
        } completion: { [weak self] in
            guard let self = self else { return }
            self.dismiss(animated: true)
        }
    }

    @objc
    private func textFieldDidChange(_ textField: UITextField) {
        updateNavigationBar()
    }

    public override func dismiss(animated flag: Bool, completion: (() -> Void)? = nil) {
        super.dismiss(animated: flag, completion: completion)
        completionHandler()
    }

    public func showMissingNameAlert() {
        AssertIsOnMainThread()

        OWSActionSheets.showActionSheet(
            title: OWSLocalizedString(
                "NEW_PRIVATE_STORY_MISSING_NAME_ALERT_TITLE",
                comment: "Title for error alert indicating that a story name is required."
            ),
            message: OWSLocalizedString(
                "NEW_PRIVATE_STORY_MISSING_NAME_ALERT_MESSAGE",
                comment: "Message for error alert indicating that a story name is required."
            )
        )
    }
}

extension PrivateStoryNameSettingsViewController: UITextFieldDelegate {
    public func textField(_ textField: UITextField, shouldChangeCharactersIn range: NSRange, replacementString string: String) -> Bool {
        if string == "\n" {
            if hasPendingChanges {
                didTapDone()
            } else {
                didTapCancel()
            }
            return false
        } else {
            return true
        }
    }
}
