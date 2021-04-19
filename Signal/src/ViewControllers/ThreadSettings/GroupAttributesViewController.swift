//
//  Copyright (c) 2021 Open Whisper Systems. All rights reserved.
//

import Foundation
import PromiseKit
import UIKit

protocol GroupAttributesViewControllerDelegate: class {
    func groupAttributesDidUpdate()
}

// MARK: -

class GroupAttributesViewController: OWSTableViewController2 {

    public enum EditAction {
        case none
        case name
        case avatar
    }

    private weak var attributesDelegate: GroupAttributesViewControllerDelegate?

    private let groupThread: TSGroupThread

    private let oldGroupModel: TSGroupModel

    private let helper: GroupAttributesEditorHelper

    private var editAction: EditAction?

    private var nameTextField: UITextField {
        return helper.nameTextField
    }

    private var hasUnsavedChanges: Bool {
        return helper.hasUnsavedChanges
    }

    public required init(groupThread: TSGroupThread,
                         editAction: EditAction,
                         delegate: GroupAttributesViewControllerDelegate) {
        self.groupThread = groupThread
        // Capture the group model before any changes are made
        // so that we can diff against it to determine the
        // user intent.
        self.oldGroupModel = groupThread.groupModel
        self.editAction = editAction
        self.attributesDelegate = delegate

        self.helper = GroupAttributesEditorHelper(groupId: groupThread.groupModel.groupId,
                                                  conversationColorName: groupThread.conversationColorName.rawValue,
                                                  groupNameOriginal: groupThread.groupModel.groupName,
                                                  avatarOriginalData: groupThread.groupModel.groupAvatarData,
                                                  iconViewSize: kLargeAvatarSize)

        super.init()
    }

    // MARK: - View Lifecycle

    @objc
    public override func viewDidLoad() {
        super.viewDidLoad()

        view.backgroundColor = Theme.backgroundColor

        title = NSLocalizedString("EDIT_GROUP_DEFAULT_TITLE", comment: "The navbar title for the 'update group' view.")

        helper.delegate = self
        helper.buildContents(avatarViewHelperDelegate: self)

        let cameraButton = GroupAttributesEditorHelper.buildCameraButtonForCorner()
        helper.avatarWrapper.addSubview(cameraButton)
        cameraButton.autoPinEdge(toSuperviewEdge: .trailing)
        cameraButton.autoPinEdge(toSuperviewEdge: .bottom)

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
        contents.addSection(avatarSection)

        let nameSection = OWSTableSection()
        nameSection.add(.init(
            customCellBlock: { [weak self] in
                let cell = OWSTableItem.newCell()
                cell.selectionStyle = .none
                guard let self = self else { return cell }

                self.nameTextField.font = .ows_dynamicTypeBodyClamped
                self.nameTextField.textColor = Theme.primaryTextColor

                cell.addSubview(self.nameTextField)
                self.nameTextField.autoPinEdgesToSuperviewMargins()

                return cell
            },
            actionBlock: { [weak self] in
                self?.nameTextField.becomeFirstResponder()
            }
        ))
        contents.addSection(nameSection)

        self.contents = contents
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)

        if let editAction = self.editAction {
            switch editAction {
            case .none, .name:
                nameTextField.becomeFirstResponder()
            case .avatar:
                helper.showAvatarUI()
            }
            self.editAction = nil
        }
    }

    // MARK: -

    fileprivate func updateNavbar() {
        if helper.hasUnsavedChanges {
            navigationItem.rightBarButtonItem = UIBarButtonItem(title: NSLocalizedString("EDIT_GROUP_UPDATE_BUTTON",
                                                                                          comment: "The title for the 'update group' button."),
                                                                style: .plain,
                                                                target: self,
                                                                action: #selector(updateGroupPressed),
                                                                accessibilityIdentifier: UIView.accessibilityIdentifier(in: self, name: "update"))
        } else {
            navigationItem.rightBarButtonItem = nil
        }
    }

    @objc func updateGroupPressed() {
        updateGroupThreadAndDismiss()
    }

    // MARK: - Events

    @objc
    func didTapAvatarView() {
        helper.didTapAvatarView()
    }
}

// MARK: -

extension GroupAttributesViewController: AvatarViewHelperDelegate {
    func avatarActionSheetTitle() -> String? {
        return NSLocalizedString("NEW_GROUP_ADD_PHOTO_ACTION", comment: "Action Sheet title prompting the user for a group avatar")
    }

