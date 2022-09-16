//
//  Copyright (c) 2022 Open Whisper Systems. All rights reserved.
//

import Foundation
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
        // We can skip call messages that are significantly old. They won't trigger a ring anyway
        let serverReceivedTimestamp = envelope.serverTimestamp > 0 ? envelope.serverTimestamp : envelope.timestamp
        let approxMessageAge = (serverDeliveryTimestamp - serverReceivedTimestamp)
        guard approxMessageAge < 5 * kMinuteInMs else {
            NSELogger.uncorrelated.info(
                "Discarding very old call message \(envelope.timestamp). No longer relevant. Server delivery: \(serverDeliveryTimestamp). Server received: \(serverReceivedTimestamp)"
            )
            return .ignore
        }

        // Only offer messages (TODO: and urgent opaque messages) will trigger a ring.
        if callMessage.offer != nil {
            return .handoff
        } else {
            NSELogger.uncorrelated.info("Ignoring call message. Not an offer.")
            return .ignore
        }
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
