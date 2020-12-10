//
//  Copyright (c) 2020 Open Whisper Systems. All rights reserved.
//

import Foundation
import PromiseKit

protocol GroupMemberRequestsAndInvitesViewControllerDelegate: class {
    func requestsAndInvitesViewDidUpdate()
}

// MARK: -

@objc
public class GroupMemberRequestsAndInvitesViewController: OWSTableViewController {

    weak var groupMemberRequestsAndInvitesViewControllerDelegate: GroupMemberRequestsAndInvitesViewControllerDelegate?

    private let oldGroupThread: TSGroupThread

    private var groupModel: TSGroupModel

    private let groupViewHelper: GroupViewHelper

    private enum Mode: Int, CaseIterable {
        case memberRequests = 0
        case pendingInvites = 1

        var title: String {
            switch self {
            case .memberRequests:
                return NSLocalizedString("GROUP_REQUESTS_AND_INVITES_VIEW_MEMBER_REQUESTS_MODE",
                                         comment: "Label for the 'member requests' mode of the 'group requests and invites' view.")
            case .pendingInvites:
                return NSLocalizedString("GROUP_REQUESTS_AND_INVITES_VIEW_PENDING_INVITES_MODE",
                                         comment: "Label for the 'pending invites' mode of the 'group requests and invites' view.")
            }
        }
    }

    private let segmentedControl = UISegmentedControl()

    required init(groupThread: TSGroupThread, groupViewHelper: GroupViewHelper) {
        self.oldGroupThread = groupThread
        self.groupModel = groupThread.groupModel
        self.groupViewHelper = groupViewHelper

        super.init()
    }

    // MARK: - View Lifecycle

    @objc
    public override func viewDidLoad() {
        super.viewDidLoad()

        if RemoteConfig.groupsV2InviteLinks {
            title = NSLocalizedString("GROUP_REQUESTS_AND_INVITES_VIEW_TITLE",
                                      comment: "The title for the 'group requests and invites' view.")
        } else {
            title = NSLocalizedString("GROUP_INVITES_VIEW_TITLE",
                                      comment: "The title for the 'group invites' view.")
        }

        self.useThemeBackgroundColors = false

        configureSegmentedControl()

        updateTableContents()
    }

