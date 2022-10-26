//
// Copyright 2022 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import SignalCoreKit
import SwiftProtobuf

// WARNING: This code is generated. Only edit within the markers.

public enum StorageServiceProtoError: Error {
    case invalidProtobuf(description: String)
}

// MARK: - StorageServiceProtoOptionalBool

public enum StorageServiceProtoOptionalBool: SwiftProtobuf.Enum {
    public typealias RawValue = Int
    case unset // 0
    case `true` // 1
    case `false` // 2
    case UNRECOGNIZED(Int)

    public init() {
        self = .unset
    }

    public init?(rawValue: Int) {
        switch rawValue {
            case 0: self = .unset
            case 1: self = .true
            case 2: self = .false
            default: self = .UNRECOGNIZED(rawValue)
        }
    }

    public var rawValue: Int {
        switch self {
            case .unset: return 0
            case .true: return 1
            case .false: return 2
            case .UNRECOGNIZED(let i): return i
        }
    }
}

private func StorageServiceProtoOptionalBoolWrap(_ value: StorageServiceProtos_OptionalBool) -> StorageServiceProtoOptionalBool {
    switch value {
    case .unset: return .unset
    case .true: return .true
    case .false: return .false
    case .UNRECOGNIZED(let i): return .UNRECOGNIZED(i)
    }
}

private func StorageServiceProtoOptionalBoolUnwrap(_ value: StorageServiceProtoOptionalBool) -> StorageServiceProtos_OptionalBool {
    switch value {
    case .unset: return .unset
    case .true: return .true
    case .false: return .false
    case .UNRECOGNIZED(let i): return .UNRECOGNIZED(i)
    }
}

// MARK: - StorageServiceProtoStorageItem

public struct StorageServiceProtoStorageItem: Codable, CustomDebugStringConvertible {

    fileprivate let proto: StorageServiceProtos_StorageItem

    public let key: Data

    public let value: Data

    public var hasUnknownFields: Bool {
        return !proto.unknownFields.data.isEmpty
    }
    public var unknownFields: SwiftProtobuf.UnknownStorage? {
        guard hasUnknownFields else { return nil }
        return proto.unknownFields
    }

    private init(proto: StorageServiceProtos_StorageItem,
                 key: Data,
                 value: Data) {
        self.proto = proto
        self.key = key
        self.value = value
    }

    public func serializedData() throws -> Data {
        return try self.proto.serializedData()
    }

    public init(serializedData: Data) throws {
        let proto = try StorageServiceProtos_StorageItem(serializedData: serializedData)
        try self.init(proto)
    }

    fileprivate init(_ proto: StorageServiceProtos_StorageItem) throws {
        let key = proto.key

        let value = proto.value

        // MARK: - Begin Validation Logic for StorageServiceProtoStorageItem -

        // MARK: - End Validation Logic for StorageServiceProtoStorageItem -

        self.init(proto: proto,
                  key: key,
                  value: value)
    }

    public init(from decoder: Swift.Decoder) throws {
        let singleValueContainer = try decoder.singleValueContainer()
        let serializedData = try singleValueContainer.decode(Data.self)
        try self.init(serializedData: serializedData)
    }
    public func encode(to encoder: Swift.Encoder) throws {
        var singleValueContainer = encoder.singleValueContainer()
        try singleValueContainer.encode(try serializedData())
    }

    public var debugDescription: String {
        return "\(proto)"
    }
}

extension StorageServiceProtoStorageItem {
    public static func builder(key: Data, value: Data) -> StorageServiceProtoStorageItemBuilder {
        return StorageServiceProtoStorageItemBuilder(key: key, value: value)
    }

    // asBuilder() constructs a builder that reflects the proto's contents.
    public func asBuilder() -> StorageServiceProtoStorageItemBuilder {
        var builder = StorageServiceProtoStorageItemBuilder(key: key, value: value)
        if let _value = unknownFields {
            builder.setUnknownFields(_value)
        }
        return builder
    }
}

public struct StorageServiceProtoStorageItemBuilder {

    private var proto = StorageServiceProtos_StorageItem()

    fileprivate init() {}

    fileprivate init(key: Data, value: Data) {

        setKey(key)
        setValue(value)
    }

    @available(swift, obsoleted: 1.0)
    public mutating func setKey(_ valueParam: Data?) {
        guard let valueParam = valueParam else { return }
        proto.key = valueParam
    }

    public mutating func setKey(_ valueParam: Data) {
        proto.key = valueParam
    }

    @available(swift, obsoleted: 1.0)
    public mutating func setValue(_ valueParam: Data?) {
        guard let valueParam = valueParam else { return }
        proto.value = valueParam
    }

    public mutating func setValue(_ valueParam: Data) {
        proto.value = valueParam
    }

    public mutating func setUnknownFields(_ unknownFields: SwiftProtobuf.UnknownStorage) {
        proto.unknownFields = unknownFields
    }

    public func build() throws -> StorageServiceProtoStorageItem {
        return try StorageServiceProtoStorageItem(proto)
    }

    public func buildSerializedData() throws -> Data {
        return try StorageServiceProtoStorageItem(proto).serializedData()
    }
}

#if TESTABLE_BUILD

extension StorageServiceProtoStorageItem {
    public func serializedDataIgnoringErrors() -> Data? {
        return try! self.serializedData()
    }
}

extension StorageServiceProtoStorageItemBuilder {
    public func buildIgnoringErrors() -> StorageServiceProtoStorageItem? {
        return try! self.build()
    }
}

#endif

// MARK: - StorageServiceProtoStorageItems

public struct StorageServiceProtoStorageItems: Codable, CustomDebugStringConvertible {

    fileprivate let proto: StorageServiceProtos_StorageItems

    public let items: [StorageServiceProtoStorageItem]

    public var hasUnknownFields: Bool {
        return !proto.unknownFields.data.isEmpty
    }
    public var unknownFields: SwiftProtobuf.UnknownStorage? {
        guard hasUnknownFields else { return nil }
        return proto.unknownFields
    }

    private init(proto: StorageServiceProtos_StorageItems,
                 items: [StorageServiceProtoStorageItem]) {
        self.proto = proto
        self.items = items
    }

    public func serializedData() throws -> Data {
        return try self.proto.serializedData()
    }

    public init(serializedData: Data) throws {
        let proto = try StorageServiceProtos_StorageItems(serializedData: serializedData)
        try self.init(proto)
    }

    fileprivate init(_ proto: StorageServiceProtos_StorageItems) throws {
        var items: [StorageServiceProtoStorageItem] = []
        items = try proto.items.map { try StorageServiceProtoStorageItem($0) }

        // MARK: - Begin Validation Logic for StorageServiceProtoStorageItems -

        // MARK: - End Validation Logic for StorageServiceProtoStorageItems -

        self.init(proto: proto,
                  items: items)
    }

    public init(from decoder: Swift.Decoder) throws {
        let singleValueContainer = try decoder.singleValueContainer()
        let serializedData = try singleValueContainer.decode(Data.self)
        try self.init(serializedData: serializedData)
    }
    public func encode(to encoder: Swift.Encoder) throws {
        var singleValueContainer = encoder.singleValueContainer()
        try singleValueContainer.encode(try serializedData())
    }

    public var debugDescription: String {
        return "\(proto)"
    }
}

extension StorageServiceProtoStorageItems {
    public static func builder() -> StorageServiceProtoStorageItemsBuilder {
        return StorageServiceProtoStorageItemsBuilder()
    }

    // asBuilder() constructs a builder that reflects the proto's contents.
    public func asBuilder() -> StorageServiceProtoStorageItemsBuilder {
        var builder = StorageServiceProtoStorageItemsBuilder()
        builder.setItems(items)
        if let _value = unknownFields {
            builder.setUnknownFields(_value)
        }
        return builder
    }
}

public struct StorageServiceProtoStorageItemsBuilder {

    private var proto = StorageServiceProtos_StorageItems()

    fileprivate init() {}

    public mutating func addItems(_ valueParam: StorageServiceProtoStorageItem) {
        proto.items.append(valueParam.proto)
    }

    public mutating func setItems(_ wrappedItems: [StorageServiceProtoStorageItem]) {
        proto.items = wrappedItems.map { $0.proto }
    }

    public mutating func setUnknownFields(_ unknownFields: SwiftProtobuf.UnknownStorage) {
        proto.unknownFields = unknownFields
    }

    public func build() throws -> StorageServiceProtoStorageItems {
        return try StorageServiceProtoStorageItems(proto)
    }

    public func buildSerializedData() throws -> Data {
        return try StorageServiceProtoStorageItems(proto).serializedData()
    }
}

#if TESTABLE_BUILD

extension StorageServiceProtoStorageItems {
    public func serializedDataIgnoringErrors() -> Data? {
        return try! self.serializedData()
    }
}

extension StorageServiceProtoStorageItemsBuilder {
    public func buildIgnoringErrors() -> StorageServiceProtoStorageItems? {
        return try! self.build()
    }
}

#endif

// MARK: - StorageServiceProtoStorageManifest

public struct StorageServiceProtoStorageManifest: Codable, CustomDebugStringConvertible {

    fileprivate let proto: StorageServiceProtos_StorageManifest

    public let version: UInt64

    public let value: Data

    public var hasUnknownFields: Bool {
        return !proto.unknownFields.data.isEmpty
    }
    public var unknownFields: SwiftProtobuf.UnknownStorage? {
        guard hasUnknownFields else { return nil }
        return proto.unknownFields
    }

    private init(proto: StorageServiceProtos_StorageManifest,
                 version: UInt64,
                 value: Data) {
        self.proto = proto
        self.version = version
        self.value = value
    }

    public func serializedData() throws -> Data {
        return try self.proto.serializedData()
    }

    public init(serializedData: Data) throws {
        let proto = try StorageServiceProtos_StorageManifest(serializedData: serializedData)
        try self.init(proto)
    }

    fileprivate init(_ proto: StorageServiceProtos_StorageManifest) throws {
        let version = proto.version

        let value = proto.value

        // MARK: - Begin Validation Logic for StorageServiceProtoStorageManifest -

        // MARK: - End Validation Logic for StorageServiceProtoStorageManifest -

        self.init(proto: proto,
                  version: version,
                  value: value)
    }

    public init(from decoder: Swift.Decoder) throws {
        let singleValueContainer = try decoder.singleValueContainer()
        let serializedData = try singleValueContainer.decode(Data.self)
        try self.init(serializedData: serializedData)
    }
    public func encode(to encoder: Swift.Encoder) throws {
        var singleValueContainer = encoder.singleValueContainer()
        try singleValueContainer.encode(try serializedData())
    }

    public var debugDescription: String {
        return "\(proto)"
    }
}

extension StorageServiceProtoStorageManifest {
    public static func builder(version: UInt64, value: Data) -> StorageServiceProtoStorageManifestBuilder {
        return StorageServiceProtoStorageManifestBuilder(version: version, value: value)
    }

    // asBuilder() constructs a builder that reflects the proto's contents.
    public func asBuilder() -> StorageServiceProtoStorageManifestBuilder {
        var builder = StorageServiceProtoStorageManifestBuilder(version: version, value: value)
        if let _value = unknownFields {
            builder.setUnknownFields(_value)
        }
        return builder
    }
}

public struct StorageServiceProtoStorageManifestBuilder {

    private var proto = StorageServiceProtos_StorageManifest()

    fileprivate init() {}

    fileprivate init(version: UInt64, value: Data) {

        setVersion(version)
        setValue(value)
    }

    public mutating func setVersion(_ valueParam: UInt64) {
        proto.version = valueParam
    }

    @available(swift, obsoleted: 1.0)
    public mutating func setValue(_ valueParam: Data?) {
        guard let valueParam = valueParam else { return }
        proto.value = valueParam
    }

    public mutating func setValue(_ valueParam: Data) {
        proto.value = valueParam
    }

    public mutating func setUnknownFields(_ unknownFields: SwiftProtobuf.UnknownStorage) {
        proto.unknownFields = unknownFields
    }

    public func build() throws -> StorageServiceProtoStorageManifest {
        return try StorageServiceProtoStorageManifest(proto)
    }

    public func buildSerializedData() throws -> Data {
        return try StorageServiceProtoStorageManifest(proto).serializedData()
    }
}

#if TESTABLE_BUILD

extension StorageServiceProtoStorageManifest {
    public func serializedDataIgnoringErrors() -> Data? {
        return try! self.serializedData()
    }
}

extension StorageServiceProtoStorageManifestBuilder {
    public func buildIgnoringErrors() -> StorageServiceProtoStorageManifest? {
        return try! self.build()
    }
}

#endif

// MARK: - StorageServiceProtoReadOperation

