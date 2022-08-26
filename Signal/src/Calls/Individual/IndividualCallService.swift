//
//  Copyright (c) 2022 Open Whisper Systems. All rights reserved.
//

import Foundation
import SignalRingRTC
import WebRTC
import SignalServiceKit
import SignalMessaging
import CallKit

// MARK: - CallService

// This class' state should only be accessed on the main queue.
@objc
final public class IndividualCallService: NSObject {

    private var callManager: CallService.CallManagerType {
        return callService.callManager
    }

    // MARK: - Properties

    // Exposed by environment.m

    @objc
    public var callUIAdapter: CallUIAdapter!

    // MARK: Class

    static let fallbackIceServer = RTCIceServer(urlStrings: ["stun:stun1.l.google.com:19302"])

    @objc
    public override init() {
        super.init()

        SwiftSingletons.register(self)
    }

    /**
     * Choose whether to use CallKit or a Notification backed interface for calling.
     */
    @objc
    public func createCallUIAdapter() {
        AssertIsOnMainThread()

        if let call = callService.currentCall {
            Logger.warn("ending current call in. Did user toggle callkit preference while in a call?")
            callService.terminate(call: call)
        }

        self.callUIAdapter = CallUIAdapter()
    }

    // MARK: - Call Control Actions

    /**
     * Initiate an outgoing call.
     */
    func handleOutgoingCall(_ call: SignalCall) {
        AssertIsOnMainThread()
        Logger.info("call: \(call)")

        BenchEventStart(title: "Outgoing Call Connection", eventId: "call-\(call.localId)")

        guard callService.currentCall == nil else {
            owsFailDebug("call already exists: \(String(describing: callService.currentCall))")
            return
        }

        // Create a callRecord for outgoing calls immediately.
        let callRecord = TSCall(
            callType: .outgoingIncomplete,
            offerType: call.individualCall.offerMediaType,
            thread: call.individualCall.thread,
            sentAtTimestamp: call.individualCall.sentAtTimestamp
        )
        databaseStorage.asyncWrite { transaction in
            callRecord.anyInsert(transaction: transaction)
        }
        call.individualCall.callRecord = callRecord

        // Get the current local device Id, must be valid for lifetime of the call.
        let localDeviceId = tsAccountManager.storedDeviceId()

        do {
            try callManager.placeCall(call: call, callMediaType: call.individualCall.offerMediaType.asCallMediaType, localDevice: localDeviceId)
        } catch {
            self.handleFailedCall(failedCall: call, error: error, shouldResetUI: true, shouldResetRingRTC: true)
        }
    }

    /**
     * User chose to answer the call. Used by the Callee only.
     */
    public func handleAcceptCall(_ call: SignalCall) {
        AssertIsOnMainThread()
        Logger.info("\(call)")

        defer {
            // This should only be non-nil if we had to defer accepting the call while waiting for RingRTC
            // If it's set, we need to make sure we call it before returning.
            call.individualCall.deferredAnswerCompletion?()
            call.individualCall.deferredAnswerCompletion = nil
        }

        guard callService.currentCall === call else {
            let error = OWSAssertionError("accepting call: \(call) which is different from currentCall: \(callService.currentCall as Optional)")
            handleFailedCall(failedCall: call, error: error, shouldResetUI: true, shouldResetRingRTC: true)
            return
        }

        guard let callId = call.individualCall.callId else {
            handleFailedCall(failedCall: call, error: OWSAssertionError("no callId for call: \(call)"), shouldResetUI: true, shouldResetRingRTC: true)
            return
        }

        let callRecord = TSCall(
            callType: .incomingIncomplete,
            offerType: call.individualCall.offerMediaType,
            thread: call.individualCall.thread,
            sentAtTimestamp: call.individualCall.sentAtTimestamp
        )
        databaseStorage.asyncWrite { transaction in
            callRecord.anyInsert(transaction: transaction)
        }
        call.individualCall.callRecord = callRecord

        // It's key that we configure the AVAudioSession for a call *before* we fulfill the
        // CXAnswerCallAction.
        //
        // Otherwise CallKit has been seen not to activate the audio session.
        // That is, `provider(_ provider: CXProvider, didActivate audioSession: AVAudioSession)`
        // was sometimes not called.`
        //
        // That is why we connect here, rather than waiting for a racy async response from
        // CallManager, confirming that the call has connected. It is also safer to do the
        // audio session configuration before WebRTC starts operating on the audio resources
        // via CallManager.accept().
        handleConnected(call: call)

        do {
            try callManager.accept(callId: callId)
        } catch {
            self.handleFailedCall(failedCall: call, error: error, shouldResetUI: true, shouldResetRingRTC: true)
        }
    }

    /**
     * Local user chose to end the call.
     */
    func handleLocalHangupCall(_ call: SignalCall) {
        AssertIsOnMainThread()
        Logger.info("\(call)")

        guard call === callService.currentCall else {
            Logger.info("ignoring hangup for obsolete call: \(call)")
            return
        }

        if let callRecord = call.individualCall.callRecord {
            if callRecord.callType == .outgoingIncomplete {
                callRecord.updateCallType(.outgoingMissed)
            }
        } else if [.localRinging_Anticipatory, .localRinging_ReadyToAnswer].contains(call.individualCall.state) {
            let callRecord = TSCall(
                callType: .incomingDeclined,
                offerType: call.individualCall.offerMediaType,
                thread: call.individualCall.thread,
                sentAtTimestamp: call.individualCall.sentAtTimestamp
            )
            databaseStorage.asyncWrite { transaction in
                callRecord.anyInsert(transaction: transaction)
            }
            call.individualCall.callRecord = callRecord
        } else {
            owsFailDebug("missing call record")
        }

        // Make RTC audio inactive early in the hangup process before the state
        // change resulting in any change to the default AudioSession.
        audioSession.isRTCAudioEnabled = false

        call.individualCall.state = .localHangup

        ensureAudioState(call: call)

        callService.terminate(call: call)

        do {
            try callManager.hangup()
        } catch {
            // no point in "failing" the call if the user expressed their intent to hang up
            // and we've already called: `terminate(call: cal)`
            owsFailDebug("error: \(error)")
        }
    }

    // MARK: - Signaling Functions

    private func allowsInboundCallsInThread(_ thread: TSContactThread,
                                            transaction: SDSAnyReadTransaction) -> Bool {
        // IFF one of the following things is true, we can handle inbound call offers
        // * The thread is in our profile whitelist
        // * The thread belongs to someone in our system contacts
        return (self.profileManager.isThread(inProfileWhitelist: thread, transaction: transaction)
                || self.contactsManager.isSystemContact(address: thread.contactAddress,
                                                        transaction: transaction))
    }

    private struct CallIdentityKeys {
      let localIdentityKey: Data
      let contactIdentityKey: Data
    }

    private func getIdentityKeys(thread: TSContactThread) -> CallIdentityKeys? {
        databaseStorage.read { transaction in
            self.getIdentityKeys(thread: thread, transaction: transaction)
        }
    }

