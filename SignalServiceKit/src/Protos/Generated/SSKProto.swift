//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

import Foundation

// WARNING: This code is generated. Only edit within the markers.

public enum SSKProtoError: Error {
    case invalidProtobuf(description: String)
}

// MARK: - SSKProtoEnvelope

@objc public class SSKProtoEnvelope: NSObject {

    // MARK: - SSKProtoEnvelopeType

    @objc public enum SSKProtoEnvelopeType: Int32 {
        case unknown = 0
        case ciphertext = 1
        case keyExchange = 2
        case prekeyBundle = 3
        case receipt = 5
    }

    private class func SSKProtoEnvelopeTypeWrap(_ value: SignalServiceProtos_Envelope.TypeEnum) -> SSKProtoEnvelopeType {
        switch value {
        case .unknown: return .unknown
        case .ciphertext: return .ciphertext
        case .keyExchange: return .keyExchange
        case .prekeyBundle: return .prekeyBundle
        case .receipt: return .receipt
        }
    }

    private class func SSKProtoEnvelopeTypeUnwrap(_ value: SSKProtoEnvelopeType) -> SignalServiceProtos_Envelope.TypeEnum {
        switch value {
        case .unknown: return .unknown
        case .ciphertext: return .ciphertext
        case .keyExchange: return .keyExchange
        case .prekeyBundle: return .prekeyBundle
        case .receipt: return .receipt
        }
    }

    // MARK: - SSKProtoEnvelopeBuilder

    @objc public class SSKProtoEnvelopeBuilder: NSObject {

        private var type: SSKProtoEnvelopeType?
        private var source: String?
        private var sourceDevice: UInt32?
        private var relay: String?
        private var timestamp: UInt64?
        private var legacyMessage: Data?
        private var content: Data?

        @objc public override init() {}

        @objc public func setType(_ value: SSKProtoEnvelopeType) {
            type = value
        }

        @objc public func setSource(_ value: String) {
            source = value
        }

        @objc public func setSourceDevice(_ value: UInt32) {
            sourceDevice = value
        }

        @objc public func setRelay(_ value: String) {
            relay = value
        }

        @objc public func setTimestamp(_ value: UInt64) {
            timestamp = value
        }

        @objc public func setLegacyMessage(_ value: Data) {
            legacyMessage = value
        }

        @objc public func setContent(_ value: Data) {
            content = value
        }

        @objc public func build() throws -> SSKProtoEnvelope {
            let proto = SignalServiceProtos_Envelope.with { (builder) in
                if let type = self.type {
                    builder.type = SSKProtoEnvelopeTypeUnwrap(type)
                }
                if let source = self.source {
                    builder.source = source
                }
                if let sourceDevice = self.sourceDevice {
                    builder.sourceDevice = sourceDevice
                }
                if let relay = self.relay {
                    builder.relay = relay
                }
                if let timestamp = self.timestamp {
                    builder.timestamp = timestamp
                }
                if let legacyMessage = self.legacyMessage {
                    builder.legacyMessage = legacyMessage
                }
                if let content = self.content {
                    builder.content = content
                }
            }

            let wrapper = try SSKProtoEnvelope.parseProto(proto)
            return wrapper
        }
    }

    @objc public let type: SSKProtoEnvelopeType
    @objc public let source: String?
    @objc public let sourceDevice: UInt32
    @objc public let relay: String?
    @objc public let timestamp: UInt64
    @objc public let legacyMessage: Data?
    @objc public let content: Data?

    @objc public init(type: SSKProtoEnvelopeType,
                      source: String?,
                      sourceDevice: UInt32,
                      relay: String?,
                      timestamp: UInt64,
                      legacyMessage: Data?,
                      content: Data?) {
        self.type = type
        self.source = source
        self.sourceDevice = sourceDevice
        self.relay = relay
        self.timestamp = timestamp
        self.legacyMessage = legacyMessage
        self.content = content
    }

    @objc
    public func serializedData() throws -> Data {
        return try self.asProtobuf.serializedData()
    }

    @objc public class func parseData(_ serializedData: Data) throws -> SSKProtoEnvelope {
        let proto = try SignalServiceProtos_Envelope(serializedData: serializedData)
        return try parseProto(proto)
    }

    fileprivate class func parseProto(_ proto: SignalServiceProtos_Envelope) throws -> SSKProtoEnvelope {
        guard proto.hasType else {
            throw SSKProtoError.invalidProtobuf(description: "\(logTag) missing required field: type")
        }
        let type = SSKProtoEnvelopeTypeWrap(proto.type)

        guard proto.hasSource else {
            throw SSKProtoError.invalidProtobuf(description: "\(logTag) missing required field: source")
        }
        let source = proto.source

        guard proto.hasSourceDevice else {
            throw SSKProtoError.invalidProtobuf(description: "\(logTag) missing required field: sourceDevice")
        }
        let sourceDevice = proto.sourceDevice

        var relay: String? = nil
        if proto.hasRelay {
            relay = proto.relay
        }

        guard proto.hasTimestamp else {
            throw SSKProtoError.invalidProtobuf(description: "\(logTag) missing required field: timestamp")
        }
        let timestamp = proto.timestamp

        var legacyMessage: Data? = nil
        if proto.hasLegacyMessage {
            legacyMessage = proto.legacyMessage
        }

        var content: Data? = nil
        if proto.hasContent {
            content = proto.content
        }

        // MARK: - Begin Validation Logic for SSKProtoEnvelope -

        guard proto.hasSource else {
            throw SSKProtoError.invalidProtobuf(description: "\(logTag) missing required field: source")
        }
        guard proto.hasType else {
            throw SSKProtoError.invalidProtobuf(description: "\(logTag) missing required field: type")
        }
        guard proto.hasTimestamp else {
            throw SSKProtoError.invalidProtobuf(description: "\(logTag) missing required field: timestamp")
        }
        guard proto.hasSourceDevice else {
            throw SSKProtoError.invalidProtobuf(description: "\(logTag) missing required field: sourceDevice")
        }

        // MARK: - End Validation Logic for SSKProtoEnvelope -

        let result = SSKProtoEnvelope(type: type,
                                      source: source,
                                      sourceDevice: sourceDevice,
                                      relay: relay,
                                      timestamp: timestamp,
                                      legacyMessage: legacyMessage,
                                      content: content)
        return result
    }

    fileprivate var asProtobuf: SignalServiceProtos_Envelope {
        let proto = SignalServiceProtos_Envelope.with { (builder) in
            builder.type = SSKProtoEnvelope.SSKProtoEnvelopeTypeUnwrap(self.type)

            if let source = self.source {
                builder.source = source
            }

            builder.sourceDevice = self.sourceDevice

            if let relay = self.relay {
                builder.relay = relay
            }

            builder.timestamp = self.timestamp

            if let legacyMessage = self.legacyMessage {
                builder.legacyMessage = legacyMessage
            }

            if let content = self.content {
                builder.content = content
            }
        }

        return proto
    }
}

// MARK: - SSKProtoContent

@objc public class SSKProtoContent: NSObject {

    // MARK: - SSKProtoContentBuilder

    @objc public class SSKProtoContentBuilder: NSObject {

        private var dataMessage: SSKProtoDataMessage?
        private var syncMessage: SSKProtoSyncMessage?
        private var callMessage: SSKProtoCallMessage?
        private var nullMessage: SSKProtoNullMessage?
        private var receiptMessage: SSKProtoReceiptMessage?

        @objc public override init() {}

        @objc public func setDataMessage(_ value: SSKProtoDataMessage) {
            dataMessage = value
        }

        @objc public func setSyncMessage(_ value: SSKProtoSyncMessage) {
            syncMessage = value
        }

        @objc public func setCallMessage(_ value: SSKProtoCallMessage) {
            callMessage = value
        }

        @objc public func setNullMessage(_ value: SSKProtoNullMessage) {
            nullMessage = value
        }

        @objc public func setReceiptMessage(_ value: SSKProtoReceiptMessage) {
            receiptMessage = value
        }

        @objc public func build() throws -> SSKProtoContent {
            let proto = SignalServiceProtos_Content.with { (builder) in
                if let dataMessage = self.dataMessage {
                    builder.dataMessage = dataMessage.asProtobuf
                }
                if let syncMessage = self.syncMessage {
                    builder.syncMessage = syncMessage.asProtobuf
                }
                if let callMessage = self.callMessage {
                    builder.callMessage = callMessage.asProtobuf
                }
                if let nullMessage = self.nullMessage {
                    builder.nullMessage = nullMessage.asProtobuf
                }
                if let receiptMessage = self.receiptMessage {
                    builder.receiptMessage = receiptMessage.asProtobuf
                }
            }

            let wrapper = try SSKProtoContent.parseProto(proto)
            return wrapper
        }
    }

    @objc public let dataMessage: SSKProtoDataMessage?
    @objc public let syncMessage: SSKProtoSyncMessage?
    @objc public let callMessage: SSKProtoCallMessage?
    @objc public let nullMessage: SSKProtoNullMessage?
    @objc public let receiptMessage: SSKProtoReceiptMessage?

    @objc public init(dataMessage: SSKProtoDataMessage?,
                      syncMessage: SSKProtoSyncMessage?,
                      callMessage: SSKProtoCallMessage?,
                      nullMessage: SSKProtoNullMessage?,
                      receiptMessage: SSKProtoReceiptMessage?) {
        self.dataMessage = dataMessage
        self.syncMessage = syncMessage
        self.callMessage = callMessage
        self.nullMessage = nullMessage
        self.receiptMessage = receiptMessage
    }

    @objc
    public func serializedData() throws -> Data {
        return try self.asProtobuf.serializedData()
    }

    @objc public class func parseData(_ serializedData: Data) throws -> SSKProtoContent {
        let proto = try SignalServiceProtos_Content(serializedData: serializedData)
        return try parseProto(proto)
    }

    fileprivate class func parseProto(_ proto: SignalServiceProtos_Content) throws -> SSKProtoContent {
        var dataMessage: SSKProtoDataMessage? = nil
        if proto.hasDataMessage {
            dataMessage = try SSKProtoDataMessage.parseProto(proto.dataMessage)
        }

        var syncMessage: SSKProtoSyncMessage? = nil
        if proto.hasSyncMessage {
            syncMessage = try SSKProtoSyncMessage.parseProto(proto.syncMessage)
        }

        var callMessage: SSKProtoCallMessage? = nil
        if proto.hasCallMessage {
            callMessage = try SSKProtoCallMessage.parseProto(proto.callMessage)
        }

        var nullMessage: SSKProtoNullMessage? = nil
        if proto.hasNullMessage {
            nullMessage = try SSKProtoNullMessage.parseProto(proto.nullMessage)
        }

        var receiptMessage: SSKProtoReceiptMessage? = nil
        if proto.hasReceiptMessage {
            receiptMessage = try SSKProtoReceiptMessage.parseProto(proto.receiptMessage)
        }

        // MARK: - Begin Validation Logic for SSKProtoContent -

        // MARK: - End Validation Logic for SSKProtoContent -

        let result = SSKProtoContent(dataMessage: dataMessage,
                                     syncMessage: syncMessage,
                                     callMessage: callMessage,
                                     nullMessage: nullMessage,
                                     receiptMessage: receiptMessage)
        return result
    }

    fileprivate var asProtobuf: SignalServiceProtos_Content {
        let proto = SignalServiceProtos_Content.with { (builder) in
            if let dataMessage = self.dataMessage {
                builder.dataMessage = dataMessage.asProtobuf
            }

            if let syncMessage = self.syncMessage {
                builder.syncMessage = syncMessage.asProtobuf
            }

            if let callMessage = self.callMessage {
                builder.callMessage = callMessage.asProtobuf
            }

            if let nullMessage = self.nullMessage {
                builder.nullMessage = nullMessage.asProtobuf
            }

            if let receiptMessage = self.receiptMessage {
                builder.receiptMessage = receiptMessage.asProtobuf
            }
        }

        return proto
    }
}

// MARK: - SSKProtoCallMessageOffer

@objc public class SSKProtoCallMessageOffer: NSObject {

    // MARK: - SSKProtoCallMessageOfferBuilder

    @objc public class SSKProtoCallMessageOfferBuilder: NSObject {

        private var id: UInt64?
        private var sessionDescription: String?

        @objc public override init() {}

        @objc public func setId(_ value: UInt64) {
            id = value
        }

        @objc public func setSessionDescription(_ value: String) {
            sessionDescription = value
        }

        @objc public func build() throws -> SSKProtoCallMessageOffer {
            let proto = SignalServiceProtos_CallMessage.Offer.with { (builder) in
                if let id = self.id {
                    builder.id = id
                }
                if let sessionDescription = self.sessionDescription {
                    builder.sessionDescription = sessionDescription
                }
            }

            let wrapper = try SSKProtoCallMessageOffer.parseProto(proto)
            return wrapper
        }
    }

    @objc public let id: UInt64
    @objc public let sessionDescription: String?

    @objc public init(id: UInt64,
                      sessionDescription: String?) {
        self.id = id
        self.sessionDescription = sessionDescription
    }

    @objc
    public func serializedData() throws -> Data {
        return try self.asProtobuf.serializedData()
    }

    @objc public class func parseData(_ serializedData: Data) throws -> SSKProtoCallMessageOffer {
        let proto = try SignalServiceProtos_CallMessage.Offer(serializedData: serializedData)
        return try parseProto(proto)
    }

    fileprivate class func parseProto(_ proto: SignalServiceProtos_CallMessage.Offer) throws -> SSKProtoCallMessageOffer {
        guard proto.hasID else {
            throw SSKProtoError.invalidProtobuf(description: "\(logTag) missing required field: id")
        }
        let id = proto.id

        var sessionDescription: String? = nil
        if proto.hasSessionDescription {
            sessionDescription = proto.sessionDescription
        }

        // MARK: - Begin Validation Logic for SSKProtoCallMessageOffer -

        // MARK: - End Validation Logic for SSKProtoCallMessageOffer -

        let result = SSKProtoCallMessageOffer(id: id,
                                              sessionDescription: sessionDescription)
        return result
    }

    fileprivate var asProtobuf: SignalServiceProtos_CallMessage.Offer {
        let proto = SignalServiceProtos_CallMessage.Offer.with { (builder) in
            builder.id = self.id

            if let sessionDescription = self.sessionDescription {
                builder.sessionDescription = sessionDescription
            }
        }

        return proto
    }
}

// MARK: - SSKProtoCallMessageAnswer

@objc public class SSKProtoCallMessageAnswer: NSObject {

    // MARK: - SSKProtoCallMessageAnswerBuilder

    @objc public class SSKProtoCallMessageAnswerBuilder: NSObject {

        private var id: UInt64?
        private var sessionDescription: String?

        @objc public override init() {}

        @objc public func setId(_ value: UInt64) {
            id = value
        }

        @objc public func setSessionDescription(_ value: String) {
            sessionDescription = value
        }

        @objc public func build() throws -> SSKProtoCallMessageAnswer {
            let proto = SignalServiceProtos_CallMessage.Answer.with { (builder) in
                if let id = self.id {
                    builder.id = id
                }
                if let sessionDescription = self.sessionDescription {
                    builder.sessionDescription = sessionDescription
                }
            }

            let wrapper = try SSKProtoCallMessageAnswer.parseProto(proto)
            return wrapper
        }
    }

    @objc public let id: UInt64
    @objc public let sessionDescription: String?

    @objc public init(id: UInt64,
                      sessionDescription: String?) {
        self.id = id
        self.sessionDescription = sessionDescription
    }

    @objc
    public func serializedData() throws -> Data {
        return try self.asProtobuf.serializedData()
    }

    @objc public class func parseData(_ serializedData: Data) throws -> SSKProtoCallMessageAnswer {
        let proto = try SignalServiceProtos_CallMessage.Answer(serializedData: serializedData)
        return try parseProto(proto)
    }

    fileprivate class func parseProto(_ proto: SignalServiceProtos_CallMessage.Answer) throws -> SSKProtoCallMessageAnswer {
        guard proto.hasID else {
            throw SSKProtoError.invalidProtobuf(description: "\(logTag) missing required field: id")
        }
        let id = proto.id

        var sessionDescription: String? = nil
        if proto.hasSessionDescription {
            sessionDescription = proto.sessionDescription
        }

        // MARK: - Begin Validation Logic for SSKProtoCallMessageAnswer -

        // MARK: - End Validation Logic for SSKProtoCallMessageAnswer -

        let result = SSKProtoCallMessageAnswer(id: id,
                                               sessionDescription: sessionDescription)
        return result
    }

    fileprivate var asProtobuf: SignalServiceProtos_CallMessage.Answer {
        let proto = SignalServiceProtos_CallMessage.Answer.with { (builder) in
            builder.id = self.id

            if let sessionDescription = self.sessionDescription {
                builder.sessionDescription = sessionDescription
            }
        }

        return proto
    }
}

// MARK: - SSKProtoCallMessageIceUpdate

@objc public class SSKProtoCallMessageIceUpdate: NSObject {

    // MARK: - SSKProtoCallMessageIceUpdateBuilder

