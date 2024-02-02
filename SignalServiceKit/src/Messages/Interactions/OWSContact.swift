//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Contacts
import Mantle

public protocol OWSContactField: AnyObject {

    var isValid: Bool { get }

    var localizedLabel: String { get }
}

// MARK: - OWSContactPhoneNumber

@objc(OWSContactPhoneNumber)
public class OWSContactPhoneNumber: MTLModel, OWSContactField {

    @objc(OWSContactPhoneType)
    public enum `Type`: Int, CustomStringConvertible {
        case home = 1
        case mobile
        case work
        case custom

        public var description: String {
            switch self {
            case .home: return "Home"
            case .mobile: return "Mobile"
            case .work: return "Work"
            case .custom: return "Custom"
            }
        }
    }

    @objc(phoneType)
    public private(set) var type: `Type` = .home

    // Applies in the Type.custom case.
    @objc
    public private(set) var label: String?

    @objc
    public private(set) var phoneNumber: String = ""

    public override init() {
        super.init()
    }

    public init(type: Type, label: String? = nil, phoneNumber: String) {
        self.type = type
        self.label = label
        self.phoneNumber = phoneNumber
        super.init()
    }

    required init!(coder: NSCoder!) {
        super.init(coder: coder)
    }

    required init(dictionary dictionaryValue: [String: Any]!) throws {
        try super.init(dictionary: dictionaryValue)
    }

    public var e164: String? {
        var parsedPhoneNumber = PhoneNumber(fromE164: phoneNumber)
        if parsedPhoneNumber == nil {
            parsedPhoneNumber = PhoneNumber.tryParsePhoneNumber(fromUserSpecifiedText: phoneNumber)
        }
        return parsedPhoneNumber?.toE164()
    }

    // MARK: OWSContactField

    public var isValid: Bool {
        guard !phoneNumber.stripped.isEmpty else {
            Logger.warn("invalid phone number: \(phoneNumber).")
            return false
        }
        return true
    }

    public var localizedLabel: String {
        switch type {
        case .home:
            return CNLabeledValue<CNPhoneNumber>.localizedString(forLabel: CNLabelHome)

        case .mobile:
            return CNLabeledValue<CNPhoneNumber>.localizedString(forLabel: CNLabelPhoneNumberMobile)

        case .work:
            return CNLabeledValue<CNPhoneNumber>.localizedString(forLabel: CNLabelWork)

        case .custom:
            guard let label = label?.strippedOrNil else {
                return OWSLocalizedString("CONTACT_PHONE", comment: "Label for a contact's phone number.")
            }
            return label
        }
    }
}

// MARK: - OWSContactEmail

@objc(OWSContactEmail)
public class OWSContactEmail: MTLModel, OWSContactField {

    @objc(OWSContactEmailType)
    public enum `Type`: Int, CustomStringConvertible {
        case home = 1
        case mobile
        case work
        case custom

        public var description: String {
            switch self {
            case .home: return "Home"
            case .mobile: return "Mobile"
            case .work: return "Work"
            case .custom: return "Custom"
            }
        }
    }

    @objc(emailType)
    public private(set) var type: `Type` = .home

    // Applies in the Type.custom case.
    @objc
    public private(set) var label: String?

    @objc
    public private(set) var email: String = ""

    public override init() {
        super.init()
    }

    public init(type: Type, label: String? = nil, email: String) {
        self.type = type
        self.label = label
        self.email = email
        super.init()
    }

    required init!(coder: NSCoder!) {
        super.init(coder: coder)
    }

    required init(dictionary dictionaryValue: [String: Any]!) throws {
        try super.init(dictionary: dictionaryValue)
    }

    // MARK: OWSContactField

    public var isValid: Bool {
        guard !email.stripped.isEmpty else {
            Logger.warn("invalid email: \(email).")
            return false
        }
        return true
    }

