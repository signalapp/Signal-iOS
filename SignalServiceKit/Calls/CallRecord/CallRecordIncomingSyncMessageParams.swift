//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import LibSignalClient

public struct CallRecordIncomingSyncMessageParams {
    enum ConversationType {
        case individual(contactServiceId: ServiceId)
        case group(groupId: Data)
    }

    enum CallEvent {
        case accepted
        case notAccepted
        case deleted

        init?(protoCallEvent: SSKProtoSyncMessageCallEventEvent) {
            switch protoCallEvent {
            case .unknownAction: return nil
            case .accepted: self = .accepted
            case .notAccepted: self = .notAccepted
            case .deleted: self = .deleted
            }
        }
    }

    let conversationType: ConversationType

    let callId: UInt64
    let callTimestamp: UInt64

    let callEvent: CallEvent
    let callType: CallRecord.CallType
    let callDirection: CallRecord.CallDirection

    init(
        conversationType: ConversationType,
        callId: UInt64,
        callTimestamp: UInt64,
        callEvent: CallEvent,
        callType: CallRecord.CallType,
        callDirection: CallRecord.CallDirection
    ) {
        self.conversationType = conversationType

        self.callId = callId
        self.callTimestamp = callTimestamp

        self.callEvent = callEvent
        self.callType = callType
        self.callDirection = callDirection
    }

    static func parse(
        callEventProto: SSKProtoSyncMessageCallEvent
    ) throws -> Self {
        enum ParseError: Error {
            case missingOrInvalidParameters
            case notImplementedYet
        }

        let logger = CallRecordLogger.shared

        guard
            let protoConversationId = callEventProto.conversationID,
            let protoCallEvent = callEventProto.event,
            let callEvent = CallEvent(protoCallEvent: protoCallEvent),
            let callType = CallRecord.CallType(protoCallType: callEventProto.type),
            let callDirection = CallRecord.CallDirection(protoCallDirection: callEventProto.direction),
            callEventProto.hasCallID,
            callEventProto.hasTimestamp,
            SDS.fitsInInt64(callEventProto.timestamp)
        else {
            logger.warn("Call event sync message with missing or invalid parameters!")
            throw ParseError.missingOrInvalidParameters
        }

        let callId = callEventProto.callID
        let callTimestamp = callEventProto.timestamp

        let conversationType: ConversationType

        switch callType {
        case .audioCall, .videoCall:
            guard let contactServiceId = try? ServiceId.parseFrom(
                serviceIdBinary: protoConversationId
            ) else {
                logger.warn("1:1 call event sync message with invalid contact service ID!")
                throw ParseError.missingOrInvalidParameters
            }

            conversationType = .individual(contactServiceId: contactServiceId)
        case .groupCall:
            guard GroupManager.isV2GroupId(protoConversationId) else {
                logger.warn("Group call event sync message with invalid conversation ID!")
                throw ParseError.missingOrInvalidParameters
            }

            conversationType = .group(groupId: protoConversationId)
        }

        return CallRecordIncomingSyncMessageParams(
            conversationType: conversationType,
            callId: callId,
            callTimestamp: callTimestamp,
            callEvent: callEvent,
            callType: callType,
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