    @objc public class SSKProtoCallMessageIceUpdateBuilder: NSObject {

        private var id: UInt64?
        private var sdpMid: String?
        private var sdpMlineIndex: UInt32?
        private var sdp: String?

        @objc public override init() {}

        @objc public func setId(_ value: UInt64) {
            id = value
        }

        @objc public func setSdpMid(_ value: String) {
            sdpMid = value
        }

        @objc public func setSdpMlineIndex(_ value: UInt32) {
            sdpMlineIndex = value
        }

        @objc public func setSdp(_ value: String) {
            sdp = value
        }

        @objc public func build() throws -> SSKProtoCallMessageIceUpdate {
            let proto = SignalServiceProtos_CallMessage.IceUpdate.with { (builder) in
                if let id = self.id {
                    builder.id = id
                }
                if let sdpMid = self.sdpMid {
                    builder.sdpMid = sdpMid
                }
                if let sdpMlineIndex = self.sdpMlineIndex {
                    builder.sdpMlineIndex = sdpMlineIndex
                }
                if let sdp = self.sdp {
                    builder.sdp = sdp
                }
            }

            let wrapper = try SSKProtoCallMessageIceUpdate.parseProto(proto)
            return wrapper
        }
    }

    @objc public let id: UInt64
    @objc public let sdpMid: String?
    @objc public let sdpMlineIndex: UInt32?
    @objc public let sdp: String?

    @objc public init(id: UInt64,
                      sdpMid: String?,
                      sdpMlineIndex: UInt32?,
                      sdp: String?) {
        self.id = id
        self.sdpMid = sdpMid
        self.sdpMlineIndex = sdpMlineIndex
        self.sdp = sdp
    }

    @objc
    public func serializedData() throws -> Data {
        return try self.asProtobuf.serializedData()
    }

    @objc public class func parseData(_ serializedData: Data) throws -> SSKProtoCallMessageIceUpdate {
        let proto = try SignalServiceProtos_CallMessage.IceUpdate(serializedData: serializedData)
        return try parseProto(proto)
    }

    fileprivate class func parseProto(_ proto: SignalServiceProtos_CallMessage.IceUpdate) throws -> SSKProtoCallMessageIceUpdate {
        guard proto.hasID else {
            throw SSKProtoError.invalidProtobuf(description: "\(logTag) missing required field: id")
        }
        let id = proto.id

        var sdpMid: String? = nil
        if proto.hasSdpMid {
            sdpMid = proto.sdpMid
        }

        var sdpMlineIndex: UInt32? = nil
        if proto.hasSdpMlineIndex {
            sdpMlineIndex = proto.sdpMlineIndex
        }

        var sdp: String? = nil
        if proto.hasSdp {
            sdp = proto.sdp
        }

        // MARK: - Begin Validation Logic for SSKProtoCallMessageIceUpdate -

        // MARK: - End Validation Logic for SSKProtoCallMessageIceUpdate -

        let result = SSKProtoCallMessageIceUpdate(id: id,
                                                  sdpMid: sdpMid,
                                                  sdpMlineIndex: sdpMlineIndex,
                                                  sdp: sdp)
        return result
    }

    fileprivate var asProtobuf: SignalServiceProtos_CallMessage.IceUpdate {
        let proto = SignalServiceProtos_CallMessage.IceUpdate.with { (builder) in
            builder.id = self.id

            if let sdpMid = self.sdpMid {
                builder.sdpMid = sdpMid
            }

            if let sdpMlineIndex = self.sdpMlineIndex {
                builder.sdpMlineIndex = sdpMlineIndex
            }

            if let sdp = self.sdp {
                builder.sdp = sdp
            }
        }

        return proto
    }
}

// MARK: - SSKProtoCallMessageBusy

@objc public class SSKProtoCallMessageBusy: NSObject {

    // MARK: - SSKProtoCallMessageBusyBuilder

    @objc public class SSKProtoCallMessageBusyBuilder: NSObject {

        private var id: UInt64?

        @objc public override init() {}

        @objc public func setId(_ value: UInt64) {
            id = value
        }

        @objc public func build() throws -> SSKProtoCallMessageBusy {
            let proto = SignalServiceProtos_CallMessage.Busy.with { (builder) in
                if let id = self.id {
                    builder.id = id
                }
            }

            let wrapper = try SSKProtoCallMessageBusy.parseProto(proto)
            return wrapper
        }
    }

    @objc public let id: UInt64

    @objc public init(id: UInt64) {
        self.id = id
    }

    @objc
    public func serializedData() throws -> Data {
        return try self.asProtobuf.serializedData()
    }

    @objc public class func parseData(_ serializedData: Data) throws -> SSKProtoCallMessageBusy {
        let proto = try SignalServiceProtos_CallMessage.Busy(serializedData: serializedData)
        return try parseProto(proto)
    }

    fileprivate class func parseProto(_ proto: SignalServiceProtos_CallMessage.Busy) throws -> SSKProtoCallMessageBusy {
        guard proto.hasID else {
            throw SSKProtoError.invalidProtobuf(description: "\(logTag) missing required field: id")
        }
        let id = proto.id

        // MARK: - Begin Validation Logic for SSKProtoCallMessageBusy -

        // MARK: - End Validation Logic for SSKProtoCallMessageBusy -

        let result = SSKProtoCallMessageBusy(id: id)
        return result
    }

    fileprivate var asProtobuf: SignalServiceProtos_CallMessage.Busy {
        let proto = SignalServiceProtos_CallMessage.Busy.with { (builder) in
            builder.id = self.id
        }

        return proto
    }
}

// MARK: - SSKProtoCallMessageHangup

@objc public class SSKProtoCallMessageHangup: NSObject {

    // MARK: - SSKProtoCallMessageHangupBuilder

    @objc public class SSKProtoCallMessageHangupBuilder: NSObject {

        private var id: UInt64?

        @objc public override init() {}

        @objc public func setId(_ value: UInt64) {
            id = value
        }

        @objc public func build() throws -> SSKProtoCallMessageHangup {
            let proto = SignalServiceProtos_CallMessage.Hangup.with { (builder) in
                if let id = self.id {
                    builder.id = id
                }
            }

            let wrapper = try SSKProtoCallMessageHangup.parseProto(proto)
            return wrapper
        }
    }

    @objc public let id: UInt64

    @objc public init(id: UInt64) {
        self.id = id
    }

    @objc
    public func serializedData() throws -> Data {
        return try self.asProtobuf.serializedData()
    }

    @objc public class func parseData(_ serializedData: Data) throws -> SSKProtoCallMessageHangup {
        let proto = try SignalServiceProtos_CallMessage.Hangup(serializedData: serializedData)
        return try parseProto(proto)
    }

    fileprivate class func parseProto(_ proto: SignalServiceProtos_CallMessage.Hangup) throws -> SSKProtoCallMessageHangup {
        guard proto.hasID else {
            throw SSKProtoError.invalidProtobuf(description: "\(logTag) missing required field: id")
        }
        let id = proto.id

        // MARK: - Begin Validation Logic for SSKProtoCallMessageHangup -

        // MARK: - End Validation Logic for SSKProtoCallMessageHangup -

        let result = SSKProtoCallMessageHangup(id: id)
        return result
    }

    fileprivate var asProtobuf: SignalServiceProtos_CallMessage.Hangup {
        let proto = SignalServiceProtos_CallMessage.Hangup.with { (builder) in
            builder.id = self.id
        }

        return proto
    }
}

// MARK: - SSKProtoCallMessage

@objc public class SSKProtoCallMessage: NSObject {

    // MARK: - SSKProtoCallMessageBuilder

    @objc public class SSKProtoCallMessageBuilder: NSObject {

        private var offer: SSKProtoCallMessageOffer?
        private var answer: SSKProtoCallMessageAnswer?
        private var iceUpdate: [SSKProtoCallMessageIceUpdate]
        private var hangup: SSKProtoCallMessageHangup?
        private var busy: SSKProtoCallMessageBusy?
        private var profileKey: Data?

        @objc public override init() {}

        @objc public func setOffer(_ value: SSKProtoCallMessageOffer) {
            offer = value
        }

        @objc public func setAnswer(_ value: SSKProtoCallMessageAnswer) {
            answer = value
        }

        @objc public func addIceUpdate(_ value: SSKProtoCallMessageIceUpdate) {
            iceUpdate.append(value)
        }

        @objc public func setHangup(_ value: SSKProtoCallMessageHangup) {
            hangup = value
        }

        @objc public func setBusy(_ value: SSKProtoCallMessageBusy) {
            busy = value
        }

        @objc public func setProfileKey(_ value: Data) {
            profileKey = value
        }

        @objc public func build() throws -> SSKProtoCallMessage {
            let proto = SignalServiceProtos_CallMessage.with { (builder) in
                if let offer = self.offer {
                    builder.offer = offer.asProtobuf
                }
                if let answer = self.answer {
                    builder.answer = answer.asProtobuf
                }
                for item in iceUpdate {
                    builder.addIceUpdate(item.asProtobuf)
                }
                if let hangup = self.hangup {
                    builder.hangup = hangup.asProtobuf
                }
                if let busy = self.busy {
                    builder.busy = busy.asProtobuf
                }
                if let profileKey = self.profileKey {
                    builder.profileKey = profileKey
                }
            }

            let wrapper = try SSKProtoCallMessage.parseProto(proto)
            return wrapper
        }
    }

    @objc public let offer: SSKProtoCallMessageOffer?
    @objc public let answer: SSKProtoCallMessageAnswer?
    @objc public let iceUpdate: [SSKProtoCallMessageIceUpdate]
    @objc public let hangup: SSKProtoCallMessageHangup?
    @objc public let busy: SSKProtoCallMessageBusy?
    @objc public let profileKey: Data?

    @objc public init(offer: SSKProtoCallMessageOffer?,
                      answer: SSKProtoCallMessageAnswer?,
                      iceUpdate: [SSKProtoCallMessageIceUpdate],
                      hangup: SSKProtoCallMessageHangup?,
                      busy: SSKProtoCallMessageBusy?,
                      profileKey: Data?) {
        self.offer = offer
        self.answer = answer
        self.iceUpdate = iceUpdate
        self.hangup = hangup
        self.busy = busy
        self.profileKey = profileKey
    }

    @objc
    public func serializedData() throws -> Data {
        return try self.asProtobuf.serializedData()
    }

    @objc public class func parseData(_ serializedData: Data) throws -> SSKProtoCallMessage {
        let proto = try SignalServiceProtos_CallMessage(serializedData: serializedData)
        return try parseProto(proto)
    }

    fileprivate class func parseProto(_ proto: SignalServiceProtos_CallMessage) throws -> SSKProtoCallMessage {
        var offer: SSKProtoCallMessageOffer? = nil
        if proto.hasOffer {
            offer = try SSKProtoCallMessageOffer.parseProto(proto.offer)
        }

        var answer: SSKProtoCallMessageAnswer? = nil
        if proto.hasAnswer {
            answer = try SSKProtoCallMessageAnswer.parseProto(proto.answer)
        }

        var iceUpdate: [SSKProtoCallMessageIceUpdate] = []
        for item in proto.iceUpdate {
            let wrapped = try SSKProtoCallMessageIceUpdate.parseProto(item)
            iceUpdate.append(wrapped)
        }

        var hangup: SSKProtoCallMessageHangup? = nil
        if proto.hasHangup {
            hangup = try SSKProtoCallMessageHangup.parseProto(proto.hangup)
        }

        var busy: SSKProtoCallMessageBusy? = nil
        if proto.hasBusy {
            busy = try SSKProtoCallMessageBusy.parseProto(proto.busy)
        }

        var profileKey: Data? = nil
        if proto.hasProfileKey {
            profileKey = proto.profileKey
        }

        // MARK: - Begin Validation Logic for SSKProtoCallMessage -

        // MARK: - End Validation Logic for SSKProtoCallMessage -

        let result = SSKProtoCallMessage(offer: offer,
                                         answer: answer,
                                         iceUpdate: iceUpdate,
                                         hangup: hangup,
                                         busy: busy,
                                         profileKey: profileKey)
        return result
    }

    fileprivate var asProtobuf: SignalServiceProtos_CallMessage {
        let proto = SignalServiceProtos_CallMessage.with { (builder) in
            if let offer = self.offer {
                builder.offer = offer.asProtobuf
            }

            if let answer = self.answer {
                builder.answer = answer.asProtobuf
            }

            var iceUpdateUnwrapped = [SignalServiceProtos_CallMessage.IceUpdate]()
            for item in iceUpdate {
                iceUpdateUnwrapped.append(item.asProtobuf)
            }
            builder.iceUpdate = iceUpdateUnwrapped

            if let hangup = self.hangup {
                builder.hangup = hangup.asProtobuf
            }

            if let busy = self.busy {
                builder.busy = busy.asProtobuf
            }

            if let profileKey = self.profileKey {
                builder.profileKey = profileKey
            }
        }

        return proto
    }
}

// MARK: - SSKProtoDataMessageQuoteQuotedAttachment

@objc public class SSKProtoDataMessageQuoteQuotedAttachment: NSObject {

    // MARK: - SSKProtoDataMessageQuoteQuotedAttachmentFlags

    @objc public enum SSKProtoDataMessageQuoteQuotedAttachmentFlags: Int32 {
        case voiceMessage = 1
    }

    private class func SSKProtoDataMessageQuoteQuotedAttachmentFlagsWrap(_ value: SignalServiceProtos_DataMessage.Quote.QuotedAttachment.Flags) -> SSKProtoDataMessageQuoteQuotedAttachmentFlags {
        switch value {
        case .voiceMessage: return .voiceMessage
        }
    }

    private class func SSKProtoDataMessageQuoteQuotedAttachmentFlagsUnwrap(_ value: SSKProtoDataMessageQuoteQuotedAttachmentFlags) -> SignalServiceProtos_DataMessage.Quote.QuotedAttachment.Flags {
        switch value {
        case .voiceMessage: return .voiceMessage
        }
    }

    // MARK: - SSKProtoDataMessageQuoteQuotedAttachmentBuilder

    @objc public class SSKProtoDataMessageQuoteQuotedAttachmentBuilder: NSObject {

        private var contentType: String?
        private var fileName: String?
        private var thumbnail: SSKProtoAttachmentPointer?
        private var flags: UInt32?

        @objc public override init() {}

        @objc public func setContentType(_ value: String) {
            contentType = value
        }

        @objc public func setFileName(_ value: String) {
            fileName = value
        }

        @objc public func setThumbnail(_ value: SSKProtoAttachmentPointer) {
            thumbnail = value
        }

        @objc public func setFlags(_ value: UInt32) {
            flags = value
        }

        @objc public func build() throws -> SSKProtoDataMessageQuoteQuotedAttachment {
            let proto = SignalServiceProtos_DataMessage.Quote.QuotedAttachment.with { (builder) in
                if let contentType = self.contentType {
                    builder.contentType = contentType
                }
                if let fileName = self.fileName {
                    builder.fileName = fileName
                }
                if let thumbnail = self.thumbnail {
                    builder.thumbnail = thumbnail.asProtobuf
                }
                if let flags = self.flags {
                    builder.flags = flags
                }
            }

            let wrapper = try SSKProtoDataMessageQuoteQuotedAttachment.parseProto(proto)
            return wrapper
        }
    }

    @objc public let contentType: String?
    @objc public let fileName: String?
    @objc public let thumbnail: SSKProtoAttachmentPointer?
    @objc public let flags: UInt32?

    @objc public init(contentType: String?,
                      fileName: String?,
                      thumbnail: SSKProtoAttachmentPointer?,
                      flags: UInt32?) {
        self.contentType = contentType
        self.fileName = fileName
        self.thumbnail = thumbnail
        self.flags = flags
    }

    @objc
    public func serializedData() throws -> Data {
        return try self.asProtobuf.serializedData()
    }

    @objc public class func parseData(_ serializedData: Data) throws -> SSKProtoDataMessageQuoteQuotedAttachment {
        let proto = try SignalServiceProtos_DataMessage.Quote.QuotedAttachment(serializedData: serializedData)
        return try parseProto(proto)
    }

    fileprivate class func parseProto(_ proto: SignalServiceProtos_DataMessage.Quote.QuotedAttachment) throws -> SSKProtoDataMessageQuoteQuotedAttachment {
        var contentType: String? = nil
        if proto.hasContentType {
            contentType = proto.contentType
        }

        var fileName: String? = nil
        if proto.hasFileName {
            fileName = proto.fileName
        }

        var thumbnail: SSKProtoAttachmentPointer? = nil
        if proto.hasThumbnail {
            thumbnail = try SSKProtoAttachmentPointer.parseProto(proto.thumbnail)
        }

        var flags: UInt32? = nil
        if proto.hasFlags {
            flags = proto.flags
        }

        // MARK: - Begin Validation Logic for SSKProtoDataMessageQuoteQuotedAttachment -

        // MARK: - End Validation Logic for SSKProtoDataMessageQuoteQuotedAttachment -

        let result = SSKProtoDataMessageQuoteQuotedAttachment(contentType: contentType,
                                                              fileName: fileName,
                                                              thumbnail: thumbnail,
                                                              flags: flags)
        return result
    }

