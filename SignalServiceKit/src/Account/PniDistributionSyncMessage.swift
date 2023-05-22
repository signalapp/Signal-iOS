//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import Curve25519Kit

/// Represents a message sent to linked devices during a PNI distribution event
/// informing those devices of the new PNI identity.
///
/// Note that this type is not a ``TSOutgoingMessage`` subclass, as it is not
/// sent through our message-sending machinery, and is instead part of a
/// PNI distribution request (and thereafter distributed by the service).
final class PniDistributionSyncMessage {
    private let pniIdentityKeyPair: ECKeyPair
    private let signedPreKey: SignedPreKeyRecord
    private let registrationId: UInt32

    init(
        pniIdentityKeyPair: ECKeyPair,
        signedPreKey: SignedPreKeyRecord,
        registrationId: UInt32
    ) {
        self.pniIdentityKeyPair = pniIdentityKeyPair
        self.signedPreKey = signedPreKey
        self.registrationId = registrationId
    }

    /// Build a serialized message proto for this sync message.
    func buildSerializedMessageProto() throws -> Data {
        let changeNumberBuilder = SSKProtoSyncMessagePniChangeNumber.builder()
        changeNumberBuilder.setIdentityKeyPair(Data(pniIdentityKeyPair.identityKeyPair.serialize()))
        changeNumberBuilder.setSignedPreKey(Data(try signedPreKey.asLSCRecord().serialize()))
        changeNumberBuilder.setRegistrationID(registrationId)

        let syncMessageBuilder = SSKProtoSyncMessage.builder()
        syncMessageBuilder.setPniChangeNumber(changeNumberBuilder.buildInfallibly())

        let syncMessageProto = try OWSOutgoingSyncMessage.buildSyncMessageProto(for: syncMessageBuilder)

        let contentProto = SSKProtoContent.builder()
        contentProto.setSyncMessage(syncMessageProto)

        return try contentProto.buildSerializedData()
    }
}
