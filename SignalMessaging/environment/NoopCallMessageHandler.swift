//
// Copyright 2017 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import SignalServiceKit

public class NoopCallMessageHandler: NSObject, OWSCallMessageHandler {

    public func action(
        for envelope: SSKProtoEnvelope,
        callMessage: SSKProtoCallMessage,
        serverDeliveryTimestamp: UInt64
    ) -> OWSCallMessageAction {
        .process
    }

    public func receivedOffer(_ offer: SSKProtoCallMessageOffer, from caller: SignalServiceAddress, sourceDevice device: UInt32, sentAtTimestamp: UInt64, serverReceivedTimestamp: UInt64, serverDeliveryTimestamp: UInt64, supportsMultiRing: Bool,
                              transaction: SDSAnyWriteTransaction) {
        owsFailDebug("")
    }

    public func receivedAnswer(_ answer: SSKProtoCallMessageAnswer, from caller: SignalServiceAddress, sourceDevice device: UInt32, supportsMultiRing: Bool) {
        owsFailDebug("")
    }

    public func receivedIceUpdate(_ iceUpdate: [SSKProtoCallMessageIceUpdate], from caller: SignalServiceAddress, sourceDevice device: UInt32) {
        owsFailDebug("")
    }

    public func receivedHangup(_ hangup: SSKProtoCallMessageHangup, from caller: SignalServiceAddress, sourceDevice device: UInt32) {
        owsFailDebug("")
    }

    public func receivedBusy(_ busy: SSKProtoCallMessageBusy, from caller: SignalServiceAddress, sourceDevice device: UInt32) {
        owsFailDebug("")
    }

    public func receivedOpaque(_ opaque: SSKProtoCallMessageOpaque, from caller: AciObjC, sourceDevice device: UInt32, serverReceivedTimestamp: UInt64, serverDeliveryTimestamp: UInt64, transaction: SDSAnyReadTransaction) {
        owsFailDebug("")
    }

    public func receivedGroupCallUpdateMessage(_ updateMessage: SSKProtoDataMessageGroupCallUpdate, for groupThread: TSGroupThread, serverReceivedTimestamp: UInt64, completion: @escaping () -> Void) {
        owsFailDebug("")
    }

    public func externallyHandleCallMessage(envelope: SSKProtoEnvelope, plaintextData: Data, wasReceivedByUD: Bool, serverDeliveryTimestamp: UInt64, transaction: SDSAnyWriteTransaction) {
        owsFailDebug("Can't handle externally.")
    }
}
