//
// Copyright 2019 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import SignalMessaging

@objc
public class NonContactTableViewCell: UITableViewCell {
    private let iconView = UIImageView()
    private let identifierLabel = UILabel()
    private let headerLabel = UILabel()
    private let accessoryLabel = UILabel()

    @objc
    public var accessoryMessage: String?

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)

        OWSTableItem.configureCell(self)

        let stackView = UIStackView()
        stackView.spacing = ContactCellView.avatarTextHSpacing
        stackView.addArrangedSubview(iconView)

        contentView.addSubview(stackView)
        stackView.autoPinWidthToSuperviewMargins()
        stackView.autoPinHeightToSuperview(withMargin: 7)

        let avatarSize = CGFloat(AvatarBuilder.smallAvatarSizePoints)
        iconView.autoSetDimensions(to: CGSize(square: avatarSize))
        iconView.layer.cornerRadius = avatarSize * 0.5
        iconView.clipsToBounds = true

        let labelStack = UIStackView()
        labelStack.axis = .vertical
        stackView.addArrangedSubview(labelStack)

        let topSpacer = UIView.vStretchingSpacer()
        labelStack.addArrangedSubview(topSpacer)

        headerLabel.font = OWSTableItem.primaryLabelFont
        headerLabel.textColor = Theme.primaryTextColor
        labelStack.addArrangedSubview(headerLabel)

        identifierLabel.font = OWSTableItem.primaryLabelFont.ows_semibold
        identifierLabel.textColor = Theme.primaryTextColor
        labelStack.addArrangedSubview(identifierLabel)

        let bottomSpacer = UIView.vStretchingSpacer()
        labelStack.addArrangedSubview(bottomSpacer)
        bottomSpacer.autoMatch(.height, to: .height, of: topSpacer)

        accessoryLabel.font = OWSTableItem.accessoryLabelFont.ows_semibold
        accessoryLabel.textColor = Theme.middleGrayColor
        accessoryLabel.textAlignment = .right
        accessoryLabel.isHidden = true
        stackView.addArrangedSubview(accessoryLabel)
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    @objc
    public func configureWithUsername(_ username: String, hideHeaderLabel: Bool) {
        iconView.setTemplateImageName("username-search-48-black", tintColor: Theme.isDarkThemeEnabled ? .ows_gray15 : .ows_gray75)
        headerLabel.text = OWSLocalizedString("NON_CONTACT_TABLE_CELL_NEW_MESSAGE",
                                             comment: "A string prompting the user to send a new mesaage to a user")
        headerLabel.isHidden = hideHeaderLabel
        identifierLabel.text = CommonFormats.formatUsername(username)
    }

    @objc
    public func configureWithPhoneNumber(_ phoneNumber: String, isRegistered: Bool, hideHeaderLabel: Bool) {
        identifierLabel.text = PhoneNumber.bestEffortFormatPartialUserSpecifiedText(toLookLikeAPhoneNumber: phoneNumber)

        if isRegistered {
            let address = SignalServiceAddress(phoneNumber: phoneNumber)
            let avatar = Self.avatarBuilder.avatarImageWithSneakyTransaction(forAddress: address,
                                                                             diameterPoints: 48,
                                                                             localUserDisplayMode: .asUser)
            iconView.image = avatar
            headerLabel.text = OWSLocalizedString("NON_CONTACT_TABLE_CELL_NEW_MESSAGE",
                                                 comment: "A string prompting the user to send a new mesaage to a user")
        } else {
            iconView.image = UIImage(named: "invite-SMS-\(Theme.isDarkThemeEnabled ? "dark-" : "")48")
            headerLabel.text = OWSLocalizedString("NON_CONTACT_TABLE_CELL_SEND_SMS",
                                                 comment: "A string asking the user if they'd like to invite a number to signal via SMS.")
        }

        headerLabel.isHidden = hideHeaderLabel

        if let accessoryMessage = accessoryMessage, !accessoryMessage.isEmpty {
            accessoryLabel.text = accessoryMessage
            accessoryLabel.isHidden = false
        } else {
            accessoryLabel.isHidden = true
        }
    }
}
