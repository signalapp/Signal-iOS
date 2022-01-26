//
//  Copyright (c) 2019 Open Whisper Systems. All rights reserved.
//

import Foundation
import SignalCoreKit

// WARNING: This code is generated. Only edit within the markers.

public enum SMKProtoError: Error {
    case invalidProtobuf(description: String)
}

// MARK: - SMKProtoServerCertificateCertificate

@objc public class SMKProtoServerCertificateCertificate: NSObject {

    // MARK: - SMKProtoServerCertificateCertificateBuilder

    @objc public class func builder(id: UInt32, key: Data) -> SMKProtoServerCertificateCertificateBuilder {
        return SMKProtoServerCertificateCertificateBuilder(id: id, key: key)
    }

    // asBuilder() constructs a builder that reflects the proto's contents.
    @objc public func asBuilder() -> SMKProtoServerCertificateCertificateBuilder {
        let builder = SMKProtoServerCertificateCertificateBuilder(id: id, key: key)
        return builder
    }

    @objc public class SMKProtoServerCertificateCertificateBuilder: NSObject {

        private var proto = SMKProtos_ServerCertificate.Certificate()

        @objc fileprivate override init() {}

        @objc fileprivate init(id: UInt32, key: Data) {
            super.init()

            setId(id)
            setKey(key)
        }

        @objc public func setId(_ valueParam: UInt32) {
            proto.id = valueParam
        }

        @objc public func setKey(_ valueParam: Data) {
            proto.key = valueParam
        }

        @objc public func build() throws -> SMKProtoServerCertificateCertificate {
            return try SMKProtoServerCertificateCertificate.parseProto(proto)
        }

        @objc public func buildSerializedData() throws -> Data {
            return try SMKProtoServerCertificateCertificate.parseProto(proto).serializedData()
        }
    }

    fileprivate let proto: SMKProtos_ServerCertificate.Certificate

    @objc public let id: UInt32

    @objc public let key: Data

    private init(proto: SMKProtos_ServerCertificate.Certificate,
                 id: UInt32,
                 key: Data) {
        self.proto = proto
        self.id = id
        self.key = key
    }

    @objc
    public func serializedData() throws -> Data {
        return try self.proto.serializedData()
    }

    @objc public class func parseData(_ serializedData: Data) throws -> SMKProtoServerCertificateCertificate {
        let proto = try SMKProtos_ServerCertificate.Certificate(serializedData: serializedData)
        return try parseProto(proto)
    }

    fileprivate class func parseProto(_ proto: SMKProtos_ServerCertificate.Certificate) throws -> SMKProtoServerCertificateCertificate {
        guard proto.hasID else {
            throw SMKProtoError.invalidProtobuf(description: "\(logTag) missing required field: id")
        }
        let id = proto.id

        guard proto.hasKey else {
            throw SMKProtoError.invalidProtobuf(description: "\(logTag) missing required field: key")
        }
        let key = proto.key

        // MARK: - Begin Validation Logic for SMKProtoServerCertificateCertificate -

        // MARK: - End Validation Logic for SMKProtoServerCertificateCertificate -

        let result = SMKProtoServerCertificateCertificate(proto: proto,
                                                          id: id,
                                                          key: key)
        return result
    }

    @objc public override var debugDescription: String {
        return "\(proto)"
    }
}

#if DEBUG

extension SMKProtoServerCertificateCertificate {
    @objc public func serializedDataIgnoringErrors() -> Data? {
        return try! self.serializedData()
    }
}

extension SMKProtoServerCertificateCertificate.SMKProtoServerCertificateCertificateBuilder {
    @objc public func buildIgnoringErrors() -> SMKProtoServerCertificateCertificate? {
        return try! self.build()
    }
}

#endif

// MARK: - SMKProtoServerCertificate

@objc public class SMKProtoServerCertificate: NSObject {

    // MARK: - SMKProtoServerCertificateBuilder