    public var localizedLabel: String {
        switch type {
        case .home:
            return CNLabeledValue<CNPhoneNumber>.localizedString(forLabel: CNLabelHome)

        case .mobile:
            return CNLabeledValue<CNPhoneNumber>.localizedString(forLabel: CNLabelPhoneNumberMobile)

        case .work:
            return CNLabeledValue<CNPhoneNumber>.localizedString(forLabel: CNLabelWork)

        case .custom:
            guard let label = label?.strippedOrNil else {
                return OWSLocalizedString("CONTACT_EMAIL", comment: "Label for a contact's email address.")
            }
            return label
        }
    }
}

// MARK: - OWSContactAddress

@objc(OWSContactAddress)
public class OWSContactAddress: MTLModel, OWSContactField {

    @objc(OWSContactAddressType)
    public enum `Type`: Int, CustomStringConvertible {
        case home = 1
        case work
        case custom

        public var description: String {
            switch self {
            case .home: return "Home"
            case .work: return "Work"
            case .custom: return "Custom"
            }
        }
    }

    @objc(addressType)
    public private(set) var type: `Type` = .home

    // Applies in the Type.custom case.
    @objc
    public private(set) var label: String?

    @objc
    public fileprivate(set) var street: String?
    @objc
    public fileprivate(set) var pobox: String?
    @objc
    public fileprivate(set) var neighborhood: String?
    @objc
    public fileprivate(set) var city: String?
    @objc
    public fileprivate(set) var region: String?
    @objc
    public fileprivate(set) var postcode: String?
    @objc
    public fileprivate(set) var country: String?

    public override init() {
        super.init()
    }

    public init(
        type: `Type`,
        label: String? = nil,
        street: String? = nil,
        pobox: String? = nil,
        neighborhood: String? = nil,
        city: String? = nil,
        region: String? = nil,
        postcode: String? = nil,
        country: String? = nil
    ) {
        self.type = type
        self.label = label
        self.street = street
        self.pobox = pobox
        self.neighborhood = neighborhood
        self.city = city
        self.region = region
        self.postcode = postcode
        self.country = country
        super.init()
    }

    required init!(coder: NSCoder!) {
        super.init(coder: coder)
    }

    required init(dictionary dictionaryValue: [String: Any]!) throws {
        try super.init(dictionary: dictionaryValue)
    }

    // MARK: OWSContactField

    public var isValid: Bool {
        let fields: [String?] = [ street, pobox, neighborhood, city, region, postcode, country ]
        for field in fields {
            if field?.strippedOrNil != nil {
                return true
            }
        }
        Logger.warn("Invalid address: empty")
        return false
    }

    public var localizedLabel: String {
        switch type {
        case .home:
            return CNLabeledValue<CNPhoneNumber>.localizedString(forLabel: CNLabelHome)

        case .work:
            return CNLabeledValue<CNPhoneNumber>.localizedString(forLabel: CNLabelWork)

        case .custom:
            guard let label = label?.strippedOrNil else {
                return OWSLocalizedString("CONTACT_ADDRESS", comment: "Label for a contact's postal address.")
            }
            return label
        }
    }
}

// MARK: - OWSContactName

@objc(OWSContactName)
public class OWSContactName: MTLModel {

    @objc
    public fileprivate(set) var givenName: String?
    @objc
    public fileprivate(set) var familyName: String?
    @objc
    public fileprivate(set) var namePrefix: String?
    @objc
    public fileprivate(set) var nameSuffix: String?
    @objc
    public fileprivate(set) var middleName: String?
    @objc
    public fileprivate(set) var nickname: String?
    @objc
    public fileprivate(set) var organizationName: String?

    public override init() {
        super.init()
    }

    public init(
        givenName: String? = nil,
        familyName: String? = nil,
        namePrefix: String? = nil,
        nameSuffix: String? = nil,
        middleName: String? = nil,
        nickname: String? = nil,
        organizationName: String? = nil
    ) {
        self.givenName = givenName
        self.familyName = familyName
        self.namePrefix = namePrefix
        self.nameSuffix = nameSuffix
        self.middleName = middleName
        self.nickname = nickname
        self.organizationName = organizationName
        super.init()
    }

