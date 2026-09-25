//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

public import Contacts
public import LibSignalClient

public protocol OWSContactField: AnyObject {
    var isValid: Bool { get }
    var localizedLabel: String { get }
}

// MARK: - OWSContact

@objc(OWSContact)
public final class OWSContact: NSObject, NSSecureCoding, NSCopying {
    public static var supportsSecureCoding: Bool { true }

    public init?(coder: NSCoder) {
        self.aci = Aci.parseFrom(aciString: coder.decodeObject(of: NSString.self, forKey: "aci") as String?)
        self.addresses = coder.decodeArrayOfObjects(ofClass: OWSContactAddress.self, forKey: "addresses") ?? []
        self.emails = coder.decodeArrayOfObjects(ofClass: OWSContactEmail.self, forKey: "emails") ?? []
        self.name = coder.decodeObject(of: OWSContactName.self, forKey: "name") ?? OWSContactName()
        self.nickname = coder.decodeObject(of: NSPersonNameComponents.self, forKey: "nickname") as PersonNameComponents?
        self.note = coder.decodeObject(of: NSString.self, forKey: "note") as String?
        self.phoneNumbers = coder.decodeArrayOfObjects(ofClass: OWSContactPhoneNumber.self, forKey: "phoneNumbers") ?? []
    }

    public func encode(with coder: NSCoder) {
        coder.encode(self.aci?.serviceIdUppercaseString, forKey: "aci")
        coder.encode(self.addresses, forKey: "addresses")
        coder.encode(self.emails, forKey: "emails")
        coder.encode(self.name, forKey: "name")
        coder.encode(self.nickname as NSPersonNameComponents?, forKey: "nickname")
        coder.encode(self.note, forKey: "note")
        coder.encode(self.phoneNumbers, forKey: "phoneNumbers")
    }

    override public var hash: Int {
        var hasher = Hasher()
        hasher.combine(aci)
        hasher.combine(addresses)
        hasher.combine(emails)
        hasher.combine(name)
        hasher.combine(nickname)
        hasher.combine(note)
        hasher.combine(phoneNumbers)
        return hasher.finalize()
    }

    override public func isEqual(_ object: Any?) -> Bool {
        guard let object = object as? Self else { return false }
        guard type(of: self) == type(of: object) else { return false }
        guard self.aci == object.aci else { return false }
        guard self.addresses == object.addresses else { return false }
        guard self.emails == object.emails else { return false }
        guard self.name == object.name else { return false }
        guard self.nickname == object.nickname else { return false }
        guard self.note == object.note else { return false }
        guard self.phoneNumbers == object.phoneNumbers else { return false }
        return true
    }

    public func copy(with zone: NSZone? = nil) -> Any {
        return Self(
            name: name,
            phoneNumbers: phoneNumbers,
            emails: emails,
            addresses: addresses,
            aci: aci,
            nickname: nickname,
            note: note,
        )
    }

    public var name: OWSContactName
    public var phoneNumbers: [OWSContactPhoneNumber]
    public var emails: [OWSContactEmail]
    public var addresses: [OWSContactAddress]
    public var aci: Aci?
    public var nickname: PersonNameComponents?
    public var note: String?

    public var isValid: Bool {
        return Self.isValid(
            name: name,
            phoneNumbers: phoneNumbers,
            emails: emails,
            addresses: addresses,
            aci: BuildFlags.accountIdentifierSharing ? aci : nil,
        )
    }

    public static func isValid(
        name: OWSContactName,
        phoneNumbers: [OWSContactPhoneNumber],
        emails: [OWSContactEmail],
        addresses: [OWSContactAddress],
        aci: Aci?,
    ) -> Bool {
        guard !name.displayName.stripped.isEmpty else {
            Logger.warn("invalid contact; no display name.")
            return false
        }
        var hasValue = aci != nil
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
        self.aci = nil
        self.nickname = nil
        self.note = nil
        super.init()
        name.updateDisplayName()
    }

    public init(
        name: OWSContactName,
        phoneNumbers: [OWSContactPhoneNumber],
        emails: [OWSContactEmail],
        addresses: [OWSContactAddress],
        aci: Aci?,
        nickname: PersonNameComponents?,
        note: String?,
    ) {
        self.name = name
        self.phoneNumbers = phoneNumbers
        self.emails = emails
        self.addresses = addresses
        self.aci = aci
        self.nickname = nickname
        self.note = note
        super.init()
    }

    public func copy(with name: OWSContactName) -> OWSContact {
        name.updateDisplayName()
        return Self(
            name: name,
            phoneNumbers: self.phoneNumbers,
            emails: self.emails,
            addresses: self.addresses,
            aci: self.aci,
            nickname: self.nickname,
            note: self.note,
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
            aci: nil,
            nickname: nil,
            note: nil,
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
