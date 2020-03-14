//
//  Copyright (c) 2020 Open Whisper Systems. All rights reserved.
//

import Foundation
import SignalCoreKit
import SwiftProtobuf

// WARNING: This code is generated. Only edit within the markers.

public enum StorageServiceProtoError: Error {
    case invalidProtobuf(description: String)
}

// MARK: - StorageServiceProtoStorageItem

public class StorageServiceProtoStorageItem: NSObject {

    // MARK: - StorageServiceProtoStorageItemBuilder

    public class func builder(key: Data, value: Data) -> StorageServiceProtoStorageItemBuilder {
        return StorageServiceProtoStorageItemBuilder(key: key, value: value)
    }

    // asBuilder() constructs a builder that reflects the proto's contents.
    public func asBuilder() -> StorageServiceProtoStorageItemBuilder {
        let builder = StorageServiceProtoStorageItemBuilder(key: key, value: value)
        return builder
    }

    public class StorageServiceProtoStorageItemBuilder: NSObject {

        private var proto = StorageServiceProtos_StorageItem()

        fileprivate override init() {}

        fileprivate init(key: Data, value: Data) {
            super.init()

            setKey(key)
            setValue(value)
        }

        @available(swift, obsoleted: 1.0)
        public func setKey(_ valueParam: Data?) {
            guard let valueParam = valueParam else { return }
            proto.key = valueParam
        }

        public func setKey(_ valueParam: Data) {
            proto.key = valueParam
        }

        @available(swift, obsoleted: 1.0)
        public func setValue(_ valueParam: Data?) {
            guard let valueParam = valueParam else { return }
            proto.value = valueParam
        }

        public func setValue(_ valueParam: Data) {
            proto.value = valueParam
        }

        public func build() throws -> StorageServiceProtoStorageItem {
            return try StorageServiceProtoStorageItem.parseProto(proto)
        }

        public func buildSerializedData() throws -> Data {
            return try StorageServiceProtoStorageItem.parseProto(proto).serializedData()
        }
    }

    fileprivate let proto: StorageServiceProtos_StorageItem

    public let key: Data

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

    public class func parseData(_ serializedData: Data) throws -> StorageServiceProtoStorageItem {
        let proto = try StorageServiceProtos_StorageItem(serializedData: serializedData)
        return try parseProto(proto)
    }

    fileprivate class func parseProto(_ proto: StorageServiceProtos_StorageItem) throws -> StorageServiceProtoStorageItem {
        let key = proto.key

        let value = proto.value

        // MARK: - Begin Validation Logic for StorageServiceProtoStorageItem -

        // MARK: - End Validation Logic for StorageServiceProtoStorageItem -

        let result = StorageServiceProtoStorageItem(proto: proto,
                                                    key: key,
                                                    value: value)
        return result
    }

    public override var debugDescription: String {
        return "\(proto)"
    }
}

#if DEBUG

extension StorageServiceProtoStorageItem {
    public func serializedDataIgnoringErrors() -> Data? {
        return try! self.serializedData()
    }
}

extension StorageServiceProtoStorageItem.StorageServiceProtoStorageItemBuilder {
    public func buildIgnoringErrors() -> StorageServiceProtoStorageItem? {
        return try! self.build()
    }
}

#endif

// MARK: - StorageServiceProtoStorageItems

public class StorageServiceProtoStorageItems: NSObject {

    // MARK: - StorageServiceProtoStorageItemsBuilder

    public class func builder() -> StorageServiceProtoStorageItemsBuilder {
        return StorageServiceProtoStorageItemsBuilder()
    }

    // asBuilder() constructs a builder that reflects the proto's contents.
    public func asBuilder() -> StorageServiceProtoStorageItemsBuilder {
        let builder = StorageServiceProtoStorageItemsBuilder()
        builder.setItems(items)
        return builder
    }

    public class StorageServiceProtoStorageItemsBuilder: NSObject {

        private var proto = StorageServiceProtos_StorageItems()

        fileprivate override init() {}

        public func addItems(_ valueParam: StorageServiceProtoStorageItem) {
            var items = proto.items
            items.append(valueParam.proto)
            proto.items = items
        }

        public func setItems(_ wrappedItems: [StorageServiceProtoStorageItem]) {
            proto.items = wrappedItems.map { $0.proto }
        }

        public func build() throws -> StorageServiceProtoStorageItems {
            return try StorageServiceProtoStorageItems.parseProto(proto)
        }

        public func buildSerializedData() throws -> Data {
            return try StorageServiceProtoStorageItems.parseProto(proto).serializedData()
        }
    }

    fileprivate let proto: StorageServiceProtos_StorageItems

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

    public override var debugDescription: String {
        return "\(proto)"
    }
}

#if DEBUG

extension StorageServiceProtoStorageItems {
    public func serializedDataIgnoringErrors() -> Data? {
        return try! self.serializedData()
    }
}

extension StorageServiceProtoStorageItems.StorageServiceProtoStorageItemsBuilder {
    public func buildIgnoringErrors() -> StorageServiceProtoStorageItems? {
        return try! self.build()
    }
}

#endif

// MARK: - StorageServiceProtoStorageManifest

public class StorageServiceProtoStorageManifest: NSObject {

    // MARK: - StorageServiceProtoStorageManifestBuilder

    public class func builder(version: UInt64, value: Data) -> StorageServiceProtoStorageManifestBuilder {
        return StorageServiceProtoStorageManifestBuilder(version: version, value: value)
    }

    // asBuilder() constructs a builder that reflects the proto's contents.
    public func asBuilder() -> StorageServiceProtoStorageManifestBuilder {
        let builder = StorageServiceProtoStorageManifestBuilder(version: version, value: value)
        return builder
    }

    public class StorageServiceProtoStorageManifestBuilder: NSObject {

        private var proto = StorageServiceProtos_StorageManifest()

        fileprivate override init() {}

        fileprivate init(version: UInt64, value: Data) {
            super.init()

            setVersion(version)
            setValue(value)
        }

        public func setVersion(_ valueParam: UInt64) {
            proto.version = valueParam
        }

        @available(swift, obsoleted: 1.0)
        public func setValue(_ valueParam: Data?) {
            guard let valueParam = valueParam else { return }
            proto.value = valueParam
        }

        public func setValue(_ valueParam: Data) {
            proto.value = valueParam
        }

        public func build() throws -> StorageServiceProtoStorageManifest {
            return try StorageServiceProtoStorageManifest.parseProto(proto)
        }

        public func buildSerializedData() throws -> Data {
            return try StorageServiceProtoStorageManifest.parseProto(proto).serializedData()
        }
    }

