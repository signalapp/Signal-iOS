//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

import Foundation

public class ContactFieldView: UIView {

    @available(*, unavailable, message: "use other constructor instead.")
    public required init?(coder aDecoder: NSCoder) {
        notImplemented()
    }

    public required init(rows: [UIView], hMargin: CGFloat) {
        super.init(frame: CGRect.zero)

        self.layoutMargins = .zero
        self.preservesSuperviewLayoutMargins = false

        addRows(rows: rows, hMargin: hMargin)
    }

    private func addRows(rows: [UIView], hMargin: CGFloat) {

        var lastRow: UIView?

        let addSpacerRow = {
            guard let prevRow = lastRow else {
                owsFailDebug("missing last row")
                return
            }
            let row = UIView()
            row.backgroundColor = Theme.hairlineColor
            self.addSubview(row)
            row.autoSetDimension(.height, toSize: CGHairlineWidth())
            row.autoPinLeadingToSuperviewMargin(withInset: hMargin)
            row.autoPinTrailingToSuperviewMargin()
            row.autoPinEdge(.top, to: .bottom, of: prevRow, withOffset: 0)
            lastRow = row
        }

        let addRow: ((UIView) -> Void) = { (row) in
            if lastRow != nil {
                addSpacerRow()
            }
            self.addSubview(row)
            row.autoPinLeadingToSuperviewMargin()
            row.autoPinTrailingToSuperviewMargin()
            if let lastRow = lastRow {
                row.autoPinEdge(.top, to: .bottom, of: lastRow, withOffset: 0)
            } else {
                row.autoPinEdge(toSuperviewEdge: .top, withInset: 0)
            }
            lastRow = row
        }

        for row in rows {
            addRow(row)
        }

        lastRow?.autoPinEdge(toSuperviewEdge: .bottom, withInset: 0)
    }

    public class func contactFieldView(forAvatarImage avatarImage: UIImage, layoutMargins: UIEdgeInsets, actionBlock : (() -> Void)?) -> UIView {
        var stackView: UIStackView
        if let actionBlock = actionBlock {
            stackView = TappableStackView(actionBlock: actionBlock)
        } else {
            stackView = UIStackView()
        }
        stackView.axis = .vertical
        stackView.alignment = .leading
        stackView.spacing = 3
        stackView.layoutMargins = layoutMargins
        stackView.isLayoutMarginsRelativeArrangement = true

        let avatarView = AvatarImageView()
        avatarView.image = avatarImage
        let avatarSize = CGFloat(50)
        avatarView.autoSetDimension(.width, toSize: avatarSize)
        avatarView.autoSetDimension(.height, toSize: avatarSize)
        avatarView.setCompressionResistanceHigh()
        avatarView.setContentHuggingHigh()
        stackView.addArrangedSubview(avatarView)

        return stackView
    }

    public class func contactFieldView(forOrganizationName organizationName: String, layoutMargins: UIEdgeInsets) -> UIView {
        return simpleFieldView(name: NSLocalizedString("CONTACT_FIELD_ORGANIZATION",
                                                       comment: "Label for the 'organization' field of a contact."),
                               value: organizationName,
                               layoutMargins: layoutMargins, actionBlock: nil)
    }

    public class func contactFieldView(forPhoneNumber phoneNumber: OWSContactPhoneNumber, layoutMargins: UIEdgeInsets, actionBlock : (() -> Void)?) -> UIView {
        let formattedPhoneNumber = PhoneNumber.bestEffortLocalizedPhoneNumber(withE164: phoneNumber.phoneNumber)
        return simpleFieldView(name: phoneNumber.localizedLabel(), value: formattedPhoneNumber, layoutMargins: layoutMargins, actionBlock: actionBlock)
    }

    public class func contactFieldView(forEmail email: OWSContactEmail, layoutMargins: UIEdgeInsets, actionBlock : (() -> Void)?) -> UIView {
        return simpleFieldView(name: email.localizedLabel(), value: email.email, layoutMargins: layoutMargins, actionBlock: actionBlock)
    }

