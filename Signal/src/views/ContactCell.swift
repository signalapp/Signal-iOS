//
//  Copyright (c) 2020 Open Whisper Systems. All rights reserved.
//

import UIKit
import Contacts
import SignalServiceKit

class ContactCell: UITableViewCell {

    public static let kSeparatorHInset: CGFloat = CGFloat(kAvatarDiameter) + 16 + 8

    static let kAvatarSpacing: CGFloat = 6
    static let kAvatarDiameter: UInt = 40

    let contactImageView: AvatarImageView
    let textStackView: UIStackView
    let titleLabel: UILabel
    var subtitleLabel: UILabel

    var contact: Contact?
    var showsWhenSelected: Bool = false

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        self.contactImageView = AvatarImageView()
        self.textStackView = UIStackView()
        self.titleLabel = UILabel()
        self.titleLabel.font = UIFont.ows_dynamicTypeBody
        self.subtitleLabel = UILabel()
        self.subtitleLabel.font = UIFont.ows_dynamicTypeSubheadline

        super.init(style: style, reuseIdentifier: reuseIdentifier)

        selectionStyle = UITableViewCell.SelectionStyle.none

        textStackView.axis = .vertical
        textStackView.addArrangedSubview(titleLabel)

        contactImageView.autoSetDimensions(to: CGSize(square: CGFloat(ContactCell.kAvatarDiameter)))

        let contentColumns: UIStackView = UIStackView(arrangedSubviews: [contactImageView, textStackView])
        contentColumns.axis = .horizontal
        contentColumns.spacing = ContactCell.kAvatarSpacing
        contentColumns.alignment = .center

        self.contentView.addSubview(contentColumns)
        contentColumns.autoPinEdgesToSuperviewMargins()

        NotificationCenter.default.addObserver(self, selector: #selector(self.didChangePreferredContentSize), name: UIContentSizeCategory.didChangeNotification, object: nil)
    }

    required init?(coder aDecoder: NSCoder) {
        notImplemented()
    }

    override func prepareForReuse() {
        accessoryType = .none
        self.subtitleLabel.removeFromSuperview()
    }

    override func setSelected(_ selected: Bool, animated: Bool) {
        super.setSelected(selected, animated: animated)
        if showsWhenSelected {
            accessoryType = selected ? .checkmark : .none
        }
    }

    @objc func didChangePreferredContentSize() {
        self.titleLabel.font = UIFont.ows_dynamicTypeBody
        self.subtitleLabel.font = UIFont.ows_dynamicTypeSubheadline
    }

    func configure(contact: Contact, subtitleType: SubtitleCellValue, showsWhenSelected: Bool) {

        self.contact = contact
        self.showsWhenSelected = showsWhenSelected

        if let cnContactId = contact.cnContactId,
            let cnContact = contactsManager.cnContact(withId: cnContactId) {
            titleLabel.attributedText = cnContact.formattedFullName(font: titleLabel.font)
        } else {
            titleLabel.text = contact.fullName
        }

        updateSubtitle(subtitleType: subtitleType, contact: contact)

        if let contactImage = contactsManager.avatarImage(forCNContactId: contact.cnContactId) {
            contactImageView.image = contactImage
        } else {
            let contactIdForDeterminingBackgroundColor: String
            if let signalId = contact.parsedPhoneNumbers.first?.toE164() {
                contactIdForDeterminingBackgroundColor = signalId
            } else {
                contactIdForDeterminingBackgroundColor = contact.fullName
            }

            var nameComponents = PersonNameComponents()
            nameComponents.givenName = contact.firstName
            nameComponents.familyName = contact.lastName

            let avatarBuilder = OWSContactAvatarBuilder(nonSignalNameComponents: nameComponents,
                                                        colorSeed: contactIdForDeterminingBackgroundColor,
                                                        diameter: ContactCell.kAvatarDiameter)

            contactImageView.image = avatarBuilder.build()
        }
    }

    func updateSubtitle(subtitleType: SubtitleCellValue, contact: Contact) {
        switch subtitleType {
        case .none:
            assert(self.subtitleLabel.superview == nil)
            break
        case .phoneNumber:
            self.textStackView.addArrangedSubview(self.subtitleLabel)

            if let firstPhoneNumber = contact.userTextPhoneNumbers.first {
                self.subtitleLabel.text = firstPhoneNumber
            } else {
                self.subtitleLabel.text = NSLocalizedString("CONTACT_PICKER_NO_PHONE_NUMBERS_AVAILABLE", comment: "table cell subtitle when contact card has no known phone number")
            }
        case .email:
            self.textStackView.addArrangedSubview(self.subtitleLabel)

            if let firstEmail = contact.emails.first {
                self.subtitleLabel.text = firstEmail
            } else {
                self.subtitleLabel.text = NSLocalizedString("CONTACT_PICKER_NO_EMAILS_AVAILABLE", comment: "table cell subtitle when contact card has no email")
            }
        }
    }

    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
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
    func formattedFullName(font: UIFont) -> NSAttributedString? {
        let keyToHighlight = ContactSortOrder == .familyName ? CNContactFamilyNameKey : CNContactGivenNameKey

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
