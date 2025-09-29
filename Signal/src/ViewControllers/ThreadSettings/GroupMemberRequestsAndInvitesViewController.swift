//
// Copyright 2020 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import LibSignalClient
import SignalServiceKit
public import SignalUI

protocol GroupMemberRequestsAndInvitesViewControllerDelegate: AnyObject {
    func requestsAndInvitesViewDidUpdate()
}

// MARK: -

final public class GroupMemberRequestsAndInvitesViewController: OWSTableViewController2 {

    weak var groupMemberRequestsAndInvitesViewControllerDelegate: GroupMemberRequestsAndInvitesViewControllerDelegate?

    private let oldGroupThread: TSGroupThread

    private var groupModel: TSGroupModel

    private let groupViewHelper: GroupViewHelper

    private let spoilerState: SpoilerRenderState

    private enum Mode: Int, CaseIterable {
        case memberRequests = 0
        case pendingInvites = 1
    }

    private let segmentedControl = UISegmentedControl()

    init(groupThread: TSGroupThread, groupViewHelper: GroupViewHelper, spoilerState: SpoilerRenderState) {
        self.oldGroupThread = groupThread
        self.groupModel = groupThread.groupModel
        self.groupViewHelper = groupViewHelper
        self.spoilerState = spoilerState

        super.init()
    }

    // MARK: - View Lifecycle

    public override func viewDidLoad() {
        super.viewDidLoad()

        title = OWSLocalizedString("GROUP_REQUESTS_AND_INVITES_VIEW_TITLE",
                                  comment: "The title for the 'group requests and invites' view.")

        defaultSeparatorInsetLeading = Self.cellHInnerMargin + CGFloat(AvatarBuilder.smallAvatarSizePoints) + ContactCellView.avatarTextHSpacing

        tableView.register(ContactTableViewCell.self, forCellReuseIdentifier: ContactTableViewCell.reuseIdentifier)

        createSegmentedControl()
        updateTableContents()
    }

    // MARK: -