    private func getIdentityKeys(thread: TSContactThread, transaction: SDSAnyReadTransaction) -> CallIdentityKeys? {
        guard let localIdentityKey = self.identityManager.identityKeyPair(for: .aci,
                                                                          transaction: transaction)?.publicKey else {
            owsFailDebug("missing localIdentityKey")
            return nil
        }
        guard let contactIdentityKey = self.identityManager.identityKey(for: thread.contactAddress, transaction: transaction) else {
            owsFailDebug("missing contactIdentityKey")
            return nil
        }
        return CallIdentityKeys(localIdentityKey: localIdentityKey, contactIdentityKey: contactIdentityKey)
    }

    /**
     * Received an incoming call Offer from call initiator.
     */
    public func handleReceivedOffer(
        thread: TSContactThread,
        callId: UInt64,
        sourceDevice: UInt32,
        sdp: String?,
        opaque: Data?,
        sentAtTimestamp: UInt64,
        serverReceivedTimestamp: UInt64,
        serverDeliveryTimestamp: UInt64,
        callType: SSKProtoCallMessageOfferType,
        supportsMultiRing: Bool,
        transaction: SDSAnyWriteTransaction
    ) {
        AssertIsOnMainThread()
        Logger.info("callId: \(callId), thread: \(thread.contactAddress)")

        // opaque is required. sdp is obsolete, but it might still come with opaque.
        guard let opaque = opaque else {
            // TODO: Remove once the proto is updated to only support opaque and require it.
            Logger.debug("opaque not received for offer, remote should update")
            return
        }

        let newCall = callService.prepareIncomingIndividualCall(
            thread: thread,
            sentAtTimestamp: sentAtTimestamp,
            callType: callType
        )

        BenchEventStart(title: "Incoming Call Connection", eventId: "call-\(newCall.localId)")

        guard tsAccountManager.isOnboarded(with: transaction) else {
            Logger.warn("user is not onboarded, skipping call.")
            let callRecord = TSCall(
                callType: .incomingMissed,
                offerType: newCall.individualCall.offerMediaType,
                thread: thread,
                sentAtTimestamp: sentAtTimestamp
            )
            assert(newCall.individualCall.callRecord == nil)
            newCall.individualCall.callRecord = callRecord
            callRecord.anyInsert(transaction: transaction)

            newCall.individualCall.state = .localFailure
            callService.terminate(call: newCall)

            return
        }

        if let untrustedIdentity = self.identityManager.untrustedIdentityForSending(to: thread.contactAddress,
                                                                                    transaction: transaction) {
            Logger.warn("missed a call due to untrusted identity: \(newCall)")

            switch untrustedIdentity.verificationState {
            case .verified:
                owsFailDebug("shouldn't have missed a call due to untrusted identity if the identity is verified")
                let sentAtTimestamp = Date(millisecondsSince1970: newCall.individualCall.sentAtTimestamp)
                self.notificationPresenter.presentMissedCall(newCall,
                                                             caller: thread.contactAddress,
                                                             sentAt: sentAtTimestamp)
            case .default:
                self.notificationPresenter.presentMissedCallBecauseOfNewIdentity(call: newCall,
                                                                                 caller: thread.contactAddress)
            case .noLongerVerified:
                self.notificationPresenter.presentMissedCallBecauseOfNoLongerVerifiedIdentity(
                    call: newCall,
                    caller: thread.contactAddress)
            }

            let callRecord = TSCall(
                callType: .incomingMissedBecauseOfChangedIdentity,
                offerType: newCall.individualCall.offerMediaType,
                thread: thread,
                sentAtTimestamp: sentAtTimestamp
            )
            assert(newCall.individualCall.callRecord == nil)
            newCall.individualCall.callRecord = callRecord
            callRecord.anyInsert(transaction: transaction)

            newCall.individualCall.state = .localFailure
            callService.terminate(call: newCall)

            return
        }

        guard let identityKeys = getIdentityKeys(thread: thread, transaction: transaction) else {
            owsFailDebug("missing identity keys, skipping call.")
            let callRecord = TSCall(
                callType: .incomingMissed,
                offerType: newCall.individualCall.offerMediaType,
                thread: thread,
                sentAtTimestamp: sentAtTimestamp
            )
            assert(newCall.individualCall.callRecord == nil)
            newCall.individualCall.callRecord = callRecord
            callRecord.anyInsert(transaction: transaction)

            newCall.individualCall.state = .localFailure
            callService.terminate(call: newCall)

            return
        }

        guard allowsInboundCallsInThread(thread, transaction: transaction) else {
            Logger.info("Ignoring call offer from \(thread.contactAddress) due to insufficient permissions.")

            // Send the need permission message to the caller, so they know why we rejected their call.
            let localDeviceId = tsAccountManager.storedDeviceId(with: transaction)
            callManager(
                callManager,
                shouldSendHangup: callId,
                call: newCall,
                destinationDeviceId: sourceDevice,
                hangupType: .needPermission,
                deviceId: localDeviceId
            )

            // Store the call as a missed call for the local user. They will see it in the conversation
            // along with the message request dialog. When they accept the dialog, they can call back
            // or the caller can try again.
            let callRecord = TSCall(
                callType: .incomingMissed,
                offerType: newCall.individualCall.offerMediaType,
                thread: thread,
                sentAtTimestamp: sentAtTimestamp
            )
            assert(newCall.individualCall.callRecord == nil)
            newCall.individualCall.callRecord = callRecord
            callRecord.anyInsert(transaction: transaction)

            newCall.individualCall.state = .localFailure
            callService.terminate(call: newCall)

            return
        }

        Logger.debug("Enable backgroundTask")
        let backgroundTask: OWSBackgroundTask? = OWSBackgroundTask(label: "\(#function)", completionBlock: { status in
            AssertIsOnMainThread()

            guard status == .expired else {
                return
            }

            // See if the newCall actually became the currentCall.
            guard case .individual(let currentCall) = self.callService.currentCall?.mode,
                  newCall === currentCall else {
                Logger.warn("ignoring obsolete call")
                return
            }

            let error = SignalCall.CallError.timeout(description: "background task time ran out before call connected")
            self.handleFailedCall(failedCall: newCall, error: error, shouldResetUI: true, shouldResetRingRTC: true)
        })

        newCall.individualCall.backgroundTask = backgroundTask

        var messageAgeSec: UInt64 = 0
        if serverReceivedTimestamp > 0 && serverDeliveryTimestamp >= serverReceivedTimestamp {
            messageAgeSec = (serverDeliveryTimestamp - serverReceivedTimestamp) / 1000
        }

        // Get the current local device Id, must be valid for lifetime of the call.
        let localDeviceId = tsAccountManager.storedDeviceId(with: transaction)
        let isPrimaryDevice = tsAccountManager.isPrimaryDevice(transaction: transaction)

        do {
            try callManager.receivedOffer(call: newCall,
                                          sourceDevice: sourceDevice,
                                          callId: callId,
                                          opaque: opaque,
                                          messageAgeSec: messageAgeSec,
                                          callMediaType: newCall.individualCall.offerMediaType.asCallMediaType,
                                          localDevice: localDeviceId,
                                          isLocalDevicePrimary: isPrimaryDevice,
                                          senderIdentityKey: identityKeys.contactIdentityKey,
                                          receiverIdentityKey: identityKeys.localIdentityKey)
        } catch {
            DispatchQueue.main.async {
                self.handleFailedCall(failedCall: newCall, error: error, shouldResetUI: true, shouldResetRingRTC: true)
            }
        }
    }

