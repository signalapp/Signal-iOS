//
// Copyright 2018 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

public import Contacts
public import LibSignalClient
public import UIKit

public class ContactShareDraft {
    public var name: OWSContactName
    public var addresses: [OWSContactAddress]
    public var emails: [OWSContactEmail]
    public var phoneNumbers: [OWSContactPhoneNumber]
    public var aci: Aci?
    public var signalNote: String?
    public var existingAvatarAttachment: ReferencedAttachment?

    private var cachedAvatarImage: UIImage?
    public var avatarImageData: Data? {
        didSet {
            self.cachedAvatarImage = nil
            existingAvatarAttachment = nil
        }
    }

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

    public static func load(
        cnContact: CNContact,
        signalContact: @autoclosure () -> SystemContact,
        contactManager: any ContactManager,
        phoneNumberUtil: PhoneNumberUtil,
        profileManager: any ProfileManager,
        recipientManager: any SignalRecipientManager,
        tsAccountManager: any TSAccountManager,
        tx: DBReadTransaction,
    ) -> ContactShareDraft {
        let avatarData = loadAvatarData(
            cnContact: cnContact,
            signalContact: signalContact(),
            contactManager: contactManager,
            phoneNumberUtil: phoneNumberUtil,
            profileManager: profileManager,
            recipientManager: recipientManager,
            tsAccountManager: tsAccountManager,
            tx: tx,
        )
        return ContactShareDraft(
            name: OWSContactName(cnContact: cnContact),
            addresses: cnContact.postalAddresses.map(OWSContactAddress.init(cnLabeledValue:)),
            emails: cnContact.emailAddresses.map(OWSContactEmail.init(cnLabeledValue:)),
            phoneNumbers: cnContact.phoneNumbers.map(OWSContactPhoneNumber.init(cnLabeledValue:)),
            aci: nil,
            signalNote: nil,
            existingAvatarAttachment: nil,
            avatarImageData: avatarData,
        )
    }

    private static func loadAvatarData(
        cnContact: CNContact,
        signalContact: @autoclosure () -> SystemContact,
        contactManager: any ContactManager,
        phoneNumberUtil: PhoneNumberUtil,
        profileManager: any ProfileManager,
        recipientManager: any SignalRecipientManager,
        tsAccountManager: any TSAccountManager,
        tx: DBReadTransaction,
    ) -> Data? {
        if let systemAvatarImageData = contactManager.avatarData(for: cnContact) {
            return systemAvatarImageData
        }

        let localPhoneNumber = tsAccountManager.localIdentifiers(tx: tx)?.phoneNumber
        let canonicalPhoneNumbers = FetchedSystemContacts.parsePhoneNumbers(
            for: signalContact(),
            phoneNumberUtil: phoneNumberUtil,
            localPhoneNumber: E164(localPhoneNumber).map(CanonicalPhoneNumber.init(nonCanonicalPhoneNumber:)),
        )
        for canonicalPhoneNumber in canonicalPhoneNumbers {
            for phoneNumber in [canonicalPhoneNumber.rawValue] + canonicalPhoneNumber.alternatePhoneNumbers() {
                let recipient = recipientManager.fetchRecipientIfPhoneNumberVisible(phoneNumber.stringValue, tx: tx)
                guard let recipient else {
                    continue
                }
                if let avatarData = profileManager.userProfile(for: recipient.address, tx: tx)?.loadAvatarData() {
                    return avatarData
                }
            }
        }

        return nil
    }

    public required init(
        name: OWSContactName,
        addresses: [OWSContactAddress],
        emails: [OWSContactEmail],
        phoneNumbers: [OWSContactPhoneNumber],
        aci: Aci?,
        signalNote: String?,
        existingAvatarAttachment: ReferencedAttachment?,
        avatarImageData: Data?,
    ) {
        self.name = name
        self.addresses = addresses
        self.emails = emails
        self.phoneNumbers = phoneNumbers
        self.aci = aci
        self.signalNote = signalNote
        self.existingAvatarAttachment = existingAvatarAttachment
        self.avatarImageData = avatarImageData
    }

    public func newContact(withName name: OWSContactName) -> ContactShareDraft {
        // If we want to keep things other than the name and the ACI, the caller will need to re-apply them.
        return ContactShareDraft(
            name: name,
            addresses: [],
            emails: [],
            phoneNumbers: [],
            aci: aci,
            signalNote: nil,
            existingAvatarAttachment: nil,
            avatarImageData: nil,
        )
    }

    // MARK: Convenience getters

    public var displayName: String {
        return name.displayName
    }

    public var ows_isValid: Bool {
        return OWSContact.isValid(
            name: name,
            phoneNumbers: phoneNumbers,
            emails: emails,
            addresses: addresses,
            aci: BuildFlags.accountIdentifierSharing ? aci : nil,
        )
    }

    public struct ForSending {
        public let name: OWSContactName
        public let addresses: [OWSContactAddress]
        public let emails: [OWSContactEmail]
        public let phoneNumbers: [OWSContactPhoneNumber]
        public let aci: Aci?
        public let note: String?
        public let avatar: AttachmentDataSource?
    }
}