    fileprivate let proto: StorageServiceProtos_StorageManifest

    public let version: UInt64

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

    public class func parseData(_ serializedData: Data) throws -> StorageServiceProtoStorageManifest {
        let proto = try StorageServiceProtos_StorageManifest(serializedData: serializedData)
        return try parseProto(proto)
    }

    fileprivate class func parseProto(_ proto: StorageServiceProtos_StorageManifest) throws -> StorageServiceProtoStorageManifest {
        let version = proto.version

        let value = proto.value

        // MARK: - Begin Validation Logic for StorageServiceProtoStorageManifest -

        // MARK: - End Validation Logic for StorageServiceProtoStorageManifest -

        let result = StorageServiceProtoStorageManifest(proto: proto,
                                                        version: version,
                                                        value: value)
        return result
    }

    public override var debugDescription: String {
        return "\(proto)"
    }
}

#if DEBUG

extension StorageServiceProtoStorageManifest {
    public func serializedDataIgnoringErrors() -> Data? {
        return try! self.serializedData()
    }
}

extension StorageServiceProtoStorageManifest.StorageServiceProtoStorageManifestBuilder {
    public func buildIgnoringErrors() -> StorageServiceProtoStorageManifest? {
        return try! self.build()
    }
}

#endif

// MARK: - StorageServiceProtoReadOperation

public class StorageServiceProtoReadOperation: NSObject {

    // MARK: - StorageServiceProtoReadOperationBuilder

    public class func builder() -> StorageServiceProtoReadOperationBuilder {
        return StorageServiceProtoReadOperationBuilder()
    }

    // asBuilder() constructs a builder that reflects the proto's contents.
    public func asBuilder() -> StorageServiceProtoReadOperationBuilder {
        let builder = StorageServiceProtoReadOperationBuilder()
        builder.setReadKey(readKey)
        return builder
    }

    public class StorageServiceProtoReadOperationBuilder: NSObject {

        private var proto = StorageServiceProtos_ReadOperation()

        fileprivate override init() {}

        public func addReadKey(_ valueParam: Data) {
            var items = proto.readKey
            items.append(valueParam)
            proto.readKey = items
        }

        public func setReadKey(_ wrappedItems: [Data]) {
            proto.readKey = wrappedItems
        }

        public func build() throws -> StorageServiceProtoReadOperation {
            return try StorageServiceProtoReadOperation.parseProto(proto)
        }

        public func buildSerializedData() throws -> Data {
            return try StorageServiceProtoReadOperation.parseProto(proto).serializedData()
        }
    }

    fileprivate let proto: StorageServiceProtos_ReadOperation

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

    public override var debugDescription: String {
        return "\(proto)"
    }
}

#if DEBUG

extension StorageServiceProtoReadOperation {
    public func serializedDataIgnoringErrors() -> Data? {
        return try! self.serializedData()
    }
}

extension StorageServiceProtoReadOperation.StorageServiceProtoReadOperationBuilder {
    public func buildIgnoringErrors() -> StorageServiceProtoReadOperation? {
        return try! self.build()
    }
}

#endif

// MARK: - StorageServiceProtoWriteOperation

public class StorageServiceProtoWriteOperation: NSObject {

    // MARK: - StorageServiceProtoWriteOperationBuilder

    public class func builder() -> StorageServiceProtoWriteOperationBuilder {
        return StorageServiceProtoWriteOperationBuilder()
    }

    // asBuilder() constructs a builder that reflects the proto's contents.
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

    public class StorageServiceProtoWriteOperationBuilder: NSObject {

        private var proto = StorageServiceProtos_WriteOperation()

        fileprivate override init() {}

        @available(swift, obsoleted: 1.0)
        public func setManifest(_ valueParam: StorageServiceProtoStorageManifest?) {
            guard let valueParam = valueParam else { return }
            proto.manifest = valueParam.proto
        }

        public func setManifest(_ valueParam: StorageServiceProtoStorageManifest) {
            proto.manifest = valueParam.proto
        }

        public func addInsertItem(_ valueParam: StorageServiceProtoStorageItem) {
            var items = proto.insertItem
            items.append(valueParam.proto)
            proto.insertItem = items
        }

        public func setInsertItem(_ wrappedItems: [StorageServiceProtoStorageItem]) {
            proto.insertItem = wrappedItems.map { $0.proto }
        }

        public func addDeleteKey(_ valueParam: Data) {
            var items = proto.deleteKey
            items.append(valueParam)
            proto.deleteKey = items
        }

        public func setDeleteKey(_ wrappedItems: [Data]) {
            proto.deleteKey = wrappedItems
        }

        public func setDeleteAll(_ valueParam: Bool) {
            proto.deleteAll = valueParam
        }

        public func build() throws -> StorageServiceProtoWriteOperation {
            return try StorageServiceProtoWriteOperation.parseProto(proto)
        }

        public func buildSerializedData() throws -> Data {
            return try StorageServiceProtoWriteOperation.parseProto(proto).serializedData()
        }
    }

    fileprivate let proto: StorageServiceProtos_WriteOperation

    public let manifest: StorageServiceProtoStorageManifest?

    public let insertItem: [StorageServiceProtoStorageItem]

    public var deleteKey: [Data] {
        return proto.deleteKey
    }

    public var deleteAll: Bool {
        return proto.deleteAll
    }
    public var hasDeleteAll: Bool {
        return true
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

    public override var debugDescription: String {
        return "\(proto)"
    }
}

#if DEBUG

extension StorageServiceProtoWriteOperation {
    public func serializedDataIgnoringErrors() -> Data? {
        return try! self.serializedData()
    }
}

extension StorageServiceProtoWriteOperation.StorageServiceProtoWriteOperationBuilder {
    public func buildIgnoringErrors() -> StorageServiceProtoWriteOperation? {
        return try! self.build()
    }
}

#endif

// MARK: - StorageServiceProtoManifestRecordKeyType

public enum StorageServiceProtoManifestRecordKeyType: SwiftProtobuf.Enum {
    public typealias RawValue = Int
    case unknown // 0
    case contact // 1
    case groupv1 // 2
    case groupv2 // 3
    case account // 4
    case UNRECOGNIZED(Int)

    public init() {
        self = .unknown
    }

    public init?(rawValue: Int) {
        switch rawValue {
            case 0: self = .unknown
            case 1: self = .contact
            case 2: self = .groupv1
            case 3: self = .groupv2
            case 4: self = .account
            default: self = .UNRECOGNIZED(rawValue)
        }
    }