public struct StorageServiceProtoReadOperation: Codable, CustomDebugStringConvertible {

    fileprivate let proto: StorageServiceProtos_ReadOperation

    public var readKey: [Data] {
        return proto.readKey
    }

    public var hasUnknownFields: Bool {
        return !proto.unknownFields.data.isEmpty
    }
    public var unknownFields: SwiftProtobuf.UnknownStorage? {
        guard hasUnknownFields else { return nil }
        return proto.unknownFields
    }

    private init(proto: StorageServiceProtos_ReadOperation) {
        self.proto = proto
    }

    public func serializedData() throws -> Data {
        return try self.proto.serializedData()
    }

    public init(serializedData: Data) throws {
        let proto = try StorageServiceProtos_ReadOperation(serializedData: serializedData)
        try self.init(proto)
    }

    fileprivate init(_ proto: StorageServiceProtos_ReadOperation) throws {
        // MARK: - Begin Validation Logic for StorageServiceProtoReadOperation -

        // MARK: - End Validation Logic for StorageServiceProtoReadOperation -

        self.init(proto: proto)
    }

    public init(from decoder: Swift.Decoder) throws {
        let singleValueContainer = try decoder.singleValueContainer()
        let serializedData = try singleValueContainer.decode(Data.self)
        try self.init(serializedData: serializedData)
    }
    public func encode(to encoder: Swift.Encoder) throws {
        var singleValueContainer = encoder.singleValueContainer()
        try singleValueContainer.encode(try serializedData())
    }

    public var debugDescription: String {
        return "\(proto)"
    }
}

extension StorageServiceProtoReadOperation {
    public static func builder() -> StorageServiceProtoReadOperationBuilder {
        return StorageServiceProtoReadOperationBuilder()
    }

    // asBuilder() constructs a builder that reflects the proto's contents.
    public func asBuilder() -> StorageServiceProtoReadOperationBuilder {
        var builder = StorageServiceProtoReadOperationBuilder()
        builder.setReadKey(readKey)
        if let _value = unknownFields {
            builder.setUnknownFields(_value)
        }
        return builder
    }
}

public struct StorageServiceProtoReadOperationBuilder {

    private var proto = StorageServiceProtos_ReadOperation()

    fileprivate init() {}

    public mutating func addReadKey(_ valueParam: Data) {
        proto.readKey.append(valueParam)
    }

    public mutating func setReadKey(_ wrappedItems: [Data]) {
        proto.readKey = wrappedItems
    }

    public mutating func setUnknownFields(_ unknownFields: SwiftProtobuf.UnknownStorage) {
        proto.unknownFields = unknownFields
    }

    public func build() throws -> StorageServiceProtoReadOperation {
        return try StorageServiceProtoReadOperation(proto)
    }

    public func buildSerializedData() throws -> Data {
        return try StorageServiceProtoReadOperation(proto).serializedData()
    }
}

#if TESTABLE_BUILD

extension StorageServiceProtoReadOperation {
    public func serializedDataIgnoringErrors() -> Data? {
        return try! self.serializedData()
    }
}

extension StorageServiceProtoReadOperationBuilder {
    public func buildIgnoringErrors() -> StorageServiceProtoReadOperation? {
        return try! self.build()
    }
}

#endif

// MARK: - StorageServiceProtoWriteOperation

public struct StorageServiceProtoWriteOperation: Codable, CustomDebugStringConvertible {

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

    public var hasUnknownFields: Bool {
        return !proto.unknownFields.data.isEmpty
    }
    public var unknownFields: SwiftProtobuf.UnknownStorage? {
        guard hasUnknownFields else { return nil }
        return proto.unknownFields
    }

    private init(proto: StorageServiceProtos_WriteOperation,
                 manifest: StorageServiceProtoStorageManifest?,
                 insertItem: [StorageServiceProtoStorageItem]) {
        self.proto = proto
        self.manifest = manifest
        self.insertItem = insertItem
    }

    public func serializedData() throws -> Data {
        return try self.proto.serializedData()
    }

    public init(serializedData: Data) throws {
        let proto = try StorageServiceProtos_WriteOperation(serializedData: serializedData)
        try self.init(proto)
    }

    fileprivate init(_ proto: StorageServiceProtos_WriteOperation) throws {
        var manifest: StorageServiceProtoStorageManifest?
        if proto.hasManifest {
            manifest = try StorageServiceProtoStorageManifest(proto.manifest)
        }

        var insertItem: [StorageServiceProtoStorageItem] = []
        insertItem = try proto.insertItem.map { try StorageServiceProtoStorageItem($0) }

        // MARK: - Begin Validation Logic for StorageServiceProtoWriteOperation -

        // MARK: - End Validation Logic for StorageServiceProtoWriteOperation -

        self.init(proto: proto,
                  manifest: manifest,
                  insertItem: insertItem)
    }

    public init(from decoder: Swift.Decoder) throws {
        let singleValueContainer = try decoder.singleValueContainer()
        let serializedData = try singleValueContainer.decode(Data.self)
        try self.init(serializedData: serializedData)
    }
    public func encode(to encoder: Swift.Encoder) throws {
        var singleValueContainer = encoder.singleValueContainer()
        try singleValueContainer.encode(try serializedData())
    }

    public var debugDescription: String {
        return "\(proto)"
    }
}

extension StorageServiceProtoWriteOperation {
    public static func builder() -> StorageServiceProtoWriteOperationBuilder {
        return StorageServiceProtoWriteOperationBuilder()
    }

    // asBuilder() constructs a builder that reflects the proto's contents.
    public func asBuilder() -> StorageServiceProtoWriteOperationBuilder {
        var builder = StorageServiceProtoWriteOperationBuilder()
        if let _value = manifest {
            builder.setManifest(_value)
        }
        builder.setInsertItem(insertItem)
        builder.setDeleteKey(deleteKey)
        if hasDeleteAll {
            builder.setDeleteAll(deleteAll)
        }
        if let _value = unknownFields {
            builder.setUnknownFields(_value)
        }
        return builder
    }
}

public struct StorageServiceProtoWriteOperationBuilder {

    private var proto = StorageServiceProtos_WriteOperation()

    fileprivate init() {}

    @available(swift, obsoleted: 1.0)
    public mutating func setManifest(_ valueParam: StorageServiceProtoStorageManifest?) {
        guard let valueParam = valueParam else { return }
        proto.manifest = valueParam.proto
    }

    public mutating func setManifest(_ valueParam: StorageServiceProtoStorageManifest) {
        proto.manifest = valueParam.proto
    }

    public mutating func addInsertItem(_ valueParam: StorageServiceProtoStorageItem) {
        proto.insertItem.append(valueParam.proto)
    }

    public mutating func setInsertItem(_ wrappedItems: [StorageServiceProtoStorageItem]) {
        proto.insertItem = wrappedItems.map { $0.proto }
    }

    public mutating func addDeleteKey(_ valueParam: Data) {
        proto.deleteKey.append(valueParam)
    }

    public mutating func setDeleteKey(_ wrappedItems: [Data]) {
        proto.deleteKey = wrappedItems
    }

    public mutating func setDeleteAll(_ valueParam: Bool) {
        proto.deleteAll = valueParam
    }

    public mutating func setUnknownFields(_ unknownFields: SwiftProtobuf.UnknownStorage) {
        proto.unknownFields = unknownFields
    }

    public func build() throws -> StorageServiceProtoWriteOperation {
        return try StorageServiceProtoWriteOperation(proto)
    }

    public func buildSerializedData() throws -> Data {
        return try StorageServiceProtoWriteOperation(proto).serializedData()
    }
}

#if TESTABLE_BUILD

extension StorageServiceProtoWriteOperation {
    public func serializedDataIgnoringErrors() -> Data? {
        return try! self.serializedData()
    }
}

extension StorageServiceProtoWriteOperationBuilder {
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
    case storyDistributionList // 5
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
            case 5: self = .storyDistributionList
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
            case .storyDistributionList: return 5
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
    case .storyDistributionList: return .storyDistributionList
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
    case .storyDistributionList: return .storyDistributionList
    case .UNRECOGNIZED(let i): return .UNRECOGNIZED(i)
    }
}

// MARK: - StorageServiceProtoManifestRecordKey

public struct StorageServiceProtoManifestRecordKey: Codable, CustomDebugStringConvertible {

    fileprivate let proto: StorageServiceProtos_ManifestRecord.Key

    public let data: Data

    public let type: StorageServiceProtoManifestRecordKeyType

    public var hasUnknownFields: Bool {
        return !proto.unknownFields.data.isEmpty
    }
    public var unknownFields: SwiftProtobuf.UnknownStorage? {
        guard hasUnknownFields else { return nil }
        return proto.unknownFields
    }

    private init(proto: StorageServiceProtos_ManifestRecord.Key,
                 data: Data,
                 type: StorageServiceProtoManifestRecordKeyType) {
        self.proto = proto
        self.data = data
        self.type = type
    }

    public func serializedData() throws -> Data {
        return try self.proto.serializedData()
    }

    public init(serializedData: Data) throws {
        let proto = try StorageServiceProtos_ManifestRecord.Key(serializedData: serializedData)
        try self.init(proto)
    }

    fileprivate init(_ proto: StorageServiceProtos_ManifestRecord.Key) throws {
        let data = proto.data

        let type = StorageServiceProtoManifestRecordKeyTypeWrap(proto.type)

        // MARK: - Begin Validation Logic for StorageServiceProtoManifestRecordKey -

        // MARK: - End Validation Logic for StorageServiceProtoManifestRecordKey -

        self.init(proto: proto,
                  data: data,
                  type: type)
    }

    public init(from decoder: Swift.Decoder) throws {
        let singleValueContainer = try decoder.singleValueContainer()
        let serializedData = try singleValueContainer.decode(Data.self)
        try self.init(serializedData: serializedData)
    }
    public func encode(to encoder: Swift.Encoder) throws {
        var singleValueContainer = encoder.singleValueContainer()
        try singleValueContainer.encode(try serializedData())
    }

    public var debugDescription: String {
        return "\(proto)"
    }
}

extension StorageServiceProtoManifestRecordKey {
    public static func builder(data: Data, type: StorageServiceProtoManifestRecordKeyType) -> StorageServiceProtoManifestRecordKeyBuilder {
        return StorageServiceProtoManifestRecordKeyBuilder(data: data, type: type)
    }

    // asBuilder() constructs a builder that reflects the proto's contents.
    public func asBuilder() -> StorageServiceProtoManifestRecordKeyBuilder {
        var builder = StorageServiceProtoManifestRecordKeyBuilder(data: data, type: type)
        if let _value = unknownFields {
            builder.setUnknownFields(_value)
        }
        return builder
    }
}

public struct StorageServiceProtoManifestRecordKeyBuilder {

    private var proto = StorageServiceProtos_ManifestRecord.Key()

    fileprivate init() {}

    fileprivate init(data: Data, type: StorageServiceProtoManifestRecordKeyType) {

        setData(data)
        setType(type)
    }

    @available(swift, obsoleted: 1.0)
    public mutating func setData(_ valueParam: Data?) {
        guard let valueParam = valueParam else { return }
        proto.data = valueParam
    }

    public mutating func setData(_ valueParam: Data) {
        proto.data = valueParam
    }

    public mutating func setType(_ valueParam: StorageServiceProtoManifestRecordKeyType) {
        proto.type = StorageServiceProtoManifestRecordKeyTypeUnwrap(valueParam)
    }

    public mutating func setUnknownFields(_ unknownFields: SwiftProtobuf.UnknownStorage) {
        proto.unknownFields = unknownFields
    }

    public func build() throws -> StorageServiceProtoManifestRecordKey {
        return try StorageServiceProtoManifestRecordKey(proto)
    }

    public func buildSerializedData() throws -> Data {
        return try StorageServiceProtoManifestRecordKey(proto).serializedData()
    }
}

#if TESTABLE_BUILD

extension StorageServiceProtoManifestRecordKey {
    public func serializedDataIgnoringErrors() -> Data? {
        return try! self.serializedData()
    }
}

extension StorageServiceProtoManifestRecordKeyBuilder {
    public func buildIgnoringErrors() -> StorageServiceProtoManifestRecordKey? {
        return try! self.build()
    }
}

#endif

// MARK: - StorageServiceProtoManifestRecord

public struct StorageServiceProtoManifestRecord: Codable, CustomDebugStringConvertible {

    fileprivate let proto: StorageServiceProtos_ManifestRecord

    public let version: UInt64

    public let keys: [StorageServiceProtoManifestRecordKey]

    public var sourceDevice: UInt32 {
        return proto.sourceDevice
    }
    public var hasSourceDevice: Bool {
        return true
    }