    private func configureSegmentedControl() {
        for mode in Mode.allCases {
            assert(mode.rawValue == segmentedControl.numberOfSegments)
            segmentedControl.insertSegment(withTitle: mode.title, at: mode.rawValue, animated: false)
        }
        segmentedControl.selectedSegmentIndex = 0
        segmentedControl.addTarget(self, action: #selector(segmentedControlDidChange), for: .valueChanged)
    }

    @objc
    func segmentedControlDidChange(_ sender: UISwitch) {
        updateTableContents()
    }

    // MARK: -

    private func updateTableContents() {
        let contents = OWSTableContents()

        var mode = Mode.pendingInvites
        if RemoteConfig.groupsV2InviteLinks {
            let modeSection = OWSTableSection()
            let modeHeader = UIStackView(arrangedSubviews: [segmentedControl])
            modeHeader.axis = .vertical
            modeHeader.alignment = .fill
            modeHeader.layoutMargins = UIEdgeInsets(top: 20, leading: 20, bottom: 20, trailing: 20)
            modeHeader.isLayoutMarginsRelativeArrangement = true
            modeSection.customHeaderView = modeHeader
            contents.addSection(modeSection)

            guard let parsedMode = Mode(rawValue: segmentedControl.selectedSegmentIndex) else {
                owsFailDebug("Invalid mode.")
                return
            }
            mode = parsedMode
        }

        switch mode {
        case .memberRequests:
            addContentsForMemberRequests(contents: contents)
        case .pendingInvites:
            addContentsForPendingInvites(contents: contents)
        }

        self.contents = contents
    }

    private func addContentsForMemberRequests(contents: OWSTableContents) {

        let canApproveMemberRequests = groupViewHelper.canApproveMemberRequests

        let groupMembership = groupModel.groupMembership
        let requestingMembersSorted = databaseStorage.uiRead { transaction in
            self.contactsManager.sortSignalServiceAddresses(Array(groupMembership.requestingMembers),
                                                            transaction: transaction)
        }

        let section = OWSTableSection()
        section.headerTitle = NSLocalizedString("PENDING_GROUP_MEMBERS_SECTION_TITLE_PENDING_MEMBER_REQUESTS",
                                                comment: "Title for the 'pending member requests' section of the 'member requests and invites' view.")
        let footerFormat = NSLocalizedString("PENDING_GROUP_MEMBERS_SECTION_FOOTER_PENDING_MEMBER_REQUESTS_FORMAT",
                                                comment: "Footer for the 'pending member requests' section of the 'member requests and invites' view. Embeds {{ the name of the group }}.")
        let groupName = self.contactsManager.displayNameWithSneakyTransaction(thread: oldGroupThread)
        section.footerTitle = String(format: footerFormat, groupName)

        if !requestingMembersSorted.isEmpty {
            for address in requestingMembersSorted {
                section.add(OWSTableItem(customCellBlock: { [weak self] in
                    guard let self = self else {
                        owsFailDebug("Missing self")
                        return OWSTableItem.newCell()
                    }

                    let cell = ContactTableViewCell(style: .default, reuseIdentifier: nil, allowUserInteraction: true)

                    if canApproveMemberRequests {
                        cell.ows_setAccessoryView(self.buildMemberRequestButtons(address: address))
                    }

                    if address.isLocalAddress {
                        // Use a custom avatar to avoid using the "note to self" icon.
                        let customAvatar: UIImage?
                        if let localProfileAvatarImage = OWSProfileManager.shared().localProfileAvatarImage() {
                            customAvatar = localProfileAvatarImage
                        } else {
                            customAvatar = Self.databaseStorage.uiRead { transaction in
                                OWSContactAvatarBuilder(forLocalUserWithDiameter: kSmallAvatarSize,
                                                        transaction: transaction).buildDefaultImage()
                            }
                        }
                        cell.setCustomAvatar(customAvatar)
                        cell.setCustomName(NSLocalizedString("GROUP_MEMBER_LOCAL_USER",
                                                             comment: "Label indicating the local user."))
                        cell.selectionStyle = .none
                    } else {
                        cell.selectionStyle = .default
                    }

                    cell.configureWithSneakyTransaction(recipientAddress: address)
                    return cell
                    }) { [weak self] in
                                                self?.showMemberActionSheet(for: address)
                })
            }
        } else {
            section.add(OWSTableItem.softCenterLabel(withText: NSLocalizedString("PENDING_GROUP_MEMBERS_NO_PENDING_MEMBER_REQUESTS",
                                                                                      comment: "Label indicating that a group has no pending member requests."),
                                                          customRowHeight: UITableView.automaticDimension))
        }
        contents.addSection(section)
    }

    private func buildMemberRequestButtons(address: SignalServiceAddress) -> UIView {
        let denyButton = OWSButton()
        denyButton.setTemplateImageName("deny-28", tintColor: Theme.primaryIconColor)
        denyButton.accessibilityIdentifier = "member-request-deny"
        denyButton.block = { [weak self] in
            self?.denyMemberRequest(address: address)
        }

        let approveButton = OWSButton()
        approveButton.setTemplateImageName("approve-28", tintColor: Theme.primaryIconColor)
        approveButton.accessibilityIdentifier = "member-request-approveButton"
        approveButton.block = { [weak self] in
            self?.approveMemberRequest(address: address)
        }

        let stackView = UIStackView(arrangedSubviews: [denyButton, approveButton])
        stackView.axis = .horizontal
        stackView.spacing = 18
        return stackView
    }

    private func approveMemberRequest(address: SignalServiceAddress) {
        showAcceptMemberRequestUI(address: address)
    }

    private func denyMemberRequest(address: SignalServiceAddress) {
        showDenyMemberRequestUI(address: address)
    }

    private func addContentsForPendingInvites(contents: OWSTableContents) {
        guard let localAddress = tsAccountManager.localAddress else {
            owsFailDebug("missing local address")
            return
        }

        let groupMembership = groupModel.groupMembership
        let allPendingMembersSorted = databaseStorage.uiRead { transaction in
            self.contactsManager.sortSignalServiceAddresses(Array(groupMembership.invitedMembers),
                                                            transaction: transaction)
        }

        // Note that these collections retain their sorting from above.
        var membersInvitedByLocalUser = [SignalServiceAddress]()
        var membersInvitedByOtherUsers = [SignalServiceAddress: [SignalServiceAddress]]()
        for invitedAddress in allPendingMembersSorted {
            guard let inviterUuid = groupMembership.addedByUuid(forInvitedMember: invitedAddress) else {
                owsFailDebug("Missing inviter.")
                continue
            }
            let inviterAddress = SignalServiceAddress(uuid: inviterUuid)
            if inviterAddress == localAddress {
                membersInvitedByLocalUser.append(invitedAddress)
            } else {
                var invitedMembers: [SignalServiceAddress] = membersInvitedByOtherUsers[inviterAddress] ?? []
                invitedMembers.append(invitedAddress)
                membersInvitedByOtherUsers[inviterAddress] = invitedMembers
            }
        }

        // Only admins can revoke invites.
        let canRevokeInvites = groupViewHelper.canRevokePendingInvites

        // MARK: - People You Invited

        let localSection = OWSTableSection()
        localSection.headerTitle = NSLocalizedString("PENDING_GROUP_MEMBERS_SECTION_TITLE_PEOPLE_YOU_INVITED",
                                                     comment: "Title for the 'people you invited' section of the 'member requests and invites' view.")
        if membersInvitedByLocalUser.count > 0 {
            for address in membersInvitedByLocalUser {
                localSection.add(OWSTableItem(customCellBlock: { [weak self] in
                    guard let self = self else {
                        owsFailDebug("Missing self")
                        return OWSTableItem.newCell()
                    }

                    let cell = ContactTableViewCell()
                    cell.selectionStyle = canRevokeInvites ? .default : .none

                    cell.configureWithSneakyTransaction(recipientAddress: address)
                    return cell
                    }) { [weak self] in
                                                self?.inviteFromLocalUserWasTapped(address,
                                                                                   canRevoke: canRevokeInvites)
                })
            }
        } else {
            localSection.add(OWSTableItem.softCenterLabel(withText: NSLocalizedString("PENDING_GROUP_MEMBERS_NO_PENDING_MEMBERS",
                                                                                      comment: "Label indicating that a group has no pending members."),
                                                          customRowHeight: UITableView.automaticDimension))
        }
        contents.addSection(localSection)

        // MARK: - Other Users

        let otherUsersSection = OWSTableSection()
        otherUsersSection.headerTitle = NSLocalizedString("PENDING_GROUP_MEMBERS_SECTION_TITLE_INVITES_FROM_OTHER_MEMBERS",
                                                          comment: "Title for the 'invites by other group members' section of the 'member requests and invites' view.")
        otherUsersSection.footerTitle = NSLocalizedString("PENDING_GROUP_MEMBERS_SECTION_FOOTER_INVITES_FROM_OTHER_MEMBERS",
                                                          comment: "Footer for the 'invites by other group members' section of the 'member requests and invites' view.")

        if membersInvitedByOtherUsers.count > 0 {
            let inviterAddresses = databaseStorage.uiRead { transaction in
                self.contactsManager.sortSignalServiceAddresses(Array(membersInvitedByOtherUsers.keys),
                                                                transaction: transaction)
            }
            for inviterAddress in inviterAddresses {
                guard let invitedAddresses = membersInvitedByOtherUsers[inviterAddress] else {
                    owsFailDebug("Missing invited addresses.")
                    continue
                }

                otherUsersSection.add(OWSTableItem(customCellBlock: { [weak self] in
                    guard let self = self else {
                        owsFailDebug("Missing self")
                        return OWSTableItem.newCell()
                    }

                    let cell = ContactTableViewCell()
                    cell.selectionStyle = canRevokeInvites ? .default : .none

                    let inviterName = self.contactsManager.displayName(for: inviterAddress)
                    let customName: String
                    if invitedAddresses.count > 1 {
                        let format = NSLocalizedString("PENDING_GROUP_MEMBERS_MEMBER_INVITED_N_USERS_FORMAT",
                                                       comment: "Format for label indicating the a group member has invited N other users to the group. Embeds {{ %1$@ name of the inviting group member, %2$@ the number of users they have invited. }}.")
                        customName = String(format: format, inviterName, OWSFormat.formatInt(invitedAddresses.count))
                    } else {
                        let format = NSLocalizedString("PENDING_GROUP_MEMBERS_MEMBER_INVITED_1_USER_FORMAT",
                                                       comment: "Format for label indicating the a group member has invited 1 other user to the group. Embeds {{ the name of the inviting group member. }}.")
                        customName = String(format: format, inviterName)
                    }
                    cell.setCustomName(customName)

                    cell.configureWithSneakyTransaction(recipientAddress: inviterAddress)

                    return cell
                    }) { [weak self] in
                                                    self?.invitesFromOtherUserWasTapped(invitedAddresses: invitedAddresses,
                                                                                        inviterAddress: inviterAddress,
                                                                                        canRevoke: canRevokeInvites)
                })
            }
        } else {
            otherUsersSection.add(OWSTableItem.softCenterLabel(withText: NSLocalizedString("PENDING_GROUP_MEMBERS_NO_PENDING_MEMBERS",
                                                                                           comment: "Label indicating that a group has no pending members."),
                                                               customRowHeight: UITableView.automaticDimension))
        }
        contents.addSection(otherUsersSection)

        // MARK: - Invalid Invites

        let invalidInvitesCount = groupMembership.invalidInvites.count
        if canRevokeInvites, invalidInvitesCount > 0 {
            let invalidInvitesSection = OWSTableSection()
            invalidInvitesSection.headerTitle = NSLocalizedString("PENDING_GROUP_MEMBERS_SECTION_TITLE_INVALID_INVITES",
                                                                  comment: "Title for the 'invalid invites' section of the 'member requests and invites' view.")

            let cellTitle: String
            if invalidInvitesCount > 1 {
                let format = NSLocalizedString("PENDING_GROUP_MEMBERS_REVOKE_INVALID_INVITES_N_FORMAT",
                                               comment: "Format for 'revoke invalid N invites' item. Embeds {{ the number of invalid invites. }}.")
                cellTitle = String(format: format, OWSFormat.formatInt(invalidInvitesCount))
            } else {
                cellTitle = NSLocalizedString("PENDING_GROUP_MEMBERS_REVOKE_INVALID_INVITE_1",
                                              comment: "Format for 'revoke invalid 1 invite' item.")
            }

            invalidInvitesSection.add(OWSTableItem.disclosureItem(withText: cellTitle) { [weak self] in
                self?.revokeInvalidInvites()
            })
            contents.addSection(invalidInvitesSection)
        }
    }

    fileprivate func reloadContent(groupThread: TSGroupThread?) {
        groupMemberRequestsAndInvitesViewControllerDelegate?.requestsAndInvitesViewDidUpdate()

        guard let newModel = { () -> TSGroupModel? in
            if let groupThread = groupThread {
                return groupThread.groupModel
            }
            return databaseStorage.read { (transaction) -> TSGroupModel? in
                guard let groupThread = TSGroupThread.fetch(groupId: self.groupModel.groupId,
                                                            transaction: transaction) else {
                    owsFailDebug("Missing group thread.")
                    return nil
                }
                return groupThread.groupModel
            }
        }() else {
            navigationController?.popViewController(animated: true)
            return
        }

        groupModel = newModel
        updateTableContents()
    }

    private func showRevokePendingInviteFromLocalUserConfirmation(invitedAddress: SignalServiceAddress) {

        let invitedName = contactsManager.displayName(for: invitedAddress)
        let format = NSLocalizedString("PENDING_GROUP_MEMBERS_REVOKE_LOCAL_INVITE_CONFIRMATION_TITLE_1_FORMAT",
                                       comment: "Format for title of 'revoke invite' confirmation alert. Embeds {{ the name of the invited group member. }}.")
        let alertTitle = String(format: format, invitedName)
        let actionSheet = ActionSheetController(title: alertTitle)
        actionSheet.addAction(ActionSheetAction(title: NSLocalizedString("PENDING_GROUP_MEMBERS_REVOKE_INVITE_1_BUTTON",
                                                                         comment: "Title of 'revoke invite' button."),
                                                style: .destructive) { _ in
                                                    self.revokePendingInvites(addresses: [invitedAddress])
        })
        actionSheet.addAction(OWSActionSheets.cancelAction)
        presentActionSheet(actionSheet)
    }

    private func showRevokePendingInviteFromOtherUserConfirmation(invitedAddresses: [SignalServiceAddress],
                                                                  inviterAddress: SignalServiceAddress) {

        let isPlural = invitedAddresses.count != 1
        let inviterName = contactsManager.displayName(for: inviterAddress)
        let alertTitle: String
        if isPlural {
            let format = NSLocalizedString("PENDING_GROUP_MEMBERS_REVOKE_INVITE_CONFIRMATION_TITLE_N_FORMAT",
                                       comment: "Format for title of 'revoke invite' confirmation alert. Embeds {{ %1$@ the number of users they have invited, %2$@ name of the inviting group member. }}.")
            alertTitle = String(format: format, OWSFormat.formatInt(invitedAddresses.count), inviterName)
        } else {
            let format = NSLocalizedString("PENDING_GROUP_MEMBERS_REVOKE_INVITE_CONFIRMATION_TITLE_1_FORMAT",
                                       comment: "Format for title of 'revoke invite' confirmation alert. Embeds {{ the name of the inviting group member. }}.")
            alertTitle = String(format: format, inviterName)
        }
        let actionSheet = ActionSheetController(title: alertTitle)
        let actionTitle = (isPlural
            ? NSLocalizedString("PENDING_GROUP_MEMBERS_REVOKE_INVITE_N_BUTTON",
                                comment: "Title of 'revoke invites' button.")
            : NSLocalizedString("PENDING_GROUP_MEMBERS_REVOKE_INVITE_1_BUTTON",
                                comment: "Title of 'revoke invite' button."))
        actionSheet.addAction(ActionSheetAction(title: actionTitle,
                                                style: .destructive) { _ in
                                                    self.revokePendingInvites(addresses: invitedAddresses)
        })
        actionSheet.addAction(OWSActionSheets.cancelAction)
        presentActionSheet(actionSheet)
    }

    private func inviteFromLocalUserWasTapped(_ address: SignalServiceAddress,
                                              canRevoke: Bool) {
        if canRevoke {
            self.showRevokePendingInviteFromLocalUserConfirmation(invitedAddress: address)
        }
    }

    private func invitesFromOtherUserWasTapped(invitedAddresses: [SignalServiceAddress],
                                               inviterAddress: SignalServiceAddress,
                                               canRevoke: Bool) {
        if canRevoke {
            self.showRevokePendingInviteFromOtherUserConfirmation(invitedAddresses: invitedAddresses,
                                                                  inviterAddress: inviterAddress)
        }
    }

    private func showMemberActionSheet(for address: SignalServiceAddress) {
        let memberActionSheet = MemberActionSheet(address: address, groupViewHelper: groupViewHelper)
        memberActionSheet.present(fromViewController: self)
    }

    private func presentRequestApprovedToast(address: SignalServiceAddress) {
        let format = NSLocalizedString("PENDING_GROUP_MEMBERS_REQUEST_APPROVED_FORMAT",
                                       comment: "Message indicating that a request to join the group was successfully approved. Embeds {{ the name of the approved user }}.")
        let userName = contactsManager.displayName(for: address)
        let text = String(format: format, userName)
        presentToast(text: text)
    }

    private func presentRequestDeniedToast(address: SignalServiceAddress) {
        let format = NSLocalizedString("PENDING_GROUP_MEMBERS_REQUEST_DENIED_FORMAT",
                                       comment: "Message indicating that a request to join the group was successfully denied. Embeds {{ the name of the denied user }}.")
        let userName = contactsManager.displayName(for: address)
        let text = String(format: format, userName)
        presentToast(text: text)
    }

    private func presentToast(text: String) {
        let toastController = ToastController(text: text)
        let bottomInset = bottomLayoutGuide.length + 8
        toastController.presentToastView(fromBottomOfView: self.view, inset: bottomInset)
    }
}

// MARK: -

private extension GroupMemberRequestsAndInvitesViewController {