    private func createSegmentedControl() {
        for mode in Mode.allCases {
            segmentedControl.insertSegment(
                withTitle: segmentTitle(forMode: mode),
                at: mode.rawValue,
                animated: false
            )
        }

        segmentedControl.selectedSegmentIndex = 0
        segmentedControl.addTarget(self, action: #selector(segmentedControlDidChange), for: .valueChanged)
    }

    private func updateSegmentedControl() {
        owsPrecondition(Mode.allCases.count == segmentedControl.numberOfSegments)

        for mode in Mode.allCases {
            segmentedControl.setTitle(
                segmentTitle(forMode: mode),
                forSegmentAt: mode.rawValue
            )
        }
    }

    private func segmentTitle(forMode mode: Mode) -> String {
        let groupMembership = groupModel.groupMembership

        var title: String
        switch mode {
        case .memberRequests:
            title = OWSLocalizedString(
                "GROUP_REQUESTS_AND_INVITES_VIEW_MEMBER_REQUESTS_MODE",
                comment: "Label for the 'member requests' mode of the 'group requests and invites' view."
            )
            if groupMembership.requestingMembers.count > 0 {
                title.append(" (\(OWSFormat.formatInt(groupMembership.requestingMembers.count)))")
            }
        case .pendingInvites:
            title = OWSLocalizedString(
                "GROUP_REQUESTS_AND_INVITES_VIEW_PENDING_INVITES_MODE",
                comment: "Label for the 'pending invites' mode of the 'group requests and invites' view."
            )
            if groupMembership.invitedMembers.count > 0 {
                title.append(" (\(OWSFormat.formatInt(groupMembership.invitedMembers.count)))")
            }
        }

        return title
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
        let requestingMembersSorted = SSKEnvironment.shared.databaseStorageRef.read { tx in
            SSKEnvironment.shared.contactManagerImplRef.sortSignalServiceAddresses(groupMembership.requestingMembers, transaction: tx)
        }

        let section = OWSTableSection()
        let footerFormat = OWSLocalizedString(
            "PENDING_GROUP_MEMBERS_SECTION_FOOTER_PENDING_MEMBER_REQUESTS_FORMAT",
            comment: "Footer for the 'pending member requests' section of the 'member requests and invites' view. Embeds {{ the name of the group }}."
        )
        let groupName = SSKEnvironment.shared.databaseStorageRef.read { tx in SSKEnvironment.shared.contactManagerRef.displayName(for: oldGroupThread, transaction: tx) }
        section.footerTitle = String(format: footerFormat, groupName)

        if !requestingMembersSorted.isEmpty {
            for address in requestingMembersSorted {
                section.add(OWSTableItem(customCellBlock: { [weak self] in
                    guard let self = self else {
                        owsFailDebug("Missing self")
                        return OWSTableItem.newCell()
                    }

                    let cell = ContactTableViewCell(style: .default, reuseIdentifier: nil)

                    SSKEnvironment.shared.databaseStorageRef.read { transaction in
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
                }, actionBlock: { [weak self] in
                    self?.showMemberActionSheet(for: address)
                }))
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
        denyButton.setBackgroundImage(UIImage.image(color: Theme.secondaryBackgroundColor), for: .normal)
        denyButton.setTemplateImageName("x-20", tintColor: Theme.primaryIconColor)
        denyButton.accessibilityIdentifier = "member-request-deny"
        denyButton.block = { [weak self] in
            self?.denyMemberRequest(address: address)
        }

        let approveButton = OWSButton()
        approveButton.layer.cornerRadius = buttonHeight / 2
        approveButton.clipsToBounds = true
        approveButton.setBackgroundImage(UIImage.image(color: Theme.secondaryBackgroundColor), for: .normal)
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
        guard let localAci = DependenciesBridge.shared.tsAccountManager.localIdentifiersWithMaybeSneakyTransaction?.aci else {
            owsFailDebug("missing local address")
            return
        }

        let groupMembership = groupModel.groupMembership

        var membersInvitedByLocalUser = [SignalServiceAddress]()
        var membersInvitedByOtherUsers = [Aci: [SignalServiceAddress]]()
        for invitedAddress in groupMembership.invitedMembers {
            guard let inviterAci = groupMembership.addedByAci(forInvitedMember: invitedAddress) else {
                owsFailDebug("Missing inviter.")
                continue
            }
            if inviterAci == localAci {
                membersInvitedByLocalUser.append(invitedAddress)
            } else {
                membersInvitedByOtherUsers[inviterAci, default: []].append(invitedAddress)
            }
        }

        let contactManager = SSKEnvironment.shared.contactManagerRef
        let databaseStorage = SSKEnvironment.shared.databaseStorageRef

        membersInvitedByLocalUser = databaseStorage.read { tx in
            return contactManager.sortSignalServiceAddresses(membersInvitedByLocalUser, transaction: tx)
        }

        // Only admins can revoke invites.
        let canRevokeInvites = groupViewHelper.canRevokePendingInvites

        // MARK: - People You Invited

        let localSection = OWSTableSection()
        localSection.headerTitle = OWSLocalizedString(
            "PENDING_GROUP_MEMBERS_SECTION_TITLE_PEOPLE_YOU_INVITED",
            comment: "Title for the 'people you invited' section of the 'member requests and invites' view.",
        )
        if membersInvitedByLocalUser.isEmpty {
            localSection.add(OWSTableItem.softCenterLabel(
                withText: OWSLocalizedString(
                    "PENDING_GROUP_MEMBERS_NO_PENDING_MEMBERS",
                    comment: "Label indicating that a group has no pending members.",
                ),
            ))
        } else {
            for address in membersInvitedByLocalUser {
                localSection.add(OWSTableItem(
                    dequeueCellBlock: { tableView in
                        guard let cell = tableView.dequeueReusableCell(withIdentifier: ContactTableViewCell.reuseIdentifier) as? ContactTableViewCell else {
                            owsFailDebug("Missing cell.")
                            return UITableViewCell()
                        }

                        cell.selectionStyle = canRevokeInvites ? .default : .none
                        cell.configureWithSneakyTransaction(address: address, localUserDisplayMode: .asUser)
                        return cell
                    },
                    actionBlock: { [weak self] in
                        self?.inviteFromLocalUserWasTapped(address, canRevoke: canRevokeInvites)
                    },
                ))
            }
        }
        contents.add(localSection)

        // MARK: - Other Users

        let otherUsersSection = OWSTableSection()
        otherUsersSection.headerTitle = OWSLocalizedString("PENDING_GROUP_MEMBERS_SECTION_TITLE_INVITES_FROM_OTHER_MEMBERS",
                                                          comment: "Title for the 'invites by other group members' section of the 'member requests and invites' view.")
        otherUsersSection.footerTitle = OWSLocalizedString("PENDING_GROUP_MEMBERS_SECTION_FOOTER_INVITES_FROM_OTHER_MEMBERS",
                                                          comment: "Footer for the 'invites by other group members' section of the 'member requests and invites' view.")

        if membersInvitedByOtherUsers.isEmpty {
            otherUsersSection.add(OWSTableItem.softCenterLabel(
                withText: OWSLocalizedString(
                    "PENDING_GROUP_MEMBERS_NO_PENDING_MEMBERS",
                    comment: "Label indicating that a group has no pending members.",
                )
            ))
        } else {
            var inviterAddresses = membersInvitedByOtherUsers.keys.map(SignalServiceAddress.init(_:))
            inviterAddresses = databaseStorage.read { tx in
                return contactManager.sortSignalServiceAddresses(inviterAddresses, transaction: tx)
            }
            for inviterAddress in inviterAddresses {
                guard let inviterAci = inviterAddress.aci, let invitedAddresses = membersInvitedByOtherUsers[inviterAci] else {
                    owsFailDebug("Missing invited addresses.")
                    continue
                }

                otherUsersSection.add(OWSTableItem(
                    dequeueCellBlock: { tableView in
                        guard let cell = tableView.dequeueReusableCell(withIdentifier: ContactTableViewCell.reuseIdentifier) as? ContactTableViewCell else {
                            owsFailDebug("Missing cell.")
                            return UITableViewCell()
                        }

                        cell.selectionStyle = canRevokeInvites ? .default : .none

                        databaseStorage.read { transaction in
                            let configuration = ContactCellConfiguration(address: inviterAddress, localUserDisplayMode: .asUser)
                            let inviterName = contactManager.displayName(for: inviterAddress, tx: transaction).resolvedValue()
                            let format = OWSLocalizedString(
                                "PENDING_GROUP_MEMBERS_MEMBER_INVITED_USERS_%d",
                                tableName: "PluralAware",
                                comment: "Format for label indicating the a group member has invited N other users to the group. Embeds {{ %1$@ the number of users they have invited, %2$@ name of the inviting group member }}.",
                            )
                            configuration.customName = String.localizedStringWithFormat(format, invitedAddresses.count, inviterName)
                            cell.configure(configuration: configuration, transaction: transaction)
                        }

                        return cell
                    },
                    actionBlock: { [weak self] in
                        self?.invitesFromOtherUserWasTapped(
                            invitedAddresses: invitedAddresses,
                            inviterAddress: inviterAddress,
                            canRevoke: canRevokeInvites,
                        )
                    },
                ))
            }
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

    fileprivate func reloadContent() {
        groupMemberRequestsAndInvitesViewControllerDelegate?.requestsAndInvitesViewDidUpdate()

        guard let newModel = { () -> TSGroupModel? in
            return SSKEnvironment.shared.databaseStorageRef.read { (transaction) -> TSGroupModel? in
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
        updateSegmentedControl()
        updateTableContents()
    }

    private func showRevokePendingInviteFromLocalUserConfirmation(invitedAddress: SignalServiceAddress) {

        let invitedName = SSKEnvironment.shared.databaseStorageRef.read { tx in SSKEnvironment.shared.contactManagerRef.displayName(for: invitedAddress, tx: tx).resolvedValue() }
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

        let inviterName = SSKEnvironment.shared.databaseStorageRef.read { tx in SSKEnvironment.shared.contactManagerRef.displayName(for: inviterAddress, tx: tx).resolvedValue() }
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
        ProfileSheetSheetCoordinator(
            address: address,
            groupViewHelper: groupViewHelper,
            spoilerState: spoilerState
        )
        .presentAppropriateSheet(from: self)
    }

    private func presentRequestApprovedToast(address: SignalServiceAddress) {
        let format = OWSLocalizedString("PENDING_GROUP_MEMBERS_REQUEST_APPROVED_FORMAT",
                                       comment: "Message indicating that a request to join the group was successfully approved. Embeds {{ the name of the approved user }}.")
        let userName = SSKEnvironment.shared.databaseStorageRef.read { tx in SSKEnvironment.shared.contactManagerRef.displayName(for: address, tx: tx).resolvedValue() }
        let text = String(format: format, userName)
        presentToast(text: text)
    }

    private func presentRequestDeniedToast(address: SignalServiceAddress) {
        let format = OWSLocalizedString("PENDING_GROUP_MEMBERS_REQUEST_DENIED_FORMAT",
                                       comment: "Message indicating that a request to join the group was successfully denied. Embeds {{ the name of the denied user }}.")
        let userName = SSKEnvironment.shared.databaseStorageRef.read { tx in SSKEnvironment.shared.contactManagerRef.displayName(for: address, tx: tx).resolvedValue() }
        let text = String(format: format, userName)
        presentToast(text: text)
    }
}

// MARK: -

private extension GroupMemberRequestsAndInvitesViewController {

    func revokePendingInvites(addresses: [SignalServiceAddress]) {
        let serviceIds = addresses.compactMap { $0.serviceId }
        guard let groupModelV2 = groupModel as? TSGroupModelV2, !serviceIds.isEmpty else {
            GroupViewUtils.showUpdateErrorUI(error: OWSAssertionError("Invalid group model or addresses"))
            return
        }

        GroupViewUtils.updateGroupWithActivityIndicator(
            fromViewController: self,
            updateBlock: {
                try await GroupManager.removeFromGroupOrRevokeInviteV2(groupModel: groupModelV2, serviceIds: serviceIds)
            },
            completion: { [weak self] in
                self?.reloadContent()
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
            updateBlock: {
                try await GroupManager.revokeInvalidInvites(groupModel: groupModelV2)
            },
            completion: { [weak self] in
                self?.reloadContent()
            }
        )
    }
}

// MARK: -

fileprivate extension GroupMemberRequestsAndInvitesViewController {

    func showAcceptMemberRequestUI(address: SignalServiceAddress) {

        let username = SSKEnvironment.shared.databaseStorageRef.read { tx in SSKEnvironment.shared.contactManagerRef.displayName(for: address, tx: tx).resolvedValue() }
        let format = OWSLocalizedString("PENDING_GROUP_MEMBERS_ACCEPT_REQUEST_CONFIRMATION_TITLE_FORMAT",
                                       comment: "Title of 'accept member request to join group' confirmation alert. Embeds {{ the name of the requesting group member. }}.")
        let alertTitle = String(format: format, username)
        let actionSheet = ActionSheetController(title: alertTitle)

        let actionTitle = OWSLocalizedString("PENDING_GROUP_MEMBERS_ACCEPT_REQUEST_BUTTON",
                                            comment: "Title of 'accept member request to join group' button.")
        actionSheet.addAction(ActionSheetAction(title: actionTitle) { _ in
            self.acceptOrDenyMemberRequests(address: address, shouldAccept: true)
        })

        actionSheet.addAction(OWSActionSheets.cancelAction)
        presentActionSheet(actionSheet)
    }

    func showDenyMemberRequestUI(address: SignalServiceAddress) {

        let username = SSKEnvironment.shared.databaseStorageRef.read { tx in SSKEnvironment.shared.contactManagerRef.displayName(for: address, tx: tx).resolvedValue() }
        let format = OWSLocalizedString("PENDING_GROUP_MEMBERS_DENY_REQUEST_CONFIRMATION_TITLE_FORMAT",
                                       comment: "Title of 'deny member request to join group' confirmation alert. Embeds {{ the name of the requesting group member. }}.")
        let alertTitle = String(format: format, username)
        let actionSheet = ActionSheetController(title: alertTitle)

        let actionTitle = OWSLocalizedString("PENDING_GROUP_MEMBERS_DENY_REQUEST_BUTTON",
                                            comment: "Title of 'deny member request to join group' button.")
        actionSheet.addAction(ActionSheetAction(title: actionTitle, style: .destructive) { _ in
            self.acceptOrDenyMemberRequests(address: address, shouldAccept: false)
        })

        actionSheet.addAction(OWSActionSheets.cancelAction)
        presentActionSheet(actionSheet)
    }

    func acceptOrDenyMemberRequests(address: SignalServiceAddress, shouldAccept: Bool) {
        guard let groupModelV2 = groupModel as? TSGroupModelV2, let aci = address.serviceId as? Aci else {
            GroupViewUtils.showUpdateErrorUI(error: OWSAssertionError("Invalid group model or address"))
            return
        }

        GroupViewUtils.updateGroupWithActivityIndicator(
            fromViewController: self,
            updateBlock: {
                try await GroupManager.acceptOrDenyMemberRequestsV2(groupModel: groupModelV2, aci: aci, shouldAccept: shouldAccept)
            },
            completion: { [weak self] in
                guard let self = self else { return }
                if shouldAccept {
                    self.presentRequestApprovedToast(address: address)
                } else {
                    self.presentRequestDeniedToast(address: address)
                }
                self.reloadContent()
            }
        )
    }
}
