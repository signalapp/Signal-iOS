//
// Copyright 2017 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import LibSignalClient
import SignalCoreKit

public class NoopCallMessageHandler: CallMessageHandler {
    public init() {}

    public func action(
        for envelope: SSKProtoEnvelope,
        callMessage: SSKProtoCallMessage,
        serverDeliveryTimestamp: UInt64
    ) -> CallMessageAction {
        return .process
    }

    public func receivedOffer(
        _ offer: SSKProtoCallMessageOffer,
        from caller: (aci: Aci, deviceId: UInt32),
        sentAtTimestamp: UInt64,
        serverReceivedTimestamp: UInt64,
        serverDeliveryTimestamp: UInt64,
        tx: SDSAnyWriteTransaction
    ) {
        owsFailDebug("")
    }

    public func receivedAnswer(
        _ answer: SSKProtoCallMessageAnswer,
        from caller: (aci: Aci, deviceId: UInt32),
        tx: SDSAnyReadTransaction
    ) {
        owsFailDebug("")
    }

    public func receivedIceUpdate(
        _ iceUpdate: [SSKProtoCallMessageIceUpdate],
        from caller: (aci: Aci, deviceId: UInt32)
    ) {
        owsFailDebug("")
    }

    public func receivedHangup(
        _ hangup: SSKProtoCallMessageHangup,
        from caller: (aci: Aci, deviceId: UInt32)
    ) {
        owsFailDebug("")
    }

    public func receivedBusy(
        _ busy: SSKProtoCallMessageBusy,
        from caller: (aci: Aci, deviceId: UInt32)
    ) {
        owsFailDebug("")
    }

    public func receivedOpaque(
        _ opaque: SSKProtoCallMessageOpaque,
        from caller: (aci: Aci, deviceId: UInt32),
        serverReceivedTimestamp: UInt64,
        serverDeliveryTimestamp: UInt64,
        tx: SDSAnyReadTransaction
    ) {
        owsFailDebug("")
    }

    public func receivedGroupCallUpdateMessage(
        _ updateMessage: SSKProtoDataMessageGroupCallUpdate,
        for groupThread: TSGroupThread,
        serverReceivedTimestamp: UInt64
    ) async {
        owsFailDebug("")
    }

    public func externallyHandleCallMessage(
        envelope: SSKProtoEnvelope,
        plaintextData: Data,
        wasReceivedByUD: Bool,
        serverDeliveryTimestamp: UInt64,
        tx: SDSAnyWriteTransaction
    ) {
        owsFailDebug("Can't handle externally.")
    }
}
