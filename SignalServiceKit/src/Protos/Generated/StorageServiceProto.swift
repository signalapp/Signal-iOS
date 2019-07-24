//
//  Copyright (c) 2019 Open Whisper Systems. All rights reserved.
//

import Foundation
import SignalCoreKit

// WARNING: This code is generated. Only edit within the markers.

public enum StorageServiceProtoError: Error {
    case invalidProtobuf(description: String)
}

// MARK: - StorageServiceProtoContact

@objc public class StorageServiceProtoContact: NSObject {

    // MARK: - StorageServiceProtoContactBuilder

    @objc public class func builder(key: Data, value: Data) -> StorageServiceProtoContactBuilder {
        return StorageServiceProtoContactBuilder(key: key, value: value)
    }

    // asBuilder() constructs a builder that reflects the proto's contents.
    @objc public func asBuilder() -> StorageServiceProtoContactBuilder {
        let builder = StorageServiceProtoContactBuilder(key: key, value: value)
        return builder
    }

    @objc public class StorageServiceProtoContactBuilder: NSObject {

        private var proto = StorageServiceProtos_Contact()

        @objc fileprivate override init() {}

        @objc fileprivate init(key: Data, value: Data) {
            super.init()

            setKey(key)
            setValue(value)
        }

        @objc public func setKey(_ valueParam: Data) {
            proto.key = valueParam
        }

        @objc public func setValue(_ valueParam: Data) {
            proto.value = valueParam
        }

        @objc public func build() throws -> StorageServiceProtoContact {
            return try StorageServiceProtoContact.parseProto(proto)
        }

        @objc public func buildSerializedData() throws -> Data {
            return try StorageServiceProtoContact.parseProto(proto).serializedData()
        }
    }

    fileprivate let proto: StorageServiceProtos_Contact

    @objc public let key: Data

    @objc public let value: Data

    private init(proto: StorageServiceProtos_Contact,
                 key: Data,
                 value: Data) {
        self.proto = proto
        self.key = key
        self.value = value
    }

    @objc
    public func serializedData() throws -> Data {
        return try self.proto.serializedData()
    }

    @objc public class func parseData(_ serializedData: Data) throws -> StorageServiceProtoContact {
        let proto = try StorageServiceProtos_Contact(serializedData: serializedData)
        return try parseProto(proto)
    }

    fileprivate class func parseProto(_ proto: StorageServiceProtos_Contact) throws -> StorageServiceProtoContact {
        guard proto.hasKey else {
            throw StorageServiceProtoError.invalidProtobuf(description: "\(logTag) missing required field: key")
        }
        let key = proto.key

        guard proto.hasValue else {
            throw StorageServiceProtoError.invalidProtobuf(description: "\(logTag) missing required field: value")
        }
        let value = proto.value

        // MARK: - Begin Validation Logic for StorageServiceProtoContact -

        // MARK: - End Validation Logic for StorageServiceProtoContact -

        let result = StorageServiceProtoContact(proto: proto,
                                                key: key,
                                                value: value)
        return result
    }

    @objc public override var debugDescription: String {
        return "\(proto)"
    }
}

#if DEBUG

extension StorageServiceProtoContact {
    @objc public func serializedDataIgnoringErrors() -> Data? {
        return try! self.serializedData()
    }
}

extension StorageServiceProtoContact.StorageServiceProtoContactBuilder {
    @objc public func buildIgnoringErrors() -> StorageServiceProtoContact? {
        return try! self.build()
    }
}

#endif

// MARK: - StorageServiceProtoContacts

@objc public class StorageServiceProtoContacts: NSObject {

    // MARK: - StorageServiceProtoContactsBuilder

    @objc public class func builder() -> StorageServiceProtoContactsBuilder {
        return StorageServiceProtoContactsBuilder()
    }

    // asBuilder() constructs a builder that reflects the proto's contents.
    @objc public func asBuilder() -> StorageServiceProtoContactsBuilder {
        let builder = StorageServiceProtoContactsBuilder()
        builder.setContacts(contacts)
        return builder
    }

