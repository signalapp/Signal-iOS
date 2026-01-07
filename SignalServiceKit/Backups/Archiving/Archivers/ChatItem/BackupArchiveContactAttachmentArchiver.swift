//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

class BackupArchiveContactAttachmentArchiver: BackupArchiveProtoStreamWriter {
    private typealias ArchiveFrameError = BackupArchive.ArchiveFrameError<BackupArchive.InteractionUniqueId>
    typealias RestoreInteractionResult = BackupArchive.RestoreInteractionResult
    private typealias RestoreFrameError = BackupArchive.RestoreFrameError<BackupArchive.ChatItemId>

    private let attachmentsArchiver: BackupArchiveMessageAttachmentArchiver

    init(
        attachmentsArchiver: BackupArchiveMessageAttachmentArchiver,
    ) {
        self.attachmentsArchiver = attachmentsArchiver
    }

    func archiveContact(
        _ contact: OWSContact,
        uniqueInteractionId: BackupArchive.InteractionUniqueId,
        messageRowId: Int64,
        context: BackupArchive.ArchivingContext,
    ) -> BackupArchive.ArchiveInteractionResult<BackupProto_ContactAttachment> {
        let resultType = BackupProto_ContactAttachment.self
        var partialErrors = [ArchiveFrameError]()

        var contactProto = BackupProto_ContactAttachment()

        switch archiveContactName(contact.name).bubbleUp(resultType, partialErrors: &partialErrors) {
        case .continue(let nameProto):
            nameProto.map { contactProto.name = $0 }
        case .bubbleUpError(let errorResult):
            return errorResult
        }

        var phoneNumberProtos = [BackupProto_ContactAttachment.Phone]()
        for phoneNumber in contact.phoneNumbers {
            switch archiveContactPhoneNumber(phoneNumber).bubbleUp(resultType, partialErrors: &partialErrors) {
            case .continue(let phoneNumberProto):
                phoneNumberProtos.append(phoneNumberProto)
            case .bubbleUpError(let errorResult):
                return errorResult
            }
        }
        contactProto.number = phoneNumberProtos

        var emailProtos = [BackupProto_ContactAttachment.Email]()
        for email in contact.emails {
            switch archiveContactEmail(email).bubbleUp(resultType, partialErrors: &partialErrors) {
            case .continue(let emailProto):
                emailProtos.append(emailProto)
            case .bubbleUpError(let errorResult):
                return errorResult
            }
        }
        contactProto.email = emailProtos

        var addressProtos = [BackupProto_ContactAttachment.PostalAddress]()
        for address in contact.addresses {
            switch archiveContactAddress(address).bubbleUp(resultType, partialErrors: &partialErrors) {
            case .continue(let addressProto):
                addressProtos.append(addressProto)
            case .bubbleUpError(let errorResult):
                return errorResult
            }
        }
        contactProto.address = addressProtos

        if let organization = contact.name.organizationName {
            contactProto.organization = organization
        }

        // Returns nil if no avatar; this is both how we check existence and how we archive.
        let avatarResult = attachmentsArchiver.archiveContactShareAvatarAttachment(
            messageRowId: messageRowId,
            context: context,
        )
        switch avatarResult.bubbleUp(BackupProto_ContactAttachment.self, partialErrors: &partialErrors) {
        case .continue(let avatarPointerProto):
            avatarPointerProto.map { contactProto.avatar = $0 }
        case .bubbleUpError(let errorResult):
            return errorResult
        }

        if partialErrors.isEmpty {
            return .success(contactProto)
        } else {
            return .partialFailure(contactProto, partialErrors)
        }
    }

    private func archiveContactName(
        _ contactName: OWSContactName,
    ) -> BackupArchive.ArchiveInteractionResult<BackupProto_ContactAttachment.Name?> {
        var nameProto = BackupProto_ContactAttachment.Name()
        var setSomeName = false

        if let givenName = contactName.givenName?.strippedOrNil {
            nameProto.givenName = givenName
            setSomeName = true
        }
        if let familyName = contactName.familyName?.strippedOrNil {
            nameProto.familyName = familyName
            setSomeName = true
        }
        if let namePrefix = contactName.namePrefix?.strippedOrNil {
            nameProto.prefix = namePrefix
            setSomeName = true
        }
        if let nameSuffix = contactName.nameSuffix?.strippedOrNil {
            nameProto.suffix = nameSuffix
            setSomeName = true
        }
        if let middleName = contactName.middleName?.strippedOrNil {
            nameProto.middleName = middleName
            setSomeName = true
        }
        if let nickname = contactName.nickname?.strippedOrNil {
            nameProto.nickname = nickname
            setSomeName = true
        }

        if setSomeName {
            return .success(nameProto)
        } else {
            return .success(nil)
        }
    }

