//
//  Copyright (c) 2021 Open Whisper Systems. All rights reserved.
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

    public func action(for envelope: SSKProtoEnvelope, callMessage: SSKProtoCallMessage) -> OWSCallMessageAction {
        // We can skip call messages that are significantly old. They won't trigger a ring anyway
        let localTimestamp = Date.ows_millisecondTimestamp()
        let remoteTimestamp = envelope.serverTimestamp > 0 ? envelope.serverTimestamp : envelope.timestamp
        let approxMessageAge = (localTimestamp - remoteTimestamp)
        guard approxMessageAge < 5 * kMinuteInMs else {
            Logger.info("Discarding very old call message. No longer relevant. Local: \(localTimestamp). Remote: \(remoteTimestamp)")
            return .ignore
        }

        // Only offer messages and urgent opaque messages will trigger a ring.
        if callMessage.offer != nil {
            return .handoff
        } else if let opaqueMessage = callMessage.opaque, opaqueMessage.urgency == .handleImmediately {
            return .handoff
        } else {
            Logger.info("Ignoring call message. Not an offer or urgent opaque message.")
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
        // There used to be a way to hand off decrypted messages to the main
        // app for processing, but it was prone to races. We have ideas to fix
        // this but in the meantime, we'll be more aggressive about blocking
        // and handoff.
        //
        // If we successfully wake the main app, we should kill the NSE mid-
        // transaction without acking to the service. This will roll back our
        // sessions to their prior state and the service will re-deliver
        // the encrypted message to the main app.
        //
        // We have to block on a semaphore because we don't want to continue
        // processing other messages and risk this transaction committing until
        // we know that the main app isn't going to be launched.
//      let payload = try CallMessageRelay.enqueueCallMessageForMainApp(
        let payload = CallMessageRelay.wakeMainAppPayload()

        // This semaphore should only be signalled if we failed to wake the main app.
        // If we successfully wake the main app, we should exit.
        let sema = DispatchSemaphore(value: 0)
        CXProvider.reportNewIncomingVoIPPushPayload(payload) { error in
            if let error = error {
                owsFailDebug("Failed to notify main app of call message: \(error)")
                sema.signal()
            } else {
                Logger.info("Successfully notified main app of call message. Quitting...")
                exit(0)
            }
        }
        if sema.wait(timeout: .now() + .seconds(15)) == .timedOut {
            owsFail("Timed out waiting for response from main app")
        }
    }

    public func receivedOffer(
        _ offer: SSKProtoCallMessageOffer,
        from caller: SignalServiceAddress,
        sourceDevice: UInt32,
        sentAtTimestamp: UInt64,
        serverReceivedTimestamp: UInt64,
        serverDeliveryTimestamp: UInt64,
        supportsMultiRing: Bool
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
        serverDeliveryTimestamp: UInt64
    ) {
        owsFailDebug("This should never be called, calls are handled externally")
    }

    public func receivedGroupCallUpdateMessage(
        _ update: SSKProtoDataMessageGroupCallUpdate,
        for groupThread: TSGroupThread,
        serverReceivedTimestamp: UInt64) {
            // TODO: Let's fix this soon, but for now let's just ignore to unblock iOS 15
            Logger.warn("Ignoring group call update message delivered to NSE")
    }
}
