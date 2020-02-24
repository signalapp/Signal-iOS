//
//  Copyright (c) 2020 Open Whisper Systems. All rights reserved.
//

import Foundation
import SignalCoreKit

// WARNING: This code is generated. Only edit within the markers.

public enum StorageServiceProtoError: Error {
    case invalidProtobuf(description: String)
}

// MARK: - StorageServiceProtoStorageItem

@objc
public class StorageServiceProtoStorageItem: NSObject {

    // MARK: - StorageServiceProtoStorageItemBuilder

    @objc
    public class func builder(key: Data, value: Data) -> StorageServiceProtoStorageItemBuilder {
        return StorageServiceProtoStorageItemBuilder(key: key, value: value)
    }

    // asBuilder() constructs a builder that reflects the proto's contents.
    @objc
    public func asBuilder() -> StorageServiceProtoStorageItemBuilder {
        let builder = StorageServiceProtoStorageItemBuilder(key: key, value: value)
        return builder
    }

    @objc
    public class StorageServiceProtoStorageItemBuilder: NSObject {

        private var proto = StorageServiceProtos_StorageItem()

        @objc
        fileprivate override init() {}

        @objc
        fileprivate init(key: Data, value: Data) {
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

        @objc
        public func build() throws -> StorageServiceProtoStorageItem {
            return try StorageServiceProtoStorageItem.parseProto(proto)
        }

        @objc
        public func buildSerializedData() throws -> Data {
            return try StorageServiceProtoStorageItem.parseProto(proto).serializedData()
        }
    }

    fileprivate let proto: StorageServiceProtos_StorageItem

    @objc
    public let key: Data

    @objc
    public let value: Data

    private init(proto: StorageServiceProtos_StorageItem,
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

    @objc
    public class func parseData(_ serializedData: Data) throws -> StorageServiceProtoStorageItem {
        let proto = try StorageServiceProtos_StorageItem(serializedData: serializedData)
        return try parseProto(proto)
    }

    fileprivate class func parseProto(_ proto: StorageServiceProtos_StorageItem) throws -> StorageServiceProtoStorageItem {
        guard proto.hasKey else {
            throw StorageServiceProtoError.invalidProtobuf(description: "\(logTag) missing required field: key")
        }
        let key = proto.key

        guard proto.hasValue else {
            throw StorageServiceProtoError.invalidProtobuf(description: "\(logTag) missing required field: value")
        }
        let value = proto.value

        // MARK: - Begin Validation Logic for StorageServiceProtoStorageItem -

        // MARK: - End Validation Logic for StorageServiceProtoStorageItem -

        let result = StorageServiceProtoStorageItem(proto: proto,
                                                    key: key,
                                                    value: value)
        return result
    }

    @objc
    public override var debugDescription: String {
        return "\(proto)"
    }
}

#if DEBUG

extension StorageServiceProtoStorageItem {
    @objc
    public func serializedDataIgnoringErrors() -> Data? {
        return try! self.serializedData()
    }
}

extension StorageServiceProtoStorageItem.StorageServiceProtoStorageItemBuilder {
    @objc
    public func buildIgnoringErrors() -> StorageServiceProtoStorageItem? {
        return try! self.build()
    }
}

#endif

// MARK: - StorageServiceProtoStorageManifest

@objc
public class StorageServiceProtoStorageManifest: NSObject {

    // MARK: - StorageServiceProtoStorageManifestBuilder

    @objc
    public class func builder(version: UInt64, value: Data) -> StorageServiceProtoStorageManifestBuilder {
        return StorageServiceProtoStorageManifestBuilder(version: version, value: value)
    }

    // asBuilder() constructs a builder that reflects the proto's contents.
    @objc
    public func asBuilder() -> StorageServiceProtoStorageManifestBuilder {
        let builder = StorageServiceProtoStorageManifestBuilder(version: version, value: value)
        return builder
    }

    @objc
    public class StorageServiceProtoStorageManifestBuilder: NSObject {

        private var proto = StorageServiceProtos_StorageManifest()

        @objc
        fileprivate override init() {}

        @objc
        fileprivate init(version: UInt64, value: Data) {
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

        @objc
        public func build() throws -> StorageServiceProtoStorageManifest {
            return try StorageServiceProtoStorageManifest.parseProto(proto)
        }

        @objc
        public func buildSerializedData() throws -> Data {
            return try StorageServiceProtoStorageManifest.parseProto(proto).serializedData()
        }
    }

    fileprivate let proto: StorageServiceProtos_StorageManifest

    @objc
    public let version: UInt64

    @objc
    public let value: Data