    fileprivate var asProtobuf: SignalServiceProtos_DataMessage.Quote.QuotedAttachment {
        let proto = SignalServiceProtos_DataMessage.Quote.QuotedAttachment.with { (builder) in
            if let contentType = self.contentType {
                builder.contentType = contentType
            }

            if let fileName = self.fileName {
                builder.fileName = fileName
            }

            if let thumbnail = self.thumbnail {
                builder.thumbnail = thumbnail.asProtobuf
            }

            if let flags = self.flags {
                builder.flags = flags
            }
        }

        return proto
    }
}

// MARK: - SSKProtoDataMessageQuote

@objc public class SSKProtoDataMessageQuote: NSObject {

    // MARK: - SSKProtoDataMessageQuoteBuilder

    @objc public class SSKProtoDataMessageQuoteBuilder: NSObject {

        private var id: UInt64?
        private var author: String?
        private var text: String?
        private var attachments: [SSKProtoDataMessageQuoteQuotedAttachment]

        @objc public override init() {}

        @objc public func setId(_ value: UInt64) {
            id = value
        }

        @objc public func setAuthor(_ value: String) {
            author = value
        }

        @objc public func setText(_ value: String) {
            text = value
        }

        @objc public func addAttachments(_ value: SSKProtoDataMessageQuoteQuotedAttachment) {
            attachments.append(value)
        }

        @objc public func build() throws -> SSKProtoDataMessageQuote {
            let proto = SignalServiceProtos_DataMessage.Quote.with { (builder) in
                if let id = self.id {
                    builder.id = id
                }
                if let author = self.author {
                    builder.author = author
                }
                if let text = self.text {
                    builder.text = text
                }
                for item in attachments {
                    builder.addAttachments(item.asProtobuf)
                }
            }

            let wrapper = try SSKProtoDataMessageQuote.parseProto(proto)
            return wrapper
        }
    }

    @objc public let id: UInt64
    @objc public let author: String?
    @objc public let text: String?
    @objc public let attachments: [SSKProtoDataMessageQuoteQuotedAttachment]

    @objc public init(id: UInt64,
                      author: String?,
                      text: String?,
                      attachments: [SSKProtoDataMessageQuoteQuotedAttachment]) {
        self.id = id
        self.author = author
        self.text = text
        self.attachments = attachments
    }

    @objc
    public func serializedData() throws -> Data {
        return try self.asProtobuf.serializedData()
    }

    @objc public class func parseData(_ serializedData: Data) throws -> SSKProtoDataMessageQuote {
        let proto = try SignalServiceProtos_DataMessage.Quote(serializedData: serializedData)
        return try parseProto(proto)
    }

    fileprivate class func parseProto(_ proto: SignalServiceProtos_DataMessage.Quote) throws -> SSKProtoDataMessageQuote {
        guard proto.hasID else {
            throw SSKProtoError.invalidProtobuf(description: "\(logTag) missing required field: id")
        }
        let id = proto.id

        guard proto.hasAuthor else {
            throw SSKProtoError.invalidProtobuf(description: "\(logTag) missing required field: author")
        }
        let author = proto.author

        var text: String? = nil
        if proto.hasText {
            text = proto.text
        }

        var attachments: [SSKProtoDataMessageQuoteQuotedAttachment] = []
        for item in proto.attachments {
            let wrapped = try SSKProtoDataMessageQuoteQuotedAttachment.parseProto(item)
            attachments.append(wrapped)
        }

        // MARK: - Begin Validation Logic for SSKProtoDataMessageQuote -

        // MARK: - End Validation Logic for SSKProtoDataMessageQuote -

        let result = SSKProtoDataMessageQuote(id: id,
                                              author: author,
                                              text: text,
                                              attachments: attachments)
        return result
    }

    fileprivate var asProtobuf: SignalServiceProtos_DataMessage.Quote {
        let proto = SignalServiceProtos_DataMessage.Quote.with { (builder) in
            builder.id = self.id

            if let author = self.author {
                builder.author = author
            }

            if let text = self.text {
                builder.text = text
            }

            var attachmentsUnwrapped = [SignalServiceProtos_DataMessage.Quote.QuotedAttachment]()
            for item in attachments {
                attachmentsUnwrapped.append(item.asProtobuf)
            }
            builder.attachments = attachmentsUnwrapped
        }

        return proto
    }
}

// MARK: - SSKProtoDataMessageContactName

@objc public class SSKProtoDataMessageContactName: NSObject {

    // MARK: - SSKProtoDataMessageContactNameBuilder

    @objc public class SSKProtoDataMessageContactNameBuilder: NSObject {

        private var givenName: String?
        private var familyName: String?
        private var prefix: String?
        private var suffix: String?
        private var middleName: String?
        private var displayName: String?

        @objc public override init() {}

        @objc public func setGivenName(_ value: String) {
            givenName = value
        }

        @objc public func setFamilyName(_ value: String) {
            familyName = value
        }

        @objc public func setPrefix(_ value: String) {
            prefix = value
        }

        @objc public func setSuffix(_ value: String) {
            suffix = value
        }

        @objc public func setMiddleName(_ value: String) {
            middleName = value
        }

        @objc public func setDisplayName(_ value: String) {
            displayName = value
        }

        @objc public func build() throws -> SSKProtoDataMessageContactName {
            let proto = SignalServiceProtos_DataMessage.Contact.Name.with { (builder) in
                if let givenName = self.givenName {
                    builder.givenName = givenName
                }
                if let familyName = self.familyName {
                    builder.familyName = familyName
                }
                if let prefix = self.prefix {
                    builder.prefix = prefix
                }
                if let suffix = self.suffix {
                    builder.suffix = suffix
                }
                if let middleName = self.middleName {
                    builder.middleName = middleName
                }
                if let displayName = self.displayName {
                    builder.displayName = displayName
                }
            }

            let wrapper = try SSKProtoDataMessageContactName.parseProto(proto)
            return wrapper
        }
    }

    @objc public let givenName: String?
    @objc public let familyName: String?
    @objc public let prefix: String?
    @objc public let suffix: String?
    @objc public let middleName: String?
    @objc public let displayName: String?

    @objc public init(givenName: String?,
                      familyName: String?,
                      prefix: String?,
                      suffix: String?,
                      middleName: String?,
                      displayName: String?) {
        self.givenName = givenName
        self.familyName = familyName
        self.prefix = prefix
        self.suffix = suffix
        self.middleName = middleName
        self.displayName = displayName
    }

    @objc
    public func serializedData() throws -> Data {
        return try self.asProtobuf.serializedData()
    }

    @objc public class func parseData(_ serializedData: Data) throws -> SSKProtoDataMessageContactName {
        let proto = try SignalServiceProtos_DataMessage.Contact.Name(serializedData: serializedData)
        return try parseProto(proto)
    }

    fileprivate class func parseProto(_ proto: SignalServiceProtos_DataMessage.Contact.Name) throws -> SSKProtoDataMessageContactName {
        var givenName: String? = nil
        if proto.hasGivenName {
            givenName = proto.givenName
        }

        var familyName: String? = nil
        if proto.hasFamilyName {
            familyName = proto.familyName
        }

        var prefix: String? = nil
        if proto.hasPrefix {
            prefix = proto.prefix
        }

        var suffix: String? = nil
        if proto.hasSuffix {
            suffix = proto.suffix
        }

        var middleName: String? = nil
        if proto.hasMiddleName {
            middleName = proto.middleName
        }

        var displayName: String? = nil
        if proto.hasDisplayName {
            displayName = proto.displayName
        }

        // MARK: - Begin Validation Logic for SSKProtoDataMessageContactName -

        // MARK: - End Validation Logic for SSKProtoDataMessageContactName -

        let result = SSKProtoDataMessageContactName(givenName: givenName,
                                                    familyName: familyName,
                                                    prefix: prefix,
                                                    suffix: suffix,
                                                    middleName: middleName,
                                                    displayName: displayName)
        return result
    }

    fileprivate var asProtobuf: SignalServiceProtos_DataMessage.Contact.Name {
        let proto = SignalServiceProtos_DataMessage.Contact.Name.with { (builder) in
            if let givenName = self.givenName {
                builder.givenName = givenName
            }

            if let familyName = self.familyName {
                builder.familyName = familyName
            }

            if let prefix = self.prefix {
                builder.prefix = prefix
            }

            if let suffix = self.suffix {
                builder.suffix = suffix
            }

            if let middleName = self.middleName {
                builder.middleName = middleName
            }

            if let displayName = self.displayName {
                builder.displayName = displayName
            }
        }

        return proto
    }
}

// MARK: - SSKProtoDataMessageContactPhone

@objc public class SSKProtoDataMessageContactPhone: NSObject {

    // MARK: - SSKProtoDataMessageContactPhoneType

    @objc public enum SSKProtoDataMessageContactPhoneType: Int32 {
        case home = 1
        case mobile = 2
        case work = 3
        case custom = 4
    }

    private class func SSKProtoDataMessageContactPhoneTypeWrap(_ value: SignalServiceProtos_DataMessage.Contact.Phone.TypeEnum) -> SSKProtoDataMessageContactPhoneType {
        switch value {
        case .home: return .home
        case .mobile: return .mobile
        case .work: return .work
        case .custom: return .custom
        }
    }

    private class func SSKProtoDataMessageContactPhoneTypeUnwrap(_ value: SSKProtoDataMessageContactPhoneType) -> SignalServiceProtos_DataMessage.Contact.Phone.TypeEnum {
        switch value {
        case .home: return .home
        case .mobile: return .mobile
        case .work: return .work
        case .custom: return .custom
        }
    }

    // MARK: - SSKProtoDataMessageContactPhoneBuilder

    @objc public class SSKProtoDataMessageContactPhoneBuilder: NSObject {

        private var value: String?
        private var type: SSKProtoDataMessageContactPhoneType?
        private var label: String?

        @objc public override init() {}

        @objc public func setValue(_ value: String) {
            value = value
        }

        @objc public func setType(_ value: SSKProtoDataMessageContactPhoneType) {
            type = value
        }

        @objc public func setLabel(_ value: String) {
            label = value
        }

        @objc public func build() throws -> SSKProtoDataMessageContactPhone {
            let proto = SignalServiceProtos_DataMessage.Contact.Phone.with { (builder) in
                if let value = self.value {
                    builder.value = value
                }
                if let type = self.type {
                    builder.type = SSKProtoDataMessageContactPhoneTypeUnwrap(type)
                }
                if let label = self.label {
                    builder.label = label
                }
            }

            let wrapper = try SSKProtoDataMessageContactPhone.parseProto(proto)
            return wrapper
        }
    }

    @objc public let value: String?
    @objc public let type: SSKProtoDataMessageContactPhoneType
    @objc public let label: String?

    @objc public init(value: String?,
                      type: SSKProtoDataMessageContactPhoneType,
                      label: String?) {
        self.value = value
        self.type = type
        self.label = label
    }

    @objc
    public func serializedData() throws -> Data {
        return try self.asProtobuf.serializedData()
    }

    @objc public class func parseData(_ serializedData: Data) throws -> SSKProtoDataMessageContactPhone {
        let proto = try SignalServiceProtos_DataMessage.Contact.Phone(serializedData: serializedData)
        return try parseProto(proto)
    }

    fileprivate class func parseProto(_ proto: SignalServiceProtos_DataMessage.Contact.Phone) throws -> SSKProtoDataMessageContactPhone {
        guard proto.hasValue else {
            throw SSKProtoError.invalidProtobuf(description: "\(logTag) missing required field: value")
        }
        let value = proto.value

        var type: SSKProtoDataMessageContactPhoneType = .home
        if proto.hasType {
            type = SSKProtoDataMessageContactPhoneTypeWrap(proto.type)
        }

        var label: String? = nil
        if proto.hasLabel {
            label = proto.label
        }

        // MARK: - Begin Validation Logic for SSKProtoDataMessageContactPhone -

        guard proto.hasValue else {
            throw SSKProtoError.invalidProtobuf(description: "\(logTag) missing required field: value")
        }

        // MARK: - End Validation Logic for SSKProtoDataMessageContactPhone -

        let result = SSKProtoDataMessageContactPhone(value: value,
                                                     type: type,
                                                     label: label)
        return result
    }

    fileprivate var asProtobuf: SignalServiceProtos_DataMessage.Contact.Phone {
        let proto = SignalServiceProtos_DataMessage.Contact.Phone.with { (builder) in
            if let value = self.value {
                builder.value = value
            }

            builder.type = SSKProtoDataMessageContactPhone.SSKProtoDataMessageContactPhoneTypeUnwrap(self.type)

            if let label = self.label {
                builder.label = label
            }
        }

        return proto
    }
}

// MARK: - SSKProtoDataMessageContactEmail

@objc public class SSKProtoDataMessageContactEmail: NSObject {

    // MARK: - SSKProtoDataMessageContactEmailType

    @objc public enum SSKProtoDataMessageContactEmailType: Int32 {
        case home = 1
        case mobile = 2
        case work = 3
        case custom = 4
    }

    private class func SSKProtoDataMessageContactEmailTypeWrap(_ value: SignalServiceProtos_DataMessage.Contact.Email.TypeEnum) -> SSKProtoDataMessageContactEmailType {
        switch value {
        case .home: return .home
        case .mobile: return .mobile
        case .work: return .work
        case .custom: return .custom
        }
    }

    private class func SSKProtoDataMessageContactEmailTypeUnwrap(_ value: SSKProtoDataMessageContactEmailType) -> SignalServiceProtos_DataMessage.Contact.Email.TypeEnum {
        switch value {
        case .home: return .home
        case .mobile: return .mobile
        case .work: return .work
        case .custom: return .custom
        }
    }

    // MARK: - SSKProtoDataMessageContactEmailBuilder

    @objc public class SSKProtoDataMessageContactEmailBuilder: NSObject {

        private var value: String?
        private var type: SSKProtoDataMessageContactEmailType?
        private var label: String?

        @objc public override init() {}

        @objc public func setValue(_ value: String) {
            value = value
        }

        @objc public func setType(_ value: SSKProtoDataMessageContactEmailType) {
            type = value
        }

        @objc public func setLabel(_ value: String) {
            label = value
        }

        @objc public func build() throws -> SSKProtoDataMessageContactEmail {
            let proto = SignalServiceProtos_DataMessage.Contact.Email.with { (builder) in
                if let value = self.value {
                    builder.value = value
                }
                if let type = self.type {
                    builder.type = SSKProtoDataMessageContactEmailTypeUnwrap(type)
                }
                if let label = self.label {
                    builder.label = label
                }
            }

            let wrapper = try SSKProtoDataMessageContactEmail.parseProto(proto)
            return wrapper
        }
    }

    @objc public let value: String?
    @objc public let type: SSKProtoDataMessageContactEmailType
    @objc public let label: String?

    @objc public init(value: String?,
                      type: SSKProtoDataMessageContactEmailType,
                      label: String?) {
        self.value = value
        self.type = type
        self.label = label
    }

    @objc
    public func serializedData() throws -> Data {
        return try self.asProtobuf.serializedData()
    }

    @objc public class func parseData(_ serializedData: Data) throws -> SSKProtoDataMessageContactEmail {
        let proto = try SignalServiceProtos_DataMessage.Contact.Email(serializedData: serializedData)
        return try parseProto(proto)
    }

    fileprivate class func parseProto(_ proto: SignalServiceProtos_DataMessage.Contact.Email) throws -> SSKProtoDataMessageContactEmail {
        guard proto.hasValue else {
            throw SSKProtoError.invalidProtobuf(description: "\(logTag) missing required field: value")
        }
        let value = proto.value

        var type: SSKProtoDataMessageContactEmailType = .home
        if proto.hasType {
            type = SSKProtoDataMessageContactEmailTypeWrap(proto.type)
        }

        var label: String? = nil
        if proto.hasLabel {
            label = proto.label
        }

        // MARK: - Begin Validation Logic for SSKProtoDataMessageContactEmail -

        guard proto.hasValue else {
            throw SSKProtoError.invalidProtobuf(description: "\(logTag) missing required field: value")
        }

        // MARK: - End Validation Logic for SSKProtoDataMessageContactEmail -

        let result = SSKProtoDataMessageContactEmail(value: value,
                                                     type: type,
                                                     label: label)
        return result
    }

    fileprivate var asProtobuf: SignalServiceProtos_DataMessage.Contact.Email {
        let proto = SignalServiceProtos_DataMessage.Contact.Email.with { (builder) in
            if let value = self.value {
                builder.value = value
            }

            builder.type = SSKProtoDataMessageContactEmail.SSKProtoDataMessageContactEmailTypeUnwrap(self.type)

            if let label = self.label {
                builder.label = label
            }
        }

        return proto
    }
}

// MARK: - SSKProtoDataMessageContactPostalAddress

@objc public class SSKProtoDataMessageContactPostalAddress: NSObject {

