//
// Copyright 2016 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import AVFoundation
import SignalServiceKit
import SignalRingRTC
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
    func individualCallStateDidChange(_ call: IndividualCall, state: CallState)
    func individualCallLocalVideoMuteDidChange(_ call: IndividualCall, isVideoMuted: Bool)
    func individualCallLocalAudioMuteDidChange(_ call: IndividualCall, isAudioMuted: Bool)
    func individualCallHoldDidChange(_ call: IndividualCall, isOnHold: Bool)
    func individualCallRemoteVideoMuteDidChange(_ call: IndividualCall, isVideoMuted: Bool)
    func individualCallRemoteSharingScreenDidChange(_ call: IndividualCall, isRemoteSharingScreen: Bool)
}

extension IndividualCallObserver {
    func individualCallLocalVideoMuteDidChange(_ call: IndividualCall, isVideoMuted: Bool) {}
    func individualCallLocalAudioMuteDidChange(_ call: IndividualCall, isAudioMuted: Bool) {}
    func individualCallHoldDidChange(_ call: IndividualCall, isOnHold: Bool) {}
    func individualCallRemoteVideoMuteDidChange(_ call: IndividualCall, isVideoMuted: Bool) {}
    func individualCallRemoteSharingScreenDidChange(_ call: IndividualCall, isRemoteSharingScreen: Bool) {}
}

/**
 * Data model for a WebRTC backed voice/video call.
 *
 * This class' state should only be accessed on the main queue.
 */
public class IndividualCall: CustomDebugStringConvertible {

