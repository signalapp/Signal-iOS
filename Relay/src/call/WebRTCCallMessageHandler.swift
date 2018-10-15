//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

import Foundation
import RelayServiceKit
import RelayMessaging

@objc(OWSWebRTCCallMessageHandler)
public class WebRTCCallMessageHandler: NSObject, OWSCallMessageHandler {

    // MARK - Properties

    let TAG = "[WebRTCCallMessageHandler]"

    // MARK: Dependencies

    let accountManager: AccountManager
    let callService: CallService
    let messageSender: MessageSender

    // MARK: Initializers

    @objc public required init(accountManager: AccountManager, callService: CallService, messageSender: MessageSender) {
        self.accountManager = accountManager
        self.callService = callService
        self.messageSender = messageSender

        super.init()

        SwiftSingletons.register(self)
    }

    // MARK: - Call Handlers
    public func receivedOffer(withThreadId threadId: String, peerId: String, sessionDescription: String) {
        SwiftAssertIsOnMainThread(#function)
        
        let thread = TSThread.getOrCreateThread(withId: threadId)
        
        self.callService.handleReceivedOffer(thread: thread, peerId: peerId, sessionDescription: sessionDescription)
    }
    
//    public func receivedOffer(_ offer: OWSSignalServiceProtosCallMessageOffer, from callerId: String) {
//        SwiftAssertIsOnMainThread(#function)
//        guard offer.hasId() else {
//            owsFail("no callId in \(#function)")
//            return
//        }
//
//        let thread = TSThread.getOrCreateThread(withId: callerId)
//        self.callService.handleReceivedOffer(thread: thread, peerId: "\(offer.id)", sessionDescription: offer.sessionDescription)
//    }

    public func receivedAnswer(_ answer: OWSSignalServiceProtosCallMessageAnswer, from callerId: String) {
        SwiftAssertIsOnMainThread(#function)
        guard answer.hasId() else {
            owsFail("no callId in \(#function)")
            return
        }

        let thread = TSThread.getOrCreateThread(withId: callerId)
        self.callService.handleReceivedAnswer(thread: thread, peerId: "\(answer.id)", sessionDescription: answer.sessionDescription)
    }
    
    public func receivedIceUpdate(withThreadId threadId: String, sessionDescription sdp: String, sdpMid: String, sdpMLineIndex: Int32) {
        SwiftAssertIsOnMainThread(#function)

        let thread = TSThread.getOrCreateThread(withId: threadId)

        // Need to untangle callId/peerId/threadId for calls
        self.callService.handleRemoteAddedIceCandidate(thread: thread, peerId: threadId, sdp: sdp, lineIndex: sdpMLineIndex, mid: sdpMid)
    }
    
//    public func receivedIceUpdate(_ iceUpdate: OWSSignalServiceProtosCallMessageIceUpdate, from callerId: String) {
//        SwiftAssertIsOnMainThread(#function)
//        guard iceUpdate.hasId() else {
//            owsFail("no callId in \(#function)")
//            return
//        }
//
//        let thread = TSThread.getOrCreateThread(withId: callerId)
//
//        // Discrepency between our protobuf's sdpMlineIndex, which is unsigned,
//        // while the RTC iOS API requires a signed int.
//        let lineIndex = Int32(iceUpdate.sdpMlineIndex)
//
//        self.callService.handleRemoteAddedIceCandidate(thread: thread, callId: iceUpdate.id, sdp: iceUpdate.sdp, lineIndex: lineIndex, mid: iceUpdate.sdpMid)
//    }

    public func receivedHangup(_ hangup: OWSSignalServiceProtosCallMessageHangup, from callerId: String) {
        SwiftAssertIsOnMainThread(#function)
        guard hangup.hasId() else {
            owsFail("no callId in \(#function)")
            return
        }

        let thread = TSThread.getOrCreateThread(withId: callerId)
        self.callService.handleRemoteHangup(thread: thread, peerId: "\(hangup.id)")
    }

    public func receivedBusy(_ busy: OWSSignalServiceProtosCallMessageBusy, from callerId: String) {
        SwiftAssertIsOnMainThread(#function)
        guard busy.hasId() else {
            owsFail("no callId in \(#function)")
            return
        }

        let thread = TSThread.getOrCreateThread(withId: callerId)
        self.callService.handleRemoteBusy(thread: thread, peerId: "\(busy.id)")
    }

}
