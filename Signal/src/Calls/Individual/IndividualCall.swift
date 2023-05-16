//
// Copyright 2016 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import SignalMessaging
import SignalServiceKit
import SignalRingRTC

public enum CallState: String {
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

public enum CallAdapterType {
    case `default`, nonCallKit
}

public enum CallDirection {
    case outgoing, incoming
}

public protocol IndividualCallDelegate: AnyObject {
    func individualCallStateDidChange(_ call: IndividualCall, state: CallState)
    func individualCallLocalVideoMuteDidChange(_ call: IndividualCall, isVideoMuted: Bool)
    func individualCallLocalAudioMuteDidChange(_ call: IndividualCall, isAudioMuted: Bool)
    func individualCallHoldDidChange(_ call: IndividualCall, isOnHold: Bool)
    func individualCallRemoteVideoMuteDidChange(_ call: IndividualCall, isVideoMuted: Bool)
    func individualCallRemoteSharingScreenDidChange(_ call: IndividualCall, isRemoteSharingScreen: Bool)
}

/**
 * Data model for a WebRTC backed voice/video call.
 *
 * This class' state should only be accessed on the main queue.
 */
public class IndividualCall: NSObject {

    // Mark -

    var backgroundTask: OWSBackgroundTask? {
        didSet {
            AssertIsOnMainThread()

            Logger.info("")
        }
    }

    var callId: UInt64? {
        didSet {
            AssertIsOnMainThread()

            Logger.info("CallId added for call")
            Self.databaseStorage.asyncWrite { transaction in
                if let callInteraction = self.callInteraction {
                    self.createOrUpdateCallRecordIfNeeded(for: callInteraction, transaction: transaction)
                }
            }
        }
    }

    let callAdapterType: CallAdapterType

    weak var remoteVideoTrack: RTCVideoTrack? {
        didSet {
            AssertIsOnMainThread()

            Logger.info("")
            delegate?.individualCallRemoteVideoMuteDidChange(self, isVideoMuted: !isRemoteVideoEnabled)
        }
    }

    var isRemoteVideoEnabled = false {
        didSet {
            AssertIsOnMainThread()

            Logger.info("\(isRemoteVideoEnabled)")
            delegate?.individualCallRemoteVideoMuteDidChange(self, isVideoMuted: !isRemoteVideoEnabled)
        }
    }

    var isRemoteSharingScreen = false {
        didSet {
            AssertIsOnMainThread()

            Logger.info("\(isRemoteSharingScreen)")
            delegate?.individualCallRemoteSharingScreenDidChange(self, isRemoteSharingScreen: isRemoteSharingScreen)
        }
    }

    var networkRoute: NetworkRoute = NetworkRoute(localAdapterType: .unknown)

    // MARK: -

    public var remoteAddress: SignalServiceAddress { thread.contactAddress }

    public var isEnded: Bool {
        switch state {
        case .localFailure, .localHangup, .remoteHangup, .remoteHangupNeedPermission, .remoteBusy, .answeredElsewhere, .declinedElsewhere, .busyElsewhere:
            return true
        case .idle, .dialing, .answering, .remoteRinging, .localRinging_Anticipatory, .localRinging_ReadyToAnswer, .accepting, .connected, .reconnecting:
            return false
        }
    }

    public let direction: CallDirection

    public let thread: TSContactThread

    public let sentAtTimestamp: UInt64

    /// Used by IndividualCallService to make decisions about what actions to take.
    /// Not guaranteed to be up-to-date with what is in the database, but
    /// is up to date with CallKit callbacks on the main thread.
    /// Can be accessed from the main thread.
    public private(set) var callType: RPRecentCallType?

    /// Used internally for caching only.
    /// Can be accessed only within write transactions.
    private var callInteraction: TSCall? {
        didSet {
            assert(oldValue == nil)
        }
    }

    /// Used internally for caching only.
    /// Can be accessed only within write transactions.
    private var callRecord: CallRecord? {
        didSet {
            assert(oldValue == nil)
        }
    }