    public var hasUnknownFields: Bool {
        return !proto.unknownFields.data.isEmpty
    }
    public var unknownFields: SwiftProtobuf.UnknownStorage? {
        guard hasUnknownFields else { return nil }
        return proto.unknownFields
    }

    private init(proto: StorageServiceProtos_ManifestRecord,
                 version: UInt64,
                 keys: [StorageServiceProtoManifestRecordKey]) {
        self.proto = proto
        self.version = version
        self.keys = keys
    }

    public func serializedData() throws -> Data {
        return try self.proto.serializedData()
    }

    public init(serializedData: Data) throws {
        let proto = try StorageServiceProtos_ManifestRecord(serializedData: serializedData)
        try self.init(proto)
    }

    fileprivate init(_ proto: StorageServiceProtos_ManifestRecord) throws {
        let version = proto.version

        var keys: [StorageServiceProtoManifestRecordKey] = []
        keys = try proto.keys.map { try StorageServiceProtoManifestRecordKey($0) }

        // MARK: - Begin Validation Logic for StorageServiceProtoManifestRecord -

        // MARK: - End Validation Logic for StorageServiceProtoManifestRecord -

        self.init(proto: proto,
                  version: version,
                  keys: keys)
    }

    public init(from decoder: Swift.Decoder) throws {
        let singleValueContainer = try decoder.singleValueContainer()
        let serializedData = try singleValueContainer.decode(Data.self)
        try self.init(serializedData: serializedData)
    }
    public func encode(to encoder: Swift.Encoder) throws {
        var singleValueContainer = encoder.singleValueContainer()
        try singleValueContainer.encode(try serializedData())
    }

    public var debugDescription: String {
        return "\(proto)"
    }
}

extension StorageServiceProtoManifestRecord {
    public static func builder(version: UInt64) -> StorageServiceProtoManifestRecordBuilder {
        return StorageServiceProtoManifestRecordBuilder(version: version)
    }

    // asBuilder() constructs a builder that reflects the proto's contents.
    public func asBuilder() -> StorageServiceProtoManifestRecordBuilder {
        var builder = StorageServiceProtoManifestRecordBuilder(version: version)
        if hasSourceDevice {
            builder.setSourceDevice(sourceDevice)
        }
        builder.setKeys(keys)
        if let _value = unknownFields {
            builder.setUnknownFields(_value)
        }
        return builder
    }
}

public struct StorageServiceProtoManifestRecordBuilder {

    private var proto = StorageServiceProtos_ManifestRecord()

    fileprivate init() {}

    fileprivate init(version: UInt64) {

        setVersion(version)
    }

    public mutating func setVersion(_ valueParam: UInt64) {
        proto.version = valueParam
    }

    public mutating func setSourceDevice(_ valueParam: UInt32) {
        proto.sourceDevice = valueParam
    }

    public mutating func addKeys(_ valueParam: StorageServiceProtoManifestRecordKey) {
        proto.keys.append(valueParam.proto)
    }

    public mutating func setKeys(_ wrappedItems: [StorageServiceProtoManifestRecordKey]) {
        proto.keys = wrappedItems.map { $0.proto }
    }

    public mutating func setUnknownFields(_ unknownFields: SwiftProtobuf.UnknownStorage) {
        proto.unknownFields = unknownFields
    }

    public func build() throws -> StorageServiceProtoManifestRecord {
        return try StorageServiceProtoManifestRecord(proto)
    }

    public func buildSerializedData() throws -> Data {
        return try StorageServiceProtoManifestRecord(proto).serializedData()
    }
}

#if TESTABLE_BUILD

extension StorageServiceProtoManifestRecord {
    public func serializedDataIgnoringErrors() -> Data? {
        return try! self.serializedData()
    }
}

extension StorageServiceProtoManifestRecordBuilder {
    public func buildIgnoringErrors() -> StorageServiceProtoManifestRecord? {
        return try! self.build()
    }
}

#endif

// MARK: - StorageServiceProtoStorageRecordOneOfRecord

public enum StorageServiceProtoStorageRecordOneOfRecord {
    case contact(StorageServiceProtoContactRecord)
    case groupV1(StorageServiceProtoGroupV1Record)
    case groupV2(StorageServiceProtoGroupV2Record)
    case account(StorageServiceProtoAccountRecord)
    case storyDistributionList(StorageServiceProtoStoryDistributionListRecord)
}

private func StorageServiceProtoStorageRecordOneOfRecordWrap(_ value: StorageServiceProtos_StorageRecord.OneOf_Record) throws -> StorageServiceProtoStorageRecordOneOfRecord {
    switch value {
    case .contact(let value): return .contact(try StorageServiceProtoContactRecord(value))
    case .groupV1(let value): return .groupV1(try StorageServiceProtoGroupV1Record(value))
    case .groupV2(let value): return .groupV2(try StorageServiceProtoGroupV2Record(value))
    case .account(let value): return .account(try StorageServiceProtoAccountRecord(value))
    case .storyDistributionList(let value): return .storyDistributionList(try StorageServiceProtoStoryDistributionListRecord(value))
    }
}

private func StorageServiceProtoStorageRecordOneOfRecordUnwrap(_ value: StorageServiceProtoStorageRecordOneOfRecord) -> StorageServiceProtos_StorageRecord.OneOf_Record {
    switch value {
    case .contact(let value): return .contact(value.proto)
    case .groupV1(let value): return .groupV1(value.proto)
    case .groupV2(let value): return .groupV2(value.proto)
    case .account(let value): return .account(value.proto)
    case .storyDistributionList(let value): return .storyDistributionList(value.proto)
    }
}

// MARK: - StorageServiceProtoStorageRecord

public struct StorageServiceProtoStorageRecord: Codable, CustomDebugStringConvertible {

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

    public var hasUnknownFields: Bool {
        return !proto.unknownFields.data.isEmpty
    }
    public var unknownFields: SwiftProtobuf.UnknownStorage? {
        guard hasUnknownFields else { return nil }
        return proto.unknownFields
    }

    private init(proto: StorageServiceProtos_StorageRecord) {
        self.proto = proto
    }

    public func serializedData() throws -> Data {
        return try self.proto.serializedData()
    }

    public init(serializedData: Data) throws {
        let proto = try StorageServiceProtos_StorageRecord(serializedData: serializedData)
        try self.init(proto)
    }

    fileprivate init(_ proto: StorageServiceProtos_StorageRecord) throws {
        // MARK: - Begin Validation Logic for StorageServiceProtoStorageRecord -

        // MARK: - End Validation Logic for StorageServiceProtoStorageRecord -

        self.init(proto: proto)
    }

    public init(from decoder: Swift.Decoder) throws {
        let singleValueContainer = try decoder.singleValueContainer()
        let serializedData = try singleValueContainer.decode(Data.self)
        try self.init(serializedData: serializedData)
    }
    public func encode(to encoder: Swift.Encoder) throws {
        var singleValueContainer = encoder.singleValueContainer()
        try singleValueContainer.encode(try serializedData())
    }

    public var debugDescription: String {
        return "\(proto)"
    }
}

extension StorageServiceProtoStorageRecord {
    public static func builder() -> StorageServiceProtoStorageRecordBuilder {
        return StorageServiceProtoStorageRecordBuilder()
    }

    // asBuilder() constructs a builder that reflects the proto's contents.
    public func asBuilder() -> StorageServiceProtoStorageRecordBuilder {
        var builder = StorageServiceProtoStorageRecordBuilder()
        if let _value = record {
            builder.setRecord(_value)
        }
        if let _value = unknownFields {
            builder.setUnknownFields(_value)
        }
        return builder
    }
}

public struct StorageServiceProtoStorageRecordBuilder {

    private var proto = StorageServiceProtos_StorageRecord()

    fileprivate init() {}

    @available(swift, obsoleted: 1.0)
    public mutating func setRecord(_ valueParam: StorageServiceProtoStorageRecordOneOfRecord?) {
        guard let valueParam = valueParam else { return }
        proto.record = StorageServiceProtoStorageRecordOneOfRecordUnwrap(valueParam)
    }

    public mutating func setRecord(_ valueParam: StorageServiceProtoStorageRecordOneOfRecord) {
        proto.record = StorageServiceProtoStorageRecordOneOfRecordUnwrap(valueParam)
    }

    public mutating func setUnknownFields(_ unknownFields: SwiftProtobuf.UnknownStorage) {
        proto.unknownFields = unknownFields
    }

    public func build() throws -> StorageServiceProtoStorageRecord {
        return try StorageServiceProtoStorageRecord(proto)
    }

    public func buildSerializedData() throws -> Data {
        return try StorageServiceProtoStorageRecord(proto).serializedData()
    }
}

#if TESTABLE_BUILD

extension StorageServiceProtoStorageRecord {
    public func serializedDataIgnoringErrors() -> Data? {
        return try! self.serializedData()
    }
}

extension StorageServiceProtoStorageRecordBuilder {
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
        self = .default
    }

    public init?(rawValue: Int) {
        switch rawValue {
            case 0: self = .default
            case 1: self = .verified
            case 2: self = .unverified
            default: self = .UNRECOGNIZED(rawValue)
        }
    }

    public var rawValue: Int {
        switch self {
            case .default: return 0
            case .verified: return 1
            case .unverified: return 2
            case .UNRECOGNIZED(let i): return i
        }
    }
}

private func StorageServiceProtoContactRecordIdentityStateWrap(_ value: StorageServiceProtos_ContactRecord.IdentityState) -> StorageServiceProtoContactRecordIdentityState {
    switch value {
    case .default: return .default
    case .verified: return .verified
    case .unverified: return .unverified
    case .UNRECOGNIZED(let i): return .UNRECOGNIZED(i)
    }
}

private func StorageServiceProtoContactRecordIdentityStateUnwrap(_ value: StorageServiceProtoContactRecordIdentityState) -> StorageServiceProtos_ContactRecord.IdentityState {
    switch value {
    case .default: return .default
    case .verified: return .verified
    case .unverified: return .unverified
    case .UNRECOGNIZED(let i): return .UNRECOGNIZED(i)
    }
}

// MARK: - StorageServiceProtoContactRecord

public struct StorageServiceProtoContactRecord: Codable, CustomDebugStringConvertible {

    fileprivate let proto: StorageServiceProtos_ContactRecord

    public var serviceUuid: String? {
        guard hasServiceUuid else {
            return nil
        }
        return proto.serviceUuid
    }
    public var hasServiceUuid: Bool {
        return !proto.serviceUuid.isEmpty
    }

    public var serviceE164: String? {
        guard hasServiceE164 else {
            return nil
        }
        return proto.serviceE164
    }
    public var hasServiceE164: Bool {
        return !proto.serviceE164.isEmpty
    }

    public var profileKey: Data? {
        guard hasProfileKey else {
            return nil
        }
        return proto.profileKey
    }
    public var hasProfileKey: Bool {
        return !proto.profileKey.isEmpty
    }

    public var identityKey: Data? {
        guard hasIdentityKey else {
            return nil
        }
        return proto.identityKey
    }
    public var hasIdentityKey: Bool {
        return !proto.identityKey.isEmpty
    }

    public var identityState: StorageServiceProtoContactRecordIdentityState? {
        guard hasIdentityState else {
            return nil
        }
        return StorageServiceProtoContactRecordIdentityStateWrap(proto.identityState)
    }
    // This "unwrapped" accessor should only be used if the "has value" accessor has already been checked.
    public var unwrappedIdentityState: StorageServiceProtoContactRecordIdentityState {
        if !hasIdentityState {
            // TODO: We could make this a crashing assert.
            owsFailDebug("Unsafe unwrap of missing optional: ContactRecord.identityState.")
        }
        return StorageServiceProtoContactRecordIdentityStateWrap(proto.identityState)
    }
    public var hasIdentityState: Bool {
        return true
    }

    public var givenName: String? {
        guard hasGivenName else {
            return nil
        }
        return proto.givenName
    }
    public var hasGivenName: Bool {
        return !proto.givenName.isEmpty
    }

    public var familyName: String? {
        guard hasFamilyName else {
            return nil
        }
        return proto.familyName
    }
    public var hasFamilyName: Bool {
        return !proto.familyName.isEmpty
    }