    public var rawValue: Int {
        switch self {
            case .unknown: return 0
            case .contact: return 1
            case .groupv1: return 2
            case .groupv2: return 3
            case .account: return 4
            case .UNRECOGNIZED(let i): return i
        }
    }
}

private func StorageServiceProtoManifestRecordKeyTypeWrap(_ value: StorageServiceProtos_ManifestRecord.Key.TypeEnum) -> StorageServiceProtoManifestRecordKeyType {
    switch value {
    case .unknown: return .unknown
    case .contact: return .contact
    case .groupv1: return .groupv1
    case .groupv2: return .groupv2
    case .account: return .account
    case .UNRECOGNIZED(let i): return .UNRECOGNIZED(i)
    }
}

private func StorageServiceProtoManifestRecordKeyTypeUnwrap(_ value: StorageServiceProtoManifestRecordKeyType) -> StorageServiceProtos_ManifestRecord.Key.TypeEnum {
    switch value {
    case .unknown: return .unknown
    case .contact: return .contact
    case .groupv1: return .groupv1
    case .groupv2: return .groupv2
    case .account: return .account
    case .UNRECOGNIZED(let i): return .UNRECOGNIZED(i)
    }
}

// MARK: - StorageServiceProtoManifestRecordKey

public class StorageServiceProtoManifestRecordKey: NSObject {

    // MARK: - StorageServiceProtoManifestRecordKeyBuilder

    public class func builder(data: Data, type: StorageServiceProtoManifestRecordKeyType) -> StorageServiceProtoManifestRecordKeyBuilder {
        return StorageServiceProtoManifestRecordKeyBuilder(data: data, type: type)
    }

    // asBuilder() constructs a builder that reflects the proto's contents.
    public func asBuilder() -> StorageServiceProtoManifestRecordKeyBuilder {
        let builder = StorageServiceProtoManifestRecordKeyBuilder(data: data, type: type)
        return builder
    }

    public class StorageServiceProtoManifestRecordKeyBuilder: NSObject {

        private var proto = StorageServiceProtos_ManifestRecord.Key()

        fileprivate override init() {}

        fileprivate init(data: Data, type: StorageServiceProtoManifestRecordKeyType) {
            super.init()

            setData(data)
            setType(type)
        }

        @available(swift, obsoleted: 1.0)
        public func setData(_ valueParam: Data?) {
            guard let valueParam = valueParam else { return }
            proto.data = valueParam
        }

        public func setData(_ valueParam: Data) {
            proto.data = valueParam
        }

        public func setType(_ valueParam: StorageServiceProtoManifestRecordKeyType) {
            proto.type = StorageServiceProtoManifestRecordKeyTypeUnwrap(valueParam)
        }

        public func build() throws -> StorageServiceProtoManifestRecordKey {
            return try StorageServiceProtoManifestRecordKey.parseProto(proto)
        }

        public func buildSerializedData() throws -> Data {
            return try StorageServiceProtoManifestRecordKey.parseProto(proto).serializedData()
        }
    }

    fileprivate let proto: StorageServiceProtos_ManifestRecord.Key

    public let data: Data

    public let type: StorageServiceProtoManifestRecordKeyType

    private init(proto: StorageServiceProtos_ManifestRecord.Key,
                 data: Data,
                 type: StorageServiceProtoManifestRecordKeyType) {
        self.proto = proto
        self.data = data
        self.type = type
    }

    @objc
    public func serializedData() throws -> Data {
        return try self.proto.serializedData()
    }

    public class func parseData(_ serializedData: Data) throws -> StorageServiceProtoManifestRecordKey {
        let proto = try StorageServiceProtos_ManifestRecord.Key(serializedData: serializedData)
        return try parseProto(proto)
    }

    fileprivate class func parseProto(_ proto: StorageServiceProtos_ManifestRecord.Key) throws -> StorageServiceProtoManifestRecordKey {
        let data = proto.data

        let type = StorageServiceProtoManifestRecordKeyTypeWrap(proto.type)

        // MARK: - Begin Validation Logic for StorageServiceProtoManifestRecordKey -

        // MARK: - End Validation Logic for StorageServiceProtoManifestRecordKey -

        let result = StorageServiceProtoManifestRecordKey(proto: proto,
                                                          data: data,
                                                          type: type)
        return result
    }

    public override var debugDescription: String {
        return "\(proto)"
    }
}

#if DEBUG

extension StorageServiceProtoManifestRecordKey {
    public func serializedDataIgnoringErrors() -> Data? {
        return try! self.serializedData()
    }
}

extension StorageServiceProtoManifestRecordKey.StorageServiceProtoManifestRecordKeyBuilder {
    public func buildIgnoringErrors() -> StorageServiceProtoManifestRecordKey? {
        return try! self.build()
    }
}

#endif

// MARK: - StorageServiceProtoManifestRecord

public class StorageServiceProtoManifestRecord: NSObject {

    // MARK: - StorageServiceProtoManifestRecordBuilder

    public class func builder(version: UInt64) -> StorageServiceProtoManifestRecordBuilder {
        return StorageServiceProtoManifestRecordBuilder(version: version)
    }

    // asBuilder() constructs a builder that reflects the proto's contents.
    public func asBuilder() -> StorageServiceProtoManifestRecordBuilder {
        let builder = StorageServiceProtoManifestRecordBuilder(version: version)
        builder.setKeys(keys)
        return builder
    }

    public class StorageServiceProtoManifestRecordBuilder: NSObject {

        private var proto = StorageServiceProtos_ManifestRecord()

        fileprivate override init() {}

        fileprivate init(version: UInt64) {
            super.init()

            setVersion(version)
        }

        public func setVersion(_ valueParam: UInt64) {
            proto.version = valueParam
        }

        public func addKeys(_ valueParam: StorageServiceProtoManifestRecordKey) {
            var items = proto.keys
            items.append(valueParam.proto)
            proto.keys = items
        }

        public func setKeys(_ wrappedItems: [StorageServiceProtoManifestRecordKey]) {
            proto.keys = wrappedItems.map { $0.proto }
        }

        public func build() throws -> StorageServiceProtoManifestRecord {
            return try StorageServiceProtoManifestRecord.parseProto(proto)
        }

        public func buildSerializedData() throws -> Data {
            return try StorageServiceProtoManifestRecord.parseProto(proto).serializedData()
        }
    }

    fileprivate let proto: StorageServiceProtos_ManifestRecord

    public let version: UInt64

    public let keys: [StorageServiceProtoManifestRecordKey]

