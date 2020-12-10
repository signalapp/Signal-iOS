//
//  Copyright (c) 2020 Open Whisper Systems. All rights reserved.
//

import Foundation
import PromiseKit
import SignalRingRTC
import WebRTC
import SignalServiceKit
import SignalMessaging

// MARK: - CallService

// This class' state should only be accessed on the main queue.
@objc final public class IndividualCallService: NSObject {
    // MARK: - Properties

    // Exposed by environment.m

    @objc public var callUIAdapter: CallUIAdapter!

    // MARK: Class

    static let fallbackIceServer = RTCIceServer(urlStrings: ["stun:stun1.l.google.com:19302"])

    @objc public override init() {
        super.init()

        SwiftSingletons.register(self)
    }

    // MARK: - Dependencies

    private var callService: CallService {
        return AppEnvironment.shared.callService
    }

    private var callManager: CallService.CallManagerType {
        return callService.callManager
    }

    private var contactsManager: OWSContactsManager {
        return Environment.shared.contactsManager
    }

    private var messageSender: MessageSender {
        return SSKEnvironment.shared.messageSender
    }

    private var accountManager: AccountManager {
        return AppEnvironment.shared.accountManager
    }

    private var tsAccountManager: TSAccountManager {
        return .shared()
    }

    private var notificationPresenter: NotificationPresenter {
        return AppEnvironment.shared.notificationPresenter
    }

    private var databaseStorage: SDSDatabaseStorage {
        return .shared
    }

    private var profileManager: OWSProfileManager {
        return .shared()
    }

    private var identityManager: OWSIdentityManager {
        return .shared()
    }