    /**
     * Called by the call initiator after receiving an Answer from the callee.
     */
    public func handleReceivedAnswer(thread: TSContactThread, callId: UInt64, sourceDevice: UInt32, sdp: String?, opaque: Data?, supportsMultiRing: Bool) {
        AssertIsOnMainThread()
        Logger.info("callId: \(callId), thread: \(thread.contactAddress)")

        // opaque is required. sdp is obsolete, but it might still come with opaque.
        guard let opaque = opaque else {
            // TODO: Remove once the proto is updated to only support opaque and require it.
            Logger.debug("opaque not received for answer, remote should update")
            return
        }

        guard let identityKeys = getIdentityKeys(thread: thread) else {
            if let currentCall = callService.currentCall, currentCall.individualCall?.callId == callId {
                handleFailedCall(failedCall: currentCall, error: OWSAssertionError("missing identity keys"), shouldResetUI: true, shouldResetRingRTC: true)
            }
            return
        }

        do {
            try callManager.receivedAnswer(sourceDevice: sourceDevice, callId: callId, opaque: opaque, senderIdentityKey: identityKeys.contactIdentityKey, receiverIdentityKey: identityKeys.localIdentityKey)
        } catch {
            owsFailDebug("error: \(error)")
            if let currentCall = callService.currentCall, currentCall.individualCall?.callId == callId {
                handleFailedCall(failedCall: currentCall, error: error, shouldResetUI: true, shouldResetRingRTC: true)
            }
        }
    }

    /**
     * Remote client (could be caller or callee) sent us a connectivity update.
     */
    public func handleReceivedIceCandidates(thread: TSContactThread, callId: UInt64, sourceDevice: UInt32, candidates: [SSKProtoCallMessageIceUpdate]) {
        AssertIsOnMainThread()
        Logger.info("callId: \(callId), thread: \(thread.contactAddress)")

        let iceCandidates = candidates.filter { $0.id == callId && $0.opaque != nil }.map { $0.opaque! }

        guard iceCandidates.count > 0 else {
            Logger.debug("no ice candidates in ice message, remote should update")
            return
        }

        do {
            try callManager.receivedIceCandidates(sourceDevice: sourceDevice, callId: callId, candidates: iceCandidates)
        } catch {
            owsFailDebug("error: \(error)")
            // we don't necessarily want to fail the call just because CallManager errored on an
            // ICE candidate
        }
    }

    /**
     * The remote client (caller or callee) ended the call.
     */
    public func handleReceivedHangup(thread: TSContactThread, callId: UInt64, sourceDevice: UInt32, type: SSKProtoCallMessageHangupType, deviceId: UInt32) {
        AssertIsOnMainThread()
        Logger.info("callId: \(callId), thread: \(thread.contactAddress)")

        let hangupType: HangupType
        switch type {
        case .hangupNormal: hangupType = .normal
        case .hangupAccepted: hangupType = .accepted
        case .hangupDeclined: hangupType = .declined
        case .hangupBusy: hangupType = .busy
        case .hangupNeedPermission: hangupType = .needPermission
        }

        do {
            try callManager.receivedHangup(sourceDevice: sourceDevice, callId: callId, hangupType: hangupType, deviceId: deviceId)
        } catch {
            owsFailDebug("\(error)")
            if let currentCall = callService.currentCall, currentCall.individualCall?.callId == callId {
                handleFailedCall(failedCall: currentCall, error: error, shouldResetUI: true, shouldResetRingRTC: true)
            }
        }
    }

    /**
     * The callee was already in another call.
     */
    public func handleReceivedBusy(thread: TSContactThread, callId: UInt64, sourceDevice: UInt32) {
        AssertIsOnMainThread()
        Logger.info("callId: \(callId), thread: \(thread.contactAddress)")

        do {
            try callManager.receivedBusy(sourceDevice: sourceDevice, callId: callId)
        } catch {
            owsFailDebug("\(error)")
            if let currentCall = callService.currentCall, currentCall.individualCall?.callId == callId {
                handleFailedCall(failedCall: currentCall, error: error, shouldResetUI: true, shouldResetRingRTC: true)
            }
        }
    }

    // MARK: - Call Manager Events

    public func callManager(_ callManager: CallService.CallManagerType, shouldStartCall call: SignalCall, callId: UInt64, isOutgoing: Bool, callMediaType: CallMediaType, shouldEarlyRing: Bool) {
        AssertIsOnMainThread()
        owsAssertDebug(call.isIndividualCall)
        Logger.info("call: \(call)")

        if shouldEarlyRing {
            if !isOutgoing {
                // If we are using the NSE, we need to kick off a ring ASAP in case this incoming call
                // has resulted in the NSE waking up the main app.
                owsAssertDebug(callUIAdapter.adaptee(for: call) === callUIAdapter.callKitAdaptee)
                Logger.info("Performing early ring")
                handleRinging(call: call, isAnticipatory: true)
            } else {
                owsFailDebug("Cannot early ring an outgoing call")
            }
        }

        // Start the call, asynchronously.
        getIceServers().done(on: .main) { iceServers in
            guard self.callService.currentCall === call else {
                Logger.debug("call has since ended")
                return
            }

            var isUnknownCaller = false
            if call.individualCall.direction == .incoming {
                isUnknownCaller = !self.contactsManagerImpl.isSystemContactWithSignalAccount(call.individualCall.thread.contactAddress)
                if isUnknownCaller {
                    Logger.warn("Using relay server because remote user is an unknown caller")
                }
            }

            let useTurnOnly = isUnknownCaller || Self.preferences.doCallsHideIPAddress()

            let useLowBandwidth = CallService.shouldUseLowBandwidthWithSneakyTransaction(for: NetworkRoute(localAdapterType: .unknown))
            Logger.info("Configuring call for \(useLowBandwidth ? "low" : "standard") bandwidth")

            // Tell the Call Manager to proceed with its active call.
            try self.callManager.proceed(callId: callId, iceServers: iceServers, hideIp: useTurnOnly, videoCaptureController: call.videoCaptureController, bandwidthMode: useLowBandwidth ? .low : .normal, audioLevelsIntervalMillis: nil)
        }.catch { error in
            owsFailDebug("\(error)")
            guard call === self.callService.currentCall else {
                Logger.debug("")
                return
            }

            callManager.drop(callId: callId)
            self.handleFailedCall(failedCall: call, error: error, shouldResetUI: true, shouldResetRingRTC: false)
        }

        Logger.debug("")
    }

