//
// Copyright 2020 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import SignalServiceKit
public import SignalUI

public class GroupInviteLinksUI: UIView {

    @available(*, unavailable, message: "Do not instantiate this class.")
    required init(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    public static func openGroupInviteLink(_ url: URL, fromViewController: UIViewController) {
        AssertIsOnMainThread()

        let showInvalidInviteLinkAlert = {
            OWSActionSheets.showActionSheet(title: OWSLocalizedString("GROUP_LINK_INVALID_GROUP_INVITE_LINK_ERROR_TITLE",
                                                                     comment: "Title for the 'invalid group invite link' alert."),
                                            message: OWSLocalizedString("GROUP_LINK_INVALID_GROUP_INVITE_LINK_ERROR_MESSAGE",
                                                                      comment: "Message for the 'invalid group invite link' alert."))
        }

        guard let groupInviteLinkInfo = GroupInviteLinkInfo.parseFrom(url) else {
            owsFailDebug("Invalid group invite link.")
            showInvalidInviteLinkAlert()
            return
        }

        let groupV2ContextInfo: GroupV2ContextInfo
        do {
            groupV2ContextInfo = try GroupV2ContextInfo.deriveFrom(masterKeyData: groupInviteLinkInfo.masterKey)
        } catch {
            owsFailDebug("Error: \(error)")
            showInvalidInviteLinkAlert()
            return
        }

        // If the group already exists in the database, open it.
        if let existingGroupThread = (SSKEnvironment.shared.databaseStorageRef.read { transaction in
            TSGroupThread.fetch(groupId: groupV2ContextInfo.groupId, transaction: transaction)
        }), existingGroupThread.isLocalUserFullMember || existingGroupThread.isLocalUserRequestingMember {
            SignalApp.shared.presentConversationForThread(existingGroupThread, animated: true)
            return
        }

        let actionSheet = GroupInviteLinksActionSheet(groupInviteLinkInfo: groupInviteLinkInfo,
                                                      groupV2ContextInfo: groupV2ContextInfo)
        fromViewController.presentActionSheet(actionSheet)
    }
}

// MARK: -

private class GroupInviteLinksActionSheet: ActionSheetController {
    private let groupInviteLinkInfo: GroupInviteLinkInfo
    private let groupV2ContextInfo: GroupV2ContextInfo

    private let avatarView = AvatarImageView()
    private let groupTitleLabel = UILabel()
    private let groupSubtitleLabel = UILabel()
    private let groupDescriptionPreview = GroupDescriptionPreviewView()

    private var groupInviteLinkPreview: GroupInviteLinkPreview?
    private var avatarData: Data?

    init(groupInviteLinkInfo: GroupInviteLinkInfo, groupV2ContextInfo: GroupV2ContextInfo) {
        self.groupInviteLinkInfo = groupInviteLinkInfo
        self.groupV2ContextInfo = groupV2ContextInfo

        super.init(theme: .default)

        isCancelable = true

        createContents()
        loadLinkPreview()
    }

    private static let avatarSize: UInt = 80

    private let messageLabel = UILabel()

    private var cancelButton: UIView!
    private var joinButton: OWSFlatButton!
    private var invalidOkayButton: UIView!

