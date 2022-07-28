//
//  Copyright (c) 2022 Open Whisper Systems. All rights reserved.
//

import Foundation

public class OWSSyncPniIdentityMessage: OWSOutgoingSyncMessage {
    // Exposed to Objective-C and made optional for MTLModel serialization.
    @objc
    private var keyPair: ECKeyPair!

    public init(thread: TSThread, keyPair: ECKeyPair, transaction: SDSAnyReadTransaction) {
        self.keyPair = keyPair
        super.init(thread: thread, transaction: transaction)
    }

    public override func syncMessageBuilder(transaction: SDSAnyReadTransaction) -> SSKProtoSyncMessageBuilder? {
        do {
            let pniIdentityBuilder = SSKProtoSyncMessagePniIdentity.builder()
            pniIdentityBuilder.setPublicKey(Data(keyPair.identityKeyPair.publicKey.serialize()))
            pniIdentityBuilder.setPrivateKey(Data(keyPair.identityKeyPair.privateKey.serialize()))

            let syncMessageBuilder = SSKProtoSyncMessage.builder()
            syncMessageBuilder.setPniIdentity(try pniIdentityBuilder.build())
            return syncMessageBuilder
        } catch {
            owsFailDebug("failed to build PniIdentity message: \(error)")
            return nil
        }
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
