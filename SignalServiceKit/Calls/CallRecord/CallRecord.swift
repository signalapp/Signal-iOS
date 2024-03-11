//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import GRDB
import LibSignalClient
import SignalCoreKit

/// Represents a record of a call, either 1:1 or in a group.
///
/// Powers both "call disposition" (i.e., sending sync messages for call-related
/// events) as well as the Calls Tab.
public final class CallRecord: Codable, PersistableRecord, FetchableRecord {

    public static let databaseTableName: String = "CallRecord"

    public enum CodingKeys: String, CodingKey {
        case id
        case callIdString = "callId"
        case interactionRowId
        case threadRowId
        case callType = "type"
        case callDirection = "direction"
        case callStatus = "status"
        case _groupCallRingerAci = "groupCallRingerAci"
        case callBeganTimestamp = "timestamp"
        case unreadStatus = "unreadStatus"
    }

    /// This record's SQLite row ID, if it represents a record that has already
    /// been inserted.
    public internal(set) var id: Int64?

    /// A string representation of the UInt64 ID for this call.
    ///
    /// SQLite stores values as Int64 and we've had issues with UInt64 and GRDB,
    /// so as a workaround we store it as a string.
    private let callIdString: String

    /// The unique ID of this call, shared across clients.
    public var callId: UInt64 { return UInt64(callIdString)! }

    /// The SQLite row ID of the interaction representing this call.
    ///
    /// Every ``CallRecord`` has an associated interaction, which is used to
    /// render call events. These interactions will be either a ``TSCall`` or
    /// ``OWSGroupCallMessage``.
    ///
    /// Some state may be duplicated between a ``CallRecord`` and its
    /// corresponding interaction; however, the ``CallRecord`` should be
    /// considered the source of truth.
    public let interactionRowId: Int64

    /// The SQLite row ID of the thread this call belongs to.
    public let threadRowId: Int64

    public let callType: CallType
    public internal(set) var callDirection: CallDirection
    public internal(set) var callStatus: CallStatus

    /// The "unread" status of this call, which is used for app icon and Calls
    /// Tab badging.
    ///
    /// - Note
    /// Only missed calls should ever be in an unread state. All other calls
    /// should have already been marked as read.
    ///
    /// - SeeAlso: ``CallRecord/CallStatus/isMissedCall``
    /// - SeeAlso: ``CallRecordStore/updateCallAndUnreadStatus(callRecord:newCallStatus:tx:)``
    public internal(set) var unreadStatus: CallUnreadStatus

    /// If this record represents a group ring, returns the user that initiated
    /// the ring.
    ///
    /// - Important
    /// This field is only usable if this record represents a group ring.
    public internal(set) var groupCallRingerAci: Aci? {
        get {
            guard isGroupRing else {
                CallRecordLogger.shared.error("Requested group call ringer, but this record wasn't a group ring!")
                return nil
            }

            return _groupCallRingerAci.map { Aci(fromUUID: $0) }
        }
        set {
            guard let newValue else {
                CallRecordLogger.shared.error("We should never attempt to clear the group call ringer!")
                return
            }

            guard isGroupRing else {
                CallRecordLogger.shared.error("Set group call ringer, but this record wasn't a group ring!")
                return
            }

            _groupCallRingerAci = newValue.rawUUID
        }
    }
    private var _groupCallRingerAci: UUID?

    /// Does this record represent a group ring?
    private var isGroupRing: Bool {
        switch callStatus {
        case .group(.ringing), .group(.ringingAccepted), .group(.ringingDeclined), .group(.ringingMissed):
            return true
        case .individual, .group(.generic), .group(.joined):
            return false
        }
    }

    /// The timestamp at which we believe the call began.
    ///
    /// For calls we discover on this device, such as by receiving a 1:1 call
    /// offer message or a group call ring, this value will be the local
    /// timestamp of the discovery.
    ///
    /// If we receive a message indicating that the call began earlier than we
    /// think it did, this value should reflect the earlier time. This helps
    /// ensure that the view of this call is consistent across our devices, and
    /// across the other participants in the call.
    ///
    /// For example, a linked device may opportunistically join a group call by
    /// peeking it (and send us a sync message about that), before a ring
    /// message for that same call arrives to us. We'll prefer the earlier time
    /// locally, which keeps us in-sync with our linked device.
    ///
    /// In another example, we may discover a group call by peeking at time T,
    /// while processing a message backlog. If that backlog contains a group
    /// call update message for this call indicating it actually began at time
    /// T-1, we'll prefer the earlier time, which keeps us in sync with everyone
    /// else who got that update message.
    ///
    /// This timestamp is intended for comparison between call records, as well
    /// as for display.
    public internal(set) var callBeganTimestamp: UInt64

    /// Creates a ``CallRecord`` with the given parameters.
    ///
    /// - Note
    /// The ``unreadStatus`` for this call record is automatically derived from
    /// its given call status.
    public init(
        callId: UInt64,
        interactionRowId: Int64,
        threadRowId: Int64,
        callType: CallType,
        callDirection: CallDirection,
        callStatus: CallStatus,
        groupCallRingerAci: Aci? = nil,
        callBeganTimestamp: UInt64
    ) {
        self.callIdString = String(callId)
        self.interactionRowId = interactionRowId
        self.threadRowId = threadRowId
        self.callType = callType
        self.callDirection = callDirection
        self.callStatus = callStatus
        self.unreadStatus = CallUnreadStatus(callStatus: callStatus)
        self.callBeganTimestamp = callBeganTimestamp

        if let groupCallRingerAci, isGroupRing {
            self.groupCallRingerAci = groupCallRingerAci
        }
    }

    /// Capture the SQLite row ID for this record, after insertion.
    public func didInsert(with rowID: Int64, for column: String?) {
        id = rowID
    }
}

// MARK: - Accessory types

extension CallRecord {
    public enum CallType: Int, Codable {
        case audioCall = 0
        case videoCall = 1
        case groupCall = 2
        // [Calls] TODO: add call links here
    }

    public enum CallDirection: Int, Codable, CaseIterable {
        case incoming = 0
        case outgoing = 1
    }

    public enum CallUnreadStatus: Int, Codable {
        case read = 0
        case unread = 1

        init(callStatus: CallStatus) {
            if callStatus.isMissedCall {
                self = .unread
            } else {
                self = .read
            }
        }
    }
}

#if TESTABLE_BUILD

extension CallRecord {
    func matches(
        _ other: CallRecord,
        overridingThreadRowId: Int64? = nil
    ) -> Bool {
        if
            id == other.id,
            callId == other.callId,
            interactionRowId == other.interactionRowId,
            threadRowId == (overridingThreadRowId ?? other.threadRowId),
            callType == other.callType,
            callDirection == other.callDirection,
            callStatus == other.callStatus,
            groupCallRingerAci == other.groupCallRingerAci,
            callBeganTimestamp == other.callBeganTimestamp,
            unreadStatus == other.unreadStatus
        {
            return true
        }

        return false
    }
}

#endif
