//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

public import Contacts
import Mantle

public protocol OWSContactField: AnyObject {

    var isValid: Bool { get }

    var localizedLabel: String { get }
}

// MARK: - OWSContact

@objc(OWSContact)
public class OWSContact: MTLModel {

    @objc
    public var name: OWSContactName

    @objc
    public var phoneNumbers: [OWSContactPhoneNumber] = []
    @objc
    public var emails: [OWSContactEmail] = []
    @objc
    public var addresses: [OWSContactAddress] = []

    @objc
    private var avatarAttachmentId: String?

    public var legacyAvatarAttachmentId: String? { avatarAttachmentId }

    public var isValid: Bool {
        return Self.isValid(
            name: name,
            phoneNumbers: phoneNumbers,
            emails: emails,
            addresses: addresses
        )
    }

    public static func isValid(
        name: OWSContactName,
        phoneNumbers: [OWSContactPhoneNumber],
        emails: [OWSContactEmail],
        addresses: [OWSContactAddress]
    ) -> Bool {
        guard !name.displayName.stripped.isEmpty else {
            Logger.warn("invalid contact; no display name.")
            return false
        }
        var hasValue = false
        for phoneNumber in phoneNumbers {
            guard phoneNumber.isValid else {
                return false
            }
            hasValue = true
        }
        for email in emails {
            guard email.isValid else {
                return false
            }
            hasValue = true
        }
        for address in addresses {
            guard address.isValid else {
                return false
            }
            hasValue = true
        }
        return hasValue
    }

    public override init() {
        self.name = OWSContactName()
        super.init()
    }

    public init(name: OWSContactName) {
        self.name = name
        super.init()
        name.updateDisplayName()
    }

    public init(
        name: OWSContactName,
        phoneNumbers: [OWSContactPhoneNumber],
        emails: [OWSContactEmail],
        addresses: [OWSContactAddress],
        avatarAttachmentId: String?
    ) {
        self.name = name
        self.phoneNumbers = phoneNumbers
        self.emails = emails
        self.addresses = addresses
        self.avatarAttachmentId = avatarAttachmentId
        super.init()
    }

    required init!(coder: NSCoder!) {
        self.name = OWSContactName()
        super.init(coder: coder)
    }

    required init(dictionary dictionaryValue: [String: Any]!) throws {
        self.name = OWSContactName()
        try super.init(dictionary: dictionaryValue)
    }

    public func copy(with name: OWSContactName) -> OWSContact {
        let contactCopy = self.copy() as! OWSContact
        contactCopy.name = name
        name.updateDisplayName()
        return contactCopy
    }

    // MARK: Avatar

    public func setLegacyAvatarAttachmentId(_ attachmentId: String) {
        self.avatarAttachmentId = attachmentId
    }

    // MARK: Phone Numbers and Recipient IDs

    private var e164PhoneNumbersCached: [String]?

    public struct PhoneNumberPartition {
        fileprivate(set) public var sendablePhoneNumbers = [String]()
        fileprivate(set) public var invitablePhoneNumbers = [String]()
        fileprivate(set) public var addablePhoneNumbers = [String]()

        public func map<T>(
            ifSendablePhoneNumbers: ([String]) -> T,
            elseIfInvitablePhoneNumbers: ([String]) -> T,
            elseIfAddablePhoneNumbers: ([String]) -> T,
            elseIfNoPhoneNumbers: () -> T
        ) -> T {
            if !sendablePhoneNumbers.isEmpty {
                return ifSendablePhoneNumbers(sendablePhoneNumbers)
            }
            if !invitablePhoneNumbers.isEmpty {
                return elseIfInvitablePhoneNumbers(invitablePhoneNumbers)
            }
            if !addablePhoneNumbers.isEmpty {
                return elseIfAddablePhoneNumbers(addablePhoneNumbers)
            }
            return elseIfNoPhoneNumbers()
        }
    }

    private struct PhoneNumberStatus {
        var phoneNumber: String
        var isSystemContact: Bool
        var canLinkToSystemContact: Bool
    }

    public func phoneNumberPartition(tx: SDSAnyReadTransaction) -> PhoneNumberPartition {
        let recipientDatabaseTable = DependenciesBridge.shared.recipientDatabaseTable
        let phoneNumberStatuses = e164PhoneNumbers().map { phoneNumber in
            let recipient = recipientDatabaseTable.fetchRecipient(phoneNumber: phoneNumber, transaction: tx.asV2Read)
            return PhoneNumberStatus(
                phoneNumber: phoneNumber,
                isSystemContact: SSKEnvironment.shared.contactManagerRef.cnContactId(for: phoneNumber) != nil,
                canLinkToSystemContact: recipient?.isRegistered == true
            )
        }
        var result = PhoneNumberPartition()
        for phoneNumberStatus in phoneNumberStatuses {
            if phoneNumberStatus.isSystemContact {
                if phoneNumberStatus.canLinkToSystemContact {
                    result.sendablePhoneNumbers.append(phoneNumberStatus.phoneNumber)
                    continue
                }
                result.invitablePhoneNumbers.append(phoneNumberStatus.phoneNumber)
                continue
            }
            result.addablePhoneNumbers.append(phoneNumberStatus.phoneNumber)
        }
        return result
    }

    public func e164PhoneNumbers() -> [String] {
        if let e164PhoneNumbersCached {
            return e164PhoneNumbersCached
        }

        let e164PhoneNumbers: [String] = phoneNumbers.compactMap { phoneNumber in
            if let parsedPhoneNumber = SSKEnvironment.shared.phoneNumberUtilRef.parsePhoneNumber(userSpecifiedText: phoneNumber.phoneNumber) {
                return parsedPhoneNumber.e164
            }
            return nil
        }

        e164PhoneNumbersCached = e164PhoneNumbers

        return e164PhoneNumbers
    }
}

// MARK: CNContact Conversion

extension OWSContact {

    public convenience init(cnContact: CNContact) {
        // Name
        let contactName = OWSContactName(cnContact: cnContact)
        self.init(
            name: contactName,
            phoneNumbers: cnContact.phoneNumbers.map { OWSContactPhoneNumber(cnLabeledValue: $0) },
            emails: cnContact.emailAddresses.map { OWSContactEmail(cnLabeledValue: $0) },
            addresses: cnContact.postalAddresses.map { OWSContactAddress(cnLabeledValue: $0) },
            avatarAttachmentId: nil
        )
    }

    public func buildSystemContact(withImageData imageData: Data?) -> CNContact? {
        guard isValid else { return nil }

        let cnContact = CNMutableContact()

        // Name
        cnContact.givenName = name.givenName ?? ""
        cnContact.middleName = name.middleName ?? ""
        cnContact.familyName = name.familyName ?? ""
        cnContact.namePrefix = name.namePrefix ?? ""
        cnContact.nameSuffix = name.nameSuffix ?? ""
        cnContact.organizationName = name.organizationName ?? ""

        // Phone Numbers, Emails, Addresses
        cnContact.phoneNumbers = phoneNumbers.map { $0.cnLabeledValue() }
        cnContact.emailAddresses = emails.map { $0.cnLabeledValue() }
        cnContact.postalAddresses = addresses.compactMap { $0.cnLabeledValue() }

        // Photo
        cnContact.imageData = imageData

        return cnContact
    }
}
