//
//  Copyright (c) 2022 Open Whisper Systems. All rights reserved.
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
 * their corresponding consequences are implemented in the CXProviderDelegate methods, e.g. using the CallService
 */
final class CallKitCallUIAdaptee: NSObject, CallUIAdaptee, CXProviderDelegate {

    private let callManager: CallKitCallManager
    private let showNamesOnCallScreen: Bool
    private let provider: CXProvider
    private let audioActivity: AudioActivity

    // CallKit handles incoming ringer stop/start for us. Yay!
    let hasManualRinger = false

    // Instantiating more than one CXProvider can cause us to miss call transactions, so
    // we maintain the provider across Adaptees using a singleton pattern
    static private let providerReadyFlag: ReadyFlag = ReadyFlag(name: "CallKitCXProviderReady", queueMode: .mainThread)
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

    // MARK: CallUIAdaptee

    func startOutgoingCall(call: SignalCall) {
        AssertIsOnMainThread()
        Logger.info("")

        // make sure we don't terminate audio session during call
        _ = self.audioSession.startAudioActivity(call.audioActivity)

        // Add the new outgoing call to the app's list of calls.
        // So we can find it in the provider delegate callbacks.
        Self.providerReadyFlag.runNowOrWhenDidBecomeReadySync {
            self.callManager.addCall(call)
            self.callManager.startCall(call)
        }
    }

    // Called from CallService after call has ended to clean up any remaining CallKit call state.
    func failCall(_ call: SignalCall, error: SignalCall.CallError) {
        AssertIsOnMainThread()
        Logger.info("")

        Self.providerReadyFlag.runNowOrWhenDidBecomeReadySync {
            switch error {
            case .timeout(description: _):
                self.provider.reportCall(with: call.localId, endedAt: Date(), reason: CXCallEndedReason.unanswered)
            default:
                self.provider.reportCall(with: call.localId, endedAt: Date(), reason: CXCallEndedReason.failed)
            }
            self.callManager.removeCall(call)
        }
    }

    func reportIncomingCall(_ call: SignalCall, completion: @escaping (Error?) -> Void) {
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
            let callKitId = CallKitCallManager.kAnonymousCallHandlePrefix + call.localId.uuidString
            update.remoteHandle = CXHandle(type: .generic, value: callKitId)
            CallKitIdStore.setAddress(call.individualCall.remoteAddress, forCallKitId: callKitId)
            update.localizedCallerName = NSLocalizedString("CALLKIT_ANONYMOUS_CONTACT_NAME", comment: "The generic name used for calls if CallKit privacy is enabled")
        }

        update.hasVideo = call.individualCall.offerMediaType == .video

        disableUnsupportedFeatures(callUpdate: update)

