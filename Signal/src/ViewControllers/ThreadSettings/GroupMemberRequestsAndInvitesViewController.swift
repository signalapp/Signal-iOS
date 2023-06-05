//
// Copyright 2020 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import SignalCoreKit
import SignalMessaging
import SignalUI

protocol GroupMemberRequestsAndInvitesViewControllerDelegate: AnyObject {
    func requestsAndInvitesViewDidUpdate()
}

// MARK: -

public class GroupMemberRequestsAndInvitesViewController: OWSTableViewController2 {

    weak var groupMemberRequestsAndInvitesViewControllerDelegate: GroupMemberRequestsAndInvitesViewControllerDelegate?

    private let oldGroupThread: TSGroupThread

    private var groupModel: TSGroupModel

    private let groupViewHelper: GroupViewHelper

    private enum Mode: Int, CaseIterable {
        case memberRequests = 0
        case pendingInvites = 1
    }

    private let segmentedControl = UISegmentedControl()

    required init(groupThread: TSGroupThread, groupViewHelper: GroupViewHelper) {
        self.oldGroupThread = groupThread
        self.groupModel = groupThread.groupModel
        self.groupViewHelper = groupViewHelper

        super.init()
    }

    // MARK: - View Lifecycle

    public override func viewDidLoad() {
        super.viewDidLoad()

        title = OWSLocalizedString("GROUP_REQUESTS_AND_INVITES_VIEW_TITLE",
                                  comment: "The title for the 'group requests and invites' view.")

        defaultSeparatorInsetLeading = Self.cellHInnerMargin + CGFloat(AvatarBuilder.smallAvatarSizePoints) + ContactCellView.avatarTextHSpacing

        configureSegmentedControl()

        tableView.register(ContactTableViewCell.self, forCellReuseIdentifier: ContactTableViewCell.reuseIdentifier)

        updateTableContents()
    }

