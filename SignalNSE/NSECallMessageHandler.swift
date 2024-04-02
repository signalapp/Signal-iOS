//
// Copyright 2021 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import CallKit
import Foundation
import LibSignalClient
import SignalRingRTC
import SignalServiceKit

class NSECallMessageHandler: CallMessageHandler {

    // MARK: Initializers

    init() {
        SwiftSingletons.register(self)
    }

    private var lightweightGroupCallManager: LightweightGroupCallManager { NSObject.lightweightGroupCallManager }
    private var messagePipelineSupervisor: MessagePipelineSupervisor { NSObject.messagePipelineSupervisor }
    private var databaseStorage: SDSDatabaseStorage { NSObject.databaseStorage }

    // MARK: - Call Handlers

    public func action(
        for envelope: SSKProtoEnvelope,
        callMessage: SSKProtoCallMessage,
        serverDeliveryTimestamp: UInt64
    ) -> CallMessageAction {
        let bufferSecondsForMainAppToAnswerRing: UInt64 = 10

        let serverReceivedTimestamp = envelope.serverTimestamp > 0 ? envelope.serverTimestamp : envelope.timestamp
        let approxMessageAge = (serverDeliveryTimestamp - serverReceivedTimestamp)
        let messageAgeForRingRtc = approxMessageAge / kSecondInMs + bufferSecondsForMainAppToAnswerRing

        if let offer = callMessage.offer {
            let callType: CallMediaType
            switch offer.type ?? .offerAudioCall {
            case .offerAudioCall: callType = .audioCall
            case .offerVideoCall: callType = .videoCall
            }

            if
                let offerData = offer.opaque,
                isValidOfferMessage(opaque: offerData, messageAgeSec: messageAgeForRingRtc, callMediaType: callType)
            {
                return .handOff
            }

            NSELogger.uncorrelated.info("Ignoring offer message; invalid according to RingRTC (likely expired).")
            return .ignore
        }

        if let opaqueMessage = callMessage.opaque {
            func validateGroupRing(groupId: Data, ringId: Int64) -> Bool {
                databaseStorage.read { transaction in
                    guard let sender = envelope.sourceAddress else {
                        owsFailDebug("shouldn't have gotten here with no sender")
                        return false
                    }

                    if sender.isLocalAddress {
                        // Always trust our other devices (important for cancellations).
                        return true
                    }

                    guard let thread = TSGroupThread.fetch(groupId: groupId, transaction: transaction) else {
                        owsFailDebug("discarding group ring \(ringId) from \(sender) for unknown group")
                        return false
                    }

                    guard GroupsV2MessageProcessor.discardMode(
                        forMessageFrom: sender,
                        groupId: groupId,
                        tx: transaction
                    ) == .doNotDiscard else {
                        NSELogger.uncorrelated.warn("discarding group ring \(ringId) from \(sender)")
                        return false
                    }

                    guard thread.groupMembership.fullMembers.count <= RemoteConfig.maxGroupCallRingSize else {
                        NSELogger.uncorrelated.warn("discarding group ring \(ringId) from \(sender) for too-large group")
                        return false
                    }

                    return true
                }
            }

            if
                opaqueMessage.urgency == .handleImmediately,
                let opaqueData = opaqueMessage.data,
                isValidOpaqueRing(opaqueCallMessage: opaqueData, messageAgeSec: messageAgeForRingRtc, validateGroupRing: validateGroupRing)
            {
                return .handOff
            }

            NSELogger.uncorrelated.info("Ignoring opaque message; not a valid ring according to RingRTC.")
            return .ignore
        }

        NSELogger.uncorrelated.info("Ignoring call message. Not an offer or urgent opaque message.")
        return .ignore
    }

    func externallyHandleCallMessage(
        envelope: SSKProtoEnvelope,
        plaintextData: Data,
        wasReceivedByUD: Bool,
        serverDeliveryTimestamp: UInt64,
        tx: SDSAnyWriteTransaction
    ) {
        do {
            let payload = try CallMessageRelay.enqueueCallMessageForMainApp(
                envelope: envelope,
                plaintextData: plaintextData,
                wasReceivedByUD: wasReceivedByUD,
                serverDeliveryTimestamp: serverDeliveryTimestamp,
                transaction: tx
            )

            // We don't want to risk consuming any call messages that the main app needs to perform the call
            // We suspend message processing in our process to give the main app a chance to wake and take over
            let suspension = messagePipelineSupervisor.suspendMessageProcessing(for: .nseWakingUpApp(suspensionId: UUID(), payloadString: "\(payload)"))
            DispatchQueue.sharedUtility.asyncAfter(deadline: .now() + .seconds(10)) {
                suspension.invalidate()
            }

            NSELogger.uncorrelated.info("Notifying primary app of incoming call with push payload: \(payload)")
            CXProvider.reportNewIncomingVoIPPushPayload(payload.payloadDict) { error in
                if let error = error {
                    owsFailDebug("Failed to notify main app of call message: \(error)")
                } else {
                    NSELogger.uncorrelated.info("Successfully notified main app of call message.")
                }
            }
        } catch {
            owsFailDebug("Failed to create relay voip payload for call message \(error)")
        }
    }

    func receivedOffer(
        _ offer: SSKProtoCallMessageOffer,
        from caller: (aci: Aci, deviceId: UInt32),
        sentAtTimestamp: UInt64,
        serverReceivedTimestamp: UInt64,
        serverDeliveryTimestamp: UInt64,
        tx: SDSAnyWriteTransaction
    ) {
        owsFailDebug("This should never be called, calls are handled externally")
    }

    func receivedAnswer(
        _ answer: SSKProtoCallMessageAnswer,
        from caller: (aci: Aci, deviceId: UInt32)
    ) {
        owsFailDebug("This should never be called, calls are handled externally")
    }

    func receivedIceUpdate(
        _ iceUpdate: [SSKProtoCallMessageIceUpdate],
        from caller: (aci: Aci, deviceId: UInt32)
    ) {
        owsFailDebug("This should never be called, calls are handled externally")
    }

    func receivedHangup(
        _ hangup: SSKProtoCallMessageHangup,
        from caller: (aci: Aci, deviceId: UInt32)
    ) {
        owsFailDebug("This should never be called, calls are handled externally")
    }

    func receivedBusy(
        _ busy: SSKProtoCallMessageBusy,
        from caller: (aci: Aci, deviceId: UInt32)
    ) {
        owsFailDebug("This should never be called, calls are handled externally")
    }

    func receivedOpaque(
        _ opaque: SSKProtoCallMessageOpaque,
        from caller: (aci: Aci, deviceId: UInt32),
        serverReceivedTimestamp: UInt64,
        serverDeliveryTimestamp: UInt64,
        tx: SDSAnyReadTransaction
    ) {
        owsFailDebug("This should never be called, calls are handled externally")
    }

    func receivedGroupCallUpdateMessage(
        _ updateMessage: SSKProtoDataMessageGroupCallUpdate,
        for groupThread: TSGroupThread,
        serverReceivedTimestamp: UInt64
    ) async {
        GroupCallPeekLogger.shared.info(
            "Received group call update message for thread \(groupThread.uniqueId), eraId \(String(describing: updateMessage.eraID))"
        )

        await lightweightGroupCallManager.peekGroupCallAndUpdateThread(
            groupThread,
            peekTrigger: .receivedGroupUpdateMessage(
                eraId: updateMessage.eraID,
                messageTimestamp: serverReceivedTimestamp
            )
        )
    }
}
