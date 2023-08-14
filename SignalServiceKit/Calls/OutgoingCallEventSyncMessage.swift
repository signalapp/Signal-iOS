//
// Copyright 2022 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import SignalCoreKit

/// Represents a call event that occurred on this device that we want to
/// communicate to our linked devices.
@objc(OutgoingCallEvent)
class OutgoingCallEvent: NSObject, NSCoding {
    enum CallType: UInt {
        case audio
        case video
    }

    enum EventDirection: UInt {
        case incoming
        case outgoing
    }

    enum EventType: UInt {
        case accepted
        case notAccepted
    }

    let timestamp: UInt64
    let conversationId: Data

    let callId: UInt64
    let callType: CallType
    let eventDirection: EventDirection
    let eventType: EventType

    init(
        timestamp: UInt64,
        conversationId: Data,
        callId: UInt64,
        callType: CallType,
        eventDirection: EventDirection,
        eventType: EventType
    ) {
        self.timestamp = timestamp
        self.conversationId = conversationId
        self.callId = callId
        self.callType = callType
        self.eventDirection = eventDirection
        self.eventType = eventType
    }

    // MARK: NSCoding

    private enum Keys {
        static let timestamp = "timestamp"
        static let conversationId = "peerUuid"
        static let callId = "callId"
        static let callType = "type"
        static let eventDirection = "direction"
        static let eventType = "event"
    }

    func encode(with coder: NSCoder) {
        coder.encode(NSNumber(value: timestamp), forKey: Keys.timestamp)
        coder.encode(conversationId as NSData, forKey: Keys.conversationId)
        coder.encode(NSNumber(value: callId), forKey: Keys.callId)
        coder.encode(NSNumber(value: callType.rawValue), forKey: Keys.callType)
        coder.encode(NSNumber(value: eventDirection.rawValue), forKey: Keys.eventDirection)
        coder.encode(NSNumber(value: eventType.rawValue), forKey: Keys.eventType)
    }

    required init?(coder: NSCoder) {
        guard
            let timestamp = coder.decodeObject(of: NSNumber.self, forKey: Keys.timestamp) as? UInt64,
            let conversationId = coder.decodeObject(of: NSData.self, forKey: Keys.conversationId),
            let callId = coder.decodeObject(of: NSNumber.self, forKey: Keys.callId) as? UInt64,
            let callTypeRaw = coder.decodeObject(of: NSNumber.self, forKey: Keys.callType) as? UInt,
            let callType = CallType(rawValue: callTypeRaw),
            let eventDirectionRaw = coder.decodeObject(of: NSNumber.self, forKey: Keys.eventDirection) as? UInt,
            let eventDirection = EventDirection(rawValue: eventDirectionRaw),
            let eventTypeRaw = coder.decodeObject(of: NSNumber.self, forKey: Keys.eventType) as? UInt,
            let eventType = EventType(rawValue: eventTypeRaw)
        else {
            owsFailDebug("Missing or unrecognized fields!")
            return nil
        }

        self.timestamp = timestamp
        self.conversationId = conversationId as Data
        self.callId = callId
        self.callType = callType
        self.eventDirection = eventDirection
        self.eventType = eventType
    }
}

/// Represents a sync message containing a "call event".
///
/// Indicates to linked devices that a call has changed state. For example, that
/// we accepted a ringing call on this device.
@objc(OutgoingCallEventSyncMessage)
public class OutgoingCallEventSyncMessage: OWSOutgoingSyncMessage {

    /// The call event.
    ///
    /// The ObjC name must remain as-is for compatibility with legacy data
    /// archived using Mantle. When this model was originally written (in ObjC),
    /// the property was named `event` - therefore, Mantle will have used that
    /// name as a key when doing its reflection-based archiving.
    ///
    /// - Note
    /// Nullability here is intentional, since Mantle will set this property via
    /// its reflection-based `init(coder:)` when we call `super.init(coder:)`.
    @objc(event)
    private(set) var callEvent: OutgoingCallEvent!

    init(
        thread: TSThread,
        event: OutgoingCallEvent,
        tx: SDSAnyReadTransaction
    ) {
        self.callEvent = event
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
        let callEventBuilder = SSKProtoSyncMessageCallEvent.builder()
        callEventBuilder.setCallID(callEvent.callId)
        callEventBuilder.setType(callEvent.callType.protoValue)
        callEventBuilder.setDirection(callEvent.eventDirection.protoValue)
        callEventBuilder.setEvent(callEvent.eventType.protoValue)
        callEventBuilder.setTimestamp(callEvent.timestamp)
        callEventBuilder.setConversationID(callEvent.conversationId)

        let builder = SSKProtoSyncMessage.builder()
        builder.setCallEvent(callEventBuilder.buildInfallibly())
        return builder
    }
}

fileprivate extension OutgoingCallEvent.CallType {
    var protoValue: SSKProtoSyncMessageCallEventType {
        switch self {
        case .audio:
            return .audioCall
        case .video:
            return .videoCall
        }
    }
}

fileprivate extension OutgoingCallEvent.EventDirection {
    var protoValue: SSKProtoSyncMessageCallEventDirection {
        switch self {
        case .incoming:
            return .incoming
        case .outgoing:
            return .outgoing
        }
    }
}

fileprivate extension OutgoingCallEvent.EventType {
    var protoValue: SSKProtoSyncMessageCallEventEvent {
        switch self {
        case .accepted:
            return .accepted
        case .notAccepted:
            return .notAccepted
        }
    }
}