    @objc public class func builder(certificate: Data, signature: Data) -> SMKProtoServerCertificateBuilder {
        return SMKProtoServerCertificateBuilder(certificate: certificate, signature: signature)
    }

    // asBuilder() constructs a builder that reflects the proto's contents.
    @objc public func asBuilder() -> SMKProtoServerCertificateBuilder {
        let builder = SMKProtoServerCertificateBuilder(certificate: certificate, signature: signature)
        return builder
    }

    @objc public class SMKProtoServerCertificateBuilder: NSObject {

        private var proto = SMKProtos_ServerCertificate()

        @objc fileprivate override init() {}

        @objc fileprivate init(certificate: Data, signature: Data) {
            super.init()

            setCertificate(certificate)
            setSignature(signature)
        }

        @objc public func setCertificate(_ valueParam: Data) {
            proto.certificate = valueParam
        }

        @objc public func setSignature(_ valueParam: Data) {
            proto.signature = valueParam
        }

        @objc public func build() throws -> SMKProtoServerCertificate {
            return try SMKProtoServerCertificate.parseProto(proto)
        }

        @objc public func buildSerializedData() throws -> Data {
            return try SMKProtoServerCertificate.parseProto(proto).serializedData()
        }
    }

    fileprivate let proto: SMKProtos_ServerCertificate

    @objc public let certificate: Data

    @objc public let signature: Data

    private init(proto: SMKProtos_ServerCertificate,
                 certificate: Data,
                 signature: Data) {
        self.proto = proto
        self.certificate = certificate
        self.signature = signature
    }

    @objc
    public func serializedData() throws -> Data {
        return try self.proto.serializedData()
    }

    @objc public class func parseData(_ serializedData: Data) throws -> SMKProtoServerCertificate {
        let proto = try SMKProtos_ServerCertificate(serializedData: serializedData)
        return try parseProto(proto)
    }

    fileprivate class func parseProto(_ proto: SMKProtos_ServerCertificate) throws -> SMKProtoServerCertificate {
        guard proto.hasCertificate else {
            throw SMKProtoError.invalidProtobuf(description: "\(logTag) missing required field: certificate")
        }
        let certificate = proto.certificate

        guard proto.hasSignature else {
            throw SMKProtoError.invalidProtobuf(description: "\(logTag) missing required field: signature")
        }
        let signature = proto.signature

        // MARK: - Begin Validation Logic for SMKProtoServerCertificate -

        // MARK: - End Validation Logic for SMKProtoServerCertificate -

        let result = SMKProtoServerCertificate(proto: proto,
                                               certificate: certificate,
                                               signature: signature)
        return result
    }

    @objc public override var debugDescription: String {
        return "\(proto)"
    }
}

#if DEBUG

extension SMKProtoServerCertificate {
    @objc public func serializedDataIgnoringErrors() -> Data? {
        return try! self.serializedData()
    }
}

extension SMKProtoServerCertificate.SMKProtoServerCertificateBuilder {
    @objc public func buildIgnoringErrors() -> SMKProtoServerCertificate? {
        return try! self.build()
    }
}

#endif

// MARK: - SMKProtoSenderCertificateCertificate

@objc public class SMKProtoSenderCertificateCertificate: NSObject {

    // MARK: - SMKProtoSenderCertificateCertificateBuilder

    @objc public class func builder(senderDevice: UInt32, expires: UInt64, identityKey: Data, signer: SMKProtoServerCertificate) -> SMKProtoSenderCertificateCertificateBuilder {
        return SMKProtoSenderCertificateCertificateBuilder(senderDevice: senderDevice, expires: expires, identityKey: identityKey, signer: signer)
    }