    private func archiveContactPhoneNumber(
        _ contactPhoneNumber: OWSContactPhoneNumber,
    ) -> BackupArchive.ArchiveInteractionResult<BackupProto_ContactAttachment.Phone> {
        var phoneProto = BackupProto_ContactAttachment.Phone()
        phoneProto.value = contactPhoneNumber.phoneNumber
        if let label = contactPhoneNumber.label {
            phoneProto.label = label
        }
        phoneProto.type = switch contactPhoneNumber.type {
        case .home:
            .home
        case .mobile:
            .mobile
        case .work:
            .work
        case .custom:
            .custom
        }
        return .success(phoneProto)
    }

    private func archiveContactEmail(
        _ contactEmail: OWSContactEmail,
    ) -> BackupArchive.ArchiveInteractionResult<BackupProto_ContactAttachment.Email> {
        var emailProto = BackupProto_ContactAttachment.Email()
        emailProto.value = contactEmail.email
        if let label = contactEmail.label {
            emailProto.label = label
        }
        emailProto.type = switch contactEmail.type {
        case .home:
            .home
        case .mobile:
            .mobile
        case .work:
            .work
        case .custom:
            .custom
        }
        return .success(emailProto)
    }

    private func archiveContactAddress(
        _ contactAddress: OWSContactAddress,
    ) -> BackupArchive.ArchiveInteractionResult<BackupProto_ContactAttachment.PostalAddress> {
        var addressProto = BackupProto_ContactAttachment.PostalAddress()
        if let label = contactAddress.label {
            addressProto.label = label
        }
        if let street = contactAddress.street {
            addressProto.street = street
        }
        if let pobox = contactAddress.pobox {
            addressProto.pobox = pobox
        }
        if let neighborhood = contactAddress.neighborhood {
            addressProto.neighborhood = neighborhood
        }
        if let city = contactAddress.city {
            addressProto.city = city
        }
        if let region = contactAddress.region {
            addressProto.region = region
        }
        if let postcode = contactAddress.postcode {
            addressProto.postcode = postcode
        }
        if let country = contactAddress.country {
            addressProto.country = country
        }
        addressProto.type = switch contactAddress.type {
        case .home:
            .home
        case .work:
            .work
        case .custom:
            .custom
        }
        return .success(addressProto)
    }

    // MARK: - Restore

    func restoreContact(
        _ contactProto: BackupProto_ContactAttachment,
        chatItemId: BackupArchive.ChatItemId,
    ) -> RestoreInteractionResult<OWSContact> {
        var partialErrors = [RestoreFrameError]()

        var givenName: String?
        var familyName: String?
        var namePrefix: String?
        var nameSuffix: String?
        var middleName: String?
        var nickname: String?
        if contactProto.hasName {
            givenName = contactProto.name.givenName.strippedOrNil
            familyName = contactProto.name.familyName.strippedOrNil
            namePrefix = contactProto.name.prefix.strippedOrNil
            nameSuffix = contactProto.name.suffix.strippedOrNil
            middleName = contactProto.name.middleName.strippedOrNil
            nickname = contactProto.name.nickname.strippedOrNil
        }

        let organizationName = contactProto.organization.strippedOrNil

        let contactName = OWSContactName(
            givenName: givenName,
            familyName: familyName,
            namePrefix: namePrefix,
            nameSuffix: nameSuffix,
            middleName: middleName,
            nickname: nickname,
            organizationName: organizationName,
        )

        contactName.ensureDisplayName()

        let contact = OWSContact(name: contactName)

        for phoneNumberProto in contactProto.number {
            switch self
                .restoreContactPhoneNumber(
                    proto: phoneNumberProto,
                    chatItemId: chatItemId,
                )
                .bubbleUp(OWSContact.self, partialErrors: &partialErrors)
            {
            case .continue(let phoneNumber):
                if let phoneNumber {
                    contact.phoneNumbers.append(phoneNumber)
                }
            case .bubbleUpError(let error):
                return error
            }
        }
        for emailProto in contactProto.email {
            switch self
                .restoreContactEmail(
                    proto: emailProto,
                    chatItemId: chatItemId,
                )
                .bubbleUp(OWSContact.self, partialErrors: &partialErrors)
            {
            case .continue(let email):
                if let email {
                    contact.emails.append(email)
                }
            case .bubbleUpError(let error):
                return error
            }
        }
        for addressProto in contactProto.address {
            switch self
                .restoreContactAddress(
                    proto: addressProto,
                    chatItemId: chatItemId,
                )
                .bubbleUp(OWSContact.self, partialErrors: &partialErrors)
            {
            case .continue(let address):
                if let address {
                    contact.addresses.append(address)
                }
            case .bubbleUpError(let error):
                return error
            }
        }

        // Note: the contact attachment's avatar is restored later (if any is set).

        if partialErrors.isEmpty {
            return .success(contact)
        } else {
            return .partialRestore(contact, partialErrors)
        }
    }

