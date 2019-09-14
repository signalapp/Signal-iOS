//
//  Copyright (c) 2019 Open Whisper Systems. All rights reserved.
//

import SignalServiceKit

@objc
public class NoopCallMessageHandler: NSObject, OWSCallMessageHandler {

    public func receivedOffer(_ offer: SSKProtoCallMessageOffer, from caller: SignalServiceAddress) {
        owsFailDebug("")
    }

    public func receivedAnswer(_ answer: SSKProtoCallMessageAnswer, from caller: SignalServiceAddress) {
        owsFailDebug("")
    }

    public func receivedIceUpdate(_ iceUpdate: SSKProtoCallMessageIceUpdate, from caller: SignalServiceAddress) {
        owsFailDebug("")
    }

    public func receivedHangup(_ hangup: SSKProtoCallMessageHangup, from caller: SignalServiceAddress) {
        owsFailDebug("")
    }

    public func receivedBusy(_ busy: SSKProtoCallMessageBusy, from caller: SignalServiceAddress) {
        owsFailDebug("")
    }
}
