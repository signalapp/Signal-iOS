//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

public protocol CallRecordStatusTransitionManager {
    func isStatusTransitionAllowed(
        from fromStatus: CallRecord.CallStatus,
        to toStatus: CallRecord.CallStatus
    ) -> Bool
}

final class CallRecordStatusTransitionManagerImpl: CallRecordStatusTransitionManager {
    func isStatusTransitionAllowed(
        from fromStatus: CallRecord.CallStatus,
        to toStatus: CallRecord.CallStatus
    ) -> Bool {
        switch (fromStatus, toStatus) {
        case (.individual, .group), (.group, .individual):
            CallRecordLogger.shared.error(
                "Attempting to transition between individual and group call statuses: \(fromStatus) -> \(toStatus)"
            )
            return false
        case let (.individual(fromIndividualStatus), .individual(toIndividualStatus)):
            return isStatusTransitionAllowed(
                fromIndividualCallStatus: fromIndividualStatus,
                toIndividualCallStatus: toIndividualStatus
            )
        case let (.group(fromGroupStatus), .group(toGroupStatus)):
            return isStatusTransitionAllowed(
                fromGroupCallStatus: fromGroupStatus,
                toGroupCallStatus: toGroupStatus
            )
        }
    }

    private func isStatusTransitionAllowed(
        fromIndividualCallStatus: CallRecord.CallStatus.IndividualCallStatus,
        toIndividualCallStatus: CallRecord.CallStatus.IndividualCallStatus
    ) -> Bool {
        switch fromIndividualCallStatus {
        case .pending:
            switch toIndividualCallStatus {
            case .pending: return false
            case .accepted, .notAccepted, .incomingMissed:
                // Pending can transition to anything.
                return true
            }
        case .accepted:
            switch toIndividualCallStatus {
            case .accepted, .pending: return false
            case .notAccepted, .incomingMissed:
                // Accepted trumps declined or missed.
                return false
            }
        case .notAccepted:
            switch toIndividualCallStatus {
            case .notAccepted, .pending: return false
            case .accepted:
                // Accepted trumps declined...
                return true
            case .incomingMissed:
                // ...but declined trumps missed.
                return false
            }
        case .incomingMissed:
            switch toIndividualCallStatus {
            case .incomingMissed, .pending: return false
            case .accepted, .notAccepted:
                // Accepted or declined trumps missed.
                return true
            }
        }
    }

    private func isStatusTransitionAllowed(
        fromGroupCallStatus: CallRecord.CallStatus.GroupCallStatus,
        toGroupCallStatus: CallRecord.CallStatus.GroupCallStatus
    ) -> Bool {
        switch fromGroupCallStatus {
        case .generic:
            switch toGroupCallStatus {
            case .generic: return false
            case .joined:
                // User joined a call started without ringing.
                return true
            case .ringingAccepted, .ringingNotAccepted, .incomingRingingMissed:
                // This probably indicates a race between us opportunistically
                // learning about a call (e.g., by peeking), and receiving a
                // ring for that call. That's fine, but we prefer the
                // ring-related status.
                return true
            }
        case .joined:
            switch toGroupCallStatus {
            case .joined: return false
            case .generic, .ringingNotAccepted, .incomingRingingMissed:
                // Prefer the fact that we joined somewhere.
                return false
            case .ringingAccepted:
                // This probably indicates a race between us opportunistically
                // joining about a call, and receiving a ring for that call.
                // That's fine, but we prefer the ring-related status.
                return true
            }
        case .ringingAccepted:
            switch toGroupCallStatus {
            case .ringingAccepted: return false
            case .generic, .joined, .ringingNotAccepted, .incomingRingingMissed:
                // Prefer the fact that we accepted the ring somewhere.
                return false
            }
        case .ringingNotAccepted:
            switch toGroupCallStatus {
            case .ringingNotAccepted: return false
            case .generic, .joined, .incomingRingingMissed:
                // Prefer the explicit ring-related status.
                return false
            case .ringingAccepted:
                // Prefer the fact that we accepted the ring somewhere.
                return true
            }
        case .incomingRingingMissed:
            switch toGroupCallStatus {
            case .incomingRingingMissed: return false
            case .generic, .joined:
                // Prefer the ring-related status.
                return false
            case .ringingAccepted, .ringingNotAccepted:
                // Prefer the explicit ring-related status.
                return true
            }
        }
    }
}
