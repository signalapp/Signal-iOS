//
// Copyright 2020 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import SafariServices
import SignalMessaging
import SignalUI

public class NewGroupConfirmViewController: OWSTableViewController2 {

    private let newGroupState: NewGroupState

    private var groupSeed: NewGroupSeed {
        return newGroupState.groupSeed
    }

    private var recipientSet: OrderedSet<PickedRecipient> {
        return newGroupState.recipientSet
    }

    private let helper: GroupAttributesEditorHelper

    private var nameTextField: UITextField {
        return helper.nameTextField
    }

    private lazy var disappearingMessagesConfiguration = databaseStorage.read { tx in
        let dmConfigurationStore = DependenciesBridge.shared.disappearingMessagesConfigurationStore
        return dmConfigurationStore.fetchOrBuildDefault(for: .universal, tx: tx.asV2Read)
    }

    required init(newGroupState: NewGroupState) {
        self.newGroupState = newGroupState

        let groupId = newGroupState.groupSeed.possibleGroupId
        self.helper = GroupAttributesEditorHelper(
            groupId: groupId,
            groupNameOriginal: newGroupState.groupName,
            groupDescriptionOriginal: nil,
            avatarOriginalData: newGroupState.avatarData,
            iconViewSize: 64
        )

        super.init()

        self.shouldAvoidKeyboard = true
    }

    // MARK: - View Lifecycle

    public override func viewDidLoad() {
        super.viewDidLoad()

        title = OWSLocalizedString("NEW_GROUP_NAME_GROUP_VIEW_TITLE",
                                  comment: "The title for the 'name new group' view.")

        navigationItem.rightBarButtonItem = UIBarButtonItem(title: OWSLocalizedString("NEW_GROUP_CREATE_BUTTON",
                                                                                     comment: "The title for the 'create group' button."),
                                                            style: .plain,
                                                            target: self,
                                                            action: #selector(createNewGroup),
                                                            accessibilityIdentifier: UIView.accessibilityIdentifier(in: self, name: "create"))

        // First section.

        helper.delegate = self
        helper.buildContents()

        tableView.register(ContactTableViewCell.self, forCellReuseIdentifier: ContactTableViewCell.reuseIdentifier)

        updateTableContents()
    }

    private var lastViewSize = CGSize.zero
    public override func viewWillLayoutSubviews() {
        super.viewWillLayoutSubviews()

        guard view.frame.size != lastViewSize else { return }
        lastViewSize = view.frame.size
        updateTableContents()
    }

    private func allMembersSupportGroupsV2() -> Bool {
        return recipientSet.orderedMembers.allSatisfy {
            guard let address = $0.address else {
                return false
            }
            return GroupManager.doesUserSupportGroupsV2(address: address)
        }
    }

