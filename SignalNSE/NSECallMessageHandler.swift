//
// Copyright 2021 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import SignalRingRTC
import SignalServiceKit
import SignalMessaging
import CallKit

public class NSECallMessageHandler: NSObject, OWSCallMessageHandler {

    // MARK: Initializers

    @objc
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

            if let offerData = offer.opaque,
               isValidOfferMessage(opaque: offerData,
                                   messageAgeSec: messageAgeForRingRtc,
                                   callMediaType: callType) {
                return .handoff
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
                    return GroupsV2MessageProcessor.discardMode(forMessageFrom: sender,
                                                                groupId: groupId,
                                                                transaction: transaction) == .doNotDiscard
                }
            }

            if opaqueMessage.urgency == .handleImmediately,
               let opaqueData = opaqueMessage.data,
               RemoteConfig.groupRings,
               isValidOpaqueRing(opaqueCallMessage: opaqueData,
                                 messageAgeSec: messageAgeForRingRtc,
                                 validateGroupRing: validateGroupRing) {
                return .handoff
            }

            NSELogger.uncorrelated.info("Ignoring opaque message; not a valid ring according to RingRTC.")
            return .ignore
        }

        NSELogger.uncorrelated.info("Ignoring call message. Not an offer or urgent opaque message.")
        return .ignore
    }

    public func externallyHandleCallMessage(
        envelope: SSKProtoEnvelope,
        plaintextData: Data,
        wasReceivedByUD: Bool,
        serverDeliveryTimestamp: UInt64,
        transaction: SDSAnyWriteTransaction
    ) {
        do {
            let payload = try CallMessageRelay.enqueueCallMessageForMainApp(
                envelope: envelope,
                plaintextData: plaintextData,
                wasReceivedByUD: wasReceivedByUD,
                serverDeliveryTimestamp: serverDeliveryTimestamp,
                transaction: transaction
            )

            // We don't want to risk consuming any call messages that the main app needs to perform the call
            // We suspend message processing in our process to give the main app a chance to wake and take over
            let suspension = messagePipelineSupervisor.suspendMessageProcessing(for: "Waking main app for \(payload)")
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
        owsFailDebug("This should never be called, calls are handled externally")
    }

    public func receivedAnswer(_ answer: SSKProtoCallMessageAnswer, from caller: SignalServiceAddress, sourceDevice: UInt32, supportsMultiRing: Bool) {
        owsFailDebug("This should never be called, calls are handled externally")
    }

    public func receivedIceUpdate(_ iceUpdate: [SSKProtoCallMessageIceUpdate], from caller: SignalServiceAddress, sourceDevice: UInt32) {
        owsFailDebug("This should never be called, calls are handled externally")
    }

    public func receivedHangup(_ hangup: SSKProtoCallMessageHangup, from caller: SignalServiceAddress, sourceDevice: UInt32) {
        owsFailDebug("This should never be called, calls are handled externally")
    }

    public func receivedBusy(_ busy: SSKProtoCallMessageBusy, from caller: SignalServiceAddress, sourceDevice: UInt32) {
        owsFailDebug("This should never be called, calls are handled externally")
    }

    public func receivedOpaque(
        _ opaque: SSKProtoCallMessageOpaque,
        from caller: SignalServiceAddress,
        sourceDevice: UInt32,
        serverReceivedTimestamp: UInt64,
        serverDeliveryTimestamp: UInt64,
        transaction: SDSAnyReadTransaction
    ) {
        owsFailDebug("This should never be called, calls are handled externally")
    }

    public func receivedGroupCallUpdateMessage(
        _ updateMessage: SSKProtoDataMessageGroupCallUpdate,
        for groupThread: TSGroupThread,
        serverReceivedTimestamp: UInt64,
        completion: @escaping () -> Void
    ) {
        NSELogger.uncorrelated.info("Received group call update for thread \(groupThread.uniqueId)")
        lightweightCallManager?.peekCallAndUpdateThread(
            groupThread,
            expectedEraId: updateMessage.eraID,
            triggerEventTimestamp: serverReceivedTimestamp,
            completion: completion)
    }
}
