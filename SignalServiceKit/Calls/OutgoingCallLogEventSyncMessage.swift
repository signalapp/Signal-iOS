//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

/// Represents a sync message an event related to the Calls Tab (also known on
/// other platforms as the "call log").
///
/// - SeeAlso ``IncomingCallLogEventSyncMessageManager``
@objc(OutgoingCallLogEventSyncMessage)
public class OutgoingCallLogEventSyncMessage: OWSOutgoingSyncMessage {

    /// The call log event.
    ///
    /// - Important
    /// The ObjC name must remain as-is for compatibility with Mantle.
    ///
    /// - Note
    /// Nullability here is intentional, since Mantle will set this property via
    /// its reflection-based `init(coder:)` when we call `super.init(coder:)`.
    @objc(callLogEvent)
    private(set) var callLogEvent: CallLogEvent!

    init(
        callLogEvent: CallLogEvent,
        thread: TSThread,
        tx: SDSAnyReadTransaction
    ) {
        self.callLogEvent = callLogEvent
        super.init(thread: thread, transaction: tx)
    }

    required public init?(coder: NSCoder) {
        super.init(coder: coder)
    }

    required public init(dictionary dictionaryValue: [String: Any]!) throws {
        try super.init(dictionary: dictionaryValue)
    }

    override public var isUrgent: Bool { false }

    override public func syncMessageBuilder(transaction: SDSAnyReadTransaction) -> SSKProtoSyncMessageBuilder? {
        let callLogEventBuilder = SSKProtoSyncMessageCallLogEvent.builder()

        callLogEventBuilder.setTimestamp(callLogEvent.timestamp)
        callLogEventBuilder.setType(callLogEvent.eventType.protoType)

        if let callId = callLogEvent.callId {
            callLogEventBuilder.setCallID(callId)
        }

        if let conversationId = callLogEvent.conversationId {
            callLogEventBuilder.setConversationID(conversationId)
        }

        let builder = SSKProtoSyncMessage.builder()
        builder.setCallLogEvent(callLogEventBuilder.buildInfallibly())
        return builder
    }
}

// MARK: -

public extension OutgoingCallLogEventSyncMessage {
    @objc(OutgoingCallLogEvent)
    class CallLogEvent: NSObject, NSCoding {
        public enum EventType: UInt, CaseIterable {
            /// Indicates we cleared our call log in its entirety.
            ///
            /// - SeeAlso
            /// ``OutgoingCallEvent/EventType/deleted``, which indicates that we
            /// deleted a singular individual call.
            ///
            /// That action is part of the `CallEvent` sync message for
            /// historical reasons, in that it predates the `CallLogEvent` sync
            /// message.
            case cleared = 0

            /// Indicates we marked calls as read.
            case markedAsRead = 1

            /// Indicates we marked calls as read in a particular conversation.
            case markedAsReadInConversation = 2
        }

        let eventType: EventType
        let callId: UInt64?
        let conversationId: Data?
        let timestamp: UInt64

        init(
            eventType: EventType,
            callId: UInt64?,
            conversationId: Data?,
            timestamp: UInt64
        ) {
            self.eventType = eventType
            self.callId = callId
            self.conversationId = conversationId
            self.timestamp = timestamp
        }

        // MARK: NSCoding

        private enum Keys {
            static let eventType = "eventType"
            static let timestamp = "timestamp"
            static let callId = "callId"
            static let conversationId = "conversationId"
        }

        required public init?(coder: NSCoder) {
            guard
                let eventTypeRaw = coder.decodeObject(of: NSNumber.self, forKey: Keys.eventType) as? UInt,
                let eventType = EventType(rawValue: eventTypeRaw),
                let timestamp = coder.decodeObject(of: NSNumber.self, forKey: Keys.timestamp) as? UInt64
            else {
                owsFailDebug("Missing or unrecognized fields!")
                return nil
            }

            self.eventType = eventType
            self.timestamp = timestamp

            if
                let callId = coder.decodeObject(of: NSNumber.self, forKey: Keys.callId) as? UInt64,
                let conversationId = coder.decodeObject(of: NSData.self, forKey: Keys.conversationId) as Data?
            {
                self.callId = callId
                self.conversationId = conversationId
            } else {
                self.callId = nil
                self.conversationId = nil
            }
        }

        public func encode(with coder: NSCoder) {
            coder.encode(NSNumber(value: eventType.rawValue), forKey: Keys.eventType)
            coder.encode(NSNumber(value: timestamp), forKey: Keys.timestamp)

            if let callId, let conversationId {
                coder.encode(NSNumber(value: callId), forKey: Keys.callId)
                coder.encode(conversationId as NSData, forKey: Keys.conversationId)
            }
        }
    }
}

// MARK: -

private extension OutgoingCallLogEventSyncMessage.CallLogEvent.EventType {
    var protoType: SSKProtoSyncMessageCallLogEventType {
        switch self {
        case .cleared: return .cleared
        case .markedAsRead: return .markedAsRead
        case .markedAsReadInConversation: return .markedAsReadInConversation
        }
    }
}
