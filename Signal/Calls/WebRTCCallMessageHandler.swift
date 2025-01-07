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
    private var groupCallManager: GroupCallManager { SSKEnvironment.shared.groupCallManagerRef }
    private var tsAccountManager: TSAccountManager { DependenciesBridge.shared.tsAccountManager }

    // MARK: - Call Handlers

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
    ) {
        switch callEnvelope {
        case .offer(let offer):
            self.callService.individualCallService.handleReceivedOffer(
                caller: caller.aci,
                sourceDevice: caller.deviceId,
                localIdentity: localIdentity,
                callId: offer.id,
                opaque: offer.opaque,
                sentAtTimestamp: sentAtTimestamp,
                serverReceivedTimestamp: serverReceivedTimestamp,
                serverDeliveryTimestamp: serverDeliveryTimestamp,
                callType: offer.type ?? .offerAudioCall,
                tx: tx
            )
        case .answer(let answer):
            self.callService.individualCallService.handleReceivedAnswer(
                caller: caller.aci,
                callId: answer.id,
                sourceDevice: caller.deviceId,
                opaque: answer.opaque,
                tx: tx
            )
        case .iceUpdate(let iceUpdate):
            self.callService.individualCallService.handleReceivedIceCandidates(
                caller: caller.aci,
                callId: iceUpdate[0].id,
                sourceDevice: caller.deviceId,
                candidates: iceUpdate
            )
        case .hangup(let hangup):
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

            self.callService.individualCallService.handleReceivedHangup(
                caller: caller.aci,
                callId: hangup.id,
                sourceDevice: caller.deviceId,
                type: type,
                deviceId: deviceId
            )
        case .busy(let busy):
            self.callService.individualCallService.handleReceivedBusy(
                caller: caller.aci,
                callId: busy.id,
                sourceDevice: caller.deviceId
            )
        case .opaque(let opaque):
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

            DispatchQueue.main.async {
                self.callService.callManager.receivedCallMessage(
                    senderUuid: caller.aci.rawUUID,
                    senderDeviceId: caller.deviceId,
                    localDeviceId: localDeviceId,
                    message: message,
                    messageAgeSec: messageAgeSec
                )
            }
        }
    }

    func receivedGroupCallUpdateMessage(
        _ updateMessage: SSKProtoDataMessageGroupCallUpdate,
        forGroupId groupId: GroupIdentifier,
        serverReceivedTimestamp: UInt64
    ) async {
        await groupCallManager.peekGroupCallAndUpdateThread(
            forGroupId: groupId,
            peekTrigger: .receivedGroupUpdateMessage(
                eraId: updateMessage.eraID,
                messageTimestamp: serverReceivedTimestamp
            )
        )
    }
}