    @objc public class StorageServiceProtoContactsBuilder: NSObject {

        private var proto = StorageServiceProtos_Contacts()

        @objc fileprivate override init() {}

        @objc public func addContacts(_ valueParam: StorageServiceProtoContact) {
            var items = proto.contacts
            items.append(valueParam.proto)
            proto.contacts = items
        }

        @objc public func setContacts(_ wrappedItems: [StorageServiceProtoContact]) {
            proto.contacts = wrappedItems.map { $0.proto }
        }

        @objc public func build() throws -> StorageServiceProtoContacts {
            return try StorageServiceProtoContacts.parseProto(proto)
        }

        @objc public func buildSerializedData() throws -> Data {
            return try StorageServiceProtoContacts.parseProto(proto).serializedData()
        }
    }

    fileprivate let proto: StorageServiceProtos_Contacts

    @objc public let contacts: [StorageServiceProtoContact]

    private init(proto: StorageServiceProtos_Contacts,
                 contacts: [StorageServiceProtoContact]) {
        self.proto = proto
        self.contacts = contacts
    }

    @objc
    public func serializedData() throws -> Data {
        return try self.proto.serializedData()
    }

    @objc public class func parseData(_ serializedData: Data) throws -> StorageServiceProtoContacts {
        let proto = try StorageServiceProtos_Contacts(serializedData: serializedData)
        return try parseProto(proto)
    }

    fileprivate class func parseProto(_ proto: StorageServiceProtos_Contacts) throws -> StorageServiceProtoContacts {
        var contacts: [StorageServiceProtoContact] = []
        contacts = try proto.contacts.map { try StorageServiceProtoContact.parseProto($0) }

        // MARK: - Begin Validation Logic for StorageServiceProtoContacts -

        // MARK: - End Validation Logic for StorageServiceProtoContacts -

        let result = StorageServiceProtoContacts(proto: proto,
                                                 contacts: contacts)
        return result
    }

    @objc public override var debugDescription: String {
        return "\(proto)"
    }
}

#if DEBUG

extension StorageServiceProtoContacts {
    @objc public func serializedDataIgnoringErrors() -> Data? {
        return try! self.serializedData()
    }
}

extension StorageServiceProtoContacts.StorageServiceProtoContactsBuilder {
    @objc public func buildIgnoringErrors() -> StorageServiceProtoContacts? {
        return try! self.build()
    }
}

#endif

// MARK: - StorageServiceProtoContactsManifest

@objc public class StorageServiceProtoContactsManifest: NSObject {

    // MARK: - StorageServiceProtoContactsManifestBuilder

    @objc public class func builder(version: UInt64, value: Data) -> StorageServiceProtoContactsManifestBuilder {
        return StorageServiceProtoContactsManifestBuilder(version: version, value: value)
    }

    // asBuilder() constructs a builder that reflects the proto's contents.
    @objc public func asBuilder() -> StorageServiceProtoContactsManifestBuilder {
        let builder = StorageServiceProtoContactsManifestBuilder(version: version, value: value)
        return builder
    }

    @objc public class StorageServiceProtoContactsManifestBuilder: NSObject {

        private var proto = StorageServiceProtos_ContactsManifest()

        @objc fileprivate override init() {}

        @objc fileprivate init(version: UInt64, value: Data) {
            super.init()

            setVersion(version)
            setValue(value)
        }

        @objc public func setVersion(_ valueParam: UInt64) {
            proto.version = valueParam
        }

        @objc public func setValue(_ valueParam: Data) {
            proto.value = valueParam
        }

        @objc public func build() throws -> StorageServiceProtoContactsManifest {
            return try StorageServiceProtoContactsManifest.parseProto(proto)
        }

        @objc public func buildSerializedData() throws -> Data {
            return try StorageServiceProtoContactsManifest.parseProto(proto).serializedData()
        }
    }

    fileprivate let proto: StorageServiceProtos_ContactsManifest

    @objc public let version: UInt64

    @objc public let value: Data