    public func callManager(_ callManager: CallService.CallManagerType, onEvent call: SignalCall, event: CallManagerEvent) {
        AssertIsOnMainThread()
        owsAssertDebug(call.isIndividualCall)
        Logger.info("call: \(call), onEvent: \(event)")

        switch event {
        case .ringingLocal:
            handleRinging(call: call)

        case .ringingRemote:
            handleRinging(call: call)

        case .connectedLocal:
            Logger.debug("")
            // nothing further to do - already handled in handleAcceptCall().

        case .connectedRemote:
            // Set the audio session configuration before audio is enabled in WebRTC
            // via recipientAcceptedCall().
            handleConnected(call: call)
            callUIAdapter.recipientAcceptedCall(call)

        case .endedLocalHangup:
            Logger.debug("")
            // nothing further to do - already handled in handleLocalHangupCall().

        case .endedRemoteHangup:
            guard call === callService.currentCall else {
                callService.cleanupStaleCall(call)
                return
            }

            // Make RTC audio inactive early in the hangup process before the state
            // change resulting in any change to the default AudioSession.
            audioSession.isRTCAudioEnabled = false

            switch call.individualCall.state {
            case .idle, .dialing, .answering, .localRinging_Anticipatory, .localRinging_ReadyToAnswer, .accepting, .localFailure, .remoteBusy, .remoteRinging:
                handleMissedCall(call)
            case .connected, .reconnecting, .localHangup, .remoteHangup, .remoteHangupNeedPermission, .answeredElsewhere, .declinedElsewhere, .busyElsewhere:
                Logger.info("call is finished")
            }

            call.individualCall.state = .remoteHangup

            // Notify UI
            callUIAdapter.remoteDidHangupCall(call)

            callService.terminate(call: call)

        case .endedRemoteHangupNeedPermission:
            guard call === callService.currentCall else {
                callService.cleanupStaleCall(call)
                return
            }

            audioSession.isRTCAudioEnabled = false

            switch call.individualCall.state {
            case .idle, .dialing, .answering, .localRinging_Anticipatory, .localRinging_ReadyToAnswer, .accepting, .localFailure, .remoteBusy, .remoteRinging:
                handleMissedCall(call)
            case .connected, .reconnecting, .localHangup, .remoteHangup, .remoteHangupNeedPermission, .answeredElsewhere, .declinedElsewhere, .busyElsewhere:
                Logger.info("call is finished")
            }

            call.individualCall.state = .remoteHangupNeedPermission

            // Notify UI
            callUIAdapter.remoteDidHangupCall(call)

            callService.terminate(call: call)

        case .endedRemoteHangupAccepted:
            guard call === callService.currentCall else {
                callService.cleanupStaleCall(call)
                return
            }

            audioSession.isRTCAudioEnabled = false

            switch call.individualCall.state {
            case .idle, .dialing, .remoteBusy, .remoteRinging, .answeredElsewhere, .declinedElsewhere, .busyElsewhere, .remoteHangup, .remoteHangupNeedPermission:
                handleFailedCall(failedCall: call, error: OWSAssertionError("unexpected state for endedRemoteHangupAccepted: \(call.individualCall.state)"), shouldResetUI: true, shouldResetRingRTC: true)
                return
            case .answering, .accepting, .connected:
                Logger.info("tried answering locally, but answered somewhere else first. state: \(call.individualCall.state)")
                handleAnsweredElsewhere(call: call)
            case .localRinging_Anticipatory, .localRinging_ReadyToAnswer, .reconnecting:
                handleAnsweredElsewhere(call: call)
            case  .localFailure, .localHangup:
                Logger.info("ignoring 'endedRemoteHangupAccepted' since call is already finished")
            }

        case .endedRemoteHangupDeclined:
            guard call === callService.currentCall else {
                callService.cleanupStaleCall(call)
                return
            }

            audioSession.isRTCAudioEnabled = false

            switch call.individualCall.state {
            case .idle, .dialing, .remoteBusy, .remoteRinging, .answeredElsewhere, .declinedElsewhere, .busyElsewhere, .remoteHangup, .remoteHangupNeedPermission:
                handleFailedCall(failedCall: call, error: OWSAssertionError("unexpected state for endedRemoteHangupDeclined: \(call.individualCall.state)"), shouldResetUI: true, shouldResetRingRTC: true)
                return
            case .answering, .accepting, .connected:
                Logger.info("tried answering locally, but declined somewhere else first. state: \(call.individualCall.state)")
                handleDeclinedElsewhere(call: call)
            case .localRinging_Anticipatory, .localRinging_ReadyToAnswer, .reconnecting:
                handleDeclinedElsewhere(call: call)
            case  .localFailure, .localHangup:
                Logger.info("ignoring 'endedRemoteHangupDeclined' since call is already finished")
            }

        case .endedRemoteHangupBusy:
            guard call === callService.currentCall else {
                callService.cleanupStaleCall(call)
                return
            }

            audioSession.isRTCAudioEnabled = false

            switch call.individualCall.state {
            case .idle, .dialing, .remoteBusy, .remoteRinging, .answeredElsewhere, .declinedElsewhere, .busyElsewhere, .remoteHangup, .remoteHangupNeedPermission:
                handleFailedCall(failedCall: call, error: OWSAssertionError("unexpected state for endedRemoteHangupBusy: \(call.individualCall.state)"), shouldResetUI: true, shouldResetRingRTC: true)
                return
            case .answering, .accepting, .connected:
                Logger.info("tried answering locally, but already in a call somewhere else first. state: \(call.individualCall.state)")
                handleBusyElsewhere(call: call)
            case .localRinging_Anticipatory, .localRinging_ReadyToAnswer, .reconnecting:
                handleBusyElsewhere(call: call)
            case  .localFailure, .localHangup:
                Logger.info("ignoring 'endedRemoteHangupBusy' since call is already finished")
            }

        case .endedRemoteBusy:
            guard call === callService.currentCall else {
                callService.cleanupStaleCall(call)
                return
            }

            assert(call.individualCall.direction == .outgoing)
            if let callRecord = call.individualCall.callRecord {
                callRecord.updateCallType(.outgoingMissed)
            } else {
                owsFailDebug("outgoing call should have call record")
            }

            call.individualCall.state = .remoteBusy

            // Notify UI
            callUIAdapter.remoteBusy(call)

            callService.terminate(call: call)

        case .endedRemoteGlare, .endedRemoteReCall:
            guard call === callService.currentCall else {
                callService.cleanupStaleCall(call)
                return
            }

            if let callRecord = call.individualCall.callRecord {
                switch callRecord.callType {
                case .outgoingMissed, .incomingDeclined, .incomingMissed, .incomingMissedBecauseOfChangedIdentity, .incomingAnsweredElsewhere, .incomingDeclinedElsewhere, .incomingBusyElsewhere, .incomingMissedBecauseOfDoNotDisturb:
                    // already handled and ended, don't update the call record.
                    break
                case .incomingIncomplete, .incoming:
                    callRecord.updateCallType(.incomingMissed)
                    callUIAdapter.reportMissedCall(call)
                case .outgoingIncomplete:
                    callRecord.updateCallType(.outgoingMissed)
                    callUIAdapter.remoteBusy(call)
                case .outgoing:
                    callRecord.updateCallType(.outgoingMissed)
                    callUIAdapter.reportMissedCall(call)
                @unknown default:
                    owsFailDebug("unknown RPRecentCallType: \(callRecord.callType)")
                }
            } else {
                assert(call.individualCall.direction == .incoming)
                let callRecord = TSCall(
                    callType: .incomingMissed,
                    offerType: call.individualCall.offerMediaType,
                    thread: call.individualCall.thread,
                    sentAtTimestamp: call.individualCall.sentAtTimestamp
                )
                databaseStorage.asyncWrite { callRecord.anyInsert(transaction: $0) }
                call.individualCall.callRecord = callRecord
                callUIAdapter.reportMissedCall(call)
            }
            call.individualCall.state = .localHangup
            callService.terminate(call: call)

        case .endedTimeout:
            let description: String

            if call.individualCall.direction == .outgoing {
                description = "timeout for outgoing call"
            } else {
                description = "timeout for incoming call"
            }

            handleFailedCall(failedCall: call, error: SignalCall.CallError.timeout(description: description), shouldResetUI: true, shouldResetRingRTC: false)

        case .endedSignalingFailure, .endedGlareHandlingFailure:
            handleFailedCall(failedCall: call, error: SignalCall.CallError.signaling, shouldResetUI: true, shouldResetRingRTC: false)

        case .endedInternalFailure:
            handleFailedCall(failedCall: call, error: OWSAssertionError("call manager internal error"), shouldResetUI: true, shouldResetRingRTC: false)

        case .endedConnectionFailure:
            handleFailedCall(failedCall: call, error: SignalCall.CallError.disconnected, shouldResetUI: true, shouldResetRingRTC: false)

        case .endedDropped:
            Logger.debug("")

            // An incoming call was dropped, ignoring because we have already
            // failed the call on the screen.

        case .remoteVideoEnable:
            guard call === callService.currentCall else {
                callService.cleanupStaleCall(call)
                return
            }

            call.individualCall.isRemoteVideoEnabled = true

        case .remoteVideoDisable:
            guard call === callService.currentCall else {
                callService.cleanupStaleCall(call)
                return
            }

            call.individualCall.isRemoteVideoEnabled = false

        case .remoteSharingScreenEnable:
            guard call === callService.currentCall else {
                callService.cleanupStaleCall(call)
                return
            }
            call.individualCall.isRemoteSharingScreen = true

        case .remoteSharingScreenDisable:
            guard call === callService.currentCall else {
                callService.cleanupStaleCall(call)
                return
            }
            call.individualCall.isRemoteSharingScreen = false

        case .reconnecting:
            self.handleReconnecting(call: call)

        case .reconnected:
            self.handleReconnected(call: call)

        case .receivedOfferExpired:
            // TODO - This is the case where an incoming offer's timestamp is
            // not within the range +/- 120 seconds of the current system time.
            // At the moment, this is not an issue since we are currently setting
            // the timestamp separately when we receive the offer (above).
            // This should not be a failure, it is just an 'old' call.
            handleMissedCall(call)
            call.individualCall.state = .localFailure
            callService.terminate(call: call)

        case .receivedOfferWhileActive:
            handleMissedCall(call)
            // TODO - This should not be a failure.
            call.individualCall.state = .localFailure
            callService.terminate(call: call)

        case .receivedOfferWithGlare:
            handleMissedCall(call)
            // TODO - This should not be a failure.
            call.individualCall.state = .localFailure
            callService.terminate(call: call)
        }
    }

