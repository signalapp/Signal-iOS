//  Originally based on EPContacts
//
//  Created by Prabaharan Elangovan on 13/10/15.
//  Copyright © 2015 Prabaharan Elangovan. All rights reserved.
//
//  Modified for Signal by Michael Kirk on 11/25/2016
//  Parts Copyright © 2016 Open Whisper Systems. All rights reserved.

import UIKit

/**
 * Used in the invite flow contact picker.
 */
@available(iOS 9.0, *)
class ContactCell: UITableViewCell {

    static let nib = UINib(nibName:"ContactCell", bundle: nil)
    
    @IBOutlet weak var contactTextLabel: UILabel!
    @IBOutlet weak var contactDetailTextLabel: UILabel!
    @IBOutlet weak var contactImageView: UIImageView!
    @IBOutlet weak var contactContainerView: UIView!
    
    var contact: ContactAdapter?
    
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
        let contactAdapter = ContactAdapter(contact: contact)
        self.contact = contactAdapter

        if contactTextLabel != nil {
            contactTextLabel.attributedText = contactAdapter.formattedFullName(font: contactTextLabel.font)
        }
        
        updateSubtitleBasedonType(subtitleType, contact: contact)

        if contact.image == nil {
            let contactIdForDeterminingBackgroundColor: String
            if let signalId = contact.parsedPhoneNumbers.first?.toE164() {
                contactIdForDeterminingBackgroundColor = signalId
            } else {
                contactIdForDeterminingBackgroundColor = contact.fullName
            }

            let avatarBuilder = OWSContactAvatarBuilder(contactId:contactIdForDeterminingBackgroundColor,
                                                        name:contact.fullName,
                                                        contactsManager:contactsManager)
            self.contactImageView?.image = avatarBuilder.buildDefaultImage();
        } else {
            self.contactImageView?.image = contact.image
        }
    }
    
    func updateSubtitleBasedonType(_ subtitleType: SubtitleCellValue , contact: Contact) {
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

