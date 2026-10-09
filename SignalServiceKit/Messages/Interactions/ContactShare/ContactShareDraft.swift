//
// Copyright 2018 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

public import Contacts
public import LibSignalClient

public class ContactShareDraft {
    public var name: OWSContactName
    public var addresses: [OWSContactAddress]
    public var emails: [OWSContactEmail]
    public var phoneNumbers: [OWSContactPhoneNumber]
    public var aci: Aci?
    public var signalNickname: PersonNameComponents?
    public var signalNote: String?
    public var systemContactAvatarImageData: Data?
    public var signalAvatarImageData: Data?

    /// The avatar attachment of a forwarded contact share. Reused when sending.
    public var existingAvatarAttachment: ReferencedAttachment?

    /// The avatar sent with the contact, or `nil` to send none.
    public var selectedAvatarImageData: Data? {
        didSet {
            existingAvatarAttachment = nil
        }
    }

    /// Loads a contact share draft, also offering the Signal profile photo of a Signal contact
    /// matching one of its phone numbers.
    public static func loadWithMatchingSignalAvatar(
        cnContact: CNContact,
        signalContact: SystemContact,
        contactManager: any ContactManager,
        phoneNumberUtil: PhoneNumberUtil,
        profileManager: any ProfileManager,
        recipientHidingManager: any RecipientHidingManager,
        recipientManager: any SignalRecipientManager,
        tsAccountManager: any TSAccountManager,
        tx: DBReadTransaction,
    ) -> ContactShareDraft {
        return load(
            cnContact: cnContact,
            contactManager: contactManager,
            signalAvatarData: loadSignalAvatarData(
                signalContact: signalContact,
                phoneNumberUtil: phoneNumberUtil,
                profileManager: profileManager,
                recipientHidingManager: recipientHidingManager,
                recipientManager: recipientManager,
                tsAccountManager: tsAccountManager,
                tx: tx,
            ),
        )
    }

    public static func load(
        cnContact: CNContact,
        contactManager: any ContactManager,
        signalAvatarData: Data?,
    ) -> ContactShareDraft {
        let systemContactAvatarData = contactManager.avatarData(for: cnContact)
        return ContactShareDraft(
            name: OWSContactName(cnContact: cnContact),
            addresses: cnContact.postalAddresses.map(OWSContactAddress.init(cnLabeledValue:)),
            emails: cnContact.emailAddresses.map(OWSContactEmail.init(cnLabeledValue:)),
            phoneNumbers: cnContact.phoneNumbers.map(OWSContactPhoneNumber.init(cnLabeledValue:)),
            aci: nil,
            signalNickname: nil,
            signalNote: nil,
            existingAvatarAttachment: nil,
            systemContactAvatarImageData: systemContactAvatarData,
            signalAvatarImageData: signalAvatarData,
            selectedAvatarImageData: systemContactAvatarData ?? signalAvatarData,
        )
    }

    private static func loadSignalAvatarData(
        signalContact: SystemContact,
        phoneNumberUtil: PhoneNumberUtil,
        profileManager: any ProfileManager,
        recipientHidingManager: any RecipientHidingManager,
        recipientManager: any SignalRecipientManager,
        tsAccountManager: any TSAccountManager,
        tx: DBReadTransaction,
    ) -> Data? {
        guard let localIdentifiers = tsAccountManager.localIdentifiers(tx: tx) else {
            owsFailDebug("can't fetch profile avatar unless registered at some point")
            return nil
        }
        let canonicalPhoneNumbers = FetchedSystemContacts.parsePhoneNumbers(
            for: signalContact,
            phoneNumberUtil: phoneNumberUtil,
            localPhoneNumber: E164(localIdentifiers.phoneNumber).map(CanonicalPhoneNumber.init(nonCanonicalPhoneNumber:)),
        )
        for canonicalPhoneNumber in canonicalPhoneNumbers {
            for phoneNumber in [canonicalPhoneNumber.rawValue] + canonicalPhoneNumber.alternatePhoneNumbers() {
                let recipient = recipientManager.fetchRecipientIfPhoneNumberVisible(phoneNumber.stringValue, tx: tx)
                guard
                    let recipient,
                    recipient.isWhitelisted,
                    recipient.isRegistered,
                    !recipientHidingManager.isHiddenRecipient(recipientId: recipient.id, tx: tx)
                else {
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
        signalNickname: PersonNameComponents?,
        signalNote: String?,
        existingAvatarAttachment: ReferencedAttachment?,
        systemContactAvatarImageData: Data?,
        signalAvatarImageData: Data?,
        selectedAvatarImageData: Data?,
    ) {
        self.name = name
        self.addresses = addresses.filter(\.isValid)
        self.emails = emails.filter(\.isValid)
        self.phoneNumbers = phoneNumbers.filter(\.isValid)
        self.aci = aci
        self.signalNickname = signalNickname
        self.signalNote = signalNote
        self.existingAvatarAttachment = existingAvatarAttachment
        self.systemContactAvatarImageData = systemContactAvatarImageData
        self.signalAvatarImageData = signalAvatarImageData
        self.selectedAvatarImageData = selectedAvatarImageData
    }

    public func newContact(withName name: OWSContactName) -> ContactShareDraft {
        // If we want to keep things other than the name and the ACI, the caller will need to re-apply them.
        return ContactShareDraft(
            name: name,
            addresses: [],
            emails: [],
            phoneNumbers: [],
            aci: aci,
            signalNickname: nil,
            signalNote: nil,
            existingAvatarAttachment: nil,
            systemContactAvatarImageData: nil,
            signalAvatarImageData: nil,
            selectedAvatarImageData: nil,
        )
    }

    // MARK: Convenience getters

    public var displayName: String {
        return name.displayName
    }

    public var ows_isValid: Bool {
        return OWSContact.isValid(name: name)
    }

    public struct ForSending {
        public let name: OWSContactName
        public let addresses: [OWSContactAddress]
        public let emails: [OWSContactEmail]
        public let phoneNumbers: [OWSContactPhoneNumber]
        public let aci: Aci?
        public let nickname: PersonNameComponents?
        public let note: String?
        public let avatar: AttachmentDataSource?
    }
}
