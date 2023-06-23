//
// Copyright 2020 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import SignalMessaging
import SignalServiceKit
import SignalUI

protocol GroupAttributesViewControllerDelegate: AnyObject {
    func groupAttributesDidUpdate()
}

// MARK: -

class GroupAttributesViewController: OWSTableViewController2 {

    public enum EditAction {
        case none
        case avatar
    }

    private weak var attributesDelegate: GroupAttributesViewControllerDelegate?

    private let groupThread: TSGroupThread

    private let helper: GroupAttributesEditorHelper

    private var editAction: EditAction?

    private var hasUnsavedChanges: Bool {
        return helper.hasUnsavedChanges
    }

    public required init(groupThread: TSGroupThread,
                         editAction: EditAction,
                         delegate: GroupAttributesViewControllerDelegate) {
        self.groupThread = groupThread
        self.editAction = editAction
        self.attributesDelegate = delegate

        self.helper = GroupAttributesEditorHelper(groupModel: groupThread.groupModel, renderDefaultAvatarWhenCleared: true)

        super.init()
    }

    // MARK: - View Lifecycle

    public override func viewDidLoad() {
        super.viewDidLoad()

        view.backgroundColor = Theme.backgroundColor

        title = OWSLocalizedString("EDIT_GROUP_DEFAULT_TITLE", comment: "The navbar title for the 'update group' view.")

        defaultSeparatorInsetLeading = Self.cellHInnerMargin + 24 + OWSTableItem.iconSpacing

        helper.delegate = self
        helper.buildContents()

        updateTableContents()
    }

    func updateTableContents() {
        let contents = OWSTableContents()

        let avatarSection = OWSTableSection()
        avatarSection.hasBackground = false
        avatarSection.add(.init(
            customCellBlock: { [weak self] in
                let cell = OWSTableItem.newCell()
                cell.selectionStyle = .none
                guard let self = self else { return cell }
                cell.contentView.addSubview(self.helper.avatarWrapper)
                self.helper.avatarWrapper.autoPinHeightToSuperviewMargins()
                self.helper.avatarWrapper.autoHCenterInSuperview()
                return cell
            },
            actionBlock: { [weak self] in
                self?.didTapAvatarView()
            }
        ))
        contents.add(avatarSection)

        let nameAndDescriptionSection = OWSTableSection()
        nameAndDescriptionSection.add(.disclosureItem(
            icon: .groupInfoEditName,
            name: helper.groupNameCurrent ?? OWSLocalizedString(
                "GROUP_NAME_VIEW_TITLE",
                comment: "Title for the group name view."
            ),
            accessibilityIdentifier: UIView.accessibilityIdentifier(in: self, name: "group_name"),
            actionBlock: { [weak self] in
                guard let self = self else { return }
                let vc = GroupNameViewController(
                    groupModel: self.groupThread.groupModel,
                    groupNameCurrent: self.helper.groupNameCurrent
                )
                vc.nameDelegate = self
                self.presentFormSheet(OWSNavigationController(rootViewController: vc), animated: true)
            }
        ))
        nameAndDescriptionSection.add(.disclosureItem(
            icon: .groupInfoEditDescription,
            name: helper.groupDescriptionCurrent ?? OWSLocalizedString(
                "GROUP_DESCRIPTION_VIEW_TITLE",
                comment: "Title for the group description view."
            ),
            maxNameLines: 2,
            accessibilityIdentifier: UIView.accessibilityIdentifier(in: self, name: "group_description"),
            actionBlock: { [weak self] in
                guard let self = self else { return }
                let vc = GroupDescriptionViewController(
                    groupModel: self.groupThread.groupModel,
                    groupDescriptionCurrent: self.helper.groupDescriptionCurrent,
                    options: .editable
                )
                vc.descriptionDelegate = self
                self.presentFormSheet(OWSNavigationController(rootViewController: vc), animated: true)
            }
        ))
        contents.add(nameAndDescriptionSection)

        self.contents = contents
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)

        if let editAction = self.editAction {
            switch editAction {
            case .none:
                break
            case .avatar:
                helper.showAvatarUI()
            }
            self.editAction = nil
        }
    }

    // MARK: -

    fileprivate func updateNavbar() {
        if helper.hasUnsavedChanges {
            navigationItem.rightBarButtonItem = UIBarButtonItem(
                title: CommonStrings.setButton,
                style: .done,
                target: self,
                action: #selector(setButtonPressed),
                accessibilityIdentifier: "set_button"
            )
        } else {
            navigationItem.rightBarButtonItem = nil
        }
    }

    @objc
    private func setButtonPressed() {
        updateGroupThreadAndDismiss()
    }

    // MARK: - Events

    @objc
    private func didTapAvatarView() {
        helper.didTapAvatarView()
    }
}

// MARK: -

extension GroupAttributesViewController {

    public var shouldCancelNavigationBack: Bool {
        let result = hasUnsavedChanges
        if result {
            GroupAttributesViewController.showUnsavedGroupChangesActionSheet(from: self,
                                                                             saveBlock: {
                                                                                self.updateGroupThreadAndDismiss()
            }, discardBlock: {
                self.navigationController?.popViewController(animated: true)
            })
        }
        return result
    }

    public static func showUnsavedGroupChangesActionSheet(
        from fromViewController: UIViewController,
        saveBlock: @escaping () -> Void,
        discardBlock: @escaping () -> Void
    ) {
        let actionSheet = ActionSheetController(title: OWSLocalizedString("EDIT_GROUP_VIEW_UNSAVED_CHANGES_TITLE",
                                                                         comment: "The alert title if user tries to exit update group view without saving changes."),
                                                message: OWSLocalizedString("EDIT_GROUP_VIEW_UNSAVED_CHANGES_MESSAGE",
                                                                          comment: "The alert message if user tries to exit update group view without saving changes."))
        actionSheet.addAction(ActionSheetAction(title: CommonStrings.saveButton,
                                                accessibilityIdentifier: UIView.accessibilityIdentifier(in: fromViewController, name: "save"),
                                                style: .default) { _ in
                                                    saveBlock()
        })
        actionSheet.addAction(ActionSheetAction(title: OWSLocalizedString("ALERT_DONT_SAVE",
                                                                         comment: "The label for the 'don't save' button in action sheets."),
                                                accessibilityIdentifier: UIView.accessibilityIdentifier(in: fromViewController, name: "dont_save"),
                                                style: .destructive) { _ in
                                                    discardBlock()
        })
        fromViewController.presentActionSheet(actionSheet)
    }
}

// MARK: -

private extension GroupAttributesViewController {
    func updateGroupThreadAndDismiss() {
        helper.updateGroupIfNecessary(fromViewController: self) { [weak self] in
            self?.attributesDelegate?.groupAttributesDidUpdate()
            self?.navigationController?.popViewController(animated: true)
        }
    }
}

// MARK: -

extension GroupAttributesViewController: GroupAttributesEditorHelperDelegate {
    func groupAttributesEditorContentsDidChange() {
        updateNavbar()
    }

    func groupAttributesEditorSelectionDidChange() {}
}

extension GroupAttributesViewController: GroupDescriptionViewControllerDelegate {
    func groupDescriptionViewControllerDidComplete(groupDescription: String?) {
        helper.groupDescriptionCurrent = groupDescription
        updateNavbar()
        updateTableContents()
    }
}

extension GroupAttributesViewController: GroupNameViewControllerDelegate {
    func groupNameViewControllerDidComplete(groupName: String?) {
        helper.groupNameCurrent = groupName
        updateNavbar()
        updateTableContents()
    }
}
