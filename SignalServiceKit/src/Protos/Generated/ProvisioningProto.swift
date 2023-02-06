//
// Copyright 2022 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import SignalCoreKit
import SwiftProtobuf

// WARNING: This code is generated. Only edit within the markers.

public enum ProvisioningProtoError: Error {
    case invalidProtobuf(description: String)
}

// MARK: - ProvisioningProtoProvisioningUuid

@objc
public class ProvisioningProtoProvisioningUuid: NSObject, Codable, NSSecureCoding {

    fileprivate let proto: ProvisioningProtos_ProvisioningUuid

    @objc
    public let uuid: String

    public var hasUnknownFields: Bool {
        return !proto.unknownFields.data.isEmpty
    }
    public var unknownFields: SwiftProtobuf.UnknownStorage? {
        guard hasUnknownFields else { return nil }
        return proto.unknownFields
    }

    private init(proto: ProvisioningProtos_ProvisioningUuid,
                 uuid: String) {
        self.proto = proto
        self.uuid = uuid
    }

    @objc
    public func serializedData() throws -> Data {
        return try self.proto.serializedData()
    }

    @objc
    public convenience init(serializedData: Data) throws {
        let proto = try ProvisioningProtos_ProvisioningUuid(serializedData: serializedData)
        try self.init(proto)
    }