    // MARK: - SSKProtoDataMessageContactPostalAddressType

    @objc public enum SSKProtoDataMessageContactPostalAddressType: Int32 {
        case home = 1
        case work = 2
        case custom = 3
    }

    private class func SSKProtoDataMessageContactPostalAddressTypeWrap(_ value: SignalServiceProtos_DataMessage.Contact.PostalAddress.TypeEnum) -> SSKProtoDataMessageContactPostalAddressType {
        switch value {
        case .home: return .home
        case .work: return .work
        case .custom: return .custom
        }
    }

    private class func SSKProtoDataMessageContactPostalAddressTypeUnwrap(_ value: SSKProtoDataMessageContactPostalAddressType) -> SignalServiceProtos_DataMessage.Contact.PostalAddress.TypeEnum {
        switch value {
        case .home: return .home
        case .work: return .work
        case .custom: return .custom
        }
    }

    // MARK: - SSKProtoDataMessageContactPostalAddressBuilder

    @objc public class SSKProtoDataMessageContactPostalAddressBuilder: NSObject {

        private var type: SSKProtoDataMessageContactPostalAddressType?
        private var label: String?
        private var street: String?
        private var pobox: String?
        private var neighborhood: String?
        private var city: String?
        private var region: String?
        private var postcode: String?
        private var country: String?

        @objc public override init() {}

        @objc public func setType(_ value: SSKProtoDataMessageContactPostalAddressType) {
            type = value
        }

        @objc public func setLabel(_ value: String) {
            label = value
        }

        @objc public func setStreet(_ value: String) {
            street = value
        }

        @objc public func setPobox(_ value: String) {
            pobox = value
        }

        @objc public func setNeighborhood(_ value: String) {
            neighborhood = value
        }

        @objc public func setCity(_ value: String) {
            city = value
        }

        @objc public func setRegion(_ value: String) {
            region = value
        }

        @objc public func setPostcode(_ value: String) {
            postcode = value
        }

        @objc public func setCountry(_ value: String) {
            country = value
        }

        @objc public func build() throws -> SSKProtoDataMessageContactPostalAddress {
            let proto = SignalServiceProtos_DataMessage.Contact.PostalAddress.with { (builder) in
                if let type = self.type {
                    builder.type = SSKProtoDataMessageContactPostalAddressTypeUnwrap(type)
                }
                if let label = self.label {
                    builder.label = label
                }
                if let street = self.street {
                    builder.street = street
                }
                if let pobox = self.pobox {
                    builder.pobox = pobox
                }
                if let neighborhood = self.neighborhood {
                    builder.neighborhood = neighborhood
                }
                if let city = self.city {
                    builder.city = city
                }
                if let region = self.region {
                    builder.region = region
                }
                if let postcode = self.postcode {
                    builder.postcode = postcode
                }
                if let country = self.country {
                    builder.country = country
                }
            }

            let wrapper = try SSKProtoDataMessageContactPostalAddress.parseProto(proto)
            return wrapper
        }
    }

    @objc public let type: SSKProtoDataMessageContactPostalAddressType
    @objc public let label: String?
    @objc public let street: String?
    @objc public let pobox: String?
    @objc public let neighborhood: String?
    @objc public let city: String?
    @objc public let region: String?
    @objc public let postcode: String?
    @objc public let country: String?

    @objc public init(type: SSKProtoDataMessageContactPostalAddressType,
                      label: String?,
                      street: String?,
                      pobox: String?,
                      neighborhood: String?,
                      city: String?,
                      region: String?,
                      postcode: String?,
                      country: String?) {
        self.type = type
        self.label = label
        self.street = street
        self.pobox = pobox
        self.neighborhood = neighborhood
        self.city = city
        self.region = region
        self.postcode = postcode
        self.country = country
    }

    @objc
    public func serializedData() throws -> Data {
        return try self.asProtobuf.serializedData()
    }

    @objc public class func parseData(_ serializedData: Data) throws -> SSKProtoDataMessageContactPostalAddress {
        let proto = try SignalServiceProtos_DataMessage.Contact.PostalAddress(serializedData: serializedData)
        return try parseProto(proto)
    }

    fileprivate class func parseProto(_ proto: SignalServiceProtos_DataMessage.Contact.PostalAddress) throws -> SSKProtoDataMessageContactPostalAddress {
        var type: SSKProtoDataMessageContactPostalAddressType = .home
        if proto.hasType {
            type = SSKProtoDataMessageContactPostalAddressTypeWrap(proto.type)
        }

        var label: String? = nil
        if proto.hasLabel {
            label = proto.label
        }

        var street: String? = nil
        if proto.hasStreet {
            street = proto.street
        }

        var pobox: String? = nil
        if proto.hasPobox {
            pobox = proto.pobox
        }

        var neighborhood: String? = nil
        if proto.hasNeighborhood {
            neighborhood = proto.neighborhood
        }

        var city: String? = nil
        if proto.hasCity {
            city = proto.city
        }

        var region: String? = nil
        if proto.hasRegion {
            region = proto.region
        }

        var postcode: String? = nil
        if proto.hasPostcode {
            postcode = proto.postcode
        }

        var country: String? = nil
        if proto.hasCountry {
            country = proto.country
        }

        // MARK: - Begin Validation Logic for SSKProtoDataMessageContactPostalAddress -

        // MARK: - End Validation Logic for SSKProtoDataMessageContactPostalAddress -

        let result = SSKProtoDataMessageContactPostalAddress(type: type,
                                                             label: label,
                                                             street: street,
                                                             pobox: pobox,
                                                             neighborhood: neighborhood,
                                                             city: city,
                                                             region: region,
                                                             postcode: postcode,
                                                             country: country)
        return result
    }

    fileprivate var asProtobuf: SignalServiceProtos_DataMessage.Contact.PostalAddress {
        let proto = SignalServiceProtos_DataMessage.Contact.PostalAddress.with { (builder) in
            builder.type = SSKProtoDataMessageContactPostalAddress.SSKProtoDataMessageContactPostalAddressTypeUnwrap(self.type)

            if let label = self.label {
                builder.label = label
            }

            if let street = self.street {
                builder.street = street
            }

            if let pobox = self.pobox {
                builder.pobox = pobox
            }

            if let neighborhood = self.neighborhood {
                builder.neighborhood = neighborhood
            }

            if let city = self.city {
                builder.city = city
            }

            if let region = self.region {
                builder.region = region
            }

            if let postcode = self.postcode {
                builder.postcode = postcode
            }

            if let country = self.country {
                builder.country = country
            }
        }

        return proto
    }
}

// MARK: - SSKProtoDataMessageContactAvatar

@objc public class SSKProtoDataMessageContactAvatar: NSObject {

    // MARK: - SSKProtoDataMessageContactAvatarBuilder

    @objc public class SSKProtoDataMessageContactAvatarBuilder: NSObject {

        private var avatar: SSKProtoAttachmentPointer?
        private var isProfile: Bool?

        @objc public override init() {}

        @objc public func setAvatar(_ value: SSKProtoAttachmentPointer) {
            avatar = value
        }

        @objc public func setIsProfile(_ value: Bool) {
            isProfile = value
        }

        @objc public func build() throws -> SSKProtoDataMessageContactAvatar {
            let proto = SignalServiceProtos_DataMessage.Contact.Avatar.with { (builder) in
                if let avatar = self.avatar {
                    builder.avatar = avatar.asProtobuf
                }
                if let isProfile = self.isProfile {
                    builder.isProfile = isProfile
                }
            }

            let wrapper = try SSKProtoDataMessageContactAvatar.parseProto(proto)
            return wrapper
        }
    }

    @objc public let avatar: SSKProtoAttachmentPointer?
    @objc public let isProfile: Bool?

    @objc public init(avatar: SSKProtoAttachmentPointer?,
                      isProfile: Bool?) {
        self.avatar = avatar
        self.isProfile = isProfile
    }

    @objc
    public func serializedData() throws -> Data {
        return try self.asProtobuf.serializedData()
    }

    @objc public class func parseData(_ serializedData: Data) throws -> SSKProtoDataMessageContactAvatar {
        let proto = try SignalServiceProtos_DataMessage.Contact.Avatar(serializedData: serializedData)
        return try parseProto(proto)
    }

    fileprivate class func parseProto(_ proto: SignalServiceProtos_DataMessage.Contact.Avatar) throws -> SSKProtoDataMessageContactAvatar {
        var avatar: SSKProtoAttachmentPointer? = nil
        if proto.hasAvatar {
            avatar = try SSKProtoAttachmentPointer.parseProto(proto.avatar)
        }

        var isProfile: Bool? = nil
        if proto.hasIsProfile {
            isProfile = proto.isProfile
        }

        // MARK: - Begin Validation Logic for SSKProtoDataMessageContactAvatar -

        // MARK: - End Validation Logic for SSKProtoDataMessageContactAvatar -

        let result = SSKProtoDataMessageContactAvatar(avatar: avatar,
                                                      isProfile: isProfile)
        return result
    }

    fileprivate var asProtobuf: SignalServiceProtos_DataMessage.Contact.Avatar {
        let proto = SignalServiceProtos_DataMessage.Contact.Avatar.with { (builder) in
            if let avatar = self.avatar {
                builder.avatar = avatar.asProtobuf
            }

            if let isProfile = self.isProfile {
                builder.isProfile = isProfile
            }
        }

        return proto
    }
}

// MARK: - SSKProtoDataMessageContact

@objc public class SSKProtoDataMessageContact: NSObject {

    // MARK: - SSKProtoDataMessageContactBuilder

    @objc public class SSKProtoDataMessageContactBuilder: NSObject {

        private var name: SSKProtoDataMessageContactName?
        private var number: [SSKProtoDataMessageContactPhone]
        private var email: [SSKProtoDataMessageContactEmail]
        private var address: [SSKProtoDataMessageContactPostalAddress]
        private var avatar: SSKProtoDataMessageContactAvatar?
        private var organization: String?

        @objc public override init() {}

        @objc public func setName(_ value: SSKProtoDataMessageContactName) {
            name = value
        }

        @objc public func addNumber(_ value: SSKProtoDataMessageContactPhone) {
            number.append(value)
        }

        @objc public func addEmail(_ value: SSKProtoDataMessageContactEmail) {
            email.append(value)
        }

        @objc public func addAddress(_ value: SSKProtoDataMessageContactPostalAddress) {
            address.append(value)
        }

        @objc public func setAvatar(_ value: SSKProtoDataMessageContactAvatar) {
            avatar = value
        }

        @objc public func setOrganization(_ value: String) {
            organization = value
        }

        @objc public func build() throws -> SSKProtoDataMessageContact {
            let proto = SignalServiceProtos_DataMessage.Contact.with { (builder) in
                if let name = self.name {
                    builder.name = name.asProtobuf
                }
                for item in number {
                    builder.addNumber(item.asProtobuf)
                }
                for item in email {
                    builder.addEmail(item.asProtobuf)
                }
                for item in address {
                    builder.addAddress(item.asProtobuf)
                }
                if let avatar = self.avatar {
                    builder.avatar = avatar.asProtobuf
                }
                if let organization = self.organization {
                    builder.organization = organization
                }
            }

            let wrapper = try SSKProtoDataMessageContact.parseProto(proto)
            return wrapper
        }
    }

    @objc public let name: SSKProtoDataMessageContactName?
    @objc public let number: [SSKProtoDataMessageContactPhone]
    @objc public let email: [SSKProtoDataMessageContactEmail]
    @objc public let address: [SSKProtoDataMessageContactPostalAddress]
    @objc public let avatar: SSKProtoDataMessageContactAvatar?
    @objc public let organization: String?

    @objc public init(name: SSKProtoDataMessageContactName?,
                      number: [SSKProtoDataMessageContactPhone],
                      email: [SSKProtoDataMessageContactEmail],
                      address: [SSKProtoDataMessageContactPostalAddress],
                      avatar: SSKProtoDataMessageContactAvatar?,
                      organization: String?) {
        self.name = name
        self.number = number
        self.email = email
        self.address = address
        self.avatar = avatar
        self.organization = organization
    }

    @objc
    public func serializedData() throws -> Data {
        return try self.asProtobuf.serializedData()
    }

    @objc public class func parseData(_ serializedData: Data) throws -> SSKProtoDataMessageContact {
        let proto = try SignalServiceProtos_DataMessage.Contact(serializedData: serializedData)
        return try parseProto(proto)
    }

    fileprivate class func parseProto(_ proto: SignalServiceProtos_DataMessage.Contact) throws -> SSKProtoDataMessageContact {
        var name: SSKProtoDataMessageContactName? = nil
        if proto.hasName {
            name = try SSKProtoDataMessageContactName.parseProto(proto.name)
        }

        var number: [SSKProtoDataMessageContactPhone] = []
        for item in proto.number {
            let wrapped = try SSKProtoDataMessageContactPhone.parseProto(item)
            number.append(wrapped)
        }

        var email: [SSKProtoDataMessageContactEmail] = []
        for item in proto.email {
            let wrapped = try SSKProtoDataMessageContactEmail.parseProto(item)
            email.append(wrapped)
        }

        var address: [SSKProtoDataMessageContactPostalAddress] = []
        for item in proto.address {
            let wrapped = try SSKProtoDataMessageContactPostalAddress.parseProto(item)
            address.append(wrapped)
        }

        var avatar: SSKProtoDataMessageContactAvatar? = nil
        if proto.hasAvatar {
            avatar = try SSKProtoDataMessageContactAvatar.parseProto(proto.avatar)
        }

        var organization: String? = nil
        if proto.hasOrganization {
            organization = proto.organization
        }

        // MARK: - Begin Validation Logic for SSKProtoDataMessageContact -

        // MARK: - End Validation Logic for SSKProtoDataMessageContact -

        let result = SSKProtoDataMessageContact(name: name,
                                                number: number,
                                                email: email,
                                                address: address,
                                                avatar: avatar,
                                                organization: organization)
        return result
    }

    fileprivate var asProtobuf: SignalServiceProtos_DataMessage.Contact {
        let proto = SignalServiceProtos_DataMessage.Contact.with { (builder) in
            if let name = self.name {
                builder.name = name.asProtobuf
            }

            var numberUnwrapped = [SignalServiceProtos_DataMessage.Contact.Phone]()
            for item in number {
                numberUnwrapped.append(item.asProtobuf)
            }
            builder.number = numberUnwrapped

            var emailUnwrapped = [SignalServiceProtos_DataMessage.Contact.Email]()
            for item in email {
                emailUnwrapped.append(item.asProtobuf)
            }
            builder.email = emailUnwrapped

            var addressUnwrapped = [SignalServiceProtos_DataMessage.Contact.PostalAddress]()
            for item in address {
                addressUnwrapped.append(item.asProtobuf)
            }
            builder.address = addressUnwrapped

            if let avatar = self.avatar {
                builder.avatar = avatar.asProtobuf
            }

            if let organization = self.organization {
                builder.organization = organization
            }
        }

        return proto
    }
}

// MARK: - SSKProtoDataMessage

@objc public class SSKProtoDataMessage: NSObject {

    // MARK: - SSKProtoDataMessageFlags

    @objc public enum SSKProtoDataMessageFlags: Int32 {
        case endSession = 1
        case expirationTimerUpdate = 2
        case profileKeyUpdate = 4
    }

    private class func SSKProtoDataMessageFlagsWrap(_ value: SignalServiceProtos_DataMessage.Flags) -> SSKProtoDataMessageFlags {
        switch value {
        case .endSession: return .endSession
        case .expirationTimerUpdate: return .expirationTimerUpdate
        case .profileKeyUpdate: return .profileKeyUpdate
        }
    }

    private class func SSKProtoDataMessageFlagsUnwrap(_ value: SSKProtoDataMessageFlags) -> SignalServiceProtos_DataMessage.Flags {
        switch value {
        case .endSession: return .endSession
        case .expirationTimerUpdate: return .expirationTimerUpdate
        case .profileKeyUpdate: return .profileKeyUpdate
        }
    }

    // MARK: - SSKProtoDataMessageBuilder

    @objc public class SSKProtoDataMessageBuilder: NSObject {

        private var body: String?
        private var attachments: [SSKProtoAttachmentPointer]
        private var group: SSKProtoGroupContext?
        private var flags: UInt32?
        private var expireTimer: UInt32?
        private var profileKey: Data?
        private var timestamp: UInt64?
        private var quote: SSKProtoDataMessageQuote?
        private var contact: [SSKProtoDataMessageContact]

        @objc public override init() {}

        @objc public func setBody(_ value: String) {
            body = value
        }

        @objc public func addAttachments(_ value: SSKProtoAttachmentPointer) {
            attachments.append(value)
        }

        @objc public func setGroup(_ value: SSKProtoGroupContext) {
            group = value
        }

        @objc public func setFlags(_ value: UInt32) {
            flags = value
        }

        @objc public func setExpireTimer(_ value: UInt32) {
            expireTimer = value
        }

        @objc public func setProfileKey(_ value: Data) {
            profileKey = value
        }

        @objc public func setTimestamp(_ value: UInt64) {
            timestamp = value
        }