    private init(proto: StorageServiceProtos_StorageManifest,
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

    @objc
    public class func parseData(_ serializedData: Data) throws -> StorageServiceProtoStorageManifest {
        let proto = try StorageServiceProtos_StorageManifest(serializedData: serializedData)
        return try parseProto(proto)
    }

    fileprivate class func parseProto(_ proto: StorageServiceProtos_StorageManifest) throws -> StorageServiceProtoStorageManifest {
        guard proto.hasVersion else {
            throw StorageServiceProtoError.invalidProtobuf(description: "\(logTag) missing required field: version")
        }
        let version = proto.version

        guard proto.hasValue else {
            throw StorageServiceProtoError.invalidProtobuf(description: "\(logTag) missing required field: value")
        }
        let value = proto.value

        // MARK: - Begin Validation Logic for StorageServiceProtoStorageManifest -

        // MARK: - End Validation Logic for StorageServiceProtoStorageManifest -

        let result = StorageServiceProtoStorageManifest(proto: proto,
                                                        version: version,
                                                        value: value)
        return result
    }

    @objc
    public override var debugDescription: String {
        return "\(proto)"
    }
}

#if DEBUG

extension StorageServiceProtoStorageManifest {
    @objc
    public func serializedDataIgnoringErrors() -> Data? {
        return try! self.serializedData()
    }
}

extension StorageServiceProtoStorageManifest.StorageServiceProtoStorageManifestBuilder {
    @objc
    public func buildIgnoringErrors() -> StorageServiceProtoStorageManifest? {
        return try! self.build()
    }
}

#endif

// MARK: - StorageServiceProtoStorageItems

@objc
public class StorageServiceProtoStorageItems: NSObject {

    // MARK: - StorageServiceProtoStorageItemsBuilder

    @objc
    public class func builder() -> StorageServiceProtoStorageItemsBuilder {
        return StorageServiceProtoStorageItemsBuilder()
    }

    // asBuilder() constructs a builder that reflects the proto's contents.
    @objc
    public func asBuilder() -> StorageServiceProtoStorageItemsBuilder {
        let builder = StorageServiceProtoStorageItemsBuilder()
        builder.setItems(items)
        return builder
    }

    @objc
    public class StorageServiceProtoStorageItemsBuilder: NSObject {

        private var proto = StorageServiceProtos_StorageItems()

        @objc
        fileprivate override init() {}

        @objc
        public func addItems(_ valueParam: StorageServiceProtoStorageItem) {
            var items = proto.items
            items.append(valueParam.proto)
            proto.items = items
        }

        @objc
        public func setItems(_ wrappedItems: [StorageServiceProtoStorageItem]) {
            proto.items = wrappedItems.map { $0.proto }
        }

        @objc
        public func build() throws -> StorageServiceProtoStorageItems {
            return try StorageServiceProtoStorageItems.parseProto(proto)
        }

        @objc
        public func buildSerializedData() throws -> Data {
            return try StorageServiceProtoStorageItems.parseProto(proto).serializedData()
        }
    }

    fileprivate let proto: StorageServiceProtos_StorageItems

    @objc
    public let items: [StorageServiceProtoStorageItem]

    private init(proto: StorageServiceProtos_StorageItems,
                 items: [StorageServiceProtoStorageItem]) {
        self.proto = proto
        self.items = items
    }

    @objc
    public func serializedData() throws -> Data {
        return try self.proto.serializedData()
    }

    @objc
    public class func parseData(_ serializedData: Data) throws -> StorageServiceProtoStorageItems {
        let proto = try StorageServiceProtos_StorageItems(serializedData: serializedData)
        return try parseProto(proto)
    }

    fileprivate class func parseProto(_ proto: StorageServiceProtos_StorageItems) throws -> StorageServiceProtoStorageItems {
        var items: [StorageServiceProtoStorageItem] = []
        items = try proto.items.map { try StorageServiceProtoStorageItem.parseProto($0) }

        // MARK: - Begin Validation Logic for StorageServiceProtoStorageItems -

        // MARK: - End Validation Logic for StorageServiceProtoStorageItems -

        let result = StorageServiceProtoStorageItems(proto: proto,
                                                     items: items)
        return result
    }

    @objc
    public override var debugDescription: String {
        return "\(proto)"
    }
}

#if DEBUG

extension StorageServiceProtoStorageItems {
    @objc
    public func serializedDataIgnoringErrors() -> Data? {
        return try! self.serializedData()
    }
}

extension StorageServiceProtoStorageItems.StorageServiceProtoStorageItemsBuilder {
    @objc
    public func buildIgnoringErrors() -> StorageServiceProtoStorageItems? {
        return try! self.build()
    }
}

#endif

// MARK: - StorageServiceProtoReadOperation

@objc
public class StorageServiceProtoReadOperation: NSObject {

    // MARK: - StorageServiceProtoReadOperationBuilder

    @objc
    public class func builder() -> StorageServiceProtoReadOperationBuilder {
        return StorageServiceProtoReadOperationBuilder()
    }

    // asBuilder() constructs a builder that reflects the proto's contents.
    @objc
    public func asBuilder() -> StorageServiceProtoReadOperationBuilder {
        let builder = StorageServiceProtoReadOperationBuilder()
        builder.setReadKey(readKey)
        return builder
    }

    @objc
    public class StorageServiceProtoReadOperationBuilder: NSObject {

        private var proto = StorageServiceProtos_ReadOperation()

        @objc
        fileprivate override init() {}

        @objc
        public func addReadKey(_ valueParam: Data) {
            var items = proto.readKey
            items.append(valueParam)
            proto.readKey = items
        }

        @objc
        public func setReadKey(_ wrappedItems: [Data]) {
            proto.readKey = wrappedItems
        }

        @objc
        public func build() throws -> StorageServiceProtoReadOperation {
            return try StorageServiceProtoReadOperation.parseProto(proto)
        }

        @objc
        public func buildSerializedData() throws -> Data {
            return try StorageServiceProtoReadOperation.parseProto(proto).serializedData()
        }
    }