    private func configureSegmentedControl() {
        for mode in Mode.allCases {
            assert(mode.rawValue == segmentedControl.numberOfSegments)

            var title: String
            switch mode {
            case .memberRequests:
                title = OWSLocalizedString("GROUP_REQUESTS_AND_INVITES_VIEW_MEMBER_REQUESTS_MODE",
                                         comment: "Label for the 'member requests' mode of the 'group requests and invites' view.")
                if groupModel.groupMembership.requestingMembers.count > 0 {
                    title.append(" (\(OWSFormat.formatInt(groupModel.groupMembership.requestingMembers.count)))")
                }
            case .pendingInvites:
                title = OWSLocalizedString("GROUP_REQUESTS_AND_INVITES_VIEW_PENDING_INVITES_MODE",
                                         comment: "Label for the 'pending invites' mode of the 'group requests and invites' view.")
                if groupModel.groupMembership.invitedMembers.count > 0 {
                    title.append(" (\(OWSFormat.formatInt(groupModel.groupMembership.invitedMembers.count)))")
                }
            }

            segmentedControl.insertSegment(withTitle: title, at: mode.rawValue, animated: false)
        }
        segmentedControl.selectedSegmentIndex = 0
        segmentedControl.addTarget(self, action: #selector(segmentedControlDidChange), for: .valueChanged)
    }

    @objc
    private func segmentedControlDidChange(_ sender: UISwitch) {
        updateTableContents()
    }

    // MARK: -

    private func updateTableContents() {
        let contents = OWSTableContents()

        let modeSection = OWSTableSection()
        let modeHeader = UIStackView(arrangedSubviews: [segmentedControl])
        modeHeader.axis = .vertical
        modeHeader.alignment = .fill
        modeHeader.layoutMargins = UIEdgeInsets(top: 20, leading: 20, bottom: 0, trailing: 20)
        modeHeader.isLayoutMarginsRelativeArrangement = true
        modeSection.customHeaderView = modeHeader
        contents.add(modeSection)

        guard let mode = Mode(rawValue: segmentedControl.selectedSegmentIndex) else {
            owsFailDebug("Invalid mode.")
            return
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
        let requestingMembersSorted = databaseStorage.read { transaction in
            self.contactsManagerImpl.sortSignalServiceAddresses(Array(groupMembership.requestingMembers),
                                                                transaction: transaction)
        }

        let section = OWSTableSection()
        let footerFormat = OWSLocalizedString("PENDING_GROUP_MEMBERS_SECTION_FOOTER_PENDING_MEMBER_REQUESTS_FORMAT",
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

                    let cell = ContactTableViewCell(style: .default, reuseIdentifier: nil)

                    Self.databaseStorage.read { transaction in
                        let configuration = ContactCellConfiguration(address: address, localUserDisplayMode: .asLocalUser)
                        configuration.allowUserInteraction = true

                        if canApproveMemberRequests {
                            configuration.accessoryView = self.buildMemberRequestButtons(address: address)
                        }

                        if address.isLocalAddress {
                            cell.selectionStyle = .none
                        } else {
                            cell.selectionStyle = .default
                        }

                        cell.configure(configuration: configuration, transaction: transaction)
                    }
                    return cell
                    }) { [weak self] in
                                                self?.showMemberActionSheet(for: address)
                })
            }
        } else {
            section.add(OWSTableItem.softCenterLabel(
                withText: OWSLocalizedString("PENDING_GROUP_MEMBERS_NO_PENDING_MEMBER_REQUESTS",
                                             comment: "Label indicating that a group has no pending member requests.")
            ))
        }
        contents.add(section)
    }

    private func buildMemberRequestButtons(address: SignalServiceAddress) -> ContactCellAccessoryView {
        let buttonHeight: CGFloat = 28

        let denyButton = OWSButton()
        denyButton.layer.cornerRadius = buttonHeight / 2
        denyButton.clipsToBounds = true
        denyButton.setBackgroundImage(UIImage(color: Theme.secondaryBackgroundColor), for: .normal)
        denyButton.setTemplateImageName("x-20", tintColor: Theme.primaryIconColor)
        denyButton.accessibilityIdentifier = "member-request-deny"
        denyButton.block = { [weak self] in
            self?.denyMemberRequest(address: address)
        }

        let approveButton = OWSButton()
        approveButton.layer.cornerRadius = buttonHeight / 2
        approveButton.clipsToBounds = true
        approveButton.setBackgroundImage(UIImage(color: Theme.secondaryBackgroundColor), for: .normal)
        approveButton.setTemplateImageName("check-20", tintColor: Theme.primaryIconColor)
        approveButton.accessibilityIdentifier = "member-request-approveButton"
        approveButton.block = { [weak self] in
            self?.approveMemberRequest(address: address)
        }

        let denyWrapper = ManualLayoutView.wrapSubviewUsingIOSAutoLayout(denyButton)
        let approveWrapper = ManualLayoutView.wrapSubviewUsingIOSAutoLayout(approveButton)

        let denyButtonSize = CGSize.square(buttonHeight)
        let approveButtonSize = CGSize.square(buttonHeight)

        let stackView = ManualStackView(name: "stackView")
        let stackConfig = CVStackViewConfig(axis: .horizontal,
                                            alignment: .center,
                                            spacing: 16,
                                            layoutMargins: .zero)
        let stackMeasurement = stackView.configure(config: stackConfig,
                                                   subviews: [denyWrapper, approveWrapper],
                                                   subviewInfos: [
                                                    denyButtonSize.asManualSubviewInfo,
                                                    approveButtonSize.asManualSubviewInfo
                                                   ])
        let stackSize = stackMeasurement.measuredSize
        return ContactCellAccessoryView(accessoryView: stackView, size: stackSize)
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
        let allPendingMembersSorted = databaseStorage.read { transaction in
            self.contactsManagerImpl.sortSignalServiceAddresses(Array(groupMembership.invitedMembers),
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
        localSection.headerTitle = OWSLocalizedString("PENDING_GROUP_MEMBERS_SECTION_TITLE_PEOPLE_YOU_INVITED",
                                                     comment: "Title for the 'people you invited' section of the 'member requests and invites' view.")
        if membersInvitedByLocalUser.count > 0 {
            for address in membersInvitedByLocalUser {
                localSection.add(OWSTableItem(dequeueCellBlock: { tableView in
                    guard let cell = tableView.dequeueReusableCell(withIdentifier: ContactTableViewCell.reuseIdentifier) as? ContactTableViewCell else {
                        owsFailDebug("Missing cell.")
                        return UITableViewCell()
                    }

                    cell.selectionStyle = canRevokeInvites ? .default : .none
                    cell.configureWithSneakyTransaction(address: address,
                                                        localUserDisplayMode: .asUser)
                    return cell
                    }) { [weak self] in
                                                self?.inviteFromLocalUserWasTapped(address,
                                                                                   canRevoke: canRevokeInvites)
                })
            }
        } else {
            localSection.add(OWSTableItem.softCenterLabel(
                withText: OWSLocalizedString("PENDING_GROUP_MEMBERS_NO_PENDING_MEMBERS",
                                             comment: "Label indicating that a group has no pending members.")
            ))
        }
        contents.add(localSection)

        // MARK: - Other Users

        let otherUsersSection = OWSTableSection()
        otherUsersSection.headerTitle = OWSLocalizedString("PENDING_GROUP_MEMBERS_SECTION_TITLE_INVITES_FROM_OTHER_MEMBERS",
                                                          comment: "Title for the 'invites by other group members' section of the 'member requests and invites' view.")
        otherUsersSection.footerTitle = OWSLocalizedString("PENDING_GROUP_MEMBERS_SECTION_FOOTER_INVITES_FROM_OTHER_MEMBERS",
                                                          comment: "Footer for the 'invites by other group members' section of the 'member requests and invites' view.")

        if membersInvitedByOtherUsers.count > 0 {
            let inviterAddresses = databaseStorage.read { transaction in
                self.contactsManagerImpl.sortSignalServiceAddresses(Array(membersInvitedByOtherUsers.keys),
                                                                    transaction: transaction)
            }
            for inviterAddress in inviterAddresses {
                guard let invitedAddresses = membersInvitedByOtherUsers[inviterAddress] else {
                    owsFailDebug("Missing invited addresses.")
                    continue
                }

                otherUsersSection.add(OWSTableItem(dequeueCellBlock: { tableView in
                    guard let cell = tableView.dequeueReusableCell(withIdentifier: ContactTableViewCell.reuseIdentifier) as? ContactTableViewCell else {
                        owsFailDebug("Missing cell.")
                        return UITableViewCell()
                    }

                    cell.selectionStyle = canRevokeInvites ? .default : .none

                    Self.databaseStorage.read { transaction in
                        let configuration = ContactCellConfiguration(address: inviterAddress, localUserDisplayMode: .asUser)
                        let inviterName = Self.contactsManager.displayName(for: inviterAddress,
                                                                           transaction: transaction)
                        let format = OWSLocalizedString("PENDING_GROUP_MEMBERS_MEMBER_INVITED_USERS_%d", tableName: "PluralAware",
                                                       comment: "Format for label indicating the a group member has invited N other users to the group. Embeds {{ %1$@ the number of users they have invited, %2$@ name of the inviting group member }}.")
                        configuration.customName = String.localizedStringWithFormat(format, invitedAddresses.count, inviterName)
                        cell.configure(configuration: configuration, transaction: transaction)
                    }

                    return cell
                }) { [weak self] in
                    self?.invitesFromOtherUserWasTapped(invitedAddresses: invitedAddresses,
                                                        inviterAddress: inviterAddress,
                                                        canRevoke: canRevokeInvites)
                })
            }
        } else {
            otherUsersSection.add(OWSTableItem.softCenterLabel(
                withText: OWSLocalizedString("PENDING_GROUP_MEMBERS_NO_PENDING_MEMBERS",
                                             comment: "Label indicating that a group has no pending members.")
            ))
        }
        contents.add(otherUsersSection)

        // MARK: - Invalid Invites

        let invalidInvitesCount = groupMembership.invalidInviteUserIds.count
        if canRevokeInvites, invalidInvitesCount > 0 {
            let invalidInvitesSection = OWSTableSection()
            invalidInvitesSection.headerTitle = OWSLocalizedString("PENDING_GROUP_MEMBERS_SECTION_TITLE_INVALID_INVITES",
                                                                  comment: "Title for the 'invalid invites' section of the 'member requests and invites' view.")

            let format = OWSLocalizedString("PENDING_GROUP_MEMBERS_REVOKE_INVALID_INVITES_%d", tableName: "PluralAware",
                                           comment: "Format for 'revoke invalid N invites' item. Embeds {{ the number of invalid invites. }}.")
            let cellTitle = String.localizedStringWithFormat(format, invalidInvitesCount)

            invalidInvitesSection.add(OWSTableItem.disclosureItem(withText: cellTitle) { [weak self] in
                self?.revokeInvalidInvites()
            })
            contents.add(invalidInvitesSection)
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
        let format = OWSLocalizedString("PENDING_GROUP_MEMBERS_REVOKE_LOCAL_INVITE_CONFIRMATION_TITLE_1_FORMAT",
                                       comment: "Format for title of 'revoke invite' confirmation alert. Embeds {{ the name of the invited group member. }}.")
        let alertTitle = String(format: format, invitedName)
        let actionSheet = ActionSheetController(title: alertTitle)
        actionSheet.addAction(ActionSheetAction(title: OWSLocalizedString("PENDING_GROUP_MEMBERS_REVOKE_INVITE_1_BUTTON",
                                                                         comment: "Title of 'revoke invite' button."),
                                                style: .destructive) { _ in
                                                    self.revokePendingInvites(addresses: [invitedAddress])
        })
        actionSheet.addAction(OWSActionSheets.cancelAction)
        presentActionSheet(actionSheet)
    }

    private func showRevokePendingInviteFromOtherUserConfirmation(invitedAddresses: [SignalServiceAddress],
                                                                  inviterAddress: SignalServiceAddress) {

        let inviterName = contactsManager.displayName(for: inviterAddress)
        let format = OWSLocalizedString("PENDING_GROUP_MEMBERS_REVOKE_INVITE_CONFIRMATION_TITLE_%d", tableName: "PluralAware",
                                       comment: "Format for title of 'revoke invite' confirmation alert. Embeds {{ %1$@ the number of users they have invited, %2$@ name of the inviting group member. }}.")
        let alertTitle = String.localizedStringWithFormat(format, invitedAddresses.count, inviterName)
        let actionSheet = ActionSheetController(title: alertTitle)
        let actionTitle = String.localizedStringWithFormat(OWSLocalizedString("PENDING_GROUP_MEMBERS_REVOKE_INVITE_BUTTON_%d", tableName: "PluralAware",
                                                                             comment: "Title of 'revoke invites' button."), invitedAddresses.count)
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
        memberActionSheet.present(from: self)
    }

    private func presentRequestApprovedToast(address: SignalServiceAddress) {
        let format = OWSLocalizedString("PENDING_GROUP_MEMBERS_REQUEST_APPROVED_FORMAT",
                                       comment: "Message indicating that a request to join the group was successfully approved. Embeds {{ the name of the approved user }}.")
        let userName = contactsManager.displayName(for: address)
        let text = String(format: format, userName)
        presentToast(text: text)
    }

    private func presentRequestDeniedToast(address: SignalServiceAddress) {
        let format = OWSLocalizedString("PENDING_GROUP_MEMBERS_REQUEST_DENIED_FORMAT",
                                       comment: "Message indicating that a request to join the group was successfully denied. Embeds {{ the name of the denied user }}.")
        let userName = contactsManager.displayName(for: address)
        let text = String(format: format, userName)
        presentToast(text: text)
    }
}

// MARK: -

private extension GroupMemberRequestsAndInvitesViewController {

    func revokePendingInvites(addresses: [SignalServiceAddress]) {
        let uuids = addresses.compactMap { $0.uuid }
        guard let groupModelV2 = groupModel as? TSGroupModelV2, !uuids.isEmpty else {
            GroupViewUtils.showUpdateErrorUI(error: OWSAssertionError("Invalid group model or addresses"))
            return
        }

        GroupViewUtils.updateGroupWithActivityIndicator(
            fromViewController: self,
            withGroupModel: groupModelV2,
            updateDescription: self.logTag,
            updateBlock: {
                GroupManager.removeFromGroupOrRevokeInviteV2(groupModel: groupModelV2,
                                                             uuids: uuids)
            },
            completion: { [weak self] groupThread in
                self?.reloadContent(groupThread: groupThread)
            }
        )
    }

    func revokeInvalidInvites() {
        guard let groupModelV2 = groupModel as? TSGroupModelV2 else {
            GroupViewUtils.showUpdateErrorUI(error: OWSAssertionError("Invalid group model"))
            return
        }

        GroupViewUtils.updateGroupWithActivityIndicator(
            fromViewController: self,
            withGroupModel: groupModelV2,
            updateDescription: self.logTag,
            updateBlock: {
                GroupManager.revokeInvalidInvites(groupModel: groupModelV2)
            },
            completion: { [weak self] groupThread in
                self?.reloadContent(groupThread: groupThread)
            }
        )
    }
}

// MARK: -

fileprivate extension GroupMemberRequestsAndInvitesViewController {

    func showAcceptMemberRequestUI(address: SignalServiceAddress) {

        let username = contactsManager.displayName(for: address)
        let format = OWSLocalizedString("PENDING_GROUP_MEMBERS_ACCEPT_REQUEST_CONFIRMATION_TITLE_FORMAT",
                                       comment: "Title of 'accept member request to join group' confirmation alert. Embeds {{ the name of the requesting group member. }}.")
        let alertTitle = String(format: format, username)
        let actionSheet = ActionSheetController(title: alertTitle)

        let actionTitle = OWSLocalizedString("PENDING_GROUP_MEMBERS_ACCEPT_REQUEST_BUTTON",
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
        let format = OWSLocalizedString("PENDING_GROUP_MEMBERS_DENY_REQUEST_CONFIRMATION_TITLE_FORMAT",
                                       comment: "Title of 'deny member request to join group' confirmation alert. Embeds {{ the name of the requesting group member. }}.")
        let alertTitle = String(format: format, username)
        let actionSheet = ActionSheetController(title: alertTitle)

        let actionTitle = OWSLocalizedString("PENDING_GROUP_MEMBERS_DENY_REQUEST_BUTTON",
                                            comment: "Title of 'deny member request to join group' button.")
        actionSheet.addAction(ActionSheetAction(title: actionTitle,
                                                style: .destructive) { _ in
                                                    self.acceptOrDenyMemberRequests(address: address, shouldAccept: false)
        })

        actionSheet.addAction(OWSActionSheets.cancelAction)
        presentActionSheet(actionSheet)
    }

    func acceptOrDenyMemberRequests(address: SignalServiceAddress, shouldAccept: Bool) {
        guard let groupModelV2 = groupModel as? TSGroupModelV2,
              let uuid = address.uuid
        else {
            GroupViewUtils.showUpdateErrorUI(error: OWSAssertionError("Invalid group model or address"))
            return
        }

        GroupViewUtils.updateGroupWithActivityIndicator(
            fromViewController: self,
            withGroupModel: groupModelV2,
            updateDescription: self.logTag,
            updateBlock: { () -> Promise<TSGroupThread> in
                GroupManager.acceptOrDenyMemberRequestsV2(groupModel: groupModelV2,
                                                          uuids: [uuid],
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
}