    // asBuilder() constructs a builder that reflects the proto's contents.
    @objc public func asBuilder() -> SMKProtoSenderCertificateCertificateBuilder {
        let builder = SMKProtoSenderCertificateCertificateBuilder(senderDevice: senderDevice, expires: expires, identityKey: identityKey, signer: signer)
        if let _value = senderE164 {
            builder.setSenderE164(_value)
        }
        if let _value = senderUuid {
            builder.setSenderUuid(_value)
        }
        return builder
    }

    @objc public class SMKProtoSenderCertificateCertificateBuilder: NSObject {

        private var proto = SMKProtos_SenderCertificate.Certificate()

        @objc fileprivate override init() {}

        @objc fileprivate init(senderDevice: UInt32, expires: UInt64, identityKey: Data, signer: SMKProtoServerCertificate) {
            super.init()

            setSenderDevice(senderDevice)
            setExpires(expires)
            setIdentityKey(identityKey)
            setSigner(signer)
        }

        @objc public func setSenderE164(_ valueParam: String) {
            proto.senderE164 = valueParam
        }

        @objc public func setSenderUuid(_ valueParam: String) {
            proto.senderUuid = valueParam
        }

        @objc public func setSenderDevice(_ valueParam: UInt32) {
            proto.senderDevice = valueParam
        }

        @objc public func setExpires(_ valueParam: UInt64) {
            proto.expires = valueParam
        }

        @objc public func setIdentityKey(_ valueParam: Data) {
            proto.identityKey = valueParam
        }

        @objc public func setSigner(_ valueParam: SMKProtoServerCertificate) {
            proto.signer = valueParam.proto
        }

        @objc public func build() throws -> SMKProtoSenderCertificateCertificate {
            return try SMKProtoSenderCertificateCertificate.parseProto(proto)
        }

        @objc public func buildSerializedData() throws -> Data {
            return try SMKProtoSenderCertificateCertificate.parseProto(proto).serializedData()
        }
    }

    fileprivate let proto: SMKProtos_SenderCertificate.Certificate

    @objc public let senderDevice: UInt32

    @objc public let expires: UInt64

    @objc public let identityKey: Data

    @objc public let signer: SMKProtoServerCertificate

    @objc public var senderE164: String? {
        guard proto.hasSenderE164 else {
            return nil
        }
        return proto.senderE164
    }
    @objc public var hasSenderE164: Bool {
        return proto.hasSenderE164
    }

    @objc public var senderUuid: String? {
        guard proto.hasSenderUuid else {
            return nil
        }
        return proto.senderUuid
    }
    @objc public var hasSenderUuid: Bool {
        return proto.hasSenderUuid
    }

    private init(proto: SMKProtos_SenderCertificate.Certificate,
                 senderDevice: UInt32,
                 expires: UInt64,
                 identityKey: Data,
                 signer: SMKProtoServerCertificate) {
        self.proto = proto
        self.senderDevice = senderDevice
        self.expires = expires
        self.identityKey = identityKey
        self.signer = signer
    }

    @objc
    public func serializedData() throws -> Data {
        return try self.proto.serializedData()
    }

    @objc public class func parseData(_ serializedData: Data) throws -> SMKProtoSenderCertificateCertificate {
        let proto = try SMKProtos_SenderCertificate.Certificate(serializedData: serializedData)
        return try parseProto(proto)
    }

    fileprivate class func parseProto(_ proto: SMKProtos_SenderCertificate.Certificate) throws -> SMKProtoSenderCertificateCertificate {
        guard proto.hasSenderDevice else {
            throw SMKProtoError.invalidProtobuf(description: "\(logTag) missing required field: senderDevice")
        }
        let senderDevice = proto.senderDevice

        guard proto.hasExpires else {
            throw SMKProtoError.invalidProtobuf(description: "\(logTag) missing required field: expires")
        }
        let expires = proto.expires

        guard proto.hasIdentityKey else {
            throw SMKProtoError.invalidProtobuf(description: "\(logTag) missing required field: identityKey")
        }
        let identityKey = proto.identityKey

        guard proto.hasSigner else {
            throw SMKProtoError.invalidProtobuf(description: "\(logTag) missing required field: signer")
        }
        let signer = try SMKProtoServerCertificate.parseProto(proto.signer)

        // MARK: - Begin Validation Logic for SMKProtoSenderCertificateCertificate -

        // MARK: - End Validation Logic for SMKProtoSenderCertificateCertificate -

        let result = SMKProtoSenderCertificateCertificate(proto: proto,
                                                          senderDevice: senderDevice,
                                                          expires: expires,
                                                          identityKey: identityKey,
                                                          signer: signer)
        return result
    }

