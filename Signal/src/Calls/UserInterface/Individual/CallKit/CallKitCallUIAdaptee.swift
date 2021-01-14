//
//  Copyright (c) 2020 Open Whisper Systems. All rights reserved.
//

import Foundation
import UIKit
import CallKit
import AVFoundation
import SignalServiceKit
import SignalMessaging

/**
 * Connects user interface to the CallService using CallKit.
 *
 * User interface is routed to the CallManager which requests CXCallActions, and if the CXProvider accepts them,
 * their corresponding consequences are implmented in the CXProviderDelegate methods, e.g. using the CallService
 */
final class CallKitCallUIAdaptee: NSObject, CallUIAdaptee, CXProviderDelegate {

    // MARK: - Dependencies

    private var contactsManager: OWSContactsManager {
        return Environment.shared.contactsManager
    }

    internal var notificationPresenter: NotificationPresenter {
        return AppEnvironment.shared.notificationPresenter
    }

    // MARK: -

    private let callManager: CallKitCallManager
    private let showNamesOnCallScreen: Bool
    private let provider: CXProvider
    private let audioActivity: AudioActivity

    // CallKit handles incoming ringer stop/start for us. Yay!
    let hasManualRinger = false

    // Instantiating more than one CXProvider can cause us to miss call transactions, so
    // we maintain the provider across Adaptees using a singleton pattern
    private static var _sharedProvider: CXProvider?
    class func sharedProvider(useSystemCallLog: Bool) -> CXProvider {
        let configuration = buildProviderConfiguration(useSystemCallLog: useSystemCallLog)

        if let sharedProvider = self._sharedProvider {
            sharedProvider.configuration = configuration
            return sharedProvider
        } else {
            SwiftSingletons.register(self)
            let provider = CXProvider(configuration: configuration)
            _sharedProvider = provider
            return provider
        }
    }

    // The app's provider configuration, representing its CallKit capabilities
    class func buildProviderConfiguration(useSystemCallLog: Bool) -> CXProviderConfiguration {
        let localizedName = NSLocalizedString("APPLICATION_NAME", comment: "Name of application")
        let providerConfiguration = CXProviderConfiguration(localizedName: localizedName)

        providerConfiguration.supportsVideo = true

        // Default maximumCallGroups is 2. We previously overrode this value to be 1.
        //
        // The terminology can be confusing. Even though we don't currently support "group calls"
        // *every* call is in a call group. Our call groups all just happen to be "groups" with 1
        // call in them.
        //
        // maximumCallGroups limits how many different calls CallKit can know about at one time.
        // Exceeding this limit will cause CallKit to error when reporting an additional call.
        //
        // Generally for us, the number of call groups is 1 or 0, *however* when handling a rapid
        // sequence of offers and hangups, due to the async nature of CXTransactions, there can
        // be a brief moment where the old limit of 1 caused CallKit to fail the newly reported
        // call, even though we were properly requesting hangup of the old call before reporting the
        // new incoming call.
        //
        // Specifically after 10 or so rapid fire call/hangup/call/hangup, eventually an incoming
        // call would fail to report due to CXErrorCodeRequestTransactionErrorMaximumCallGroupsReached
        //
        // ...so that's why we no longer use the non-default value of 1, which I assume was only ever
        // set to 1 out of confusion.
        // providerConfiguration.maximumCallGroups = 1

        providerConfiguration.maximumCallsPerCallGroup = 1

        providerConfiguration.supportedHandleTypes = [.phoneNumber, .generic]

        let iconMaskImage = #imageLiteral(resourceName: "signal-logo-128")
        providerConfiguration.iconTemplateImageData = iconMaskImage.pngData()

        // We don't set the ringtoneSound property, so that we use either the
        // default iOS ringtone OR the custom ringtone associated with this user's
        // system contact.
        providerConfiguration.includesCallsInRecents = useSystemCallLog

        return providerConfiguration
    }