    public var username: String? {
        guard hasUsername else {
            return nil
        }
        return proto.username
    }
    public var hasUsername: Bool {
        return !proto.username.isEmpty
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

    public var archived: Bool {
        return proto.archived
    }
    public var hasArchived: Bool {
        return true
    }

    public var markedUnread: Bool {
        return proto.markedUnread
    }
    public var hasMarkedUnread: Bool {
        return true
    }

    public var mutedUntilTimestamp: UInt64 {
        return proto.mutedUntilTimestamp
    }
    public var hasMutedUntilTimestamp: Bool {
        return true
    }

    public var hideStory: Bool {
        return proto.hideStory
    }
    public var hasHideStory: Bool {
        return true
    }

    public var unregisteredAtTimestamp: UInt64 {
        return proto.unregisteredAtTimestamp
    }
    public var hasUnregisteredAtTimestamp: Bool {
        return true
    }

    public var systemGivenName: String? {
        guard hasSystemGivenName else {
            return nil
        }
        return proto.systemGivenName
    }
    public var hasSystemGivenName: Bool {
        return !proto.systemGivenName.isEmpty
    }

    public var systemFamilyName: String? {
        guard hasSystemFamilyName else {
            return nil
        }
        return proto.systemFamilyName
    }
    public var hasSystemFamilyName: Bool {
        return !proto.systemFamilyName.isEmpty
    }

    public var systemNickname: String? {
        guard hasSystemNickname else {
            return nil
        }
        return proto.systemNickname
    }
    public var hasSystemNickname: Bool {
        return !proto.systemNickname.isEmpty
    }

    public var hasValidService: Bool {
        return serviceAddress != nil
    }
    public let serviceAddress: SignalServiceAddress?

    public var hasUnknownFields: Bool {
        return !proto.unknownFields.data.isEmpty
    }
    public var unknownFields: SwiftProtobuf.UnknownStorage? {
        guard hasUnknownFields else { return nil }
        return proto.unknownFields
    }

    private init(proto: StorageServiceProtos_ContactRecord) {
        self.proto = proto

        let hasServiceUuid = !proto.serviceUuid.isEmpty
        let hasServiceE164 = !proto.serviceE164.isEmpty
        let serviceUuid: String? = proto.serviceUuid
        let serviceE164: String? = proto.serviceE164
        self.serviceAddress = {
            guard hasServiceUuid || hasServiceE164 else { return nil }

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
                    return nil
                }

                return ProtoUtils.parseProtoE164(serviceE164, name: "StorageServiceProtos_ContactRecord.serviceE164")
            }()

            let address = SignalServiceAddress(
                uuidString: uuidString,
                phoneNumber: phoneNumber,
                trustLevel: .high
            )
            guard address.isValid else {
                owsFailDebug("address was unexpectedly invalid")
                return nil
            }

            return address
        }()
    }

    public func serializedData() throws -> Data {
        return try self.proto.serializedData()
    }

    public init(serializedData: Data) throws {
        let proto = try StorageServiceProtos_ContactRecord(serializedData: serializedData)
        try self.init(proto)
    }

    fileprivate init(_ proto: StorageServiceProtos_ContactRecord) throws {
        // MARK: - Begin Validation Logic for StorageServiceProtoContactRecord -

        // MARK: - End Validation Logic for StorageServiceProtoContactRecord -

        self.init(proto: proto)
    }

    public init(from decoder: Swift.Decoder) throws {
        let singleValueContainer = try decoder.singleValueContainer()
        let serializedData = try singleValueContainer.decode(Data.self)
        try self.init(serializedData: serializedData)
    }
    public func encode(to encoder: Swift.Encoder) throws {
        var singleValueContainer = encoder.singleValueContainer()
        try singleValueContainer.encode(try serializedData())
    }

    public var debugDescription: String {
        return "\(proto)"
    }
}

extension StorageServiceProtoContactRecord {
    public static func builder() -> StorageServiceProtoContactRecordBuilder {
        return StorageServiceProtoContactRecordBuilder()
    }

    // asBuilder() constructs a builder that reflects the proto's contents.
    public func asBuilder() -> StorageServiceProtoContactRecordBuilder {
        var builder = StorageServiceProtoContactRecordBuilder()
        if let _value = serviceUuid {
            builder.setServiceUuid(_value)
        }
        if let _value = serviceE164 {
            builder.setServiceE164(_value)
        }
        if let _value = profileKey {
            builder.setProfileKey(_value)
        }
        if let _value = identityKey {
            builder.setIdentityKey(_value)
        }
        if let _value = identityState {
            builder.setIdentityState(_value)
        }
        if let _value = givenName {
            builder.setGivenName(_value)
        }
        if let _value = familyName {
            builder.setFamilyName(_value)
        }
        if let _value = username {
            builder.setUsername(_value)
        }
        if hasBlocked {
            builder.setBlocked(blocked)
        }
        if hasWhitelisted {
            builder.setWhitelisted(whitelisted)
        }
        if hasArchived {
            builder.setArchived(archived)
        }
        if hasMarkedUnread {
            builder.setMarkedUnread(markedUnread)
        }
        if hasMutedUntilTimestamp {
            builder.setMutedUntilTimestamp(mutedUntilTimestamp)
        }
        if hasHideStory {
            builder.setHideStory(hideStory)
        }
        if hasUnregisteredAtTimestamp {
            builder.setUnregisteredAtTimestamp(unregisteredAtTimestamp)
        }
        if let _value = systemGivenName {
            builder.setSystemGivenName(_value)
        }
        if let _value = systemFamilyName {
            builder.setSystemFamilyName(_value)
        }
        if let _value = systemNickname {
            builder.setSystemNickname(_value)
        }
        if let _value = unknownFields {
            builder.setUnknownFields(_value)
        }
        return builder
    }
}

public struct StorageServiceProtoContactRecordBuilder {

    private var proto = StorageServiceProtos_ContactRecord()

    fileprivate init() {}

    @available(swift, obsoleted: 1.0)
    public mutating func setServiceUuid(_ valueParam: String?) {
        guard let valueParam = valueParam else { return }
        proto.serviceUuid = valueParam
    }

    public mutating func setServiceUuid(_ valueParam: String) {
        proto.serviceUuid = valueParam
    }

    @available(swift, obsoleted: 1.0)
    public mutating func setServiceE164(_ valueParam: String?) {
        guard let valueParam = valueParam else { return }
        if let valueParam = valueParam.nilIfEmpty {
            owsAssertDebug(PhoneNumber.resemblesE164(valueParam))
        }

        proto.serviceE164 = valueParam
    }

    public mutating func setServiceE164(_ valueParam: String) {
        if let valueParam = valueParam.nilIfEmpty {
            owsAssertDebug(PhoneNumber.resemblesE164(valueParam))
        }

        proto.serviceE164 = valueParam
    }

    @available(swift, obsoleted: 1.0)
    public mutating func setProfileKey(_ valueParam: Data?) {
        guard let valueParam = valueParam else { return }
        proto.profileKey = valueParam
    }

    public mutating func setProfileKey(_ valueParam: Data) {
        proto.profileKey = valueParam
    }

    @available(swift, obsoleted: 1.0)
    public mutating func setIdentityKey(_ valueParam: Data?) {
        guard let valueParam = valueParam else { return }
        proto.identityKey = valueParam
    }

    public mutating func setIdentityKey(_ valueParam: Data) {
        proto.identityKey = valueParam
    }

    public mutating func setIdentityState(_ valueParam: StorageServiceProtoContactRecordIdentityState) {
        proto.identityState = StorageServiceProtoContactRecordIdentityStateUnwrap(valueParam)
    }

    @available(swift, obsoleted: 1.0)
    public mutating func setGivenName(_ valueParam: String?) {
        guard let valueParam = valueParam else { return }
        proto.givenName = valueParam
    }

    public mutating func setGivenName(_ valueParam: String) {
        proto.givenName = valueParam
    }

    @available(swift, obsoleted: 1.0)
    public mutating func setFamilyName(_ valueParam: String?) {
        guard let valueParam = valueParam else { return }
        proto.familyName = valueParam
    }

    public mutating func setFamilyName(_ valueParam: String) {
        proto.familyName = valueParam
    }

    @available(swift, obsoleted: 1.0)
    public mutating func setUsername(_ valueParam: String?) {
        guard let valueParam = valueParam else { return }
        proto.username = valueParam
    }

    public mutating func setUsername(_ valueParam: String) {
        proto.username = valueParam
    }

    public mutating func setBlocked(_ valueParam: Bool) {
        proto.blocked = valueParam
    }

    public mutating func setWhitelisted(_ valueParam: Bool) {
        proto.whitelisted = valueParam
    }

    public mutating func setArchived(_ valueParam: Bool) {
        proto.archived = valueParam
    }

    public mutating func setMarkedUnread(_ valueParam: Bool) {
        proto.markedUnread = valueParam
    }

    public mutating func setMutedUntilTimestamp(_ valueParam: UInt64) {
        proto.mutedUntilTimestamp = valueParam
    }

    public mutating func setHideStory(_ valueParam: Bool) {
        proto.hideStory = valueParam
    }

    public mutating func setUnregisteredAtTimestamp(_ valueParam: UInt64) {
        proto.unregisteredAtTimestamp = valueParam
    }

    @available(swift, obsoleted: 1.0)
    public mutating func setSystemGivenName(_ valueParam: String?) {
        guard let valueParam = valueParam else { return }
        proto.systemGivenName = valueParam
    }

    public mutating func setSystemGivenName(_ valueParam: String) {
        proto.systemGivenName = valueParam
    }

    @available(swift, obsoleted: 1.0)
    public mutating func setSystemFamilyName(_ valueParam: String?) {
        guard let valueParam = valueParam else { return }
        proto.systemFamilyName = valueParam
    }

    public mutating func setSystemFamilyName(_ valueParam: String) {
        proto.systemFamilyName = valueParam
    }

    @available(swift, obsoleted: 1.0)
    public mutating func setSystemNickname(_ valueParam: String?) {
        guard let valueParam = valueParam else { return }
        proto.systemNickname = valueParam
    }

    public mutating func setSystemNickname(_ valueParam: String) {
        proto.systemNickname = valueParam
    }

    public mutating func setUnknownFields(_ unknownFields: SwiftProtobuf.UnknownStorage) {
        proto.unknownFields = unknownFields
    }

    public func build() throws -> StorageServiceProtoContactRecord {
        return try StorageServiceProtoContactRecord(proto)
    }

    public func buildSerializedData() throws -> Data {
        return try StorageServiceProtoContactRecord(proto).serializedData()
    }
}

#if TESTABLE_BUILD

extension StorageServiceProtoContactRecord {
    public func serializedDataIgnoringErrors() -> Data? {
        return try! self.serializedData()
    }
}

extension StorageServiceProtoContactRecordBuilder {
    public func buildIgnoringErrors() -> StorageServiceProtoContactRecord? {
        return try! self.build()
    }
}

#endif

// MARK: - StorageServiceProtoGroupV1Record

public struct StorageServiceProtoGroupV1Record: Codable, CustomDebugStringConvertible {

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

    public var archived: Bool {
        return proto.archived
    }
    public var hasArchived: Bool {
        return true
    }

    public var markedUnread: Bool {
        return proto.markedUnread
    }
    public var hasMarkedUnread: Bool {
        return true
    }

    public var mutedUntilTimestamp: UInt64 {
        return proto.mutedUntilTimestamp
    }
    public var hasMutedUntilTimestamp: Bool {
        return true
    }

    public var hasUnknownFields: Bool {
        return !proto.unknownFields.data.isEmpty
    }
    public var unknownFields: SwiftProtobuf.UnknownStorage? {
        guard hasUnknownFields else { return nil }
        return proto.unknownFields
    }

    private init(proto: StorageServiceProtos_GroupV1Record,
                 id: Data) {
        self.proto = proto
        self.id = id
    }

    public func serializedData() throws -> Data {
        return try self.proto.serializedData()
    }

    public init(serializedData: Data) throws {
        let proto = try StorageServiceProtos_GroupV1Record(serializedData: serializedData)
        try self.init(proto)
    }

    fileprivate init(_ proto: StorageServiceProtos_GroupV1Record) throws {
        let id = proto.id

        // MARK: - Begin Validation Logic for StorageServiceProtoGroupV1Record -

        // MARK: - End Validation Logic for StorageServiceProtoGroupV1Record -

        self.init(proto: proto,
                  id: id)
    }

    public init(from decoder: Swift.Decoder) throws {
        let singleValueContainer = try decoder.singleValueContainer()
        let serializedData = try singleValueContainer.decode(Data.self)
        try self.init(serializedData: serializedData)
    }
    public func encode(to encoder: Swift.Encoder) throws {
        var singleValueContainer = encoder.singleValueContainer()
        try singleValueContainer.encode(try serializedData())
    }

    public var debugDescription: String {
        return "\(proto)"
    }
}

extension StorageServiceProtoGroupV1Record {
    public static func builder(id: Data) -> StorageServiceProtoGroupV1RecordBuilder {
        return StorageServiceProtoGroupV1RecordBuilder(id: id)
    }

