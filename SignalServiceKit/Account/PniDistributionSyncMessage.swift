//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import LibSignalClient

/// Represents a message sent to linked devices during a PNI distribution event
/// informing those devices of the new PNI identity.
///
/// Note that this type is not a ``TSOutgoingMessage`` subclass, as it is not
/// sent through our message-sending machinery, and is instead part of a
/// PNI distribution request (and thereafter distributed by the service).
final class PniDistributionSyncMessage {
    let pniIdentityKeyPair: ECKeyPair
    let signedPreKey: LibSignalClient.SignedPreKeyRecord
    let pqLastResortPreKey: LibSignalClient.KyberPreKeyRecord
    let registrationId: UInt32
    let e164: E164

    init(
        pniIdentityKeyPair: ECKeyPair,
        signedPreKey: LibSignalClient.SignedPreKeyRecord,
        pqLastResortPreKey: LibSignalClient.KyberPreKeyRecord,
        registrationId: UInt32,
        e164: E164,
    ) {
        self.pniIdentityKeyPair = pniIdentityKeyPair
        self.signedPreKey = signedPreKey
        self.pqLastResortPreKey = pqLastResortPreKey
        self.registrationId = registrationId
        self.e164 = e164
    }

    /// Build a serialized message proto for this sync message.
    func buildSerializedMessageProto() throws -> Data {
        let changeNumberBuilder = SSKProtoSyncMessagePniChangeNumber.builder()
        changeNumberBuilder.setIdentityKeyPair(pniIdentityKeyPair.identityKeyPair.serialize())
        changeNumberBuilder.setSignedPreKey(signedPreKey.serialize())
        changeNumberBuilder.setLastResortKyberPreKey(pqLastResortPreKey.serialize())
        changeNumberBuilder.setRegistrationID(registrationId)
        changeNumberBuilder.setNewE164(e164.stringValue)

        let syncMessageBuilder = SSKProtoSyncMessage.builder()
        syncMessageBuilder.setPniChangeNumber(changeNumberBuilder.buildInfallibly())

        let syncMessageProto = try OWSOutgoingSyncMessage.buildSyncMessageProto(for: syncMessageBuilder)

        let contentProto = SSKProtoContent.builder()
        contentProto.setSyncMessage(syncMessageProto)

        return try contentProto.buildSerializedData()
    }
}
