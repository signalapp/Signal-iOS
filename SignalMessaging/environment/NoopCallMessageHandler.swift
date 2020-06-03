//
//  Copyright (c) 2020 Open Whisper Systems. All rights reserved.
//

import SignalServiceKit

@objc
public class NoopCallMessageHandler: NSObject, OWSCallMessageHandler {

    public func receivedOffer(_ offer: SSKProtoCallMessageOffer, from caller: SignalServiceAddress, sourceDevice device: UInt32, sentAtTimestamp: UInt64, supportsMultiRing: Bool) {
        owsFailDebug("")
    }

    public func receivedAnswer(_ answer: SSKProtoCallMessageAnswer, from caller: SignalServiceAddress, sourceDevice device: UInt32, supportsMultiRing: Bool) {
        owsFailDebug("")
    }

    public func receivedIceUpdate(_ iceUpdate: [SSKProtoCallMessageIceUpdate], from caller: SignalServiceAddress, sourceDevice device: UInt32) {
        owsFailDebug("")
    }

    public func receivedHangup(_ hangup: SSKProtoCallMessageHangup, from caller: SignalServiceAddress, sourceDevice device: UInt32) {
        owsFailDebug("")
    }

    public func receivedBusy(_ busy: SSKProtoCallMessageBusy, from caller: SignalServiceAddress, sourceDevice device: UInt32) {
        owsFailDebug("")
    }
}