    public lazy var hasLocalVideo = offerMediaType == .video {
        didSet {
            AssertIsOnMainThread()

            delegate?.individualCallLocalVideoMuteDidChange(self, isVideoMuted: !hasLocalVideo)
        }
    }

    var deferredAnswerCompletion: (() -> Void)? {
        didSet {
            owsAssertDebug(deferredAnswerCompletion == nil || state == .accepting)
        }
    }

    public var state: CallState {
        didSet {
            AssertIsOnMainThread()
            Logger.debug("state changed: \(oldValue) -> \(self.state) for call: \(self)")

            let state = self.state
            if let callType = self.callType {
                Self.databaseStorage.asyncWrite {
                    if
                        let callInteraction = self.callInteraction,
                        let newCallType = self.validateCallType(
                            callType,
                            state: state,
                            for: callInteraction,
                            transaction: $0
                        )
                    {
                        self.createOrUpdateCallInteraction(callType: newCallType, transaction: $0)
                    }
                }
            }
            delegate?.individualCallStateDidChange(self, state: state)
        }
    }

    public var offerMediaType: TSRecentCallOfferType = .audio

    // We start out muted if the record permission isn't granted. This should generally
    // only happen for incoming calls, because we proactively ask about it before you
    // can make an outgoing call.
    public var isMuted = AVAudioSession.sharedInstance().recordPermission != .granted {
        didSet {
            AssertIsOnMainThread()

            Logger.debug("muted changed: \(oldValue) -> \(self.isMuted)")

            delegate?.individualCallLocalAudioMuteDidChange(self, isAudioMuted: isMuted)
        }
    }

    public var isOnHold = false {
        didSet {
            AssertIsOnMainThread()
            Logger.debug("isOnHold changed: \(oldValue) -> \(self.isOnHold)")

            delegate?.individualCallHoldDidChange(self, isOnHold: isOnHold)
        }
    }

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

    public weak var delegate: IndividualCallDelegate?

    // MARK: Initializers and Factory Methods

    init(direction: CallDirection, state: CallState, thread: TSContactThread, sentAtTimestamp: UInt64, callAdapterType: CallAdapterType) {
        self.direction = direction
        self.state = state
        self.thread = thread
        self.sentAtTimestamp = sentAtTimestamp
        self.callAdapterType = callAdapterType
    }

    deinit {
        Logger.debug("")
        owsAssertDebug(isEnded, "isEnded was unexpectedly false")
    }

    override public var description: String {
        return "IndividualCall: {\(remoteAddress), signalingId: \(callId as Optional)))}"
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
        // Snapshot the state at the time we enqueued the write.
        let state = self.state
        Self.databaseStorage.asyncWrite {
            self._createOrUpdateCallInteraction(
                callType: callType,
                state: state,
                transaction: $0
            )
        }
    }

    public func createOrUpdateCallInteraction(
        callType: RPRecentCallType,
        transaction: SDSAnyWriteTransaction
    ) {
        // We have to set this as soon as we can; see comment in async version above.
        self.callType = callType
        _createOrUpdateCallInteraction(
            callType: callType,
            state: self.state,
            transaction: transaction
        )
    }

