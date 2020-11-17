//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

import Foundation

// See:
// https://github.com/signalapp/libsignal-metadata-java/blob/cac0dde9de416a192e64a8940503982820870090/java/src/main/java/org/signal/libsignal/metadata/certificate/ServerCertificate.java
@objc public class SMKServerCertificate: NSObject {

    @objc public let keyId: UInt32
    @objc public let key: ECPublicKey
    @objc public let signatureData: Data

    public init(keyId: UInt32,
                key: ECPublicKey,
                signatureData: Data) {
        self.keyId = keyId
        self.key = key
        self.signatureData = signatureData
    }

    @objc public class func parse(data: Data) throws -> SMKServerCertificate {
        let proto = try SMKProtoServerCertificate.parseData(data)
        return try parse(proto: proto)
    }

    @objc public class func parse(proto: SMKProtoServerCertificate) throws -> SMKServerCertificate {
        let signatureData = proto.signature
        let certificateData = proto.certificate
        let certificateProto = try SMKProtoServerCertificateCertificate.parseData(certificateData)
        let keyId = certificateProto.id
        let keyData = certificateProto.key
        let key = try ECPublicKey(serializedKeyData: keyData)
        return SMKServerCertificate(keyId: keyId, key: key, signatureData: signatureData)
    }

    @objc public func toProto() throws -> SMKProtoServerCertificate {
        let certificateBuilder = SMKProtoServerCertificateCertificate.builder(id: keyId, key: key.serialized)

        let builder =
            SMKProtoServerCertificate.builder(certificate: try certificateBuilder.buildSerializedData(),
                                              signature: signatureData)
        return try builder.build()
    }

    @objc public func serialized() throws -> Data {
        return try toProto().serializedData()
    }

    open override func isEqual(_ other: Any?) -> Bool {
        if let other = other as? SMKServerCertificate {
            return (keyId == other.keyId &&
                key.isEqual(other.key) &&
                (signatureData == other.signatureData))
        } else {
            return false
        }
    }

    public override var hash: Int {
        return keyId.hashValue ^ key.hashValue ^ signatureData.hashValue
    }
}
