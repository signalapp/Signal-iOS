//
//  Copyright (c) 2017 Open Whisper Systems. All rights reserved.
//

import Foundation
import PromiseKit
import CallKit

protocol CallUIAdaptee {
    var notificationsAdapter: CallNotificationsAdapter { get }

    func startOutgoingCall(_ call: SignalCall)
    func reportIncomingCall(_ call: SignalCall, callerName: String)
    func reportMissedCall(_ call: SignalCall, callerName: String)
    func answerCall(_ call: SignalCall)
    func declineCall(_ call: SignalCall)
    func recipientAcceptedCall(_ call: SignalCall)
    func endCall(_ call: SignalCall)
    func setIsMuted(call: SignalCall, isMuted: Bool)
    func setHasVideo(call: SignalCall, hasVideo: Bool)
}

// Shared default implementations
extension CallUIAdaptee {
    internal func showCall(_ call: SignalCall) {
        let callNotificationName = CallService.callServiceActiveCallNotificationName()
        NotificationCenter.default.post(name: NSNotification.Name(rawValue: callNotificationName), object: call)
    }

    internal func reportMissedCall(_ call: SignalCall, callerName: String) {
        notificationsAdapter.presentMissedCall(call, callerName: callerName)
    }
}

/**
 * Notify the user of call related activities.
 * Driven by either a CallKit or System notifications adaptee
 */
class CallUIAdapter {

    let TAG = "[CallUIAdapter]"
    private let adaptee: CallUIAdaptee
    private let contactsManager: OWSContactsManager

    required init(callService: CallService, contactsManager: OWSContactsManager, notificationsAdapter: CallNotificationsAdapter) {
        self.contactsManager = contactsManager
        if Platform.isSimulator {
            // CallKit doesn't seem entirely supported in simulator.
            // e.g. you can't receive calls in the call screen.
            // So we use the non-CallKit call UI.
            Logger.info("\(TAG) choosing non-callkit adaptee for simulator.")
            adaptee = NonCallKitCallUIAdaptee(callService: callService, notificationsAdapter: notificationsAdapter)
        } else if #available(iOS 10.0, *) {
            Logger.info("\(TAG) choosing callkit adaptee for iOS10+")
            adaptee = CallKitCallUIAdaptee(callService: callService, notificationsAdapter: notificationsAdapter)
        } else {
            Logger.info("\(TAG) choosing non-callkit adaptee for older iOS")
            adaptee = NonCallKitCallUIAdaptee(callService: callService, notificationsAdapter: notificationsAdapter)
        }
    }

    internal func reportIncomingCall(_ call: SignalCall, thread: TSContactThread) {
        let callerName = self.contactsManager.displayName(forPhoneIdentifier: call.remotePhoneNumber)
        adaptee.reportIncomingCall(call, callerName: callerName)
    }

    internal func reportMissedCall(_ call: SignalCall) {
        let callerName = self.contactsManager.displayName(forPhoneIdentifier: call.remotePhoneNumber)
        adaptee.reportMissedCall(call, callerName: callerName)
    }

    internal func startOutgoingCall(handle: String) -> SignalCall {
        let call = SignalCall.outgoingCall(localId: UUID(), remotePhoneNumber: handle)
        adaptee.startOutgoingCall(call)
        return call
    }

    internal func answerCall(_ call: SignalCall) {
        adaptee.answerCall(call)
    }

    internal func declineCall(_ call: SignalCall) {
        adaptee.declineCall(call)
    }

    internal func recipientAcceptedCall(_ call: SignalCall) {
        adaptee.recipientAcceptedCall(call)
    }

    internal func endCall(_ call: SignalCall) {
        adaptee.endCall(call)
    }

    internal func showCall(_ call: SignalCall) {
        adaptee.showCall(call)
    }

    internal func setIsMuted(call: SignalCall, isMuted: Bool) {
        adaptee.setIsMuted(call: call, isMuted: isMuted)
    }

    internal func setHasVideo(call: SignalCall, hasVideo: Bool) {
        adaptee.setHasVideo(call: call, hasVideo: hasVideo)
    }
}
