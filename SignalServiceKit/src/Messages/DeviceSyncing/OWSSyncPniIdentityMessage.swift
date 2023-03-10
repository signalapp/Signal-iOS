//
// Copyright 2022 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import Curve25519Kit

public class OWSSyncPniIdentityMessage: OWSOutgoingSyncMessage {
    // Exposed to Objective-C and made optional for MTLModel serialization.
    @objc
    private var keyPair: ECKeyPair!

    public init(thread: TSThread, keyPair: ECKeyPair, transaction: SDSAnyReadTransaction) {
        self.keyPair = keyPair
        super.init(thread: thread, transaction: transaction)
    }

    public override func syncMessageBuilder(transaction: SDSAnyReadTransaction) -> SSKProtoSyncMessageBuilder? {
        let pniIdentityBuilder = SSKProtoSyncMessagePniIdentity.builder()
        pniIdentityBuilder.setPublicKey(Data(keyPair.identityKeyPair.publicKey.serialize()))
        pniIdentityBuilder.setPrivateKey(Data(keyPair.identityKeyPair.privateKey.serialize()))

        let syncMessageBuilder = SSKProtoSyncMessage.builder()
        syncMessageBuilder.setPniIdentity(pniIdentityBuilder.buildInfallibly())
        return syncMessageBuilder
    }

    public override var isUrgent: Bool { false }

    // MARK: - MTLModel

    public required init?(coder: NSCoder) {
        super.init(coder: coder)
    }

    public required init(dictionary: [String: Any]) throws {
        try super.init(dictionary: dictionary)
    }
}
