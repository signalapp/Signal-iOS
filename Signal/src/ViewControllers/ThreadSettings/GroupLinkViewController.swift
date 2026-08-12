//
// Copyright 2020 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import LibSignalClient
public import SignalServiceKit
public import SignalUI

protocol GroupLinkViewControllerDelegate: AnyObject {
    func groupLinkViewViewDidUpdate()
}

// MARK: -

public class GroupLinkViewController: OWSTableViewController2 {

    weak var groupLinkViewControllerDelegate: GroupLinkViewControllerDelegate?

    private let secretParams: GroupSecretParams
    private var inviteLinkConfiguration: GroupInviteLinkConfiguration
    private var isAdmin: Bool

    init(secretParams: GroupSecretParams) {
        self.secretParams = secretParams
        let groupModel = Self.fetchGroupModelWithSneakyTransaction(secretParams: secretParams).owsFailUnwrap("should exist during init")
        self.inviteLinkConfiguration = groupModel.inviteLinkConfiguration()
        self.isAdmin = groupModel.groupMembership.isLocalUserFullMemberAndAdministrator
        super.init()
    }

    // MARK: - View Lifecycle

    override public func viewDidLoad() {
        super.viewDidLoad()

        title = OWSLocalizedString(
            "GROUP_LINK_VIEW_TITLE",
            comment: "The title for the 'group link' view.",
        )
        updateTableContents()
    }

    // MARK: -

    private func updateTableContents() {
        let contents = OWSTableContents()

        // MARK: - Enable

        do {
            let section = OWSTableSection()

            section.add(.switch(
                withText: OWSLocalizedString(
                    "GROUP_LINK_VIEW_ENABLE_GROUP_LINK_SWITCH",
                    comment: "Label for the 'enable group link' switch in the 'group link' view.",
                ),
                accessibilityIdentifier: "group_link_view_enable_group_link",
                isOn: {
                    if case .enabled = self.inviteLinkConfiguration {
                        return true
                    } else {
                        return false
                    }
                },
                actionBlock: { [weak self] uiSwitch in
                    self?.didToggleGroupLinkEnabled(uiSwitch)
                },
            ))

            if case .enabled(let inviteLink, requireAdminApproval: _) = inviteLinkConfiguration {
                do {
                    let inviteLink = try inviteLink.get()
                    let urlLabel = UILabel()
                    urlLabel.text = inviteLink.url().absoluteString
                    urlLabel.font = .dynamicTypeSubheadline
                    urlLabel.textColor = Theme.secondaryTextAndIconColor
                    urlLabel.numberOfLines = 0
                    urlLabel.lineBreakMode = .byCharWrapping

                    section.add(.init(
                        customCellBlock: { () -> UITableViewCell in
                            let cell = OWSTableItem.newCell()
                            cell.selectionStyle = .none
                            cell.contentView.addSubview(urlLabel)
                            urlLabel.autoPinEdgesToSuperviewMargins()
                            return cell
                        },
                        actionBlock: {

                        },
                    ))
                } catch {
                    owsFailDebug("Error: \(error)")
                }
            }

            contents.add(section)
        }

        // MARK: - Sharing

        if case .enabled(let inviteLink, requireAdminApproval: _) = inviteLinkConfiguration {
            let section = OWSTableSection()
            section.separatorInsetLeading = Self.cellHInnerMargin + 24 + OWSTableItem.iconSpacing
            section.add(OWSTableItem.item(
                icon: .buttonShare,
                name: OWSLocalizedString(
                    "GROUP_LINK_VIEW_SHARE_LINK",
                    comment: "Label for the 'share link' button in the 'group link' view.",
                ),
                accessibilityIdentifier: "group_link_view_share_link",
                actionBlock: { [weak self] in
                    self?.shareLinkPressed(inviteLink: failIfThrows { try inviteLink.get() })
                },
            ))
            section.add(OWSTableItem.item(
                icon: .buttonRetry,
                name: OWSLocalizedString(
                    "GROUP_LINK_VIEW_RESET_LINK",
                    comment: "Label for the 'reset link' button in the 'group link' view.",
                ),
                accessibilityIdentifier: "group_link_view_reset_link",
                actionBlock: { [weak self] in
                    self?.resetLinkPressed()
                },
            ))
            contents.add(section)
        }

        // MARK: - Member Requests

        if case .enabled(inviteLink: _, let requireAdminApproval) = inviteLinkConfiguration {
            do {
                let section = OWSTableSection()
                section.footerTitle = OWSLocalizedString(
                    "GROUP_LINK_VIEW_MEMBER_REQUESTS_SECTION_FOOTER",
                    comment: "Footer for the 'member requests' section of the 'group link' view.",
                )

                section.add(OWSTableItem.switch(
                    withText: OWSLocalizedString(
                        "GROUP_LINK_VIEW_APPROVE_NEW_MEMBERS_SWITCH",
                        comment: "Label for the 'approve new members' switch in the 'group link' view.",
                    ),
                    isOn: { requireAdminApproval },
                    actionBlock: { [weak self] uiSwitch in
                        self?.didToggleApproveNewMembers(uiSwitch)
                    },
                ))

                contents.add(section)
            }
        }

        self.contents = contents
    }

