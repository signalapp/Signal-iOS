//
//  Copyright (c) 2020 Open Whisper Systems. All rights reserved.
//

import Foundation
import SignalCoreKit
import SwiftProtobuf

// WARNING: This code is generated. Only edit within the markers.

public enum SignalIOSProtoError: Error {
    case invalidProtobuf(description: String)
}

// MARK: - SignalIOSProtoBackupSnapshotBackupEntityType

@objc
public enum SignalIOSProtoBackupSnapshotBackupEntityType: Int32 {
    case unknown = 0
    case migration = 1
    case thread = 2
    case interaction = 3
    case attachment = 4
    case misc = 5
}

private func SignalIOSProtoBackupSnapshotBackupEntityTypeWrap(_ value: IOSProtos_BackupSnapshot.BackupEntity.TypeEnum) -> SignalIOSProtoBackupSnapshotBackupEntityType {
    switch value {
    case .unknown: return .unknown
    case .migration: return .migration
    case .thread: return .thread
    case .interaction: return .interaction
    case .attachment: return .attachment
    case .misc: return .misc
    }
}

private func SignalIOSProtoBackupSnapshotBackupEntityTypeUnwrap(_ value: SignalIOSProtoBackupSnapshotBackupEntityType) -> IOSProtos_BackupSnapshot.BackupEntity.TypeEnum {
    switch value {
    case .unknown: return .unknown
    case .migration: return .migration
    case .thread: return .thread
    case .interaction: return .interaction
    case .attachment: return .attachment
    case .misc: return .misc
    }
}

// MARK: - SignalIOSProtoBackupSnapshotBackupEntity

@objc
public class SignalIOSProtoBackupSnapshotBackupEntity: NSObject, Codable {

    // MARK: - SignalIOSProtoBackupSnapshotBackupEntityBuilder

    @objc
    public class func builder(entityData: Data, collection: String, key: String) -> SignalIOSProtoBackupSnapshotBackupEntityBuilder {
        return SignalIOSProtoBackupSnapshotBackupEntityBuilder(entityData: entityData, collection: collection, key: key)
    }

    // asBuilder() constructs a builder that reflects the proto's contents.
    @objc
    public func asBuilder() -> SignalIOSProtoBackupSnapshotBackupEntityBuilder {
        let builder = SignalIOSProtoBackupSnapshotBackupEntityBuilder(entityData: entityData, collection: collection, key: key)
        if let _value = type {
            builder.setType(_value)
        }
        if let _value = unknownFields {
            builder.setUnknownFields(_value)
        }
        return builder
    }

    @objc
    public class SignalIOSProtoBackupSnapshotBackupEntityBuilder: NSObject {

        private var proto = IOSProtos_BackupSnapshot.BackupEntity()

        @objc
        fileprivate override init() {}

        @objc
        fileprivate init(entityData: Data, collection: String, key: String) {
            super.init()

            setEntityData(entityData)
            setCollection(collection)
            setKey(key)
        }

        @objc
        public func setType(_ valueParam: SignalIOSProtoBackupSnapshotBackupEntityType) {
            proto.type = SignalIOSProtoBackupSnapshotBackupEntityTypeUnwrap(valueParam)
        }

        @objc
        @available(swift, obsoleted: 1.0)
        public func setEntityData(_ valueParam: Data?) {
            guard let valueParam = valueParam else { return }
            proto.entityData = valueParam
        }

        public func setEntityData(_ valueParam: Data) {
            proto.entityData = valueParam
        }

        @objc
        @available(swift, obsoleted: 1.0)
        public func setCollection(_ valueParam: String?) {
            guard let valueParam = valueParam else { return }
            proto.collection = valueParam
        }

        public func setCollection(_ valueParam: String) {
            proto.collection = valueParam
        }

        @objc
        @available(swift, obsoleted: 1.0)
        public func setKey(_ valueParam: String?) {
            guard let valueParam = valueParam else { return }
            proto.key = valueParam
        }

        public func setKey(_ valueParam: String) {
            proto.key = valueParam
        }

        public func setUnknownFields(_ unknownFields: SwiftProtobuf.UnknownStorage) {
            proto.unknownFields = unknownFields
        }

        @objc
        public func build() throws -> SignalIOSProtoBackupSnapshotBackupEntity {
            return try SignalIOSProtoBackupSnapshotBackupEntity(proto)
        }

        @objc
        public func buildSerializedData() throws -> Data {
            return try SignalIOSProtoBackupSnapshotBackupEntity(proto).serializedData()
        }
    }