    fileprivate let proto: StorageServiceProtos_ReadOperation

    @objc
    public var readKey: [Data] {
        return proto.readKey
    }

    private init(proto: StorageServiceProtos_ReadOperation) {
        self.proto = proto
    }

    @objc
    public func serializedData() throws -> Data {
        return try self.proto.serializedData()
    }

    @objc
    public class func parseData(_ serializedData: Data) throws -> StorageServiceProtoReadOperation {
        let proto = try StorageServiceProtos_ReadOperation(serializedData: serializedData)
        return try parseProto(proto)
    }

    fileprivate class func parseProto(_ proto: StorageServiceProtos_ReadOperation) throws -> StorageServiceProtoReadOperation {
        // MARK: - Begin Validation Logic for StorageServiceProtoReadOperation -

        // MARK: - End Validation Logic for StorageServiceProtoReadOperation -

        let result = StorageServiceProtoReadOperation(proto: proto)
        return result
    }

    @objc
    public override var debugDescription: String {
        return "\(proto)"
    }
}

#if DEBUG

extension StorageServiceProtoReadOperation {
    @objc
    public func serializedDataIgnoringErrors() -> Data? {
        return try! self.serializedData()
    }
}

extension StorageServiceProtoReadOperation.StorageServiceProtoReadOperationBuilder {
    @objc
    public func buildIgnoringErrors() -> StorageServiceProtoReadOperation? {
        return try! self.build()
    }
}

#endif

// MARK: - StorageServiceProtoWriteOperation

@objc
public class StorageServiceProtoWriteOperation: NSObject {

    // MARK: - StorageServiceProtoWriteOperationBuilder

    @objc
    public class func builder() -> StorageServiceProtoWriteOperationBuilder {
        return StorageServiceProtoWriteOperationBuilder()
    }

    // asBuilder() constructs a builder that reflects the proto's contents.
    @objc
    public func asBuilder() -> StorageServiceProtoWriteOperationBuilder {
        let builder = StorageServiceProtoWriteOperationBuilder()
        if let _value = manifest {
            builder.setManifest(_value)
        }
        builder.setInsertItem(insertItem)
        builder.setDeleteKey(deleteKey)
        if hasDeleteAll {
            builder.setDeleteAll(deleteAll)
        }
        return builder
    }

    @objc
    public class StorageServiceProtoWriteOperationBuilder: NSObject {

        private var proto = StorageServiceProtos_WriteOperation()

        @objc
        fileprivate override init() {}

        @objc
        @available(swift, obsoleted: 1.0)
        public func setManifest(_ valueParam: StorageServiceProtoStorageManifest?) {
            guard let valueParam = valueParam else { return }
            proto.manifest = valueParam.proto
        }

        public func setManifest(_ valueParam: StorageServiceProtoStorageManifest) {
            proto.manifest = valueParam.proto
        }

        @objc
        public func addInsertItem(_ valueParam: StorageServiceProtoStorageItem) {
            var items = proto.insertItem
            items.append(valueParam.proto)
            proto.insertItem = items
        }

        @objc
        public func setInsertItem(_ wrappedItems: [StorageServiceProtoStorageItem]) {
            proto.insertItem = wrappedItems.map { $0.proto }
        }

        @objc
        public func addDeleteKey(_ valueParam: Data) {
            var items = proto.deleteKey
            items.append(valueParam)
            proto.deleteKey = items
        }

        @objc
        public func setDeleteKey(_ wrappedItems: [Data]) {
            proto.deleteKey = wrappedItems
        }

        @objc
        public func setDeleteAll(_ valueParam: Bool) {
            proto.deleteAll = valueParam
        }

        @objc
        public func build() throws -> StorageServiceProtoWriteOperation {
            return try StorageServiceProtoWriteOperation.parseProto(proto)
        }

        @objc
        public func buildSerializedData() throws -> Data {
            return try StorageServiceProtoWriteOperation.parseProto(proto).serializedData()
        }
    }

    fileprivate let proto: StorageServiceProtos_WriteOperation

    @objc
    public let manifest: StorageServiceProtoStorageManifest?

    @objc
    public let insertItem: [StorageServiceProtoStorageItem]

    @objc
    public var deleteKey: [Data] {
        return proto.deleteKey
    }

    @objc
    public var deleteAll: Bool {
        return proto.deleteAll
    }
    @objc
    public var hasDeleteAll: Bool {
        return proto.hasDeleteAll
    }

    private init(proto: StorageServiceProtos_WriteOperation,
                 manifest: StorageServiceProtoStorageManifest?,
                 insertItem: [StorageServiceProtoStorageItem]) {
        self.proto = proto
        self.manifest = manifest
        self.insertItem = insertItem
    }

    @objc
    public func serializedData() throws -> Data {
        return try self.proto.serializedData()
    }

    @objc
    public class func parseData(_ serializedData: Data) throws -> StorageServiceProtoWriteOperation {
        let proto = try StorageServiceProtos_WriteOperation(serializedData: serializedData)
        return try parseProto(proto)
    }

