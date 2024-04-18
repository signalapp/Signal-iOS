//
// Copyright 2016 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import LibSignalClient
import SignalServiceKit

class WebRTCCallMessageHandler: CallMessageHandler {

    // MARK: Initializers

    public init() {
        SwiftSingletons.register(self)
    }

    private var callService: CallService { AppEnvironment.shared.callService }
    private var groupCallManager: GroupCallManager { NSObject.groupCallManager }
    private var tsAccountManager: TSAccountManager { DependenciesBridge.shared.tsAccountManager }

    // MARK: - Call Handlers

    public func action(
        for envelope: SSKProtoEnvelope,
        callMessage: SSKProtoCallMessage,
        serverDeliveryTimestamp: UInt64
    ) -> CallMessageAction {
        return .process
    }

    func receivedOffer(
        _ offer: SSKProtoCallMessageOffer,
        from caller: (aci: Aci, deviceId: UInt32),
        sentAtTimestamp: UInt64,
        serverReceivedTimestamp: UInt64,
        serverDeliveryTimestamp: UInt64,
        tx: SDSAnyWriteTransaction
    ) {
        AssertIsOnMainThread()

        let callType: SSKProtoCallMessageOfferType
        if offer.hasType {
            callType = offer.unwrappedType
        } else {
            // The type is not defined so assume the default, audio.
            callType = .offerAudioCall
        }

        let thread = TSContactThread.getOrCreateThread(
            withContactAddress: SignalServiceAddress(caller.aci),
            transaction: tx
        )
        self.callService.individualCallService.handleReceivedOffer(
            thread: thread,
            callId: offer.id,
            sourceDevice: caller.deviceId,
            opaque: offer.opaque,
            sentAtTimestamp: sentAtTimestamp,
            serverReceivedTimestamp: serverReceivedTimestamp,
            serverDeliveryTimestamp: serverDeliveryTimestamp,
            callType: callType,
            transaction: tx
        )
    }

    func receivedAnswer(
        _ answer: SSKProtoCallMessageAnswer,
        from caller: (aci: Aci, deviceId: UInt32)
    ) {
        AssertIsOnMainThread()

        let thread = TSContactThread.getOrCreateThread(contactAddress: SignalServiceAddress(caller.aci))
        self.callService.individualCallService.handleReceivedAnswer(
            thread: thread,
            callId: answer.id,
            sourceDevice: caller.deviceId,
            opaque: answer.opaque
        )
    }

    func receivedIceUpdate(
        _ iceUpdate: [SSKProtoCallMessageIceUpdate],
        from caller: (aci: Aci, deviceId: UInt32)
    ) {
        AssertIsOnMainThread()

        let thread = TSContactThread.getOrCreateThread(contactAddress: SignalServiceAddress(caller.aci))
        self.callService.individualCallService.handleReceivedIceCandidates(
            thread: thread,
            callId: iceUpdate[0].id,
            sourceDevice: caller.deviceId,
            candidates: iceUpdate
        )
    }

    func receivedHangup(
        _ hangup: SSKProtoCallMessageHangup,
        from caller: (aci: Aci, deviceId: UInt32)
    ) {
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

        let thread = TSContactThread.getOrCreateThread(contactAddress: SignalServiceAddress(caller.aci))
        self.callService.individualCallService.handleReceivedHangup(
            thread: thread,
            callId: hangup.id,
            sourceDevice: caller.deviceId,
            type: type,
            deviceId: deviceId
        )
    }

    func receivedBusy(
        _ busy: SSKProtoCallMessageBusy,
        from caller: (aci: Aci, deviceId: UInt32)
    ) {
        AssertIsOnMainThread()

        let thread = TSContactThread.getOrCreateThread(contactAddress: SignalServiceAddress(caller.aci))
        self.callService.individualCallService.handleReceivedBusy(
            thread: thread,
            callId: busy.id,
            sourceDevice: caller.deviceId
        )
    }

    func receivedOpaque(
        _ opaque: SSKProtoCallMessageOpaque,
        from caller: (aci: Aci, deviceId: UInt32),
        serverReceivedTimestamp: UInt64,
        serverDeliveryTimestamp: UInt64,
        tx: SDSAnyReadTransaction
    ) {
        AssertIsOnMainThread()
        Logger.info("Received opaque call message from \(caller.aci).\(caller.deviceId)")

        guard let message = opaque.data else {
            owsFailDebug("Received opaque call message without data")
            return
        }

        var messageAgeSec: UInt64 = 0
        if serverReceivedTimestamp > 0 && serverDeliveryTimestamp >= serverReceivedTimestamp {
            messageAgeSec = (serverDeliveryTimestamp - serverReceivedTimestamp) / 1000
        }

        let localDeviceId = tsAccountManager.storedDeviceId(tx: tx.asV2Read)

        self.callService.callManager.receivedCallMessage(
            senderUuid: caller.aci.rawUUID,
            senderDeviceId: caller.deviceId,
            localDeviceId: localDeviceId,
            message: message,
            messageAgeSec: messageAgeSec
        )
    }

    func receivedGroupCallUpdateMessage(
        _ updateMessage: SSKProtoDataMessageGroupCallUpdate,
        for groupThread: TSGroupThread,
        serverReceivedTimestamp: UInt64
    ) async {
        await groupCallManager.peekGroupCallAndUpdateThread(
            groupThread,
            peekTrigger: .receivedGroupUpdateMessage(
                eraId: updateMessage.eraID,
                messageTimestamp: serverReceivedTimestamp
            )
        )
    }

    func externallyHandleCallMessage(
        envelope: SSKProtoEnvelope,
        plaintextData: Data,
        wasReceivedByUD: Bool,
        serverDeliveryTimestamp: UInt64,
        tx: SDSAnyWriteTransaction
    ) {
        owsFailDebug("Can't handle externally. We're already the main app.")
    }
}
