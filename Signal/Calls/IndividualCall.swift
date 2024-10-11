//
// Copyright 2016 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import AVFoundation
import SignalRingRTC
public import SignalServiceKit
import SignalUI
import WebRTC

enum CallState: String {
    case idle
    case dialing
    case answering
    case remoteRinging

    // The local ringing state is a bit more complex since we sometimes kick off
    // a CallKit ring before RingRTC is ready to answer. We can only answer the call
    // once both the user has answered and RingRTC is ready.
    case localRinging_Anticipatory      // RingRTC not ready. User has not answered
    case localRinging_ReadyToAnswer     // RingRTC ready. User has not answered
    case accepting                      // RingRTC not ready. User has answered

    case connected
    case reconnecting
    case localFailure // terminal
    case localHangup // terminal
    case remoteHangup // terminal
    case remoteHangupNeedPermission // terminal
    case remoteBusy // terminal
    case answeredElsewhere // terminal
    case declinedElsewhere // terminal
    case busyElsewhere // terminal
}

enum CallDirection {
    case outgoing, incoming
}

protocol IndividualCallObserver: AnyObject {
    @MainActor func individualCallStateDidChange(_ call: IndividualCall, state: CallState)
    @MainActor func individualCallLocalVideoMuteDidChange(_ call: IndividualCall, isVideoMuted: Bool)
    @MainActor func individualCallLocalAudioMuteDidChange(_ call: IndividualCall, isAudioMuted: Bool)
    @MainActor func individualCallHoldDidChange(_ call: IndividualCall, isOnHold: Bool)
    @MainActor func individualCallRemoteAudioMuteDidChange(_ call: IndividualCall, isAudioMuted: Bool)
    @MainActor func individualCallRemoteVideoMuteDidChange(_ call: IndividualCall, isVideoMuted: Bool)
    @MainActor func individualCallRemoteSharingScreenDidChange(_ call: IndividualCall, isRemoteSharingScreen: Bool)
}

extension IndividualCallObserver {
    func individualCallLocalVideoMuteDidChange(_ call: IndividualCall, isVideoMuted: Bool) {}
    func individualCallLocalAudioMuteDidChange(_ call: IndividualCall, isAudioMuted: Bool) {}
    func individualCallHoldDidChange(_ call: IndividualCall, isOnHold: Bool) {}
    func individualCallRemoteAudioMuteDidChange(_ call: IndividualCall, isAudioMuted: Bool) {}
    func individualCallRemoteVideoMuteDidChange(_ call: IndividualCall, isVideoMuted: Bool) {}
    func individualCallRemoteSharingScreenDidChange(_ call: IndividualCall, isRemoteSharingScreen: Bool) {}
}

/**
 * Data model for a WebRTC backed voice/video call.
 *
 * This class' state should only be accessed on the main queue.
 */
public class IndividualCall: CustomDebugStringConvertible {
    private var databaseStorage: SDSDatabaseStorage { SSKEnvironment.shared.databaseStorageRef }

    // Mark -

    var backgroundTask: OWSBackgroundTask? {
        didSet {
            AssertIsOnMainThread()

            Logger.info("")
        }
    }

    private(set) var callId: UInt64?

    let callEventInserter: CallEventInserter

    func setOutgoingCallIdAndUpdateCallRecord(_ callId: UInt64) {
        AssertIsOnMainThread()
        owsPrecondition(self.direction == .outgoing)
        Logger.info("")

        self.callId = callId
        self.databaseStorage.asyncWrite { tx in
            self.callEventInserter.setOutgoingCallId(callId, tx: tx)
        }
    }

    @MainActor
    weak var remoteVideoTrack: RTCVideoTrack? {
        didSet {
            Logger.info("")

            observers.elements.forEach {
                $0.individualCallRemoteVideoMuteDidChange(self, isVideoMuted: !isRemoteVideoEnabled)
            }
        }
    }

    @MainActor
    var isRemoteAudioMuted = false {
        didSet {
            Logger.info("\(isRemoteAudioMuted)")
            observers.elements.forEach {
                $0.individualCallRemoteAudioMuteDidChange(self, isAudioMuted: isRemoteAudioMuted)
            }
        }
    }

    @MainActor
    var isRemoteVideoEnabled = false {
        didSet {
            Logger.info("\(isRemoteVideoEnabled)")
            observers.elements.forEach {
                $0.individualCallRemoteVideoMuteDidChange(self, isVideoMuted: !isRemoteVideoEnabled)
            }
        }
    }

    @MainActor
    var isRemoteSharingScreen = false {
        didSet {
            Logger.info("\(isRemoteSharingScreen)")
            observers.elements.forEach {
                $0.individualCallRemoteSharingScreenDidChange(self, isRemoteSharingScreen: isRemoteSharingScreen)
            }
        }
    }

    var networkRoute: NetworkRoute = NetworkRoute(localAdapterType: .unknown)

    // MARK: -

    var remoteAddress: SignalServiceAddress { thread.contactAddress }

    @MainActor
    var isEnded: Bool {
        switch state {
        case .localFailure, .localHangup, .remoteHangup, .remoteHangupNeedPermission, .remoteBusy, .answeredElsewhere, .declinedElsewhere, .busyElsewhere:
            return true
        case .idle, .dialing, .answering, .remoteRinging, .localRinging_Anticipatory, .localRinging_ReadyToAnswer, .accepting, .connected, .reconnecting:
            return false
        }
    }

    let commonState: CommonCallState

    let direction: CallDirection

    let thread: TSContactThread

    let sentAtTimestamp: UInt64

    /// Used by IndividualCallService to make decisions about what actions to take.
    /// Not guaranteed to be up-to-date with what is in the database, but
    /// is up to date with CallKit callbacks on the main thread.
    /// Can be accessed from the main thread.
    private(set) var callType: RPRecentCallType?

