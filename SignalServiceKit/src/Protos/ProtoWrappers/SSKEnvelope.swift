//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

import Foundation

@objc
public class SSKEnvelope: NSObject {

    enum EnvelopeError: Error {
        case invalidProtobuf(description: String)
    }

    @objc
    public enum SSKEnvelopeType: Int32 {
        case unknown = 0
        case ciphertext = 1
        case keyExchange = 2
        case prekeyBundle = 3
        case receipt = 5
    }

    @objc
    public let timestamp: UInt64

    @objc
    public let source: String

    @objc
    public let sourceDevice: UInt32

    @objc
    public let type: SSKEnvelopeType

    @objc
    public let relay: String?

    @objc
    public let content: Data?

    @objc
    public let legacyMessage: Data?

    @objc
    public init(timestamp: UInt64, source: String, sourceDevice: UInt32, type: SSKEnvelopeType, content: Data?, legacyMessage: Data?) {
        self.source = source
        self.type = type
        self.timestamp = timestamp
        self.sourceDevice = sourceDevice
        self.relay = nil
        self.content = content
        self.legacyMessage = legacyMessage
    }

    @objc
    public init(serializedData: Data) throws {
        let proto: SignalServiceProtos_Envelope = try SignalServiceProtos_Envelope(serializedData: serializedData)

        guard proto.hasSource else {
            throw EnvelopeError.invalidProtobuf(description: "missing required field: source")
        }
        self.source = proto.source

        guard proto.hasType else {
            throw EnvelopeError.invalidProtobuf(description: "missing required field: type")
        }
        self.type = {
            switch proto.type {
            case .unknown:
                return .unknown
            case .ciphertext:
                return .ciphertext
            case .keyExchange:
                return .keyExchange
            case .prekeyBundle:
                return .prekeyBundle
            case .receipt:
                return .receipt
            }
        }()

        guard proto.hasTimestamp else {
            throw EnvelopeError.invalidProtobuf(description: "missing required field: timestamp")
        }
        self.timestamp = proto.timestamp

        guard proto.hasSourceDevice else {
            throw EnvelopeError.invalidProtobuf(description: "missing required field: sourceDevice")
        }
        self.sourceDevice = proto.sourceDevice

        if proto.hasContent {
            self.content = proto.content
        } else {
            self.content = nil
        }

        if proto.hasLegacyMessage {
            self.legacyMessage = proto.legacyMessage
        } else {
            self.legacyMessage = nil
        }

        if proto.relay.count > 0 {
            self.relay = proto.relay
        } else {
            relay = nil
        }
    }

    @objc
    public func serializedData() throws -> Data {
        return try self.asProtobuf.serializedData()
    }

    private var asProtobuf: SignalServiceProtos_Envelope {
        let proto = SignalServiceProtos_Envelope.with { (builder) in
            builder.source = self.source

            builder.type = {
                switch self.type {
                case .unknown:
                    return .unknown
                case .ciphertext:
                    return .ciphertext
                case .keyExchange:
                    return .keyExchange
                case .prekeyBundle:
                    return .prekeyBundle
                case .receipt:
                    return .receipt
                }
            }()

            builder.timestamp = self.timestamp
            builder.sourceDevice = self.sourceDevice

            if let relay = self.relay {
                builder.relay = relay
            }

            if let content = self.content {
                builder.content = content
            }
        }

        return proto
    }
}
