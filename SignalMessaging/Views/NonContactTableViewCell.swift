//
//  Copyright (c) 2019 Open Whisper Systems. All rights reserved.
//

import Foundation

@objc
class NonContactTableViewCell: UITableViewCell {
    private let iconView = UIImageView()
    private let identifierLabel = UILabel()
    private let headerLabel = UILabel()

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)

        backgroundColor = Theme.backgroundColor

        let stackView = UIStackView()
        stackView.isLayoutMarginsRelativeArrangement = true
        stackView.layoutMargins = UIEdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16)
        stackView.spacing = 12
        stackView.addArrangedSubview(iconView)

        contentView.addSubview(stackView)
        stackView.autoPinEdgesToSuperviewEdges()

        iconView.autoSetDimensions(to: CGSize(square: 48))

        let labelStack = UIStackView()
        labelStack.axis = .vertical
        stackView.addArrangedSubview(labelStack)

        let topSpacer = UIView.vStretchingSpacer()
        labelStack.addArrangedSubview(topSpacer)

        headerLabel.font = .ows_dynamicTypeBody
        headerLabel.textColor = Theme.primaryColor
        labelStack.addArrangedSubview(headerLabel)

        identifierLabel.font = UIFont.ows_dynamicTypeBody.ows_semiBold()
        identifierLabel.textColor = Theme.primaryColor
        labelStack.addArrangedSubview(identifierLabel)

        let bottomSpacer = UIView.vStretchingSpacer()
        labelStack.addArrangedSubview(bottomSpacer)
        bottomSpacer.autoMatch(.height, to: .height, of: topSpacer)
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    @objc public func configureWithUsername(_ username: String) {
        iconView.setTemplateImageName("username-search-48-black", tintColor: Theme.isDarkThemeEnabled ? .ows_gray15 : .ows_gray75)
        headerLabel.text = NSLocalizedString("NON_CONTACT_TABLE_CELL_NEW_MESSAGE",
                                             comment: "A string prompting the user to send a new mesaage to a user")
        identifierLabel.text = CommonFormats.formatUsername(username)
    }

    @objc public func configureWithPhoneNumber(_ phoneNumber: String, isRegistered: Bool) {
        identifierLabel.text = PhoneNumber.bestEffortFormatPartialUserSpecifiedText(toLookLikeAPhoneNumber: phoneNumber)

        if isRegistered {
            iconView.setTemplateImageName("username-search-48-black", tintColor: Theme.isDarkThemeEnabled ? .ows_gray15 : .ows_gray75)
            headerLabel.text = NSLocalizedString("NON_CONTACT_TABLE_CELL_NEW_MESSAGE",
                                                 comment: "A string prompting the user to send a new mesaage to a user")
        } else {
            iconView.image = UIImage(named: "invite-SMS-\(Theme.isDarkThemeEnabled ? "dark-" : "")48")
            headerLabel.text = NSLocalizedString("NON_CONTACT_TABLE_CELL_SEND_SMS",
                                                 comment: "A string asking the user if they'd like to invite a number to signal via SMS.")
        }
    }
}