    private static func fetchGroupModelWithSneakyTransaction(secretParams: GroupSecretParams) -> TSGroupModelV2? {
        let databaseStorage = SSKEnvironment.shared.databaseStorageRef
        let groupId = failIfThrows { try secretParams.getPublicParams().getGroupIdentifier() }
        let groupThread = databaseStorage.read { tx in
            return TSGroupThread.fetchThread(forGroupId: groupId, tx: tx)
        }
        return groupThread?.groupModel as? TSGroupModelV2
    }

    static func fetchInviteLinkConfigurationWithSneakyTransaction(secretParams: GroupSecretParams) -> GroupInviteLinkConfiguration? {
        return fetchGroupModelWithSneakyTransaction(secretParams: secretParams)?.inviteLinkConfiguration()
    }

    fileprivate func didModifyGroup() {
        let newGroupModel = Self.fetchGroupModelWithSneakyTransaction(secretParams: secretParams)
        guard let newGroupModel else {
            navigationController?.popViewController(animated: true)
            return
        }

        groupLinkViewControllerDelegate?.groupLinkViewViewDidUpdate()

        self.inviteLinkConfiguration = newGroupModel.inviteLinkConfiguration()
        self.isAdmin = newGroupModel.groupMembership.isLocalUserFullMemberAndAdministrator
        updateTableContents()
    }

    // MARK: - Events

    private var canEditGroupLink: Bool {
        return isAdmin
    }

    private func presentAdminOnlyWarningToast() {
        let message = OWSLocalizedString(
            "GROUP_ADMIN_ONLY_WARNING",
            comment: "Message indicating that a feature can only be used by group admins.",
        )
        presentToast(text: message)
    }

    private func didToggleGroupLinkEnabled(_ sender: UISwitch) {
        guard canEditGroupLink else {
            presentAdminOnlyWarningToast()
            updateTableContents()
            return
        }

        let isGroupInviteLinkEnabled = sender.isOn
        // Whenever we activate the group link, default to _not_ requiring admin approval.
        updateLinkMode(linkMode: isGroupInviteLinkEnabled ? .enabled(requireAdminApproval: false) : .disabled)
    }

    private func didToggleApproveNewMembers(_ sender: UISwitch) {
        guard canEditGroupLink else {
            presentAdminOnlyWarningToast()
            updateTableContents()
            return
        }

        let requireAdminApproval = sender.isOn
        updateLinkMode(linkMode: .enabled(requireAdminApproval: requireAdminApproval))
    }

    private func shareLinkPressed(inviteLink: GroupInviteLink) {
        showShareLinkAlert(inviteLink: inviteLink)
    }

    private func resetLinkPressed() {
        guard canEditGroupLink else {
            presentAdminOnlyWarningToast()
            return
        }
        showResetLinkConfirmAlert()
    }

    // We need to retain a link to this delegate during the send flow.
    private var sendMessageController: SendMessageController?

    private func showShareLinkAlert(inviteLink: GroupInviteLink) {
        let sendMessageController = SendMessageController(fromViewController: self)
        self.sendMessageController = sendMessageController
        GroupLinkViewUtils.showShareLinkAlert(
            inviteLink: inviteLink,
            fromViewController: self,
            sendMessageController: sendMessageController,
        )
    }

    private func showResetLinkConfirmAlert() {
        let alertTitle = OWSLocalizedString(
            "GROUP_LINK_VIEW_RESET_LINK_CONFIRM_ALERT_TITLE",
            comment: "Title for the 'confirm reset link' alert in the 'group link' view.",
        )
        let actionSheet = ActionSheetController(title: alertTitle)
        let resetTitle = OWSLocalizedString(
            "GROUP_LINK_VIEW_RESET_LINK",
            comment: "Label for the 'reset link' button in the 'group link' view.",
        )
        actionSheet.addAction(.init(title: resetTitle, style: .destructive) { [weak self] _ in
            self?.resetLink()
        })
        actionSheet.addAction(OWSActionSheets.cancelAction)
        presentActionSheet(actionSheet)
    }
}

// MARK: -

public class GroupLinkViewUtils {

