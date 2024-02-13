//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import SignalCoreKit

/// Represents a sync message an event related to the Calls Tab (also known on
/// other platforms as the "call log").
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

        let builder = SSKProtoSyncMessage.builder()
        builder.setCallLogEvent(callLogEventBuilder.buildInfallibly())
        return builder
    }
}

// MARK: -

public extension OutgoingCallLogEventSyncMessage {
    @objc(OutgoingCallLogEvent)
    class CallLogEvent: NSObject, NSCoding {
        public enum EventType: UInt {
            /// Indicates we should clear our call log.
            case clear = 0
        }

        let eventType: EventType
        let timestamp: UInt64

        init(
            eventType: EventType,
            timestamp: UInt64
        ) {
            self.eventType = eventType
            self.timestamp = timestamp
        }

        // MARK: NSCoding

        private enum Keys {
            static let eventType = "eventType"
            static let timestamp = "timestamp"
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
        }

        public func encode(with coder: NSCoder) {
            coder.encode(NSNumber(value: timestamp), forKey: Keys.timestamp)
            coder.encode(NSNumber(value: eventType.rawValue), forKey: Keys.eventType)
        }
    }
}

// MARK: -

private extension OutgoingCallLogEventSyncMessage.CallLogEvent.EventType {
    var protoType: SSKProtoSyncMessageCallLogEventType {
        switch self {
        case .clear: return .clear
        }
    }
}
