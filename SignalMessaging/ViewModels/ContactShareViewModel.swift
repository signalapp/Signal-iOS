//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

import Foundation

@objc
public class ContactShareViewModel: NSObject {

    public let dbRecord: OWSContact
    public let avatarImage: UIImage?

    public required init(contactShareRecord: OWSContact, avatarImage: UIImage?) {
        self.dbRecord = contactShareRecord
        self.avatarImage = avatarImage
    }

    public convenience init(contactShareRecord: OWSContact, transaction: YapDatabaseReadTransaction) {
        if let avatarAttachment = contactShareRecord.avatarAttachment(with: transaction) as? TSAttachmentStream {
            self.init(contactShareRecord: contactShareRecord, avatarImage: avatarAttachment.image())
        } else {
            self.init(contactShareRecord: contactShareRecord, avatarImage: nil)
        }
    }

    public func getAvatarImage(diameter: CGFloat, contactsManager: OWSContactsManager) -> UIImage {
        if let avatarImage = avatarImage {
            return avatarImage
        }

        // TODO: What's the best colorSeed value to use?
        let avatarBuilder = OWSContactAvatarBuilder(nonSignalName: displayName,
                                                    colorSeed: displayName,
                                                    diameter: UInt(diameter),
                                                    contactsManager: contactsManager)
        return avatarBuilder.build()
    }

    // MARK: Delegated -> dbRecord

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
        return dbRecord.displayName
    }

    public var ows_isValid: Bool {
        return dbRecord.ows_isValid()
    }

    public var namePrefix: String? {
        return dbRecord.namePrefix
    }

    public var givenName: String? {
        return dbRecord.givenName
    }

    public var middleName: String? {
        return dbRecord.middleName
    }

    public var familyName: String? {
        return dbRecord.familyName
    }

    public var nameSuffix: String? {
        return dbRecord.nameSuffix
    }

    public var isProfileAvatar: Bool {
        return dbRecord.isProfileAvatar
    }

    public func cnContact(mergedWithExistingContact existingContact: Contact) -> CNContact? {

        guard let mergedCNContact: CNMutableContact = existingContact.cnContact?.mutableCopy() as? CNMutableContact else {
            owsFail("\(logTag) in \(#function) mergedCNContact was unexpectedly nil")
            return nil
        }

        guard let newCNContact = OWSContacts.systemContact(for: self.dbRecord) else {
            owsFail("\(logTag) in \(#function) newCNContact was unexpectedly nil")
            return nil
        }

        let normalize = { (input: String) -> String in
            return (input as NSString).ows_stripped()
        }

        // TODO display name - but only if existing is blank

        var existingPhoneNumberSet: Set<String> = Set()
        mergedCNContact.phoneNumbers.map { $0.value }.forEach { (existingPhoneNumber: CNPhoneNumber) in
            // compare e164?
            let normalizedValue = normalize(existingPhoneNumber.stringValue as String)
            existingPhoneNumberSet.insert(normalizedValue)
        }

        newCNContact.phoneNumbers.forEach { (newLabeledPhoneNumber: CNLabeledValue<CNPhoneNumber>) in
            let normalizedValue = normalize(newLabeledPhoneNumber.value.stringValue as String)
            guard !existingPhoneNumberSet.contains(normalizedValue) else {
                Logger.debug("\(self.logTag) in \(#function) ignoring matching phone number: \(normalizedValue)")
                return
            }

            Logger.debug("\(self.logTag) in \(#function) adding new phone number: \(normalizedValue)")
            mergedCNContact.phoneNumbers.append(newLabeledPhoneNumber)
        }

//        // TODO emails
//        var existingEmailSet: Set<String> = Set()
//        mergedCNContact.emailAddresses.forEach { (existingEmail: CNLabeledValue<NSString>) in
//            existingEmailSet.insert(normalize(existingEmail.value as String))
//        }

        // TODO address

//        newCNContact.emailAddresses.forEach { newEmail in
//            let match = mergedCNContact.emailAddresses.first { existingEmail in
//                return normalize(existingEmail) == normalize(newEmail)
//            }
//            if match == nil {
//                mergedCNContact.emailAddresses.add
//            }
//        }
//
//
//

        return mergedCNContact.copy() as? CNContact
    }

    public func copy(withNamePrefix namePrefix: String?,
                     givenName: String?,
                     middleName: String?,
                     familyName: String?,
                     nameSuffix: String?) -> ContactShareViewModel {

        // TODO move the `copy` logic into the view model?
        let newDbRecord = dbRecord.copy(withNamePrefix: namePrefix, givenName: givenName, middleName: middleName, familyName: familyName, nameSuffix: nameSuffix)

        return ContactShareViewModel(contactShareRecord: newDbRecord, avatarImage: self.avatarImage)
    }

    public func newContact(withNamePrefix namePrefix: String?,
                           givenName: String?,
                           middleName: String?,
                           familyName: String?,
                           nameSuffix: String?) -> ContactShareViewModel {

        // TODO move the `newContact` logic into the view model?
        let newDbRecord = dbRecord.newContact(withNamePrefix: namePrefix,
                                              givenName: givenName,
                                              middleName: middleName,
                                              familyName: familyName,
                                              nameSuffix: nameSuffix)

        return ContactShareViewModel(contactShareRecord: newDbRecord, avatarImage: self.avatarImage)
    }

}