    private init(proto: StorageServiceProtos_ManifestRecord,
                 version: UInt64,
                 keys: [StorageServiceProtoManifestRecordKey]) {
        self.proto = proto
        self.version = version
        self.keys = keys
    }

    @objc
    public func serializedData() throws -> Data {
        return try self.proto.serializedData()
    }

    public class func parseData(_ serializedData: Data) throws -> StorageServiceProtoManifestRecord {
        let proto = try StorageServiceProtos_ManifestRecord(serializedData: serializedData)
        return try parseProto(proto)
    }

    fileprivate class func parseProto(_ proto: StorageServiceProtos_ManifestRecord) throws -> StorageServiceProtoManifestRecord {
        let version = proto.version

        var keys: [StorageServiceProtoManifestRecordKey] = []
        keys = try proto.keys.map { try StorageServiceProtoManifestRecordKey.parseProto($0) }

        // MARK: - Begin Validation Logic for StorageServiceProtoManifestRecord -

        // MARK: - End Validation Logic for StorageServiceProtoManifestRecord -

        let result = StorageServiceProtoManifestRecord(proto: proto,
                                                       version: version,
                                                       keys: keys)
        return result
    }

    public override var debugDescription: String {
        return "\(proto)"
    }
}

#if DEBUG

extension StorageServiceProtoManifestRecord {
    public func serializedDataIgnoringErrors() -> Data? {
        return try! self.serializedData()
    }
}

extension StorageServiceProtoManifestRecord.StorageServiceProtoManifestRecordBuilder {
    public func buildIgnoringErrors() -> StorageServiceProtoManifestRecord? {
        return try! self.build()
    }
}

#endif

// MARK: - StorageServiceProtoStorageRecordOneOfRecord

public enum StorageServiceProtoStorageRecordOneOfRecord: Equatable {
    case contact(StorageServiceProtoContactRecord)
    case groupV1(StorageServiceProtoGroupV1Record)
    case groupV2(StorageServiceProtoGroupV2Record)
    case account(StorageServiceProtoAccountRecord)
}

private func StorageServiceProtoStorageRecordOneOfRecordWrap(_ value: StorageServiceProtos_StorageRecord.OneOf_Record) throws -> StorageServiceProtoStorageRecordOneOfRecord {
    switch value {
    case .contact(let value): return .contact(try StorageServiceProtoContactRecord.parseProto(value))
    case .groupV1(let value): return .groupV1(try StorageServiceProtoGroupV1Record.parseProto(value))
    case .groupV2(let value): return .groupV2(try StorageServiceProtoGroupV2Record.parseProto(value))
    case .account(let value): return .account(try StorageServiceProtoAccountRecord.parseProto(value))
    }
}

private func StorageServiceProtoStorageRecordOneOfRecordUnwrap(_ value: StorageServiceProtoStorageRecordOneOfRecord) -> StorageServiceProtos_StorageRecord.OneOf_Record {
    switch value {
    case .contact(let value): return .contact(value.proto)
    case .groupV1(let value): return .groupV1(value.proto)
    case .groupV2(let value): return .groupV2(value.proto)
    case .account(let value): return .account(value.proto)
    }
}

// MARK: - StorageServiceProtoStorageRecord

public class StorageServiceProtoStorageRecord: NSObject {

    // MARK: - StorageServiceProtoStorageRecordBuilder

    public class func builder() -> StorageServiceProtoStorageRecordBuilder {
        return StorageServiceProtoStorageRecordBuilder()
    }

    // asBuilder() constructs a builder that reflects the proto's contents.
    public func asBuilder() -> StorageServiceProtoStorageRecordBuilder {
        let builder = StorageServiceProtoStorageRecordBuilder()
        if let _value = record {
            builder.setRecord(_value)
        }
        return builder
    }

    public class StorageServiceProtoStorageRecordBuilder: NSObject {

        private var proto = StorageServiceProtos_StorageRecord()

        fileprivate override init() {}

        @available(swift, obsoleted: 1.0)
        public func setRecord(_ valueParam: StorageServiceProtoStorageRecordOneOfRecord?) {
            guard let valueParam = valueParam else { return }
            proto.record = StorageServiceProtoStorageRecordOneOfRecordUnwrap(valueParam)
        }

        public func setRecord(_ valueParam: StorageServiceProtoStorageRecordOneOfRecord) {
            proto.record = StorageServiceProtoStorageRecordOneOfRecordUnwrap(valueParam)
        }

        public func build() throws -> StorageServiceProtoStorageRecord {
            return try StorageServiceProtoStorageRecord.parseProto(proto)
        }

        public func buildSerializedData() throws -> Data {
            return try StorageServiceProtoStorageRecord.parseProto(proto).serializedData()
        }
    }

    fileprivate let proto: StorageServiceProtos_StorageRecord

    public var record: StorageServiceProtoStorageRecordOneOfRecord? {
        guard hasRecord else {
            return nil
        }
        guard let record = proto.record else {
            owsFailDebug("record was unexpectedly nil")
            return nil
        }
        guard let unwrappedRecord = try? StorageServiceProtoStorageRecordOneOfRecordWrap(record) else {
            owsFailDebug("failed to unwrap record")
            return nil
        }
        return unwrappedRecord
    }
    public var hasRecord: Bool {
        return true
    }

    private init(proto: StorageServiceProtos_StorageRecord) {
        self.proto = proto
    }

    @objc
    public func serializedData() throws -> Data {
        return try self.proto.serializedData()
    }

    public class func parseData(_ serializedData: Data) throws -> StorageServiceProtoStorageRecord {
        let proto = try StorageServiceProtos_StorageRecord(serializedData: serializedData)
        return try parseProto(proto)
    }

    fileprivate class func parseProto(_ proto: StorageServiceProtos_StorageRecord) throws -> StorageServiceProtoStorageRecord {
        // MARK: - Begin Validation Logic for StorageServiceProtoStorageRecord -

        // MARK: - End Validation Logic for StorageServiceProtoStorageRecord -

        let result = StorageServiceProtoStorageRecord(proto: proto)
        return result
    }

    public override var debugDescription: String {
        return "\(proto)"
    }
}

#if DEBUG

extension StorageServiceProtoStorageRecord {
    public func serializedDataIgnoringErrors() -> Data? {
        return try! self.serializedData()
    }
}

extension StorageServiceProtoStorageRecord.StorageServiceProtoStorageRecordBuilder {
    public func buildIgnoringErrors() -> StorageServiceProtoStorageRecord? {
        return try! self.build()
    }
}

#endif

// MARK: - StorageServiceProtoContactRecordIdentityState

public enum StorageServiceProtoContactRecordIdentityState: SwiftProtobuf.Enum {
    public typealias RawValue = Int
    case `default` // 0
    case verified // 1
    case unverified // 2
    case UNRECOGNIZED(Int)

