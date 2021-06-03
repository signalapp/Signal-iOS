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

    public func externallyHandleCallMessage(
        envelope: SSKProtoEnvelope,
        serverDeliveryTimestamp: UInt64
    ) -> Bool {
        do {
            let payload = try CallMessageRelay.voipPayload(
                envelope: envelope,
                serverDeliveryTimestamp: serverDeliveryTimestamp
            )
            CXProvider.reportNewIncomingVoIPPushPayload(payload) { error in
                if let error = error {
                    owsFailDebug("Failed to notify main app of call message: \(error)")
                } else {
                    Logger.info("Successfully notified main app of call message")
                }
            }
        } catch {
            owsFailDebug("Failed to create relay voip payload for call message \(error)")
        }

        return true
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
        owsFailDebug("This should never be called, calls are handled externally")
    }
}