    private init(proto: StorageServiceProtos_ContactsManifest,
                 version: UInt64,
                 value: Data) {
        self.proto = proto
        self.version = version
        self.value = value
    }

    @objc
    public func serializedData() throws -> Data {
        return try self.proto.serializedData()
    }

    @objc public class func parseData(_ serializedData: Data) throws -> StorageServiceProtoContactsManifest {
        let proto = try StorageServiceProtos_ContactsManifest(serializedData: serializedData)
        return try parseProto(proto)
    }

    fileprivate class func parseProto(_ proto: StorageServiceProtos_ContactsManifest) throws -> StorageServiceProtoContactsManifest {
        guard proto.hasVersion else {
            throw StorageServiceProtoError.invalidProtobuf(description: "\(logTag) missing required field: version")
        }
        let version = proto.version

        guard proto.hasValue else {
            throw StorageServiceProtoError.invalidProtobuf(description: "\(logTag) missing required field: value")
        }
        let value = proto.value

        // MARK: - Begin Validation Logic for StorageServiceProtoContactsManifest -

        // MARK: - End Validation Logic for StorageServiceProtoContactsManifest -

        let result = StorageServiceProtoContactsManifest(proto: proto,
                                                         version: version,
                                                         value: value)
        return result
    }

    @objc public override var debugDescription: String {
        return "\(proto)"
    }
}

#if DEBUG

extension StorageServiceProtoContactsManifest {
    @objc public func serializedDataIgnoringErrors() -> Data? {
        return try! self.serializedData()
    }
}

extension StorageServiceProtoContactsManifest.StorageServiceProtoContactsManifestBuilder {
    @objc public func buildIgnoringErrors() -> StorageServiceProtoContactsManifest? {
        return try! self.build()
    }
}

#endif

// MARK: - StorageServiceProtoReadOperation

@objc public class StorageServiceProtoReadOperation: NSObject {

    // MARK: - StorageServiceProtoReadOperationBuilder

    @objc public class func builder() -> StorageServiceProtoReadOperationBuilder {
        return StorageServiceProtoReadOperationBuilder()
    }

    // asBuilder() constructs a builder that reflects the proto's contents.
    @objc public func asBuilder() -> StorageServiceProtoReadOperationBuilder {
        let builder = StorageServiceProtoReadOperationBuilder()
        builder.setReadKey(readKey)
        return builder
    }

    @objc public class StorageServiceProtoReadOperationBuilder: NSObject {

        private var proto = StorageServiceProtos_ReadOperation()

        @objc fileprivate override init() {}

        @objc public func addReadKey(_ valueParam: Data) {
            var items = proto.readKey
            items.append(valueParam)
            proto.readKey = items
        }

        @objc public func setReadKey(_ wrappedItems: [Data]) {
            proto.readKey = wrappedItems
        }

        @objc public func build() throws -> StorageServiceProtoReadOperation {
            return try StorageServiceProtoReadOperation.parseProto(proto)
        }

        @objc public func buildSerializedData() throws -> Data {
            return try StorageServiceProtoReadOperation.parseProto(proto).serializedData()
        }
    }

    fileprivate let proto: StorageServiceProtos_ReadOperation

    @objc public var readKey: [Data] {
        return proto.readKey
    }

    private init(proto: StorageServiceProtos_ReadOperation) {
        self.proto = proto
    }

    @objc
    public func serializedData() throws -> Data {
        return try self.proto.serializedData()
    }

    @objc public class func parseData(_ serializedData: Data) throws -> StorageServiceProtoReadOperation {
        let proto = try StorageServiceProtos_ReadOperation(serializedData: serializedData)
        return try parseProto(proto)
    }

    fileprivate class func parseProto(_ proto: StorageServiceProtos_ReadOperation) throws -> StorageServiceProtoReadOperation {
        // MARK: - Begin Validation Logic for StorageServiceProtoReadOperation -

        // MARK: - End Validation Logic for StorageServiceProtoReadOperation -

        let result = StorageServiceProtoReadOperation(proto: proto)
        return result
    }

    @objc public override var debugDescription: String {
        return "\(proto)"
    }
}

#if DEBUG

