//
// Copyright 2020 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import SignalMessaging
import SignalRingRTC
import SignalServiceKit
import SignalUI

/// Represents an observer who will receive updates about a call happening on
/// this device. See ``SignalCall``.
public protocol CallObserver: AnyObject {
    func individualCallStateDidChange(_ call: SignalCall, state: CallState)
    func individualCallLocalVideoMuteDidChange(_ call: SignalCall, isVideoMuted: Bool)
    func individualCallLocalAudioMuteDidChange(_ call: SignalCall, isAudioMuted: Bool)
    func individualCallRemoteVideoMuteDidChange(_ call: SignalCall, isVideoMuted: Bool)
    func individualCallRemoteSharingScreenDidChange(_ call: SignalCall, isRemoteSharingScreen: Bool)
    func individualCallHoldDidChange(_ call: SignalCall, isOnHold: Bool)

    func groupCallLocalDeviceStateChanged(_ call: SignalCall)
    func groupCallRemoteDeviceStatesChanged(_ call: SignalCall)
    func groupCallPeekChanged(_ call: SignalCall)
    func groupCallRequestMembershipProof(_ call: SignalCall)
    func groupCallRequestGroupMembers(_ call: SignalCall)
    func groupCallEnded(_ call: SignalCall, reason: GroupCallEndReason)

    /// Invoked if a call message failed to send because of a safety number change
    /// UI observing call state may choose to alert the user (e.g. presenting a SafetyNumberConfirmationSheet)
    func callMessageSendFailedUntrustedIdentity(_ call: SignalCall)
}

public extension CallObserver {
    func individualCallStateDidChange(_ call: SignalCall, state: CallState) {}
    func individualCallLocalVideoMuteDidChange(_ call: SignalCall, isVideoMuted: Bool) {}
    func individualCallLocalAudioMuteDidChange(_ call: SignalCall, isAudioMuted: Bool) {}
    func individualCallRemoteVideoMuteDidChange(_ call: SignalCall, isVideoMuted: Bool) {}
    func individualCallRemoteSharingScreenDidChange(_ call: SignalCall, isRemoteSharingScreen: Bool) {}
    func individualCallHoldDidChange(_ call: SignalCall, isOnHold: Bool) {}

    func groupCallLocalDeviceStateChanged(_ call: SignalCall) {}
    func groupCallRemoteDeviceStatesChanged(_ call: SignalCall) {}
    func groupCallPeekChanged(_ call: SignalCall) {}
    func groupCallRequestMembershipProof(_ call: SignalCall) {}
    func groupCallRequestGroupMembers(_ call: SignalCall) {}
    func groupCallEnded(_ call: SignalCall, reason: GroupCallEndReason) {}

    func callMessageSendFailedUntrustedIdentity(_ call: SignalCall) {}
}

/// Represents a call happening on this device.
@objc
public class SignalCall: NSObject, CallManagerCallReference {
    public let mode: Mode
    public enum Mode {
        case individual(IndividualCall)
        case group(GroupCall)
    }

    public let audioActivity: AudioActivity

    private(set) var systemState: SystemState = .notReported
    enum SystemState {
        case notReported
        case pending
        case reported
        case removed
    }

    var isGroupCall: Bool {
        switch mode {
        case .group: return true
        case .individual: return false
        }
    }

    var groupCall: GroupCall! {
        owsAssertDebug(isGroupCall)
        guard case .group(let call) = mode else {
            owsFailDebug("Missing group call")
            return nil
        }
        return call
    }

    @objc
    var isIndividualCall: Bool {
        switch mode {
        case .group: return false
        case .individual: return true
        }
    }

    var individualCall: IndividualCall! {
        owsAssertDebug(isIndividualCall)
        guard case .individual(let call) = mode else {
            owsFailDebug("Missing individual call")
            return nil
        }
        return call
    }

