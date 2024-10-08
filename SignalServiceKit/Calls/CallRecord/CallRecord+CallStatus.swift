//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

extension CallRecord {
    public enum CallStatus: Codable, Equatable {
        case individual(IndividualCallStatus)
        case group(GroupCallStatus)
        case callLink(CallLinkCallStatus)

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

            /// This call involves ringing which is actively occuring. No action
            /// has yet been taken on the ring, and it has not expired.
            ///
            /// - Note
            /// We do not track the state of outgoing group rings and instead
            /// record them as accepted when we start the ring. Consequently,
            /// only incoming rings should be in this state.
            case ringing = 9

            /// This call involved ringing, and the ring was accepted.
            ///
            /// - Note
            /// We do not track the state of outgoing group rings and instead
            /// record them as accepted when we start the ring. All outgoing
            /// group rings will therefore end up in this state.
            case ringingAccepted = 6

            /// This call involved ringing, and the ring was declined.
            ///
            /// For an incoming call, indicates we actively declined the ring.
            ///
            /// - Note
            /// We do not track the state of outgoing group rings and instead
            /// record them as accepted when we start the ring. Consequently,
            /// only incoming rings should be in this state.
            case ringingDeclined = 7

            /// This call involved ringing, and no action was taken on the ring
            /// before it expired.
            ///
            /// A missed call is contrasted with an actively-declined one, which
            /// would fall under ``ringingNotAccepted`` above.
            ///
            /// - Note
            /// Calls declined as "busy" use this case.
            ///
            /// - Note
            /// We do not track the state of outgoing group rings and instead
            /// record them as accepted when we start the ring. Consequently,
            /// only incoming rings should be in this state.
            case ringingMissed = 8

            /// This call involved ringing, but the ring was auto-declined due
            /// to the user's Do Not Disturb settings.
            ///
            /// A missed call is contrasted with an actively-declined one, which
            /// would fall under ``ringingNotAccepted`` above.
            ///
            /// - Note
            /// At the time of writing, the iOS app does not set this status for
            /// any group calls. However, we might encounter calls with this
            /// status when restoring from a Backup.
            ///
            /// - Note
            /// We do not track the state of outgoing group rings and instead
            /// record them as accepted when we start the ring. Consequently,
            /// only incoming rings should be in this state.
            case ringingMissedNotificationProfile = 10
        }

        /// Represents the states that a call link call may be in.
        ///
        /// - Important
        /// The raw values of the cases of this enum must not overlap with the enums
        /// for the other types of calls in this file.
        public enum CallLinkCallStatus: Int, CaseIterable {
            /// We've tapped the join button but haven't been let into the call yet.
            case generic = 11

            /// We've joined the call.
            case joined = 12

            func canTransition(to newValue: Self) -> Bool {
                return self != newValue && newValue == .joined
            }
        }

        // MARK: Codable

        var intValue: Int {
            switch self {
            case .individual(let individualCallStatus): return individualCallStatus.rawValue
            case .group(let groupCallStatus): return groupCallStatus.rawValue
            case .callLink(let callLinkCallStatus): return callLinkCallStatus.rawValue
            }
        }

        private init?(intValue: Int) {
            if let individualCallStatus = IndividualCallStatus(rawValue: intValue) {
                self = .individual(individualCallStatus)
            } else if let groupCallStatus = GroupCallStatus(rawValue: intValue) {
                self = .group(groupCallStatus)
            } else if let callLinkCallStatus = CallLinkCallStatus(rawValue: intValue) {
                self = .callLink(callLinkCallStatus)
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

// MARK: - All cases

public extension CallRecord.CallStatus {
    static var allCases: [CallRecord.CallStatus] {
        let allIndividualCases: [CallRecord.CallStatus] = IndividualCallStatus.allCases
            .map { .individual($0) }
        let allGroupCases: [CallRecord.CallStatus] = GroupCallStatus.allCases
            .map { .group($0) }
        let allCallLinkCases: [CallRecord.CallStatus] = CallLinkCallStatus.allCases
            .map { .callLink($0) }

        return allIndividualCases + allGroupCases + allCallLinkCases
    }
}

// MARK: - Missed calls

public extension CallRecord.CallStatus {
    static var missedCalls: [CallRecord.CallStatus] {
        return [
            .individual(.incomingMissed),
            .group(.ringingMissed),
            .group(.ringingMissedNotificationProfile),
        ]
    }

    var isMissedCall: Bool {
        return Self.missedCalls.contains(self)
    }
}