    @MainActor
    lazy var hasLocalVideo = offerMediaType == .video {
        didSet {
            observers.elements.forEach {
                $0.individualCallLocalVideoMuteDidChange(self, isVideoMuted: !hasLocalVideo)
            }
        }
    }

    /// This is part of an ugly hack, but CallService is currently responsible
    /// for starting/stopping the video preview, but we don't want to do that
    /// until the view is actually going to be displayed. So we pass state
    /// through IndividualCall.
    var isViewLoaded = false

    @MainActor
    var deferredAnswerCompletion: (() -> Void)? {
        didSet {
            owsAssertDebug(deferredAnswerCompletion == nil || state == .accepting)
        }
    }

    @MainActor
    var state: CallState {
        didSet {
            Logger.debug("state changed: \(oldValue) -> \(self.state) for call: \(self)")

            let state = self.state

            if case .connected = state {
                commonState.setConnectedDateIfNeeded()
            }

            observers.elements.forEach {
                $0.individualCallStateDidChange(self, state: state)
            }
        }
    }

    var error: CallError?

    public let offerMediaType: TSRecentCallOfferType

    // We start out muted if the record permission isn't granted. This should generally
    // only happen for incoming calls, because we proactively ask about it before you
    // can make an outgoing call.
    @MainActor
    public var isMuted = AVAudioSession.sharedInstance().recordPermission != .granted {
        didSet {
            Logger.debug("muted changed: \(oldValue) -> \(self.isMuted)")

            observers.elements.forEach {
                $0.individualCallLocalAudioMuteDidChange(self, isAudioMuted: isMuted)
            }
        }
    }

    @MainActor
    public var isOnHold = false {
        didSet {
            Logger.debug("isOnHold changed: \(oldValue) -> \(self.isOnHold)")

            observers.elements.forEach {
                $0.individualCallHoldDidChange(self, isOnHold: isOnHold)
            }
        }
    }

    @MainActor
    var hasTerminated: Bool {
        switch state {
        case .idle, .dialing, .answering, .remoteRinging, .localRinging_Anticipatory, .localRinging_ReadyToAnswer,
                .accepting, .connected, .reconnecting:
            return false

        case .localFailure, .localHangup, .remoteHangup, .remoteHangupNeedPermission, .remoteBusy, .answeredElsewhere,
                .declinedElsewhere, .busyElsewhere:
            return true
        }
    }

    private(set) lazy var videoCaptureController = VideoCaptureController()

    // MARK: Initializers and Factory Methods

    static func outgoingIndividualCall(
        thread: TSContactThread,
        offerMediaType: TSRecentCallOfferType
    ) -> IndividualCall {
        return IndividualCall(
            callId: nil,
            direction: .outgoing,
            offerMediaType: offerMediaType,
            state: .dialing,
            thread: thread,
            sentAtTimestamp: MessageTimestampGenerator.sharedInstance.generateTimestamp()
        )
    }

    static func incomingIndividualCall(
        callId: UInt64,
        thread: TSContactThread,
        sentAtTimestamp: UInt64,
        offerMediaType: TSRecentCallOfferType
    ) -> IndividualCall {
        return IndividualCall(
            callId: callId,
            direction: .incoming,
            offerMediaType: offerMediaType,
            state: .answering,
            thread: thread,
            sentAtTimestamp: sentAtTimestamp
        )
    }

    private init(
        callId: UInt64?,
        direction: CallDirection,
        offerMediaType: TSRecentCallOfferType,
        state: CallState,
        thread: TSContactThread,
        sentAtTimestamp: UInt64
    ) {
        self.callId = callId
        self.callEventInserter = CallEventInserter(
            thread: thread,
            callId: callId,
            offerMediaType: offerMediaType,
            sentAtTimestamp: sentAtTimestamp
        )
        self.commonState = CommonCallState(
            audioActivity: AudioActivity(
                audioDescription: "[SignalCall] with individual \(thread.contactAddress)",
                behavior: .call
            )
        )
        self.direction = direction
        self.offerMediaType = offerMediaType
        self.state = state
        self.thread = thread
        self.sentAtTimestamp = sentAtTimestamp
    }

    deinit {
        Logger.debug("")
    }

    public var debugDescription: String {
        return "IndividualCall: {\(remoteAddress), signalingId: \(callId as Optional)))}"
    }

    // MARK: - Observers

    private var observers: WeakArray<any IndividualCallObserver> = []

    @MainActor
    func addObserverAndSyncState(_ observer: any IndividualCallObserver) {
        AssertIsOnMainThread()

        observers.append(observer)

        // Synchronize observer with current call state
        observer.individualCallStateDidChange(self, state: state)
    }

    func removeObserver(_ observer: any IndividualCallObserver) {
        observers.removeAll(where: { $0 === observer })
    }

    // MARK: - Fetching and updating db objects

    public func createOrUpdateCallInteractionAsync(
        callType: RPRecentCallType
    ) {
        // Set the call type immediately; additional CallKit callbacks might come in
        // before we get the lock to write, and they may make decisions based on the
        // last callType they tried to set.
        // They _should not_ rely on the callType actually being set on the TSCall; TSCall fields
        // should be read within write transactions if they will be used as inputs when determining
        // what new state to write to TSCall.
        // Write transactions should almost always be asyncWrite, which puts them in a queue and
        // enforces FIFO ordering; sync writes skip the line and can cause older state to get
        // written later. A sync write is used only for the initial call offer handling, as that
        // is always the first write for any given call, anyway.
        self.callType = callType
        self.databaseStorage.asyncWrite { tx in
            self.callEventInserter.createOrUpdate(callType: callType, tx: tx)
        }
    }
}
