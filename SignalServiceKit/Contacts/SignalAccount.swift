//
// Copyright 2021 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import GRDB
import LibSignalClient
import SignalCoreKit

/// We need to query the system preferences to achieve the behaviour at Messages on iOS.
/// 
/// If we ask NSPersonNameComponentsFormatter for "short" we will get the nickname if it
/// exists but if it _doesn't_ exit we'll just get the first name. (Or the name pattern
/// the user has selected in their system preferences. This means that in the conversation
/// list in the left, where Messages displays the full name of a contact if they don't
/// have a nickname, we'd just display the Short Name. To match the behaviour we ask
/// UserDefaults for the value of this key and prefer to use the nickname, if available,
/// in the conversation list.
private let kSignalPreferNicknamesPreference = "NSPersonNameDefaultShouldPreferNicknamesPreference"

@objc(SignalAccount)
public final class SignalAccount: NSObject, SDSCodableModel, Decodable, NSCoding {
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
    }

    public var id: RowId?
    public let uniqueId: String

    @objc
    public private(set) var contact: Contact?
    public let contactAvatarHash: Data?
    public let multipleAccountLabelText: String

    @objc
    public let recipientPhoneNumber: String?
    public private(set) var recipientServiceId: ServiceId?
    @objc
    public var recipientServiceIdObjc: ServiceIdObjC? {
        recipientServiceId.map { .wrapValue($0) }
    }

    public convenience init(
        contact: Contact?,
        contactAvatarHash: Data?,
        multipleAccountLabelText: String?,
        recipientPhoneNumber: String?,
        recipientServiceId: ServiceId?
    ) {
        self.init(
            id: nil,
            uniqueId: UUID().uuidString,
            contact: contact,
            contactAvatarHash: contactAvatarHash,
            multipleAccountLabelText: multipleAccountLabelText,
            recipientPhoneNumber: recipientPhoneNumber,
            recipientServiceId: recipientServiceId
        )
    }

    private init(
        id: RowId?,
        uniqueId: String,
        contact: Contact?,
        contactAvatarHash: Data?,
        multipleAccountLabelText: String?,
        recipientPhoneNumber: String?,
        recipientServiceId: ServiceId?
    ) {
        self.id = id
        self.uniqueId = uniqueId
        self.contact = contact
        self.contactAvatarHash = contactAvatarHash
        self.multipleAccountLabelText = multipleAccountLabelText ?? ""
        self.recipientPhoneNumber = recipientPhoneNumber
        self.recipientServiceId = recipientServiceId
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        let decodedRecordType = try container.decode(UInt.self, forKey: .recordType)
        owsAssertDebug(decodedRecordType == Self.recordType, "Unexpectedly decoded record with wrong type!")

        id = try container.decodeIfPresent(RowId.self, forKey: .id)
        uniqueId = try container.decode(String.self, forKey: .uniqueId)

        contact = try container.decodeIfPresent(
            Data.self,
            forKey: .contact
        ).map { contactData in
            try LegacySDSSerializer().deserializeLegacySDSData(
                contactData,
                propertyName: "contact"
            )
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

        try container.encodeIfPresent(
            LegacySDSSerializer().serializeAsLegacySDSData(property: contact),
            forKey: .contact
        )
        try container.encodeIfPresent(contactAvatarHash, forKey: .contactAvatarHash)
        try container.encode(multipleAccountLabelText, forKey: .multipleAccountLabelText)
        try container.encodeIfPresent(recipientPhoneNumber, forKey: .recipientPhoneNumber)
        try container.encodeIfPresent(recipientServiceId?.serviceIdUppercaseString, forKey: .recipientServiceId)
    }

    private enum NSCoderKeys: String {
        case grdbId
        case uniqueId
        case accountSchemaVersion
        case contact
        case contactAvatarHash
        case multipleAccountLabelText
        case recipientId
        case recipientPhoneNumber
        case recipientServiceId = "recipientUUID"
    }

    public init?(coder: NSCoder) {
        func decodeObject<DecodedObjectType>(
            of objectType: DecodedObjectType.Type,
            forKey key: NSCoderKeys
        ) -> DecodedObjectType? where DecodedObjectType: NSObject, DecodedObjectType: NSCoding {
            return coder.decodeObject(of: objectType, forKey: key.rawValue)
        }
        let accountSchemaVersion = decodeObject(of: NSNumber.self, forKey: .accountSchemaVersion)?.intValue ?? 0
        self.id = decodeObject(of: NSNumber.self, forKey: .grdbId)?.int64Value
        guard let uniqueId = decodeObject(of: NSString.self, forKey: .uniqueId) else {
            return nil
        }
        self.uniqueId = uniqueId as String
        self.contact = decodeObject(of: Contact.self, forKey: .contact)
        self.contactAvatarHash = decodeObject(of: NSData.self, forKey: .contactAvatarHash) as Data?
        guard let multipleAccountLabelText = decodeObject(of: NSString.self, forKey: .multipleAccountLabelText) else {
            return nil
        }
        self.multipleAccountLabelText = multipleAccountLabelText as String
        if accountSchemaVersion == 0 {
            self.recipientPhoneNumber = decodeObject(of: NSString.self, forKey: .recipientId) as String?
            owsAssert(self.recipientPhoneNumber != nil)
        } else {
            self.recipientPhoneNumber = decodeObject(of: NSString.self, forKey: .recipientPhoneNumber) as String?
        }
        self.recipientServiceId = (decodeObject(of: NSString.self, forKey: .recipientServiceId) as String?)
            .flatMap { try? ServiceId.parseFrom(serviceIdString: $0) }
    }

    public func encode(with coder: NSCoder) {
        func encodeObject(_ value: Any?, forKey key: NSCoderKeys) {
            if let value { coder.encode(value, forKey: key.rawValue) }
        }
        encodeObject(NSNumber(value: 1), forKey: .accountSchemaVersion)
        encodeObject(grdbId, forKey: .grdbId)
        encodeObject(uniqueId, forKey: .uniqueId)
        encodeObject(contact, forKey: .contact)
        encodeObject(contactAvatarHash, forKey: .contactAvatarHash)
        encodeObject(multipleAccountLabelText, forKey: .multipleAccountLabelText)
        encodeObject(recipientPhoneNumber, forKey: .recipientPhoneNumber)
        encodeObject(recipientServiceId?.serviceIdUppercaseString, forKey: .recipientServiceId)
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
    public convenience init(
        contact: Contact? = nil,
        address: SignalServiceAddress
    ) {
        self.init(
            contact: contact,
            contactAvatarHash: nil,
            multipleAccountLabelText: nil,
            recipientPhoneNumber: address.phoneNumber,
            recipientServiceId: address.serviceId
        )
    }
}

// MARK: - DB Operation Hooks

extension SignalAccount {

    public func anyDidInsert(transaction: SDSAnyWriteTransaction) {
        Self.modelReadCaches.signalAccountReadCache.didInsertOrUpdate(signalAccount: self, transaction: transaction)
        let searchableNameIndexer = DependenciesBridge.shared.searchableNameIndexer
        searchableNameIndexer.insert(self, tx: transaction.asV2Write)
    }

    public func anyDidUpdate(transaction: SDSAnyWriteTransaction) {
        Self.modelReadCaches.signalAccountReadCache.didInsertOrUpdate(signalAccount: self, transaction: transaction)
        let searchableNameIndexer = DependenciesBridge.shared.searchableNameIndexer
        searchableNameIndexer.update(self, tx: transaction.asV2Write)
    }

    public func anyDidRemove(transaction: SDSAnyWriteTransaction) {
        Self.modelReadCaches.signalAccountReadCache.didRemove(signalAccount: self, transaction: transaction)
    }

    public func anyDidFetchOne(transaction: SDSAnyReadTransaction) {
        Self.modelReadCaches.signalAccountReadCache.didReadSignalAccount(self, transaction: transaction)
    }

    public func anyDidEnumerateOne(transaction: SDSAnyReadTransaction) {
        Self.modelReadCaches.signalAccountReadCache.didReadSignalAccount(self, transaction: transaction)
    }
}

// MARK: - Contact Display Name

extension SignalAccount {
    /// Name components for the contact. No empty strings will be present. If a
    /// non-nil value is returned, it is guaranteed that at least one string in
    /// the components object is non-nil.
    public func contactNameComponents() -> PersonNameComponents? {
        var components = PersonNameComponents()
        if let firstName = self.contact?.firstName.strippedOrNil {
            components.givenName = firstName
        }
        if let lastName = self.contact?.lastName.strippedOrNil {
            components.familyName = lastName
        }

        if
            components.givenName == nil,
            components.familyName == nil,
            let fullName = self.contact?.fullName.strippedOrNil
        {
            components.givenName = fullName
        }

        if let nickname = self.contact?.nickname.strippedOrNil {
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

    /// Whether nicknames should be used.
    ///
    /// - SeeAlso: docs on``kSignalPreferNicknamesPreference``.
    public static func shouldUseNicknames(userDefaults: UserDefaults = .standard) -> Bool {
        userDefaults.bool(forKey: kSignalPreferNicknamesPreference)
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
        && contact?.cnContactId == otherAccount.contact?.cnContactId
        && Contact.areNamesEqual(contact, otherAccount.contact)
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

    @objc
    public func buildContactAvatarJpegData() -> Data? {
        guard
            let contact = self.contact,
            contact.isFromLocalAddressBook
        else {
            return nil
        }
        guard let cnContactId = contact.cnContactId else {
            owsFailDebug("Missing cnContactId.")
            return nil
        }
        guard let contactAvatarData = Self.contactsManager.avatarData(for: cnContactId) else {
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
            contact: self.contact,
            contactAvatarHash: self.contactAvatarHash,
            multipleAccountLabelText: self.multipleAccountLabelText,
            recipientPhoneNumber: self.recipientPhoneNumber,
            recipientServiceId: self.recipientServiceId
        )
    }
}