    public func callManager(_ callManager: CallService.CallManagerType, onUpdateLocalVideoSession call: SignalCall, session: AVCaptureSession?) {
        AssertIsOnMainThread()
        owsAssertDebug(call.isIndividualCall)
        Logger.info("onUpdateLocalVideoSession")

        guard call === callService.currentCall else {
            callService.cleanupStaleCall(call)
            return
        }
    }

    public func callManager(_ callManager: CallService.CallManagerType, onAddRemoteVideoTrack call: SignalCall, track: RTCVideoTrack) {
        AssertIsOnMainThread()
        owsAssertDebug(call.isIndividualCall)
        Logger.info("onAddRemoteVideoTrack")

        guard call === callService.currentCall else {
            callService.cleanupStaleCall(call)
            return
        }

        call.individualCall.remoteVideoTrack = track
    }

    // MARK: - Call Manager Signaling

    public func callManager(_ callManager: CallService.CallManagerType, shouldSendOffer callId: UInt64, call: SignalCall, destinationDeviceId: UInt32?, opaque: Data, callMediaType: CallMediaType) {
        AssertIsOnMainThread()
        owsAssertDebug(call.isIndividualCall)

        Logger.info("shouldSendOffer")

        firstly(on: .global()) { () throws -> Promise<Void> in
            let offerBuilder = SSKProtoCallMessageOffer.builder(id: callId)
            offerBuilder.setOpaque(opaque)
            switch callMediaType {
            case .audioCall: offerBuilder.setType(.offerAudioCall)
            case .videoCall: offerBuilder.setType(.offerVideoCall)
            }

            return try Self.databaseStorage.write { transaction -> Promise<Void> in
                let callMessage = OWSOutgoingCallMessage(
                    thread: call.individualCall.thread,
                    offerMessage: try offerBuilder.build(),
                    destinationDeviceId: NSNumber(value: destinationDeviceId),
                    transaction: transaction)

                return ThreadUtil.enqueueMessagePromise(
                    message: callMessage,
                    limitToCurrentProcessLifetime: true,
                    isHighPriority: true,
                    transaction: transaction
                )
            }
        }.done(on: .main) {
            Logger.info("sent offer message to \(call.individualCall.thread.contactAddress) device: \((destinationDeviceId != nil) ? String(destinationDeviceId!) : "nil")")
            try self.callManager.signalingMessageDidSend(callId: callId)
        }.catch(on: .main) { error in
            Logger.error("failed to send offer message to \(call.individualCall.thread.contactAddress) with error: \(error)")
            self.callManager.signalingMessageDidFail(callId: callId)
        }
    }

    public func callManager(_ callManager: CallService.CallManagerType, shouldSendAnswer callId: UInt64, call: SignalCall, destinationDeviceId: UInt32?, opaque: Data) {
        AssertIsOnMainThread()
        owsAssertDebug(call.isIndividualCall)
        Logger.info("shouldSendAnswer")

        firstly(on: .global()) { () throws -> Promise<Void> in
            let answerBuilder = SSKProtoCallMessageAnswer.builder(id: callId)
            answerBuilder.setOpaque(opaque)

            return try Self.databaseStorage.write { transaction -> Promise<Void> in
                let callMessage = OWSOutgoingCallMessage(
                    thread: call.individualCall.thread,
                    answerMessage: try answerBuilder.build(),
                    destinationDeviceId: NSNumber(value: destinationDeviceId),
                    transaction: transaction)

                return ThreadUtil.enqueueMessagePromise(
                    message: callMessage,
                    limitToCurrentProcessLifetime: true,
                    isHighPriority: true,
                    transaction: transaction
                )
            }
        }.done(on: .main) {
            Logger.debug("sent answer message to \(call.individualCall.thread.contactAddress) device: \((destinationDeviceId != nil) ? String(destinationDeviceId!) : "nil")")
            try self.callManager.signalingMessageDidSend(callId: callId)
        }.catch(on: .main) { error in
            Logger.error("failed to send answer message to \(call.individualCall.thread.contactAddress) with error: \(error)")
            self.callManager.signalingMessageDidFail(callId: callId)
        }
    }

