//
//  Copyright (c) 2020 Open Whisper Systems. All rights reserved.
//

import Foundation
import UIKit
import PromiseKit

@objc
public class GroupInviteLinksUI: UIView {

    @available(*, unavailable, message:"Do not instantiate this class.")
    required init(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    @objc
    public static func openGroupInviteLink(_ url: URL,
                                           fromViewController: UIViewController) {
        AssertIsOnMainThread()

        let showInvalidInviteLinkAlert = {
            OWSActionSheets.showActionSheet(title: NSLocalizedString("GROUP_LINK_INVALID_GROUP_INVITE_LINK_ERROR_TITLE",
                                                                     comment: "Title for the 'invalid group invite link' alert."),
                                            message: NSLocalizedString("GROUP_LINK_INVALID_GROUP_INVITE_LINK_ERROR_MESSAGE",
                                                                      comment: "Message for the 'invalid group invite link' alert."))
        }

        guard let groupInviteLinkInfo = GroupManager.parseGroupInviteLink(url) else {
            owsFailDebug("Invalid group invite link.")
            showInvalidInviteLinkAlert()
            return
        }

        let groupV2ContextInfo: GroupV2ContextInfo
        do {
            groupV2ContextInfo = try self.groupsV2.groupV2ContextInfo(forMasterKeyData: groupInviteLinkInfo.masterKey)
        } catch {
            owsFailDebug("Error: \(error)")
            showInvalidInviteLinkAlert()
            return
        }

        // If the group already exists in the database, open it.
        if let existingGroupThread = (databaseStorage.read { transaction in
            TSGroupThread.fetch(groupId: groupV2ContextInfo.groupId, transaction: transaction)
        }), existingGroupThread.isLocalUserFullMember || existingGroupThread.isLocalUserRequestingMember {
            SignalApp.shared().presentConversation(for: existingGroupThread, animated: true)
            return
        }

        let actionSheet = GroupInviteLinksActionSheet(groupInviteLinkInfo: groupInviteLinkInfo,
                                                      groupV2ContextInfo: groupV2ContextInfo)
        fromViewController.presentActionSheet(actionSheet)
    }
}

// MARK: -

class GroupInviteLinksActionSheet: ActionSheetController {

    private let groupInviteLinkInfo: GroupInviteLinkInfo
    private let groupV2ContextInfo: GroupV2ContextInfo

    private let avatarView = AvatarImageView()
    private let groupTitleLabel = UILabel()
    private let groupSubtitleLabel = UILabel()

    private var groupInviteLinkPreview: GroupInviteLinkPreview?
    private var avatarData: Data?

    init(groupInviteLinkInfo: GroupInviteLinkInfo, groupV2ContextInfo: GroupV2ContextInfo) {
        self.groupInviteLinkInfo = groupInviteLinkInfo
        self.groupV2ContextInfo = groupV2ContextInfo

        super.init(theme: .default)

        isCancelable = true

        createContents()

        loadDefaultContent()
        loadLinkPreview()
    }

    private static let avatarSize: UInt = 112

    private let messageLabel = UILabel()

    private var cancelButton: UIView?
    private var joinButton: UIView?
    private var invalidOkayButton: UIView?

