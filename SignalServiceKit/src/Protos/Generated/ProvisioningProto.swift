//
//  Copyright (c) 2020 Open Whisper Systems. All rights reserved.
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
public class ProvisioningProtoProvisioningUuid: NSObject, Codable {

    // MARK: - ProvisioningProtoProvisioningUuidBuilder

    @objc
    public class func builder(uuid: String) -> ProvisioningProtoProvisioningUuidBuilder {
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
            throw ProvisioningProtoError.invalidProtobuf(description: "\(Self.logTag) missing required field: uuid")
        }
        let uuid = proto.uuid

        // MARK: - Begin Validation Logic for ProvisioningProtoProvisioningUuid -

        // MARK: - End Validation Logic for ProvisioningProtoProvisioningUuid -

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

    @objc
    public override var debugDescription: String {
        return "\(proto)"
    }
}

#if DEBUG

extension ProvisioningProtoProvisioningUuid {
    @objc
    public func serializedDataIgnoringErrors() -> Data? {
        return try! self.serializedData()
    }
}

extension ProvisioningProtoProvisioningUuid.ProvisioningProtoProvisioningUuidBuilder {
    @objc
    public func buildIgnoringErrors() -> ProvisioningProtoProvisioningUuid? {
        return try! self.build()
    }
}

#endif

// MARK: - ProvisioningProtoProvisionEnvelope

@objc
public class ProvisioningProtoProvisionEnvelope: NSObject, Codable {

    // MARK: - ProvisioningProtoProvisionEnvelopeBuilder

    @objc
    public class func builder(publicKey: Data, body: Data) -> ProvisioningProtoProvisionEnvelopeBuilder {
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
            throw ProvisioningProtoError.invalidProtobuf(description: "\(Self.logTag) missing required field: publicKey")
        }
        let publicKey = proto.publicKey

        guard proto.hasBody else {
            throw ProvisioningProtoError.invalidProtobuf(description: "\(Self.logTag) missing required field: body")
        }
        let body = proto.body

        // MARK: - Begin Validation Logic for ProvisioningProtoProvisionEnvelope -

        // MARK: - End Validation Logic for ProvisioningProtoProvisionEnvelope -

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

    @objc
    public override var debugDescription: String {
        return "\(proto)"
    }
}

#if DEBUG

extension ProvisioningProtoProvisionEnvelope {
    @objc
    public func serializedDataIgnoringErrors() -> Data? {
        return try! self.serializedData()
    }
}

extension ProvisioningProtoProvisionEnvelope.ProvisioningProtoProvisionEnvelopeBuilder {
    @objc
    public func buildIgnoringErrors() -> ProvisioningProtoProvisionEnvelope? {
        return try! self.build()
    }
}

#endif

// MARK: - ProvisioningProtoProvisionMessage

@objc
public class ProvisioningProtoProvisionMessage: NSObject, Codable {

    // MARK: - ProvisioningProtoProvisionMessageBuilder

    @objc
    public class func builder(identityKeyPublic: Data, identityKeyPrivate: Data, provisioningCode: String, profileKey: Data) -> ProvisioningProtoProvisionMessageBuilder {
        return ProvisioningProtoProvisionMessageBuilder(identityKeyPublic: identityKeyPublic, identityKeyPrivate: identityKeyPrivate, provisioningCode: provisioningCode, profileKey: profileKey)
    }

