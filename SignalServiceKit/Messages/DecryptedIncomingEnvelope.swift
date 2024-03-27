//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import LibSignalClient
import SignalCoreKit

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
@objc
class DecryptedIncomingEnvelope: NSObject {
    @objc
    let envelope: SSKProtoEnvelope

    @objc
    let timestamp: UInt64

    @objc
    let serverTimestamp: UInt64

    let sourceAci: Aci

    @objc
    let sourceDeviceId: UInt32

    let localIdentity: OWSIdentity
    let wasReceivedByUD: Bool
    let plaintextData: Data
    let content: SSKProtoContent?

    @objc
    var sourceAciObjC: AciObjC { AciObjC(sourceAci) }

    init(
        validatedEnvelope: ValidatedIncomingEnvelope,
        updatedEnvelope: SSKProtoEnvelope,
        sourceAci: Aci,
        sourceDeviceId: UInt32,
        wasReceivedByUD: Bool,
        plaintextData: Data
    ) {
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
    }
}