    fileprivate let proto: IOSProtos_BackupSnapshot.BackupEntity

    @objc
    public let entityData: Data

    @objc
    public let collection: String

    @objc
    public let key: String

    public var type: SignalIOSProtoBackupSnapshotBackupEntityType? {
        guard hasType else {
            return nil
        }
        return SignalIOSProtoBackupSnapshotBackupEntityTypeWrap(proto.type)
    }
    // This "unwrapped" accessor should only be used if the "has value" accessor has already been checked.
    @objc
    public var unwrappedType: SignalIOSProtoBackupSnapshotBackupEntityType {
        if !hasType {
            // TODO: We could make this a crashing assert.
            owsFailDebug("Unsafe unwrap of missing optional: BackupEntity.type.")
        }
        return SignalIOSProtoBackupSnapshotBackupEntityTypeWrap(proto.type)
    }
    @objc
    public var hasType: Bool {
        return proto.hasType
    }

    public var hasUnknownFields: Bool {
        return !proto.unknownFields.data.isEmpty
    }
    public var unknownFields: SwiftProtobuf.UnknownStorage? {
        guard hasUnknownFields else { return nil }
        return proto.unknownFields
    }

    private init(proto: IOSProtos_BackupSnapshot.BackupEntity,
                 entityData: Data,
                 collection: String,
                 key: String) {
        self.proto = proto
        self.entityData = entityData
        self.collection = collection
        self.key = key
    }

    @objc
    public func serializedData() throws -> Data {
        return try self.proto.serializedData()
    }

    @objc
    public convenience init(serializedData: Data) throws {
        let proto = try IOSProtos_BackupSnapshot.BackupEntity(serializedData: serializedData)
        try self.init(proto)
    }

    fileprivate convenience init(_ proto: IOSProtos_BackupSnapshot.BackupEntity) throws {
        guard proto.hasEntityData else {
            throw SignalIOSProtoError.invalidProtobuf(description: "\(Self.logTag) missing required field: entityData")
        }
        let entityData = proto.entityData

        guard proto.hasCollection else {
            throw SignalIOSProtoError.invalidProtobuf(description: "\(Self.logTag) missing required field: collection")
        }
        let collection = proto.collection

        guard proto.hasKey else {
            throw SignalIOSProtoError.invalidProtobuf(description: "\(Self.logTag) missing required field: key")
        }
        let key = proto.key

        // MARK: - Begin Validation Logic for SignalIOSProtoBackupSnapshotBackupEntity -

        // MARK: - End Validation Logic for SignalIOSProtoBackupSnapshotBackupEntity -

        self.init(proto: proto,
                  entityData: entityData,
                  collection: collection,
                  key: key)
    }

    public required convenience init(from decoder: Swift.Decoder) throws {
        let singleValueContainer = try decoder.singleValueContainer()
        let serializedData = try singleValueContainer.decode(Data.self)
        try self.init(serializedData: serializedData)
    }
    public func encode(to encoder: Swift.Encoder) throws {
        var singleValueContainer = encoder.singleValueContainer()
        try singleValueContainer.encode(try serializedData())
    }

    @objc
    public override var debugDescription: String {
        return "\(proto)"
    }
}

#if DEBUG

extension SignalIOSProtoBackupSnapshotBackupEntity {
    @objc
    public func serializedDataIgnoringErrors() -> Data? {
        return try! self.serializedData()
    }
}

extension SignalIOSProtoBackupSnapshotBackupEntity.SignalIOSProtoBackupSnapshotBackupEntityBuilder {
    @objc
    public func buildIgnoringErrors() -> SignalIOSProtoBackupSnapshotBackupEntity? {
        return try! self.build()
    }
}

#endif

// MARK: - SignalIOSProtoBackupSnapshot

@objc
public class SignalIOSProtoBackupSnapshot: NSObject, Codable {

    // MARK: - SignalIOSProtoBackupSnapshotBuilder

    @objc
    public class func builder() -> SignalIOSProtoBackupSnapshotBuilder {
        return SignalIOSProtoBackupSnapshotBuilder()
    }

    // asBuilder() constructs a builder that reflects the proto's contents.
    @objc
    public func asBuilder() -> SignalIOSProtoBackupSnapshotBuilder {
        let builder = SignalIOSProtoBackupSnapshotBuilder()
        builder.setEntity(entity)
        if let _value = unknownFields {
            builder.setUnknownFields(_value)
        }
        return builder
    }

    @objc
    public class SignalIOSProtoBackupSnapshotBuilder: NSObject {

        private var proto = IOSProtos_BackupSnapshot()

