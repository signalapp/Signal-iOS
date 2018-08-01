//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

import Foundation

// WARNING: This code is generated. Only edit within the markers.

public enum SSKProtoError: Error {
    case invalidProtobuf(description: String)
    case invalidProtoAccess(description: String)
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

        @objc public func setType(_ _value: SSKProtoEnvelopeType) {
            type = _value
        }

        @objc public func setSource(_ _value: String) {
            source = _value
        }

        @objc public func setSourceDevice(_ _value: UInt32) {
            sourceDevice = _value
        }

        @objc public func setRelay(_ _value: String) {
            relay = _value
        }

        @objc public func setTimestamp(_ _value: UInt64) {
            timestamp = _value
        }

        @objc public func setLegacyMessage(_ _value: Data) {
            legacyMessage = _value
        }

        @objc public func setContent(_ _value: Data) {
            content = _value
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

    fileprivate let proto: SignalServiceProtos_Envelope

    @objc public let type: SSKProtoEnvelopeType
    @objc public let source: String
    @objc public let sourceDevice: UInt32
    @objc public let timestamp: UInt64

    @objc public var relay: String {
        return proto.relay
    }
    @objc public var hasRelay: Bool {
        return proto.hasRelay
    }

    @objc public var legacyMessage: Data {
        return proto.legacyMessage
    }
    @objc public var hasLegacyMessage: Bool {
        return proto.hasLegacyMessage
    }

    @objc public var content: Data {
        return proto.content
    }
    @objc public var hasContent: Bool {
        return proto.hasContent
    }

    private init(proto: SignalServiceProtos_Envelope,
                 type: SSKProtoEnvelopeType,
                 source: String,
                 sourceDevice: UInt32,
                 timestamp: UInt64) {
        self.proto = proto
        self.type = type
        self.source = source
        self.sourceDevice = sourceDevice
        self.timestamp = timestamp
    }

    @objc
    public func serializedData() throws -> Data {
        return try self.proto.serializedData()
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

        guard proto.hasTimestamp else {
            throw SSKProtoError.invalidProtobuf(description: "\(logTag) missing required field: timestamp")
        }
        let timestamp = proto.timestamp

        // MARK: - Begin Validation Logic for SSKProtoEnvelope -

        // MARK: - End Validation Logic for SSKProtoEnvelope -

        let result = SSKProtoEnvelope(proto: proto,
                                      type: type,
                                      source: source,
                                      sourceDevice: sourceDevice,
                                      timestamp: timestamp)
        return result
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

        @objc public func setDataMessage(_ _value: SSKProtoDataMessage) {
            dataMessage = _value
        }

        @objc public func setSyncMessage(_ _value: SSKProtoSyncMessage) {
            syncMessage = _value
        }

        @objc public func setCallMessage(_ _value: SSKProtoCallMessage) {
            callMessage = _value
        }

        @objc public func setNullMessage(_ _value: SSKProtoNullMessage) {
            nullMessage = _value
        }

        @objc public func setReceiptMessage(_ _value: SSKProtoReceiptMessage) {
            receiptMessage = _value
        }

        @objc public func build() throws -> SSKProtoContent {
            let proto = SignalServiceProtos_Content.with { (builder) in
                if let dataMessage = self.dataMessage {
                    builder.dataMessage = dataMessage.proto
                }

                if let syncMessage = self.syncMessage {
                    builder.syncMessage = syncMessage.proto
                }

                if let callMessage = self.callMessage {
                    builder.callMessage = callMessage.proto
                }

                if let nullMessage = self.nullMessage {
                    builder.nullMessage = nullMessage.proto
                }

                if let receiptMessage = self.receiptMessage {
                    builder.receiptMessage = receiptMessage.proto
                }
            }

            let wrapper = try SSKProtoContent.parseProto(proto)
            return wrapper
        }
    }

    fileprivate let proto: SignalServiceProtos_Content

    @objc public let dataMessage: SSKProtoDataMessage?
    @objc public let syncMessage: SSKProtoSyncMessage?
    @objc public let callMessage: SSKProtoCallMessage?
    @objc public let nullMessage: SSKProtoNullMessage?
    @objc public let receiptMessage: SSKProtoReceiptMessage?

    private init(proto: SignalServiceProtos_Content,
                 dataMessage: SSKProtoDataMessage?,
                 syncMessage: SSKProtoSyncMessage?,
                 callMessage: SSKProtoCallMessage?,
                 nullMessage: SSKProtoNullMessage?,
                 receiptMessage: SSKProtoReceiptMessage?) {
        self.proto = proto
        self.dataMessage = dataMessage
        self.syncMessage = syncMessage
        self.callMessage = callMessage
        self.nullMessage = nullMessage
        self.receiptMessage = receiptMessage
    }

    @objc
    public func serializedData() throws -> Data {
        return try self.proto.serializedData()
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

        let result = SSKProtoContent(proto: proto,
                                     dataMessage: dataMessage,
                                     syncMessage: syncMessage,
                                     callMessage: callMessage,
                                     nullMessage: nullMessage,
                                     receiptMessage: receiptMessage)
        return result
    }
}

// MARK: - SSKProtoCallMessageOffer

@objc public class SSKProtoCallMessageOffer: NSObject {

    // MARK: - SSKProtoCallMessageOfferBuilder

    @objc public class SSKProtoCallMessageOfferBuilder: NSObject {

        private var id: UInt64?
        private var sessionDescription: String?

        @objc public override init() {}

        @objc public func setId(_ _value: UInt64) {
            id = _value
        }

        @objc public func setSessionDescription(_ _value: String) {
            sessionDescription = _value
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

    fileprivate let proto: SignalServiceProtos_CallMessage.Offer

    @objc public let id: UInt64

    @objc public var sessionDescription: String {
        return proto.sessionDescription
    }
    @objc public var hasSessionDescription: Bool {
        return proto.hasSessionDescription
    }

    private init(proto: SignalServiceProtos_CallMessage.Offer,
                 id: UInt64) {
        self.proto = proto
        self.id = id
    }

    @objc
    public func serializedData() throws -> Data {
        return try self.proto.serializedData()
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

        // MARK: - Begin Validation Logic for SSKProtoCallMessageOffer -

        // MARK: - End Validation Logic for SSKProtoCallMessageOffer -

        let result = SSKProtoCallMessageOffer(proto: proto,
                                              id: id)
        return result
    }
}

// MARK: - SSKProtoCallMessageAnswer

@objc public class SSKProtoCallMessageAnswer: NSObject {

    // MARK: - SSKProtoCallMessageAnswerBuilder

    @objc public class SSKProtoCallMessageAnswerBuilder: NSObject {

        private var id: UInt64?
        private var sessionDescription: String?

        @objc public override init() {}

        @objc public func setId(_ _value: UInt64) {
            id = _value
        }