    fileprivate class func parseProto(_ proto: StorageServiceProtos_WriteOperation) throws -> StorageServiceProtoWriteOperation {
        var manifest: StorageServiceProtoStorageManifest?
        if proto.hasManifest {
            manifest = try StorageServiceProtoStorageManifest.parseProto(proto.manifest)
        }

        var insertItem: [StorageServiceProtoStorageItem] = []
        insertItem = try proto.insertItem.map { try StorageServiceProtoStorageItem.parseProto($0) }

        // MARK: - Begin Validation Logic for StorageServiceProtoWriteOperation -

        // MARK: - End Validation Logic for StorageServiceProtoWriteOperation -

        let result = StorageServiceProtoWriteOperation(proto: proto,
                                                       manifest: manifest,
                                                       insertItem: insertItem)
        return result
    }

    @objc
    public override var debugDescription: String {
        return "\(proto)"
    }
}

#if DEBUG

extension StorageServiceProtoWriteOperation {
    @objc
    public func serializedDataIgnoringErrors() -> Data? {
        return try! self.serializedData()
    }
}

extension StorageServiceProtoWriteOperation.StorageServiceProtoWriteOperationBuilder {
    @objc
    public func buildIgnoringErrors() -> StorageServiceProtoWriteOperation? {
        return try! self.build()
    }
}

#endif

// MARK: - StorageServiceProtoStorageRecordType

@objc
public enum StorageServiceProtoStorageRecordType: Int32 {
    case unknown = 0
    case contact = 1
    case groupv1 = 2
}

private func StorageServiceProtoStorageRecordTypeWrap(_ value: StorageServiceProtos_StorageRecord.TypeEnum) -> StorageServiceProtoStorageRecordType {
    switch value {
    case .unknown: return .unknown
    case .contact: return .contact
    case .groupv1: return .groupv1
    }
}

private func StorageServiceProtoStorageRecordTypeUnwrap(_ value: StorageServiceProtoStorageRecordType) -> StorageServiceProtos_StorageRecord.TypeEnum {
    switch value {
    case .unknown: return .unknown
    case .contact: return .contact
    case .groupv1: return .groupv1
    }
}

// MARK: - StorageServiceProtoStorageRecord

@objc
public class StorageServiceProtoStorageRecord: NSObject {

    // MARK: - StorageServiceProtoStorageRecordBuilder

    @objc
    public class func builder(type: UInt32) -> StorageServiceProtoStorageRecordBuilder {
        return StorageServiceProtoStorageRecordBuilder(type: type)
    }

    // asBuilder() constructs a builder that reflects the proto's contents.
    @objc
    public func asBuilder() -> StorageServiceProtoStorageRecordBuilder {
        let builder = StorageServiceProtoStorageRecordBuilder(type: type)
        if let _value = contact {
            builder.setContact(_value)
        }
        if let _value = groupV1 {
            builder.setGroupV1(_value)
        }
        return builder
    }

    @objc
    public class StorageServiceProtoStorageRecordBuilder: NSObject {

        private var proto = StorageServiceProtos_StorageRecord()

        @objc
        fileprivate override init() {}

        @objc
        fileprivate init(type: UInt32) {
            super.init()

            setType(type)
        }

        @objc
        public func setType(_ valueParam: UInt32) {
            proto.type = valueParam
        }

        @objc
        @available(swift, obsoleted: 1.0)
        public func setContact(_ valueParam: StorageServiceProtoContactRecord?) {
            guard let valueParam = valueParam else { return }
            proto.contact = valueParam.proto
        }

        public func setContact(_ valueParam: StorageServiceProtoContactRecord) {
            proto.contact = valueParam.proto
        }

        @objc
        @available(swift, obsoleted: 1.0)
        public func setGroupV1(_ valueParam: StorageServiceProtoGroupV1Record?) {
            guard let valueParam = valueParam else { return }
            proto.groupV1 = valueParam.proto
        }

        public func setGroupV1(_ valueParam: StorageServiceProtoGroupV1Record) {
            proto.groupV1 = valueParam.proto
        }

        @objc
        public func build() throws -> StorageServiceProtoStorageRecord {
            return try StorageServiceProtoStorageRecord.parseProto(proto)
        }

        @objc
        public func buildSerializedData() throws -> Data {
            return try StorageServiceProtoStorageRecord.parseProto(proto).serializedData()
        }
    }

    fileprivate let proto: StorageServiceProtos_StorageRecord

    @objc
    public let type: UInt32

    @objc
    public let contact: StorageServiceProtoContactRecord?

    @objc
    public let groupV1: StorageServiceProtoGroupV1Record?

    private init(proto: StorageServiceProtos_StorageRecord,
                 type: UInt32,
                 contact: StorageServiceProtoContactRecord?,
                 groupV1: StorageServiceProtoGroupV1Record?) {
        self.proto = proto
        self.type = type
        self.contact = contact
        self.groupV1 = groupV1
    }

    @objc
    public func serializedData() throws -> Data {
        return try self.proto.serializedData()
    }

    @objc
    public class func parseData(_ serializedData: Data) throws -> StorageServiceProtoStorageRecord {
        let proto = try StorageServiceProtos_StorageRecord(serializedData: serializedData)
        return try parseProto(proto)
    }

