//
// Copyright 2020 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import SignalMessaging
import SignalUI

protocol GroupAttributesEditorHelperDelegate: AnyObject {
    func groupAttributesEditorContentsDidChange()
    func groupAttributesEditorSelectionDidChange()
    func presentFormSheet(_ viewControllerToPresent: UIViewController, animated: Bool, completion: (() -> Void)?)
}

// MARK: -

// A helper class used to DRY up the common views/logic
// used when editing group names & avatars in the
// "create new group" and "edit group" views.
class GroupAttributesEditorHelper: NSObject {

    public enum EditAction {
        case none
        case name
        case avatar
    }

    weak var delegate: GroupAttributesEditorHelperDelegate?

    private let groupModelOriginal: TSGroupModel?

    private let groupId: Data

    private var avatarView: UIImageView?

    let avatarWrapper = UIView.container()

    private let avatarImageView = UIImageView()

    private let iconViewSize: UInt

    private let cameraButton = GroupAttributesEditorHelper.buildCameraButtonForCenter()
    private let cameraCornerButton = GroupAttributesEditorHelper.buildCameraButtonForCorner()

    let nameTextField = UITextField()

    var groupNameOriginal: String?

    var groupNameCurrent: String? {
        get { nameTextField.text?.nilIfEmpty?.filterStringForDisplay() }
        set { nameTextField.text = newValue?.nilIfEmpty?.filterStringForDisplay() }
    }

    let descriptionTextView = TextViewWithPlaceholder()

    var groupDescriptionOriginal: String?

    var groupDescriptionCurrent: String? {
        get { descriptionTextView.text?.nilIfEmpty?.filterStringForDisplay() }
        set { descriptionTextView.text = newValue?.nilIfEmpty?.filterStringForDisplay() }
    }

    private var avatarOriginal: GroupAvatar?

    var avatarCurrent: GroupAvatar?

    private let renderDefaultAvatarWhenCleared: Bool

    var hasUnsavedChanges: Bool {
        return (groupNameOriginal != groupNameCurrent ||
                    groupDescriptionOriginal != groupDescriptionCurrent ||
                    avatarOriginal?.imageData != avatarCurrent?.imageData)
    }

    public convenience init(
        groupModel: TSGroupModel,
        iconViewSize: UInt = AvatarBuilder.largeAvatarSizePoints,
        renderDefaultAvatarWhenCleared: Bool = false
    ) {
        self.init(
            groupModelOriginal: groupModel,
            groupId: groupModel.groupId,
            groupNameOriginal: groupModel.groupName,
            groupDescriptionOriginal: (groupModel as? TSGroupModelV2)?.descriptionText,
            avatarOriginalData: groupModel.avatarData,
            iconViewSize: iconViewSize,
            renderDefaultAvatarWhenCleared: renderDefaultAvatarWhenCleared
        )
    }

    public required init(
        groupModelOriginal: TSGroupModel? = nil,
        groupId: Data,
        groupNameOriginal: String?,
        groupDescriptionOriginal: String? = nil,
        avatarOriginalData: Data?,
        iconViewSize: UInt,
        renderDefaultAvatarWhenCleared: Bool = false
    ) {
        self.groupModelOriginal = groupModelOriginal
        self.groupId = groupId
        self.groupNameOriginal = groupNameOriginal?.nilIfEmpty?.filterStringForDisplay()
        self.groupDescriptionOriginal = groupDescriptionOriginal?.nilIfEmpty?.filterStringForDisplay()
        self.avatarOriginal = GroupAvatar.build(imageData: avatarOriginalData)
        self.avatarCurrent = avatarOriginal
        self.iconViewSize = iconViewSize
        self.renderDefaultAvatarWhenCleared = renderDefaultAvatarWhenCleared

        super.init()
    }

    // MARK: -

