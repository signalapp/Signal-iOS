//
// Copyright 2022 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import SignalUI
import UIKit

class BadgeGiftingAlreadyRedeemedSheet: OWSTableSheetViewController {
    private let profileBadge: ProfileBadge
    private let shortName: String

    public init(badge: ProfileBadge, shortName: String) {
        owsAssertDebug(badge.assets != nil)

        self.profileBadge = badge
        self.shortName = shortName

        super.init()

        updateTableContents()
    }

    public required init() {
        fatalError("init() has not been implemented")
    }

    public override func updateTableContents(shouldReload: Bool = true) {
        let contents = OWSTableContents()
        defer { tableViewController.setContents(contents, shouldReload: shouldReload) }

        let headerSection = OWSTableSection()
        headerSection.hasBackground = false
        headerSection.customHeaderHeight = 1
        contents.addSection(headerSection)

        headerSection.add(.init(customCellBlock: { [weak self] in
            let cell = OWSTableItem.newCell()
            guard let self = self else { return cell }
            cell.selectionStyle = .none

            let stackView = UIStackView()
            stackView.axis = .vertical
            stackView.alignment = .center
            stackView.layoutMargins = UIEdgeInsets(hMargin: 24, vMargin: 0)
            stackView.isLayoutMarginsRelativeArrangement = true

            cell.contentView.addSubview(stackView)
            stackView.autoPinEdgesToSuperviewEdges()

            let badgeImageView = UIImageView()
            badgeImageView.image = self.profileBadge.assets?.universal160
            badgeImageView.autoSetDimensions(to: CGSize(square: 160))
            stackView.addArrangedSubview(badgeImageView)
            stackView.setCustomSpacing(24, after: badgeImageView)

            let titleLabel = UILabel()
            let titleFormat = OWSLocalizedString(
                "DONATION_ON_BEHALF_OF_A_FRIEND_REDEEM_BADGE_TITLE_FORMAT",
                comment: "A friend has donated on your behalf and you received a badge. A sheet opens for you to redeem this badge. Embeds {{contact's short name, such as a first name}}."
            )
            titleLabel.font = .dynamicTypeTitle2.semibold()
            titleLabel.textColor = Theme.primaryTextColor
            titleLabel.textAlignment = .center
            titleLabel.numberOfLines = 0
            titleLabel.text = String(format: titleFormat, self.shortName)
            stackView.addArrangedSubview(titleLabel)
            stackView.setCustomSpacing(12, after: titleLabel)

            let label = UILabel()
            let labelFormat = OWSLocalizedString(
                "DONATION_ON_BEHALF_OF_A_FRIEND_YOU_RECEIVED_A_BADGE_FORMAT",
                comment: "A friend has donated on your behalf and you received a badge. This text says that you received a badge, and from whom. Embeds {{contact's short name, such as a first name}}."
            )
            label.font = .dynamicTypeBody
            label.textColor = Theme.primaryTextColor
            label.numberOfLines = 0
            label.text = String(format: labelFormat, self.shortName)
            label.textAlignment = .center
            stackView.addArrangedSubview(label)

            return cell
        }, actionBlock: nil))
    }

    public override func willDismissInteractively() {
        super.willDismissInteractively()
        self.dismiss(animated: true)
    }
}