    fileprivate class func parseProto(_ proto: StorageServiceProtos_StorageRecord) throws -> StorageServiceProtoStorageRecord {
        guard proto.hasType else {
            throw StorageServiceProtoError.invalidProtobuf(description: "\(logTag) missing required field: type")
        }
        let type = proto.type

        var contact: StorageServiceProtoContactRecord?
        if proto.hasContact {
            contact = try StorageServiceProtoContactRecord.parseProto(proto.contact)
        }

        var groupV1: StorageServiceProtoGroupV1Record?
        if proto.hasGroupV1 {
            groupV1 = try StorageServiceProtoGroupV1Record.parseProto(proto.groupV1)
        }

        // MARK: - Begin Validation Logic for StorageServiceProtoStorageRecord -

        // MARK: - End Validation Logic for StorageServiceProtoStorageRecord -

        let result = StorageServiceProtoStorageRecord(proto: proto,
                                                      type: type,
                                                      contact: contact,
                                                      groupV1: groupV1)
        return result
    }

    @objc
    public override var debugDescription: String {
        return "\(proto)"
    }
}

#if DEBUG

extension StorageServiceProtoStorageRecord {
    @objc
    public func serializedDataIgnoringErrors() -> Data? {
        return try! self.serializedData()
    }
}

extension StorageServiceProtoStorageRecord.StorageServiceProtoStorageRecordBuilder {
    @objc
    public func buildIgnoringErrors() -> StorageServiceProtoStorageRecord? {
        return try! self.build()
    }
}

#endif

// MARK: - StorageServiceProtoContactRecordIdentityState

@objc
public enum StorageServiceProtoContactRecordIdentityState: Int32 {
    case `default` = 0
    case verified = 1
    case unverified = 2
}

private func StorageServiceProtoContactRecordIdentityStateWrap(_ value: StorageServiceProtos_ContactRecord.Identity.State) -> StorageServiceProtoContactRecordIdentityState {
    switch value {
    case .default: return .default
    case .verified: return .verified
    case .unverified: return .unverified
    }
}

private func StorageServiceProtoContactRecordIdentityStateUnwrap(_ value: StorageServiceProtoContactRecordIdentityState) -> StorageServiceProtos_ContactRecord.Identity.State {
    switch value {
    case .default: return .default
    case .verified: return .verified
    case .unverified: return .unverified
    }
}

// MARK: - StorageServiceProtoContactRecordIdentity

@objc
public class StorageServiceProtoContactRecordIdentity: NSObject {

    // MARK: - StorageServiceProtoContactRecordIdentityBuilder

    @objc
    public class func builder() -> StorageServiceProtoContactRecordIdentityBuilder {
        return StorageServiceProtoContactRecordIdentityBuilder()
    }

    // asBuilder() constructs a builder that reflects the proto's contents.
    @objc
    public func asBuilder() -> StorageServiceProtoContactRecordIdentityBuilder {
        let builder = StorageServiceProtoContactRecordIdentityBuilder()
        if let _value = key {
            builder.setKey(_value)
        }
        if let _value = state {
            builder.setState(_value)
        }
        return builder
    }

    @objc
    public class StorageServiceProtoContactRecordIdentityBuilder: NSObject {

        private var proto = StorageServiceProtos_ContactRecord.Identity()

        @objc
        fileprivate override init() {}

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

        @objc
        public func build() throws -> StorageServiceProtoContactRecordIdentity {
            return try StorageServiceProtoContactRecordIdentity.parseProto(proto)
        }

        @objc
        public func buildSerializedData() throws -> Data {
            return try StorageServiceProtoContactRecordIdentity.parseProto(proto).serializedData()
        }
    }

    fileprivate let proto: StorageServiceProtos_ContactRecord.Identity

    @objc
    public var key: Data? {
        guard hasKey else {
            return nil
        }
        return proto.key
    }
    @objc
    public var hasKey: Bool {
        return proto.hasKey
    }

    public var state: StorageServiceProtoContactRecordIdentityState? {
        guard hasState else {
            return nil
        }
        return StorageServiceProtoContactRecordIdentityStateWrap(proto.state)
    }
    // This "unwrapped" accessor should only be used if the "has value" accessor has already been checked.
    @objc
    public var unwrappedState: StorageServiceProtoContactRecordIdentityState {
        if !hasState {
            // TODO: We could make this a crashing assert.
            owsFailDebug("Unsafe unwrap of missing optional: Identity.state.")
        }
        return StorageServiceProtoContactRecordIdentityStateWrap(proto.state)
    }
    @objc
    public var hasState: Bool {
        return proto.hasState
    }

    private init(proto: StorageServiceProtos_ContactRecord.Identity) {
        self.proto = proto
    }

    @objc
    public func serializedData() throws -> Data {
        return try self.proto.serializedData()
    }

    @objc
    public class func parseData(_ serializedData: Data) throws -> StorageServiceProtoContactRecordIdentity {
        let proto = try StorageServiceProtos_ContactRecord.Identity(serializedData: serializedData)
        return try parseProto(proto)
    }

    fileprivate class func parseProto(_ proto: StorageServiceProtos_ContactRecord.Identity) throws -> StorageServiceProtoContactRecordIdentity {
        // MARK: - Begin Validation Logic for StorageServiceProtoContactRecordIdentity -

        // MARK: - End Validation Logic for StorageServiceProtoContactRecordIdentity -

        let result = StorageServiceProtoContactRecordIdentity(proto: proto)
        return result
    }

