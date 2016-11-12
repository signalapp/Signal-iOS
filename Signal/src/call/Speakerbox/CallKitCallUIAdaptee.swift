//  Created by Michael Kirk on 1/3/17.
//  Copyright © 2017 Open Whisper Systems. All rights reserved.

import Foundation

@available(iOS 10.0, *)
class CallKitCallUIAdaptee: CallUIAdaptee {

    let TAG = "[CallKitCallUIAdaptee]"
    let providerDelegate: CallKitProviderDelegate
    let callManager: CallKitCallManager
    let notificationsAdapter: CallNotificationsAdapter

    init(callService: CallService, notificationsAdapter: CallNotificationsAdapter) {
        self.callManager = CallKitCallManager()
        self.providerDelegate = CallKitProviderDelegate(callManager: callManager, callService: callService)
        self.notificationsAdapter = notificationsAdapter
    }

    public func startOutgoingCall(_ call: SignalCall) {
        // Add the new outgoing call to the app's list of calls.
        // So we can find it in the provider delegate callbacks.
        self.callManager.addCall(call)
        providerDelegate.callManager.startCall(call)
    }

    public func reportIncomingCall(_ call: SignalCall, callerName: String, audioManager: SignalCallAudioManager) {
        // FIXME weird to pass the audio manager in here.
        // Crux is, the peerconnectionclient is what controls the audio channel.
        // But a peerconnectionclient is per call.
        // While this providerDelegate is an app singleton.
        providerDelegate.audioManager = audioManager

        providerDelegate.reportIncomingCall(call) { error in
            if error == nil {
                Logger.debug("\(self.TAG) successfully reported incoming call.")
            } else {
                Logger.error("\(self.TAG) providerDelegate.reportIncomingCall failed with error: \(error)")
            }
        }
    }

    public func reportMissedCall(_ call: SignalCall, callerName: String) {
        notificationsAdapter.presentMissedCall(call, callerName: callerName)
    }

    func answerCall(_ call: SignalCall) {
        showCall(call)
    }

    public func declineCall(_ call: SignalCall) {
        callManager.end(call: call)
    }

    func endCall(_ call: SignalCall) {
        callManager.end(call: call)
    }
}