        @objc public func setSessionDescription(_ _value: String) {
            sessionDescription = _value
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

    fileprivate let proto: SignalServiceProtos_CallMessage.Answer

    @objc public let id: UInt64

    @objc public var sessionDescription: String {
        return proto.sessionDescription
    }
    @objc public var hasSessionDescription: Bool {
        return proto.hasSessionDescription
    }

    private init(proto: SignalServiceProtos_CallMessage.Answer,
                 id: UInt64) {
        self.proto = proto
        self.id = id
    }

    @objc
    public func serializedData() throws -> Data {
        return try self.proto.serializedData()
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

        // MARK: - Begin Validation Logic for SSKProtoCallMessageAnswer -

        // MARK: - End Validation Logic for SSKProtoCallMessageAnswer -

        let result = SSKProtoCallMessageAnswer(proto: proto,
                                               id: id)
        return result
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

        @objc public func setId(_ _value: UInt64) {
            id = _value
        }

        @objc public func setSdpMid(_ _value: String) {
            sdpMid = _value
        }

        @objc public func setSdpMlineIndex(_ _value: UInt32) {
            sdpMlineIndex = _value
        }

        @objc public func setSdp(_ _value: String) {
            sdp = _value
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

    fileprivate let proto: SignalServiceProtos_CallMessage.IceUpdate

    @objc public let id: UInt64

    @objc public var sdpMid: String {
        return proto.sdpMid
    }
    @objc public var hasSdpMid: Bool {
        return proto.hasSdpMid
    }

    @objc public var sdpMlineIndex: UInt32 {
        return proto.sdpMlineIndex
    }
    @objc public var hasSdpMlineIndex: Bool {
        return proto.hasSdpMlineIndex
    }

    @objc public var sdp: String {
        return proto.sdp
    }
    @objc public var hasSdp: Bool {
        return proto.hasSdp
    }

    private init(proto: SignalServiceProtos_CallMessage.IceUpdate,
                 id: UInt64) {
        self.proto = proto
        self.id = id
    }

    @objc
    public func serializedData() throws -> Data {
        return try self.proto.serializedData()
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

        // MARK: - Begin Validation Logic for SSKProtoCallMessageIceUpdate -

        // MARK: - End Validation Logic for SSKProtoCallMessageIceUpdate -

        let result = SSKProtoCallMessageIceUpdate(proto: proto,
                                                  id: id)
        return result
    }
}

// MARK: - SSKProtoCallMessageBusy

@objc public class SSKProtoCallMessageBusy: NSObject {

    // MARK: - SSKProtoCallMessageBusyBuilder

    @objc public class SSKProtoCallMessageBusyBuilder: NSObject {

        private var id: UInt64?

        @objc public override init() {}

        @objc public func setId(_ _value: UInt64) {
            id = _value
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

    fileprivate let proto: SignalServiceProtos_CallMessage.Busy

    @objc public let id: UInt64

    private init(proto: SignalServiceProtos_CallMessage.Busy,
                 id: UInt64) {
        self.proto = proto
        self.id = id
    }

    @objc
    public func serializedData() throws -> Data {
        return try self.proto.serializedData()
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

        let result = SSKProtoCallMessageBusy(proto: proto,
                                             id: id)
        return result
    }
}

// MARK: - SSKProtoCallMessageHangup

@objc public class SSKProtoCallMessageHangup: NSObject {

    // MARK: - SSKProtoCallMessageHangupBuilder

    @objc public class SSKProtoCallMessageHangupBuilder: NSObject {

        private var id: UInt64?

        @objc public override init() {}

        @objc public func setId(_ _value: UInt64) {
            id = _value
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

    fileprivate let proto: SignalServiceProtos_CallMessage.Hangup

    @objc public let id: UInt64

    private init(proto: SignalServiceProtos_CallMessage.Hangup,
                 id: UInt64) {
        self.proto = proto
        self.id = id
    }

    @objc
    public func serializedData() throws -> Data {
        return try self.proto.serializedData()
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

        let result = SSKProtoCallMessageHangup(proto: proto,
                                               id: id)
        return result
    }
}

// MARK: - SSKProtoCallMessage

@objc public class SSKProtoCallMessage: NSObject {

    // MARK: - SSKProtoCallMessageBuilder

    @objc public class SSKProtoCallMessageBuilder: NSObject {

        private var offer: SSKProtoCallMessageOffer?
        private var answer: SSKProtoCallMessageAnswer?
        private var iceUpdate: [SSKProtoCallMessageIceUpdate] = []
        private var hangup: SSKProtoCallMessageHangup?
        private var busy: SSKProtoCallMessageBusy?
        private var profileKey: Data?

        @objc public override init() {}

        @objc public func setOffer(_ _value: SSKProtoCallMessageOffer) {
            offer = _value
        }

        @objc public func setAnswer(_ _value: SSKProtoCallMessageAnswer) {
            answer = _value
        }

        @objc public func addIceUpdate(_ _value: SSKProtoCallMessageIceUpdate) {
            iceUpdate.append(_value)
        }

        @objc public func setHangup(_ _value: SSKProtoCallMessageHangup) {
            hangup = _value
        }

        @objc public func setBusy(_ _value: SSKProtoCallMessageBusy) {
            busy = _value
        }

        @objc public func setProfileKey(_ _value: Data) {
            profileKey = _value
        }

        @objc public func build() throws -> SSKProtoCallMessage {
            let proto = SignalServiceProtos_CallMessage.with { (builder) in
                if let offer = self.offer {
                    builder.offer = offer.proto
                }

                if let answer = self.answer {
                    builder.answer = answer.proto
                }

                var iceUpdateWrapped: [SignalServiceProtos_CallMessage.IceUpdate] = []
                for item in iceUpdate {
                    iceUpdateWrapped.append(item.proto)
                }
                builder.iceUpdate = iceUpdateWrapped

                if let hangup = self.hangup {
                    builder.hangup = hangup.proto
                }

                if let busy = self.busy {
                    builder.busy = busy.proto
                }

                if let profileKey = self.profileKey {
                    builder.profileKey = profileKey
                }
            }

            let wrapper = try SSKProtoCallMessage.parseProto(proto)
            return wrapper
        }
    }

    fileprivate let proto: SignalServiceProtos_CallMessage

    @objc public let offer: SSKProtoCallMessageOffer?
    @objc public let answer: SSKProtoCallMessageAnswer?
    @objc public let iceUpdate: [SSKProtoCallMessageIceUpdate]
    @objc public let hangup: SSKProtoCallMessageHangup?
    @objc public let busy: SSKProtoCallMessageBusy?

    @objc public var profileKey: Data {
        return proto.profileKey
    }
    @objc public var hasProfileKey: Bool {
        return proto.hasProfileKey
    }

    private init(proto: SignalServiceProtos_CallMessage,
                 offer: SSKProtoCallMessageOffer?,
                 answer: SSKProtoCallMessageAnswer?,
                 iceUpdate: [SSKProtoCallMessageIceUpdate],
                 hangup: SSKProtoCallMessageHangup?,
                 busy: SSKProtoCallMessageBusy?) {
        self.proto = proto
        self.offer = offer
        self.answer = answer
        self.iceUpdate = iceUpdate
        self.hangup = hangup
        self.busy = busy
    }

    @objc
    public func serializedData() throws -> Data {
        return try self.proto.serializedData()
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

        // MARK: - Begin Validation Logic for SSKProtoCallMessage -

        // MARK: - End Validation Logic for SSKProtoCallMessage -

        let result = SSKProtoCallMessage(proto: proto,
                                         offer: offer,
                                         answer: answer,
                                         iceUpdate: iceUpdate,
                                         hangup: hangup,
                                         busy: busy)
        return result
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

        @objc public func setContentType(_ _value: String) {
            contentType = _value
        }

        @objc public func setFileName(_ _value: String) {
            fileName = _value
        }

        @objc public func setThumbnail(_ _value: SSKProtoAttachmentPointer) {
            thumbnail = _value
        }

        @objc public func setFlags(_ _value: UInt32) {
            flags = _value
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
                    builder.thumbnail = thumbnail.proto
                }

                if let flags = self.flags {
                    builder.flags = flags
                }
            }

            let wrapper = try SSKProtoDataMessageQuoteQuotedAttachment.parseProto(proto)
            return wrapper
        }
    }

    fileprivate let proto: SignalServiceProtos_DataMessage.Quote.QuotedAttachment

    @objc public let thumbnail: SSKProtoAttachmentPointer?

    @objc public var contentType: String {
        return proto.contentType
    }
    @objc public var hasContentType: Bool {
        return proto.hasContentType
    }

    @objc public var fileName: String {
        return proto.fileName
    }
    @objc public var hasFileName: Bool {
        return proto.hasFileName
    }

    @objc public var flags: UInt32 {
        return proto.flags
    }
    @objc public var hasFlags: Bool {
        return proto.hasFlags
    }

    private init(proto: SignalServiceProtos_DataMessage.Quote.QuotedAttachment,
                 thumbnail: SSKProtoAttachmentPointer?) {
        self.proto = proto
        self.thumbnail = thumbnail
    }

    @objc
    public func serializedData() throws -> Data {
        return try self.proto.serializedData()
    }

    @objc public class func parseData(_ serializedData: Data) throws -> SSKProtoDataMessageQuoteQuotedAttachment {
        let proto = try SignalServiceProtos_DataMessage.Quote.QuotedAttachment(serializedData: serializedData)
        return try parseProto(proto)
    }

    fileprivate class func parseProto(_ proto: SignalServiceProtos_DataMessage.Quote.QuotedAttachment) throws -> SSKProtoDataMessageQuoteQuotedAttachment {
        var thumbnail: SSKProtoAttachmentPointer? = nil
        if proto.hasThumbnail {
            thumbnail = try SSKProtoAttachmentPointer.parseProto(proto.thumbnail)
        }

        // MARK: - Begin Validation Logic for SSKProtoDataMessageQuoteQuotedAttachment -

        // MARK: - End Validation Logic for SSKProtoDataMessageQuoteQuotedAttachment -

        let result = SSKProtoDataMessageQuoteQuotedAttachment(proto: proto,
                                                              thumbnail: thumbnail)
        return result
    }
}

// MARK: - SSKProtoDataMessageQuote

@objc public class SSKProtoDataMessageQuote: NSObject {

    // MARK: - SSKProtoDataMessageQuoteBuilder

    @objc public class SSKProtoDataMessageQuoteBuilder: NSObject {

        private var id: UInt64?
        private var author: String?
        private var text: String?
        private var attachments: [SSKProtoDataMessageQuoteQuotedAttachment] = []

        @objc public override init() {}

        @objc public func setId(_ _value: UInt64) {
            id = _value
        }

        @objc public func setAuthor(_ _value: String) {
            author = _value
        }

        @objc public func setText(_ _value: String) {
            text = _value
        }

        @objc public func addAttachments(_ _value: SSKProtoDataMessageQuoteQuotedAttachment) {
            attachments.append(_value)
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

                var attachmentsWrapped: [SignalServiceProtos_DataMessage.Quote.QuotedAttachment] = []
                for item in attachments {
                    attachmentsWrapped.append(item.proto)
                }
                builder.attachments = attachmentsWrapped
            }

            let wrapper = try SSKProtoDataMessageQuote.parseProto(proto)
            return wrapper
        }
    }

    fileprivate let proto: SignalServiceProtos_DataMessage.Quote

    @objc public let id: UInt64
    @objc public let author: String
    @objc public let attachments: [SSKProtoDataMessageQuoteQuotedAttachment]

    @objc public var text: String {
        return proto.text
    }
    @objc public var hasText: Bool {
        return proto.hasText
    }

    private init(proto: SignalServiceProtos_DataMessage.Quote,
                 id: UInt64,
                 author: String,
                 attachments: [SSKProtoDataMessageQuoteQuotedAttachment]) {
        self.proto = proto
        self.id = id
        self.author = author
        self.attachments = attachments
    }

    @objc
    public func serializedData() throws -> Data {
        return try self.proto.serializedData()
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

        var attachments: [SSKProtoDataMessageQuoteQuotedAttachment] = []
        for item in proto.attachments {
            let wrapped = try SSKProtoDataMessageQuoteQuotedAttachment.parseProto(item)
            attachments.append(wrapped)
        }

        // MARK: - Begin Validation Logic for SSKProtoDataMessageQuote -

        // MARK: - End Validation Logic for SSKProtoDataMessageQuote -

        let result = SSKProtoDataMessageQuote(proto: proto,
                                              id: id,
                                              author: author,
                                              attachments: attachments)
        return result
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

        @objc public func setGivenName(_ _value: String) {
            givenName = _value
        }

        @objc public func setFamilyName(_ _value: String) {
            familyName = _value
        }

        @objc public func setPrefix(_ _value: String) {
            prefix = _value
        }

        @objc public func setSuffix(_ _value: String) {
            suffix = _value
        }

        @objc public func setMiddleName(_ _value: String) {
            middleName = _value
        }

        @objc public func setDisplayName(_ _value: String) {
            displayName = _value
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

    fileprivate let proto: SignalServiceProtos_DataMessage.Contact.Name

    @objc public var givenName: String {
        return proto.givenName
    }
    @objc public var hasGivenName: Bool {
        return proto.hasGivenName
    }

    @objc public var familyName: String {
        return proto.familyName
    }
    @objc public var hasFamilyName: Bool {
        return proto.hasFamilyName
    }

    @objc public var prefix: String {
        return proto.prefix
    }
    @objc public var hasPrefix: Bool {
        return proto.hasPrefix
    }

    @objc public var suffix: String {
        return proto.suffix
    }
    @objc public var hasSuffix: Bool {
        return proto.hasSuffix
    }

    @objc public var middleName: String {
        return proto.middleName
    }
    @objc public var hasMiddleName: Bool {
        return proto.hasMiddleName
    }

    @objc public var displayName: String {
        return proto.displayName
    }
    @objc public var hasDisplayName: Bool {
        return proto.hasDisplayName
    }

    private init(proto: SignalServiceProtos_DataMessage.Contact.Name) {
        self.proto = proto
    }

    @objc
    public func serializedData() throws -> Data {
        return try self.proto.serializedData()
    }

    @objc public class func parseData(_ serializedData: Data) throws -> SSKProtoDataMessageContactName {
        let proto = try SignalServiceProtos_DataMessage.Contact.Name(serializedData: serializedData)
        return try parseProto(proto)
    }

    fileprivate class func parseProto(_ proto: SignalServiceProtos_DataMessage.Contact.Name) throws -> SSKProtoDataMessageContactName {
        // MARK: - Begin Validation Logic for SSKProtoDataMessageContactName -

        // MARK: - End Validation Logic for SSKProtoDataMessageContactName -

        let result = SSKProtoDataMessageContactName(proto: proto)
        return result
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

        @objc public func setValue(_ _value: String) {
            value = _value
        }

        @objc public func setType(_ _value: SSKProtoDataMessageContactPhoneType) {
            type = _value
        }

        @objc public func setLabel(_ _value: String) {
            label = _value
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

    fileprivate let proto: SignalServiceProtos_DataMessage.Contact.Phone

    @objc public let value: String

    @objc public var type: SSKProtoDataMessageContactPhoneType {
        return SSKProtoDataMessageContactPhone.SSKProtoDataMessageContactPhoneTypeWrap(proto.type)
    }
    @objc public var hasType: Bool {
        return proto.hasType
    }

    @objc public var label: String {
        return proto.label
    }
    @objc public var hasLabel: Bool {
        return proto.hasLabel
    }

    private init(proto: SignalServiceProtos_DataMessage.Contact.Phone,
                 value: String) {
        self.proto = proto
        self.value = value
    }

    @objc
    public func serializedData() throws -> Data {
        return try self.proto.serializedData()
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

        // MARK: - Begin Validation Logic for SSKProtoDataMessageContactPhone -

        // MARK: - End Validation Logic for SSKProtoDataMessageContactPhone -

        let result = SSKProtoDataMessageContactPhone(proto: proto,
                                                     value: value)
        return result
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

        @objc public func setValue(_ _value: String) {
            value = _value
        }

        @objc public func setType(_ _value: SSKProtoDataMessageContactEmailType) {
            type = _value
        }

        @objc public func setLabel(_ _value: String) {
            label = _value
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

    fileprivate let proto: SignalServiceProtos_DataMessage.Contact.Email

    @objc public let value: String

    @objc public var type: SSKProtoDataMessageContactEmailType {
        return SSKProtoDataMessageContactEmail.SSKProtoDataMessageContactEmailTypeWrap(proto.type)
    }
    @objc public var hasType: Bool {
        return proto.hasType
    }

    @objc public var label: String {
        return proto.label
    }
    @objc public var hasLabel: Bool {
        return proto.hasLabel
    }

    private init(proto: SignalServiceProtos_DataMessage.Contact.Email,
                 value: String) {
        self.proto = proto
        self.value = value
    }

    @objc
    public func serializedData() throws -> Data {
        return try self.proto.serializedData()
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

        // MARK: - Begin Validation Logic for SSKProtoDataMessageContactEmail -

        // MARK: - End Validation Logic for SSKProtoDataMessageContactEmail -

        let result = SSKProtoDataMessageContactEmail(proto: proto,
                                                     value: value)
        return result
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

        @objc public func setType(_ _value: SSKProtoDataMessageContactPostalAddressType) {
            type = _value
        }

        @objc public func setLabel(_ _value: String) {
            label = _value
        }

        @objc public func setStreet(_ _value: String) {
            street = _value
        }

        @objc public func setPobox(_ _value: String) {
            pobox = _value
        }

        @objc public func setNeighborhood(_ _value: String) {
            neighborhood = _value
        }

        @objc public func setCity(_ _value: String) {
            city = _value
        }

        @objc public func setRegion(_ _value: String) {
            region = _value
        }

        @objc public func setPostcode(_ _value: String) {
            postcode = _value
        }

        @objc public func setCountry(_ _value: String) {
            country = _value
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

    fileprivate let proto: SignalServiceProtos_DataMessage.Contact.PostalAddress

    @objc public var type: SSKProtoDataMessageContactPostalAddressType {
        return SSKProtoDataMessageContactPostalAddress.SSKProtoDataMessageContactPostalAddressTypeWrap(proto.type)
    }
    @objc public var hasType: Bool {
        return proto.hasType
    }

    @objc public var label: String {
        return proto.label
    }
    @objc public var hasLabel: Bool {
        return proto.hasLabel
    }

    @objc public var street: String {
        return proto.street
    }
    @objc public var hasStreet: Bool {
        return proto.hasStreet
    }

    @objc public var pobox: String {
        return proto.pobox
    }
    @objc public var hasPobox: Bool {
        return proto.hasPobox
    }

    @objc public var neighborhood: String {
        return proto.neighborhood
    }
    @objc public var hasNeighborhood: Bool {
        return proto.hasNeighborhood
    }

    @objc public var city: String {
        return proto.city
    }
    @objc public var hasCity: Bool {
        return proto.hasCity
    }

    @objc public var region: String {
        return proto.region
    }
    @objc public var hasRegion: Bool {
        return proto.hasRegion
    }

    @objc public var postcode: String {
        return proto.postcode
    }
    @objc public var hasPostcode: Bool {
        return proto.hasPostcode
    }

    @objc public var country: String {
        return proto.country
    }
    @objc public var hasCountry: Bool {
        return proto.hasCountry
    }

    private init(proto: SignalServiceProtos_DataMessage.Contact.PostalAddress) {
        self.proto = proto
    }

    @objc
    public func serializedData() throws -> Data {
        return try self.proto.serializedData()
    }

    @objc public class func parseData(_ serializedData: Data) throws -> SSKProtoDataMessageContactPostalAddress {
        let proto = try SignalServiceProtos_DataMessage.Contact.PostalAddress(serializedData: serializedData)
        return try parseProto(proto)
    }

    fileprivate class func parseProto(_ proto: SignalServiceProtos_DataMessage.Contact.PostalAddress) throws -> SSKProtoDataMessageContactPostalAddress {
        // MARK: - Begin Validation Logic for SSKProtoDataMessageContactPostalAddress -

        // MARK: - End Validation Logic for SSKProtoDataMessageContactPostalAddress -

        let result = SSKProtoDataMessageContactPostalAddress(proto: proto)
        return result
    }
}

// MARK: - SSKProtoDataMessageContactAvatar

@objc public class SSKProtoDataMessageContactAvatar: NSObject {

    // MARK: - SSKProtoDataMessageContactAvatarBuilder

    @objc public class SSKProtoDataMessageContactAvatarBuilder: NSObject {

        private var avatar: SSKProtoAttachmentPointer?
        private var isProfile: Bool?

        @objc public override init() {}

        @objc public func setAvatar(_ _value: SSKProtoAttachmentPointer) {
            avatar = _value
        }

        @objc public func setIsProfile(_ _value: Bool) {
            isProfile = _value
        }

        @objc public func build() throws -> SSKProtoDataMessageContactAvatar {
            let proto = SignalServiceProtos_DataMessage.Contact.Avatar.with { (builder) in
                if let avatar = self.avatar {
                    builder.avatar = avatar.proto
                }

                if let isProfile = self.isProfile {
                    builder.isProfile = isProfile
                }
            }

            let wrapper = try SSKProtoDataMessageContactAvatar.parseProto(proto)
            return wrapper
        }
    }

    fileprivate let proto: SignalServiceProtos_DataMessage.Contact.Avatar

    @objc public let avatar: SSKProtoAttachmentPointer?

    @objc public var isProfile: Bool {
        return proto.isProfile
    }
    @objc public var hasIsProfile: Bool {
        return proto.hasIsProfile
    }

    private init(proto: SignalServiceProtos_DataMessage.Contact.Avatar,
                 avatar: SSKProtoAttachmentPointer?) {
        self.proto = proto
        self.avatar = avatar
    }

    @objc
    public func serializedData() throws -> Data {
        return try self.proto.serializedData()
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

        // MARK: - Begin Validation Logic for SSKProtoDataMessageContactAvatar -

        // MARK: - End Validation Logic for SSKProtoDataMessageContactAvatar -

        let result = SSKProtoDataMessageContactAvatar(proto: proto,
                                                      avatar: avatar)
        return result
    }
}

// MARK: - SSKProtoDataMessageContact

@objc public class SSKProtoDataMessageContact: NSObject {

    // MARK: - SSKProtoDataMessageContactBuilder

    @objc public class SSKProtoDataMessageContactBuilder: NSObject {

        private var name: SSKProtoDataMessageContactName?
        private var number: [SSKProtoDataMessageContactPhone] = []
        private var email: [SSKProtoDataMessageContactEmail] = []
        private var address: [SSKProtoDataMessageContactPostalAddress] = []
        private var avatar: SSKProtoDataMessageContactAvatar?
        private var organization: String?

        @objc public override init() {}

        @objc public func setName(_ _value: SSKProtoDataMessageContactName) {
            name = _value
        }

        @objc public func addNumber(_ _value: SSKProtoDataMessageContactPhone) {
            number.append(_value)
        }

        @objc public func addEmail(_ _value: SSKProtoDataMessageContactEmail) {
            email.append(_value)
        }

        @objc public func addAddress(_ _value: SSKProtoDataMessageContactPostalAddress) {
            address.append(_value)
        }

        @objc public func setAvatar(_ _value: SSKProtoDataMessageContactAvatar) {
            avatar = _value
        }

        @objc public func setOrganization(_ _value: String) {
            organization = _value
        }

        @objc public func build() throws -> SSKProtoDataMessageContact {
            let proto = SignalServiceProtos_DataMessage.Contact.with { (builder) in
                if let name = self.name {
                    builder.name = name.proto
                }

                var numberWrapped: [SignalServiceProtos_DataMessage.Contact.Phone] = []
                for item in number {
                    numberWrapped.append(item.proto)
                }
                builder.number = numberWrapped

                var emailWrapped: [SignalServiceProtos_DataMessage.Contact.Email] = []
                for item in email {
                    emailWrapped.append(item.proto)
                }
                builder.email = emailWrapped

                var addressWrapped: [SignalServiceProtos_DataMessage.Contact.PostalAddress] = []
                for item in address {
                    addressWrapped.append(item.proto)
                }
                builder.address = addressWrapped

                if let avatar = self.avatar {
                    builder.avatar = avatar.proto
                }

                if let organization = self.organization {
                    builder.organization = organization
                }
            }

            let wrapper = try SSKProtoDataMessageContact.parseProto(proto)
            return wrapper
        }
    }

    fileprivate let proto: SignalServiceProtos_DataMessage.Contact

    @objc public let name: SSKProtoDataMessageContactName?
    @objc public let number: [SSKProtoDataMessageContactPhone]
    @objc public let email: [SSKProtoDataMessageContactEmail]
    @objc public let address: [SSKProtoDataMessageContactPostalAddress]
    @objc public let avatar: SSKProtoDataMessageContactAvatar?

    @objc public var organization: String {
        return proto.organization
    }
    @objc public var hasOrganization: Bool {
        return proto.hasOrganization
    }

    private init(proto: SignalServiceProtos_DataMessage.Contact,
                 name: SSKProtoDataMessageContactName?,
                 number: [SSKProtoDataMessageContactPhone],
                 email: [SSKProtoDataMessageContactEmail],
                 address: [SSKProtoDataMessageContactPostalAddress],
                 avatar: SSKProtoDataMessageContactAvatar?) {
        self.proto = proto
        self.name = name
        self.number = number
        self.email = email
        self.address = address
        self.avatar = avatar
    }

    @objc
    public func serializedData() throws -> Data {
        return try self.proto.serializedData()
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

        // MARK: - Begin Validation Logic for SSKProtoDataMessageContact -

        // MARK: - End Validation Logic for SSKProtoDataMessageContact -

        let result = SSKProtoDataMessageContact(proto: proto,
                                                name: name,
                                                number: number,
                                                email: email,
                                                address: address,
                                                avatar: avatar)
        return result
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
        private var attachments: [SSKProtoAttachmentPointer] = []
        private var group: SSKProtoGroupContext?
        private var flags: UInt32?
        private var expireTimer: UInt32?
        private var profileKey: Data?
        private var timestamp: UInt64?
        private var quote: SSKProtoDataMessageQuote?
        private var contact: [SSKProtoDataMessageContact] = []

        @objc public override init() {}

        @objc public func setBody(_ _value: String) {
            body = _value
        }

        @objc public func addAttachments(_ _value: SSKProtoAttachmentPointer) {
            attachments.append(_value)
        }

        @objc public func setGroup(_ _value: SSKProtoGroupContext) {
            group = _value
        }

        @objc public func setFlags(_ _value: UInt32) {
            flags = _value
        }

        @objc public func setExpireTimer(_ _value: UInt32) {
            expireTimer = _value
        }

        @objc public func setProfileKey(_ _value: Data) {
            profileKey = _value
        }

        @objc public func setTimestamp(_ _value: UInt64) {
            timestamp = _value
        }

        @objc public func setQuote(_ _value: SSKProtoDataMessageQuote) {
            quote = _value
        }

        @objc public func addContact(_ _value: SSKProtoDataMessageContact) {
            contact.append(_value)
        }

        @objc public func build() throws -> SSKProtoDataMessage {
            let proto = SignalServiceProtos_DataMessage.with { (builder) in
                if let body = self.body {
                    builder.body = body
                }

                var attachmentsWrapped: [SignalServiceProtos_AttachmentPointer] = []
                for item in attachments {
                    attachmentsWrapped.append(item.proto)
                }
                builder.attachments = attachmentsWrapped

                if let group = self.group {
                    builder.group = group.proto
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
                    builder.quote = quote.proto
                }

                var contactWrapped: [SignalServiceProtos_DataMessage.Contact] = []
                for item in contact {
                    contactWrapped.append(item.proto)
                }
                builder.contact = contactWrapped
            }

            let wrapper = try SSKProtoDataMessage.parseProto(proto)
            return wrapper
        }
    }

    fileprivate let proto: SignalServiceProtos_DataMessage

    @objc public let attachments: [SSKProtoAttachmentPointer]
    @objc public let group: SSKProtoGroupContext?
    @objc public let quote: SSKProtoDataMessageQuote?
    @objc public let contact: [SSKProtoDataMessageContact]

    @objc public var body: String {
        return proto.body
    }
    @objc public var hasBody: Bool {
        return proto.hasBody
    }

    @objc public var flags: UInt32 {
        return proto.flags
    }
    @objc public var hasFlags: Bool {
        return proto.hasFlags
    }

    @objc public var expireTimer: UInt32 {
        return proto.expireTimer
    }
    @objc public var hasExpireTimer: Bool {
        return proto.hasExpireTimer
    }

    @objc public var profileKey: Data {
        return proto.profileKey
    }
    @objc public var hasProfileKey: Bool {
        return proto.hasProfileKey
    }

    @objc public var timestamp: UInt64 {
        return proto.timestamp
    }
    @objc public var hasTimestamp: Bool {
        return proto.hasTimestamp
    }

    private init(proto: SignalServiceProtos_DataMessage,
                 attachments: [SSKProtoAttachmentPointer],
                 group: SSKProtoGroupContext?,
                 quote: SSKProtoDataMessageQuote?,
                 contact: [SSKProtoDataMessageContact]) {
        self.proto = proto
        self.attachments = attachments
        self.group = group
        self.quote = quote
        self.contact = contact
    }

    @objc
    public func serializedData() throws -> Data {
        return try self.proto.serializedData()
    }

    @objc public class func parseData(_ serializedData: Data) throws -> SSKProtoDataMessage {
        let proto = try SignalServiceProtos_DataMessage(serializedData: serializedData)
        return try parseProto(proto)
    }

    fileprivate class func parseProto(_ proto: SignalServiceProtos_DataMessage) throws -> SSKProtoDataMessage {
        var attachments: [SSKProtoAttachmentPointer] = []
        for item in proto.attachments {
            let wrapped = try SSKProtoAttachmentPointer.parseProto(item)
            attachments.append(wrapped)
        }

        var group: SSKProtoGroupContext? = nil
        if proto.hasGroup {
            group = try SSKProtoGroupContext.parseProto(proto.group)
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

        let result = SSKProtoDataMessage(proto: proto,
                                         attachments: attachments,
                                         group: group,
                                         quote: quote,
                                         contact: contact)
        return result
    }
}

// MARK: - SSKProtoNullMessage

@objc public class SSKProtoNullMessage: NSObject {

    // MARK: - SSKProtoNullMessageBuilder

    @objc public class SSKProtoNullMessageBuilder: NSObject {

        private var padding: Data?

        @objc public override init() {}

        @objc public func setPadding(_ _value: Data) {
            padding = _value
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

    fileprivate let proto: SignalServiceProtos_NullMessage

    @objc public var padding: Data {
        return proto.padding
    }
    @objc public var hasPadding: Bool {
        return proto.hasPadding
    }

    private init(proto: SignalServiceProtos_NullMessage) {
        self.proto = proto
    }

    @objc
    public func serializedData() throws -> Data {
        return try self.proto.serializedData()
    }

    @objc public class func parseData(_ serializedData: Data) throws -> SSKProtoNullMessage {
        let proto = try SignalServiceProtos_NullMessage(serializedData: serializedData)
        return try parseProto(proto)
    }

    fileprivate class func parseProto(_ proto: SignalServiceProtos_NullMessage) throws -> SSKProtoNullMessage {
        // MARK: - Begin Validation Logic for SSKProtoNullMessage -

        // MARK: - End Validation Logic for SSKProtoNullMessage -

        let result = SSKProtoNullMessage(proto: proto)
        return result
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
        private var timestamp: [UInt64] = []

        @objc public override init() {}

        @objc public func setType(_ _value: SSKProtoReceiptMessageType) {
            type = _value
        }

        @objc public func addTimestamp(_ _value: UInt64) {
            timestamp.append(_value)
        }

        @objc public func build() throws -> SSKProtoReceiptMessage {
            let proto = SignalServiceProtos_ReceiptMessage.with { (builder) in
                if let type = self.type {
                    builder.type = SSKProtoReceiptMessageTypeUnwrap(type)
                }

                var timestampWrapped: [UInt64] = []
                for item in timestamp {
                    timestampWrapped.append(item)
                }
                builder.timestamp = timestampWrapped
            }

            let wrapper = try SSKProtoReceiptMessage.parseProto(proto)
            return wrapper
        }
    }

    fileprivate let proto: SignalServiceProtos_ReceiptMessage

    @objc public let type: SSKProtoReceiptMessageType

    @objc public var timestamp: [UInt64] {
    return proto.timestamp
}

private init(proto: SignalServiceProtos_ReceiptMessage,
             type: SSKProtoReceiptMessageType) {
    self.proto = proto
    self.type = type
}

@objc
public func serializedData() throws -> Data {
    return try self.proto.serializedData()
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

    // MARK: - Begin Validation Logic for SSKProtoReceiptMessage -

    // MARK: - End Validation Logic for SSKProtoReceiptMessage -

    let result = SSKProtoReceiptMessage(proto: proto,
                                        type: type)
    return result
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

    @objc public func setDestination(_ _value: String) {
        destination = _value
    }

    @objc public func setIdentityKey(_ _value: Data) {
        identityKey = _value
    }

    @objc public func setState(_ _value: SSKProtoVerifiedState) {
        state = _value
    }

    @objc public func setNullMessage(_ _value: Data) {
        nullMessage = _value
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

fileprivate let proto: SignalServiceProtos_Verified

@objc public let destination: String

@objc public var identityKey: Data {
    return proto.identityKey
}
@objc public var hasIdentityKey: Bool {
    return proto.hasIdentityKey
}

@objc public var state: SSKProtoVerifiedState {
    return SSKProtoVerified.SSKProtoVerifiedStateWrap(proto.state)
}
@objc public var hasState: Bool {
    return proto.hasState
}

@objc public var nullMessage: Data {
    return proto.nullMessage
}
@objc public var hasNullMessage: Bool {
    return proto.hasNullMessage
}

private init(proto: SignalServiceProtos_Verified,
             destination: String) {
    self.proto = proto
    self.destination = destination
}

@objc
public func serializedData() throws -> Data {
    return try self.proto.serializedData()
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

    // MARK: - Begin Validation Logic for SSKProtoVerified -

    // MARK: - End Validation Logic for SSKProtoVerified -

    let result = SSKProtoVerified(proto: proto,
                                  destination: destination)
    return result
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

    @objc public func setDestination(_ _value: String) {
        destination = _value
    }

    @objc public func setTimestamp(_ _value: UInt64) {
        timestamp = _value
    }

    @objc public func setMessage(_ _value: SSKProtoDataMessage) {
        message = _value
    }

    @objc public func setExpirationStartTimestamp(_ _value: UInt64) {
        expirationStartTimestamp = _value
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
                builder.message = message.proto
            }

            if let expirationStartTimestamp = self.expirationStartTimestamp {
                builder.expirationStartTimestamp = expirationStartTimestamp
            }
        }

        let wrapper = try SSKProtoSyncMessageSent.parseProto(proto)
        return wrapper
    }
}

fileprivate let proto: SignalServiceProtos_SyncMessage.Sent

@objc public let message: SSKProtoDataMessage?

@objc public var destination: String {
    return proto.destination
}
@objc public var hasDestination: Bool {
    return proto.hasDestination
}

@objc public var timestamp: UInt64 {
    return proto.timestamp
}
@objc public var hasTimestamp: Bool {
    return proto.hasTimestamp
}

@objc public var expirationStartTimestamp: UInt64 {
    return proto.expirationStartTimestamp
}
@objc public var hasExpirationStartTimestamp: Bool {
    return proto.hasExpirationStartTimestamp
}

private init(proto: SignalServiceProtos_SyncMessage.Sent,
             message: SSKProtoDataMessage?) {
    self.proto = proto
    self.message = message
}

@objc
public func serializedData() throws -> Data {
    return try self.proto.serializedData()
}

@objc public class func parseData(_ serializedData: Data) throws -> SSKProtoSyncMessageSent {
    let proto = try SignalServiceProtos_SyncMessage.Sent(serializedData: serializedData)
    return try parseProto(proto)
}

fileprivate class func parseProto(_ proto: SignalServiceProtos_SyncMessage.Sent) throws -> SSKProtoSyncMessageSent {
    var message: SSKProtoDataMessage? = nil
    if proto.hasMessage {
        message = try SSKProtoDataMessage.parseProto(proto.message)
    }

    // MARK: - Begin Validation Logic for SSKProtoSyncMessageSent -

    // MARK: - End Validation Logic for SSKProtoSyncMessageSent -

    let result = SSKProtoSyncMessageSent(proto: proto,
                                         message: message)
    return result
}
}

// MARK: - SSKProtoSyncMessageContacts

@objc public class SSKProtoSyncMessageContacts: NSObject {

// MARK: - SSKProtoSyncMessageContactsBuilder

@objc public class SSKProtoSyncMessageContactsBuilder: NSObject {

    private var blob: SSKProtoAttachmentPointer?
    private var isComplete: Bool?

    @objc public override init() {}

    @objc public func setBlob(_ _value: SSKProtoAttachmentPointer) {
        blob = _value
    }

    @objc public func setIsComplete(_ _value: Bool) {
        isComplete = _value
    }

    @objc public func build() throws -> SSKProtoSyncMessageContacts {
        let proto = SignalServiceProtos_SyncMessage.Contacts.with { (builder) in
            if let blob = self.blob {
                builder.blob = blob.proto
            }

            if let isComplete = self.isComplete {
                builder.isComplete = isComplete
            }
        }

        let wrapper = try SSKProtoSyncMessageContacts.parseProto(proto)
        return wrapper
    }
}

fileprivate let proto: SignalServiceProtos_SyncMessage.Contacts

@objc public let blob: SSKProtoAttachmentPointer

@objc public var isComplete: Bool {
    return proto.isComplete
}
@objc public var hasIsComplete: Bool {
    return proto.hasIsComplete
}

private init(proto: SignalServiceProtos_SyncMessage.Contacts,
             blob: SSKProtoAttachmentPointer) {
    self.proto = proto
    self.blob = blob
}

@objc
public func serializedData() throws -> Data {
    return try self.proto.serializedData()
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

    // MARK: - Begin Validation Logic for SSKProtoSyncMessageContacts -

    // MARK: - End Validation Logic for SSKProtoSyncMessageContacts -

    let result = SSKProtoSyncMessageContacts(proto: proto,
                                             blob: blob)
    return result
}
}

// MARK: - SSKProtoSyncMessageGroups

@objc public class SSKProtoSyncMessageGroups: NSObject {

// MARK: - SSKProtoSyncMessageGroupsBuilder

@objc public class SSKProtoSyncMessageGroupsBuilder: NSObject {

    private var blob: SSKProtoAttachmentPointer?

    @objc public override init() {}

    @objc public func setBlob(_ _value: SSKProtoAttachmentPointer) {
        blob = _value
    }

    @objc public func build() throws -> SSKProtoSyncMessageGroups {
        let proto = SignalServiceProtos_SyncMessage.Groups.with { (builder) in
            if let blob = self.blob {
                builder.blob = blob.proto
            }
        }

        let wrapper = try SSKProtoSyncMessageGroups.parseProto(proto)
        return wrapper
    }
}

fileprivate let proto: SignalServiceProtos_SyncMessage.Groups

@objc public let blob: SSKProtoAttachmentPointer?

private init(proto: SignalServiceProtos_SyncMessage.Groups,
             blob: SSKProtoAttachmentPointer?) {
    self.proto = proto
    self.blob = blob
}

@objc
public func serializedData() throws -> Data {
    return try self.proto.serializedData()
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

    // MARK: - End Validation Logic for SSKProtoSyncMessageGroups -

    let result = SSKProtoSyncMessageGroups(proto: proto,
                                           blob: blob)
    return result
}
}

// MARK: - SSKProtoSyncMessageBlocked

@objc public class SSKProtoSyncMessageBlocked: NSObject {

// MARK: - SSKProtoSyncMessageBlockedBuilder

@objc public class SSKProtoSyncMessageBlockedBuilder: NSObject {

    private var numbers: [String] = []

    @objc public override init() {}

    @objc public func addNumbers(_ _value: String) {
        numbers.append(_value)
    }

    @objc public func build() throws -> SSKProtoSyncMessageBlocked {
        let proto = SignalServiceProtos_SyncMessage.Blocked.with { (builder) in
            var numbersWrapped: [String] = []
            for item in numbers {
                numbersWrapped.append(item)
            }
            builder.numbers = numbersWrapped
        }

        let wrapper = try SSKProtoSyncMessageBlocked.parseProto(proto)
        return wrapper
    }
}

fileprivate let proto: SignalServiceProtos_SyncMessage.Blocked

@objc public var numbers: [String] {
return proto.numbers
}

private init(proto: SignalServiceProtos_SyncMessage.Blocked) {
self.proto = proto
}

@objc
public func serializedData() throws -> Data {
    return try self.proto.serializedData()
}

@objc public class func parseData(_ serializedData: Data) throws -> SSKProtoSyncMessageBlocked {
let proto = try SignalServiceProtos_SyncMessage.Blocked(serializedData: serializedData)
return try parseProto(proto)
}

fileprivate class func parseProto(_ proto: SignalServiceProtos_SyncMessage.Blocked) throws -> SSKProtoSyncMessageBlocked {
// MARK: - Begin Validation Logic for SSKProtoSyncMessageBlocked -

// MARK: - End Validation Logic for SSKProtoSyncMessageBlocked -

let result = SSKProtoSyncMessageBlocked(proto: proto)
return result
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

@objc public func setType(_ _value: SSKProtoSyncMessageRequestType) {
    type = _value
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

fileprivate let proto: SignalServiceProtos_SyncMessage.Request

@objc public let type: SSKProtoSyncMessageRequestType

private init(proto: SignalServiceProtos_SyncMessage.Request,
             type: SSKProtoSyncMessageRequestType) {
self.proto = proto
self.type = type
}

@objc
public func serializedData() throws -> Data {
    return try self.proto.serializedData()
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

// MARK: - End Validation Logic for SSKProtoSyncMessageRequest -

let result = SSKProtoSyncMessageRequest(proto: proto,
                                        type: type)
return result
}
}

// MARK: - SSKProtoSyncMessageRead

@objc public class SSKProtoSyncMessageRead: NSObject {

// MARK: - SSKProtoSyncMessageReadBuilder

@objc public class SSKProtoSyncMessageReadBuilder: NSObject {

private var sender: String?
private var timestamp: UInt64?

@objc public override init() {}

@objc public func setSender(_ _value: String) {
    sender = _value
}

@objc public func setTimestamp(_ _value: UInt64) {
    timestamp = _value
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

fileprivate let proto: SignalServiceProtos_SyncMessage.Read

@objc public let sender: String
@objc public let timestamp: UInt64

private init(proto: SignalServiceProtos_SyncMessage.Read,
             sender: String,
             timestamp: UInt64) {
self.proto = proto
self.sender = sender
self.timestamp = timestamp
}

@objc
public func serializedData() throws -> Data {
    return try self.proto.serializedData()
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

// MARK: - End Validation Logic for SSKProtoSyncMessageRead -

let result = SSKProtoSyncMessageRead(proto: proto,
                                     sender: sender,
                                     timestamp: timestamp)
return result
}
}

// MARK: - SSKProtoSyncMessageConfiguration

@objc public class SSKProtoSyncMessageConfiguration: NSObject {

// MARK: - SSKProtoSyncMessageConfigurationBuilder

@objc public class SSKProtoSyncMessageConfigurationBuilder: NSObject {

private var readReceipts: Bool?

@objc public override init() {}

@objc public func setReadReceipts(_ _value: Bool) {
    readReceipts = _value
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

fileprivate let proto: SignalServiceProtos_SyncMessage.Configuration

@objc public var readReceipts: Bool {
return proto.readReceipts
}
@objc public var hasReadReceipts: Bool {
return proto.hasReadReceipts
}

private init(proto: SignalServiceProtos_SyncMessage.Configuration) {
self.proto = proto
}

@objc
public func serializedData() throws -> Data {
    return try self.proto.serializedData()
}

@objc public class func parseData(_ serializedData: Data) throws -> SSKProtoSyncMessageConfiguration {
let proto = try SignalServiceProtos_SyncMessage.Configuration(serializedData: serializedData)
return try parseProto(proto)
}

fileprivate class func parseProto(_ proto: SignalServiceProtos_SyncMessage.Configuration) throws -> SSKProtoSyncMessageConfiguration {
// MARK: - Begin Validation Logic for SSKProtoSyncMessageConfiguration -

// MARK: - End Validation Logic for SSKProtoSyncMessageConfiguration -

let result = SSKProtoSyncMessageConfiguration(proto: proto)
return result
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
private var read: [SSKProtoSyncMessageRead] = []
private var blocked: SSKProtoSyncMessageBlocked?
private var verified: SSKProtoVerified?
private var configuration: SSKProtoSyncMessageConfiguration?
private var padding: Data?

@objc public override init() {}

@objc public func setSent(_ _value: SSKProtoSyncMessageSent) {
    sent = _value
}

@objc public func setContacts(_ _value: SSKProtoSyncMessageContacts) {
    contacts = _value
}

@objc public func setGroups(_ _value: SSKProtoSyncMessageGroups) {
    groups = _value
}

@objc public func setRequest(_ _value: SSKProtoSyncMessageRequest) {
    request = _value
}

@objc public func addRead(_ _value: SSKProtoSyncMessageRead) {
    read.append(_value)
}

@objc public func setBlocked(_ _value: SSKProtoSyncMessageBlocked) {
    blocked = _value
}

@objc public func setVerified(_ _value: SSKProtoVerified) {
    verified = _value
}

@objc public func setConfiguration(_ _value: SSKProtoSyncMessageConfiguration) {
    configuration = _value
}

@objc public func setPadding(_ _value: Data) {
    padding = _value
}

@objc public func build() throws -> SSKProtoSyncMessage {
    let proto = SignalServiceProtos_SyncMessage.with { (builder) in
        if let sent = self.sent {
            builder.sent = sent.proto
        }

        if let contacts = self.contacts {
            builder.contacts = contacts.proto
        }

        if let groups = self.groups {
            builder.groups = groups.proto
        }

        if let request = self.request {
            builder.request = request.proto
        }

        var readWrapped: [SignalServiceProtos_SyncMessage.Read] = []
        for item in read {
            readWrapped.append(item.proto)
        }
        builder.read = readWrapped

        if let blocked = self.blocked {
            builder.blocked = blocked.proto
        }

        if let verified = self.verified {
            builder.verified = verified.proto
        }

        if let configuration = self.configuration {
            builder.configuration = configuration.proto
        }

        if let padding = self.padding {
            builder.padding = padding
        }
    }

    let wrapper = try SSKProtoSyncMessage.parseProto(proto)
    return wrapper
}
}

fileprivate let proto: SignalServiceProtos_SyncMessage

@objc public let sent: SSKProtoSyncMessageSent?
@objc public let contacts: SSKProtoSyncMessageContacts?
@objc public let groups: SSKProtoSyncMessageGroups?
@objc public let request: SSKProtoSyncMessageRequest?
@objc public let read: [SSKProtoSyncMessageRead]
@objc public let blocked: SSKProtoSyncMessageBlocked?
@objc public let verified: SSKProtoVerified?
@objc public let configuration: SSKProtoSyncMessageConfiguration?

@objc public var padding: Data {
return proto.padding
}
@objc public var hasPadding: Bool {
return proto.hasPadding
}

private init(proto: SignalServiceProtos_SyncMessage,
             sent: SSKProtoSyncMessageSent?,
             contacts: SSKProtoSyncMessageContacts?,
             groups: SSKProtoSyncMessageGroups?,
             request: SSKProtoSyncMessageRequest?,
             read: [SSKProtoSyncMessageRead],
             blocked: SSKProtoSyncMessageBlocked?,
             verified: SSKProtoVerified?,
             configuration: SSKProtoSyncMessageConfiguration?) {
self.proto = proto
self.sent = sent
self.contacts = contacts
self.groups = groups
self.request = request
self.read = read
self.blocked = blocked
self.verified = verified
self.configuration = configuration
}

@objc
public func serializedData() throws -> Data {
    return try self.proto.serializedData()
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

// MARK: - Begin Validation Logic for SSKProtoSyncMessage -

// MARK: - End Validation Logic for SSKProtoSyncMessage -

let result = SSKProtoSyncMessage(proto: proto,
                                 sent: sent,
                                 contacts: contacts,
                                 groups: groups,
                                 request: request,
                                 read: read,
                                 blocked: blocked,
                                 verified: verified,
                                 configuration: configuration)
return result
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

@objc public func setId(_ _value: UInt64) {
    id = _value
}

@objc public func setContentType(_ _value: String) {
    contentType = _value
}

@objc public func setKey(_ _value: Data) {
    key = _value
}

@objc public func setSize(_ _value: UInt32) {
    size = _value
}

@objc public func setThumbnail(_ _value: Data) {
    thumbnail = _value
}

@objc public func setDigest(_ _value: Data) {
    digest = _value
}

@objc public func setFileName(_ _value: String) {
    fileName = _value
}

@objc public func setFlags(_ _value: UInt32) {
    flags = _value
}

@objc public func setWidth(_ _value: UInt32) {
    width = _value
}

@objc public func setHeight(_ _value: UInt32) {
    height = _value
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

fileprivate let proto: SignalServiceProtos_AttachmentPointer

@objc public let id: UInt64

@objc public var contentType: String {
return proto.contentType
}
@objc public var hasContentType: Bool {
return proto.hasContentType
}

@objc public var key: Data {
return proto.key
}
@objc public var hasKey: Bool {
return proto.hasKey
}

@objc public var size: UInt32 {
return proto.size
}
@objc public var hasSize: Bool {
return proto.hasSize
}

@objc public var thumbnail: Data {
return proto.thumbnail
}
@objc public var hasThumbnail: Bool {
return proto.hasThumbnail
}

@objc public var digest: Data {
return proto.digest
}
@objc public var hasDigest: Bool {
return proto.hasDigest
}

@objc public var fileName: String {
return proto.fileName
}
@objc public var hasFileName: Bool {
return proto.hasFileName
}

@objc public var flags: UInt32 {
return proto.flags
}
@objc public var hasFlags: Bool {
return proto.hasFlags
}

@objc public var width: UInt32 {
return proto.width
}
@objc public var hasWidth: Bool {
return proto.hasWidth
}

@objc public var height: UInt32 {
return proto.height
}
@objc public var hasHeight: Bool {
return proto.hasHeight
}

private init(proto: SignalServiceProtos_AttachmentPointer,
             id: UInt64) {
self.proto = proto
self.id = id
}

@objc
public func serializedData() throws -> Data {
    return try self.proto.serializedData()
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

// MARK: - Begin Validation Logic for SSKProtoAttachmentPointer -

// MARK: - End Validation Logic for SSKProtoAttachmentPointer -

let result = SSKProtoAttachmentPointer(proto: proto,
                                       id: id)
return result
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
private var members: [String] = []
private var avatar: SSKProtoAttachmentPointer?

@objc public override init() {}

@objc public func setId(_ _value: Data) {
    id = _value
}

@objc public func setType(_ _value: SSKProtoGroupContextType) {
    type = _value
}

@objc public func setName(_ _value: String) {
    name = _value
}

@objc public func addMembers(_ _value: String) {
    members.append(_value)
}

@objc public func setAvatar(_ _value: SSKProtoAttachmentPointer) {
    avatar = _value
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

        var membersWrapped: [String] = []
        for item in members {
            membersWrapped.append(item)
        }
        builder.members = membersWrapped

        if let avatar = self.avatar {
            builder.avatar = avatar.proto
        }
    }

    let wrapper = try SSKProtoGroupContext.parseProto(proto)
    return wrapper
}
}

fileprivate let proto: SignalServiceProtos_GroupContext

@objc public let id: Data
@objc public let type: SSKProtoGroupContextType
@objc public let avatar: SSKProtoAttachmentPointer?

@objc public var name: String {
return proto.name
}
@objc public var hasName: Bool {
return proto.hasName
}

@objc public var members: [String] {
return proto.members
}

private init(proto: SignalServiceProtos_GroupContext,
             id: Data,
             type: SSKProtoGroupContextType,
             avatar: SSKProtoAttachmentPointer?) {
self.proto = proto
self.id = id
self.type = type
self.avatar = avatar
}

@objc
public func serializedData() throws -> Data {
    return try self.proto.serializedData()
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

var avatar: SSKProtoAttachmentPointer? = nil
if proto.hasAvatar {
avatar = try SSKProtoAttachmentPointer.parseProto(proto.avatar)
}

// MARK: - Begin Validation Logic for SSKProtoGroupContext -

// MARK: - End Validation Logic for SSKProtoGroupContext -

let result = SSKProtoGroupContext(proto: proto,
                                  id: id,
                                  type: type,
                                  avatar: avatar)
return result
}
}

// MARK: - SSKProtoContactDetailsAvatar

@objc public class SSKProtoContactDetailsAvatar: NSObject {

// MARK: - SSKProtoContactDetailsAvatarBuilder

@objc public class SSKProtoContactDetailsAvatarBuilder: NSObject {

private var contentType: String?
private var length: UInt32?

@objc public override init() {}

@objc public func setContentType(_ _value: String) {
contentType = _value
}

@objc public func setLength(_ _value: UInt32) {
length = _value
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

fileprivate let proto: SignalServiceProtos_ContactDetails.Avatar

@objc public var contentType: String {
return proto.contentType
}
@objc public var hasContentType: Bool {
return proto.hasContentType
}

@objc public var length: UInt32 {
return proto.length
}
@objc public var hasLength: Bool {
return proto.hasLength
}

private init(proto: SignalServiceProtos_ContactDetails.Avatar) {
self.proto = proto
}

@objc
public func serializedData() throws -> Data {
    return try self.proto.serializedData()
}

@objc public class func parseData(_ serializedData: Data) throws -> SSKProtoContactDetailsAvatar {
let proto = try SignalServiceProtos_ContactDetails.Avatar(serializedData: serializedData)
return try parseProto(proto)
}

fileprivate class func parseProto(_ proto: SignalServiceProtos_ContactDetails.Avatar) throws -> SSKProtoContactDetailsAvatar {
// MARK: - Begin Validation Logic for SSKProtoContactDetailsAvatar -

// MARK: - End Validation Logic for SSKProtoContactDetailsAvatar -

let result = SSKProtoContactDetailsAvatar(proto: proto)
return result
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

@objc public func setNumber(_ _value: String) {
number = _value
}

@objc public func setName(_ _value: String) {
name = _value
}

@objc public func setAvatar(_ _value: SSKProtoContactDetailsAvatar) {
avatar = _value
}

@objc public func setColor(_ _value: String) {
color = _value
}

@objc public func setVerified(_ _value: SSKProtoVerified) {
verified = _value
}

@objc public func setProfileKey(_ _value: Data) {
profileKey = _value
}

@objc public func setBlocked(_ _value: Bool) {
blocked = _value
}

@objc public func setExpireTimer(_ _value: UInt32) {
expireTimer = _value
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
        builder.avatar = avatar.proto
    }

    if let color = self.color {
        builder.color = color
    }

    if let verified = self.verified {
        builder.verified = verified.proto
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

fileprivate let proto: SignalServiceProtos_ContactDetails

@objc public let number: String
@objc public let avatar: SSKProtoContactDetailsAvatar?
@objc public let verified: SSKProtoVerified?

@objc public var name: String {
return proto.name
}
@objc public var hasName: Bool {
return proto.hasName
}

@objc public var color: String {
return proto.color
}
@objc public var hasColor: Bool {
return proto.hasColor
}

@objc public var profileKey: Data {
return proto.profileKey
}
@objc public var hasProfileKey: Bool {
return proto.hasProfileKey
}

@objc public var blocked: Bool {
return proto.blocked
}
@objc public var hasBlocked: Bool {
return proto.hasBlocked
}

@objc public var expireTimer: UInt32 {
return proto.expireTimer
}
@objc public var hasExpireTimer: Bool {
return proto.hasExpireTimer
}

private init(proto: SignalServiceProtos_ContactDetails,
             number: String,
             avatar: SSKProtoContactDetailsAvatar?,
             verified: SSKProtoVerified?) {
self.proto = proto
self.number = number
self.avatar = avatar
self.verified = verified
}

@objc
public func serializedData() throws -> Data {
    return try self.proto.serializedData()
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

var avatar: SSKProtoContactDetailsAvatar? = nil
if proto.hasAvatar {
avatar = try SSKProtoContactDetailsAvatar.parseProto(proto.avatar)
}

var verified: SSKProtoVerified? = nil
if proto.hasVerified {
verified = try SSKProtoVerified.parseProto(proto.verified)
}

// MARK: - Begin Validation Logic for SSKProtoContactDetails -

// MARK: - End Validation Logic for SSKProtoContactDetails -

let result = SSKProtoContactDetails(proto: proto,
                                    number: number,
                                    avatar: avatar,
                                    verified: verified)
return result
}
}

// MARK: - SSKProtoGroupDetailsAvatar

@objc public class SSKProtoGroupDetailsAvatar: NSObject {

// MARK: - SSKProtoGroupDetailsAvatarBuilder

@objc public class SSKProtoGroupDetailsAvatarBuilder: NSObject {

private var contentType: String?
private var length: UInt32?

@objc public override init() {}

@objc public func setContentType(_ _value: String) {
contentType = _value
}

@objc public func setLength(_ _value: UInt32) {
length = _value
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

fileprivate let proto: SignalServiceProtos_GroupDetails.Avatar

@objc public var contentType: String {
return proto.contentType
}
@objc public var hasContentType: Bool {
return proto.hasContentType
}

@objc public var length: UInt32 {
return proto.length
}
@objc public var hasLength: Bool {
return proto.hasLength
}

private init(proto: SignalServiceProtos_GroupDetails.Avatar) {
self.proto = proto
}

@objc
public func serializedData() throws -> Data {
    return try self.proto.serializedData()
}

@objc public class func parseData(_ serializedData: Data) throws -> SSKProtoGroupDetailsAvatar {
let proto = try SignalServiceProtos_GroupDetails.Avatar(serializedData: serializedData)
return try parseProto(proto)
}

fileprivate class func parseProto(_ proto: SignalServiceProtos_GroupDetails.Avatar) throws -> SSKProtoGroupDetailsAvatar {
// MARK: - Begin Validation Logic for SSKProtoGroupDetailsAvatar -

// MARK: - End Validation Logic for SSKProtoGroupDetailsAvatar -

let result = SSKProtoGroupDetailsAvatar(proto: proto)
return result
}
}

// MARK: - SSKProtoGroupDetails

@objc public class SSKProtoGroupDetails: NSObject {

// MARK: - SSKProtoGroupDetailsBuilder

@objc public class SSKProtoGroupDetailsBuilder: NSObject {

private var id: Data?
private var name: String?
private var members: [String] = []
private var avatar: SSKProtoGroupDetailsAvatar?
private var active: Bool?
private var expireTimer: UInt32?
private var color: String?

@objc public override init() {}

@objc public func setId(_ _value: Data) {
id = _value
}

@objc public func setName(_ _value: String) {
name = _value
}

@objc public func addMembers(_ _value: String) {
members.append(_value)
}

@objc public func setAvatar(_ _value: SSKProtoGroupDetailsAvatar) {
avatar = _value
}

@objc public func setActive(_ _value: Bool) {
active = _value
}

@objc public func setExpireTimer(_ _value: UInt32) {
expireTimer = _value
}

@objc public func setColor(_ _value: String) {
color = _value
}

@objc public func build() throws -> SSKProtoGroupDetails {
let proto = SignalServiceProtos_GroupDetails.with { (builder) in
    if let id = self.id {
        builder.id = id
    }

    if let name = self.name {
        builder.name = name
    }

    var membersWrapped: [String] = []
    for item in members {
        membersWrapped.append(item)
    }
    builder.members = membersWrapped

    if let avatar = self.avatar {
        builder.avatar = avatar.proto
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

fileprivate let proto: SignalServiceProtos_GroupDetails

@objc public let id: Data
@objc public let avatar: SSKProtoGroupDetailsAvatar?

@objc public var name: String {
return proto.name
}
@objc public var hasName: Bool {
return proto.hasName
}

@objc public var members: [String] {
return proto.members
}

@objc public var active: Bool {
return proto.active
}
@objc public var hasActive: Bool {
return proto.hasActive
}

@objc public var expireTimer: UInt32 {
return proto.expireTimer
}
@objc public var hasExpireTimer: Bool {
return proto.hasExpireTimer
}

@objc public var color: String {
return proto.color
}
@objc public var hasColor: Bool {
return proto.hasColor
}

private init(proto: SignalServiceProtos_GroupDetails,
             id: Data,
             avatar: SSKProtoGroupDetailsAvatar?) {
self.proto = proto
self.id = id
self.avatar = avatar
}

@objc
public func serializedData() throws -> Data {
    return try self.proto.serializedData()
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

var avatar: SSKProtoGroupDetailsAvatar? = nil
if proto.hasAvatar {
avatar = try SSKProtoGroupDetailsAvatar.parseProto(proto.avatar)
}

// MARK: - Begin Validation Logic for SSKProtoGroupDetails -

// MARK: - End Validation Logic for SSKProtoGroupDetails -

let result = SSKProtoGroupDetails(proto: proto,
                                  id: id,
                                  avatar: avatar)
return result
}
}
