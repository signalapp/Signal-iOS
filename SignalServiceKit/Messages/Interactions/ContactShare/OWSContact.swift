//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

public import Contacts

public protocol OWSContactField: AnyObject {
    var isValid: Bool { get }
    var localizedLabel: String { get }
}

// MARK: - OWSContact

@objc(OWSContact)
public final class OWSContact: NSObject, NSCoding, NSCopying {
    public init?(coder: NSCoder) {
        self.addresses = coder.decodeObject(of: [NSArray.self, OWSContactAddress.self], forKey: "addresses") as? [OWSContactAddress] ?? []
        self.emails = coder.decodeObject(of: [NSArray.self, OWSContactEmail.self], forKey: "emails") as? [OWSContactEmail] ?? []
        self.name = coder.decodeObject(of: OWSContactName.self, forKey: "name") ?? OWSContactName()
        self.phoneNumbers = coder.decodeObject(of: [NSArray.self, OWSContactPhoneNumber.self], forKey: "phoneNumbers") as? [OWSContactPhoneNumber] ?? []
    }

    public func encode(with coder: NSCoder) {
        coder.encode(self.addresses, forKey: "addresses")
        coder.encode(self.emails, forKey: "emails")
        coder.encode(self.name, forKey: "name")
        coder.encode(self.phoneNumbers, forKey: "phoneNumbers")
    }

    override public var hash: Int {
        var hasher = Hasher()
        hasher.combine(addresses)
        hasher.combine(emails)
        hasher.combine(name)
        hasher.combine(phoneNumbers)
        return hasher.finalize()
    }

    override public func isEqual(_ object: Any?) -> Bool {
        guard let object = object as? Self else { return false }
        guard type(of: self) == type(of: object) else { return false }
        guard self.addresses == object.addresses else { return false }
        guard self.emails == object.emails else { return false }
        guard self.name == object.name else { return false }
        guard self.phoneNumbers == object.phoneNumbers else { return false }
        return true
    }

    public func copy(with zone: NSZone? = nil) -> Any {
        return Self(
            name: name,
            phoneNumbers: phoneNumbers,
            emails: emails,
            addresses: addresses,
        )
    }

    public var name: OWSContactName
    public var phoneNumbers: [OWSContactPhoneNumber]
    public var emails: [OWSContactEmail]
    public var addresses: [OWSContactAddress]

    public var isValid: Bool {
        return Self.isValid(
            name: name,
            phoneNumbers: phoneNumbers,
            emails: emails,
            addresses: addresses,
        )
    }

    public static func isValid(
        name: OWSContactName,
        phoneNumbers: [OWSContactPhoneNumber],
        emails: [OWSContactEmail],
        addresses: [OWSContactAddress],
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

    public init(name: OWSContactName) {
        self.name = name
        self.addresses = []
        self.emails = []
        self.phoneNumbers = []
        super.init()
        name.updateDisplayName()
    }

    public init(
        name: OWSContactName,
        phoneNumbers: [OWSContactPhoneNumber],
        emails: [OWSContactEmail],
        addresses: [OWSContactAddress],
    ) {
        self.name = name
        self.phoneNumbers = phoneNumbers
        self.emails = emails
        self.addresses = addresses
        super.init()
    }

    public func copy(with name: OWSContactName) -> OWSContact {
        name.updateDisplayName()
        return Self(
            name: name,
            phoneNumbers: self.phoneNumbers,
            emails: self.emails,
            addresses: self.addresses,
        )
    }

    // MARK: Phone Numbers and Recipient IDs

    private var e164PhoneNumbersCached: [String]?

    public struct PhoneNumberPartition {
        public fileprivate(set) var sendablePhoneNumbers = [String]()
        public fileprivate(set) var invitablePhoneNumbers = [String]()
        public fileprivate(set) var addablePhoneNumbers = [String]()

        public func map<T>(
            ifSendablePhoneNumbers: ([String]) -> T,
            elseIfInvitablePhoneNumbers: ([String]) -> T,
            elseIfAddablePhoneNumbers: ([String]) -> T,
            elseIfNoPhoneNumbers: () -> T,
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

    public func phoneNumberPartition(tx: DBReadTransaction) -> PhoneNumberPartition {
        let recipientDatabaseTable = DependenciesBridge.shared.recipientDatabaseTable
        let phoneNumberStatuses = e164PhoneNumbers().map { phoneNumber in
            let recipient = recipientDatabaseTable.fetchRecipient(phoneNumber: phoneNumber, transaction: tx)
            return PhoneNumberStatus(
                phoneNumber: phoneNumber,
                isSystemContact: SSKEnvironment.shared.contactManagerRef.cnContactId(for: phoneNumber) != nil,
                canLinkToSystemContact: recipient?.isRegistered == true,
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
        self.init(
            name: OWSContactName(cnContact: cnContact),
            phoneNumbers: cnContact.phoneNumbers.map { OWSContactPhoneNumber(cnLabeledValue: $0) },
            emails: cnContact.emailAddresses.map { OWSContactEmail(cnLabeledValue: $0) },
            addresses: cnContact.postalAddresses.map { OWSContactAddress(cnLabeledValue: $0) },
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