    func avatarDidChange(_ image: UIImage) {
        helper.setAvatarImage(image)
    }

    func fromViewController() -> UIViewController {
        return self
    }

    func hasClearAvatarAction() -> Bool {
        return helper.avatarCurrent != nil
    }

    func clearAvatar() {
        helper.setAvatarImage(nil)
    }

    func clearAvatarActionLabel() -> String {
        return NSLocalizedString("EDIT_GROUP_CLEAR_AVATAR", comment: "The 'clear avatar' button in the 'edit group' view.")
    }
}

// MARK: -

extension GroupAttributesViewController: OWSNavigationView {

    public func shouldCancelNavigationBack() -> Bool {
        nameTextField.acceptAutocorrectSuggestion()

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

    @objc
    public static func showUnsavedGroupChangesActionSheet(from fromViewController: UIViewController,
                                                     saveBlock: @escaping () -> Void,
                                                     discardBlock: @escaping () -> Void) {
        let actionSheet = ActionSheetController(title: NSLocalizedString("EDIT_GROUP_VIEW_UNSAVED_CHANGES_TITLE",
                                                                         comment: "The alert title if user tries to exit update group view without saving changes."),
                                                message: NSLocalizedString("EDIT_GROUP_VIEW_UNSAVED_CHANGES_MESSAGE",
                                                                          comment: "The alert message if user tries to exit update group view without saving changes."))
        actionSheet.addAction(ActionSheetAction(title: NSLocalizedString("ALERT_SAVE",
                                                                         comment: "The label for the 'save' button in action sheets."),
                                                accessibilityIdentifier: UIView.accessibilityIdentifier(in: fromViewController, name: "save"),
                                                style: .default) { _ in
                                                    saveBlock()
        })
        actionSheet.addAction(ActionSheetAction(title: NSLocalizedString("ALERT_DONT_SAVE",
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

    func buildNewGroupModel(groupName: String?, groupAvatar: GroupAvatar?) -> TSGroupModel? {
        do {
            return try databaseStorage.read { transaction in
                var builder = self.groupThread.groupModel.asBuilder
                builder.name = groupName
                builder.avatarData = groupAvatar?.imageData
                return try builder.build(transaction: transaction)
            }
        } catch {
            owsFailDebug("Error: \(error)")
            return nil
        }
    }

    func updateGroupThreadAndDismiss() {

        guard let newGroupName = helper.groupNameCurrent,
            !newGroupName.isEmpty else {
                NewGroupConfirmViewController.showMissingGroupNameAlert()
                return
        }
        let avatarCurrent: GroupAvatar? = helper.avatarCurrent

        let dismissAndUpdateDelegate = { [weak self] in
            self?.attributesDelegate?.groupAttributesDidUpdate()
            self?.navigationController?.popViewController(animated: true)
        }

        guard hasUnsavedChanges else {
            owsFailDebug("!hasUnsavedChanges.")
            return dismissAndUpdateDelegate()
        }

        guard let newGroupModel = buildNewGroupModel(groupName: newGroupName,
                                                     groupAvatar: avatarCurrent) else {
                                                        let error = OWSAssertionError("Couldn't build group model.")
                                                        GroupViewUtils.showUpdateErrorUI(error: error)
            return
        }
        GroupViewUtils.updateGroupWithActivityIndicator(fromViewController: self,
                                                        updatePromiseBlock: {
                                                            self.updateGroupThreadPromise(newGroupModel: newGroupModel)
        },
                                                        completion: { _ in
            dismissAndUpdateDelegate()
        })
    }

    func updateGroupThreadPromise(newGroupModel: TSGroupModel) -> Promise<Void> {

        let oldGroupModel = self.oldGroupModel

        guard let localAddress = tsAccountManager.localAddress else {
            return Promise(error: OWSAssertionError("Missing localAddress."))
        }

        return firstly { () -> Promise<Void> in
            return GroupManager.messageProcessingPromise(for: oldGroupModel,
                                                         description: self.logTag)
        }.then(on: .global()) { _ in
            // dmConfiguration: nil means don't change disappearing messages configuration.
            GroupManager.localUpdateExistingGroup(oldGroupModel: oldGroupModel,
                                                  newGroupModel: newGroupModel,
                                                  dmConfiguration: nil,
                                                  groupUpdateSourceAddress: localAddress)
        }.asVoid()
    }
}

// MARK: -

extension GroupAttributesViewController: GroupAttributesEditorHelperDelegate {
    func groupAttributesEditorContentsDidChange() {
        updateNavbar()
    }
}
