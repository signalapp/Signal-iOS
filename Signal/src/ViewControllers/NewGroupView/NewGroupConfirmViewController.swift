//
// Copyright 2020 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import SafariServices
import SignalMessaging

@objc
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

    private lazy var disappearingMessagesConfiguration = databaseStorage.read { transaction in
        OWSDisappearingMessagesConfiguration.fetchOrBuildDefaultUniversalConfiguration(with: transaction)
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

    @objc
    public override func viewDidLoad() {
        super.viewDidLoad()

        title = NSLocalizedString("NEW_GROUP_NAME_GROUP_VIEW_TITLE",
                                  comment: "The title for the 'name new group' view.")

        navigationItem.rightBarButtonItem = UIBarButtonItem(title: NSLocalizedString("NEW_GROUP_CREATE_BUTTON",
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

    private var membersDoNotSupportGroupsV2: [PickedRecipient] {
        recipientSet.orderedMembers.filter {
            guard let address = $0.address else {
                return false
            }
            return !GroupManager.doesUserSupportGroupsV2(address: address)
        }
    }

    @objc
    func didTapLegacyGroupView() {
        showLegacyGroupAlert()
    }

    @objc
    func showLegacyGroupAlert() {
        let membersDoNotSupportGroupsV2 = self.membersDoNotSupportGroupsV2
        guard !membersDoNotSupportGroupsV2.isEmpty else {
            return
        }
        NewLegacyGroupView(v1Members: membersDoNotSupportGroupsV2).present(fromViewController: self)
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
            nameAndAvatarSection.footerTitle = NSLocalizedString("GROUP_MEMBERS_NO_OTHER_MEMBERS",
                                                    comment: "Label indicating that a new group has no other members.")
        } else if membersDoNotSupportGroupsV2.count > 0 {
            let legacyGroupText: String
            let learnMoreText = CommonStrings.learnMore
            let legacyGroupFormat = NSLocalizedString("GROUPS_LEGACY_GROUP_CREATION_ERROR_%d", tableName: "PluralAware",
                                                      comment: "Indicates that a new group cannot be created because on ore more members do not support v2 groups. Embeds {{ %1$@ the number of members who do not support v2 groups, %2$@ a \"learn more\" link. }}.")
            legacyGroupText = String.localizedStringWithFormat(legacyGroupFormat, membersDoNotSupportGroupsV2.count, learnMoreText)

            let attributedString = NSMutableAttributedString(string: legacyGroupText)
            attributedString.setAttributes(
                [.foregroundColor: Theme.primaryTextColor],
                forSubstring: learnMoreText
            )

            let legacyGroupLabel = UILabel()
            legacyGroupLabel.textColor = Theme.secondaryTextAndIconColor
            legacyGroupLabel.font = .ows_dynamicTypeCaption1Clamped
            legacyGroupLabel.attributedText = attributedString
            legacyGroupLabel.numberOfLines = 0
            legacyGroupLabel.lineBreakMode = .byWordWrapping

            let containerView = UIView()
            containerView.layoutMargins = cellOuterInsetsWithMargin(
                top: 12,
                left: OWSTableViewController2.cellHInnerMargin,
                bottom: 0,
                right: OWSTableViewController2.cellHInnerMargin
            )
            containerView.addSubview(legacyGroupLabel)
            legacyGroupLabel.autoPinEdgesToSuperviewMargins()
            legacyGroupLabel.isUserInteractionEnabled = true
            legacyGroupLabel.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(didTapLegacyGroupView)))

            nameAndAvatarSection.customFooterView = containerView
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
        contents.addSection(nameAndAvatarSection)

        let disappearingMessagesSection = OWSTableSection()
        disappearingMessagesSection.add(.init(
            customCellBlock: { [weak self] in
                guard let self = self else { return UITableViewCell() }
                let cell = OWSTableItem.buildIconNameCell(
                    icon: self.disappearingMessagesConfiguration.isEnabled
                        ? .settingsTimer
                        : .settingsTimerDisabled,
                    itemName: NSLocalizedString(
                        "DISAPPEARING_MESSAGES",
                        comment: "table cell label in conversation settings"
                    ),
                    accessoryText: self.disappearingMessagesConfiguration.isEnabled
                        ? NSString.formatDurationSeconds(self.disappearingMessagesConfiguration.durationSeconds, useShortFormat: true)
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
        contents.addSection(disappearingMessagesSection)

        if members.count > 0 {
            let section = OWSTableSection()
            section.headerTitle = NSLocalizedString("GROUP_MEMBERS_SECTION_TITLE_MEMBERS",
                                                    comment: "Title for the 'members' section of the 'group members' view.")

            let membersDoNotSupportGroupsV2 = self.membersDoNotSupportGroupsV2.map { $0.address }

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
                            if membersDoNotSupportGroupsV2.contains(address) {
                                let warning = NSLocalizedString("NEW_GROUP_CREATION_MEMBER_DOES_NOT_SUPPORT_NEW_GROUPS",
                                                                comment: "Indicates that a group member does not support New Groups.")
                                configuration.attributedSubtitle = warning.attributedString()
                            }

                            cell.configure(configuration: configuration, transaction: transaction)
                        }
                        return cell
                }))
            }
            contents.addSection(section)
        }

        self.contents = contents
    }

    // MARK: - Actions

    @objc
    func createNewGroup() {
        AssertIsOnMainThread()

        guard let localAddress = tsAccountManager.localAddress else {
            owsFailDebug("missing local address")
            return
        }

        guard let groupName = newGroupState.groupName,
            !groupName.isEmpty else {
                Self.showMissingGroupNameAlert()
             return
        }
        guard self.membersDoNotSupportGroupsV2.isEmpty else {
            showLegacyGroupAlert()
            return
        }

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
            OWSActionSheets.showActionSheet(title: NSLocalizedString("ERROR_NETWORK_FAILURE",
                                                                     comment: "Error indicating network connectivity problems."),
                                            message: NSLocalizedString("NEW_GROUP_CREATION_FAILED_DUE_TO_NETWORK",
                                                                     comment: "Error indicating that a new group could not be created due to network connectivity problems."))
            return
        }

        OWSActionSheets.showActionSheet(title: NSLocalizedString("NEW_GROUP_CREATION_FAILED",
                                                                 comment: "Error indicating that a new group could not be created."))
    }

    public class func showMissingGroupNameAlert() {
        AssertIsOnMainThread()

        OWSActionSheets.showActionSheet(title: NSLocalizedString("NEW_GROUP_CREATION_MISSING_NAME_ALERT_TITLE",
                                                                 comment: "Title for error alert indicating that a group name is required."),
                                        message: NSLocalizedString("NEW_GROUP_CREATION_MISSING_NAME_ALERT_MESSAGE",
                                                                   comment: "Message for error alert indicating that a group name is required."))
    }

    func groupWasCreated(groupThread: TSGroupThread,
                         modalActivityIndicator: ModalActivityIndicatorViewController) {
        AssertIsOnMainThread()

        let hasAnyRemoteMembers = groupThread.groupModel.groupMembership.allMembersOfAnyKind.count > 1

        func navigateToNewGroup(completion: (() -> Void)?) {
            _ = self.presentingViewController?.dismiss(animated: true) {
                SignalApp.shared().presentConversation(for: groupThread,
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
        let alertTitleFormat = NSLocalizedString("GROUP_INVITES_SENT_ALERT_TITLE_%d", tableName: "PluralAware",
                                       comment: "Format for the title for an alert indicating that some members were invited to a group. Embeds: {{ the number of invites sent. }}")
        if pendingMembers.count > 0 {
            alertTitle = String.localizedStringWithFormat(alertTitleFormat, pendingMembers.count)
            alertMessage = NSLocalizedString("GROUP_INVITES_SENT_ALERT_TITLE_N_MESSAGE",
                                             comment: "Message for an alert indicating that some members were invited to a group.")
        } else {
            alertTitle = String.localizedStringWithFormat(alertTitleFormat, 1)
            let inviteeName = contactsManager.displayName(for: firstPendingMember)
            let alertMessageFormat = NSLocalizedString("GROUP_INVITES_SENT_ALERT_MESSAGE_1_FORMAT",
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

// MARK: -

class NewLegacyGroupView: UIView {

    private let v1Members: [PickedRecipient]

    private let tableViewController = OWSTableViewController2()

    weak var actionSheetController: ActionSheetController?

    required init(v1Members: [PickedRecipient]) {
        self.v1Members = v1Members

        super.init(frame: .zero)

        tableViewController.tableView.register(ContactTableViewCell.self, forCellReuseIdentifier: ContactTableViewCell.reuseIdentifier)
    }

    required init(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func present(fromViewController: UIViewController) {

        let wrapViewWithHMargins = { (viewToWrap: UIView) -> UIView in
            let stackView = UIStackView(arrangedSubviews: [viewToWrap])
            stackView.axis = .vertical
            stackView.alignment = .fill
            stackView.layoutMargins = UIEdgeInsets(top: 0, leading: 20, bottom: 0, trailing: 24)
            stackView.isLayoutMarginsRelativeArrangement = true
            return stackView
        }

        let headerLabel = UILabel()
        headerLabel.textColor = Theme.primaryTextColor
        headerLabel.numberOfLines = 0
        headerLabel.lineBreakMode = .byWordWrapping
        headerLabel.font = UIFont.ows_dynamicTypeBody
        let format = NSLocalizedString("GROUPS_LEGACY_GROUP_CREATION_ERROR_ALERT_TITLE_%d", tableName: "PluralAware",
                                       comment: "Title for alert that explains that a new group cannot be created one ore more members does not support v2 groups. Embeds {{ the number of members which do not support v2 groups. }}")
        headerLabel.text = String.localizedStringWithFormat(format, v1Members.count)
        headerLabel.textAlignment = .center

        let members = databaseStorage.read { transaction in
            BaseGroupMemberViewController.orderedMembers(recipientSet: OrderedSet(self.v1Members),
                                                         shouldSort: true,
                                                         transaction: transaction)
        }.compactMap { $0.address }

        let section = OWSTableSection()
        for address in members {
            section.add(OWSTableItem(
                            dequeueCellBlock: { tableView in

                    guard let cell = tableView.dequeueReusableCell(withIdentifier: ContactTableViewCell.reuseIdentifier) as? ContactTableViewCell else {
                        owsFailDebug("Missing cell.")
                        return UITableViewCell()
                    }

                    cell.selectionStyle = .none
                    cell.configureWithSneakyTransaction(address: address,
                                                        localUserDisplayMode: .asUser)
                    return cell
            }))
        }
        let contents = OWSTableContents()
        contents.addSection(section)
        tableViewController.contents = contents
        tableViewController.view.autoSetDimension(.height, toSize: 200)

        let buttonFont = UIFont.ows_dynamicTypeBodyClamped.ows_semibold
        let buttonHeight = OWSFlatButton.heightForFont(buttonFont)
        let okayButton = OWSFlatButton.button(title: CommonStrings.okayButton,
                                              font: buttonFont,
                                              titleColor: .white,
                                              backgroundColor: .ows_accentBlue,
                                              target: self,
                                              selector: #selector(dismissAlert))
        okayButton.autoSetDimension(.height, toSize: buttonHeight)

        let stackView = UIStackView(arrangedSubviews: [
            wrapViewWithHMargins(headerLabel),
            UIView.spacer(withHeight: 20),
            tableViewController.view,
            UIView.spacer(withHeight: 20),
            wrapViewWithHMargins(okayButton)
        ])
        stackView.axis = .vertical
        stackView.alignment = .fill
        stackView.layoutMargins = UIEdgeInsets(top: 20, leading: 0, bottom: 38, trailing: 0)
        stackView.isLayoutMarginsRelativeArrangement = true
        stackView.addBackgroundView(withBackgroundColor: tableViewController.tableBackgroundColor)

        layoutMargins = .zero
        addSubview(stackView)
        stackView.autoPinEdgesToSuperviewMargins()

        let actionSheetController = ActionSheetController()
        actionSheetController.customHeader = self
        actionSheetController.isCancelable = true
        fromViewController.presentActionSheet(actionSheetController)
        self.actionSheetController = actionSheetController
    }

    @objc
    func dismissAlert() {
        actionSheetController?.dismiss(animated: true)
    }
}
