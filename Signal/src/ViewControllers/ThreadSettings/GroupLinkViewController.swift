//
//  Copyright (c) 2021 Open Whisper Systems. All rights reserved.
//

import Foundation
import PromiseKit

protocol GroupLinkViewControllerDelegate: class {
    func groupLinkViewViewDidUpdate()
}

// MARK: -

@objc
public class GroupLinkViewController: OWSTableViewController {

    weak var groupLinkViewControllerDelegate: GroupLinkViewControllerDelegate?

    private var groupModelV2: TSGroupModelV2

    required init(groupModelV2: TSGroupModelV2) {
        self.groupModelV2 = groupModelV2

        super.init()
    }

    // MARK: - View Lifecycle

    @objc
    public override func viewDidLoad() {
        super.viewDidLoad()

        title = NSLocalizedString("GROUP_LINK_VIEW_TITLE",
                                  comment: "The title for the 'group link' view.")

        self.useThemeBackgroundColors = true

        updateTableContents()
    }

    // MARK: -

    private func updateTableContents() {
        let groupModelV2 = self.groupModelV2
        let canEditGroupLinkSettings = groupModelV2.groupMembership.isLocalUserFullMemberAndAdministrator

        let contents = OWSTableContents()

        // MARK: - Enable

        do {
            let section = OWSTableSection()
            section.headerTitle = NSLocalizedString("GROUP_LINK_VIEW_MANAGE_AND_SHARE_SECTION_TITLE",
                                                    comment: "Title for the 'manage and share' section of the 'group link' view.")
            let switchAction = #selector(didToggleGroupLinkEnabled(_:))
            section.add(OWSTableItem(customCellBlock: { [weak self] () -> UITableViewCell in
                guard let self = self else {
                    owsFailDebug("Missing self")
                    return OWSTableItem.newCell()
                }
                let cell = OWSTableItem.newCell()
                cell.preservesSuperviewLayoutMargins = true
                cell.contentView.preservesSuperviewLayoutMargins = true
                cell.selectionStyle = .none

                let rowLabel = UILabel()
                rowLabel.text = NSLocalizedString("GROUP_LINK_VIEW_ENABLE_GROUP_LINK_SWITCH",
                                                  comment: "Label for the 'enable group link' switch in the 'group link' view.")
                rowLabel.textColor = Theme.primaryTextColor
                rowLabel.font = OWSTableItem.primaryLabelFont
                rowLabel.lineBreakMode = .byTruncatingTail

                let switchView = UISwitch()
                switchView.isOn = groupModelV2.isGroupInviteLinkEnabled
                switchView.addTarget(self, action: switchAction, for: .valueChanged)
                switchView.isEnabled = true

                let topRow = UIStackView(arrangedSubviews: [ rowLabel, switchView ])
                topRow.spacing = 16
                topRow.alignment = .center

                let vStack = UIStackView(arrangedSubviews: [ topRow ])
                vStack.axis = .vertical
                vStack.alignment = .fill
                vStack.spacing = 10
                cell.contentView.addSubview(vStack)
                vStack.autoPinEdgesToSuperviewMargins()

                if groupModelV2.isGroupInviteLinkEnabled {
                    do {
                        let inviteLinkUrl = try GroupManager.groupInviteLink(forGroupModelV2: groupModelV2)
                        let urlLabel = UILabel()
                        urlLabel.text = inviteLinkUrl.absoluteString
                        urlLabel.font = .ows_dynamicTypeSubheadline
                        urlLabel.textColor = Theme.secondaryTextAndIconColor
                        urlLabel.numberOfLines = 0
                        urlLabel.lineBreakMode = .byCharWrapping
                        vStack.addArrangedSubview(urlLabel)
                    } catch {
                        owsFailDebug("Error: \(error)")
                    }
                }

                switchView.accessibilityIdentifier = "group_link_view_enable_group_link_switch"
                cell.accessibilityIdentifier = "group_link_view_enable_group_link"

                return cell
            }))

            if groupModelV2.isGroupInviteLinkEnabled {
                section.add(OWSTableItem.actionItem(icon: ThemeIcon.messageActionShare,
                                                    tintColor: Theme.accentBlueColor,
                                                    name: NSLocalizedString("GROUP_LINK_VIEW_SHARE_LINK",
                                                                                comment: "Label for the 'share link' button in the 'group link' view."),
                                                    textColor: Theme.accentBlueColor,
                                                    accessibilityIdentifier: "group_link_view_share_link",
                                                    actionBlock: { [weak self] in
                                                        self?.shareLinkPressed()
                }))
                section.add(OWSTableItem.actionItem(icon: ThemeIcon.retry24,
                                                    tintColor: Theme.accentBlueColor,
                                                    name: NSLocalizedString("GROUP_LINK_VIEW_RESET_LINK",
                                                                            comment: "Label for the 'reset link' button in the 'group link' view."),
                                                    textColor: Theme.accentBlueColor,
                                                    accessibilityIdentifier: "group_link_view_reset_link",
                                                    actionBlock: { [weak self] in
                                                        self?.resetLinkPressed()
                }))
            }

            contents.addSection(section)
        }

        // MARK: - Member Requests

        do {
            let section = OWSTableSection()
            section.headerTitle = NSLocalizedString("GROUP_LINK_VIEW_MEMBER_REQUESTS_SECTION_TITLE",
                                                    comment: "Title for the 'member requests' section of the 'group link' view.")
            section.footerTitle = NSLocalizedString("GROUP_LINK_VIEW_MEMBER_REQUESTS_SECTION_FOOTER",
                                                    comment: "Footer for the 'member requests' section of the 'group link' view.")
            section.add(OWSTableItem.switch(withText: NSLocalizedString("GROUP_LINK_VIEW_APPROVE_NEW_MEMBERS_SWITCH",
                                                                        comment: "Label for the 'approve new members' switch in the 'group link' view."),
                                            isOn: { groupModelV2.access.addFromInviteLink == .administrator },
                                            isEnabledBlock: {
                                                true
            },
                                            target: self,
                                            selector: #selector(didToggleApproveNewMembers(_:))))
            contents.addSection(section)
        }

        self.contents = contents
    }

    fileprivate func updateView(groupThread: TSGroupThread) {
        guard let groupModelV2 = groupThread.groupModel as? TSGroupModelV2 else {
            owsFailDebug("Invalid thread.")
            navigationController?.popViewController(animated: true)
            return
        }

        groupLinkViewControllerDelegate?.groupLinkViewViewDidUpdate()

        self.groupModelV2 = groupModelV2
        updateTableContents()
    }

    // MARK: - Events

    @objc
    func didToggleGroupLinkEnabled(_ sender: UISwitch) {
        let canEditGroupLinkSettings = groupModelV2.groupMembership.isLocalUserFullMemberAndAdministrator
        guard canEditGroupLinkSettings else {
            let message = NSLocalizedString("GROUP_ADMIN_ONLY_WARNING",
                                            comment: "Message indicating that a feature can only be used by group admins.")
            showToast(message: message)
            updateTableContents()
            return
        }

        let isGroupInviteLinkEnabled = sender.isOn
        // Whenever we activate the group link, default to _not_ requiring admin approval.
        let approveNewMembers = groupModelV2.access.addFromInviteLink == .administrator

        let linkMode = GroupLinkViewUtils.linkMode(isGroupInviteLinkEnabled: isGroupInviteLinkEnabled,
                                                   approveNewMembers: approveNewMembers)
        updateLinkMode(linkMode: linkMode)
    }

    @objc
    func didToggleApproveNewMembers(_ sender: UISwitch) {
        guard groupModelV2.isGroupInviteLinkEnabled else {
            return
        }
        let canEditGroupLinkSettings = groupModelV2.groupMembership.isLocalUserFullMemberAndAdministrator
        guard canEditGroupLinkSettings else {
            let message = NSLocalizedString("GROUP_ADMIN_ONLY_WARNING",
                                            comment: "Message indicating that a feature can only be used by group admins.")
            showToast(message: message)
            updateTableContents()
            return
        }

        let isGroupInviteLinkEnabled = groupModelV2.isGroupInviteLinkEnabled
        let linkMode = GroupLinkViewUtils.linkMode(isGroupInviteLinkEnabled: isGroupInviteLinkEnabled,
                                                   approveNewMembers: sender.isOn)
        updateLinkMode(linkMode: linkMode)
    }

    private func showToast(message: String) {
        let toastController = ToastController(text: message)
        let toastInset = bottomLayoutGuide.length + 8
        toastController.presentToastView(fromBottomOfView: view, inset: toastInset)
    }

    func shareLinkPressed() {
        showShareLinkAlert()
    }

    func resetLinkPressed() {
        showResetLinkConfirmAlert()
    }

    // We need to retain a link to this delegate during the send flow.
    private var sendMessageController: SendMessageController?

    private func showShareLinkAlert() {
        let sendMessageController = SendMessageController(fromViewController: self)
        self.sendMessageController = sendMessageController
        GroupLinkViewUtils.showShareLinkAlert(groupModelV2: groupModelV2,
                                              fromViewController: self,
                                              sendMessageController: sendMessageController)
    }

    private func showResetLinkConfirmAlert() {
        let alertTitle = NSLocalizedString("GROUP_LINK_VIEW_RESET_LINK_CONFIRM_ALERT_TITLE",
                                           comment: "Title for the 'confirm reset link' alert in the 'group link' view.")
        let actionSheet = ActionSheetController(title: alertTitle)
        let resetTitle = NSLocalizedString("GROUP_LINK_VIEW_RESET_LINK",
                                           comment: "Label for the 'reset link' button in the 'group link' view.")
        actionSheet.addAction(ActionSheetAction(title: resetTitle,
                                                style: .destructive) { _ in
                                                    self.resetLink()
        })
        actionSheet.addAction(OWSActionSheets.cancelAction)
        presentActionSheet(actionSheet)
    }
}

// MARK: -

public class GroupLinkViewUtils {

    static func updateLinkMode(groupModelV2: TSGroupModelV2,
                               linkMode: GroupsV2LinkMode,
                               description: String,
                               fromViewController: UIViewController,
                               completion: @escaping (TSGroupThread) -> Void) {
        GroupViewUtils.updateGroupWithActivityIndicator(fromViewController: fromViewController,
                                                        updatePromiseBlock: { () -> Promise<TSGroupThread> in
                                                            self.updateLinkModePromise(groupModelV2: groupModelV2,
                                                                                       linkMode: linkMode,
                                                                                       description: description)
                                                        },
                                                        completion: { (groupThread: TSGroupThread?) in
                                                            guard let groupThread = groupThread else {
                                                                owsFailDebug("Missing groupThread.")
                                                                return
                                                            }
                                                            completion(groupThread)
                                                        })
    }

    static func updateLinkModePromise(groupModelV2: TSGroupModelV2,
                                      linkMode: GroupsV2LinkMode,
                                      description: String) -> Promise<TSGroupThread> {
        return firstly { () -> Promise<Void> in
            return GroupManager.messageProcessingPromise(for: groupModelV2, description: description)
        }.then(on: .global()) { _ in
            GroupManager.updateLinkModeV2(groupModel: groupModelV2, linkMode: linkMode)
        }
    }

    static func linkMode(isGroupInviteLinkEnabled: Bool, approveNewMembers: Bool) -> GroupsV2LinkMode {
        if isGroupInviteLinkEnabled {
            return (approveNewMembers ? .enabledWithApproval : .enabledWithoutApproval)
        } else {
            return .disabled
        }
    }

    // MARK: -

    public static func showShareLinkAlert(groupModelV2: TSGroupModelV2,
                                          fromViewController: UIViewController,
                                          sendMessageController: SendMessageController) {
        let message = NSLocalizedString("GROUP_LINK_VIEW_SHARE_SHEET_MESSAGE",
                                        comment: "Message for the 'share group link' action sheet in the 'group link' view.")
        let actionSheet = ActionSheetController(message: message)
        actionSheet.addAction(ActionSheetAction(title: NSLocalizedString("GROUP_LINK_VIEW_SHARE_LINK_VIA_SIGNAL",
                                                                         comment: "Label for the 'share group link via Signal' button in the 'group link' view."),
                                                style: .default) { _ in
            Self.shareLinkViaSignal(groupModelV2: groupModelV2,
                                    fromViewController: fromViewController,
                                    sendMessageController: sendMessageController)
        })
        actionSheet.addAction(ActionSheetAction(title: NSLocalizedString("GROUP_LINK_VIEW_COPY_LINK",
                                                                         comment: "Label for the 'copy link' button in the 'group link' view."),
                                                style: .default) { _ in
            Self.copyLinkToPasteboard(groupModelV2: groupModelV2)
        })
        actionSheet.addAction(ActionSheetAction(title: NSLocalizedString("GROUP_LINK_VIEW_SHARE_LINK_VIA_QR_CODE",
                                                                         comment: "Label for the 'share group link via QR code' button in the 'group link' view."),
                                                style: .default) { _ in
            Self.shareLinkViaQRCode(groupModelV2: groupModelV2,
                                    fromViewController: fromViewController)
        })
        actionSheet.addAction(ActionSheetAction(title: NSLocalizedString("GROUP_LINK_VIEW_SHARE_LINK_VIA_IOS_SHARING",
                                                                         comment: "Label for the 'share group link via iOS sharing UI' button in the 'group link' view."),
                                                style: .default) { _ in
            Self.shareLinkViaSharingUI(groupModelV2: groupModelV2)
        })
        actionSheet.addAction(OWSActionSheets.cancelAction)
        fromViewController.presentActionSheet(actionSheet)
    }

    private static func shareLinkViaSignal(groupModelV2: TSGroupModelV2,
                                           fromViewController: UIViewController,
                                           sendMessageController: SendMessageController) {
        guard let navigationController = fromViewController.navigationController else {
            owsFailDebug("Missing navigationController.")
            return
        }

        do {
            let inviteLinkUrl = try GroupManager.groupInviteLink(forGroupModelV2: groupModelV2)
            let messageBody = MessageBody(text: inviteLinkUrl.absoluteString, ranges: .empty)
            let unapprovedContent = SendMessageUnapprovedContent.text(messageBody: messageBody)
            let sendMessageFlow = SendMessageFlow(flowType: .`default`,
                                                  unapprovedContent: unapprovedContent,
                                                  useConversationComposeForSingleRecipient: true,
                                                  navigationController: navigationController,
                                                  delegate: sendMessageController)
            // Retain the flow until it is complete.
            sendMessageController.sendMessageFlow.set(sendMessageFlow)
        } catch {
            owsFailDebug("Error: \(error)")
        }
    }

    private static func copyLinkToPasteboard(groupModelV2: TSGroupModelV2) {
        guard groupModelV2.isGroupInviteLinkEnabled else {
            owsFailDebug("Group link not enabled.")
            return
        }
        do {
            let inviteLinkUrl = try GroupManager.groupInviteLink(forGroupModelV2: groupModelV2)
            UIPasteboard.general.url = inviteLinkUrl
        } catch {
            owsFailDebug("Error: \(error)")
        }
    }

    private static func shareLinkViaQRCode(groupModelV2: TSGroupModelV2,
                                           fromViewController: UIViewController) {
        let qrCodeView = GroupLinkQRCodeViewController(groupModelV2: groupModelV2)
        fromViewController.navigationController?.pushViewController(qrCodeView, animated: true)
    }

    private static func shareLinkViaSharingUI(groupModelV2: TSGroupModelV2) {
        guard groupModelV2.isGroupInviteLinkEnabled else {
            owsFailDebug("Group link not enabled.")
            return
        }
        do {
            let inviteLinkUrl = try GroupManager.groupInviteLink(forGroupModelV2: groupModelV2)
            AttachmentSharing.showShareUI(for: inviteLinkUrl, sender: self)
        } catch {
            owsFailDebug("Error: \(error)")
        }
    }
}

// MARK: -

private extension GroupLinkViewController {

    func updateLinkMode(linkMode: GroupsV2LinkMode) {
        GroupLinkViewUtils.updateLinkMode(groupModelV2: groupModelV2,
                                          linkMode: linkMode,
                                          description: self.logTag,
                                          fromViewController: self) { [weak self] groupThread in
            self?.updateView(groupThread: groupThread)
        }
    }

    func resetLink() {
        GroupViewUtils.updateGroupWithActivityIndicator(fromViewController: self,
                                                        updatePromiseBlock: { () -> Promise<TSGroupThread> in
                                                            self.resetLinkPromise()
        },
                                                        completion: { [weak self] (groupThread: TSGroupThread?) in
                                                            guard let groupThread = groupThread else {
                                                                owsFailDebug("Missing groupThread.")
                                                                return
                                                            }
                                                            self?.updateView(groupThread: groupThread)
        })
    }

    func resetLinkPromise() -> Promise<TSGroupThread> {
        let groupModelV2 = self.groupModelV2
        return firstly { () -> Promise<Void> in
            return GroupManager.messageProcessingPromise(for: groupModelV2, description: self.logTag)
        }.then(on: .global()) { _ in
            GroupManager.resetLinkV2(groupModel: groupModelV2)
        }
    }
}
