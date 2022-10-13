//
// Copyright 2022 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import SignalCoreKit
import SwiftProtobuf

// WARNING: This code is generated. Only edit within the markers.

public enum FingerprintProtoError: Error {
    case invalidProtobuf(description: String)
}

// MARK: - FingerprintProtoLogicalFingerprint

@objc
public class FingerprintProtoLogicalFingerprint: NSObject, Codable, NSSecureCoding {

    fileprivate let proto: FingerprintProtos_LogicalFingerprint

    @objc
    public let identityData: Data

    public var hasUnknownFields: Bool {
        return !proto.unknownFields.data.isEmpty
    }
    public var unknownFields: SwiftProtobuf.UnknownStorage? {
        guard hasUnknownFields else { return nil }
        return proto.unknownFields
    }

    private init(proto: FingerprintProtos_LogicalFingerprint,
                 identityData: Data) {
        self.proto = proto
        self.identityData = identityData
    }

    @objc
    public func serializedData() throws -> Data {
        return try self.proto.serializedData()
    }

    @objc
    public convenience init(serializedData: Data) throws {
        let proto = try FingerprintProtos_LogicalFingerprint(serializedData: serializedData)
        try self.init(proto)
    }

    fileprivate convenience init(_ proto: FingerprintProtos_LogicalFingerprint) throws {
        guard proto.hasIdentityData else {
            throw FingerprintProtoError.invalidProtobuf(description: "\(Self.logTag()) missing required field: identityData")
        }
        let identityData = proto.identityData

        // MARK: - Begin Validation Logic for FingerprintProtoLogicalFingerprint -

        // MARK: - End Validation Logic for FingerprintProtoLogicalFingerprint -

        self.init(proto: proto,
                  identityData: identityData)
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

    public static var supportsSecureCoding: Bool { true }

    public required convenience init?(coder: NSCoder) {
        guard let serializedData = coder.decodeData() else { return nil }
        do {
            try self.init(serializedData: serializedData)
        } catch {
            owsFailDebug("Failed to decode serialized data \(error)")
            return nil
        }
    }

    public func encode(with coder: NSCoder) {
        do {
            coder.encode(try serializedData())
        } catch {
            owsFailDebug("Failed to encode serialized data \(error)")
        }
    }

    @objc
    public override var debugDescription: String {
        return "\(proto)"
    }
}

extension FingerprintProtoLogicalFingerprint {
    @objc
    public static func builder(identityData: Data) -> FingerprintProtoLogicalFingerprintBuilder {
        return FingerprintProtoLogicalFingerprintBuilder(identityData: identityData)
    }

    // asBuilder() constructs a builder that reflects the proto's contents.
    @objc
    public func asBuilder() -> FingerprintProtoLogicalFingerprintBuilder {
        let builder = FingerprintProtoLogicalFingerprintBuilder(identityData: identityData)
        if let _value = unknownFields {
            builder.setUnknownFields(_value)
        }
        return builder
    }
}

@objc
public class FingerprintProtoLogicalFingerprintBuilder: NSObject {

    private var proto = FingerprintProtos_LogicalFingerprint()

    @objc
    fileprivate override init() {}

    @objc
    fileprivate init(identityData: Data) {
        super.init()

        setIdentityData(identityData)
    }

    @objc
    @available(swift, obsoleted: 1.0)
    public func setIdentityData(_ valueParam: Data?) {
        guard let valueParam = valueParam else { return }
        proto.identityData = valueParam
    }

    public func setIdentityData(_ valueParam: Data) {
        proto.identityData = valueParam
    }

    public func setUnknownFields(_ unknownFields: SwiftProtobuf.UnknownStorage) {
        proto.unknownFields = unknownFields
    }

    @objc
    public func build() throws -> FingerprintProtoLogicalFingerprint {
        return try FingerprintProtoLogicalFingerprint(proto)
    }

    @objc
    public func buildSerializedData() throws -> Data {
        return try FingerprintProtoLogicalFingerprint(proto).serializedData()
    }
}

#if TESTABLE_BUILD

extension FingerprintProtoLogicalFingerprint {
    @objc
    public func serializedDataIgnoringErrors() -> Data? {
        return try! self.serializedData()
    }
}

extension FingerprintProtoLogicalFingerprintBuilder {
    @objc
    public func buildIgnoringErrors() -> FingerprintProtoLogicalFingerprint? {
        return try! self.build()
    }
}

#endif

// MARK: - FingerprintProtoLogicalFingerprints

@objc
public class FingerprintProtoLogicalFingerprints: NSObject, Codable, NSSecureCoding {

    fileprivate let proto: FingerprintProtos_LogicalFingerprints

    @objc
    public let version: UInt32

    @objc
    public let localFingerprint: FingerprintProtoLogicalFingerprint

    @objc
    public let remoteFingerprint: FingerprintProtoLogicalFingerprint

    public var hasUnknownFields: Bool {
        return !proto.unknownFields.data.isEmpty
    }
    public var unknownFields: SwiftProtobuf.UnknownStorage? {
        guard hasUnknownFields else { return nil }
        return proto.unknownFields
    }

    private init(proto: FingerprintProtos_LogicalFingerprints,
                 version: UInt32,
                 localFingerprint: FingerprintProtoLogicalFingerprint,
                 remoteFingerprint: FingerprintProtoLogicalFingerprint) {
        self.proto = proto
        self.version = version
        self.localFingerprint = localFingerprint
        self.remoteFingerprint = remoteFingerprint
    }