    // asBuilder() constructs a builder that reflects the proto's contents.
    public func asBuilder() -> StorageServiceProtoGroupV1RecordBuilder {
        var builder = StorageServiceProtoGroupV1RecordBuilder(id: id)
        if hasBlocked {
            builder.setBlocked(blocked)
        }
        if hasWhitelisted {
            builder.setWhitelisted(whitelisted)
        }
        if hasArchived {
            builder.setArchived(archived)
        }
        if hasMarkedUnread {
            builder.setMarkedUnread(markedUnread)
        }
        if hasMutedUntilTimestamp {
            builder.setMutedUntilTimestamp(mutedUntilTimestamp)
        }
        if let _value = unknownFields {
            builder.setUnknownFields(_value)
        }
        return builder
    }
}

public struct StorageServiceProtoGroupV1RecordBuilder {

    private var proto = StorageServiceProtos_GroupV1Record()

    fileprivate init() {}

    fileprivate init(id: Data) {

        setId(id)
    }

    @available(swift, obsoleted: 1.0)
    public mutating func setId(_ valueParam: Data?) {
        guard let valueParam = valueParam else { return }
        proto.id = valueParam
    }

    public mutating func setId(_ valueParam: Data) {
        proto.id = valueParam
    }

    public mutating func setBlocked(_ valueParam: Bool) {
        proto.blocked = valueParam
    }

    public mutating func setWhitelisted(_ valueParam: Bool) {
        proto.whitelisted = valueParam
    }

    public mutating func setArchived(_ valueParam: Bool) {
        proto.archived = valueParam
    }

    public mutating func setMarkedUnread(_ valueParam: Bool) {
        proto.markedUnread = valueParam
    }

    public mutating func setMutedUntilTimestamp(_ valueParam: UInt64) {
        proto.mutedUntilTimestamp = valueParam
    }

    public mutating func setUnknownFields(_ unknownFields: SwiftProtobuf.UnknownStorage) {
        proto.unknownFields = unknownFields
    }

    public func build() throws -> StorageServiceProtoGroupV1Record {
        return try StorageServiceProtoGroupV1Record(proto)
    }

    public func buildSerializedData() throws -> Data {
        return try StorageServiceProtoGroupV1Record(proto).serializedData()
    }
}

#if TESTABLE_BUILD

extension StorageServiceProtoGroupV1Record {
    public func serializedDataIgnoringErrors() -> Data? {
        return try! self.serializedData()
    }
}

extension StorageServiceProtoGroupV1RecordBuilder {
    public func buildIgnoringErrors() -> StorageServiceProtoGroupV1Record? {
        return try! self.build()
    }
}

#endif

// MARK: - StorageServiceProtoGroupV2RecordStorySendMode

public enum StorageServiceProtoGroupV2RecordStorySendMode: SwiftProtobuf.Enum {
    public typealias RawValue = Int
    case `default` // 0
    case disabled // 1
    case enabled // 2
    case UNRECOGNIZED(Int)

    public init() {
        self = .default
    }

    public init?(rawValue: Int) {
        switch rawValue {
            case 0: self = .default
            case 1: self = .disabled
            case 2: self = .enabled
            default: self = .UNRECOGNIZED(rawValue)
        }
    }

    public var rawValue: Int {
        switch self {
            case .default: return 0
            case .disabled: return 1
            case .enabled: return 2
            case .UNRECOGNIZED(let i): return i
        }
    }
}

private func StorageServiceProtoGroupV2RecordStorySendModeWrap(_ value: StorageServiceProtos_GroupV2Record.StorySendMode) -> StorageServiceProtoGroupV2RecordStorySendMode {
    switch value {
    case .default: return .default
    case .disabled: return .disabled
    case .enabled: return .enabled
    case .UNRECOGNIZED(let i): return .UNRECOGNIZED(i)
    }
}

private func StorageServiceProtoGroupV2RecordStorySendModeUnwrap(_ value: StorageServiceProtoGroupV2RecordStorySendMode) -> StorageServiceProtos_GroupV2Record.StorySendMode {
    switch value {
    case .default: return .default
    case .disabled: return .disabled
    case .enabled: return .enabled
    case .UNRECOGNIZED(let i): return .UNRECOGNIZED(i)
    }
}

// MARK: - StorageServiceProtoGroupV2Record

public struct StorageServiceProtoGroupV2Record: Codable, CustomDebugStringConvertible {

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

    public var archived: Bool {
        return proto.archived
    }
    public var hasArchived: Bool {
        return true
    }

    public var markedUnread: Bool {
        return proto.markedUnread
    }
    public var hasMarkedUnread: Bool {
        return true
    }

    public var mutedUntilTimestamp: UInt64 {
        return proto.mutedUntilTimestamp
    }
    public var hasMutedUntilTimestamp: Bool {
        return true
    }

    public var hideStory: Bool {
        return proto.hideStory
    }
    public var hasHideStory: Bool {
        return true
    }

    public var storySendMode: StorageServiceProtoGroupV2RecordStorySendMode? {
        guard hasStorySendMode else {
            return nil
        }
        return StorageServiceProtoGroupV2RecordStorySendModeWrap(proto.storySendMode)
    }
    // This "unwrapped" accessor should only be used if the "has value" accessor has already been checked.
    public var unwrappedStorySendMode: StorageServiceProtoGroupV2RecordStorySendMode {
        if !hasStorySendMode {
            // TODO: We could make this a crashing assert.
            owsFailDebug("Unsafe unwrap of missing optional: GroupV2Record.storySendMode.")
        }
        return StorageServiceProtoGroupV2RecordStorySendModeWrap(proto.storySendMode)
    }
    public var hasStorySendMode: Bool {
        return true
    }

    public var hasUnknownFields: Bool {
        return !proto.unknownFields.data.isEmpty
    }
    public var unknownFields: SwiftProtobuf.UnknownStorage? {
        guard hasUnknownFields else { return nil }
        return proto.unknownFields
    }

    private init(proto: StorageServiceProtos_GroupV2Record,
                 masterKey: Data) {
        self.proto = proto
        self.masterKey = masterKey
    }

    public func serializedData() throws -> Data {
        return try self.proto.serializedData()
    }

    public init(serializedData: Data) throws {
        let proto = try StorageServiceProtos_GroupV2Record(serializedData: serializedData)
        try self.init(proto)
    }

    fileprivate init(_ proto: StorageServiceProtos_GroupV2Record) throws {
        let masterKey = proto.masterKey

        // MARK: - Begin Validation Logic for StorageServiceProtoGroupV2Record -

        // MARK: - End Validation Logic for StorageServiceProtoGroupV2Record -

        self.init(proto: proto,
                  masterKey: masterKey)
    }

    public init(from decoder: Swift.Decoder) throws {
        let singleValueContainer = try decoder.singleValueContainer()
        let serializedData = try singleValueContainer.decode(Data.self)
        try self.init(serializedData: serializedData)
    }
    public func encode(to encoder: Swift.Encoder) throws {
        var singleValueContainer = encoder.singleValueContainer()
        try singleValueContainer.encode(try serializedData())
    }

    public var debugDescription: String {
        return "\(proto)"
    }
}

extension StorageServiceProtoGroupV2Record {
    public static func builder(masterKey: Data) -> StorageServiceProtoGroupV2RecordBuilder {
        return StorageServiceProtoGroupV2RecordBuilder(masterKey: masterKey)
    }

    // asBuilder() constructs a builder that reflects the proto's contents.
    public func asBuilder() -> StorageServiceProtoGroupV2RecordBuilder {
        var builder = StorageServiceProtoGroupV2RecordBuilder(masterKey: masterKey)
        if hasBlocked {
            builder.setBlocked(blocked)
        }
        if hasWhitelisted {
            builder.setWhitelisted(whitelisted)
        }
        if hasArchived {
            builder.setArchived(archived)
        }
        if hasMarkedUnread {
            builder.setMarkedUnread(markedUnread)
        }
        if hasMutedUntilTimestamp {
            builder.setMutedUntilTimestamp(mutedUntilTimestamp)
        }
        if hasHideStory {
            builder.setHideStory(hideStory)
        }
        if let _value = storySendMode {
            builder.setStorySendMode(_value)
        }
        if let _value = unknownFields {
            builder.setUnknownFields(_value)
        }
        return builder
    }
}

public struct StorageServiceProtoGroupV2RecordBuilder {

    private var proto = StorageServiceProtos_GroupV2Record()

    fileprivate init() {}

    fileprivate init(masterKey: Data) {

        setMasterKey(masterKey)
    }

    @available(swift, obsoleted: 1.0)
    public mutating func setMasterKey(_ valueParam: Data?) {
        guard let valueParam = valueParam else { return }
        proto.masterKey = valueParam
    }

    public mutating func setMasterKey(_ valueParam: Data) {
        proto.masterKey = valueParam
    }

    public mutating func setBlocked(_ valueParam: Bool) {
        proto.blocked = valueParam
    }

    public mutating func setWhitelisted(_ valueParam: Bool) {
        proto.whitelisted = valueParam
    }

    public mutating func setArchived(_ valueParam: Bool) {
        proto.archived = valueParam
    }

    public mutating func setMarkedUnread(_ valueParam: Bool) {
        proto.markedUnread = valueParam
    }

    public mutating func setMutedUntilTimestamp(_ valueParam: UInt64) {
        proto.mutedUntilTimestamp = valueParam
    }

    public mutating func setHideStory(_ valueParam: Bool) {
        proto.hideStory = valueParam
    }

    public mutating func setStorySendMode(_ valueParam: StorageServiceProtoGroupV2RecordStorySendMode) {
        proto.storySendMode = StorageServiceProtoGroupV2RecordStorySendModeUnwrap(valueParam)
    }

    public mutating func setUnknownFields(_ unknownFields: SwiftProtobuf.UnknownStorage) {
        proto.unknownFields = unknownFields
    }

    public func build() throws -> StorageServiceProtoGroupV2Record {
        return try StorageServiceProtoGroupV2Record(proto)
    }

    public func buildSerializedData() throws -> Data {
        return try StorageServiceProtoGroupV2Record(proto).serializedData()
    }
}

#if TESTABLE_BUILD

extension StorageServiceProtoGroupV2Record {
    public func serializedDataIgnoringErrors() -> Data? {
        return try! self.serializedData()
    }
}

extension StorageServiceProtoGroupV2RecordBuilder {
    public func buildIgnoringErrors() -> StorageServiceProtoGroupV2Record? {
        return try! self.build()
    }
}

#endif

// MARK: - StorageServiceProtoAccountRecordPinnedConversationContact

public struct StorageServiceProtoAccountRecordPinnedConversationContact: Codable, CustomDebugStringConvertible {

    fileprivate let proto: StorageServiceProtos_AccountRecord.PinnedConversation.Contact

    public var uuid: String? {
        guard hasUuid else {
            return nil
        }
        return proto.uuid
    }
    public var hasUuid: Bool {
        return !proto.uuid.isEmpty
    }

    public var e164: String? {
        guard hasE164 else {
            return nil
        }
        return proto.e164
    }
    public var hasE164: Bool {
        return !proto.e164.isEmpty
    }

    public var hasUnknownFields: Bool {
        return !proto.unknownFields.data.isEmpty
    }
    public var unknownFields: SwiftProtobuf.UnknownStorage? {
        guard hasUnknownFields else { return nil }
        return proto.unknownFields
    }

    private init(proto: StorageServiceProtos_AccountRecord.PinnedConversation.Contact) {
        self.proto = proto
    }

    public func serializedData() throws -> Data {
        return try self.proto.serializedData()
    }

    public init(serializedData: Data) throws {
        let proto = try StorageServiceProtos_AccountRecord.PinnedConversation.Contact(serializedData: serializedData)
        try self.init(proto)
    }

    fileprivate init(_ proto: StorageServiceProtos_AccountRecord.PinnedConversation.Contact) throws {
        // MARK: - Begin Validation Logic for StorageServiceProtoAccountRecordPinnedConversationContact -

        // MARK: - End Validation Logic for StorageServiceProtoAccountRecordPinnedConversationContact -

        self.init(proto: proto)
    }

    public init(from decoder: Swift.Decoder) throws {
        let singleValueContainer = try decoder.singleValueContainer()
        let serializedData = try singleValueContainer.decode(Data.self)
        try self.init(serializedData: serializedData)
    }
    public func encode(to encoder: Swift.Encoder) throws {
        var singleValueContainer = encoder.singleValueContainer()
        try singleValueContainer.encode(try serializedData())
    }

    public var debugDescription: String {
        return "\(proto)"
    }
}

extension StorageServiceProtoAccountRecordPinnedConversationContact {
    public static func builder() -> StorageServiceProtoAccountRecordPinnedConversationContactBuilder {
        return StorageServiceProtoAccountRecordPinnedConversationContactBuilder()
    }

