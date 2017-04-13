//
//  Copyright (c) 2017 Open Whisper Systems. All rights reserved.
//

import Foundation

@objc(OWSWebRTCCallMessageHandler)
class WebRTCCallMessageHandler: NSObject, OWSCallMessageHandler {

    // MARK - Properties

    let TAG = "[WebRTCCallMessageHandler]"

    // MARK: Dependencies

    let accountManager: AccountManager
    let callService: CallService
    let messageSender: MessageSender

    // MARK: Initializers

    required init(accountManager: AccountManager, callService: CallService, messageSender: MessageSender) {
        self.accountManager = accountManager
        self.callService = callService
        self.messageSender = messageSender
    }

    // MARK: - Call Handlers

    public func receivedOffer(_ offer: OWSSignalServiceProtosCallMessageOffer, from callerId: String) {
        AssertIsOnMainThread()
        Logger.verbose("\(TAG) handling offer from caller:\(callerId)")

        let thread = TSContactThread.getOrCreateThread(contactId: callerId)
        self.callService.handleReceivedOffer(thread: thread, callId: offer.id, sessionDescription: offer.description)
    }

    public func receivedAnswer(_ answer: OWSSignalServiceProtosCallMessageAnswer, from callerId: String) {
        AssertIsOnMainThread()
        Logger.verbose("\(TAG) handling answer from caller:\(callerId)")

        let thread = TSContactThread.getOrCreateThread(contactId: callerId)
        self.callService.handleReceivedAnswer(thread: thread, callId: answer.id, sessionDescription: answer.description)
    }

    public func receivedIceUpdate(_ iceUpdate: OWSSignalServiceProtosCallMessageIceUpdate, from callerId: String) {
        AssertIsOnMainThread()
        Logger.verbose("\(TAG) handling iceUpdates from caller:\(callerId)")

        let thread = TSContactThread.getOrCreateThread(contactId: callerId)

        // Discrepency between our protobuf's sdpMlineIndex, which is unsigned, 
        // while the RTC iOS API requires a signed int.
        let lineIndex = Int32(iceUpdate.sdpMlineIndex)

        self.callService.handleRemoteAddedIceCandidate(thread: thread, callId: iceUpdate.id, sdp: iceUpdate.sdp, lineIndex: lineIndex, mid: iceUpdate.sdpMid)
    }

    public func receivedHangup(_ hangup: OWSSignalServiceProtosCallMessageHangup, from callerId: String) {
        AssertIsOnMainThread()
        Logger.verbose("\(TAG) handling 'hangup' from caller:\(callerId)")

        let thread = TSContactThread.getOrCreateThread(contactId: callerId)

        self.callService.handleRemoteHangup(thread: thread)
    }

    public func receivedBusy(_ busy: OWSSignalServiceProtosCallMessageBusy, from callerId: String) {
        AssertIsOnMainThread()
        Logger.verbose("\(TAG) handling 'busy' from caller:\(callerId)")

        let thread = TSContactThread.getOrCreateThread(contactId: callerId)

        self.callService.handleRemoteBusy(thread: thread)
    }

}