    @objc
    public override var debugDescription: String {
        return "\(proto)"
    }
}

#if DEBUG

extension StorageServiceProtoContactRecordIdentity {
    @objc
    public func serializedDataIgnoringErrors() -> Data? {
        return try! self.serializedData()
    }
}

extension StorageServiceProtoContactRecordIdentity.StorageServiceProtoContactRecordIdentityBuilder {
    @objc
    public func buildIgnoringErrors() -> StorageServiceProtoContactRecordIdentity? {
        return try! self.build()
    }
}

#endif

// MARK: - StorageServiceProtoContactRecordProfile

@objc
public class StorageServiceProtoContactRecordProfile: NSObject {

    // MARK: - StorageServiceProtoContactRecordProfileBuilder

    @objc
    public class func builder() -> StorageServiceProtoContactRecordProfileBuilder {
        return StorageServiceProtoContactRecordProfileBuilder()
    }

    // asBuilder() constructs a builder that reflects the proto's contents.
    @objc
    public func asBuilder() -> StorageServiceProtoContactRecordProfileBuilder {
        let builder = StorageServiceProtoContactRecordProfileBuilder()
        if let _value = givenName {
            builder.setGivenName(_value)
        }
        if let _value = key {
            builder.setKey(_value)
        }
        if let _value = username {
            builder.setUsername(_value)
        }
        if let _value = familyName {
            builder.setFamilyName(_value)
        }
        return builder
    }

    @objc
    public class StorageServiceProtoContactRecordProfileBuilder: NSObject {

        private var proto = StorageServiceProtos_ContactRecord.Profile()

        @objc
        fileprivate override init() {}

        @objc
        @available(swift, obsoleted: 1.0)
        public func setGivenName(_ valueParam: String?) {
            guard let valueParam = valueParam else { return }
            proto.givenName = valueParam
        }

        public func setGivenName(_ valueParam: String) {
            proto.givenName = valueParam
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
        public func setUsername(_ valueParam: String?) {
            guard let valueParam = valueParam else { return }
            proto.username = valueParam
        }

        public func setUsername(_ valueParam: String) {
            proto.username = valueParam
        }

        @objc
        @available(swift, obsoleted: 1.0)
        public func setFamilyName(_ valueParam: String?) {
            guard let valueParam = valueParam else { return }
            proto.familyName = valueParam
        }

        public func setFamilyName(_ valueParam: String) {
            proto.familyName = valueParam
        }

        @objc
        public func build() throws -> StorageServiceProtoContactRecordProfile {
            return try StorageServiceProtoContactRecordProfile.parseProto(proto)
        }

        @objc
        public func buildSerializedData() throws -> Data {
            return try StorageServiceProtoContactRecordProfile.parseProto(proto).serializedData()
        }
    }

    fileprivate let proto: StorageServiceProtos_ContactRecord.Profile

    @objc
    public var givenName: String? {
        guard hasGivenName else {
            return nil
        }
        return proto.givenName
    }
    @objc
    public var hasGivenName: Bool {
        return proto.hasGivenName
    }

    @objc
    public var key: Data? {
        guard hasKey else {
            return nil
        }
        return proto.key
    }
    @objc
    public var hasKey: Bool {
        return proto.hasKey
    }

    @objc
    public var username: String? {
        guard hasUsername else {
            return nil
        }
        return proto.username
    }
    @objc
    public var hasUsername: Bool {
        return proto.hasUsername
    }

    @objc
    public var familyName: String? {
        guard hasFamilyName else {
            return nil
        }
        return proto.familyName
    }
    @objc
    public var hasFamilyName: Bool {
        return proto.hasFamilyName
    }

    private init(proto: StorageServiceProtos_ContactRecord.Profile) {
        self.proto = proto
    }

    @objc
    public func serializedData() throws -> Data {
        return try self.proto.serializedData()
    }

    @objc
    public class func parseData(_ serializedData: Data) throws -> StorageServiceProtoContactRecordProfile {
        let proto = try StorageServiceProtos_ContactRecord.Profile(serializedData: serializedData)
        return try parseProto(proto)
    }

    fileprivate class func parseProto(_ proto: StorageServiceProtos_ContactRecord.Profile) throws -> StorageServiceProtoContactRecordProfile {
        // MARK: - Begin Validation Logic for StorageServiceProtoContactRecordProfile -

        // MARK: - End Validation Logic for StorageServiceProtoContactRecordProfile -

        let result = StorageServiceProtoContactRecordProfile(proto: proto)
        return result
    }

    @objc
    public override var debugDescription: String {
        return "\(proto)"
    }
}

#if DEBUG

extension StorageServiceProtoContactRecordProfile {
    @objc
    public func serializedDataIgnoringErrors() -> Data? {
        return try! self.serializedData()
    }
}

extension StorageServiceProtoContactRecordProfile.StorageServiceProtoContactRecordProfileBuilder {
    @objc
    public func buildIgnoringErrors() -> StorageServiceProtoContactRecordProfile? {
        return try! self.build()
    }
}

#endif

// MARK: - StorageServiceProtoContactRecord

@objc
public class StorageServiceProtoContactRecord: NSObject {

    // MARK: - StorageServiceProtoContactRecordBuilder

    @objc
    public class func builder() -> StorageServiceProtoContactRecordBuilder {
        return StorageServiceProtoContactRecordBuilder()
    }

