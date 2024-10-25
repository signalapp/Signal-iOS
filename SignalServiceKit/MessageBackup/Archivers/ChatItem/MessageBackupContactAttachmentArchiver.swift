//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

internal class MessageBackupContactAttachmentArchiver: MessageBackupProtoArchiver {
    private typealias ArchiveFrameError = MessageBackup.ArchiveFrameError<MessageBackup.InteractionUniqueId>
    typealias RestoreInteractionResult = MessageBackup.RestoreInteractionResult
    private typealias RestoreFrameError = MessageBackup.RestoreFrameError<MessageBackup.ChatItemId>

    private let attachmentsArchiver: MessageBackupMessageAttachmentArchiver

    init(
        attachmentsArchiver: MessageBackupMessageAttachmentArchiver
    ) {
        self.attachmentsArchiver = attachmentsArchiver
    }

    func archiveContact(
        _ contact: OWSContact,
        uniqueInteractionId: MessageBackup.InteractionUniqueId,
        messageRowId: Int64,
        context: MessageBackup.ArchivingContext
    ) -> MessageBackup.ArchiveInteractionResult<BackupProto_ContactAttachment> {
        let resultType = BackupProto_ContactAttachment.self
        var partialErrors = [ArchiveFrameError]()

        var contactProto = BackupProto_ContactAttachment()

        switch archiveContactName(contact.name).bubbleUp(resultType, partialErrors: &partialErrors) {
        case .continue(let nameProto):
            contactProto.name = nameProto
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
            messageId: uniqueInteractionId,
            messageRowId: messageRowId,
            context: context
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
        _ contactName: OWSContactName
    ) -> MessageBackup.ArchiveInteractionResult<BackupProto_ContactAttachment.Name> {
        var nameProto = BackupProto_ContactAttachment.Name()
        if let givenName = contactName.givenName {
            nameProto.givenName = givenName
        }
        if let familyName = contactName.familyName {
            nameProto.familyName = familyName
        }
        if let namePrefix = contactName.namePrefix {
            nameProto.prefix = namePrefix
        }
        if let nameSuffix = contactName.nameSuffix {
            nameProto.suffix = nameSuffix
        }
        if let middleName = contactName.middleName {
            nameProto.middleName = middleName
        }
        if let nickname = contactName.nickname {
            nameProto.nickname = nickname
        }
        return .success(nameProto)
    }

    private func archiveContactPhoneNumber(
        _ contactPhoneNumber: OWSContactPhoneNumber
    ) -> MessageBackup.ArchiveInteractionResult<BackupProto_ContactAttachment.Phone> {
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
        _ contactEmail: OWSContactEmail
    ) -> MessageBackup.ArchiveInteractionResult<BackupProto_ContactAttachment.Email> {
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
        _ contactAddress: OWSContactAddress
    ) -> MessageBackup.ArchiveInteractionResult<BackupProto_ContactAttachment.PostalAddress> {
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
        chatItemId: MessageBackup.ChatItemId
    ) -> RestoreInteractionResult<OWSContact> {
        var partialErrors = [RestoreFrameError]()

        var givenName: String?
        var familyName: String?
        var namePrefix: String?
        var nameSuffix: String?
        var middleName: String?
        var nickname: String?
        if contactProto.hasName {
            if contactProto.name.hasGivenName {
                givenName = contactProto.name.givenName.stripped
            }
            if contactProto.name.hasFamilyName {
                familyName = contactProto.name.familyName.stripped
            }
            if contactProto.name.hasPrefix {
                namePrefix = contactProto.name.prefix.stripped
            }
            if contactProto.name.hasSuffix {
                nameSuffix = contactProto.name.suffix.stripped
            }
            if contactProto.name.hasMiddleName {
                middleName = contactProto.name.middleName.stripped
            }
            if contactProto.name.hasNickname {
                nickname = contactProto.name.nickname.stripped
            }
        }

        var organizationName: String?
        if contactProto.hasOrganization {
            organizationName = contactProto.organization.stripped
        }

        let contactName = OWSContactName(
            givenName: givenName,
            familyName: familyName,
            namePrefix: namePrefix,
            nameSuffix: nameSuffix,
            middleName: middleName,
            nickname: nickname,
            organizationName: organizationName
        )

        contactName.ensureDisplayName()

        let contact = OWSContact(name: contactName)

        contact.phoneNumbers = contactProto.number.compactMap { phoneNumberProto in
            return self
                .restoreContactPhoneNumber(
                    proto: phoneNumberProto,
                    chatItemId: chatItemId
                )
                .unwrap(partialErrors: &partialErrors)
                // Double unwrap; we will just drops nulls.
                ?? nil
        }
        contact.emails = contactProto.email.compactMap { emailProto in
            return self
                .restoreContactEmail(
                    proto: emailProto,
                    chatItemId: chatItemId
                )
                .unwrap(partialErrors: &partialErrors)
                // Double unwrap; we will just drops nulls.
                ?? nil
        }
        contact.addresses = contactProto.address.compactMap { addressProto in
            return self
                .restoreContactAddress(
                    proto: addressProto,
                    chatItemId: chatItemId
                )
                .unwrap(partialErrors: &partialErrors)
                // Double unwrap; we will just drops nulls.
                ?? nil
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
        chatItemId: MessageBackup.ChatItemId
    ) -> RestoreInteractionResult<OWSContactPhoneNumber?> {
        guard
            proto.hasValue,
            let phoneNumber = proto.value.strippedOrNil
        else {
            return .partialRestore(nil, [.restoreFrameError(
                .invalidProtoData(.contactAttachmentPhoneNumberMissingValue),
                chatItemId
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
        case .unknown, .UNRECOGNIZED(_):
            return .partialRestore(nil, [.restoreFrameError(
                .invalidProtoData(.contactAttachmentPhoneNumberUnknownType),
                chatItemId
            )])
        }

        return .success(OWSContactPhoneNumber(
            type: type,
            label: proto.hasLabel ? proto.label.stripped : nil,
            phoneNumber: phoneNumber
        ))
    }

    private func restoreContactEmail(
        proto: BackupProto_ContactAttachment.Email,
        chatItemId: MessageBackup.ChatItemId
    ) -> RestoreInteractionResult<OWSContactEmail?> {
        guard
            proto.hasValue,
            let email = proto.value.strippedOrNil
        else {
            return .partialRestore(nil, [.restoreFrameError(
                .invalidProtoData(.contactAttachmentEmailMissingValue),
                chatItemId
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
        case .unknown, .UNRECOGNIZED(_):
            return .partialRestore(nil, [.restoreFrameError(
                .invalidProtoData(.contactAttachmentEmailUnknownType),
                chatItemId
            )])
        }

        return .success(OWSContactEmail(
            type: type,
            label: proto.hasLabel ? proto.label.stripped : nil,
            email: email
        ))
    }

    private func restoreContactAddress(
        proto: BackupProto_ContactAttachment.PostalAddress,
        chatItemId: MessageBackup.ChatItemId
    ) -> RestoreInteractionResult<OWSContactAddress?> {
        let type: OWSContactAddress.`Type`
        switch proto.type {
        case .home:
            type = .home
        case .work:
            type = .work
        case .custom:
            type = .custom
        case .unknown, .UNRECOGNIZED(_):
            return .partialRestore(nil, [.restoreFrameError(
                .invalidProtoData(.contactAttachmentAddressUnknownType),
                chatItemId
            )])
        }

        let address = OWSContactAddress(
            type: type,
            label: proto.hasLabel ? proto.label.stripped : nil,
            street: proto.hasStreet ? proto.street.stripped : nil,
            pobox: proto.hasPobox ? proto.pobox.stripped : nil,
            neighborhood: proto.hasNeighborhood ? proto.neighborhood.stripped : nil,
            city: proto.hasCity ? proto.city.stripped : nil,
            region: proto.hasRegion ? proto.region.stripped : nil,
            postcode: proto.hasPostcode ? proto.postcode.stripped : nil,
            country: proto.hasCountry ? proto.country.stripped : nil
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
                chatItemId
            )])
        }

        return .success(address)
    }
}