    public var hasTerminated: Bool {
        switch mode {
        case .group:
            if case .incomingRingCancelled = groupCallRingState {
                return true
            }
            return false
        case .individual(let call):
            return call.hasTerminated
        }
    }

    public var isOutgoingAudioMuted: Bool {
        switch mode {
        case .individual(let call): return call.isMuted
        case .group(let call): return call.isOutgoingAudioMuted
        }
    }

    /// Returns the remote party for an incoming 1:1 call, or the ringer for a group call ring.
    ///
    /// Returns `nil` for an outgoing 1:1 call, a manually-entered group call,
    /// or a group call that has already been joined.
    public var caller: SignalServiceAddress? {
        switch mode {
        case .individual(let call):
            guard call.direction == .incoming else {
                return nil
            }
            return call.remoteAddress
        case .group:
            guard case .incomingRing(let caller, _) = groupCallRingState else {
                return nil
            }
            return caller
        }
    }

    private(set) lazy var videoCaptureController = VideoCaptureController()

    // Should be used only on the main thread
    public var connectedDate: Date? {
        didSet { AssertIsOnMainThread() }
    }

    // Distinguishes between calls locally, e.g. in CallKit
    public let localId: UUID = UUID()

    @objc
    public let thread: TSThread

    internal struct RingRestrictions: OptionSet {
        var rawValue: UInt8

        /// The user does not get to choose whether this kind of call rings.
        static let notApplicable = Self(rawValue: 1 << 0)
        /// The user cannot ring because there is already a call in progress.
        static let callInProgress = Self(rawValue: 1 << 1)
        /// This group is too large to allow ringing.
        static let groupTooLarge = Self(rawValue: 1 << 2)
    }

    internal var ringRestrictions: RingRestrictions {
        didSet {
            AssertIsOnMainThread()
            if ringRestrictions != oldValue && groupCall.localDeviceState.joinState == .notJoined {
                // Use a fake local state change to refresh the call controls.
                self.groupCall(onLocalDeviceStateChanged: groupCall)
            }
        }
    }

    internal enum GroupCallRingState {
        case doNotRing
        case shouldRing
        case ringing
        case ringingEnded
        case incomingRing(caller: SignalServiceAddress, ringId: Int64)
        case incomingRingCancelled

        var isIncomingRing: Bool {
            switch self {
            case .incomingRing, .incomingRingCancelled:
                return true
            default:
                return false
            }
        }
    }

    internal var groupCallRingState: GroupCallRingState = .shouldRing {
        didSet {
            AssertIsOnMainThread()
            // If we ever support non-ringing 1:1 calls, we might want to reuse this.
            owsAssertDebug(isGroupCall)
        }
    }

    public var error: CallError?
    public enum CallError: Error {
        case providerReset
        case disconnected
        case externalError(underlyingError: Error)
        case timeout(description: String)
        case signaling
        case doNotDisturbEnabled
        case contactIsBlocked

        func shouldSilentlyDropCall() -> Bool {
            switch self {
            case .providerReset, .disconnected, .externalError, .timeout, .signaling:
                return false
            case .doNotDisturbEnabled, .contactIsBlocked:
                return true
            }
        }
    }

    var participantAddresses: [SignalServiceAddress] {
        switch mode {
        case .group(let call):
            return call.remoteDeviceStates.values.map { $0.address }
        case .individual(let call):
            return [call.remoteAddress]
        }
    }