        Self.providerReadyFlag.runNowOrWhenDidBecomeReadySync {
            // Report the incoming call to the system
            self.provider.reportNewIncomingCall(with: call.localId, update: update) { error in
                /*
                 Only add incoming call to the app's list of calls if the call was allowed (i.e. there was no error)
                 since calls may be "denied" for various legitimate reasons. See CXErrorCodeIncomingCallError.
                 */
                self.pushRegistrationManager.didFinishReportingIncomingCall()

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
    }

    func answerCall(localId: UUID) {
        AssertIsOnMainThread()
        Logger.info("")

        owsFailDebug("CallKit should answer calls via system call screen, not via notifications.")
    }

    func answerCall(_ call: SignalCall) {
        AssertIsOnMainThread()
        Logger.info("")

        Self.providerReadyFlag.runNowOrWhenDidBecomeReadySync {
            self.callManager.answer(call: call)
        }
    }

    private var ignoreFirstUnmuteAfterRemoteAnswer = false
    func recipientAcceptedCall(_ call: SignalCall) {
        AssertIsOnMainThread()
        Logger.info("")

        Self.providerReadyFlag.runNowOrWhenDidBecomeReadySync {
            self.provider.reportOutgoingCall(with: call.localId, connectedAt: nil)

            let update = CXCallUpdate()
            self.disableUnsupportedFeatures(callUpdate: update)

            self.provider.reportCall(with: call.localId, updated: update)

            // When we tell CallKit about the call, it tries
            // to unmute the call. We can work around this
            // by ignoring the next "unmute" request from
            // CallKit after the call is answered.
            self.ignoreFirstUnmuteAfterRemoteAnswer = call.individualCall.isMuted

            // Enable audio for remotely accepted calls after the session is configured.
            self.audioSession.isRTCAudioEnabled = true
        }
    }

    func localHangupCall(localId: UUID) {
        AssertIsOnMainThread()

        owsFailDebug("CallKit should decline calls via system call screen, not via notifications.")
    }

    func localHangupCall(_ call: SignalCall) {
        AssertIsOnMainThread()
        Logger.info("")

        Self.providerReadyFlag.runNowOrWhenDidBecomeReadySync {
            self.callManager.localHangup(call: call)
        }
    }

    func remoteDidHangupCall(_ call: SignalCall) {
        AssertIsOnMainThread()
        Logger.info("")

        Self.providerReadyFlag.runNowOrWhenDidBecomeReadySync {
            self.provider.reportCall(with: call.localId, endedAt: nil, reason: CXCallEndedReason.remoteEnded)
            self.callManager.removeCall(call)
        }
    }

    func remoteBusy(_ call: SignalCall) {
        AssertIsOnMainThread()
        Logger.info("")

        Self.providerReadyFlag.runNowOrWhenDidBecomeReadySync {
            self.provider.reportCall(with: call.localId, endedAt: nil, reason: CXCallEndedReason.unanswered)
            self.callManager.removeCall(call)
        }
    }

    func didAnswerElsewhere(call: SignalCall) {
        AssertIsOnMainThread()
        Logger.info("")

        Self.providerReadyFlag.runNowOrWhenDidBecomeReadySync {
            self.provider.reportCall(with: call.localId, endedAt: nil, reason: .answeredElsewhere)
            self.callManager.removeCall(call)
        }
    }

    func didDeclineElsewhere(call: SignalCall) {
        AssertIsOnMainThread()
        Logger.info("")

        Self.providerReadyFlag.runNowOrWhenDidBecomeReadySync {
            self.provider.reportCall(with: call.localId, endedAt: nil, reason: .declinedElsewhere)
            self.callManager.removeCall(call)
        }
    }

    func wasBusyElsewhere(call: SignalCall) {
        AssertIsOnMainThread()
        Logger.info("")

        Self.providerReadyFlag.runNowOrWhenDidBecomeReadySync {
            // Callkit doesn't have a reason for "busy elsewhere", .declinedElsewhere is close enough.
            self.provider.reportCall(with: call.localId, endedAt: nil, reason: .declinedElsewhere)
            self.callManager.removeCall(call)
        }
    }

    func setIsMuted(call: SignalCall, isMuted: Bool) {
        AssertIsOnMainThread()
        Logger.info("")

        Self.providerReadyFlag.runNowOrWhenDidBecomeReadySync {
            self.callManager.setIsMuted(call: call, isMuted: isMuted)
        }
    }

    func setHasLocalVideo(call: SignalCall, hasLocalVideo: Bool) {
        AssertIsOnMainThread()
        Logger.debug("")
        callService.updateIsLocalVideoMuted(isLocalVideoMuted: !hasLocalVideo)

        // Update the CallKit UI.
        Self.providerReadyFlag.runNowOrWhenDidBecomeReadySync {
            let update = CXCallUpdate()
            update.hasVideo = hasLocalVideo
            self.provider.reportCall(with: call.localId, updated: update)
        }
    }

    // MARK: CXProviderDelegate

    func providerDidBegin(_ provider: CXProvider) {
        AssertIsOnMainThread()
        Logger.info("")
        Self.providerReadyFlag.setIsReady()
    }

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
        provider.reportOutgoingCall(with: call.localId, startedConnectingAt: nil)

        let update = CXCallUpdate()
        if showNamesOnCallScreen {
            update.localizedCallerName = contactsManager.displayNameWithSneakyTransaction(thread: call.thread)
        } else {
            update.localizedCallerName = NSLocalizedString("CALLKIT_ANONYMOUS_CONTACT_NAME",
                                                           comment: "The generic name used for calls if CallKit privacy is enabled")
        }
        provider.reportCall(with: call.localId, updated: update)
    }

    func provider(_ provider: CXProvider, perform action: CXAnswerCallAction) {
        AssertIsOnMainThread()

        Logger.info("Received \(#function) CXAnswerCallAction \(action.timeoutDate)")
        guard let call = callManager.callWithLocalId(action.callUUID) else {
            owsFailDebug("call as unexpectedly nil")
            action.fail()
            return
        }

        if call.individualCall.state == .localRinging_Anticipatory {
            // We can't answer the call until RingRTC is ready
            call.individualCall.state = .accepting
            call.individualCall.deferredAnswerCompletion = {
                action.fulfill()
            }
        } else {
            owsAssertDebug(call.individualCall.state == .localRinging_ReadyToAnswer)
            self.callService.individualCallService.handleAcceptCall(call)
            action.fulfill()
        }
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
        guard nil != callManager.callWithLocalId(action.callUUID) else {
            Logger.info("Failing CXSetMutedCallAction for unknown (ended?) call: \(action.callUUID)")
            action.fail()
            return
        }

        defer { ignoreFirstUnmuteAfterRemoteAnswer = false }
        guard !ignoreFirstUnmuteAfterRemoteAnswer || action.isMuted else { return }

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
                // We don't need this - we have our own mechanism for coalescing audio state, so
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

        Logger.debug("Received \(#function) didActivate")

        _ = self.audioSession.startAudioActivity(self.audioActivity)

        guard let call = self.callManager.callService.currentCall else {
            owsFailDebug("No current call for AudioSession")
            return
        }

        if call.individualCall.direction == .incoming {
            // Only enable audio upon activation for locally accepted calls.
            self.audioSession.isRTCAudioEnabled = true
        }
    }

    func provider(_ provider: CXProvider, didDeactivate audioSession: AVAudioSession) {
        AssertIsOnMainThread()

        Logger.debug("Received \(#function) didDeactivate")
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
