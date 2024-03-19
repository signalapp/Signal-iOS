//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import LibSignalClient

public enum CallMessageAction {
    // This message should not be processed
    case ignore
    // Process the message by deferring to -externallyHandleCallMessage...
    case handOff
    // Process the message normally
    case process
}

public protocol CallMessageHandler {
    /// Informs caller of how the handler would like to handle this message
    func action(
        for envelope: SSKProtoEnvelope,
        callMessage: SSKProtoCallMessage,
        serverDeliveryTimestamp: UInt64
    ) -> CallMessageAction

    func receivedOffer(
        _ offer: SSKProtoCallMessageOffer,
        from caller: (aci: Aci, deviceId: UInt32),
        sentAtTimestamp: UInt64,
        serverReceivedTimestamp: UInt64,
        serverDeliveryTimestamp: UInt64,
        tx: SDSAnyWriteTransaction
    )

    func receivedAnswer(
        _ answer: SSKProtoCallMessageAnswer,
        from caller: (aci: Aci, deviceId: UInt32)
    )

    func receivedIceUpdate(
        _ iceUpdate: [SSKProtoCallMessageIceUpdate],
        from caller: (aci: Aci, deviceId: UInt32)
    )

    func receivedHangup(
        _ hangup: SSKProtoCallMessageHangup,
        from caller: (aci: Aci, deviceId: UInt32)
    )

    func receivedBusy(
        _ busy: SSKProtoCallMessageBusy,
        from caller: (aci: Aci, deviceId: UInt32)
    )

    func receivedOpaque(
        _ opaque: SSKProtoCallMessageOpaque,
        from caller: (aci: Aci, deviceId: UInt32),
        serverReceivedTimestamp: UInt64,
        serverDeliveryTimestamp: UInt64,
        tx: SDSAnyReadTransaction
    )

    func receivedGroupCallUpdateMessage(
        _ updateMessage: SSKProtoDataMessageGroupCallUpdate,
        for thread: TSGroupThread,
        serverReceivedTimestamp: UInt64,
        completion: @escaping () -> Void
    )

    func externallyHandleCallMessage(
        envelope: SSKProtoEnvelope,
        plaintextData: Data,
        wasReceivedByUD: Bool,
        serverDeliveryTimestamp: UInt64,
        tx: SDSAnyWriteTransaction
    )
}