    private func createContents() {

        let header = UIView()
        header.layoutMargins = UIEdgeInsets(top: 20, leading: 20, bottom: 20, trailing: 20)
        header.backgroundColor = Theme.backgroundColor
        self.customHeader = header

        avatarView.autoSetDimension(.width, toSize: CGFloat(Self.avatarSize))

        groupTitleLabel.font = UIFont.ows_dynamicTypeBody.ows_semibold
        groupTitleLabel.textColor = Theme.primaryTextColor

        groupSubtitleLabel.font = UIFont.ows_dynamicTypeSubheadline
        groupSubtitleLabel.textColor = Theme.primaryTextColor

        let headerStack = UIStackView(arrangedSubviews: [
            avatarView,
            UIView.spacer(withHeight: 10),
            groupTitleLabel,
            groupSubtitleLabel
        ])
        headerStack.axis = .vertical
        headerStack.alignment = .center

        messageLabel.text = NSLocalizedString("GROUP_LINK_ACTION_SHEET_VIEW_MESSAGE",
                                              comment: "Message text for the 'group invite link' action sheet.")
        messageLabel.font = UIFont.ows_dynamicTypeSubheadline
        messageLabel.textColor = Theme.secondaryTextAndIconColor
        messageLabel.numberOfLines = 0
        messageLabel.lineBreakMode = .byWordWrapping
        messageLabel.setContentHuggingVerticalHigh()

        let cancelButton = OWSFlatButton.button(title: CommonStrings.cancelButton,
                                                font: UIFont.ows_dynamicTypeBody.ows_semibold,
                                                titleColor: Theme.secondaryTextAndIconColor,
                                                backgroundColor: Theme.washColor,
                                                target: self,
                                                selector: #selector(didTapCancel))
        cancelButton.autoSetHeightUsingFont()
        self.cancelButton = cancelButton

        let joinButton = OWSFlatButton.button(title: NSLocalizedString("GROUP_LINK_ACTION_SHEET_VIEW_JOIN_BUTTON",
                                                                       comment: "Label for the 'join' button in the 'group invite link' action sheet."),
                                              font: UIFont.ows_dynamicTypeBody.ows_semibold,
                                              titleColor: .ows_accentBlue,
                                              backgroundColor: Theme.washColor,
                                              target: self,
                                              selector: #selector(didTapJoin))
        joinButton.autoSetHeightUsingFont()
        self.joinButton = joinButton

        let invalidOkayButton = OWSFlatButton.button(title: CommonStrings.okayButton,
                                              font: UIFont.ows_dynamicTypeBody.ows_semibold,
                                              titleColor: Theme.primaryTextColor,
                                              backgroundColor: Theme.washColor,
                                              target: self,
                                              selector: #selector(didTapInvalidOkay))
        invalidOkayButton.autoSetHeightUsingFont()
        invalidOkayButton.isHidden = true
        self.invalidOkayButton = invalidOkayButton

        let buttonStack = UIStackView(arrangedSubviews: [
            cancelButton,
            joinButton,
            invalidOkayButton
        ])
        buttonStack.axis = .horizontal
        buttonStack.alignment = .fill
        buttonStack.distribution = .fillEqually
        buttonStack.spacing = 10

        let stackView = UIStackView(arrangedSubviews: [
            headerStack,
            UIView.spacer(withHeight: 50),
            messageLabel,
            UIView.spacer(withHeight: 14),
            buttonStack
        ])
        stackView.axis = .vertical
        stackView.alignment = .fill
        header.addSubview(stackView)
        stackView.autoPinEdgesToSuperviewMargins()

        headerStack.setContentHuggingVerticalHigh()
        stackView.setContentHuggingVerticalHigh()
    }

    private func loadDefaultContent() {
        avatarView.image = OWSGroupAvatarBuilder.defaultAvatar(forGroupId: groupV2ContextInfo.groupId,
                                                               conversationColorName: ConversationColorName.default.rawValue,
                                                               diameter: Self.avatarSize)
        groupTitleLabel.text = NSLocalizedString("GROUP_LINK_ACTION_SHEET_VIEW_LOADING_TITLE",
                                                 comment: "Label indicating that the group info is being loaded in the 'group invite link' action sheet.")
        groupSubtitleLabel.text = " "
    }

    private func loadLinkPreview() {
        firstly(on: .global()) {
            self.groupsV2.fetchGroupInviteLinkPreview(inviteLinkPassword: self.groupInviteLinkInfo.inviteLinkPassword,
                                                      groupSecretParamsData: self.groupV2ContextInfo.groupSecretParamsData,
                                                      allowCached: false)
        }.done { [weak self] (groupInviteLinkPreview: GroupInviteLinkPreview) in
            self?.applyGroupInviteLinkPreview(groupInviteLinkPreview)

            if let avatarUrlPath = groupInviteLinkPreview.avatarUrlPath {
                self?.loadGroupAvatar(avatarUrlPath: avatarUrlPath)
            }
        }.catch { [weak self] error in
            if case GroupsV2Error.expiredGroupInviteLink = error {
                self?.applyExpiredGroupInviteLink()
            } else {
                // TODO: Retry errors?
                owsFailDebugUnlessNetworkFailure(error)
            }
        }
    }

    private func loadGroupAvatar(avatarUrlPath: String) {
        firstly(on: .global()) {
            self.groupsV2.fetchGroupInviteLinkAvatar(avatarUrlPath: avatarUrlPath,
                                                     groupSecretParamsData: self.groupV2ContextInfo.groupSecretParamsData)
        }.done { [weak self] (groupAvatar: Data) in
            self?.applyGroupAvatar(groupAvatar)
        }.catch { error in
            // TODO: Add retry?
            owsFailDebugUnlessNetworkFailure(error)
        }
    }

    private func applyGroupInviteLinkPreview(_ groupInviteLinkPreview: GroupInviteLinkPreview) {
        AssertIsOnMainThread()

        self.groupInviteLinkPreview = groupInviteLinkPreview

        let memberCount = GroupViewUtils.formatGroupMembersLabel(memberCount: Int(groupInviteLinkPreview.memberCount))

        if let title = groupInviteLinkPreview.title.filterForDisplay,
            !title.isEmpty {
            groupTitleLabel.text = title

            let groupIndicator = NSLocalizedString("GROUP_LINK_ACTION_SHEET_VIEW_GROUP_INDICATOR",
                                                   comment: "Indicator for group conversations in the 'group invite link' action sheet.")
            groupSubtitleLabel.text = groupIndicator + " • " + memberCount
        } else {
            groupTitleLabel.text = TSGroupThread.defaultGroupName
            groupSubtitleLabel.text = memberCount
        }
    }

    private func applyGroupAvatar(_ groupAvatar: Data) {
        AssertIsOnMainThread()

        guard (groupAvatar as NSData).ows_isValidImage() else {
            owsFailDebug("Invalid group avatar.")
            return
        }
        guard let image = UIImage(data: groupAvatar) else {
            owsFailDebug("Could not load group avatar.")
            return
        }
        avatarView.image = image
        self.avatarData = groupAvatar
    }

    private func applyExpiredGroupInviteLink() {
        AssertIsOnMainThread()

        self.groupInviteLinkPreview = nil

        groupTitleLabel.text = NSLocalizedString("GROUP_LINK_ACTION_SHEET_VIEW_EXPIRED_LINK_TITLE",
                                                 comment: "Title indicating that the group invite link has expired in the 'group invite link' action sheet.")
        groupSubtitleLabel.text = NSLocalizedString("GROUP_LINK_ACTION_SHEET_VIEW_EXPIRED_LINK_SUBTITLE",
                                                    comment: "Subtitle indicating that the group invite link has expired in the 'group invite link' action sheet.")
        messageLabel.textColor = Theme.backgroundColor
        cancelButton?.isHidden = true
        joinButton?.isHidden = true
        invalidOkayButton?.isHidden = false
    }

    @objc
    func didTapCancel(_ sender: UIButton) {
        dismiss(animated: true)
    }

    @objc
    func didTapInvalidOkay(_ sender: UIButton) {
        dismiss(animated: true)
    }

    private func showActionSheet(title: String?,
                                 message: String? = nil,
                                 buttonTitle: String? = nil,
                                 buttonAction: ActionSheetAction.Handler? = nil) {
        OWSActionSheets.showActionSheet(title: title,
                                        message: message,
                                        buttonTitle: buttonTitle,
                                        buttonAction: buttonAction,
                                        fromViewController: self)
    }

    @objc
    func didTapJoin(_ sender: UIButton) {
        AssertIsOnMainThread()

        Logger.info("")

        guard doesLocalUserSupportGroupsV2 else {
            Logger.warn("Local user does not support groups v2.")
            showActionSheet(title: CommonStrings.errorAlertTitle,
                            message: NSLocalizedString("GROUP_LINK_LOCAL_USER_DOES_NOT_SUPPORT_GROUPS_V2_ERROR_MESSAGE",
                                                       comment: "Error message indicating that the local user does not support groups v2."))
            return
        }

        // These values may not be filled in yet.
        // They may be being downloaded now or their downloads may have failed.
        let existingGroupInviteLinkPreview = self.groupInviteLinkPreview
        let existingAvatarData = self.avatarData

        ModalActivityIndicatorViewController.present(fromViewController: self, canCancel: false) { modalActivityIndicator in
            firstly(on: .global()) { () -> Promise<GroupInviteLinkPreview> in
                if let existingGroupInviteLinkPreview = existingGroupInviteLinkPreview {
                    // View has already downloaded the preview.
                    return Promise.value(existingGroupInviteLinkPreview)
                }
                // Kick off a fresh attempt to download the link preview.
                // We cannot join the group without the preview.
                return self.groupsV2.fetchGroupInviteLinkPreview(inviteLinkPassword: self.groupInviteLinkInfo.inviteLinkPassword,
                                                                 groupSecretParamsData: self.groupV2ContextInfo.groupSecretParamsData,
                                                                 allowCached: false)
            }.then(on: .global()) { (groupInviteLinkPreview: GroupInviteLinkPreview) -> Promise<(GroupInviteLinkPreview, Data?)> in
                guard let avatarUrlPath = groupInviteLinkPreview.avatarUrlPath else {
                    // Group has no avatar.
                    return Promise.value((groupInviteLinkPreview, nil))
                }
                if let existingAvatarData = existingAvatarData {
                    // View has already downloaded the avatar.
                    return Promise.value((groupInviteLinkPreview, existingAvatarData))
                }
                return firstly(on: .global()) {
                    self.groupsV2.fetchGroupInviteLinkAvatar(avatarUrlPath: avatarUrlPath,
                                                             groupSecretParamsData: self.groupV2ContextInfo.groupSecretParamsData)
                }.map(on: .global()) { (groupAvatar: Data) in
                    (groupInviteLinkPreview, groupAvatar)
                }.recover(on: .global()) { error -> Promise<(GroupInviteLinkPreview, Data?)> in
                    Logger.warn("Error: \(error)")
                    // We made a best effort to fill in the avatar.
                    // Don't block joining the group on downloading
                    // the avatar. It will only be used in a
                    // placeholder model if at all.
                    return Promise.value((groupInviteLinkPreview, nil))
                }
            }.then(on: .global()) { (groupInviteLinkPreview: GroupInviteLinkPreview, avatarData: Data?) in
                GroupManager.joinGroupViaInviteLink(groupId: self.groupV2ContextInfo.groupId,
                                                    groupSecretParamsData: self.groupV2ContextInfo.groupSecretParamsData,
                                                    inviteLinkPassword: self.groupInviteLinkInfo.inviteLinkPassword,
                                                    groupInviteLinkPreview: groupInviteLinkPreview,
                                                    avatarData: avatarData)
            }.done { [weak self] (groupThread: TSGroupThread) in
                modalActivityIndicator.dismiss {
                    AssertIsOnMainThread()
                    self?.dismiss(animated: true) {
                        AssertIsOnMainThread()
                        SignalApp.shared().presentConversation(for: groupThread, animated: true)
                    }
                }
            }.catch { error in
                Logger.warn("Error: \(error)")

                modalActivityIndicator.dismiss {
                    AssertIsOnMainThread()

                    let title = NSLocalizedString("GROUP_LINK_ACTION_SHEET_VIEW_EXPIRED_LINK_TITLE",
                                                  comment: "Title indicating that the group invite link has expired in the 'group invite link' action sheet.")
                    let message: String
                    if case GroupsV2Error.expiredGroupInviteLink = error {
                        message = NSLocalizedString("GROUP_LINK_ACTION_SHEET_VIEW_EXPIRED_LINK_SUBTITLE",
                                                    comment: "Subtitle indicating that the group invite link has expired in the 'group invite link' action sheet.")
                    } else if IsNetworkConnectivityFailure(error) {
                        message = NSLocalizedString("GROUP_LINK_COULD_NOT_REQUEST_TO_JOIN_GROUP_DUE_TO_NETWORK_ERROR_MESSAGE",
                                                    comment: "Error message the attempt to request to join the group failed due to network connectivity.")
                    } else {
                        message = NSLocalizedString("GROUP_LINK_COULD_NOT_REQUEST_TO_JOIN_GROUP_ERROR_MESSAGE",
                                                    comment: "Error message the attempt to request to join the group failed.")
                    }
                    self.showActionSheet(title: title, message: message)
                }
            }
        }
    }

    private var doesLocalUserSupportGroupsV2: Bool {
        guard let localAddress = tsAccountManager.localAddress else {
            owsFailDebug("missing local address")
            return false
        }
        return databaseStorage.read { transaction in
            GroupManager.doesUserSupportGroupsV2(address: localAddress, transaction: transaction)
        }
    }
}
