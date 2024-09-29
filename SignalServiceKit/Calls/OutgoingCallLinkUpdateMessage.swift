//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
public import SignalRingRTC

@objc(OutgoingCallLinkUpdateMessage)
public class OutgoingCallLinkUpdateMessage: OWSOutgoingSyncMessage {
    @objc
    private var rootKey: Data!

    @objc
    private var adminPasskey: Data?

    public init(
        localThread: TSContactThread,
        rootKey: CallLinkRootKey,
        adminPasskey: Data?,
        tx: SDSAnyReadTransaction
    ) {
        self.rootKey = rootKey.bytes
        self.adminPasskey = adminPasskey
        super.init(thread: localThread, transaction: tx)
    }

    public required init?(coder: NSCoder) {
        super.init(coder: coder)
    }

    public required init(dictionary dictionaryValue: [String: Any]!) throws {
        try super.init(dictionary: dictionaryValue)
    }

    public override var isUrgent: Bool { false }

    public override func syncMessageBuilder(transaction: SDSAnyReadTransaction) -> SSKProtoSyncMessageBuilder? {
        let callLinkUpdateBuilder = SSKProtoSyncMessageCallLinkUpdate.builder()
        callLinkUpdateBuilder.setType(.update)
        callLinkUpdateBuilder.setRootKey(self.rootKey)
        if let adminPasskey = self.adminPasskey {
            callLinkUpdateBuilder.setAdminPasskey(adminPasskey)
        }

        let builder = SSKProtoSyncMessage.builder()
        builder.setCallLinkUpdate(callLinkUpdateBuilder.buildInfallibly())
        return builder
    }
}
