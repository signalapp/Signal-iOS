//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

import Foundation

// WARNING: This code is generated. Only edit within the markers.

public enum ProvisioningProtoError: Error {
    case invalidProtobuf(description: String)
}

// MARK: - ProvisioningProtoProvisionEnvelope

@objc public class ProvisioningProtoProvisionEnvelope: NSObject {

    // MARK: - ProvisioningProtoProvisionEnvelopeBuilder

    @objc public class ProvisioningProtoProvisionEnvelopeBuilder: NSObject {

        private var proto = ProvisioningProtos_ProvisionEnvelope()

        @objc public override init() {}

        // Initializer for required fields
        @objc public init(publicKey: Data, body: Data) {
            super.init()

            setPublicKey(publicKey)
            setBody(body)
        }

        @objc public func setPublicKey(_ valueParam: Data) {
            proto.publicKey = valueParam
        }

        @objc public func setBody(_ valueParam: Data) {
            proto.body = valueParam
        }

        @objc public func build() throws -> ProvisioningProtoProvisionEnvelope {
            return try ProvisioningProtoProvisionEnvelope.parseProto(proto)
        }

        @objc public func buildSerializedData() throws -> Data {
            return try ProvisioningProtoProvisionEnvelope.parseProto(proto).serializedData()
        }
    }

    fileprivate let proto: ProvisioningProtos_ProvisionEnvelope

    @objc public let publicKey: Data

    @objc public let body: Data

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

    @objc public class func parseData(_ serializedData: Data) throws -> ProvisioningProtoProvisionEnvelope {
        let proto = try ProvisioningProtos_ProvisionEnvelope(serializedData: serializedData)
        return try parseProto(proto)
    }

    fileprivate class func parseProto(_ proto: ProvisioningProtos_ProvisionEnvelope) throws -> ProvisioningProtoProvisionEnvelope {
        guard proto.hasPublicKey else {
            throw ProvisioningProtoError.invalidProtobuf(description: "\(logTag) missing required field: publicKey")
        }
        let publicKey = proto.publicKey

        guard proto.hasBody else {
            throw ProvisioningProtoError.invalidProtobuf(description: "\(logTag) missing required field: body")
        }
        let body = proto.body

        // MARK: - Begin Validation Logic for ProvisioningProtoProvisionEnvelope -

        // MARK: - End Validation Logic for ProvisioningProtoProvisionEnvelope -

        let result = ProvisioningProtoProvisionEnvelope(proto: proto,
                                                        publicKey: publicKey,
                                                        body: body)
        return result
    }
}

#if DEBUG

extension ProvisioningProtoProvisionEnvelope {
    @objc public func serializedDataIgnoringErrors() -> Data? {
        return try! self.serializedData()
    }
}

extension ProvisioningProtoProvisionEnvelope.ProvisioningProtoProvisionEnvelopeBuilder {
    @objc public func buildIgnoringErrors() -> ProvisioningProtoProvisionEnvelope? {
        return try! self.build()
    }
}

#endif

// MARK: - ProvisioningProtoProvisionMessage

@objc public class ProvisioningProtoProvisionMessage: NSObject {

    // MARK: - ProvisioningProtoProvisionMessageBuilder

    @objc public class ProvisioningProtoProvisionMessageBuilder: NSObject {

        private var proto = ProvisioningProtos_ProvisionMessage()

        @objc public override init() {}

        // Initializer for required fields
        @objc public init(identityKeyPublic: Data, identityKeyPrivate: Data, number: String, provisioningCode: String, userAgent: String, profileKey: Data, readReceipts: Bool) {
            super.init()

            setIdentityKeyPublic(identityKeyPublic)
            setIdentityKeyPrivate(identityKeyPrivate)
            setNumber(number)
            setProvisioningCode(provisioningCode)
            setUserAgent(userAgent)
            setProfileKey(profileKey)
            setReadReceipts(readReceipts)
        }

        @objc public func setIdentityKeyPublic(_ valueParam: Data) {
            proto.identityKeyPublic = valueParam
        }

        @objc public func setIdentityKeyPrivate(_ valueParam: Data) {
            proto.identityKeyPrivate = valueParam
        }

        @objc public func setNumber(_ valueParam: String) {
            proto.number = valueParam
        }

        @objc public func setProvisioningCode(_ valueParam: String) {
            proto.provisioningCode = valueParam
        }

        @objc public func setUserAgent(_ valueParam: String) {
            proto.userAgent = valueParam
        }

