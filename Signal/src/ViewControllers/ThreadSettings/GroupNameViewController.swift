//
// Copyright 2021 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import SignalUI

protocol GroupNameViewControllerDelegate: AnyObject {
    func groupNameViewControllerDidComplete(groupName: String?)
}

class GroupNameViewController: OWSTableViewController2 {
    private let helper: GroupAttributesEditorHelper

    weak var nameDelegate: GroupNameViewControllerDelegate?

    required init(groupModel: TSGroupModel, groupNameCurrent: String? = nil) {
        self.helper = GroupAttributesEditorHelper(groupModel: groupModel)

        if let groupNameCurrent = groupNameCurrent {
            self.helper.groupNameOriginal = groupNameCurrent
        }

        super.init()

        shouldAvoidKeyboard = true
    }

    // MARK: -

    override func viewDidLoad() {
        super.viewDidLoad()

        helper.delegate = self
        helper.buildContents()

        updateNavigation()
        updateTableContents()
    }

    override func viewWillTransition(to size: CGSize, with coordinator: UIViewControllerTransitionCoordinator) {
        super.viewWillTransition(to: size, with: coordinator)

        coordinator.animate(alongsideTransition: { (_) in
            self.helper.descriptionTextView.scrollToFocus(in: self.tableView, animated: true)
        }, completion: nil)
    }

    // Don't allow interactive dismiss when there are unsaved changes.
    override var isModalInPresentation: Bool {
        get { helper.hasUnsavedChanges }
        set {}
    }

    private func updateNavigation() {
        title = OWSLocalizedString(
            "GROUP_NAME_VIEW_TITLE",
            comment: "Title for the group name view."
        )

        navigationItem.leftBarButtonItem = UIBarButtonItem(
            barButtonSystemItem: .cancel,
            target: self,
            action: #selector(didTapCancel),
            accessibilityIdentifier: "cancel_button"
        )

        if helper.hasUnsavedChanges {
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

        helper.nameTextField.becomeFirstResponder()
    }

    func updateTableContents() {
        let contents = OWSTableContents()

        let nameTextField = helper.nameTextField

        let section = OWSTableSection()
        section.add(.init(
            customCellBlock: {
                let cell = OWSTableItem.newCell()

                cell.selectionStyle = .none

                nameTextField.font = .dynamicTypeBodyClamped
                nameTextField.textColor = Theme.primaryTextColor

                cell.contentView.addSubview(nameTextField)
                nameTextField.autoPinEdgesToSuperviewMargins()

                return cell
            },
            actionBlock: {
                nameTextField.becomeFirstResponder()
            }
        ))

        contents.add(section)

        self.contents = contents
    }

    @objc
    private func didTapCancel() {
        guard helper.hasUnsavedChanges else {
            dismiss(animated: true)
            return
        }

        OWSActionSheets.showPendingChangesActionSheet(discardAction: { [weak self] in
            self?.dismiss(animated: true)
        })
    }

    @objc
    private func didTapDone() {
        helper.nameTextField.acceptAutocorrectSuggestion()
        nameDelegate?.groupNameViewControllerDidComplete(groupName: helper.groupNameCurrent)
        dismiss(animated: true)
    }
}

extension GroupNameViewController: GroupAttributesEditorHelperDelegate {
    func groupAttributesEditorContentsDidChange() {
        updateNavigation()
    }

    func groupAttributesEditorSelectionDidChange() {}
}
