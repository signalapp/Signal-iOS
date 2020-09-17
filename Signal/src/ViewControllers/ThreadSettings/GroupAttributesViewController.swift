//
//  Copyright (c) 2020 Open Whisper Systems. All rights reserved.
//

import Foundation
import PromiseKit
import UIKit

protocol GroupAttributesViewControllerDelegate: class {
    func groupAttributesDidUpdate()
}

// MARK: -

class GroupAttributesViewController: OWSViewController {

    public enum EditAction {
        case none
        case name
        case avatar
    }

    private weak var delegate: GroupAttributesViewControllerDelegate?

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
        self.delegate = delegate

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

        let avatarStack = UIStackView(arrangedSubviews: [ helper.avatarWrapper ])
        avatarStack.axis = .vertical
        avatarStack.spacing = 10
        avatarStack.alignment = .center
        avatarStack.isUserInteractionEnabled = true
        avatarStack.addGestureRecognizer(UITapGestureRecognizer(target: self,
                                                                action: #selector(didTapAvatarView)))
        avatarStack.layoutMargins = UIEdgeInsets(top: 12, leading: 18, bottom: 18, trailing: 28)
        avatarStack.isLayoutMarginsRelativeArrangement = true

        let nameLabel = UILabel()
        nameLabel.text = NSLocalizedString("EDIT_GROUP_GROUP_NAME",
                                           comment: "Label for the group name in the 'edit group' view.")
        nameLabel.font = .ows_dynamicTypeBody
        nameLabel.textColor = Theme.primaryTextColor
        nameLabel.setCompressionResistanceHorizontalHigh()
        nameLabel.setContentHuggingHorizontalHigh()

        nameTextField.setCompressionResistanceHorizontalLow()
        nameTextField.textAlignment = CurrentAppContext().isRTL ? .left : .right

        let nameStack = UIStackView(arrangedSubviews: [ nameLabel, nameTextField ])
        nameStack.axis = .horizontal
        nameStack.spacing = 10
        nameStack.alignment = .center
        nameStack.distribution = .fill
        nameStack.layoutMargins = UIEdgeInsets(top: 12, leading: 18, bottom: 18, trailing: 12)
        nameStack.isLayoutMarginsRelativeArrangement = true

        let makeHairlineSeparator = { () -> UIView in
            let seperator = UIView.container()
            seperator.backgroundColor = Theme.secondaryBackgroundColor
            seperator.autoSetDimension(.height, toSize: 1)
            seperator.setContentHuggingHorizontalLow()
            return seperator
        }

        let stackView = UIStackView(arrangedSubviews: [ avatarStack,
                                                        makeHairlineSeparator(),
                                                        nameStack,
                                                        makeHairlineSeparator(),
                                                        UIView.vStretchingSpacer() ])
        stackView.axis = .vertical
        nameStack.alignment = .fill
        view.addSubview(stackView)
        stackView.autoPin(toTopLayoutGuideOf: self, withInset: 0)
        stackView.autoPinEdge(toSuperviewEdge: .leading)
        stackView.autoPinEdge(toSuperviewEdge: .trailing)
        stackView.autoPinEdge(toSuperviewEdge: .bottom)
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
    func didTapAvatarView(sender: UIGestureRecognizer) {
        helper.didTapAvatarView(sender: sender)
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
            guard let self = self else {
                return
            }
            if let delegate = self.delegate {
                delegate.groupAttributesDidUpdate()
            }
            self.navigationController?.popViewController(animated: true)
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