    public init() {
        self = .`default`
    }

    public init?(rawValue: Int) {
        switch rawValue {
            case 0: self = .`default`
            case 1: self = .verified
            case 2: self = .unverified
            default: self = .UNRECOGNIZED(rawValue)
        }
    }

    public var rawValue: Int {
        switch self {
            case .`default`: return 0
            case .verified: return 1
            case .unverified: return 2
            case .UNRECOGNIZED(let i): return i
        }
    }
}

private func StorageServiceProtoContactRecordIdentityStateWrap(_ value: StorageServiceProtos_ContactRecord.Identity.State) -> StorageServiceProtoContactRecordIdentityState {
    switch value {
    case .default: return .default
    case .verified: return .verified
    case .unverified: return .unverified
    case .UNRECOGNIZED(let i): return .UNRECOGNIZED(i)
    }
}

private func StorageServiceProtoContactRecordIdentityStateUnwrap(_ value: StorageServiceProtoContactRecordIdentityState) -> StorageServiceProtos_ContactRecord.Identity.State {
    switch value {
    case .default: return .default
    case .verified: return .verified
    case .unverified: return .unverified
    case .UNRECOGNIZED(let i): return .UNRECOGNIZED(i)
    }
}

// MARK: - StorageServiceProtoContactRecordIdentity

public class StorageServiceProtoContactRecordIdentity: NSObject {

    // MARK: - StorageServiceProtoContactRecordIdentityBuilder

    public class func builder() -> StorageServiceProtoContactRecordIdentityBuilder {
        return StorageServiceProtoContactRecordIdentityBuilder()
    }

    // asBuilder() constructs a builder that reflects the proto's contents.
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

    public class StorageServiceProtoContactRecordIdentityBuilder: NSObject {

        private var proto = StorageServiceProtos_ContactRecord.Identity()

        fileprivate override init() {}

        @available(swift, obsoleted: 1.0)
        public func setKey(_ valueParam: Data?) {
            guard let valueParam = valueParam else { return }
            proto.key = valueParam
        }

        public func setKey(_ valueParam: Data) {
            proto.key = valueParam
        }

        public func setState(_ valueParam: StorageServiceProtoContactRecordIdentityState) {
            proto.state = StorageServiceProtoContactRecordIdentityStateUnwrap(valueParam)
        }

        public func build() throws -> StorageServiceProtoContactRecordIdentity {
            return try StorageServiceProtoContactRecordIdentity.parseProto(proto)
        }

        public func buildSerializedData() throws -> Data {
            return try StorageServiceProtoContactRecordIdentity.parseProto(proto).serializedData()
        }
    }

    fileprivate let proto: StorageServiceProtos_ContactRecord.Identity

    public var key: Data? {
        guard hasKey else {
            return nil
        }
        return proto.key
    }
    public var hasKey: Bool {
        return proto.key.count > 0
    }

    public var state: StorageServiceProtoContactRecordIdentityState? {
        guard hasState else {
            return nil
        }
        return StorageServiceProtoContactRecordIdentityStateWrap(proto.state)
    }
    // This "unwrapped" accessor should only be used if the "has value" accessor has already been checked.
    public var unwrappedState: StorageServiceProtoContactRecordIdentityState {
        if !hasState {
            // TODO: We could make this a crashing assert.
            owsFailDebug("Unsafe unwrap of missing optional: Identity.state.")
        }
        return StorageServiceProtoContactRecordIdentityStateWrap(proto.state)
    }
    public var hasState: Bool {
        return true
    }

    private init(proto: StorageServiceProtos_ContactRecord.Identity) {
        self.proto = proto
    }

    @objc
    public func serializedData() throws -> Data {
        return try self.proto.serializedData()
    }

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

    public override var debugDescription: String {
        return "\(proto)"
    }
}

#if DEBUG

extension StorageServiceProtoContactRecordIdentity {
    public func serializedDataIgnoringErrors() -> Data? {
        return try! self.serializedData()
    }
}

extension StorageServiceProtoContactRecordIdentity.StorageServiceProtoContactRecordIdentityBuilder {
    public func buildIgnoringErrors() -> StorageServiceProtoContactRecordIdentity? {
        return try! self.build()
    }
}

#endif

// MARK: - StorageServiceProtoContactRecordProfile

public class StorageServiceProtoContactRecordProfile: NSObject {

    // MARK: - StorageServiceProtoContactRecordProfileBuilder

    public class func builder() -> StorageServiceProtoContactRecordProfileBuilder {
        return StorageServiceProtoContactRecordProfileBuilder()
    }

    // asBuilder() constructs a builder that reflects the proto's contents.
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

    public class StorageServiceProtoContactRecordProfileBuilder: NSObject {

        private var proto = StorageServiceProtos_ContactRecord.Profile()

        fileprivate override init() {}

        @available(swift, obsoleted: 1.0)
        public func setGivenName(_ valueParam: String?) {
            guard let valueParam = valueParam else { return }
            proto.givenName = valueParam
        }

        public func setGivenName(_ valueParam: String) {
            proto.givenName = valueParam
        }

        @available(swift, obsoleted: 1.0)
        public func setKey(_ valueParam: Data?) {
            guard let valueParam = valueParam else { return }
            proto.key = valueParam
        }

        public func setKey(_ valueParam: Data) {
            proto.key = valueParam
        }

        @available(swift, obsoleted: 1.0)
        public func setUsername(_ valueParam: String?) {
            guard let valueParam = valueParam else { return }
            proto.username = valueParam
        }

        public func setUsername(_ valueParam: String) {
            proto.username = valueParam
        }

        @available(swift, obsoleted: 1.0)
        public func setFamilyName(_ valueParam: String?) {
            guard let valueParam = valueParam else { return }
            proto.familyName = valueParam
        }

        public func setFamilyName(_ valueParam: String) {
            proto.familyName = valueParam
        }

        public func build() throws -> StorageServiceProtoContactRecordProfile {
            return try StorageServiceProtoContactRecordProfile.parseProto(proto)
        }

        public func buildSerializedData() throws -> Data {
            return try StorageServiceProtoContactRecordProfile.parseProto(proto).serializedData()
        }
    }

    fileprivate let proto: StorageServiceProtos_ContactRecord.Profile

    public var givenName: String? {
        guard hasGivenName else {
            return nil
        }
        return proto.givenName
    }
    public var hasGivenName: Bool {
        return true
    }