    required init!(coder: NSCoder!) {
        super.init(coder: coder)
    }

    required init(dictionary dictionaryValue: [String: Any]!) throws {
        try super.init(dictionary: dictionaryValue)
    }

    // MARK: Display Name

    private var _displayName: String?

    @objc
    public var displayName: String {
        ensureDisplayName()

        guard let displayName = _displayName?.nilIfEmpty else {
            owsFailDebug("could not derive a valid display name.")
            return OWSLocalizedString("CONTACT_WITHOUT_NAME", comment: "Indicates that a contact has no name.")
        }

        return displayName
    }

    fileprivate func ensureDisplayName() {
        if _displayName.isEmptyOrNil {
            if let cnContact = systemContactForName() {
                if let nickname = cnContact.nickname.nilIfEmpty {
                    _displayName = nickname
                } else {
                    _displayName = CNContactFormatter.string(from: cnContact, style: .fullName)
                }
            }
        }

        if _displayName.isEmptyOrNil {
            if let nickname = nickname?.nilIfEmpty {
                _displayName = nickname
            } else {
                // Fall back to using the organization name.
                _displayName = organizationName
            }
        }
    }

    fileprivate func updateDisplayName() {
        _displayName = nil
        ensureDisplayName()
    }

    private func systemContactForName() -> CNContact? {
        let cnContact = CNMutableContact()
        cnContact.givenName = givenName?.stripped ?? ""
        cnContact.middleName = middleName?.stripped ?? ""
        cnContact.familyName = familyName?.stripped ?? ""
        cnContact.namePrefix = namePrefix?.stripped ?? ""
        cnContact.nameSuffix = nameSuffix?.stripped ?? ""
        cnContact.nickname = nickname?.stripped ?? ""
        cnContact.organizationName = organizationName?.stripped ?? ""
        // We don't need to set display name, it's implicit for system contacts.
        return cnContact
    }

    // Returns true if any of the name parts (which doesn't include
    // organization name) is non-empty.
    public var hasAnyNamePart: Bool {
        let components: [String?] = [ givenName, middleName, familyName, namePrefix, nameSuffix, nickname ]
        for component in components {
            if component?.strippedOrNil != nil {
                return true
            }
        }
        return false
    }

    public var components: PersonNameComponents {
        var components = PersonNameComponents()
        components.givenName = givenName
        components.familyName = familyName
        components.middleName = middleName
        components.namePrefix = namePrefix
        components.nameSuffix = nameSuffix
        components.nickname = nickname
        return components
    }
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
    public private(set) var avatarAttachmentId: String?
    @objc
    public var isProfileAvatar: Bool = false

    public var isValid: Bool {
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

    @objc(avatarAttachmentWithTransaction:)
    public func avatarAttachment(with tx: SDSAnyReadTransaction) -> TSAttachment? {
        guard let avatarAttachmentId else { return nil }

        return TSAttachment.anyFetch(uniqueId: avatarAttachmentId, transaction: tx)
    }

    public func saveAvatarImage(_ image: UIImage, transaction tx: SDSAnyWriteTransaction) {
        guard let imageData = image.jpegData(compressionQuality: 0.9) else {
            owsFailBeta("Failed to get JPEG")
            return
        }

        let attachmentStream = TSAttachmentStream(
            contentType: OWSMimeTypeImageJpeg,
            byteCount: UInt32(imageData.count),
            sourceFilename: nil,
            caption: nil,
            attachmentType: .default,
            albumMessageId: nil
        )
        do {
            try attachmentStream.write(imageData)
        } catch {
            owsAssertDebug(false)
        }

        attachmentStream.anyInsert(transaction: tx)
        avatarAttachmentId = attachmentStream.uniqueId
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
                isSystemContact: Self.contactsManager.isSystemContact(phoneNumber: phoneNumber, transaction: tx),
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
            if let parsedPhoneNumber = PhoneNumber(fromE164: phoneNumber.phoneNumber) {
                return parsedPhoneNumber.toE164()
            }
            if let parsedPhoneNumber = PhoneNumber.tryParsePhoneNumber(fromUserSpecifiedText: phoneNumber.phoneNumber) {
                return parsedPhoneNumber.toE164()
            }
            return nil
        }

        e164PhoneNumbersCached = e164PhoneNumbers

        return e164PhoneNumbers
    }
}