    // asBuilder() constructs a builder that reflects the proto's contents.
    @objc
    public func asBuilder() -> StorageServiceProtoContactRecordBuilder {
        let builder = StorageServiceProtoContactRecordBuilder()
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
        if let _value = nickname {
            builder.setNickname(_value)
        }
        return builder
    }

    @objc
    public class StorageServiceProtoContactRecordBuilder: NSObject {

        private var proto = StorageServiceProtos_ContactRecord()

        @objc
        fileprivate override init() {}

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

        @objc
        @available(swift, obsoleted: 1.0)
        public func setNickname(_ valueParam: String?) {
            guard let valueParam = valueParam else { return }
            proto.nickname = valueParam
        }

        public func setNickname(_ valueParam: String) {
            proto.nickname = valueParam
        }

        @objc
        public func build() throws -> StorageServiceProtoContactRecord {
            return try StorageServiceProtoContactRecord.parseProto(proto)
        }

        @objc
        public func buildSerializedData() throws -> Data {
            return try StorageServiceProtoContactRecord.parseProto(proto).serializedData()
        }
    }

    fileprivate let proto: StorageServiceProtos_ContactRecord

    @objc
    public let profile: StorageServiceProtoContactRecordProfile?

    @objc
    public let identity: StorageServiceProtoContactRecordIdentity?

    @objc
    public var serviceUuid: String? {
        guard hasServiceUuid else {
            return nil
        }
        return proto.serviceUuid
    }
    @objc
    public var hasServiceUuid: Bool {
        return proto.hasServiceUuid
    }

    @objc
    public var serviceE164: String? {
        guard hasServiceE164 else {
            return nil
        }
        return proto.serviceE164
    }
    @objc
    public var hasServiceE164: Bool {
        return proto.hasServiceE164
    }

    @objc
    public var blocked: Bool {
        return proto.blocked
    }
    @objc
    public var hasBlocked: Bool {
        return proto.hasBlocked
    }

    @objc
    public var whitelisted: Bool {
        return proto.whitelisted
    }
    @objc
    public var hasWhitelisted: Bool {
        return proto.hasWhitelisted
    }

    @objc
    public var nickname: String? {
        guard hasNickname else {
            return nil
        }
        return proto.nickname
    }
    @objc
    public var hasNickname: Bool {
        return proto.hasNickname
    }

    @objc
    public var hasValidService: Bool {
        return serviceAddress != nil
    }
    @objc
    public var serviceAddress: SignalServiceAddress? {
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
                 profile: StorageServiceProtoContactRecordProfile?,
                 identity: StorageServiceProtoContactRecordIdentity?) {
        self.proto = proto
        self.profile = profile
        self.identity = identity
    }

    @objc
    public func serializedData() throws -> Data {
        return try self.proto.serializedData()
    }

    @objc
    public class func parseData(_ serializedData: Data) throws -> StorageServiceProtoContactRecord {
        let proto = try StorageServiceProtos_ContactRecord(serializedData: serializedData)
        return try parseProto(proto)
    }

    fileprivate class func parseProto(_ proto: StorageServiceProtos_ContactRecord) throws -> StorageServiceProtoContactRecord {
        var profile: StorageServiceProtoContactRecordProfile?
        if proto.hasProfile {
            profile = try StorageServiceProtoContactRecordProfile.parseProto(proto.profile)
        }

        var identity: StorageServiceProtoContactRecordIdentity?
        if proto.hasIdentity {
            identity = try StorageServiceProtoContactRecordIdentity.parseProto(proto.identity)
        }

        // MARK: - Begin Validation Logic for StorageServiceProtoContactRecord -

        // MARK: - End Validation Logic for StorageServiceProtoContactRecord -

        let result = StorageServiceProtoContactRecord(proto: proto,
                                                      profile: profile,
                                                      identity: identity)
        return result
    }

    @objc
    public override var debugDescription: String {
        return "\(proto)"
    }
}

#if DEBUG

extension StorageServiceProtoContactRecord {
    @objc
    public func serializedDataIgnoringErrors() -> Data? {
        return try! self.serializedData()
    }
}

extension StorageServiceProtoContactRecord.StorageServiceProtoContactRecordBuilder {
    @objc
    public func buildIgnoringErrors() -> StorageServiceProtoContactRecord? {
        return try! self.build()
    }
}

#endif

// MARK: - StorageServiceProtoGroupV1Record

@objc
public class StorageServiceProtoGroupV1Record: NSObject {

    // MARK: - StorageServiceProtoGroupV1RecordBuilder

    @objc
    public class func builder(id: Data) -> StorageServiceProtoGroupV1RecordBuilder {
        return StorageServiceProtoGroupV1RecordBuilder(id: id)
    }

    // asBuilder() constructs a builder that reflects the proto's contents.
    @objc
    public func asBuilder() -> StorageServiceProtoGroupV1RecordBuilder {
        let builder = StorageServiceProtoGroupV1RecordBuilder(id: id)
        if hasBlocked {
            builder.setBlocked(blocked)
        }
        if hasWhitelisted {
            builder.setWhitelisted(whitelisted)
        }
        return builder
    }

    @objc
    public class StorageServiceProtoGroupV1RecordBuilder: NSObject {

        private var proto = StorageServiceProtos_GroupV1Record()

        @objc
        fileprivate override init() {}