    public var key: Data? {
        guard hasKey else {
            return nil
        }
        return proto.key
    }
    public var hasKey: Bool {
        return proto.key.count > 0
    }

    public var username: String? {
        guard hasUsername else {
            return nil
        }
        return proto.username
    }
    public var hasUsername: Bool {
        return true
    }

    public var familyName: String? {
        guard hasFamilyName else {
            return nil
        }
        return proto.familyName
    }
    public var hasFamilyName: Bool {
        return true
    }

    private init(proto: StorageServiceProtos_ContactRecord.Profile) {
        self.proto = proto
    }

    @objc
    public func serializedData() throws -> Data {
        return try self.proto.serializedData()
    }

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

    public override var debugDescription: String {
        return "\(proto)"
    }
}

#if DEBUG

extension StorageServiceProtoContactRecordProfile {
    public func serializedDataIgnoringErrors() -> Data? {
        return try! self.serializedData()
    }
}

extension StorageServiceProtoContactRecordProfile.StorageServiceProtoContactRecordProfileBuilder {
    public func buildIgnoringErrors() -> StorageServiceProtoContactRecordProfile? {
        return try! self.build()
    }
}

#endif

// MARK: - StorageServiceProtoContactRecord

public class StorageServiceProtoContactRecord: NSObject {

    // MARK: - StorageServiceProtoContactRecordBuilder

    public class func builder() -> StorageServiceProtoContactRecordBuilder {
        return StorageServiceProtoContactRecordBuilder()
    }

    // asBuilder() constructs a builder that reflects the proto's contents.
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

    public class StorageServiceProtoContactRecordBuilder: NSObject {

        private var proto = StorageServiceProtos_ContactRecord()

        fileprivate override init() {}

        @available(swift, obsoleted: 1.0)
        public func setServiceUuid(_ valueParam: String?) {
            guard let valueParam = valueParam else { return }
            proto.serviceUuid = valueParam
        }

        public func setServiceUuid(_ valueParam: String) {
            proto.serviceUuid = valueParam
        }

        @available(swift, obsoleted: 1.0)
        public func setServiceE164(_ valueParam: String?) {
            guard let valueParam = valueParam else { return }
            proto.serviceE164 = valueParam
        }

        public func setServiceE164(_ valueParam: String) {
            proto.serviceE164 = valueParam
        }

        @available(swift, obsoleted: 1.0)
        public func setProfile(_ valueParam: StorageServiceProtoContactRecordProfile?) {
            guard let valueParam = valueParam else { return }
            proto.profile = valueParam.proto
        }

        public func setProfile(_ valueParam: StorageServiceProtoContactRecordProfile) {
            proto.profile = valueParam.proto
        }

        @available(swift, obsoleted: 1.0)
        public func setIdentity(_ valueParam: StorageServiceProtoContactRecordIdentity?) {
            guard let valueParam = valueParam else { return }
            proto.identity = valueParam.proto
        }

        public func setIdentity(_ valueParam: StorageServiceProtoContactRecordIdentity) {
            proto.identity = valueParam.proto
        }

        public func setBlocked(_ valueParam: Bool) {
            proto.blocked = valueParam
        }

        public func setWhitelisted(_ valueParam: Bool) {
            proto.whitelisted = valueParam
        }

        @available(swift, obsoleted: 1.0)
        public func setNickname(_ valueParam: String?) {
            guard let valueParam = valueParam else { return }
            proto.nickname = valueParam
        }

        public func setNickname(_ valueParam: String) {
            proto.nickname = valueParam
        }

        public func build() throws -> StorageServiceProtoContactRecord {
            return try StorageServiceProtoContactRecord.parseProto(proto)
        }

        public func buildSerializedData() throws -> Data {
            return try StorageServiceProtoContactRecord.parseProto(proto).serializedData()
        }
    }

    fileprivate let proto: StorageServiceProtos_ContactRecord

    public let profile: StorageServiceProtoContactRecordProfile?

    public let identity: StorageServiceProtoContactRecordIdentity?

    public var serviceUuid: String? {
        guard hasServiceUuid else {
            return nil
        }
        return proto.serviceUuid
    }
    public var hasServiceUuid: Bool {
        return true
    }

    public var serviceE164: String? {
        guard hasServiceE164 else {
            return nil
        }
        return proto.serviceE164
    }
    public var hasServiceE164: Bool {
        return true
    }

    public var blocked: Bool {
        return proto.blocked
    }
    public var hasBlocked: Bool {
        return true
    }

    public var whitelisted: Bool {
        return proto.whitelisted
    }
    public var hasWhitelisted: Bool {
        return true
    }

    public var nickname: String? {
        guard hasNickname else {
            return nil
        }
        return proto.nickname
    }
    public var hasNickname: Bool {
        return true
    }

    public var hasValidService: Bool {
        return serviceAddress != nil
    }
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

    public override var debugDescription: String {
        return "\(proto)"
    }
}

#if DEBUG

extension StorageServiceProtoContactRecord {
    public func serializedDataIgnoringErrors() -> Data? {
        return try! self.serializedData()
    }
}

extension StorageServiceProtoContactRecord.StorageServiceProtoContactRecordBuilder {
    public func buildIgnoringErrors() -> StorageServiceProtoContactRecord? {
        return try! self.build()
    }
}

#endif

// MARK: - StorageServiceProtoGroupV1Record

public class StorageServiceProtoGroupV1Record: NSObject {

    // MARK: - StorageServiceProtoGroupV1RecordBuilder

    public class func builder(id: Data) -> StorageServiceProtoGroupV1RecordBuilder {
        return StorageServiceProtoGroupV1RecordBuilder(id: id)
    }

    // asBuilder() constructs a builder that reflects the proto's contents.
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

    public class StorageServiceProtoGroupV1RecordBuilder: NSObject {

        private var proto = StorageServiceProtos_GroupV1Record()

        fileprivate override init() {}

        fileprivate init(id: Data) {
            super.init()

            setId(id)
        }

        @available(swift, obsoleted: 1.0)
        public func setId(_ valueParam: Data?) {
            guard let valueParam = valueParam else { return }
            proto.id = valueParam
        }

        public func setId(_ valueParam: Data) {
            proto.id = valueParam
        }

        public func setBlocked(_ valueParam: Bool) {
            proto.blocked = valueParam
        }

        public func setWhitelisted(_ valueParam: Bool) {
            proto.whitelisted = valueParam
        }