extension StorageServiceProtoReadOperation {
    @objc public func serializedDataIgnoringErrors() -> Data? {
        return try! self.serializedData()
    }
}

extension StorageServiceProtoReadOperation.StorageServiceProtoReadOperationBuilder {
    @objc public func buildIgnoringErrors() -> StorageServiceProtoReadOperation? {
        return try! self.build()
    }
}

#endif

// MARK: - StorageServiceProtoWriteOperation

@objc public class StorageServiceProtoWriteOperation: NSObject {

    // MARK: - StorageServiceProtoWriteOperationBuilder

    @objc public class func builder() -> StorageServiceProtoWriteOperationBuilder {
        return StorageServiceProtoWriteOperationBuilder()
    }

    // asBuilder() constructs a builder that reflects the proto's contents.
    @objc public func asBuilder() -> StorageServiceProtoWriteOperationBuilder {
        let builder = StorageServiceProtoWriteOperationBuilder()
        if let _value = manifest {
            builder.setManifest(_value)
        }
        builder.setInsertContact(insertContact)
        builder.setDeleteKey(deleteKey)
        return builder
    }

    @objc public class StorageServiceProtoWriteOperationBuilder: NSObject {

        private var proto = StorageServiceProtos_WriteOperation()

        @objc fileprivate override init() {}

        @objc public func setManifest(_ valueParam: StorageServiceProtoContactsManifest) {
            proto.manifest = valueParam.proto
        }

        @objc public func addInsertContact(_ valueParam: StorageServiceProtoContact) {
            var items = proto.insertContact
            items.append(valueParam.proto)
            proto.insertContact = items
        }

        @objc public func setInsertContact(_ wrappedItems: [StorageServiceProtoContact]) {
            proto.insertContact = wrappedItems.map { $0.proto }
        }

        @objc public func addDeleteKey(_ valueParam: Data) {
            var items = proto.deleteKey
            items.append(valueParam)
            proto.deleteKey = items
        }

        @objc public func setDeleteKey(_ wrappedItems: [Data]) {
            proto.deleteKey = wrappedItems
        }

        @objc public func build() throws -> StorageServiceProtoWriteOperation {
            return try StorageServiceProtoWriteOperation.parseProto(proto)
        }

        @objc public func buildSerializedData() throws -> Data {
            return try StorageServiceProtoWriteOperation.parseProto(proto).serializedData()
        }
    }

    fileprivate let proto: StorageServiceProtos_WriteOperation

    @objc public let manifest: StorageServiceProtoContactsManifest?

    @objc public let insertContact: [StorageServiceProtoContact]

    @objc public var deleteKey: [Data] {
        return proto.deleteKey
    }

    private init(proto: StorageServiceProtos_WriteOperation,
                 manifest: StorageServiceProtoContactsManifest?,
                 insertContact: [StorageServiceProtoContact]) {
        self.proto = proto
        self.manifest = manifest
        self.insertContact = insertContact
    }

    @objc
    public func serializedData() throws -> Data {
        return try self.proto.serializedData()
    }

    @objc public class func parseData(_ serializedData: Data) throws -> StorageServiceProtoWriteOperation {
        let proto = try StorageServiceProtos_WriteOperation(serializedData: serializedData)
        return try parseProto(proto)
    }

    fileprivate class func parseProto(_ proto: StorageServiceProtos_WriteOperation) throws -> StorageServiceProtoWriteOperation {
        var manifest: StorageServiceProtoContactsManifest? = nil
        if proto.hasManifest {
            manifest = try StorageServiceProtoContactsManifest.parseProto(proto.manifest)
        }

        var insertContact: [StorageServiceProtoContact] = []
        insertContact = try proto.insertContact.map { try StorageServiceProtoContact.parseProto($0) }

        // MARK: - Begin Validation Logic for StorageServiceProtoWriteOperation -

        // MARK: - End Validation Logic for StorageServiceProtoWriteOperation -

        let result = StorageServiceProtoWriteOperation(proto: proto,
                                                       manifest: manifest,
                                                       insertContact: insertContact)
        return result
    }