        @objc
        fileprivate override init() {}

        @objc
        public func addEntity(_ valueParam: SignalIOSProtoBackupSnapshotBackupEntity) {
            var items = proto.entity
            items.append(valueParam.proto)
            proto.entity = items
        }

        @objc
        public func setEntity(_ wrappedItems: [SignalIOSProtoBackupSnapshotBackupEntity]) {
            proto.entity = wrappedItems.map { $0.proto }
        }

        public func setUnknownFields(_ unknownFields: SwiftProtobuf.UnknownStorage) {
            proto.unknownFields = unknownFields
        }

        @objc
        public func build() throws -> SignalIOSProtoBackupSnapshot {
            return try SignalIOSProtoBackupSnapshot(proto)
        }

        @objc
        public func buildSerializedData() throws -> Data {
            return try SignalIOSProtoBackupSnapshot(proto).serializedData()
        }
    }

    fileprivate let proto: IOSProtos_BackupSnapshot

    @objc
    public let entity: [SignalIOSProtoBackupSnapshotBackupEntity]

    public var hasUnknownFields: Bool {
        return !proto.unknownFields.data.isEmpty
    }
    public var unknownFields: SwiftProtobuf.UnknownStorage? {
        guard hasUnknownFields else { return nil }
        return proto.unknownFields
    }

    private init(proto: IOSProtos_BackupSnapshot,
                 entity: [SignalIOSProtoBackupSnapshotBackupEntity]) {
        self.proto = proto
        self.entity = entity
    }

    @objc
    public func serializedData() throws -> Data {
        return try self.proto.serializedData()
    }

    @objc
    public convenience init(serializedData: Data) throws {
        let proto = try IOSProtos_BackupSnapshot(serializedData: serializedData)
        try self.init(proto)
    }

    fileprivate convenience init(_ proto: IOSProtos_BackupSnapshot) throws {
        var entity: [SignalIOSProtoBackupSnapshotBackupEntity] = []
        entity = try proto.entity.map { try SignalIOSProtoBackupSnapshotBackupEntity($0) }

        // MARK: - Begin Validation Logic for SignalIOSProtoBackupSnapshot -

        // MARK: - End Validation Logic for SignalIOSProtoBackupSnapshot -

        self.init(proto: proto,
                  entity: entity)
    }

    public required convenience init(from decoder: Swift.Decoder) throws {
        let singleValueContainer = try decoder.singleValueContainer()
        let serializedData = try singleValueContainer.decode(Data.self)
        try self.init(serializedData: serializedData)
    }
    public func encode(to encoder: Swift.Encoder) throws {
        var singleValueContainer = encoder.singleValueContainer()
        try singleValueContainer.encode(try serializedData())
    }

    @objc
    public override var debugDescription: String {
        return "\(proto)"
    }
}

#if DEBUG

extension SignalIOSProtoBackupSnapshot {
    @objc
    public func serializedDataIgnoringErrors() -> Data? {
        return try! self.serializedData()
    }
}

extension SignalIOSProtoBackupSnapshot.SignalIOSProtoBackupSnapshotBuilder {
    @objc
    public func buildIgnoringErrors() -> SignalIOSProtoBackupSnapshot? {
        return try! self.build()
    }
}

#endif

// MARK: - SignalIOSProtoDeviceName

@objc
public class SignalIOSProtoDeviceName: NSObject, Codable {

    // MARK: - SignalIOSProtoDeviceNameBuilder

    @objc
    public class func builder(ephemeralPublic: Data, syntheticIv: Data, ciphertext: Data) -> SignalIOSProtoDeviceNameBuilder {
        return SignalIOSProtoDeviceNameBuilder(ephemeralPublic: ephemeralPublic, syntheticIv: syntheticIv, ciphertext: ciphertext)
    }

    // asBuilder() constructs a builder that reflects the proto's contents.
    @objc
    public func asBuilder() -> SignalIOSProtoDeviceNameBuilder {
        let builder = SignalIOSProtoDeviceNameBuilder(ephemeralPublic: ephemeralPublic, syntheticIv: syntheticIv, ciphertext: ciphertext)
        if let _value = unknownFields {
            builder.setUnknownFields(_value)
        }
        return builder
    }

    @objc
    public class SignalIOSProtoDeviceNameBuilder: NSObject {

        private var proto = IOSProtos_DeviceName()

        @objc
        fileprivate override init() {}

        @objc
        fileprivate init(ephemeralPublic: Data, syntheticIv: Data, ciphertext: Data) {
            super.init()

            setEphemeralPublic(ephemeralPublic)
            setSyntheticIv(syntheticIv)
            setCiphertext(ciphertext)
        }