    public func callManager(_ callManager: CallService.CallManagerType, shouldSendIceCandidates callId: UInt64, call: SignalCall, destinationDeviceId: UInt32?, candidates: [Data]) {
        AssertIsOnMainThread()
        owsAssertDebug(call.isIndividualCall)
        Logger.info("shouldSendIceCandidates")

        firstly(on: .global()) { () throws -> Promise<Void> in
            var iceUpdateProtos = [SSKProtoCallMessageIceUpdate]()

            for iceCandidate in candidates {
                let iceUpdateProto: SSKProtoCallMessageIceUpdate
                let iceUpdateBuilder = SSKProtoCallMessageIceUpdate.builder(id: callId)
                iceUpdateBuilder.setOpaque(iceCandidate)

                iceUpdateProto = try iceUpdateBuilder.build()
                iceUpdateProtos.append(iceUpdateProto)
            }

            guard !iceUpdateProtos.isEmpty else {
                throw OWSAssertionError("no ice updates to send")
            }

            return Self.databaseStorage.write { transaction -> Promise<Void> in
                let callMessage = OWSOutgoingCallMessage(
                    thread: call.individualCall.thread,
                    iceUpdateMessages: iceUpdateProtos,
                    destinationDeviceId: NSNumber(value: destinationDeviceId),
                    transaction: transaction)

                return ThreadUtil.enqueueMessagePromise(
                    message: callMessage,
                    limitToCurrentProcessLifetime: true,
                    isHighPriority: true,
                    transaction: transaction
                )
            }
        }.done(on: .main) {
            Logger.debug("sent ice update message to \(call.individualCall.thread.contactAddress) device: \((destinationDeviceId != nil) ? String(destinationDeviceId!) : "nil")")
            try self.callManager.signalingMessageDidSend(callId: callId)
        }.catch(on: .main) { error in
            Logger.error("failed to send ice update message to \(call.individualCall.thread.contactAddress) with error: \(error)")
            callManager.signalingMessageDidFail(callId: callId)
        }
    }

    public func callManager(_ callManager: CallService.CallManagerType, shouldSendHangup callId: UInt64, call: SignalCall, destinationDeviceId: UInt32?, hangupType: HangupType, deviceId: UInt32) {
        AssertIsOnMainThread()
        owsAssertDebug(call.isIndividualCall)
        Logger.info("shouldSendHangup")

        firstly(on: .global()) { () throws -> Promise<Void> in
            let hangupBuilder = SSKProtoCallMessageHangup.builder(id: callId)

            switch hangupType {
            case .normal: hangupBuilder.setType(.hangupNormal)
            case .accepted: hangupBuilder.setType(.hangupAccepted)
            case .declined: hangupBuilder.setType(.hangupDeclined)
            case .busy: hangupBuilder.setType(.hangupBusy)
            case .needPermission: hangupBuilder.setType(.hangupNeedPermission)
            }

            if hangupType != .normal {
                // deviceId is optional and only used when indicated by a hangup due to
                // a call being accepted elsewhere.
                hangupBuilder.setDeviceID(deviceId)
            }

            return try Self.databaseStorage.write { transaction -> Promise<Void> in
                let callMessage = OWSOutgoingCallMessage(
                    thread: call.individualCall.thread,
                    hangupMessage: try hangupBuilder.build(),
                    destinationDeviceId: NSNumber(value: destinationDeviceId),
                    transaction: transaction)

                return ThreadUtil.enqueueMessagePromise(
                    message: callMessage,
                    limitToCurrentProcessLifetime: true,
                    isHighPriority: true,
                    transaction: transaction
                )
            }
        }.done(on: .main) {
            Logger.debug("sent hangup message to \(call.individualCall.thread.contactAddress) device: \((destinationDeviceId != nil) ? String(destinationDeviceId!) : "nil")")
            try self.callManager.signalingMessageDidSend(callId: callId)
        }.catch(on: .main) { error in
            Logger.error("failed to send hangup message to \(call.individualCall.thread.contactAddress) with error: \(error)")
            self.callManager.signalingMessageDidFail(callId: callId)
        }
    }

    public func callManager(_ callManager: CallService.CallManagerType, shouldSendBusy callId: UInt64, call: SignalCall, destinationDeviceId: UInt32?) {
        AssertIsOnMainThread()
        owsAssertDebug(call.isIndividualCall)
        Logger.info("shouldSendBusy")

        firstly(on: .global()) { () throws -> Promise<Void> in
            let busyBuilder = SSKProtoCallMessageBusy.builder(id: callId)

            return try Self.databaseStorage.write { transaction -> Promise<Void> in
                let callMessage = OWSOutgoingCallMessage(
                    thread: call.individualCall.thread,
                    busyMessage: try busyBuilder.build(),
                    destinationDeviceId: NSNumber(value: destinationDeviceId),
                    transaction: transaction)

                return ThreadUtil.enqueueMessagePromise(
                    message: callMessage,
                    limitToCurrentProcessLifetime: true,
                    isHighPriority: true,
                    transaction: transaction
                )
            }
        }.done(on: .main) {
            Logger.debug("sent busy message to \(call.individualCall.thread.contactAddress) device: \((destinationDeviceId != nil) ? String(destinationDeviceId!) : "nil")")
            try self.callManager.signalingMessageDidSend(callId: callId)
        }.catch(on: .main) { error in
            Logger.error("failed to send busy message to \(call.individualCall.thread.contactAddress) with error: \(error)")
            self.callManager.signalingMessageDidFail(callId: callId)
        }
    }

    // MARK: - Support Functions

    /**
     * User didn't answer incoming call
     */
    public func handleMissedCall(_ call: SignalCall, error: SignalCall.CallError? = nil) {
        AssertIsOnMainThread()
        Logger.info("call: \(call)")

        let callType: RPRecentCallType
        switch error {
        case .doNotDisturbEnabled?:
            callType = .incomingMissedBecauseOfDoNotDisturb
        default:
            if call.individualCall?.direction == .outgoing {
                callType = .outgoingMissed
            } else {
                callType = .incomingMissed
            }
        }

        let callRecord: TSCall
        if let existingCallRecord = call.individualCall.callRecord {
            callRecord = existingCallRecord
        } else {
            callRecord = TSCall(
                callType: .incomingMissed,
                offerType: call.individualCall.offerMediaType,
                thread: call.individualCall.thread,
                sentAtTimestamp: call.individualCall.sentAtTimestamp
            )
            call.individualCall.callRecord = callRecord
        }

        switch callRecord.callType {
        case .incomingMissed:
            databaseStorage.asyncWrite { transaction in
                callRecord.updateCallType(callType, transaction: transaction)
                callRecord.anyUpsert(transaction: transaction)
            }
            callUIAdapter.reportMissedCall(call)
        case .incomingIncomplete, .incoming:
            callRecord.updateCallType(callType)
            callUIAdapter.reportMissedCall(call)
        case .outgoingIncomplete:
            callRecord.updateCallType(callType)
        case .incomingMissedBecauseOfChangedIdentity, .incomingDeclined, .outgoingMissed, .outgoing, .incomingAnsweredElsewhere, .incomingDeclinedElsewhere, .incomingBusyElsewhere, .incomingMissedBecauseOfDoNotDisturb:
            owsFailDebug("unexpected RPRecentCallType: \(callRecord.callType)")
            databaseStorage.asyncWrite { transaction in
                callRecord.anyUpsert(transaction: transaction)
            }
        @unknown default:
            databaseStorage.asyncWrite { transaction in
                callRecord.anyUpsert(transaction: transaction)
            }
            owsFailDebug("unknown RPRecentCallType: \(callRecord.callType)")
        }
    }

