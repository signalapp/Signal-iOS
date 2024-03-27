//
// Copyright 2022 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import SignalCoreKit
import SwiftProtobuf

// WARNING: This code is generated. Only edit within the markers.

public enum SignalIOSProtoError: Error {
    case invalidProtobuf(description: String)
}

// MARK: - SignalIOSProtoDeviceName

@objc
public class SignalIOSProtoDeviceName: NSObject, Codable, NSSecureCoding {

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
            throw SignalIOSProtoError.invalidProtobuf(description: "\(Self.logTag()) missing required field: ephemeralPublic")
        }
        let ephemeralPublic = proto.ephemeralPublic

        guard proto.hasSyntheticIv else {
            throw SignalIOSProtoError.invalidProtobuf(description: "\(Self.logTag()) missing required field: syntheticIv")
        }
        let syntheticIv = proto.syntheticIv

        guard proto.hasCiphertext else {
            throw SignalIOSProtoError.invalidProtobuf(description: "\(Self.logTag()) missing required field: ciphertext")
        }
        let ciphertext = proto.ciphertext

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

extension SignalIOSProtoDeviceName {
    @objc
    public static func builder(ephemeralPublic: Data, syntheticIv: Data, ciphertext: Data) -> SignalIOSProtoDeviceNameBuilder {
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

#if TESTABLE_BUILD

extension SignalIOSProtoDeviceName {
    @objc
    public func serializedDataIgnoringErrors() -> Data? {
        return try! self.serializedData()
    }
}

extension SignalIOSProtoDeviceNameBuilder {
    @objc
    public func buildIgnoringErrors() -> SignalIOSProtoDeviceName? {
        return try! self.build()
    }
}

#endif
