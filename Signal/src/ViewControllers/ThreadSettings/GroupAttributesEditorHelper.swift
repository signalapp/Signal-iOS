//
//  Copyright (c) 2021 Open Whisper Systems. All rights reserved.
//

import Foundation
import PromiseKit
import UIKit

protocol GroupAttributesEditorHelperDelegate: class {
    func groupAttributesEditorContentsDidChange()
}

// MARK: -

// A helper class used to DRY up the common views/logic
// used when editing group names & avatars in the
// "create new group" and "edit group" views.
class GroupAttributesEditorHelper: NSObject {

    // MARK: - Dependencies

    fileprivate var databaseStorage: SDSDatabaseStorage {
        return SDSDatabaseStorage.shared
    }

    fileprivate var tsAccountManager: TSAccountManager {
        return .shared()
    }

    // MARK: -

    public enum EditAction {
        case none
        case name
        case avatar
    }

    weak var delegate: GroupAttributesEditorHelperDelegate?

    private let groupId: Data

    private let conversationColorName: String

    private let avatarViewHelper = AvatarViewHelper()

    private var avatarView: UIImageView?

    let avatarWrapper = UIView.container()

    private let avatarImageView = UIImageView()

    private let iconViewSize: UInt

    private let cameraButton = GroupAttributesEditorHelper.buildCameraButtonForCenter()

    let nameTextField = UITextField()

    private var groupNameOriginal: String?

    var groupNameCurrent: String? {
        return nameTextField.text?.filterStringForDisplay()
    }

    private var avatarOriginal: GroupAvatar?

    var avatarCurrent: GroupAvatar?

    var hasUnsavedChanges: Bool {
        return (groupNameOriginal != groupNameCurrent ||
                avatarOriginal?.imageData != avatarCurrent?.imageData)
    }

    public required init(groupId: Data,
                         conversationColorName: String,
                         groupNameOriginal: String?,
                         avatarOriginalData: Data?,
                         iconViewSize: UInt) {

        self.groupId = groupId
        self.conversationColorName = conversationColorName
        self.groupNameOriginal = groupNameOriginal?.filterStringForDisplay()
        self.avatarOriginal = GroupAvatar.build(imageData: avatarOriginalData)
        self.avatarCurrent = avatarOriginal
        self.iconViewSize = iconViewSize

        super.init()
    }

    // MARK: -

    func buildContents(avatarViewHelperDelegate: AvatarViewHelperDelegate) {

        avatarViewHelper.delegate = avatarViewHelperDelegate

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
        avatarImageView.autoSetDimensions(to: CGSize(square: CGFloat(iconViewSize)))
        avatarImageView.isUserInteractionEnabled = true
        avatarImageView.addGestureRecognizer(UITapGestureRecognizer(target: self,
                                                              action: #selector(didTapAvatarView)))

        avatarWrapper.addSubview(avatarImageView)
        avatarImageView.autoPinEdgesToSuperviewEdges()

        avatarWrapper.addSubview(cameraButton)
        cameraButton.autoCenterInSuperview()

        nameTextField.text = groupNameOriginal
        nameTextField.font = .ows_dynamicTypeBody
        nameTextField.backgroundColor = .clear
        nameTextField.textColor = Theme.primaryTextColor
        nameTextField.delegate = self
        nameTextField.addTarget(self, action: #selector(textFieldDidChange), for: .editingChanged)
        nameTextField.placeholder = NSLocalizedString("GROUP_NAME_PLACEHOLDER",
                                                      comment: "Placeholder text for 'group name' field.")
    }

    public static func buildCameraButtonForCorner() -> UIView {
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
        cameraWrapper.autoSetDimensions(to: CGSize(square: wrapperSize))
        return cameraWrapper
    }

    public static func buildCameraButtonForCenter() -> UIView {
        let cameraImageView = UIImageView()
        cameraImageView.setTemplateImageName("camera-outline-24", tintColor: Theme.accentBlueColor)
        let iconSize: CGFloat = 32
        cameraImageView.autoSetDimensions(to: CGSize(square: iconSize))
        return cameraImageView
    }

    private func updateAvatarView(groupAvatar: GroupAvatar?) {
        if let groupAvatar = groupAvatar {
            avatarImageView.image = groupAvatar.image
            avatarImageView.backgroundColor = nil
            cameraButton.isHidden = true
        } else {
            avatarImageView.image = nil
            avatarImageView.backgroundColor = Theme.washColor
            cameraButton.isHidden = false
        }
    }

    func setAvatarImage(_ image: UIImage?) {
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

        delegate?.groupAttributesEditorContentsDidChange()
    }

    // MARK: - Events

    @objc
    func textFieldDidChange(_ textField: UITextField) {
        delegate?.groupAttributesEditorContentsDidChange()
    }

    @objc
    func didTapAvatarView(sender: UIGestureRecognizer) {
        showAvatarUI()
    }

    func showAvatarUI() {
        nameTextField.resignFirstResponder()
        avatarViewHelper.showChangeAvatarUI()
    }
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

// MARK: 

extension GroupAttributesEditorHelper: UITextFieldDelegate {
    public func textField(_ textField: UITextField, shouldChangeCharactersIn range: NSRange, replacementString: String) -> Bool {
        // Truncate the replacement to fit.
        return TextFieldHelper.textField(
            textField,
            shouldChangeCharactersInRange: range,
            replacementString: replacementString.withoutBidiControlCharacters,
            stringLengthLimit: .characterCount(maxCharacterCount: GroupManager.maxGroupNameCharactersCount)
        )
    }
}