    init(groupCall: GroupCall, groupThread: TSGroupThread) {
        mode = .group(groupCall)
        audioActivity = AudioActivity(
            audioDescription: "[SignalCall] with group \(groupThread.groupModel.groupId)",
            behavior: .call
        )
        thread = groupThread
        if !RemoteConfig.outboundGroupRings {
            ringRestrictions = .notApplicable
        } else {
            ringRestrictions = []
            if groupThread.groupModel.groupMembers.count > RemoteConfig.maxGroupCallRingSize {
                ringRestrictions.insert(.groupTooLarge)
            }
        }

        // Track the callInProgress restriction regardless; we use that for purposes other than rings.
        let hasActiveCallMessage = Self.databaseStorage.read { transaction -> Bool in
            !GroupCallInteractionFinder().unendedCallsForGroupThread(groupThread, transaction: transaction).isEmpty
        }
        if hasActiveCallMessage {
            // This info may be out of date, but the first peek will update it.
            ringRestrictions.insert(.callInProgress)
        }

        super.init()

        groupCall.delegate = self
        // Watch group membership changes.
        // The object is the group thread ID, which is a string.
        // NotificationCenter dispatches by object identity rather than equality,
        // so we watch all changes and filter later.
        NotificationCenter.default.addObserver(self,
                                               selector: #selector(groupMembershipDidChange),
                                               name: TSGroupThread.membershipDidChange,
                                               object: nil)
    }

    init(individualCall: IndividualCall) {
        mode = .individual(individualCall)
        audioActivity = AudioActivity(
            audioDescription: "[SignalCall] with individual \(individualCall.remoteAddress)",
            behavior: .call
        )
        thread = individualCall.thread
        ringRestrictions = .notApplicable
        super.init()
        individualCall.delegate = self
    }

    deinit {
        owsAssertDebug(systemState != .reported, "call \(localId) was reported to system but never removed")
    }

    public class func groupCall(thread: TSGroupThread) -> SignalCall? {
        owsAssertDebug(thread.groupModel.groupsVersion == .V2)

        let videoCaptureController = VideoCaptureController()
        let sfuURL = DebugFlags.callingUseTestSFU.get() ? TSConstants.sfuTestURL : TSConstants.sfuURL

        guard let groupCall = Self.callService.callManager.createGroupCall(
            groupId: thread.groupModel.groupId,
            sfuUrl: sfuURL,
            hkdfExtraInfo: Data.init(),
            audioLevelsIntervalMillis: nil,
            videoCaptureController: videoCaptureController
        ) else {
            owsFailDebug("Failed to create group call")
            return nil
        }

        let call = SignalCall(groupCall: groupCall, groupThread: thread)
        call.videoCaptureController = videoCaptureController
        return call
    }

    public class func outgoingIndividualCall(thread: TSContactThread) -> SignalCall {
        let individualCall = IndividualCall(
            direction: .outgoing,
            state: .dialing,
            thread: thread,
            sentAtTimestamp: Date.ows_millisecondTimestamp(),
            callAdapterType: .default
        )
        return SignalCall(individualCall: individualCall)
    }

    public class func incomingIndividualCall(
        thread: TSContactThread,
        sentAtTimestamp: UInt64,
        offerMediaType: TSRecentCallOfferType
    ) -> SignalCall {
        // If this is a video call, we want to use in the in app call screen
        // because CallKit has poor support for video calls. On iOS 14+ we
        // always use CallKit, because as of iOS 14 AVAudioPlayer is no longer
        // able to start playing sounds in the background.
        let callAdapterType: CallAdapterType
        if #available(iOS 14, *) {
            callAdapterType = .default
        } else if offerMediaType == .video {
            callAdapterType = .nonCallKit
        } else {
            callAdapterType = .default
        }