    func revokePendingInvites(addresses: [SignalServiceAddress]) {
        GroupViewUtils.updateGroupWithActivityIndicator(fromViewController: self,
                                                        updatePromiseBlock: {
                                                            self.revokePendingInvitesPromise(addresses: addresses)
        },
                                                        completion: { [weak self] groupThread in
                                                            self?.reloadContent(groupThread: groupThread)
        })
    }

    func revokePendingInvitesPromise(addresses: [SignalServiceAddress]) -> Promise<TSGroupThread> {
        guard let groupModelV2 = groupModel as? TSGroupModelV2 else {
            return Promise(error: OWSAssertionError("Invalid group model."))
        }
        let uuids = addresses.compactMap { $0.uuid }
        guard !uuids.isEmpty else {
            return Promise(error: OWSAssertionError("Invalid addresses."))
        }

        return firstly { () -> Promise<Void> in
            return GroupManager.messageProcessingPromise(for: groupModel,
                                                         description: self.logTag)
        }.then(on: .global()) { _ in
            GroupManager.removeFromGroupOrRevokeInviteV2(groupModel: groupModelV2, uuids: uuids)
        }
    }

    func revokeInvalidInvites() {
        GroupViewUtils.updateGroupWithActivityIndicator(fromViewController: self,
                                                        updatePromiseBlock: {
                                                            self.revokeInvalidInvitesPromise()
        },
                                                        completion: { [weak self] groupThread in
                                                            self?.reloadContent(groupThread: groupThread)
        })
    }