    /**
     * Choose whether to use CallKit or a Notification backed interface for calling.
     */
    @objc public func createCallUIAdapter() {
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

        BenchEventStart(title: "Outgoing Call Connection", eventId: "call-\(call.individualCall.localId)")

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
            self.handleFailedCall(failedCall: call, error: error)
        }
    }

    /**
     * User chose to answer the call. Used by the Callee only.
     */
    public func handleAcceptCall(_ call: SignalCall) {
        AssertIsOnMainThread()
        Logger.info("\(call)")

        guard callService.currentCall === call else {
            let error = OWSAssertionError("accepting call: \(call) which is different from currentCall: \(callService.currentCall as Optional)")
            handleFailedCall(failedCall: call, error: error)
            return
        }

        guard let callId = call.individualCall.callId else {
            handleFailedCall(failedCall: call, error: OWSAssertionError("no callId for call: \(call)"))
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

        do {
            try callManager.accept(callId: callId)

            // It's key that we configure the AVAudioSession for a call *before* we fulfill the
            // CXAnswerCallAction.
            //
            // Otherwise CallKit has been seen not to activate the audio session.
            // That is, `provider(_ provider: CXProvider, didActivate audioSession: AVAudioSession)`
            // was sometimes not called.`
            //
            // That is why we connect here, rather than waiting for a racy async response from CallManager,
            // confirming that the call has connected.
            handleConnected(call: call)
        } catch {
            self.handleFailedCall(failedCall: call, error: error)
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
        } else if call.individualCall.state == .localRinging {
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

    private func allowsInboundCallsInThread(_ thread: TSContactThread) -> Bool {
        return databaseStorage.read { transaction in
            // IFF one of the following things is true, we can handle inbound call offers
            // * The thread is in our profile whitelist
            // * The thread belongs to someone in our system contacts
            // * The thread existed before messages requests
            return self.profileManager.isThread(inProfileWhitelist: thread, transaction: transaction)
                || self.contactsManager.isSystemContact(address: thread.contactAddress)
                || GRDBThreadFinder.isPreMessageRequestsThread(thread, transaction: transaction.unwrapGrdbRead)
        }
    }

    private struct CallIdentityKeys {
      let localIdentityKey: Data
      let contactIdentityKey: Data
    }

    private func getIdentityKeys(thread: TSContactThread) -> CallIdentityKeys? {
        return databaseStorage.read { transaction -> CallIdentityKeys? in
            guard let localIdentityKey = self.identityManager.identityKeyPair(with: transaction)?.publicKey else {
                owsFailDebug("missing localIdentityKey")
                return nil
            }
            guard let contactIdentityKey = self.identityManager.identityKey(for: thread.contactAddress, transaction: transaction) else {
                owsFailDebug("missing contactIdentityKey")
                return nil
            }
            return CallIdentityKeys(localIdentityKey: localIdentityKey, contactIdentityKey: contactIdentityKey)
        }
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
        supportsMultiRing: Bool
    ) {
        AssertIsOnMainThread()
        Logger.info("callId: \(callId), thread: \(thread.contactAddress)")

        let newCall = callService.prepareIncomingIndividualCall(
            thread: thread,
            sentAtTimestamp: sentAtTimestamp,
            callType: callType
        )

        BenchEventStart(title: "Incoming Call Connection", eventId: "call-\(newCall.individualCall.localId)")

        guard tsAccountManager.isOnboarded() else {
            Logger.warn("user is not onboarded, skipping call.")
            let callRecord = TSCall(
                callType: .incomingMissed,
                offerType: newCall.individualCall.offerMediaType,
                thread: thread,
                sentAtTimestamp: sentAtTimestamp
            )
            assert(newCall.individualCall.callRecord == nil)
            newCall.individualCall.callRecord = callRecord
            databaseStorage.asyncWrite { transaction in
                callRecord.anyInsert(transaction: transaction)
            }

            newCall.individualCall.state = .localFailure
            callService.terminate(call: newCall)

            return
        }

        if let untrustedIdentity = self.identityManager.untrustedIdentityForSending(to: thread.contactAddress) {
            Logger.warn("missed a call due to untrusted identity: \(newCall)")

            let callerName = self.contactsManager.displayName(for: thread.contactAddress)

            switch untrustedIdentity.verificationState {
            case .verified:
                owsFailDebug("shouldn't have missed a call due to untrusted identity if the identity is verified")
                self.notificationPresenter.presentMissedCall(newCall.individualCall, callerName: callerName)
            case .default:
                self.notificationPresenter.presentMissedCallBecauseOfNewIdentity(call: newCall.individualCall, callerName: callerName)
            case .noLongerVerified:
                self.notificationPresenter.presentMissedCallBecauseOfNoLongerVerifiedIdentity(call: newCall.individualCall, callerName: callerName)
            }

            let callRecord = TSCall(
                callType: .incomingMissedBecauseOfChangedIdentity,
                offerType: newCall.individualCall.offerMediaType,
                thread: thread,
                sentAtTimestamp: sentAtTimestamp
            )
            assert(newCall.individualCall.callRecord == nil)
            newCall.individualCall.callRecord = callRecord
            databaseStorage.asyncWrite { transaction in
                callRecord.anyInsert(transaction: transaction)
            }

            newCall.individualCall.state = .localFailure
            callService.terminate(call: newCall)

            return
        }

        guard let identityKeys = getIdentityKeys(thread: thread) else {
            owsFailDebug("missing identity keys, skipping call.")
            let callRecord = TSCall(
                callType: .incomingMissed,
                offerType: newCall.individualCall.offerMediaType,
                thread: thread,
                sentAtTimestamp: sentAtTimestamp
            )
            assert(newCall.individualCall.callRecord == nil)
            newCall.individualCall.callRecord = callRecord
            databaseStorage.write { transaction in
                callRecord.anyInsert(transaction: transaction)
            }

            newCall.individualCall.state = .localFailure
            callService.terminate(call: newCall)

            return
        }

        guard allowsInboundCallsInThread(thread) else {
            Logger.info("Ignoring call offer from \(thread.contactAddress) due to insufficient permissions.")

            // Send the need permission message to the caller, so they know why we rejected their call.
            callManager(
                callManager,
                shouldSendHangup: callId,
                call: newCall,
                destinationDeviceId: sourceDevice,
                hangupType: .needPermission,
                deviceId: tsAccountManager.storedDeviceId(),
                useLegacyHangupMessage: true
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
            databaseStorage.asyncWrite { transaction in
                callRecord.anyInsert(transaction: transaction)
            }

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

            self.handleFailedCall(failedCall: newCall, error: SignalCall.CallError.timeout(description: "background task time ran out before call connected"))
        })

        newCall.individualCall.backgroundTask = backgroundTask

        var messageAgeSec: UInt64 = 0
        if serverReceivedTimestamp > 0 && serverDeliveryTimestamp >= serverReceivedTimestamp {
            messageAgeSec = (serverDeliveryTimestamp - serverReceivedTimestamp) / 1000
        }

        // Get the current local device Id, must be valid for lifetime of the call.
        let localDeviceId = tsAccountManager.storedDeviceId()
        let isPrimaryDevice = tsAccountManager.isPrimaryDevice

        do {
            try callManager.receivedOffer(call: newCall, sourceDevice: sourceDevice, callId: callId, opaque: opaque, sdp: sdp, messageAgeSec: messageAgeSec, callMediaType: newCall.individualCall.offerMediaType.asCallMediaType, localDevice: localDeviceId, remoteSupportsMultiRing: supportsMultiRing, isLocalDevicePrimary: isPrimaryDevice, senderIdentityKey: identityKeys.contactIdentityKey, receiverIdentityKey: identityKeys.localIdentityKey)
        } catch {
            handleFailedCall(failedCall: newCall, error: error)
        }
    }

    /**
     * Called by the call initiator after receiving an Answer from the callee.
     */
    public func handleReceivedAnswer(thread: TSContactThread, callId: UInt64, sourceDevice: UInt32, sdp: String?, opaque: Data?, supportsMultiRing: Bool) {
        AssertIsOnMainThread()
        Logger.info("callId: \(callId), thread: \(thread.contactAddress)")

        guard let identityKeys = getIdentityKeys(thread: thread) else {
            if let currentCall = callService.currentCall, currentCall.individualCall?.callId == callId {
                handleFailedCall(failedCall: currentCall, error: OWSAssertionError("missing identity keys"))
            }
            return
        }

        do {
            try callManager.receivedAnswer(sourceDevice: sourceDevice, callId: callId, opaque: opaque, sdp: sdp, remoteSupportsMultiRing: supportsMultiRing, senderIdentityKey: identityKeys.contactIdentityKey, receiverIdentityKey: identityKeys.localIdentityKey)
        } catch {
            owsFailDebug("error: \(error)")
            if let currentCall = callService.currentCall, currentCall.individualCall?.callId == callId {
                handleFailedCall(failedCall: currentCall, error: error)
            }
        }
    }

    /**
     * Remote client (could be caller or callee) sent us a connectivity update.
     */
    public func handleReceivedIceCandidates(thread: TSContactThread, callId: UInt64, sourceDevice: UInt32, candidates: [SSKProtoCallMessageIceUpdate]) {
        AssertIsOnMainThread()
        Logger.info("callId: \(callId), thread: \(thread.contactAddress)")

        let iceCandidates = candidates.filter { $0.id == callId }.map { candidate in
            CallManagerIceCandidate(opaque: candidate.opaque, sdp: candidate.sdp)
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
                handleFailedCall(failedCall: currentCall, error: error)
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
                handleFailedCall(failedCall: currentCall, error: error)
            }
        }
    }

    // MARK: - Call Manager Events

    public func callManager(_ callManager: CallService.CallManagerType, shouldStartCall call: SignalCall, callId: UInt64, isOutgoing: Bool, callMediaType: CallMediaType) {
        AssertIsOnMainThread()
        owsAssertDebug(call.isIndividualCall)
        Logger.info("call: \(call)")

        // Start the call, asynchronously.
        getIceServers().done { iceServers in
            guard self.callService.currentCall === call else {
                Logger.debug("call has since ended")
                return
            }

            var isUnknownCaller = false
            if call.individualCall.direction == .incoming {
                isUnknownCaller = !self.contactsManager.hasSignalAccount(for: call.individualCall.thread.contactAddress)
            }

            let useTurnOnly = isUnknownCaller || Environment.shared.preferences.doCallsHideIPAddress()

            // Tell the Call Manager to proceed with its active call.
            try self.callManager.proceed(callId: callId, iceServers: iceServers, hideIp: useTurnOnly, videoCaptureController: call.videoCaptureController)
        }.catch { error in
            owsFailDebug("\(error)")
            guard call === self.callService.currentCall else {
                Logger.debug("")
                return
            }

            callManager.drop(callId: callId)
            self.handleFailedCall(failedCall: call, error: error)
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
            callUIAdapter.recipientAcceptedCall(call)
            handleConnected(call: call)

        case .endedLocalHangup:
            Logger.debug("")
            // nothing further to do - already handled in handleLocalHangupCall().

        case .endedRemoteHangup:
            guard call === callService.currentCall else {
                callService.cleanupStaleCall(call)
                return
            }

            switch call.individualCall.state {
            case .idle, .dialing, .answering, .localRinging, .localFailure, .remoteBusy, .remoteRinging:
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

            switch call.individualCall.state {
            case .idle, .dialing, .answering, .localRinging, .localFailure, .remoteBusy, .remoteRinging:
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

            switch call.individualCall.state {
            case .idle, .dialing, .remoteBusy, .remoteRinging, .answeredElsewhere, .declinedElsewhere, .busyElsewhere, .remoteHangup, .remoteHangupNeedPermission:
                handleFailedCall(failedCall: call, error: OWSAssertionError("unexpected state for endedRemoteHangupAccepted: \(call.individualCall.state)"))
                return
            case .answering, .connected:
                Logger.info("tried answering locally, but answered somewhere else first. state: \(call.individualCall.state)")
                handleAnsweredElsewhere(call: call)
            case .localRinging, .reconnecting:
                handleAnsweredElsewhere(call: call)
            case  .localFailure, .localHangup:
                Logger.info("ignoring 'endedRemoteHangupAccepted' since call is already finished")
            }

        case .endedRemoteHangupDeclined:
            guard call === callService.currentCall else {
                callService.cleanupStaleCall(call)
                return
            }

            switch call.individualCall.state {
            case .idle, .dialing, .remoteBusy, .remoteRinging, .answeredElsewhere, .declinedElsewhere, .busyElsewhere, .remoteHangup, .remoteHangupNeedPermission:
                handleFailedCall(failedCall: call, error: OWSAssertionError("unexpected state for endedRemoteHangupDeclined: \(call.individualCall.state)"))
                return
            case .answering, .connected:
                Logger.info("tried answering locally, but declined somewhere else first. state: \(call.individualCall.state)")
                handleDeclinedElsewhere(call: call)
            case .localRinging, .reconnecting:
                handleDeclinedElsewhere(call: call)
            case  .localFailure, .localHangup:
                Logger.info("ignoring 'endedRemoteHangupDeclined' since call is already finished")
            }

        case .endedRemoteHangupBusy:
            guard call === callService.currentCall else {
                callService.cleanupStaleCall(call)
                return
            }

            switch call.individualCall.state {
            case .idle, .dialing, .remoteBusy, .remoteRinging, .answeredElsewhere, .declinedElsewhere, .busyElsewhere, .remoteHangup, .remoteHangupNeedPermission:
                handleFailedCall(failedCall: call, error: OWSAssertionError("unexpected state for endedRemoteHangupBusy: \(call.individualCall.state)"))
                return
            case .answering, .connected:
                Logger.info("tried answering locally, but already in a call somewhere else first. state: \(call.individualCall.state)")
                handleBusyElsewhere(call: call)
            case .localRinging, .reconnecting:
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

        case .endedRemoteGlare:
            guard call === callService.currentCall else {
                callService.cleanupStaleCall(call)
                return
            }

            if let callRecord = call.individualCall.callRecord {
                switch callRecord.callType {
                case .outgoingMissed, .incomingDeclined, .incomingMissed, .incomingMissedBecauseOfChangedIdentity, .incomingAnsweredElsewhere, .incomingDeclinedElsewhere, .incomingBusyElsewhere:
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
            call.individualCall.state = .localFailure
            callService.terminate(call: call)

        case .endedTimeout:
            let description: String

            if call.individualCall.direction == .outgoing {
                description = "timeout for outgoing call"
            } else {
                description = "timeout for incoming call"
            }

            handleFailedCall(failedCall: call, error: SignalCall.CallError.timeout(description: description))

        case .endedSignalingFailure:
            handleFailedCall(failedCall: call, error: SignalCall.CallError.timeout(description: "signaling failure for call"))

        case .endedInternalFailure:
            handleFailedCall(failedCall: call, error: OWSAssertionError("call manager internal error"))

        case .endedConnectionFailure:
            handleFailedCall(failedCall: call, error: SignalCall.CallError.disconnected)

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

        case .ignoreCallsFromNonMultiringCallers:
            handleMissedCall(call)
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

    public func callManager(_ callManager: CallService.CallManagerType, shouldSendOffer callId: UInt64, call: SignalCall, destinationDeviceId: UInt32?, opaque: Data?, sdp: String?, callMediaType: CallMediaType) {
        AssertIsOnMainThread()
        owsAssertDebug(call.isIndividualCall)

        Logger.info("shouldSendOffer")

        firstly { () throws -> Promise<Void> in
            let offerBuilder = SSKProtoCallMessageOffer.builder(id: callId)
            if let opaque = opaque { offerBuilder.setOpaque(opaque) }
            if let sdp = sdp { offerBuilder.setSdp(sdp) }
            switch callMediaType {
            case .audioCall: offerBuilder.setType(.offerAudioCall)
            case .videoCall: offerBuilder.setType(.offerVideoCall)
            }
            let callMessage = OWSOutgoingCallMessage(thread: call.individualCall.thread, offerMessage: try offerBuilder.build(), destinationDeviceId: NSNumber(value: destinationDeviceId))
            return messageSender.sendMessage(.promise, callMessage.asPreparer)
        }.done {
            Logger.info("sent offer message to \(call.individualCall.thread.contactAddress) device: \((destinationDeviceId != nil) ? String(destinationDeviceId!) : "nil")")
            try self.callManager.signalingMessageDidSend(callId: callId)
        }.catch { error in
            Logger.error("failed to send offer message to \(call.individualCall.thread.contactAddress) with error: \(error)")
            self.callManager.signalingMessageDidFail(callId: callId)
        }
    }

    public func callManager(_ callManager: CallService.CallManagerType, shouldSendAnswer callId: UInt64, call: SignalCall, destinationDeviceId: UInt32?, opaque: Data?, sdp: String?) {
        AssertIsOnMainThread()
        owsAssertDebug(call.isIndividualCall)
        Logger.info("shouldSendAnswer")

        firstly { () throws -> Promise<Void> in
            let answerBuilder = SSKProtoCallMessageAnswer.builder(id: callId)
            if let opaque = opaque { answerBuilder.setOpaque(opaque) }
            if let sdp = sdp { answerBuilder.setSdp(sdp) }
            let callMessage = OWSOutgoingCallMessage(thread: call.individualCall.thread, answerMessage: try answerBuilder.build(), destinationDeviceId: NSNumber(value: destinationDeviceId))
            return messageSender.sendMessage(.promise, callMessage.asPreparer)
        }.done {
            Logger.debug("sent answer message to \(call.individualCall.thread.contactAddress) device: \((destinationDeviceId != nil) ? String(destinationDeviceId!) : "nil")")
            try self.callManager.signalingMessageDidSend(callId: callId)
        }.catch { error in
            Logger.error("failed to send answer message to \(call.individualCall.thread.contactAddress) with error: \(error)")
            self.callManager.signalingMessageDidFail(callId: callId)
        }
    }

    public func callManager(_ callManager: CallService.CallManagerType, shouldSendIceCandidates callId: UInt64, call: SignalCall, destinationDeviceId: UInt32?, candidates: [CallManagerIceCandidate]) {
        AssertIsOnMainThread()
        owsAssertDebug(call.isIndividualCall)
        Logger.info("shouldSendIceCandidates")

        firstly { () throws -> Promise<Void> in
            var iceUpdateProtos = [SSKProtoCallMessageIceUpdate]()

            for iceCandidate in candidates {
                let iceUpdateProto: SSKProtoCallMessageIceUpdate
                let iceUpdateBuilder = SSKProtoCallMessageIceUpdate.builder(id: callId)
                if let opaque = iceCandidate.opaque { iceUpdateBuilder.setOpaque(opaque) }
                if let sdp = iceCandidate.sdp { iceUpdateBuilder.setSdp(sdp) }

                // Hardcode fields for older clients; remove after appropriate time period.
                iceUpdateBuilder.setLine(0)
                iceUpdateBuilder.setMid("audio")

                iceUpdateProto = try iceUpdateBuilder.build()
                iceUpdateProtos.append(iceUpdateProto)
            }

            guard !iceUpdateProtos.isEmpty else {
                throw OWSAssertionError("no ice updates to send")
            }

            let callMessage = OWSOutgoingCallMessage(thread: call.individualCall.thread, iceUpdateMessages: iceUpdateProtos, destinationDeviceId: NSNumber(value: destinationDeviceId))
            return messageSender.sendMessage(.promise, callMessage.asPreparer)
        }.done {
            Logger.debug("sent ice update message to \(call.individualCall.thread.contactAddress) device: \((destinationDeviceId != nil) ? String(destinationDeviceId!) : "nil")")
            try self.callManager.signalingMessageDidSend(callId: callId)
        }.catch { error in
            Logger.error("failed to send ice update message to \(call.individualCall.thread.contactAddress) with error: \(error)")
            callManager.signalingMessageDidFail(callId: callId)
        }
    }

    public func callManager(_ callManager: CallService.CallManagerType, shouldSendHangup callId: UInt64, call: SignalCall, destinationDeviceId: UInt32?, hangupType: HangupType, deviceId: UInt32, useLegacyHangupMessage: Bool) {
        AssertIsOnMainThread()
        owsAssertDebug(call.isIndividualCall)
        Logger.info("shouldSendHangup")

        firstly { () throws -> Promise<Void> in
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

            let callMessage: OWSOutgoingCallMessage
            if useLegacyHangupMessage {
                callMessage = OWSOutgoingCallMessage(thread: call.individualCall.thread, legacyHangupMessage: try hangupBuilder.build(), destinationDeviceId: NSNumber(value: destinationDeviceId))
            } else {
                callMessage = OWSOutgoingCallMessage(thread: call.individualCall.thread, hangupMessage: try hangupBuilder.build(), destinationDeviceId: NSNumber(value: destinationDeviceId))
            }
            return messageSender.sendMessage(.promise, callMessage.asPreparer)
        }.done {
            Logger.debug("sent hangup message to \(call.individualCall.thread.contactAddress) device: \((destinationDeviceId != nil) ? String(destinationDeviceId!) : "nil")")
            try self.callManager.signalingMessageDidSend(callId: callId)
        }.catch { error in
            Logger.error("failed to send hangup message to \(call.individualCall.thread.contactAddress) with error: \(error)")
            self.callManager.signalingMessageDidFail(callId: callId)
        }
    }

    public func callManager(_ callManager: CallService.CallManagerType, shouldSendBusy callId: UInt64, call: SignalCall, destinationDeviceId: UInt32?) {
        AssertIsOnMainThread()
        owsAssertDebug(call.isIndividualCall)
        Logger.info("shouldSendBusy")

        firstly { () throws -> Promise<Void> in
            let busyBuilder = SSKProtoCallMessageBusy.builder(id: callId)
            let callMessage = OWSOutgoingCallMessage(thread: call.individualCall.thread, busyMessage: try busyBuilder.build(), destinationDeviceId: NSNumber(value: destinationDeviceId))
            return messageSender.sendMessage(.promise, callMessage.asPreparer)
        }.done {
            Logger.debug("sent busy message to \(call.individualCall.thread.contactAddress) device: \((destinationDeviceId != nil) ? String(destinationDeviceId!) : "nil")")
            try self.callManager.signalingMessageDidSend(callId: callId)
        }.catch { error in
            Logger.error("failed to send busy message to \(call.individualCall.thread.contactAddress) with error: \(error)")
            self.callManager.signalingMessageDidFail(callId: callId)
        }
    }

    // MARK: - Support Functions

    /**
     * User didn't answer incoming call
     */
    public func handleMissedCall(_ call: SignalCall) {
        AssertIsOnMainThread()
        Logger.info("call: \(call)")

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
                callRecord.anyUpsert(transaction: transaction)
            }
            callUIAdapter.reportMissedCall(call)
        case .incomingIncomplete, .incoming:
            callRecord.updateCallType(.incomingMissed)
            callUIAdapter.reportMissedCall(call)
        case .outgoingIncomplete:
            callRecord.updateCallType(.outgoingMissed)
        case .incomingMissedBecauseOfChangedIdentity, .incomingDeclined, .outgoingMissed, .outgoing, .incomingAnsweredElsewhere, .incomingDeclinedElsewhere, .incomingBusyElsewhere:
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
        callUIAdapter.reportMissedCall(call)

        callService.terminate(call: call)
    }

    /**
     * The clients can now communicate via WebRTC, so we can let the UI know.
     *
     * Called by both caller and callee. Compatible ICE messages have been exchanged between the local and remote
     * client.
     */
    private func handleRinging(call: SignalCall) {
        AssertIsOnMainThread()
        Logger.info("call: \(call)")

        guard call === callService.currentCall else {
            callService.cleanupStaleCall(call)
            return
        }

        switch call.individualCall.state {
        case .dialing:
            if call.individualCall.state != .remoteRinging {
                BenchEventComplete(eventId: "call-\(call.individualCall.localId)")
            }
            call.individualCall.state = .remoteRinging
        case .answering:
            if call.individualCall.state != .localRinging {
                BenchEventComplete(eventId: "call-\(call.individualCall.localId)")
            }
            call.individualCall.state = .localRinging
            self.callUIAdapter.reportIncomingCall(call, thread: call.individualCall.thread)
        case .remoteRinging:
            Logger.info("call already ringing. Ignoring \(#function): \(call).")
        case .idle, .localRinging, .connected, .reconnecting, .localFailure, .localHangup, .remoteHangup, .remoteHangupNeedPermission, .remoteBusy, .answeredElsewhere, .declinedElsewhere, .busyElsewhere:
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
        case .remoteRinging, .localRinging:
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
            handleFailedCall(failedCall: call, error: SignalCall.CallError.providerReset)
        }
        callManager.reset()
    }

    // This method should be called when a fatal error occurred for a call.
    //
    // * If we know which call it was, we should update that call's state
    //   to reflect the error.
    // * IFF that call is the current call, we want to terminate it.
    public func handleFailedCall(failedCall: SignalCall, error: Error) {
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
        case .answering, .localRinging:
            assert(failedCall.individualCall.callRecord == nil)
            // call failed before any call record could be created, make one now.
            handleMissedCall(failedCall)
        default:
            assert(failedCall.individualCall.callRecord != nil)
        }

        guard !failedCall.individualCall.isEnded else {
            Logger.debug("ignoring error: \(error) for already terminated call: \(failedCall)")
            return
        }

        failedCall.error = callError
        failedCall.individualCall.state = .localFailure
        self.callUIAdapter.failCall(failedCall, error: callError)

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
        self.handleFailedCall(failedCall: call, error: OWSAssertionError("Call view didn't present after \(kMaxViewPresentationDelay) seconds"))
    }

    func stopAnyCallTimer() {
        AssertIsOnMainThread()

        self.activeCallTimer?.invalidate()
        self.activeCallTimer = nil
    }
}

extension RPRecentCallType: CustomStringConvertible {
    public var description: String {
        switch self {
        case .incoming:
            return ".incoming"
        case .outgoing:
            return ".outgoing"
        case .incomingMissed:
            return ".incomingMissed"
        case .outgoingIncomplete:
            return ".outgoingIncomplete"
        case .incomingIncomplete:
            return ".incomingIncomplete"
        case .incomingMissedBecauseOfChangedIdentity:
            return ".incomingMissedBecauseOfChangedIdentity"
        case .incomingDeclined:
            return ".incomingDeclined"
        case .outgoingMissed:
            return ".outgoingMissed"
        default:
            owsFailDebug("unexpected RPRecentCallType: \(self.rawValue)")
            return "RPRecentCallTypeUnknown"
        }
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
