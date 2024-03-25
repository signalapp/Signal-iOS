//
// Copyright 2018 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Contacts
import SignalServiceKit

public class ContactFieldViewHelper {

    public class func contactFieldView(forAvatarImage avatarImage: UIImage) -> UIView {
        let avatarView = AvatarImageView()
        avatarView.image = avatarImage
        avatarView.autoSetDimensions(to: .square(56))

        // Container allows to provide additional vertical margin around avatar.
        let containerView = UIView.container()
        containerView.addSubview(avatarView)
        avatarView.autoPinHeightToSuperview(withMargin: 4)
        avatarView.autoPinEdge(toSuperviewEdge: .leading)
        NSLayoutConstraint.autoSetPriority(.defaultHigh) {
            avatarView.autoPinEdge(toSuperviewEdge: .trailing, relation: .lessThanOrEqual)
        }
        return containerView
    }

    public class func contactFieldView(forContactName contactName: String) -> UIView {
        return simpleFieldView(name: nil, value: contactName)
    }

    public class func contactFieldView(forOrganizationName organizationName: String) -> UIView {
        return simpleFieldView(
            name: OWSLocalizedString("CONTACT_FIELD_ORGANIZATION", comment: "Label for the 'organization' field of a contact."),
            value: organizationName
        )
    }

    public class func contactFieldView(forPhoneNumber phoneNumber: OWSContactPhoneNumber) -> UIView {
        let formattedPhoneNumber = PhoneNumber.bestEffortLocalizedPhoneNumber(withE164: phoneNumber.phoneNumber)
        return simpleFieldView(name: phoneNumber.localizedLabel, value: formattedPhoneNumber)
    }

    public class func contactFieldView(forEmail email: OWSContactEmail) -> UIView {
        return simpleFieldView(name: email.localizedLabel, value: email.email)
    }

    private class func simpleFieldView(name: String?, value: String?) -> UIView {
        let stackView = UIStackView()
        stackView.axis = .vertical
        stackView.alignment = .leading
        stackView.spacing = 3

        if let name {
            let nameLabel = UILabel()
            nameLabel.text = name.lowercased()
            nameLabel.font = .dynamicTypeSubheadline
            nameLabel.textColor = Theme.secondaryTextAndIconColor
            nameLabel.lineBreakMode = .byTruncatingTail
            stackView.addArrangedSubview(nameLabel)
        }

        let valueLabel = UILabel()
        valueLabel.text = value
        valueLabel.font = .dynamicTypeBody
        valueLabel.textColor = Theme.primaryTextColor
        valueLabel.lineBreakMode = .byTruncatingTail
        stackView.addArrangedSubview(valueLabel)

        return stackView
    }

    public class func contactFieldView(forAddress address: OWSContactAddress) -> UIView {
        owsAssertDebug(address.isValid)

        let stackView = UIStackView()
        stackView.axis = .vertical
        stackView.alignment = .leading
        stackView.spacing = 3

        let nameLabel = UILabel()
        nameLabel.text = address.localizedLabel
        nameLabel.font = UIFont.dynamicTypeSubheadline
        nameLabel.textColor = Theme.secondaryTextAndIconColor
        nameLabel.lineBreakMode = .byTruncatingTail
        stackView.addArrangedSubview(nameLabel)

        if let postalAddress = address.cnLabeledValue()?.value {
            let formatter = CNPostalAddressFormatter()
            formatter.style = .mailingAddress
            let formattedAddress = formatter.string(from: postalAddress)

            let valueLabel = UILabel()
            valueLabel.text = formattedAddress
            valueLabel.font = UIFont.dynamicTypeBody
            valueLabel.textColor = Theme.primaryTextColor
            valueLabel.lineBreakMode = .byWordWrapping
            valueLabel.numberOfLines = 0
            stackView.addArrangedSubview(valueLabel)
        }

        return stackView
    }
}