    func revokeInvalidInvitesPromise() -> Promise<TSGroupThread> {
        guard let groupModelV2 = groupModel as? TSGroupModelV2 else {
            return Promise(error: OWSAssertionError("Invalid group model."))
        }

        return firstly { () -> Promise<Void> in
            return GroupManager.messageProcessingPromise(for: groupModel,
                                                         description: self.logTag)
        }.then(on: .global()) { _ in
            GroupManager.revokeInvalidInvites(groupModel: groupModelV2)
        }
    }
}

// MARK: -

fileprivate extension GroupMemberRequestsAndInvitesViewController {

    func showAcceptMemberRequestUI(address: SignalServiceAddress) {

        let username = contactsManager.displayName(for: address)
        let format = NSLocalizedString("PENDING_GROUP_MEMBERS_ACCEPT_REQUEST_CONFIRMATION_TITLE_FORMAT",
                                       comment: "Title of 'accept member request to join group' confirmation alert. Embeds {{ the name of the requesting group member. }}.")
        let alertTitle = String(format: format, username)
        let actionSheet = ActionSheetController(title: alertTitle)

        let actionTitle = NSLocalizedString("PENDING_GROUP_MEMBERS_ACCEPT_REQUEST_BUTTON",
                                            comment: "Title of 'accept member request to join group' button.")
        actionSheet.addAction(ActionSheetAction(title: actionTitle,
                                                style: .destructive) { _ in
                                                    self.acceptOrDenyMemberRequests(address: address, shouldAccept: true)
        })

        actionSheet.addAction(OWSActionSheets.cancelAction)
        presentActionSheet(actionSheet)
    }

    func showDenyMemberRequestUI(address: SignalServiceAddress) {

        let username = contactsManager.displayName(for: address)
        let format = NSLocalizedString("PENDING_GROUP_MEMBERS_DENY_REQUEST_CONFIRMATION_TITLE_FORMAT",
                                       comment: "Title of 'deny member request to join group' confirmation alert. Embeds {{ the name of the requesting group member. }}.")
        let alertTitle = String(format: format, username)
        let actionSheet = ActionSheetController(title: alertTitle)

        let actionTitle = NSLocalizedString("PENDING_GROUP_MEMBERS_DENY_REQUEST_BUTTON",
                                            comment: "Title of 'deny member request to join group' button.")
        actionSheet.addAction(ActionSheetAction(title: actionTitle,
                                                style: .destructive) { _ in
                                                    self.acceptOrDenyMemberRequests(address: address, shouldAccept: false)
        })

        actionSheet.addAction(OWSActionSheets.cancelAction)
        presentActionSheet(actionSheet)
    }

    func acceptOrDenyMemberRequests(address: SignalServiceAddress, shouldAccept: Bool) {
        GroupViewUtils.updateGroupWithActivityIndicator(fromViewController: self,
                                                        updatePromiseBlock: {
                                                            self.acceptOrDenyMemberRequestsPromise(addresses: [address],
                                                                                             shouldAccept: shouldAccept)
        },
                                                        completion: { [weak self] groupThread in
                                                            guard let self = self else { return }
                                                            if shouldAccept {
                                                                self.presentRequestApprovedToast(address: address)
                                                            } else {
                                                                self.presentRequestDeniedToast(address: address)
                                                            }
                                                            self.reloadContent(groupThread: groupThread)
        })
    }

    func acceptOrDenyMemberRequestsPromise(addresses: [SignalServiceAddress], shouldAccept: Bool) -> Promise<TSGroupThread> {
        guard let groupModelV2 = groupModel as? TSGroupModelV2 else {
            return Promise(error: OWSAssertionError("Invalid group model."))
        }
        let uuids = addresses.compactMap { $0.uuid }
        guard !uuids.isEmpty else {
            return Promise(error: OWSAssertionError("Invalid addresses."))
        }

        return firstly { () -> Promise<Void> in
            return GroupManager.messageProcessingPromise(for: groupModel,
                                                         description: self.logTag)
        }.then(on: .global()) { _ in
            GroupManager.acceptOrDenyMemberRequestsV2(groupModel: groupModelV2, uuids: uuids, shouldAccept: shouldAccept)
        }
    }
}
