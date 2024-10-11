//
// Copyright 2021 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

public import GRDB
public import LibSignalClient

@objc(SignalAccount)
public final class SignalAccount: NSObject, SDSCodableModel, Decodable {
    public static let databaseTableName = "model_SignalAccount"
    public static var recordType: UInt { SDSRecordType.signalAccount.rawValue }

    public enum CodingKeys: String, CodingKey, ColumnExpression, CaseIterable {
        case id
        case recordType
        case uniqueId

        case contact
        case contactAvatarHash
        case multipleAccountLabelText
        case recipientPhoneNumber
        case recipientServiceId = "recipientUUID"

        case cnContactId
        case givenName
        case familyName
        case nickname
        case fullName
    }

    public var id: RowId?
    public let uniqueId: String

    public let contactAvatarHash: Data?
    public let multipleAccountLabelText: String

    public let recipientPhoneNumber: String?
    public private(set) var recipientServiceId: ServiceId?

    public let hasDeprecatedRepresentation: Bool
    public let cnContactId: String?
    public var isFromLocalAddressBook: Bool { cnContactId != nil }
    public let givenName: String
    public let familyName: String
    public let nickname: String
    public let fullName: String

    public convenience init(
        recipientPhoneNumber: String?,
        recipientServiceId: ServiceId?,
        multipleAccountLabelText: String?,
        cnContactId: String?,
        givenName: String,
        familyName: String,
        nickname: String,
        fullName: String,
        contactAvatarHash: Data?
    ) {
        self.init(
            id: nil,
            uniqueId: UUID().uuidString,
            contactAvatarHash: contactAvatarHash,
            multipleAccountLabelText: multipleAccountLabelText,
            recipientPhoneNumber: recipientPhoneNumber,
            recipientServiceId: recipientServiceId,
            hasDeprecatedRepresentation: false,
            cnContactId: cnContactId,
            givenName: givenName,
            familyName: familyName,
            nickname: nickname,
            fullName: fullName
        )
    }

    private init(
        id: RowId?,
        uniqueId: String,
        contactAvatarHash: Data?,
        multipleAccountLabelText: String?,
        recipientPhoneNumber: String?,
        recipientServiceId: ServiceId?,
        hasDeprecatedRepresentation: Bool,
        cnContactId: String?,
        givenName: String,
        familyName: String,
        nickname: String,
        fullName: String
    ) {
        self.id = id
        self.uniqueId = uniqueId
        self.contactAvatarHash = contactAvatarHash
        self.multipleAccountLabelText = multipleAccountLabelText ?? ""
        self.recipientPhoneNumber = recipientPhoneNumber
        self.recipientServiceId = recipientServiceId
        self.hasDeprecatedRepresentation = hasDeprecatedRepresentation
        self.cnContactId = cnContactId
        self.givenName = givenName
        self.familyName = familyName
        self.nickname = nickname
        self.fullName = fullName
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        let decodedRecordType = try container.decode(UInt.self, forKey: .recordType)
        owsAssertDebug(decodedRecordType == Self.recordType, "Unexpectedly decoded record with wrong type!")

        id = try container.decodeIfPresent(RowId.self, forKey: .id)
        uniqueId = try container.decode(String.self, forKey: .uniqueId)

        // To match iOS system behavior, the String name fields are NONNULL. As a
        // result, we must test for whether or not `contact` exists to know if we
        // have a deprecated or modern representation.
        if let deprecatedContactData = try container.decodeIfPresent(Data.self, forKey: .contact) {
            let deprecatedContact: Contact = try LegacySDSSerializer().deserializeLegacySDSData(
                deprecatedContactData,
                propertyName: "contact"
            )
            self.hasDeprecatedRepresentation = true
            self.cnContactId = deprecatedContact.cnContactId
            self.givenName = deprecatedContact.firstName
            self.familyName = deprecatedContact.lastName
            self.nickname = deprecatedContact.nickname
            self.fullName = deprecatedContact.fullName
        } else {
            self.hasDeprecatedRepresentation = false
            self.cnContactId = try container.decodeIfPresent(String.self, forKey: .cnContactId)
            self.givenName = try container.decode(String.self, forKey: .givenName)
            self.familyName = try container.decode(String.self, forKey: .familyName)
            self.nickname = try container.decode(String.self, forKey: .nickname)
            self.fullName = try container.decode(String.self, forKey: .fullName)
        }

        contactAvatarHash = try container.decodeIfPresent(Data.self, forKey: .contactAvatarHash)
        multipleAccountLabelText = try container.decode(String.self, forKey: .multipleAccountLabelText)
        recipientPhoneNumber = try container.decodeIfPresent(String.self, forKey: .recipientPhoneNumber)
        recipientServiceId = try container.decodeIfPresent(String.self, forKey: .recipientServiceId)
            .flatMap { try? ServiceId.parseFrom(serviceIdString: $0) }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)