// MARK: CNContact Conversion

extension OWSContactPhoneNumber {

    fileprivate convenience init(cnLabeledValue: CNLabeledValue<CNPhoneNumber>) {
        // Make a best effort to parse the phone number to e164.
        let unparsedPhoneNumber = cnLabeledValue.value.stringValue
        let parsedPhoneNumber: String = {
            if let phoneNumber = PhoneNumber(fromE164: unparsedPhoneNumber) {
                return phoneNumber.toE164()
            }
            if let phoneNumber = PhoneNumber.tryParsePhoneNumber(fromUserSpecifiedText: unparsedPhoneNumber) {
                return phoneNumber.toE164()
            }
            return unparsedPhoneNumber
        }()

        let customLabel: String?
        let type: `Type`
        switch cnLabeledValue.label {
        case CNLabelHome:
            type = .home
            customLabel = nil

        case CNLabelWork:
            type = .work
            customLabel = nil

        case CNLabelPhoneNumberMobile:
            type = .mobile
            customLabel = nil

        default:
            type = .custom
            customLabel = Contact.localizedString(forCNLabel: cnLabeledValue.label)
        }

        self.init(type: type, label: customLabel, phoneNumber: parsedPhoneNumber)
    }

    public func cnLabeledValue() -> CNLabeledValue<CNPhoneNumber> {
        let cnPhoneNumber = CNPhoneNumber(stringValue: phoneNumber)
        let cnLabel: String? = {
            switch type {
            case .home:
                return CNLabelHome
            case .mobile:
                return CNLabelPhoneNumberMobile
            case .work:
                return CNLabelWork
            case .custom:
                return label
            }
        }()
        return CNLabeledValue(label: cnLabel, value: cnPhoneNumber)
    }
}

extension OWSContactEmail {

    fileprivate convenience init(cnLabeledValue: CNLabeledValue<NSString>) {
        let email = cnLabeledValue.value as String

        let customLabel: String?
        let type: `Type`
        switch cnLabeledValue.label {
        case CNLabelHome:
            type = .home
            customLabel = nil

        case CNLabelWork:
            type = .work
            customLabel = nil

        default:
            type = .custom
            customLabel = Contact.localizedString(forCNLabel: cnLabeledValue.label)
        }

        self.init(type: type, label: customLabel, email: email)
    }

    public func cnLabeledValue() -> CNLabeledValue<NSString> {
        let cnLabel: String? = {
            switch type {
            case .home:
                return CNLabelHome
            case .mobile:
                return "Mobile"
            case .work:
                return CNLabelWork
            case .custom:
                return label
            }
        }()
        return CNLabeledValue(label: cnLabel, value: email as NSString)
    }
}

extension OWSContactAddress {

    fileprivate convenience init(cnLabeledValue: CNLabeledValue<CNPostalAddress>) {
        let customLabel: String?
        let type: `Type`
        switch cnLabeledValue.label {
        case CNLabelHome:
            type = .home
            customLabel = nil

        case CNLabelWork:
            type = .work
            customLabel = nil

        default:
            type = .custom
            customLabel = Contact.localizedString(forCNLabel: cnLabeledValue.label)
        }
        let cnPostalAddress = cnLabeledValue.value
        self.init(
            type: type,
            label: customLabel,
            street: cnPostalAddress.street,
            pobox: nil,
            neighborhood: nil,
            city: cnPostalAddress.city,
            region: cnPostalAddress.state,
            postcode: cnPostalAddress.postalCode,
            country: cnPostalAddress.isoCountryCode
        )
    }