        let individualCall = IndividualCall(
            direction: .incoming,
            state: .answering,
            thread: thread,
            sentAtTimestamp: sentAtTimestamp,
            callAdapterType: callAdapterType
        )
        individualCall.offerMediaType = offerMediaType
        return SignalCall(individualCall: individualCall)
    }

    @objc
    private func groupMembershipDidChange(_ notification: Notification) {
        // NotificationCenter dispatches by object identity rather than equality,
        // so we filter based on the thread ID here.
        guard !ringRestrictions.contains(.notApplicable),
              self.thread.uniqueId == notification.object as? String else {
            return
        }
        databaseStorage.read { transaction in
            self.thread.anyReload(transaction: transaction)
        }
        guard let groupModel = self.thread.groupModelIfGroupThread else {
            owsFailDebug("should not observe membership for a non-group thread")
            return
        }

        let isGroupTooLarge = groupModel.groupMembers.count > RemoteConfig.maxGroupCallRingSize
        ringRestrictions.update(.groupTooLarge, present: isGroupTooLarge)
    }

    // MARK: -

    private var observers: WeakArray<CallObserver> = []

    public func addObserverAndSyncState(observer: CallObserver) {
        AssertIsOnMainThread()

        observers.append(observer)

        // Synchronize observer with current call state
        switch mode {
        case .individual(let individualCall):
            observer.individualCallStateDidChange(self, state: individualCall.state)
        case .group:
            observer.groupCallLocalDeviceStateChanged(self)
            observer.groupCallRemoteDeviceStatesChanged(self)
        }
    }

    public func removeObserver(_ observer: CallObserver) {
        AssertIsOnMainThread()

        observers.removeAll { $0 === observer }
    }

    public func removeAllObservers() {
        AssertIsOnMainThread()

        observers = []
    }

    public func publishSendFailureUntrustedParticipantIdentity() {
        observers.elements.forEach { $0.callMessageSendFailedUntrustedIdentity(self) }
    }

    // MARK: -

    // This method should only be called when the call state is "connected".
    public func connectionDuration() -> TimeInterval {
        guard let connectedDate = connectedDate else {
            owsFailDebug("Called connectionDuration before connected.")
            return 0
        }
        return -connectedDate.timeIntervalSinceNow
    }

    func markPendingReportToSystem() {
        owsAssertDebug(systemState == .notReported, "call \(localId) had unexpected system state: \(systemState)")
        systemState = .pending
    }

    func markReportedToSystem() {
        owsAssertDebug(systemState == .notReported || systemState == .pending,
                       "call \(localId) had unexpected system state: \(systemState)")
        systemState = .reported
    }

    func markRemovedFromSystem() {
        // This was an assert that was firing when coming back online after missing
        // a call while offline. See IOS-3416
        if systemState != .reported {
            Logger.warn("call \(localId) had unexpected system state: \(systemState)")
        }
        systemState = .removed
    }
}

extension SignalCall: GroupCallDelegate {
    public func groupCall(onLocalDeviceStateChanged groupCall: GroupCall) {
        if groupCall.localDeviceState.joinState == .joined, connectedDate == nil {
            connectedDate = Date()
            if groupCallRingState.isIncomingRing {
                groupCallRingState = .ringingEnded
            }

            // make sure we don't terminate audio session during call
            audioSession.isRTCAudioEnabled = true
            owsAssertDebug(audioSession.startAudioActivity(audioActivity))
        }

        observers.elements.forEach { $0.groupCallLocalDeviceStateChanged(self) }
    }

    public func groupCall(onRemoteDeviceStatesChanged groupCall: GroupCall) {
        observers.elements.forEach { $0.groupCallRemoteDeviceStatesChanged(self) }
        // Change this after notifying observers so that they can see when the ring has concluded.
        if case .ringing = groupCallRingState, !groupCall.remoteDeviceStates.isEmpty {
            groupCallRingState = .ringingEnded
            // Treat the end of ringing as a "local state change" for listeners that normally ignore remote changes.
            self.groupCall(onLocalDeviceStateChanged: groupCall)
        }
    }

    public func groupCall(onAudioLevels groupCall: GroupCall) {
        // TODO: Implement audio level handling for group calls.
    }

    public func groupCall(onLowBandwidthForVideo groupCall: SignalRingRTC.GroupCall, recovered: Bool) {
        // TODO: Implement handling of the "low outgoing bandwidth for video" notification.
    }

    public func groupCall(onReactions groupCall: SignalRingRTC.GroupCall, reactions: [SignalRingRTC.Reaction]) {
        // TODO: Implement handling of reactions.
    }

