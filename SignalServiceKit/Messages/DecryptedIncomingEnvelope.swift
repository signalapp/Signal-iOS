//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import LibSignalClient

/// Represents an envelope that's already been decrypted.
///
/// This might be a message from one of our linked devices, or it might be a
/// message from another user.
///
/// Identified and unidentified envelopes take different paths to produce
/// this object, but they both produce this type so that most downstream
/// logic doesn't need to care about the source of a message.
///
/// For identified envelopes, `sourceAci` is taken directly from the
/// `ValidatedIncomingEnvelope`, and then we decrypt the envelope payload to
/// populate `plaintextData`.
///
/// For unidentified envelopes, we first decrypt the envelope payload which
/// gives us the `sourceAci` and a nested payload. We then decrypt that
/// nested payload to populate `plaintextData`.
class DecryptedIncomingEnvelope {
    let envelope: SSKProtoEnvelope
    let timestamp: UInt64
    let serverTimestamp: UInt64
    let sourceAci: Aci
    let sourceDeviceId: DeviceId
    let localIdentity: OWSIdentity
    let wasReceivedByUD: Bool
    let plaintextData: Data
    let content: SSKProtoContent?

    init(
        validatedEnvelope: ValidatedIncomingEnvelope,
        updatedEnvelope: SSKProtoEnvelope,
        sourceAci: Aci,
        sourceDeviceId: DeviceId,
        wasReceivedByUD: Bool,
        plaintextData: Data,
        isPlaintextCipher: Bool?,
    ) throws {
        self.envelope = updatedEnvelope
        self.timestamp = validatedEnvelope.timestamp
        self.serverTimestamp = validatedEnvelope.serverTimestamp
        self.sourceAci = sourceAci
        self.sourceDeviceId = sourceDeviceId
        self.localIdentity = validatedEnvelope.localIdentity
        self.wasReceivedByUD = wasReceivedByUD
        self.plaintextData = plaintextData
        self.content = {
            do {
                return try SSKProtoContent(serializedData: plaintextData)
            } catch {
                owsFailDebug("Failed to deserialize content proto: \(error)")
                return nil
            }
        }()

        let hasDecryptionError = (
            content?.decryptionErrorMessage != nil,
        )
        let hasAnythingElse = (
            content?.dataMessage != nil
                || content?.syncMessage != nil
                || content?.callMessage != nil
                || content?.nullMessage != nil
                || content?.receiptMessage != nil
                || content?.typingMessage != nil
                || content?.storyMessage != nil
                || content?.pniSignatureMessage != nil
                || content?.senderKeyDistributionMessage != nil
                || content?.unknownFields != nil,
        )
        if hasDecryptionError, hasAnythingElse {
            throw OWSGenericError("Message content must contain one type.")
        }
        if let isPlaintextCipher, isPlaintextCipher != hasDecryptionError {
            throw OWSGenericError("Plaintext ciphers must have decryption errors.")
        }

        // This prevents replay attacks by the service.
        if let dataMessage = content?.dataMessage, dataMessage.timestamp != timestamp {
            throw OWSGenericError("Data messages must have matching timestamps \(sourceAci)")
        }
        if let typingMessage = content?.typingMessage, typingMessage.timestamp != timestamp {
            throw OWSGenericError("Typing messages must have matching timestamps \(sourceAci)")
        }
    }
}
