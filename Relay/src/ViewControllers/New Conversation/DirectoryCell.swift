//
//  DirectoryCell.swift
//  Relay
//
//  Created by Mark Descalzo on 9/11/18.
//  Copyright © 2018 Open Whisper Systems. All rights reserved.
//
import UIImageView_Extension

@objc class DirectoryCell: UITableViewCell {
    @IBOutlet weak var nameLabel: UILabel!
    @IBOutlet weak var detailLabel: UILabel!
    @IBOutlet weak var avatarImageView: UIImageView!
    
    override func awakeFromNib() {
        super.awakeFromNib()

        avatarImageView.circle = true
        
        nameLabel.text = NSLocalizedString("LOADING", comment: "")
        detailLabel.text = NSLocalizedString("LOADING", comment: "")
    }
    
    
    @objc public func configureCell(recipient: RelayRecipient?) {
        
        guard recipient != nil else {
            Logger.debug("Configuring cell for nil recipient!")
            return
        }
        
        DispatchQueue.main.async(execute: {
            
            self.nameLabel.attributedText = self.attributedString(recipient: recipient)
            self.detailLabel.text = recipient?.orgSlug
            
            let avatar: UIImage? = FLContactsManager.shared.avatarImageRecipientId((recipient?.uniqueId)!)
            
            if avatar != nil {
                self.avatarImageView.image = avatar
            } else {
                let avatarBuilder = OWSContactAvatarBuilder(nonSignalName: (recipient?.fullName())!,
                                                            colorSeed: (recipient?.uniqueId)!,
                                                            diameter: UInt(self.avatarImageView.frame.size.height),
                                                            contactsManager: FLContactsManager.shared)
                
//                let avatarBuilder = OWSContactAvatarBuilder(contactId: recipient?.uniqueId, name: recipient?.fullName, contactsManager: Environment.getCurrent().contactsManager, diameter: self.avatarImageView.frame.size.height)
                self.avatarImageView.image = avatarBuilder.buildDefaultImage()
            }
        })
    }
    
    @objc public func configureCell(aTag: FLTag?) {
        var description: String? = nil
        if (aTag?.uniqueId == TSAccountManager.sharedInstance().selfRecipient().flTag?.uniqueId) {
            description = NSLocalizedString("ME_STRING", comment: "")
        } else {
            description = aTag?.tagDescription
        }
        let orgSlug = aTag?.orgSlug
        
        
        // Get an avatar
        DispatchQueue.main.async(execute: {
            var avatar: UIImage? = nil
//            if aTag?.recipientIds?.count == 1 {
//                let recipient: RelayRecipient? = FLContactsManager.shared.recipient(withId: aTag?.recipientIds.first)
//                avatar = FLContactsManager.shared.image(forRecipientId: (recipient?.uniqueId)!)
//                if avatar == nil {
//                    let avatarBuilder = OWSContactAvatarBuilder(nonSignalName: (recipient?.fullName())!,
//                                                                colorSeed: (recipient?.uniqueId)!,
//                                                                diameter: self.avatarImageView.frame.size.height,
//                                                                contactsManager: FLContactsManager.shared)
//
//                    let avatarBuilder = OWSContactAvatarBuilder(contactId: recipient?.uniqueId, name: recipient?.fullName, contactsManager: FLContactsManager.shared, diameter: self.contentView.frame.size.height)
//                    avatar = avatarBuilder.buildDefaultImage()
//                    recipient?.avatar = avatar
//                    FLContactsManager.shared.save(recipient)
//                }
//            } else {
            let avatarBuilder = OWSContactAvatarBuilder(nonSignalName: (aTag?.tagDescription)!,
                                                        colorSeed: (aTag?.uniqueId)!,
                                                        diameter: UInt(self.avatarImageView.frame.size.height),
                                                        contactsManager: FLContactsManager.shared)

                avatar = avatarBuilder.buildDefaultImage()
//            }
            self.nameLabel.text = description
            self.detailLabel.text = orgSlug
            self.avatarImageView.image = avatar
        })
    }
    
    func attributedString(recipient: RelayRecipient?) -> NSAttributedString? {
        
        guard recipient != nil else {
            return NSAttributedString.init(string: "Nil Recipient")
        }
        
        let fontSize: CGFloat = 17.0
        let firstNameFont = UIFont.ows_regularFont(withSize: fontSize)
        let lastNameFont = UIFont.ows_regularFont(withSize: fontSize)
        
        var fullNameAttributedString: NSMutableAttributedString? = nil
        //    NSString *displayString = nil;
        
        // If self...
        if (recipient?.uniqueId == TSAccountManager.sharedInstance().selfRecipient().uniqueId) {
            fullNameAttributedString = NSMutableAttributedString(string: NSLocalizedString("ME_STRING", comment: ""))
            
            fullNameAttributedString?.addAttribute(.font, value: lastNameFont, range: NSRange(location: 0, length: fullNameAttributedString?.length ?? 0))
            fullNameAttributedString?.addAttribute(.foregroundColor, value: UIColor.black, range: NSRange(location: 0, length: fullNameAttributedString?.length ?? 0))
            // Everyone else
        } else {
            fullNameAttributedString = NSMutableAttributedString(string: (recipient?.fullName())!)
            
            fullNameAttributedString?.addAttribute(.font, value: firstNameFont, range: NSRange(location: 0, length: recipient?.firstName?.count ?? 0))
            fullNameAttributedString?.addAttribute(.font, value: lastNameFont, range: NSRange(location: recipient?.firstName?.count ?? 0 + 1, length: recipient?.lastName?.count ?? 0))
            fullNameAttributedString?.addAttribute(.foregroundColor, value: UIColor.black, range: NSRange(location: 0, length: recipient?.fullName().count ?? 0))
            fullNameAttributedString?.addAttribute(.foregroundColor, value: UIColor.black, range: NSRange(location: 0, length: recipient?.firstName?.count ?? 0))
        }
        return fullNameAttributedString
    }
}
