//
// Copyright 2022 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import SignalServiceKit
import SignalUI

class BadgeGiftingThanksSheet: OWSTableViewController2 {
    private let thread: TSContactThread
    private let badge: ProfileBadge

    init(thread: TSContactThread, badge: ProfileBadge) {
        owsAssertDebug(badge.assets != nil)
        self.thread = thread
        self.badge = badge

        super.init()

        self.defaultSpacingBetweenSections = 16

        if let presentationController = sheetPresentationController {
            presentationController.detents = [.medium()]
            presentationController.prefersGrabberVisible = true
            presentationController.preferredCornerRadius = 16
        }
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        setUpTableContents()
    }

    private static func tableCell() -> UITableViewCell {
        let cell = OWSTableItem.newCell()
        cell.selectionStyle = .none
        cell.layoutMargins = UIEdgeInsets(hMargin: 24, vMargin: 0)
        cell.contentView.layoutMargins = .zero
        return cell
    }

    private func setUpTableContents() {
        let avatarView = ConversationAvatarView(
            sizeClass: .eightyEight,
            localUserDisplayMode: .asUser,
            badged: true,
        )
        let recipientName = SSKEnvironment.shared.databaseStorageRef.read { transaction -> String in
            avatarView.update(transaction) { config in
                config.dataSource = .thread(self.thread)
            }
            return SSKEnvironment.shared.contactManagerRef.displayName(for: self.thread, transaction: transaction)
        }

        let titleSection = OWSTableSection()
        titleSection.hasBackground = false
        titleSection.add(.init(customCellBlock: {
            let cell = Self.tableCell()

            let titleLabel = UILabel.title2Label(text: OWSLocalizedString(
                "DONATION_ON_BEHALF_OF_A_FRIEND_THANKS_TITLE",
                comment: "When you donate on behalf of a friend, a thank-you sheet will appear. This is the title on that sheet.",
            ))

            cell.contentView.addSubview(titleLabel)
            titleLabel.autoPinEdgesToSuperviewMargins()

            return cell
        }))

        let infoSection = OWSTableSection()
        infoSection.hasBackground = false
        infoSection.add(.init(customCellBlock: {
            let cell = Self.tableCell()

            let infoLabelFormat = OWSLocalizedString(
                "DONATION_ON_BEHALF_OF_A_FRIEND_THANKS_BODY_FORMAT",
                comment: "When you donate on behalf of a friend, a thank-you sheet will appear. This is the text on that sheet. Embeds {{recipient name}}.",
            )
            let infoLabel = UILabel.explanationTextLabel(text: String(format: infoLabelFormat, recipientName))

            cell.contentView.addSubview(infoLabel)
            infoLabel.autoPinEdgesToSuperviewMargins()

            return cell
        }))

        let avatarSection = OWSTableSection()
        avatarSection.hasBackground = false
        avatarSection.add(.init(customCellBlock: {
            let cell = Self.tableCell()

            let avatarDiameter = avatarView.configuration.sizeClass.diameter

            cell.contentView.autoPinWidthToSuperviewMargins()
            cell.contentView.autoSetDimension(.height, toSize: CGFloat(avatarDiameter + 16))
            cell.contentView.addSubview(avatarView)
            avatarView.autoHCenterInSuperview()

            return cell
        }))

        let dismissButtonSection = OWSTableSection()
        dismissButtonSection.hasBackground = false
        dismissButtonSection.add(.init(customCellBlock: { [weak self] in
            let cell = Self.tableCell()

            let dismissButton = UIButton(
                configuration: .largePrimary(title: CommonStrings.okayButton),
                primaryAction: UIAction { [weak self] _ in
                    self?.dismiss(animated: true)
                },
            )
            cell.contentView.addSubview(dismissButton)
            dismissButton.autoPinEdgesToSuperviewMargins()

            return cell
        }))

        contents = OWSTableContents(sections: [
            titleSection,
            infoSection,
            avatarSection,
            dismissButtonSection,
        ])
    }
}
