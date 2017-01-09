//  Created by Michael Kirk on 12/23/16.
//  Copyright © 2016 Open Whisper Systems. All rights reserved.

import Foundation
import UIKit
import CallKit
import AVFoundation

/**
 * Connects user interface to the CallService usin CallKit.
 *
 * User interface is mapped to CXCall action requests, and if the CXProvider accepts them,
 * their corresponding consequences are requested via the CallService
 */
@available(iOS 10.0, *)
final class CallKitCallUIAdaptee: NSObject, CallUIAdaptee, CXProviderDelegate {

    let TAG = "[CallKitCallUIAdaptee]"

    private let callManager: CallKitCallManager
    private let callService: CallService
    internal let notificationsAdapter: CallNotificationsAdapter
    private let provider: CXProvider

    /// The app's provider configuration, representing its CallKit capabilities
    static var providerConfiguration: CXProviderConfiguration {
        let localizedName = NSLocalizedString("APPLICATION_NAME", comment: "Name of application")
        let providerConfiguration = CXProviderConfiguration(localizedName: localizedName)

        providerConfiguration.supportsVideo = true

        providerConfiguration.maximumCallsPerCallGroup = 1

        providerConfiguration.supportedHandleTypes = [.phoneNumber]

        if let iconMaskImage = UIImage(named: "IconMask") {
            providerConfiguration.iconTemplateImageData = UIImagePNGRepresentation(iconMaskImage)
        }

        providerConfiguration.ringtoneSound = "r.caf"

        return providerConfiguration
    }

    init(callService: CallService,  notificationsAdapter: CallNotificationsAdapter) {
        self.callManager = CallKitCallManager()
        self.callService = callService
        self.notificationsAdapter = notificationsAdapter
        self.provider = CXProvider(configuration: type(of: self).providerConfiguration)

        super.init()

        self.provider.setDelegate(self, queue: nil)
    }

    // MARK: CallUIAdaptee

    internal func startOutgoingCall(_ call: SignalCall) {
        // Add the new outgoing call to the app's list of calls.
        // So we can find it in the provider delegate callbacks.
        callManager.addCall(call)
        callManager.startCall(call)
    }