    fileprivate convenience init(_ proto: ProvisioningProtos_ProvisioningUuid) throws {
        guard proto.hasUuid else {
            throw ProvisioningProtoError.invalidProtobuf(description: "\(Self.logTag()) missing required field: uuid")
        }
        let uuid = proto.uuid

        self.init(proto: proto,
                  uuid: uuid)
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

extension ProvisioningProtoProvisioningUuid {
    @objc
    public static func builder(uuid: String) -> ProvisioningProtoProvisioningUuidBuilder {
        return ProvisioningProtoProvisioningUuidBuilder(uuid: uuid)
    }

    // asBuilder() constructs a builder that reflects the proto's contents.
    @objc
    public func asBuilder() -> ProvisioningProtoProvisioningUuidBuilder {
        let builder = ProvisioningProtoProvisioningUuidBuilder(uuid: uuid)
        if let _value = unknownFields {
            builder.setUnknownFields(_value)
        }
        return builder
    }
}

@objc
public class ProvisioningProtoProvisioningUuidBuilder: NSObject {

    private var proto = ProvisioningProtos_ProvisioningUuid()

    @objc
    fileprivate override init() {}

    @objc
    fileprivate init(uuid: String) {
        super.init()

        setUuid(uuid)
    }

    @objc
    @available(swift, obsoleted: 1.0)
    public func setUuid(_ valueParam: String?) {
        guard let valueParam = valueParam else { return }
        proto.uuid = valueParam
    }

    public func setUuid(_ valueParam: String) {
        proto.uuid = valueParam
    }

    public func setUnknownFields(_ unknownFields: SwiftProtobuf.UnknownStorage) {
        proto.unknownFields = unknownFields
    }

    @objc
    public func build() throws -> ProvisioningProtoProvisioningUuid {
        return try ProvisioningProtoProvisioningUuid(proto)
    }

    @objc
    public func buildSerializedData() throws -> Data {
        return try ProvisioningProtoProvisioningUuid(proto).serializedData()
    }
}

#if TESTABLE_BUILD

extension ProvisioningProtoProvisioningUuid {
    @objc
    public func serializedDataIgnoringErrors() -> Data? {
        return try! self.serializedData()
    }
}

extension ProvisioningProtoProvisioningUuidBuilder {
    @objc
    public func buildIgnoringErrors() -> ProvisioningProtoProvisioningUuid? {
        return try! self.build()
    }
}

#endif

// MARK: - ProvisioningProtoProvisionEnvelope

@objc
public class ProvisioningProtoProvisionEnvelope: NSObject, Codable, NSSecureCoding {

    fileprivate let proto: ProvisioningProtos_ProvisionEnvelope

    @objc
    public let publicKey: Data

    @objc
    public let body: Data

    public var hasUnknownFields: Bool {
        return !proto.unknownFields.data.isEmpty
    }
    public var unknownFields: SwiftProtobuf.UnknownStorage? {
        guard hasUnknownFields else { return nil }
        return proto.unknownFields
    }

    private init(proto: ProvisioningProtos_ProvisionEnvelope,
                 publicKey: Data,
                 body: Data) {
        self.proto = proto
        self.publicKey = publicKey
        self.body = body
    }

    @objc
    public func serializedData() throws -> Data {
        return try self.proto.serializedData()
    }

    @objc
    public convenience init(serializedData: Data) throws {
        let proto = try ProvisioningProtos_ProvisionEnvelope(serializedData: serializedData)
        try self.init(proto)
    }

    fileprivate convenience init(_ proto: ProvisioningProtos_ProvisionEnvelope) throws {
        guard proto.hasPublicKey else {
            throw ProvisioningProtoError.invalidProtobuf(description: "\(Self.logTag()) missing required field: publicKey")
        }
        let publicKey = proto.publicKey

        guard proto.hasBody else {
            throw ProvisioningProtoError.invalidProtobuf(description: "\(Self.logTag()) missing required field: body")
        }
        let body = proto.body

        self.init(proto: proto,
                  publicKey: publicKey,
                  body: body)
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

extension ProvisioningProtoProvisionEnvelope {
    @objc
    public static func builder(publicKey: Data, body: Data) -> ProvisioningProtoProvisionEnvelopeBuilder {
        return ProvisioningProtoProvisionEnvelopeBuilder(publicKey: publicKey, body: body)
    }

    // asBuilder() constructs a builder that reflects the proto's contents.
    @objc
    public func asBuilder() -> ProvisioningProtoProvisionEnvelopeBuilder {
        let builder = ProvisioningProtoProvisionEnvelopeBuilder(publicKey: publicKey, body: body)
        if let _value = unknownFields {
            builder.setUnknownFields(_value)
        }
        return builder
    }
}

@objc
public class ProvisioningProtoProvisionEnvelopeBuilder: NSObject {

    private var proto = ProvisioningProtos_ProvisionEnvelope()

    @objc
    fileprivate override init() {}

    @objc
    fileprivate init(publicKey: Data, body: Data) {
        super.init()

        setPublicKey(publicKey)
        setBody(body)
    }

    @objc
    @available(swift, obsoleted: 1.0)
    public func setPublicKey(_ valueParam: Data?) {
        guard let valueParam = valueParam else { return }
        proto.publicKey = valueParam
    }

    public func setPublicKey(_ valueParam: Data) {
        proto.publicKey = valueParam
    }

    @objc
    @available(swift, obsoleted: 1.0)
    public func setBody(_ valueParam: Data?) {
        guard let valueParam = valueParam else { return }
        proto.body = valueParam
    }

    public func setBody(_ valueParam: Data) {
        proto.body = valueParam
    }

    public func setUnknownFields(_ unknownFields: SwiftProtobuf.UnknownStorage) {
        proto.unknownFields = unknownFields
    }

    @objc
    public func build() throws -> ProvisioningProtoProvisionEnvelope {
        return try ProvisioningProtoProvisionEnvelope(proto)
    }

    @objc
    public func buildSerializedData() throws -> Data {
        return try ProvisioningProtoProvisionEnvelope(proto).serializedData()
    }
}

#if TESTABLE_BUILD

extension ProvisioningProtoProvisionEnvelope {
    @objc
    public func serializedDataIgnoringErrors() -> Data? {
        return try! self.serializedData()
    }
}

extension ProvisioningProtoProvisionEnvelopeBuilder {
    @objc
    public func buildIgnoringErrors() -> ProvisioningProtoProvisionEnvelope? {
        return try! self.build()
    }
}

#endif

// MARK: - ProvisioningProtoProvisionMessage

@objc
public class ProvisioningProtoProvisionMessage: NSObject, Codable, NSSecureCoding {

    fileprivate let proto: ProvisioningProtos_ProvisionMessage

    @objc
    public let aciIdentityKeyPublic: Data

    @objc
    public let aciIdentityKeyPrivate: Data

    @objc
    public let provisioningCode: String

    @objc
    public let profileKey: Data

    @objc
    public var pniIdentityKeyPublic: Data? {
        guard hasPniIdentityKeyPublic else {
            return nil
        }
        return proto.pniIdentityKeyPublic
    }
    @objc
    public var hasPniIdentityKeyPublic: Bool {
        return proto.hasPniIdentityKeyPublic
    }

    @objc
    public var pniIdentityKeyPrivate: Data? {
        guard hasPniIdentityKeyPrivate else {
            return nil
        }
        return proto.pniIdentityKeyPrivate
    }
    @objc
    public var hasPniIdentityKeyPrivate: Bool {
        return proto.hasPniIdentityKeyPrivate
    }

    @objc
    public var aci: String? {
        guard hasAci else {
            return nil
        }
        return proto.aci
    }
    @objc
    public var hasAci: Bool {
        return proto.hasAci
    }

    @objc
    public var pni: String? {
        guard hasPni else {
            return nil
        }
        return proto.pni
    }
    @objc
    public var hasPni: Bool {
        return proto.hasPni
    }

    @objc
    public var number: String? {
        guard hasNumber else {
            return nil
        }
        return proto.number
    }
    @objc
    public var hasNumber: Bool {
        return proto.hasNumber
    }

    @objc
    public var userAgent: String? {
        guard hasUserAgent else {
            return nil
        }
        return proto.userAgent
    }
    @objc
    public var hasUserAgent: Bool {
        return proto.hasUserAgent
    }

    @objc
    public var readReceipts: Bool {
        return proto.readReceipts
    }
    @objc
    public var hasReadReceipts: Bool {
        return proto.hasReadReceipts
    }

    @objc
    public var provisioningVersion: UInt32 {
        return proto.provisioningVersion
    }
    @objc
    public var hasProvisioningVersion: Bool {
        return proto.hasProvisioningVersion
    }

    public var hasUnknownFields: Bool {
        return !proto.unknownFields.data.isEmpty
    }
    public var unknownFields: SwiftProtobuf.UnknownStorage? {
        guard hasUnknownFields else { return nil }
        return proto.unknownFields
    }

    private init(proto: ProvisioningProtos_ProvisionMessage,
                 aciIdentityKeyPublic: Data,
                 aciIdentityKeyPrivate: Data,
                 provisioningCode: String,
                 profileKey: Data) {
        self.proto = proto
        self.aciIdentityKeyPublic = aciIdentityKeyPublic
        self.aciIdentityKeyPrivate = aciIdentityKeyPrivate
        self.provisioningCode = provisioningCode
        self.profileKey = profileKey
    }

    @objc
    public func serializedData() throws -> Data {
        return try self.proto.serializedData()
    }

    @objc
    public convenience init(serializedData: Data) throws {
        let proto = try ProvisioningProtos_ProvisionMessage(serializedData: serializedData)
        try self.init(proto)
    }

    fileprivate convenience init(_ proto: ProvisioningProtos_ProvisionMessage) throws {
        guard proto.hasAciIdentityKeyPublic else {
            throw ProvisioningProtoError.invalidProtobuf(description: "\(Self.logTag()) missing required field: aciIdentityKeyPublic")
        }
        let aciIdentityKeyPublic = proto.aciIdentityKeyPublic

        guard proto.hasAciIdentityKeyPrivate else {
            throw ProvisioningProtoError.invalidProtobuf(description: "\(Self.logTag()) missing required field: aciIdentityKeyPrivate")
        }
        let aciIdentityKeyPrivate = proto.aciIdentityKeyPrivate

        guard proto.hasProvisioningCode else {
            throw ProvisioningProtoError.invalidProtobuf(description: "\(Self.logTag()) missing required field: provisioningCode")
        }
        let provisioningCode = proto.provisioningCode

        guard proto.hasProfileKey else {
            throw ProvisioningProtoError.invalidProtobuf(description: "\(Self.logTag()) missing required field: profileKey")
        }
        let profileKey = proto.profileKey

        self.init(proto: proto,
                  aciIdentityKeyPublic: aciIdentityKeyPublic,
                  aciIdentityKeyPrivate: aciIdentityKeyPrivate,
                  provisioningCode: provisioningCode,
                  profileKey: profileKey)
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

extension ProvisioningProtoProvisionMessage {
    @objc
    public static func builder(aciIdentityKeyPublic: Data, aciIdentityKeyPrivate: Data, provisioningCode: String, profileKey: Data) -> ProvisioningProtoProvisionMessageBuilder {
        return ProvisioningProtoProvisionMessageBuilder(aciIdentityKeyPublic: aciIdentityKeyPublic, aciIdentityKeyPrivate: aciIdentityKeyPrivate, provisioningCode: provisioningCode, profileKey: profileKey)
    }

    // asBuilder() constructs a builder that reflects the proto's contents.
    @objc
    public func asBuilder() -> ProvisioningProtoProvisionMessageBuilder {
        let builder = ProvisioningProtoProvisionMessageBuilder(aciIdentityKeyPublic: aciIdentityKeyPublic, aciIdentityKeyPrivate: aciIdentityKeyPrivate, provisioningCode: provisioningCode, profileKey: profileKey)
        if let _value = pniIdentityKeyPublic {
            builder.setPniIdentityKeyPublic(_value)
        }
        if let _value = pniIdentityKeyPrivate {
            builder.setPniIdentityKeyPrivate(_value)
        }
        if let _value = aci {
            builder.setAci(_value)
        }
        if let _value = pni {
            builder.setPni(_value)
        }
        if let _value = number {
            builder.setNumber(_value)
        }
        if let _value = userAgent {
            builder.setUserAgent(_value)
        }
        if hasReadReceipts {
            builder.setReadReceipts(readReceipts)
        }
        if hasProvisioningVersion {
            builder.setProvisioningVersion(provisioningVersion)
        }
        if let _value = unknownFields {
            builder.setUnknownFields(_value)
        }
        return builder
    }
}

@objc
public class ProvisioningProtoProvisionMessageBuilder: NSObject {

    private var proto = ProvisioningProtos_ProvisionMessage()

    @objc
    fileprivate override init() {}

    @objc
    fileprivate init(aciIdentityKeyPublic: Data, aciIdentityKeyPrivate: Data, provisioningCode: String, profileKey: Data) {
        super.init()

        setAciIdentityKeyPublic(aciIdentityKeyPublic)
        setAciIdentityKeyPrivate(aciIdentityKeyPrivate)
        setProvisioningCode(provisioningCode)
        setProfileKey(profileKey)
    }

    @objc
    @available(swift, obsoleted: 1.0)
    public func setAciIdentityKeyPublic(_ valueParam: Data?) {
        guard let valueParam = valueParam else { return }
        proto.aciIdentityKeyPublic = valueParam
    }

    public func setAciIdentityKeyPublic(_ valueParam: Data) {
        proto.aciIdentityKeyPublic = valueParam
    }

    @objc
    @available(swift, obsoleted: 1.0)
    public func setAciIdentityKeyPrivate(_ valueParam: Data?) {
        guard let valueParam = valueParam else { return }
        proto.aciIdentityKeyPrivate = valueParam
    }

    public func setAciIdentityKeyPrivate(_ valueParam: Data) {
        proto.aciIdentityKeyPrivate = valueParam
    }

    @objc
    @available(swift, obsoleted: 1.0)
    public func setPniIdentityKeyPublic(_ valueParam: Data?) {
        guard let valueParam = valueParam else { return }
        proto.pniIdentityKeyPublic = valueParam
    }

    public func setPniIdentityKeyPublic(_ valueParam: Data) {
        proto.pniIdentityKeyPublic = valueParam
    }

    @objc
    @available(swift, obsoleted: 1.0)
    public func setPniIdentityKeyPrivate(_ valueParam: Data?) {
        guard let valueParam = valueParam else { return }
        proto.pniIdentityKeyPrivate = valueParam
    }

    public func setPniIdentityKeyPrivate(_ valueParam: Data) {
        proto.pniIdentityKeyPrivate = valueParam
    }

    @objc
    @available(swift, obsoleted: 1.0)
    public func setAci(_ valueParam: String?) {
        guard let valueParam = valueParam else { return }
        proto.aci = valueParam
    }

    public func setAci(_ valueParam: String) {
        proto.aci = valueParam
    }

    @objc
    @available(swift, obsoleted: 1.0)
    public func setPni(_ valueParam: String?) {
        guard let valueParam = valueParam else { return }
        proto.pni = valueParam
    }

    public func setPni(_ valueParam: String) {
        proto.pni = valueParam
    }

    @objc
    @available(swift, obsoleted: 1.0)
    public func setNumber(_ valueParam: String?) {
        guard let valueParam = valueParam else { return }
        proto.number = valueParam
    }

    public func setNumber(_ valueParam: String) {
        proto.number = valueParam
    }

    @objc
    @available(swift, obsoleted: 1.0)
    public func setProvisioningCode(_ valueParam: String?) {
        guard let valueParam = valueParam else { return }
        proto.provisioningCode = valueParam
    }

    public func setProvisioningCode(_ valueParam: String) {
        proto.provisioningCode = valueParam
    }

    @objc
    @available(swift, obsoleted: 1.0)
    public func setUserAgent(_ valueParam: String?) {
        guard let valueParam = valueParam else { return }
        proto.userAgent = valueParam
    }

    public func setUserAgent(_ valueParam: String) {
        proto.userAgent = valueParam
    }

    @objc
    @available(swift, obsoleted: 1.0)
    public func setProfileKey(_ valueParam: Data?) {
        guard let valueParam = valueParam else { return }
        proto.profileKey = valueParam
    }

    public func setProfileKey(_ valueParam: Data) {
        proto.profileKey = valueParam
    }

    @objc
    public func setReadReceipts(_ valueParam: Bool) {
        proto.readReceipts = valueParam
    }

    @objc
    public func setProvisioningVersion(_ valueParam: UInt32) {
        proto.provisioningVersion = valueParam
    }

    public func setUnknownFields(_ unknownFields: SwiftProtobuf.UnknownStorage) {
        proto.unknownFields = unknownFields
    }

    @objc
    public func build() throws -> ProvisioningProtoProvisionMessage {
        return try ProvisioningProtoProvisionMessage(proto)
    }

    @objc
    public func buildSerializedData() throws -> Data {
        return try ProvisioningProtoProvisionMessage(proto).serializedData()
    }
}

#if TESTABLE_BUILD

extension ProvisioningProtoProvisionMessage {
    @objc
    public func serializedDataIgnoringErrors() -> Data? {
        return try! self.serializedData()
    }
}

extension ProvisioningProtoProvisionMessageBuilder {
    @objc
    public func buildIgnoringErrors() -> ProvisioningProtoProvisionMessage? {
        return try! self.build()
    }
}

#endif