    @objc public override var debugDescription: String {
        return "\(proto)"
    }
}

#if DEBUG

extension StorageServiceProtoWriteOperation {
    @objc public func serializedDataIgnoringErrors() -> Data? {
        return try! self.serializedData()
    }
}

extension StorageServiceProtoWriteOperation.StorageServiceProtoWriteOperationBuilder {
    @objc public func buildIgnoringErrors() -> StorageServiceProtoWriteOperation? {
        return try! self.build()
    }
}

#endif

// MARK: - StorageServiceProtoContactRecord

@objc public class StorageServiceProtoContactRecord: NSObject {

    // MARK: - StorageServiceProtoContactRecordBuilder

    @objc public class func builder(key: Data) -> StorageServiceProtoContactRecordBuilder {
        return StorageServiceProtoContactRecordBuilder(key: key)
    }

    // asBuilder() constructs a builder that reflects the proto's contents.
    @objc public func asBuilder() -> StorageServiceProtoContactRecordBuilder {
        let builder = StorageServiceProtoContactRecordBuilder(key: key)
        if let _value = serviceUuid {
            builder.setServiceUuid(_value)
        }
        if let _value = serviceE164 {
            builder.setServiceE164(_value)
        }
        if let _value = profileName {
            builder.setProfileName(_value)
        }
        if let _value = profileAvatar {
            builder.setProfileAvatar(_value)
        }
        if let _value = profileKey {
            builder.setProfileKey(_value)
        }
        if let _value = conversationColor {
            builder.setConversationColor(_value)
        }
        if hasConversationTimer {
            builder.setConversationTimer(conversationTimer)
        }
        if let _value = notificationTone {
            builder.setNotificationTone(_value)
        }
        if let _value = identityKey {
            builder.setIdentityKey(_value)
        }
        if hasVerified {
            builder.setVerified(verified)
        }
        if hasBlocked {
            builder.setBlocked(blocked)
        }
        return builder
    }

    @objc public class StorageServiceProtoContactRecordBuilder: NSObject {

        private var proto = StorageServiceProtos_ContactRecord()

        @objc fileprivate override init() {}

        @objc fileprivate init(key: Data) {
            super.init()

            setKey(key)
        }

        @objc public func setKey(_ valueParam: Data) {
            proto.key = valueParam
        }

        @objc public func setServiceUuid(_ valueParam: String) {
            proto.serviceUuid = valueParam
        }

        @objc public func setServiceE164(_ valueParam: String) {
            proto.serviceE164 = valueParam
        }

        @objc public func setProfileName(_ valueParam: String) {
            proto.profileName = valueParam
        }

        @objc public func setProfileAvatar(_ valueParam: Data) {
            proto.profileAvatar = valueParam
        }

        @objc public func setProfileKey(_ valueParam: Data) {
            proto.profileKey = valueParam
        }

        @objc public func setConversationColor(_ valueParam: String) {
            proto.conversationColor = valueParam
        }

        @objc public func setConversationTimer(_ valueParam: UInt32) {
            proto.conversationTimer = valueParam
        }

        @objc public func setNotificationTone(_ valueParam: String) {
            proto.notificationTone = valueParam
        }

        @objc public func setIdentityKey(_ valueParam: Data) {
            proto.identityKey = valueParam
        }

        @objc public func setVerified(_ valueParam: Bool) {
            proto.verified = valueParam
        }

        @objc public func setBlocked(_ valueParam: Bool) {
            proto.blocked = valueParam
        }

        @objc public func build() throws -> StorageServiceProtoContactRecord {
            return try StorageServiceProtoContactRecord.parseProto(proto)
        }

        @objc public func buildSerializedData() throws -> Data {
            return try StorageServiceProtoContactRecord.parseProto(proto).serializedData()
        }
    }

    fileprivate let proto: StorageServiceProtos_ContactRecord

    @objc public let key: Data

    @objc public var serviceUuid: String? {
        guard proto.hasServiceUuid else {
            return nil
        }
        return proto.serviceUuid
    }
    @objc public var hasServiceUuid: Bool {
        return proto.hasServiceUuid
    }