    private class func simpleFieldView(name: String, value: String?, layoutMargins: UIEdgeInsets, actionBlock : (() -> Void)?) -> UIView {
        var stackView: UIStackView
        if let actionBlock = actionBlock {
            stackView = TappableStackView(actionBlock: actionBlock)
        } else {
            stackView = UIStackView()
        }
        stackView.axis = .vertical
        stackView.alignment = .leading
        stackView.spacing = 3
        stackView.layoutMargins = layoutMargins
        stackView.isLayoutMarginsRelativeArrangement = true

        let nameLabel = UILabel()
        nameLabel.text = name.lowercased()
        nameLabel.font = UIFont.ows_dynamicTypeSubheadline
        nameLabel.textColor = Theme.secondaryColor
        nameLabel.lineBreakMode = .byTruncatingTail
        stackView.addArrangedSubview(nameLabel)

        let valueLabel = UILabel()
        valueLabel.text = value
        valueLabel.font = UIFont.ows_dynamicTypeBody
        valueLabel.textColor = Theme.primaryColor
        valueLabel.lineBreakMode = .byTruncatingTail
        stackView.addArrangedSubview(valueLabel)

        return stackView
    }

    public class func contactFieldView(forAddress address: OWSContactAddress, layoutMargins: UIEdgeInsets, actionBlock : (() -> Void)?) -> UIView {
        var stackView: UIStackView
        if let actionBlock = actionBlock {
             stackView = TappableStackView(actionBlock: actionBlock)
        } else {
            stackView = UIStackView()
        }
        stackView.axis = .vertical
        stackView.alignment = .leading
        stackView.spacing = 3
        stackView.layoutMargins = layoutMargins
        stackView.isLayoutMarginsRelativeArrangement = true

        let nameLabel = UILabel()
        nameLabel.text = address.localizedLabel()
        nameLabel.font = UIFont.ows_dynamicTypeSubheadline
        nameLabel.textColor = Theme.secondaryColor
        nameLabel.lineBreakMode = .byTruncatingTail
        stackView.addArrangedSubview(nameLabel)

        let tryToAddNameValue: ((String, String?) -> Void) = { (propertyName, propertyValue) in
            guard let propertyValue = propertyValue else {
                return
            }
            guard propertyValue.count > 0 else {
                return
            }

            let row = UIStackView()
            row.axis = .horizontal
            row.alignment = .leading
            row.spacing = 10
            row.layoutMargins = .zero

            let nameLabel = UILabel()
            nameLabel.text = propertyName
            nameLabel.font = UIFont.ows_dynamicTypeBody
            nameLabel.textColor = Theme.secondaryColor
            nameLabel.lineBreakMode = .byTruncatingTail
            row.addArrangedSubview(nameLabel)
            nameLabel.setContentHuggingHigh()
            nameLabel.setCompressionResistanceHigh()

            let valueLabel = UILabel()
            valueLabel.text = propertyValue
            valueLabel.font = UIFont.ows_dynamicTypeBody
            valueLabel.textColor = Theme.primaryColor
            valueLabel.lineBreakMode = .byTruncatingTail
            row.addArrangedSubview(valueLabel)

            stackView.addArrangedSubview(row)
        }

        tryToAddNameValue(NSLocalizedString("CONTACT_FIELD_ADDRESS_STREET", comment: "Label for the 'street' field of a contact's address."),
                          address.street)
        tryToAddNameValue(NSLocalizedString("CONTACT_FIELD_ADDRESS_POBOX", comment: "Label for the 'pobox' field of a contact's address."),
                          address.pobox)
        tryToAddNameValue(NSLocalizedString("CONTACT_FIELD_ADDRESS_NEIGHBORHOOD", comment: "Label for the 'neighborhood' field of a contact's address."),
                          address.neighborhood)
        tryToAddNameValue(NSLocalizedString("CONTACT_FIELD_ADDRESS_CITY", comment: "Label for the 'city' field of a contact's address."),
                          address.city)
        tryToAddNameValue(NSLocalizedString("CONTACT_FIELD_ADDRESS_REGION", comment: "Label for the 'region' field of a contact's address."),
                          address.region)
        tryToAddNameValue(NSLocalizedString("CONTACT_FIELD_ADDRESS_POSTCODE", comment: "Label for the 'postcode' field of a contact's address."),
                          address.postcode)
        tryToAddNameValue(NSLocalizedString("CONTACT_FIELD_ADDRESS_COUNTRY", comment: "Label for the 'country' field of a contact's address."),
                          address.country)

        return stackView
    }
}
