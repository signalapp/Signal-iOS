//
// Copyright 2016 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import SignalServiceKit
import SignalMessaging

public class WebRTCCallMessageHandler: NSObject, OWSCallMessageHandler {

    // MARK: Initializers

    public override init() {
        super.init()

        SwiftSingletons.register(self)
    }

    // MARK: - Call Handlers

    public func action(
        for envelope: SSKProtoEnvelope,
        callMessage: SSKProtoCallMessage,
        serverDeliveryTimestamp: UInt64
    ) -> OWSCallMessageAction {
        .process
    }

    public func receivedOffer(
        _ offer: SSKProtoCallMessageOffer,
        from caller: SignalServiceAddress,
        sourceDevice: UInt32,
        sentAtTimestamp: UInt64,
        serverReceivedTimestamp: UInt64,
        serverDeliveryTimestamp: UInt64,
        supportsMultiRing: Bool,
        transaction: SDSAnyWriteTransaction
    ) {
        AssertIsOnMainThread()

        let callType: SSKProtoCallMessageOfferType
        if offer.hasType {
            callType = offer.unwrappedType
        } else {
            // The type is not defined so assume the default, audio.
            callType = .offerAudioCall
        }

        let thread = TSContactThread.getOrCreateThread(withContactAddress: caller,
                                                       transaction: transaction)
        self.callService.individualCallService.handleReceivedOffer(
            thread: thread,
            callId: offer.id,
            sourceDevice: sourceDevice,
            sdp: offer.sdp,
            opaque: offer.opaque,
            sentAtTimestamp: sentAtTimestamp,
            serverReceivedTimestamp: serverReceivedTimestamp,
            serverDeliveryTimestamp: serverDeliveryTimestamp,
            callType: callType,
            supportsMultiRing: supportsMultiRing,
            transaction: transaction
        )
    }

    public func receivedAnswer(_ answer: SSKProtoCallMessageAnswer, from caller: SignalServiceAddress, sourceDevice: UInt32, supportsMultiRing: Bool) {
        AssertIsOnMainThread()

        let thread = TSContactThread.getOrCreateThread(contactAddress: caller)
        self.callService.individualCallService.handleReceivedAnswer(
            thread: thread,
            callId: answer.id,
            sourceDevice: sourceDevice,
            sdp: answer.sdp,
            opaque: answer.opaque,
            supportsMultiRing: supportsMultiRing
        )
    }

    public func receivedIceUpdate(_ iceUpdate: [SSKProtoCallMessageIceUpdate], from caller: SignalServiceAddress, sourceDevice: UInt32) {
        AssertIsOnMainThread()

        let thread = TSContactThread.getOrCreateThread(contactAddress: caller)
        self.callService.individualCallService.handleReceivedIceCandidates(
            thread: thread,
            callId: iceUpdate[0].id,
            sourceDevice: sourceDevice,
            candidates: iceUpdate
        )
    }

    public func receivedHangup(_ hangup: SSKProtoCallMessageHangup, from caller: SignalServiceAddress, sourceDevice: UInt32) {
        AssertIsOnMainThread()

        // deviceId is optional and defaults to 0.
        var deviceId: UInt32 = 0

        let type: SSKProtoCallMessageHangupType
        if hangup.hasType {
            type = hangup.unwrappedType

            if hangup.hasDeviceID {
                deviceId = hangup.deviceID
            }
        } else {
            // The type is not defined so assume the default, normal.
            type = .hangupNormal
        }

        let thread = TSContactThread.getOrCreateThread(contactAddress: caller)
        self.callService.individualCallService.handleReceivedHangup(
            thread: thread,
            callId: hangup.id,
            sourceDevice: sourceDevice,
            type: type,
            deviceId: deviceId
        )
    }

    public func receivedBusy(_ busy: SSKProtoCallMessageBusy, from caller: SignalServiceAddress, sourceDevice: UInt32) {
        AssertIsOnMainThread()

        let thread = TSContactThread.getOrCreateThread(contactAddress: caller)
        self.callService.individualCallService.handleReceivedBusy(
            thread: thread,
            callId: busy.id,
            sourceDevice: sourceDevice
        )
    }

    public func receivedOpaque(
        _ opaque: SSKProtoCallMessageOpaque,
        from caller: AciObjC,
        sourceDevice: UInt32,
        serverReceivedTimestamp: UInt64,
        serverDeliveryTimestamp: UInt64,
        transaction: SDSAnyReadTransaction
    ) {
        AssertIsOnMainThread()
        Logger.info("Received opaque call message from \(caller) on device \(sourceDevice)")

        guard let message = opaque.data else {
            return owsFailDebug("Received opaque call message without data")
        }

        var messageAgeSec: UInt64 = 0
        if serverReceivedTimestamp > 0 && serverDeliveryTimestamp >= serverReceivedTimestamp {
            messageAgeSec = (serverDeliveryTimestamp - serverReceivedTimestamp) / 1000
        }

        let localDeviceId = Self.tsAccountManager.storedDeviceId(transaction: transaction)

        self.callService.callManager.receivedCallMessage(
            senderUuid: caller.rawUUID,
            senderDeviceId: sourceDevice,
            localDeviceId: localDeviceId,
            message: message,
            messageAgeSec: messageAgeSec
        )
    }

    public func receivedGroupCallUpdateMessage(
        _ updateMessage: SSKProtoDataMessageGroupCallUpdate,
        for groupThread: TSGroupThread,
        serverReceivedTimestamp: UInt64,
        completion: @escaping () -> Void
    ) {
        Logger.info("Received group call update message for thread: \(groupThread.uniqueId) eraId: \(String(describing: updateMessage.eraID))")
        callService.peekCallAndUpdateThread(
            groupThread,
            expectedEraId: updateMessage.eraID,
            triggerEventTimestamp: serverReceivedTimestamp,
            completion: completion)
    }

    public func externallyHandleCallMessage(envelope: SSKProtoEnvelope, plaintextData: Data, wasReceivedByUD: Bool, serverDeliveryTimestamp: UInt64, transaction: SDSAnyWriteTransaction) {
        owsFailDebug("Can't handle externally. We're already the main app.")
    }
}
