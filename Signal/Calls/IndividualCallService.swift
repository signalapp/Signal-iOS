//
// Copyright 2016 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import CallKit
import Foundation
import SignalRingRTC
import SignalServiceKit
import SignalUI
import WebRTC

// MARK: - CallService

// This class' state should only be accessed on the main queue.
final class IndividualCallService: CallServiceStateObserver {

    // MARK: Class

    private let callManager: CallService.CallManagerType
    private let callServiceState: CallServiceState

    init(
        callManager: CallService.CallManagerType,
        callServiceState: CallServiceState
    ) {
        self.callManager = callManager
        self.callServiceState = callServiceState
        SwiftSingletons.register(self)
        self.callServiceState.addObserver(self)
    }

    private var audioSession: AudioSession { NSObject.audioSession }
    private var callService: CallService { AppEnvironment.shared.callService }
    private var callUIAdapter: CallUIAdapter { AppEnvironment.shared.callService.callUIAdapter }
    private var contactManager: any ContactManager { NSObject.contactsManager }
    private var databaseStorage: SDSDatabaseStorage { NSObject.databaseStorage }
    private var networkManager: NetworkManager { NSObject.networkManager }
    private var notificationPresenter: NotificationPresenterImpl { NSObject.notificationPresenterImpl }
    private var preferences: Preferences { NSObject.preferences }
    private var profileManager: any ProfileManager { NSObject.profileManager }
    private var tsAccountManager: any TSAccountManager { DependenciesBridge.shared.tsAccountManager }
    private var identityManager: any OWSIdentityManager { DependenciesBridge.shared.identityManager }

    func didUpdateCall(from oldValue: SignalCall?, to newValue: SignalCall?) {
        stopAnyCallTimer()
        if let newValue {
            switch newValue.mode {
            case .individual:
                startCallTimer(for: newValue)
            case .groupThread:
                break
            }
        }
    }

    // MARK: - Call Control Actions

    /**
     * Initiate an outgoing call.
     */
    func handleOutgoingCall(_ call: SignalCall) {
        AssertIsOnMainThread()
        Logger.info("call: \(call)")

        guard callServiceState.currentCall == nil else {
            owsFailDebug("call already exists: \(String(describing: callServiceState.currentCall))")
            return
        }

        // Create a call interaction for outgoing calls immediately.
        call.individualCall.createOrUpdateCallInteractionAsync(callType: .outgoingIncomplete)

        // Get the current local device Id, must be valid for lifetime of the call.
        let localDeviceId = tsAccountManager.storedDeviceIdWithMaybeTransaction

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

        guard callServiceState.currentCall === call else {
            let error = OWSAssertionError("accepting call: \(call) which is different from currentCall: \(callServiceState.currentCall as Optional)")
            handleFailedCall(failedCall: call, error: error, shouldResetUI: true, shouldResetRingRTC: true)
            return
        }

        guard let callId = call.individualCall.callId else {
            handleFailedCall(failedCall: call, error: OWSAssertionError("no callId for call: \(call)"), shouldResetUI: true, shouldResetRingRTC: true)
            return
        }

        Logger.info("Creating call interaction: \(call)")
        call.individualCall.createOrUpdateCallInteractionAsync(callType: .incomingIncomplete)

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

        // Update the interaction now that we've accepted.
        call.individualCall.createOrUpdateCallInteractionAsync(callType: .incoming)

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

        guard call === callServiceState.currentCall else {
            Logger.info("ignoring hangup for obsolete call: \(call)")
            return
        }

        if let callType = call.individualCall.callType {
            if callType == .outgoingIncomplete {
                call.individualCall.createOrUpdateCallInteractionAsync(callType: .outgoingMissed)
            }
        } else if [.localRinging_Anticipatory, .localRinging_ReadyToAnswer, .accepting].contains(call.individualCall.state) {
            call.individualCall.createOrUpdateCallInteractionAsync(callType: .incomingDeclined)
        } else {
            owsFailDebug("missing call record")
        }

        // Make RTC audio inactive early in the hangup process before the state
        // change resulting in any change to the default AudioSession.
        audioSession.isRTCAudioEnabled = false

        call.individualCall.state = .localHangup

        ensureAudioState(call: call)

        callServiceState.terminateCall(call)

        do {
            try callManager.hangup()
        } catch {
            // no point in "failing" the call if the user expressed their intent to hang up
            // and we've already called: `terminate(call: cal)`
            owsFailDebug("error: \(error)")
        }
    }

    // MARK: - Signaling Functions