        public func build() throws -> StorageServiceProtoGroupV1Record {
            return try StorageServiceProtoGroupV1Record.parseProto(proto)
        }

        public func buildSerializedData() throws -> Data {
            return try StorageServiceProtoGroupV1Record.parseProto(proto).serializedData()
        }
    }

    fileprivate let proto: StorageServiceProtos_GroupV1Record

    public let id: Data

    public var blocked: Bool {
        return proto.blocked
    }
    public var hasBlocked: Bool {
        return true
    }

    public var whitelisted: Bool {
        return proto.whitelisted
    }
    public var hasWhitelisted: Bool {
        return true
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

    public class func parseData(_ serializedData: Data) throws -> StorageServiceProtoGroupV1Record {
        let proto = try StorageServiceProtos_GroupV1Record(serializedData: serializedData)
        return try parseProto(proto)
    }

    fileprivate class func parseProto(_ proto: StorageServiceProtos_GroupV1Record) throws -> StorageServiceProtoGroupV1Record {
        let id = proto.id

        // MARK: - Begin Validation Logic for StorageServiceProtoGroupV1Record -

        // MARK: - End Validation Logic for StorageServiceProtoGroupV1Record -

        let result = StorageServiceProtoGroupV1Record(proto: proto,
                                                      id: id)
        return result
    }

    public override var debugDescription: String {
        return "\(proto)"
    }
}

#if DEBUG

extension StorageServiceProtoGroupV1Record {
    public func serializedDataIgnoringErrors() -> Data? {
        return try! self.serializedData()
    }
}

extension StorageServiceProtoGroupV1Record.StorageServiceProtoGroupV1RecordBuilder {
    public func buildIgnoringErrors() -> StorageServiceProtoGroupV1Record? {
        return try! self.build()
    }
}

#endif

// MARK: - StorageServiceProtoGroupV2Record

public class StorageServiceProtoGroupV2Record: NSObject {

    // MARK: - StorageServiceProtoGroupV2RecordBuilder

    public class func builder(masterKey: Data) -> StorageServiceProtoGroupV2RecordBuilder {
        return StorageServiceProtoGroupV2RecordBuilder(masterKey: masterKey)
    }

    // asBuilder() constructs a builder that reflects the proto's contents.
    public func asBuilder() -> StorageServiceProtoGroupV2RecordBuilder {
        let builder = StorageServiceProtoGroupV2RecordBuilder(masterKey: masterKey)
        if hasBlocked {
            builder.setBlocked(blocked)
        }
        if hasWhitelisted {
            builder.setWhitelisted(whitelisted)
        }
        return builder
    }

    public class StorageServiceProtoGroupV2RecordBuilder: NSObject {

        private var proto = StorageServiceProtos_GroupV2Record()

        fileprivate override init() {}

        fileprivate init(masterKey: Data) {
            super.init()

            setMasterKey(masterKey)
        }

        @available(swift, obsoleted: 1.0)
        public func setMasterKey(_ valueParam: Data?) {
            guard let valueParam = valueParam else { return }
            proto.masterKey = valueParam
        }

        public func setMasterKey(_ valueParam: Data) {
            proto.masterKey = valueParam
        }

        public func setBlocked(_ valueParam: Bool) {
            proto.blocked = valueParam
        }

        public func setWhitelisted(_ valueParam: Bool) {
            proto.whitelisted = valueParam
        }

        public func build() throws -> StorageServiceProtoGroupV2Record {
            return try StorageServiceProtoGroupV2Record.parseProto(proto)
        }

        public func buildSerializedData() throws -> Data {
            return try StorageServiceProtoGroupV2Record.parseProto(proto).serializedData()
        }
    }

    fileprivate let proto: StorageServiceProtos_GroupV2Record

    public let masterKey: Data

    public var blocked: Bool {
        return proto.blocked
    }
    public var hasBlocked: Bool {
        return true
    }

    public var whitelisted: Bool {
        return proto.whitelisted
    }
    public var hasWhitelisted: Bool {
        return true
    }

    private init(proto: StorageServiceProtos_GroupV2Record,
                 masterKey: Data) {
        self.proto = proto
        self.masterKey = masterKey
    }

    @objc
    public func serializedData() throws -> Data {
        return try self.proto.serializedData()
    }

    public class func parseData(_ serializedData: Data) throws -> StorageServiceProtoGroupV2Record {
        let proto = try StorageServiceProtos_GroupV2Record(serializedData: serializedData)
        return try parseProto(proto)
    }

    fileprivate class func parseProto(_ proto: StorageServiceProtos_GroupV2Record) throws -> StorageServiceProtoGroupV2Record {
        let masterKey = proto.masterKey

        // MARK: - Begin Validation Logic for StorageServiceProtoGroupV2Record -

        // MARK: - End Validation Logic for StorageServiceProtoGroupV2Record -

        let result = StorageServiceProtoGroupV2Record(proto: proto,
                                                      masterKey: masterKey)
        return result
    }

    public override var debugDescription: String {
        return "\(proto)"
    }
}

#if DEBUG

extension StorageServiceProtoGroupV2Record {
    public func serializedDataIgnoringErrors() -> Data? {
        return try! self.serializedData()
    }
}

extension StorageServiceProtoGroupV2Record.StorageServiceProtoGroupV2RecordBuilder {
    public func buildIgnoringErrors() -> StorageServiceProtoGroupV2Record? {
        return try! self.build()
    }
}

#endif

// MARK: - StorageServiceProtoAccountRecordConfig

public class StorageServiceProtoAccountRecordConfig: NSObject {

    // MARK: - StorageServiceProtoAccountRecordConfigBuilder

    public class func builder() -> StorageServiceProtoAccountRecordConfigBuilder {
        return StorageServiceProtoAccountRecordConfigBuilder()
    }

    // asBuilder() constructs a builder that reflects the proto's contents.
    public func asBuilder() -> StorageServiceProtoAccountRecordConfigBuilder {
        let builder = StorageServiceProtoAccountRecordConfigBuilder()
        if hasReadReceipts {
            builder.setReadReceipts(readReceipts)
        }
        if hasSealedSenderIndicators {
            builder.setSealedSenderIndicators(sealedSenderIndicators)
        }
        if hasTypingIndicators {
            builder.setTypingIndicators(typingIndicators)
        }
        if hasLinkPreviews {
            builder.setLinkPreviews(linkPreviews)
        }
        return builder
    }

    public class StorageServiceProtoAccountRecordConfigBuilder: NSObject {

        private var proto = StorageServiceProtos_AccountRecord.Config()

        fileprivate override init() {}