    private var callRecordStore: any CallRecordStore { DependenciesBridge.shared.callRecordStore }
    private var databaseStorage: SDSDatabaseStorage { NSObject.databaseStorage }
    private var individualCallRecordManager: any IndividualCallRecordManager { DependenciesBridge.shared.individualCallRecordManager }
    private var notificationPresenter: NotificationPresenterImpl { NSObject.notificationPresenterImpl }

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
            self.databaseStorage.asyncWrite { transaction in
                if let callInteraction = self.callInteraction {
                    self.createOrUpdateCallRecordIfNeeded(for: callInteraction, transaction: transaction)
                } else {
                    Logger.info("Unable to create call record with id; no interaction yet")
                }
            }
        }
    }

    weak var remoteVideoTrack: RTCVideoTrack? {
        didSet {
            AssertIsOnMainThread()

            Logger.info("")

            observers.elements.forEach {
                $0.individualCallRemoteVideoMuteDidChange(self, isVideoMuted: !isRemoteVideoEnabled)
            }
        }
    }

    var isRemoteVideoEnabled = false {
        didSet {
            AssertIsOnMainThread()

            Logger.info("\(isRemoteVideoEnabled)")
            observers.elements.forEach {
                $0.individualCallRemoteVideoMuteDidChange(self, isVideoMuted: !isRemoteVideoEnabled)
            }
        }
    }

    var isRemoteSharingScreen = false {
        didSet {
            AssertIsOnMainThread()

            Logger.info("\(isRemoteSharingScreen)")
            observers.elements.forEach {
                $0.individualCallRemoteSharingScreenDidChange(self, isRemoteSharingScreen: isRemoteSharingScreen)
            }
        }
    }

    var networkRoute: NetworkRoute = NetworkRoute(localAdapterType: .unknown)

    // MARK: -

    var remoteAddress: SignalServiceAddress { thread.contactAddress }

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

    lazy var hasLocalVideo = offerMediaType == .video {
        didSet {
            AssertIsOnMainThread()

            observers.elements.forEach {
                $0.individualCallLocalVideoMuteDidChange(self, isVideoMuted: !hasLocalVideo)
            }
        }
    }

    var deferredAnswerCompletion: (() -> Void)? {
        didSet {
            owsAssertDebug(deferredAnswerCompletion == nil || state == .accepting)
        }
    }

    var state: CallState {
        didSet {
            AssertIsOnMainThread()
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
    public var isMuted = AVAudioSession.sharedInstance().recordPermission != .granted {
        didSet {
            AssertIsOnMainThread()

            Logger.debug("muted changed: \(oldValue) -> \(self.isMuted)")

            observers.elements.forEach {
                $0.individualCallLocalAudioMuteDidChange(self, isAudioMuted: isMuted)
            }
        }
    }

    public var isOnHold = false {
        didSet {
            AssertIsOnMainThread()
            Logger.debug("isOnHold changed: \(oldValue) -> \(self.isOnHold)")

            observers.elements.forEach {
                $0.individualCallHoldDidChange(self, isOnHold: isOnHold)
            }
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

    private(set) lazy var videoCaptureController = VideoCaptureController()

    // MARK: Initializers and Factory Methods

    static func outgoingIndividualCall(
        thread: TSContactThread,
        offerMediaType: TSRecentCallOfferType
    ) -> IndividualCall {
        return IndividualCall(
            direction: .outgoing,
            offerMediaType: offerMediaType,
            state: .dialing,
            thread: thread,
            sentAtTimestamp: Date.ows_millisecondTimestamp()
        )
    }

    static func incomingIndividualCall(
        thread: TSContactThread,
        sentAtTimestamp: UInt64,
        offerMediaType: TSRecentCallOfferType
    ) -> IndividualCall {
        return IndividualCall(
            direction: .incoming,
            offerMediaType: offerMediaType,
            state: .answering,
            thread: thread,
            sentAtTimestamp: sentAtTimestamp
        )
    }

    init(
        direction: CallDirection,
        offerMediaType: TSRecentCallOfferType,
        state: CallState,
        thread: TSContactThread,
        sentAtTimestamp: UInt64
    ) {
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
        owsAssertDebug(isEnded, "isEnded was unexpectedly false")
    }

    public var debugDescription: String {
        return "IndividualCall: {\(remoteAddress), signalingId: \(callId as Optional)))}"
    }

    // MARK: - Observers

    private var observers: WeakArray<any IndividualCallObserver> = []

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
        self.databaseStorage.asyncWrite {
            self._createOrUpdateCallInteraction(
                callType: callType,
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
        transaction: SDSAnyWriteTransaction
    ) {
        func updateCallType(existingCall: TSCall) {
            guard shouldUpdateCallType(callType, for: existingCall, tx: transaction) else {
                return
            }

            guard let existingCallRowId = existingCall.sqliteRowId else {
                owsFailDebug("Missing SQLite row ID for call!")
                return
            }

            individualCallRecordManager.updateInteractionTypeAndRecordIfExists(
                individualCallInteraction: existingCall,
                individualCallInteractionRowId: existingCallRowId,
                contactThread: thread,
                newCallInteractionType: callType,
                tx: transaction.asV2Write
            )
        }

        if let existingCall = self.callInteraction {
            Logger.info("Existing call interaction found, updating")
            updateCallType(existingCall: existingCall)
            return
        }

        if
            // find a matching existing call interaction via call records.
            // this happens if a call event sync message creates the record and
            // interaction before callkit callbacks.
            let callRecord = self.fetchCallRecord(transaction: transaction),
            let existingCall = InteractionFinder.fetch(
                rowId: callRecord.interactionRowId,
                transaction: transaction
            ) as? TSCall
        {
            Logger.info("Existing call interaction found on disk, updating")
            self.callInteraction = existingCall
            updateCallType(existingCall: existingCall)
            return
        }

        Logger.info("No existing call interaction found; creating")

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
            DispatchQueue.main.async { [notificationPresenter] in
                notificationPresenter.cancelNotificationsForMissedCalls(threadUniqueId: threadUniqueId)
            }
        }
    }

    private func fetchCallRecord(
        transaction: SDSAnyReadTransaction
    ) -> CallRecord? {
        if let callRecord {
            return callRecord
        }

        guard let callId else {
            // Without a callId we can't look up a record.
            return nil
        }

        guard let threadRowId = thread.sqliteRowId else {
            owsFailDebug("Missing SQLite row ID for thread!")
            return nil
        }

        let callRecord: CallRecord? = {
            switch self.callRecordStore.fetch(
                callId: callId, threadRowId: threadRowId, tx: transaction.asV2Read
            ) {
            case .matchFound(let callRecord):
                return callRecord
            case .matchDeleted, .matchNotFound:
                return nil
            }
        }()

        self.callRecord = callRecord
        return callRecord
    }

    /// Takes a call type to apply to a TSCall, and returns whether or not the
    /// update should be applied. Pass nil for the TSCall if creating a new one.
    ///
    /// We can't blindly update the TSCall's status based on CallKit callbacks.
    /// The status might be set by a linked device via call event syncs, so we should
    /// check that the transition is valid and only update if so.
    /// (e.g. if a linked device picks up as we decline, we should leave it as accepted)
    private func shouldUpdateCallType(
        _ callType: RPRecentCallType,
        for callInteraction: TSCall?,
        tx transaction: SDSAnyReadTransaction
    ) -> Bool {
        guard let callInteraction = callInteraction else {
            // No further checks if we are creating a new one.
            return true
        }
        // Otherwise we are updated and need to check if transition
        // is valid.
        guard callInteraction.callType != callType else {
            return false
        }
        guard
            let callRecord = fetchCallRecord(transaction: transaction),
            case let .individual(existingIndividualCallStatus) = callRecord.callStatus,
            let newIndividualCallStatus = CallRecord.CallStatus.IndividualCallStatus(
                individualCallInteractionType: callType
            )
        else {
            return true
        }
        // Multiple RPRecentCallTypes can map to the same CallRecord status,
        // but transitioning from a CallRecord status to itself is invalid.
        // Catch this case by letting the RPRecentCallType through if
        // it is different (checked above) but the mapped status is the same.
        guard
            existingIndividualCallStatus == newIndividualCallStatus
            || IndividualCallRecordStatusTransitionManager().isStatusTransitionAllowed(
                fromIndividualCallStatus: existingIndividualCallStatus,
                toIndividualCallStatus: newIndividualCallStatus
            )
         else {
            return false
        }
        return true
    }

    private func createOrUpdateCallRecordIfNeeded(
        for callInteraction: TSCall,
        transaction: SDSAnyWriteTransaction
    ) {
        guard let callId = self.callId else {
            Logger.info("No call id; unable to create call record.")
            return
        }
        Logger.info("Creating or updating call record for interaction: \(callInteraction.callType).")

        guard
            let callInteractionRowId = callInteraction.sqliteRowId,
            let threadRowId = thread.sqliteRowId
        else {
            owsFailDebug("Missing SQLite row IDs for models!")
            return
        }

        individualCallRecordManager.createOrUpdateRecordForInteraction(
            individualCallInteraction: callInteraction,
            individualCallInteractionRowId: callInteractionRowId,
            contactThread: thread,
            contactThreadRowId: threadRowId,
            callId: callId,
            tx: transaction.asV2Write
        )
    }
}