        @objc public func setQuote(_ value: SSKProtoDataMessageQuote) {
            quote = value
        }

        @objc public func addContact(_ value: SSKProtoDataMessageContact) {
            contact.append(value)
        }

        @objc public func build() throws -> SSKProtoDataMessage {
            let proto = SignalServiceProtos_DataMessage.with { (builder) in
                if let body = self.body {
                    builder.body = body
                }
                for item in attachments {
                    builder.addAttachments(item.asProtobuf)
                }
                if let group = self.group {
                    builder.group = group.asProtobuf
                }
                if let flags = self.flags {
                    builder.flags = flags
                }
                if let expireTimer = self.expireTimer {
                    builder.expireTimer = expireTimer
                }
                if let profileKey = self.profileKey {
                    builder.profileKey = profileKey
                }
                if let timestamp = self.timestamp {
                    builder.timestamp = timestamp
                }
                if let quote = self.quote {
                    builder.quote = quote.asProtobuf
                }
                for item in contact {
                    builder.addContact(item.asProtobuf)
                }
            }

            let wrapper = try SSKProtoDataMessage.parseProto(proto)
            return wrapper
        }
    }

    @objc public let body: String?
    @objc public let attachments: [SSKProtoAttachmentPointer]
    @objc public let group: SSKProtoGroupContext?
    @objc public let flags: UInt32?
    @objc public let expireTimer: UInt32?
    @objc public let profileKey: Data?
    @objc public let timestamp: UInt64?
    @objc public let quote: SSKProtoDataMessageQuote?
    @objc public let contact: [SSKProtoDataMessageContact]

    @objc public init(body: String?,
                      attachments: [SSKProtoAttachmentPointer],
                      group: SSKProtoGroupContext?,
                      flags: UInt32?,
                      expireTimer: UInt32?,
                      profileKey: Data?,
                      timestamp: UInt64?,
                      quote: SSKProtoDataMessageQuote?,
                      contact: [SSKProtoDataMessageContact]) {
        self.body = body
        self.attachments = attachments
        self.group = group
        self.flags = flags
        self.expireTimer = expireTimer
        self.profileKey = profileKey
        self.timestamp = timestamp
        self.quote = quote
        self.contact = contact
    }

    @objc
    public func serializedData() throws -> Data {
        return try self.asProtobuf.serializedData()
    }

    @objc public class func parseData(_ serializedData: Data) throws -> SSKProtoDataMessage {
        let proto = try SignalServiceProtos_DataMessage(serializedData: serializedData)
        return try parseProto(proto)
    }

    fileprivate class func parseProto(_ proto: SignalServiceProtos_DataMessage) throws -> SSKProtoDataMessage {
        var body: String? = nil
        if proto.hasBody {
            body = proto.body
        }

        var attachments: [SSKProtoAttachmentPointer] = []
        for item in proto.attachments {
            let wrapped = try SSKProtoAttachmentPointer.parseProto(item)
            attachments.append(wrapped)
        }

        var group: SSKProtoGroupContext? = nil
        if proto.hasGroup {
            group = try SSKProtoGroupContext.parseProto(proto.group)
        }

        var flags: UInt32? = nil
        if proto.hasFlags {
            flags = proto.flags
        }

        var expireTimer: UInt32? = nil
        if proto.hasExpireTimer {
            expireTimer = proto.expireTimer
        }

        var profileKey: Data? = nil
        if proto.hasProfileKey {
            profileKey = proto.profileKey
        }

        var timestamp: UInt64? = nil
        if proto.hasTimestamp {
            timestamp = proto.timestamp
        }

        var quote: SSKProtoDataMessageQuote? = nil
        if proto.hasQuote {
            quote = try SSKProtoDataMessageQuote.parseProto(proto.quote)
        }

        var contact: [SSKProtoDataMessageContact] = []
        for item in proto.contact {
            let wrapped = try SSKProtoDataMessageContact.parseProto(item)
            contact.append(wrapped)
        }

        // MARK: - Begin Validation Logic for SSKProtoDataMessage -

        // MARK: - End Validation Logic for SSKProtoDataMessage -

        let result = SSKProtoDataMessage(body: body,
                                         attachments: attachments,
                                         group: group,
                                         flags: flags,
                                         expireTimer: expireTimer,
                                         profileKey: profileKey,
                                         timestamp: timestamp,
                                         quote: quote,
                                         contact: contact)
        return result
    }

    fileprivate var asProtobuf: SignalServiceProtos_DataMessage {
        let proto = SignalServiceProtos_DataMessage.with { (builder) in
            if let body = self.body {
                builder.body = body
            }

            var attachmentsUnwrapped = [SignalServiceProtos_AttachmentPointer]()
            for item in attachments {
                attachmentsUnwrapped.append(item.asProtobuf)
            }
            builder.attachments = attachmentsUnwrapped

            if let group = self.group {
                builder.group = group.asProtobuf
            }

            if let flags = self.flags {
                builder.flags = flags
            }

            if let expireTimer = self.expireTimer {
                builder.expireTimer = expireTimer
            }

            if let profileKey = self.profileKey {
                builder.profileKey = profileKey
            }

            if let timestamp = self.timestamp {
                builder.timestamp = timestamp
            }

            if let quote = self.quote {
                builder.quote = quote.asProtobuf
            }

            var contactUnwrapped = [SignalServiceProtos_DataMessage.Contact]()
            for item in contact {
                contactUnwrapped.append(item.asProtobuf)
            }
            builder.contact = contactUnwrapped
        }

        return proto
    }
}

// MARK: - SSKProtoNullMessage

@objc public class SSKProtoNullMessage: NSObject {

    // MARK: - SSKProtoNullMessageBuilder

    @objc public class SSKProtoNullMessageBuilder: NSObject {

        private var padding: Data?

        @objc public override init() {}

        @objc public func setPadding(_ value: Data) {
            padding = value
        }

        @objc public func build() throws -> SSKProtoNullMessage {
            let proto = SignalServiceProtos_NullMessage.with { (builder) in
                if let padding = self.padding {
                    builder.padding = padding
                }
            }

            let wrapper = try SSKProtoNullMessage.parseProto(proto)
            return wrapper
        }
    }

    @objc public let padding: Data?

    @objc public init(padding: Data?) {
        self.padding = padding
    }

    @objc
    public func serializedData() throws -> Data {
        return try self.asProtobuf.serializedData()
    }

    @objc public class func parseData(_ serializedData: Data) throws -> SSKProtoNullMessage {
        let proto = try SignalServiceProtos_NullMessage(serializedData: serializedData)
        return try parseProto(proto)
    }

    fileprivate class func parseProto(_ proto: SignalServiceProtos_NullMessage) throws -> SSKProtoNullMessage {
        var padding: Data? = nil
        if proto.hasPadding {
            padding = proto.padding
        }

        // MARK: - Begin Validation Logic for SSKProtoNullMessage -

        // MARK: - End Validation Logic for SSKProtoNullMessage -

        let result = SSKProtoNullMessage(padding: padding)
        return result
    }

    fileprivate var asProtobuf: SignalServiceProtos_NullMessage {
        let proto = SignalServiceProtos_NullMessage.with { (builder) in
            if let padding = self.padding {
                builder.padding = padding
            }
        }

        return proto
    }
}

// MARK: - SSKProtoReceiptMessage

@objc public class SSKProtoReceiptMessage: NSObject {

    // MARK: - SSKProtoReceiptMessageType

    @objc public enum SSKProtoReceiptMessageType: Int32 {
        case delivery = 0
        case read = 1
    }

    private class func SSKProtoReceiptMessageTypeWrap(_ value: SignalServiceProtos_ReceiptMessage.TypeEnum) -> SSKProtoReceiptMessageType {
        switch value {
        case .delivery: return .delivery
        case .read: return .read
        }
    }

    private class func SSKProtoReceiptMessageTypeUnwrap(_ value: SSKProtoReceiptMessageType) -> SignalServiceProtos_ReceiptMessage.TypeEnum {
        switch value {
        case .delivery: return .delivery
        case .read: return .read
        }
    }

    // MARK: - SSKProtoReceiptMessageBuilder

    @objc public class SSKProtoReceiptMessageBuilder: NSObject {

        private var type: SSKProtoReceiptMessageType?
        private var timestamp: [UInt64]

        @objc public override init() {}

        @objc public func setType(_ value: SSKProtoReceiptMessageType) {
            type = value
        }

        @objc public func addTimestamp(_ value: UInt64) {
            timestamp.append(value)
        }

        @objc public func build() throws -> SSKProtoReceiptMessage {
            let proto = SignalServiceProtos_ReceiptMessage.with { (builder) in
                if let type = self.type {
                    builder.type = SSKProtoReceiptMessageTypeUnwrap(type)
                }
                for item in timestamp {
                    builder.addTimestamp(item)
                }
            }

            let wrapper = try SSKProtoReceiptMessage.parseProto(proto)
            return wrapper
        }
    }

    @objc public let type: SSKProtoReceiptMessageType
    @objc public let timestamp: [UInt64]

    @objc public init(type: SSKProtoReceiptMessageType,
                      timestamp: [UInt64]) {
        self.type = type
        self.timestamp = timestamp
    }

    @objc
    public func serializedData() throws -> Data {
        return try self.asProtobuf.serializedData()
    }

    @objc public class func parseData(_ serializedData: Data) throws -> SSKProtoReceiptMessage {
        let proto = try SignalServiceProtos_ReceiptMessage(serializedData: serializedData)
        return try parseProto(proto)
    }

    fileprivate class func parseProto(_ proto: SignalServiceProtos_ReceiptMessage) throws -> SSKProtoReceiptMessage {
        guard proto.hasType else {
            throw SSKProtoError.invalidProtobuf(description: "\(logTag) missing required field: type")
        }
        let type = SSKProtoReceiptMessageTypeWrap(proto.type)

        var timestamp: [UInt64] = []
        for item in proto.timestamp {
            let wrapped = item
            timestamp.append(wrapped)
        }

        // MARK: - Begin Validation Logic for SSKProtoReceiptMessage -

        guard proto.hasType else {
            throw SSKProtoError.invalidProtobuf(description: "\(logTag) missing required field: type")
        }

        // MARK: - End Validation Logic for SSKProtoReceiptMessage -

        let result = SSKProtoReceiptMessage(type: type,
                                            timestamp: timestamp)
        return result
    }

    fileprivate var asProtobuf: SignalServiceProtos_ReceiptMessage {
        let proto = SignalServiceProtos_ReceiptMessage.with { (builder) in
            builder.type = SSKProtoReceiptMessage.SSKProtoReceiptMessageTypeUnwrap(self.type)

            var timestampUnwrapped = [UInt64]()
            for item in timestamp {
                timestampUnwrapped.append(item)
            }
            builder.timestamp = timestampUnwrapped
        }

        return proto
    }
}

// MARK: - SSKProtoVerified

@objc public class SSKProtoVerified: NSObject {

    // MARK: - SSKProtoVerifiedState

    @objc public enum SSKProtoVerifiedState: Int32 {
        case `default` = 0
        case verified = 1
        case unverified = 2
    }

    private class func SSKProtoVerifiedStateWrap(_ value: SignalServiceProtos_Verified.State) -> SSKProtoVerifiedState {
        switch value {
        case .default: return .default
        case .verified: return .verified
        case .unverified: return .unverified
        }
    }

    private class func SSKProtoVerifiedStateUnwrap(_ value: SSKProtoVerifiedState) -> SignalServiceProtos_Verified.State {
        switch value {
        case .default: return .default
        case .verified: return .verified
        case .unverified: return .unverified
        }
    }

    // MARK: - SSKProtoVerifiedBuilder

    @objc public class SSKProtoVerifiedBuilder: NSObject {

        private var destination: String?
        private var identityKey: Data?
        private var state: SSKProtoVerifiedState?
        private var nullMessage: Data?

        @objc public override init() {}

        @objc public func setDestination(_ value: String) {
            destination = value
        }

        @objc public func setIdentityKey(_ value: Data) {
            identityKey = value
        }

        @objc public func setState(_ value: SSKProtoVerifiedState) {
            state = value
        }

        @objc public func setNullMessage(_ value: Data) {
            nullMessage = value
        }

        @objc public func build() throws -> SSKProtoVerified {
            let proto = SignalServiceProtos_Verified.with { (builder) in
                if let destination = self.destination {
                    builder.destination = destination
                }
                if let identityKey = self.identityKey {
                    builder.identityKey = identityKey
                }
                if let state = self.state {
                    builder.state = SSKProtoVerifiedStateUnwrap(state)
                }
                if let nullMessage = self.nullMessage {
                    builder.nullMessage = nullMessage
                }
            }

            let wrapper = try SSKProtoVerified.parseProto(proto)
            return wrapper
        }
    }

    @objc public let destination: String?
    @objc public let identityKey: Data?
    @objc public let state: SSKProtoVerifiedState
    @objc public let nullMessage: Data?

    @objc public init(destination: String?,
                      identityKey: Data?,
                      state: SSKProtoVerifiedState,
                      nullMessage: Data?) {
        self.destination = destination
        self.identityKey = identityKey
        self.state = state
        self.nullMessage = nullMessage
    }

    @objc
    public func serializedData() throws -> Data {
        return try self.asProtobuf.serializedData()
    }

    @objc public class func parseData(_ serializedData: Data) throws -> SSKProtoVerified {
        let proto = try SignalServiceProtos_Verified(serializedData: serializedData)
        return try parseProto(proto)
    }

    fileprivate class func parseProto(_ proto: SignalServiceProtos_Verified) throws -> SSKProtoVerified {
        guard proto.hasDestination else {
            throw SSKProtoError.invalidProtobuf(description: "\(logTag) missing required field: destination")
        }
        let destination = proto.destination

        var identityKey: Data? = nil
        if proto.hasIdentityKey {
            identityKey = proto.identityKey
        }

        var state: SSKProtoVerifiedState = .default
        if proto.hasState {
            state = SSKProtoVerifiedStateWrap(proto.state)
        }

        var nullMessage: Data? = nil
        if proto.hasNullMessage {
            nullMessage = proto.nullMessage
        }

        // MARK: - Begin Validation Logic for SSKProtoVerified -

        // MARK: - End Validation Logic for SSKProtoVerified -

        let result = SSKProtoVerified(destination: destination,
                                      identityKey: identityKey,
                                      state: state,
                                      nullMessage: nullMessage)
        return result
    }

    fileprivate var asProtobuf: SignalServiceProtos_Verified {
        let proto = SignalServiceProtos_Verified.with { (builder) in
            if let destination = self.destination {
                builder.destination = destination
            }

            if let identityKey = self.identityKey {
                builder.identityKey = identityKey
            }

            builder.state = SSKProtoVerified.SSKProtoVerifiedStateUnwrap(self.state)

            if let nullMessage = self.nullMessage {
                builder.nullMessage = nullMessage
            }
        }

        return proto
    }
}

// MARK: - SSKProtoSyncMessageSent

@objc public class SSKProtoSyncMessageSent: NSObject {

    // MARK: - SSKProtoSyncMessageSentBuilder

    @objc public class SSKProtoSyncMessageSentBuilder: NSObject {

        private var destination: String?
        private var timestamp: UInt64?
        private var message: SSKProtoDataMessage?
        private var expirationStartTimestamp: UInt64?

        @objc public override init() {}

        @objc public func setDestination(_ value: String) {
            destination = value
        }

        @objc public func setTimestamp(_ value: UInt64) {
            timestamp = value
        }

        @objc public func setMessage(_ value: SSKProtoDataMessage) {
            message = value
        }

        @objc public func setExpirationStartTimestamp(_ value: UInt64) {
            expirationStartTimestamp = value
        }

        @objc public func build() throws -> SSKProtoSyncMessageSent {
            let proto = SignalServiceProtos_SyncMessage.Sent.with { (builder) in
                if let destination = self.destination {
                    builder.destination = destination
                }
                if let timestamp = self.timestamp {
                    builder.timestamp = timestamp
                }
                if let message = self.message {
                    builder.message = message.asProtobuf
                }
                if let expirationStartTimestamp = self.expirationStartTimestamp {
                    builder.expirationStartTimestamp = expirationStartTimestamp
                }
            }

            let wrapper = try SSKProtoSyncMessageSent.parseProto(proto)
            return wrapper
        }
    }

    @objc public let destination: String?
    @objc public let timestamp: UInt64?
    @objc public let message: SSKProtoDataMessage?
    @objc public let expirationStartTimestamp: UInt64?

    @objc public init(destination: String?,
                      timestamp: UInt64?,
                      message: SSKProtoDataMessage?,
                      expirationStartTimestamp: UInt64?) {
        self.destination = destination
        self.timestamp = timestamp
        self.message = message
        self.expirationStartTimestamp = expirationStartTimestamp
    }

    @objc
    public func serializedData() throws -> Data {
        return try self.asProtobuf.serializedData()
    }

    @objc public class func parseData(_ serializedData: Data) throws -> SSKProtoSyncMessageSent {
        let proto = try SignalServiceProtos_SyncMessage.Sent(serializedData: serializedData)
        return try parseProto(proto)
    }