        public func setReadReceipts(_ valueParam: Bool) {
            proto.readReceipts = valueParam
        }

        public func setSealedSenderIndicators(_ valueParam: Bool) {
            proto.sealedSenderIndicators = valueParam
        }

        public func setTypingIndicators(_ valueParam: Bool) {
            proto.typingIndicators = valueParam
        }

        public func setLinkPreviews(_ valueParam: Bool) {
            proto.linkPreviews = valueParam
        }

        public func build() throws -> StorageServiceProtoAccountRecordConfig {
            return try StorageServiceProtoAccountRecordConfig.parseProto(proto)
        }

        public func buildSerializedData() throws -> Data {
            return try StorageServiceProtoAccountRecordConfig.parseProto(proto).serializedData()
        }
    }

    fileprivate let proto: StorageServiceProtos_AccountRecord.Config

    public var readReceipts: Bool {
        return proto.readReceipts
    }
    public var hasReadReceipts: Bool {
        return true
    }

    public var sealedSenderIndicators: Bool {
        return proto.sealedSenderIndicators
    }
    public var hasSealedSenderIndicators: Bool {
        return true
    }

    public var typingIndicators: Bool {
        return proto.typingIndicators
    }
    public var hasTypingIndicators: Bool {
        return true
    }

    public var linkPreviews: Bool {
        return proto.linkPreviews
    }
    public var hasLinkPreviews: Bool {
        return true
    }

    private init(proto: StorageServiceProtos_AccountRecord.Config) {
        self.proto = proto
    }

    @objc
    public func serializedData() throws -> Data {
        return try self.proto.serializedData()
    }

    public class func parseData(_ serializedData: Data) throws -> StorageServiceProtoAccountRecordConfig {
        let proto = try StorageServiceProtos_AccountRecord.Config(serializedData: serializedData)
        return try parseProto(proto)
    }

    fileprivate class func parseProto(_ proto: StorageServiceProtos_AccountRecord.Config) throws -> StorageServiceProtoAccountRecordConfig {
        // MARK: - Begin Validation Logic for StorageServiceProtoAccountRecordConfig -

        // MARK: - End Validation Logic for StorageServiceProtoAccountRecordConfig -

        let result = StorageServiceProtoAccountRecordConfig(proto: proto)
        return result
    }

    public override var debugDescription: String {
        return "\(proto)"
    }
}

#if DEBUG

extension StorageServiceProtoAccountRecordConfig {
    public func serializedDataIgnoringErrors() -> Data? {
        return try! self.serializedData()
    }
}

extension StorageServiceProtoAccountRecordConfig.StorageServiceProtoAccountRecordConfigBuilder {
    public func buildIgnoringErrors() -> StorageServiceProtoAccountRecordConfig? {
        return try! self.build()
    }
}

#endif

// MARK: - StorageServiceProtoAccountRecord

public class StorageServiceProtoAccountRecord: NSObject {

    // MARK: - StorageServiceProtoAccountRecordBuilder

    public class func builder() -> StorageServiceProtoAccountRecordBuilder {
        return StorageServiceProtoAccountRecordBuilder()
    }

    // asBuilder() constructs a builder that reflects the proto's contents.
    public func asBuilder() -> StorageServiceProtoAccountRecordBuilder {
        let builder = StorageServiceProtoAccountRecordBuilder()
        if let _value = contact {
            builder.setContact(_value)
        }
        if let _value = config {
            builder.setConfig(_value)
        }
        return builder
    }

    public class StorageServiceProtoAccountRecordBuilder: NSObject {

        private var proto = StorageServiceProtos_AccountRecord()

        fileprivate override init() {}

        @available(swift, obsoleted: 1.0)
        public func setContact(_ valueParam: StorageServiceProtoContactRecord?) {
            guard let valueParam = valueParam else { return }
            proto.contact = valueParam.proto
        }

        public func setContact(_ valueParam: StorageServiceProtoContactRecord) {
            proto.contact = valueParam.proto
        }

        @available(swift, obsoleted: 1.0)
        public func setConfig(_ valueParam: StorageServiceProtoAccountRecordConfig?) {
            guard let valueParam = valueParam else { return }
            proto.config = valueParam.proto
        }

        public func setConfig(_ valueParam: StorageServiceProtoAccountRecordConfig) {
            proto.config = valueParam.proto
        }

        public func build() throws -> StorageServiceProtoAccountRecord {
            return try StorageServiceProtoAccountRecord.parseProto(proto)
        }

        public func buildSerializedData() throws -> Data {
            return try StorageServiceProtoAccountRecord.parseProto(proto).serializedData()
        }
    }

    fileprivate let proto: StorageServiceProtos_AccountRecord

    public let contact: StorageServiceProtoContactRecord?

    public let config: StorageServiceProtoAccountRecordConfig?

    private init(proto: StorageServiceProtos_AccountRecord,
                 contact: StorageServiceProtoContactRecord?,
                 config: StorageServiceProtoAccountRecordConfig?) {
        self.proto = proto
        self.contact = contact
        self.config = config
    }

    @objc
    public func serializedData() throws -> Data {
        return try self.proto.serializedData()
    }

    public class func parseData(_ serializedData: Data) throws -> StorageServiceProtoAccountRecord {
        let proto = try StorageServiceProtos_AccountRecord(serializedData: serializedData)
        return try parseProto(proto)
    }

    fileprivate class func parseProto(_ proto: StorageServiceProtos_AccountRecord) throws -> StorageServiceProtoAccountRecord {
        var contact: StorageServiceProtoContactRecord?
        if proto.hasContact {
            contact = try StorageServiceProtoContactRecord.parseProto(proto.contact)
        }

        var config: StorageServiceProtoAccountRecordConfig?
        if proto.hasConfig {
            config = try StorageServiceProtoAccountRecordConfig.parseProto(proto.config)
        }

        // MARK: - Begin Validation Logic for StorageServiceProtoAccountRecord -

        // MARK: - End Validation Logic for StorageServiceProtoAccountRecord -

        let result = StorageServiceProtoAccountRecord(proto: proto,
                                                      contact: contact,
                                                      config: config)
        return result
    }

    public override var debugDescription: String {
        return "\(proto)"
    }
}

#if DEBUG

extension StorageServiceProtoAccountRecord {
    public func serializedDataIgnoringErrors() -> Data? {
        return try! self.serializedData()
    }
}

extension StorageServiceProtoAccountRecord.StorageServiceProtoAccountRecordBuilder {
    public func buildIgnoringErrors() -> StorageServiceProtoAccountRecord? {
        return try! self.build()
    }
}

#endif
