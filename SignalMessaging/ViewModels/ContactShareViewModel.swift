//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

import Foundation

@objc
public class ContactShareViewModel: NSObject {

    public let dbRecord: OWSContact

    public var avatarImageData: Data? {
        didSet {
            self.cachedAvatarImage = nil
        }
    }

    var cachedAvatarImage: UIImage?
    var avatarImage: UIImage? {
        if self.cachedAvatarImage != nil {
            return self.cachedAvatarImage
        }

        guard let avatarImageData = self.avatarImageData else {
            return nil
        }

        self.cachedAvatarImage = UIImage(data: avatarImageData)
        return cachedAvatarImage
    }

    public required init(contactShareRecord: OWSContact, avatarImageData: Data?) {
        self.dbRecord = contactShareRecord
        self.avatarImageData = avatarImageData
    }

    public convenience init(contactShareRecord: OWSContact, transaction: YapDatabaseReadTransaction) {
        if let avatarAttachment = contactShareRecord.avatarAttachment(with: transaction) as? TSAttachmentStream {
            self.init(contactShareRecord: contactShareRecord, avatarImageData: avatarAttachment.validStillImageData())
        } else {
            self.init(contactShareRecord: contactShareRecord, avatarImageData: nil)
        }
    }

    public func getAvatarImage(diameter: CGFloat, contactsManager: OWSContactsManager, ignoreContactAndProfile: Bool = false) -> UIImage {
        if let avatarImage = avatarImage {
            return avatarImage
        }

        var colorSeed = name.displayName
        let recipientIds = systemContactsWithSignalAccountPhoneNumbers(contactsManager)
        if let firstRecipientId = recipientIds.first {
            // Try to use the first signal id as the default
            // avatar's color seed, so that it is as consistent
            // as possible with the user's avatar in other views.
            colorSeed = firstRecipientId
        }

        let avatarBuilder = OWSContactAvatarBuilder(nonSignalName: displayName,
                                                    colorSeed: colorSeed,
                                                    diameter: UInt(diameter),
                                                    ignoreContactAndProfile: ignoreContactAndProfile,
                                                    contactsManager: contactsManager)
        return avatarBuilder.build()
    }

    // MARK: Delegated -> dbRecord

    public var name: OWSContactName {
        get {
            return dbRecord.name
        }
        set {
            return dbRecord.name = newValue
        }
    }

    public var addresses: [OWSContactAddress] {
        get {
            return dbRecord.addresses
        }
        set {
            return dbRecord.addresses = newValue
        }
    }

    public var emails: [OWSContactEmail] {
        get {
            return dbRecord.emails
        }
        set {
            dbRecord.emails = newValue
        }
    }

    public var phoneNumbers: [OWSContactPhoneNumber] {
        get {
            return dbRecord.phoneNumbers
        }
        set {
            dbRecord.phoneNumbers = newValue
        }
    }

    public func systemContactsWithSignalAccountPhoneNumbers(_ contactsManager: ContactsManagerProtocol) -> [String] {
        return dbRecord.systemContactsWithSignalAccountPhoneNumbers(contactsManager)
    }

    public func systemContactPhoneNumbers(_ contactsManager: ContactsManagerProtocol) -> [String] {
        return dbRecord.systemContactPhoneNumbers(contactsManager)
    }

    public func e164PhoneNumbers() -> [String] {
        return dbRecord.e164PhoneNumbers()
    }

    public var displayName: String {
        return dbRecord.name.displayName
    }

    public var ows_isValid: Bool {
        return dbRecord.ows_isValid()
    }

    public var isProfileAvatar: Bool {
        return dbRecord.isProfileAvatar
    }

    public func cnContact(mergedWithExistingContact existingContact: Contact) -> CNContact? {

        guard let newCNContact = OWSContacts.systemContact(for: self.dbRecord, imageData: self.avatarImageData) else {
            owsFail("\(logTag) in \(#function) newCNContact was unexpectedly nil")
            return nil
        }

        return existingContact.buildCNContact(mergedWithNewContact: newCNContact)
    }

    public func copy(withName name: OWSContactName) -> ContactShareViewModel {

        // TODO move the `copy` logic into the view model?
        let newDbRecord = dbRecord.copy(with: name)

        return ContactShareViewModel(contactShareRecord: newDbRecord, avatarImageData: self.avatarImageData)
    }

    public func newContact(withName name: OWSContactName) -> ContactShareViewModel {

        // TODO move the `newContact` logic into the view model?
        let newDbRecord = dbRecord.newContact(with: name)

        // If we want to keep the avatar image, the caller will need to re-apply it.
        return ContactShareViewModel(contactShareRecord: newDbRecord, avatarImageData: nil)
    }

}
