//
// Copyright 2022 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

#if TESTABLE_BUILD

@objc(OWSFakeCallMessageHandler)
class FakeCallMessageHandler: NSObject, OWSCallMessageHandler {
    func action(
        for envelope: SSKProtoEnvelope,
        callMessage message: SSKProtoCallMessage,
        serverDeliveryTimestamp: UInt64
    ) -> OWSCallMessageAction {
        .process
    }

    func receivedOffer(
        _ offer: SSKProtoCallMessageOffer,
        from caller: SignalServiceAddress,
        sourceDevice device: UInt32,
        sentAtTimestamp: UInt64,
        serverReceivedTimestamp: UInt64,
        serverDeliveryTimestamp: UInt64,
        transaction: SDSAnyWriteTransaction
    ) {
        Logger.info("")
    }

    func receivedAnswer(
        _ answer: SSKProtoCallMessageAnswer,
        from caller: SignalServiceAddress,
        sourceDevice device: UInt32
    ) {
        Logger.info("")
    }

    func receivedIceUpdate(
        _ iceUpdate: [SSKProtoCallMessageIceUpdate],
        from caller: SignalServiceAddress,
        sourceDevice device: UInt32
    ) {
        Logger.info("")
    }

    func receivedHangup(
        _ hangup: SSKProtoCallMessageHangup,
        from caller: SignalServiceAddress,
        sourceDevice device: UInt32
    ) {
        Logger.info("")
    }

    func receivedBusy(
        _ busy: SSKProtoCallMessageBusy,
        from caller: SignalServiceAddress,
        sourceDevice device: UInt32
    ) {
        Logger.info("")
    }

    func receivedOpaque(
        _ opaque: SSKProtoCallMessageOpaque,
        from caller: AciObjC,
        sourceDevice device: UInt32,
        serverReceivedTimestamp: UInt64,
        serverDeliveryTimestamp: UInt64,
        transaction: SDSAnyReadTransaction
    ) {
        Logger.info("")
    }

    func receivedGroupCallUpdateMessage(
        _ updateMessage: SSKProtoDataMessageGroupCallUpdate,
        for groupThread: TSGroupThread,
        serverReceivedTimestamp: UInt64,
        completion completionHandler: @escaping () -> Void
    ) {
        Logger.info("")
    }

    func externallyHandleCallMessage(
        envelope: SSKProtoEnvelope,
        plaintextData: Data,
        wasReceivedByUD: Bool,
        serverDeliveryTimestamp: UInt64,
        transaction: SDSAnyWriteTransaction
    ) {
        owsFailDebug("Can't handle externally.")
    }
}

#endif
