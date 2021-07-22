//
//  Copyright (c) 2021 Open Whisper Systems. All rights reserved.
//

import SignalClient

extension OWSOutgoingResendRequest {

    @objc
    func buildDecryptionError(from originalMessageBytes: Data,
                              type cipherType: UInt8,
                              originalMessageTimestamp: UInt64,
                              senderDeviceId: UInt32) -> Data? {
        do {
            let cipherType = CiphertextMessage.MessageType(rawValue: cipherType)
            guard [.whisper, .senderKey, .preKey, .plaintext].contains(cipherType) else {
                owsFailDebug("Invalid message type")
                return nil
            }
            let error = try DecryptionErrorMessage(
                originalMessageBytes: originalMessageBytes,
                type: cipherType,
                timestamp: originalMessageTimestamp,
                originalSenderDeviceId: senderDeviceId)
            return Data(error.serialize())

        } catch {
            owsFailDebug("Failed to construct message \(error)")
            return nil
        }
    }
}
