//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
public import LibSignalClient

public enum CallEnvelopeType {
    case offer(SSKProtoCallMessageOffer)
    case answer(SSKProtoCallMessageAnswer)
    case iceUpdate([SSKProtoCallMessageIceUpdate])
    case hangup(SSKProtoCallMessageHangup)
    case busy(SSKProtoCallMessageBusy)
    case opaque(SSKProtoCallMessageOpaque)
}

public protocol CallMessageHandler {
    func receivedEnvelope(
        _ envelope: SSKProtoEnvelope,
        callEnvelope: CallEnvelopeType,
        from caller: (aci: Aci, deviceId: UInt32),
        toLocalIdentity localIdentity: OWSIdentity,
        plaintextData: Data,
        wasReceivedByUD: Bool,
        sentAtTimestamp: UInt64,
        serverReceivedTimestamp: UInt64,
        serverDeliveryTimestamp: UInt64,
        tx: SDSAnyWriteTransaction
    )

    func receivedGroupCallUpdateMessage(
        _ updateMessage: SSKProtoDataMessageGroupCallUpdate,
        forGroupId groupId: GroupIdentifier,
        serverReceivedTimestamp: UInt64
    ) async
}
