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
    public static var ftsIndexMode: TSFTSIndexMode { .always }

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

// MARK: DB Operation Hooks

extension SignalAccount {

    public func anyDidInsert(transaction: SDSAnyWriteTransaction) {
        Self.modelReadCaches.signalAccountReadCache.didInsertOrUpdate(signalAccount: self, transaction: transaction)
    }

    public func anyDidUpdate(transaction: SDSAnyWriteTransaction) {
        Self.modelReadCaches.signalAccountReadCache.didInsertOrUpdate(signalAccount: self, transaction: transaction)
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

    /// The display name to use for the contact.
    ///
    /// - Returns: A non-empty string or nil.
    public func contactPreferredDisplayName(userDefaults: UserDefaults = UserDefaults.standard) -> String? {
        guard let components = contactPersonNameComponents(userDefaults: userDefaults) else {
            return nil
        }
        if let nickname = components.nickname {
            return nickname
        } else {
            return OWSFormat.formatNameComponents(components).displayStringIfNonEmpty
        }
    }

    /// Name components for the contact. Each name string in the resulting
    /// components object has been processed for display. No empty strings
    /// will be present. If a non-nil value is returned, it is guaranteed
    /// that at least one string in the components object is non-nil.
    @objc
    public func contactPersonNameComponents(userDefaults: UserDefaults = UserDefaults.standard) -> PersonNameComponents? {
        var components = PersonNameComponents()
        if let firstName = contactFirstName {
            components.givenName = firstName
        }
        if let lastName = contactLastName {
            components.familyName = lastName
        }

        if
            components.givenName == nil,
            components.familyName == nil,
            let fullName = self.contact?.fullName.displayStringIfNonEmpty
        {
            components.givenName = fullName
        }

        if let nickname = self.contactNicknameIfAvailable(userDefaults: userDefaults) {
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

    /// The contact's nickname if it exists, is non-empty, and is preferred.
    ///
    /// - SeeAlso: ``shouldUseNicknames``.
    /// - Note:
    /// `userDefaults` parameter should only be set to something other than
    /// the default value in testing.
    @objc
    public func contactNicknameIfAvailable(userDefaults: UserDefaults = UserDefaults.standard) -> String? {
        guard
            self.shouldUseNicknames(userDefaults: userDefaults),
            let nickname = self.contact?.nickname,
            !nickname.isEmpty
        else {
            return nil
        }
        return nickname.displayStringIfNonEmpty
    }

    /// The contact's full name, processed for display.
    ///
    /// - Returns: A non-empty string or nil.
    public var contactFullName: String? {
        guard let components = contactPersonNameComponents() else {
            return nil
        }

        return OWSFormat.formatNameComponents(components).displayStringIfNonEmpty
    }

    /// The contact's first name, processed for display.
    ///
    /// - Returns: A non-empty string or nil.
    public var contactFirstName: String? {
        return self.contact?.firstName?.displayStringIfNonEmpty
    }

    /// The contact's last name, processed for display.
    ///
    /// - Returns: A non-empty string or nil.
    public var contactLastName: String? {
        return self.contact?.lastName?.displayStringIfNonEmpty
    }

    /// Whether nicknames should be used.
    ///
    /// - SeeAlso: docs on``kSignalPreferNicknamesPreference``.
    private func shouldUseNicknames(userDefaults: UserDefaults) -> Bool {
        userDefaults.bool(forKey: kSignalPreferNicknamesPreference)
    }
}

// MARK: - SignalServiceAddress

extension SignalAccount {

    @objc
    public var recipientAddress: SignalServiceAddress {
        SignalServiceAddress(serviceId: recipientServiceId, phoneNumber: recipientPhoneNumber)
    }

    public var addressComponentsDescription: String {
        recipientAddress.description
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
        && contactHasSameContent(otherAccount.contact)
    }

    private func contactHasSameContent(_ otherContact: Contact?) -> Bool {
        if let contact, let otherContact {
            return contact.hasSameContent(otherContact)
        } else {
            return contact == nil && otherContact == nil
        }
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
        guard let contactAvatarData = Self.contactsManager.avatarData(forCNContactId: cnContactId) else {
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

// MARK: - Testing

#if TESTABLE_BUILD

public extension SignalAccount {
    func replaceContactForTests(_ contact: Contact?) {
        self.contact = contact
    }
}

public extension UserDefaults {
    func setNicknamePreferred(isPreferred: Bool) {
        self.set(isPreferred, forKey: kSignalPreferNicknamesPreference)
    }
}

#endif