    func handleAnsweredElsewhere(call: SignalCall) {
        if let existingCallRecord = call.individualCall.callRecord {
            // There should only be an existing call record due to a race where the call is answered
            // simultaneously on multiple devices, and the caller is proceeding with the *other*
            // devices call.
            existingCallRecord.updateCallType(.incomingAnsweredElsewhere)
        } else {
            let callRecord = TSCall(
                callType: .incomingAnsweredElsewhere,
                offerType: call.individualCall.offerMediaType,
                thread: call.individualCall.thread,
                sentAtTimestamp: call.individualCall.sentAtTimestamp
            )
            call.individualCall.callRecord = callRecord
            databaseStorage.asyncWrite { callRecord.anyInsert(transaction: $0) }
        }

        call.individualCall.state = .answeredElsewhere

        // Notify UI
        callUIAdapter.didAnswerElsewhere(call: call)

        callService.terminate(call: call)
    }

    func handleDeclinedElsewhere(call: SignalCall) {
        if let existingCallRecord = call.individualCall.callRecord {
            // There should only be an existing call record due to a race where the call is answered
            // simultaneously on multiple devices, and the caller is proceeding with the *other*
            // devices call.
            existingCallRecord.updateCallType(.incomingDeclinedElsewhere)
        } else {
            let callRecord = TSCall(
                callType: .incomingDeclinedElsewhere,
                offerType: call.individualCall.offerMediaType,
                thread: call.individualCall.thread,
                sentAtTimestamp: call.individualCall.sentAtTimestamp
            )
            call.individualCall.callRecord = callRecord
            databaseStorage.asyncWrite { callRecord.anyInsert(transaction: $0) }
        }

        call.individualCall.state = .declinedElsewhere

        // Notify UI
        callUIAdapter.didDeclineElsewhere(call: call)

        callService.terminate(call: call)
    }

    func handleBusyElsewhere(call: SignalCall) {
        if let existingCallRecord = call.individualCall.callRecord {
            // There should only be an existing call record due to a race where the call is answered
            // simultaneously on multiple devices, and the caller is proceeding with the *other*
            // devices call.
            existingCallRecord.updateCallType(.incomingBusyElsewhere)
        } else {
            let callRecord = TSCall(
                callType: .incomingBusyElsewhere,
                offerType: call.individualCall.offerMediaType,
                thread: call.individualCall.thread,
                sentAtTimestamp: call.individualCall.sentAtTimestamp
            )
            call.individualCall.callRecord = callRecord
            databaseStorage.asyncWrite { callRecord.anyInsert(transaction: $0) }
        }

        call.individualCall.state = .busyElsewhere

        // Notify UI
        callUIAdapter.wasBusyElsewhere(call: call)

        callService.terminate(call: call)
    }

    /**
     * Present UI to begin ringing.
     *
     * This can be performed in response to:
     * - Established communication via WebRTC
     * - Anticipation of an expected future ring.
     *
     * In the former case, compatible ICE messages have been exchanged between the local and remote
     * client and we can ring with confidence that the call will connect.
     *
     * In the latter case, the ring is performed before any messages have been exchanged. This is to satisfy
     * callservicesd which requires that we post a CallKit ring shortly after the NSE wakes the main app.
     */
    private func handleRinging(call: SignalCall, isAnticipatory: Bool = false) {
        AssertIsOnMainThread()
        // Only incoming calls can use the early ring states
        owsAssertDebug(!(call.individualCall.direction == .outgoing && isAnticipatory))
        Logger.info("call: \(call)")

        guard call === callService.currentCall else {
            callService.cleanupStaleCall(call)
            return
        }

        switch call.individualCall.state {
        case .dialing:
            BenchEventComplete(eventId: "call-\(call.localId)")
            call.individualCall.state = .remoteRinging
        case .answering:
            BenchEventComplete(eventId: "call-\(call.localId)")
            call.individualCall.state = isAnticipatory ? .localRinging_Anticipatory : .localRinging_ReadyToAnswer
            self.callUIAdapter.reportIncomingCall(call)
        case .localRinging_Anticipatory:
            // RingRTC became ready during our anticipatory ring. User hasn't tried to answer yet.
            owsAssertDebug(isAnticipatory == false)
            call.individualCall.state = .localRinging_ReadyToAnswer
        case .accepting:
            // The user answered during our early ring, but we've been waiting for RingRTC to tell us to start
            // actually ringing before trying to accept. We can do that now.
            handleAcceptCall(call)
        case .remoteRinging:
            Logger.info("call already ringing. Ignoring \(#function): \(call).")
        case .idle, .connected, .reconnecting, .localFailure, .localHangup, .remoteHangup, .remoteHangupNeedPermission, .remoteBusy, .answeredElsewhere, .declinedElsewhere, .busyElsewhere, .localRinging_ReadyToAnswer:
            owsFailDebug("unexpected call state: \(call.individualCall.state): \(call).")
        }
    }

    private func handleReconnecting(call: SignalCall) {
        AssertIsOnMainThread()
        Logger.info("call: \(call)")

        guard call === callService.currentCall else {
            callService.cleanupStaleCall(call)
            return
        }

        switch call.individualCall.state {
        case .remoteRinging, .localRinging_Anticipatory, .localRinging_ReadyToAnswer, .accepting:
            Logger.debug("disconnect while ringing... we'll keep ringing")
        case .connected:
            call.individualCall.state = .reconnecting
        default:
            owsFailDebug("unexpected call state: \(call.individualCall.state): \(call).")
        }
    }

    private func handleReconnected(call: SignalCall) {
        AssertIsOnMainThread()
        Logger.info("call: \(call)")

        guard call === callService.currentCall else {
            callService.cleanupStaleCall(call)
            return
        }

        switch call.individualCall.state {
        case .reconnecting:
            call.individualCall.state = .connected
        default:
            owsFailDebug("unexpected call state: \(call.individualCall.state): \(call).")
        }
    }

    /**
     * For outgoing call, when the callee has chosen to accept the call.
     * For incoming call, when the local user has chosen to accept the call.
     */
    private func handleConnected(call: SignalCall) {
        AssertIsOnMainThread()
        Logger.info("call: \(call)")

        guard call === callService.currentCall else {
            callService.cleanupStaleCall(call)
            return
        }

        // End the background task.
        call.individualCall.backgroundTask = nil

        call.individualCall.state = .connected

        // We don't risk transmitting any media until the remote client has admitted to being connected.
        ensureAudioState(call: call)

        callService.callManager.setLocalVideoEnabled(enabled: callService.shouldHaveLocalVideoTrack, call: call)
    }

