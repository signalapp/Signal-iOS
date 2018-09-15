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

        private var proto = SignalServiceProtos_Envelope()

        @objc public override init() {}

        // Initializer for required fields
        @objc public init(type: SSKProtoEnvelopeType, source: String, sourceDevice: UInt32, timestamp: UInt64) {
            super.init()

            setType(type)
            setSource(source)
            setSourceDevice(sourceDevice)
            setTimestamp(timestamp)
        }

        @objc public func setType(_ valueParam: SSKProtoEnvelopeType) {
            proto.type = SSKProtoEnvelopeTypeUnwrap(valueParam)
        }

        @objc public func setSource(_ valueParam: String) {
            proto.source = valueParam
        }

        @objc public func setSourceDevice(_ valueParam: UInt32) {
            proto.sourceDevice = valueParam
        }

        @objc public func setRelay(_ valueParam: String) {
            proto.relay = valueParam
        }

        @objc public func setTimestamp(_ valueParam: UInt64) {
            proto.timestamp = valueParam
        }

        @objc public func setLegacyMessage(_ valueParam: Data) {
            proto.legacyMessage = valueParam
        }

        @objc public func setContent(_ valueParam: Data) {
            proto.content = valueParam
        }

        @objc public func build() throws -> SSKProtoEnvelope {
            return try SSKProtoEnvelope.parseProto(proto)
        }

        @objc public func buildSerializedData() throws -> Data {
            return try SSKProtoEnvelope.parseProto(proto).serializedData()
        }
    }

    fileprivate let proto: SignalServiceProtos_Envelope

    @objc public let type: SSKProtoEnvelopeType

    @objc public let source: String

    @objc public let sourceDevice: UInt32

    @objc public let timestamp: UInt64

    @objc public var relay: String? {
        guard proto.hasRelay else {
            return nil
        }
        return proto.relay
    }
    @objc public var hasRelay: Bool {
        return proto.hasRelay
    }

    @objc public var legacyMessage: Data? {
        guard proto.hasLegacyMessage else {
            return nil
        }
        return proto.legacyMessage
    }
    @objc public var hasLegacyMessage: Bool {
        return proto.hasLegacyMessage
    }

    @objc public var content: Data? {
        guard proto.hasContent else {
            return nil
        }
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

#if DEBUG

extension SSKProtoEnvelope {
    @objc public func serializedDataIgnoringErrors() -> Data? {
        return try! self.serializedData()
    }
}

extension SSKProtoEnvelope.SSKProtoEnvelopeBuilder {
    @objc public func buildIgnoringErrors() -> SSKProtoEnvelope? {
        return try! self.build()
    }
}

#endif

// MARK: - SSKProtoContent

@objc public class SSKProtoContent: NSObject {

    // MARK: - SSKProtoContentBuilder

    @objc public class SSKProtoContentBuilder: NSObject {

        private var proto = SignalServiceProtos_Content()

        @objc public override init() {}

        @objc public func setDataMessage(_ valueParam: SSKProtoDataMessage) {
            proto.dataMessage = valueParam.proto
        }

        @objc public func setSyncMessage(_ valueParam: SSKProtoSyncMessage) {
            proto.syncMessage = valueParam.proto
        }

        @objc public func setCallMessage(_ valueParam: SSKProtoCallMessage) {
            proto.callMessage = valueParam.proto
        }

        @objc public func setNullMessage(_ valueParam: SSKProtoNullMessage) {
            proto.nullMessage = valueParam.proto
        }

        @objc public func setReceiptMessage(_ valueParam: SSKProtoReceiptMessage) {
            proto.receiptMessage = valueParam.proto
        }

        @objc public func build() throws -> SSKProtoContent {
            return try SSKProtoContent.parseProto(proto)
        }

        @objc public func buildSerializedData() throws -> Data {
            return try SSKProtoContent.parseProto(proto).serializedData()
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

#if DEBUG

extension SSKProtoContent {
    @objc public func serializedDataIgnoringErrors() -> Data? {
        return try! self.serializedData()
    }
}

extension SSKProtoContent.SSKProtoContentBuilder {
    @objc public func buildIgnoringErrors() -> SSKProtoContent? {
        return try! self.build()
    }
}

#endif

// MARK: - SSKProtoCallMessageOffer

@objc public class SSKProtoCallMessageOffer: NSObject {

    // MARK: - SSKProtoCallMessageOfferBuilder

    @objc public class SSKProtoCallMessageOfferBuilder: NSObject {

        private var proto = SignalServiceProtos_CallMessage.Offer()

        @objc public override init() {}

        // Initializer for required fields
        @objc public init(id: UInt64, sessionDescription: String) {
            super.init()

            setId(id)
            setSessionDescription(sessionDescription)
        }

        @objc public func setId(_ valueParam: UInt64) {
            proto.id = valueParam
        }

        @objc public func setSessionDescription(_ valueParam: String) {
            proto.sessionDescription = valueParam
        }

        @objc public func build() throws -> SSKProtoCallMessageOffer {
            return try SSKProtoCallMessageOffer.parseProto(proto)
        }

        @objc public func buildSerializedData() throws -> Data {
            return try SSKProtoCallMessageOffer.parseProto(proto).serializedData()
        }
    }

    fileprivate let proto: SignalServiceProtos_CallMessage.Offer

    @objc public let id: UInt64

    @objc public let sessionDescription: String

    private init(proto: SignalServiceProtos_CallMessage.Offer,
                 id: UInt64,
                 sessionDescription: String) {
        self.proto = proto
        self.id = id
        self.sessionDescription = sessionDescription
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

        guard proto.hasSessionDescription else {
            throw SSKProtoError.invalidProtobuf(description: "\(logTag) missing required field: sessionDescription")
        }
        let sessionDescription = proto.sessionDescription

        // MARK: - Begin Validation Logic for SSKProtoCallMessageOffer -

        // MARK: - End Validation Logic for SSKProtoCallMessageOffer -

        let result = SSKProtoCallMessageOffer(proto: proto,
                                              id: id,
                                              sessionDescription: sessionDescription)
        return result
    }
}

#if DEBUG

extension SSKProtoCallMessageOffer {
    @objc public func serializedDataIgnoringErrors() -> Data? {
        return try! self.serializedData()
    }
}

extension SSKProtoCallMessageOffer.SSKProtoCallMessageOfferBuilder {
    @objc public func buildIgnoringErrors() -> SSKProtoCallMessageOffer? {
        return try! self.build()
    }
}

#endif

// MARK: - SSKProtoCallMessageAnswer

@objc public class SSKProtoCallMessageAnswer: NSObject {

    // MARK: - SSKProtoCallMessageAnswerBuilder

    @objc public class SSKProtoCallMessageAnswerBuilder: NSObject {

        private var proto = SignalServiceProtos_CallMessage.Answer()

        @objc public override init() {}

        // Initializer for required fields
        @objc public init(id: UInt64, sessionDescription: String) {
            super.init()

            setId(id)
            setSessionDescription(sessionDescription)
        }

        @objc public func setId(_ valueParam: UInt64) {
            proto.id = valueParam
        }

        @objc public func setSessionDescription(_ valueParam: String) {
            proto.sessionDescription = valueParam
        }

        @objc public func build() throws -> SSKProtoCallMessageAnswer {
            return try SSKProtoCallMessageAnswer.parseProto(proto)
        }

        @objc public func buildSerializedData() throws -> Data {
            return try SSKProtoCallMessageAnswer.parseProto(proto).serializedData()
        }
    }

    fileprivate let proto: SignalServiceProtos_CallMessage.Answer

    @objc public let id: UInt64

    @objc public let sessionDescription: String

    private init(proto: SignalServiceProtos_CallMessage.Answer,
                 id: UInt64,
                 sessionDescription: String) {
        self.proto = proto
        self.id = id
        self.sessionDescription = sessionDescription
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

        guard proto.hasSessionDescription else {
            throw SSKProtoError.invalidProtobuf(description: "\(logTag) missing required field: sessionDescription")
        }
        let sessionDescription = proto.sessionDescription

        // MARK: - Begin Validation Logic for SSKProtoCallMessageAnswer -

        // MARK: - End Validation Logic for SSKProtoCallMessageAnswer -

        let result = SSKProtoCallMessageAnswer(proto: proto,
                                               id: id,
                                               sessionDescription: sessionDescription)
        return result
    }
}

#if DEBUG

extension SSKProtoCallMessageAnswer {
    @objc public func serializedDataIgnoringErrors() -> Data? {
        return try! self.serializedData()
    }
}

extension SSKProtoCallMessageAnswer.SSKProtoCallMessageAnswerBuilder {
    @objc public func buildIgnoringErrors() -> SSKProtoCallMessageAnswer? {
        return try! self.build()
    }
}

#endif

// MARK: - SSKProtoCallMessageIceUpdate

@objc public class SSKProtoCallMessageIceUpdate: NSObject {

    // MARK: - SSKProtoCallMessageIceUpdateBuilder

    @objc public class SSKProtoCallMessageIceUpdateBuilder: NSObject {

        private var proto = SignalServiceProtos_CallMessage.IceUpdate()

        @objc public override init() {}

        // Initializer for required fields
        @objc public init(id: UInt64, sdpMid: String, sdpMlineIndex: UInt32, sdp: String) {
            super.init()

            setId(id)
            setSdpMid(sdpMid)
            setSdpMlineIndex(sdpMlineIndex)
            setSdp(sdp)
        }

        @objc public func setId(_ valueParam: UInt64) {
            proto.id = valueParam
        }

        @objc public func setSdpMid(_ valueParam: String) {
            proto.sdpMid = valueParam
        }

        @objc public func setSdpMlineIndex(_ valueParam: UInt32) {
            proto.sdpMlineIndex = valueParam
        }

        @objc public func setSdp(_ valueParam: String) {
            proto.sdp = valueParam
        }

        @objc public func build() throws -> SSKProtoCallMessageIceUpdate {
            return try SSKProtoCallMessageIceUpdate.parseProto(proto)
        }

        @objc public func buildSerializedData() throws -> Data {
            return try SSKProtoCallMessageIceUpdate.parseProto(proto).serializedData()
        }
    }

    fileprivate let proto: SignalServiceProtos_CallMessage.IceUpdate

    @objc public let id: UInt64

    @objc public let sdpMid: String

    @objc public let sdpMlineIndex: UInt32

    @objc public let sdp: String

    private init(proto: SignalServiceProtos_CallMessage.IceUpdate,
                 id: UInt64,
                 sdpMid: String,
                 sdpMlineIndex: UInt32,
                 sdp: String) {
        self.proto = proto
        self.id = id
        self.sdpMid = sdpMid
        self.sdpMlineIndex = sdpMlineIndex
        self.sdp = sdp
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

        guard proto.hasSdpMid else {
            throw SSKProtoError.invalidProtobuf(description: "\(logTag) missing required field: sdpMid")
        }
        let sdpMid = proto.sdpMid

        guard proto.hasSdpMlineIndex else {
            throw SSKProtoError.invalidProtobuf(description: "\(logTag) missing required field: sdpMlineIndex")
        }
        let sdpMlineIndex = proto.sdpMlineIndex

        guard proto.hasSdp else {
            throw SSKProtoError.invalidProtobuf(description: "\(logTag) missing required field: sdp")
        }
        let sdp = proto.sdp

        // MARK: - Begin Validation Logic for SSKProtoCallMessageIceUpdate -

        // MARK: - End Validation Logic for SSKProtoCallMessageIceUpdate -

        let result = SSKProtoCallMessageIceUpdate(proto: proto,
                                                  id: id,
                                                  sdpMid: sdpMid,
                                                  sdpMlineIndex: sdpMlineIndex,
                                                  sdp: sdp)
        return result
    }
}

#if DEBUG

extension SSKProtoCallMessageIceUpdate {
    @objc public func serializedDataIgnoringErrors() -> Data? {
        return try! self.serializedData()
    }
}

extension SSKProtoCallMessageIceUpdate.SSKProtoCallMessageIceUpdateBuilder {
    @objc public func buildIgnoringErrors() -> SSKProtoCallMessageIceUpdate? {
        return try! self.build()
    }
}

#endif

// MARK: - SSKProtoCallMessageBusy

@objc public class SSKProtoCallMessageBusy: NSObject {

    // MARK: - SSKProtoCallMessageBusyBuilder

    @objc public class SSKProtoCallMessageBusyBuilder: NSObject {

        private var proto = SignalServiceProtos_CallMessage.Busy()

        @objc public override init() {}

        // Initializer for required fields
        @objc public init(id: UInt64) {
            super.init()

            setId(id)
        }

        @objc public func setId(_ valueParam: UInt64) {
            proto.id = valueParam
        }

        @objc public func build() throws -> SSKProtoCallMessageBusy {
            return try SSKProtoCallMessageBusy.parseProto(proto)
        }

        @objc public func buildSerializedData() throws -> Data {
            return try SSKProtoCallMessageBusy.parseProto(proto).serializedData()
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

#if DEBUG

extension SSKProtoCallMessageBusy {
    @objc public func serializedDataIgnoringErrors() -> Data? {
        return try! self.serializedData()
    }
}

extension SSKProtoCallMessageBusy.SSKProtoCallMessageBusyBuilder {
    @objc public func buildIgnoringErrors() -> SSKProtoCallMessageBusy? {
        return try! self.build()
    }
}

#endif

// MARK: - SSKProtoCallMessageHangup

@objc public class SSKProtoCallMessageHangup: NSObject {

    // MARK: - SSKProtoCallMessageHangupBuilder

    @objc public class SSKProtoCallMessageHangupBuilder: NSObject {

        private var proto = SignalServiceProtos_CallMessage.Hangup()

        @objc public override init() {}

        // Initializer for required fields
        @objc public init(id: UInt64) {
            super.init()

            setId(id)
        }

        @objc public func setId(_ valueParam: UInt64) {
            proto.id = valueParam
        }

        @objc public func build() throws -> SSKProtoCallMessageHangup {
            return try SSKProtoCallMessageHangup.parseProto(proto)
        }

        @objc public func buildSerializedData() throws -> Data {
            return try SSKProtoCallMessageHangup.parseProto(proto).serializedData()
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

#if DEBUG

extension SSKProtoCallMessageHangup {
    @objc public func serializedDataIgnoringErrors() -> Data? {
        return try! self.serializedData()
    }
}

extension SSKProtoCallMessageHangup.SSKProtoCallMessageHangupBuilder {
    @objc public func buildIgnoringErrors() -> SSKProtoCallMessageHangup? {
        return try! self.build()
    }
}

#endif

// MARK: - SSKProtoCallMessage

@objc public class SSKProtoCallMessage: NSObject {

    // MARK: - SSKProtoCallMessageBuilder

    @objc public class SSKProtoCallMessageBuilder: NSObject {

        private var proto = SignalServiceProtos_CallMessage()

        @objc public override init() {}

        @objc public func setOffer(_ valueParam: SSKProtoCallMessageOffer) {
            proto.offer = valueParam.proto
        }

        @objc public func setAnswer(_ valueParam: SSKProtoCallMessageAnswer) {
            proto.answer = valueParam.proto
        }

        @objc public func addIceUpdate(_ valueParam: SSKProtoCallMessageIceUpdate) {
            var items = proto.iceUpdate
            items.append(valueParam.proto)
            proto.iceUpdate = items
        }

        @objc public func setIceUpdate(_ wrappedItems: [SSKProtoCallMessageIceUpdate]) {
            proto.iceUpdate = wrappedItems.map { $0.proto }
        }

        @objc public func setHangup(_ valueParam: SSKProtoCallMessageHangup) {
            proto.hangup = valueParam.proto
        }

        @objc public func setBusy(_ valueParam: SSKProtoCallMessageBusy) {
            proto.busy = valueParam.proto
        }

        @objc public func setProfileKey(_ valueParam: Data) {
            proto.profileKey = valueParam
        }

        @objc public func build() throws -> SSKProtoCallMessage {
            return try SSKProtoCallMessage.parseProto(proto)
        }

        @objc public func buildSerializedData() throws -> Data {
            return try SSKProtoCallMessage.parseProto(proto).serializedData()
        }
    }

    fileprivate let proto: SignalServiceProtos_CallMessage

    @objc public let offer: SSKProtoCallMessageOffer?

    @objc public let answer: SSKProtoCallMessageAnswer?

    @objc public let iceUpdate: [SSKProtoCallMessageIceUpdate]

    @objc public let hangup: SSKProtoCallMessageHangup?

    @objc public let busy: SSKProtoCallMessageBusy?

    @objc public var profileKey: Data? {
        guard proto.hasProfileKey else {
            return nil
        }
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
        iceUpdate = try proto.iceUpdate.map { try SSKProtoCallMessageIceUpdate.parseProto($0) }

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

#if DEBUG

extension SSKProtoCallMessage {
    @objc public func serializedDataIgnoringErrors() -> Data? {
        return try! self.serializedData()
    }
}

extension SSKProtoCallMessage.SSKProtoCallMessageBuilder {
    @objc public func buildIgnoringErrors() -> SSKProtoCallMessage? {
        return try! self.build()
    }
}

#endif

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

        private var proto = SignalServiceProtos_DataMessage.Quote.QuotedAttachment()

        @objc public override init() {}

        @objc public func setContentType(_ valueParam: String) {
            proto.contentType = valueParam
        }

        @objc public func setFileName(_ valueParam: String) {
            proto.fileName = valueParam
        }

        @objc public func setThumbnail(_ valueParam: SSKProtoAttachmentPointer) {
            proto.thumbnail = valueParam.proto
        }

        @objc public func setFlags(_ valueParam: UInt32) {
            proto.flags = valueParam
        }

        @objc public func build() throws -> SSKProtoDataMessageQuoteQuotedAttachment {
            return try SSKProtoDataMessageQuoteQuotedAttachment.parseProto(proto)
        }

        @objc public func buildSerializedData() throws -> Data {
            return try SSKProtoDataMessageQuoteQuotedAttachment.parseProto(proto).serializedData()
        }
    }

    fileprivate let proto: SignalServiceProtos_DataMessage.Quote.QuotedAttachment

    @objc public let thumbnail: SSKProtoAttachmentPointer?

    @objc public var contentType: String? {
        guard proto.hasContentType else {
            return nil
        }
        return proto.contentType
    }
    @objc public var hasContentType: Bool {
        return proto.hasContentType
    }

    @objc public var fileName: String? {
        guard proto.hasFileName else {
            return nil
        }
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

#if DEBUG

extension SSKProtoDataMessageQuoteQuotedAttachment {
    @objc public func serializedDataIgnoringErrors() -> Data? {
        return try! self.serializedData()
    }
}

extension SSKProtoDataMessageQuoteQuotedAttachment.SSKProtoDataMessageQuoteQuotedAttachmentBuilder {
    @objc public func buildIgnoringErrors() -> SSKProtoDataMessageQuoteQuotedAttachment? {
        return try! self.build()
    }
}

#endif

// MARK: - SSKProtoDataMessageQuote

@objc public class SSKProtoDataMessageQuote: NSObject {

    // MARK: - SSKProtoDataMessageQuoteBuilder

    @objc public class SSKProtoDataMessageQuoteBuilder: NSObject {

        private var proto = SignalServiceProtos_DataMessage.Quote()

        @objc public override init() {}

        // Initializer for required fields
        @objc public init(id: UInt64, author: String) {
            super.init()

            setId(id)
            setAuthor(author)
        }

        @objc public func setId(_ valueParam: UInt64) {
            proto.id = valueParam
        }

        @objc public func setAuthor(_ valueParam: String) {
            proto.author = valueParam
        }

        @objc public func setText(_ valueParam: String) {
            proto.text = valueParam
        }

        @objc public func addAttachments(_ valueParam: SSKProtoDataMessageQuoteQuotedAttachment) {
            var items = proto.attachments
            items.append(valueParam.proto)
            proto.attachments = items
        }

        @objc public func setAttachments(_ wrappedItems: [SSKProtoDataMessageQuoteQuotedAttachment]) {
            proto.attachments = wrappedItems.map { $0.proto }
        }

        @objc public func build() throws -> SSKProtoDataMessageQuote {
            return try SSKProtoDataMessageQuote.parseProto(proto)
        }

        @objc public func buildSerializedData() throws -> Data {
            return try SSKProtoDataMessageQuote.parseProto(proto).serializedData()
        }
    }

    fileprivate let proto: SignalServiceProtos_DataMessage.Quote

    @objc public let id: UInt64

    @objc public let author: String

    @objc public let attachments: [SSKProtoDataMessageQuoteQuotedAttachment]

    @objc public var text: String? {
        guard proto.hasText else {
            return nil
        }
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
        attachments = try proto.attachments.map { try SSKProtoDataMessageQuoteQuotedAttachment.parseProto($0) }

        // MARK: - Begin Validation Logic for SSKProtoDataMessageQuote -

        // MARK: - End Validation Logic for SSKProtoDataMessageQuote -

        let result = SSKProtoDataMessageQuote(proto: proto,
                                              id: id,
                                              author: author,
                                              attachments: attachments)
        return result
    }
}

#if DEBUG

extension SSKProtoDataMessageQuote {
    @objc public func serializedDataIgnoringErrors() -> Data? {
        return try! self.serializedData()
    }
}

extension SSKProtoDataMessageQuote.SSKProtoDataMessageQuoteBuilder {
    @objc public func buildIgnoringErrors() -> SSKProtoDataMessageQuote? {
        return try! self.build()
    }
}

#endif

// MARK: - SSKProtoDataMessageContactName

@objc public class SSKProtoDataMessageContactName: NSObject {

    // MARK: - SSKProtoDataMessageContactNameBuilder

    @objc public class SSKProtoDataMessageContactNameBuilder: NSObject {

        private var proto = SignalServiceProtos_DataMessage.Contact.Name()

        @objc public override init() {}

        @objc public func setGivenName(_ valueParam: String) {
            proto.givenName = valueParam
        }

        @objc public func setFamilyName(_ valueParam: String) {
            proto.familyName = valueParam
        }

        @objc public func setPrefix(_ valueParam: String) {
            proto.prefix = valueParam
        }

        @objc public func setSuffix(_ valueParam: String) {
            proto.suffix = valueParam
        }

        @objc public func setMiddleName(_ valueParam: String) {
            proto.middleName = valueParam
        }

        @objc public func setDisplayName(_ valueParam: String) {
            proto.displayName = valueParam
        }

        @objc public func build() throws -> SSKProtoDataMessageContactName {
            return try SSKProtoDataMessageContactName.parseProto(proto)
        }

        @objc public func buildSerializedData() throws -> Data {
            return try SSKProtoDataMessageContactName.parseProto(proto).serializedData()
        }
    }

    fileprivate let proto: SignalServiceProtos_DataMessage.Contact.Name

    @objc public var givenName: String? {
        guard proto.hasGivenName else {
            return nil
        }
        return proto.givenName
    }
    @objc public var hasGivenName: Bool {
        return proto.hasGivenName
    }

    @objc public var familyName: String? {
        guard proto.hasFamilyName else {
            return nil
        }
        return proto.familyName
    }
    @objc public var hasFamilyName: Bool {
        return proto.hasFamilyName
    }

    @objc public var prefix: String? {
        guard proto.hasPrefix else {
            return nil
        }
        return proto.prefix
    }
    @objc public var hasPrefix: Bool {
        return proto.hasPrefix
    }

    @objc public var suffix: String? {
        guard proto.hasSuffix else {
            return nil
        }
        return proto.suffix
    }
    @objc public var hasSuffix: Bool {
        return proto.hasSuffix
    }

    @objc public var middleName: String? {
        guard proto.hasMiddleName else {
            return nil
        }
        return proto.middleName
    }
    @objc public var hasMiddleName: Bool {
        return proto.hasMiddleName
    }

    @objc public var displayName: String? {
        guard proto.hasDisplayName else {
            return nil
        }
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

#if DEBUG

extension SSKProtoDataMessageContactName {
    @objc public func serializedDataIgnoringErrors() -> Data? {
        return try! self.serializedData()
    }
}

extension SSKProtoDataMessageContactName.SSKProtoDataMessageContactNameBuilder {
    @objc public func buildIgnoringErrors() -> SSKProtoDataMessageContactName? {
        return try! self.build()
    }
}

#endif

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

        private var proto = SignalServiceProtos_DataMessage.Contact.Phone()

        @objc public override init() {}

        @objc public func setValue(_ valueParam: String) {
            proto.value = valueParam
        }

        @objc public func setType(_ valueParam: SSKProtoDataMessageContactPhoneType) {
            proto.type = SSKProtoDataMessageContactPhoneTypeUnwrap(valueParam)
        }

        @objc public func setLabel(_ valueParam: String) {
            proto.label = valueParam
        }

        @objc public func build() throws -> SSKProtoDataMessageContactPhone {
            return try SSKProtoDataMessageContactPhone.parseProto(proto)
        }

        @objc public func buildSerializedData() throws -> Data {
            return try SSKProtoDataMessageContactPhone.parseProto(proto).serializedData()
        }
    }

    fileprivate let proto: SignalServiceProtos_DataMessage.Contact.Phone

    @objc public var value: String? {
        guard proto.hasValue else {
            return nil
        }
        return proto.value
    }
    @objc public var hasValue: Bool {
        return proto.hasValue
    }

    @objc public var type: SSKProtoDataMessageContactPhoneType {
        return SSKProtoDataMessageContactPhone.SSKProtoDataMessageContactPhoneTypeWrap(proto.type)
    }
    @objc public var hasType: Bool {
        return proto.hasType
    }

    @objc public var label: String? {
        guard proto.hasLabel else {
            return nil
        }
        return proto.label
    }
    @objc public var hasLabel: Bool {
        return proto.hasLabel
    }

    private init(proto: SignalServiceProtos_DataMessage.Contact.Phone) {
        self.proto = proto
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
        // MARK: - Begin Validation Logic for SSKProtoDataMessageContactPhone -

        // MARK: - End Validation Logic for SSKProtoDataMessageContactPhone -

        let result = SSKProtoDataMessageContactPhone(proto: proto)
        return result
    }
}

#if DEBUG

extension SSKProtoDataMessageContactPhone {
    @objc public func serializedDataIgnoringErrors() -> Data? {
        return try! self.serializedData()
    }
}

extension SSKProtoDataMessageContactPhone.SSKProtoDataMessageContactPhoneBuilder {
    @objc public func buildIgnoringErrors() -> SSKProtoDataMessageContactPhone? {
        return try! self.build()
    }
}

#endif

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

        private var proto = SignalServiceProtos_DataMessage.Contact.Email()

        @objc public override init() {}

        @objc public func setValue(_ valueParam: String) {
            proto.value = valueParam
        }

        @objc public func setType(_ valueParam: SSKProtoDataMessageContactEmailType) {
            proto.type = SSKProtoDataMessageContactEmailTypeUnwrap(valueParam)
        }

        @objc public func setLabel(_ valueParam: String) {
            proto.label = valueParam
        }

        @objc public func build() throws -> SSKProtoDataMessageContactEmail {
            return try SSKProtoDataMessageContactEmail.parseProto(proto)
        }

        @objc public func buildSerializedData() throws -> Data {
            return try SSKProtoDataMessageContactEmail.parseProto(proto).serializedData()
        }
    }

    fileprivate let proto: SignalServiceProtos_DataMessage.Contact.Email

    @objc public var value: String? {
        guard proto.hasValue else {
            return nil
        }
        return proto.value
    }
    @objc public var hasValue: Bool {
        return proto.hasValue
    }

    @objc public var type: SSKProtoDataMessageContactEmailType {
        return SSKProtoDataMessageContactEmail.SSKProtoDataMessageContactEmailTypeWrap(proto.type)
    }
    @objc public var hasType: Bool {
        return proto.hasType
    }

    @objc public var label: String? {
        guard proto.hasLabel else {
            return nil
        }
        return proto.label
    }
    @objc public var hasLabel: Bool {
        return proto.hasLabel
    }

    private init(proto: SignalServiceProtos_DataMessage.Contact.Email) {
        self.proto = proto
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
        // MARK: - Begin Validation Logic for SSKProtoDataMessageContactEmail -

        // MARK: - End Validation Logic for SSKProtoDataMessageContactEmail -

        let result = SSKProtoDataMessageContactEmail(proto: proto)
        return result
    }
}

#if DEBUG

extension SSKProtoDataMessageContactEmail {
    @objc public func serializedDataIgnoringErrors() -> Data? {
        return try! self.serializedData()
    }
}

extension SSKProtoDataMessageContactEmail.SSKProtoDataMessageContactEmailBuilder {
    @objc public func buildIgnoringErrors() -> SSKProtoDataMessageContactEmail? {
        return try! self.build()
    }
}

#endif

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

        private var proto = SignalServiceProtos_DataMessage.Contact.PostalAddress()

        @objc public override init() {}

        @objc public func setType(_ valueParam: SSKProtoDataMessageContactPostalAddressType) {
            proto.type = SSKProtoDataMessageContactPostalAddressTypeUnwrap(valueParam)
        }

        @objc public func setLabel(_ valueParam: String) {
            proto.label = valueParam
        }

        @objc public func setStreet(_ valueParam: String) {
            proto.street = valueParam
        }

        @objc public func setPobox(_ valueParam: String) {
            proto.pobox = valueParam
        }

        @objc public func setNeighborhood(_ valueParam: String) {
            proto.neighborhood = valueParam
        }

        @objc public func setCity(_ valueParam: String) {
            proto.city = valueParam
        }

        @objc public func setRegion(_ valueParam: String) {
            proto.region = valueParam
        }

        @objc public func setPostcode(_ valueParam: String) {
            proto.postcode = valueParam
        }

        @objc public func setCountry(_ valueParam: String) {
            proto.country = valueParam
        }

        @objc public func build() throws -> SSKProtoDataMessageContactPostalAddress {
            return try SSKProtoDataMessageContactPostalAddress.parseProto(proto)
        }

        @objc public func buildSerializedData() throws -> Data {
            return try SSKProtoDataMessageContactPostalAddress.parseProto(proto).serializedData()
        }
    }

    fileprivate let proto: SignalServiceProtos_DataMessage.Contact.PostalAddress

    @objc public var type: SSKProtoDataMessageContactPostalAddressType {
        return SSKProtoDataMessageContactPostalAddress.SSKProtoDataMessageContactPostalAddressTypeWrap(proto.type)
    }
    @objc public var hasType: Bool {
        return proto.hasType
    }

    @objc public var label: String? {
        guard proto.hasLabel else {
            return nil
        }
        return proto.label
    }
    @objc public var hasLabel: Bool {
        return proto.hasLabel
    }

    @objc public var street: String? {
        guard proto.hasStreet else {
            return nil
        }
        return proto.street
    }
    @objc public var hasStreet: Bool {
        return proto.hasStreet
    }

    @objc public var pobox: String? {
        guard proto.hasPobox else {
            return nil
        }
        return proto.pobox
    }
    @objc public var hasPobox: Bool {
        return proto.hasPobox
    }

    @objc public var neighborhood: String? {
        guard proto.hasNeighborhood else {
            return nil
        }
        return proto.neighborhood
    }
    @objc public var hasNeighborhood: Bool {
        return proto.hasNeighborhood
    }

    @objc public var city: String? {
        guard proto.hasCity else {
            return nil
        }
        return proto.city
    }
    @objc public var hasCity: Bool {
        return proto.hasCity
    }

    @objc public var region: String? {
        guard proto.hasRegion else {
            return nil
        }
        return proto.region
    }
    @objc public var hasRegion: Bool {
        return proto.hasRegion
    }

    @objc public var postcode: String? {
        guard proto.hasPostcode else {
            return nil
        }
        return proto.postcode
    }
    @objc public var hasPostcode: Bool {
        return proto.hasPostcode
    }

    @objc public var country: String? {
        guard proto.hasCountry else {
            return nil
        }
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

#if DEBUG

extension SSKProtoDataMessageContactPostalAddress {
    @objc public func serializedDataIgnoringErrors() -> Data? {
        return try! self.serializedData()
    }
}

extension SSKProtoDataMessageContactPostalAddress.SSKProtoDataMessageContactPostalAddressBuilder {
    @objc public func buildIgnoringErrors() -> SSKProtoDataMessageContactPostalAddress? {
        return try! self.build()
    }
}

#endif

// MARK: - SSKProtoDataMessageContactAvatar

@objc public class SSKProtoDataMessageContactAvatar: NSObject {

    // MARK: - SSKProtoDataMessageContactAvatarBuilder

    @objc public class SSKProtoDataMessageContactAvatarBuilder: NSObject {

        private var proto = SignalServiceProtos_DataMessage.Contact.Avatar()

        @objc public override init() {}

        @objc public func setAvatar(_ valueParam: SSKProtoAttachmentPointer) {
            proto.avatar = valueParam.proto
        }

        @objc public func setIsProfile(_ valueParam: Bool) {
            proto.isProfile = valueParam
        }

        @objc public func build() throws -> SSKProtoDataMessageContactAvatar {
            return try SSKProtoDataMessageContactAvatar.parseProto(proto)
        }

        @objc public func buildSerializedData() throws -> Data {
            return try SSKProtoDataMessageContactAvatar.parseProto(proto).serializedData()
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

#if DEBUG

extension SSKProtoDataMessageContactAvatar {
    @objc public func serializedDataIgnoringErrors() -> Data? {
        return try! self.serializedData()
    }
}

extension SSKProtoDataMessageContactAvatar.SSKProtoDataMessageContactAvatarBuilder {
    @objc public func buildIgnoringErrors() -> SSKProtoDataMessageContactAvatar? {
        return try! self.build()
    }
}

#endif

// MARK: - SSKProtoDataMessageContact

@objc public class SSKProtoDataMessageContact: NSObject {

    // MARK: - SSKProtoDataMessageContactBuilder

    @objc public class SSKProtoDataMessageContactBuilder: NSObject {

        private var proto = SignalServiceProtos_DataMessage.Contact()

        @objc public override init() {}

        @objc public func setName(_ valueParam: SSKProtoDataMessageContactName) {
            proto.name = valueParam.proto
        }

        @objc public func addNumber(_ valueParam: SSKProtoDataMessageContactPhone) {
            var items = proto.number
            items.append(valueParam.proto)
            proto.number = items
        }

        @objc public func setNumber(_ wrappedItems: [SSKProtoDataMessageContactPhone]) {
            proto.number = wrappedItems.map { $0.proto }
        }

        @objc public func addEmail(_ valueParam: SSKProtoDataMessageContactEmail) {
            var items = proto.email
            items.append(valueParam.proto)
            proto.email = items
        }

        @objc public func setEmail(_ wrappedItems: [SSKProtoDataMessageContactEmail]) {
            proto.email = wrappedItems.map { $0.proto }
        }

        @objc public func addAddress(_ valueParam: SSKProtoDataMessageContactPostalAddress) {
            var items = proto.address
            items.append(valueParam.proto)
            proto.address = items
        }

        @objc public func setAddress(_ wrappedItems: [SSKProtoDataMessageContactPostalAddress]) {
            proto.address = wrappedItems.map { $0.proto }
        }

        @objc public func setAvatar(_ valueParam: SSKProtoDataMessageContactAvatar) {
            proto.avatar = valueParam.proto
        }

        @objc public func setOrganization(_ valueParam: String) {
            proto.organization = valueParam
        }

        @objc public func build() throws -> SSKProtoDataMessageContact {
            return try SSKProtoDataMessageContact.parseProto(proto)
        }

        @objc public func buildSerializedData() throws -> Data {
            return try SSKProtoDataMessageContact.parseProto(proto).serializedData()
        }
    }

    fileprivate let proto: SignalServiceProtos_DataMessage.Contact

    @objc public let name: SSKProtoDataMessageContactName?

    @objc public let number: [SSKProtoDataMessageContactPhone]

    @objc public let email: [SSKProtoDataMessageContactEmail]

    @objc public let address: [SSKProtoDataMessageContactPostalAddress]

    @objc public let avatar: SSKProtoDataMessageContactAvatar?

    @objc public var organization: String? {
        guard proto.hasOrganization else {
            return nil
        }
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
        number = try proto.number.map { try SSKProtoDataMessageContactPhone.parseProto($0) }

        var email: [SSKProtoDataMessageContactEmail] = []
        email = try proto.email.map { try SSKProtoDataMessageContactEmail.parseProto($0) }

        var address: [SSKProtoDataMessageContactPostalAddress] = []
        address = try proto.address.map { try SSKProtoDataMessageContactPostalAddress.parseProto($0) }

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

#if DEBUG

extension SSKProtoDataMessageContact {
    @objc public func serializedDataIgnoringErrors() -> Data? {
        return try! self.serializedData()
    }
}

extension SSKProtoDataMessageContact.SSKProtoDataMessageContactBuilder {
    @objc public func buildIgnoringErrors() -> SSKProtoDataMessageContact? {
        return try! self.build()
    }
}

#endif

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

        private var proto = SignalServiceProtos_DataMessage()

        @objc public override init() {}

        @objc public func setBody(_ valueParam: String) {
            proto.body = valueParam
        }

        @objc public func addAttachments(_ valueParam: SSKProtoAttachmentPointer) {
            var items = proto.attachments
            items.append(valueParam.proto)
            proto.attachments = items
        }

        @objc public func setAttachments(_ wrappedItems: [SSKProtoAttachmentPointer]) {
            proto.attachments = wrappedItems.map { $0.proto }
        }

        @objc public func setGroup(_ valueParam: SSKProtoGroupContext) {
            proto.group = valueParam.proto
        }

        @objc public func setFlags(_ valueParam: UInt32) {
            proto.flags = valueParam
        }

        @objc public func setExpireTimer(_ valueParam: UInt32) {
            proto.expireTimer = valueParam
        }

        @objc public func setProfileKey(_ valueParam: Data) {
            proto.profileKey = valueParam
        }

        @objc public func setTimestamp(_ valueParam: UInt64) {
            proto.timestamp = valueParam
        }

        @objc public func setQuote(_ valueParam: SSKProtoDataMessageQuote) {
            proto.quote = valueParam.proto
        }

        @objc public func addContact(_ valueParam: SSKProtoDataMessageContact) {
            var items = proto.contact
            items.append(valueParam.proto)
            proto.contact = items
        }

        @objc public func setContact(_ wrappedItems: [SSKProtoDataMessageContact]) {
            proto.contact = wrappedItems.map { $0.proto }
        }

        @objc public func build() throws -> SSKProtoDataMessage {
            return try SSKProtoDataMessage.parseProto(proto)
        }

        @objc public func buildSerializedData() throws -> Data {
            return try SSKProtoDataMessage.parseProto(proto).serializedData()
        }
    }

    fileprivate let proto: SignalServiceProtos_DataMessage

    @objc public let attachments: [SSKProtoAttachmentPointer]

    @objc public let group: SSKProtoGroupContext?

    @objc public let quote: SSKProtoDataMessageQuote?

    @objc public let contact: [SSKProtoDataMessageContact]

    @objc public var body: String? {
        guard proto.hasBody else {
            return nil
        }
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

    @objc public var profileKey: Data? {
        guard proto.hasProfileKey else {
            return nil
        }
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
        attachments = try proto.attachments.map { try SSKProtoAttachmentPointer.parseProto($0) }

        var group: SSKProtoGroupContext? = nil
        if proto.hasGroup {
            group = try SSKProtoGroupContext.parseProto(proto.group)
        }

        var quote: SSKProtoDataMessageQuote? = nil
        if proto.hasQuote {
            quote = try SSKProtoDataMessageQuote.parseProto(proto.quote)
        }

        var contact: [SSKProtoDataMessageContact] = []
        contact = try proto.contact.map { try SSKProtoDataMessageContact.parseProto($0) }

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

#if DEBUG

extension SSKProtoDataMessage {
    @objc public func serializedDataIgnoringErrors() -> Data? {
        return try! self.serializedData()
    }
}

extension SSKProtoDataMessage.SSKProtoDataMessageBuilder {
    @objc public func buildIgnoringErrors() -> SSKProtoDataMessage? {
        return try! self.build()
    }
}

#endif

// MARK: - SSKProtoNullMessage

@objc public class SSKProtoNullMessage: NSObject {

    // MARK: - SSKProtoNullMessageBuilder

    @objc public class SSKProtoNullMessageBuilder: NSObject {

        private var proto = SignalServiceProtos_NullMessage()

        @objc public override init() {}

        @objc public func setPadding(_ valueParam: Data) {
            proto.padding = valueParam
        }

        @objc public func build() throws -> SSKProtoNullMessage {
            return try SSKProtoNullMessage.parseProto(proto)
        }

        @objc public func buildSerializedData() throws -> Data {
            return try SSKProtoNullMessage.parseProto(proto).serializedData()
        }
    }

    fileprivate let proto: SignalServiceProtos_NullMessage

    @objc public var padding: Data? {
        guard proto.hasPadding else {
            return nil
        }
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

#if DEBUG

extension SSKProtoNullMessage {
    @objc public func serializedDataIgnoringErrors() -> Data? {
        return try! self.serializedData()
    }
}

extension SSKProtoNullMessage.SSKProtoNullMessageBuilder {
    @objc public func buildIgnoringErrors() -> SSKProtoNullMessage? {
        return try! self.build()
    }
}

#endif

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

        private var proto = SignalServiceProtos_ReceiptMessage()

        @objc public override init() {}

        // Initializer for required fields
        @objc public init(type: SSKProtoReceiptMessageType) {
            super.init()

            setType(type)
        }

        @objc public func setType(_ valueParam: SSKProtoReceiptMessageType) {
            proto.type = SSKProtoReceiptMessageTypeUnwrap(valueParam)
        }

        @objc public func addTimestamp(_ valueParam: UInt64) {
            var items = proto.timestamp
            items.append(valueParam)
            proto.timestamp = items
        }

        @objc public func setTimestamp(_ wrappedItems: [UInt64]) {
            proto.timestamp = wrappedItems
        }

        @objc public func build() throws -> SSKProtoReceiptMessage {
            return try SSKProtoReceiptMessage.parseProto(proto)
        }

        @objc public func buildSerializedData() throws -> Data {
            return try SSKProtoReceiptMessage.parseProto(proto).serializedData()
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

#if DEBUG

extension SSKProtoReceiptMessage {
    @objc public func serializedDataIgnoringErrors() -> Data? {
        return try! self.serializedData()
    }
}

extension SSKProtoReceiptMessage.SSKProtoReceiptMessageBuilder {
    @objc public func buildIgnoringErrors() -> SSKProtoReceiptMessage? {
        return try! self.build()
    }
}

#endif

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

        private var proto = SignalServiceProtos_Verified()

        @objc public override init() {}

        // Initializer for required fields
        @objc public init(destination: String) {
            super.init()

            setDestination(destination)
        }

        @objc public func setDestination(_ valueParam: String) {
            proto.destination = valueParam
        }

        @objc public func setIdentityKey(_ valueParam: Data) {
            proto.identityKey = valueParam
        }

        @objc public func setState(_ valueParam: SSKProtoVerifiedState) {
            proto.state = SSKProtoVerifiedStateUnwrap(valueParam)
        }

        @objc public func setNullMessage(_ valueParam: Data) {
            proto.nullMessage = valueParam
        }

        @objc public func build() throws -> SSKProtoVerified {
            return try SSKProtoVerified.parseProto(proto)
        }

        @objc public func buildSerializedData() throws -> Data {
            return try SSKProtoVerified.parseProto(proto).serializedData()
        }
    }

    fileprivate let proto: SignalServiceProtos_Verified

    @objc public let destination: String

    @objc public var identityKey: Data? {
        guard proto.hasIdentityKey else {
            return nil
        }
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

    @objc public var nullMessage: Data? {
        guard proto.hasNullMessage else {
            return nil
        }
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

#if DEBUG

extension SSKProtoVerified {
    @objc public func serializedDataIgnoringErrors() -> Data? {
        return try! self.serializedData()
    }
}

extension SSKProtoVerified.SSKProtoVerifiedBuilder {
    @objc public func buildIgnoringErrors() -> SSKProtoVerified? {
        return try! self.build()
    }
}

#endif

// MARK: - SSKProtoSyncMessageSent

@objc public class SSKProtoSyncMessageSent: NSObject {

    // MARK: - SSKProtoSyncMessageSentBuilder

    @objc public class SSKProtoSyncMessageSentBuilder: NSObject {

        private var proto = SignalServiceProtos_SyncMessage.Sent()

        @objc public override init() {}

        @objc public func setDestination(_ valueParam: String) {
            proto.destination = valueParam
        }

        @objc public func setTimestamp(_ valueParam: UInt64) {
            proto.timestamp = valueParam
        }

        @objc public func setMessage(_ valueParam: SSKProtoDataMessage) {
            proto.message = valueParam.proto
        }

        @objc public func setExpirationStartTimestamp(_ valueParam: UInt64) {
            proto.expirationStartTimestamp = valueParam
        }

        @objc public func build() throws -> SSKProtoSyncMessageSent {
            return try SSKProtoSyncMessageSent.parseProto(proto)
        }

        @objc public func buildSerializedData() throws -> Data {
            return try SSKProtoSyncMessageSent.parseProto(proto).serializedData()
        }
    }

    fileprivate let proto: SignalServiceProtos_SyncMessage.Sent

    @objc public let message: SSKProtoDataMessage?

    @objc public var destination: String? {
        guard proto.hasDestination else {
            return nil
        }
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

#if DEBUG

extension SSKProtoSyncMessageSent {
    @objc public func serializedDataIgnoringErrors() -> Data? {
        return try! self.serializedData()
    }
}

extension SSKProtoSyncMessageSent.SSKProtoSyncMessageSentBuilder {
    @objc public func buildIgnoringErrors() -> SSKProtoSyncMessageSent? {
        return try! self.build()
    }
}

#endif

// MARK: - SSKProtoSyncMessageContacts

@objc public class SSKProtoSyncMessageContacts: NSObject {

    // MARK: - SSKProtoSyncMessageContactsBuilder

    @objc public class SSKProtoSyncMessageContactsBuilder: NSObject {

        private var proto = SignalServiceProtos_SyncMessage.Contacts()

        @objc public override init() {}

        // Initializer for required fields
        @objc public init(blob: SSKProtoAttachmentPointer) {
            super.init()

            setBlob(blob)
        }

        @objc public func setBlob(_ valueParam: SSKProtoAttachmentPointer) {
            proto.blob = valueParam.proto
        }

        @objc public func setIsComplete(_ valueParam: Bool) {
            proto.isComplete = valueParam
        }

        @objc public func build() throws -> SSKProtoSyncMessageContacts {
            return try SSKProtoSyncMessageContacts.parseProto(proto)
        }

        @objc public func buildSerializedData() throws -> Data {
            return try SSKProtoSyncMessageContacts.parseProto(proto).serializedData()
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

#if DEBUG

extension SSKProtoSyncMessageContacts {
    @objc public func serializedDataIgnoringErrors() -> Data? {
        return try! self.serializedData()
    }
}

extension SSKProtoSyncMessageContacts.SSKProtoSyncMessageContactsBuilder {
    @objc public func buildIgnoringErrors() -> SSKProtoSyncMessageContacts? {
        return try! self.build()
    }
}

#endif

// MARK: - SSKProtoSyncMessageGroups

@objc public class SSKProtoSyncMessageGroups: NSObject {

    // MARK: - SSKProtoSyncMessageGroupsBuilder

    @objc public class SSKProtoSyncMessageGroupsBuilder: NSObject {

        private var proto = SignalServiceProtos_SyncMessage.Groups()

        @objc public override init() {}

        @objc public func setBlob(_ valueParam: SSKProtoAttachmentPointer) {
            proto.blob = valueParam.proto
        }

        @objc public func build() throws -> SSKProtoSyncMessageGroups {
            return try SSKProtoSyncMessageGroups.parseProto(proto)
        }

        @objc public func buildSerializedData() throws -> Data {
            return try SSKProtoSyncMessageGroups.parseProto(proto).serializedData()
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

#if DEBUG

extension SSKProtoSyncMessageGroups {
    @objc public func serializedDataIgnoringErrors() -> Data? {
        return try! self.serializedData()
    }
}

extension SSKProtoSyncMessageGroups.SSKProtoSyncMessageGroupsBuilder {
    @objc public func buildIgnoringErrors() -> SSKProtoSyncMessageGroups? {
        return try! self.build()
    }
}

#endif

// MARK: - SSKProtoSyncMessageBlocked

@objc public class SSKProtoSyncMessageBlocked: NSObject {

    // MARK: - SSKProtoSyncMessageBlockedBuilder

    @objc public class SSKProtoSyncMessageBlockedBuilder: NSObject {

        private var proto = SignalServiceProtos_SyncMessage.Blocked()

        @objc public override init() {}

        @objc public func addNumbers(_ valueParam: String) {
            var items = proto.numbers
            items.append(valueParam)
            proto.numbers = items
        }

        @objc public func setNumbers(_ wrappedItems: [String]) {
            proto.numbers = wrappedItems
        }

        @objc public func addGroupIds(_ valueParam: Data) {
            var items = proto.groupIds
            items.append(valueParam)
            proto.groupIds = items
        }

        @objc public func setGroupIds(_ wrappedItems: [Data]) {
            proto.groupIds = wrappedItems
        }

        @objc public func build() throws -> SSKProtoSyncMessageBlocked {
            return try SSKProtoSyncMessageBlocked.parseProto(proto)
        }

        @objc public func buildSerializedData() throws -> Data {
            return try SSKProtoSyncMessageBlocked.parseProto(proto).serializedData()
        }
    }

    fileprivate let proto: SignalServiceProtos_SyncMessage.Blocked

    @objc public var numbers: [String] {
        return proto.numbers
    }

    @objc public var groupIds: [Data] {
        return proto.groupIds
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

#if DEBUG

extension SSKProtoSyncMessageBlocked {
    @objc public func serializedDataIgnoringErrors() -> Data? {
        return try! self.serializedData()
    }
}

extension SSKProtoSyncMessageBlocked.SSKProtoSyncMessageBlockedBuilder {
    @objc public func buildIgnoringErrors() -> SSKProtoSyncMessageBlocked? {
        return try! self.build()
    }
}

#endif

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

        private var proto = SignalServiceProtos_SyncMessage.Request()

        @objc public override init() {}

        // Initializer for required fields
        @objc public init(type: SSKProtoSyncMessageRequestType) {
            super.init()

            setType(type)
        }

        @objc public func setType(_ valueParam: SSKProtoSyncMessageRequestType) {
            proto.type = SSKProtoSyncMessageRequestTypeUnwrap(valueParam)
        }

        @objc public func build() throws -> SSKProtoSyncMessageRequest {
            return try SSKProtoSyncMessageRequest.parseProto(proto)
        }

        @objc public func buildSerializedData() throws -> Data {
            return try SSKProtoSyncMessageRequest.parseProto(proto).serializedData()
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

#if DEBUG

extension SSKProtoSyncMessageRequest {
    @objc public func serializedDataIgnoringErrors() -> Data? {
        return try! self.serializedData()
    }
}

extension SSKProtoSyncMessageRequest.SSKProtoSyncMessageRequestBuilder {
    @objc public func buildIgnoringErrors() -> SSKProtoSyncMessageRequest? {
        return try! self.build()
    }
}

#endif

// MARK: - SSKProtoSyncMessageRead

@objc public class SSKProtoSyncMessageRead: NSObject {

    // MARK: - SSKProtoSyncMessageReadBuilder

    @objc public class SSKProtoSyncMessageReadBuilder: NSObject {

        private var proto = SignalServiceProtos_SyncMessage.Read()

        @objc public override init() {}

        // Initializer for required fields
        @objc public init(sender: String, timestamp: UInt64) {
            super.init()

            setSender(sender)
            setTimestamp(timestamp)
        }

        @objc public func setSender(_ valueParam: String) {
            proto.sender = valueParam
        }

        @objc public func setTimestamp(_ valueParam: UInt64) {
            proto.timestamp = valueParam
        }

        @objc public func build() throws -> SSKProtoSyncMessageRead {
            return try SSKProtoSyncMessageRead.parseProto(proto)
        }

        @objc public func buildSerializedData() throws -> Data {
            return try SSKProtoSyncMessageRead.parseProto(proto).serializedData()
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

#if DEBUG

extension SSKProtoSyncMessageRead {
    @objc public func serializedDataIgnoringErrors() -> Data? {
        return try! self.serializedData()
    }
}

extension SSKProtoSyncMessageRead.SSKProtoSyncMessageReadBuilder {
    @objc public func buildIgnoringErrors() -> SSKProtoSyncMessageRead? {
        return try! self.build()
    }
}

#endif

// MARK: - SSKProtoSyncMessageConfiguration

@objc public class SSKProtoSyncMessageConfiguration: NSObject {

    // MARK: - SSKProtoSyncMessageConfigurationBuilder

    @objc public class SSKProtoSyncMessageConfigurationBuilder: NSObject {

        private var proto = SignalServiceProtos_SyncMessage.Configuration()

        @objc public override init() {}

        @objc public func setReadReceipts(_ valueParam: Bool) {
            proto.readReceipts = valueParam
        }

        @objc public func build() throws -> SSKProtoSyncMessageConfiguration {
            return try SSKProtoSyncMessageConfiguration.parseProto(proto)
        }

        @objc public func buildSerializedData() throws -> Data {
            return try SSKProtoSyncMessageConfiguration.parseProto(proto).serializedData()
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

#if DEBUG

extension SSKProtoSyncMessageConfiguration {
    @objc public func serializedDataIgnoringErrors() -> Data? {
        return try! self.serializedData()
    }
}

extension SSKProtoSyncMessageConfiguration.SSKProtoSyncMessageConfigurationBuilder {
    @objc public func buildIgnoringErrors() -> SSKProtoSyncMessageConfiguration? {
        return try! self.build()
    }
}

#endif

// MARK: - SSKProtoSyncMessage

@objc public class SSKProtoSyncMessage: NSObject {

    // MARK: - SSKProtoSyncMessageBuilder

    @objc public class SSKProtoSyncMessageBuilder: NSObject {

        private var proto = SignalServiceProtos_SyncMessage()

        @objc public override init() {}

        @objc public func setSent(_ valueParam: SSKProtoSyncMessageSent) {
            proto.sent = valueParam.proto
        }

        @objc public func setContacts(_ valueParam: SSKProtoSyncMessageContacts) {
            proto.contacts = valueParam.proto
        }

        @objc public func setGroups(_ valueParam: SSKProtoSyncMessageGroups) {
            proto.groups = valueParam.proto
        }

        @objc public func setRequest(_ valueParam: SSKProtoSyncMessageRequest) {
            proto.request = valueParam.proto
        }

        @objc public func addRead(_ valueParam: SSKProtoSyncMessageRead) {
            var items = proto.read
            items.append(valueParam.proto)
            proto.read = items
        }

        @objc public func setRead(_ wrappedItems: [SSKProtoSyncMessageRead]) {
            proto.read = wrappedItems.map { $0.proto }
        }

        @objc public func setBlocked(_ valueParam: SSKProtoSyncMessageBlocked) {
            proto.blocked = valueParam.proto
        }

        @objc public func setVerified(_ valueParam: SSKProtoVerified) {
            proto.verified = valueParam.proto
        }

        @objc public func setConfiguration(_ valueParam: SSKProtoSyncMessageConfiguration) {
            proto.configuration = valueParam.proto
        }

        @objc public func setPadding(_ valueParam: Data) {
            proto.padding = valueParam
        }

        @objc public func build() throws -> SSKProtoSyncMessage {
            return try SSKProtoSyncMessage.parseProto(proto)
        }

        @objc public func buildSerializedData() throws -> Data {
            return try SSKProtoSyncMessage.parseProto(proto).serializedData()
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

    @objc public var padding: Data? {
        guard proto.hasPadding else {
            return nil
        }
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
        read = try proto.read.map { try SSKProtoSyncMessageRead.parseProto($0) }

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

#if DEBUG

extension SSKProtoSyncMessage {
    @objc public func serializedDataIgnoringErrors() -> Data? {
        return try! self.serializedData()
    }
}

extension SSKProtoSyncMessage.SSKProtoSyncMessageBuilder {
    @objc public func buildIgnoringErrors() -> SSKProtoSyncMessage? {
        return try! self.build()
    }
}

#endif

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

        private var proto = SignalServiceProtos_AttachmentPointer()

        @objc public override init() {}

        // Initializer for required fields
        @objc public init(id: UInt64) {
            super.init()

            setId(id)
        }

        @objc public func setId(_ valueParam: UInt64) {
            proto.id = valueParam
        }

        @objc public func setContentType(_ valueParam: String) {
            proto.contentType = valueParam
        }

        @objc public func setKey(_ valueParam: Data) {
            proto.key = valueParam
        }

        @objc public func setSize(_ valueParam: UInt32) {
            proto.size = valueParam
        }

        @objc public func setThumbnail(_ valueParam: Data) {
            proto.thumbnail = valueParam
        }

        @objc public func setDigest(_ valueParam: Data) {
            proto.digest = valueParam
        }

        @objc public func setFileName(_ valueParam: String) {
            proto.fileName = valueParam
        }

        @objc public func setFlags(_ valueParam: UInt32) {
            proto.flags = valueParam
        }

        @objc public func setWidth(_ valueParam: UInt32) {
            proto.width = valueParam
        }

        @objc public func setHeight(_ valueParam: UInt32) {
            proto.height = valueParam
        }

        @objc public func build() throws -> SSKProtoAttachmentPointer {
            return try SSKProtoAttachmentPointer.parseProto(proto)
        }

        @objc public func buildSerializedData() throws -> Data {
            return try SSKProtoAttachmentPointer.parseProto(proto).serializedData()
        }
    }

    fileprivate let proto: SignalServiceProtos_AttachmentPointer

    @objc public let id: UInt64

    @objc public var contentType: String? {
        guard proto.hasContentType else {
            return nil
        }
        return proto.contentType
    }
    @objc public var hasContentType: Bool {
        return proto.hasContentType
    }

    @objc public var key: Data? {
        guard proto.hasKey else {
            return nil
        }
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

    @objc public var thumbnail: Data? {
        guard proto.hasThumbnail else {
            return nil
        }
        return proto.thumbnail
    }
    @objc public var hasThumbnail: Bool {
        return proto.hasThumbnail
    }

    @objc public var digest: Data? {
        guard proto.hasDigest else {
            return nil
        }
        return proto.digest
    }
    @objc public var hasDigest: Bool {
        return proto.hasDigest
    }

    @objc public var fileName: String? {
        guard proto.hasFileName else {
            return nil
        }
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

#if DEBUG

extension SSKProtoAttachmentPointer {
    @objc public func serializedDataIgnoringErrors() -> Data? {
        return try! self.serializedData()
    }
}

extension SSKProtoAttachmentPointer.SSKProtoAttachmentPointerBuilder {
    @objc public func buildIgnoringErrors() -> SSKProtoAttachmentPointer? {
        return try! self.build()
    }
}

#endif

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

        private var proto = SignalServiceProtos_GroupContext()

        @objc public override init() {}

        // Initializer for required fields
        @objc public init(id: Data, type: SSKProtoGroupContextType) {
            super.init()

            setId(id)
            setType(type)
        }

        @objc public func setId(_ valueParam: Data) {
            proto.id = valueParam
        }

        @objc public func setType(_ valueParam: SSKProtoGroupContextType) {
            proto.type = SSKProtoGroupContextTypeUnwrap(valueParam)
        }

        @objc public func setName(_ valueParam: String) {
            proto.name = valueParam
        }

        @objc public func addMembers(_ valueParam: String) {
            var items = proto.members
            items.append(valueParam)
            proto.members = items
        }

        @objc public func setMembers(_ wrappedItems: [String]) {
            proto.members = wrappedItems
        }

        @objc public func setAvatar(_ valueParam: SSKProtoAttachmentPointer) {
            proto.avatar = valueParam.proto
        }

        @objc public func build() throws -> SSKProtoGroupContext {
            return try SSKProtoGroupContext.parseProto(proto)
        }

        @objc public func buildSerializedData() throws -> Data {
            return try SSKProtoGroupContext.parseProto(proto).serializedData()
        }
    }

    fileprivate let proto: SignalServiceProtos_GroupContext

    @objc public let id: Data

    @objc public let type: SSKProtoGroupContextType

    @objc public let avatar: SSKProtoAttachmentPointer?

    @objc public var name: String? {
        guard proto.hasName else {
            return nil
        }
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

#if DEBUG

extension SSKProtoGroupContext {
    @objc public func serializedDataIgnoringErrors() -> Data? {
        return try! self.serializedData()
    }
}

extension SSKProtoGroupContext.SSKProtoGroupContextBuilder {
    @objc public func buildIgnoringErrors() -> SSKProtoGroupContext? {
        return try! self.build()
    }
}

#endif

// MARK: - SSKProtoContactDetailsAvatar

@objc public class SSKProtoContactDetailsAvatar: NSObject {

    // MARK: - SSKProtoContactDetailsAvatarBuilder

    @objc public class SSKProtoContactDetailsAvatarBuilder: NSObject {

        private var proto = SignalServiceProtos_ContactDetails.Avatar()

        @objc public override init() {}

        @objc public func setContentType(_ valueParam: String) {
            proto.contentType = valueParam
        }

        @objc public func setLength(_ valueParam: UInt32) {
            proto.length = valueParam
        }

        @objc public func build() throws -> SSKProtoContactDetailsAvatar {
            return try SSKProtoContactDetailsAvatar.parseProto(proto)
        }

        @objc public func buildSerializedData() throws -> Data {
            return try SSKProtoContactDetailsAvatar.parseProto(proto).serializedData()
        }
    }

    fileprivate let proto: SignalServiceProtos_ContactDetails.Avatar

    @objc public var contentType: String? {
        guard proto.hasContentType else {
            return nil
        }
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

#if DEBUG

extension SSKProtoContactDetailsAvatar {
    @objc public func serializedDataIgnoringErrors() -> Data? {
        return try! self.serializedData()
    }
}

extension SSKProtoContactDetailsAvatar.SSKProtoContactDetailsAvatarBuilder {
    @objc public func buildIgnoringErrors() -> SSKProtoContactDetailsAvatar? {
        return try! self.build()
    }
}

#endif

// MARK: - SSKProtoContactDetails

@objc public class SSKProtoContactDetails: NSObject {

    // MARK: - SSKProtoContactDetailsBuilder

    @objc public class SSKProtoContactDetailsBuilder: NSObject {

        private var proto = SignalServiceProtos_ContactDetails()

        @objc public override init() {}

        // Initializer for required fields
        @objc public init(number: String) {
            super.init()

            setNumber(number)
        }

        @objc public func setNumber(_ valueParam: String) {
            proto.number = valueParam
        }

        @objc public func setName(_ valueParam: String) {
            proto.name = valueParam
        }

        @objc public func setAvatar(_ valueParam: SSKProtoContactDetailsAvatar) {
            proto.avatar = valueParam.proto
        }

        @objc public func setColor(_ valueParam: String) {
            proto.color = valueParam
        }

        @objc public func setVerified(_ valueParam: SSKProtoVerified) {
            proto.verified = valueParam.proto
        }

        @objc public func setProfileKey(_ valueParam: Data) {
            proto.profileKey = valueParam
        }

        @objc public func setBlocked(_ valueParam: Bool) {
            proto.blocked = valueParam
        }

        @objc public func setExpireTimer(_ valueParam: UInt32) {
            proto.expireTimer = valueParam
        }

        @objc public func build() throws -> SSKProtoContactDetails {
            return try SSKProtoContactDetails.parseProto(proto)
        }

        @objc public func buildSerializedData() throws -> Data {
            return try SSKProtoContactDetails.parseProto(proto).serializedData()
        }
    }

    fileprivate let proto: SignalServiceProtos_ContactDetails

    @objc public let number: String

    @objc public let avatar: SSKProtoContactDetailsAvatar?

    @objc public let verified: SSKProtoVerified?

    @objc public var name: String? {
        guard proto.hasName else {
            return nil
        }
        return proto.name
    }
    @objc public var hasName: Bool {
        return proto.hasName
    }

    @objc public var color: String? {
        guard proto.hasColor else {
            return nil
        }
        return proto.color
    }
    @objc public var hasColor: Bool {
        return proto.hasColor
    }

    @objc public var profileKey: Data? {
        guard proto.hasProfileKey else {
            return nil
        }
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

#if DEBUG

extension SSKProtoContactDetails {
    @objc public func serializedDataIgnoringErrors() -> Data? {
        return try! self.serializedData()
    }
}

extension SSKProtoContactDetails.SSKProtoContactDetailsBuilder {
    @objc public func buildIgnoringErrors() -> SSKProtoContactDetails? {
        return try! self.build()
    }
}

#endif

// MARK: - SSKProtoGroupDetailsAvatar

@objc public class SSKProtoGroupDetailsAvatar: NSObject {

    // MARK: - SSKProtoGroupDetailsAvatarBuilder

    @objc public class SSKProtoGroupDetailsAvatarBuilder: NSObject {

        private var proto = SignalServiceProtos_GroupDetails.Avatar()

        @objc public override init() {}

        @objc public func setContentType(_ valueParam: String) {
            proto.contentType = valueParam
        }

        @objc public func setLength(_ valueParam: UInt32) {
            proto.length = valueParam
        }

        @objc public func build() throws -> SSKProtoGroupDetailsAvatar {
            return try SSKProtoGroupDetailsAvatar.parseProto(proto)
        }

        @objc public func buildSerializedData() throws -> Data {
            return try SSKProtoGroupDetailsAvatar.parseProto(proto).serializedData()
        }
    }

    fileprivate let proto: SignalServiceProtos_GroupDetails.Avatar

    @objc public var contentType: String? {
        guard proto.hasContentType else {
            return nil
        }
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

#if DEBUG

extension SSKProtoGroupDetailsAvatar {
    @objc public func serializedDataIgnoringErrors() -> Data? {
        return try! self.serializedData()
    }
}

extension SSKProtoGroupDetailsAvatar.SSKProtoGroupDetailsAvatarBuilder {
    @objc public func buildIgnoringErrors() -> SSKProtoGroupDetailsAvatar? {
        return try! self.build()
    }
}

#endif

// MARK: - SSKProtoGroupDetails

@objc public class SSKProtoGroupDetails: NSObject {

    // MARK: - SSKProtoGroupDetailsBuilder

    @objc public class SSKProtoGroupDetailsBuilder: NSObject {

        private var proto = SignalServiceProtos_GroupDetails()

        @objc public override init() {}

        // Initializer for required fields
        @objc public init(id: Data) {
            super.init()

            setId(id)
        }

        @objc public func setId(_ valueParam: Data) {
            proto.id = valueParam
        }

        @objc public func setName(_ valueParam: String) {
            proto.name = valueParam
        }

        @objc public func addMembers(_ valueParam: String) {
            var items = proto.members
            items.append(valueParam)
            proto.members = items
        }

        @objc public func setMembers(_ wrappedItems: [String]) {
            proto.members = wrappedItems
        }

        @objc public func setAvatar(_ valueParam: SSKProtoGroupDetailsAvatar) {
            proto.avatar = valueParam.proto
        }

        @objc public func setActive(_ valueParam: Bool) {
            proto.active = valueParam
        }

        @objc public func setExpireTimer(_ valueParam: UInt32) {
            proto.expireTimer = valueParam
        }

        @objc public func setColor(_ valueParam: String) {
            proto.color = valueParam
        }

        @objc public func setBlocked(_ valueParam: Bool) {
            proto.blocked = valueParam
        }

        @objc public func build() throws -> SSKProtoGroupDetails {
            return try SSKProtoGroupDetails.parseProto(proto)
        }

        @objc public func buildSerializedData() throws -> Data {
            return try SSKProtoGroupDetails.parseProto(proto).serializedData()
        }
    }

    fileprivate let proto: SignalServiceProtos_GroupDetails

    @objc public let id: Data

    @objc public let avatar: SSKProtoGroupDetailsAvatar?

    @objc public var name: String? {
        guard proto.hasName else {
            return nil
        }
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

    @objc public var color: String? {
        guard proto.hasColor else {
            return nil
        }
        return proto.color
    }
    @objc public var hasColor: Bool {
        return proto.hasColor
    }

    @objc public var blocked: Bool {
        return proto.blocked
    }
    @objc public var hasBlocked: Bool {
        return proto.hasBlocked
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

#if DEBUG

extension SSKProtoGroupDetails {
    @objc public func serializedDataIgnoringErrors() -> Data? {
        return try! self.serializedData()
    }
}

extension SSKProtoGroupDetails.SSKProtoGroupDetailsBuilder {
    @objc public func buildIgnoringErrors() -> SSKProtoGroupDetails? {
        return try! self.build()
    }
}

#endif