    private func restoreContactPhoneNumber(
        proto: BackupProto_ContactAttachment.Phone,
        chatItemId: BackupArchive.ChatItemId,
    ) -> RestoreInteractionResult<OWSContactPhoneNumber?> {
        guard let phoneNumber = proto.value.strippedOrNil else {
            return .partialRestore(nil, [.restoreFrameError(
                .invalidProtoData(.contactAttachmentPhoneNumberMissingValue),
                chatItemId,
            )])
        }

        let type: OWSContactPhoneNumber.`Type`
        switch proto.type {
        case .home:
            type = .home
        case .mobile:
            type = .mobile
        case .work:
            type = .work
        case .custom:
            type = .custom
        case .unknown, .UNRECOGNIZED:
            type = .home
        }

        return .success(OWSContactPhoneNumber(
            type: type,
            label: proto.label.strippedOrNil,
            phoneNumber: phoneNumber,
        ))
    }

    private func restoreContactEmail(
        proto: BackupProto_ContactAttachment.Email,
        chatItemId: BackupArchive.ChatItemId,
    ) -> RestoreInteractionResult<OWSContactEmail?> {
        guard let email = proto.value.strippedOrNil else {
            return .partialRestore(nil, [.restoreFrameError(
                .invalidProtoData(.contactAttachmentEmailMissingValue),
                chatItemId,
            )])
        }

        let type: OWSContactEmail.`Type`
        switch proto.type {
        case .home:
            type = .home
        case .mobile:
            type = .mobile
        case .work:
            type = .work
        case .custom:
            type = .custom
        case .unknown, .UNRECOGNIZED:
            type = .home
        }

        return .success(OWSContactEmail(
            type: type,
            label: proto.label.strippedOrNil,
            email: email,
        ))
    }

    private func restoreContactAddress(
        proto: BackupProto_ContactAttachment.PostalAddress,
        chatItemId: BackupArchive.ChatItemId,
    ) -> RestoreInteractionResult<OWSContactAddress?> {
        let type: OWSContactAddress.`Type`
        switch proto.type {
        case .home:
            type = .home
        case .work:
            type = .work
        case .custom:
            type = .custom
        case .unknown, .UNRECOGNIZED:
            type = .home
        }

        let address = OWSContactAddress(
            type: type,
            label: proto.label.strippedOrNil,
            street: proto.street.strippedOrNil,
            pobox: proto.pobox.strippedOrNil,
            neighborhood: proto.neighborhood.strippedOrNil,
            city: proto.city.strippedOrNil,
            region: proto.region.strippedOrNil,
            postcode: proto.postcode.strippedOrNil,
            country: proto.country.strippedOrNil,
        )

        guard
            address.street?.isEmpty == false
            || address.pobox?.isEmpty == false
            || address.neighborhood?.isEmpty == false
            || address.city?.isEmpty == false
            || address.region?.isEmpty == false
            || address.postcode?.isEmpty == false
            || address.country?.isEmpty == false
        else {
            return .partialRestore(nil, [.restoreFrameError(
                .invalidProtoData(.contactAttachmentEmptyAddress),
                chatItemId,
            )])
        }

        return .success(address)
    }
}
