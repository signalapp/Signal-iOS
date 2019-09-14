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

        @objc
        @available(swift, obsoleted: 1.0)
        public func setKey(_ valueParam: Data?) {
            guard let valueParam = valueParam else { return }
            proto.key = valueParam
        }

        public func setKey(_ valueParam: Data) {
            proto.key = valueParam
        }

        @objc
        @available(swift, obsoleted: 1.0)
        public func setValue(_ valueParam: Data?) {
            guard let valueParam = valueParam else { return }
            proto.value = valueParam
        }

        public func setValue(_ valueParam: Data) {
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

        @objc
        public func setVersion(_ valueParam: UInt64) {
            proto.version = valueParam
        }

        @objc
        @available(swift, obsoleted: 1.0)
        public func setValue(_ valueParam: Data?) {
            guard let valueParam = valueParam else { return }
            proto.value = valueParam
        }

        public func setValue(_ valueParam: Data) {
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

        @objc
        @available(swift, obsoleted: 1.0)
        public func setManifest(_ valueParam: StorageServiceProtoContactsManifest?) {
            guard let valueParam = valueParam else { return }
            proto.manifest = valueParam.proto
        }

        public func setManifest(_ valueParam: StorageServiceProtoContactsManifest) {
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

// MARK: - StorageServiceProtoContactRecordIdentity

@objc public class StorageServiceProtoContactRecordIdentity: NSObject {

    // MARK: - StorageServiceProtoContactRecordIdentityState

    @objc public enum StorageServiceProtoContactRecordIdentityState: Int32 {
        case `default` = 0
        case verified = 1
        case unverified = 2
    }

    private class func StorageServiceProtoContactRecordIdentityStateWrap(_ value: StorageServiceProtos_ContactRecord.Identity.State) -> StorageServiceProtoContactRecordIdentityState {
        switch value {
        case .default: return .default
        case .verified: return .verified
        case .unverified: return .unverified
        }
    }

    private class func StorageServiceProtoContactRecordIdentityStateUnwrap(_ value: StorageServiceProtoContactRecordIdentityState) -> StorageServiceProtos_ContactRecord.Identity.State {
        switch value {
        case .default: return .default
        case .verified: return .verified
        case .unverified: return .unverified
        }
    }

    // MARK: - StorageServiceProtoContactRecordIdentityBuilder

    @objc public class func builder() -> StorageServiceProtoContactRecordIdentityBuilder {
        return StorageServiceProtoContactRecordIdentityBuilder()
    }

    // asBuilder() constructs a builder that reflects the proto's contents.
    @objc public func asBuilder() -> StorageServiceProtoContactRecordIdentityBuilder {
        let builder = StorageServiceProtoContactRecordIdentityBuilder()
        if let _value = key {
            builder.setKey(_value)
        }
        if let _value = state {
            builder.setState(_value)
        }
        return builder
    }

    @objc public class StorageServiceProtoContactRecordIdentityBuilder: NSObject {

        private var proto = StorageServiceProtos_ContactRecord.Identity()

        @objc fileprivate override init() {}

        @objc
        @available(swift, obsoleted: 1.0)
        public func setKey(_ valueParam: Data?) {
            guard let valueParam = valueParam else { return }
            proto.key = valueParam
        }

        public func setKey(_ valueParam: Data) {
            proto.key = valueParam
        }

        @objc
        public func setState(_ valueParam: StorageServiceProtoContactRecordIdentityState) {
            proto.state = StorageServiceProtoContactRecordIdentityStateUnwrap(valueParam)
        }

        @objc public func build() throws -> StorageServiceProtoContactRecordIdentity {
            return try StorageServiceProtoContactRecordIdentity.parseProto(proto)
        }

        @objc public func buildSerializedData() throws -> Data {
            return try StorageServiceProtoContactRecordIdentity.parseProto(proto).serializedData()
        }
    }

    fileprivate let proto: StorageServiceProtos_ContactRecord.Identity

    @objc public var key: Data? {
        guard proto.hasKey else {
            return nil
        }
        return proto.key
    }
    @objc public var hasKey: Bool {
        return proto.hasKey
    }

    public var state: StorageServiceProtoContactRecordIdentityState? {
        guard proto.hasState else {
            return nil
        }
        return StorageServiceProtoContactRecordIdentity.StorageServiceProtoContactRecordIdentityStateWrap(proto.state)
    }
    // This "unwrapped" accessor should only be used if the "has value" accessor has already been checked.
    @objc public var unwrappedState: StorageServiceProtoContactRecordIdentityState {
        if !hasState {
            // TODO: We could make this a crashing assert.
            owsFailDebug("Unsafe unwrap of missing optional: Identity.state.")
        }
        return StorageServiceProtoContactRecordIdentity.StorageServiceProtoContactRecordIdentityStateWrap(proto.state)
    }
    @objc public var hasState: Bool {
        return proto.hasState
    }

    private init(proto: StorageServiceProtos_ContactRecord.Identity) {
        self.proto = proto
    }

    @objc
    public func serializedData() throws -> Data {
        return try self.proto.serializedData()
    }

    @objc public class func parseData(_ serializedData: Data) throws -> StorageServiceProtoContactRecordIdentity {
        let proto = try StorageServiceProtos_ContactRecord.Identity(serializedData: serializedData)
        return try parseProto(proto)
    }

    fileprivate class func parseProto(_ proto: StorageServiceProtos_ContactRecord.Identity) throws -> StorageServiceProtoContactRecordIdentity {
        // MARK: - Begin Validation Logic for StorageServiceProtoContactRecordIdentity -

        // MARK: - End Validation Logic for StorageServiceProtoContactRecordIdentity -

        let result = StorageServiceProtoContactRecordIdentity(proto: proto)
        return result
    }

    @objc public override var debugDescription: String {
        return "\(proto)"
    }
}

#if DEBUG

extension StorageServiceProtoContactRecordIdentity {
    @objc public func serializedDataIgnoringErrors() -> Data? {
        return try! self.serializedData()
    }
}

extension StorageServiceProtoContactRecordIdentity.StorageServiceProtoContactRecordIdentityBuilder {
    @objc public func buildIgnoringErrors() -> StorageServiceProtoContactRecordIdentity? {
        return try! self.build()
    }
}

#endif

// MARK: - StorageServiceProtoContactRecordProfile

@objc public class StorageServiceProtoContactRecordProfile: NSObject {

    // MARK: - StorageServiceProtoContactRecordProfileBuilder

    @objc public class func builder() -> StorageServiceProtoContactRecordProfileBuilder {
        return StorageServiceProtoContactRecordProfileBuilder()
    }

    // asBuilder() constructs a builder that reflects the proto's contents.
    @objc public func asBuilder() -> StorageServiceProtoContactRecordProfileBuilder {
        let builder = StorageServiceProtoContactRecordProfileBuilder()
        if let _value = name {
            builder.setName(_value)
        }
        if let _value = key {
            builder.setKey(_value)
        }
        if let _value = avatar {
            builder.setAvatar(_value)
        }
        return builder
    }

    @objc public class StorageServiceProtoContactRecordProfileBuilder: NSObject {

        private var proto = StorageServiceProtos_ContactRecord.Profile()

        @objc fileprivate override init() {}

        @objc
        @available(swift, obsoleted: 1.0)
        public func setName(_ valueParam: String?) {
            guard let valueParam = valueParam else { return }
            proto.name = valueParam
        }

        public func setName(_ valueParam: String) {
            proto.name = valueParam
        }

        @objc
        @available(swift, obsoleted: 1.0)
        public func setKey(_ valueParam: Data?) {
            guard let valueParam = valueParam else { return }
            proto.key = valueParam
        }

        public func setKey(_ valueParam: Data) {
            proto.key = valueParam
        }

        @objc
        @available(swift, obsoleted: 1.0)
        public func setAvatar(_ valueParam: Data?) {
            guard let valueParam = valueParam else { return }
            proto.avatar = valueParam
        }

        public func setAvatar(_ valueParam: Data) {
            proto.avatar = valueParam
        }

        @objc public func build() throws -> StorageServiceProtoContactRecordProfile {
            return try StorageServiceProtoContactRecordProfile.parseProto(proto)
        }

        @objc public func buildSerializedData() throws -> Data {
            return try StorageServiceProtoContactRecordProfile.parseProto(proto).serializedData()
        }
    }

    fileprivate let proto: StorageServiceProtos_ContactRecord.Profile

    @objc public var name: String? {
        guard proto.hasName else {
            return nil
        }
        return proto.name
    }
    @objc public var hasName: Bool {
        return proto.hasName
    }

    @objc public var key: Data? {
        guard proto.hasKey else {
            return nil
        }
        return proto.key
    }
    @objc public var hasKey: Bool {
        return proto.hasKey
    }

    @objc public var avatar: Data? {
        guard proto.hasAvatar else {
            return nil
        }
        return proto.avatar
    }
    @objc public var hasAvatar: Bool {
        return proto.hasAvatar
    }

    private init(proto: StorageServiceProtos_ContactRecord.Profile) {
        self.proto = proto
    }

    @objc
    public func serializedData() throws -> Data {
        return try self.proto.serializedData()
    }

    @objc public class func parseData(_ serializedData: Data) throws -> StorageServiceProtoContactRecordProfile {
        let proto = try StorageServiceProtos_ContactRecord.Profile(serializedData: serializedData)
        return try parseProto(proto)
    }

    fileprivate class func parseProto(_ proto: StorageServiceProtos_ContactRecord.Profile) throws -> StorageServiceProtoContactRecordProfile {
        // MARK: - Begin Validation Logic for StorageServiceProtoContactRecordProfile -

        // MARK: - End Validation Logic for StorageServiceProtoContactRecordProfile -

        let result = StorageServiceProtoContactRecordProfile(proto: proto)
        return result
    }

    @objc public override var debugDescription: String {
        return "\(proto)"
    }
}

#if DEBUG

extension StorageServiceProtoContactRecordProfile {
    @objc public func serializedDataIgnoringErrors() -> Data? {
        return try! self.serializedData()
    }
}

extension StorageServiceProtoContactRecordProfile.StorageServiceProtoContactRecordProfileBuilder {
    @objc public func buildIgnoringErrors() -> StorageServiceProtoContactRecordProfile? {
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
        if let _value = profile {
            builder.setProfile(_value)
        }
        if let _value = identity {
            builder.setIdentity(_value)
        }
        if hasBlocked {
            builder.setBlocked(blocked)
        }
        if hasWhitelisted {
            builder.setWhitelisted(whitelisted)
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

        @objc
        @available(swift, obsoleted: 1.0)
        public func setKey(_ valueParam: Data?) {
            guard let valueParam = valueParam else { return }
            proto.key = valueParam
        }

        public func setKey(_ valueParam: Data) {
            proto.key = valueParam
        }

        @objc
        @available(swift, obsoleted: 1.0)
        public func setServiceUuid(_ valueParam: String?) {
            guard let valueParam = valueParam else { return }
            proto.serviceUuid = valueParam
        }

        public func setServiceUuid(_ valueParam: String) {
            proto.serviceUuid = valueParam
        }

        @objc
        @available(swift, obsoleted: 1.0)
        public func setServiceE164(_ valueParam: String?) {
            guard let valueParam = valueParam else { return }
            proto.serviceE164 = valueParam
        }

        public func setServiceE164(_ valueParam: String) {
            proto.serviceE164 = valueParam
        }

        @objc
        @available(swift, obsoleted: 1.0)
        public func setProfile(_ valueParam: StorageServiceProtoContactRecordProfile?) {
            guard let valueParam = valueParam else { return }
            proto.profile = valueParam.proto
        }

        public func setProfile(_ valueParam: StorageServiceProtoContactRecordProfile) {
            proto.profile = valueParam.proto
        }

        @objc
        @available(swift, obsoleted: 1.0)
        public func setIdentity(_ valueParam: StorageServiceProtoContactRecordIdentity?) {
            guard let valueParam = valueParam else { return }
            proto.identity = valueParam.proto
        }

        public func setIdentity(_ valueParam: StorageServiceProtoContactRecordIdentity) {
            proto.identity = valueParam.proto
        }

        @objc
        public func setBlocked(_ valueParam: Bool) {
            proto.blocked = valueParam
        }

        @objc
        public func setWhitelisted(_ valueParam: Bool) {
            proto.whitelisted = valueParam
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

    @objc public let profile: StorageServiceProtoContactRecordProfile?

    @objc public let identity: StorageServiceProtoContactRecordIdentity?

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

    @objc public var blocked: Bool {
        return proto.blocked
    }
    @objc public var hasBlocked: Bool {
        return proto.hasBlocked
    }

    @objc public var whitelisted: Bool {
        return proto.whitelisted
    }
    @objc public var hasWhitelisted: Bool {
        return proto.hasWhitelisted
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
                 key: Data,
                 profile: StorageServiceProtoContactRecordProfile?,
                 identity: StorageServiceProtoContactRecordIdentity?) {
        self.proto = proto
        self.key = key
        self.profile = profile
        self.identity = identity
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

        var profile: StorageServiceProtoContactRecordProfile? = nil
        if proto.hasProfile {
            profile = try StorageServiceProtoContactRecordProfile.parseProto(proto.profile)
        }

        var identity: StorageServiceProtoContactRecordIdentity? = nil
        if proto.hasIdentity {
            identity = try StorageServiceProtoContactRecordIdentity.parseProto(proto.identity)
        }

        // MARK: - Begin Validation Logic for StorageServiceProtoContactRecord -

        // MARK: - End Validation Logic for StorageServiceProtoContactRecord -

        let result = StorageServiceProtoContactRecord(proto: proto,
                                                      key: key,
                                                      profile: profile,
                                                      identity: identity)
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

        @objc
        public func setVersion(_ valueParam: UInt64) {
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