    public func groupCall(onRaisedHands groupCall: SignalRingRTC.GroupCall, raisedHands: [UInt32]) {
        // TODO: Implement handling of raise hand.
    }

    public func groupCall(onPeekChanged groupCall: GroupCall) {
        guard
            let localAci = DependenciesBridge.shared.tsAccountManager
                .localIdentifiersWithMaybeSneakyTransaction?.aci
        else {
            owsFailDebug("Peek changed for a group call, but we're not registered?")
            return
        }

        if let peekInfo = groupCall.peekInfo {
            // Note that we track this regardless of whether ringing is available.
            // There are other places that use this.

            let minDevicesToConsiderCallInProgress: UInt32 = {
                if peekInfo.joinedMembers.contains(localAci.rawUUID) {
                    // If we're joined, require us + someone else.
                    return 2
                } else {
                    // Otherwise, anyone else in the call counts.
                    return 1
                }
            }()

            ringRestrictions.update(
                .callInProgress,
                present: peekInfo.deviceCountExcludingPendingDevices >= minDevicesToConsiderCallInProgress
            )
        }
        observers.elements.forEach { $0.groupCallPeekChanged(self) }
    }

    public func groupCall(requestMembershipProof groupCall: GroupCall) {
        observers.elements.forEach { $0.groupCallRequestMembershipProof(self) }
    }

    public func groupCall(requestGroupMembers groupCall: GroupCall) {
        observers.elements.forEach { $0.groupCallRequestGroupMembers(self) }
    }

    public func groupCall(onEnded groupCall: GroupCall, reason: GroupCallEndReason) {
        observers.elements.forEach { $0.groupCallEnded(self, reason: reason) }
    }
}

extension SignalCall: IndividualCallDelegate {
    public func individualCallStateDidChange(_ call: IndividualCall, state: CallState) {
        if case .connected = state, connectedDate == nil {
            connectedDate = Date()
        }

        observers.elements.forEach { $0.individualCallStateDidChange(self, state: state) }
    }

    public func individualCallLocalVideoMuteDidChange(_ call: IndividualCall, isVideoMuted: Bool) {
        observers.elements.forEach { $0.individualCallLocalVideoMuteDidChange(self, isVideoMuted: isVideoMuted) }
    }

    public func individualCallLocalAudioMuteDidChange(_ call: IndividualCall, isAudioMuted: Bool) {
        observers.elements.forEach { $0.individualCallLocalAudioMuteDidChange(self, isAudioMuted: isAudioMuted) }
    }

    public func individualCallHoldDidChange(_ call: IndividualCall, isOnHold: Bool) {
        observers.elements.forEach { $0.individualCallHoldDidChange(self, isOnHold: isOnHold) }
    }

    public func individualCallRemoteVideoMuteDidChange(_ call: IndividualCall, isVideoMuted: Bool) {
        observers.elements.forEach { $0.individualCallRemoteVideoMuteDidChange(self, isVideoMuted: isVideoMuted) }
    }

    public func individualCallRemoteSharingScreenDidChange(_ call: IndividualCall, isRemoteSharingScreen: Bool) {
        observers.elements.forEach { $0.individualCallRemoteSharingScreenDidChange(self, isRemoteSharingScreen: isRemoteSharingScreen) }
    }
}

extension SignalCall: CallNotificationInfo {
    public var offerMediaType: TSRecentCallOfferType {
        switch mode {
        case .individual(let call): return call.offerMediaType
        case .group: return .video
        }
    }
}

extension GroupCall {
    public var isFull: Bool {
        guard let peekInfo = peekInfo, let maxDevices = peekInfo.maxDevices else { return false }
        return peekInfo.deviceCountExcludingPendingDevices >= maxDevices
    }
    public var maxDevices: UInt32? {
        guard let peekInfo = peekInfo, let maxDevices = peekInfo.maxDevices else { return nil }
        return maxDevices
    }
}