    public func cnLabeledValue() -> CNLabeledValue<CNPostalAddress>? {
        guard isValid else { return nil }

        let cnPostalAddress = CNMutablePostalAddress()
        cnPostalAddress.street = street ?? ""
        // TODO: Is this the correct mapping?
        // cnPostalAddress.subLocality = address.neighborhood;
        cnPostalAddress.city = city ?? ""
        // TODO: Is this the correct mapping?
        // cnPostalAddress.subAdministrativeArea = address.region;
        cnPostalAddress.state = region ?? ""
        cnPostalAddress.postalCode = postcode ?? ""
        // TODO: Should we be using 2-letter codes, 3-letter codes or names?
        if let country {
            cnPostalAddress.isoCountryCode = country
            cnPostalAddress.country = PhoneNumberUtil.countryName(fromCountryCode: country)
        }

        let cnLabel: String? = {
            switch type {
            case .home:
                return CNLabelHome
            case .work:
                return CNLabelWork
            case .custom:
                return label
            }
        }()
        return CNLabeledValue(label: cnLabel, value: cnPostalAddress)
    }
}

extension OWSContact {

    public convenience init(cnContact: CNContact) {
        // Name
        let contactName = OWSContactName(
            givenName: cnContact.givenName.stripped,
            familyName: cnContact.familyName.stripped,
            namePrefix: cnContact.namePrefix.stripped,
            nameSuffix: cnContact.nameSuffix.stripped,
            middleName: cnContact.middleName.stripped,
            nickname: cnContact.nickname.stripped,
            organizationName: cnContact.organizationName.stripped
        )
        self.init(name: contactName)

        // Phone Numbers, Emails, Addresses
        phoneNumbers = cnContact.phoneNumbers.map { OWSContactPhoneNumber(cnLabeledValue: $0) }
        emails = cnContact.emailAddresses.map { OWSContactEmail(cnLabeledValue: $0) }
        addresses = cnContact.postalAddresses.map { OWSContactAddress(cnLabeledValue: $0) }
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

// MARK: - Protobuf

extension OWSContactPhoneNumber {

    fileprivate convenience init?(proto: SSKProtoDataMessageContactPhone) {
        guard proto.hasValue, let phoneNumber = proto.value?.strippedOrNil else { return nil }

        let type: `Type`
        if proto.hasType {
            switch proto.unwrappedType {
            case .home:
                type = .home

            case .mobile:
                type = .mobile

            case .work:
                type = .work

            default:
                type = .custom
            }
        } else {
            type = .custom
        }

        let label: String?
        if proto.hasLabel {
            label = proto.label?.strippedOrNil
        } else {
            label = nil
        }

        self.init(type: type, label: label, phoneNumber: phoneNumber)
    }

    fileprivate func proto() -> SSKProtoDataMessageContactPhone? {
        guard isValid else { return nil }

        let builder = SSKProtoDataMessageContactPhone.builder()
        builder.setValue(phoneNumber)
        if let label = label?.strippedOrNil {
            builder.setLabel(label)
        }
        let type: SSKProtoDataMessageContactPhoneType = {
            switch self.type {
            case .home: return .home
            case .work: return .work
            case .mobile: return .mobile
            case .custom: return .custom
            }
        }()
        builder.setType(type)

        do {
            let proto = try builder.build()
            return proto
        } catch {
            Logger.error("could not build proto: \(error)")
            return nil
        }
    }
}

extension OWSContactEmail {

    fileprivate convenience init?(proto: SSKProtoDataMessageContactEmail) {
        guard proto.hasValue, let email = proto.value?.strippedOrNil else { return nil }

        let type: `Type`
        if proto.hasType {
             switch proto.unwrappedType {
             case .home:
                 type = .home

             case .mobile:
                 type = .mobile

             case .work:
                 type = .work

             default:
                 type = .custom
             }
        } else {
            type = .custom
        }

        let label: String?
        if proto.hasLabel {
            label = proto.label?.strippedOrNil
        } else {
            label = nil
        }

        self.init(type: type, label: label, email: email)
    }

    fileprivate func proto() -> SSKProtoDataMessageContactEmail? {
        guard isValid else { return nil }

        let builder = SSKProtoDataMessageContactEmail.builder()
        builder.setValue(email)
        if let label = label?.strippedOrNil {
            builder.setLabel(label)
        }
        let type: SSKProtoDataMessageContactEmailType = {
            switch self.type {
            case .home: return .home
            case .work: return .work
            case .mobile: return .mobile
            case .custom: return .custom
            }
        }()
        builder.setType(type)

        do {
            let proto = try builder.build()
            return proto
        } catch {
            Logger.error("could not build proto: \(error)")
            return nil
        }
    }
}

extension OWSContactAddress {

    fileprivate convenience init?(proto: SSKProtoDataMessageContactPostalAddress) {
        let type: `Type`
        if proto.hasType {
             switch proto.unwrappedType {
             case .home:
                 type = .home

             case .work:
                 type = .work

             default:
                 type = .custom
             }
        } else {
            type = .custom
        }

        let label: String?
        if proto.hasLabel {
            label = proto.label?.strippedOrNil
        } else {
            label = nil
        }

        self.init(type: type, label: label)

         if proto.hasStreet {
             street = proto.street?.strippedOrNil
         }
         if proto.hasPobox {
             pobox = proto.pobox?.strippedOrNil
         }
         if proto.hasNeighborhood {
             neighborhood = proto.neighborhood?.strippedOrNil
         }
         if proto.hasCity {
             city = proto.city?.strippedOrNil
         }
         if proto.hasRegion {
             region = proto.region?.strippedOrNil
         }
         if proto.hasPostcode {
             postcode = proto.postcode?.strippedOrNil
         }
         if proto.hasCountry {
             country = proto.country?.strippedOrNil
         }

        guard isValid else { return nil }
    }

    fileprivate func proto() -> SSKProtoDataMessageContactPostalAddress? {
        guard isValid else { return nil }

        let builder = SSKProtoDataMessageContactPostalAddress.builder()

        if let label = label?.strippedOrNil {
            builder.setLabel(label)
        }

        let type: SSKProtoDataMessageContactPostalAddressType = {
            switch self.type {
            case .home: return .home
            case .work: return .work
            case .custom: return .custom
            }
        }()
        builder.setType(type)

        if let value = street?.strippedOrNil {
            builder.setStreet(value)
        }
        if let value = pobox?.strippedOrNil {
            builder.setPobox(value)
        }
        if let value = neighborhood?.strippedOrNil {
            builder.setNeighborhood(value)
        }
        if let value = city?.strippedOrNil {
            builder.setCity(value)
        }
        if let value = region?.strippedOrNil {
            builder.setRegion(value)
        }
        if let value = postcode?.strippedOrNil {
            builder.setPostcode(value)
        }
        if let value = country?.strippedOrNil {
            builder.setCountry(value)
        }

        do {
            let proto = try builder.build()
            return proto
        } catch {
            Logger.error("could not build proto: \(error)")
            return nil
        }
    }
}

@objc
extension OWSContact {

    @objc(protoWithTransaction:)
    public func proto(withTransaction tx: SDSAnyReadTransaction) -> SSKProtoDataMessageContact? {

        let contactBuilder = SSKProtoDataMessageContact.builder()

        let nameBuilder = SSKProtoDataMessageContactName.builder()

        if let givenName = name.givenName?.strippedOrNil {
            nameBuilder.setGivenName(givenName)
        }
        if let familyName = name.familyName?.strippedOrNil {
            nameBuilder.setFamilyName(familyName)
        }
        if let middleName = name.middleName?.strippedOrNil {
            nameBuilder.setMiddleName(middleName)
        }
        if let namePrefix = name.namePrefix?.strippedOrNil {
            nameBuilder.setPrefix(namePrefix)
        }
        if let nameSuffix = name.nameSuffix?.strippedOrNil {
            nameBuilder.setSuffix(nameSuffix)
        }
        if let organizationName = name.organizationName?.strippedOrNil {
            contactBuilder.setOrganization(organizationName)
        }
        nameBuilder.setDisplayName(name.displayName)

        do {
            let nameProto = try nameBuilder.build()
            contactBuilder.setName(nameProto)
        } catch {
            Logger.error("could not build proto: \(error)")
        }

        contactBuilder.setNumber(phoneNumbers.compactMap({ $0.proto() }))
        contactBuilder.setEmail(emails.compactMap({ $0.proto() }))
        contactBuilder.setAddress(addresses.compactMap({ $0.proto() }))

        if let avatarAttachmentId {
            if let attachmentProto = TSAttachmentStream.buildProto(
                attachmentId: avatarAttachmentId,
                caption: nil,
                attachmentType: .default,
                transaction: tx
            ) {
                let avatarBuilder = SSKProtoDataMessageContactAvatar.builder()
                avatarBuilder.setAvatar(attachmentProto)

                do {
                    let avatarProto = try avatarBuilder.build()
                    contactBuilder.setAvatar(avatarProto)
                } catch {
                    Logger.error("could not build proto: \(error)")
                }
            } else {
                Logger.error("could not build protobuf")
            }
        }

        let contactProto: SSKProtoDataMessageContact
        do {
            contactProto = try contactBuilder.build()
        } catch {
            owsFailDebug("could not build proto: \(error)")
            return nil
        }

        guard !contactProto.number.isEmpty || !contactProto.email.isEmpty || !contactProto.address.isEmpty else {
            owsFailDebug("contact has neither phone, email or address.")
            return nil
        }

        return contactProto
    }

    @objc(contactForDataMessage:transaction:)
    public class func contact(
        for dataMessage: SSKProtoDataMessage,
        transaction tx: SDSAnyWriteTransaction
    ) -> OWSContact? {
        return OWSContact(dataMessage: dataMessage, transaction: tx)
    }

    private convenience init?(dataMessage: SSKProtoDataMessage, transaction tx: SDSAnyWriteTransaction) {
        guard let contactProto = dataMessage.contact.first else { return nil }

        owsAssertBeta(dataMessage.contact.count == 1)

        let contactName = OWSContactName()
        if let nameProto = contactProto.name {
            if nameProto.hasGivenName {
                contactName.givenName = nameProto.givenName?.stripped
            }
            if nameProto.hasFamilyName {
                contactName.familyName = nameProto.familyName?.stripped
            }
            if nameProto.hasPrefix {
                contactName.namePrefix = nameProto.prefix?.stripped
            }
            if nameProto.hasSuffix {
                contactName.nameSuffix = nameProto.suffix?.stripped
            }
            if nameProto.hasMiddleName {
                contactName.middleName = nameProto.middleName?.stripped
            }
        }
        if contactProto.hasOrganization {
            contactName.organizationName = contactProto.organization?.stripped
        }
        contactName.ensureDisplayName()

        self.init(name: contactName)

        self.phoneNumbers = contactProto.number.compactMap { OWSContactPhoneNumber(proto: $0) }
        self.emails = contactProto.email.compactMap { OWSContactEmail(proto: $0) }
        self.addresses = contactProto.address.compactMap { OWSContactAddress(proto: $0) }

        if
            let avatar = contactProto.avatar,
            let avatarAttachment = avatar.avatar,
            let attachmentPointer  = TSAttachmentPointer(fromProto: avatarAttachment, albumMessage: nil) {
            attachmentPointer.anyInsert(transaction: tx)
            self.avatarAttachmentId = attachmentPointer.uniqueId
            self.isProfileAvatar = avatar.isProfile
        }
    }
}
