//
//  Copyright (c) 2020 Open Whisper Systems. All rights reserved.
//

import Foundation
import PromiseKit
import UIKit

protocol GroupAttributesViewControllerDelegate: class {
    func groupAttributesDidUpdate(groupName: String?, groupAvatar: GroupAvatar?)
}

// MARK: -

struct GroupAvatar {
    let imageData: Data
    let image: UIImage

    static func build(imageData: Data?) -> GroupAvatar? {
        guard let imageData = imageData else {
            return nil
        }
        guard (imageData as NSData).ows_isValidImage() else {
            owsFailDebug("Invalid image data.")
            return nil
        }
        guard let image = UIImage(data: imageData) else {
            owsFailDebug("Could not load image.")
            return nil
        }
        return GroupAvatar(imageData: imageData, image: image)
    }

    static func build(image: UIImage?) -> GroupAvatar? {
        guard let image = image else {
            return nil
        }
        guard let imageData = TSGroupModel.data(forGroupAvatar: image) else {
            owsFailDebug("Invalid image.")
            return nil
        }
        return GroupAvatar(imageData: imageData, image: image)
    }
}

// MARK: -

class GroupAttributesViewController: OWSViewController {

    // MARK: - Dependencies

    fileprivate var databaseStorage: SDSDatabaseStorage {
        return SDSDatabaseStorage.shared
    }

    fileprivate var tsAccountManager: TSAccountManager {
        return .sharedInstance()
    }

    // MARK: -

    public enum EditAction {
        case none
        case name
        case avatar
    }

    private weak var delegate: GroupAttributesViewControllerDelegate?

    private let groupThread: TSGroupThread

    private let avatarViewHelper = AvatarViewHelper()

    private var avatarView: UIImageView?

    private var editAction: EditAction?

    private let iconViewSize: UInt = kLargeAvatarSize

    private let avatarImageView = UIImageView()

    private let cameraButton = GroupAttributesViewController.buildCameraButton()

    private let nameTextField = UITextField()

    private var groupNameOriginal: String?

    private var groupNameCurrent: String? {
        return nameTextField.text?.filterStringForDisplay()
    }

    private var avatarOriginal: GroupAvatar?

    private var avatarCurrent: GroupAvatar?

    private var hasUnsavedChanges: Bool {
        return (groupNameOriginal != groupNameCurrent ||
                avatarOriginal?.imageData != avatarCurrent?.imageData)
    }

    public required init(groupThread: TSGroupThread,
                         editAction: EditAction,
                         delegate: GroupAttributesViewControllerDelegate) {
        self.groupThread = groupThread
        self.editAction = editAction
        self.delegate = delegate

        super.init(nibName: nil, bundle: nil)

        avatarViewHelper.delegate = self

        groupNameOriginal = groupThread.groupModel.groupName?.filterStringForDisplay()

        avatarOriginal = GroupAvatar.build(imageData: groupThread.groupModel.groupAvatarData)
        avatarCurrent = avatarOriginal
    }

    @available(*, unavailable, message:"use other constructor instead.")
    @objc
    public required init(coder aDecoder: NSCoder) {
        notImplemented()
    }

    // MARK: - View Lifecycle

