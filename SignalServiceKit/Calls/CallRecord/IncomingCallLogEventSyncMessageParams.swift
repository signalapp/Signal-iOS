//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import LibSignalClient

/// Represents parameters describing an incoming `CallLogEvent` sync message.
///
/// `CallLogEvent` sync messages are used to communicate events that relate to
/// the Calls Tab, known on other clients as the "call log". These are bulk
/// events, and do not apply to only a particular call. They do, however,
/// contain data identifying an "anchor" call, which serves as a reference point
/// when performing the specified bulk-action.
///
/// - SeeAlso ``IncomingCallLogEventSyncMessageManager``
/// - SeeAlso ``IncomingCallEventSyncMessageParams``
struct IncomingCallLogEventSyncMessageParams {
    enum EventType {
        case cleared
        case markedAsRead
        case markedAsReadInConversation
    }

    struct CallIdentifiers {
        let callId: UInt64
        let conversationId: Data
    }

    let eventType: EventType
    let anchorCallIdentifiers: CallIdentifiers?
    let anchorTimestamp: UInt64

    init(
        eventType: EventType,
        anchorCallIdentifiers: CallIdentifiers?,
        anchorTimestamp: UInt64
    ) {
        self.eventType = eventType
        self.anchorCallIdentifiers = anchorCallIdentifiers
        self.anchorTimestamp = anchorTimestamp
    }

    static func parse(
        callLogEvent: SSKProtoSyncMessageCallLogEvent
    ) throws -> Self {
        enum ParseError: Error {
            case missingOrInvalidParams
        }

        guard
            let eventType = callLogEvent.type.map({ EventType(protoEventType: $0) }),
            callLogEvent.hasTimestamp,
            SDS.fitsInInt64(callLogEvent.timestamp)
        else {
            throw ParseError.missingOrInvalidParams
        }

        let timestamp = callLogEvent.timestamp

        /// Sync messages from old devices may not contain a `callId` or
        /// `conversationId`, which we use in newer messages to identify the
        /// call this sync message is referencing.
        let callIdentifiers = { () -> CallIdentifiers? in
            guard
                let conversationId = callLogEvent.conversationID,
                callLogEvent.hasCallID
            else { return nil }

            return CallIdentifiers(
                callId: callLogEvent.callID,
                conversationId: conversationId
            )
        }()

        return IncomingCallLogEventSyncMessageParams(
            eventType: eventType,
            anchorCallIdentifiers: callIdentifiers,
            anchorTimestamp: timestamp
        )
    }
}

private extension IncomingCallLogEventSyncMessageParams.EventType {
    init(protoEventType: SSKProtoSyncMessageCallLogEventType) {
        switch protoEventType {
        case .cleared: self = .cleared
        case .markedAsRead: self = .markedAsRead
        case .markedAsReadInConversation: self = .markedAsReadInConversation
        }
    }
}