    fileprivate class func parseProto(_ proto: SignalServiceProtos_SyncMessage.Sent) throws -> SSKProtoSyncMessageSent {
        var destination: String? = nil
        if proto.hasDestination {
            destination = proto.destination
        }

        var timestamp: UInt64? = nil
        if proto.hasTimestamp {
            timestamp = proto.timestamp
        }

        var message: SSKProtoDataMessage? = nil
        if proto.hasMessage {
            message = try SSKProtoDataMessage.parseProto(proto.message)
        }

        var expirationStartTimestamp: UInt64? = nil
        if proto.hasExpirationStartTimestamp {
            expirationStartTimestamp = proto.expirationStartTimestamp
        }

        // MARK: - Begin Validation Logic for SSKProtoSyncMessageSent -

        // MARK: - End Validation Logic for SSKProtoSyncMessageSent -

        let result = SSKProtoSyncMessageSent(destination: destination,
                                             timestamp: timestamp,
                                             message: message,
                                             expirationStartTimestamp: expirationStartTimestamp)
        return result
    }

    fileprivate var asProtobuf: SignalServiceProtos_SyncMessage.Sent {
        let proto = SignalServiceProtos_SyncMessage.Sent.with { (builder) in
            if let destination = self.destination {
                builder.destination = destination
            }

            if let timestamp = self.timestamp {
                builder.timestamp = timestamp
            }

            if let message = self.message {
                builder.message = message.asProtobuf
            }

            if let expirationStartTimestamp = self.expirationStartTimestamp {
                builder.expirationStartTimestamp = expirationStartTimestamp
            }
        }

        return proto
    }
}

// MARK: - SSKProtoSyncMessageContacts

@objc public class SSKProtoSyncMessageContacts: NSObject {

    // MARK: - SSKProtoSyncMessageContactsBuilder

    @objc public class SSKProtoSyncMessageContactsBuilder: NSObject {

        private var blob: SSKProtoAttachmentPointer?
        private var isComplete: Bool?

        @objc public override init() {}

        @objc public func setBlob(_ value: SSKProtoAttachmentPointer) {
            blob = value
        }

        @objc public func setIsComplete(_ value: Bool) {
            isComplete = value
        }

        @objc public func build() throws -> SSKProtoSyncMessageContacts {
            let proto = SignalServiceProtos_SyncMessage.Contacts.with { (builder) in
                if let blob = self.blob {
                    builder.blob = blob.asProtobuf
                }
                if let isComplete = self.isComplete {
                    builder.isComplete = isComplete
                }
            }

            let wrapper = try SSKProtoSyncMessageContacts.parseProto(proto)
            return wrapper
        }
    }

    @objc public let blob: SSKProtoAttachmentPointer?
    @objc public let isComplete: Bool?

    @objc public init(blob: SSKProtoAttachmentPointer?,
                      isComplete: Bool?) {
        self.blob = blob
        self.isComplete = isComplete
    }

    @objc
    public func serializedData() throws -> Data {
        return try self.asProtobuf.serializedData()
    }

    @objc public class func parseData(_ serializedData: Data) throws -> SSKProtoSyncMessageContacts {
        let proto = try SignalServiceProtos_SyncMessage.Contacts(serializedData: serializedData)
        return try parseProto(proto)
    }

    fileprivate class func parseProto(_ proto: SignalServiceProtos_SyncMessage.Contacts) throws -> SSKProtoSyncMessageContacts {
        guard proto.hasBlob else {
            throw SSKProtoError.invalidProtobuf(description: "\(logTag) missing required field: blob")
        }
        let blob = try SSKProtoAttachmentPointer.parseProto(proto.blob)

        var isComplete: Bool? = false
        if proto.hasIsComplete {
            isComplete = proto.isComplete
        }

        // MARK: - Begin Validation Logic for SSKProtoSyncMessageContacts -

        guard proto.hasBlob else {
            throw SSKProtoError.invalidProtobuf(description: "\(logTag) missing required field: blob")
        }

        // MARK: - End Validation Logic for SSKProtoSyncMessageContacts -

        let result = SSKProtoSyncMessageContacts(blob: blob,
                                                 isComplete: isComplete)
        return result
    }

    fileprivate var asProtobuf: SignalServiceProtos_SyncMessage.Contacts {
        let proto = SignalServiceProtos_SyncMessage.Contacts.with { (builder) in
            if let blob = self.blob {
                builder.blob = blob.asProtobuf
            }

            if let isComplete = self.isComplete {
                builder.isComplete = isComplete
            }
        }

        return proto
    }
}

// MARK: - SSKProtoSyncMessageGroups

@objc public class SSKProtoSyncMessageGroups: NSObject {

    // MARK: - SSKProtoSyncMessageGroupsBuilder

    @objc public class SSKProtoSyncMessageGroupsBuilder: NSObject {

        private var blob: SSKProtoAttachmentPointer?

        @objc public override init() {}

        @objc public func setBlob(_ value: SSKProtoAttachmentPointer) {
            blob = value
        }

        @objc public func build() throws -> SSKProtoSyncMessageGroups {
            let proto = SignalServiceProtos_SyncMessage.Groups.with { (builder) in
                if let blob = self.blob {
                    builder.blob = blob.asProtobuf
                }
            }

            let wrapper = try SSKProtoSyncMessageGroups.parseProto(proto)
            return wrapper
        }
    }

    @objc public let blob: SSKProtoAttachmentPointer?

    @objc public init(blob: SSKProtoAttachmentPointer?) {
        self.blob = blob
    }

    @objc
    public func serializedData() throws -> Data {
        return try self.asProtobuf.serializedData()
    }

    @objc public class func parseData(_ serializedData: Data) throws -> SSKProtoSyncMessageGroups {
        let proto = try SignalServiceProtos_SyncMessage.Groups(serializedData: serializedData)
        return try parseProto(proto)
    }

    fileprivate class func parseProto(_ proto: SignalServiceProtos_SyncMessage.Groups) throws -> SSKProtoSyncMessageGroups {
        var blob: SSKProtoAttachmentPointer? = nil
        if proto.hasBlob {
            blob = try SSKProtoAttachmentPointer.parseProto(proto.blob)
        }

        // MARK: - Begin Validation Logic for SSKProtoSyncMessageGroups -

        guard proto.hasBlob else {
            throw SSKProtoError.invalidProtobuf(description: "\(logTag) missing required field: blob")
        }

        // MARK: - End Validation Logic for SSKProtoSyncMessageGroups -

        let result = SSKProtoSyncMessageGroups(blob: blob)
        return result
    }

    fileprivate var asProtobuf: SignalServiceProtos_SyncMessage.Groups {
        let proto = SignalServiceProtos_SyncMessage.Groups.with { (builder) in
            if let blob = self.blob {
                builder.blob = blob.asProtobuf
            }
        }

        return proto
    }
}

// MARK: - SSKProtoSyncMessageBlocked

@objc public class SSKProtoSyncMessageBlocked: NSObject {

    // MARK: - SSKProtoSyncMessageBlockedBuilder

    @objc public class SSKProtoSyncMessageBlockedBuilder: NSObject {

        private var numbers: [String]

        @objc public override init() {}

        @objc public func addNumbers(_ value: String) {
            numbers.append(value)
        }

        @objc public func build() throws -> SSKProtoSyncMessageBlocked {
            let proto = SignalServiceProtos_SyncMessage.Blocked.with { (builder) in
                for item in numbers {
                    builder.addNumbers(item)
                }
            }

            let wrapper = try SSKProtoSyncMessageBlocked.parseProto(proto)
            return wrapper
        }
    }

    @objc public let numbers: [String]

    @objc public init(numbers: [String]) {
        self.numbers = numbers
    }

    @objc
    public func serializedData() throws -> Data {
        return try self.asProtobuf.serializedData()
    }

    @objc public class func parseData(_ serializedData: Data) throws -> SSKProtoSyncMessageBlocked {
        let proto = try SignalServiceProtos_SyncMessage.Blocked(serializedData: serializedData)
        return try parseProto(proto)
    }

    fileprivate class func parseProto(_ proto: SignalServiceProtos_SyncMessage.Blocked) throws -> SSKProtoSyncMessageBlocked {
        var numbers: [String] = []
        for item in proto.numbers {
            let wrapped = item
            numbers.append(wrapped)
        }

        // MARK: - Begin Validation Logic for SSKProtoSyncMessageBlocked -

        // MARK: - End Validation Logic for SSKProtoSyncMessageBlocked -

        let result = SSKProtoSyncMessageBlocked(numbers: numbers)
        return result
    }

    fileprivate var asProtobuf: SignalServiceProtos_SyncMessage.Blocked {
        let proto = SignalServiceProtos_SyncMessage.Blocked.with { (builder) in
            var numbersUnwrapped = [String]()
            for item in numbers {
                numbersUnwrapped.append(item)
            }
            builder.numbers = numbersUnwrapped
        }

        return proto
    }
}

// MARK: - SSKProtoSyncMessageRequest

@objc public class SSKProtoSyncMessageRequest: NSObject {

    // MARK: - SSKProtoSyncMessageRequestType

    @objc public enum SSKProtoSyncMessageRequestType: Int32 {
        case unknown = 0
        case contacts = 1
        case groups = 2
        case blocked = 3
        case configuration = 4
    }

    private class func SSKProtoSyncMessageRequestTypeWrap(_ value: SignalServiceProtos_SyncMessage.Request.TypeEnum) -> SSKProtoSyncMessageRequestType {
        switch value {
        case .unknown: return .unknown
        case .contacts: return .contacts
        case .groups: return .groups
        case .blocked: return .blocked
        case .configuration: return .configuration
        }
    }

    private class func SSKProtoSyncMessageRequestTypeUnwrap(_ value: SSKProtoSyncMessageRequestType) -> SignalServiceProtos_SyncMessage.Request.TypeEnum {
        switch value {
        case .unknown: return .unknown
        case .contacts: return .contacts
        case .groups: return .groups
        case .blocked: return .blocked
        case .configuration: return .configuration
        }
    }

    // MARK: - SSKProtoSyncMessageRequestBuilder

    @objc public class SSKProtoSyncMessageRequestBuilder: NSObject {

        private var type: SSKProtoSyncMessageRequestType?

        @objc public override init() {}

        @objc public func setType(_ value: SSKProtoSyncMessageRequestType) {
            type = value
        }

        @objc public func build() throws -> SSKProtoSyncMessageRequest {
            let proto = SignalServiceProtos_SyncMessage.Request.with { (builder) in
                if let type = self.type {
                    builder.type = SSKProtoSyncMessageRequestTypeUnwrap(type)
                }
            }

            let wrapper = try SSKProtoSyncMessageRequest.parseProto(proto)
            return wrapper
        }
    }

    @objc public let type: SSKProtoSyncMessageRequestType

    @objc public init(type: SSKProtoSyncMessageRequestType) {
        self.type = type
    }

    @objc
    public func serializedData() throws -> Data {
        return try self.asProtobuf.serializedData()
    }

    @objc public class func parseData(_ serializedData: Data) throws -> SSKProtoSyncMessageRequest {
        let proto = try SignalServiceProtos_SyncMessage.Request(serializedData: serializedData)
        return try parseProto(proto)
    }

    fileprivate class func parseProto(_ proto: SignalServiceProtos_SyncMessage.Request) throws -> SSKProtoSyncMessageRequest {
        guard proto.hasType else {
            throw SSKProtoError.invalidProtobuf(description: "\(logTag) missing required field: type")
        }
        let type = SSKProtoSyncMessageRequestTypeWrap(proto.type)

        // MARK: - Begin Validation Logic for SSKProtoSyncMessageRequest -

        guard proto.hasType else {
            throw SSKProtoError.invalidProtobuf(description: "\(logTag) missing required field: type")
        }

        // MARK: - End Validation Logic for SSKProtoSyncMessageRequest -

        let result = SSKProtoSyncMessageRequest(type: type)
        return result
    }

    fileprivate var asProtobuf: SignalServiceProtos_SyncMessage.Request {
        let proto = SignalServiceProtos_SyncMessage.Request.with { (builder) in
            builder.type = SSKProtoSyncMessageRequest.SSKProtoSyncMessageRequestTypeUnwrap(self.type)
        }

        return proto
    }
}

// MARK: - SSKProtoSyncMessageRead

@objc public class SSKProtoSyncMessageRead: NSObject {

    // MARK: - SSKProtoSyncMessageReadBuilder

    @objc public class SSKProtoSyncMessageReadBuilder: NSObject {

        private var sender: String?
        private var timestamp: UInt64?

        @objc public override init() {}

        @objc public func setSender(_ value: String) {
            sender = value
        }

        @objc public func setTimestamp(_ value: UInt64) {
            timestamp = value
        }

        @objc public func build() throws -> SSKProtoSyncMessageRead {
            let proto = SignalServiceProtos_SyncMessage.Read.with { (builder) in
                if let sender = self.sender {
                    builder.sender = sender
                }
                if let timestamp = self.timestamp {
                    builder.timestamp = timestamp
                }
            }

            let wrapper = try SSKProtoSyncMessageRead.parseProto(proto)
            return wrapper
        }
    }

    @objc public let sender: String?
    @objc public let timestamp: UInt64

    @objc public init(sender: String?,
                      timestamp: UInt64) {
        self.sender = sender
        self.timestamp = timestamp
    }

    @objc
    public func serializedData() throws -> Data {
        return try self.asProtobuf.serializedData()
    }

    @objc public class func parseData(_ serializedData: Data) throws -> SSKProtoSyncMessageRead {
        let proto = try SignalServiceProtos_SyncMessage.Read(serializedData: serializedData)
        return try parseProto(proto)
    }

    fileprivate class func parseProto(_ proto: SignalServiceProtos_SyncMessage.Read) throws -> SSKProtoSyncMessageRead {
        guard proto.hasSender else {
            throw SSKProtoError.invalidProtobuf(description: "\(logTag) missing required field: sender")
        }
        let sender = proto.sender

        guard proto.hasTimestamp else {
            throw SSKProtoError.invalidProtobuf(description: "\(logTag) missing required field: timestamp")
        }
        let timestamp = proto.timestamp

        // MARK: - Begin Validation Logic for SSKProtoSyncMessageRead -

        guard proto.hasSender else {
            throw SSKProtoError.invalidProtobuf(description: "\(logTag) missing required field: sender")
        }
        guard proto.hasTimestamp else {
            throw SSKProtoError.invalidProtobuf(description: "\(logTag) missing required field: timestamp")
        }

        // MARK: - End Validation Logic for SSKProtoSyncMessageRead -

        let result = SSKProtoSyncMessageRead(sender: sender,
                                             timestamp: timestamp)
        return result
    }

    fileprivate var asProtobuf: SignalServiceProtos_SyncMessage.Read {
        let proto = SignalServiceProtos_SyncMessage.Read.with { (builder) in
            if let sender = self.sender {
                builder.sender = sender
            }

            builder.timestamp = self.timestamp
        }

        return proto
    }
}

// MARK: - SSKProtoSyncMessageConfiguration

@objc public class SSKProtoSyncMessageConfiguration: NSObject {

    // MARK: - SSKProtoSyncMessageConfigurationBuilder

    @objc public class SSKProtoSyncMessageConfigurationBuilder: NSObject {

        private var readReceipts: Bool?

        @objc public override init() {}

        @objc public func setReadReceipts(_ value: Bool) {
            readReceipts = value
        }

        @objc public func build() throws -> SSKProtoSyncMessageConfiguration {
            let proto = SignalServiceProtos_SyncMessage.Configuration.with { (builder) in
                if let readReceipts = self.readReceipts {
                    builder.readReceipts = readReceipts
                }
            }

            let wrapper = try SSKProtoSyncMessageConfiguration.parseProto(proto)
            return wrapper
        }
    }

    @objc public let readReceipts: Bool?

    @objc public init(readReceipts: Bool?) {
        self.readReceipts = readReceipts
    }

    @objc
    public func serializedData() throws -> Data {
        return try self.asProtobuf.serializedData()
    }

    @objc public class func parseData(_ serializedData: Data) throws -> SSKProtoSyncMessageConfiguration {
        let proto = try SignalServiceProtos_SyncMessage.Configuration(serializedData: serializedData)
        return try parseProto(proto)
    }

    fileprivate class func parseProto(_ proto: SignalServiceProtos_SyncMessage.Configuration) throws -> SSKProtoSyncMessageConfiguration {
        var readReceipts: Bool? = nil
        if proto.hasReadReceipts {
            readReceipts = proto.readReceipts
        }

        // MARK: - Begin Validation Logic for SSKProtoSyncMessageConfiguration -

        // MARK: - End Validation Logic for SSKProtoSyncMessageConfiguration -

        let result = SSKProtoSyncMessageConfiguration(readReceipts: readReceipts)
        return result
    }

    fileprivate var asProtobuf: SignalServiceProtos_SyncMessage.Configuration {
        let proto = SignalServiceProtos_SyncMessage.Configuration.with { (builder) in
            if let readReceipts = self.readReceipts {
                builder.readReceipts = readReceipts
            }
        }

        return proto
    }
}