    @objc public override var debugDescription: String {
        return "\(proto)"
    }
}

#if DEBUG

extension SMKProtoSenderCertificateCertificate {
    @objc public func serializedDataIgnoringErrors() -> Data? {
        return try! self.serializedData()
    }
}

extension SMKProtoSenderCertificateCertificate.SMKProtoSenderCertificateCertificateBuilder {
    @objc public func buildIgnoringErrors() -> SMKProtoSenderCertificateCertificate? {
        return try! self.build()
    }
}

#endif

// MARK: - SMKProtoSenderCertificate

@objc public class SMKProtoSenderCertificate: NSObject {

    // MARK: - SMKProtoSenderCertificateBuilder

    @objc public class func builder(certificate: Data, signature: Data) -> SMKProtoSenderCertificateBuilder {
        return SMKProtoSenderCertificateBuilder(certificate: certificate, signature: signature)
    }

    // asBuilder() constructs a builder that reflects the proto's contents.
    @objc public func asBuilder() -> SMKProtoSenderCertificateBuilder {
        let builder = SMKProtoSenderCertificateBuilder(certificate: certificate, signature: signature)
        return builder
    }

    @objc public class SMKProtoSenderCertificateBuilder: NSObject {

        private var proto = SMKProtos_SenderCertificate()

        @objc fileprivate override init() {}

        @objc fileprivate init(certificate: Data, signature: Data) {
            super.init()

            setCertificate(certificate)
            setSignature(signature)
        }

        @objc public func setCertificate(_ valueParam: Data) {
            proto.certificate = valueParam
        }

        @objc public func setSignature(_ valueParam: Data) {
            proto.signature = valueParam
        }

        @objc public func build() throws -> SMKProtoSenderCertificate {
            return try SMKProtoSenderCertificate.parseProto(proto)
        }

        @objc public func buildSerializedData() throws -> Data {
            return try SMKProtoSenderCertificate.parseProto(proto).serializedData()
        }
    }

    fileprivate let proto: SMKProtos_SenderCertificate

    @objc public let certificate: Data

    @objc public let signature: Data

    private init(proto: SMKProtos_SenderCertificate,
                 certificate: Data,
                 signature: Data) {
        self.proto = proto
        self.certificate = certificate
        self.signature = signature
    }

    @objc
    public func serializedData() throws -> Data {
        return try self.proto.serializedData()
    }

    @objc public class func parseData(_ serializedData: Data) throws -> SMKProtoSenderCertificate {
        let proto = try SMKProtos_SenderCertificate(serializedData: serializedData)
        return try parseProto(proto)
    }

    fileprivate class func parseProto(_ proto: SMKProtos_SenderCertificate) throws -> SMKProtoSenderCertificate {
        guard proto.hasCertificate else {
            throw SMKProtoError.invalidProtobuf(description: "\(logTag) missing required field: certificate")
        }
        let certificate = proto.certificate

        guard proto.hasSignature else {
            throw SMKProtoError.invalidProtobuf(description: "\(logTag) missing required field: signature")
        }
        let signature = proto.signature

        // MARK: - Begin Validation Logic for SMKProtoSenderCertificate -

        // MARK: - End Validation Logic for SMKProtoSenderCertificate -

        let result = SMKProtoSenderCertificate(proto: proto,
                                               certificate: certificate,
                                               signature: signature)
        return result
    }

