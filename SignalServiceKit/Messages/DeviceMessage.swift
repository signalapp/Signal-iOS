//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import LibSignalClient

enum DeviceMessage {
    case sealedSender(SingleOutboundSealedSenderMessage)
    case unsealed(SingleOutboundUnsealedMessage)

    var type: SSKProtoEnvelopeType {
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

    var content: Data {
        switch self {
        case .sealedSender(let message): return message.contents
        case .unsealed(let message): return message.contents.serialize()
        }
    }
}

struct SentDeviceMessage {
    var destinationDeviceId: DeviceId
    var destinationRegistrationId: UInt32
}
