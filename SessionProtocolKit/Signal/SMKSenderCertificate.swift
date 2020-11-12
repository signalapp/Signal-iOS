//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

import Foundation

// See:
// https://github.com/signalapp/libsignal-metadata-java/blob/cac0dde9de416a192e64a8940503982820870090/java/src/main/java/org/signal/libsignal/metadata/certificate/SenderCertificate.java
@objc public class SMKSenderCertificate: NSObject {

    @objc public let senderDeviceId: UInt32
    @objc public let senderRecipientId: String

    @objc public init(senderDeviceId: UInt32, senderRecipientId: String) {
        self.senderDeviceId = senderDeviceId
        self.senderRecipientId = senderRecipientId
    }

    @objc public class func parse(data: Data) throws -> SMKSenderCertificate {
        let proto = try SMKProtoSenderCertificate.parseData(data)
        return try parse(proto: proto)
    }

    @objc public class func parse(proto: SMKProtoSenderCertificate) throws -> SMKSenderCertificate {

        let sender = proto.sender
        let senderDevice = proto.senderDevice

        return SMKSenderCertificate(senderDeviceId: senderDevice, senderRecipientId: sender)
    }

    @objc public func toProto() throws -> SMKProtoSenderCertificate {
        let builder =
            SMKProtoSenderCertificate.builder(sender: senderRecipientId, senderDevice: senderDeviceId)
        return try builder.build()
    }

    @objc public func serialized() throws -> Data {
        return try toProto().serializedData()
    }

    open override func isEqual(_ other: Any?) -> Bool {
        if let other = other as? SMKSenderCertificate {
            return (senderDeviceId == other.senderDeviceId && senderRecipientId == other.senderRecipientId)
        } else {
            return false
        }
    }

    public override var hash: Int {
        return senderDeviceId.hashValue ^ senderRecipientId.hashValue
    }
}
