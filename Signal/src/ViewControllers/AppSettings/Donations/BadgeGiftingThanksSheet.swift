//
//  Copyright (c) 2022 Open Whisper Systems. All rights reserved.
//

import Foundation
import UIKit

class BadgeGiftingThanksSheet: OWSTableViewController2 {
    private let thread: TSContactThread
    private let badge: ProfileBadge

    init(thread: TSContactThread, badge: ProfileBadge) {
        owsAssertDebug(badge.assets != nil)
        self.thread = thread
        self.badge = badge

        super.init()

        self.defaultSpacingBetweenSections = 16

        if #available(iOS 15.0, *), let presentationController = presentationController as? UISheetPresentationController {
            presentationController.detents = [.medium()]
            presentationController.prefersGrabberVisible = true
            presentationController.preferredCornerRadius = 16
        }
    }

    override public func viewDidLoad() {
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
        let avatarView = ConversationAvatarView(sizeClass: .eightyEight,
                                                localUserDisplayMode: .asUser,
                                                badged: true)
        let recipientName = databaseStorage.read { transaction -> String in
            avatarView.update(transaction) { config in
                config.dataSource = .thread(self.thread)
            }
            return self.contactsManager.displayName(for: self.thread, transaction: transaction)
        }

        let titleSection = OWSTableSection()
        titleSection.hasBackground = false
        titleSection.add(.init(customCellBlock: {
            let cell = Self.tableCell()

            let titleLabel = UILabel()
            titleLabel.text = NSLocalizedString("BADGE_GIFT_THANKS_TITLE",
                                                comment: "Title for the sheet that's shown when you gift someone a badge")
            titleLabel.textAlignment = .center
            titleLabel.font = .ows_dynamicTypeTitle2.ows_semibold
            titleLabel.numberOfLines = 0

            cell.contentView.addSubview(titleLabel)
            titleLabel.autoPinEdgesToSuperviewMargins()

            return cell
        }))

        let infoSection = OWSTableSection()
        infoSection.hasBackground = false
        infoSection.add(.init(customCellBlock: {
            let cell = Self.tableCell()

            let infoLabel = UILabel()
            infoLabel.text = String(format: NSLocalizedString("BADGE_GIFT_THANKS_BODY",
                                                              comment: "Text in the sheet that's shown when you gift someone a badge. Embeds {recipient name}."),
                                    recipientName)
            infoLabel.textAlignment = .center
            infoLabel.font = .ows_dynamicTypeBody
            infoLabel.numberOfLines = 0

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

            let dismissButton = OWSFlatButton()
            dismissButton.setTitle(
                title: CommonStrings.okayButton,
                font: .ows_dynamicTypeBody.ows_semibold,
                titleColor: .white
            )
            dismissButton.setBackgroundColors(upColor: .ows_accentBlue)
            dismissButton.setPressedBlock { [weak self] in
                self?.dismiss(animated: true)
            }
            dismissButton.autoSetHeightUsingFont()
            dismissButton.cornerRadius = 8
            cell.contentView.addSubview(dismissButton)
            dismissButton.autoPinWidthToSuperviewMargins()

            return cell
        }))

        contents = OWSTableContents(sections: [titleSection,
                                               infoSection,
                                               avatarSection,
                                               dismissButtonSection])
    }
}
