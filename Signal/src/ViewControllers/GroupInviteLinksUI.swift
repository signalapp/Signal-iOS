//
//  Copyright (c) 2020 Open Whisper Systems. All rights reserved.
//

import Foundation
import UIKit
import PromiseKit

@objc
public class GroupInviteLinksUI: NSObject {

    // MARK: - Dependencies

    private class var databaseStorage: SDSDatabaseStorage {
        return SDSDatabaseStorage.shared
    }

    private class var groupsV2: GroupsV2Swift {
        return SSKEnvironment.shared.groupsV2 as! GroupsV2Swift
    }

    // MARK: -

    @available(*, unavailable, message:"Do not instantiate this class.")
    private override init() {
    }

    @objc
    public static func openGroupInviteLink(_ url: URL,
                                           fromViewController: UIViewController) {
        AssertIsOnMainThread()

        guard RemoteConfig.groupsV2GoodCitizen else {
            return
        }
        let showInvalidInviteLinkAlert = {
            // TODO: Add copy from design.
            // TODO: Surface "revoked invite link" error here and elsewhere.
            OWSActionSheets.showErrorAlert(message: NSLocalizedString("GROUP_LINK_INVALID_GROUP_INVITE_LINK_ERROR_MESSAGE",
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
        //
        // TODO: Design.
        if let existingGroupThread = (databaseStorage.read { transaction in
            TSGroupThread.fetch(groupId: groupV2ContextInfo.groupId, transaction: transaction)
        }), existingGroupThread.isLocalUserFullMember {
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

    // MARK: - Dependencies

    private var groupsV2: GroupsV2Swift {
        return SSKEnvironment.shared.groupsV2 as! GroupsV2Swift
    }

    private var databaseStorage: SDSDatabaseStorage {
        return SDSDatabaseStorage.shared
    }

    private var tsAccountManager: TSAccountManager {
        return .sharedInstance()
    }

    // MARK: -

    private let groupInviteLinkInfo: GroupInviteLinkInfo
    private let groupV2ContextInfo: GroupV2ContextInfo

    private let avatarView = AvatarImageView()
    private let groupTitleLabel = UILabel()
    private let groupSubtitleLabel = UILabel()

    init(groupInviteLinkInfo: GroupInviteLinkInfo, groupV2ContextInfo: GroupV2ContextInfo) {
        self.groupInviteLinkInfo = groupInviteLinkInfo
        self.groupV2ContextInfo = groupV2ContextInfo

        super.init()

        isCancelable = true

        createContents()
    }

    private static let avatarSize: UInt = 112

    private func createContents() {

        let header = UIView()
        header.layoutMargins = UIEdgeInsets(top: 20, leading: 20, bottom: 20, trailing: 20)
        header.backgroundColor = Theme.backgroundColor
        self.customHeader = header

        avatarView.autoSetDimension(.width, toSize: CGFloat(Self.avatarSize))

        groupTitleLabel.font = UIFont.ows_dynamicTypeBody.ows_semibold()
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

        let messageLabel = UILabel()
        messageLabel.text = NSLocalizedString("GROUP_LINK_ACTION_SHEET_VIEW_MESSAGE",
                                              comment: "Message text for the 'group invite link' action sheet.")
        messageLabel.font = UIFont.ows_dynamicTypeSubheadline
        messageLabel.textColor = Theme.secondaryTextAndIconColor
        messageLabel.numberOfLines = 0
        messageLabel.lineBreakMode = .byWordWrapping
        messageLabel.setContentHuggingVerticalHigh()

        let cancelButton = OWSFlatButton.button(title: CommonStrings.cancelButton,
                                                font: UIFont.ows_dynamicTypeBody.ows_semibold(),
                                                titleColor: Theme.secondaryTextAndIconColor,
                                                backgroundColor: Theme.washColor,
                                                target: self,
                                                selector: #selector(didTapCancel))
        cancelButton.autoSetHeightUsingFont()

        let joinButton = OWSFlatButton.button(title: NSLocalizedString("GROUP_LINK_ACTION_SHEET_VIEW_JOIN_BUTTON",
                                                                       comment: "Label for the 'join' button in the 'group invite link' action sheet."),
                                                font: UIFont.ows_dynamicTypeBody.ows_semibold(),
                                                titleColor: .ows_accentBlue,
                                                backgroundColor: Theme.washColor,
                                                target: self,
                                                selector: #selector(didTapJoin))
        joinButton.autoSetHeightUsingFont()

        let buttonStack = UIStackView(arrangedSubviews: [
            cancelButton,
            joinButton
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

        loadDefaultContent()
        loadLinkPreview()
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
                                                      groupSecretParamsData: self.groupV2ContextInfo.groupSecretParamsData)
        }.done { [weak self] (groupInviteLinkPreview: GroupInviteLinkPreview) in
            self?.applyGroupInviteLinkPreview(groupInviteLinkPreview)

            if let avatarUrlPath = groupInviteLinkPreview.avatarUrlPath {
                self?.loadGroupAvatar(avatarUrlPath: avatarUrlPath)
            }
        }.catch { error in
            // TODO: Retry errors?
            if IsNetworkConnectivityFailure(error) {
                Logger.warn("Error: \(error)")
            } else {
                owsFailDebug("Error: \(error)")
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
            if IsNetworkConnectivityFailure(error) {
                Logger.warn("Error: \(error)")
            } else {
                owsFailDebug("Error: \(error)")
            }
        }
    }

    private var groupInviteLinkPreview: GroupInviteLinkPreview?

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
    }

    @objc
    func didTapCancel(_ sender: UIButton) {
        dismiss(animated: true)
    }

    @objc
    func didTapJoin(_ sender: UIButton) {
        guard doesLocalUserSupportGroupsV2 else {
            // TODO: Add copy from design.
            OWSActionSheets.showErrorAlert(message: NSLocalizedString("GROUP_LINK_LOCAL_USER_DOES_NOT_SUPPORT_GROUPS_V2_ERROR_MESSAGE",
                                                                      comment: "Error message indicating that the local user does not support groups v2."))
            return
        }

        ModalActivityIndicatorViewController.present(fromViewController: self, canCancel: false) { modalActivityIndicator in
            firstly(on: .global()) {
                GroupManager.joinGroupViaInviteLink(groupId: self.groupV2ContextInfo.groupId,
                                                    groupSecretParamsData: self.groupV2ContextInfo.groupSecretParamsData,
                                                    inviteLinkPassword: self.groupInviteLinkInfo.inviteLinkPassword)
            }.done { [weak self] (groupThread: TSGroupThread) in
                modalActivityIndicator.dismiss {
                    self?.dismiss(animated: true) {
                        SignalApp.shared().presentConversation(for: groupThread, animated: true)
                    }
                }
            }.catch { _ in
                modalActivityIndicator.dismiss {
                    OWSActionSheets.showErrorAlert(message: NSLocalizedString("GROUP_LINK_LOCAL_USER_DOES_NOT_SUPPORT_GROUPS_V2_ERROR_MESSAGE",
                                                                              comment: "Error message indicating that the local user does not support groups v2."))
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