    // asBuilder() constructs a builder that reflects the proto's contents.
    public func asBuilder() -> StorageServiceProtoAccountRecordPinnedConversationContactBuilder {
        var builder = StorageServiceProtoAccountRecordPinnedConversationContactBuilder()
        if let _value = uuid {
            builder.setUuid(_value)
        }
        if let _value = e164 {
            builder.setE164(_value)
        }
        if let _value = unknownFields {
            builder.setUnknownFields(_value)
        }
        return builder
    }
}

public struct StorageServiceProtoAccountRecordPinnedConversationContactBuilder {

    private var proto = StorageServiceProtos_AccountRecord.PinnedConversation.Contact()

    fileprivate init() {}

    @available(swift, obsoleted: 1.0)
    public mutating func setUuid(_ valueParam: String?) {
        guard let valueParam = valueParam else { return }
        proto.uuid = valueParam
    }

    public mutating func setUuid(_ valueParam: String) {
        proto.uuid = valueParam
    }

    @available(swift, obsoleted: 1.0)
    public mutating func setE164(_ valueParam: String?) {
        guard let valueParam = valueParam else { return }
        proto.e164 = valueParam
    }

    public mutating func setE164(_ valueParam: String) {
        proto.e164 = valueParam
    }

    public mutating func setUnknownFields(_ unknownFields: SwiftProtobuf.UnknownStorage) {
        proto.unknownFields = unknownFields
    }

    public func build() throws -> StorageServiceProtoAccountRecordPinnedConversationContact {
        return try StorageServiceProtoAccountRecordPinnedConversationContact(proto)
    }

    public func buildSerializedData() throws -> Data {
        return try StorageServiceProtoAccountRecordPinnedConversationContact(proto).serializedData()
    }
}

#if TESTABLE_BUILD

extension StorageServiceProtoAccountRecordPinnedConversationContact {
    public func serializedDataIgnoringErrors() -> Data? {
        return try! self.serializedData()
    }
}

extension StorageServiceProtoAccountRecordPinnedConversationContactBuilder {
    public func buildIgnoringErrors() -> StorageServiceProtoAccountRecordPinnedConversationContact? {
        return try! self.build()
    }
}

#endif

// MARK: - StorageServiceProtoAccountRecordPinnedConversationOneOfIdentifier

public enum StorageServiceProtoAccountRecordPinnedConversationOneOfIdentifier {
    case contact(StorageServiceProtoAccountRecordPinnedConversationContact)
    case legacyGroupID(Data)
    case groupMasterKey(Data)
}

private func StorageServiceProtoAccountRecordPinnedConversationOneOfIdentifierWrap(_ value: StorageServiceProtos_AccountRecord.PinnedConversation.OneOf_Identifier) throws -> StorageServiceProtoAccountRecordPinnedConversationOneOfIdentifier {
    switch value {
    case .contact(let value): return .contact(try StorageServiceProtoAccountRecordPinnedConversationContact(value))
    case .legacyGroupID(let value): return .legacyGroupID(value)
    case .groupMasterKey(let value): return .groupMasterKey(value)
    }
}

private func StorageServiceProtoAccountRecordPinnedConversationOneOfIdentifierUnwrap(_ value: StorageServiceProtoAccountRecordPinnedConversationOneOfIdentifier) -> StorageServiceProtos_AccountRecord.PinnedConversation.OneOf_Identifier {
    switch value {
    case .contact(let value): return .contact(value.proto)
    case .legacyGroupID(let value): return .legacyGroupID(value)
    case .groupMasterKey(let value): return .groupMasterKey(value)
    }
}

// MARK: - StorageServiceProtoAccountRecordPinnedConversation

public struct StorageServiceProtoAccountRecordPinnedConversation: Codable, CustomDebugStringConvertible {

    fileprivate let proto: StorageServiceProtos_AccountRecord.PinnedConversation

    public var identifier: StorageServiceProtoAccountRecordPinnedConversationOneOfIdentifier? {
        guard hasIdentifier else {
            return nil
        }
        guard let identifier = proto.identifier else {
            owsFailDebug("identifier was unexpectedly nil")
            return nil
        }
        guard let unwrappedIdentifier = try? StorageServiceProtoAccountRecordPinnedConversationOneOfIdentifierWrap(identifier) else {
            owsFailDebug("failed to unwrap identifier")
            return nil
        }
        return unwrappedIdentifier
    }
    public var hasIdentifier: Bool {
        return true
    }

    public var hasUnknownFields: Bool {
        return !proto.unknownFields.data.isEmpty
    }
    public var unknownFields: SwiftProtobuf.UnknownStorage? {
        guard hasUnknownFields else { return nil }
        return proto.unknownFields
    }

    private init(proto: StorageServiceProtos_AccountRecord.PinnedConversation) {
        self.proto = proto
    }

    public func serializedData() throws -> Data {
        return try self.proto.serializedData()
    }

    public init(serializedData: Data) throws {
        let proto = try StorageServiceProtos_AccountRecord.PinnedConversation(serializedData: serializedData)
        try self.init(proto)
    }

    fileprivate init(_ proto: StorageServiceProtos_AccountRecord.PinnedConversation) throws {
        // MARK: - Begin Validation Logic for StorageServiceProtoAccountRecordPinnedConversation -

        // MARK: - End Validation Logic for StorageServiceProtoAccountRecordPinnedConversation -

        self.init(proto: proto)
    }

    public init(from decoder: Swift.Decoder) throws {
        let singleValueContainer = try decoder.singleValueContainer()
        let serializedData = try singleValueContainer.decode(Data.self)
        try self.init(serializedData: serializedData)
    }
    public func encode(to encoder: Swift.Encoder) throws {
        var singleValueContainer = encoder.singleValueContainer()
        try singleValueContainer.encode(try serializedData())
    }

    public var debugDescription: String {
        return "\(proto)"
    }
}

extension StorageServiceProtoAccountRecordPinnedConversation {
    public static func builder() -> StorageServiceProtoAccountRecordPinnedConversationBuilder {
        return StorageServiceProtoAccountRecordPinnedConversationBuilder()
    }

    // asBuilder() constructs a builder that reflects the proto's contents.
    public func asBuilder() -> StorageServiceProtoAccountRecordPinnedConversationBuilder {
        var builder = StorageServiceProtoAccountRecordPinnedConversationBuilder()
        if let _value = identifier {
            builder.setIdentifier(_value)
        }
        if let _value = unknownFields {
            builder.setUnknownFields(_value)
        }
        return builder
    }
}

public struct StorageServiceProtoAccountRecordPinnedConversationBuilder {

    private var proto = StorageServiceProtos_AccountRecord.PinnedConversation()

    fileprivate init() {}

    @available(swift, obsoleted: 1.0)
    public mutating func setIdentifier(_ valueParam: StorageServiceProtoAccountRecordPinnedConversationOneOfIdentifier?) {
        guard let valueParam = valueParam else { return }
        proto.identifier = StorageServiceProtoAccountRecordPinnedConversationOneOfIdentifierUnwrap(valueParam)
    }

    public mutating func setIdentifier(_ valueParam: StorageServiceProtoAccountRecordPinnedConversationOneOfIdentifier) {
        proto.identifier = StorageServiceProtoAccountRecordPinnedConversationOneOfIdentifierUnwrap(valueParam)
    }

    public mutating func setUnknownFields(_ unknownFields: SwiftProtobuf.UnknownStorage) {
        proto.unknownFields = unknownFields
    }

    public func build() throws -> StorageServiceProtoAccountRecordPinnedConversation {
        return try StorageServiceProtoAccountRecordPinnedConversation(proto)
    }

    public func buildSerializedData() throws -> Data {
        return try StorageServiceProtoAccountRecordPinnedConversation(proto).serializedData()
    }
}

#if TESTABLE_BUILD

extension StorageServiceProtoAccountRecordPinnedConversation {
    public func serializedDataIgnoringErrors() -> Data? {
        return try! self.serializedData()
    }
}

extension StorageServiceProtoAccountRecordPinnedConversationBuilder {
    public func buildIgnoringErrors() -> StorageServiceProtoAccountRecordPinnedConversation? {
        return try! self.build()
    }
}

#endif

// MARK: - StorageServiceProtoAccountRecordPayments

public struct StorageServiceProtoAccountRecordPayments: Codable, CustomDebugStringConvertible {

    fileprivate let proto: StorageServiceProtos_AccountRecord.Payments

    public var enabled: Bool {
        return proto.enabled
    }
    public var hasEnabled: Bool {
        return true
    }

    public var paymentsEntropy: Data? {
        guard hasPaymentsEntropy else {
            return nil
        }
        return proto.paymentsEntropy
    }
    public var hasPaymentsEntropy: Bool {
        return !proto.paymentsEntropy.isEmpty
    }

    public var hasUnknownFields: Bool {
        return !proto.unknownFields.data.isEmpty
    }
    public var unknownFields: SwiftProtobuf.UnknownStorage? {
        guard hasUnknownFields else { return nil }
        return proto.unknownFields
    }

    private init(proto: StorageServiceProtos_AccountRecord.Payments) {
        self.proto = proto
    }

    public func serializedData() throws -> Data {
        return try self.proto.serializedData()
    }

    public init(serializedData: Data) throws {
        let proto = try StorageServiceProtos_AccountRecord.Payments(serializedData: serializedData)
        try self.init(proto)
    }

    fileprivate init(_ proto: StorageServiceProtos_AccountRecord.Payments) throws {
        // MARK: - Begin Validation Logic for StorageServiceProtoAccountRecordPayments -

        // MARK: - End Validation Logic for StorageServiceProtoAccountRecordPayments -

        self.init(proto: proto)
    }

    public init(from decoder: Swift.Decoder) throws {
        let singleValueContainer = try decoder.singleValueContainer()
        let serializedData = try singleValueContainer.decode(Data.self)
        try self.init(serializedData: serializedData)
    }
    public func encode(to encoder: Swift.Encoder) throws {
        var singleValueContainer = encoder.singleValueContainer()
        try singleValueContainer.encode(try serializedData())
    }

    public var debugDescription: String {
        return "\(proto)"
    }
}

extension StorageServiceProtoAccountRecordPayments {
    public static func builder() -> StorageServiceProtoAccountRecordPaymentsBuilder {
        return StorageServiceProtoAccountRecordPaymentsBuilder()
    }

    // asBuilder() constructs a builder that reflects the proto's contents.
    public func asBuilder() -> StorageServiceProtoAccountRecordPaymentsBuilder {
        var builder = StorageServiceProtoAccountRecordPaymentsBuilder()
        if hasEnabled {
            builder.setEnabled(enabled)
        }
        if let _value = paymentsEntropy {
            builder.setPaymentsEntropy(_value)
        }
        if let _value = unknownFields {
            builder.setUnknownFields(_value)
        }
        return builder
    }
}

public struct StorageServiceProtoAccountRecordPaymentsBuilder {

    private var proto = StorageServiceProtos_AccountRecord.Payments()

    fileprivate init() {}

    public mutating func setEnabled(_ valueParam: Bool) {
        proto.enabled = valueParam
    }

    @available(swift, obsoleted: 1.0)
    public mutating func setPaymentsEntropy(_ valueParam: Data?) {
        guard let valueParam = valueParam else { return }
        proto.paymentsEntropy = valueParam
    }

    public mutating func setPaymentsEntropy(_ valueParam: Data) {
        proto.paymentsEntropy = valueParam
    }

    public mutating func setUnknownFields(_ unknownFields: SwiftProtobuf.UnknownStorage) {
        proto.unknownFields = unknownFields
    }

    public func build() throws -> StorageServiceProtoAccountRecordPayments {
        return try StorageServiceProtoAccountRecordPayments(proto)
    }

    public func buildSerializedData() throws -> Data {
        return try StorageServiceProtoAccountRecordPayments(proto).serializedData()
    }
}

#if TESTABLE_BUILD

extension StorageServiceProtoAccountRecordPayments {
    public func serializedDataIgnoringErrors() -> Data? {
        return try! self.serializedData()
    }
}

extension StorageServiceProtoAccountRecordPaymentsBuilder {
    public func buildIgnoringErrors() -> StorageServiceProtoAccountRecordPayments? {
        return try! self.build()
    }
}

#endif

// MARK: - StorageServiceProtoAccountRecordPhoneNumberSharingMode

public enum StorageServiceProtoAccountRecordPhoneNumberSharingMode: SwiftProtobuf.Enum {
    public typealias RawValue = Int
    case everybody // 0
    case contactsOnly // 1
    case nobody // 2
    case UNRECOGNIZED(Int)

    public init() {
        self = .everybody
    }

    public init?(rawValue: Int) {
        switch rawValue {
            case 0: self = .everybody
            case 1: self = .contactsOnly
            case 2: self = .nobody
            default: self = .UNRECOGNIZED(rawValue)
        }
    }

