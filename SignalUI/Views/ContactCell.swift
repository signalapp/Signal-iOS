//
// Copyright 2016 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import UIKit
import Contacts
import SignalServiceKit

public class ContactCell: UITableViewCell, ReusableTableViewCell {

    public static let reuseIdentifier = "ContactCell"

    static private let avatarDiameter: CGFloat = 36

    private let contactImageView = AvatarImageView()
    private lazy var textStackView: UIStackView = {
        let stackView = UIStackView(arrangedSubviews: [titleLabel])
        stackView.axis = .vertical
        return stackView
     }()
    private let titleLabel: UILabel = {
        let label = UILabel()
        label.font = .dynamicTypeBody
        label.adjustsFontForContentSizeCategory = true
        return label
    }()
    private let subtitleLabel: UILabel = {
        let label = UILabel()
        label.font = .dynamicTypeSubheadline
        label.adjustsFontForContentSizeCategory = true
        return label
    }()

    private var showsWhenSelected: Bool = false

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)

        selectionStyle = UITableViewCell.SelectionStyle.none

        contactImageView.autoSetDimensions(to: CGSize(square: CGFloat(ContactCell.avatarDiameter)))

        let contentColumns: UIStackView = UIStackView(arrangedSubviews: [contactImageView, textStackView])
        contentColumns.axis = .horizontal
        contentColumns.spacing = 12
        contentColumns.alignment = .center
        contentView.addSubview(contentColumns)
        contentColumns.autoPinWidthToSuperviewMargins()
        contentColumns.autoPinHeightToSuperview(withMargin: 7)
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    public override func prepareForReuse() {
        accessoryType = .none
        subtitleLabel.removeFromSuperview()
    }

    public override func setSelected(_ selected: Bool, animated: Bool) {
        super.setSelected(selected, animated: animated)
        if showsWhenSelected {
            accessoryType = selected ? .checkmark : .none
        }
    }

    public func configure(contact: Contact, sortOrder: CNContactSortOrder, subtitleType: SubtitleCellValue, showsWhenSelected: Bool) {
        self.showsWhenSelected = showsWhenSelected

        let cnContact: CNContact?
        if let cnContactId = contact.cnContactId {
            cnContact = contactsManager.cnContact(withId: cnContactId)
        } else {
            cnContact = nil
        }

        if let cnContact {
            titleLabel.attributedText = cnContact.formattedFullName(sortOrder: sortOrder, font: titleLabel.font)
        } else {
            titleLabel.text = contact.fullName
        }

        updateSubtitle(subtitleType: subtitleType, contact: contact)

        var contactImage: UIImage?
        if let cnContact {
            if let avatarImage = contactsManager.avatarImage(forCNContactId: cnContact.identifier) {
                contactImage = avatarImage
            } else if cnContact.imageDataAvailable, let contactImageData = cnContact.imageData {
                contactImage = UIImage(data: contactImageData)
            }
        }
        if contactImage == nil {
            var nameComponents = PersonNameComponents()
            nameComponents.givenName = contact.firstName
            nameComponents.familyName = contact.lastName

            let avatar = databaseStorage.read { transaction in
                Self.avatarBuilder.avatarImage(personNameComponents: nameComponents,
                                               diameterPoints: UInt(ContactCell.avatarDiameter),
                                               transaction: transaction)
            }
            contactImage = avatar
        }
        contactImageView.image = contactImage
    }

    func updateSubtitle(subtitleType: SubtitleCellValue, contact: Contact) {
        switch subtitleType {
        case .none:
            owsAssertBeta(subtitleLabel.superview == nil)
        case .phoneNumber:
            textStackView.addArrangedSubview(subtitleLabel)

            if let firstPhoneNumber = contact.userTextPhoneNumbers.first {
                subtitleLabel.text = firstPhoneNumber
            } else {
                subtitleLabel.text = OWSLocalizedString("CONTACT_PICKER_NO_PHONE_NUMBERS_AVAILABLE", comment: "table cell subtitle when contact card has no known phone number")
            }
        case .email:
            textStackView.addArrangedSubview(subtitleLabel)

            if let firstEmail = contact.emails.first {
                subtitleLabel.text = firstEmail
            } else {
                subtitleLabel.text = OWSLocalizedString("CONTACT_PICKER_NO_EMAILS_AVAILABLE", comment: "table cell subtitle when contact card has no email")
            }
        }
    }

    public override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)

        titleLabel.textColor = Theme.primaryTextColor
        subtitleLabel.textColor = Theme.secondaryTextAndIconColor

        OWSTableItem.configureCell(self)
    }
}

fileprivate extension CNContact {
    /**
     * Bold the sorting portion of the name. e.g. if we sort by family name, bold the family name.
     */
    func formattedFullName(sortOrder: CNContactSortOrder, font: UIFont) -> NSAttributedString? {
        let keyToHighlight = sortOrder == .familyName ? CNContactFamilyNameKey : CNContactGivenNameKey

        let boldDescriptor = font.fontDescriptor.withSymbolicTraits(.traitBold)
        let boldAttributes = [
            NSAttributedString.Key.font: UIFont(descriptor: boldDescriptor!, size: 0)
        ]

        if let attributedName = CNContactFormatter.attributedString(from: self, style: .fullName, defaultAttributes: nil) {
            let highlightedName = attributedName.mutableCopy() as! NSMutableAttributedString
            highlightedName.enumerateAttributes(in: highlightedName.entireRange, options: [], using: { (attrs, range, _) in
                if let property = attrs[NSAttributedString.Key(rawValue: CNContactPropertyAttribute)] as? String, property == keyToHighlight {
                    highlightedName.addAttributes(boldAttributes, range: range)
                }
            })
            return highlightedName
        }

        if let emailAddress = self.emailAddresses.first?.value {
            return NSAttributedString(string: emailAddress as String, attributes: boldAttributes)
        }

        if let phoneNumber = self.phoneNumbers.first?.value.stringValue {
            return NSAttributedString(string: phoneNumber, attributes: boldAttributes)
        }

        return nil
    }
}
