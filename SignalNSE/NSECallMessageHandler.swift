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

    private var databaseStorage: SDSDatabaseStorage { NSObject.databaseStorage }
    private var groupCallManager: GroupCallManager { NSObject.groupCallManager }
    private var messagePipelineSupervisor: MessagePipelineSupervisor { NSObject.messagePipelineSupervisor }

    // MARK: - Call Handlers

    func receivedEnvelope(
        _ envelope: SSKProtoEnvelope,
        callEnvelope: CallEnvelopeType,
        from caller: (aci: Aci, deviceId: UInt32),
        plaintextData: Data,
        wasReceivedByUD: Bool,
        sentAtTimestamp: UInt64,
        serverReceivedTimestamp: UInt64,
        serverDeliveryTimestamp: UInt64,
        tx: SDSAnyWriteTransaction
    ) {
        let bufferSecondsForMainAppToAnswerRing: UInt64 = 10

        let serverReceivedTimestamp = serverReceivedTimestamp > 0 ? serverReceivedTimestamp : sentAtTimestamp
        let approxMessageAge = (serverDeliveryTimestamp - serverReceivedTimestamp)
        let messageAgeForRingRtc = approxMessageAge / kSecondInMs + bufferSecondsForMainAppToAnswerRing

        let shouldHandleExternally: Bool

        switch callEnvelope {
        case .offer(let offer):
            let callType: CallMediaType
            switch offer.type ?? .offerAudioCall {
            case .offerAudioCall: callType = .audioCall
            case .offerVideoCall: callType = .videoCall
            }

            shouldHandleExternally = { () -> Bool in
                guard let offerData = offer.opaque else {
                    return false
                }
                return isValidOfferMessage(
                    opaque: offerData,
                    messageAgeSec: messageAgeForRingRtc,
                    callMediaType: callType
                )
            }()
            if !shouldHandleExternally {
                NSELogger.uncorrelated.warn("Dropping offer message; invalid according to RingRTC (likely expired).")
            }

        case .opaque(let opaque):
            func validateGroupRing(groupId: Data, ringId: Int64) -> Bool {
                databaseStorage.read { transaction in
                    let sender = SignalServiceAddress(caller.aci)

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

            shouldHandleExternally = { () -> Bool in
                guard opaque.urgency == .handleImmediately else {
                    return false
                }
                guard let opaqueData = opaque.data else {
                    return false
                }
                return isValidOpaqueRing(
                    opaqueCallMessage: opaqueData,
                    messageAgeSec: messageAgeForRingRtc,
                    validateGroupRing: validateGroupRing
                )
            }()
            if !shouldHandleExternally {
                NSELogger.uncorrelated.info("Ignoring opaque message; not a valid ring according to RingRTC.")
            }

        case .answer, .iceUpdate, .hangup, .busy:
            shouldHandleExternally = false
            NSELogger.uncorrelated.warn("Dropping call message; the main app should be connected")
        }

        guard shouldHandleExternally else {
            return
        }

        externallyHandleCallMessage(
            envelope: envelope,
            plaintextData: plaintextData,
            wasReceivedByUD: wasReceivedByUD,
            serverDeliveryTimestamp: serverDeliveryTimestamp,
            tx: tx
        )
    }

    private func externallyHandleCallMessage(
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
}
