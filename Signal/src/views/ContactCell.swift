//
//  Copyright (c) 2017 Open Whisper Systems. All rights reserved.
//

import UIKit
import Contacts

@available(iOS 9.0, *)
class ContactCell: UITableViewCell {

    static let nib = UINib(nibName:"ContactCell", bundle: nil)

    @IBOutlet weak var contactTextLabel: UILabel!
    @IBOutlet weak var contactDetailTextLabel: UILabel!
    @IBOutlet weak var contactImageView: UIImageView!
    @IBOutlet weak var contactContainerView: UIView!

    var contact: Contact?

    override func awakeFromNib() {
        super.awakeFromNib()

        // Initialization code
        selectionStyle = UITableViewCellSelectionStyle.none

        contactContainerView.layer.masksToBounds = true
        contactContainerView.layer.cornerRadius = contactContainerView.frame.size.width/2

        NotificationCenter.default.addObserver(self, selector: #selector(self.didChangePreferredContentSize), name: NSNotification.Name.UIContentSizeCategoryDidChange, object: nil)
    }

    override func prepareForReuse() {
        accessoryType = .none
    }

    override func setSelected(_ selected: Bool, animated: Bool) {
        super.setSelected(selected, animated: animated)
        accessoryType = selected ? .checkmark : .none
    }

    func didChangePreferredContentSize() {
        contactTextLabel.font = UIFont.preferredFont(forTextStyle: .body)
        contactDetailTextLabel.font = UIFont.preferredFont(forTextStyle: .subheadline)
    }

    func updateContactsinUI(_ contact: Contact, subtitleType: SubtitleCellValue, contactsManager: OWSContactsManager) {
        self.contact = contact

        if contactTextLabel != nil {
            contactTextLabel.attributedText = contact.cnContact?.formattedFullName(font:contactTextLabel.font)
        }

        updateSubtitleBasedonType(subtitleType, contact: contact)

        if contact.image == nil {
            let contactIdForDeterminingBackgroundColor: String
            if let signalId = contact.parsedPhoneNumbers.first?.toE164() {
                contactIdForDeterminingBackgroundColor = signalId
            } else {
                contactIdForDeterminingBackgroundColor = contact.fullName
            }

            let kAvatarWidth: UInt = 40
            let avatarBuilder = OWSContactAvatarBuilder(contactId:contactIdForDeterminingBackgroundColor,
                                                        name:contact.fullName,
                                                        contactsManager:contactsManager,
                                                        diameter: kAvatarWidth)
            self.contactImageView?.image = avatarBuilder.buildDefaultImage()
        } else {
            self.contactImageView?.image = contact.image
        }
    }

    func updateSubtitleBasedonType(_ subtitleType: SubtitleCellValue, contact: Contact) {
        switch subtitleType {

        case SubtitleCellValue.phoneNumber:
            if contact.userTextPhoneNumbers.count > 0 {
                self.contactDetailTextLabel.text = "\(contact.userTextPhoneNumbers[0])"
            } else {
                self.contactDetailTextLabel.text = NSLocalizedString("CONTACT_PICKER_NO_PHONE_NUMBERS_AVAILABLE", comment: "table cell subtitle when contact card has no known phone number")
            }
        case SubtitleCellValue.email:
            if contact.emails.count > 0 {
                self.contactDetailTextLabel.text = "\(contact.emails[0])"
            } else {
                self.contactDetailTextLabel.text = NSLocalizedString("CONTACT_PICKER_NO_EMAILS_AVAILABLE", comment: "table cell subtitle when contact card has no email")
            }
        }
    }
}

@available(iOS 9.0, *)
fileprivate extension CNContact {
    /**
     * Bold the sorting portion of the name. e.g. if we sort by family name, bold the family name.
     */
    func formattedFullName(font: UIFont) -> NSAttributedString? {
        let keyToHighlight = ContactSortOrder == .familyName ? CNContactFamilyNameKey : CNContactGivenNameKey

        let boldDescriptor = font.fontDescriptor.withSymbolicTraits(.traitBold)
        let boldAttributes = [
            NSFontAttributeName: UIFont(descriptor:boldDescriptor!, size: 0)
        ]

        if let attributedName = CNContactFormatter.attributedString(from: self, style: .fullName, defaultAttributes: nil) {
            let highlightedName = attributedName.mutableCopy() as! NSMutableAttributedString
            highlightedName.enumerateAttributes(in: NSMakeRange(0, highlightedName.length), options: [], using: { (attrs, range, _) in
                if let property = attrs[CNContactPropertyAttribute] as? String, property == keyToHighlight {
                    highlightedName.addAttributes(boldAttributes, range: range)
                }
            })
            return highlightedName
        }

        if let emailAddress = (self.emailAddresses.first?.value as String?) {
            return NSAttributedString(string: emailAddress, attributes: boldAttributes)
        }

        return nil
    }
}
