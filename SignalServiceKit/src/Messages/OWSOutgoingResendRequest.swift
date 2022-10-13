//
// Copyright 2021 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import LibSignalClient

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

    @objc
    open override func buildPlainTextData(_ thread: TSThread, transaction: SDSAnyWriteTransaction) -> Data? {
        do {
            let decryptionErrorMessage = try DecryptionErrorMessage(bytes: decryptionErrorData)
            let plaintextContent = PlaintextContent(decryptionErrorMessage)
            return Data(plaintextContent.serialize())
        } catch {
            owsFailDebug("Failed to build plaintext: \(error)")
            return nil
        }
    }
}