    @objc public override var debugDescription: String {
        return "\(proto)"
    }
}

#if DEBUG

extension SMKProtoSenderCertificate {
    @objc public func serializedDataIgnoringErrors() -> Data? {
        return try! self.serializedData()
    }
}

extension SMKProtoSenderCertificate.SMKProtoSenderCertificateBuilder {
    @objc public func buildIgnoringErrors() -> SMKProtoSenderCertificate? {
        return try! self.build()
    }
}

#endif

// MARK: - SMKProtoUnidentifiedSenderMessageMessage

@objc public class SMKProtoUnidentifiedSenderMessageMessage: NSObject {

    // MARK: - SMKProtoUnidentifiedSenderMessageMessageType

    @objc public enum SMKProtoUnidentifiedSenderMessageMessageType: Int32 {
        case prekeyMessage = 1
        case message = 2
    }

    private class func SMKProtoUnidentifiedSenderMessageMessageTypeWrap(_ value: SMKProtos_UnidentifiedSenderMessage.Message.TypeEnum) -> SMKProtoUnidentifiedSenderMessageMessageType {
        switch value {
        case .prekeyMessage: return .prekeyMessage
        case .message: return .message
        }
    }

    private class func SMKProtoUnidentifiedSenderMessageMessageTypeUnwrap(_ value: SMKProtoUnidentifiedSenderMessageMessageType) -> SMKProtos_UnidentifiedSenderMessage.Message.TypeEnum {
        switch value {
        case .prekeyMessage: return .prekeyMessage
        case .message: return .message
        }
    }

    // MARK: - SMKProtoUnidentifiedSenderMessageMessageBuilder

    @objc public class func builder(senderCertificate: SMKProtoSenderCertificate, content: Data) -> SMKProtoUnidentifiedSenderMessageMessageBuilder {
        return SMKProtoUnidentifiedSenderMessageMessageBuilder(senderCertificate: senderCertificate, content: content)
    }

    // asBuilder() constructs a builder that reflects the proto's contents.
    @objc public func asBuilder() -> SMKProtoUnidentifiedSenderMessageMessageBuilder {
        let builder = SMKProtoUnidentifiedSenderMessageMessageBuilder(senderCertificate: senderCertificate, content: content)
        if let _value = type {
            builder.setType(_value)
        }
        return builder
    }

    @objc public class SMKProtoUnidentifiedSenderMessageMessageBuilder: NSObject {

        private var proto = SMKProtos_UnidentifiedSenderMessage.Message()

        @objc fileprivate override init() {}

        @objc fileprivate init(senderCertificate: SMKProtoSenderCertificate, content: Data) {
            super.init()

            setSenderCertificate(senderCertificate)
            setContent(content)
        }

        @objc public func setType(_ valueParam: SMKProtoUnidentifiedSenderMessageMessageType) {
            proto.type = SMKProtoUnidentifiedSenderMessageMessageTypeUnwrap(valueParam)
        }

        @objc public func setSenderCertificate(_ valueParam: SMKProtoSenderCertificate) {
            proto.senderCertificate = valueParam.proto
        }

        @objc public func setContent(_ valueParam: Data) {
            proto.content = valueParam
        }

        @objc public func build() throws -> SMKProtoUnidentifiedSenderMessageMessage {
            return try SMKProtoUnidentifiedSenderMessageMessage.parseProto(proto)
        }

        @objc public func buildSerializedData() throws -> Data {
            return try SMKProtoUnidentifiedSenderMessageMessage.parseProto(proto).serializedData()
        }
    }

    fileprivate let proto: SMKProtos_UnidentifiedSenderMessage.Message

    @objc public let senderCertificate: SMKProtoSenderCertificate

    @objc public let content: Data

