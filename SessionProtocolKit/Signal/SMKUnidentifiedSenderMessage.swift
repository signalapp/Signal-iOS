//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

import Foundation

// https://github.com/signalapp/libsignal-metadata-java/blob/master/java/src/main/java/org/signal/libsignal/metadata/protocol/UnidentifiedSenderMessage.java
@objc public class SMKUnidentifiedSenderMessage: NSObject {

    @objc public static let kSMKMessageCipherTextVersion: UInt = 1

    public let cipherTextVersion: UInt
    public let ephemeralKey: ECPublicKey
    public let encryptedStatic: Data
    public let encryptedMessage: Data

    public init(cipherTextVersion: UInt,
                ephemeralKey: ECPublicKey,
                encryptedStatic: Data,
                encryptedMessage: Data) {
        self.cipherTextVersion = cipherTextVersion
        self.ephemeralKey = ephemeralKey
        self.encryptedStatic = encryptedStatic
        self.encryptedMessage = encryptedMessage
    }

    public init(ephemeralKey: ECPublicKey,
                encryptedStatic: Data,
                encryptedMessage: Data) {
        self.cipherTextVersion = SMKUnidentifiedSenderMessage.kSMKMessageCipherTextVersion
        self.ephemeralKey = ephemeralKey
        self.encryptedStatic = encryptedStatic
        self.encryptedMessage = encryptedMessage
    }

    @objc public class func parse(dataAndPrefix: Data) throws -> SMKUnidentifiedSenderMessage {
        // public UnidentifiedSenderMessage(byte[] serialized)
        // throws InvalidMetadataMessageException, InvalidMetadataVersionException

        let parser = OWSDataParser(data: dataAndPrefix)

        // this.version = ByteUtil.highBitsToInt(serialized[0]);
        let versionByte = try parser.nextByte(name: "version byte")
        let cipherTextVersion = UInt(SerializationUtilities.highBitsToInt(fromByte: versionByte))

        // if (version > CIPHERTEXT_VERSION) {
        // throw new InvalidMetadataVersionException("Unknown version: " + this.version);
        // }
        guard cipherTextVersion <= SMKUnidentifiedSenderMessage.kSMKMessageCipherTextVersion else {
            throw SMKError.assertionError(description: "\(logTag) unknown cipher text version: \(cipherTextVersion)")
        }

        // SignalProtos.UnidentifiedSenderMessage unidentifiedSenderMessage =
        // SignalProtos.UnidentifiedSenderMessage.parseFrom(ByteString.copyFrom(serialized, 1, serialized.length - 1));
        let protoData = try parser.remainder(name: "proto data")
        let proto = try SMKProtoUnidentifiedSenderMessage.parseData(protoData)

        // if (!unidentifiedSenderMessage.hasEphemeralPublic() ||
        // !unidentifiedSenderMessage.hasEncryptedStatic() ||
        // !unidentifiedSenderMessage.hasEncryptedMessage())
        // {
        // throw new InvalidMetadataMessageException("Missing fields");
        // }
        // NOTE: These fields are required in the proto schema.

        // this.ephemeral        = Curve.decodePoint(unidentifiedSenderMessage.getEphemeralPublic().toByteArray(), 0);
        let ephemeralKeyData = proto.ephemeralPublic
        let ephemeralKey = try ECPublicKey(serializedKeyData: ephemeralKeyData)

        // this.encryptedStatic  = unidentifiedSenderMessage.getEncryptedStatic().toByteArray();
        let encryptedStatic = proto.encryptedStatic

        // this.encryptedMessage = unidentifiedSenderMessage.getEncryptedMessage().toByteArray();
        let encryptedMessage = proto.encryptedMessage

        return SMKUnidentifiedSenderMessage(cipherTextVersion: cipherTextVersion, ephemeralKey: ephemeralKey, encryptedStatic: encryptedStatic, encryptedMessage: encryptedMessage)
    }

    @objc public func toProto() throws -> SMKProtoUnidentifiedSenderMessage {
        let builder = SMKProtoUnidentifiedSenderMessage.builder(ephemeralPublic: ephemeralKey.serialized,
                                                                encryptedStatic: encryptedStatic,
                                                                encryptedMessage: encryptedMessage)
        return try builder.build()
    }

    @objc public func serialized() throws -> Data {
        let versionByte: UInt8 = UInt8((self.cipherTextVersion << 4 | self.cipherTextVersion) & 0xFF)
        let versionBytes = [versionByte]
        let versionData = Data(bytes: versionBytes)
        let messageData = try toProto().serializedData()

        return NSData.join([versionData, messageData])
    }
}