    @objc
    public override func viewDidLoad() {
        super.viewDidLoad()

        view.backgroundColor = Theme.backgroundColor

        title = NSLocalizedString("EDIT_GROUP_DEFAULT_TITLE", comment: "The navbar title for the 'update group' view.")

        // We need to specify a contentMode since the size of the image
        // might not match the aspect ratio of the view.
        avatarImageView.contentMode = .scaleAspectFill
        // Use trilinear filters for better scaling quality at
        // some performance cost.
        avatarImageView.layer.minificationFilter = .trilinear
        avatarImageView.layer.magnificationFilter = .trilinear
        updateAvatarView(groupAvatar: avatarCurrent)
        avatarImageView.layer.cornerRadius = CGFloat(iconViewSize) * 0.5
        avatarImageView.clipsToBounds = true
        avatarImageView.autoSetDimensions(to: CGSize(width: CGFloat(iconViewSize),
                                                     height: CGFloat(iconViewSize)))
        avatarImageView.isUserInteractionEnabled = true
        avatarImageView.addGestureRecognizer(UITapGestureRecognizer(target: self,
                                                              action: #selector(didTapAvatarView)))

        let avatarWrapper = UIView.container()
        avatarWrapper.addSubview(avatarImageView)
        avatarImageView.autoPinEdgesToSuperviewEdges()

        avatarWrapper.addSubview(cameraButton)
        cameraButton.autoPinEdge(toSuperviewEdge: .trailing)
        cameraButton.autoPinEdge(toSuperviewEdge: .bottom)

        let avatarStack = UIStackView(arrangedSubviews: [ avatarWrapper ])
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

        nameTextField.text = groupNameOriginal
        nameTextField.font = .ows_dynamicTypeBody
        nameTextField.backgroundColor = .clear
        nameTextField.textColor = Theme.primaryTextColor
        nameTextField.textAlignment = CurrentAppContext().isRTL ? .left : .right
        nameTextField.addTarget(self, action: #selector(textFieldDidChange), for: .editingChanged)
        nameTextField.placeholder = NSLocalizedString("NEW_GROUP_NAMEGROUP_REQUEST_DEFAULT",
                                                      comment: "Placeholder text for group name field")
        nameTextField.setCompressionResistanceHorizontalLow()

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

    public static func buildCameraButton() -> UIView {
        let cameraImageView = UIImageView()
        cameraImageView.setTemplateImageName("camera-outline-24", tintColor: .ows_gray45)
        let cameraWrapper = UIView.container()
        cameraWrapper.backgroundColor = .ows_white
        cameraWrapper.addSubview(cameraImageView)
        cameraImageView.autoCenterInSuperview()
        let wrapperSize: CGFloat = 32
        cameraWrapper.layer.shadowColor = UIColor.ows_black.cgColor
        cameraWrapper.layer.shadowOpacity = 0.5
        cameraWrapper.layer.shadowRadius = 4
        cameraWrapper.layer.shadowOffset = CGSize(width: 0, height: 4)
        cameraWrapper.layer.cornerRadius = wrapperSize * 0.5
        cameraWrapper.autoSetDimensions(to: CGSize(width: wrapperSize, height: wrapperSize))
        return cameraWrapper
    }

    private func updateAvatarView(groupAvatar: GroupAvatar?) {
        if let groupAvatar = groupAvatar {
            avatarImageView.image = groupAvatar.image
            cameraButton.isHidden = true
        } else {
            avatarImageView.image = OWSGroupAvatarBuilder(thread: groupThread, diameter: iconViewSize).buildDefaultImage()
            cameraButton.isHidden = false
        }
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)

        if let editAction = self.editAction {
            switch editAction {
            case .none, .name:
                nameTextField.becomeFirstResponder()
            case .avatar:
                showAvatarUI()
            }
            self.editAction = nil
        }
    }

    // MARK: -

    private func updateNavbar() {
        if hasUnsavedChanges {
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
    func textFieldDidChange(_ textField: UITextField) {
        updateNavbar()
    }

    @objc
    func didTapAvatarView(sender: UIGestureRecognizer) {
        showAvatarUI()
    }

    private func showAvatarUI() {
        nameTextField.resignFirstResponder()
        avatarViewHelper.showChangeAvatarUI()
    }
}

// MARK: -

extension GroupAttributesViewController: AvatarViewHelperDelegate {
    func avatarActionSheetTitle() -> String? {
        return NSLocalizedString("NEW_GROUP_ADD_PHOTO_ACTION", comment: "Action Sheet title prompting the user for a group avatar")
    }

    private func setAvatarImage(_ image: UIImage?) {
        let groupAvatar: GroupAvatar? = {
            guard let image = image else {
                return nil
            }
            guard let groupAvatar = GroupAvatar.build(image: image) else {
                OWSActionSheets.showErrorAlert(message: NSLocalizedString("EDIT_GROUP_ERROR_INVALID_AVATAR",
                                                                          comment: "Error message indicating that an avatar image is invalid and cannot be used."))
                owsFailDebug("Invalid image.")
                return nil
            }
            return groupAvatar
        }()
        avatarCurrent = groupAvatar
        updateAvatarView(groupAvatar: avatarCurrent)
        updateNavbar()
    }

    func avatarDidChange(_ image: UIImage) {
        setAvatarImage(image)
    }

    func fromViewController() -> UIViewController {
        return self
    }

    func hasClearAvatarAction() -> Bool {
        return true
    }

    func clearAvatar() {
        setAvatarImage(nil)
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

        let groupNameCurrent: String? = self.groupNameCurrent
        let avatarCurrent: GroupAvatar? = self.avatarCurrent

        let dismissAndUpdateDelegate = { [weak self] in
            guard let self = self else {
                return
            }
            if let delegate = self.delegate {
                delegate.groupAttributesDidUpdate(groupName: groupNameCurrent, groupAvatar: avatarCurrent)
            }
            self.navigationController?.popViewController(animated: true)
        }

        guard hasUnsavedChanges else {
            owsFailDebug("!hasUnsavedChanges.")
            return dismissAndUpdateDelegate()
        }

        let groupThread = self.groupThread
        let oldGroupModel = groupThread.groupModel
        guard let newGroupModel = buildNewGroupModel(groupName: groupNameCurrent,
                                                     groupAvatar: avatarCurrent) else {
                                                        let error = OWSAssertionError("Couldn't build group model.")
                                                        GroupViewUtils.showUpdateErrorUI(error: error)
            return
        }
        GroupViewUtils.updateGroupWithActivityIndicator(fromViewController: self,
                                                        updatePromiseBlock: {
                                                            self.updateGroupThreadPromise(oldGroupModel: oldGroupModel,
                                                                newGroupModel: newGroupModel)
        },
                                                        completion: {
            dismissAndUpdateDelegate()
        })
    }

    func updateGroupThreadPromise(oldGroupModel: TSGroupModel,
                                  newGroupModel: TSGroupModel) -> Promise<Void> {

        guard let localAddress = tsAccountManager.localAddress else {
            return Promise(error: OWSAssertionError("Missing localAddress."))
        }

        return firstly { () -> Promise<Void> in
            return GroupManager.messageProcessingPromise(for: oldGroupModel,
                                                         description: self.logTag)
        }.then(on: .global()) { _ in
            // dmConfiguration: nil means don't change disappearing messages configuration.
            GroupManager.localUpdateExistingGroup(groupModel: newGroupModel,
                                                  dmConfiguration: nil,
                                                  groupUpdateSourceAddress: localAddress)
        }.asVoid()
    }
}
