//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

public struct ValidatedContactShareProto {
    public let contact: OWSContact
    public let avatarProto: SSKProtoAttachmentPointer?
}

public struct ValidatedContactShareDataSource {
    public let contact: OWSContact
    public let avatarDataSource: AttachmentDataSource?
}

// MARK: -

public protocol ContactShareManager {
    func validateAndBuild(
        for contactProto: SSKProtoDataMessageContact,
    ) -> ValidatedContactShareProto

    func validateAndPrepare(
        draft: ContactShareDraft,
    ) async throws -> ContactShareDraft.ForSending

    func validateAndBuild(
        preparedDraft: ContactShareDraft.ForSending,
    ) -> ValidatedContactShareDataSource

    func buildProtoForSending(
        from contactShare: OWSContact,
        parentMessage: TSMessage,
        tx: DBReadTransaction,
    ) throws -> SSKProtoDataMessageContact
}

// MARK: -

class ContactShareManagerImpl: ContactShareManager {

    private let attachmentManager: AttachmentManager
    private let attachmentStore: AttachmentStore
    private let attachmentValidator: AttachmentContentValidator

    init(
        attachmentManager: AttachmentManager,
        attachmentStore: AttachmentStore,
        attachmentValidator: AttachmentContentValidator,
    ) {
        self.attachmentManager = attachmentManager
        self.attachmentStore = attachmentStore
        self.attachmentValidator = attachmentValidator
    }

    func validateAndBuild(
        for contactProto: SSKProtoDataMessageContact,
    ) -> ValidatedContactShareProto {
        var givenName: String?
        var familyName: String?
        var namePrefix: String?
        var nameSuffix: String?
        var middleName: String?
        if let nameProto = contactProto.name {
            if nameProto.hasGivenName {
                givenName = nameProto.givenName?.stripped
            }
            if nameProto.hasFamilyName {
                familyName = nameProto.familyName?.stripped
            }
            if nameProto.hasPrefix {
                namePrefix = nameProto.prefix?.stripped
            }
            if nameProto.hasSuffix {
                nameSuffix = nameProto.suffix?.stripped
            }
            if nameProto.hasMiddleName {
                middleName = nameProto.middleName?.stripped
            }
        }

        var organizationName: String?
        if contactProto.hasOrganization {
            organizationName = contactProto.organization?.stripped
        }

        let contactName = OWSContactName(
            givenName: givenName,
            familyName: familyName,
            namePrefix: namePrefix,
            nameSuffix: nameSuffix,
            middleName: middleName,
            organizationName: organizationName,
        )

        contactName.ensureDisplayName()

        let contact = OWSContact(name: contactName)

        contact.phoneNumbers = contactProto.number.compactMap { OWSContactPhoneNumber(proto: $0) }
        contact.emails = contactProto.email.compactMap { OWSContactEmail(proto: $0) }
        contact.addresses = contactProto.address.compactMap { OWSContactAddress(proto: $0) }

        return ValidatedContactShareProto(
            contact: contact,
            avatarProto: contactProto.avatar?.avatar,
        )
    }

    func validateAndPrepare(
        draft: ContactShareDraft,
    ) async throws -> ContactShareDraft.ForSending {
        let avatarDataSource: AttachmentDataSource? = try await {
            if
                let existingAvatarAttachment = draft.existingAvatarAttachment,
                let stream = existingAvatarAttachment.attachment.asStream()
            {
                return .forwarding(
                    existingAttachment: stream,
                    with: existingAvatarAttachment.reference,
                )
            } else if let avatarImage = draft.avatarImage {
                guard let imageData = avatarImage.jpegData(compressionQuality: 0.9) else {
                    throw OWSAssertionError("Failed to get JPEG")
                }
                let mimeType = MimeType.imageJpeg.rawValue
                let pendingAttachment = try await attachmentValidator.validateDataContents(
                    imageData,
                    mimeType: mimeType,
                    renderingFlag: .default,
                    sourceFilename: nil,
                )
                return .pendingAttachment(pendingAttachment)
            } else {
                return nil
            }
        }()
        return ContactShareDraft.ForSending(
            name: draft.name,
            addresses: draft.addresses,
            emails: draft.emails,
            phoneNumbers: draft.phoneNumbers,
            avatar: avatarDataSource,
        )
    }

    func validateAndBuild(
        preparedDraft draft: ContactShareDraft.ForSending,
    ) -> ValidatedContactShareDataSource {
        return ValidatedContactShareDataSource(
            contact: OWSContact(
                name: draft.name,
                phoneNumbers: draft.phoneNumbers,
                emails: draft.emails,
                addresses: draft.addresses,
            ),
            avatarDataSource: draft.avatar,
        )
    }

    func buildProtoForSending(
        from contactShare: OWSContact,
        parentMessage: TSMessage,
        tx: DBReadTransaction,
    ) throws -> SSKProtoDataMessageContact {

        let contactBuilder = SSKProtoDataMessageContact.builder()

        let nameBuilder = SSKProtoDataMessageContactName.builder()

        if let givenName = contactShare.name.givenName?.strippedOrNil {
            nameBuilder.setGivenName(givenName)
        }
        if let familyName = contactShare.name.familyName?.strippedOrNil {
            nameBuilder.setFamilyName(familyName)
        }
        if let middleName = contactShare.name.middleName?.strippedOrNil {
            nameBuilder.setMiddleName(middleName)
        }
        if let namePrefix = contactShare.name.namePrefix?.strippedOrNil {
            nameBuilder.setPrefix(namePrefix)
        }
        if let nameSuffix = contactShare.name.nameSuffix?.strippedOrNil {
            nameBuilder.setSuffix(nameSuffix)
        }
        if let organizationName = contactShare.name.organizationName?.strippedOrNil {
            contactBuilder.setOrganization(organizationName)
        }

        contactBuilder.setName(nameBuilder.buildInfallibly())

        contactBuilder.setNumber(contactShare.phoneNumbers.compactMap({ $0.proto() }))
        contactBuilder.setEmail(contactShare.emails.compactMap({ $0.proto() }))
        contactBuilder.setAddress(contactShare.addresses.compactMap({ $0.proto() }))

        if
            let parentMessageRowId = parentMessage.sqliteRowId,
            let avatarAttachment = attachmentStore.fetchAnyReferencedAttachment(
                for: .messageContactAvatar(messageRowId: parentMessageRowId),
                tx: tx,
            ),
            let avatarPointer = avatarAttachment.attachment.asTransitTierPointer(),
            case let .digestSHA256Ciphertext(digestSHA256Ciphertext) = avatarPointer.info.integrityCheck
        {
            let attachmentProto = attachmentManager.buildProtoForSending(
                from: avatarAttachment.reference,
                pointer: avatarPointer,
                digestSHA256Ciphertext: digestSHA256Ciphertext,
            )
            let avatarBuilder = SSKProtoDataMessageContactAvatar.builder()
            avatarBuilder.setAvatar(attachmentProto)
            contactBuilder.setAvatar(avatarBuilder.buildInfallibly())
        }

        let contactProto = contactBuilder.buildInfallibly()

        guard !contactProto.number.isEmpty || !contactProto.email.isEmpty || !contactProto.address.isEmpty else {
            throw OWSAssertionError("contact has neither phone, email or address.")
        }

        return contactProto
    }
}