    /// Fills out this view's contents before any group-invite-link-preview info
    /// fetches have been attempted.
    private func createContents() {
        let header = UIView()
        header.layoutMargins = UIEdgeInsets(hMargin: 32, vMargin: 32)
        header.backgroundColor = Theme.actionSheetBackgroundColor
        self.customHeader = header

        avatarView.image = SSKEnvironment.shared.avatarBuilderRef.avatarImage(
            forGroupId: groupV2ContextInfo.groupId,
            diameterPoints: Self.avatarSize
        )
        avatarView.autoSetDimension(.width, toSize: CGFloat(Self.avatarSize))

        groupTitleLabel.font = UIFont.semiboldFont(ofSize: UIFont.dynamicTypeTitle1Clamped.pointSize * (13/14))
        groupTitleLabel.textColor = Theme.primaryTextColor
        groupTitleLabel.text = OWSLocalizedString(
            "GROUP_LINK_ACTION_SHEET_VIEW_LOADING_TITLE",
            comment: "Label indicating that the group info is being loaded in the 'group invite link' action sheet."
        )
        groupSubtitleLabel.text = ""

        groupSubtitleLabel.font = UIFont.dynamicTypeSubheadline
        groupSubtitleLabel.textColor = Theme.secondaryTextAndIconColor

        groupDescriptionPreview.font = .dynamicTypeSubheadline
        groupDescriptionPreview.textColor = Theme.secondaryTextAndIconColor
        groupDescriptionPreview.numberOfLines = 2
        groupDescriptionPreview.textAlignment = .center
        groupDescriptionPreview.isHidden = true
        groupDescriptionPreview.descriptionText = ""

        let headerStack = UIStackView(arrangedSubviews: [
            avatarView,
            groupTitleLabel,
            groupSubtitleLabel,
            .spacer(withHeight: 4),
            groupDescriptionPreview
        ])
        headerStack.spacing = 8
        headerStack.axis = .vertical
        headerStack.alignment = .center

        messageLabel.font = .dynamicTypeFootnote
        messageLabel.textColor = Theme.secondaryTextAndIconColor
        messageLabel.numberOfLines = 0
        messageLabel.lineBreakMode = .byWordWrapping
        messageLabel.textAlignment = .center
        messageLabel.setContentHuggingVerticalHigh()

        let buttonColor: UIColor = Theme.isDarkThemeEnabled ? .ows_gray65 : .ows_gray05
        let cancelButton = OWSFlatButton.button(title: CommonStrings.cancelButton,
                                                font: UIFont.dynamicTypeBody.semibold(),
                                                titleColor: Theme.secondaryTextAndIconColor,
                                                backgroundColor: buttonColor,
                                                target: self,
                                                selector: #selector(didTapCancel))
        cancelButton.enableMultilineLabel()
        cancelButton.autoSetMinimumHeighUsingFont()
        cancelButton.cornerRadius = 14
        self.cancelButton = cancelButton

        let joinButton = OWSFlatButton.button(title: "",
                                              font: UIFont.dynamicTypeBody.semibold(),
                                              titleColor: .ows_accentBlue,
                                              backgroundColor: buttonColor,
                                              target: self,
                                              selector: #selector(didTapJoin))
        joinButton.enableMultilineLabel()
        joinButton.autoSetMinimumHeighUsingFont()
        joinButton.cornerRadius = 14
        joinButton.isUserInteractionEnabled = false
        self.joinButton = joinButton

        let invalidOkayButton = OWSFlatButton.button(title: CommonStrings.okayButton,
                                              font: UIFont.dynamicTypeBody.semibold(),
                                              titleColor: Theme.primaryTextColor,
                                              backgroundColor: buttonColor,
                                              target: self,
                                              selector: #selector(didTapInvalidOkay))
        invalidOkayButton.enableMultilineLabel()
        invalidOkayButton.autoSetMinimumHeighUsingFont()
        invalidOkayButton.cornerRadius = 14
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

        let divider = UIView()
        divider.autoSetDimension(.height, toSize: .hairlineWidth)
        divider.backgroundColor = buttonColor

        let stackView = UIStackView(arrangedSubviews: [
            headerStack,
            UIView.spacer(withHeight: 32),
            divider,
            UIView.spacer(withHeight: 16),
            messageLabel,
            UIView.spacer(withHeight: 16),
            buttonStack
        ])
        stackView.axis = .vertical
        stackView.alignment = .fill
        header.addSubview(stackView)
        stackView.autoPinEdgesToSuperviewMargins()

        headerStack.setContentHuggingVerticalHigh()
        stackView.setContentHuggingVerticalHigh()
    }

    // MARK: - Load invite link preview

    private enum LinkPreviewLoadResult {
        case success(GroupInviteLinkPreview)
        case expiredLink
        case failure(Error)
    }

    private func loadLinkPreview() {
        Task { [weak self, groupInviteLinkInfo, groupV2ContextInfo] in
            do {
                let groupInviteLinkPreview = try await SSKEnvironment.shared.groupsV2Ref.fetchGroupInviteLinkPreview(
                    inviteLinkPassword: groupInviteLinkInfo.inviteLinkPassword,
                    groupSecretParams: groupV2ContextInfo.groupSecretParams,
                    allowCached: false
                )
                self?.applyLinkPreviewLoadResult(.success(groupInviteLinkPreview))

                guard self != nil else {
                    return
                }

                if let avatarUrlPath = groupInviteLinkPreview.avatarUrlPath {
                    do {
                        let avatarData = try await SSKEnvironment.shared.groupsV2Ref.fetchGroupInviteLinkAvatar(
                            avatarUrlPath: avatarUrlPath,
                            groupSecretParams: groupV2ContextInfo.groupSecretParams
                        )
                        self?.applyGroupAvatar(avatarData)
                    } catch {
                        owsFailDebugUnlessNetworkFailure(error)
                    }
                }
            } catch GroupsV2Error.expiredGroupInviteLink {
                self?.applyLinkPreviewLoadResult(.expiredLink)
            } catch GroupsV2Error.localUserBlockedFromJoining {
                Logger.warn("User blocked")
                self?.dismiss(animated: true, completion: {
                    OWSActionSheets.showActionSheet(
                        title: OWSLocalizedString(
                            "GROUP_LINK_ACTION_SHEET_VIEW_CANNOT_JOIN_GROUP_TITLE",
                            comment: "Title indicating that you cannot join a group in the 'group invite link' action sheet."
                        ),
                        message: OWSLocalizedString(
                            "GROUP_LINK_ACTION_SHEET_VIEW_BLOCKED_FROM_JOINING_SUBTITLE",
                            comment: "Subtitle indicating that the local user has been blocked from joining the group"
                        )
                    )
                })
            } catch {
                self?.applyLinkPreviewLoadResult(.failure(error))
            }
        }
    }

    private func applyLinkPreviewLoadResult(_ result: LinkPreviewLoadResult) {
        AssertIsOnMainThread()

        let joinGroupMessage = OWSLocalizedString(
            "GROUP_LINK_ACTION_SHEET_VIEW_MESSAGE",
            comment: "Message text for the 'group invite link' action sheet."
        )
        let joinGroupButtonTitle = OWSLocalizedString(
            "GROUP_LINK_ACTION_SHEET_VIEW_JOIN_BUTTON",
            comment: "Label for the 'join' button in the 'group invite link' action sheet."
        )
        let requestToJoinGroupMessage = OWSLocalizedString(
            "GROUP_LINK_ACTION_SHEET_VIEW_REQUEST_TO_JOIN_MESSAGE",
            comment: "Message text for the 'group invite link' action sheet, if the user will be requesting to join."
        )
        let requestToJoinGroupButtonTitle = OWSLocalizedString(
            "GROUP_LINK_ACTION_SHEET_VIEW_REQUEST_TO_JOIN_BUTTON",
            comment: "Label for the 'request to join' button in the 'group invite link' action sheet."
        )

        switch result {
        case .success(let groupInviteLinkPreview):
            self.groupInviteLinkPreview = groupInviteLinkPreview

            /// This button starts disabled since we don't know if it should be
            /// "join" or "request to join", but now that we do we'll enable it.
            joinButton.isUserInteractionEnabled = true
            switch groupInviteLinkPreview.addFromInviteLinkAccess {
            case .any:
                joinButton.button.setTitle(joinGroupButtonTitle, for: .normal)
                messageLabel.text = joinGroupMessage
            case .administrator:
                joinButton.button.setTitle(requestToJoinGroupButtonTitle, for: .normal)
                messageLabel.text = requestToJoinGroupMessage
            case .member, .unsatisfiable, .unknown:
                owsFailDebug("Invalid addFromInviteLinkAccess!")
            }

            let groupName = groupInviteLinkPreview.title.filterForDisplay.nilIfEmpty ?? TSGroupThread.defaultGroupName
            groupTitleLabel.text = groupName
            groupSubtitleLabel.text = GroupViewUtils.formatGroupMembersLabel(
                memberCount: Int(groupInviteLinkPreview.memberCount)
            )
            if let descriptionText = groupInviteLinkPreview.descriptionText?.filterForDisplay.nilIfEmpty {
                groupDescriptionPreview.descriptionText = descriptionText
                groupDescriptionPreview.groupName = groupName
                groupDescriptionPreview.isHidden = false
            }
        case .expiredLink:
            groupTitleLabel.text = OWSLocalizedString("GROUP_LINK_ACTION_SHEET_VIEW_CANNOT_JOIN_GROUP_TITLE",
                                                      comment: "Title indicating that you cannot join a group in the 'group invite link' action sheet.")
            groupSubtitleLabel.text = OWSLocalizedString("GROUP_LINK_ACTION_SHEET_VIEW_EXPIRED_LINK_SUBTITLE",
                                                         comment: "Subtitle indicating that the group invite link has expired in the 'group invite link' action sheet.")
            messageLabel.textColor = Theme.backgroundColor
            cancelButton?.isHidden = true
            joinButton?.isHidden = true
            invalidOkayButton?.isHidden = false
        case .failure(let error):
            owsFailDebugUnlessNetworkFailure(error)

            /// We don't know what went wrong, but existing behavior at the time
            /// of writing is that tapping the join button will make another
            /// attempt to load the link preview, and automatically attempt to
            /// join (or request to join) if possible. If this was a transient
            /// network error, for example, then you may be able to recover by
            /// hitting the join button.
            ///
            /// To that end, we'll enable it and default-populate it with the
            /// "join" strings (since we won't know until that re-attempt if it
            /// should've actually been "request to join").
            joinButton.isUserInteractionEnabled = true
            joinButton.button.setTitle(joinGroupButtonTitle, for: .normal)
            messageLabel.text = joinGroupMessage
        }
    }

    // MARK: - Group avatar

    private func applyGroupAvatar(_ groupAvatar: Data) {
        AssertIsOnMainThread()

        guard groupAvatar.ows_isValidImage else {
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

    // MARK: - Actions

    @objc
    private func didTapCancel(_ sender: UIButton) {
        dismiss(animated: true)
    }

    @objc
    private func didTapInvalidOkay(_ sender: UIButton) {
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
    private func didTapJoin(_ sender: UIButton) {
        AssertIsOnMainThread()

        Logger.info("")

        // These values may not be filled in yet.
        // They may be being downloaded now or their downloads may have failed.
        let existingGroupInviteLinkPreview = self.groupInviteLinkPreview
        let existingAvatarData = self.avatarData

        ModalActivityIndicatorViewController.present(
            fromViewController: self,
            canCancel: false,
            asyncBlock: { [weak self, groupInviteLinkInfo, groupV2ContextInfo] modal in
                do {
                    let groupInviteLinkPreview: GroupInviteLinkPreview
                    if let existingGroupInviteLinkPreview {
                        groupInviteLinkPreview = existingGroupInviteLinkPreview
                    } else {
                        // Kick off a fresh attempt to download the link preview.
                        // We cannot join the group without the preview.
                        groupInviteLinkPreview = try await SSKEnvironment.shared.groupsV2Ref.fetchGroupInviteLinkPreview(
                            inviteLinkPassword: groupInviteLinkInfo.inviteLinkPassword,
                            groupSecretParams: groupV2ContextInfo.groupSecretParams,
                            allowCached: false
                        )
                    }

                    let avatarData: Data?
                    if let avatarUrlPath = groupInviteLinkPreview.avatarUrlPath {
                        if let existingAvatarData {
                            avatarData = existingAvatarData
                        } else {
                            do {
                                avatarData = try await SSKEnvironment.shared.groupsV2Ref.fetchGroupInviteLinkAvatar(
                                    avatarUrlPath: avatarUrlPath,
                                    groupSecretParams: groupV2ContextInfo.groupSecretParams
                                )
                            } catch {
                                Logger.warn("Error: \(error)")
                                // We made a best effort to fill in the avatar. Don't block joining the
                                // group on downloading the avatar. It will only be used in a placeholder
                                // model if at all.
                                avatarData = nil
                            }
                        }
                    } else {
                        // Group has no avatar.
                        avatarData = nil
                    }

                    try await GroupManager.joinGroupViaInviteLink(
                        groupId: groupV2ContextInfo.groupId,
                        groupSecretParams: groupV2ContextInfo.groupSecretParams,
                        inviteLinkPassword: groupInviteLinkInfo.inviteLinkPassword,
                        groupInviteLinkPreview: groupInviteLinkPreview,
                        avatarData: avatarData
                    )

                    modal.dismiss {
                        AssertIsOnMainThread()
                        self?.dismiss(animated: true) {
                            AssertIsOnMainThread()
                            let groupThread = SSKEnvironment.shared.databaseStorageRef.read { tx in
                                // We successfully joined, so we must be able to find the TSGroupThread.
                                return TSGroupThread.fetch(groupId: groupV2ContextInfo.groupId, transaction: tx)!
                            }
                            SignalApp.shared.presentConversationForThread(groupThread, animated: true)
                        }
                    }
                } catch {
                    Logger.warn("Error: \(error)")

                    modal.dismiss {
                        AssertIsOnMainThread()

                        self?.showActionSheet(
                            title: OWSLocalizedString(
                                "GROUP_LINK_ACTION_SHEET_VIEW_CANNOT_JOIN_GROUP_TITLE",
                                comment: "Title indicating that you cannot join a group in the 'group invite link' action sheet."
                            ),
                            message: {
                                switch error {
                                case GroupsV2Error.expiredGroupInviteLink:
                                    return OWSLocalizedString(
                                        "GROUP_LINK_ACTION_SHEET_VIEW_EXPIRED_LINK_SUBTITLE",
                                        comment: "Subtitle indicating that the group invite link has expired in the 'group invite link' action sheet."
                                    )
                                case GroupsV2Error.localUserBlockedFromJoining:
                                    return OWSLocalizedString(
                                        "GROUP_LINK_ACTION_SHEET_VIEW_BLOCKED_FROM_JOINING_SUBTITLE",
                                        comment: "Subtitle indicating that the local user has been blocked from joining the group"
                                    )
                                case _ where error.isNetworkFailureOrTimeout:
                                    return OWSLocalizedString(
                                        "GROUP_LINK_COULD_NOT_REQUEST_TO_JOIN_GROUP_DUE_TO_NETWORK_ERROR_MESSAGE",
                                        comment: "Error message the attempt to request to join the group failed due to network connectivity."
                                    )
                                default:
                                    return OWSLocalizedString(
                                        "GROUP_LINK_COULD_NOT_REQUEST_TO_JOIN_GROUP_ERROR_MESSAGE",
                                        comment: "Error message the attempt to request to join the group failed."
                                    )
                                }
                            }()
                        )
                    }
                }
            }
        )
    }
}
