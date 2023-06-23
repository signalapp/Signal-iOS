//
// Copyright 2019 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import SignalMessaging

public final class NonContactTableViewCell: UITableViewCell, ReusableTableViewCell {
    @objc
    public static let reuseIdentifier = "NonContactTableViewCell"

    private let iconView: UIImageView = {
        let avatarSize = CGFloat(AvatarBuilder.smallAvatarSizePoints)
        let iconView = UIImageView()
        iconView.contentMode = .center
        iconView.autoSetDimensions(to: CGSize(square: avatarSize))
        iconView.layer.cornerRadius = avatarSize * 0.5
        iconView.clipsToBounds = true
        return iconView
    }()

    private let labelView: UILabel = {
        let labelView = UILabel()
        labelView.font = OWSTableItem.primaryLabelFont
        return labelView
    }()

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)

        OWSTableItem.configureCell(self)

        let stackView = UIStackView()
        stackView.spacing = ContactCellView.avatarTextHSpacing
        stackView.addArrangedSubview(iconView)
        stackView.addArrangedSubview(labelView)
        contentView.addSubview(stackView)
        stackView.autoPinWidthToSuperviewMargins()
        stackView.autoPinHeightToSuperview(withMargin: 7)
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func configureWithTitle(_ title: String, imageName: String) {
        iconView.setTemplateImageName(imageName, tintColor: Theme.isDarkThemeEnabled ? .ows_gray02 : .ows_gray75)
        iconView.backgroundColor = Theme.isDarkThemeEnabled ? .ows_gray75 : .ows_gray10
        labelView.textColor = Theme.primaryTextColor
        labelView.text = title
    }

    public func configureWithUsername(_ username: String) {
        configureWithTitle(username, imageName: "search-20")
    }

    public func configureWithPhoneNumber(_ phoneNumber: String) {
        let formattedPhoneNumber = PhoneNumber.bestEffortFormatPartialUserSpecifiedText(toLookLikeAPhoneNumber: phoneNumber)
        configureWithTitle(formattedPhoneNumber, imageName: "person-20")
    }
}