    @MainActor
    static func updateLinkMode(
        secretParams: GroupSecretParams,
        linkMode: GroupInviteLinkMode,
        fromViewController: UIViewController,
        completion: @escaping () -> Void,
    ) {
        GroupViewUtils.updateGroupWithActivityIndicator(
            fromViewController: fromViewController,
            updateBlock: {
                try await GroupManager.updateLinkModeV2(secretParams: secretParams, linkMode: linkMode)
            },
            completion: completion,
        )
    }

    // MARK: -

    public static func showShareLinkAlert(
        inviteLink: GroupInviteLink,
        fromViewController: UIViewController,
        sendMessageController: SendMessageController,
    ) {
        let message = OWSLocalizedString(
            "GROUP_LINK_VIEW_SHARE_SHEET_MESSAGE",
            comment: "Message for the 'share group link' action sheet in the 'group link' view.",
        )
        let actionSheet = ActionSheetController(message: message)
        actionSheet.addAction(ActionSheetAction(
            title: OWSLocalizedString(
                "GROUP_LINK_VIEW_SHARE_LINK_VIA_SIGNAL",
                comment: "Label for the 'share group link via Signal' button in the 'group link' view.",
            ),
            style: .default,
        ) { _ in
            Self.shareLinkViaSignal(
                groupInviteLinkUrl: inviteLink.url(),
                fromViewController: fromViewController,
                sendMessageController: sendMessageController,
            )
        })
        actionSheet.addAction(ActionSheetAction(
            title: OWSLocalizedString(
                "GROUP_LINK_VIEW_COPY_LINK",
                comment: "Label for the 'copy link' button in the 'group link' view.",
            ),
            style: .default,
        ) { _ in
            Self.copyLinkToPasteboard(groupInviteLinkUrl: inviteLink.url())
        })
        actionSheet.addAction(ActionSheetAction(
            title: OWSLocalizedString(
                "GROUP_LINK_VIEW_SHARE_LINK_VIA_QR_CODE",
                comment: "Label for the 'share group link via QR code' button in the 'group link' view.",
            ),
            style: .default,
        ) { _ in
            Self.shareLinkViaQRCode(
                groupInviteLinkUrl: inviteLink.url(),
                fromViewController: fromViewController,
            )
        })
        actionSheet.addAction(ActionSheetAction(
            title: OWSLocalizedString(
                "GROUP_LINK_VIEW_SHARE_LINK_VIA_IOS_SHARING",
                comment: "Label for the 'share group link via iOS sharing UI' button in the 'group link' view.",
            ),
            style: .default,
        ) { _ in
            Self.shareLinkViaSharingUI(groupInviteLinkUrl: inviteLink.url())
        })
        actionSheet.addAction(OWSActionSheets.cancelAction)
        fromViewController.presentActionSheet(actionSheet)
    }

    private static func shareLinkViaSignal(
        groupInviteLinkUrl: URL,
        fromViewController: UIViewController,
        sendMessageController: SendMessageController,
    ) {
        guard let navigationController = fromViewController.navigationController else {
            owsFailDebug("Missing navigationController.")
            return
        }
        let messageBody = MessageBody(text: groupInviteLinkUrl.absoluteString, ranges: .empty)
        guard let unapprovedContent = SendMessageUnapprovedContent(messageBody: messageBody) else {
            owsFailDebug("Missing messageBody.")
            return
        }
        let sendMessageFlow = SendMessageFlow(
            unapprovedContent: unapprovedContent,
            presentationStyle: .pushOnto(navigationController),
            delegate: sendMessageController,
        )
        // Retain the flow until it is complete.
        sendMessageController.sendMessageFlow.set(sendMessageFlow)
    }

    private static func copyLinkToPasteboard(groupInviteLinkUrl: URL) {
        UIPasteboard.general.url = groupInviteLinkUrl
    }

    private static func shareLinkViaQRCode(
        groupInviteLinkUrl: URL,
        fromViewController: UIViewController,
    ) {
        let qrCodeView = GroupLinkQRCodeViewController(groupInviteLinkUrl: groupInviteLinkUrl)
        fromViewController.navigationController?.pushViewController(qrCodeView, animated: true)
    }

    private static func shareLinkViaSharingUI(groupInviteLinkUrl: URL) {
        AttachmentSharing.showShareUI(for: groupInviteLinkUrl, sender: self)
    }
}

// MARK: -

private extension GroupLinkViewController {

    func updateLinkMode(linkMode: GroupInviteLinkMode) {
        GroupLinkViewUtils.updateLinkMode(
            secretParams: secretParams,
            linkMode: linkMode,
            fromViewController: self,
            completion: { [weak self] in self?.didModifyGroup() },
        )
    }

    func resetLink() {
        GroupViewUtils.updateGroupWithActivityIndicator(
            fromViewController: self,
            updateBlock: { [secretParams] in
                try await GroupManager.resetLinkV2(secretParams: secretParams)
            },
            completion: { [weak self] in self?.didModifyGroup() },
        )
    }
}
