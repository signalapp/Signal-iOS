//
// Copyright 2026 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import SignalServiceKit
import UIKit

class ContactSharingRowCell: UITableViewCell, ReusableTableViewCell {
    static let reuseIdentifier = "ContactSharingRowCell"

    static var avatarDiameter: CGFloat { CGFloat(AvatarBuilder.smallAvatarSizePoints) }

    static let avatarTextSpacing: CGFloat = 12
    private static let nameIconSpacing: CGFloat = 6
    private static let verticalMargin: CGFloat = 7

    private let avatarView = AvatarImageView()

    private let nameLabel: UILabel = {
        let label = UILabel()
        label.font = .dynamicTypeBody
        label.adjustsFontForContentSizeCategory = true
        label.lineBreakMode = .byTruncatingTail
        return label
    }()

    private let contactIconLabel: UILabel = {
        let label = UILabel()
        label.adjustsFontForContentSizeCategory = true
        return label
    }()

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)

        selectionStyle = .default
        backgroundColor = .clear
        preservesSuperviewLayoutMargins = true
        contentView.preservesSuperviewLayoutMargins = true

        avatarView.autoSetDimensions(to: CGSize(square: Self.avatarDiameter))

        nameLabel.setCompressionResistanceHorizontalLow()
        contactIconLabel.setCompressionResistanceHigh()
        contactIconLabel.setContentHuggingHorizontalHigh()

        let contentColumns = UIStackView(arrangedSubviews: [
            avatarView,
            nameLabel,
            contactIconLabel,
            UIView.hStretchingSpacer(),
        ])
        contentColumns.axis = .horizontal
        contentColumns.spacing = Self.avatarTextSpacing
        contentColumns.alignment = .center
        contentColumns.setCustomSpacing(Self.nameIconSpacing, after: nameLabel)
        contentColumns.setCustomSpacing(0, after: contactIconLabel)
        contentView.addSubview(contentColumns)
        contentColumns.autoPinWidthToSuperviewMargins()
        contentColumns.autoPinHeightToSuperview(withMargin: Self.verticalMargin)
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        avatarView.image = nil
        nameLabel.text = nil
        contactIconLabel.attributedText = nil
        contactIconLabel.isHidden = true
    }

    func configure(avatarImage: UIImage?, displayName: String, shouldShowContactIcon: Bool) {
        nameLabel.textColor = Theme.primaryTextColor
        nameLabel.text = displayName
        avatarView.image = avatarImage

        if shouldShowContactIcon {
            contactIconLabel.attributedText = SignalSymbol.personCircle.attributedString(
                dynamicTypeBaseSize: 14,
                weight: .bold,
                attributes: [.foregroundColor: Theme.primaryTextColor],
            )
            contactIconLabel.isHidden = false
        } else {
            contactIconLabel.attributedText = nil
            contactIconLabel.isHidden = true
        }
    }
}