        @objc
        @available(swift, obsoleted: 1.0)
        public func setEphemeralPublic(_ valueParam: Data?) {
            guard let valueParam = valueParam else { return }
            proto.ephemeralPublic = valueParam
        }

        public func setEphemeralPublic(_ valueParam: Data) {
            proto.ephemeralPublic = valueParam
        }

        @objc
        @available(swift, obsoleted: 1.0)
        public func setSyntheticIv(_ valueParam: Data?) {
            guard let valueParam = valueParam else { return }
            proto.syntheticIv = valueParam
        }

        public func setSyntheticIv(_ valueParam: Data) {
            proto.syntheticIv = valueParam
        }

        @objc
        @available(swift, obsoleted: 1.0)
        public func setCiphertext(_ valueParam: Data?) {
            guard let valueParam = valueParam else { return }
            proto.ciphertext = valueParam
        }

        public func setCiphertext(_ valueParam: Data) {
            proto.ciphertext = valueParam
        }

        public func setUnknownFields(_ unknownFields: SwiftProtobuf.UnknownStorage) {
            proto.unknownFields = unknownFields
        }

        @objc
        public func build() throws -> SignalIOSProtoDeviceName {
            return try SignalIOSProtoDeviceName(proto)
        }

        @objc
        public func buildSerializedData() throws -> Data {
            return try SignalIOSProtoDeviceName(proto).serializedData()
        }
    }

    fileprivate let proto: IOSProtos_DeviceName

    @objc
    public let ephemeralPublic: Data

    @objc
    public let syntheticIv: Data

    @objc
    public let ciphertext: Data

    public var hasUnknownFields: Bool {
        return !proto.unknownFields.data.isEmpty
    }
    public var unknownFields: SwiftProtobuf.UnknownStorage? {
        guard hasUnknownFields else { return nil }
        return proto.unknownFields
    }

    private init(proto: IOSProtos_DeviceName,
                 ephemeralPublic: Data,
                 syntheticIv: Data,
                 ciphertext: Data) {
        self.proto = proto
        self.ephemeralPublic = ephemeralPublic
        self.syntheticIv = syntheticIv
        self.ciphertext = ciphertext
    }

    @objc
    public func serializedData() throws -> Data {
        return try self.proto.serializedData()
    }

    @objc
    public convenience init(serializedData: Data) throws {
        let proto = try IOSProtos_DeviceName(serializedData: serializedData)
        try self.init(proto)
    }

    fileprivate convenience init(_ proto: IOSProtos_DeviceName) throws {
        guard proto.hasEphemeralPublic else {
            throw SignalIOSProtoError.invalidProtobuf(description: "\(Self.logTag) missing required field: ephemeralPublic")
        }
        let ephemeralPublic = proto.ephemeralPublic

        guard proto.hasSyntheticIv else {
            throw SignalIOSProtoError.invalidProtobuf(description: "\(Self.logTag) missing required field: syntheticIv")
        }
        let syntheticIv = proto.syntheticIv

        guard proto.hasCiphertext else {
            throw SignalIOSProtoError.invalidProtobuf(description: "\(Self.logTag) missing required field: ciphertext")
        }
        let ciphertext = proto.ciphertext

        // MARK: - Begin Validation Logic for SignalIOSProtoDeviceName -

        // MARK: - End Validation Logic for SignalIOSProtoDeviceName -

        self.init(proto: proto,
                  ephemeralPublic: ephemeralPublic,
                  syntheticIv: syntheticIv,
                  ciphertext: ciphertext)
    }

    public required convenience init(from decoder: Swift.Decoder) throws {
        let singleValueContainer = try decoder.singleValueContainer()
        let serializedData = try singleValueContainer.decode(Data.self)
        try self.init(serializedData: serializedData)
    }
    public func encode(to encoder: Swift.Encoder) throws {
        var singleValueContainer = encoder.singleValueContainer()
        try singleValueContainer.encode(try serializedData())
    }

    @objc
    public override var debugDescription: String {
        return "\(proto)"
    }
}

#if DEBUG

extension SignalIOSProtoDeviceName {
    @objc
    public func serializedDataIgnoringErrors() -> Data? {
        return try! self.serializedData()
    }
}

extension SignalIOSProtoDeviceName.SignalIOSProtoDeviceNameBuilder {
    @objc
    public func buildIgnoringErrors() -> SignalIOSProtoDeviceName? {
        return try! self.build()
    }
}

#endif