    /// Finds any existing TSCalls if they exist, or creates a new one and inserts it into
    /// the db if not.
    ///
    /// Looks for TSCalls in the following order:
    /// * Cached in memory on IndividualCall (i.e. this call service already has dealt with it)
    /// * On the interactions table, using the CallRecord table to bridge by callId
    /// If the existing interaction needs updating to the new call type, updates it.
    /// *WILL NOT* write other fields, as they are assumed to come from a linked device
    /// that triggered the TSCall to be created and are therefore canonical.
    private func _createOrUpdateCallInteraction(
        callType: RPRecentCallType,
        state: CallState,
        transaction: SDSAnyWriteTransaction
    ) {
        if let existingCall = self.callInteraction {
            if let newCallType = self.validateCallType(callType, state: state, for: existingCall, transaction: transaction) {
                existingCall.updateCallType(newCallType, transaction: transaction)
            }
            return
        }

        if
            // find a matching existing call interaction via call records.
            // this happens if a call event sync message creates the record and
            // interaction before callkit callbacks.
            let callRecord = self.fetchCallRecord(transaction: transaction),
            let existingCall = TSCall.anyFetchCall(
                uniqueId: callRecord.interactionUniqueId,
                transaction: transaction
            )
        {
            self.callInteraction = existingCall
            if let newCallType = self.validateCallType(callType, state: state, for: existingCall, transaction: transaction) {
                existingCall.updateCallType(newCallType, transaction: transaction)
            }
            return
        }

        // Validation might modify the call type, but ignore if it tries to say we
        // shouldn't update and fall back to the original value since we are creating,
        // not updating.
        let callType = self.validateCallType(callType, state: state, for: nil, transaction: transaction) ?? callType
        // If we found nothing, create a new interaction.
        let callInteraction = TSCall(
            callType: callType,
            offerType: self.offerMediaType,
            thread: self.thread,
            sentAtTimestamp: self.sentAtTimestamp
        )
        callInteraction.anyInsert(transaction: transaction)
        self.callInteraction = callInteraction
        createOrUpdateCallRecordIfNeeded(for: callInteraction, transaction: transaction)

        if callInteraction.wasRead {
            // Mark previous unread call interactions as read.
            OWSReceiptManager.markAllCallInteractionsAsReadLocally(
                beforeSQLId: callInteraction.grdbId,
                thread: self.thread,
                transaction: transaction
            )
            let threadUniqueId = self.thread.uniqueId
            DispatchQueue.main.async {
                Self.notificationPresenter.cancelNotificationsForMissedCalls(threadUniqueId: threadUniqueId)
            }
        }
    }

    private func fetchCallRecord(
        transaction: SDSAnyReadTransaction
    ) -> CallRecord? {
        if let callRecord = callRecord {
            return callRecord
        }
        guard let callId = callId else {
            // Without a callId we can't look up a record.
            return nil
        }
        let callRecord = CallRecord.fetch(forCallId: callId, transaction: transaction)
        self.callRecord = callRecord
        return callRecord
    }

    /// Takes a call type to apply to a TSCall, and returns nil if the update is illegal (should not be applied)
    /// or the call type that should actually be applied, which can be the same or different.
    /// Pass nil for the TSCall if creating a new one.
    ///
    /// We can't blindly update the TSCall's status based on CallKit callbacks.
    /// The status might be set by a linked device via call event syncs, so we should
    /// check that the transition is valid and only update if so.
    /// (e.g. if a linked device picks up as we decline, we should leave it as accepted)
    private func validateCallType(
        _ callType: RPRecentCallType,
        state: CallState,
        for callInteraction: TSCall?,
        transaction: SDSAnyReadTransaction
    ) -> RPRecentCallType? {
        var callType = callType
        // Mark incomplete calls as completed if call has connected.
        if state == .connected, callType == .outgoingIncomplete {
            callType = .outgoing
        }
        if state == .connected, callType == .incomingIncomplete {
            callType = .incoming
        }

        guard let callInteraction = callInteraction else {
            // No further checks if we are creating a new one.
            return callType
        }
        // Otherwise we are updated and need to check if transition
        // is valid.
        guard callInteraction.callType != callType else {
            return nil
        }
        guard
            let callRecord = fetchCallRecord(transaction: transaction),
            let newStatus = callType.callRecordStatus
        else {
            return callType
        }
        // Multiple RPRecentCallTypes can map to the same CallRecord.Status,
        // but transitioning from a CallRecord.Status to itself is invalid.
        // Catch this case by letting the RPRecentCallType through if
        // it is different (checked above) but the mapped status is the same.
        guard callRecord.status == newStatus
                || CallRecord.isAllowedTransition(from: callRecord.status, to: newStatus)
        else {
            return nil
        }
        return callType
    }

    private func createOrUpdateCallRecordIfNeeded(
        for callInteraction: TSCall,
        transaction: SDSAnyWriteTransaction
    ) {
        guard let callId = self.callId else {
            return
        }
        CallRecord.createOrUpdate(
            interaction: callInteraction,
            thread: thread,
            callId: callId,
            transaction: transaction
        )
    }
}