        try container.encode(Self.recordType, forKey: .recordType)

        try id.map { try container.encode($0, forKey: .id) }
        try container.encode(uniqueId, forKey: .uniqueId)

        try container.encodeIfPresent(contactAvatarHash, forKey: .contactAvatarHash)
        try container.encode(multipleAccountLabelText, forKey: .multipleAccountLabelText)
        try container.encodeIfPresent(recipientPhoneNumber, forKey: .recipientPhoneNumber)
        try container.encodeIfPresent(recipientServiceId?.serviceIdUppercaseString, forKey: .recipientServiceId)
        try container.encodeIfPresent(cnContactId, forKey: .cnContactId)
        try container.encode(givenName, forKey: .givenName)
        try container.encode(familyName, forKey: .familyName)
        try container.encode(nickname, forKey: .nickname)
        try container.encode(fullName, forKey: .fullName)
    }

    public func didInsert(with rowID: Int64, for column: String?) {
        self.id = rowID
    }
}

// MARK: - Update in place

extension SignalAccount {
    func updateServiceId(_ newServiceId: ServiceId, tx: SDSAnyWriteTransaction) {
        recipientServiceId = newServiceId
        anyOverwritingUpdate(transaction: tx)
    }
}

// MARK: - Convenience Inits

extension SignalAccount {
    @objc
    public convenience init(address: SignalServiceAddress) {
        self.init(
            recipientPhoneNumber: address.phoneNumber,
            recipientServiceId: address.serviceId,
            multipleAccountLabelText: nil,
            cnContactId: nil,
            givenName: "",
            familyName: "",
            nickname: "",
            fullName: "",
            contactAvatarHash: nil
        )
    }
}

// MARK: - DB Operation Hooks

extension SignalAccount {
    public func anyDidInsert(transaction: SDSAnyWriteTransaction) {
        let searchableNameIndexer = DependenciesBridge.shared.searchableNameIndexer
        searchableNameIndexer.insert(self, tx: transaction.asV2Write)
    }

    public func anyDidUpdate(transaction: SDSAnyWriteTransaction) {
        let searchableNameIndexer = DependenciesBridge.shared.searchableNameIndexer
        searchableNameIndexer.update(self, tx: transaction.asV2Write)
    }
}

// MARK: - Contact Display Name

extension SignalAccount {
    /// Name components for the contact. No empty strings will be present. If a
    /// non-nil value is returned, it is guaranteed that at least one string in
    /// the components object is non-nil.
    public func contactNameComponents() -> PersonNameComponents? {
        var components = PersonNameComponents()
        if let firstName = self.givenName.strippedOrNil {
            components.givenName = firstName
        }
        if let lastName = self.familyName.strippedOrNil {
            components.familyName = lastName
        }

        if
            components.givenName == nil,
            components.familyName == nil,
            let fullName = self.fullName.strippedOrNil
        {
            components.givenName = fullName
        }

        if let nickname = self.nickname.strippedOrNil {
            components.nickname = nickname
        }

        guard
            components.givenName != nil ||
            components.familyName != nil ||
            components.nickname != nil
        else {
            return nil
        }

        return components
    }

