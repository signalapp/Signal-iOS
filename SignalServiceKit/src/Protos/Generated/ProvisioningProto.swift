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

    @objc public let publicKey: Data?
    @objc public let body: Data?

    @objc public init(publicKey: Data?,
                      body: Data?) {
        self.publicKey = publicKey
        self.body = body
    }

    @objc
    public func serializedData() throws -> Data {
        return try self.asProtobuf.serializedData()
    }

    @objc public class func parseData(_ serializedData: Data) throws -> ProvisioningProtoProvisionEnvelope {
        let proto = try ProvisioningProtos_ProvisionEnvelope(serializedData: serializedData)
        return try parseProto(proto)
    }

    fileprivate class func parseProto(_ proto: ProvisioningProtos_ProvisionEnvelope) throws -> ProvisioningProtoProvisionEnvelope {
        var publicKey: Data? = nil
        if proto.hasPublicKey {
            publicKey = proto.publicKey
        }

        var body: Data? = nil
        if proto.hasBody {
            body = proto.body
        }

        // MARK: - Begin Validation Logic for ProvisioningProtoProvisionEnvelope -

        // MARK: - End Validation Logic for ProvisioningProtoProvisionEnvelope -

        let result = ProvisioningProtoProvisionEnvelope(publicKey: publicKey,
                                                        body: body)
        return result
    }

    fileprivate var asProtobuf: ProvisioningProtos_ProvisionEnvelope {
        let proto = ProvisioningProtos_ProvisionEnvelope.with { (builder) in
            if let publicKey = self.publicKey {
                builder.publicKey = publicKey
            }

            if let body = self.body {
                builder.body = body
            }
        }

        return proto
    }
}

// MARK: - ProvisioningProtoProvisionMessage

@objc public class ProvisioningProtoProvisionMessage: NSObject {

    @objc public let identityKeyPublic: Data?
    @objc public let identityKeyPrivate: Data?
    @objc public let number: String?
    @objc public let provisioningCode: String?
    @objc public let userAgent: String?
    @objc public let profileKey: Data?
    @objc public let readReceipts: Bool

    @objc public init(identityKeyPublic: Data?,
                      identityKeyPrivate: Data?,
                      number: String?,
                      provisioningCode: String?,
                      userAgent: String?,
                      profileKey: Data?,
                      readReceipts: Bool) {
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
        return try self.asProtobuf.serializedData()
    }

    @objc public class func parseData(_ serializedData: Data) throws -> ProvisioningProtoProvisionMessage {
        let proto = try ProvisioningProtos_ProvisionMessage(serializedData: serializedData)
        return try parseProto(proto)
    }

    fileprivate class func parseProto(_ proto: ProvisioningProtos_ProvisionMessage) throws -> ProvisioningProtoProvisionMessage {
        var identityKeyPublic: Data? = nil
        if proto.hasIdentityKeyPublic {
            identityKeyPublic = proto.identityKeyPublic
        }

        var identityKeyPrivate: Data? = nil
        if proto.hasIdentityKeyPrivate {
            identityKeyPrivate = proto.identityKeyPrivate
        }

        var number: String? = nil
        if proto.hasNumber {
            number = proto.number
        }

        var provisioningCode: String? = nil
        if proto.hasProvisioningCode {
            provisioningCode = proto.provisioningCode
        }

        var userAgent: String? = nil
        if proto.hasUserAgent {
            userAgent = proto.userAgent
        }

        var profileKey: Data? = nil
        if proto.hasProfileKey {
            profileKey = proto.profileKey
        }

        var readReceipts: Bool = false
        if proto.hasReadReceipts {
            readReceipts = proto.readReceipts
        }

        // MARK: - Begin Validation Logic for ProvisioningProtoProvisionMessage -

        // MARK: - End Validation Logic for ProvisioningProtoProvisionMessage -

        let result = ProvisioningProtoProvisionMessage(identityKeyPublic: identityKeyPublic,
                                                       identityKeyPrivate: identityKeyPrivate,
                                                       number: number,
                                                       provisioningCode: provisioningCode,
                                                       userAgent: userAgent,
                                                       profileKey: profileKey,
                                                       readReceipts: readReceipts)
        return result
    }

    fileprivate var asProtobuf: ProvisioningProtos_ProvisionMessage {
        let proto = ProvisioningProtos_ProvisionMessage.with { (builder) in
            if let identityKeyPublic = self.identityKeyPublic {
                builder.identityKeyPublic = identityKeyPublic
            }

            if let identityKeyPrivate = self.identityKeyPrivate {
                builder.identityKeyPrivate = identityKeyPrivate
            }

            if let number = self.number {
                builder.number = number
            }

            if let provisioningCode = self.provisioningCode {
                builder.provisioningCode = provisioningCode
            }

            if let userAgent = self.userAgent {
                builder.userAgent = userAgent
            }

            if let profileKey = self.profileKey {
                builder.profileKey = profileKey
            }

            builder.readReceipts = self.readReceipts
        }

        return proto
    }
}