    init(showNamesOnCallScreen: Bool, useSystemCallLog: Bool) {
        AssertIsOnMainThread()

        Logger.debug("")

        self.callManager = CallKitCallManager(showNamesOnCallScreen: showNamesOnCallScreen)

        self.provider = type(of: self).sharedProvider(useSystemCallLog: useSystemCallLog)

        self.audioActivity = AudioActivity(audioDescription: "[CallKitCallUIAdaptee]", behavior: .call)
        self.showNamesOnCallScreen = showNamesOnCallScreen

        super.init()

        // We cannot assert singleton here, because this class gets rebuilt when the user changes relevant call settings

        self.provider.setDelegate(self, queue: nil)
    }

    // MARK: Dependencies

    var audioSession: OWSAudioSession {
        return Environment.shared.audioSession
    }

    // MARK: CallUIAdaptee

    func startOutgoingCall(call: SignalCall) {
        AssertIsOnMainThread()
        Logger.info("")

        // make sure we don't terminate audio session during call
        _ = self.audioSession.startAudioActivity(call.audioActivity)

        // Add the new outgoing call to the app's list of calls.
        // So we can find it in the provider delegate callbacks.
        callManager.addCall(call)
        callManager.startCall(call)
    }

    // Called from CallService after call has ended to clean up any remaining CallKit call state.
    func failCall(_ call: SignalCall, error: SignalCall.CallError) {
        AssertIsOnMainThread()
        Logger.info("")

        switch error {
        case .timeout(description: _):
            provider.reportCall(with: call.individualCall.localId, endedAt: Date(), reason: CXCallEndedReason.unanswered)
        default:
            provider.reportCall(with: call.individualCall.localId, endedAt: Date(), reason: CXCallEndedReason.failed)
        }

        callManager.removeCall(call)
    }

    func reportIncomingCall(_ call: SignalCall, callerName: String, completion: @escaping (Error?) -> Void) {
        AssertIsOnMainThread()
        Logger.info("")

        // Construct a CXCallUpdate describing the incoming call, including the caller.
        let update = CXCallUpdate()

        if showNamesOnCallScreen {
            update.localizedCallerName = contactsManager.displayName(for: call.individualCall.remoteAddress)
            if let phoneNumber = call.individualCall.remoteAddress.phoneNumber {
                update.remoteHandle = CXHandle(type: .phoneNumber, value: phoneNumber)
            }
        } else {
            let callKitId = CallKitCallManager.kAnonymousCallHandlePrefix + call.individualCall.localId.uuidString
            update.remoteHandle = CXHandle(type: .generic, value: callKitId)
            CallKitIdStore.setAddress(call.individualCall.remoteAddress, forCallKitId: callKitId)
            update.localizedCallerName = NSLocalizedString("CALLKIT_ANONYMOUS_CONTACT_NAME", comment: "The generic name used for calls if CallKit privacy is enabled")
        }

        update.hasVideo = call.individualCall.offerMediaType == .video

        disableUnsupportedFeatures(callUpdate: update)

        // Report the incoming call to the system
        provider.reportNewIncomingCall(with: call.individualCall.localId, update: update) { error in
            /*
             Only add incoming call to the app's list of calls if the call was allowed (i.e. there was no error)
             since calls may be "denied" for various legitimate reasons. See CXErrorCodeIncomingCallError.
             */
            guard error == nil else {
                completion(error)
                Logger.error("failed to report new incoming call, error: \(error!)")
                return
            }

            completion(nil)

            self.showCall(call)
            self.callManager.addCall(call)
        }
    }

    func answerCall(localId: UUID) {
        AssertIsOnMainThread()
        Logger.info("")

        owsFailDebug("CallKit should answer calls via system call screen, not via notifications.")
    }

    func answerCall(_ call: SignalCall) {
        AssertIsOnMainThread()
        Logger.info("")

        callManager.answer(call: call)
    }

    private var ignoreFirstUnuteAfterRemoteAnswer = false
    func recipientAcceptedCall(_ call: SignalCall) {
        AssertIsOnMainThread()
        Logger.info("")

        self.provider.reportOutgoingCall(with: call.individualCall.localId, connectedAt: nil)

        let update = CXCallUpdate()
        disableUnsupportedFeatures(callUpdate: update)

        provider.reportCall(with: call.individualCall.localId, updated: update)

        // When we tell CallKit about the call, it tries
        // to unmute the call. We can work around this
        // by ignoring the next "unmute" request from
        // CallKit after the call is answered.
        ignoreFirstUnuteAfterRemoteAnswer = call.individualCall.isMuted
    }

