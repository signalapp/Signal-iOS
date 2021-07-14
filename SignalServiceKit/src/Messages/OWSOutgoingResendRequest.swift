//
//  Copyright (c) 2021 Open Whisper Systems. All rights reserved.
//

import SignalClient

extension OWSOutgoingResendRequest {

    @objc
    func buildDecryptionError() -> Data? {
        do {
            let cipherType = CiphertextMessage.MessageType(rawValue: UInt8(self.cipherType))
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