    @objc public var serviceE164: String? {
        guard proto.hasServiceE164 else {
            return nil
        }
        return proto.serviceE164
    }
    @objc public var hasServiceE164: Bool {
        return proto.hasServiceE164
    }

    @objc public var profileName: String? {
        guard proto.hasProfileName else {
            return nil
        }
        return proto.profileName
    }
    @objc public var hasProfileName: Bool {
        return proto.hasProfileName
    }

    @objc public var profileAvatar: Data? {
        guard proto.hasProfileAvatar else {
            return nil
        }
        return proto.profileAvatar
    }
    @objc public var hasProfileAvatar: Bool {
        return proto.hasProfileAvatar
    }

    @objc public var profileKey: Data? {
        guard proto.hasProfileKey else {
            return nil
        }
        return proto.profileKey
    }
    @objc public var hasProfileKey: Bool {
        return proto.hasProfileKey
    }

    @objc public var conversationColor: String? {
        guard proto.hasConversationColor else {
            return nil
        }
        return proto.conversationColor
    }
    @objc public var hasConversationColor: Bool {
        return proto.hasConversationColor
    }

    @objc public var conversationTimer: UInt32 {
        return proto.conversationTimer
    }
    @objc public var hasConversationTimer: Bool {
        return proto.hasConversationTimer
    }

    @objc public var notificationTone: String? {
        guard proto.hasNotificationTone else {
            return nil
        }
        return proto.notificationTone
    }
    @objc public var hasNotificationTone: Bool {
        return proto.hasNotificationTone
    }

    @objc public var identityKey: Data? {
        guard proto.hasIdentityKey else {
            return nil
        }
        return proto.identityKey
    }
    @objc public var hasIdentityKey: Bool {
        return proto.hasIdentityKey
    }

    @objc public var verified: Bool {
        return proto.verified
    }
    @objc public var hasVerified: Bool {
        return proto.hasVerified
    }

    @objc public var blocked: Bool {
        return proto.blocked
    }
    @objc public var hasBlocked: Bool {
        return proto.hasBlocked
    }

    @objc public var hasValidService: Bool {
        return serviceAddress != nil
    }
    @objc public var serviceAddress: SignalServiceAddress? {
        guard hasServiceE164 || hasServiceUuid else { return nil }

        let uuidString: String? = {
            guard hasServiceUuid else { return nil }

            guard let serviceUuid = serviceUuid else {
                owsFailDebug("serviceUuid was unexpectedly nil")
                return nil
            }

            return serviceUuid
        }()

        let phoneNumber: String? = {
            guard hasServiceE164 else {
                // Shouldn’t happen in prod yet
                assert(FeatureFlags.allowUUIDOnlyContacts)
                return nil
            }

            guard let serviceE164 = serviceE164 else {
                owsFailDebug("serviceE164 was unexpectedly nil")
                return nil
            }

            guard !serviceE164.isEmpty else {
                owsFailDebug("serviceE164 was unexpectedly empty")
                return nil
            }

            return serviceE164
        }()

        let address = SignalServiceAddress(uuidString: uuidString, phoneNumber: phoneNumber)
        guard address.isValid else {
            owsFailDebug("address was unexpectedly invalid")
            return nil
        }

        return address
    }

    private init(proto: StorageServiceProtos_ContactRecord,
                 key: Data) {
        self.proto = proto
        self.key = key
    }

    @objc
    public func serializedData() throws -> Data {
        return try self.proto.serializedData()
    }

    @objc public class func parseData(_ serializedData: Data) throws -> StorageServiceProtoContactRecord {
        let proto = try StorageServiceProtos_ContactRecord(serializedData: serializedData)
        return try parseProto(proto)
    }

    fileprivate class func parseProto(_ proto: StorageServiceProtos_ContactRecord) throws -> StorageServiceProtoContactRecord {
        guard proto.hasKey else {
            throw StorageServiceProtoError.invalidProtobuf(description: "\(logTag) missing required field: key")
        }
        let key = proto.key

        // MARK: - Begin Validation Logic for StorageServiceProtoContactRecord -

        // MARK: - End Validation Logic for StorageServiceProtoContactRecord -

        let result = StorageServiceProtoContactRecord(proto: proto,
                                                      key: key)
        return result
    }