    public override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)

        nameTextField.becomeFirstResponder()
    }

    // MARK: -

    private func updateTableContents() {
        let contents = OWSTableContents()

        let nameAndAvatarSection = OWSTableSection()

        let members = databaseStorage.read { transaction in
            BaseGroupMemberViewController.orderedMembers(recipientSet: self.recipientSet,
                                                         shouldSort: true,
                                                         transaction: transaction)
        }.compactMap { $0.address }

        if members.isEmpty {
            nameAndAvatarSection.footerTitle = OWSLocalizedString("GROUP_MEMBERS_NO_OTHER_MEMBERS",
                                                    comment: "Label indicating that a new group has no other members.")
        }

        nameAndAvatarSection.add(.init(
            customCellBlock: { [weak self] in
                let cell = OWSTableItem.newCell()
                cell.selectionStyle = .none
                guard let self = self else { return cell }

                self.helper.avatarWrapper.setContentHuggingVerticalHigh()
                self.helper.nameTextField.setContentHuggingHorizontalLow()
                let firstSection = UIStackView(arrangedSubviews: [
                    self.helper.avatarWrapper,
                    self.helper.nameTextField
                ])
                firstSection.axis = .horizontal
                firstSection.alignment = .center
                firstSection.spacing = ContactCellView.avatarTextHSpacing

                cell.contentView.addSubview(firstSection)
                firstSection.autoPinEdgesToSuperviewMargins()

                return cell
            },
            actionBlock: {}
        ))
        contents.add(nameAndAvatarSection)

        let disappearingMessagesSection = OWSTableSection()
        disappearingMessagesSection.add(.init(
            customCellBlock: { [weak self] in
                guard let self = self else { return UITableViewCell() }
                let cell = OWSTableItem.buildCell(
                    icon: self.disappearingMessagesConfiguration.isEnabled
                        ? .settingsTimer
                        : .settingsTimerDisabled,
                    itemName: OWSLocalizedString(
                        "DISAPPEARING_MESSAGES",
                        comment: "table cell label in conversation settings"
                    ),
                    accessoryText: self.disappearingMessagesConfiguration.isEnabled
                        ? DateUtil.formatDuration(seconds: self.disappearingMessagesConfiguration.durationSeconds, useShortFormat: true)
                        : CommonStrings.switchOff,
                    accessoryType: .disclosureIndicator,
                    accessoryImage: nil,
                    accessibilityIdentifier: UIView.accessibilityIdentifier(in: self, name: "disappearing_messages")
                )
                return cell
            }, actionBlock: { [weak self] in
                guard let self = self else { return }
                let vc = DisappearingMessagesTimerSettingsViewController(configuration: self.disappearingMessagesConfiguration) { configuration in
                    self.disappearingMessagesConfiguration = configuration
                    self.updateTableContents()
                }
                self.presentFormSheet(OWSNavigationController(rootViewController: vc), animated: true)
            }
        ))
        contents.add(disappearingMessagesSection)

        if members.count > 0 {
            let section = OWSTableSection()
            section.headerTitle = OWSLocalizedString("GROUP_MEMBERS_SECTION_TITLE_MEMBERS",
                                                    comment: "Title for the 'members' section of the 'group members' view.")

            for address in members {
                section.add(OWSTableItem(
                                dequeueCellBlock: { tableView in
                        guard let cell = tableView.dequeueReusableCell(withIdentifier: ContactTableViewCell.reuseIdentifier) as? ContactTableViewCell else {
                            owsFailDebug("Missing cell.")
                            return UITableViewCell()
                        }

                        cell.selectionStyle = .none

                        Self.databaseStorage.read { transaction in
                            let configuration = ContactCellConfiguration(address: address, localUserDisplayMode: .asUser)
                            cell.configure(configuration: configuration, transaction: transaction)
                        }
                        return cell
                }))
            }
            contents.add(section)
        }

        self.contents = contents
    }

    // MARK: - Actions

    @objc
    private func createNewGroup() {
        AssertIsOnMainThread()

        guard let localAddress = tsAccountManager.localAddress else {
            owsFailDebug("missing local address")
            return
        }
        guard let groupName = newGroupState.groupName, !groupName.isEmpty else {
            Self.showMissingGroupNameAlert()
            return
        }
        owsAssertDebug(allMembersSupportGroupsV2(), "Members must already be checked for v2 support.")

        let avatarData = newGroupState.avatarData
        let memberSet = Set([localAddress] + recipientSet.orderedMembers.compactMap { $0.address })
        let members = Array(memberSet)
        let newGroupSeed = groupSeed
        let disappearingMessageToken = disappearingMessagesConfiguration.asToken

        // GroupsV2 TODO: Should we allow cancel here?
        ModalActivityIndicatorViewController.present(fromViewController: self,
                                                     canCancel: false) { modalActivityIndicator in
                                                        firstly {
                                                            GroupManager.localCreateNewGroup(members: members,
                                                                                             groupId: nil,
                                                                                             name: groupName,
                                                                                             avatarData: avatarData,
                                                                                             disappearingMessageToken: disappearingMessageToken,
                                                                                             newGroupSeed: newGroupSeed,
                                                                                             shouldSendMessage: true)
                                                        }.done { groupThread in
                                                            self.groupWasCreated(groupThread: groupThread,
                                                                                 modalActivityIndicator: modalActivityIndicator)
                                                        }.catch { error in
                                                            owsFailDebug("Could not create group: \(error)")

                                                            modalActivityIndicator.dismiss {
                                                                // Partial success could create the group on the service.
                                                                // This would cause retries to fail with 409.  Therefore
                                                                // we must rotate the seed after every failure.
                                                                self.newGroupState.deriveNewGroupSeedForRetry()

                                                                NewGroupConfirmViewController.showCreateErrorUI(error: error)
                                                            }
                                                        }
        }
    }

    public class func showCreateErrorUI(error: Error) {
        AssertIsOnMainThread()

        if error.isNetworkFailureOrTimeout {
            OWSActionSheets.showActionSheet(title: OWSLocalizedString("ERROR_NETWORK_FAILURE",
                                                                     comment: "Error indicating network connectivity problems."),
                                            message: OWSLocalizedString("NEW_GROUP_CREATION_FAILED_DUE_TO_NETWORK",
                                                                     comment: "Error indicating that a new group could not be created due to network connectivity problems."))
            return
        }

        OWSActionSheets.showActionSheet(title: OWSLocalizedString("NEW_GROUP_CREATION_FAILED",
                                                                 comment: "Error indicating that a new group could not be created."))
    }

    public class func showMissingGroupNameAlert() {
        AssertIsOnMainThread()

        OWSActionSheets.showActionSheet(title: OWSLocalizedString("NEW_GROUP_CREATION_MISSING_NAME_ALERT_TITLE",
                                                                 comment: "Title for error alert indicating that a group name is required."),
                                        message: OWSLocalizedString("NEW_GROUP_CREATION_MISSING_NAME_ALERT_MESSAGE",
                                                                   comment: "Message for error alert indicating that a group name is required."))
    }

    func groupWasCreated(groupThread: TSGroupThread,
                         modalActivityIndicator: ModalActivityIndicatorViewController) {
        AssertIsOnMainThread()

        let hasAnyRemoteMembers = groupThread.groupModel.groupMembership.allMembersOfAnyKind.count > 1

        func navigateToNewGroup(completion: (() -> Void)?) {
            _ = self.presentingViewController?.dismiss(animated: true) {
                SignalApp.shared.presentConversationForThread(groupThread,
                                                              action: hasAnyRemoteMembers ? .none : .newGroupActionSheet,
                                                              animated: false)
                completion?()
            }
        }

        let pendingMembers = groupThread.groupModel.groupMembership.invitedMembers
        guard let firstPendingMember = pendingMembers.first else {
            // No pending members.
            return navigateToNewGroup(completion: nil)
        }

        let alertTitle: String
        let alertMessage: String
        let alertTitleFormat = OWSLocalizedString("GROUP_INVITES_SENT_ALERT_TITLE_%d", tableName: "PluralAware",
                                       comment: "Format for the title for an alert indicating that some members were invited to a group. Embeds: {{ the number of invites sent. }}")
        if pendingMembers.count > 0 {
            alertTitle = String.localizedStringWithFormat(alertTitleFormat, pendingMembers.count)
            alertMessage = OWSLocalizedString("GROUP_INVITES_SENT_ALERT_TITLE_N_MESSAGE",
                                             comment: "Message for an alert indicating that some members were invited to a group.")
        } else {
            alertTitle = String.localizedStringWithFormat(alertTitleFormat, 1)
            let inviteeName = contactsManager.displayName(for: firstPendingMember)
            let alertMessageFormat = OWSLocalizedString("GROUP_INVITES_SENT_ALERT_MESSAGE_1_FORMAT",
                                                     comment: "Format for the message for an alert indicating that a member was invited to a group. Embeds: {{ the name of the member. }}")
            alertMessage = String(format: alertMessageFormat, inviteeName)
        }

        let actionSheet = ActionSheetController(title: alertTitle, message: alertMessage)

        actionSheet.addAction(ActionSheetAction(title: CommonStrings.learnMore,
                                                style: .default) { _ in
                                                    // We present the "learn more" view atop the
                                                    // new conversation view to avoid users getting
                                                    // stucks in the "create group" view.
                                                    navigateToNewGroup {
                                                        Self.showLearnMoreView()
                                                    }
        })
        actionSheet.addAction(ActionSheetAction(title: CommonStrings.okayButton,
                                                style: .default) { _ in
                                                    navigateToNewGroup(completion: nil)
        })

        modalActivityIndicator.dismiss {
            self.presentActionSheet(actionSheet)
        }
    }

    private class func showLearnMoreView() {
        guard let url = URL(string: "https://support.signal.org/hc/articles/360007319331") else {
            owsFailDebug("Invalid url.")
            return
        }
        guard let fromViewController = CurrentAppContext().frontmostViewController() else {
            owsFailDebug("Missing fromViewController.")
            return
        }
        let vc = SFSafariViewController(url: url)
        fromViewController.present(vc, animated: true, completion: nil)
    }
}

// MARK: -

extension NewGroupConfirmViewController: GroupAttributesEditorHelperDelegate {
    func groupAttributesEditorContentsDidChange() {
        newGroupState.groupName = helper.groupNameCurrent
        newGroupState.avatarData = helper.avatarCurrent?.imageData
    }

    func groupAttributesEditorSelectionDidChange() {}
}
