//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import LibSignalClient

public struct CallRecordIncomingSyncMessageParams {
    enum ConversationParams {
        case oneToOne(
            contactServiceId: ServiceId,
            individualCallStatus: CallRecord.CallStatus.IndividualCallStatus,
            individualCallInteractionType: RPRecentCallType
        )

        case group(
            groupId: Data,
            groupCallStatus: CallRecord.CallStatus.GroupCallStatus
        )
    }

    let callId: UInt64
    let conversationParams: ConversationParams
    let callTimestamp: UInt64

    let callType: CallRecord.CallType
    let callDirection: CallRecord.CallDirection

    init(
        callId: UInt64,
        conversationParams: ConversationParams,
        callTimestamp: UInt64,
        callType: CallRecord.CallType,
        callDirection: CallRecord.CallDirection
    ) {
        self.callId = callId
        self.conversationParams = conversationParams
        self.callTimestamp = callTimestamp

        self.callType = callType
        self.callDirection = callDirection
    }

    static func parse(
        callEventProto callEvent: SSKProtoSyncMessageCallEvent
    ) throws -> Self {
        enum ParseError: Error {
            case missingOrInvalidParameters
            case notImplementedYet
        }

        let logger = CallRecordLogger.shared

        guard
            let protoConversationId = callEvent.conversationID,
            let protoCallEvent = callEvent.event,
            let callType = CallRecord.CallType(protoCallType: callEvent.type),
            let callDirection = CallRecord.CallDirection(protoCallDirection: callEvent.direction),
            callEvent.hasCallID,
            callEvent.hasTimestamp
        else {
            logger.warn("Call event sync message with missing or invalid parameters!")
            throw ParseError.missingOrInvalidParameters
        }

        let callId = callEvent.callID
        let callTimestamp = callEvent.timestamp

        let conversationParams: ConversationParams

        switch callType {
        case .audioCall, .videoCall:
            guard
                let contactServiceId = try? ServiceId.parseFrom(serviceIdBinary: protoConversationId),
                let individualCallStatus = CallRecord.CallStatus.IndividualCallStatus(protoCallEvent: protoCallEvent)
            else {
                logger.warn("1:1 call event sync message with invalid parameters!")
                throw ParseError.missingOrInvalidParameters
            }

            let individualCallInteractionType: RPRecentCallType = {
                switch (callDirection, individualCallStatus) {
                case (.incoming, .accepted): return .incomingAnsweredElsewhere
                case (.incoming, .notAccepted): return .incomingDeclinedElsewhere
                case (.outgoing, .accepted): return .outgoing
                case (.outgoing, .notAccepted): return .outgoingMissed
                case (_, .pending), (_, .incomingMissed):
                    owsFail("Impossible to parse out local-only states. How did we get here?")
                }
            }()

            conversationParams = .oneToOne(
                contactServiceId: contactServiceId,
                individualCallStatus: individualCallStatus,
                individualCallInteractionType: individualCallInteractionType
            )
        case .groupCall:
            guard GroupManager.isV2GroupId(protoConversationId) else {
                logger.warn("Group call event sync message with invalid conversation ID!")
                throw ParseError.missingOrInvalidParameters
            }

            throw ParseError.notImplementedYet
        }

        return CallRecordIncomingSyncMessageParams(
            callId: callId,
            conversationParams: conversationParams,
            callTimestamp: callTimestamp,
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

private extension CallRecord.CallStatus.IndividualCallStatus {
    init?(protoCallEvent: SSKProtoSyncMessageCallEventEvent) {
        switch protoCallEvent {
        case .unknownAction: return nil
        case .accepted: self = .accepted
        case .notAccepted: self = .notAccepted
        }
    }
}
