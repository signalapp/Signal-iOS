//
// Copyright 2020 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import SignalMessaging
import UIKit

@objc
public class GroupMigrationActionSheet: UIView {

    enum Mode {
        case upgradeGroup(migrationInfo: GroupsV2MigrationInfo)
        case tooManyMembers
        case someMembersCantMigrate
        case migrationComplete(oldGroupModel: TSGroupModel,
                               newGroupModel: TSGroupModel)
        case reAddDroppedMembers(members: Set<SignalServiceAddress>)
    }

    private let groupThread: TSGroupThread
    private let mode: Mode

    weak var actionSheetController: ActionSheetController?

    private let stackView = UIStackView()

    required init(groupThread: TSGroupThread, mode: Mode) {
        self.groupThread = groupThread
        self.mode = mode

        super.init(frame: .zero)

        configure()
    }

    @objc
    public static func actionSheetForMigratedGroup(groupThread: TSGroupThread,
                                                   oldGroupModel: TSGroupModel,
                                                   newGroupModel: TSGroupModel) -> GroupMigrationActionSheet {
        let droppedMembers = groupThread.groupModel.getDroppedMembers
        if droppedMembers.isEmpty {
            owsAssertDebug(oldGroupModel.groupsVersion == .V1)
            owsAssertDebug(newGroupModel.groupsVersion == .V2)
            return GroupMigrationActionSheet(groupThread: groupThread,
                                             mode: .migrationComplete(oldGroupModel: oldGroupModel,
                                                                      newGroupModel: newGroupModel))
        }

        guard let droppedMembersInfo = Self.buildDroppedMembersInfo(thread: groupThread),
              !droppedMembersInfo.addableMembers.isEmpty else {
            return GroupMigrationActionSheet(groupThread: groupThread,
                                             mode: .migrationComplete(oldGroupModel: oldGroupModel,
                                                                      newGroupModel: newGroupModel))
        }

        return GroupMigrationActionSheet(groupThread: groupThread,
                                         mode: .reAddDroppedMembers(members: droppedMembersInfo.addableMembers))
    }

