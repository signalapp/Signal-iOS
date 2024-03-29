//
// Copyright 2018 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Contacts

public class ContactShareDraft {

    public var name: OWSContactName

    public var addresses: [OWSContactAddress]

    public var emails: [OWSContactEmail]

    public var phoneNumbers: [OWSContactPhoneNumber]

    public var existingAvatarAttachment: ReferencedTSResource?

    public var avatarImageData: Data? {
        didSet {
            self.cachedAvatarImage = nil
            existingAvatarAttachment = nil
        }
    }

    private var cachedAvatarImage: UIImage?

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
        signalContact: @autoclosure () -> Contact,
        contactsManager: ContactManager,
        profileManager: ProfileManager,
        recipientManager: SignalRecipientManager,
        tx: SDSAnyReadTransaction
    ) -> ContactShareDraft {
        let avatarData = loadAvatarData(
            cnContact: cnContact,
            signalContact: signalContact(),
            contactsManager: contactsManager,
            profileManager: profileManager,
            recipientManager: recipientManager,
            tx: tx
        )
        return ContactShareDraft(
            name: OWSContactName(cnContact: cnContact),
            addresses: cnContact.postalAddresses.map(OWSContactAddress.init(cnLabeledValue:)),
            emails: cnContact.emailAddresses.map(OWSContactEmail.init(cnLabeledValue:)),
            phoneNumbers: cnContact.phoneNumbers.map(OWSContactPhoneNumber.init(cnLabeledValue:)),
            existingAvatarAttachment: nil,
            avatarImageData: avatarData
        )
    }

    private static func loadAvatarData(
        cnContact: CNContact,
        signalContact: @autoclosure () -> Contact,
        contactsManager: ContactManager,
        profileManager: ProfileManager,
        recipientManager: SignalRecipientManager,
        tx: SDSAnyReadTransaction
    ) -> Data? {
        if let systemAvatarImageData = contactsManager.avatarData(for: cnContact.identifier) {
            return systemAvatarImageData
        }

        let recipientManager = DependenciesBridge.shared.recipientManager
        let profileAvatarData: Data? = signalContact().e164sForIntersection.lazy.compactMap { phoneNumber in
            let recipient = recipientManager.fetchRecipientIfPhoneNumberVisible(phoneNumber, tx: tx.asV2Read)
            guard let recipient else {
                return nil
            }
            return profileManager.profileAvatarData(for: recipient.address, transaction: tx)
        }.first
        if let profileAvatarData {
            return profileAvatarData
        }

        return nil
    }

    public required init(
        name: OWSContactName,
        addresses: [OWSContactAddress],
        emails: [OWSContactEmail],
        phoneNumbers: [OWSContactPhoneNumber],
        existingAvatarAttachment: ReferencedTSResource?,
        avatarImageData: Data?
    ) {
        self.name = name
        self.addresses = addresses
        self.emails = emails
        self.phoneNumbers = phoneNumbers
        self.existingAvatarAttachment = existingAvatarAttachment
        self.avatarImageData = avatarImageData
    }

    public func newContact(withName name: OWSContactName) -> ContactShareDraft {
        // If we want to keep things other than the name, the caller will need to re-apply it.
        return ContactShareDraft(
            name: name,
            addresses: [],
            emails: [],
            phoneNumbers: [],
            existingAvatarAttachment: nil,
            avatarImageData: nil
        )
    }

    public func builderForSending(tx: SDSAnyWriteTransaction) throws -> OwnedAttachmentBuilder<OWSContact> {
        func buildContact(legacyAttachmentId: String? = nil) -> OWSContact {
            return OWSContact(
                name: name,
                phoneNumbers: phoneNumbers,
                emails: emails,
                addresses: addresses,
                avatarAttachmentId: legacyAttachmentId
            )
        }

        let avatarDataSource: TSResourceDataSource
        if let existingAvatarAttachment, let stream = existingAvatarAttachment.attachment.asResourceStream() {
            avatarDataSource = .forwarding(
                existingAttachment: stream,
                with: existingAvatarAttachment.reference
            )
        } else if let avatarImage {
            guard let imageData = avatarImage.jpegData(compressionQuality: 0.9) else {
                throw OWSAssertionError("Failed to get JPEG")
            }
            let mimeType = OWSMimeTypeImageJpeg
            avatarDataSource = .from(
                data: imageData,
                mimeType: mimeType,
                caption: nil,
                renderingFlag: .default,
                sourceFilename: nil
            )
        } else {
            return .withoutFinalizer(buildContact())
        }

        return try DependenciesBridge.shared.tsResourceManager.createAttachmentStreamBuilder(
            from: avatarDataSource,
            tx: tx.asV2Write
        ).wrap { attachmentInfo in
            switch attachmentInfo {
            case .legacy(uniqueId: let uniqueId):
                return buildContact(legacyAttachmentId: uniqueId)
            case .v2:
                return buildContact()
            }
        }

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
            addresses: addresses
        )
    }
}
