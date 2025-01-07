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

    private var databaseStorage: SDSDatabaseStorage { SSKEnvironment.shared.databaseStorageRef }
    private var groupCallManager: GroupCallManager { SSKEnvironment.shared.groupCallManagerRef }
    private var identityManager: any OWSIdentityManager { DependenciesBridge.shared.identityManager }
    private var messagePipelineSupervisor: MessagePipelineSupervisor { SSKEnvironment.shared.messagePipelineSupervisorRef }
    private var notificationPresenter: NotificationPresenterImpl { SSKEnvironment.shared.notificationPresenterRef as! NotificationPresenterImpl }
    private var profileManager: any ProfileManager { SSKEnvironment.shared.profileManagerRef }
    private var tsAccountManager: any TSAccountManager { DependenciesBridge.shared.tsAccountManager }

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
        let bufferSecondsForMainAppToAnswerRing: UInt64 = 10

        let serverReceivedTimestamp = serverReceivedTimestamp > 0 ? serverReceivedTimestamp : sentAtTimestamp
        let approxMessageAge = (serverDeliveryTimestamp - serverReceivedTimestamp)
        let messageAgeForRingRtc = approxMessageAge / kSecondInMs + bufferSecondsForMainAppToAnswerRing

        switch callEnvelope {
        case .offer(let offer):
            guard let opaque = offer.opaque else {
                return
            }
            let callOfferHandler = CallOfferHandlerImpl(
                identityManager: identityManager,
                notificationPresenter: notificationPresenter,
                profileManager: profileManager,
                tsAccountManager: tsAccountManager
            )
            let partialResult = callOfferHandler.startHandlingOffer(
                caller: caller.aci,
                sourceDevice: caller.deviceId,
                localIdentity: localIdentity,
                callId: offer.id,
                callType: offer.type ?? .offerAudioCall,
                sentAtTimestamp: sentAtTimestamp,
                tx: tx
            )
            guard let partialResult else {
                return
            }

            let callType: CallMediaType
            switch offer.type ?? .offerAudioCall {
            case .offerAudioCall: callType = .audioCall
            case .offerVideoCall: callType = .videoCall
            }
            let isValid = isValidOfferMessage(
                opaque: opaque,
                messageAgeSec: messageAgeForRingRtc,
                callMediaType: callType
            )
            guard isValid else {
                NSELogger.uncorrelated.warn("missed a call because it's not valid (according to RingRTC)")
                callOfferHandler.insertMissedCallInteraction(
                    for: offer.id,
                    in: partialResult.thread,
                    outcome: .incomingMissed,
                    callType: partialResult.offerMediaType,
                    sentAtTimestamp: sentAtTimestamp,
                    tx: tx
                )
                return
            }

        case .opaque(let opaque):
            func validateGroupRing(groupId: Data, ringId: Int64) -> Bool {
                databaseStorage.read { transaction in
                    if SignalServiceAddress(caller.aci).isLocalAddress {
                        // Always trust our other devices (important for cancellations).
                        return true
                    }

                    guard let thread = TSGroupThread.fetch(groupId: groupId, transaction: transaction) else {
                        owsFailDebug("discarding group ring \(ringId) from \(caller.aci) for unknown group")
                        return false
                    }

                    guard GroupsV2MessageProcessor.discardMode(
                        forMessageFrom: caller.aci,
                        groupId: groupId,
                        tx: transaction
                    ) == .doNotDiscard else {
                        NSELogger.uncorrelated.warn("discarding group ring \(ringId) from \(caller.aci)")
                        return false
                    }

                    guard thread.groupMembership.fullMembers.count <= RemoteConfig.current.maxGroupCallRingSize else {
                        NSELogger.uncorrelated.warn("discarding group ring \(ringId) from \(caller.aci) for too-large group")
                        return false
                    }

                    return true
                }
            }

            let shouldHandleExternally = { () -> Bool in
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
            guard shouldHandleExternally else {
                NSELogger.uncorrelated.info("Ignoring opaque message; not a valid ring according to RingRTC.")
                return
            }

        case .answer, .iceUpdate, .hangup, .busy:
            NSELogger.uncorrelated.warn("Dropping call message; the main app should be connected")
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