    required init(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    @objc
    public func present(fromViewController: UIViewController) {
        let actionSheetController = ActionSheetController()
        actionSheetController.customHeader = self
        actionSheetController.isCancelable = true
        fromViewController.presentActionSheet(actionSheetController)
        self.actionSheetController = actionSheetController
    }

    @objc
    public func configure() {
        let subviews = buildContents()

        let stackView = UIStackView(arrangedSubviews: subviews)
        stackView.axis = .vertical
        stackView.alignment = .fill
        stackView.layoutMargins = UIEdgeInsets(top: 48, leading: 20, bottom: 38, trailing: 24)
        stackView.isLayoutMarginsRelativeArrangement = true
        stackView.addBackgroundView(withBackgroundColor: Theme.actionSheetBackgroundColor)

        layoutMargins = .zero
        addSubview(stackView)
        stackView.autoPinEdgesToSuperviewMargins()
        stackView.setContentHuggingHorizontalLow()
    }

    private struct Builder: Dependencies {

        var subviews = [UIView]()

        func buildLabel() -> UILabel {
            let label = UILabel()
            label.textColor = Theme.primaryTextColor
            label.numberOfLines = 0
            label.lineBreakMode = .byWordWrapping
            return label
        }

        func buildTitleLabel(text: String) -> UILabel {
            let label = UILabel()
            label.text = text
            label.textColor = Theme.primaryTextColor
            label.font = UIFont.ows_dynamicTypeTitle2.ows_semibold
            label.numberOfLines = 0
            label.lineBreakMode = .byWordWrapping
            label.textAlignment = .center
            return label
        }

        mutating func addTitleLabel(text: String) {
            subviews.append(buildTitleLabel(text: text))
        }

        mutating func addVerticalSpacer(height: CGFloat) {
            subviews.append(UIView.spacer(withHeight: height))
        }

        mutating func addRow(subview: UIView, hasBulletPoint: Bool) {

            let bulletSize = CGSize(width: 5, height: 11)
            let bulletWrapper = UIView.container()
            bulletWrapper.autoSetDimension(.width, toSize: bulletSize.width)
            bulletWrapper.setContentHuggingHorizontalHigh()
            bulletWrapper.setCompressionResistanceHorizontalHigh()

            if hasBulletPoint {
                let bullet = UIView()
                bullet.autoSetDimensions(to: bulletSize)
                bullet.backgroundColor = (Theme.isDarkThemeEnabled
                                            ? UIColor.ows_gray60
                                            : UIColor(rgbHex: 0xdedede))
                bulletWrapper.addSubview(bullet)
                bullet.autoPinEdge(toSuperviewEdge: .top, withInset: 4)
                bullet.autoPinEdge(toSuperviewEdge: .leading)
                bullet.autoPinEdge(toSuperviewEdge: .trailing)
                bullet.setContentHuggingHigh()
                bullet.setCompressionResistanceHigh()
            }

            subview.setContentHuggingHorizontalLow()
            subview.setCompressionResistanceHigh()

            let row = UIStackView(arrangedSubviews: [bulletWrapper, subview])
            row.axis = .horizontal
            row.alignment = .top
            row.spacing = 20
            row.setCompressionResistanceVerticalHigh()
            row.setContentHuggingHorizontalLow()
            subviews.append(row)
        }

        mutating func addBodyLabel(_ text: String) {
            let label = buildLabel()
            label.font = .ows_dynamicTypeBody
            label.text = text
            addRow(subview: label, hasBulletPoint: true)
        }

        mutating func addMemberRow(address: SignalServiceAddress,
                                   transaction: SDSAnyReadTransaction) {

            let avatarView = ConversationAvatarView(sizeClass: .twentyEight, localUserDisplayMode: .asUser)
            avatarView.update(transaction) { config in
                config.dataSource = .address(address)
            }

            let label = buildLabel()
            label.font = .ows_dynamicTypeBody
            label.text = Self.contactsManagerImpl.displayName(for: address, transaction: transaction)
            label.setContentHuggingHorizontalLow()

            let row = UIStackView(arrangedSubviews: [avatarView, label])
            row.axis = .horizontal
            row.alignment = .center
            row.spacing = 6
            row.setContentHuggingHorizontalLow()

            addRow(subview: row, hasBulletPoint: false)
        }

        mutating func addBottomButton(title: String,
                                      titleColor: UIColor,
                                      backgroundColor: UIColor,
                                      target: Any,
                                      selector: Selector) {
            let buttonFont = UIFont.ows_dynamicTypeBodyClamped.ows_semibold
            let buttonHeight = OWSFlatButton.heightForFont(buttonFont)
            let upgradeButton = OWSFlatButton.button(title: title,
                                                     font: buttonFont,
                                                     titleColor: titleColor,
                                                     backgroundColor: backgroundColor,
                                                     target: target,
                                                     selector: selector)
            upgradeButton.autoSetDimension(.height, toSize: buttonHeight)
            subviews.append(upgradeButton)
        }

        mutating func addOkayButton(target: Any, selector: Selector) {
            addBottomButton(title: CommonStrings.okayButton,
                            titleColor: .white,
                            backgroundColor: .ows_accentBlue,
                            target: target,
                            selector: selector)
        }
    }

    private func buildContents() -> [UIView] {
        switch mode {
        case .upgradeGroup(let migrationInfo):
            return buildUpgradeGroupContents(migrationInfo: migrationInfo)
        case .tooManyMembers:
            return buildTooManyMembersContents()
        case .someMembersCantMigrate:
            return buildSomeMembersCantMigrateContents()
        case .migrationComplete(let oldGroupModel, let newGroupModel):
            return buildMigrationCompleteContents(oldGroupModel: oldGroupModel,
                                                  newGroupModel: newGroupModel)
        case .reAddDroppedMembers(let members):
            return buildReAddDroppedMembersContents(members: members)
        }
    }

    private func buildUpgradeGroupContents(migrationInfo: GroupsV2MigrationInfo) -> [UIView] {
        var builder = Builder()

        builder.addTitleLabel(text: NSLocalizedString("GROUPS_LEGACY_GROUP_UPGRADE_ALERT_TITLE",
                                                      comment: "Title for the 'upgrade legacy group' alert view."))
        builder.addVerticalSpacer(height: 28)

        builder.addBodyLabel(NSLocalizedString("GROUPS_LEGACY_GROUP_NEW_GROUP_DESCRIPTION",
                                               comment: "Explanation of new groups in the 'legacy group' alert views."))
        builder.addVerticalSpacer(height: 20)
        builder.addBodyLabel(NSLocalizedString("GROUPS_LEGACY_GROUP_UPGRADE_ALERT_SECTION_2_BODY",
                                               comment: "Body text for the second section of the 'upgrade legacy group' alert view."))

        owsAssertDebug(isFullMemberOfGroup)
        if isFullMemberOfGroup {
            databaseStorage.read { transaction in
                let membersToDrop = migrationInfo.membersWithoutUuids
                let membersToInvite = migrationInfo.membersWithoutProfileKeys
                if !membersToInvite.isEmpty {
                    builder.addVerticalSpacer(height: 20)
                    if membersToInvite.count == 1 {
                        builder.addBodyLabel(NSLocalizedString("GROUPS_LEGACY_GROUP_UPGRADE_ALERT_SECTION_INVITED_MEMBERS_1",
                                                               comment: "Body text for the 'invites member' section of the 'upgrade legacy group' alert view."))
                    } else {
                        builder.addBodyLabel(NSLocalizedString("GROUPS_LEGACY_GROUP_UPGRADE_ALERT_SECTION_INVITED_MEMBERS_N",
                                                               comment: "Body text for the 'invites members' section of the 'upgrade legacy group' alert view."))
                    }
                    for address in membersToInvite {
                        builder.addVerticalSpacer(height: 16)
                        builder.addMemberRow(address: address, transaction: transaction)
                    }
                }
                if !membersToDrop.isEmpty {
                    builder.addVerticalSpacer(height: 20)
                    if membersToDrop.count == 1 {
                        builder.addBodyLabel(NSLocalizedString("GROUPS_LEGACY_GROUP_UPGRADE_ALERT_SECTION_POSSIBLY_DROPPED_MEMBERS_1",
                                                               comment: "Body text for the 'possibly dropped member' section of the 'upgrade legacy group' alert view."))
                    } else {
                        builder.addBodyLabel(NSLocalizedString("GROUPS_LEGACY_GROUP_UPGRADE_ALERT_SECTION_POSSIBLY_DROPPED_MEMBERS_N",
                                                               comment: "Body text for the 'possibly dropped members' section of the 'upgrade legacy group' alert view."))
                    }
                    for address in membersToDrop {
                        builder.addVerticalSpacer(height: 16)
                        builder.addMemberRow(address: address, transaction: transaction)
                    }
                }
            }
        }

        builder.addVerticalSpacer(height: 40)

        builder.addBottomButton(title: NSLocalizedString("GROUPS_LEGACY_GROUP_UPGRADE_ALERT_UPGRADE_BUTTON",
                                                         comment: "Label for the 'upgrade this group' button in the 'upgrade legacy group' alert view."),
                                titleColor: .white,
                                backgroundColor: .ows_accentBlue,
                                target: self,
                                selector: #selector(upgradeGroup))
        builder.addVerticalSpacer(height: 5)
        builder.addBottomButton(title: CommonStrings.cancelButton,
                                titleColor: .ows_accentBlue,
                                backgroundColor: .white,
                                target: self,
                                selector: #selector(dismissAlert))

        return builder.subviews
    }

    private var isFullMemberOfGroup: Bool {
        groupThread.isLocalUserFullMember
    }

    private var isInvitedMemberOfGroup: Bool {
        groupThread.isLocalUserInvitedMember
    }

    private func buildTooManyMembersContents() -> [UIView] {
        var builder = Builder()

        builder.addTitleLabel(text: NSLocalizedString("GROUPS_LEGACY_GROUP_CANT_UPGRADE_ALERT_TITLE",
                                                      comment: "Title for the 'can't upgrade legacy group' alert view."))
        builder.addVerticalSpacer(height: 28)

        builder.addBodyLabel(NSLocalizedString("GROUPS_LEGACY_GROUP_NEW_GROUP_DESCRIPTION",
                                               comment: "Explanation of new groups in the 'legacy group' alert views."))
        builder.addVerticalSpacer(height: 20)
        let descriptionFormat = NSLocalizedString("GROUPS_LEGACY_GROUP_CANT_UPGRADE_ALERT_TOO_MANY_MEMBERS_FORMAT",
                                                  comment: "Text indicating that a legacy group can't be upgraded because it has too many members. Embeds {{ The maximum number of members allowed in a group. }}.")
        let maxMemberCount = OWSFormat.formatUInt(RemoteConfig.groupsV2MaxGroupSizeHardLimit - 1)
        let description = String(format: descriptionFormat, maxMemberCount)
        builder.addBodyLabel(description)

        builder.addVerticalSpacer(height: 100)

        builder.addOkayButton(target: self, selector: #selector(dismissAlert))

        return builder.subviews
    }

    private func buildSomeMembersCantMigrateContents() -> [UIView] {
        var builder = Builder()

        builder.addTitleLabel(text: NSLocalizedString("GROUPS_LEGACY_GROUP_NEW_GROUPS_ALERT_TITLE",
                                                      comment: "Title for the 'new groups' alert view."))
        builder.addVerticalSpacer(height: 28)

        builder.addBodyLabel(NSLocalizedString("GROUPS_LEGACY_GROUP_NEW_GROUP_DESCRIPTION",
                                               comment: "Explanation of new groups in the 'legacy group' alert views."))
        builder.addVerticalSpacer(height: 20)
        builder.addBodyLabel(NSLocalizedString("GROUPS_LEGACY_GROUP_CANT_UPGRADE_YET_1",
                                               comment: "Explanation of group migration for groups that can't yet be migrated in the 'legacy group' alert views."))
        builder.addVerticalSpacer(height: 20)
        builder.addBodyLabel(NSLocalizedString("GROUPS_LEGACY_GROUP_CANT_UPGRADE_YET_2",
                                               comment: "Explanation of group migration for groups that can't yet be migrated in the 'legacy group' alert views."))

        builder.addVerticalSpacer(height: 100)

        builder.addOkayButton(target: self, selector: #selector(dismissAlert))

        return builder.subviews
    }

    private func buildMigrationCompleteContents(oldGroupModel: TSGroupModel,
                                                newGroupModel: TSGroupModel) -> [UIView] {
        var builder = Builder()

        builder.addTitleLabel(text: NSLocalizedString("GROUPS_LEGACY_GROUP_MIGRATED_GROUP_ALERT_TITLE",
                                                      comment: "Title for the 'migrated group' alert view."))
        builder.addVerticalSpacer(height: 28)

        builder.addBodyLabel(NSLocalizedString("GROUPS_LEGACY_GROUP_NEW_GROUP_DESCRIPTION",
                                               comment: "Explanation of new groups in the 'legacy group' alert views."))
        builder.addVerticalSpacer(height: 20)
        builder.addBodyLabel(NSLocalizedString("GROUPS_LEGACY_GROUP_MIGRATED_GROUP_DESCRIPTION",
                                               comment: "Explanation of group migration for a migrated group in the 'legacy group' alert views."))

        let invitedMembers = oldGroupModel.groupMembership.fullMembers.intersection(newGroupModel.groupMembership.invitedMembers)
        let droppedMembers = oldGroupModel.groupMembership.fullMembers.subtracting(newGroupModel.groupMembership.allMembersOfAnyKind)

        if isFullMemberOfGroup {
            databaseStorage.read { transaction in
                if !invitedMembers.isEmpty {
                    builder.addVerticalSpacer(height: 20)
                    if invitedMembers.count == 1 {
                        builder.addBodyLabel(NSLocalizedString("GROUPS_LEGACY_GROUP_UPGRADE_ALERT_SECTION_INVITED_MEMBERS_1",
                                                               comment: "Body text for the 'invites member' section of the 'upgrade legacy group' alert view."))
                    } else {
                        builder.addBodyLabel(NSLocalizedString("GROUPS_LEGACY_GROUP_UPGRADE_ALERT_SECTION_INVITED_MEMBERS_N",
                                                               comment: "Body text for the 'invites members' section of the 'upgrade legacy group' alert view."))
                    }
                    for address in invitedMembers {
                        builder.addVerticalSpacer(height: 16)
                        builder.addMemberRow(address: address, transaction: transaction)
                    }
                }
                if !droppedMembers.isEmpty {
                    builder.addVerticalSpacer(height: 20)
                    if droppedMembers.count == 1 {
                        builder.addBodyLabel(NSLocalizedString("GROUPS_LEGACY_GROUP_UPGRADE_ALERT_SECTION_DROPPED_MEMBERS_1",
                                                               comment: "Body text for the 'dropped member' section of the 'upgrade legacy group' alert view."))
                    } else {
                        builder.addBodyLabel(NSLocalizedString("GROUPS_LEGACY_GROUP_UPGRADE_ALERT_SECTION_DROPPED_MEMBERS_N",
                                                               comment: "Body text for the 'dropped members' section of the 'upgrade legacy group' alert view."))
                    }
                    for address in droppedMembers {
                        builder.addVerticalSpacer(height: 16)
                        builder.addMemberRow(address: address, transaction: transaction)
                    }
                }
            }
        } else if isInvitedMemberOfGroup {
            builder.addVerticalSpacer(height: 20)
            builder.addBodyLabel(NSLocalizedString("GROUPS_LEGACY_GROUP_LOCAL_USER_INVITED",
                                                   comment: "Indicates that the local user needs to accept an invitation to rejoin the group after a group migration."))
        }

        builder.addVerticalSpacer(height: 40)

        builder.addOkayButton(target: self, selector: #selector(dismissAlert))

        return builder.subviews
    }

    private func buildReAddDroppedMembersContents(members: Set<SignalServiceAddress>) -> [UIView] {
        owsAssertDebug(isFullMemberOfGroup)

        var builder = Builder()

        if members.count > 1 {
            builder.addTitleLabel(text: NSLocalizedString("GROUPS_LEGACY_GROUP_RE_ADD_DROPPED_GROUP_MEMBERS_ALERT_TITLE_N",
                                                          comment: "Title for the 're-add dropped group members' alert view."))
            builder.addVerticalSpacer(height: 28)
            builder.addBodyLabel(NSLocalizedString("GROUPS_LEGACY_GROUP_RE_ADD_DROPPED_GROUP_MEMBERS_DESCRIPTION_N",
                                                   comment: "Explanation of 're-adding dropped group member' in the 'legacy group' alert views."))
        } else {
            builder.addTitleLabel(text: NSLocalizedString("GROUPS_LEGACY_GROUP_RE_ADD_DROPPED_GROUP_MEMBERS_ALERT_TITLE_1",
                                                          comment: "Title for the 're-add dropped group members' alert view."))
            builder.addVerticalSpacer(height: 28)
            builder.addBodyLabel(NSLocalizedString("GROUPS_LEGACY_GROUP_RE_ADD_DROPPED_GROUP_MEMBERS_DESCRIPTION_1",
                                                   comment: "Explanation of 're-adding dropped group member' in the 'legacy group' alert views."))
        }

        databaseStorage.read { transaction in
            for address in members {
                builder.addVerticalSpacer(height: 16)
                builder.addMemberRow(address: address, transaction: transaction)
            }
        }

        builder.addVerticalSpacer(height: 16)

        builder.addBottomButton(title: NSLocalizedString("GROUPS_LEGACY_GROUP_RE_ADD_DROPPED_GROUP_MEMBERS_ADD_MEMBERS_BUTTON",
                                                         comment: "Label for the 'add members' button in the 're-add dropped group members' alert view."),
                                titleColor: .white,
                                backgroundColor: .ows_accentBlue,
                                target: self,
                                selector: #selector(reAddDroppedMembers))
        builder.addVerticalSpacer(height: 5)
        builder.addBottomButton(title: CommonStrings.cancelButton,
                                titleColor: .ows_accentBlue,
                                backgroundColor: .white,
                                target: self,
                                selector: #selector(dismissAlert))

        return builder.subviews
    }

    private func showToast(text: String) {
        guard let viewController = UIApplication.shared.frontmostViewController else {
            owsFailDebug("Missing frontmostViewController.")
            return
        }
        viewController.presentToast(text: text)
    }

    // MARK: - Events

    @objc
    func dismissAlert() {
        actionSheetController?.dismiss(animated: true)
    }
}

// MARK: -

private extension GroupMigrationActionSheet {

    @objc
    func upgradeGroup() {
        guard let actionSheetController = actionSheetController else {
            owsFailDebug("Missing actionSheetController.")
            return
        }

        let groupThread = self.groupThread
        if GroupsV2Migration.verboseLogging {
            Logger.info("groupId: \(groupThread.groupId.hexadecimalString)")
        }

        ModalActivityIndicatorViewController.present(fromViewController: actionSheetController,
                                                     canCancel: false) { modalActivityIndicator in
                                                        firstly {
                                                            self.upgradePromise()
                                                        }.done { (_) in
                                                            if GroupsV2Migration.verboseLogging {
                                                                Logger.info("success groupId: \(groupThread.groupId.hexadecimalString)")
                                                            }

                                                            modalActivityIndicator.dismiss {
                                                                self.dismissAndShowUpgradeSuccessToast()
                                                            }
                                                        }.catch { error in
                                                            if GroupsV2Migration.verboseLogging {
                                                                Logger.info("failure groupId: \(groupThread.groupId.hexadecimalString), error: \(error)")
                                                            }

                                                            owsFailDebug("Error: \(error)")

                                                            modalActivityIndicator.dismiss {
                                                                self.showUpgradeFailedAlert(error: error)
                                                            }
                                                        }
        }
    }

    private func upgradePromise() -> Promise<Void> {
        GroupsV2Migration.tryManualMigration(groupThread: groupThread).asVoid()
    }

    private func dismissAndShowUpgradeSuccessToast() {
        AssertIsOnMainThread()

        guard let actionSheetController = actionSheetController else {
            owsFailDebug("Missing actionSheetController.")
            return
        }

        actionSheetController.dismiss(animated: true) {
            self.showUpgradeSuccessToast()
        }
    }

    private func showUpgradeSuccessToast() {
        let text = NSLocalizedString("GROUPS_LEGACY_GROUP_UPGRADE_ALERT_UPGRADE_SUCCEEDED",
                                     comment: "Message indicating the group update succeeded.")
        showToast(text: text)
    }
}

// MARK: -

private extension GroupMigrationActionSheet {

    @objc
    func reAddDroppedMembers() {
        guard case .reAddDroppedMembers(let members) = mode else {
            owsFailDebug("Invalid mode.")
            return
        }
        guard let actionSheetController = actionSheetController else {
            owsFailDebug("Missing actionSheetController.")
            return
        }
        ModalActivityIndicatorViewController.present(fromViewController: actionSheetController,
                                                     canCancel: false) { modalActivityIndicator in
                                                        firstly {
                                                            self.reAddDroppedMembersPromise(members: members)
                                                        }.done { (_) in
                                                            modalActivityIndicator.dismiss {
                                                                self.dismissActionSheet()
                                                            }
                                                        }.catch { error in
                                                            owsFailDebug("Error: \(error)")

                                                            modalActivityIndicator.dismiss {
                                                                self.showUpgradeFailedAlert(error: error)
                                                            }
                                                        }
        }
    }

    private func reAddDroppedMembersPromise(members: Set<SignalServiceAddress>) -> Promise<Void> {
        guard let oldGroupModel = self.groupThread.groupModel as? TSGroupModelV2 else {
            return Promise(error: OWSAssertionError("Invalid groupModel."))
        }

        return firstly { () -> Promise<Void> in
            GroupManager.messageProcessingPromise(for: oldGroupModel,
                                                  description: self.logTag)
        }.map(on: .global()) { _ -> Promise<TSGroupThread> in
            let uuidsToAdd = members
                .compactMap { address -> UUID? in
                    if let uuid = address.uuid,
                       !oldGroupModel.groupMembership.isMemberOfAnyKind(uuid) {
                        return uuid
                    }

                    return nil
                }

            guard !uuidsToAdd.isEmpty else {
                throw OWSAssertionError("No members to add.")
            }

            return GroupManager.addOrInvite(
                aciOrPniUuids: uuidsToAdd,
                toExistingGroup: oldGroupModel
            )
        }.asVoid()
    }

    private func dismissActionSheet() {
        AssertIsOnMainThread()

        actionSheetController?.dismiss(animated: true)
    }

    private func showUpgradeFailedAlert(error: Error) {
        AssertIsOnMainThread()

        guard let actionSheetController = actionSheetController else {
            owsFailDebug("Missing actionSheetController.")
            return
        }

        let title = NSLocalizedString("GROUPS_LEGACY_GROUP_UPGRADE_ALERT_UPGRADE_FAILED_ERROR_TITLE",
                                      comment: "Title for error alert indicating the group update failed.")
        let message: String
        if error.isNetworkConnectivityFailure {
            message = NSLocalizedString("GROUPS_LEGACY_GROUP_UPGRADE_ALERT_UPGRADE_FAILED_ERROR_MESSAGE_NETWORK",
                                          comment: "Message for error alert indicating the group update failed due to network connectivity.")
        } else {
            message = NSLocalizedString("GROUPS_LEGACY_GROUP_UPGRADE_ALERT_UPGRADE_FAILED_ERROR_MESSAGE",
                                        comment: "Message for error alert indicating the group update failed.")
        }
        OWSActionSheets.showActionSheet(title: title, message: message, fromViewController: actionSheetController)
    }
}

// MARK: -

public extension GroupMigrationActionSheet {

    struct DroppedMembersInfo {
        let groupThread: TSGroupThread
        let addableMembers: Set<SignalServiceAddress>
    }

    static func buildDroppedMembersInfo(thread: TSThread) -> DroppedMembersInfo? {
        guard let groupThread = thread as? TSGroupThread else {
            return nil
        }
        guard let groupModel = groupThread.groupModel as? TSGroupModelV2 else {
            return nil
        }
        guard groupThread.isLocalUserFullMember else {
            return nil
        }

        var addableMembers = Set<SignalServiceAddress>()
        Self.databaseStorage.read { transaction in
            for address in groupModel.droppedMembers {
                guard address.uuid != nil else {
                    continue
                }
                addableMembers.insert(address)
            }
        }
        guard !addableMembers.isEmpty else {
            return nil
        }
        let droppedMembersInfo = DroppedMembersInfo(groupThread: groupThread,
                                                    addableMembers: addableMembers)
        return droppedMembersInfo
    }
}
