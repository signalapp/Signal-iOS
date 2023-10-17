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
    public enum CodingKeys: String, CodingKey {
        case id
        case callIdString = "callId"
        case interactionRowId
        case threadRowId
        case callType = "type"
        case callDirection = "direction"
        case callStatus = "status"
        case timestamp
    }

    public static let databaseTableName: String = "CallRecord"

    /// This record's SQLite row ID, if it represents a record that has already
    /// been inserted.
    public var id: Int64?

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
    public let callDirection: CallDirection
    public internal(set) var callStatus: CallStatus

    /// The timestamp of the call event represented by this record.
    ///
    /// This value will originate locally for events we learned about locally,
    /// such as receiving a 1:1 call offer message; receiving a group ring; or
    /// opportunistically discovering a group call exists. For events that
    /// occurred on linked devices, which we learned about via sync message,
    /// this value may refer to a timestamp originating on the linked device.
    ///
    /// This timestamp is intended for comparison between call records as well
    /// as display.
    public let timestamp: UInt64

    init(
        callId: UInt64,
        interactionRowId: Int64,
        threadRowId: Int64,
        callType: CallType,
        callDirection: CallDirection,
        callStatus: CallStatus,
        timestamp: UInt64
    ) {
        self.callIdString = String(callId)
        self.interactionRowId = interactionRowId
        self.threadRowId = threadRowId
        self.callType = callType
        self.callDirection = callDirection
        self.callStatus = callStatus
        self.timestamp = timestamp
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

    public enum CallDirection: Int, Codable {
        case incoming = 0
        case outgoing = 1
    }

    public enum CallStatus: Codable, Equatable {
        case individual(IndividualCallStatus)
        case group(GroupCallStatus)

        /// Represents the states that an individual (1:1) call may be in.
        ///
        /// - Important
        /// The raw values of the cases of this enum must not overlap with those
        /// for ``GroupCallStatus``, or en/decoding becomes ambiguous.
        public enum IndividualCallStatus: Int, CaseIterable {
            /// This is a call for which no action has yet been taken.
            ///
            /// For example, this call may have been accepted on a linked
            /// device, but we haven't yet received the corresponding sync
            /// message. Records with this status can be used to bridge between
            /// an incoming sync mesage and other state, such as the
            /// corresponding interaction.
            ///
            /// Records with this status should eventually be updated to another
            /// status. If they aren't, the call should be treated as missed.
            case pending = 0

            /// This call was accepted.
            ///
            /// For an incoming call, indicates we accepted the ring. For an
            /// outgoing call, indicates the receiver accepted the ring.
            case accepted = 1

            /// This call was not accepted.
            ///
            /// For an incoming call, indicates we actively declined the ring.
            /// For an outgoing call, indicates the receiver did not accept.
            case notAccepted = 2

            /// This was an incoming call that we missed.
            ///
            /// An incoming missed call is contrasted with an actively-declined
            /// one, which would fall under ``notAccepted`` above.
            ///
            /// - Note
            /// Calls declined as "busy" use this case.
            case incomingMissed = 3
        }

        /// Represents the states that a group call may be in.
        ///
        /// - Important
        /// The raw values of the cases of this enum must not overlap with those
        /// for ``IndividualCallStatus``, or en/decoding becomes ambiguous.
        public enum GroupCallStatus: Int, CaseIterable {
            /// This is a call that was started without ringing, which we have
            /// learned about but are not involved with.
            case generic = 4

            /// This is a call that was started without ringing, which we have
            /// joined.
            case joined = 5

            /// This call involved ringing, and the ring was accepted.
            ///
            /// For an incoming call, indicates we accepted the ring.
            /// - Note
            /// We do not track the state of outgoing group rings, so outgoing
            /// calls should not end up in this state.
            case ringingAccepted = 6

            /// This call involved ringing, and the ring was not accepted.
            ///
            /// For an incoming call, indicates we actively declined the ring.
            /// - Note
            /// We do not track the state of outgoing group rings, so outgoing
            /// calls should not end up in this state.
            case ringingNotAccepted = 7

            /// This was an incoming call that involved ringing, that we missed.
            ///
            /// An incoming missed call is contrasted with an actively-declined
            /// one, which would fall under ``ringingNotAccepted`` above.
            ///
            /// - Note
            /// Calls declined as "busy" use this case.
            case incomingRingingMissed = 8
        }

        // MARK: Codable

        private var intValue: Int {
            switch self {
            case .individual(let individualCallStatus): return individualCallStatus.rawValue
            case .group(let groupCallStatus): return groupCallStatus.rawValue
            }
        }

        private init?(intValue: Int) {
            if let individualCallStatus = IndividualCallStatus(rawValue: intValue) {
                self = .individual(individualCallStatus)
            } else if let groupCallStatus = GroupCallStatus(rawValue: intValue) {
                self = .group(groupCallStatus)
            } else {
                owsFailDebug("Unexpected int value: \(intValue)")
                return nil
            }
        }

        public init(from decoder: Decoder) throws {
            let singleValueContainer = try decoder.singleValueContainer()
            let intValue = try singleValueContainer.decode(Int.self)

            guard let selfValue = CallStatus(intValue: intValue) else {
                throw DecodingError.dataCorruptedError(
                    in: singleValueContainer,
                    debugDescription: "\(type(of: self)) contained unexpected int value: \(intValue)"
                )
            }

            self = selfValue
        }

        public func encode(to encoder: Encoder) throws {
            var singleValueContainer = encoder.singleValueContainer()
            try singleValueContainer.encode(intValue)
        }
    }
}