    private func allowsInboundCallsInThread(_ thread: TSContactThread, transaction: SDSAnyReadTransaction) -> Bool {
        // If the thread is in our whitelist, then we've either trusted it manually
        // or it's a chat with someone in our system contacts.
        return profileManager.isThread(inProfileWhitelist: thread, transaction: transaction)
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

    private func getIdentityKeys(thread: TSContactThread, transaction tx: SDSAnyReadTransaction) -> CallIdentityKeys? {
        guard let localIdentityKey = identityManager.identityKeyPair(for: .aci, tx: tx.asV2Read)?.publicKey else {
            owsFailDebug("missing localIdentityKey")
            return nil
        }
        guard let contactIdentityKey = identityManager.identityKey(for: thread.contactAddress, tx: tx.asV2Read) else {
            owsFailDebug("missing contactIdentityKey")
            return nil
        }
        return CallIdentityKeys(localIdentityKey: localIdentityKey, contactIdentityKey: contactIdentityKey)
    }

    private func prepareIncomingIndividualCall(
        callId: UInt64,
        thread: TSContactThread,
        sentAtTimestamp: UInt64,
        callType: SSKProtoCallMessageOfferType
    ) -> SignalCall {
        AssertIsOnMainThread()

        let offerMediaType: TSRecentCallOfferType
        switch callType {
        case .offerAudioCall:
            offerMediaType = .audio
        case .offerVideoCall:
            offerMediaType = .video
        }

        let individualCall = IndividualCall.incomingIndividualCall(
            callId: callId,
            thread: thread,
            sentAtTimestamp: sentAtTimestamp,
            offerMediaType: offerMediaType
        )

        let newCall = SignalCall(individualCall: individualCall)

        callServiceState.addCall(newCall)

        return newCall
    }

    /**
     * Received an incoming call Offer from call initiator.
     */
    public func handleReceivedOffer(
        thread: TSContactThread,
        callId: UInt64,
        sourceDevice: UInt32,
        opaque: Data?,
        sentAtTimestamp: UInt64,
        serverReceivedTimestamp: UInt64,
        serverDeliveryTimestamp: UInt64,
        callType: SSKProtoCallMessageOfferType,
        transaction: SDSAnyWriteTransaction
    ) {
        AssertIsOnMainThread()
        Logger.info("callId: \(callId), thread: \(thread.contactAddress)")

        guard let opaque = opaque else {
            Logger.debug("opaque not received for offer, remote should update")
            return
        }

        let newCall = prepareIncomingIndividualCall(
            callId: callId,
            thread: thread,
            sentAtTimestamp: sentAtTimestamp,
            callType: callType
        )

        guard tsAccountManager.registrationState(tx: transaction.asV2Read).isRegistered else {
            Logger.warn("user is not registered, skipping call.")
            newCall.individualCall.callEventInserter.createOrUpdate(callType: .incomingMissed, tx: transaction)

            newCall.individualCall.state = .localFailure
            callServiceState.terminateCall(newCall)

            return
        }

        if let untrustedIdentity = identityManager.untrustedIdentityForSending(
            to: thread.contactAddress,
            untrustedThreshold: nil,
            tx: transaction.asV2Read
        ) {
            Logger.warn("missed a call due to untrusted identity: \(newCall)")

            switch untrustedIdentity.verificationState {
            case .verified, .defaultAcknowledged:
                owsFailDebug("shouldn't have missed a call due to untrusted identity if the identity is verified")
                let sentAtTimestamp = Date(millisecondsSince1970: newCall.individualCall.sentAtTimestamp)
                self.notificationPresenter.presentMissedCall(
                    newCall,
                    caller: thread.contactAddress,
                    sentAt: sentAtTimestamp
                )
            case .default:
                self.notificationPresenter.presentMissedCallBecauseOfNewIdentity(
                    call: newCall,
                    caller: thread.contactAddress
                )
            case .noLongerVerified:
                self.notificationPresenter.presentMissedCallBecauseOfNoLongerVerifiedIdentity(
                    call: newCall,
                    caller: thread.contactAddress
                )
            }

            newCall.individualCall.callEventInserter.createOrUpdate(callType: .incomingMissedBecauseOfChangedIdentity, tx: transaction)

            newCall.individualCall.state = .localFailure
            callServiceState.terminateCall(newCall)

            return
        }

        guard let identityKeys = getIdentityKeys(thread: thread, transaction: transaction) else {
            owsFailDebug("missing identity keys, skipping call.")
            newCall.individualCall.callEventInserter.createOrUpdate(callType: .incomingMissed, tx: transaction)

            newCall.individualCall.state = .localFailure
            callServiceState.terminateCall(newCall)

            return
        }

        guard allowsInboundCallsInThread(thread, transaction: transaction) else {
            Logger.info("Ignoring call offer from \(thread.contactAddress) due to insufficient permissions.")

            // Send the need permission message to the caller, so they know why we rejected their call.
            let localDeviceId = tsAccountManager.storedDeviceId(tx: transaction.asV2Read)
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
            newCall.individualCall.callEventInserter.createOrUpdate(callType: .incomingMissed, tx: transaction)

            newCall.individualCall.state = .localFailure
            callServiceState.terminateCall(newCall)

            return
        }

        Logger.debug("Enable backgroundTask")
        let backgroundTask: OWSBackgroundTask? = OWSBackgroundTask(label: "\(#function)", completionBlock: { status in
            AssertIsOnMainThread()

            guard status == .expired else {
                return
            }

            // See if the newCall actually became the currentCall.
            guard case .individual(let currentCall) = self.callServiceState.currentCall?.mode, newCall === currentCall else {
                Logger.warn("ignoring obsolete call")
                return
            }

            let error = CallError.timeout(description: "background task time ran out before call connected")
            self.handleFailedCall(failedCall: newCall, error: error, shouldResetUI: true, shouldResetRingRTC: true)
        })

        newCall.individualCall.backgroundTask = backgroundTask

        var messageAgeSec: UInt64 = 0
        if serverReceivedTimestamp > 0 && serverDeliveryTimestamp >= serverReceivedTimestamp {
            messageAgeSec = (serverDeliveryTimestamp - serverReceivedTimestamp) / 1000
        }

        // Get the current local device Id, must be valid for lifetime of the call.
        let localDeviceId = tsAccountManager.storedDeviceId(tx: transaction.asV2Read)
        let isPrimaryDevice = tsAccountManager.registrationState(tx: transaction.asV2Read).isPrimaryDevice ?? true

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
    public func handleReceivedAnswer(thread: TSContactThread, callId: UInt64, sourceDevice: UInt32, opaque: Data?) {
        AssertIsOnMainThread()
        Logger.info("callId: \(callId), thread: \(thread.contactAddress)")

        guard let opaque = opaque else {
            Logger.debug("opaque not received for answer, remote should update")
            return
        }

        guard let identityKeys = getIdentityKeys(thread: thread) else {
            if let currentCall = callServiceState.currentCall, currentCall.individualCall?.callId == callId {
                handleFailedCall(failedCall: currentCall, error: OWSAssertionError("missing identity keys"), shouldResetUI: true, shouldResetRingRTC: true)
            }
            return
        }

        do {
            try callManager.receivedAnswer(sourceDevice: sourceDevice, callId: callId, opaque: opaque, senderIdentityKey: identityKeys.contactIdentityKey, receiverIdentityKey: identityKeys.localIdentityKey)
        } catch {
            owsFailDebug("error: \(error)")
            if let currentCall = callServiceState.currentCall, currentCall.individualCall?.callId == callId {
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
            if let currentCall = callServiceState.currentCall, currentCall.individualCall?.callId == callId {
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
            if let currentCall = callServiceState.currentCall, currentCall.individualCall?.callId == callId {
                handleFailedCall(failedCall: currentCall, error: error, shouldResetUI: true, shouldResetRingRTC: true)
            }
        }
    }

    // MARK: - Call Manager Events

    public func callManager(_ callManager: CallService.CallManagerType, shouldStartCall call: SignalCall, callId: UInt64, isOutgoing: Bool, callMediaType: CallMediaType, shouldEarlyRing: Bool) {
        AssertIsOnMainThread()
        Logger.info("call: \(call)")

        if shouldEarlyRing {
            if !isOutgoing {
                // If we are using the NSE, we need to kick off a ring ASAP in case this incoming call
                // has resulted in the NSE waking up the main app.
                Logger.info("Performing early ring")
                handleRinging(call: call, isAnticipatory: true)
            } else {
                owsFailDebug("Cannot early ring an outgoing call")
            }
        }

        // Start the call, asynchronously.
        Task { @MainActor in
            do {
                let iceServers = try await self.getIceServers()
                guard self.callServiceState.currentCall === call else {
                    Logger.debug("call has since ended")
                    return
                }

                var isUnknownCaller = false
                if call.individualCall.direction == .incoming {
                    isUnknownCaller = self.databaseStorage.read { tx in
                        return self.contactManager.fetchSignalAccount(for: call.individualCall.thread.contactAddress, transaction: tx) == nil
                    }
                    if isUnknownCaller {
                        Logger.warn("Using relay server because remote user is an unknown caller")
                    }
                }

                let useTurnOnly = isUnknownCaller || self.preferences.doCallsHideIPAddress

                let useLowData = self.callService.shouldUseLowDataWithSneakyTransaction(for: NetworkRoute(localAdapterType: .unknown))
                Logger.info("Configuring call for \(useLowData ? "low" : "standard") data")

                // Tell the Call Manager to proceed with its active call.
                try self.callManager.proceed(callId: callId, iceServers: iceServers, hideIp: useTurnOnly, videoCaptureController: call.videoCaptureController, dataMode: useLowData ? .low : .normal, audioLevelsIntervalMillis: nil)
            } catch {
                owsFailDebug("\(error)")
                guard call === self.callServiceState.currentCall else {
                    return
                }

                callManager.drop(callId: callId)
                self.handleFailedCall(failedCall: call, error: error, shouldResetUI: true, shouldResetRingRTC: false)
            }
        }
    }

    public func callManager(_ callManager: CallService.CallManagerType, onEvent call: SignalCall, event: CallManagerEvent) {
        AssertIsOnMainThread()
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
            defer {
                callUIAdapter.recipientAcceptedCall(call.mode)
            }

            guard call === callServiceState.currentCall else {
                cleanUpStaleCall(call)
                return
            }

            // Set the audio session configuration before audio is enabled in WebRTC
            // via recipientAcceptedCall().
            handleConnected(call: call)

            // Update the call interaction now that we've connected.
            call.individualCall.createOrUpdateCallInteractionAsync(callType: .outgoing)

        case .endedLocalHangup:
            Logger.debug("")
            // nothing further to do - already handled in handleLocalHangupCall().

        case .endedRemoteHangup:
            guard call === callServiceState.currentCall else {
                cleanUpStaleCall(call)
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

            callServiceState.terminateCall(call)

        case .endedRemoteHangupNeedPermission:
            guard call === callServiceState.currentCall else {
                cleanUpStaleCall(call)
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

            callServiceState.terminateCall(call)

        case .endedRemoteHangupAccepted:
            guard call === callServiceState.currentCall else {
                cleanUpStaleCall(call)
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
            guard call === callServiceState.currentCall else {
                cleanUpStaleCall(call)
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
            guard call === callServiceState.currentCall else {
                cleanUpStaleCall(call)
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
            guard call === callServiceState.currentCall else {
                cleanUpStaleCall(call)
                return
            }

            assert(call.individualCall.direction == .outgoing)
            call.individualCall.createOrUpdateCallInteractionAsync(callType: .outgoingMissed)

            call.individualCall.state = .remoteBusy

            // Notify UI
            callUIAdapter.remoteBusy(call)

            callServiceState.terminateCall(call)

        case .endedRemoteGlare, .endedRemoteReCall:
            guard call === callServiceState.currentCall else {
                cleanUpStaleCall(call)
                return
            }

            if let callType = call.individualCall.callType {
                switch callType {
                case .outgoingMissed, .incomingDeclined, .incomingMissed, .incomingMissedBecauseOfChangedIdentity, .incomingAnsweredElsewhere, .incomingDeclinedElsewhere, .incomingBusyElsewhere, .incomingMissedBecauseOfDoNotDisturb, .incomingMissedBecauseBlockedSystemContact:
                    // already handled and ended, don't update the call record.
                    break
                case .incomingIncomplete, .incoming:
                    call.individualCall.createOrUpdateCallInteractionAsync(callType: .incomingMissed)
                    callUIAdapter.reportMissedCall(call, individualCall: call.individualCall)
                case .outgoingIncomplete:
                    call.individualCall.createOrUpdateCallInteractionAsync(callType: .outgoingMissed)
                    callUIAdapter.remoteBusy(call)
                case .outgoing:
                    call.individualCall.createOrUpdateCallInteractionAsync(callType: .outgoingMissed)
                    callUIAdapter.reportMissedCall(call, individualCall: call.individualCall)
                @unknown default:
                    owsFailDebug("unknown RPRecentCallType: \(callType)")
                }
            } else {
                assert(call.individualCall.direction == .incoming)
                call.individualCall.createOrUpdateCallInteractionAsync(callType: .incomingMissed)
                callUIAdapter.reportMissedCall(call, individualCall: call.individualCall)
            }
            call.individualCall.state = .localHangup
            callServiceState.terminateCall(call)

        case .endedTimeout:
            let description: String

            if call.individualCall.direction == .outgoing {
                description = "timeout for outgoing call"
            } else {
                description = "timeout for incoming call"
            }

            handleFailedCall(failedCall: call, error: CallError.timeout(description: description), shouldResetUI: true, shouldResetRingRTC: false)

        case .endedSignalingFailure, .endedGlareHandlingFailure:
            handleFailedCall(failedCall: call, error: CallError.signaling, shouldResetUI: true, shouldResetRingRTC: false)

        case .endedInternalFailure:
            handleFailedCall(failedCall: call, error: OWSAssertionError("call manager internal error"), shouldResetUI: true, shouldResetRingRTC: false)

        case .endedConnectionFailure:
            handleFailedCall(failedCall: call, error: CallError.disconnected, shouldResetUI: true, shouldResetRingRTC: false)

        case .endedDropped:
            Logger.debug("")

            // An incoming call was dropped, ignoring because we have already
            // failed the call on the screen.

        case .remoteVideoEnable:
            guard call === callServiceState.currentCall else {
                cleanUpStaleCall(call)
                return
            }

            call.individualCall.isRemoteVideoEnabled = true

        case .remoteVideoDisable:
            guard call === callServiceState.currentCall else {
                cleanUpStaleCall(call)
                return
            }

            call.individualCall.isRemoteVideoEnabled = false

        case .remoteSharingScreenEnable:
            guard call === callServiceState.currentCall else {
                cleanUpStaleCall(call)
                return
            }
            call.individualCall.isRemoteSharingScreen = true

        case .remoteSharingScreenDisable:
            guard call === callServiceState.currentCall else {
                cleanUpStaleCall(call)
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
            callServiceState.terminateCall(call)

        case .receivedOfferWhileActive:
            handleMissedCall(call)
            // TODO - This should not be a failure.
            call.individualCall.state = .localFailure
            callServiceState.terminateCall(call)

        case .receivedOfferWithGlare:
            handleMissedCall(call)
            // TODO - This should not be a failure.
            call.individualCall.state = .localFailure
            callServiceState.terminateCall(call)
        }
    }

    public func callManager(_ callManager: CallService.CallManagerType, onUpdateLocalVideoSession call: SignalCall, session: AVCaptureSession?) {
        AssertIsOnMainThread()
        Logger.info("onUpdateLocalVideoSession")

        guard call === callServiceState.currentCall else {
            cleanUpStaleCall(call)
            return
        }
    }

    public func callManager(_ callManager: CallService.CallManagerType, onAddRemoteVideoTrack call: SignalCall, track: RTCVideoTrack) {
        AssertIsOnMainThread()
        Logger.info("onAddRemoteVideoTrack")

        guard call === callServiceState.currentCall else {
            cleanUpStaleCall(call)
            return
        }

        call.individualCall.remoteVideoTrack = track
    }

    // MARK: - Call Manager Signaling

    public func callManager(_ callManager: CallService.CallManagerType, shouldSendOffer callId: UInt64, call: SignalCall, destinationDeviceId: UInt32?, opaque: Data, callMediaType: CallMediaType) {
        AssertIsOnMainThread()

        Logger.info("shouldSendOffer")

        Task { @MainActor in
            do {
                let offerBuilder = SSKProtoCallMessageOffer.builder(id: callId)
                offerBuilder.setOpaque(opaque)
                switch callMediaType {
                case .audioCall: offerBuilder.setType(.offerAudioCall)
                case .videoCall: offerBuilder.setType(.offerVideoCall)
                }
                let sendPromise = try await self.databaseStorage.awaitableWrite { tx -> Promise<Void> in
                    let callMessage = OWSOutgoingCallMessage(
                        thread: call.individualCall.thread,
                        offerMessage: try offerBuilder.build(),
                        destinationDeviceId: NSNumber(value: destinationDeviceId),
                        transaction: tx
                    )
                    let preparedMessage = PreparedOutgoingMessage.preprepared(
                        transientMessageWithoutAttachments: callMessage
                    )
                    return ThreadUtil.enqueueMessagePromise(
                        message: preparedMessage,
                        limitToCurrentProcessLifetime: true,
                        isHighPriority: true,
                        transaction: tx
                    )
                }
                try await sendPromise.awaitable()
                Logger.info("sent offer message to \(call.individualCall.thread.contactAddress) device: \((destinationDeviceId != nil) ? String(destinationDeviceId!) : "nil")")
                try self.callManager.signalingMessageDidSend(callId: callId)
            } catch {
                Logger.error("failed to send offer message to \(call.individualCall.thread.contactAddress) with error: \(error)")
                self.callManager.signalingMessageDidFail(callId: callId)
            }
        }
    }

    public func callManager(_ callManager: CallService.CallManagerType, shouldSendAnswer callId: UInt64, call: SignalCall, destinationDeviceId: UInt32?, opaque: Data) {
        AssertIsOnMainThread()
        Logger.info("shouldSendAnswer")

        Task { @MainActor in
            do {
                let answerBuilder = SSKProtoCallMessageAnswer.builder(id: callId)
                answerBuilder.setOpaque(opaque)
                let sendPromise = try await self.databaseStorage.awaitableWrite { tx -> Promise<Void> in
                    let callMessage = OWSOutgoingCallMessage(
                        thread: call.individualCall.thread,
                        answerMessage: try answerBuilder.build(),
                        destinationDeviceId: NSNumber(value: destinationDeviceId),
                        transaction: tx
                    )
                    let preparedMessage = PreparedOutgoingMessage.preprepared(
                        transientMessageWithoutAttachments: callMessage
                    )
                    return ThreadUtil.enqueueMessagePromise(
                        message: preparedMessage,
                        limitToCurrentProcessLifetime: true,
                        isHighPriority: true,
                        transaction: tx
                    )
                }
                try await sendPromise.awaitable()
                Logger.debug("sent answer message to \(call.individualCall.thread.contactAddress) device: \((destinationDeviceId != nil) ? String(destinationDeviceId!) : "nil")")
                try self.callManager.signalingMessageDidSend(callId: callId)
            } catch {
                Logger.error("failed to send answer message to \(call.individualCall.thread.contactAddress) with error: \(error)")
                self.callManager.signalingMessageDidFail(callId: callId)
            }
        }
    }

    public func callManager(_ callManager: CallService.CallManagerType, shouldSendIceCandidates callId: UInt64, call: SignalCall, destinationDeviceId: UInt32?, candidates: [Data]) {
        AssertIsOnMainThread()
        Logger.info("shouldSendIceCandidates")

        Task { @MainActor in
            do {
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

                let sendPromise = await self.databaseStorage.awaitableWrite { tx -> Promise<Void> in
                    let callMessage = OWSOutgoingCallMessage(
                        thread: call.individualCall.thread,
                        iceUpdateMessages: iceUpdateProtos,
                        destinationDeviceId: NSNumber(value: destinationDeviceId),
                        transaction: tx
                    )
                    let preparedMessage = PreparedOutgoingMessage.preprepared(
                        transientMessageWithoutAttachments: callMessage
                    )
                    return ThreadUtil.enqueueMessagePromise(
                        message: preparedMessage,
                        limitToCurrentProcessLifetime: true,
                        isHighPriority: true,
                        transaction: tx
                    )
                }
                try await sendPromise.awaitable()
                Logger.debug("sent ice update message to \(call.individualCall.thread.contactAddress) device: \((destinationDeviceId != nil) ? String(destinationDeviceId!) : "nil")")
                try self.callManager.signalingMessageDidSend(callId: callId)
            } catch {
                Logger.error("failed to send ice update message to \(call.individualCall.thread.contactAddress) with error: \(error)")
                callManager.signalingMessageDidFail(callId: callId)
            }
        }
    }

    public func callManager(_ callManager: CallService.CallManagerType, shouldSendHangup callId: UInt64, call: SignalCall, destinationDeviceId: UInt32?, hangupType: HangupType, deviceId: UInt32) {
        AssertIsOnMainThread()
        Logger.info("shouldSendHangup")

        Task { @MainActor in
            do {
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

                let sendPromise = try await self.databaseStorage.awaitableWrite { tx -> Promise<Void> in
                    let callMessage = OWSOutgoingCallMessage(
                        thread: call.individualCall.thread,
                        hangupMessage: try hangupBuilder.build(),
                        destinationDeviceId: NSNumber(value: destinationDeviceId),
                        transaction: tx
                    )
                    let preparedMessage = PreparedOutgoingMessage.preprepared(
                        transientMessageWithoutAttachments: callMessage
                    )
                    return ThreadUtil.enqueueMessagePromise(
                        message: preparedMessage,
                        limitToCurrentProcessLifetime: true,
                        isHighPriority: true,
                        transaction: tx
                    )
                }
                try await sendPromise.awaitable()
                Logger.debug("sent hangup message to \(call.individualCall.thread.contactAddress) device: \((destinationDeviceId != nil) ? String(destinationDeviceId!) : "nil")")
                try self.callManager.signalingMessageDidSend(callId: callId)
            } catch {
                Logger.error("failed to send hangup message to \(call.individualCall.thread.contactAddress) with error: \(error)")
                self.callManager.signalingMessageDidFail(callId: callId)
            }
        }
    }

    public func callManager(_ callManager: CallService.CallManagerType, shouldSendBusy callId: UInt64, call: SignalCall, destinationDeviceId: UInt32?) {
        AssertIsOnMainThread()
        Logger.info("shouldSendBusy")

        Task { @MainActor in
            do {
                let busyBuilder = SSKProtoCallMessageBusy.builder(id: callId)

                let sendPromise = try await self.databaseStorage.awaitableWrite { tx -> Promise<Void> in
                    let callMessage = OWSOutgoingCallMessage(
                        thread: call.individualCall.thread,
                        busyMessage: try busyBuilder.build(),
                        destinationDeviceId: NSNumber(value: destinationDeviceId),
                        transaction: tx
                    )
                    let preparedMessage = PreparedOutgoingMessage.preprepared(
                        transientMessageWithoutAttachments: callMessage
                    )
                    return ThreadUtil.enqueueMessagePromise(
                        message: preparedMessage,
                        limitToCurrentProcessLifetime: true,
                        isHighPriority: true,
                        transaction: tx
                    )
                }
                try await sendPromise.awaitable()
                Logger.debug("sent busy message to \(call.individualCall.thread.contactAddress) device: \((destinationDeviceId != nil) ? String(destinationDeviceId!) : "nil")")
                try self.callManager.signalingMessageDidSend(callId: callId)
            } catch {
                Logger.error("failed to send busy message to \(call.individualCall.thread.contactAddress) with error: \(error)")
                self.callManager.signalingMessageDidFail(callId: callId)
            }
        }
    }

    // MARK: - Support Functions

    /**
     * User didn't answer incoming call
     */
    public func handleMissedCall(_ call: SignalCall, error: CallError? = nil) {
        AssertIsOnMainThread()
        Logger.info("call: \(call)")

        let callType: RPRecentCallType
        switch error {
        case .doNotDisturbEnabled?:
            callType = .incomingMissedBecauseOfDoNotDisturb
        case .contactIsBlocked:
            callType = .incomingMissedBecauseBlockedSystemContact
        default:
            if call.individualCall?.direction == .outgoing {
                callType = .outgoingMissed
            } else {
                callType = .incomingMissed
            }
        }

        let oldCallType = call.individualCall.callType
        call.individualCall.createOrUpdateCallInteractionAsync(callType: callType)

        switch oldCallType {
        case .incomingMissed, .none:
            callUIAdapter.reportMissedCall(call, individualCall: call.individualCall)
        case .incomingIncomplete, .incoming:
            callUIAdapter.reportMissedCall(call, individualCall: call.individualCall)
        case .outgoingIncomplete, .incomingDeclined, .incomingDeclinedElsewhere, .incomingAnsweredElsewhere:
            break
        case .incomingMissedBecauseOfChangedIdentity, .outgoingMissed, .outgoing, .incomingBusyElsewhere, .incomingMissedBecauseOfDoNotDisturb, .incomingMissedBecauseBlockedSystemContact:
            owsFailDebug("unexpected RPRecentCallType: \(String(describing: oldCallType))")
        @unknown default:
            owsFailDebug("unknown RPRecentCallType: \(String(describing: oldCallType))")
        }
    }

    func handleAnsweredElsewhere(call: SignalCall) {
        call.individualCall.createOrUpdateCallInteractionAsync(callType: .incomingAnsweredElsewhere)

        call.individualCall.state = .answeredElsewhere

        // Notify UI
        callUIAdapter.didAnswerElsewhere(call: call)

        callServiceState.terminateCall(call)
    }

    func handleDeclinedElsewhere(call: SignalCall) {
        call.individualCall.createOrUpdateCallInteractionAsync(callType: .incomingDeclinedElsewhere)

        call.individualCall.state = .declinedElsewhere

        // Notify UI
        callUIAdapter.didDeclineElsewhere(call: call)

        callServiceState.terminateCall(call)
    }

    func handleBusyElsewhere(call: SignalCall) {
        call.individualCall.createOrUpdateCallInteractionAsync(callType: .incomingBusyElsewhere)

        call.individualCall.state = .busyElsewhere

        // Notify UI
        callUIAdapter.wasBusyElsewhere(call: call)

        callServiceState.terminateCall(call)
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

        guard call === callServiceState.currentCall else {
            cleanUpStaleCall(call)
            return
        }

        switch call.individualCall.state {
        case .dialing:
            call.individualCall.state = .remoteRinging
        case .answering:
            call.individualCall.state = isAnticipatory ? .localRinging_Anticipatory : .localRinging_ReadyToAnswer
            callUIAdapter.reportIncomingCall(call)
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

        guard call === callServiceState.currentCall else {
            cleanUpStaleCall(call)
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

        guard call === callServiceState.currentCall else {
            cleanUpStaleCall(call)
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
        owsAssert(call === callServiceState.currentCall)
        Logger.info("call: \(call)")

        // End the background task.
        call.individualCall.backgroundTask = nil

        call.individualCall.state = .connected

        // We don't risk transmitting any media until the remote client has admitted to being connected.
        ensureAudioState(call: call)

        callService.updateIsVideoEnabled()
    }

    /**
     * Local user toggled to hold call. Currently only possible via CallKit screen,
     * e.g. when another Call comes in.
     */
    func setIsOnHold(call: SignalCall, isOnHold: Bool) {
        AssertIsOnMainThread()
        Logger.info("call: \(call)")

        guard call === callServiceState.currentCall else {
            cleanUpStaleCall(call)
            return
        }

        call.individualCall.isOnHold = isOnHold

        ensureAudioState(call: call)
    }

    /**
     * RTCIceServers are used when attempting to establish an optimal
     * connection to the other party. SignalService supplies a list of servers.
     */
    private func getIceServers() async throws -> [RTCIceServer] {
        let tsi = try await self.getTurnServerInfo()
        Logger.debug("got turn server urls: \(tsi.urls) and \(tsi.urlsWithIps)")

        // prioritize ip options by putting them first
        // only provide hostname for ip based options
        return tsi.urlsWithIps.map { url in
            return RTCIceServer(urlStrings: [url], username: tsi.username, credential: tsi.password, tlsCertPolicy: RTCTlsCertPolicy.secure, hostname: tsi.hostname)
        } + tsi.urls.map { url in
            return RTCIceServer(urlStrings: [url], username: tsi.username, credential: tsi.password)
        }
    }

    private func getTurnServerInfo() async throws -> TurnServerInfo {
        let request = OWSRequestFactory.turnServerInfoRequest()
        let response = try await self.networkManager.makePromise(request: request).awaitable()
        guard
            let json = response.responseBodyJson,
            let responseDictionary = json as? [String: AnyObject],
            let turnServerInfo = TurnServerInfo(attributes: responseDictionary)
        else {
            throw OWSAssertionError("Missing or invalid JSON")
        }
        return turnServerInfo
    }

    public func handleCallKitProviderReset() {
        AssertIsOnMainThread()
        Logger.debug("")

        // Return to a known good state by ending the current call, if any.
        if let call = callServiceState.currentCall {
            handleFailedCall(failedCall: call, error: CallError.providerReset, shouldResetUI: false, shouldResetRingRTC: true)
        }
    }

    func cleanUpStaleCall(_ staleCall: SignalCall, function: StaticString = #function, line: UInt = #line) {
        assert(staleCall !== callServiceState.currentCall)
        if let currentCall = callServiceState.currentCall {
            let error = OWSAssertionError("trying \(function):\(line) for call: \(staleCall) which is not currentCall: \(currentCall as Optional)")
            handleFailedCall(failedCall: staleCall, error: error, shouldResetUI: false, shouldResetRingRTC: true)
        } else {
            Logger.info("ignoring \(function):\(line) for call: \(staleCall) since currentCall has ended.")
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

        let callError = CallError.wrapErrorIfNeeded(error)

        switch failedCall.individualCall.state {
        case .answering, .localRinging_Anticipatory, .localRinging_ReadyToAnswer, .accepting:
            assert(failedCall.individualCall.callType == nil)
            // call failed before any call record could be created, make one now.
            handleMissedCall(failedCall, error: callError)
        default:
            assert(failedCall.individualCall.callType != nil)
        }

        guard !failedCall.individualCall.isEnded else {
            Logger.debug("ignoring error: \(error) for already terminated call: \(failedCall)")
            return
        }

        failedCall.individualCall.error = callError
        failedCall.individualCall.state = .localFailure

        if shouldResetUI {
            callUIAdapter.failCall(failedCall, error: callError)
        }

        if callError.shouldSilentlyDropCall(), let callId = failedCall.individualCall.callId {
            // Drop the call explicitly to avoid sending a hangup.
            callManager.drop(callId: callId)
        } else if shouldResetRingRTC {
            callManager.reset()
        }

        Logger.error("call: \(failedCall) failed with error: \(error)")
        callServiceState.terminateCall(failedCall)
    }

    func ensureAudioState(call: SignalCall) {
        let isLocalAudioMuted = call.individualCall.state != .connected || call.individualCall.isMuted || call.individualCall.isOnHold
        callManager.setLocalAudioEnabled(enabled: !isLocalAudioMuted)
    }

    // MARK: CallViewController Timer

    private var activeCallTimer: Timer?
    func startCallTimer(for call: SignalCall) {
        AssertIsOnMainThread()

        var hasUsedUpTimerSlop: Bool = false

        assert(self.activeCallTimer == nil)
        self.activeCallTimer = WeakTimer.scheduledTimer(timeInterval: 1, target: self, userInfo: nil, repeats: true) { timer in
            guard call === self.callServiceState.currentCall else {
                owsFailDebug("call has since ended. Timer should have been invalidated.")
                timer.invalidate()
                return
            }
            self.ensureCallScreenPresented(call: call, hasUsedUpTimerSlop: &hasUsedUpTimerSlop)
        }
    }

    private func ensureCallScreenPresented(call: SignalCall, hasUsedUpTimerSlop: inout Bool) {
        guard let connectedDate = call.commonState.connectedDate else {
            // Ignore; call hasn't connected yet.
            return
        }

        let kMaxViewPresentationDelay: UInt64 = 5
        guard MonotonicDate() - connectedDate > kMaxViewPresentationDelay*NSEC_PER_SEC else {
            // Ignore; call connected recently.
            return
        }

        guard !WindowManager.shared.hasCall else {
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
        self.handleFailedCall(
            failedCall: call,
            error: OWSAssertionError("Call view didn't present after \(kMaxViewPresentationDelay) seconds"),
            shouldResetUI: true,
            shouldResetRingRTC: true
        )
    }

    private func stopAnyCallTimer() {
        AssertIsOnMainThread()

        self.activeCallTimer?.invalidate()
        self.activeCallTimer = nil
    }

    enum InteractionUpdateMethod {
        case writeAsync
        case inTransaction(SDSAnyWriteTransaction)
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

private extension SignalCall {
    var individualCall: IndividualCall! {
        switch self.mode {
        case .individual(let individualCall):
            return individualCall
        case .groupThread:
            owsFail("Must have individual call.")
        }
    }
}
