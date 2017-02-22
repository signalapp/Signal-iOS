//
//  Copyright (c) 2017 Open Whisper Systems. All rights reserved.
//

import Foundation
import UIKit
import CallKit
import AVFoundation

/**
 * Connects user interface to the CallService using CallKit.
 *
 * User interface is routed to the CallManager which requests CXCallActions, and if the CXProvider accepts them,
 * their corresponding consequences are implmented in the CXProviderDelegate methods, e.g. using the CallService
 */
@available(iOS 10.0, *)
final class CallKitCallUIAdaptee: NSObject, CallUIAdaptee, CXProviderDelegate {

    let TAG = "[CallKitCallUIAdaptee]"

    private let callManager: CallKitCallManager
    internal let callService: CallService
    internal let notificationsAdapter: CallNotificationsAdapter
    private let provider: CXProvider

    // CallKit handles incoming ringer stop/start for us. Yay!
    let hasManualRinger = false

    // The app's provider configuration, representing its CallKit capabilities
    static var providerConfiguration: CXProviderConfiguration {
        let localizedName = NSLocalizedString("APPLICATION_NAME", comment: "Name of application")
        let providerConfiguration = CXProviderConfiguration(localizedName: localizedName)

        providerConfiguration.supportsVideo = true

        providerConfiguration.maximumCallGroups = 1

        providerConfiguration.maximumCallsPerCallGroup = 1

        providerConfiguration.supportedHandleTypes = [.phoneNumber, .generic]

        if let iconMaskImage = UIImage(named: "IconMask") {
            providerConfiguration.iconTemplateImageData = UIImagePNGRepresentation(iconMaskImage)
        }

        providerConfiguration.ringtoneSound = "r.caf"

        return providerConfiguration
    }

    init(callService: CallService, notificationsAdapter: CallNotificationsAdapter) {
        AssertIsOnMainThread()

        Logger.debug("\(self.TAG) \(#function)")

        self.callManager = CallKitCallManager()
        self.callService = callService
        self.notificationsAdapter = notificationsAdapter
        self.provider = CXProvider(configuration: type(of: self).providerConfiguration)

        super.init()

        self.provider.setDelegate(self, queue: nil)
    }

    // MARK: CallUIAdaptee

    func startOutgoingCall(handle: String) -> SignalCall {
        AssertIsOnMainThread()
        Logger.debug("\(self.TAG) \(#function)")

        let call = SignalCall.outgoingCall(localId: UUID(), remotePhoneNumber: handle)

        // Add the new outgoing call to the app's list of calls.
        // So we can find it in the provider delegate callbacks.
        callManager.addCall(call)
        callManager.startCall(call)

        return call
    }

    // Called from CallService after call has ended to clean up any remaining CallKit call state.
    func failCall(_ call: SignalCall, error: CallError) {
        AssertIsOnMainThread()
        Logger.debug("\(self.TAG) \(#function)")

        switch error {
        case .timeout(description: _):
            provider.reportCall(with: call.localId, endedAt: Date(), reason: CXCallEndedReason.unanswered)
        default:
            provider.reportCall(with: call.localId, endedAt: Date(), reason: CXCallEndedReason.failed)
        }

        self.callManager.removeCall(call)
    }

    func reportIncomingCall(_ call: SignalCall, callerName: String) {
        AssertIsOnMainThread()
        Logger.debug("\(self.TAG) \(#function)")

        // Construct a CXCallUpdate describing the incoming call, including the caller.
        let update = CXCallUpdate()
        update.remoteHandle = (Environment.getCurrent().preferences.isCallKitPrivacyEnabled()
            ? CXHandle(type: .generic, value: CallKitCallManager.kAnonymousCallHandlePrefix + call.localId.uuidString)
            : CXHandle(type: .phoneNumber, value: call.remotePhoneNumber))
        update.hasVideo = call.hasLocalVideo
        // Update the name used in the CallKit UI for incoming calls.
        update.localizedCallerName = NSLocalizedString("CALLKIT_ANONYMOUS_CONTACT_NAME", comment: "The generic name used for calls if CallKit privacy is enabled")
        disableUnsupportedFeatures(callUpdate: update)

        // Report the incoming call to the system
        provider.reportNewIncomingCall(with: call.localId, update: update) { error in
            /*
             Only add incoming call to the app's list of calls if the call was allowed (i.e. there was no error)
             since calls may be "denied" for various legitimate reasons. See CXErrorCodeIncomingCallError.
             */
            guard error == nil else {
                Logger.error("\(self.TAG) failed to report new incoming call")
                return
            }

            self.callManager.addCall(call)
        }
    }