    func localHangupCall(localId: UUID) {
        AssertIsOnMainThread()

        owsFailDebug("CallKit should decline calls via system call screen, not via notifications.")
    }

    func localHangupCall(_ call: SignalCall) {
        AssertIsOnMainThread()
        Logger.info("")

        callManager.localHangup(call: call)
    }

    func remoteDidHangupCall(_ call: SignalCall) {
        AssertIsOnMainThread()
        Logger.info("")

        provider.reportCall(with: call.individualCall.localId, endedAt: nil, reason: CXCallEndedReason.remoteEnded)
        callManager.removeCall(call)
    }

    func remoteBusy(_ call: SignalCall) {
        AssertIsOnMainThread()
        Logger.info("")

        provider.reportCall(with: call.individualCall.localId, endedAt: nil, reason: CXCallEndedReason.unanswered)
        callManager.removeCall(call)
    }

    func didAnswerElsewhere(call: SignalCall) {
        AssertIsOnMainThread()
        Logger.info("")

        provider.reportCall(with: call.individualCall.localId, endedAt: nil, reason: .answeredElsewhere)
        callManager.removeCall(call)
    }

    func didDeclineElsewhere(call: SignalCall) {
        AssertIsOnMainThread()
        Logger.info("")

        provider.reportCall(with: call.individualCall.localId, endedAt: nil, reason: .declinedElsewhere)
        callManager.removeCall(call)
    }

    func setIsMuted(call: SignalCall, isMuted: Bool) {
        AssertIsOnMainThread()
        Logger.info("")

        callManager.setIsMuted(call: call, isMuted: isMuted)
    }

    func setHasLocalVideo(call: SignalCall, hasLocalVideo: Bool) {
        AssertIsOnMainThread()
        Logger.debug("")

        let update = CXCallUpdate()
        update.hasVideo = hasLocalVideo

        // Update the CallKit UI.
        provider.reportCall(with: call.individualCall.localId, updated: update)

        self.callService.updateIsLocalVideoMuted(isLocalVideoMuted: !hasLocalVideo)
    }

    // MARK: CXProviderDelegate

    func providerDidReset(_ provider: CXProvider) {
        AssertIsOnMainThread()
        Logger.info("")

        // End any ongoing calls if the provider resets, and remove them from the app's list of calls,
        // since they are no longer valid.
        callService.individualCallService.handleCallKitProviderReset()

        // Remove all calls from the app's list of calls.
        callManager.removeAllCalls()
    }

    func provider(_ provider: CXProvider, perform action: CXStartCallAction) {
        AssertIsOnMainThread()

        Logger.info("CXStartCallAction")

        guard let call = callManager.callWithLocalId(action.callUUID) else {
            Logger.error("unable to find call")
            return
        }

        // We can't wait for long before fulfilling the CXAction, else CallKit will show a "Failed Call". We don't 
        // actually need to wait for the outcome of the handleOutgoingCall promise, because it handles any errors by 
        // manually failing the call.
        self.callService.individualCallService.handleOutgoingCall(call)

        action.fulfill()
        self.provider.reportOutgoingCall(with: call.individualCall.localId, startedConnectingAt: nil)

        // Update the name used in the CallKit UI for outgoing calls when the user prefers not to show names
        // in ther notifications
        if !showNamesOnCallScreen {
            let update = CXCallUpdate()
            update.localizedCallerName = NSLocalizedString("CALLKIT_ANONYMOUS_CONTACT_NAME",
                                                           comment: "The generic name used for calls if CallKit privacy is enabled")
            provider.reportCall(with: call.individualCall.localId, updated: update)
        }
    }

    func provider(_ provider: CXProvider, perform action: CXAnswerCallAction) {
        AssertIsOnMainThread()

        Logger.info("Received \(#function) CXAnswerCallAction")
        // Retrieve the instance corresponding to the action's call UUID
        guard let call = callManager.callWithLocalId(action.callUUID) else {
            owsFailDebug("call as unexpectedly nil")
            action.fail()
            return
        }

        self.callService.individualCallService.handleAcceptCall(call)
        action.fulfill()
    }