    func buildContents() {
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

        avatarWrapper.addSubview(cameraCornerButton)
        cameraCornerButton.autoPinEdge(toSuperviewEdge: .trailing)
        cameraCornerButton.autoPinEdge(toSuperviewEdge: .bottom)

        nameTextField.text = groupNameOriginal
        nameTextField.font = .dynamicTypeBody
        nameTextField.backgroundColor = .clear
        nameTextField.textColor = Theme.primaryTextColor
        nameTextField.delegate = self
        nameTextField.addTarget(self, action: #selector(textFieldDidChange), for: .editingChanged)
        nameTextField.placeholder = OWSLocalizedString("GROUP_NAME_PLACEHOLDER",
                                                      comment: "Placeholder text for 'group name' field.")

        descriptionTextView.text = groupDescriptionOriginal
        descriptionTextView.delegate = self
        descriptionTextView.placeholderText = OWSLocalizedString("GROUP_DESCRIPTION_PLACEHOLDER",
                                                                comment: "Placeholder text for 'group description' field.")
    }

    public static func buildCameraButtonForCorner() -> UIView {
        let cameraImageContainer = UIView()
        cameraImageContainer.autoSetDimensions(to: CGSize.square(32))
        cameraImageContainer.backgroundColor = Theme.isDarkThemeEnabled ? .ows_gray15 : UIColor(rgbHex: 0xf8f9f9)
        cameraImageContainer.layer.cornerRadius = 16

        cameraImageContainer.layer.shadowColor = UIColor.black.cgColor
        cameraImageContainer.layer.shadowOpacity = 0.2
        cameraImageContainer.layer.shadowRadius = 4
        cameraImageContainer.layer.shadowOffset = CGSize(width: 0, height: 2)

        let secondaryShadowView = UIView()
        secondaryShadowView.layer.shadowColor = UIColor.black.cgColor
        secondaryShadowView.layer.shadowOpacity = 0.12
        secondaryShadowView.layer.shadowRadius = 16
        secondaryShadowView.layer.shadowOffset = CGSize(width: 0, height: 4)

        cameraImageContainer.addSubview(secondaryShadowView)
        secondaryShadowView.autoPinEdgesToSuperviewEdges()

        let cameraImageView = UIImageView(image: Theme.iconImage(.buttonCamera))
        cameraImageView.tintColor = Theme.isDarkThemeEnabled ? .ows_gray80 : .ows_black
        cameraImageView.autoSetDimensions(to: CGSize.square(20))
        cameraImageView.contentMode = .scaleAspectFit

        cameraImageContainer.addSubview(cameraImageView)
        cameraImageView.autoCenterInSuperview()

        return cameraImageContainer
    }

    public static func buildCameraButtonForCenter() -> UIView {
        let cameraImageView = UIImageView()
        cameraImageView.setTemplateImageName("camera", tintColor: Theme.primaryIconColor)
        let iconSize: CGFloat = 32
        cameraImageView.autoSetDimensions(to: CGSize(square: iconSize))
        return cameraImageView
    }

    private func updateAvatarView(groupAvatar: GroupAvatar?) {
        if let groupAvatar = groupAvatar {
            avatarImageView.image = groupAvatar.image
            avatarImageView.layer.borderWidth = 0
            avatarImageView.layer.borderColor = nil
            cameraButton.isHidden = true
            cameraCornerButton.isHidden = false
        } else if renderDefaultAvatarWhenCleared {
            avatarImageView.image = avatarBuilder.avatarImage(forGroupId: groupId, diameterPoints: iconViewSize)
            avatarImageView.layer.borderWidth = 0
            avatarImageView.layer.borderColor = nil
            cameraButton.isHidden = true
            cameraCornerButton.isHidden = false
        } else {
            avatarImageView.image = nil
            avatarImageView.layer.borderWidth = 2
            avatarImageView.layer.borderColor = Theme.outlineColor.cgColor
            cameraButton.isHidden = false
            cameraCornerButton.isHidden = true
        }
    }

    func setAvatarImage(_ image: UIImage?) {
        let groupAvatar: GroupAvatar? = {
            guard let image = image else {
                return nil
            }
            guard let groupAvatar = GroupAvatar.build(image: image) else {
                OWSActionSheets.showErrorAlert(message: OWSLocalizedString("EDIT_GROUP_ERROR_INVALID_AVATAR",
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
    private func textFieldDidChange(_ textField: UITextField) {
        delegate?.groupAttributesEditorContentsDidChange()
    }

    @objc
    func didTapAvatarView() {
        showAvatarUI()
    }

    func showAvatarUI() {
        nameTextField.resignFirstResponder()
        descriptionTextView.resignFirstResponder()

        let vc = AvatarSettingsViewController(
            context: .groupId(groupId),
            currentAvatarImage: avatarCurrent?.image
        ) { [weak self] newAvatarImage in
            self?.setAvatarImage(newAvatarImage)
        }

        delegate?.presentFormSheet(OWSNavigationController(rootViewController: vc), animated: true, completion: nil)
    }

    // MARK: - update

    func updateGroupIfNecessary(fromViewController: UIViewController, completion: @escaping () -> Void) {
        nameTextField.acceptAutocorrectSuggestion()
        descriptionTextView.acceptAutocorrectSuggestion()

        guard !groupNameCurrent.isEmptyOrNil else {
            NewGroupConfirmViewController.showMissingGroupNameAlert()
            return
        }

        guard hasUnsavedChanges else {
            owsFailDebug("!hasUnsavedChanges.")
            return completion()
        }

        guard let oldGroupModel = groupModelOriginal else {
            GroupViewUtils.showUpdateErrorUI(error: OWSAssertionError("Missing groupModelOriginal"))
            return
        }

        let currentTitle = groupNameCurrent
        let currentDescription = groupDescriptionCurrent
        let currentAvatarData = avatarCurrent?.imageData

        GroupViewUtils.updateGroupWithActivityIndicator(
            fromViewController: fromViewController,
            withGroupModel: oldGroupModel,
            updateDescription: self.logTag,
            updateBlock: {
                GroupManager.updateGroupAttributes(
                    title: currentTitle,
                    description: currentDescription,
                    avatarData: currentAvatarData,
                    inExistingGroup: oldGroupModel
                )
            },
            completion: { _ in completion() }
        )
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
        guard imageData.ows_isValidImage else {
            owsFailDebug("Invalid image data.")
            return nil
        }
        guard TSGroupModel.isValidGroupAvatarData(imageData) else {
            owsFailDebug("Invalid group avatar.")
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
        return build(imageData: imageData)
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
            maxGlyphCount: GroupManager.maxGroupNameGlyphCount
        )
    }
}

extension GroupAttributesEditorHelper: TextViewWithPlaceholderDelegate {
    func textViewDidUpdateText(_ textView: TextViewWithPlaceholder) {
        delegate?.groupAttributesEditorContentsDidChange()
    }

    func textViewDidUpdateSelection(_ textView: TextViewWithPlaceholder) {
        delegate?.groupAttributesEditorSelectionDidChange()
    }

    func textView(
        _ textView: TextViewWithPlaceholder,
        uiTextView: UITextView,
        shouldChangeTextIn range: NSRange,
        replacementText text: String
    ) -> Bool {
        // Truncate the replacement to fit.
        return TextViewHelper.textView(
            uiTextView,
            shouldChangeTextIn: range,
            replacementText: text,
            maxGlyphCount: GroupManager.maxGroupDescriptionGlyphCount
        )
    }
}