        @objc public func setProfileKey(_ valueParam: Data) {
            proto.profileKey = valueParam
        }

        @objc public func setReadReceipts(_ valueParam: Bool) {
            proto.readReceipts = valueParam
        }

        @objc public func build() throws -> ProvisioningProtoProvisionMessage {
            return try ProvisioningProtoProvisionMessage.parseProto(proto)
        }

        @objc public func buildSerializedData() throws -> Data {
            return try ProvisioningProtoProvisionMessage.parseProto(proto).serializedData()
        }
    }

    fileprivate let proto: ProvisioningProtos_ProvisionMessage

    @objc public let identityKeyPublic: Data

    @objc public let identityKeyPrivate: Data

    @objc public let number: String

    @objc public let provisioningCode: String

    @objc public let userAgent: String

    @objc public let profileKey: Data

    @objc public let readReceipts: Bool

    private init(proto: ProvisioningProtos_ProvisionMessage,
                 identityKeyPublic: Data,
                 identityKeyPrivate: Data,
                 number: String,
                 provisioningCode: String,
                 userAgent: String,
                 profileKey: Data,
                 readReceipts: Bool) {
        self.proto = proto
        self.identityKeyPublic = identityKeyPublic
        self.identityKeyPrivate = identityKeyPrivate
        self.number = number
        self.provisioningCode = provisioningCode
        self.userAgent = userAgent
        self.profileKey = profileKey
        self.readReceipts = readReceipts
    }

    @objc
    public func serializedData() throws -> Data {
        return try self.proto.serializedData()
    }

    @objc public class func parseData(_ serializedData: Data) throws -> ProvisioningProtoProvisionMessage {
        let proto = try ProvisioningProtos_ProvisionMessage(serializedData: serializedData)
        return try parseProto(proto)
    }

    fileprivate class func parseProto(_ proto: ProvisioningProtos_ProvisionMessage) throws -> ProvisioningProtoProvisionMessage {
        guard proto.hasIdentityKeyPublic else {
            throw ProvisioningProtoError.invalidProtobuf(description: "\(logTag) missing required field: identityKeyPublic")
        }
        let identityKeyPublic = proto.identityKeyPublic

        guard proto.hasIdentityKeyPrivate else {
            throw ProvisioningProtoError.invalidProtobuf(description: "\(logTag) missing required field: identityKeyPrivate")
        }
        let identityKeyPrivate = proto.identityKeyPrivate

        guard proto.hasNumber else {
            throw ProvisioningProtoError.invalidProtobuf(description: "\(logTag) missing required field: number")
        }
        let number = proto.number

        guard proto.hasProvisioningCode else {
            throw ProvisioningProtoError.invalidProtobuf(description: "\(logTag) missing required field: provisioningCode")
        }
        let provisioningCode = proto.provisioningCode

        guard proto.hasUserAgent else {
            throw ProvisioningProtoError.invalidProtobuf(description: "\(logTag) missing required field: userAgent")
        }
        let userAgent = proto.userAgent

        guard proto.hasProfileKey else {
            throw ProvisioningProtoError.invalidProtobuf(description: "\(logTag) missing required field: profileKey")
        }
        let profileKey = proto.profileKey

        guard proto.hasReadReceipts else {
            throw ProvisioningProtoError.invalidProtobuf(description: "\(logTag) missing required field: readReceipts")
        }
        let readReceipts = proto.readReceipts

        // MARK: - Begin Validation Logic for ProvisioningProtoProvisionMessage -

        // MARK: - End Validation Logic for ProvisioningProtoProvisionMessage -

        let result = ProvisioningProtoProvisionMessage(proto: proto,
                                                       identityKeyPublic: identityKeyPublic,
                                                       identityKeyPrivate: identityKeyPrivate,
                                                       number: number,
                                                       provisioningCode: provisioningCode,
                                                       userAgent: userAgent,
                                                       profileKey: profileKey,
                                                       readReceipts: readReceipts)
        return result
    }
}

#if DEBUG

extension ProvisioningProtoProvisionMessage {
    @objc public func serializedDataIgnoringErrors() -> Data? {
        return try! self.serializedData()
    }
}

extension ProvisioningProtoProvisionMessage.ProvisioningProtoProvisionMessageBuilder {
    @objc public func buildIgnoringErrors() -> ProvisioningProtoProvisionMessage? {
        return try! self.build()
    }
}

#endif