    func answerCall(localId: UUID) {
        AssertIsOnMainThread()
        Logger.debug("\(self.TAG) \(#function)")

        assertionFailure("CallKit should answer calls via system call screen, not via notifications.")
    }

    func answerCall(_ call: SignalCall) {
        AssertIsOnMainThread()
        Logger.debug("\(self.TAG) \(#function)")

        callManager.answer(call: call)
    }

    func declineCall(localId: UUID) {
        AssertIsOnMainThread()
        Logger.debug("\(self.TAG) \(#function)")

        assertionFailure("CallKit should decline calls via system call screen, not via notifications.")
    }

    func declineCall(_ call: SignalCall) {
        AssertIsOnMainThread()
        Logger.debug("\(self.TAG) \(#function)")

        callManager.localHangup(call: call)
    }

    func recipientAcceptedCall(_ call: SignalCall) {
        AssertIsOnMainThread()
        Logger.debug("\(self.TAG) \(#function)")

        self.provider.reportOutgoingCall(with: call.localId, connectedAt: nil)

        let update = CXCallUpdate()
        disableUnsupportedFeatures(callUpdate: update)

        provider.reportCall(with: call.localId, updated: update)
    }

    func localHangupCall(_ call: SignalCall) {
        AssertIsOnMainThread()
        Logger.debug("\(self.TAG) \(#function)")

        callManager.localHangup(call: call)
    }

    func remoteDidHangupCall(_ call: SignalCall) {
        AssertIsOnMainThread()
        Logger.debug("\(self.TAG) \(#function)")

        provider.reportCall(with: call.localId, endedAt: nil, reason: CXCallEndedReason.remoteEnded)
    }

    func remoteBusy(_ call: SignalCall) {
        AssertIsOnMainThread()
        Logger.debug("\(self.TAG) \(#function)")

        provider.reportCall(with: call.localId, endedAt: nil, reason: CXCallEndedReason.unanswered)
    }

    func setIsMuted(call: SignalCall, isMuted: Bool) {
        AssertIsOnMainThread()
        Logger.debug("\(self.TAG) \(#function)")

        callManager.setIsMuted(call: call, isMuted: isMuted)
    }

    func setHasLocalVideo(call: SignalCall, hasLocalVideo: Bool) {
        AssertIsOnMainThread()
        Logger.debug("\(self.TAG) \(#function)")

        let update = CXCallUpdate()
        update.hasVideo = hasLocalVideo

        // Update the CallKit UI.
        provider.reportCall(with: call.localId, updated: update)

        self.callService.setHasLocalVideo(hasLocalVideo: hasLocalVideo)
    }

    // MARK: CXProviderDelegate

    func providerDidReset(_ provider: CXProvider) {
        AssertIsOnMainThread()
        Logger.debug("\(self.TAG) \(#function)")

        // Stop any in-progress WebRTC related audio.
        PeerConnectionClient.stopAudioSession()

        // End any ongoing calls if the provider resets, and remove them from the app's list of calls,
        // since they are no longer valid.
        callService.handleFailedCall(error: .providerReset)

        // Remove all calls from the app's list of calls.
        callManager.removeAllCalls()
    }

    func provider(_ provider: CXProvider, perform action: CXStartCallAction) {
        AssertIsOnMainThread()

        Logger.debug("\(TAG) in \(#function) CXStartCallAction")

        guard let call = callManager.callWithLocalId(action.callUUID) else {
            Logger.error("\(TAG) unable to find call in \(#function)")
            return
        }

        // We can't wait for long before fulfilling the CXAction, else CallKit will show a "Failed Call". We don't 
        // actually need to wait for the outcome of the handleOutgoingCall promise, because it handles any errors by 
        // manually failing the call.
        _ = self.callService.handleOutgoingCall(call)
        action.fulfill()
        self.provider.reportOutgoingCall(with: call.localId, startedConnectingAt: nil)
        
        ensureCallName(call:call)
    }

