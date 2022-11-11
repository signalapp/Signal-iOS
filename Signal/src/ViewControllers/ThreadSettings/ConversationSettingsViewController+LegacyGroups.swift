//
// Copyright 2020 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import SignalMessaging
import UIKit

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
        fatalError("init(coder:) has not been implemented")
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
        let learnMoreText = CommonStrings.learnMore
        configureLabel(format: format, highlightedSubstring: learnMoreText)

        isUserInteractionEnabled = true
        addGestureRecognizer(UITapGestureRecognizer(target: self,
                                                    action: #selector(didTapLearnMore)))
    }

    func configureCantUpgradeDueToMembersContents() {
        let format = NSLocalizedString("GROUPS_LEGACY_GROUP_DESCRIPTION_MEMBERS_CANT_BE_MIGRATED_FORMAT",
                                       comment: "Indicates that a legacy group can't be upgraded because some members can't be migrated. Embeds {{ an \"learn more\" link. }}.")
        let learnMoreText = CommonStrings.learnMore
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
            Logger.verbose("Local user has not accepted message request.")
            configureDefaultLabelContents()
        case .cantBeMigrated_TooManyMembers:
            let format = NSLocalizedString("GROUPS_LEGACY_GROUP_DESCRIPTION_TOO_MANY_MEMBERS_FORMAT",
                                           comment: "Indicates that a legacy group can't be upgraded because it has too many members. Embeds {{ an \"learn more\" link. }}.")
            let learnMoreText = CommonStrings.learnMore
            configureLabel(format: format, highlightedSubstring: learnMoreText)

            isUserInteractionEnabled = true
            addGestureRecognizer(UITapGestureRecognizer(target: self,
                                                        action: #selector(didTapTooManyMembers)))
        case .cantBeMigrated_MembersWithoutUuids:
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
        showMigrationAlert(mode: .upgradeGroup(migrationInfo: migrationInfo))
    }

    @objc
    public func didTapTooManyMembers() {
        showMigrationAlert(mode: .tooManyMembers)
    }

    @objc
    public func didTapCantUpgradeDueToMemberState() {
        showMigrationAlert(mode: .someMembersCantMigrate)
    }

    private func showMigrationAlert(mode: GroupMigrationActionSheet.Mode) {
        guard let viewController = viewController else {
            owsFailDebug("Missing viewController.")
            return
        }
        let view = GroupMigrationActionSheet(groupThread: groupThread, mode: mode)
        view.present(fromViewController: viewController)
    }
}

// MARK: -

public class LegacyGroupViewLearnMoreView: UIView {

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