    public var type: SMKProtoUnidentifiedSenderMessageMessageType? {
        guard proto.hasType else {
            return nil
        }
        return SMKProtoUnidentifiedSenderMessageMessage.SMKProtoUnidentifiedSenderMessageMessageTypeWrap(proto.type)
    }
    // This "unwrapped" accessor should only be used if the "has value" accessor has already been checked.
    @objc public var unwrappedType: SMKProtoUnidentifiedSenderMessageMessageType {
        if !hasType {
            // TODO: We could make this a crashing assert.
            owsFailDebug("Unsafe unwrap of missing optional: Message.type.")
        }
        return SMKProtoUnidentifiedSenderMessageMessage.SMKProtoUnidentifiedSenderMessageMessageTypeWrap(proto.type)
    }
    @objc public var hasType: Bool {
        return proto.hasType
    }

    private init(proto: SMKProtos_UnidentifiedSenderMessage.Message,
                 senderCertificate: SMKProtoSenderCertificate,
                 content: Data) {
        self.proto = proto
        self.senderCertificate = senderCertificate
        self.content = content
    }

    @objc
    public func serializedData() throws -> Data {
        return try self.proto.serializedData()
    }

    @objc public class func parseData(_ serializedData: Data) throws -> SMKProtoUnidentifiedSenderMessageMessage {
        let proto = try SMKProtos_UnidentifiedSenderMessage.Message(serializedData: serializedData)
        return try parseProto(proto)
    }

    fileprivate class func parseProto(_ proto: SMKProtos_UnidentifiedSenderMessage.Message) throws -> SMKProtoUnidentifiedSenderMessageMessage {
        guard proto.hasSenderCertificate else {
            throw SMKProtoError.invalidProtobuf(description: "\(logTag) missing required field: senderCertificate")
        }
        let senderCertificate = try SMKProtoSenderCertificate.parseProto(proto.senderCertificate)

        guard proto.hasContent else {
            throw SMKProtoError.invalidProtobuf(description: "\(logTag) missing required field: content")
        }
        let content = proto.content

        // MARK: - Begin Validation Logic for SMKProtoUnidentifiedSenderMessageMessage -

        // MARK: - End Validation Logic for SMKProtoUnidentifiedSenderMessageMessage -

        let result = SMKProtoUnidentifiedSenderMessageMessage(proto: proto,
                                                              senderCertificate: senderCertificate,
                                                              content: content)
        return result
    }

    @objc public override var debugDescription: String {
        return "\(proto)"
    }
}

#if DEBUG

extension SMKProtoUnidentifiedSenderMessageMessage {
    @objc public func serializedDataIgnoringErrors() -> Data? {
        return try! self.serializedData()
    }
}

extension SMKProtoUnidentifiedSenderMessageMessage.SMKProtoUnidentifiedSenderMessageMessageBuilder {
    @objc public func buildIgnoringErrors() -> SMKProtoUnidentifiedSenderMessageMessage? {
        return try! self.build()
    }
}

#endif

// MARK: - SMKProtoUnidentifiedSenderMessage

@objc public class SMKProtoUnidentifiedSenderMessage: NSObject {

    // MARK: - SMKProtoUnidentifiedSenderMessageBuilder

    @objc public class func builder(ephemeralPublic: Data, encryptedStatic: Data, encryptedMessage: Data) -> SMKProtoUnidentifiedSenderMessageBuilder {
        return SMKProtoUnidentifiedSenderMessageBuilder(ephemeralPublic: ephemeralPublic, encryptedStatic: encryptedStatic, encryptedMessage: encryptedMessage)
    }

    // asBuilder() constructs a builder that reflects the proto's contents.
    @objc public func asBuilder() -> SMKProtoUnidentifiedSenderMessageBuilder {
        let builder = SMKProtoUnidentifiedSenderMessageBuilder(ephemeralPublic: ephemeralPublic, encryptedStatic: encryptedStatic, encryptedMessage: encryptedMessage)
        return builder
    }