    func ensureCallName(call : SignalCall) {
        guard Environment.getCurrent().preferences.isCallKitPrivacyEnabled() else {
            return;
        }
        
        // Update the name used in the CallKit UI for outgoing calls.
        let update = CXCallUpdate()
        update.localizedCallerName = NSLocalizedString("CALLKIT_ANONYMOUS_CONTACT_NAME", comment: "The generic name used for calls if CallKit privacy is enabled")
        provider.reportCall(with: call.localId, updated: update)
    }

    func provider(_ provider: CXProvider, perform action: CXAnswerCallAction) {
        AssertIsOnMainThread()

        Logger.debug("\(TAG) Received \(#function) CXAnswerCallAction")
        // Retrieve the instance corresponding to the action's call UUID
        guard let call = callManager.callWithLocalId(action.callUUID) else {
            action.fail()
            return
        }

        self.callService.handleAnswerCall(call)
        self.showCall(call)
        action.fulfill()
    }

    public func provider(_ provider: CXProvider, perform action: CXEndCallAction) {
        AssertIsOnMainThread()

        Logger.debug("\(TAG) Received \(#function) CXEndCallAction")
        guard let call = callManager.callWithLocalId(action.callUUID) else {
            action.fail()
            return
        }

        self.callService.handleLocalHungupCall(call)

        // Signal to the system that the action has been successfully performed.
        action.fulfill()

        // Remove the ended call from the app's list of calls.
        self.callManager.removeCall(call)
    }

    public func provider(_ provider: CXProvider, perform action: CXSetHeldCallAction) {
        AssertIsOnMainThread()

        Logger.debug("\(TAG) Received \(#function) CXSetHeldCallAction")
        guard let call = callManager.callWithLocalId(action.callUUID) else {
            action.fail()
            return
        }

        // Update the SignalCall's underlying hold state.
        call.isOnHold = action.isOnHold

        // Stop or start audio in response to holding or unholding the call.
        if call.isOnHold {
            // stopAudio() <-- SpeakerBox
            PeerConnectionClient.stopAudioSession()
        } else {
            // startAudio() <-- SpeakerBox
            // This is redundant with what happens in `provider(_:didActivate:)`
            //PeerConnectionClient.startAudioSession()
        }

        // Signal to the system that the action has been successfully performed.
        action.fulfill()
    }

    public func provider(_ provider: CXProvider, perform action: CXSetMutedCallAction) {
        AssertIsOnMainThread()

        Logger.debug("\(TAG) Received \(#function) CXSetMutedCallAction")
        guard callManager.callWithLocalId(action.callUUID) != nil else {
            Logger.error("\(TAG) Failing CXSetMutedCallAction for unknown call: \(action.callUUID)")
            action.fail()
            return
        }

        self.callService.setIsMuted(isMuted: action.isMuted)
        action.fulfill()
    }

    public func provider(_ provider: CXProvider, perform action: CXSetGroupCallAction) {
        AssertIsOnMainThread()

        Logger.warn("\(TAG) unimplemented \(#function) for CXSetGroupCallAction")
    }

    public func provider(_ provider: CXProvider, perform action: CXPlayDTMFCallAction) {
        AssertIsOnMainThread()

        Logger.warn("\(TAG) unimplemented \(#function) for CXPlayDTMFCallAction")
    }

    func provider(_ provider: CXProvider, timedOutPerforming action: CXAction) {
        AssertIsOnMainThread()

        Logger.debug("\(TAG) Timed out \(#function)")

        // React to the action timeout if necessary, such as showing an error UI.
    }

    func provider(_ provider: CXProvider, didActivate audioSession: AVAudioSession) {
        AssertIsOnMainThread()

        Logger.debug("\(TAG) Received \(#function)")

        // Start recording
        PeerConnectionClient.startAudioSession()
    }

    func provider(_ provider: CXProvider, didDeactivate audioSession: AVAudioSession) {
        AssertIsOnMainThread()

        Logger.debug("\(TAG) Received \(#function)")

        /*
         Restart any non-call related audio now that the app's audio session has been
         de-activated after having its priority restored to normal.
         */
    }

    // MARK: - Util

    private func disableUnsupportedFeatures(callUpdate: CXCallUpdate) {
        // Call Holding is failing to restart audio when "swapping" calls on the CallKit screen
        // until user returns to in-app call screen.
        callUpdate.supportsHolding = false

        // Not yet supported
        callUpdate.supportsGrouping = false
        callUpdate.supportsUngrouping = false

        // Is there any reason to support this?
        callUpdate.supportsDTMF = false
    }
}
