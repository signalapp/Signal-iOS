//
// Copyright 2022 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

@objc
public extension OutgoingCallEventSyncMessage {

    @objc(syncMessageBuilderWithCallEvent:transaction:)
    func syncMessageBuilder(
        event: OutgoingCallEvent,
        transaction: SDSAnyReadTransaction
    ) -> SSKProtoSyncMessageBuilder? {
        do {
            let callEventBuilder = SSKProtoSyncMessageCallEvent.builder()
            callEventBuilder.setCallID(event.callId)
            callEventBuilder.setType(event.type.protoValue)
            callEventBuilder.setDirection(event.direction.protoValue)
            callEventBuilder.setEvent(event.event.protoValue)
            callEventBuilder.setTimestamp(event.timestamp)
            callEventBuilder.setConversationID(event.peerUuid)

            let builder = SSKProtoSyncMessage.builder()
            builder.setCallEvent(try callEventBuilder.build())
            return builder
        } catch {
            owsFailDebug("Error: \(error)")
            return nil
        }
    }
}

fileprivate extension OWSSyncCallEventType {

    var protoValue: SSKProtoSyncMessageCallEventType {
        switch self {
        case .audioCall:
            return .audioCall
        case .videoCall:
            return .videoCall
        }
    }
}

fileprivate extension OWSSyncCallEventDirection {

    var protoValue: SSKProtoSyncMessageCallEventDirection {
        switch self {
        case .incoming:
            return .incoming
        case .outgoing:
            return .outgoing
        }
    }
}

fileprivate extension OWSSyncCallEventEvent {

    var protoValue: SSKProtoSyncMessageCallEventEvent {
        switch self {
        case .accepted:
            return .accepted
        case .notAccepted:
            return .notAccepted
        }
    }
}