    /// If we ask PersonNameComponentsFormatter for `.short`, we will get the
    /// nickname (if it exists). To match the system behavior for the chat list,
    /// we use the nickname in lieu of the full name as well.
    public static func shouldUseNicknames() -> Bool {
        var nameComponents = PersonNameComponents()
        nameComponents.givenName = "givenName"
        nameComponents.nickname = "nickname"
        let nameFormatter = PersonNameComponentsFormatter()
        nameFormatter.style = .short
        return nameFormatter.string(from: nameComponents) == "nickname"
    }
}

// MARK: - SignalServiceAddress

extension SignalAccount {
    public var recipientAddress: SignalServiceAddress {
        SignalServiceAddress(serviceId: recipientServiceId, phoneNumber: recipientPhoneNumber)
    }
}

// MARK: - Account Comparison

extension SignalAccount {

    public func hasSameContent(_ otherAccount: SignalAccount) -> Bool {
        // NOTE: We don't want to compare contactAvatarJpegData. It can't change
        // without contactAvatarHash changing as well.
        recipientPhoneNumber == otherAccount.recipientPhoneNumber
        && recipientServiceId == otherAccount.recipientServiceId
        && multipleAccountLabelText == otherAccount.multipleAccountLabelText
        && contactAvatarHash == otherAccount.contactAvatarHash
        && cnContactId == otherAccount.cnContactId
        && hasSameName(otherAccount)
    }

    public func hasSameName(_ otherAccount: SignalAccount) -> Bool {
        return (
            self.givenName == otherAccount.givenName
            && self.familyName == otherAccount.familyName
            && self.nickname == otherAccount.nickname
            && self.fullName == otherAccount.fullName
        )
    }

    public static func aciForPhoneNumberVisibilityUpdate(
        oldAccount: SignalAccount?,
        newAccount: SignalAccount?
    ) -> Aci? {
        let oldAci = oldAccount?.recipientServiceId as? Aci
        let newAci = newAccount?.recipientServiceId as? Aci
        // Don't do anything unless a system contact was added/removed or had an
        // ACI added to/removed from it.
        if (newAci == nil) == (oldAci == nil) {
            return nil
        }
        return (newAci ?? oldAci)!
    }
}

// MARK: - Avatar

extension SignalAccount {
    public func buildContactAvatarJpegData() -> Data? {
        guard isFromLocalAddressBook else {
            return nil
        }
        guard let cnContactId else {
            owsFailDebug("Missing cnContactId.")
            return nil
        }
        guard let contactAvatarData = SSKEnvironment.shared.contactManagerRef.avatarData(for: cnContactId) else {
            return nil
        }
        guard let contactAvatarJpegData = UIImage.validJpegData(fromAvatarData: contactAvatarData) else {
            owsFailDebug("Could not convert avatar to JPEG.")
            return nil
        }
        return contactAvatarJpegData
    }
}

// MARK: - String extension

private extension String {

    /// Returns the string filtered for display.
    ///
    /// - Note: If the string is empty after filtering, we return nil.
    var displayStringIfNonEmpty: String? {
        let filtered = self.filterForDisplay
        return filtered.nilIfEmpty
    }
}

// MARK: - NSCopying

extension SignalAccount: NSCopying {
    public func copy(with zone: NSZone? = nil) -> Any {
        return SignalAccount(
            id: self.id,
            uniqueId: self.uniqueId,
            contactAvatarHash: self.contactAvatarHash,
            multipleAccountLabelText: self.multipleAccountLabelText,
            recipientPhoneNumber: self.recipientPhoneNumber,
            recipientServiceId: self.recipientServiceId,
            hasDeprecatedRepresentation: self.hasDeprecatedRepresentation,
            cnContactId: self.cnContactId,
            givenName: self.givenName,
            familyName: self.familyName,
            nickname: self.nickname,
            fullName: self.fullName
        )
    }
}