    public func provider(_ provider: CXProvider, perform action: CXEndCallAction) {
        AssertIsOnMainThread()

        Logger.info("Received \(#function) CXEndCallAction")
        guard let call = callManager.callWithLocalId(action.callUUID) else {
            Logger.error("trying to end unknown call with localId: \(action.callUUID)")
            action.fail()
            return
        }

        self.callService.individualCallService.handleLocalHangupCall(call)

        // Signal to the system that the action has been successfully performed.
        action.fulfill()

        // Remove the ended call from the app's list of calls.
        self.callManager.removeCall(call)
    }

    public func provider(_ provider: CXProvider, perform action: CXSetHeldCallAction) {
        AssertIsOnMainThread()

        Logger.info("Received \(#function) CXSetHeldCallAction")
        guard let call = callManager.callWithLocalId(action.callUUID) else {
            action.fail()
            return
        }

        // Update the IndividualCall's underlying hold state.
        self.callService.individualCallService.setIsOnHold(call: call, isOnHold: action.isOnHold)

        // Signal to the system that the action has been successfully performed.
        action.fulfill()
    }

    public func provider(_ provider: CXProvider, perform action: CXSetMutedCallAction) {
        AssertIsOnMainThread()

        Logger.info("Received \(#function) CXSetMutedCallAction")
        guard let call = callManager.callWithLocalId(action.callUUID) else {
            Logger.info("Failing CXSetMutedCallAction for unknown (ended?) call: \(action.callUUID)")
            action.fail()
            return
        }

        defer { ignoreFirstUnuteAfterRemoteAnswer = false }
        guard !ignoreFirstUnuteAfterRemoteAnswer || action.isMuted else { return }

        self.callService.updateIsLocalAudioMuted(isLocalAudioMuted: action.isMuted)
        action.fulfill()
    }

    public func provider(_ provider: CXProvider, perform action: CXSetGroupCallAction) {
        AssertIsOnMainThread()

        Logger.warn("unimplemented \(#function) for CXSetGroupCallAction")
    }

    public func provider(_ provider: CXProvider, perform action: CXPlayDTMFCallAction) {
        AssertIsOnMainThread()

        Logger.warn("unimplemented \(#function) for CXPlayDTMFCallAction")
    }

    func provider(_ provider: CXProvider, timedOutPerforming action: CXAction) {
        AssertIsOnMainThread()

        if #available(iOS 13, *), let muteAction = action as? CXSetMutedCallAction {
            guard callManager.callWithLocalId(muteAction.callUUID) != nil else {
                // When a call is over, if it was muted, CallKit "helpfully" attempts to unmute the
                // call with "CXSetMutedCallAction", presumably to help us clean up state.
                //
                // That is, it calls func provider(_ provider: CXProvider, perform action: CXSetMutedCallAction)
                //
                // We don't need this - we have our own mechanism for coallescing audio state, so
                // we acknowledge the action, but perform a no-op.
                //
                // However, regardless of fulfilling or failing the action, the action "times out"
                // on iOS13. CallKit similarly "auto unmutes" ended calls on iOS12, but on iOS12
                // it doesn't timeout.
                //
                // Presumably this is a regression in iOS13 - so we ignore it.
                // #RADAR FB7568405
                Logger.info("ignoring timeout for CXSetMutedCallAction for ended call: \(muteAction.callUUID)")
                return
            }
        }

        owsFailDebug("Timed out while performing \(action)")
    }

    func provider(_ provider: CXProvider, didActivate audioSession: AVAudioSession) {
        AssertIsOnMainThread()

        Logger.debug("Received")

        _ = self.audioSession.startAudioActivity(self.audioActivity)
        self.audioSession.isRTCAudioEnabled = true
    }

    func provider(_ provider: CXProvider, didDeactivate audioSession: AVAudioSession) {
        AssertIsOnMainThread()

        Logger.debug("Received")
        self.audioSession.isRTCAudioEnabled = false
        self.audioSession.endAudioActivity(self.audioActivity)
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
