//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import Curve25519Kit

/// Represents a message sent to linked devices during a change-number
/// informing those devices of the new PNI identity.
///
/// Note that while this type is a "message" subclass for compatibility with
/// other machinery, it should never be sent through the standard "send
/// message" message" machinery. Rather, it is _only_ used as part of a
/// change-number request.
final class PniChangePhoneNumberSyncMessage: OWSOutgoingSyncMessage {
    private let pniIdentityKeyPair: ECKeyPair
    private let signedPreKey: SignedPreKeyRecord
    private let registrationId: UInt32

    init(
        pniIdentityKeyPair: ECKeyPair,
        signedPreKey: SignedPreKeyRecord,
        registrationId: UInt32,
        thread: TSThread,
        transaction: SDSAnyReadTransaction
    ) {
        self.pniIdentityKeyPair = pniIdentityKeyPair
        self.signedPreKey = signedPreKey
        self.registrationId = registrationId

        super.init(thread: thread, transaction: transaction)
    }

    public override func syncMessageBuilder(
        transaction: SDSAnyReadTransaction
    ) -> SSKProtoSyncMessageBuilder? {
        let changeNumberBuilder = SSKProtoSyncMessagePniChangeNumber.builder()

        do {
            changeNumberBuilder.setIdentityKeyPair(Data(pniIdentityKeyPair.identityKeyPair.serialize()))
            changeNumberBuilder.setSignedPreKey(Data(try signedPreKey.asLSCRecord().serialize()))
            changeNumberBuilder.setRegistrationID(registrationId)
        } catch let error {
            owsFailDebug("Failed to build message: \(error)")
            return nil
        }

        let syncMessageBuilder = SSKProtoSyncMessage.builder()
        syncMessageBuilder.setPniChangeNumber(changeNumberBuilder.buildInfallibly())
        return syncMessageBuilder
    }

    override var shouldBeSaved: Bool {
        false
    }

    // MARK: - MTLModel

    @available(*, unavailable, message: "This type should never be serialized/deserialized.")
    public required init?(coder: NSCoder) {
        owsFail("This type should never be serialized/deserialized.")
    }

    @available(*, unavailable, message: "This type should never be serialized/deserialized.")
    public required init(dictionary: [String: Any]) throws {
        owsFail("This type should never be serialized/deserialized.")
    }
}