        @objc
        fileprivate init(id: Data) {
            super.init()

            setId(id)
        }

        @objc
        @available(swift, obsoleted: 1.0)
        public func setId(_ valueParam: Data?) {
            guard let valueParam = valueParam else { return }
            proto.id = valueParam
        }

        public func setId(_ valueParam: Data) {
            proto.id = valueParam
        }

        @objc
        public func setBlocked(_ valueParam: Bool) {
            proto.blocked = valueParam
        }

        @objc
        public func setWhitelisted(_ valueParam: Bool) {
            proto.whitelisted = valueParam
        }

        @objc
        public func build() throws -> StorageServiceProtoGroupV1Record {
            return try StorageServiceProtoGroupV1Record.parseProto(proto)
        }

        @objc
        public func buildSerializedData() throws -> Data {
            return try StorageServiceProtoGroupV1Record.parseProto(proto).serializedData()
        }
    }

    fileprivate let proto: StorageServiceProtos_GroupV1Record

    @objc
    public let id: Data

    @objc
    public var blocked: Bool {
        return proto.blocked
    }
    @objc
    public var hasBlocked: Bool {
        return proto.hasBlocked
    }

    @objc
    public var whitelisted: Bool {
        return proto.whitelisted
    }
    @objc
    public var hasWhitelisted: Bool {
        return proto.hasWhitelisted
    }

    private init(proto: StorageServiceProtos_GroupV1Record,
                 id: Data) {
        self.proto = proto
        self.id = id
    }

    @objc
    public func serializedData() throws -> Data {
        return try self.proto.serializedData()
    }

    @objc
    public class func parseData(_ serializedData: Data) throws -> StorageServiceProtoGroupV1Record {
        let proto = try StorageServiceProtos_GroupV1Record(serializedData: serializedData)
        return try parseProto(proto)
    }

    fileprivate class func parseProto(_ proto: StorageServiceProtos_GroupV1Record) throws -> StorageServiceProtoGroupV1Record {
        guard proto.hasID else {
            throw StorageServiceProtoError.invalidProtobuf(description: "\(logTag) missing required field: id")
        }
        let id = proto.id

        // MARK: - Begin Validation Logic for StorageServiceProtoGroupV1Record -

        // MARK: - End Validation Logic for StorageServiceProtoGroupV1Record -

        let result = StorageServiceProtoGroupV1Record(proto: proto,
                                                      id: id)
        return result
    }

    @objc
    public override var debugDescription: String {
        return "\(proto)"
    }
}

#if DEBUG

extension StorageServiceProtoGroupV1Record {
    @objc
    public func serializedDataIgnoringErrors() -> Data? {
        return try! self.serializedData()
    }
}

extension StorageServiceProtoGroupV1Record.StorageServiceProtoGroupV1RecordBuilder {
    @objc
    public func buildIgnoringErrors() -> StorageServiceProtoGroupV1Record? {
        return try! self.build()
    }
}

#endif

// MARK: - StorageServiceProtoManifestRecord

@objc
public class StorageServiceProtoManifestRecord: NSObject {

    // MARK: - StorageServiceProtoManifestRecordBuilder

    @objc
    public class func builder(version: UInt64) -> StorageServiceProtoManifestRecordBuilder {
        return StorageServiceProtoManifestRecordBuilder(version: version)
    }

    // asBuilder() constructs a builder that reflects the proto's contents.
    @objc
    public func asBuilder() -> StorageServiceProtoManifestRecordBuilder {
        let builder = StorageServiceProtoManifestRecordBuilder(version: version)
        builder.setKeys(keys)
        return builder
    }

    @objc
    public class StorageServiceProtoManifestRecordBuilder: NSObject {

        private var proto = StorageServiceProtos_ManifestRecord()

        @objc
        fileprivate override init() {}

        @objc
        fileprivate init(version: UInt64) {
            super.init()

            setVersion(version)
        }

        @objc
        public func setVersion(_ valueParam: UInt64) {
            proto.version = valueParam
        }

        @objc
        public func addKeys(_ valueParam: Data) {
            var items = proto.keys
            items.append(valueParam)
            proto.keys = items
        }

        @objc
        public func setKeys(_ wrappedItems: [Data]) {
            proto.keys = wrappedItems
        }

        @objc
        public func build() throws -> StorageServiceProtoManifestRecord {
            return try StorageServiceProtoManifestRecord.parseProto(proto)
        }

        @objc
        public func buildSerializedData() throws -> Data {
            return try StorageServiceProtoManifestRecord.parseProto(proto).serializedData()
        }
    }

    fileprivate let proto: StorageServiceProtos_ManifestRecord

    @objc
    public let version: UInt64

    @objc
    public var keys: [Data] {
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

    @objc
    public class func parseData(_ serializedData: Data) throws -> StorageServiceProtoManifestRecord {
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

    @objc
    public override var debugDescription: String {
        return "\(proto)"
    }
}

#if DEBUG

extension StorageServiceProtoManifestRecord {
    @objc
    public func serializedDataIgnoringErrors() -> Data? {
        return try! self.serializedData()
    }
}

extension StorageServiceProtoManifestRecord.StorageServiceProtoManifestRecordBuilder {
    @objc
    public func buildIgnoringErrors() -> StorageServiceProtoManifestRecord? {
        return try! self.build()
    }
}

#endif
