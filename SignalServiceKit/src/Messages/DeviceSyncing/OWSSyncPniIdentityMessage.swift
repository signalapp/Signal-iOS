//
//  Copyright (c) 2022 Open Whisper Systems. All rights reserved.
//

import Foundation

public class OWSSyncPniIdentityMessage: OWSOutgoingSyncMessage {
    // Exposed to Objective-C and made optional for MTLModel serialization.
    @objc
    private var keyPair: ECKeyPair!

    public init(thread: TSThread, keyPair: ECKeyPair) {
        self.keyPair = keyPair
        super.init(thread: thread)
    }

    public override func syncMessageBuilder(transaction: SDSAnyReadTransaction) -> SSKProtoSyncMessageBuilderProtocol? {
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

    // MARK: - MTLModel

    public required init?(coder: NSCoder) {
        super.init(coder: coder)
    }

    public required init(dictionary: [String: Any]) throws {
        try super.init(dictionary: dictionary)
    }
}
