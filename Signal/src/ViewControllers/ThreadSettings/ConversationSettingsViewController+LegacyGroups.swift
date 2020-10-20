//
//  Copyright (c) 2020 Open Whisper Systems. All rights reserved.
//

import Foundation
import UIKit
import PromiseKit

class LegacyGroupView: UIView {

    private let groupThread: TSGroupThread
    private let migrationInfo: GroupsV2MigrationInfo
    private weak var viewController: UIViewController?

    required init(groupThread: TSGroupThread,
                  migrationInfo: GroupsV2MigrationInfo,
                  viewController: UIViewController) {
        self.groupThread = groupThread
        self.migrationInfo = migrationInfo
        self.viewController = viewController

        super.init(frame: .zero)
    }

    @available(*, unavailable, message: "use other init() instead.")
    required public init(coder aDecoder: NSCoder) {
        notImplemented()
    }

    private let label = UILabel()

    func configureLabel(format: String, highlightedSubstring: String) {
        let text = String(format: format, highlightedSubstring)
        let attributedString = NSMutableAttributedString(string: text)
        attributedString.setAttributes([
            .foregroundColor: Theme.accentBlueColor
            ],
                                       forSubstring: highlightedSubstring)
        label.attributedText = attributedString
    }

    func configureDefaultLabelContents() {
        let format = NSLocalizedString("GROUPS_LEGACY_GROUP_DESCRIPTION_FORMAT",
                                       comment: "Brief explanation of legacy groups. Embeds {{ a \"learn more\" link. }}.")
        let learnMoreText = NSLocalizedString("GROUPS_LEGACY_GROUP_LEARN_MORE_LINK",
                                              comment: "A \"learn more\" link with more information about legacy groups.")
        configureLabel(format: format, highlightedSubstring: learnMoreText)

        isUserInteractionEnabled = true
        addGestureRecognizer(UITapGestureRecognizer(target: self,
                                                    action: #selector(didTapLearnMore)))
    }

    func configureCantUpgradeDueToMembersContents() {
        let format = NSLocalizedString("GROUPS_LEGACY_GROUP_DESCRIPTION_MEMBERS_CANT_BE_MIGRATED_FORMAT",
                                       comment: "Indicates that a legacy group can't be upgraded because some members can't be migrated. Embeds {{ an \"learn more\" link. }}.")
        let learnMoreText = NSLocalizedString("GROUPS_LEGACY_GROUP_LEARN_MORE_LINK",
                                              comment: "A \"learn more\" link with more information about legacy groups.")
        configureLabel(format: format, highlightedSubstring: learnMoreText)

        isUserInteractionEnabled = true
        addGestureRecognizer(UITapGestureRecognizer(target: self,
                                                    action: #selector(didTapCantUpgradeDueToMemberState)))
    }

    public func configure() {
        backgroundColor = Theme.secondaryBackgroundColor
        layer.cornerRadius = 4
        layoutMargins = UIEdgeInsets(top: 10, leading: 12, bottom: 10, trailing: 12)

        label.textColor = Theme.secondaryTextAndIconColor
        label.font = .ows_dynamicTypeFootnote
        label.numberOfLines = 0
        label.lineBreakMode = .byWordWrapping
        addSubview(label)
        label.autoPinEdgesToSuperviewMargins()

        switch migrationInfo.state {
        case .canBeMigrated:
            let format = NSLocalizedString("GROUPS_LEGACY_GROUP_DESCRIPTION_WITH_UPGRADE_OFFER_FORMAT",
                                           comment: "Explanation of legacy groups. Embeds {{ an \"upgrade\" link. }}.")
            let upgradeText = NSLocalizedString("GROUPS_LEGACY_GROUP_UPGRADE_LINK",
                                                comment: "An \"upgrade\" link for upgrading legacy groups to new groups.")
            configureLabel(format: format, highlightedSubstring: upgradeText)

            isUserInteractionEnabled = true
            addGestureRecognizer(UITapGestureRecognizer(target: self,
                                                        action: #selector(didTapUpgrade)))
        case .cantBeMigrated_FeatureNotEnabled:
            configureDefaultLabelContents()
        case .cantBeMigrated_NotAV1Group:
            owsFailDebug("Unexpected group.")
            configureDefaultLabelContents()
        case .cantBeMigrated_NotRegistered:
            owsFailDebug("Not registered.")
            configureDefaultLabelContents()
        case .cantBeMigrated_LocalUserIsNotAMember:
            Logger.verbose("Local user is not a member.")
            configureDefaultLabelContents()
        case .cantBeMigrated_NotInProfileWhitelist:
            // TODO: Should we special-case this?
            Logger.verbose("Local user has not accepted message request.")
            configureDefaultLabelContents()
        case .cantBeMigrated_TooManyMembers:
            let format = NSLocalizedString("GROUPS_LEGACY_GROUP_DESCRIPTION_TOO_MANY_MEMBERS_FORMAT",
                                           comment: "Indicates that a legacy group can't be upgraded because it has too many members. Embeds {{ an \"learn more\" link. }}.")
            let learnMoreText = NSLocalizedString("GROUPS_LEGACY_GROUP_LEARN_MORE_LINK",
                                                  comment: "A \"learn more\" link with more information about legacy groups.")
            configureLabel(format: format, highlightedSubstring: learnMoreText)

            isUserInteractionEnabled = true
            addGestureRecognizer(UITapGestureRecognizer(target: self,
                                                        action: #selector(didTapTooManyMembers)))
        case .cantBeMigrated_MembersWithoutUuids,
             .cantBeMigrated_MembersWithoutCapabilities:
            configureCantUpgradeDueToMembersContents()
        case .cantBeMigrated_MembersWithoutProfileKey:
            owsFailDebug("Manual migrations should ignore missing profile keys.")
            configureCantUpgradeDueToMembersContents()
        }
    }

    // MARK: - Events

    @objc
    public func didTapLearnMore() {
        guard let viewController = viewController else {
            owsFailDebug("Missing viewController.")
            return
        }
        LegacyGroupViewLearnMoreView().present(fromViewController: viewController)
    }

    @objc
    public func didTapUpgrade() {
        showMigrationAlert(mode: .upgradeGroup)
    }

    @objc
    public func didTapTooManyMembers() {
        showMigrationAlert(mode: .tooManyMembers)
    }

    @objc
    public func didTapCantUpgradeDueToMemberState() {
        showMigrationAlert(mode: .someMembersCantMigrate)
    }

    private func showMigrationAlert(mode: LegacyGroupMigrationView.Mode) {
        guard let viewController = viewController else {
            owsFailDebug("Missing viewController.")
            return
        }
        let view = LegacyGroupMigrationView(groupThread: groupThread,
                                            mode: mode,
                                            migrationInfo: migrationInfo)
        view.present(fromViewController: viewController)
    }
}

// MARK: -

private class LegacyGroupViewLearnMoreView: UIView {

    weak var actionSheetController: ActionSheetController?

    init() {
        super.init(frame: .zero)
    }

    required init(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func present(fromViewController: UIViewController) {
        let buildLabel = { () -> UILabel in
            let label = UILabel()
            label.textColor = Theme.primaryTextColor
            label.numberOfLines = 0
            label.lineBreakMode = .byWordWrapping
            return label
        }

        let titleLabel = buildLabel()
        titleLabel.font = UIFont.ows_dynamicTypeTitle2.ows_semibold
        titleLabel.text = NSLocalizedString("GROUPS_LEGACY_GROUP_ALERT_TITLE",
                                            comment: "Title for the 'legacy group' alert view.")

        let section1TitleLabel = buildLabel()
        section1TitleLabel.font = UIFont.ows_dynamicTypeBody.ows_semibold
        section1TitleLabel.text = NSLocalizedString("GROUPS_LEGACY_GROUP_ALERT_SECTION_1_TITLE",
                                                    comment: "Title for the first section of the 'legacy group' alert view.")

        let section1BodyLabel = buildLabel()
        section1BodyLabel.font = .ows_dynamicTypeBody
        section1BodyLabel.text = NSLocalizedString("GROUPS_LEGACY_GROUP_ALERT_SECTION_1_BODY",
                                                   comment: "Body text for the first section of the 'legacy group' alert view.")

        let section2TitleLabel = buildLabel()
        section2TitleLabel.font = UIFont.ows_dynamicTypeBody.ows_semibold
        section2TitleLabel.text = NSLocalizedString("GROUPS_LEGACY_GROUP_ALERT_SECTION_2_TITLE",
                                                    comment: "Title for the second section of the 'legacy group' alert view.")

        let section2BodyLabel = buildLabel()
        section2BodyLabel.font = .ows_dynamicTypeBody
        section2BodyLabel.text = NSLocalizedString("GROUPS_LEGACY_GROUP_ALERT_SECTION_2_BODY",
                                                   comment: "Body text for the second section of the 'legacy group' alert view.")

        let section3BodyLabel = buildLabel()
        section3BodyLabel.font = .ows_dynamicTypeBody
        section3BodyLabel.text = NSLocalizedString("GROUPS_LEGACY_GROUP_ALERT_SECTION_3_BODY",
                                                   comment: "Body text for the third section of the 'legacy group' alert view.")

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
            titleLabel,
            UIView.spacer(withHeight: 28),
            section1TitleLabel,
            UIView.spacer(withHeight: 4),
            section1BodyLabel,
            UIView.spacer(withHeight: 21),
            section2TitleLabel,
            UIView.spacer(withHeight: 4),
            section2BodyLabel,
            UIView.spacer(withHeight: 24),
            section3BodyLabel,
            UIView.spacer(withHeight: 28),
            okayButton
        ])
        stackView.axis = .vertical
        stackView.alignment = .fill
        stackView.layoutMargins = UIEdgeInsets(top: 48, leading: 20, bottom: 38, trailing: 24)
        stackView.isLayoutMarginsRelativeArrangement = true
        stackView.addBackgroundView(withBackgroundColor: Theme.backgroundColor)

        layoutMargins = .zero
        addSubview(stackView)
        stackView.autoPinEdgesToSuperviewMargins()

        let actionSheetController = ActionSheetController()
        actionSheetController.customHeader = self
        actionSheetController.isCancelable = true
        fromViewController.presentActionSheet(actionSheetController)
        self.actionSheetController = actionSheetController
    }

    // MARK: - Events

    @objc
    func dismissAlert() {
        actionSheetController?.dismiss(animated: true)
    }
}

// MARK: -

private class LegacyGroupMigrationView: UIView {

    enum Mode {
        case upgradeGroup
        case tooManyMembers
        case someMembersCantMigrate
    }

    private let groupThread: TSGroupThread
    private let mode: Mode
    private let migrationInfo: GroupsV2MigrationInfo

    weak var actionSheetController: ActionSheetController?

    required init(groupThread: TSGroupThread,
                  mode: Mode,
                  migrationInfo: GroupsV2MigrationInfo) {
        self.groupThread = groupThread
        self.mode = mode
        self.migrationInfo = migrationInfo

        super.init(frame: .zero)
    }

    required init(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func present(fromViewController: UIViewController) {
        let subviews = buildContents()

        let stackView = UIStackView(arrangedSubviews: subviews)
        stackView.axis = .vertical
        stackView.alignment = .fill
        stackView.layoutMargins = UIEdgeInsets(top: 48, leading: 20, bottom: 38, trailing: 24)
        stackView.isLayoutMarginsRelativeArrangement = true
        stackView.addBackgroundView(withBackgroundColor: Theme.backgroundColor)

        layoutMargins = .zero
        addSubview(stackView)
        stackView.autoPinEdgesToSuperviewMargins()

        let actionSheetController = ActionSheetController(isFullWidth: true)
        actionSheetController.customHeader = self
        actionSheetController.isCancelable = true
        fromViewController.presentActionSheet(actionSheetController)
        self.actionSheetController = actionSheetController
    }

    private struct Builder {

        // MARK: - Dependencies

        private static var contactsManager: OWSContactsManager {
            return Environment.shared.contactsManager
        }

        // MARK: -

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

            if hasBulletPoint {
                let bullet = UIView()
                bullet.autoSetDimensions(to: bulletSize)
                // TODO: Dark theme value?
                bullet.backgroundColor =  UIColor(rgbHex: 0xdedede)
                bulletWrapper.addSubview(bullet)
                bullet.autoPinEdge(toSuperviewEdge: .top, withInset: 4)
                bullet.autoPinEdge(toSuperviewEdge: .leading)
                bullet.autoPinEdge(toSuperviewEdge: .trailing)
            }

            bulletWrapper.setContentHuggingHorizontalHigh()
            subview.setContentHuggingHorizontalLow()
            subview.setCompressionResistanceVerticalHigh()

            let row = UIStackView(arrangedSubviews: [bulletWrapper, subview])
            row.axis = .horizontal
            row.alignment = .top
            row.spacing = 20
            row.setCompressionResistanceVerticalHigh()
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

            let avatarSize: UInt = 28
            let conversationColorName = TSContactThread.conversationColorName(forContactAddress: address,
                                                                              transaction: transaction)
            let avatarBuilder = OWSContactAvatarBuilder(address: address,
                                                        colorName: conversationColorName,
                                                        diameter: avatarSize,
                                                        transaction: transaction)
            let avatar = avatarBuilder.build(with: transaction)

            let avatarView = AvatarImageView()
            avatarView.image = avatar
            avatarView.autoSetDimensions(to: CGSize(square: CGFloat(avatarSize)))
            avatarView.setContentHuggingHorizontalHigh()

            let label = buildLabel()
            label.font = .ows_dynamicTypeBody
            label.text = Self.contactsManager.displayName(for: address, transaction: transaction)
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
        case .upgradeGroup:
            return buildUpgradeGroupContents()
        case .tooManyMembers:
            return buildTooManyMembersContents()
        case .someMembersCantMigrate:
            return buildSomeMembersCantMigrateContents()
        }
    }

    private func buildUpgradeGroupContents() -> [UIView] {
        var builder = Builder()

        builder.addTitleLabel(text: NSLocalizedString("GROUPS_LEGACY_GROUP_UPGRADE_ALERT_TITLE",
                                                      comment: "Title for the 'upgrade legacy group' alert view."))
        builder.addVerticalSpacer(height: 28)

        builder.addBodyLabel(NSLocalizedString("GROUPS_LEGACY_GROUP_NEW_GROUP_DESCRIPTION",
                                               comment: "Explanation of new groups in the 'legacy group' alert views."))
        builder.addVerticalSpacer(height: 20)
        builder.addBodyLabel(NSLocalizedString("GROUPS_LEGACY_GROUP_UPGRADE_ALERT_SECTION_2_BODY",
                                               comment: "Body text for the second section of the 'upgrade legacy group' alert view."))

        let migrationInfo = self.migrationInfo
        databaseStorage.read { transaction in
            // TODO: We need to break these out into separate sections.
            // TODO: Scroll view?
            //            let members = (migrationInfo.membersWithoutUuids +
            //                migrationInfo.membersWithoutCapabilities +
            //                migrationInfo.membersWithoutProfileKeys)
            var members = (migrationInfo.membersWithoutUuids +
                migrationInfo.membersWithoutCapabilities +
                migrationInfo.membersWithoutProfileKeys)
            members = members + members
            members = members + members
            members = members + members
            members = members + members
            if !members.isEmpty {
                builder.addVerticalSpacer(height: 20)
                builder.addBodyLabel(NSLocalizedString("GROUPS_LEGACY_GROUP_UPGRADE_ALERT_SECTION_INVITED_MEMBERS",
                                                       comment: "Body text for the 'invites members' section of the 'upgrade legacy group' alert view."))
                for address in members {
                    builder.addVerticalSpacer(height: 16)
                    builder.addMemberRow(address: address, transaction: transaction)
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

        builder.addVerticalSpacer(height: 40)

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
                                               comment: "Explanation group migration for groups that can't yet be migrated in the 'legacy group' alert views."))
        builder.addVerticalSpacer(height: 20)
        builder.addBodyLabel(NSLocalizedString("GROUPS_LEGACY_GROUP_CANT_UPGRADE_YET_2",
                                               comment: "Explanation group migration for groups that can't yet be migrated in the 'legacy group' alert views."))

        builder.addVerticalSpacer(height: 40)

        builder.addOkayButton(target: self, selector: #selector(dismissAlert))

        return builder.subviews
    }

    // MARK: - Events

    @objc
    func dismissAlert() {
        actionSheetController?.dismiss(animated: true)
    }

    @objc
    func upgradeGroup() {
        guard let actionSheetController = actionSheetController else {
            owsFailDebug("Missing actionSheetController.")
            return
        }
        ModalActivityIndicatorViewController.present(fromViewController: actionSheetController,
                                                     canCancel: false) { modalActivityIndicator in
                                                        firstly {
                                                            self.upgradePromise()
                                                        }.done { (_) in
                                                            modalActivityIndicator.dismiss {
                                                                self.dismissAndShowUpgradeSuccessToast()
                                                            }
                                                        }.catch { error in
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
        guard let viewController = UIApplication.shared.frontmostViewController else {
            owsFailDebug("Missing frontmostViewController.")
            return
        }

        let text = NSLocalizedString("GROUPS_LEGACY_GROUP_UPGRADE_ALERT_UPGRADE_SUCCEEDED",
                                     comment: "Message indicating the group update succeeded.")
        let toastController = ToastController(text: text)
        let toastInset = viewController.bottomLayoutGuide.length + 8
        toastController.presentToastView(fromBottomOfView: viewController.view, inset: toastInset)
    }

    private func showUpgradeFailedAlert(error: Error) {
        AssertIsOnMainThread()

        guard let actionSheetController = actionSheetController else {
            owsFailDebug("Missing actionSheetController.")
            return
        }

        let title: String
        // TODO: We need final copy.
        title = NSLocalizedString("GROUPS_LEGACY_GROUP_UPGRADE_ALERT_UPGRADE_FAILED_ERROR",
                                  comment: "Error indicating the group update failed.")
        OWSActionSheets.showActionSheet(title: title, fromViewController: actionSheetController)
    }
}
