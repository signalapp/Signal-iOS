//
// Copyright 2022 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import SignalUI
import UIKit

class BadgeGiftingAlreadyRedeemedSheet: OWSTableSheetViewController {
    private let profileBadge: ProfileBadge
    private let fullName: String

    public init(badge: ProfileBadge, fullName: String) {
        owsAssertDebug(badge.assets != nil)

        self.profileBadge = badge
        self.fullName = fullName

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
            titleLabel.font = .ows_dynamicTypeTitle2.ows_semibold
            titleLabel.textColor = Theme.primaryTextColor
            titleLabel.textAlignment = .center
            titleLabel.numberOfLines = 0
            titleLabel.text = BadgeGiftingStrings.giftBadgeTitle
            stackView.addArrangedSubview(titleLabel)
            stackView.setCustomSpacing(12, after: titleLabel)

            let label = UILabel()
            label.font = .ows_dynamicTypeBody
            label.textColor = Theme.primaryTextColor
            label.numberOfLines = 0
            label.text = BadgeGiftingStrings.youReceived(from: self.fullName)
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