    internal func reportIncomingCall(_ call: SignalCall, callerName: String) {
        // Construct a CXCallUpdate describing the incoming call, including the caller.
        let update = CXCallUpdate()
        update.remoteHandle = CXHandle(type: .phoneNumber, value: call.remotePhoneNumber)
        update.hasVideo = call.hasVideo

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

    internal func answerCall(_ call: SignalCall) {
        showCall(call)
    }

    internal func declineCall(_ call: SignalCall) {
        callManager.end(call: call)
    }

    internal func endCall(_ call: SignalCall) {
        callManager.end(call: call)
    }

    internal func toggleMute(call: SignalCall, isMuted: Bool) {
        callManager.toggleMute(call: call, isMuted: isMuted)
    }

    // MARK: CXProviderDelegate

    func providerDidReset(_ provider: CXProvider) {
        Logger.debug("\(TAG) in \(#function)")

        // TODO
        // copied from Speakerbox, but is there a corallary with peerconnection, since peer connection starts the audio
        // session when adding an audiotrack
//        stopAudio()

        /*
         End any ongoing calls if the provider resets, and remove them from the app's list of calls,
         since they are no longer valid.
         */
        // This is a little goofy because CallKit assumes multiple calls (maybe some are held, or group calls?)
        // but CallService currently just has one call at a time.
        for call in callManager.calls {
            callService.handleFailedCall(error: .providerReset)
        }

        // Remove all calls from the app's list of calls.
        callManager.removeAllCalls()
    }

    func provider(_ provider: CXProvider, perform action: CXStartCallAction) {
        Logger.debug("\(TAG) in \(#function) CXStartCallAction")

        /*
         Configure the audio session, but do not start call audio here, since it must be done once
         the audio session has been activated by the system after having its priority elevated.
         */
        // TODO
        // copied from Speakerbox, but is there a corallary with peerconnection, since peer connection starts the audio
        // session when adding an audiotrack
        //configureAudioSession()

        // TODO does this work when `action.handle.value` is not in e164 format, e.g. if called via intent?
        guard let call = callManager.callWithLocalId(action.callUUID) else {
            Logger.error("\(TAG) unable to find call in \(#function)")
            return
        }

        CallService.signalingQueue.async {
            self.callService.handleOutgoingCall(call).then {
                action.fulfill()
                }.catch { error in
                    self.callManager.removeCall(call)
                    action.fail()
            }
        }

        // TODO FIXME
        //        /*
        //            Set callback blocks for significant events in the call's lifecycle, so that the CXProvider may be updated
        //            to reflect the updated state.
        //         */
        //        call.hasStartedConnectingDidChange = { [weak self] in
        //            self?.provider.reportOutgoingCall(with: call.uuid, startedConnectingAt: call.connectingDate)
        //        }
        //        call.hasConnectedDidChange = { [weak self] in
        //            self?.provider.reportOutgoingCall(with: call.uuid, connectedAt: call.connectDate)
        //        }

    }

    func provider(_ provider: CXProvider, perform action: CXAnswerCallAction) {
        Logger.debug("\(TAG) Received \(#function) CXAnswerCallAction")
        // Retrieve the SpeakerboxCall instance corresponding to the action's call UUID
        guard let call = callManager.callWithLocalId(action.callUUID) else {
            action.fail()
            return
        }

        //         Original Speakerbox implementation
        //        /*
        //            Configure the audio session, but do not start call audio here, since it must be done once
        //            the audio session has been activated by the system after having its priority elevated.
        //         */
        //        configureAudioSession()
        //
        //        // Trigger the call to be answered via the underlying network service.
        //        call.answerSpeakerboxCall()

        // Synchronous to ensure work is done before call is displayed as "answered"
        CallService.signalingQueue.sync {
            self.callService.handleAnswerCall(call)
        }

        // Signal to the system that the action has been successfully performed.
        action.fulfill()
    }

    public func provider(_ provider: CXProvider, perform action: CXEndCallAction) {
        Logger.debug("\(TAG) Received \(#function) CXEndCallAction")
        guard let call = callManager.callWithLocalId(action.callUUID) else {
            action.fail()
            return
        }

        // Original Speakerbox implementation
        //        // Stop call audio whenever ending the call.
        //        stopAudio()
        //        // Trigger the call to be ended via the underlying network service.
        //        call.endSpeakerboxCall()

        // Synchronous to ensure call is terminated before call is displayed as "ended"
        CallService.signalingQueue.sync {
            self.callService.handleLocalHungupCall(call)
        }

        // Signal to the system that the action has been successfully performed.
        action.fulfill()

        // Remove the ended call from the app's list of calls.
        callManager.removeCall(call)
    }

    public func provider(_ provider: CXProvider, perform action: CXSetHeldCallAction) {
        Logger.debug("\(TAG) Received \(#function) CXSetHeldCallAction")
        guard let call = callManager.callWithLocalId(action.callUUID) else {
            action.fail()
            return
        }
        Logger.warn("TODO, unimplemented set held call: \(call)")

        // TODO FIXME
        //        // Update the SpeakerboxCall's underlying hold state.
        //        call.isOnHold = action.isOnHold
        //
        //        // Stop or start audio in response to holding or unholding the call.
        //        if call.isOnHold {
        //            stopAudio()
        //        } else {
        //            startAudio()
        //        }

        // Signal to the system that the action has been successfully performed.
        action.fulfill()
    }

    public func provider(_ provider: CXProvider, perform action: CXSetMutedCallAction) {
        Logger.debug("\(TAG) Received \(#function) CXSetMutedCallAction")
        guard callManager.callWithLocalId(action.callUUID) != nil else {
            Logger.error("\(TAG) Failing CXSetMutedCallAction for unknown call: \(action.callUUID)")
            action.fail()
            return
        }

        CallService.signalingQueue.async {
            self.callService.handleToggledMute(isMuted: action.isMuted)
            action.fulfill()
        }
    }

    public func provider(_ provider: CXProvider, perform action: CXSetGroupCallAction) {
        Logger.warn("\(TAG) unimplemented \(#function) for CXSetGroupCallAction")
    }

    public func provider(_ provider: CXProvider, perform action: CXPlayDTMFCallAction) {
        Logger.warn("\(TAG) unimplemented \(#function) for CXPlayDTMFCallAction")
    }

    func provider(_ provider: CXProvider, timedOutPerforming action: CXAction) {
        Logger.debug("\(TAG) Timed out \(#function)")

        // React to the action timeout if necessary, such as showing an error UI.
    }

    func provider(_ provider: CXProvider, didActivate audioSession: AVAudioSession) {
        Logger.debug("\(TAG) Received \(#function)")

        // TODO 
        // copied from Speakerbox, but is there a corallary with peerconnection, since peer connection starts the audio
        // session when adding an audiotrack
        // startAudio()
    }

    func provider(_ provider: CXProvider, didDeactivate audioSession: AVAudioSession) {
        Logger.debug("\(TAG) Received \(#function)")

        /*
         Restart any non-call related audio now that the app's audio session has been
         de-activated after having its priority restored to normal.
         */
    }
}