    // asBuilder() constructs a builder that reflects the proto's contents.
    @objc
    public func asBuilder() -> ProvisioningProtoProvisionMessageBuilder {
        let builder = ProvisioningProtoProvisionMessageBuilder(identityKeyPublic: identityKeyPublic, identityKeyPrivate: identityKeyPrivate, provisioningCode: provisioningCode, profileKey: profileKey)
        if let _value = number {
            builder.setNumber(_value)
        }
        if let _value = uuid {
            builder.setUuid(_value)
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

    @objc
    public class ProvisioningProtoProvisionMessageBuilder: NSObject {

        private var proto = ProvisioningProtos_ProvisionMessage()

        @objc
        fileprivate override init() {}

        @objc
        fileprivate init(identityKeyPublic: Data, identityKeyPrivate: Data, provisioningCode: String, profileKey: Data) {
            super.init()

            setIdentityKeyPublic(identityKeyPublic)
            setIdentityKeyPrivate(identityKeyPrivate)
            setProvisioningCode(provisioningCode)
            setProfileKey(profileKey)
        }

        @objc
        @available(swift, obsoleted: 1.0)
        public func setIdentityKeyPublic(_ valueParam: Data?) {
            guard let valueParam = valueParam else { return }
            proto.identityKeyPublic = valueParam
        }

        public func setIdentityKeyPublic(_ valueParam: Data) {
            proto.identityKeyPublic = valueParam
        }

        @objc
        @available(swift, obsoleted: 1.0)
        public func setIdentityKeyPrivate(_ valueParam: Data?) {
            guard let valueParam = valueParam else { return }
            proto.identityKeyPrivate = valueParam
        }

        public func setIdentityKeyPrivate(_ valueParam: Data) {
            proto.identityKeyPrivate = valueParam
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
        public func setUuid(_ valueParam: String?) {
            guard let valueParam = valueParam else { return }
            proto.uuid = valueParam
        }

        public func setUuid(_ valueParam: String) {
            proto.uuid = valueParam
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

    fileprivate let proto: ProvisioningProtos_ProvisionMessage

    @objc
    public let identityKeyPublic: Data

    @objc
    public let identityKeyPrivate: Data

    @objc
    public let provisioningCode: String

    @objc
    public let profileKey: Data

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
    public var uuid: String? {
        guard hasUuid else {
            return nil
        }
        return proto.uuid
    }
    @objc
    public var hasUuid: Bool {
        return proto.hasUuid
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
                 identityKeyPublic: Data,
                 identityKeyPrivate: Data,
                 provisioningCode: String,
                 profileKey: Data) {
        self.proto = proto
        self.identityKeyPublic = identityKeyPublic
        self.identityKeyPrivate = identityKeyPrivate
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
        guard proto.hasIdentityKeyPublic else {
            throw ProvisioningProtoError.invalidProtobuf(description: "\(Self.logTag) missing required field: identityKeyPublic")
        }
        let identityKeyPublic = proto.identityKeyPublic

        guard proto.hasIdentityKeyPrivate else {
            throw ProvisioningProtoError.invalidProtobuf(description: "\(Self.logTag) missing required field: identityKeyPrivate")
        }
        let identityKeyPrivate = proto.identityKeyPrivate

        guard proto.hasProvisioningCode else {
            throw ProvisioningProtoError.invalidProtobuf(description: "\(Self.logTag) missing required field: provisioningCode")
        }
        let provisioningCode = proto.provisioningCode

        guard proto.hasProfileKey else {
            throw ProvisioningProtoError.invalidProtobuf(description: "\(Self.logTag) missing required field: profileKey")
        }
        let profileKey = proto.profileKey

        // MARK: - Begin Validation Logic for ProvisioningProtoProvisionMessage -

        // MARK: - End Validation Logic for ProvisioningProtoProvisionMessage -

        self.init(proto: proto,
                  identityKeyPublic: identityKeyPublic,
                  identityKeyPrivate: identityKeyPrivate,
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

    @objc
    public override var debugDescription: String {
        return "\(proto)"
    }
}

#if DEBUG

extension ProvisioningProtoProvisionMessage {
    @objc
    public func serializedDataIgnoringErrors() -> Data? {
        return try! self.serializedData()
    }
}

extension ProvisioningProtoProvisionMessage.ProvisioningProtoProvisionMessageBuilder {
    @objc
    public func buildIgnoringErrors() -> ProvisioningProtoProvisionMessage? {
        return try! self.build()
    }
}

#endif
