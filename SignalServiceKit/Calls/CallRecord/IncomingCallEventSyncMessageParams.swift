//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import LibSignalClient

/// Represents parameters describing an incoming `CallEvent` sync message.
///
/// `CallEvent` sync messages are used to communicate events that relate to a
/// particular call.
///
/// - SeeAlso ``IncomingCallEventSyncMessageManager``
/// - SeeAlso ``IncomingCallLogEventSyncMessageParams``
public struct IncomingCallEventSyncMessageParams {
    enum CallEvent {
        case accepted
        case notAccepted
        case deleted
        case observed

        init?(protoCallEvent: SSKProtoSyncMessageCallEventEvent) {
            switch protoCallEvent {
            case .unknownAction: return nil
            case .accepted: self = .accepted
            case .notAccepted: self = .notAccepted
            case .deleted: self = .deleted
            case .observed: self = .observed
            }
        }
    }

    let conversation: CallEventConversation
    let callId: UInt64
    let callTimestamp: UInt64
    let callEvent: CallEvent
    let callDirection: CallRecord.CallDirection

    init(
        conversation: CallEventConversation,
        callId: UInt64,
        callTimestamp: UInt64,
        callEvent: CallEvent,
        callDirection: CallRecord.CallDirection
    ) {
        self.conversation = conversation
        self.callId = callId
        self.callTimestamp = callTimestamp
        self.callEvent = callEvent
        self.callDirection = callDirection
    }

    static func parse(
        callEventProto: SSKProtoSyncMessageCallEvent
    ) throws -> Self {
        enum ParseError: Error {
            case missingOrInvalidParameters
        }

        guard
            let conversationId = callEventProto.conversationID,
            let protoCallEvent = callEventProto.event,
            let callEvent = CallEvent(protoCallEvent: protoCallEvent),
            let callType = CallRecord.CallType(protoCallType: callEventProto.type),
            let callDirection = CallRecord.CallDirection(protoCallDirection: callEventProto.direction),
            callEventProto.hasCallID,
            callEventProto.hasTimestamp,
            SDS.fitsInInt64(callEventProto.timestamp)
        else {
            throw ParseError.missingOrInvalidParameters
        }

        let callId = callEventProto.callID
        let callTimestamp = callEventProto.timestamp

        return IncomingCallEventSyncMessageParams(
            conversation: try CallEventConversation(type: callType, conversationId: conversationId),
            callId: callId,
            callTimestamp: callTimestamp,
            callEvent: callEvent,
            callDirection: callDirection
        )
    }
}

// MARK: - Conversions for incoming sync message types

private extension CallRecord.CallType {
    init?(protoCallType: SSKProtoSyncMessageCallEventType?) {
        switch protoCallType {
        case nil, .unknownType: return nil
        case .audioCall: self = .audioCall
        case .videoCall: self = .videoCall
        case .groupCall: self = .groupCall
        case .adHocCall: self = .adHocCall
        }
    }
}

private extension CallRecord.CallDirection {
    init?(protoCallDirection: SSKProtoSyncMessageCallEventDirection?) {
        switch protoCallDirection {
        case nil, .unknownDirection: return nil
        case .incoming: self = .incoming
        case .outgoing: self = .outgoing
        }
    }
}
