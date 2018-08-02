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

        @objc public func setPublicKey(_ valueParam: Data) {
            proto.publicKey = valueParam
        }

        @objc public func setBody(_ valueParam: Data) {
            proto.body = valueParam
        }

        @objc public func build() throws -> ProvisioningProtoProvisionEnvelope {
            let wrapper = try ProvisioningProtoProvisionEnvelope.parseProto(proto)
            return wrapper
        }
    }

    fileprivate let proto: ProvisioningProtos_ProvisionEnvelope

    @objc public var publicKey: Data? {
        guard proto.hasPublicKey else {
            return nil
        }
        return proto.publicKey
    }
    @objc public var hasPublicKey: Bool {
        return proto.hasPublicKey
    }

    @objc public var body: Data? {
        guard proto.hasBody else {
            return nil
        }
        return proto.body
    }
    @objc public var hasBody: Bool {
        return proto.hasBody
    }

    private init(proto: ProvisioningProtos_ProvisionEnvelope) {
        self.proto = proto
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
        // MARK: - Begin Validation Logic for ProvisioningProtoProvisionEnvelope -

        // MARK: - End Validation Logic for ProvisioningProtoProvisionEnvelope -

        let result = ProvisioningProtoProvisionEnvelope(proto: proto)
        return result
    }
}

// MARK: - ProvisioningProtoProvisionMessage

@objc public class ProvisioningProtoProvisionMessage: NSObject {

    // MARK: - ProvisioningProtoProvisionMessageBuilder

    @objc public class ProvisioningProtoProvisionMessageBuilder: NSObject {

        private var proto = ProvisioningProtos_ProvisionMessage()

        @objc public override init() {}

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
            let wrapper = try ProvisioningProtoProvisionMessage.parseProto(proto)
            return wrapper
        }
    }

    fileprivate let proto: ProvisioningProtos_ProvisionMessage

    @objc public var identityKeyPublic: Data? {
        guard proto.hasIdentityKeyPublic else {
            return nil
        }
        return proto.identityKeyPublic
    }
    @objc public var hasIdentityKeyPublic: Bool {
        return proto.hasIdentityKeyPublic
    }

    @objc public var identityKeyPrivate: Data? {
        guard proto.hasIdentityKeyPrivate else {
            return nil
        }
        return proto.identityKeyPrivate
    }
    @objc public var hasIdentityKeyPrivate: Bool {
        return proto.hasIdentityKeyPrivate
    }

    @objc public var number: String? {
        guard proto.hasNumber else {
            return nil
        }
        return proto.number
    }
    @objc public var hasNumber: Bool {
        return proto.hasNumber
    }

    @objc public var provisioningCode: String? {
        guard proto.hasProvisioningCode else {
            return nil
        }
        return proto.provisioningCode
    }
    @objc public var hasProvisioningCode: Bool {
        return proto.hasProvisioningCode
    }

    @objc public var userAgent: String? {
        guard proto.hasUserAgent else {
            return nil
        }
        return proto.userAgent
    }
    @objc public var hasUserAgent: Bool {
        return proto.hasUserAgent
    }

    @objc public var profileKey: Data? {
        guard proto.hasProfileKey else {
            return nil
        }
        return proto.profileKey
    }
    @objc public var hasProfileKey: Bool {
        return proto.hasProfileKey
    }

    @objc public var readReceipts: Bool {
        return proto.readReceipts
    }
    @objc public var hasReadReceipts: Bool {
        return proto.hasReadReceipts
    }

    private init(proto: ProvisioningProtos_ProvisionMessage) {
        self.proto = proto
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
        // MARK: - Begin Validation Logic for ProvisioningProtoProvisionMessage -

        // MARK: - End Validation Logic for ProvisioningProtoProvisionMessage -

        let result = ProvisioningProtoProvisionMessage(proto: proto)
        return result
    }
}