    @objc
    public func serializedData() throws -> Data {
        return try self.proto.serializedData()
    }

    @objc
    public convenience init(serializedData: Data) throws {
        let proto = try FingerprintProtos_LogicalFingerprints(serializedData: serializedData)
        try self.init(proto)
    }

    fileprivate convenience init(_ proto: FingerprintProtos_LogicalFingerprints) throws {
        guard proto.hasVersion else {
            throw FingerprintProtoError.invalidProtobuf(description: "\(Self.logTag()) missing required field: version")
        }
        let version = proto.version

        guard proto.hasLocalFingerprint else {
            throw FingerprintProtoError.invalidProtobuf(description: "\(Self.logTag()) missing required field: localFingerprint")
        }
        let localFingerprint = try FingerprintProtoLogicalFingerprint(proto.localFingerprint)

        guard proto.hasRemoteFingerprint else {
            throw FingerprintProtoError.invalidProtobuf(description: "\(Self.logTag()) missing required field: remoteFingerprint")
        }
        let remoteFingerprint = try FingerprintProtoLogicalFingerprint(proto.remoteFingerprint)

        // MARK: - Begin Validation Logic for FingerprintProtoLogicalFingerprints -

        // MARK: - End Validation Logic for FingerprintProtoLogicalFingerprints -

        self.init(proto: proto,
                  version: version,
                  localFingerprint: localFingerprint,
                  remoteFingerprint: remoteFingerprint)
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

    public static var supportsSecureCoding: Bool { true }

    public required convenience init?(coder: NSCoder) {
        guard let serializedData = coder.decodeData() else { return nil }
        do {
            try self.init(serializedData: serializedData)
        } catch {
            owsFailDebug("Failed to decode serialized data \(error)")
            return nil
        }
    }

    public func encode(with coder: NSCoder) {
        do {
            coder.encode(try serializedData())
        } catch {
            owsFailDebug("Failed to encode serialized data \(error)")
        }
    }

    @objc
    public override var debugDescription: String {
        return "\(proto)"
    }
}

extension FingerprintProtoLogicalFingerprints {
    @objc
    public static func builder(version: UInt32, localFingerprint: FingerprintProtoLogicalFingerprint, remoteFingerprint: FingerprintProtoLogicalFingerprint) -> FingerprintProtoLogicalFingerprintsBuilder {
        return FingerprintProtoLogicalFingerprintsBuilder(version: version, localFingerprint: localFingerprint, remoteFingerprint: remoteFingerprint)
    }

    // asBuilder() constructs a builder that reflects the proto's contents.
    @objc
    public func asBuilder() -> FingerprintProtoLogicalFingerprintsBuilder {
        let builder = FingerprintProtoLogicalFingerprintsBuilder(version: version, localFingerprint: localFingerprint, remoteFingerprint: remoteFingerprint)
        if let _value = unknownFields {
            builder.setUnknownFields(_value)
        }
        return builder
    }
}

@objc
public class FingerprintProtoLogicalFingerprintsBuilder: NSObject {

    private var proto = FingerprintProtos_LogicalFingerprints()

    @objc
    fileprivate override init() {}

    @objc
    fileprivate init(version: UInt32, localFingerprint: FingerprintProtoLogicalFingerprint, remoteFingerprint: FingerprintProtoLogicalFingerprint) {
        super.init()

        setVersion(version)
        setLocalFingerprint(localFingerprint)
        setRemoteFingerprint(remoteFingerprint)
    }

    @objc
    public func setVersion(_ valueParam: UInt32) {
        proto.version = valueParam
    }

    @objc
    @available(swift, obsoleted: 1.0)
    public func setLocalFingerprint(_ valueParam: FingerprintProtoLogicalFingerprint?) {
        guard let valueParam = valueParam else { return }
        proto.localFingerprint = valueParam.proto
    }

    public func setLocalFingerprint(_ valueParam: FingerprintProtoLogicalFingerprint) {
        proto.localFingerprint = valueParam.proto
    }

    @objc
    @available(swift, obsoleted: 1.0)
    public func setRemoteFingerprint(_ valueParam: FingerprintProtoLogicalFingerprint?) {
        guard let valueParam = valueParam else { return }
        proto.remoteFingerprint = valueParam.proto
    }

    public func setRemoteFingerprint(_ valueParam: FingerprintProtoLogicalFingerprint) {
        proto.remoteFingerprint = valueParam.proto
    }

    public func setUnknownFields(_ unknownFields: SwiftProtobuf.UnknownStorage) {
        proto.unknownFields = unknownFields
    }

    @objc
    public func build() throws -> FingerprintProtoLogicalFingerprints {
        return try FingerprintProtoLogicalFingerprints(proto)
    }

    @objc
    public func buildSerializedData() throws -> Data {
        return try FingerprintProtoLogicalFingerprints(proto).serializedData()
    }
}

#if TESTABLE_BUILD

extension FingerprintProtoLogicalFingerprints {
    @objc
    public func serializedDataIgnoringErrors() -> Data? {
        return try! self.serializedData()
    }
}

extension FingerprintProtoLogicalFingerprintsBuilder {
    @objc
    public func buildIgnoringErrors() -> FingerprintProtoLogicalFingerprints? {
        return try! self.build()
    }
}

#endif
