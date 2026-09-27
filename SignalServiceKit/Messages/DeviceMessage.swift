//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import LibSignalClient

enum DeviceMessage: Encodable {
    case sealedSender(SingleOutboundSealedSenderMessage)
    case unsealed(SingleOutboundUnsealedMessage)

    private var type: SSKProtoEnvelopeType {
        switch self {
        case .sealedSender:
            return .unidentifiedSender
        case .unsealed(let message):
            switch message.contents.messageType {
            case .whisper:
                return .ciphertext
            case .preKey:
                return .prekeyBundle
            case .plaintext:
                return .plaintextContent
            default:
                return .unknown
            }
        }
    }

    var deviceId: DeviceId {
        switch self {
        case .sealedSender(let message): return message.deviceId
        case .unsealed(let message): return message.deviceId
        }
    }

    var registrationId: UInt32 {
        switch self {
        case .sealedSender(let message): return message.registrationId
        case .unsealed(let message): return message.registrationId
        }
    }

    private var content: Data {
        switch self {
        case .sealedSender(let message): return message.contents
        case .unsealed(let message): return message.contents.serialize()
        }
    }

    private enum CodingKeys: String, CodingKey {
        case type
        case destinationDeviceId
        case destinationRegistrationId
        case content
    }

    /// See <https://github.com/signalapp/Signal-Server/blob/ab26a65/service/src/main/java/org/whispersystems/textsecuregcm/entities/IncomingMessage.java>.
    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(self.type.rawValue, forKey: .type)
        try container.encode(self.deviceId, forKey: .destinationDeviceId)
        try container.encode(self.registrationId, forKey: .destinationRegistrationId)
        try container.encode(self.content.base64EncodedString(), forKey: .content)
    }
}

struct SentDeviceMessage {
    var destinationDeviceId: DeviceId
    var destinationRegistrationId: UInt32
}