// MARK: - SSKProtoSyncMessage

@objc public class SSKProtoSyncMessage: NSObject {

    // MARK: - SSKProtoSyncMessageBuilder

    @objc public class SSKProtoSyncMessageBuilder: NSObject {

        private var sent: SSKProtoSyncMessageSent?
        private var contacts: SSKProtoSyncMessageContacts?
        private var groups: SSKProtoSyncMessageGroups?
        private var request: SSKProtoSyncMessageRequest?
        private var read: [SSKProtoSyncMessageRead]
        private var blocked: SSKProtoSyncMessageBlocked?
        private var verified: SSKProtoVerified?
        private var configuration: SSKProtoSyncMessageConfiguration?
        private var padding: Data?

        @objc public override init() {}

        @objc public func setSent(_ value: SSKProtoSyncMessageSent) {
            sent = value
        }

        @objc public func setContacts(_ value: SSKProtoSyncMessageContacts) {
            contacts = value
        }

        @objc public func setGroups(_ value: SSKProtoSyncMessageGroups) {
            groups = value
        }

        @objc public func setRequest(_ value: SSKProtoSyncMessageRequest) {
            request = value
        }

        @objc public func addRead(_ value: SSKProtoSyncMessageRead) {
            read.append(value)
        }

        @objc public func setBlocked(_ value: SSKProtoSyncMessageBlocked) {
            blocked = value
        }

        @objc public func setVerified(_ value: SSKProtoVerified) {
            verified = value
        }

        @objc public func setConfiguration(_ value: SSKProtoSyncMessageConfiguration) {
            configuration = value
        }

        @objc public func setPadding(_ value: Data) {
            padding = value
        }

        @objc public func build() throws -> SSKProtoSyncMessage {
            let proto = SignalServiceProtos_SyncMessage.with { (builder) in
                if let sent = self.sent {
                    builder.sent = sent.asProtobuf
                }
                if let contacts = self.contacts {
                    builder.contacts = contacts.asProtobuf
                }
                if let groups = self.groups {
                    builder.groups = groups.asProtobuf
                }
                if let request = self.request {
                    builder.request = request.asProtobuf
                }
                for item in read {
                    builder.addRead(item.asProtobuf)
                }
                if let blocked = self.blocked {
                    builder.blocked = blocked.asProtobuf
                }
                if let verified = self.verified {
                    builder.verified = verified.asProtobuf
                }
                if let configuration = self.configuration {
                    builder.configuration = configuration.asProtobuf
                }
                if let padding = self.padding {
                    builder.padding = padding
                }
            }

            let wrapper = try SSKProtoSyncMessage.parseProto(proto)
            return wrapper
        }
    }

    @objc public let sent: SSKProtoSyncMessageSent?
    @objc public let contacts: SSKProtoSyncMessageContacts?
    @objc public let groups: SSKProtoSyncMessageGroups?
    @objc public let request: SSKProtoSyncMessageRequest?
    @objc public let read: [SSKProtoSyncMessageRead]
    @objc public let blocked: SSKProtoSyncMessageBlocked?
    @objc public let verified: SSKProtoVerified?
    @objc public let configuration: SSKProtoSyncMessageConfiguration?
    @objc public let padding: Data?

    @objc public init(sent: SSKProtoSyncMessageSent?,
                      contacts: SSKProtoSyncMessageContacts?,
                      groups: SSKProtoSyncMessageGroups?,
                      request: SSKProtoSyncMessageRequest?,
                      read: [SSKProtoSyncMessageRead],
                      blocked: SSKProtoSyncMessageBlocked?,
                      verified: SSKProtoVerified?,
                      configuration: SSKProtoSyncMessageConfiguration?,
                      padding: Data?) {
        self.sent = sent
        self.contacts = contacts
        self.groups = groups
        self.request = request
        self.read = read
        self.blocked = blocked
        self.verified = verified
        self.configuration = configuration
        self.padding = padding
    }

    @objc
    public func serializedData() throws -> Data {
        return try self.asProtobuf.serializedData()
    }

    @objc public class func parseData(_ serializedData: Data) throws -> SSKProtoSyncMessage {
        let proto = try SignalServiceProtos_SyncMessage(serializedData: serializedData)
        return try parseProto(proto)
    }

    fileprivate class func parseProto(_ proto: SignalServiceProtos_SyncMessage) throws -> SSKProtoSyncMessage {
        var sent: SSKProtoSyncMessageSent? = nil
        if proto.hasSent {
            sent = try SSKProtoSyncMessageSent.parseProto(proto.sent)
        }

        var contacts: SSKProtoSyncMessageContacts? = nil
        if proto.hasContacts {
            contacts = try SSKProtoSyncMessageContacts.parseProto(proto.contacts)
        }

        var groups: SSKProtoSyncMessageGroups? = nil
        if proto.hasGroups {
            groups = try SSKProtoSyncMessageGroups.parseProto(proto.groups)
        }

        var request: SSKProtoSyncMessageRequest? = nil
        if proto.hasRequest {
            request = try SSKProtoSyncMessageRequest.parseProto(proto.request)
        }

        var read: [SSKProtoSyncMessageRead] = []
        for item in proto.read {
            let wrapped = try SSKProtoSyncMessageRead.parseProto(item)
            read.append(wrapped)
        }

        var blocked: SSKProtoSyncMessageBlocked? = nil
        if proto.hasBlocked {
            blocked = try SSKProtoSyncMessageBlocked.parseProto(proto.blocked)
        }

        var verified: SSKProtoVerified? = nil
        if proto.hasVerified {
            verified = try SSKProtoVerified.parseProto(proto.verified)
        }

        var configuration: SSKProtoSyncMessageConfiguration? = nil
        if proto.hasConfiguration {
            configuration = try SSKProtoSyncMessageConfiguration.parseProto(proto.configuration)
        }

        var padding: Data? = nil
        if proto.hasPadding {
            padding = proto.padding
        }

        // MARK: - Begin Validation Logic for SSKProtoSyncMessage -

        // MARK: - End Validation Logic for SSKProtoSyncMessage -

        let result = SSKProtoSyncMessage(sent: sent,
                                         contacts: contacts,
                                         groups: groups,
                                         request: request,
                                         read: read,
                                         blocked: blocked,
                                         verified: verified,
                                         configuration: configuration,
                                         padding: padding)
        return result
    }

    fileprivate var asProtobuf: SignalServiceProtos_SyncMessage {
        let proto = SignalServiceProtos_SyncMessage.with { (builder) in
            if let sent = self.sent {
                builder.sent = sent.asProtobuf
            }

            if let contacts = self.contacts {
                builder.contacts = contacts.asProtobuf
            }

            if let groups = self.groups {
                builder.groups = groups.asProtobuf
            }

            if let request = self.request {
                builder.request = request.asProtobuf
            }

            var readUnwrapped = [SignalServiceProtos_SyncMessage.Read]()
            for item in read {
                readUnwrapped.append(item.asProtobuf)
            }
            builder.read = readUnwrapped

            if let blocked = self.blocked {
                builder.blocked = blocked.asProtobuf
            }

            if let verified = self.verified {
                builder.verified = verified.asProtobuf
            }

            if let configuration = self.configuration {
                builder.configuration = configuration.asProtobuf
            }

            if let padding = self.padding {
                builder.padding = padding
            }
        }

        return proto
    }
}

// MARK: - SSKProtoAttachmentPointer

@objc public class SSKProtoAttachmentPointer: NSObject {

    // MARK: - SSKProtoAttachmentPointerFlags

    @objc public enum SSKProtoAttachmentPointerFlags: Int32 {
        case voiceMessage = 1
    }

    private class func SSKProtoAttachmentPointerFlagsWrap(_ value: SignalServiceProtos_AttachmentPointer.Flags) -> SSKProtoAttachmentPointerFlags {
        switch value {
        case .voiceMessage: return .voiceMessage
        }
    }

    private class func SSKProtoAttachmentPointerFlagsUnwrap(_ value: SSKProtoAttachmentPointerFlags) -> SignalServiceProtos_AttachmentPointer.Flags {
        switch value {
        case .voiceMessage: return .voiceMessage
        }
    }

    // MARK: - SSKProtoAttachmentPointerBuilder

    @objc public class SSKProtoAttachmentPointerBuilder: NSObject {

        private var id: UInt64?
        private var contentType: String?
        private var key: Data?
        private var size: UInt32?
        private var thumbnail: Data?
        private var digest: Data?
        private var fileName: String?
        private var flags: UInt32?
        private var width: UInt32?
        private var height: UInt32?

        @objc public override init() {}

        @objc public func setId(_ value: UInt64) {
            id = value
        }

        @objc public func setContentType(_ value: String) {
            contentType = value
        }

        @objc public func setKey(_ value: Data) {
            key = value
        }

        @objc public func setSize(_ value: UInt32) {
            size = value
        }

        @objc public func setThumbnail(_ value: Data) {
            thumbnail = value
        }

        @objc public func setDigest(_ value: Data) {
            digest = value
        }

        @objc public func setFileName(_ value: String) {
            fileName = value
        }

        @objc public func setFlags(_ value: UInt32) {
            flags = value
        }

        @objc public func setWidth(_ value: UInt32) {
            width = value
        }

        @objc public func setHeight(_ value: UInt32) {
            height = value
        }

        @objc public func build() throws -> SSKProtoAttachmentPointer {
            let proto = SignalServiceProtos_AttachmentPointer.with { (builder) in
                if let id = self.id {
                    builder.id = id
                }
                if let contentType = self.contentType {
                    builder.contentType = contentType
                }
                if let key = self.key {
                    builder.key = key
                }
                if let size = self.size {
                    builder.size = size
                }
                if let thumbnail = self.thumbnail {
                    builder.thumbnail = thumbnail
                }
                if let digest = self.digest {
                    builder.digest = digest
                }
                if let fileName = self.fileName {
                    builder.fileName = fileName
                }
                if let flags = self.flags {
                    builder.flags = flags
                }
                if let width = self.width {
                    builder.width = width
                }
                if let height = self.height {
                    builder.height = height
                }
            }

            let wrapper = try SSKProtoAttachmentPointer.parseProto(proto)
            return wrapper
        }
    }

    @objc public let id: UInt64
    @objc public let contentType: String?
    @objc public let key: Data?
    @objc public let size: UInt32?
    @objc public let thumbnail: Data?
    @objc public let digest: Data?
    @objc public let fileName: String?
    @objc public let flags: UInt32?
    @objc public let width: UInt32?
    @objc public let height: UInt32?

    @objc public init(id: UInt64,
                      contentType: String?,
                      key: Data?,
                      size: UInt32?,
                      thumbnail: Data?,
                      digest: Data?,
                      fileName: String?,
                      flags: UInt32?,
                      width: UInt32?,
                      height: UInt32?) {
        self.id = id
        self.contentType = contentType
        self.key = key
        self.size = size
        self.thumbnail = thumbnail
        self.digest = digest
        self.fileName = fileName
        self.flags = flags
        self.width = width
        self.height = height
    }

    @objc
    public func serializedData() throws -> Data {
        return try self.asProtobuf.serializedData()
    }

    @objc public class func parseData(_ serializedData: Data) throws -> SSKProtoAttachmentPointer {
        let proto = try SignalServiceProtos_AttachmentPointer(serializedData: serializedData)
        return try parseProto(proto)
    }

    fileprivate class func parseProto(_ proto: SignalServiceProtos_AttachmentPointer) throws -> SSKProtoAttachmentPointer {
        guard proto.hasID else {
            throw SSKProtoError.invalidProtobuf(description: "\(logTag) missing required field: id")
        }
        let id = proto.id

        var contentType: String? = nil
        if proto.hasContentType {
            contentType = proto.contentType
        }

        var key: Data? = nil
        if proto.hasKey {
            key = proto.key
        }

        var size: UInt32? = nil
        if proto.hasSize {
            size = proto.size
        }

        var thumbnail: Data? = nil
        if proto.hasThumbnail {
            thumbnail = proto.thumbnail
        }

        var digest: Data? = nil
        if proto.hasDigest {
            digest = proto.digest
        }

        var fileName: String? = nil
        if proto.hasFileName {
            fileName = proto.fileName
        }

        var flags: UInt32? = nil
        if proto.hasFlags {
            flags = proto.flags
        }

        var width: UInt32? = nil
        if proto.hasWidth {
            width = proto.width
        }

        var height: UInt32? = nil
        if proto.hasHeight {
            height = proto.height
        }

        // MARK: - Begin Validation Logic for SSKProtoAttachmentPointer -

        guard proto.hasID else {
            throw SSKProtoError.invalidProtobuf(description: "\(logTag) missing required field: id")
        }

        // MARK: - End Validation Logic for SSKProtoAttachmentPointer -

        let result = SSKProtoAttachmentPointer(id: id,
                                               contentType: contentType,
                                               key: key,
                                               size: size,
                                               thumbnail: thumbnail,
                                               digest: digest,
                                               fileName: fileName,
                                               flags: flags,
                                               width: width,
                                               height: height)
        return result
    }

    fileprivate var asProtobuf: SignalServiceProtos_AttachmentPointer {
        let proto = SignalServiceProtos_AttachmentPointer.with { (builder) in
            builder.id = self.id

            if let contentType = self.contentType {
                builder.contentType = contentType
            }

            if let key = self.key {
                builder.key = key
            }

            if let size = self.size {
                builder.size = size
            }

            if let thumbnail = self.thumbnail {
                builder.thumbnail = thumbnail
            }

            if let digest = self.digest {
                builder.digest = digest
            }

            if let fileName = self.fileName {
                builder.fileName = fileName
            }

            if let flags = self.flags {
                builder.flags = flags
            }

            if let width = self.width {
                builder.width = width
            }

            if let height = self.height {
                builder.height = height
            }
        }

        return proto
    }
}

// MARK: - SSKProtoGroupContext

@objc public class SSKProtoGroupContext: NSObject {

    // MARK: - SSKProtoGroupContextType

    @objc public enum SSKProtoGroupContextType: Int32 {
        case unknown = 0
        case update = 1
        case deliver = 2
        case quit = 3
        case requestInfo = 4
    }

    private class func SSKProtoGroupContextTypeWrap(_ value: SignalServiceProtos_GroupContext.TypeEnum) -> SSKProtoGroupContextType {
        switch value {
        case .unknown: return .unknown
        case .update: return .update
        case .deliver: return .deliver
        case .quit: return .quit
        case .requestInfo: return .requestInfo
        }
    }

    private class func SSKProtoGroupContextTypeUnwrap(_ value: SSKProtoGroupContextType) -> SignalServiceProtos_GroupContext.TypeEnum {
        switch value {
        case .unknown: return .unknown
        case .update: return .update
        case .deliver: return .deliver
        case .quit: return .quit
        case .requestInfo: return .requestInfo
        }
    }

    // MARK: - SSKProtoGroupContextBuilder

    @objc public class SSKProtoGroupContextBuilder: NSObject {

        private var id: Data?
        private var type: SSKProtoGroupContextType?
        private var name: String?
        private var members: [String]
        private var avatar: SSKProtoAttachmentPointer?

        @objc public override init() {}

        @objc public func setId(_ value: Data) {
            id = value
        }

        @objc public func setType(_ value: SSKProtoGroupContextType) {
            type = value
        }

        @objc public func setName(_ value: String) {
            name = value
        }

        @objc public func addMembers(_ value: String) {
            members.append(value)
        }

        @objc public func setAvatar(_ value: SSKProtoAttachmentPointer) {
            avatar = value
        }

        @objc public func build() throws -> SSKProtoGroupContext {
            let proto = SignalServiceProtos_GroupContext.with { (builder) in
                if let id = self.id {
                    builder.id = id
                }
                if let type = self.type {
                    builder.type = SSKProtoGroupContextTypeUnwrap(type)
                }
                if let name = self.name {
                    builder.name = name
                }
                for item in members {
                    builder.addMembers(item)
                }
                if let avatar = self.avatar {
                    builder.avatar = avatar.asProtobuf
                }
            }

            let wrapper = try SSKProtoGroupContext.parseProto(proto)
            return wrapper
        }
    }

    @objc public let id: Data?
    @objc public let type: SSKProtoGroupContextType
    @objc public let name: String?
    @objc public let members: [String]
    @objc public let avatar: SSKProtoAttachmentPointer?

    @objc public init(id: Data?,
                      type: SSKProtoGroupContextType,
                      name: String?,
                      members: [String],
                      avatar: SSKProtoAttachmentPointer?) {
        self.id = id
        self.type = type
        self.name = name
        self.members = members
        self.avatar = avatar
    }

    @objc
    public func serializedData() throws -> Data {
        return try self.asProtobuf.serializedData()
    }

    @objc public class func parseData(_ serializedData: Data) throws -> SSKProtoGroupContext {
        let proto = try SignalServiceProtos_GroupContext(serializedData: serializedData)
        return try parseProto(proto)
    }