    /**
     * Local user toggled to hold call. Currently only possible via CallKit screen,
     * e.g. when another Call comes in.
     */
    func setIsOnHold(call: SignalCall, isOnHold: Bool) {
        AssertIsOnMainThread()
        Logger.info("call: \(call)")

        guard call === callService.currentCall else {
            callService.cleanupStaleCall(call)
            return
        }

        call.individualCall.isOnHold = isOnHold

        ensureAudioState(call: call)
    }

    @objc
    func handleCallKitStartVideo() {
        AssertIsOnMainThread()

        callService.updateIsLocalVideoMuted(isLocalVideoMuted: false)
    }

    /**
     * RTCIceServers are used when attempting to establish an optimal connection to the other party. SignalService supplies
     * a list of servers, plus we have fallback servers hardcoded in the app.
     */
    private func getIceServers() -> Promise<[RTCIceServer]> {

        return firstly {
            accountManager.getTurnServerInfo()
        }.map(on: .global()) { turnServerInfo -> [RTCIceServer] in
            Logger.debug("got turn server urls: \(turnServerInfo.urls)")

            return turnServerInfo.urls.map { url in
                if url.hasPrefix("turn") {
                    // Only "turn:" servers require authentication. Don't include the credentials to other ICE servers
                    // as 1.) they aren't used, and 2.) the non-turn servers might not be under our control.
                    // e.g. we use a public fallback STUN server.
                    return RTCIceServer(urlStrings: [url], username: turnServerInfo.username, credential: turnServerInfo.password)
                } else {
                    return RTCIceServer(urlStrings: [url])
                }
            } + [IndividualCallService.fallbackIceServer]
        }.recover(on: .global()) { (error: Error) -> Guarantee<[RTCIceServer]> in
            Logger.error("fetching ICE servers failed with error: \(error)")
            Logger.warn("using fallback ICE Servers")

            return Guarantee.value([IndividualCallService.fallbackIceServer])
        }
    }

    public func handleCallKitProviderReset() {
        AssertIsOnMainThread()
        Logger.debug("")

        // Return to a known good state by ending the current call, if any.
        if let call = callService.currentCall {
            handleFailedCall(failedCall: call, error: SignalCall.CallError.providerReset, shouldResetUI: false, shouldResetRingRTC: true)
        }
    }

    // This method should be called when an error occurred for a call from
    // the UI/UX or the RingRTC library.
    //
    // * If we know which call it was, we should update that call's state
    //   to reflect the error.
    // * IFF that call is the current call, we want to terminate it.
    public func handleFailedCall(failedCall: SignalCall, error: Error, shouldResetUI: Bool, shouldResetRingRTC: Bool) {
        AssertIsOnMainThread()
        Logger.debug("")

        let callError: SignalCall.CallError = {
            switch error {
            case let callError as SignalCall.CallError:
                return callError
            default:
                return SignalCall.CallError.externalError(underlyingError: error)
            }
        }()

        switch failedCall.individualCall.state {
        case .answering, .localRinging_Anticipatory, .localRinging_ReadyToAnswer, .accepting:
            assert(failedCall.individualCall.callRecord == nil)
            // call failed before any call record could be created, make one now.
            handleMissedCall(failedCall, error: callError)
        default:
            assert(failedCall.individualCall.callRecord != nil)
        }

        guard !failedCall.individualCall.isEnded else {
            Logger.debug("ignoring error: \(error) for already terminated call: \(failedCall)")
            return
        }

        failedCall.error = callError
        failedCall.individualCall.state = .localFailure

        if shouldResetUI {
            self.callUIAdapter.failCall(failedCall, error: callError)
        }

        if callError.shouldSilentlyDropCall(),
           let callId = failedCall.individualCall.callId {
            // Drop the call explicitly to avoid sending a hangup.
            callManager.drop(callId: callId)
        } else if shouldResetRingRTC {
            callManager.reset()
        }

        Logger.error("call: \(failedCall) failed with error: \(error)")
        callService.terminate(call: failedCall)
    }

    func ensureAudioState(call: SignalCall) {
        owsAssertDebug(call.isIndividualCall)
        let isLocalAudioMuted = call.individualCall.state != .connected || call.individualCall.isMuted || call.individualCall.isOnHold
        callManager.setLocalAudioEnabled(enabled: !isLocalAudioMuted)
    }

    // MARK: CallViewController Timer

    var activeCallTimer: Timer?
    func startCallTimer() {
        AssertIsOnMainThread()

        stopAnyCallTimer()
        assert(self.activeCallTimer == nil)

        guard let call = callService.currentCall else {
            owsFailDebug("Missing call.")
            return
        }

        var hasUsedUpTimerSlop: Bool = false

        self.activeCallTimer = WeakTimer.scheduledTimer(timeInterval: 1, target: self, userInfo: nil, repeats: true) { timer in
            guard call === self.callService.currentCall else {
                owsFailDebug("call has since ended. Timer should have been invalidated.")
                timer.invalidate()
                return
            }
            self.ensureCallScreenPresented(call: call, hasUsedUpTimerSlop: &hasUsedUpTimerSlop)
        }
    }

    func ensureCallScreenPresented(call: SignalCall, hasUsedUpTimerSlop: inout Bool) {
        guard callService.currentCall === call else {
            owsFailDebug("obsolete call: \(call)")
            return
        }

        guard let connectedDate = call.connectedDate else {
            // Ignore; call hasn't connected yet.
            return
        }

        let kMaxViewPresentationDelay: Double = 5
        guard fabs(connectedDate.timeIntervalSinceNow) > kMaxViewPresentationDelay else {
            // Ignore; call connected recently.
            return
        }

        guard !OWSWindowManager.shared.hasCall else {
            // call screen is visible
            return
        }

        guard hasUsedUpTimerSlop else {
            // We hide the call screen synchronously, as soon as the user hangs up the call
            // But it takes a while to communicate the hangup from the UI -> CallKit -> CallService
            // However it's possible the timer fired the *instant* after the user hit the hangup
            // button, so we allow one tick of the timer cycle as slop.
            Logger.verbose("using up timer slop")
            hasUsedUpTimerSlop = true
            return
        }

        owsFailDebug("Call terminated due to missing call view.")
        self.handleFailedCall(failedCall: call, error: OWSAssertionError("Call view didn't present after \(kMaxViewPresentationDelay) seconds"), shouldResetUI: true, shouldResetRingRTC: true)
    }

    func stopAnyCallTimer() {
        AssertIsOnMainThread()

        self.activeCallTimer?.invalidate()
        self.activeCallTimer = nil
    }
}

extension RPRecentCallType: CustomStringConvertible {
    public var description: String {
        NSStringFromCallType(self)
    }
}

extension NSNumber {
    convenience init?(value: UInt32?) {
        guard let value = value else { return nil }
        self.init(value: value)
    }
}

extension TSRecentCallOfferType {
    var asCallMediaType: CallMediaType {
        switch self {
        case .audio: return .audioCall
        case .video: return .videoCall
        }
    }
}
