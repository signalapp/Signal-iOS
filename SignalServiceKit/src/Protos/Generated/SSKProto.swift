//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

import Foundation
import SignalCoreKit

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
        case unidentifiedSender = 6
    }

    private class func SSKProtoEnvelopeTypeWrap(_ value: SignalServiceProtos_Envelope.TypeEnum) -> SSKProtoEnvelopeType {
        switch value {
        case .unknown: return .unknown
        case .ciphertext: return .ciphertext
        case .keyExchange: return .keyExchange
        case .prekeyBundle: return .prekeyBundle
        case .receipt: return .receipt
        case .unidentifiedSender: return .unidentifiedSender
        }
    }

    private class func SSKProtoEnvelopeTypeUnwrap(_ value: SSKProtoEnvelopeType) -> SignalServiceProtos_Envelope.TypeEnum {
        switch value {
        case .unknown: return .unknown
        case .ciphertext: return .ciphertext
        case .keyExchange: return .keyExchange
        case .prekeyBundle: return .prekeyBundle
        case .receipt: return .receipt
        case .unidentifiedSender: return .unidentifiedSender
        }
    }

    // MARK: - SSKProtoEnvelopeBuilder

    @objc public class func builder(timestamp: UInt64) -> SSKProtoEnvelopeBuilder {
        return SSKProtoEnvelopeBuilder(timestamp: timestamp)
    }

    // asBuilder() constructs a builder that reflects the proto's contents.
    @objc public func asBuilder() -> SSKProtoEnvelopeBuilder {
        let builder = SSKProtoEnvelopeBuilder(timestamp: timestamp)
        if let _value = type {
            builder.setType(_value)
        }
        if let _value = sourceE164 {
            builder.setSourceE164(_value)
        }
        if hasSourceDevice {
            builder.setSourceDevice(sourceDevice)
        }
        if let _value = relay {
            builder.setRelay(_value)
        }
        if let _value = legacyMessage {
            builder.setLegacyMessage(_value)
        }
        if let _value = content {
            builder.setContent(_value)
        }
        if let _value = serverGuid {
            builder.setServerGuid(_value)
        }
        if hasServerTimestamp {
            builder.setServerTimestamp(serverTimestamp)
        }
        if let _value = sourceUuid {
            builder.setSourceUuid(_value)
        }
        return builder
    }

    @objc public class SSKProtoEnvelopeBuilder: NSObject {

        private var proto = SignalServiceProtos_Envelope()

        @objc fileprivate override init() {}

        @objc fileprivate init(timestamp: UInt64) {
            super.init()

            setTimestamp(timestamp)
        }

        @objc public func setType(_ valueParam: SSKProtoEnvelopeType) {
            proto.type = SSKProtoEnvelopeTypeUnwrap(valueParam)
        }

        @objc public func setSourceE164(_ valueParam: String) {
            proto.sourceE164 = valueParam
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

        @objc public func setServerGuid(_ valueParam: String) {
            proto.serverGuid = valueParam
        }

        @objc public func setServerTimestamp(_ valueParam: UInt64) {
            proto.serverTimestamp = valueParam
        }

        @objc public func setSourceUuid(_ valueParam: String) {
            proto.sourceUuid = valueParam
        }

        @objc public func build() throws -> SSKProtoEnvelope {
            return try SSKProtoEnvelope.parseProto(proto)
        }

        @objc public func buildSerializedData() throws -> Data {
            return try SSKProtoEnvelope.parseProto(proto).serializedData()
        }
    }

    fileprivate let proto: SignalServiceProtos_Envelope

    @objc public let timestamp: UInt64

    public var type: SSKProtoEnvelopeType? {
        guard proto.hasType else {
            return nil
        }
        return SSKProtoEnvelope.SSKProtoEnvelopeTypeWrap(proto.type)
    }
    // This "unwrapped" accessor should only be used if the "has value" accessor has already been checked.
    @objc public var unwrappedType: SSKProtoEnvelopeType {
        if !hasType {
            // TODO: We could make this a crashing assert.
            owsFailDebug("Unsafe unwrap of missing optional: Envelope.type.")
        }
        return SSKProtoEnvelope.SSKProtoEnvelopeTypeWrap(proto.type)
    }
    @objc public var hasType: Bool {
        return proto.hasType
    }

    @objc public var sourceE164: String? {
        guard proto.hasSourceE164 else {
            return nil
        }
        return proto.sourceE164
    }
    @objc public var hasSourceE164: Bool {
        return proto.hasSourceE164
    }

    @objc public var sourceDevice: UInt32 {
        return proto.sourceDevice
    }
    @objc public var hasSourceDevice: Bool {
        return proto.hasSourceDevice
    }

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

    @objc public var serverGuid: String? {
        guard proto.hasServerGuid else {
            return nil
        }
        return proto.serverGuid
    }
    @objc public var hasServerGuid: Bool {
        return proto.hasServerGuid
    }

    @objc public var serverTimestamp: UInt64 {
        return proto.serverTimestamp
    }
    @objc public var hasServerTimestamp: Bool {
        return proto.hasServerTimestamp
    }

    @objc public var sourceUuid: String? {
        guard proto.hasSourceUuid else {
            return nil
        }
        return proto.sourceUuid
    }
    @objc public var hasSourceUuid: Bool {
        return proto.hasSourceUuid
    }

    private init(proto: SignalServiceProtos_Envelope,
                 timestamp: UInt64) {
        self.proto = proto
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
        guard proto.hasTimestamp else {
            throw SSKProtoError.invalidProtobuf(description: "\(logTag) missing required field: timestamp")
        }
        let timestamp = proto.timestamp

        // MARK: - Begin Validation Logic for SSKProtoEnvelope -

        // MARK: - End Validation Logic for SSKProtoEnvelope -

        let result = SSKProtoEnvelope(proto: proto,
                                      timestamp: timestamp)
        return result
    }

    @objc public override var debugDescription: String {
        return "\(proto)"
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

// MARK: - SSKProtoTypingMessage

@objc public class SSKProtoTypingMessage: NSObject {

    // MARK: - SSKProtoTypingMessageAction

    @objc public enum SSKProtoTypingMessageAction: Int32 {
        case started = 0
        case stopped = 1
    }

    private class func SSKProtoTypingMessageActionWrap(_ value: SignalServiceProtos_TypingMessage.Action) -> SSKProtoTypingMessageAction {
        switch value {
        case .started: return .started
        case .stopped: return .stopped
        }
    }

    private class func SSKProtoTypingMessageActionUnwrap(_ value: SSKProtoTypingMessageAction) -> SignalServiceProtos_TypingMessage.Action {
        switch value {
        case .started: return .started
        case .stopped: return .stopped
        }
    }

    // MARK: - SSKProtoTypingMessageBuilder

    @objc public class func builder(timestamp: UInt64) -> SSKProtoTypingMessageBuilder {
        return SSKProtoTypingMessageBuilder(timestamp: timestamp)
    }

    // asBuilder() constructs a builder that reflects the proto's contents.
    @objc public func asBuilder() -> SSKProtoTypingMessageBuilder {
        let builder = SSKProtoTypingMessageBuilder(timestamp: timestamp)
        if let _value = action {
            builder.setAction(_value)
        }
        if let _value = groupID {
            builder.setGroupID(_value)
        }
        return builder
    }

    @objc public class SSKProtoTypingMessageBuilder: NSObject {

        private var proto = SignalServiceProtos_TypingMessage()

        @objc fileprivate override init() {}

        @objc fileprivate init(timestamp: UInt64) {
            super.init()

            setTimestamp(timestamp)
        }

        @objc public func setTimestamp(_ valueParam: UInt64) {
            proto.timestamp = valueParam
        }

        @objc public func setAction(_ valueParam: SSKProtoTypingMessageAction) {
            proto.action = SSKProtoTypingMessageActionUnwrap(valueParam)
        }

        @objc public func setGroupID(_ valueParam: Data) {
            proto.groupID = valueParam
        }

        @objc public func build() throws -> SSKProtoTypingMessage {
            return try SSKProtoTypingMessage.parseProto(proto)
        }

        @objc public func buildSerializedData() throws -> Data {
            return try SSKProtoTypingMessage.parseProto(proto).serializedData()
        }
    }

    fileprivate let proto: SignalServiceProtos_TypingMessage

    @objc public let timestamp: UInt64

    public var action: SSKProtoTypingMessageAction? {
        guard proto.hasAction else {
            return nil
        }
        return SSKProtoTypingMessage.SSKProtoTypingMessageActionWrap(proto.action)
    }
    // This "unwrapped" accessor should only be used if the "has value" accessor has already been checked.
    @objc public var unwrappedAction: SSKProtoTypingMessageAction {
        if !hasAction {
            // TODO: We could make this a crashing assert.
            owsFailDebug("Unsafe unwrap of missing optional: TypingMessage.action.")
        }
        return SSKProtoTypingMessage.SSKProtoTypingMessageActionWrap(proto.action)
    }
    @objc public var hasAction: Bool {
        return proto.hasAction
    }

    @objc public var groupID: Data? {
        guard proto.hasGroupID else {
            return nil
        }
        return proto.groupID
    }
    @objc public var hasGroupID: Bool {
        return proto.hasGroupID
    }

    private init(proto: SignalServiceProtos_TypingMessage,
                 timestamp: UInt64) {
        self.proto = proto
        self.timestamp = timestamp
    }

    @objc
    public func serializedData() throws -> Data {
        return try self.proto.serializedData()
    }

    @objc public class func parseData(_ serializedData: Data) throws -> SSKProtoTypingMessage {
        let proto = try SignalServiceProtos_TypingMessage(serializedData: serializedData)
        return try parseProto(proto)
    }

    fileprivate class func parseProto(_ proto: SignalServiceProtos_TypingMessage) throws -> SSKProtoTypingMessage {
        guard proto.hasTimestamp else {
            throw SSKProtoError.invalidProtobuf(description: "\(logTag) missing required field: timestamp")
        }
        let timestamp = proto.timestamp

        // MARK: - Begin Validation Logic for SSKProtoTypingMessage -

        // MARK: - End Validation Logic for SSKProtoTypingMessage -

        let result = SSKProtoTypingMessage(proto: proto,
                                           timestamp: timestamp)
        return result
    }

    @objc public override var debugDescription: String {
        return "\(proto)"
    }
}

#if DEBUG

extension SSKProtoTypingMessage {
    @objc public func serializedDataIgnoringErrors() -> Data? {
        return try! self.serializedData()
    }
}

extension SSKProtoTypingMessage.SSKProtoTypingMessageBuilder {
    @objc public func buildIgnoringErrors() -> SSKProtoTypingMessage? {
        return try! self.build()
    }
}

#endif

// MARK: - SSKProtoContent

@objc public class SSKProtoContent: NSObject {

    // MARK: - SSKProtoContentBuilder

    @objc public class func builder() -> SSKProtoContentBuilder {
        return SSKProtoContentBuilder()
    }

    // asBuilder() constructs a builder that reflects the proto's contents.
    @objc public func asBuilder() -> SSKProtoContentBuilder {
        let builder = SSKProtoContentBuilder()
        if let _value = dataMessage {
            builder.setDataMessage(_value)
        }
        if let _value = syncMessage {
            builder.setSyncMessage(_value)
        }
        if let _value = callMessage {
            builder.setCallMessage(_value)
        }
        if let _value = nullMessage {
            builder.setNullMessage(_value)
        }
        if let _value = receiptMessage {
            builder.setReceiptMessage(_value)
        }
        if let _value = typingMessage {
            builder.setTypingMessage(_value)
        }
        return builder
    }

    @objc public class SSKProtoContentBuilder: NSObject {

        private var proto = SignalServiceProtos_Content()

        @objc fileprivate override init() {}

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

        @objc public func setTypingMessage(_ valueParam: SSKProtoTypingMessage) {
            proto.typingMessage = valueParam.proto
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

    @objc public let typingMessage: SSKProtoTypingMessage?

    private init(proto: SignalServiceProtos_Content,
                 dataMessage: SSKProtoDataMessage?,
                 syncMessage: SSKProtoSyncMessage?,
                 callMessage: SSKProtoCallMessage?,
                 nullMessage: SSKProtoNullMessage?,
                 receiptMessage: SSKProtoReceiptMessage?,
                 typingMessage: SSKProtoTypingMessage?) {
        self.proto = proto
        self.dataMessage = dataMessage
        self.syncMessage = syncMessage
        self.callMessage = callMessage
        self.nullMessage = nullMessage
        self.receiptMessage = receiptMessage
        self.typingMessage = typingMessage
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

        var typingMessage: SSKProtoTypingMessage? = nil
        if proto.hasTypingMessage {
            typingMessage = try SSKProtoTypingMessage.parseProto(proto.typingMessage)
        }

        // MARK: - Begin Validation Logic for SSKProtoContent -

        // MARK: - End Validation Logic for SSKProtoContent -

        let result = SSKProtoContent(proto: proto,
                                     dataMessage: dataMessage,
                                     syncMessage: syncMessage,
                                     callMessage: callMessage,
                                     nullMessage: nullMessage,
                                     receiptMessage: receiptMessage,
                                     typingMessage: typingMessage)
        return result
    }

    @objc public override var debugDescription: String {
        return "\(proto)"
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

    @objc public class func builder(id: UInt64, sessionDescription: String) -> SSKProtoCallMessageOfferBuilder {
        return SSKProtoCallMessageOfferBuilder(id: id, sessionDescription: sessionDescription)
    }

    // asBuilder() constructs a builder that reflects the proto's contents.
    @objc public func asBuilder() -> SSKProtoCallMessageOfferBuilder {
        let builder = SSKProtoCallMessageOfferBuilder(id: id, sessionDescription: sessionDescription)
        return builder
    }

    @objc public class SSKProtoCallMessageOfferBuilder: NSObject {

        private var proto = SignalServiceProtos_CallMessage.Offer()

        @objc fileprivate override init() {}

        @objc fileprivate init(id: UInt64, sessionDescription: String) {
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

    @objc public override var debugDescription: String {
        return "\(proto)"
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

    @objc public class func builder(id: UInt64, sessionDescription: String) -> SSKProtoCallMessageAnswerBuilder {
        return SSKProtoCallMessageAnswerBuilder(id: id, sessionDescription: sessionDescription)
    }

    // asBuilder() constructs a builder that reflects the proto's contents.
    @objc public func asBuilder() -> SSKProtoCallMessageAnswerBuilder {
        let builder = SSKProtoCallMessageAnswerBuilder(id: id, sessionDescription: sessionDescription)
        return builder
    }

    @objc public class SSKProtoCallMessageAnswerBuilder: NSObject {

        private var proto = SignalServiceProtos_CallMessage.Answer()

        @objc fileprivate override init() {}

        @objc fileprivate init(id: UInt64, sessionDescription: String) {
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

    @objc public override var debugDescription: String {
        return "\(proto)"
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

    @objc public class func builder(id: UInt64, sdpMid: String, sdpMlineIndex: UInt32, sdp: String) -> SSKProtoCallMessageIceUpdateBuilder {
        return SSKProtoCallMessageIceUpdateBuilder(id: id, sdpMid: sdpMid, sdpMlineIndex: sdpMlineIndex, sdp: sdp)
    }

    // asBuilder() constructs a builder that reflects the proto's contents.
    @objc public func asBuilder() -> SSKProtoCallMessageIceUpdateBuilder {
        let builder = SSKProtoCallMessageIceUpdateBuilder(id: id, sdpMid: sdpMid, sdpMlineIndex: sdpMlineIndex, sdp: sdp)
        return builder
    }

    @objc public class SSKProtoCallMessageIceUpdateBuilder: NSObject {

        private var proto = SignalServiceProtos_CallMessage.IceUpdate()

        @objc fileprivate override init() {}

        @objc fileprivate init(id: UInt64, sdpMid: String, sdpMlineIndex: UInt32, sdp: String) {
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

    @objc public override var debugDescription: String {
        return "\(proto)"
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

    @objc public class func builder(id: UInt64) -> SSKProtoCallMessageBusyBuilder {
        return SSKProtoCallMessageBusyBuilder(id: id)
    }

    // asBuilder() constructs a builder that reflects the proto's contents.
    @objc public func asBuilder() -> SSKProtoCallMessageBusyBuilder {
        let builder = SSKProtoCallMessageBusyBuilder(id: id)
        return builder
    }

    @objc public class SSKProtoCallMessageBusyBuilder: NSObject {

        private var proto = SignalServiceProtos_CallMessage.Busy()

        @objc fileprivate override init() {}

        @objc fileprivate init(id: UInt64) {
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

    @objc public override var debugDescription: String {
        return "\(proto)"
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

    @objc public class func builder(id: UInt64) -> SSKProtoCallMessageHangupBuilder {
        return SSKProtoCallMessageHangupBuilder(id: id)
    }

    // asBuilder() constructs a builder that reflects the proto's contents.
    @objc public func asBuilder() -> SSKProtoCallMessageHangupBuilder {
        let builder = SSKProtoCallMessageHangupBuilder(id: id)
        return builder
    }

    @objc public class SSKProtoCallMessageHangupBuilder: NSObject {

        private var proto = SignalServiceProtos_CallMessage.Hangup()

        @objc fileprivate override init() {}

        @objc fileprivate init(id: UInt64) {
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

    @objc public override var debugDescription: String {
        return "\(proto)"
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

    @objc public class func builder() -> SSKProtoCallMessageBuilder {
        return SSKProtoCallMessageBuilder()
    }

    // asBuilder() constructs a builder that reflects the proto's contents.
    @objc public func asBuilder() -> SSKProtoCallMessageBuilder {
        let builder = SSKProtoCallMessageBuilder()
        if let _value = offer {
            builder.setOffer(_value)
        }
        if let _value = answer {
            builder.setAnswer(_value)
        }
        builder.setIceUpdate(iceUpdate)
        if let _value = hangup {
            builder.setHangup(_value)
        }
        if let _value = busy {
            builder.setBusy(_value)
        }
        if let _value = profileKey {
            builder.setProfileKey(_value)
        }
        return builder
    }

    @objc public class SSKProtoCallMessageBuilder: NSObject {

        private var proto = SignalServiceProtos_CallMessage()

        @objc fileprivate override init() {}

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

    @objc public override var debugDescription: String {
        return "\(proto)"
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

    @objc public class func builder() -> SSKProtoDataMessageQuoteQuotedAttachmentBuilder {
        return SSKProtoDataMessageQuoteQuotedAttachmentBuilder()
    }

    // asBuilder() constructs a builder that reflects the proto's contents.
    @objc public func asBuilder() -> SSKProtoDataMessageQuoteQuotedAttachmentBuilder {
        let builder = SSKProtoDataMessageQuoteQuotedAttachmentBuilder()
        if let _value = contentType {
            builder.setContentType(_value)
        }
        if let _value = fileName {
            builder.setFileName(_value)
        }
        if let _value = thumbnail {
            builder.setThumbnail(_value)
        }
        if hasFlags {
            builder.setFlags(flags)
        }
        return builder
    }

    @objc public class SSKProtoDataMessageQuoteQuotedAttachmentBuilder: NSObject {

        private var proto = SignalServiceProtos_DataMessage.Quote.QuotedAttachment()

        @objc fileprivate override init() {}

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

    @objc public override var debugDescription: String {
        return "\(proto)"
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

    @objc public class func builder(id: UInt64, author: String) -> SSKProtoDataMessageQuoteBuilder {
        return SSKProtoDataMessageQuoteBuilder(id: id, author: author)
    }

    // asBuilder() constructs a builder that reflects the proto's contents.
    @objc public func asBuilder() -> SSKProtoDataMessageQuoteBuilder {
        let builder = SSKProtoDataMessageQuoteBuilder(id: id, author: author)
        if let _value = text {
            builder.setText(_value)
        }
        builder.setAttachments(attachments)
        return builder
    }

    @objc public class SSKProtoDataMessageQuoteBuilder: NSObject {

        private var proto = SignalServiceProtos_DataMessage.Quote()

        @objc fileprivate override init() {}

        @objc fileprivate init(id: UInt64, author: String) {
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

    @objc public override var debugDescription: String {
        return "\(proto)"
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

    @objc public class func builder() -> SSKProtoDataMessageContactNameBuilder {
        return SSKProtoDataMessageContactNameBuilder()
    }

    // asBuilder() constructs a builder that reflects the proto's contents.
    @objc public func asBuilder() -> SSKProtoDataMessageContactNameBuilder {
        let builder = SSKProtoDataMessageContactNameBuilder()
        if let _value = givenName {
            builder.setGivenName(_value)
        }
        if let _value = familyName {
            builder.setFamilyName(_value)
        }
        if let _value = prefix {
            builder.setPrefix(_value)
        }
        if let _value = suffix {
            builder.setSuffix(_value)
        }
        if let _value = middleName {
            builder.setMiddleName(_value)
        }
        if let _value = displayName {
            builder.setDisplayName(_value)
        }
        return builder
    }

    @objc public class SSKProtoDataMessageContactNameBuilder: NSObject {

        private var proto = SignalServiceProtos_DataMessage.Contact.Name()

        @objc fileprivate override init() {}

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

    @objc public override var debugDescription: String {
        return "\(proto)"
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

    @objc public class func builder() -> SSKProtoDataMessageContactPhoneBuilder {
        return SSKProtoDataMessageContactPhoneBuilder()
    }

    // asBuilder() constructs a builder that reflects the proto's contents.
    @objc public func asBuilder() -> SSKProtoDataMessageContactPhoneBuilder {
        let builder = SSKProtoDataMessageContactPhoneBuilder()
        if let _value = value {
            builder.setValue(_value)
        }
        if let _value = type {
            builder.setType(_value)
        }
        if let _value = label {
            builder.setLabel(_value)
        }
        return builder
    }

    @objc public class SSKProtoDataMessageContactPhoneBuilder: NSObject {

        private var proto = SignalServiceProtos_DataMessage.Contact.Phone()

        @objc fileprivate override init() {}

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

    public var type: SSKProtoDataMessageContactPhoneType? {
        guard proto.hasType else {
            return nil
        }
        return SSKProtoDataMessageContactPhone.SSKProtoDataMessageContactPhoneTypeWrap(proto.type)
    }
    // This "unwrapped" accessor should only be used if the "has value" accessor has already been checked.
    @objc public var unwrappedType: SSKProtoDataMessageContactPhoneType {
        if !hasType {
            // TODO: We could make this a crashing assert.
            owsFailDebug("Unsafe unwrap of missing optional: Phone.type.")
        }
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

    @objc public override var debugDescription: String {
        return "\(proto)"
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

    @objc public class func builder() -> SSKProtoDataMessageContactEmailBuilder {
        return SSKProtoDataMessageContactEmailBuilder()
    }

    // asBuilder() constructs a builder that reflects the proto's contents.
    @objc public func asBuilder() -> SSKProtoDataMessageContactEmailBuilder {
        let builder = SSKProtoDataMessageContactEmailBuilder()
        if let _value = value {
            builder.setValue(_value)
        }
        if let _value = type {
            builder.setType(_value)
        }
        if let _value = label {
            builder.setLabel(_value)
        }
        return builder
    }

    @objc public class SSKProtoDataMessageContactEmailBuilder: NSObject {

        private var proto = SignalServiceProtos_DataMessage.Contact.Email()

        @objc fileprivate override init() {}

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

    public var type: SSKProtoDataMessageContactEmailType? {
        guard proto.hasType else {
            return nil
        }
        return SSKProtoDataMessageContactEmail.SSKProtoDataMessageContactEmailTypeWrap(proto.type)
    }
    // This "unwrapped" accessor should only be used if the "has value" accessor has already been checked.
    @objc public var unwrappedType: SSKProtoDataMessageContactEmailType {
        if !hasType {
            // TODO: We could make this a crashing assert.
            owsFailDebug("Unsafe unwrap of missing optional: Email.type.")
        }
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

    @objc public override var debugDescription: String {
        return "\(proto)"
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

    @objc public class func builder() -> SSKProtoDataMessageContactPostalAddressBuilder {
        return SSKProtoDataMessageContactPostalAddressBuilder()
    }

    // asBuilder() constructs a builder that reflects the proto's contents.
    @objc public func asBuilder() -> SSKProtoDataMessageContactPostalAddressBuilder {
        let builder = SSKProtoDataMessageContactPostalAddressBuilder()
        if let _value = type {
            builder.setType(_value)
        }
        if let _value = label {
            builder.setLabel(_value)
        }
        if let _value = street {
            builder.setStreet(_value)
        }
        if let _value = pobox {
            builder.setPobox(_value)
        }
        if let _value = neighborhood {
            builder.setNeighborhood(_value)
        }
        if let _value = city {
            builder.setCity(_value)
        }
        if let _value = region {
            builder.setRegion(_value)
        }
        if let _value = postcode {
            builder.setPostcode(_value)
        }
        if let _value = country {
            builder.setCountry(_value)
        }
        return builder
    }

    @objc public class SSKProtoDataMessageContactPostalAddressBuilder: NSObject {

        private var proto = SignalServiceProtos_DataMessage.Contact.PostalAddress()

        @objc fileprivate override init() {}

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

    public var type: SSKProtoDataMessageContactPostalAddressType? {
        guard proto.hasType else {
            return nil
        }
        return SSKProtoDataMessageContactPostalAddress.SSKProtoDataMessageContactPostalAddressTypeWrap(proto.type)
    }
    // This "unwrapped" accessor should only be used if the "has value" accessor has already been checked.
    @objc public var unwrappedType: SSKProtoDataMessageContactPostalAddressType {
        if !hasType {
            // TODO: We could make this a crashing assert.
            owsFailDebug("Unsafe unwrap of missing optional: PostalAddress.type.")
        }
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

    @objc public override var debugDescription: String {
        return "\(proto)"
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

    @objc public class func builder() -> SSKProtoDataMessageContactAvatarBuilder {
        return SSKProtoDataMessageContactAvatarBuilder()
    }

    // asBuilder() constructs a builder that reflects the proto's contents.
    @objc public func asBuilder() -> SSKProtoDataMessageContactAvatarBuilder {
        let builder = SSKProtoDataMessageContactAvatarBuilder()
        if let _value = avatar {
            builder.setAvatar(_value)
        }
        if hasIsProfile {
            builder.setIsProfile(isProfile)
        }
        return builder
    }

    @objc public class SSKProtoDataMessageContactAvatarBuilder: NSObject {

        private var proto = SignalServiceProtos_DataMessage.Contact.Avatar()

        @objc fileprivate override init() {}

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

    @objc public override var debugDescription: String {
        return "\(proto)"
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

    @objc public class func builder() -> SSKProtoDataMessageContactBuilder {
        return SSKProtoDataMessageContactBuilder()
    }

    // asBuilder() constructs a builder that reflects the proto's contents.
    @objc public func asBuilder() -> SSKProtoDataMessageContactBuilder {
        let builder = SSKProtoDataMessageContactBuilder()
        if let _value = name {
            builder.setName(_value)
        }
        builder.setNumber(number)
        builder.setEmail(email)
        builder.setAddress(address)
        if let _value = avatar {
            builder.setAvatar(_value)
        }
        if let _value = organization {
            builder.setOrganization(_value)
        }
        return builder
    }

    @objc public class SSKProtoDataMessageContactBuilder: NSObject {

        private var proto = SignalServiceProtos_DataMessage.Contact()

        @objc fileprivate override init() {}

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

    @objc public override var debugDescription: String {
        return "\(proto)"
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

// MARK: - SSKProtoDataMessagePreview

@objc public class SSKProtoDataMessagePreview: NSObject {

    // MARK: - SSKProtoDataMessagePreviewBuilder

    @objc public class func builder(url: String) -> SSKProtoDataMessagePreviewBuilder {
        return SSKProtoDataMessagePreviewBuilder(url: url)
    }

    // asBuilder() constructs a builder that reflects the proto's contents.
    @objc public func asBuilder() -> SSKProtoDataMessagePreviewBuilder {
        let builder = SSKProtoDataMessagePreviewBuilder(url: url)
        if let _value = title {
            builder.setTitle(_value)
        }
        if let _value = image {
            builder.setImage(_value)
        }
        return builder
    }

    @objc public class SSKProtoDataMessagePreviewBuilder: NSObject {

        private var proto = SignalServiceProtos_DataMessage.Preview()

        @objc fileprivate override init() {}

        @objc fileprivate init(url: String) {
            super.init()

            setUrl(url)
        }

        @objc public func setUrl(_ valueParam: String) {
            proto.url = valueParam
        }

        @objc public func setTitle(_ valueParam: String) {
            proto.title = valueParam
        }

        @objc public func setImage(_ valueParam: SSKProtoAttachmentPointer) {
            proto.image = valueParam.proto
        }

        @objc public func build() throws -> SSKProtoDataMessagePreview {
            return try SSKProtoDataMessagePreview.parseProto(proto)
        }

        @objc public func buildSerializedData() throws -> Data {
            return try SSKProtoDataMessagePreview.parseProto(proto).serializedData()
        }
    }

    fileprivate let proto: SignalServiceProtos_DataMessage.Preview

    @objc public let url: String

    @objc public let image: SSKProtoAttachmentPointer?

    @objc public var title: String? {
        guard proto.hasTitle else {
            return nil
        }
        return proto.title
    }
    @objc public var hasTitle: Bool {
        return proto.hasTitle
    }

    private init(proto: SignalServiceProtos_DataMessage.Preview,
                 url: String,
                 image: SSKProtoAttachmentPointer?) {
        self.proto = proto
        self.url = url
        self.image = image
    }

    @objc
    public func serializedData() throws -> Data {
        return try self.proto.serializedData()
    }

    @objc public class func parseData(_ serializedData: Data) throws -> SSKProtoDataMessagePreview {
        let proto = try SignalServiceProtos_DataMessage.Preview(serializedData: serializedData)
        return try parseProto(proto)
    }

    fileprivate class func parseProto(_ proto: SignalServiceProtos_DataMessage.Preview) throws -> SSKProtoDataMessagePreview {
        guard proto.hasURL else {
            throw SSKProtoError.invalidProtobuf(description: "\(logTag) missing required field: url")
        }
        let url = proto.url

        var image: SSKProtoAttachmentPointer? = nil
        if proto.hasImage {
            image = try SSKProtoAttachmentPointer.parseProto(proto.image)
        }

        // MARK: - Begin Validation Logic for SSKProtoDataMessagePreview -

        // MARK: - End Validation Logic for SSKProtoDataMessagePreview -

        let result = SSKProtoDataMessagePreview(proto: proto,
                                                url: url,
                                                image: image)
        return result
    }

    @objc public override var debugDescription: String {
        return "\(proto)"
    }
}

#if DEBUG

extension SSKProtoDataMessagePreview {
    @objc public func serializedDataIgnoringErrors() -> Data? {
        return try! self.serializedData()
    }
}

extension SSKProtoDataMessagePreview.SSKProtoDataMessagePreviewBuilder {
    @objc public func buildIgnoringErrors() -> SSKProtoDataMessagePreview? {
        return try! self.build()
    }
}

#endif

// MARK: - SSKProtoDataMessageSticker

@objc public class SSKProtoDataMessageSticker: NSObject {

    // MARK: - SSKProtoDataMessageStickerBuilder

    @objc public class func builder(packID: Data, packKey: Data, stickerID: UInt32, data: SSKProtoAttachmentPointer) -> SSKProtoDataMessageStickerBuilder {
        return SSKProtoDataMessageStickerBuilder(packID: packID, packKey: packKey, stickerID: stickerID, data: data)
    }

    // asBuilder() constructs a builder that reflects the proto's contents.
    @objc public func asBuilder() -> SSKProtoDataMessageStickerBuilder {
        let builder = SSKProtoDataMessageStickerBuilder(packID: packID, packKey: packKey, stickerID: stickerID, data: data)
        return builder
    }

    @objc public class SSKProtoDataMessageStickerBuilder: NSObject {

        private var proto = SignalServiceProtos_DataMessage.Sticker()

        @objc fileprivate override init() {}

        @objc fileprivate init(packID: Data, packKey: Data, stickerID: UInt32, data: SSKProtoAttachmentPointer) {
            super.init()

            setPackID(packID)
            setPackKey(packKey)
            setStickerID(stickerID)
            setData(data)
        }

        @objc public func setPackID(_ valueParam: Data) {
            proto.packID = valueParam
        }

        @objc public func setPackKey(_ valueParam: Data) {
            proto.packKey = valueParam
        }

        @objc public func setStickerID(_ valueParam: UInt32) {
            proto.stickerID = valueParam
        }

        @objc public func setData(_ valueParam: SSKProtoAttachmentPointer) {
            proto.data = valueParam.proto
        }

        @objc public func build() throws -> SSKProtoDataMessageSticker {
            return try SSKProtoDataMessageSticker.parseProto(proto)
        }

        @objc public func buildSerializedData() throws -> Data {
            return try SSKProtoDataMessageSticker.parseProto(proto).serializedData()
        }
    }

    fileprivate let proto: SignalServiceProtos_DataMessage.Sticker

    @objc public let packID: Data

    @objc public let packKey: Data

    @objc public let stickerID: UInt32

    @objc public let data: SSKProtoAttachmentPointer

    private init(proto: SignalServiceProtos_DataMessage.Sticker,
                 packID: Data,
                 packKey: Data,
                 stickerID: UInt32,
                 data: SSKProtoAttachmentPointer) {
        self.proto = proto
        self.packID = packID
        self.packKey = packKey
        self.stickerID = stickerID
        self.data = data
    }

    @objc
    public func serializedData() throws -> Data {
        return try self.proto.serializedData()
    }

    @objc public class func parseData(_ serializedData: Data) throws -> SSKProtoDataMessageSticker {
        let proto = try SignalServiceProtos_DataMessage.Sticker(serializedData: serializedData)
        return try parseProto(proto)
    }

    fileprivate class func parseProto(_ proto: SignalServiceProtos_DataMessage.Sticker) throws -> SSKProtoDataMessageSticker {
        guard proto.hasPackID else {
            throw SSKProtoError.invalidProtobuf(description: "\(logTag) missing required field: packID")
        }
        let packID = proto.packID

        guard proto.hasPackKey else {
            throw SSKProtoError.invalidProtobuf(description: "\(logTag) missing required field: packKey")
        }
        let packKey = proto.packKey

        guard proto.hasStickerID else {
            throw SSKProtoError.invalidProtobuf(description: "\(logTag) missing required field: stickerID")
        }
        let stickerID = proto.stickerID

        guard proto.hasData else {
            throw SSKProtoError.invalidProtobuf(description: "\(logTag) missing required field: data")
        }
        let data = try SSKProtoAttachmentPointer.parseProto(proto.data)

        // MARK: - Begin Validation Logic for SSKProtoDataMessageSticker -

        // MARK: - End Validation Logic for SSKProtoDataMessageSticker -

        let result = SSKProtoDataMessageSticker(proto: proto,
                                                packID: packID,
                                                packKey: packKey,
                                                stickerID: stickerID,
                                                data: data)
        return result
    }

    @objc public override var debugDescription: String {
        return "\(proto)"
    }
}

#if DEBUG

extension SSKProtoDataMessageSticker {
    @objc public func serializedDataIgnoringErrors() -> Data? {
        return try! self.serializedData()
    }
}

extension SSKProtoDataMessageSticker.SSKProtoDataMessageStickerBuilder {
    @objc public func buildIgnoringErrors() -> SSKProtoDataMessageSticker? {
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

    // MARK: - SSKProtoDataMessageProtocolVersion

    @objc public enum SSKProtoDataMessageProtocolVersion: Int32 {
        case initial = 0
        case messageTimers = 1
    }

    private class func SSKProtoDataMessageProtocolVersionWrap(_ value: SignalServiceProtos_DataMessage.ProtocolVersion) -> SSKProtoDataMessageProtocolVersion {
        switch value {
        case .initial: return .initial
        case .messageTimers: return .messageTimers
        }
    }

    private class func SSKProtoDataMessageProtocolVersionUnwrap(_ value: SSKProtoDataMessageProtocolVersion) -> SignalServiceProtos_DataMessage.ProtocolVersion {
        switch value {
        case .initial: return .initial
        case .messageTimers: return .messageTimers
        }
    }

    // MARK: - SSKProtoDataMessageBuilder

    @objc public class func builder() -> SSKProtoDataMessageBuilder {
        return SSKProtoDataMessageBuilder()
    }

    // asBuilder() constructs a builder that reflects the proto's contents.
    @objc public func asBuilder() -> SSKProtoDataMessageBuilder {
        let builder = SSKProtoDataMessageBuilder()
        if let _value = body {
            builder.setBody(_value)
        }
        builder.setAttachments(attachments)
        if let _value = group {
            builder.setGroup(_value)
        }
        if hasFlags {
            builder.setFlags(flags)
        }
        if hasExpireTimer {
            builder.setExpireTimer(expireTimer)
        }
        if let _value = profileKey {
            builder.setProfileKey(_value)
        }
        if hasTimestamp {
            builder.setTimestamp(timestamp)
        }
        if let _value = quote {
            builder.setQuote(_value)
        }
        builder.setContact(contact)
        builder.setPreview(preview)
        if let _value = sticker {
            builder.setSticker(_value)
        }
        if hasRequiredProtocolVersion {
            builder.setRequiredProtocolVersion(requiredProtocolVersion)
        }
        if hasMessageTimer {
            builder.setMessageTimer(messageTimer)
        }
        return builder
    }

    @objc public class SSKProtoDataMessageBuilder: NSObject {

        private var proto = SignalServiceProtos_DataMessage()

        @objc fileprivate override init() {}

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

        @objc public func addPreview(_ valueParam: SSKProtoDataMessagePreview) {
            var items = proto.preview
            items.append(valueParam.proto)
            proto.preview = items
        }

        @objc public func setPreview(_ wrappedItems: [SSKProtoDataMessagePreview]) {
            proto.preview = wrappedItems.map { $0.proto }
        }

        @objc public func setSticker(_ valueParam: SSKProtoDataMessageSticker) {
            proto.sticker = valueParam.proto
        }

        @objc public func setRequiredProtocolVersion(_ valueParam: UInt32) {
            proto.requiredProtocolVersion = valueParam
        }

        @objc public func setMessageTimer(_ valueParam: UInt32) {
            proto.messageTimer = valueParam
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

    @objc public let preview: [SSKProtoDataMessagePreview]

    @objc public let sticker: SSKProtoDataMessageSticker?

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

    @objc public var requiredProtocolVersion: UInt32 {
        return proto.requiredProtocolVersion
    }
    @objc public var hasRequiredProtocolVersion: Bool {
        return proto.hasRequiredProtocolVersion
    }

    @objc public var messageTimer: UInt32 {
        return proto.messageTimer
    }
    @objc public var hasMessageTimer: Bool {
        return proto.hasMessageTimer
    }

    private init(proto: SignalServiceProtos_DataMessage,
                 attachments: [SSKProtoAttachmentPointer],
                 group: SSKProtoGroupContext?,
                 quote: SSKProtoDataMessageQuote?,
                 contact: [SSKProtoDataMessageContact],
                 preview: [SSKProtoDataMessagePreview],
                 sticker: SSKProtoDataMessageSticker?) {
        self.proto = proto
        self.attachments = attachments
        self.group = group
        self.quote = quote
        self.contact = contact
        self.preview = preview
        self.sticker = sticker
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

        var preview: [SSKProtoDataMessagePreview] = []
        preview = try proto.preview.map { try SSKProtoDataMessagePreview.parseProto($0) }

        var sticker: SSKProtoDataMessageSticker? = nil
        if proto.hasSticker {
            sticker = try SSKProtoDataMessageSticker.parseProto(proto.sticker)
        }

        // MARK: - Begin Validation Logic for SSKProtoDataMessage -

        // MARK: - End Validation Logic for SSKProtoDataMessage -

        let result = SSKProtoDataMessage(proto: proto,
                                         attachments: attachments,
                                         group: group,
                                         quote: quote,
                                         contact: contact,
                                         preview: preview,
                                         sticker: sticker)
        return result
    }

    @objc public override var debugDescription: String {
        return "\(proto)"
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

    @objc public class func builder() -> SSKProtoNullMessageBuilder {
        return SSKProtoNullMessageBuilder()
    }

    // asBuilder() constructs a builder that reflects the proto's contents.
    @objc public func asBuilder() -> SSKProtoNullMessageBuilder {
        let builder = SSKProtoNullMessageBuilder()
        if let _value = padding {
            builder.setPadding(_value)
        }
        return builder
    }

    @objc public class SSKProtoNullMessageBuilder: NSObject {

        private var proto = SignalServiceProtos_NullMessage()

        @objc fileprivate override init() {}

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

    @objc public override var debugDescription: String {
        return "\(proto)"
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

    @objc public class func builder() -> SSKProtoReceiptMessageBuilder {
        return SSKProtoReceiptMessageBuilder()
    }

    // asBuilder() constructs a builder that reflects the proto's contents.
    @objc public func asBuilder() -> SSKProtoReceiptMessageBuilder {
        let builder = SSKProtoReceiptMessageBuilder()
        if let _value = type {
            builder.setType(_value)
        }
        builder.setTimestamp(timestamp)
        return builder
    }

    @objc public class SSKProtoReceiptMessageBuilder: NSObject {

        private var proto = SignalServiceProtos_ReceiptMessage()

        @objc fileprivate override init() {}

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

    public var type: SSKProtoReceiptMessageType? {
        guard proto.hasType else {
            return nil
        }
        return SSKProtoReceiptMessage.SSKProtoReceiptMessageTypeWrap(proto.type)
    }
    // This "unwrapped" accessor should only be used if the "has value" accessor has already been checked.
    @objc public var unwrappedType: SSKProtoReceiptMessageType {
        if !hasType {
            // TODO: We could make this a crashing assert.
            owsFailDebug("Unsafe unwrap of missing optional: ReceiptMessage.type.")
        }
        return SSKProtoReceiptMessage.SSKProtoReceiptMessageTypeWrap(proto.type)
    }
    @objc public var hasType: Bool {
        return proto.hasType
    }

    @objc public var timestamp: [UInt64] {
        return proto.timestamp
    }

    private init(proto: SignalServiceProtos_ReceiptMessage) {
        self.proto = proto
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
        // MARK: - Begin Validation Logic for SSKProtoReceiptMessage -

        // MARK: - End Validation Logic for SSKProtoReceiptMessage -

        let result = SSKProtoReceiptMessage(proto: proto)
        return result
    }

    @objc public override var debugDescription: String {
        return "\(proto)"
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

    @objc public class func builder(destination: String) -> SSKProtoVerifiedBuilder {
        return SSKProtoVerifiedBuilder(destination: destination)
    }

    // asBuilder() constructs a builder that reflects the proto's contents.
    @objc public func asBuilder() -> SSKProtoVerifiedBuilder {
        let builder = SSKProtoVerifiedBuilder(destination: destination)
        if let _value = identityKey {
            builder.setIdentityKey(_value)
        }
        if let _value = state {
            builder.setState(_value)
        }
        if let _value = nullMessage {
            builder.setNullMessage(_value)
        }
        return builder
    }

    @objc public class SSKProtoVerifiedBuilder: NSObject {

        private var proto = SignalServiceProtos_Verified()

        @objc fileprivate override init() {}

        @objc fileprivate init(destination: String) {
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

    public var state: SSKProtoVerifiedState? {
        guard proto.hasState else {
            return nil
        }
        return SSKProtoVerified.SSKProtoVerifiedStateWrap(proto.state)
    }
    // This "unwrapped" accessor should only be used if the "has value" accessor has already been checked.
    @objc public var unwrappedState: SSKProtoVerifiedState {
        if !hasState {
            // TODO: We could make this a crashing assert.
            owsFailDebug("Unsafe unwrap of missing optional: Verified.state.")
        }
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

    @objc public override var debugDescription: String {
        return "\(proto)"
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

// MARK: - SSKProtoSyncMessageSentUnidentifiedDeliveryStatus

@objc public class SSKProtoSyncMessageSentUnidentifiedDeliveryStatus: NSObject {

    // MARK: - SSKProtoSyncMessageSentUnidentifiedDeliveryStatusBuilder

    @objc public class func builder() -> SSKProtoSyncMessageSentUnidentifiedDeliveryStatusBuilder {
        return SSKProtoSyncMessageSentUnidentifiedDeliveryStatusBuilder()
    }

    // asBuilder() constructs a builder that reflects the proto's contents.
    @objc public func asBuilder() -> SSKProtoSyncMessageSentUnidentifiedDeliveryStatusBuilder {
        let builder = SSKProtoSyncMessageSentUnidentifiedDeliveryStatusBuilder()
        if let _value = destination {
            builder.setDestination(_value)
        }
        if hasUnidentified {
            builder.setUnidentified(unidentified)
        }
        return builder
    }

    @objc public class SSKProtoSyncMessageSentUnidentifiedDeliveryStatusBuilder: NSObject {

        private var proto = SignalServiceProtos_SyncMessage.Sent.UnidentifiedDeliveryStatus()

        @objc fileprivate override init() {}

        @objc public func setDestination(_ valueParam: String) {
            proto.destination = valueParam
        }

        @objc public func setUnidentified(_ valueParam: Bool) {
            proto.unidentified = valueParam
        }

        @objc public func build() throws -> SSKProtoSyncMessageSentUnidentifiedDeliveryStatus {
            return try SSKProtoSyncMessageSentUnidentifiedDeliveryStatus.parseProto(proto)
        }

        @objc public func buildSerializedData() throws -> Data {
            return try SSKProtoSyncMessageSentUnidentifiedDeliveryStatus.parseProto(proto).serializedData()
        }
    }

    fileprivate let proto: SignalServiceProtos_SyncMessage.Sent.UnidentifiedDeliveryStatus

    @objc public var destination: String? {
        guard proto.hasDestination else {
            return nil
        }
        return proto.destination
    }
    @objc public var hasDestination: Bool {
        return proto.hasDestination
    }

    @objc public var unidentified: Bool {
        return proto.unidentified
    }
    @objc public var hasUnidentified: Bool {
        return proto.hasUnidentified
    }

    private init(proto: SignalServiceProtos_SyncMessage.Sent.UnidentifiedDeliveryStatus) {
        self.proto = proto
    }

    @objc
    public func serializedData() throws -> Data {
        return try self.proto.serializedData()
    }

    @objc public class func parseData(_ serializedData: Data) throws -> SSKProtoSyncMessageSentUnidentifiedDeliveryStatus {
        let proto = try SignalServiceProtos_SyncMessage.Sent.UnidentifiedDeliveryStatus(serializedData: serializedData)
        return try parseProto(proto)
    }

    fileprivate class func parseProto(_ proto: SignalServiceProtos_SyncMessage.Sent.UnidentifiedDeliveryStatus) throws -> SSKProtoSyncMessageSentUnidentifiedDeliveryStatus {
        // MARK: - Begin Validation Logic for SSKProtoSyncMessageSentUnidentifiedDeliveryStatus -

        // MARK: - End Validation Logic for SSKProtoSyncMessageSentUnidentifiedDeliveryStatus -

        let result = SSKProtoSyncMessageSentUnidentifiedDeliveryStatus(proto: proto)
        return result
    }

    @objc public override var debugDescription: String {
        return "\(proto)"
    }
}

#if DEBUG

extension SSKProtoSyncMessageSentUnidentifiedDeliveryStatus {
    @objc public func serializedDataIgnoringErrors() -> Data? {
        return try! self.serializedData()
    }
}

extension SSKProtoSyncMessageSentUnidentifiedDeliveryStatus.SSKProtoSyncMessageSentUnidentifiedDeliveryStatusBuilder {
    @objc public func buildIgnoringErrors() -> SSKProtoSyncMessageSentUnidentifiedDeliveryStatus? {
        return try! self.build()
    }
}

#endif

// MARK: - SSKProtoSyncMessageSent

@objc public class SSKProtoSyncMessageSent: NSObject {

    // MARK: - SSKProtoSyncMessageSentBuilder

    @objc public class func builder() -> SSKProtoSyncMessageSentBuilder {
        return SSKProtoSyncMessageSentBuilder()
    }

    // asBuilder() constructs a builder that reflects the proto's contents.
    @objc public func asBuilder() -> SSKProtoSyncMessageSentBuilder {
        let builder = SSKProtoSyncMessageSentBuilder()
        if let _value = destination {
            builder.setDestination(_value)
        }
        if hasTimestamp {
            builder.setTimestamp(timestamp)
        }
        if let _value = message {
            builder.setMessage(_value)
        }
        if hasExpirationStartTimestamp {
            builder.setExpirationStartTimestamp(expirationStartTimestamp)
        }
        builder.setUnidentifiedStatus(unidentifiedStatus)
        if hasIsRecipientUpdate {
            builder.setIsRecipientUpdate(isRecipientUpdate)
        }
        return builder
    }

    @objc public class SSKProtoSyncMessageSentBuilder: NSObject {

        private var proto = SignalServiceProtos_SyncMessage.Sent()

        @objc fileprivate override init() {}

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

        @objc public func addUnidentifiedStatus(_ valueParam: SSKProtoSyncMessageSentUnidentifiedDeliveryStatus) {
            var items = proto.unidentifiedStatus
            items.append(valueParam.proto)
            proto.unidentifiedStatus = items
        }

        @objc public func setUnidentifiedStatus(_ wrappedItems: [SSKProtoSyncMessageSentUnidentifiedDeliveryStatus]) {
            proto.unidentifiedStatus = wrappedItems.map { $0.proto }
        }

        @objc public func setIsRecipientUpdate(_ valueParam: Bool) {
            proto.isRecipientUpdate = valueParam
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

    @objc public let unidentifiedStatus: [SSKProtoSyncMessageSentUnidentifiedDeliveryStatus]

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

    @objc public var isRecipientUpdate: Bool {
        return proto.isRecipientUpdate
    }
    @objc public var hasIsRecipientUpdate: Bool {
        return proto.hasIsRecipientUpdate
    }

    private init(proto: SignalServiceProtos_SyncMessage.Sent,
                 message: SSKProtoDataMessage?,
                 unidentifiedStatus: [SSKProtoSyncMessageSentUnidentifiedDeliveryStatus]) {
        self.proto = proto
        self.message = message
        self.unidentifiedStatus = unidentifiedStatus
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

        var unidentifiedStatus: [SSKProtoSyncMessageSentUnidentifiedDeliveryStatus] = []
        unidentifiedStatus = try proto.unidentifiedStatus.map { try SSKProtoSyncMessageSentUnidentifiedDeliveryStatus.parseProto($0) }

        // MARK: - Begin Validation Logic for SSKProtoSyncMessageSent -

        // MARK: - End Validation Logic for SSKProtoSyncMessageSent -

        let result = SSKProtoSyncMessageSent(proto: proto,
                                             message: message,
                                             unidentifiedStatus: unidentifiedStatus)
        return result
    }

    @objc public override var debugDescription: String {
        return "\(proto)"
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

    @objc public class func builder(blob: SSKProtoAttachmentPointer) -> SSKProtoSyncMessageContactsBuilder {
        return SSKProtoSyncMessageContactsBuilder(blob: blob)
    }

    // asBuilder() constructs a builder that reflects the proto's contents.
    @objc public func asBuilder() -> SSKProtoSyncMessageContactsBuilder {
        let builder = SSKProtoSyncMessageContactsBuilder(blob: blob)
        if hasIsComplete {
            builder.setIsComplete(isComplete)
        }
        return builder
    }

    @objc public class SSKProtoSyncMessageContactsBuilder: NSObject {

        private var proto = SignalServiceProtos_SyncMessage.Contacts()

        @objc fileprivate override init() {}

        @objc fileprivate init(blob: SSKProtoAttachmentPointer) {
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

    @objc public override var debugDescription: String {
        return "\(proto)"
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

    @objc public class func builder() -> SSKProtoSyncMessageGroupsBuilder {
        return SSKProtoSyncMessageGroupsBuilder()
    }

    // asBuilder() constructs a builder that reflects the proto's contents.
    @objc public func asBuilder() -> SSKProtoSyncMessageGroupsBuilder {
        let builder = SSKProtoSyncMessageGroupsBuilder()
        if let _value = blob {
            builder.setBlob(_value)
        }
        return builder
    }

    @objc public class SSKProtoSyncMessageGroupsBuilder: NSObject {

        private var proto = SignalServiceProtos_SyncMessage.Groups()

        @objc fileprivate override init() {}

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

    @objc public override var debugDescription: String {
        return "\(proto)"
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

    @objc public class func builder() -> SSKProtoSyncMessageBlockedBuilder {
        return SSKProtoSyncMessageBlockedBuilder()
    }

    // asBuilder() constructs a builder that reflects the proto's contents.
    @objc public func asBuilder() -> SSKProtoSyncMessageBlockedBuilder {
        let builder = SSKProtoSyncMessageBlockedBuilder()
        builder.setNumbers(numbers)
        builder.setGroupIds(groupIds)
        builder.setUuids(uuids)
        return builder
    }

    @objc public class SSKProtoSyncMessageBlockedBuilder: NSObject {

        private var proto = SignalServiceProtos_SyncMessage.Blocked()

        @objc fileprivate override init() {}

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

        @objc public func addUuids(_ valueParam: String) {
            var items = proto.uuids
            items.append(valueParam)
            proto.uuids = items
        }

        @objc public func setUuids(_ wrappedItems: [String]) {
            proto.uuids = wrappedItems
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

    @objc public var uuids: [String] {
        return proto.uuids
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

    @objc public override var debugDescription: String {
        return "\(proto)"
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

    @objc public class func builder() -> SSKProtoSyncMessageRequestBuilder {
        return SSKProtoSyncMessageRequestBuilder()
    }

    // asBuilder() constructs a builder that reflects the proto's contents.
    @objc public func asBuilder() -> SSKProtoSyncMessageRequestBuilder {
        let builder = SSKProtoSyncMessageRequestBuilder()
        if let _value = type {
            builder.setType(_value)
        }
        return builder
    }

    @objc public class SSKProtoSyncMessageRequestBuilder: NSObject {

        private var proto = SignalServiceProtos_SyncMessage.Request()

        @objc fileprivate override init() {}

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

    public var type: SSKProtoSyncMessageRequestType? {
        guard proto.hasType else {
            return nil
        }
        return SSKProtoSyncMessageRequest.SSKProtoSyncMessageRequestTypeWrap(proto.type)
    }
    // This "unwrapped" accessor should only be used if the "has value" accessor has already been checked.
    @objc public var unwrappedType: SSKProtoSyncMessageRequestType {
        if !hasType {
            // TODO: We could make this a crashing assert.
            owsFailDebug("Unsafe unwrap of missing optional: Request.type.")
        }
        return SSKProtoSyncMessageRequest.SSKProtoSyncMessageRequestTypeWrap(proto.type)
    }
    @objc public var hasType: Bool {
        return proto.hasType
    }

    private init(proto: SignalServiceProtos_SyncMessage.Request) {
        self.proto = proto
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
        // MARK: - Begin Validation Logic for SSKProtoSyncMessageRequest -

        // MARK: - End Validation Logic for SSKProtoSyncMessageRequest -

        let result = SSKProtoSyncMessageRequest(proto: proto)
        return result
    }

    @objc public override var debugDescription: String {
        return "\(proto)"
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

    @objc public class func builder(sender: String, timestamp: UInt64) -> SSKProtoSyncMessageReadBuilder {
        return SSKProtoSyncMessageReadBuilder(sender: sender, timestamp: timestamp)
    }

    // asBuilder() constructs a builder that reflects the proto's contents.
    @objc public func asBuilder() -> SSKProtoSyncMessageReadBuilder {
        let builder = SSKProtoSyncMessageReadBuilder(sender: sender, timestamp: timestamp)
        return builder
    }

    @objc public class SSKProtoSyncMessageReadBuilder: NSObject {

        private var proto = SignalServiceProtos_SyncMessage.Read()

        @objc fileprivate override init() {}

        @objc fileprivate init(sender: String, timestamp: UInt64) {
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

    @objc public override var debugDescription: String {
        return "\(proto)"
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

    @objc public class func builder() -> SSKProtoSyncMessageConfigurationBuilder {
        return SSKProtoSyncMessageConfigurationBuilder()
    }

    // asBuilder() constructs a builder that reflects the proto's contents.
    @objc public func asBuilder() -> SSKProtoSyncMessageConfigurationBuilder {
        let builder = SSKProtoSyncMessageConfigurationBuilder()
        if hasReadReceipts {
            builder.setReadReceipts(readReceipts)
        }
        if hasUnidentifiedDeliveryIndicators {
            builder.setUnidentifiedDeliveryIndicators(unidentifiedDeliveryIndicators)
        }
        if hasTypingIndicators {
            builder.setTypingIndicators(typingIndicators)
        }
        if hasLinkPreviews {
            builder.setLinkPreviews(linkPreviews)
        }
        return builder
    }

    @objc public class SSKProtoSyncMessageConfigurationBuilder: NSObject {

        private var proto = SignalServiceProtos_SyncMessage.Configuration()

        @objc fileprivate override init() {}

        @objc public func setReadReceipts(_ valueParam: Bool) {
            proto.readReceipts = valueParam
        }

        @objc public func setUnidentifiedDeliveryIndicators(_ valueParam: Bool) {
            proto.unidentifiedDeliveryIndicators = valueParam
        }

        @objc public func setTypingIndicators(_ valueParam: Bool) {
            proto.typingIndicators = valueParam
        }

        @objc public func setLinkPreviews(_ valueParam: Bool) {
            proto.linkPreviews = valueParam
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

    @objc public var unidentifiedDeliveryIndicators: Bool {
        return proto.unidentifiedDeliveryIndicators
    }
    @objc public var hasUnidentifiedDeliveryIndicators: Bool {
        return proto.hasUnidentifiedDeliveryIndicators
    }

    @objc public var typingIndicators: Bool {
        return proto.typingIndicators
    }
    @objc public var hasTypingIndicators: Bool {
        return proto.hasTypingIndicators
    }

    @objc public var linkPreviews: Bool {
        return proto.linkPreviews
    }
    @objc public var hasLinkPreviews: Bool {
        return proto.hasLinkPreviews
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

    @objc public override var debugDescription: String {
        return "\(proto)"
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

// MARK: - SSKProtoSyncMessageStickerPackOperation

@objc public class SSKProtoSyncMessageStickerPackOperation: NSObject {

    // MARK: - SSKProtoSyncMessageStickerPackOperationType

    @objc public enum SSKProtoSyncMessageStickerPackOperationType: Int32 {
        case install = 0
        case remove = 1
    }

    private class func SSKProtoSyncMessageStickerPackOperationTypeWrap(_ value: SignalServiceProtos_SyncMessage.StickerPackOperation.TypeEnum) -> SSKProtoSyncMessageStickerPackOperationType {
        switch value {
        case .install: return .install
        case .remove: return .remove
        }
    }

    private class func SSKProtoSyncMessageStickerPackOperationTypeUnwrap(_ value: SSKProtoSyncMessageStickerPackOperationType) -> SignalServiceProtos_SyncMessage.StickerPackOperation.TypeEnum {
        switch value {
        case .install: return .install
        case .remove: return .remove
        }
    }

    // MARK: - SSKProtoSyncMessageStickerPackOperationBuilder

    @objc public class func builder(packID: Data, packKey: Data) -> SSKProtoSyncMessageStickerPackOperationBuilder {
        return SSKProtoSyncMessageStickerPackOperationBuilder(packID: packID, packKey: packKey)
    }

    // asBuilder() constructs a builder that reflects the proto's contents.
    @objc public func asBuilder() -> SSKProtoSyncMessageStickerPackOperationBuilder {
        let builder = SSKProtoSyncMessageStickerPackOperationBuilder(packID: packID, packKey: packKey)
        if let _value = type {
            builder.setType(_value)
        }
        return builder
    }

    @objc public class SSKProtoSyncMessageStickerPackOperationBuilder: NSObject {

        private var proto = SignalServiceProtos_SyncMessage.StickerPackOperation()

        @objc fileprivate override init() {}

        @objc fileprivate init(packID: Data, packKey: Data) {
            super.init()

            setPackID(packID)
            setPackKey(packKey)
        }

        @objc public func setPackID(_ valueParam: Data) {
            proto.packID = valueParam
        }

        @objc public func setPackKey(_ valueParam: Data) {
            proto.packKey = valueParam
        }

        @objc public func setType(_ valueParam: SSKProtoSyncMessageStickerPackOperationType) {
            proto.type = SSKProtoSyncMessageStickerPackOperationTypeUnwrap(valueParam)
        }

        @objc public func build() throws -> SSKProtoSyncMessageStickerPackOperation {
            return try SSKProtoSyncMessageStickerPackOperation.parseProto(proto)
        }

        @objc public func buildSerializedData() throws -> Data {
            return try SSKProtoSyncMessageStickerPackOperation.parseProto(proto).serializedData()
        }
    }

    fileprivate let proto: SignalServiceProtos_SyncMessage.StickerPackOperation

    @objc public let packID: Data

    @objc public let packKey: Data

    public var type: SSKProtoSyncMessageStickerPackOperationType? {
        guard proto.hasType else {
            return nil
        }
        return SSKProtoSyncMessageStickerPackOperation.SSKProtoSyncMessageStickerPackOperationTypeWrap(proto.type)
    }
    // This "unwrapped" accessor should only be used if the "has value" accessor has already been checked.
    @objc public var unwrappedType: SSKProtoSyncMessageStickerPackOperationType {
        if !hasType {
            // TODO: We could make this a crashing assert.
            owsFailDebug("Unsafe unwrap of missing optional: StickerPackOperation.type.")
        }
        return SSKProtoSyncMessageStickerPackOperation.SSKProtoSyncMessageStickerPackOperationTypeWrap(proto.type)
    }
    @objc public var hasType: Bool {
        return proto.hasType
    }

    private init(proto: SignalServiceProtos_SyncMessage.StickerPackOperation,
                 packID: Data,
                 packKey: Data) {
        self.proto = proto
        self.packID = packID
        self.packKey = packKey
    }

    @objc
    public func serializedData() throws -> Data {
        return try self.proto.serializedData()
    }

    @objc public class func parseData(_ serializedData: Data) throws -> SSKProtoSyncMessageStickerPackOperation {
        let proto = try SignalServiceProtos_SyncMessage.StickerPackOperation(serializedData: serializedData)
        return try parseProto(proto)
    }

    fileprivate class func parseProto(_ proto: SignalServiceProtos_SyncMessage.StickerPackOperation) throws -> SSKProtoSyncMessageStickerPackOperation {
        guard proto.hasPackID else {
            throw SSKProtoError.invalidProtobuf(description: "\(logTag) missing required field: packID")
        }
        let packID = proto.packID

        guard proto.hasPackKey else {
            throw SSKProtoError.invalidProtobuf(description: "\(logTag) missing required field: packKey")
        }
        let packKey = proto.packKey

        // MARK: - Begin Validation Logic for SSKProtoSyncMessageStickerPackOperation -

        // MARK: - End Validation Logic for SSKProtoSyncMessageStickerPackOperation -

        let result = SSKProtoSyncMessageStickerPackOperation(proto: proto,
                                                             packID: packID,
                                                             packKey: packKey)
        return result
    }

    @objc public override var debugDescription: String {
        return "\(proto)"
    }
}

#if DEBUG

extension SSKProtoSyncMessageStickerPackOperation {
    @objc public func serializedDataIgnoringErrors() -> Data? {
        return try! self.serializedData()
    }
}

extension SSKProtoSyncMessageStickerPackOperation.SSKProtoSyncMessageStickerPackOperationBuilder {
    @objc public func buildIgnoringErrors() -> SSKProtoSyncMessageStickerPackOperation? {
        return try! self.build()
    }
}

#endif

// MARK: - SSKProtoSyncMessageMessageTimerRead

@objc public class SSKProtoSyncMessageMessageTimerRead: NSObject {

    // MARK: - SSKProtoSyncMessageMessageTimerReadBuilder

    @objc public class func builder(sender: String, timestamp: UInt64) -> SSKProtoSyncMessageMessageTimerReadBuilder {
        return SSKProtoSyncMessageMessageTimerReadBuilder(sender: sender, timestamp: timestamp)
    }

    // asBuilder() constructs a builder that reflects the proto's contents.
    @objc public func asBuilder() -> SSKProtoSyncMessageMessageTimerReadBuilder {
        let builder = SSKProtoSyncMessageMessageTimerReadBuilder(sender: sender, timestamp: timestamp)
        return builder
    }

    @objc public class SSKProtoSyncMessageMessageTimerReadBuilder: NSObject {

        private var proto = SignalServiceProtos_SyncMessage.MessageTimerRead()

        @objc fileprivate override init() {}

        @objc fileprivate init(sender: String, timestamp: UInt64) {
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

        @objc public func build() throws -> SSKProtoSyncMessageMessageTimerRead {
            return try SSKProtoSyncMessageMessageTimerRead.parseProto(proto)
        }

        @objc public func buildSerializedData() throws -> Data {
            return try SSKProtoSyncMessageMessageTimerRead.parseProto(proto).serializedData()
        }
    }

    fileprivate let proto: SignalServiceProtos_SyncMessage.MessageTimerRead

    @objc public let sender: String

    @objc public let timestamp: UInt64

    private init(proto: SignalServiceProtos_SyncMessage.MessageTimerRead,
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

    @objc public class func parseData(_ serializedData: Data) throws -> SSKProtoSyncMessageMessageTimerRead {
        let proto = try SignalServiceProtos_SyncMessage.MessageTimerRead(serializedData: serializedData)
        return try parseProto(proto)
    }

    fileprivate class func parseProto(_ proto: SignalServiceProtos_SyncMessage.MessageTimerRead) throws -> SSKProtoSyncMessageMessageTimerRead {
        guard proto.hasSender else {
            throw SSKProtoError.invalidProtobuf(description: "\(logTag) missing required field: sender")
        }
        let sender = proto.sender

        guard proto.hasTimestamp else {
            throw SSKProtoError.invalidProtobuf(description: "\(logTag) missing required field: timestamp")
        }
        let timestamp = proto.timestamp

        // MARK: - Begin Validation Logic for SSKProtoSyncMessageMessageTimerRead -

        // MARK: - End Validation Logic for SSKProtoSyncMessageMessageTimerRead -

        let result = SSKProtoSyncMessageMessageTimerRead(proto: proto,
                                                         sender: sender,
                                                         timestamp: timestamp)
        return result
    }

    @objc public override var debugDescription: String {
        return "\(proto)"
    }
}

#if DEBUG

extension SSKProtoSyncMessageMessageTimerRead {
    @objc public func serializedDataIgnoringErrors() -> Data? {
        return try! self.serializedData()
    }
}

extension SSKProtoSyncMessageMessageTimerRead.SSKProtoSyncMessageMessageTimerReadBuilder {
    @objc public func buildIgnoringErrors() -> SSKProtoSyncMessageMessageTimerRead? {
        return try! self.build()
    }
}

#endif

// MARK: - SSKProtoSyncMessage

@objc public class SSKProtoSyncMessage: NSObject {

    // MARK: - SSKProtoSyncMessageBuilder

    @objc public class func builder() -> SSKProtoSyncMessageBuilder {
        return SSKProtoSyncMessageBuilder()
    }

    // asBuilder() constructs a builder that reflects the proto's contents.
    @objc public func asBuilder() -> SSKProtoSyncMessageBuilder {
        let builder = SSKProtoSyncMessageBuilder()
        if let _value = sent {
            builder.setSent(_value)
        }
        if let _value = contacts {
            builder.setContacts(_value)
        }
        if let _value = groups {
            builder.setGroups(_value)
        }
        if let _value = request {
            builder.setRequest(_value)
        }
        builder.setRead(read)
        if let _value = blocked {
            builder.setBlocked(_value)
        }
        if let _value = verified {
            builder.setVerified(_value)
        }
        if let _value = configuration {
            builder.setConfiguration(_value)
        }
        if let _value = padding {
            builder.setPadding(_value)
        }
        builder.setStickerPackOperation(stickerPackOperation)
        if let _value = messageTimerRead {
            builder.setMessageTimerRead(_value)
        }
        return builder
    }

    @objc public class SSKProtoSyncMessageBuilder: NSObject {

        private var proto = SignalServiceProtos_SyncMessage()

        @objc fileprivate override init() {}

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

        @objc public func addStickerPackOperation(_ valueParam: SSKProtoSyncMessageStickerPackOperation) {
            var items = proto.stickerPackOperation
            items.append(valueParam.proto)
            proto.stickerPackOperation = items
        }

        @objc public func setStickerPackOperation(_ wrappedItems: [SSKProtoSyncMessageStickerPackOperation]) {
            proto.stickerPackOperation = wrappedItems.map { $0.proto }
        }

        @objc public func setMessageTimerRead(_ valueParam: SSKProtoSyncMessageMessageTimerRead) {
            proto.messageTimerRead = valueParam.proto
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

    @objc public let stickerPackOperation: [SSKProtoSyncMessageStickerPackOperation]

    @objc public let messageTimerRead: SSKProtoSyncMessageMessageTimerRead?

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
                 configuration: SSKProtoSyncMessageConfiguration?,
                 stickerPackOperation: [SSKProtoSyncMessageStickerPackOperation],
                 messageTimerRead: SSKProtoSyncMessageMessageTimerRead?) {
        self.proto = proto
        self.sent = sent
        self.contacts = contacts
        self.groups = groups
        self.request = request
        self.read = read
        self.blocked = blocked
        self.verified = verified
        self.configuration = configuration
        self.stickerPackOperation = stickerPackOperation
        self.messageTimerRead = messageTimerRead
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

        var stickerPackOperation: [SSKProtoSyncMessageStickerPackOperation] = []
        stickerPackOperation = try proto.stickerPackOperation.map { try SSKProtoSyncMessageStickerPackOperation.parseProto($0) }

        var messageTimerRead: SSKProtoSyncMessageMessageTimerRead? = nil
        if proto.hasMessageTimerRead {
            messageTimerRead = try SSKProtoSyncMessageMessageTimerRead.parseProto(proto.messageTimerRead)
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
                                         configuration: configuration,
                                         stickerPackOperation: stickerPackOperation,
                                         messageTimerRead: messageTimerRead)
        return result
    }

    @objc public override var debugDescription: String {
        return "\(proto)"
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

    @objc public class func builder(id: UInt64) -> SSKProtoAttachmentPointerBuilder {
        return SSKProtoAttachmentPointerBuilder(id: id)
    }

    // asBuilder() constructs a builder that reflects the proto's contents.
    @objc public func asBuilder() -> SSKProtoAttachmentPointerBuilder {
        let builder = SSKProtoAttachmentPointerBuilder(id: id)
        if let _value = contentType {
            builder.setContentType(_value)
        }
        if let _value = key {
            builder.setKey(_value)
        }
        if hasSize {
            builder.setSize(size)
        }
        if let _value = thumbnail {
            builder.setThumbnail(_value)
        }
        if let _value = digest {
            builder.setDigest(_value)
        }
        if let _value = fileName {
            builder.setFileName(_value)
        }
        if hasFlags {
            builder.setFlags(flags)
        }
        if hasWidth {
            builder.setWidth(width)
        }
        if hasHeight {
            builder.setHeight(height)
        }
        if let _value = caption {
            builder.setCaption(_value)
        }
        return builder
    }

    @objc public class SSKProtoAttachmentPointerBuilder: NSObject {

        private var proto = SignalServiceProtos_AttachmentPointer()

        @objc fileprivate override init() {}

        @objc fileprivate init(id: UInt64) {
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

        @objc public func setCaption(_ valueParam: String) {
            proto.caption = valueParam
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

    @objc public var caption: String? {
        guard proto.hasCaption else {
            return nil
        }
        return proto.caption
    }
    @objc public var hasCaption: Bool {
        return proto.hasCaption
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

    @objc public override var debugDescription: String {
        return "\(proto)"
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

    @objc public class func builder(id: Data) -> SSKProtoGroupContextBuilder {
        return SSKProtoGroupContextBuilder(id: id)
    }

    // asBuilder() constructs a builder that reflects the proto's contents.
    @objc public func asBuilder() -> SSKProtoGroupContextBuilder {
        let builder = SSKProtoGroupContextBuilder(id: id)
        if let _value = type {
            builder.setType(_value)
        }
        if let _value = name {
            builder.setName(_value)
        }
        builder.setMembers(members)
        if let _value = avatar {
            builder.setAvatar(_value)
        }
        return builder
    }

    @objc public class SSKProtoGroupContextBuilder: NSObject {

        private var proto = SignalServiceProtos_GroupContext()

        @objc fileprivate override init() {}

        @objc fileprivate init(id: Data) {
            super.init()

            setId(id)
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

    @objc public let avatar: SSKProtoAttachmentPointer?

    public var type: SSKProtoGroupContextType? {
        guard proto.hasType else {
            return nil
        }
        return SSKProtoGroupContext.SSKProtoGroupContextTypeWrap(proto.type)
    }
    // This "unwrapped" accessor should only be used if the "has value" accessor has already been checked.
    @objc public var unwrappedType: SSKProtoGroupContextType {
        if !hasType {
            // TODO: We could make this a crashing assert.
            owsFailDebug("Unsafe unwrap of missing optional: GroupContext.type.")
        }
        return SSKProtoGroupContext.SSKProtoGroupContextTypeWrap(proto.type)
    }
    @objc public var hasType: Bool {
        return proto.hasType
    }

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
                 avatar: SSKProtoAttachmentPointer?) {
        self.proto = proto
        self.id = id
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

        var avatar: SSKProtoAttachmentPointer? = nil
        if proto.hasAvatar {
            avatar = try SSKProtoAttachmentPointer.parseProto(proto.avatar)
        }

        // MARK: - Begin Validation Logic for SSKProtoGroupContext -

        // MARK: - End Validation Logic for SSKProtoGroupContext -

        let result = SSKProtoGroupContext(proto: proto,
                                          id: id,
                                          avatar: avatar)
        return result
    }

    @objc public override var debugDescription: String {
        return "\(proto)"
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

    @objc public class func builder() -> SSKProtoContactDetailsAvatarBuilder {
        return SSKProtoContactDetailsAvatarBuilder()
    }

    // asBuilder() constructs a builder that reflects the proto's contents.
    @objc public func asBuilder() -> SSKProtoContactDetailsAvatarBuilder {
        let builder = SSKProtoContactDetailsAvatarBuilder()
        if let _value = contentType {
            builder.setContentType(_value)
        }
        if hasLength {
            builder.setLength(length)
        }
        return builder
    }

    @objc public class SSKProtoContactDetailsAvatarBuilder: NSObject {

        private var proto = SignalServiceProtos_ContactDetails.Avatar()

        @objc fileprivate override init() {}

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

    @objc public override var debugDescription: String {
        return "\(proto)"
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

    @objc public class func builder(number: String) -> SSKProtoContactDetailsBuilder {
        return SSKProtoContactDetailsBuilder(number: number)
    }

    // asBuilder() constructs a builder that reflects the proto's contents.
    @objc public func asBuilder() -> SSKProtoContactDetailsBuilder {
        let builder = SSKProtoContactDetailsBuilder(number: number)
        if let _value = name {
            builder.setName(_value)
        }
        if let _value = avatar {
            builder.setAvatar(_value)
        }
        if let _value = color {
            builder.setColor(_value)
        }
        if let _value = verified {
            builder.setVerified(_value)
        }
        if let _value = profileKey {
            builder.setProfileKey(_value)
        }
        if hasBlocked {
            builder.setBlocked(blocked)
        }
        if hasExpireTimer {
            builder.setExpireTimer(expireTimer)
        }
        return builder
    }

    @objc public class SSKProtoContactDetailsBuilder: NSObject {

        private var proto = SignalServiceProtos_ContactDetails()

        @objc fileprivate override init() {}

        @objc fileprivate init(number: String) {
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

    @objc public override var debugDescription: String {
        return "\(proto)"
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

    @objc public class func builder() -> SSKProtoGroupDetailsAvatarBuilder {
        return SSKProtoGroupDetailsAvatarBuilder()
    }

    // asBuilder() constructs a builder that reflects the proto's contents.
    @objc public func asBuilder() -> SSKProtoGroupDetailsAvatarBuilder {
        let builder = SSKProtoGroupDetailsAvatarBuilder()
        if let _value = contentType {
            builder.setContentType(_value)
        }
        if hasLength {
            builder.setLength(length)
        }
        return builder
    }

    @objc public class SSKProtoGroupDetailsAvatarBuilder: NSObject {

        private var proto = SignalServiceProtos_GroupDetails.Avatar()

        @objc fileprivate override init() {}

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

    @objc public override var debugDescription: String {
        return "\(proto)"
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

    @objc public class func builder(id: Data) -> SSKProtoGroupDetailsBuilder {
        return SSKProtoGroupDetailsBuilder(id: id)
    }

    // asBuilder() constructs a builder that reflects the proto's contents.
    @objc public func asBuilder() -> SSKProtoGroupDetailsBuilder {
        let builder = SSKProtoGroupDetailsBuilder(id: id)
        if let _value = name {
            builder.setName(_value)
        }
        builder.setMembers(members)
        if let _value = avatar {
            builder.setAvatar(_value)
        }
        if hasActive {
            builder.setActive(active)
        }
        if hasExpireTimer {
            builder.setExpireTimer(expireTimer)
        }
        if let _value = color {
            builder.setColor(_value)
        }
        if hasBlocked {
            builder.setBlocked(blocked)
        }
        return builder
    }

    @objc public class SSKProtoGroupDetailsBuilder: NSObject {

        private var proto = SignalServiceProtos_GroupDetails()

        @objc fileprivate override init() {}

        @objc fileprivate init(id: Data) {
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

    @objc public override var debugDescription: String {
        return "\(proto)"
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

// MARK: - SSKProtoPackSticker

@objc public class SSKProtoPackSticker: NSObject {

    // MARK: - SSKProtoPackStickerBuilder

    @objc public class func builder(id: UInt32, emoji: String) -> SSKProtoPackStickerBuilder {
        return SSKProtoPackStickerBuilder(id: id, emoji: emoji)
    }

    // asBuilder() constructs a builder that reflects the proto's contents.
    @objc public func asBuilder() -> SSKProtoPackStickerBuilder {
        let builder = SSKProtoPackStickerBuilder(id: id, emoji: emoji)
        return builder
    }

    @objc public class SSKProtoPackStickerBuilder: NSObject {

        private var proto = SignalServiceProtos_Pack.Sticker()

        @objc fileprivate override init() {}

        @objc fileprivate init(id: UInt32, emoji: String) {
            super.init()

            setId(id)
            setEmoji(emoji)
        }

        @objc public func setId(_ valueParam: UInt32) {
            proto.id = valueParam
        }

        @objc public func setEmoji(_ valueParam: String) {
            proto.emoji = valueParam
        }

        @objc public func build() throws -> SSKProtoPackSticker {
            return try SSKProtoPackSticker.parseProto(proto)
        }

        @objc public func buildSerializedData() throws -> Data {
            return try SSKProtoPackSticker.parseProto(proto).serializedData()
        }
    }

    fileprivate let proto: SignalServiceProtos_Pack.Sticker

    @objc public let id: UInt32

    @objc public let emoji: String

    private init(proto: SignalServiceProtos_Pack.Sticker,
                 id: UInt32,
                 emoji: String) {
        self.proto = proto
        self.id = id
        self.emoji = emoji
    }

    @objc
    public func serializedData() throws -> Data {
        return try self.proto.serializedData()
    }

    @objc public class func parseData(_ serializedData: Data) throws -> SSKProtoPackSticker {
        let proto = try SignalServiceProtos_Pack.Sticker(serializedData: serializedData)
        return try parseProto(proto)
    }

    fileprivate class func parseProto(_ proto: SignalServiceProtos_Pack.Sticker) throws -> SSKProtoPackSticker {
        guard proto.hasID else {
            throw SSKProtoError.invalidProtobuf(description: "\(logTag) missing required field: id")
        }
        let id = proto.id

        guard proto.hasEmoji else {
            throw SSKProtoError.invalidProtobuf(description: "\(logTag) missing required field: emoji")
        }
        let emoji = proto.emoji

        // MARK: - Begin Validation Logic for SSKProtoPackSticker -

        // MARK: - End Validation Logic for SSKProtoPackSticker -

        let result = SSKProtoPackSticker(proto: proto,
                                         id: id,
                                         emoji: emoji)
        return result
    }

    @objc public override var debugDescription: String {
        return "\(proto)"
    }
}

#if DEBUG

extension SSKProtoPackSticker {
    @objc public func serializedDataIgnoringErrors() -> Data? {
        return try! self.serializedData()
    }
}

extension SSKProtoPackSticker.SSKProtoPackStickerBuilder {
    @objc public func buildIgnoringErrors() -> SSKProtoPackSticker? {
        return try! self.build()
    }
}

#endif

// MARK: - SSKProtoPack

@objc public class SSKProtoPack: NSObject {

    // MARK: - SSKProtoPackBuilder

    @objc public class func builder() -> SSKProtoPackBuilder {
        return SSKProtoPackBuilder()
    }

    // asBuilder() constructs a builder that reflects the proto's contents.
    @objc public func asBuilder() -> SSKProtoPackBuilder {
        let builder = SSKProtoPackBuilder()
        if let _value = title {
            builder.setTitle(_value)
        }
        if let _value = author {
            builder.setAuthor(_value)
        }
        if let _value = cover {
            builder.setCover(_value)
        }
        builder.setStickers(stickers)
        return builder
    }

    @objc public class SSKProtoPackBuilder: NSObject {

        private var proto = SignalServiceProtos_Pack()

        @objc fileprivate override init() {}

        @objc public func setTitle(_ valueParam: String) {
            proto.title = valueParam
        }

        @objc public func setAuthor(_ valueParam: String) {
            proto.author = valueParam
        }

        @objc public func setCover(_ valueParam: SSKProtoPackSticker) {
            proto.cover = valueParam.proto
        }

        @objc public func addStickers(_ valueParam: SSKProtoPackSticker) {
            var items = proto.stickers
            items.append(valueParam.proto)
            proto.stickers = items
        }

        @objc public func setStickers(_ wrappedItems: [SSKProtoPackSticker]) {
            proto.stickers = wrappedItems.map { $0.proto }
        }

        @objc public func build() throws -> SSKProtoPack {
            return try SSKProtoPack.parseProto(proto)
        }

        @objc public func buildSerializedData() throws -> Data {
            return try SSKProtoPack.parseProto(proto).serializedData()
        }
    }

    fileprivate let proto: SignalServiceProtos_Pack

    @objc public let cover: SSKProtoPackSticker?

    @objc public let stickers: [SSKProtoPackSticker]

    @objc public var title: String? {
        guard proto.hasTitle else {
            return nil
        }
        return proto.title
    }
    @objc public var hasTitle: Bool {
        return proto.hasTitle
    }

    @objc public var author: String? {
        guard proto.hasAuthor else {
            return nil
        }
        return proto.author
    }
    @objc public var hasAuthor: Bool {
        return proto.hasAuthor
    }

    private init(proto: SignalServiceProtos_Pack,
                 cover: SSKProtoPackSticker?,
                 stickers: [SSKProtoPackSticker]) {
        self.proto = proto
        self.cover = cover
        self.stickers = stickers
    }

    @objc
    public func serializedData() throws -> Data {
        return try self.proto.serializedData()
    }

    @objc public class func parseData(_ serializedData: Data) throws -> SSKProtoPack {
        let proto = try SignalServiceProtos_Pack(serializedData: serializedData)
        return try parseProto(proto)
    }

    fileprivate class func parseProto(_ proto: SignalServiceProtos_Pack) throws -> SSKProtoPack {
        var cover: SSKProtoPackSticker? = nil
        if proto.hasCover {
            cover = try SSKProtoPackSticker.parseProto(proto.cover)
        }

        var stickers: [SSKProtoPackSticker] = []
        stickers = try proto.stickers.map { try SSKProtoPackSticker.parseProto($0) }

        // MARK: - Begin Validation Logic for SSKProtoPack -

        // MARK: - End Validation Logic for SSKProtoPack -

        let result = SSKProtoPack(proto: proto,
                                  cover: cover,
                                  stickers: stickers)
        return result
    }

    @objc public override var debugDescription: String {
        return "\(proto)"
    }
}

#if DEBUG

extension SSKProtoPack {
    @objc public func serializedDataIgnoringErrors() -> Data? {
        return try! self.serializedData()
    }
}

extension SSKProtoPack.SSKProtoPackBuilder {
    @objc public func buildIgnoringErrors() -> SSKProtoPack? {
        return try! self.build()
    }
}

#endif