    @objc public override var debugDescription: String {
        return "\(proto)"
    }
}

#if DEBUG

extension StorageServiceProtoContactRecord {
    @objc public func serializedDataIgnoringErrors() -> Data? {
        return try! self.serializedData()
    }
}

extension StorageServiceProtoContactRecord.StorageServiceProtoContactRecordBuilder {
    @objc public func buildIgnoringErrors() -> StorageServiceProtoContactRecord? {
        return try! self.build()
    }
}

#endif

// MARK: - StorageServiceProtoManifestRecord

@objc public class StorageServiceProtoManifestRecord: NSObject {

    // MARK: - StorageServiceProtoManifestRecordBuilder

    @objc public class func builder(version: UInt64) -> StorageServiceProtoManifestRecordBuilder {
        return StorageServiceProtoManifestRecordBuilder(version: version)
    }

    // asBuilder() constructs a builder that reflects the proto's contents.
    @objc public func asBuilder() -> StorageServiceProtoManifestRecordBuilder {
        let builder = StorageServiceProtoManifestRecordBuilder(version: version)
        builder.setKeys(keys)
        return builder
    }

    @objc public class StorageServiceProtoManifestRecordBuilder: NSObject {

        private var proto = StorageServiceProtos_ManifestRecord()

        @objc fileprivate override init() {}

        @objc fileprivate init(version: UInt64) {
            super.init()

            setVersion(version)
        }

        @objc public func setVersion(_ valueParam: UInt64) {
            proto.version = valueParam
        }

        @objc public func addKeys(_ valueParam: Data) {
            var items = proto.keys
            items.append(valueParam)
            proto.keys = items
        }

        @objc public func setKeys(_ wrappedItems: [Data]) {
            proto.keys = wrappedItems
        }

        @objc public func build() throws -> StorageServiceProtoManifestRecord {
            return try StorageServiceProtoManifestRecord.parseProto(proto)
        }

        @objc public func buildSerializedData() throws -> Data {
            return try StorageServiceProtoManifestRecord.parseProto(proto).serializedData()
        }
    }

    fileprivate let proto: StorageServiceProtos_ManifestRecord

    @objc public let version: UInt64

    @objc public var keys: [Data] {
        return proto.keys
    }

    private init(proto: StorageServiceProtos_ManifestRecord,
                 version: UInt64) {
        self.proto = proto
        self.version = version
    }

    @objc
    public func serializedData() throws -> Data {
        return try self.proto.serializedData()
    }

    @objc public class func parseData(_ serializedData: Data) throws -> StorageServiceProtoManifestRecord {
        let proto = try StorageServiceProtos_ManifestRecord(serializedData: serializedData)
        return try parseProto(proto)
    }

    fileprivate class func parseProto(_ proto: StorageServiceProtos_ManifestRecord) throws -> StorageServiceProtoManifestRecord {
        guard proto.hasVersion else {
            throw StorageServiceProtoError.invalidProtobuf(description: "\(logTag) missing required field: version")
        }
        let version = proto.version

        // MARK: - Begin Validation Logic for StorageServiceProtoManifestRecord -

        // MARK: - End Validation Logic for StorageServiceProtoManifestRecord -

        let result = StorageServiceProtoManifestRecord(proto: proto,
                                                       version: version)
        return result
    }

    @objc public override var debugDescription: String {
        return "\(proto)"
    }
}

#if DEBUG

extension StorageServiceProtoManifestRecord {
    @objc public func serializedDataIgnoringErrors() -> Data? {
        return try! self.serializedData()
    }
}

extension StorageServiceProtoManifestRecord.StorageServiceProtoManifestRecordBuilder {
    @objc public func buildIgnoringErrors() -> StorageServiceProtoManifestRecord? {
        return try! self.build()
    }
}

#endif