    public var rawValue: Int {
        switch self {
            case .everybody: return 0
            case .contactsOnly: return 1
            case .nobody: return 2
            case .UNRECOGNIZED(let i): return i
        }
    }
}

private func StorageServiceProtoAccountRecordPhoneNumberSharingModeWrap(_ value: StorageServiceProtos_AccountRecord.PhoneNumberSharingMode) -> StorageServiceProtoAccountRecordPhoneNumberSharingMode {
    switch value {
    case .everybody: return .everybody
    case .contactsOnly: return .contactsOnly
    case .nobody: return .nobody
    case .UNRECOGNIZED(let i): return .UNRECOGNIZED(i)
    }
}

private func StorageServiceProtoAccountRecordPhoneNumberSharingModeUnwrap(_ value: StorageServiceProtoAccountRecordPhoneNumberSharingMode) -> StorageServiceProtos_AccountRecord.PhoneNumberSharingMode {
    switch value {
    case .everybody: return .everybody
    case .contactsOnly: return .contactsOnly
    case .nobody: return .nobody
    case .UNRECOGNIZED(let i): return .UNRECOGNIZED(i)
    }
}

// MARK: - StorageServiceProtoAccountRecord

public struct StorageServiceProtoAccountRecord: Codable, CustomDebugStringConvertible {

    fileprivate let proto: StorageServiceProtos_AccountRecord

    public let pinnedConversations: [StorageServiceProtoAccountRecordPinnedConversation]

    public let payments: StorageServiceProtoAccountRecordPayments?

    public var profileKey: Data? {
        guard hasProfileKey else {
            return nil
        }
        return proto.profileKey
    }
    public var hasProfileKey: Bool {
        return !proto.profileKey.isEmpty
    }

    public var givenName: String? {
        guard hasGivenName else {
            return nil
        }
        return proto.givenName
    }
    public var hasGivenName: Bool {
        return !proto.givenName.isEmpty
    }

    public var familyName: String? {
        guard hasFamilyName else {
            return nil
        }
        return proto.familyName
    }
    public var hasFamilyName: Bool {
        return !proto.familyName.isEmpty
    }

    public var avatarURL: String? {
        guard hasAvatarURL else {
            return nil
        }
        return proto.avatarURL
    }
    public var hasAvatarURL: Bool {
        return !proto.avatarURL.isEmpty
    }

    public var noteToSelfArchived: Bool {
        return proto.noteToSelfArchived
    }
    public var hasNoteToSelfArchived: Bool {
        return true
    }

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

    public var proxiedLinkPreviews: Bool {
        return proto.proxiedLinkPreviews
    }
    public var hasProxiedLinkPreviews: Bool {
        return true
    }

    public var noteToSelfMarkedUnread: Bool {
        return proto.noteToSelfMarkedUnread
    }
    public var hasNoteToSelfMarkedUnread: Bool {
        return true
    }

    public var linkPreviews: Bool {
        return proto.linkPreviews
    }
    public var hasLinkPreviews: Bool {
        return true
    }

    public var phoneNumberSharingMode: StorageServiceProtoAccountRecordPhoneNumberSharingMode? {
        guard hasPhoneNumberSharingMode else {
            return nil
        }
        return StorageServiceProtoAccountRecordPhoneNumberSharingModeWrap(proto.phoneNumberSharingMode)
    }
    // This "unwrapped" accessor should only be used if the "has value" accessor has already been checked.
    public var unwrappedPhoneNumberSharingMode: StorageServiceProtoAccountRecordPhoneNumberSharingMode {
        if !hasPhoneNumberSharingMode {
            // TODO: We could make this a crashing assert.
            owsFailDebug("Unsafe unwrap of missing optional: AccountRecord.phoneNumberSharingMode.")
        }
        return StorageServiceProtoAccountRecordPhoneNumberSharingModeWrap(proto.phoneNumberSharingMode)
    }
    public var hasPhoneNumberSharingMode: Bool {
        return true
    }

    public var notDiscoverableByPhoneNumber: Bool {
        return proto.notDiscoverableByPhoneNumber
    }
    public var hasNotDiscoverableByPhoneNumber: Bool {
        return true
    }

    public var preferContactAvatars: Bool {
        return proto.preferContactAvatars
    }
    public var hasPreferContactAvatars: Bool {
        return true
    }

    public var universalExpireTimer: UInt32 {
        return proto.universalExpireTimer
    }
    public var hasUniversalExpireTimer: Bool {
        return true
    }

    public var e164: String? {
        guard hasE164 else {
            return nil
        }
        return proto.e164
    }
    public var hasE164: Bool {
        return !proto.e164.isEmpty
    }

    public var preferredReactionEmoji: [String] {
        return proto.preferredReactionEmoji
    }

    public var subscriberID: Data? {
        guard hasSubscriberID else {
            return nil
        }
        return proto.subscriberID
    }
    public var hasSubscriberID: Bool {
        return !proto.subscriberID.isEmpty
    }

    public var subscriberCurrencyCode: String? {
        guard hasSubscriberCurrencyCode else {
            return nil
        }
        return proto.subscriberCurrencyCode
    }
    public var hasSubscriberCurrencyCode: Bool {
        return !proto.subscriberCurrencyCode.isEmpty
    }

    public var displayBadgesOnProfile: Bool {
        return proto.displayBadgesOnProfile
    }
    public var hasDisplayBadgesOnProfile: Bool {
        return true
    }

    public var subscriptionManuallyCancelled: Bool {
        return proto.subscriptionManuallyCancelled
    }
    public var hasSubscriptionManuallyCancelled: Bool {
        return true
    }

    public var keepMutedChatsArchived: Bool {
        return proto.keepMutedChatsArchived
    }
    public var hasKeepMutedChatsArchived: Bool {
        return true
    }

    public var myStoryPrivacyHasBeenSet: Bool {
        return proto.myStoryPrivacyHasBeenSet
    }
    public var hasMyStoryPrivacyHasBeenSet: Bool {
        return true
    }

    public var viewedOnboardingStory: Bool {
        return proto.viewedOnboardingStory
    }
    public var hasViewedOnboardingStory: Bool {
        return true
    }

    public var storiesDisabled: Bool {
        return proto.storiesDisabled
    }
    public var hasStoriesDisabled: Bool {
        return true
    }

    public var storyViewReceiptsEnabled: StorageServiceProtoOptionalBool? {
        guard hasStoryViewReceiptsEnabled else {
            return nil
        }
        return StorageServiceProtoOptionalBoolWrap(proto.storyViewReceiptsEnabled)
    }
    // This "unwrapped" accessor should only be used if the "has value" accessor has already been checked.
    public var unwrappedStoryViewReceiptsEnabled: StorageServiceProtoOptionalBool {
        if !hasStoryViewReceiptsEnabled {
            // TODO: We could make this a crashing assert.
            owsFailDebug("Unsafe unwrap of missing optional: AccountRecord.storyViewReceiptsEnabled.")
        }
        return StorageServiceProtoOptionalBoolWrap(proto.storyViewReceiptsEnabled)
    }
    public var hasStoryViewReceiptsEnabled: Bool {
        return true
    }

    public var readOnboardingStory: Bool {
        return proto.readOnboardingStory
    }
    public var hasReadOnboardingStory: Bool {
        return true
    }

    public var hasUnknownFields: Bool {
        return !proto.unknownFields.data.isEmpty
    }
    public var unknownFields: SwiftProtobuf.UnknownStorage? {
        guard hasUnknownFields else { return nil }
        return proto.unknownFields
    }

    private init(proto: StorageServiceProtos_AccountRecord,
                 pinnedConversations: [StorageServiceProtoAccountRecordPinnedConversation],
                 payments: StorageServiceProtoAccountRecordPayments?) {
        self.proto = proto
        self.pinnedConversations = pinnedConversations
        self.payments = payments
    }

    public func serializedData() throws -> Data {
        return try self.proto.serializedData()
    }

    public init(serializedData: Data) throws {
        let proto = try StorageServiceProtos_AccountRecord(serializedData: serializedData)
        try self.init(proto)
    }

    fileprivate init(_ proto: StorageServiceProtos_AccountRecord) throws {
        var pinnedConversations: [StorageServiceProtoAccountRecordPinnedConversation] = []
        pinnedConversations = try proto.pinnedConversations.map { try StorageServiceProtoAccountRecordPinnedConversation($0) }

        var payments: StorageServiceProtoAccountRecordPayments?
        if proto.hasPayments {
            payments = try StorageServiceProtoAccountRecordPayments(proto.payments)
        }

        // MARK: - Begin Validation Logic for StorageServiceProtoAccountRecord -

        // MARK: - End Validation Logic for StorageServiceProtoAccountRecord -

        self.init(proto: proto,
                  pinnedConversations: pinnedConversations,
                  payments: payments)
    }

    public init(from decoder: Swift.Decoder) throws {
        let singleValueContainer = try decoder.singleValueContainer()
        let serializedData = try singleValueContainer.decode(Data.self)
        try self.init(serializedData: serializedData)
    }
    public func encode(to encoder: Swift.Encoder) throws {
        var singleValueContainer = encoder.singleValueContainer()
        try singleValueContainer.encode(try serializedData())
    }

    public var debugDescription: String {
        return "\(proto)"
    }
}

extension StorageServiceProtoAccountRecord {
    public static func builder() -> StorageServiceProtoAccountRecordBuilder {
        return StorageServiceProtoAccountRecordBuilder()
    }

    // asBuilder() constructs a builder that reflects the proto's contents.
    public func asBuilder() -> StorageServiceProtoAccountRecordBuilder {
        var builder = StorageServiceProtoAccountRecordBuilder()
        if let _value = profileKey {
            builder.setProfileKey(_value)
        }
        if let _value = givenName {
            builder.setGivenName(_value)
        }
        if let _value = familyName {
            builder.setFamilyName(_value)
        }
        if let _value = avatarURL {
            builder.setAvatarURL(_value)
        }
        if hasNoteToSelfArchived {
            builder.setNoteToSelfArchived(noteToSelfArchived)
        }
        if hasReadReceipts {
            builder.setReadReceipts(readReceipts)
        }
        if hasSealedSenderIndicators {
            builder.setSealedSenderIndicators(sealedSenderIndicators)
        }
        if hasTypingIndicators {
            builder.setTypingIndicators(typingIndicators)
        }
        if hasProxiedLinkPreviews {
            builder.setProxiedLinkPreviews(proxiedLinkPreviews)
        }
        if hasNoteToSelfMarkedUnread {
            builder.setNoteToSelfMarkedUnread(noteToSelfMarkedUnread)
        }
        if hasLinkPreviews {
            builder.setLinkPreviews(linkPreviews)
        }
        if let _value = phoneNumberSharingMode {
            builder.setPhoneNumberSharingMode(_value)
        }
        if hasNotDiscoverableByPhoneNumber {
            builder.setNotDiscoverableByPhoneNumber(notDiscoverableByPhoneNumber)
        }
        builder.setPinnedConversations(pinnedConversations)
        if hasPreferContactAvatars {
            builder.setPreferContactAvatars(preferContactAvatars)
        }
        if let _value = payments {
            builder.setPayments(_value)
        }
        if hasUniversalExpireTimer {
            builder.setUniversalExpireTimer(universalExpireTimer)
        }
        if let _value = e164 {
            builder.setE164(_value)
        }
        builder.setPreferredReactionEmoji(preferredReactionEmoji)
        if let _value = subscriberID {
            builder.setSubscriberID(_value)
        }
        if let _value = subscriberCurrencyCode {
            builder.setSubscriberCurrencyCode(_value)
        }
        if hasDisplayBadgesOnProfile {
            builder.setDisplayBadgesOnProfile(displayBadgesOnProfile)
        }
        if hasSubscriptionManuallyCancelled {
            builder.setSubscriptionManuallyCancelled(subscriptionManuallyCancelled)
        }
        if hasKeepMutedChatsArchived {
            builder.setKeepMutedChatsArchived(keepMutedChatsArchived)
        }
        if hasMyStoryPrivacyHasBeenSet {
            builder.setMyStoryPrivacyHasBeenSet(myStoryPrivacyHasBeenSet)
        }
        if hasViewedOnboardingStory {
            builder.setViewedOnboardingStory(viewedOnboardingStory)
        }
        if hasStoriesDisabled {
            builder.setStoriesDisabled(storiesDisabled)
        }
        if let _value = storyViewReceiptsEnabled {
            builder.setStoryViewReceiptsEnabled(_value)
        }
        if hasReadOnboardingStory {
            builder.setReadOnboardingStory(readOnboardingStory)
        }
        if let _value = unknownFields {
            builder.setUnknownFields(_value)
        }
        return builder
    }
}