    fileprivate class func parseProto(_ proto: SignalServiceProtos_GroupContext) throws -> SSKProtoGroupContext {
        guard proto.hasID else {
            throw SSKProtoError.invalidProtobuf(description: "\(logTag) missing required field: id")
        }
        let id = proto.id

        guard proto.hasType else {
            throw SSKProtoError.invalidProtobuf(description: "\(logTag) missing required field: type")
        }
        let type = SSKProtoGroupContextTypeWrap(proto.type)

        var name: String? = nil
        if proto.hasName {
            name = proto.name
        }

        var members: [String] = []
        for item in proto.members {
            let wrapped = item
            members.append(wrapped)
        }

        var avatar: SSKProtoAttachmentPointer? = nil
        if proto.hasAvatar {
            avatar = try SSKProtoAttachmentPointer.parseProto(proto.avatar)
        }

        // MARK: - Begin Validation Logic for SSKProtoGroupContext -

        guard proto.hasID else {
            throw SSKProtoError.invalidProtobuf(description: "\(logTag) missing required field: id")
        }
        guard proto.hasType else {
            throw SSKProtoError.invalidProtobuf(description: "\(logTag) missing required field: type")
        }

        // MARK: - End Validation Logic for SSKProtoGroupContext -

        let result = SSKProtoGroupContext(id: id,
                                          type: type,
                                          name: name,
                                          members: members,
                                          avatar: avatar)
        return result
    }

    fileprivate var asProtobuf: SignalServiceProtos_GroupContext {
        let proto = SignalServiceProtos_GroupContext.with { (builder) in
            if let id = self.id {
                builder.id = id
            }

            builder.type = SSKProtoGroupContext.SSKProtoGroupContextTypeUnwrap(self.type)

            if let name = self.name {
                builder.name = name
            }

            var membersUnwrapped = [String]()
            for item in members {
                membersUnwrapped.append(item)
            }
            builder.members = membersUnwrapped

            if let avatar = self.avatar {
                builder.avatar = avatar.asProtobuf
            }
        }

        return proto
    }
}

// MARK: - SSKProtoContactDetailsAvatar

@objc public class SSKProtoContactDetailsAvatar: NSObject {

    // MARK: - SSKProtoContactDetailsAvatarBuilder

    @objc public class SSKProtoContactDetailsAvatarBuilder: NSObject {

        private var contentType: String?
        private var length: UInt32?

        @objc public override init() {}

        @objc public func setContentType(_ value: String) {
            contentType = value
        }

        @objc public func setLength(_ value: UInt32) {
            length = value
        }

        @objc public func build() throws -> SSKProtoContactDetailsAvatar {
            let proto = SignalServiceProtos_ContactDetails.Avatar.with { (builder) in
                if let contentType = self.contentType {
                    builder.contentType = contentType
                }
                if let length = self.length {
                    builder.length = length
                }
            }

            let wrapper = try SSKProtoContactDetailsAvatar.parseProto(proto)
            return wrapper
        }
    }

    @objc public let contentType: String?
    @objc public let length: UInt32?

    @objc public init(contentType: String?,
                      length: UInt32?) {
        self.contentType = contentType
        self.length = length
    }

    @objc
    public func serializedData() throws -> Data {
        return try self.asProtobuf.serializedData()
    }

    @objc public class func parseData(_ serializedData: Data) throws -> SSKProtoContactDetailsAvatar {
        let proto = try SignalServiceProtos_ContactDetails.Avatar(serializedData: serializedData)
        return try parseProto(proto)
    }

    fileprivate class func parseProto(_ proto: SignalServiceProtos_ContactDetails.Avatar) throws -> SSKProtoContactDetailsAvatar {
        var contentType: String? = nil
        if proto.hasContentType {
            contentType = proto.contentType
        }

        var length: UInt32? = nil
        if proto.hasLength {
            length = proto.length
        }

        // MARK: - Begin Validation Logic for SSKProtoContactDetailsAvatar -

        // MARK: - End Validation Logic for SSKProtoContactDetailsAvatar -

        let result = SSKProtoContactDetailsAvatar(contentType: contentType,
                                                  length: length)
        return result
    }

    fileprivate var asProtobuf: SignalServiceProtos_ContactDetails.Avatar {
        let proto = SignalServiceProtos_ContactDetails.Avatar.with { (builder) in
            if let contentType = self.contentType {
                builder.contentType = contentType
            }

            if let length = self.length {
                builder.length = length
            }
        }

        return proto
    }
}

// MARK: - SSKProtoContactDetails

@objc public class SSKProtoContactDetails: NSObject {

    // MARK: - SSKProtoContactDetailsBuilder

    @objc public class SSKProtoContactDetailsBuilder: NSObject {

        private var number: String?
        private var name: String?
        private var avatar: SSKProtoContactDetailsAvatar?
        private var color: String?
        private var verified: SSKProtoVerified?
        private var profileKey: Data?
        private var blocked: Bool?
        private var expireTimer: UInt32?

        @objc public override init() {}

        @objc public func setNumber(_ value: String) {
            number = value
        }

        @objc public func setName(_ value: String) {
            name = value
        }

        @objc public func setAvatar(_ value: SSKProtoContactDetailsAvatar) {
            avatar = value
        }

        @objc public func setColor(_ value: String) {
            color = value
        }

        @objc public func setVerified(_ value: SSKProtoVerified) {
            verified = value
        }

        @objc public func setProfileKey(_ value: Data) {
            profileKey = value
        }

        @objc public func setBlocked(_ value: Bool) {
            blocked = value
        }

        @objc public func setExpireTimer(_ value: UInt32) {
            expireTimer = value
        }

        @objc public func build() throws -> SSKProtoContactDetails {
            let proto = SignalServiceProtos_ContactDetails.with { (builder) in
                if let number = self.number {
                    builder.number = number
                }
                if let name = self.name {
                    builder.name = name
                }
                if let avatar = self.avatar {
                    builder.avatar = avatar.asProtobuf
                }
                if let color = self.color {
                    builder.color = color
                }
                if let verified = self.verified {
                    builder.verified = verified.asProtobuf
                }
                if let profileKey = self.profileKey {
                    builder.profileKey = profileKey
                }
                if let blocked = self.blocked {
                    builder.blocked = blocked
                }
                if let expireTimer = self.expireTimer {
                    builder.expireTimer = expireTimer
                }
            }

            let wrapper = try SSKProtoContactDetails.parseProto(proto)
            return wrapper
        }
    }

    @objc public let number: String?
    @objc public let name: String?
    @objc public let avatar: SSKProtoContactDetailsAvatar?
    @objc public let color: String?
    @objc public let verified: SSKProtoVerified?
    @objc public let profileKey: Data?
    @objc public let blocked: Bool?
    @objc public let expireTimer: UInt32?

    @objc public init(number: String?,
                      name: String?,
                      avatar: SSKProtoContactDetailsAvatar?,
                      color: String?,
                      verified: SSKProtoVerified?,
                      profileKey: Data?,
                      blocked: Bool?,
                      expireTimer: UInt32?) {
        self.number = number
        self.name = name
        self.avatar = avatar
        self.color = color
        self.verified = verified
        self.profileKey = profileKey
        self.blocked = blocked
        self.expireTimer = expireTimer
    }

    @objc
    public func serializedData() throws -> Data {
        return try self.asProtobuf.serializedData()
    }

    @objc public class func parseData(_ serializedData: Data) throws -> SSKProtoContactDetails {
        let proto = try SignalServiceProtos_ContactDetails(serializedData: serializedData)
        return try parseProto(proto)
    }

    fileprivate class func parseProto(_ proto: SignalServiceProtos_ContactDetails) throws -> SSKProtoContactDetails {
        guard proto.hasNumber else {
            throw SSKProtoError.invalidProtobuf(description: "\(logTag) missing required field: number")
        }
        let number = proto.number

        var name: String? = nil
        if proto.hasName {
            name = proto.name
        }

        var avatar: SSKProtoContactDetailsAvatar? = nil
        if proto.hasAvatar {
            avatar = try SSKProtoContactDetailsAvatar.parseProto(proto.avatar)
        }

        var color: String? = nil
        if proto.hasColor {
            color = proto.color
        }

        var verified: SSKProtoVerified? = nil
        if proto.hasVerified {
            verified = try SSKProtoVerified.parseProto(proto.verified)
        }

        var profileKey: Data? = nil
        if proto.hasProfileKey {
            profileKey = proto.profileKey
        }

        var blocked: Bool? = nil
        if proto.hasBlocked {
            blocked = proto.blocked
        }

        var expireTimer: UInt32? = nil
        if proto.hasExpireTimer {
            expireTimer = proto.expireTimer
        }

        // MARK: - Begin Validation Logic for SSKProtoContactDetails -

        guard proto.hasNumber else {
            throw SSKProtoError.invalidProtobuf(description: "\(logTag) missing required field: number")
        }

        // MARK: - End Validation Logic for SSKProtoContactDetails -

        let result = SSKProtoContactDetails(number: number,
                                            name: name,
                                            avatar: avatar,
                                            color: color,
                                            verified: verified,
                                            profileKey: profileKey,
                                            blocked: blocked,
                                            expireTimer: expireTimer)
        return result
    }

    fileprivate var asProtobuf: SignalServiceProtos_ContactDetails {
        let proto = SignalServiceProtos_ContactDetails.with { (builder) in
            if let number = self.number {
                builder.number = number
            }

            if let name = self.name {
                builder.name = name
            }

            if let avatar = self.avatar {
                builder.avatar = avatar.asProtobuf
            }

            if let color = self.color {
                builder.color = color
            }

            if let verified = self.verified {
                builder.verified = verified.asProtobuf
            }

            if let profileKey = self.profileKey {
                builder.profileKey = profileKey
            }

            if let blocked = self.blocked {
                builder.blocked = blocked
            }

            if let expireTimer = self.expireTimer {
                builder.expireTimer = expireTimer
            }
        }

        return proto
    }
}

// MARK: - SSKProtoGroupDetailsAvatar

@objc public class SSKProtoGroupDetailsAvatar: NSObject {

    // MARK: - SSKProtoGroupDetailsAvatarBuilder

    @objc public class SSKProtoGroupDetailsAvatarBuilder: NSObject {

        private var contentType: String?
        private var length: UInt32?

        @objc public override init() {}

        @objc public func setContentType(_ value: String) {
            contentType = value
        }

        @objc public func setLength(_ value: UInt32) {
            length = value
        }

        @objc public func build() throws -> SSKProtoGroupDetailsAvatar {
            let proto = SignalServiceProtos_GroupDetails.Avatar.with { (builder) in
                if let contentType = self.contentType {
                    builder.contentType = contentType
                }
                if let length = self.length {
                    builder.length = length
                }
            }

            let wrapper = try SSKProtoGroupDetailsAvatar.parseProto(proto)
            return wrapper
        }
    }

    @objc public let contentType: String?
    @objc public let length: UInt32?

    @objc public init(contentType: String?,
                      length: UInt32?) {
        self.contentType = contentType
        self.length = length
    }

    @objc
    public func serializedData() throws -> Data {
        return try self.asProtobuf.serializedData()
    }

    @objc public class func parseData(_ serializedData: Data) throws -> SSKProtoGroupDetailsAvatar {
        let proto = try SignalServiceProtos_GroupDetails.Avatar(serializedData: serializedData)
        return try parseProto(proto)
    }

    fileprivate class func parseProto(_ proto: SignalServiceProtos_GroupDetails.Avatar) throws -> SSKProtoGroupDetailsAvatar {
        var contentType: String? = nil
        if proto.hasContentType {
            contentType = proto.contentType
        }

        var length: UInt32? = nil
        if proto.hasLength {
            length = proto.length
        }

        // MARK: - Begin Validation Logic for SSKProtoGroupDetailsAvatar -

        // MARK: - End Validation Logic for SSKProtoGroupDetailsAvatar -

        let result = SSKProtoGroupDetailsAvatar(contentType: contentType,
                                                length: length)
        return result
    }

    fileprivate var asProtobuf: SignalServiceProtos_GroupDetails.Avatar {
        let proto = SignalServiceProtos_GroupDetails.Avatar.with { (builder) in
            if let contentType = self.contentType {
                builder.contentType = contentType
            }

            if let length = self.length {
                builder.length = length
            }
        }

        return proto
    }
}

// MARK: - SSKProtoGroupDetails

@objc public class SSKProtoGroupDetails: NSObject {

    // MARK: - SSKProtoGroupDetailsBuilder

    @objc public class SSKProtoGroupDetailsBuilder: NSObject {

        private var id: Data?
        private var name: String?
        private var members: [String]
        private var avatar: SSKProtoGroupDetailsAvatar?
        private var active: Bool?
        private var expireTimer: UInt32?
        private var color: String?

        @objc public override init() {}

        @objc public func setId(_ value: Data) {
            id = value
        }

        @objc public func setName(_ value: String) {
            name = value
        }

        @objc public func addMembers(_ value: String) {
            members.append(value)
        }

        @objc public func setAvatar(_ value: SSKProtoGroupDetailsAvatar) {
            avatar = value
        }

        @objc public func setActive(_ value: Bool) {
            active = value
        }

        @objc public func setExpireTimer(_ value: UInt32) {
            expireTimer = value
        }

        @objc public func setColor(_ value: String) {
            color = value
        }

        @objc public func build() throws -> SSKProtoGroupDetails {
            let proto = SignalServiceProtos_GroupDetails.with { (builder) in
                if let id = self.id {
                    builder.id = id
                }
                if let name = self.name {
                    builder.name = name
                }
                for item in members {
                    builder.addMembers(item)
                }
                if let avatar = self.avatar {
                    builder.avatar = avatar.asProtobuf
                }
                if let active = self.active {
                    builder.active = active
                }
                if let expireTimer = self.expireTimer {
                    builder.expireTimer = expireTimer
                }
                if let color = self.color {
                    builder.color = color
                }
            }

            let wrapper = try SSKProtoGroupDetails.parseProto(proto)
            return wrapper
        }
    }

    @objc public let id: Data?
    @objc public let name: String?
    @objc public let members: [String]
    @objc public let avatar: SSKProtoGroupDetailsAvatar?
    @objc public let active: Bool?
    @objc public let expireTimer: UInt32?
    @objc public let color: String?

    @objc public init(id: Data?,
                      name: String?,
                      members: [String],
                      avatar: SSKProtoGroupDetailsAvatar?,
                      active: Bool?,
                      expireTimer: UInt32?,
                      color: String?) {
        self.id = id
        self.name = name
        self.members = members
        self.avatar = avatar
        self.active = active
        self.expireTimer = expireTimer
        self.color = color
    }

    @objc
    public func serializedData() throws -> Data {
        return try self.asProtobuf.serializedData()
    }

    @objc public class func parseData(_ serializedData: Data) throws -> SSKProtoGroupDetails {
        let proto = try SignalServiceProtos_GroupDetails(serializedData: serializedData)
        return try parseProto(proto)
    }

    fileprivate class func parseProto(_ proto: SignalServiceProtos_GroupDetails) throws -> SSKProtoGroupDetails {
        guard proto.hasID else {
            throw SSKProtoError.invalidProtobuf(description: "\(logTag) missing required field: id")
        }
        let id = proto.id

        var name: String? = nil
        if proto.hasName {
            name = proto.name
        }

        var members: [String] = []
        for item in proto.members {
            let wrapped = item
            members.append(wrapped)
        }

        var avatar: SSKProtoGroupDetailsAvatar? = nil
        if proto.hasAvatar {
            avatar = try SSKProtoGroupDetailsAvatar.parseProto(proto.avatar)
        }

        var active: Bool? = true
        if proto.hasActive {
            active = proto.active
        }

        var expireTimer: UInt32? = nil
        if proto.hasExpireTimer {
            expireTimer = proto.expireTimer
        }

        var color: String? = nil
        if proto.hasColor {
            color = proto.color
        }

        // MARK: - Begin Validation Logic for SSKProtoGroupDetails -

        guard proto.hasID else {
            throw SSKProtoError.invalidProtobuf(description: "\(logTag) missing required field: id")
        }

        // MARK: - End Validation Logic for SSKProtoGroupDetails -

        let result = SSKProtoGroupDetails(id: id,
                                          name: name,
                                          members: members,
                                          avatar: avatar,
                                          active: active,
                                          expireTimer: expireTimer,
                                          color: color)
        return result
    }

    fileprivate var asProtobuf: SignalServiceProtos_GroupDetails {
        let proto = SignalServiceProtos_GroupDetails.with { (builder) in
            if let id = self.id {
                builder.id = id
            }

            if let name = self.name {
                builder.name = name
            }

            var membersUnwrapped = [String]()
            for item in members {
                membersUnwrapped.append(item)
            }
            builder.members = membersUnwrapped

            if let avatar = self.avatar {
                builder.avatar = avatar.asProtobuf
            }

            if let active = self.active {
                builder.active = active
            }

            if let expireTimer = self.expireTimer {
                builder.expireTimer = expireTimer
            }

            if let color = self.color {
                builder.color = color
            }
        }

        return proto
    }
}
