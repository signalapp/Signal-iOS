//  Created by Michael Kirk on 12/13/16.
//  Copyright © 2016 Open Whisper Systems. All rights reserved.

import Foundation
import PromiseKit
import CallKit

protocol CallUIAdaptee {
    func startOutgoingCall(_ call: SignalCall)
    func reportIncomingCall(_ call: SignalCall, callerName: String, audioManager: SignalCallAudioManager)
    func reportMissedCall(_ call: SignalCall, callerName: String)
    func answerCall(_ call: SignalCall)
    func declineCall(_ call: SignalCall)
    func endCall(_ call: SignalCall)
}

extension CallUIAdaptee {
    public func showCall(_ call: SignalCall) {
        let callNotificationName = CallService.callServiceActiveCallNotificationName()
        NotificationCenter.default.post(name: NSNotification.Name(rawValue: callNotificationName), object: call)
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
            // Callkit doesn't seem entirely supported in simulator.
            // e.g. you can't receive calls in the call screen.
            // So we use the non-call kit call UI.
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

    public func reportIncomingCall(_ call: SignalCall, thread: TSContactThread, audioManager: SignalCallAudioManager) {
        let callerName = self.contactsManager.displayName(forPhoneIdentifier: call.remotePhoneNumber)
        adaptee.reportIncomingCall(call, callerName: callerName, audioManager: audioManager)
    }

    public func reportMissedCall(_ call: SignalCall) {
        let callerName = self.contactsManager.displayName(forPhoneIdentifier: call.remotePhoneNumber)
        adaptee.reportMissedCall(call, callerName: callerName)
    }

    public func startOutgoingCall(handle: String) -> SignalCall {
        let call = SignalCall.outgoingCall(localId: UUID(), remotePhoneNumber: handle)
        adaptee.startOutgoingCall(call)
        return call
    }

    public func answerCall(_ call: SignalCall) {
        adaptee.answerCall(call)
    }

    public func declineCall(_ call: SignalCall) {
        adaptee.declineCall(call)
    }

    public func endCall(_ call: SignalCall) {
        adaptee.endCall(call)
    }

    public func showCall(_ call: SignalCall) {
        adaptee.showCall(call)
    }
}

/**
 * FIXME TODO I actually don't yet understand the role of these CallAudioManager methods as
 * called in the speakerbox example. Are they redundant with what the RTC setup
 * already does for us?
 *
 * Here's the AVSessionConfig for the ARDRTC Example app, which maybe belongs
 * in the coonfigureAudio session. and maybe the adding audio tracks is sufficient for startAudio's implenetation?
 *
 *
 187   RTCAudioSessionConfiguration *configuration =
 188       [[RTCAudioSessionConfiguration alloc] init];
 189   configuration.category = AVAudioSessionCategoryAmbient;
 190   configuration.categoryOptions = AVAudioSessionCategoryOptionDuckOthers;
 191   configuration.mode = AVAudioSessionModeDefault;
 192
 193   RTCAudioSession *session = [RTCAudioSession sharedInstance];
 194   [session lockForConfiguration];
 195   BOOL hasSucceeded = NO;
 196   NSError *error = nil;
 197   if (session.isActive) {
 198     hasSucceeded = [session setConfiguration:configuration error:&error];
 199   } else {
 200     hasSucceeded = [session setConfiguration:configuration
 201                                       active:YES
 202                                        error:&error];
 203   }
 204   if (!hasSucceeded) {
 205     RTCLogError(@"Error setting configuration: %@", error.localizedDescription);
 206   }
 207   [session unlockForConfiguration];
 */
protocol SignalCallAudioManager {
    func startAudio()
    func stopAudio()
    func configureAudioSession()
}