public struct StorageServiceProtoAccountRecordBuilder {

    private var proto = StorageServiceProtos_AccountRecord()

    fileprivate init() {}

    @available(swift, obsoleted: 1.0)
    public mutating func setProfileKey(_ valueParam: Data?) {
        guard let valueParam = valueParam else { return }
        proto.profileKey = valueParam
    }

    public mutating func setProfileKey(_ valueParam: Data) {
        proto.profileKey = valueParam
    }

    @available(swift, obsoleted: 1.0)
    public mutating func setGivenName(_ valueParam: String?) {
        guard let valueParam = valueParam else { return }
        proto.givenName = valueParam
    }

    public mutating func setGivenName(_ valueParam: String) {
        proto.givenName = valueParam
    }

    @available(swift, obsoleted: 1.0)
    public mutating func setFamilyName(_ valueParam: String?) {
        guard let valueParam = valueParam else { return }
        proto.familyName = valueParam
    }

    public mutating func setFamilyName(_ valueParam: String) {
        proto.familyName = valueParam
    }

    @available(swift, obsoleted: 1.0)
    public mutating func setAvatarURL(_ valueParam: String?) {
        guard let valueParam = valueParam else { return }
        proto.avatarURL = valueParam
    }

    public mutating func setAvatarURL(_ valueParam: String) {
        proto.avatarURL = valueParam
    }

    public mutating func setNoteToSelfArchived(_ valueParam: Bool) {
        proto.noteToSelfArchived = valueParam
    }

    public mutating func setReadReceipts(_ valueParam: Bool) {
        proto.readReceipts = valueParam
    }

    public mutating func setSealedSenderIndicators(_ valueParam: Bool) {
        proto.sealedSenderIndicators = valueParam
    }

    public mutating func setTypingIndicators(_ valueParam: Bool) {
        proto.typingIndicators = valueParam
    }

    public mutating func setProxiedLinkPreviews(_ valueParam: Bool) {
        proto.proxiedLinkPreviews = valueParam
    }

    public mutating func setNoteToSelfMarkedUnread(_ valueParam: Bool) {
        proto.noteToSelfMarkedUnread = valueParam
    }

    public mutating func setLinkPreviews(_ valueParam: Bool) {
        proto.linkPreviews = valueParam
    }

    public mutating func setPhoneNumberSharingMode(_ valueParam: StorageServiceProtoAccountRecordPhoneNumberSharingMode) {
        proto.phoneNumberSharingMode = StorageServiceProtoAccountRecordPhoneNumberSharingModeUnwrap(valueParam)
    }

    public mutating func setNotDiscoverableByPhoneNumber(_ valueParam: Bool) {
        proto.notDiscoverableByPhoneNumber = valueParam
    }

    public mutating func addPinnedConversations(_ valueParam: StorageServiceProtoAccountRecordPinnedConversation) {
        proto.pinnedConversations.append(valueParam.proto)
    }

    public mutating func setPinnedConversations(_ wrappedItems: [StorageServiceProtoAccountRecordPinnedConversation]) {
        proto.pinnedConversations = wrappedItems.map { $0.proto }
    }

    public mutating func setPreferContactAvatars(_ valueParam: Bool) {
        proto.preferContactAvatars = valueParam
    }

    @available(swift, obsoleted: 1.0)
    public mutating func setPayments(_ valueParam: StorageServiceProtoAccountRecordPayments?) {
        guard let valueParam = valueParam else { return }
        proto.payments = valueParam.proto
    }

    public mutating func setPayments(_ valueParam: StorageServiceProtoAccountRecordPayments) {
        proto.payments = valueParam.proto
    }

    public mutating func setUniversalExpireTimer(_ valueParam: UInt32) {
        proto.universalExpireTimer = valueParam
    }

    @available(swift, obsoleted: 1.0)
    public mutating func setE164(_ valueParam: String?) {
        guard let valueParam = valueParam else { return }
        proto.e164 = valueParam
    }

    public mutating func setE164(_ valueParam: String) {
        proto.e164 = valueParam
    }

    public mutating func addPreferredReactionEmoji(_ valueParam: String) {
        proto.preferredReactionEmoji.append(valueParam)
    }

    public mutating func setPreferredReactionEmoji(_ wrappedItems: [String]) {
        proto.preferredReactionEmoji = wrappedItems
    }

    @available(swift, obsoleted: 1.0)
    public mutating func setSubscriberID(_ valueParam: Data?) {
        guard let valueParam = valueParam else { return }
        proto.subscriberID = valueParam
    }

    public mutating func setSubscriberID(_ valueParam: Data) {
        proto.subscriberID = valueParam
    }

    @available(swift, obsoleted: 1.0)
    public mutating func setSubscriberCurrencyCode(_ valueParam: String?) {
        guard let valueParam = valueParam else { return }
        proto.subscriberCurrencyCode = valueParam
    }

    public mutating func setSubscriberCurrencyCode(_ valueParam: String) {
        proto.subscriberCurrencyCode = valueParam
    }

    public mutating func setDisplayBadgesOnProfile(_ valueParam: Bool) {
        proto.displayBadgesOnProfile = valueParam
    }

    public mutating func setSubscriptionManuallyCancelled(_ valueParam: Bool) {
        proto.subscriptionManuallyCancelled = valueParam
    }

    public mutating func setKeepMutedChatsArchived(_ valueParam: Bool) {
        proto.keepMutedChatsArchived = valueParam
    }

    public mutating func setMyStoryPrivacyHasBeenSet(_ valueParam: Bool) {
        proto.myStoryPrivacyHasBeenSet = valueParam
    }

    public mutating func setViewedOnboardingStory(_ valueParam: Bool) {
        proto.viewedOnboardingStory = valueParam
    }

    public mutating func setStoriesDisabled(_ valueParam: Bool) {
        proto.storiesDisabled = valueParam
    }

    public mutating func setStoryViewReceiptsEnabled(_ valueParam: StorageServiceProtoOptionalBool) {
        proto.storyViewReceiptsEnabled = StorageServiceProtoOptionalBoolUnwrap(valueParam)
    }

    public mutating func setReadOnboardingStory(_ valueParam: Bool) {
        proto.readOnboardingStory = valueParam
    }

    public mutating func setUnknownFields(_ unknownFields: SwiftProtobuf.UnknownStorage) {
        proto.unknownFields = unknownFields
    }

    public func build() throws -> StorageServiceProtoAccountRecord {
        return try StorageServiceProtoAccountRecord(proto)
    }

    public func buildSerializedData() throws -> Data {
        return try StorageServiceProtoAccountRecord(proto).serializedData()
    }
}

#if TESTABLE_BUILD

extension StorageServiceProtoAccountRecord {
    public func serializedDataIgnoringErrors() -> Data? {
        return try! self.serializedData()
    }
}

extension StorageServiceProtoAccountRecordBuilder {
    public func buildIgnoringErrors() -> StorageServiceProtoAccountRecord? {
        return try! self.build()
    }
}

#endif

// MARK: - StorageServiceProtoStoryDistributionListRecord

public struct StorageServiceProtoStoryDistributionListRecord: Codable, CustomDebugStringConvertible {

    fileprivate let proto: StorageServiceProtos_StoryDistributionListRecord

    public var identifier: Data? {
        guard hasIdentifier else {
            return nil
        }
        return proto.identifier
    }
    public var hasIdentifier: Bool {
        return !proto.identifier.isEmpty
    }

    public var name: String? {
        guard hasName else {
            return nil
        }
        return proto.name
    }
    public var hasName: Bool {
        return !proto.name.isEmpty
    }

    public var recipientUuids: [String] {
        return proto.recipientUuids
    }

    public var deletedAtTimestamp: UInt64 {
        return proto.deletedAtTimestamp
    }
    public var hasDeletedAtTimestamp: Bool {
        return true
    }

    public var allowsReplies: Bool {
        return proto.allowsReplies
    }
    public var hasAllowsReplies: Bool {
        return true
    }

    public var isBlockList: Bool {
        return proto.isBlockList
    }
    public var hasIsBlockList: Bool {
        return true
    }

    public var hasUnknownFields: Bool {
        return !proto.unknownFields.data.isEmpty
    }
    public var unknownFields: SwiftProtobuf.UnknownStorage? {
        guard hasUnknownFields else { return nil }
        return proto.unknownFields
    }

    private init(proto: StorageServiceProtos_StoryDistributionListRecord) {
        self.proto = proto
    }

    public func serializedData() throws -> Data {
        return try self.proto.serializedData()
    }

    public init(serializedData: Data) throws {
        let proto = try StorageServiceProtos_StoryDistributionListRecord(serializedData: serializedData)
        try self.init(proto)
    }

    fileprivate init(_ proto: StorageServiceProtos_StoryDistributionListRecord) throws {
        // MARK: - Begin Validation Logic for StorageServiceProtoStoryDistributionListRecord -

        // MARK: - End Validation Logic for StorageServiceProtoStoryDistributionListRecord -

        self.init(proto: proto)
    }

    public init(from decoder: Swift.Decoder) throws {
        let singleValueContainer = try decoder.singleValueContainer()
        let serializedData = try singleValueContainer.decode(Data.self)
        try self.init(serializedData: serializedData)
    }
    public func encode(to encoder: Swift.Encoder) throws {
        var singleValueContainer = encoder.singleValueContainer()
        try singleValueContainer.encode(try serializedData())
    }

    public var debugDescription: String {
        return "\(proto)"
    }
}

extension StorageServiceProtoStoryDistributionListRecord {
    public static func builder() -> StorageServiceProtoStoryDistributionListRecordBuilder {
        return StorageServiceProtoStoryDistributionListRecordBuilder()
    }

    // asBuilder() constructs a builder that reflects the proto's contents.
    public func asBuilder() -> StorageServiceProtoStoryDistributionListRecordBuilder {
        var builder = StorageServiceProtoStoryDistributionListRecordBuilder()
        if let _value = identifier {
            builder.setIdentifier(_value)
        }
        if let _value = name {
            builder.setName(_value)
        }
        builder.setRecipientUuids(recipientUuids)
        if hasDeletedAtTimestamp {
            builder.setDeletedAtTimestamp(deletedAtTimestamp)
        }
        if hasAllowsReplies {
            builder.setAllowsReplies(allowsReplies)
        }
        if hasIsBlockList {
            builder.setIsBlockList(isBlockList)
        }
        if let _value = unknownFields {
            builder.setUnknownFields(_value)
        }
        return builder
    }
}

public struct StorageServiceProtoStoryDistributionListRecordBuilder {

    private var proto = StorageServiceProtos_StoryDistributionListRecord()

    fileprivate init() {}

    @available(swift, obsoleted: 1.0)
    public mutating func setIdentifier(_ valueParam: Data?) {
        guard let valueParam = valueParam else { return }
        proto.identifier = valueParam
    }

    public mutating func setIdentifier(_ valueParam: Data) {
        proto.identifier = valueParam
    }

    @available(swift, obsoleted: 1.0)
    public mutating func setName(_ valueParam: String?) {
        guard let valueParam = valueParam else { return }
        proto.name = valueParam
    }

    public mutating func setName(_ valueParam: String) {
        proto.name = valueParam
    }

    public mutating func addRecipientUuids(_ valueParam: String) {
        proto.recipientUuids.append(valueParam)
    }

    public mutating func setRecipientUuids(_ wrappedItems: [String]) {
        proto.recipientUuids = wrappedItems
    }

    public mutating func setDeletedAtTimestamp(_ valueParam: UInt64) {
        proto.deletedAtTimestamp = valueParam
    }

    public mutating func setAllowsReplies(_ valueParam: Bool) {
        proto.allowsReplies = valueParam
    }

    public mutating func setIsBlockList(_ valueParam: Bool) {
        proto.isBlockList = valueParam
    }

    public mutating func setUnknownFields(_ unknownFields: SwiftProtobuf.UnknownStorage) {
        proto.unknownFields = unknownFields
    }

    public func build() throws -> StorageServiceProtoStoryDistributionListRecord {
        return try StorageServiceProtoStoryDistributionListRecord(proto)
    }

    public func buildSerializedData() throws -> Data {
        return try StorageServiceProtoStoryDistributionListRecord(proto).serializedData()
    }
}

#if TESTABLE_BUILD

extension StorageServiceProtoStoryDistributionListRecord {
    public func serializedDataIgnoringErrors() -> Data? {
        return try! self.serializedData()
    }
}

extension StorageServiceProtoStoryDistributionListRecordBuilder {
    public func buildIgnoringErrors() -> StorageServiceProtoStoryDistributionListRecord? {
        return try! self.build()
    }
}

#endif
