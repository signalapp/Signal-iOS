//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

import Foundation

@objc public enum SMKMessageType: Int {
    case whisper
    case prekey
    case fallback
}

// See:
// https://github.com/signalapp/libsignal-metadata-java/blob/0cbbbf23eaf9f46fdf2d9463f3dfab2fb3271292/java/src/main/java/org/signal/libsignal/metadata/protocol/UnidentifiedSenderMessageContent.java
@objc public class SMKUnidentifiedSenderMessageContent: NSObject {

    @objc public let messageType: SMKMessageType
    @objc public let senderCertificate: SMKSenderCertificate
    @objc public let contentData: Data

    @objc public init(messageType: SMKMessageType,
                      senderCertificate: SMKSenderCertificate,
                      contentData: Data) {
        self.messageType = messageType
        self.senderCertificate = senderCertificate
        self.contentData = contentData
    }

    @objc public class func parse(data: Data) throws -> SMKUnidentifiedSenderMessageContent {

        let proto = try SMKProtoUnidentifiedSenderMessageMessage.parseData(data)

        // TODO: Should we have a default case in our switches? Probably.
        var messageType: SMKMessageType
        switch (proto.type) {
        case .prekeyMessage:
            messageType = .prekey
        case .message:
            messageType = .whisper
        case .fallbackMessage:
            messageType = .fallback
        }

        let contentData = proto.content
        let senderCertificateProto = proto.senderCertificate
        let senderCertificate = try SMKSenderCertificate.parse(proto: senderCertificateProto)

        return SMKUnidentifiedSenderMessageContent(messageType: messageType, senderCertificate: senderCertificate, contentData: contentData)
    }

    @objc public func toProto() throws -> SMKProtoUnidentifiedSenderMessageMessage {
        let builderType: SMKProtoUnidentifiedSenderMessageMessage.SMKProtoUnidentifiedSenderMessageMessageType
        switch messageType {
        case .whisper:
            builderType = .message
        case .prekey:
            builderType = .prekeyMessage
        case .fallback:
            builderType = .fallbackMessage
        }

        let builder = SMKProtoUnidentifiedSenderMessageMessage.builder(type: builderType,
                                                                       senderCertificate: try senderCertificate.toProto(),
                                                                       content: contentData)
        return try builder.build()
    }

    @objc public func serialized() throws -> Data {
        return try toProto().serializedData()
    }
}