    @objc public class SMKProtoUnidentifiedSenderMessageBuilder: NSObject {

        private var proto = SMKProtos_UnidentifiedSenderMessage()

        @objc fileprivate override init() {}

        @objc fileprivate init(ephemeralPublic: Data, encryptedStatic: Data, encryptedMessage: Data) {
            super.init()

            setEphemeralPublic(ephemeralPublic)
            setEncryptedStatic(encryptedStatic)
            setEncryptedMessage(encryptedMessage)
        }

        @objc public func setEphemeralPublic(_ valueParam: Data) {
            proto.ephemeralPublic = valueParam
        }

        @objc public func setEncryptedStatic(_ valueParam: Data) {
            proto.encryptedStatic = valueParam
        }

        @objc public func setEncryptedMessage(_ valueParam: Data) {
            proto.encryptedMessage = valueParam
        }

        @objc public func build() throws -> SMKProtoUnidentifiedSenderMessage {
            return try SMKProtoUnidentifiedSenderMessage.parseProto(proto)
        }

        @objc public func buildSerializedData() throws -> Data {
            return try SMKProtoUnidentifiedSenderMessage.parseProto(proto).serializedData()
        }
    }

    fileprivate let proto: SMKProtos_UnidentifiedSenderMessage

    @objc public let ephemeralPublic: Data

    @objc public let encryptedStatic: Data

    @objc public let encryptedMessage: Data

    private init(proto: SMKProtos_UnidentifiedSenderMessage,
                 ephemeralPublic: Data,
                 encryptedStatic: Data,
                 encryptedMessage: Data) {
        self.proto = proto
        self.ephemeralPublic = ephemeralPublic
        self.encryptedStatic = encryptedStatic
        self.encryptedMessage = encryptedMessage
    }

    @objc
    public func serializedData() throws -> Data {
        return try self.proto.serializedData()
    }

    @objc public class func parseData(_ serializedData: Data) throws -> SMKProtoUnidentifiedSenderMessage {
        let proto = try SMKProtos_UnidentifiedSenderMessage(serializedData: serializedData)
        return try parseProto(proto)
    }

    fileprivate class func parseProto(_ proto: SMKProtos_UnidentifiedSenderMessage) throws -> SMKProtoUnidentifiedSenderMessage {
        guard proto.hasEphemeralPublic else {
            throw SMKProtoError.invalidProtobuf(description: "\(logTag) missing required field: ephemeralPublic")
        }
        let ephemeralPublic = proto.ephemeralPublic

        guard proto.hasEncryptedStatic else {
            throw SMKProtoError.invalidProtobuf(description: "\(logTag) missing required field: encryptedStatic")
        }
        let encryptedStatic = proto.encryptedStatic

        guard proto.hasEncryptedMessage else {
            throw SMKProtoError.invalidProtobuf(description: "\(logTag) missing required field: encryptedMessage")
        }
        let encryptedMessage = proto.encryptedMessage

        // MARK: - Begin Validation Logic for SMKProtoUnidentifiedSenderMessage -

        // MARK: - End Validation Logic for SMKProtoUnidentifiedSenderMessage -

        let result = SMKProtoUnidentifiedSenderMessage(proto: proto,
                                                       ephemeralPublic: ephemeralPublic,
                                                       encryptedStatic: encryptedStatic,
                                                       encryptedMessage: encryptedMessage)
        return result
    }

    @objc public override var debugDescription: String {
        return "\(proto)"
    }
}

#if DEBUG

extension SMKProtoUnidentifiedSenderMessage {
    @objc public func serializedDataIgnoringErrors() -> Data? {
        return try! self.serializedData()
    }
}

extension SMKProtoUnidentifiedSenderMessage.SMKProtoUnidentifiedSenderMessageBuilder {
    @objc public func buildIgnoringErrors() -> SMKProtoUnidentifiedSenderMessage? {
        return try! self.build()
    }
}

#endif
