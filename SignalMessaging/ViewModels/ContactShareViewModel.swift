//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

import Foundation

@objc
public class ContactShareViewModel: NSObject {

    @objc
    public let dbRecord: OWSContact

    @objc
    public var avatarImageData: Data? {
        didSet {
            self.cachedAvatarImage = nil
        }
    }

    private var cachedAvatarImage: UIImage?

    @objc
    public var avatarImage: UIImage? {
        if self.cachedAvatarImage != nil {
            return self.cachedAvatarImage
        }

        guard let avatarImageData = self.avatarImageData else {
            return nil
        }

        self.cachedAvatarImage = UIImage(data: avatarImageData)
        return cachedAvatarImage
    }

    @objc
    public required init(contactShareRecord: OWSContact, avatarImageData: Data?) {
        self.dbRecord = contactShareRecord
        self.avatarImageData = avatarImageData
    }

    @objc
    public convenience init(contactShareRecord: OWSContact, transaction: YapDatabaseReadTransaction) {
        if let avatarAttachment = contactShareRecord.avatarAttachment(with: transaction) as? TSAttachmentStream {
            self.init(contactShareRecord: contactShareRecord, avatarImageData: avatarAttachment.validStillImageData())
        } else {
            self.init(contactShareRecord: contactShareRecord, avatarImageData: nil)
        }
    }

    @objc
    public func getAvatarImage(diameter: CGFloat, contactsManager: OWSContactsManager) -> UIImage? {
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
                                                    diameter: UInt(diameter))
        // Note: we use buildDefaultImage() and not build() so that contact
        // share views always reflect the contents of the contact share.
        // build() might return an avatar from a corresponding system
        // contact or profile.  This could mislead the user into thinking
        // that an avatar they did not share was in fact included in the
        // contact share.
        return avatarBuilder.buildDefaultImage()
    }

    // MARK: Delegated -> dbRecord

    @objc
    public var name: OWSContactName {
        get {
            return dbRecord.name
        }
        set {
            return dbRecord.name = newValue
        }
    }

    @objc
    public var addresses: [OWSContactAddress] {
        get {
            return dbRecord.addresses
        }
        set {
            return dbRecord.addresses = newValue
        }
    }

    @objc
    public var emails: [OWSContactEmail] {
        get {
            return dbRecord.emails
        }
        set {
            dbRecord.emails = newValue
        }
    }

    @objc
    public var phoneNumbers: [OWSContactPhoneNumber] {
        get {
            return dbRecord.phoneNumbers
        }
        set {
            dbRecord.phoneNumbers = newValue
        }
    }

    @objc
    public func systemContactsWithSignalAccountPhoneNumbers(_ contactsManager: ContactsManagerProtocol) -> [String] {
        return dbRecord.systemContactsWithSignalAccountPhoneNumbers(contactsManager)
    }

    @objc
    public func systemContactPhoneNumbers(_ contactsManager: ContactsManagerProtocol) -> [String] {
        return dbRecord.systemContactPhoneNumbers(contactsManager)
    }

    @objc
    public func e164PhoneNumbers() -> [String] {
        return dbRecord.e164PhoneNumbers()
    }

    @objc
    public var displayName: String {
        return dbRecord.name.displayName
    }

    @objc
    public var ows_isValid: Bool {
        return dbRecord.ows_isValid()
    }

    @objc
    public var isProfileAvatar: Bool {
        return dbRecord.isProfileAvatar
    }

    @objc
    public func copy(withName name: OWSContactName) -> ContactShareViewModel {

        // TODO move the `copy` logic into the view model?
        let newDbRecord = dbRecord.copy(with: name)

        return ContactShareViewModel(contactShareRecord: newDbRecord, avatarImageData: self.avatarImageData)
    }

    @objc
    public func newContact(withName name: OWSContactName) -> ContactShareViewModel {

        // TODO move the `newContact` logic into the view model?
        let newDbRecord = dbRecord.newContact(with: name)

        // If we want to keep the avatar image, the caller will need to re-apply it.
        return ContactShareViewModel(contactShareRecord: newDbRecord, avatarImageData: nil)
    }
}
