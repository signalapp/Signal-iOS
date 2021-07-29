//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

import Foundation

// WARNING: This code is generated. Only edit within the markers.

public enum SNProtoError: Error {
    case invalidProtobuf(description: String)
}

// MARK: - SNProtoEnvelope

@objc public class SNProtoEnvelope: NSObject {

    // MARK: - SNProtoEnvelopeType

    @objc public enum SNProtoEnvelopeType: Int32 {
        case sessionMessage = 6
        case closedGroupMessage = 7
    }

    private class func SNProtoEnvelopeTypeWrap(_ value: SessionProtos_Envelope.TypeEnum) -> SNProtoEnvelopeType {
        switch value {
        case .sessionMessage: return .sessionMessage
        case .closedGroupMessage: return .closedGroupMessage
        }
    }

    private class func SNProtoEnvelopeTypeUnwrap(_ value: SNProtoEnvelopeType) -> SessionProtos_Envelope.TypeEnum {
        switch value {
        case .sessionMessage: return .sessionMessage
        case .closedGroupMessage: return .closedGroupMessage
        }
    }

    // MARK: - SNProtoEnvelopeBuilder

    @objc public class func builder(type: SNProtoEnvelopeType, timestamp: UInt64) -> SNProtoEnvelopeBuilder {
        return SNProtoEnvelopeBuilder(type: type, timestamp: timestamp)
    }

    // asBuilder() constructs a builder that reflects the proto's contents.
    @objc public func asBuilder() -> SNProtoEnvelopeBuilder {
        let builder = SNProtoEnvelopeBuilder(type: type, timestamp: timestamp)
        if let _value = source {
            builder.setSource(_value)
        }
        if hasSourceDevice {
            builder.setSourceDevice(sourceDevice)
        }
        if let _value = content {
            builder.setContent(_value)
        }
        if hasServerTimestamp {
            builder.setServerTimestamp(serverTimestamp)
        }
        return builder
    }

    @objc public class SNProtoEnvelopeBuilder: NSObject {

        private var proto = SessionProtos_Envelope()

        @objc fileprivate override init() {}

        @objc fileprivate init(type: SNProtoEnvelopeType, timestamp: UInt64) {
            super.init()

            setType(type)
            setTimestamp(timestamp)
        }

        @objc public func setType(_ valueParam: SNProtoEnvelopeType) {
            proto.type = SNProtoEnvelopeTypeUnwrap(valueParam)
        }

        @objc public func setSource(_ valueParam: String) {
            proto.source = valueParam
        }

        @objc public func setSourceDevice(_ valueParam: UInt32) {
            proto.sourceDevice = valueParam
        }

        @objc public func setTimestamp(_ valueParam: UInt64) {
            proto.timestamp = valueParam
        }

        @objc public func setContent(_ valueParam: Data) {
            proto.content = valueParam
        }

        @objc public func setServerTimestamp(_ valueParam: UInt64) {
            proto.serverTimestamp = valueParam
        }

        @objc public func build() throws -> SNProtoEnvelope {
            return try SNProtoEnvelope.parseProto(proto)
        }

        @objc public func buildSerializedData() throws -> Data {
            return try SNProtoEnvelope.parseProto(proto).serializedData()
        }
    }

    fileprivate let proto: SessionProtos_Envelope

    @objc public let type: SNProtoEnvelopeType

    @objc public let timestamp: UInt64

    @objc public var source: String? {
        guard proto.hasSource else {
            return nil
        }
        return proto.source
    }
    @objc public var hasSource: Bool {
        return proto.hasSource
    }

    @objc public var sourceDevice: UInt32 {
        return proto.sourceDevice
    }
    @objc public var hasSourceDevice: Bool {
        return proto.hasSourceDevice
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

    @objc public var serverTimestamp: UInt64 {
        return proto.serverTimestamp
    }
    @objc public var hasServerTimestamp: Bool {
        return proto.hasServerTimestamp
    }

    private init(proto: SessionProtos_Envelope,
                 type: SNProtoEnvelopeType,
                 timestamp: UInt64) {
        self.proto = proto
        self.type = type
        self.timestamp = timestamp
    }

    @objc
    public func serializedData() throws -> Data {
        return try self.proto.serializedData()
    }

    @objc public class func parseData(_ serializedData: Data) throws -> SNProtoEnvelope {
        let proto = try SessionProtos_Envelope(serializedData: serializedData)
        return try parseProto(proto)
    }

    fileprivate class func parseProto(_ proto: SessionProtos_Envelope) throws -> SNProtoEnvelope {
        guard proto.hasType else {
            throw SNProtoError.invalidProtobuf(description: "\(logTag) missing required field: type")
        }
        let type = SNProtoEnvelopeTypeWrap(proto.type)

        guard proto.hasTimestamp else {
            throw SNProtoError.invalidProtobuf(description: "\(logTag) missing required field: timestamp")
        }
        let timestamp = proto.timestamp

        // MARK: - Begin Validation Logic for SNProtoEnvelope -

        // MARK: - End Validation Logic for SNProtoEnvelope -

        let result = SNProtoEnvelope(proto: proto,
                                     type: type,
                                     timestamp: timestamp)
        return result
    }

    @objc public override var debugDescription: String {
        return "\(proto)"
    }
}

#if DEBUG

extension SNProtoEnvelope {
    @objc public func serializedDataIgnoringErrors() -> Data? {
        return try! self.serializedData()
    }
}

extension SNProtoEnvelope.SNProtoEnvelopeBuilder {
    @objc public func buildIgnoringErrors() -> SNProtoEnvelope? {
        return try! self.build()
    }
}

#endif

// MARK: - SNProtoTypingMessage

@objc public class SNProtoTypingMessage: NSObject {

    // MARK: - SNProtoTypingMessageAction

    @objc public enum SNProtoTypingMessageAction: Int32 {
        case started = 0
        case stopped = 1
    }

    private class func SNProtoTypingMessageActionWrap(_ value: SessionProtos_TypingMessage.Action) -> SNProtoTypingMessageAction {
        switch value {
        case .started: return .started
        case .stopped: return .stopped
        }
    }

    private class func SNProtoTypingMessageActionUnwrap(_ value: SNProtoTypingMessageAction) -> SessionProtos_TypingMessage.Action {
        switch value {
        case .started: return .started
        case .stopped: return .stopped
        }
    }

    // MARK: - SNProtoTypingMessageBuilder

    @objc public class func builder(timestamp: UInt64, action: SNProtoTypingMessageAction) -> SNProtoTypingMessageBuilder {
        return SNProtoTypingMessageBuilder(timestamp: timestamp, action: action)
    }

    // asBuilder() constructs a builder that reflects the proto's contents.
    @objc public func asBuilder() -> SNProtoTypingMessageBuilder {
        let builder = SNProtoTypingMessageBuilder(timestamp: timestamp, action: action)
        return builder
    }

    @objc public class SNProtoTypingMessageBuilder: NSObject {

        private var proto = SessionProtos_TypingMessage()

        @objc fileprivate override init() {}

        @objc fileprivate init(timestamp: UInt64, action: SNProtoTypingMessageAction) {
            super.init()

            setTimestamp(timestamp)
            setAction(action)
        }

        @objc public func setTimestamp(_ valueParam: UInt64) {
            proto.timestamp = valueParam
        }

        @objc public func setAction(_ valueParam: SNProtoTypingMessageAction) {
            proto.action = SNProtoTypingMessageActionUnwrap(valueParam)
        }

        @objc public func build() throws -> SNProtoTypingMessage {
            return try SNProtoTypingMessage.parseProto(proto)
        }

        @objc public func buildSerializedData() throws -> Data {
            return try SNProtoTypingMessage.parseProto(proto).serializedData()
        }
    }

    fileprivate let proto: SessionProtos_TypingMessage

    @objc public let timestamp: UInt64

    @objc public let action: SNProtoTypingMessageAction

    private init(proto: SessionProtos_TypingMessage,
                 timestamp: UInt64,
                 action: SNProtoTypingMessageAction) {
        self.proto = proto
        self.timestamp = timestamp
        self.action = action
    }

    @objc
    public func serializedData() throws -> Data {
        return try self.proto.serializedData()
    }

    @objc public class func parseData(_ serializedData: Data) throws -> SNProtoTypingMessage {
        let proto = try SessionProtos_TypingMessage(serializedData: serializedData)
        return try parseProto(proto)
    }

    fileprivate class func parseProto(_ proto: SessionProtos_TypingMessage) throws -> SNProtoTypingMessage {
        guard proto.hasTimestamp else {
            throw SNProtoError.invalidProtobuf(description: "\(logTag) missing required field: timestamp")
        }
        let timestamp = proto.timestamp

        guard proto.hasAction else {
            throw SNProtoError.invalidProtobuf(description: "\(logTag) missing required field: action")
        }
        let action = SNProtoTypingMessageActionWrap(proto.action)

        // MARK: - Begin Validation Logic for SNProtoTypingMessage -

        // MARK: - End Validation Logic for SNProtoTypingMessage -

        let result = SNProtoTypingMessage(proto: proto,
                                          timestamp: timestamp,
                                          action: action)
        return result
    }

    @objc public override var debugDescription: String {
        return "\(proto)"
    }
}

#if DEBUG

extension SNProtoTypingMessage {
    @objc public func serializedDataIgnoringErrors() -> Data? {
        return try! self.serializedData()
    }
}

extension SNProtoTypingMessage.SNProtoTypingMessageBuilder {
    @objc public func buildIgnoringErrors() -> SNProtoTypingMessage? {
        return try! self.build()
    }
}

#endif

// MARK: - SNProtoContent

@objc public class SNProtoContent: NSObject {

    // MARK: - SNProtoContentBuilder

    @objc public class func builder() -> SNProtoContentBuilder {
        return SNProtoContentBuilder()
    }

    // asBuilder() constructs a builder that reflects the proto's contents.
    @objc public func asBuilder() -> SNProtoContentBuilder {
        let builder = SNProtoContentBuilder()
        if let _value = dataMessage {
            builder.setDataMessage(_value)
        }
        if let _value = receiptMessage {
            builder.setReceiptMessage(_value)
        }
        if let _value = typingMessage {
            builder.setTypingMessage(_value)
        }
        if let _value = configurationMessage {
            builder.setConfigurationMessage(_value)
        }
        if let _value = dataExtractionNotification {
            builder.setDataExtractionNotification(_value)
        }
        return builder
    }

    @objc public class SNProtoContentBuilder: NSObject {

        private var proto = SessionProtos_Content()

        @objc fileprivate override init() {}

        @objc public func setDataMessage(_ valueParam: SNProtoDataMessage) {
            proto.dataMessage = valueParam.proto
        }

        @objc public func setReceiptMessage(_ valueParam: SNProtoReceiptMessage) {
            proto.receiptMessage = valueParam.proto
        }

        @objc public func setTypingMessage(_ valueParam: SNProtoTypingMessage) {
            proto.typingMessage = valueParam.proto
        }

        @objc public func setConfigurationMessage(_ valueParam: SNProtoConfigurationMessage) {
            proto.configurationMessage = valueParam.proto
        }

        @objc public func setDataExtractionNotification(_ valueParam: SNProtoDataExtractionNotification) {
            proto.dataExtractionNotification = valueParam.proto
        }

        @objc public func build() throws -> SNProtoContent {
            return try SNProtoContent.parseProto(proto)
        }

        @objc public func buildSerializedData() throws -> Data {
            return try SNProtoContent.parseProto(proto).serializedData()
        }
    }

    fileprivate let proto: SessionProtos_Content

    @objc public let dataMessage: SNProtoDataMessage?

    @objc public let receiptMessage: SNProtoReceiptMessage?

    @objc public let typingMessage: SNProtoTypingMessage?

    @objc public let configurationMessage: SNProtoConfigurationMessage?

    @objc public let dataExtractionNotification: SNProtoDataExtractionNotification?

    private init(proto: SessionProtos_Content,
                 dataMessage: SNProtoDataMessage?,
                 receiptMessage: SNProtoReceiptMessage?,
                 typingMessage: SNProtoTypingMessage?,
                 configurationMessage: SNProtoConfigurationMessage?,
                 dataExtractionNotification: SNProtoDataExtractionNotification?) {
        self.proto = proto
        self.dataMessage = dataMessage
        self.receiptMessage = receiptMessage
        self.typingMessage = typingMessage
        self.configurationMessage = configurationMessage
        self.dataExtractionNotification = dataExtractionNotification
    }

    @objc
    public func serializedData() throws -> Data {
        return try self.proto.serializedData()
    }

    @objc public class func parseData(_ serializedData: Data) throws -> SNProtoContent {
        let proto = try SessionProtos_Content(serializedData: serializedData)
        return try parseProto(proto)
    }

    fileprivate class func parseProto(_ proto: SessionProtos_Content) throws -> SNProtoContent {
        var dataMessage: SNProtoDataMessage? = nil
        if proto.hasDataMessage {
            dataMessage = try SNProtoDataMessage.parseProto(proto.dataMessage)
        }

        var receiptMessage: SNProtoReceiptMessage? = nil
        if proto.hasReceiptMessage {
            receiptMessage = try SNProtoReceiptMessage.parseProto(proto.receiptMessage)
        }

        var typingMessage: SNProtoTypingMessage? = nil
        if proto.hasTypingMessage {
            typingMessage = try SNProtoTypingMessage.parseProto(proto.typingMessage)
        }

        var configurationMessage: SNProtoConfigurationMessage? = nil
        if proto.hasConfigurationMessage {
            configurationMessage = try SNProtoConfigurationMessage.parseProto(proto.configurationMessage)
        }

        var dataExtractionNotification: SNProtoDataExtractionNotification? = nil
        if proto.hasDataExtractionNotification {
            dataExtractionNotification = try SNProtoDataExtractionNotification.parseProto(proto.dataExtractionNotification)
        }

        // MARK: - Begin Validation Logic for SNProtoContent -

        // MARK: - End Validation Logic for SNProtoContent -

        let result = SNProtoContent(proto: proto,
                                    dataMessage: dataMessage,
                                    receiptMessage: receiptMessage,
                                    typingMessage: typingMessage,
                                    configurationMessage: configurationMessage,
                                    dataExtractionNotification: dataExtractionNotification)
        return result
    }

    @objc public override var debugDescription: String {
        return "\(proto)"
    }
}

#if DEBUG

extension SNProtoContent {
    @objc public func serializedDataIgnoringErrors() -> Data? {
        return try! self.serializedData()
    }
}

extension SNProtoContent.SNProtoContentBuilder {
    @objc public func buildIgnoringErrors() -> SNProtoContent? {
        return try! self.build()
    }
}

#endif

// MARK: - SNProtoCallMessageOffer

@objc public class SNProtoCallMessageOffer: NSObject {

    // MARK: - SNProtoCallMessageOfferType

    @objc public enum SNProtoCallMessageOfferType: Int32 {
        case offerAudioCall = 0
        case offerVideoCall = 1
    }

    private class func SNProtoCallMessageOfferTypeWrap(_ value: SessionProtos_CallMessage.Offer.TypeEnum) -> SNProtoCallMessageOfferType {
        switch value {
        case .offerAudioCall: return .offerAudioCall
        case .offerVideoCall: return .offerVideoCall
        }
    }

    private class func SNProtoCallMessageOfferTypeUnwrap(_ value: SNProtoCallMessageOfferType) -> SessionProtos_CallMessage.Offer.TypeEnum {
        switch value {
        case .offerAudioCall: return .offerAudioCall
        case .offerVideoCall: return .offerVideoCall
        }
    }

    // MARK: - SNProtoCallMessageOfferBuilder

    @objc public class func builder(id: UInt64) -> SNProtoCallMessageOfferBuilder {
        return SNProtoCallMessageOfferBuilder(id: id)
    }

    // asBuilder() constructs a builder that reflects the proto's contents.
    @objc public func asBuilder() -> SNProtoCallMessageOfferBuilder {
        let builder = SNProtoCallMessageOfferBuilder(id: id)
        if let _value = sdp {
            builder.setSdp(_value)
        }
        if hasType {
            builder.setType(type)
        }
        if let _value = opaque {
            builder.setOpaque(_value)
        }
        return builder
    }

    @objc public class SNProtoCallMessageOfferBuilder: NSObject {

        private var proto = SessionProtos_CallMessage.Offer()

        @objc fileprivate override init() {}

        @objc fileprivate init(id: UInt64) {
            super.init()

            setId(id)
        }

        @objc public func setId(_ valueParam: UInt64) {
            proto.id = valueParam
        }

        @objc public func setSdp(_ valueParam: String) {
            proto.sdp = valueParam
        }

        @objc public func setType(_ valueParam: SNProtoCallMessageOfferType) {
            proto.type = SNProtoCallMessageOfferTypeUnwrap(valueParam)
        }

        @objc public func setOpaque(_ valueParam: Data) {
            proto.opaque = valueParam
        }

        @objc public func build() throws -> SNProtoCallMessageOffer {
            return try SNProtoCallMessageOffer.parseProto(proto)
        }

        @objc public func buildSerializedData() throws -> Data {
            return try SNProtoCallMessageOffer.parseProto(proto).serializedData()
        }
    }

    fileprivate let proto: SessionProtos_CallMessage.Offer

    @objc public let id: UInt64

    @objc public var sdp: String? {
        guard proto.hasSdp else {
            return nil
        }
        return proto.sdp
    }
    @objc public var hasSdp: Bool {
        return proto.hasSdp
    }

    @objc public var type: SNProtoCallMessageOfferType {
        return SNProtoCallMessageOffer.SNProtoCallMessageOfferTypeWrap(proto.type)
    }
    @objc public var hasType: Bool {
        return proto.hasType
    }

    @objc public var opaque: Data? {
        guard proto.hasOpaque else {
            return nil
        }
        return proto.opaque
    }
    @objc public var hasOpaque: Bool {
        return proto.hasOpaque
    }

    private init(proto: SessionProtos_CallMessage.Offer,
                 id: UInt64) {
        self.proto = proto
        self.id = id
    }

    @objc
    public func serializedData() throws -> Data {
        return try self.proto.serializedData()
    }

    @objc public class func parseData(_ serializedData: Data) throws -> SNProtoCallMessageOffer {
        let proto = try SessionProtos_CallMessage.Offer(serializedData: serializedData)
        return try parseProto(proto)
    }

    fileprivate class func parseProto(_ proto: SessionProtos_CallMessage.Offer) throws -> SNProtoCallMessageOffer {
        guard proto.hasID else {
            throw SNProtoError.invalidProtobuf(description: "\(logTag) missing required field: id")
        }
        let id = proto.id

        // MARK: - Begin Validation Logic for SNProtoCallMessageOffer -

        // MARK: - End Validation Logic for SNProtoCallMessageOffer -

        let result = SNProtoCallMessageOffer(proto: proto,
                                             id: id)
        return result
    }

    @objc public override var debugDescription: String {
        return "\(proto)"
    }
}

#if DEBUG

extension SNProtoCallMessageOffer {
    @objc public func serializedDataIgnoringErrors() -> Data? {
        return try! self.serializedData()
    }
}

extension SNProtoCallMessageOffer.SNProtoCallMessageOfferBuilder {
    @objc public func buildIgnoringErrors() -> SNProtoCallMessageOffer? {
        return try! self.build()
    }
}

#endif

// MARK: - SNProtoCallMessageAnswer

@objc public class SNProtoCallMessageAnswer: NSObject {

    // MARK: - SNProtoCallMessageAnswerBuilder

    @objc public class func builder(id: UInt64) -> SNProtoCallMessageAnswerBuilder {
        return SNProtoCallMessageAnswerBuilder(id: id)
    }

    // asBuilder() constructs a builder that reflects the proto's contents.
    @objc public func asBuilder() -> SNProtoCallMessageAnswerBuilder {
        let builder = SNProtoCallMessageAnswerBuilder(id: id)
        if let _value = sdp {
            builder.setSdp(_value)
        }
        if let _value = opaque {
            builder.setOpaque(_value)
        }
        return builder
    }

    @objc public class SNProtoCallMessageAnswerBuilder: NSObject {

        private var proto = SessionProtos_CallMessage.Answer()

        @objc fileprivate override init() {}

        @objc fileprivate init(id: UInt64) {
            super.init()

            setId(id)
        }

        @objc public func setId(_ valueParam: UInt64) {
            proto.id = valueParam
        }

        @objc public func setSdp(_ valueParam: String) {
            proto.sdp = valueParam
        }

        @objc public func setOpaque(_ valueParam: Data) {
            proto.opaque = valueParam
        }

        @objc public func build() throws -> SNProtoCallMessageAnswer {
            return try SNProtoCallMessageAnswer.parseProto(proto)
        }

        @objc public func buildSerializedData() throws -> Data {
            return try SNProtoCallMessageAnswer.parseProto(proto).serializedData()
        }
    }

    fileprivate let proto: SessionProtos_CallMessage.Answer

    @objc public let id: UInt64

    @objc public var sdp: String? {
        guard proto.hasSdp else {
            return nil
        }
        return proto.sdp
    }
    @objc public var hasSdp: Bool {
        return proto.hasSdp
    }

    @objc public var opaque: Data? {
        guard proto.hasOpaque else {
            return nil
        }
        return proto.opaque
    }
    @objc public var hasOpaque: Bool {
        return proto.hasOpaque
    }

    private init(proto: SessionProtos_CallMessage.Answer,
                 id: UInt64) {
        self.proto = proto
        self.id = id
    }

    @objc
    public func serializedData() throws -> Data {
        return try self.proto.serializedData()
    }

    @objc public class func parseData(_ serializedData: Data) throws -> SNProtoCallMessageAnswer {
        let proto = try SessionProtos_CallMessage.Answer(serializedData: serializedData)
        return try parseProto(proto)
    }

    fileprivate class func parseProto(_ proto: SessionProtos_CallMessage.Answer) throws -> SNProtoCallMessageAnswer {
        guard proto.hasID else {
            throw SNProtoError.invalidProtobuf(description: "\(logTag) missing required field: id")
        }
        let id = proto.id

        // MARK: - Begin Validation Logic for SNProtoCallMessageAnswer -

        // MARK: - End Validation Logic for SNProtoCallMessageAnswer -

        let result = SNProtoCallMessageAnswer(proto: proto,
                                              id: id)
        return result
    }

    @objc public override var debugDescription: String {
        return "\(proto)"
    }
}

#if DEBUG

extension SNProtoCallMessageAnswer {
    @objc public func serializedDataIgnoringErrors() -> Data? {
        return try! self.serializedData()
    }
}

extension SNProtoCallMessageAnswer.SNProtoCallMessageAnswerBuilder {
    @objc public func buildIgnoringErrors() -> SNProtoCallMessageAnswer? {
        return try! self.build()
    }
}

#endif

// MARK: - SNProtoCallMessageIceUpdate

@objc public class SNProtoCallMessageIceUpdate: NSObject {

    // MARK: - SNProtoCallMessageIceUpdateBuilder

    @objc public class func builder(id: UInt64) -> SNProtoCallMessageIceUpdateBuilder {
        return SNProtoCallMessageIceUpdateBuilder(id: id)
    }

    // asBuilder() constructs a builder that reflects the proto's contents.
    @objc public func asBuilder() -> SNProtoCallMessageIceUpdateBuilder {
        let builder = SNProtoCallMessageIceUpdateBuilder(id: id)
        if let _value = mid {
            builder.setMid(_value)
        }
        if hasLine {
            builder.setLine(line)
        }
        if let _value = sdp {
            builder.setSdp(_value)
        }
        if let _value = opaque {
            builder.setOpaque(_value)
        }
        return builder
    }

    @objc public class SNProtoCallMessageIceUpdateBuilder: NSObject {

        private var proto = SessionProtos_CallMessage.IceUpdate()

        @objc fileprivate override init() {}

        @objc fileprivate init(id: UInt64) {
            super.init()

            setId(id)
        }

        @objc public func setId(_ valueParam: UInt64) {
            proto.id = valueParam
        }

        @objc public func setMid(_ valueParam: String) {
            proto.mid = valueParam
        }

        @objc public func setLine(_ valueParam: UInt32) {
            proto.line = valueParam
        }

        @objc public func setSdp(_ valueParam: String) {
            proto.sdp = valueParam
        }

        @objc public func setOpaque(_ valueParam: Data) {
            proto.opaque = valueParam
        }

        @objc public func build() throws -> SNProtoCallMessageIceUpdate {
            return try SNProtoCallMessageIceUpdate.parseProto(proto)
        }

        @objc public func buildSerializedData() throws -> Data {
            return try SNProtoCallMessageIceUpdate.parseProto(proto).serializedData()
        }
    }

    fileprivate let proto: SessionProtos_CallMessage.IceUpdate

    @objc public let id: UInt64

    @objc public var mid: String? {
        guard proto.hasMid else {
            return nil
        }
        return proto.mid
    }
    @objc public var hasMid: Bool {
        return proto.hasMid
    }

    @objc public var line: UInt32 {
        return proto.line
    }
    @objc public var hasLine: Bool {
        return proto.hasLine
    }

    @objc public var sdp: String? {
        guard proto.hasSdp else {
            return nil
        }
        return proto.sdp
    }
    @objc public var hasSdp: Bool {
        return proto.hasSdp
    }

    @objc public var opaque: Data? {
        guard proto.hasOpaque else {
            return nil
        }
        return proto.opaque
    }
    @objc public var hasOpaque: Bool {
        return proto.hasOpaque
    }

    private init(proto: SessionProtos_CallMessage.IceUpdate,
                 id: UInt64) {
        self.proto = proto
        self.id = id
    }

    @objc
    public func serializedData() throws -> Data {
        return try self.proto.serializedData()
    }

    @objc public class func parseData(_ serializedData: Data) throws -> SNProtoCallMessageIceUpdate {
        let proto = try SessionProtos_CallMessage.IceUpdate(serializedData: serializedData)
        return try parseProto(proto)
    }

    fileprivate class func parseProto(_ proto: SessionProtos_CallMessage.IceUpdate) throws -> SNProtoCallMessageIceUpdate {
        guard proto.hasID else {
            throw SNProtoError.invalidProtobuf(description: "\(logTag) missing required field: id")
        }
        let id = proto.id

        // MARK: - Begin Validation Logic for SNProtoCallMessageIceUpdate -

        // MARK: - End Validation Logic for SNProtoCallMessageIceUpdate -

        let result = SNProtoCallMessageIceUpdate(proto: proto,
                                                 id: id)
        return result
    }

    @objc public override var debugDescription: String {
        return "\(proto)"
    }
}

#if DEBUG

extension SNProtoCallMessageIceUpdate {
    @objc public func serializedDataIgnoringErrors() -> Data? {
        return try! self.serializedData()
    }
}

extension SNProtoCallMessageIceUpdate.SNProtoCallMessageIceUpdateBuilder {
    @objc public func buildIgnoringErrors() -> SNProtoCallMessageIceUpdate? {
        return try! self.build()
    }
}

#endif

// MARK: - SNProtoCallMessageBusy

@objc public class SNProtoCallMessageBusy: NSObject {

    // MARK: - SNProtoCallMessageBusyBuilder

    @objc public class func builder(id: UInt64) -> SNProtoCallMessageBusyBuilder {
        return SNProtoCallMessageBusyBuilder(id: id)
    }

    // asBuilder() constructs a builder that reflects the proto's contents.
    @objc public func asBuilder() -> SNProtoCallMessageBusyBuilder {
        let builder = SNProtoCallMessageBusyBuilder(id: id)
        return builder
    }

    @objc public class SNProtoCallMessageBusyBuilder: NSObject {

        private var proto = SessionProtos_CallMessage.Busy()

        @objc fileprivate override init() {}

        @objc fileprivate init(id: UInt64) {
            super.init()

            setId(id)
        }

        @objc public func setId(_ valueParam: UInt64) {
            proto.id = valueParam
        }

        @objc public func build() throws -> SNProtoCallMessageBusy {
            return try SNProtoCallMessageBusy.parseProto(proto)
        }

        @objc public func buildSerializedData() throws -> Data {
            return try SNProtoCallMessageBusy.parseProto(proto).serializedData()
        }
    }

    fileprivate let proto: SessionProtos_CallMessage.Busy

    @objc public let id: UInt64

    private init(proto: SessionProtos_CallMessage.Busy,
                 id: UInt64) {
        self.proto = proto
        self.id = id
    }

    @objc
    public func serializedData() throws -> Data {
        return try self.proto.serializedData()
    }

    @objc public class func parseData(_ serializedData: Data) throws -> SNProtoCallMessageBusy {
        let proto = try SessionProtos_CallMessage.Busy(serializedData: serializedData)
        return try parseProto(proto)
    }

    fileprivate class func parseProto(_ proto: SessionProtos_CallMessage.Busy) throws -> SNProtoCallMessageBusy {
        guard proto.hasID else {
            throw SNProtoError.invalidProtobuf(description: "\(logTag) missing required field: id")
        }
        let id = proto.id

        // MARK: - Begin Validation Logic for SNProtoCallMessageBusy -

        // MARK: - End Validation Logic for SNProtoCallMessageBusy -

        let result = SNProtoCallMessageBusy(proto: proto,
                                            id: id)
        return result
    }

    @objc public override var debugDescription: String {
        return "\(proto)"
    }
}

#if DEBUG

extension SNProtoCallMessageBusy {
    @objc public func serializedDataIgnoringErrors() -> Data? {
        return try! self.serializedData()
    }
}

extension SNProtoCallMessageBusy.SNProtoCallMessageBusyBuilder {
    @objc public func buildIgnoringErrors() -> SNProtoCallMessageBusy? {
        return try! self.build()
    }
}

#endif

// MARK: - SNProtoCallMessageHangup

@objc public class SNProtoCallMessageHangup: NSObject {

    // MARK: - SNProtoCallMessageHangupType

    @objc public enum SNProtoCallMessageHangupType: Int32 {
        case hangupNormal = 0
        case hangupAccepted = 1
        case hangupDeclined = 2
        case hangupBusy = 3
        case hangupNeedPermission = 4
    }

    private class func SNProtoCallMessageHangupTypeWrap(_ value: SessionProtos_CallMessage.Hangup.TypeEnum) -> SNProtoCallMessageHangupType {
        switch value {
        case .hangupNormal: return .hangupNormal
        case .hangupAccepted: return .hangupAccepted
        case .hangupDeclined: return .hangupDeclined
        case .hangupBusy: return .hangupBusy
        case .hangupNeedPermission: return .hangupNeedPermission
        }
    }

    private class func SNProtoCallMessageHangupTypeUnwrap(_ value: SNProtoCallMessageHangupType) -> SessionProtos_CallMessage.Hangup.TypeEnum {
        switch value {
        case .hangupNormal: return .hangupNormal
        case .hangupAccepted: return .hangupAccepted
        case .hangupDeclined: return .hangupDeclined
        case .hangupBusy: return .hangupBusy
        case .hangupNeedPermission: return .hangupNeedPermission
        }
    }

    // MARK: - SNProtoCallMessageHangupBuilder

    @objc public class func builder(id: UInt64) -> SNProtoCallMessageHangupBuilder {
        return SNProtoCallMessageHangupBuilder(id: id)
    }

    // asBuilder() constructs a builder that reflects the proto's contents.
    @objc public func asBuilder() -> SNProtoCallMessageHangupBuilder {
        let builder = SNProtoCallMessageHangupBuilder(id: id)
        if hasType {
            builder.setType(type)
        }
        if hasDeviceID {
            builder.setDeviceID(deviceID)
        }
        return builder
    }

    @objc public class SNProtoCallMessageHangupBuilder: NSObject {

        private var proto = SessionProtos_CallMessage.Hangup()

        @objc fileprivate override init() {}

        @objc fileprivate init(id: UInt64) {
            super.init()

            setId(id)
        }

        @objc public func setId(_ valueParam: UInt64) {
            proto.id = valueParam
        }

        @objc public func setType(_ valueParam: SNProtoCallMessageHangupType) {
            proto.type = SNProtoCallMessageHangupTypeUnwrap(valueParam)
        }

        @objc public func setDeviceID(_ valueParam: UInt32) {
            proto.deviceID = valueParam
        }

        @objc public func build() throws -> SNProtoCallMessageHangup {
            return try SNProtoCallMessageHangup.parseProto(proto)
        }

        @objc public func buildSerializedData() throws -> Data {
            return try SNProtoCallMessageHangup.parseProto(proto).serializedData()
        }
    }

    fileprivate let proto: SessionProtos_CallMessage.Hangup

    @objc public let id: UInt64

    @objc public var type: SNProtoCallMessageHangupType {
        return SNProtoCallMessageHangup.SNProtoCallMessageHangupTypeWrap(proto.type)
    }
    @objc public var hasType: Bool {
        return proto.hasType
    }

    @objc public var deviceID: UInt32 {
        return proto.deviceID
    }
    @objc public var hasDeviceID: Bool {
        return proto.hasDeviceID
    }

    private init(proto: SessionProtos_CallMessage.Hangup,
                 id: UInt64) {
        self.proto = proto
        self.id = id
    }

    @objc
    public func serializedData() throws -> Data {
        return try self.proto.serializedData()
    }

    @objc public class func parseData(_ serializedData: Data) throws -> SNProtoCallMessageHangup {
        let proto = try SessionProtos_CallMessage.Hangup(serializedData: serializedData)
        return try parseProto(proto)
    }

    fileprivate class func parseProto(_ proto: SessionProtos_CallMessage.Hangup) throws -> SNProtoCallMessageHangup {
        guard proto.hasID else {
            throw SNProtoError.invalidProtobuf(description: "\(logTag) missing required field: id")
        }
        let id = proto.id

        // MARK: - Begin Validation Logic for SNProtoCallMessageHangup -

        // MARK: - End Validation Logic for SNProtoCallMessageHangup -

        let result = SNProtoCallMessageHangup(proto: proto,
                                              id: id)
        return result
    }

    @objc public override var debugDescription: String {
        return "\(proto)"
    }
}

#if DEBUG

extension SNProtoCallMessageHangup {
    @objc public func serializedDataIgnoringErrors() -> Data? {
        return try! self.serializedData()
    }
}

extension SNProtoCallMessageHangup.SNProtoCallMessageHangupBuilder {
    @objc public func buildIgnoringErrors() -> SNProtoCallMessageHangup? {
        return try! self.build()
    }
}

#endif

// MARK: - SNProtoCallMessageOpaque

@objc public class SNProtoCallMessageOpaque: NSObject {

    // MARK: - SNProtoCallMessageOpaqueBuilder

    @objc public class func builder() -> SNProtoCallMessageOpaqueBuilder {
        return SNProtoCallMessageOpaqueBuilder()
    }

    // asBuilder() constructs a builder that reflects the proto's contents.
    @objc public func asBuilder() -> SNProtoCallMessageOpaqueBuilder {
        let builder = SNProtoCallMessageOpaqueBuilder()
        if let _value = data {
            builder.setData(_value)
        }
        return builder
    }

    @objc public class SNProtoCallMessageOpaqueBuilder: NSObject {

        private var proto = SessionProtos_CallMessage.Opaque()

        @objc fileprivate override init() {}

        @objc public func setData(_ valueParam: Data) {
            proto.data = valueParam
        }

        @objc public func build() throws -> SNProtoCallMessageOpaque {
            return try SNProtoCallMessageOpaque.parseProto(proto)
        }

        @objc public func buildSerializedData() throws -> Data {
            return try SNProtoCallMessageOpaque.parseProto(proto).serializedData()
        }
    }

    fileprivate let proto: SessionProtos_CallMessage.Opaque

    @objc public var data: Data? {
        guard proto.hasData else {
            return nil
        }
        return proto.data
    }
    @objc public var hasData: Bool {
        return proto.hasData
    }

    private init(proto: SessionProtos_CallMessage.Opaque) {
        self.proto = proto
    }

    @objc
    public func serializedData() throws -> Data {
        return try self.proto.serializedData()
    }

    @objc public class func parseData(_ serializedData: Data) throws -> SNProtoCallMessageOpaque {
        let proto = try SessionProtos_CallMessage.Opaque(serializedData: serializedData)
        return try parseProto(proto)
    }

    fileprivate class func parseProto(_ proto: SessionProtos_CallMessage.Opaque) throws -> SNProtoCallMessageOpaque {
        // MARK: - Begin Validation Logic for SNProtoCallMessageOpaque -

        // MARK: - End Validation Logic for SNProtoCallMessageOpaque -

        let result = SNProtoCallMessageOpaque(proto: proto)
        return result
    }

    @objc public override var debugDescription: String {
        return "\(proto)"
    }
}

#if DEBUG

extension SNProtoCallMessageOpaque {
    @objc public func serializedDataIgnoringErrors() -> Data? {
        return try! self.serializedData()
    }
}

extension SNProtoCallMessageOpaque.SNProtoCallMessageOpaqueBuilder {
    @objc public func buildIgnoringErrors() -> SNProtoCallMessageOpaque? {
        return try! self.build()
    }
}

#endif

// MARK: - SNProtoCallMessage

@objc public class SNProtoCallMessage: NSObject {

    // MARK: - SNProtoCallMessageBuilder

    @objc public class func builder() -> SNProtoCallMessageBuilder {
        return SNProtoCallMessageBuilder()
    }

    // asBuilder() constructs a builder that reflects the proto's contents.
    @objc public func asBuilder() -> SNProtoCallMessageBuilder {
        let builder = SNProtoCallMessageBuilder()
        if let _value = offer {
            builder.setOffer(_value)
        }
        if let _value = answer {
            builder.setAnswer(_value)
        }
        builder.setIceUpdate(iceUpdate)
        if let _value = legacyHangup {
            builder.setLegacyHangup(_value)
        }
        if let _value = busy {
            builder.setBusy(_value)
        }
        if let _value = profileKey {
            builder.setProfileKey(_value)
        }
        if let _value = hangup {
            builder.setHangup(_value)
        }
        if hasSupportsMultiRing {
            builder.setSupportsMultiRing(supportsMultiRing)
        }
        if hasDestinationDeviceID {
            builder.setDestinationDeviceID(destinationDeviceID)
        }
        if let _value = opaque {
            builder.setOpaque(_value)
        }
        return builder
    }

    @objc public class SNProtoCallMessageBuilder: NSObject {

        private var proto = SessionProtos_CallMessage()

        @objc fileprivate override init() {}

        @objc public func setOffer(_ valueParam: SNProtoCallMessageOffer) {
            proto.offer = valueParam.proto
        }

        @objc public func setAnswer(_ valueParam: SNProtoCallMessageAnswer) {
            proto.answer = valueParam.proto
        }

        @objc public func addIceUpdate(_ valueParam: SNProtoCallMessageIceUpdate) {
            var items = proto.iceUpdate
            items.append(valueParam.proto)
            proto.iceUpdate = items
        }

        @objc public func setIceUpdate(_ wrappedItems: [SNProtoCallMessageIceUpdate]) {
            proto.iceUpdate = wrappedItems.map { $0.proto }
        }

        @objc public func setLegacyHangup(_ valueParam: SNProtoCallMessageHangup) {
            proto.legacyHangup = valueParam.proto
        }

        @objc public func setBusy(_ valueParam: SNProtoCallMessageBusy) {
            proto.busy = valueParam.proto
        }

        @objc public func setProfileKey(_ valueParam: Data) {
            proto.profileKey = valueParam
        }

        @objc public func setHangup(_ valueParam: SNProtoCallMessageHangup) {
            proto.hangup = valueParam.proto
        }

        @objc public func setSupportsMultiRing(_ valueParam: Bool) {
            proto.supportsMultiRing = valueParam
        }

        @objc public func setDestinationDeviceID(_ valueParam: UInt32) {
            proto.destinationDeviceID = valueParam
        }

        @objc public func setOpaque(_ valueParam: SNProtoCallMessageOpaque) {
            proto.opaque = valueParam.proto
        }

        @objc public func build() throws -> SNProtoCallMessage {
            return try SNProtoCallMessage.parseProto(proto)
        }

        @objc public func buildSerializedData() throws -> Data {
            return try SNProtoCallMessage.parseProto(proto).serializedData()
        }
    }

    fileprivate let proto: SessionProtos_CallMessage

    @objc public let offer: SNProtoCallMessageOffer?

    @objc public let answer: SNProtoCallMessageAnswer?

    @objc public let iceUpdate: [SNProtoCallMessageIceUpdate]

    @objc public let legacyHangup: SNProtoCallMessageHangup?

    @objc public let busy: SNProtoCallMessageBusy?

    @objc public let hangup: SNProtoCallMessageHangup?

    @objc public let opaque: SNProtoCallMessageOpaque?

    @objc public var profileKey: Data? {
        guard proto.hasProfileKey else {
            return nil
        }
        return proto.profileKey
    }
    @objc public var hasProfileKey: Bool {
        return proto.hasProfileKey
    }

    @objc public var supportsMultiRing: Bool {
        return proto.supportsMultiRing
    }
    @objc public var hasSupportsMultiRing: Bool {
        return proto.hasSupportsMultiRing
    }

    @objc public var destinationDeviceID: UInt32 {
        return proto.destinationDeviceID
    }
    @objc public var hasDestinationDeviceID: Bool {
        return proto.hasDestinationDeviceID
    }

    private init(proto: SessionProtos_CallMessage,
                 offer: SNProtoCallMessageOffer?,
                 answer: SNProtoCallMessageAnswer?,
                 iceUpdate: [SNProtoCallMessageIceUpdate],
                 legacyHangup: SNProtoCallMessageHangup?,
                 busy: SNProtoCallMessageBusy?,
                 hangup: SNProtoCallMessageHangup?,
                 opaque: SNProtoCallMessageOpaque?) {
        self.proto = proto
        self.offer = offer
        self.answer = answer
        self.iceUpdate = iceUpdate
        self.legacyHangup = legacyHangup
        self.busy = busy
        self.hangup = hangup
        self.opaque = opaque
    }

    @objc
    public func serializedData() throws -> Data {
        return try self.proto.serializedData()
    }

    @objc public class func parseData(_ serializedData: Data) throws -> SNProtoCallMessage {
        let proto = try SessionProtos_CallMessage(serializedData: serializedData)
        return try parseProto(proto)
    }

    fileprivate class func parseProto(_ proto: SessionProtos_CallMessage) throws -> SNProtoCallMessage {
        var offer: SNProtoCallMessageOffer? = nil
        if proto.hasOffer {
            offer = try SNProtoCallMessageOffer.parseProto(proto.offer)
        }

        var answer: SNProtoCallMessageAnswer? = nil
        if proto.hasAnswer {
            answer = try SNProtoCallMessageAnswer.parseProto(proto.answer)
        }

        var iceUpdate: [SNProtoCallMessageIceUpdate] = []
        iceUpdate = try proto.iceUpdate.map { try SNProtoCallMessageIceUpdate.parseProto($0) }

        var legacyHangup: SNProtoCallMessageHangup? = nil
        if proto.hasLegacyHangup {
            legacyHangup = try SNProtoCallMessageHangup.parseProto(proto.legacyHangup)
        }

        var busy: SNProtoCallMessageBusy? = nil
        if proto.hasBusy {
            busy = try SNProtoCallMessageBusy.parseProto(proto.busy)
        }

        var hangup: SNProtoCallMessageHangup? = nil
        if proto.hasHangup {
            hangup = try SNProtoCallMessageHangup.parseProto(proto.hangup)
        }

        var opaque: SNProtoCallMessageOpaque? = nil
        if proto.hasOpaque {
            opaque = try SNProtoCallMessageOpaque.parseProto(proto.opaque)
        }

        // MARK: - Begin Validation Logic for SNProtoCallMessage -

        // MARK: - End Validation Logic for SNProtoCallMessage -

        let result = SNProtoCallMessage(proto: proto,
                                        offer: offer,
                                        answer: answer,
                                        iceUpdate: iceUpdate,
                                        legacyHangup: legacyHangup,
                                        busy: busy,
                                        hangup: hangup,
                                        opaque: opaque)
        return result
    }

    @objc public override var debugDescription: String {
        return "\(proto)"
    }
}

#if DEBUG

extension SNProtoCallMessage {
    @objc public func serializedDataIgnoringErrors() -> Data? {
        return try! self.serializedData()
    }
}

extension SNProtoCallMessage.SNProtoCallMessageBuilder {
    @objc public func buildIgnoringErrors() -> SNProtoCallMessage? {
        return try! self.build()
    }
}

#endif

// MARK: - SNProtoKeyPair

@objc public class SNProtoKeyPair: NSObject {

    // MARK: - SNProtoKeyPairBuilder

    @objc public class func builder(publicKey: Data, privateKey: Data) -> SNProtoKeyPairBuilder {
        return SNProtoKeyPairBuilder(publicKey: publicKey, privateKey: privateKey)
    }

    // asBuilder() constructs a builder that reflects the proto's contents.
    @objc public func asBuilder() -> SNProtoKeyPairBuilder {
        let builder = SNProtoKeyPairBuilder(publicKey: publicKey, privateKey: privateKey)
        return builder
    }

    @objc public class SNProtoKeyPairBuilder: NSObject {

        private var proto = SessionProtos_KeyPair()

        @objc fileprivate override init() {}

        @objc fileprivate init(publicKey: Data, privateKey: Data) {
            super.init()

            setPublicKey(publicKey)
            setPrivateKey(privateKey)
        }

        @objc public func setPublicKey(_ valueParam: Data) {
            proto.publicKey = valueParam
        }

        @objc public func setPrivateKey(_ valueParam: Data) {
            proto.privateKey = valueParam
        }

        @objc public func build() throws -> SNProtoKeyPair {
            return try SNProtoKeyPair.parseProto(proto)
        }

        @objc public func buildSerializedData() throws -> Data {
            return try SNProtoKeyPair.parseProto(proto).serializedData()
        }
    }

    fileprivate let proto: SessionProtos_KeyPair

    @objc public let publicKey: Data

    @objc public let privateKey: Data

    private init(proto: SessionProtos_KeyPair,
                 publicKey: Data,
                 privateKey: Data) {
        self.proto = proto
        self.publicKey = publicKey
        self.privateKey = privateKey
    }

    @objc
    public func serializedData() throws -> Data {
        return try self.proto.serializedData()
    }

    @objc public class func parseData(_ serializedData: Data) throws -> SNProtoKeyPair {
        let proto = try SessionProtos_KeyPair(serializedData: serializedData)
        return try parseProto(proto)
    }

    fileprivate class func parseProto(_ proto: SessionProtos_KeyPair) throws -> SNProtoKeyPair {
        guard proto.hasPublicKey else {
            throw SNProtoError.invalidProtobuf(description: "\(logTag) missing required field: publicKey")
        }
        let publicKey = proto.publicKey

        guard proto.hasPrivateKey else {
            throw SNProtoError.invalidProtobuf(description: "\(logTag) missing required field: privateKey")
        }
        let privateKey = proto.privateKey

        // MARK: - Begin Validation Logic for SNProtoKeyPair -

        // MARK: - End Validation Logic for SNProtoKeyPair -

        let result = SNProtoKeyPair(proto: proto,
                                    publicKey: publicKey,
                                    privateKey: privateKey)
        return result
    }

    @objc public override var debugDescription: String {
        return "\(proto)"
    }
}

#if DEBUG

extension SNProtoKeyPair {
    @objc public func serializedDataIgnoringErrors() -> Data? {
        return try! self.serializedData()
    }
}

extension SNProtoKeyPair.SNProtoKeyPairBuilder {
    @objc public func buildIgnoringErrors() -> SNProtoKeyPair? {
        return try! self.build()
    }
}

#endif

// MARK: - SNProtoDataExtractionNotification

@objc public class SNProtoDataExtractionNotification: NSObject {

    // MARK: - SNProtoDataExtractionNotificationType

    @objc public enum SNProtoDataExtractionNotificationType: Int32 {
        case screenshot = 1
        case mediaSaved = 2
    }

    private class func SNProtoDataExtractionNotificationTypeWrap(_ value: SessionProtos_DataExtractionNotification.TypeEnum) -> SNProtoDataExtractionNotificationType {
        switch value {
        case .screenshot: return .screenshot
        case .mediaSaved: return .mediaSaved
        }
    }

    private class func SNProtoDataExtractionNotificationTypeUnwrap(_ value: SNProtoDataExtractionNotificationType) -> SessionProtos_DataExtractionNotification.TypeEnum {
        switch value {
        case .screenshot: return .screenshot
        case .mediaSaved: return .mediaSaved
        }
    }

    // MARK: - SNProtoDataExtractionNotificationBuilder

    @objc public class func builder(type: SNProtoDataExtractionNotificationType) -> SNProtoDataExtractionNotificationBuilder {
        return SNProtoDataExtractionNotificationBuilder(type: type)
    }

    // asBuilder() constructs a builder that reflects the proto's contents.
    @objc public func asBuilder() -> SNProtoDataExtractionNotificationBuilder {
        let builder = SNProtoDataExtractionNotificationBuilder(type: type)
        if hasTimestamp {
            builder.setTimestamp(timestamp)
        }
        return builder
    }

    @objc public class SNProtoDataExtractionNotificationBuilder: NSObject {

        private var proto = SessionProtos_DataExtractionNotification()

        @objc fileprivate override init() {}

        @objc fileprivate init(type: SNProtoDataExtractionNotificationType) {
            super.init()

            setType(type)
        }

        @objc public func setType(_ valueParam: SNProtoDataExtractionNotificationType) {
            proto.type = SNProtoDataExtractionNotificationTypeUnwrap(valueParam)
        }

        @objc public func setTimestamp(_ valueParam: UInt64) {
            proto.timestamp = valueParam
        }

        @objc public func build() throws -> SNProtoDataExtractionNotification {
            return try SNProtoDataExtractionNotification.parseProto(proto)
        }

        @objc public func buildSerializedData() throws -> Data {
            return try SNProtoDataExtractionNotification.parseProto(proto).serializedData()
        }
    }

    fileprivate let proto: SessionProtos_DataExtractionNotification

    @objc public let type: SNProtoDataExtractionNotificationType

    @objc public var timestamp: UInt64 {
        return proto.timestamp
    }
    @objc public var hasTimestamp: Bool {
        return proto.hasTimestamp
    }

    private init(proto: SessionProtos_DataExtractionNotification,
                 type: SNProtoDataExtractionNotificationType) {
        self.proto = proto
        self.type = type
    }

    @objc
    public func serializedData() throws -> Data {
        return try self.proto.serializedData()
    }

    @objc public class func parseData(_ serializedData: Data) throws -> SNProtoDataExtractionNotification {
        let proto = try SessionProtos_DataExtractionNotification(serializedData: serializedData)
        return try parseProto(proto)
    }

    fileprivate class func parseProto(_ proto: SessionProtos_DataExtractionNotification) throws -> SNProtoDataExtractionNotification {
        guard proto.hasType else {
            throw SNProtoError.invalidProtobuf(description: "\(logTag) missing required field: type")
        }
        let type = SNProtoDataExtractionNotificationTypeWrap(proto.type)

        // MARK: - Begin Validation Logic for SNProtoDataExtractionNotification -

        // MARK: - End Validation Logic for SNProtoDataExtractionNotification -

        let result = SNProtoDataExtractionNotification(proto: proto,
                                                       type: type)
        return result
    }

    @objc public override var debugDescription: String {
        return "\(proto)"
    }
}

#if DEBUG

extension SNProtoDataExtractionNotification {
    @objc public func serializedDataIgnoringErrors() -> Data? {
        return try! self.serializedData()
    }
}

extension SNProtoDataExtractionNotification.SNProtoDataExtractionNotificationBuilder {
    @objc public func buildIgnoringErrors() -> SNProtoDataExtractionNotification? {
        return try! self.build()
    }
}

#endif

// MARK: - SNProtoDataMessageQuoteQuotedAttachment

@objc public class SNProtoDataMessageQuoteQuotedAttachment: NSObject {

    // MARK: - SNProtoDataMessageQuoteQuotedAttachmentFlags

    @objc public enum SNProtoDataMessageQuoteQuotedAttachmentFlags: Int32 {
        case voiceMessage = 1
    }

    private class func SNProtoDataMessageQuoteQuotedAttachmentFlagsWrap(_ value: SessionProtos_DataMessage.Quote.QuotedAttachment.Flags) -> SNProtoDataMessageQuoteQuotedAttachmentFlags {
        switch value {
        case .voiceMessage: return .voiceMessage
        }
    }

    private class func SNProtoDataMessageQuoteQuotedAttachmentFlagsUnwrap(_ value: SNProtoDataMessageQuoteQuotedAttachmentFlags) -> SessionProtos_DataMessage.Quote.QuotedAttachment.Flags {
        switch value {
        case .voiceMessage: return .voiceMessage
        }
    }

    // MARK: - SNProtoDataMessageQuoteQuotedAttachmentBuilder

    @objc public class func builder() -> SNProtoDataMessageQuoteQuotedAttachmentBuilder {
        return SNProtoDataMessageQuoteQuotedAttachmentBuilder()
    }

    // asBuilder() constructs a builder that reflects the proto's contents.
    @objc public func asBuilder() -> SNProtoDataMessageQuoteQuotedAttachmentBuilder {
        let builder = SNProtoDataMessageQuoteQuotedAttachmentBuilder()
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

    @objc public class SNProtoDataMessageQuoteQuotedAttachmentBuilder: NSObject {

        private var proto = SessionProtos_DataMessage.Quote.QuotedAttachment()

        @objc fileprivate override init() {}

        @objc public func setContentType(_ valueParam: String) {
            proto.contentType = valueParam
        }

        @objc public func setFileName(_ valueParam: String) {
            proto.fileName = valueParam
        }

        @objc public func setThumbnail(_ valueParam: SNProtoAttachmentPointer) {
            proto.thumbnail = valueParam.proto
        }

        @objc public func setFlags(_ valueParam: UInt32) {
            proto.flags = valueParam
        }

        @objc public func build() throws -> SNProtoDataMessageQuoteQuotedAttachment {
            return try SNProtoDataMessageQuoteQuotedAttachment.parseProto(proto)
        }

        @objc public func buildSerializedData() throws -> Data {
            return try SNProtoDataMessageQuoteQuotedAttachment.parseProto(proto).serializedData()
        }
    }

    fileprivate let proto: SessionProtos_DataMessage.Quote.QuotedAttachment

    @objc public let thumbnail: SNProtoAttachmentPointer?

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

    private init(proto: SessionProtos_DataMessage.Quote.QuotedAttachment,
                 thumbnail: SNProtoAttachmentPointer?) {
        self.proto = proto
        self.thumbnail = thumbnail
    }

    @objc
    public func serializedData() throws -> Data {
        return try self.proto.serializedData()
    }

    @objc public class func parseData(_ serializedData: Data) throws -> SNProtoDataMessageQuoteQuotedAttachment {
        let proto = try SessionProtos_DataMessage.Quote.QuotedAttachment(serializedData: serializedData)
        return try parseProto(proto)
    }

    fileprivate class func parseProto(_ proto: SessionProtos_DataMessage.Quote.QuotedAttachment) throws -> SNProtoDataMessageQuoteQuotedAttachment {
        var thumbnail: SNProtoAttachmentPointer? = nil
        if proto.hasThumbnail {
            thumbnail = try SNProtoAttachmentPointer.parseProto(proto.thumbnail)
        }

        // MARK: - Begin Validation Logic for SNProtoDataMessageQuoteQuotedAttachment -

        // MARK: - End Validation Logic for SNProtoDataMessageQuoteQuotedAttachment -

        let result = SNProtoDataMessageQuoteQuotedAttachment(proto: proto,
                                                             thumbnail: thumbnail)
        return result
    }

    @objc public override var debugDescription: String {
        return "\(proto)"
    }
}

#if DEBUG

extension SNProtoDataMessageQuoteQuotedAttachment {
    @objc public func serializedDataIgnoringErrors() -> Data? {
        return try! self.serializedData()
    }
}

extension SNProtoDataMessageQuoteQuotedAttachment.SNProtoDataMessageQuoteQuotedAttachmentBuilder {
    @objc public func buildIgnoringErrors() -> SNProtoDataMessageQuoteQuotedAttachment? {
        return try! self.build()
    }
}

#endif

// MARK: - SNProtoDataMessageQuote

@objc public class SNProtoDataMessageQuote: NSObject {

    // MARK: - SNProtoDataMessageQuoteBuilder

    @objc public class func builder(id: UInt64, author: String) -> SNProtoDataMessageQuoteBuilder {
        return SNProtoDataMessageQuoteBuilder(id: id, author: author)
    }

    // asBuilder() constructs a builder that reflects the proto's contents.
    @objc public func asBuilder() -> SNProtoDataMessageQuoteBuilder {
        let builder = SNProtoDataMessageQuoteBuilder(id: id, author: author)
        if let _value = text {
            builder.setText(_value)
        }
        builder.setAttachments(attachments)
        return builder
    }

    @objc public class SNProtoDataMessageQuoteBuilder: NSObject {

        private var proto = SessionProtos_DataMessage.Quote()

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

        @objc public func addAttachments(_ valueParam: SNProtoDataMessageQuoteQuotedAttachment) {
            var items = proto.attachments
            items.append(valueParam.proto)
            proto.attachments = items
        }

        @objc public func setAttachments(_ wrappedItems: [SNProtoDataMessageQuoteQuotedAttachment]) {
            proto.attachments = wrappedItems.map { $0.proto }
        }

        @objc public func build() throws -> SNProtoDataMessageQuote {
            return try SNProtoDataMessageQuote.parseProto(proto)
        }

        @objc public func buildSerializedData() throws -> Data {
            return try SNProtoDataMessageQuote.parseProto(proto).serializedData()
        }
    }

    fileprivate let proto: SessionProtos_DataMessage.Quote

    @objc public let id: UInt64

    @objc public let author: String

    @objc public let attachments: [SNProtoDataMessageQuoteQuotedAttachment]

    @objc public var text: String? {
        guard proto.hasText else {
            return nil
        }
        return proto.text
    }
    @objc public var hasText: Bool {
        return proto.hasText
    }

    private init(proto: SessionProtos_DataMessage.Quote,
                 id: UInt64,
                 author: String,
                 attachments: [SNProtoDataMessageQuoteQuotedAttachment]) {
        self.proto = proto
        self.id = id
        self.author = author
        self.attachments = attachments
    }

    @objc
    public func serializedData() throws -> Data {
        return try self.proto.serializedData()
    }

    @objc public class func parseData(_ serializedData: Data) throws -> SNProtoDataMessageQuote {
        let proto = try SessionProtos_DataMessage.Quote(serializedData: serializedData)
        return try parseProto(proto)
    }

    fileprivate class func parseProto(_ proto: SessionProtos_DataMessage.Quote) throws -> SNProtoDataMessageQuote {
        guard proto.hasID else {
            throw SNProtoError.invalidProtobuf(description: "\(logTag) missing required field: id")
        }
        let id = proto.id

        guard proto.hasAuthor else {
            throw SNProtoError.invalidProtobuf(description: "\(logTag) missing required field: author")
        }
        let author = proto.author

        var attachments: [SNProtoDataMessageQuoteQuotedAttachment] = []
        attachments = try proto.attachments.map { try SNProtoDataMessageQuoteQuotedAttachment.parseProto($0) }

        // MARK: - Begin Validation Logic for SNProtoDataMessageQuote -

        // MARK: - End Validation Logic for SNProtoDataMessageQuote -

        let result = SNProtoDataMessageQuote(proto: proto,
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

extension SNProtoDataMessageQuote {
    @objc public func serializedDataIgnoringErrors() -> Data? {
        return try! self.serializedData()
    }
}

extension SNProtoDataMessageQuote.SNProtoDataMessageQuoteBuilder {
    @objc public func buildIgnoringErrors() -> SNProtoDataMessageQuote? {
        return try! self.build()
    }
}

#endif

// MARK: - SNProtoDataMessagePreview

@objc public class SNProtoDataMessagePreview: NSObject {

    // MARK: - SNProtoDataMessagePreviewBuilder

    @objc public class func builder(url: String) -> SNProtoDataMessagePreviewBuilder {
        return SNProtoDataMessagePreviewBuilder(url: url)
    }

    // asBuilder() constructs a builder that reflects the proto's contents.
    @objc public func asBuilder() -> SNProtoDataMessagePreviewBuilder {
        let builder = SNProtoDataMessagePreviewBuilder(url: url)
        if let _value = title {
            builder.setTitle(_value)
        }
        if let _value = image {
            builder.setImage(_value)
        }
        return builder
    }

    @objc public class SNProtoDataMessagePreviewBuilder: NSObject {

        private var proto = SessionProtos_DataMessage.Preview()

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

        @objc public func setImage(_ valueParam: SNProtoAttachmentPointer) {
            proto.image = valueParam.proto
        }

        @objc public func build() throws -> SNProtoDataMessagePreview {
            return try SNProtoDataMessagePreview.parseProto(proto)
        }

        @objc public func buildSerializedData() throws -> Data {
            return try SNProtoDataMessagePreview.parseProto(proto).serializedData()
        }
    }

    fileprivate let proto: SessionProtos_DataMessage.Preview

    @objc public let url: String

    @objc public let image: SNProtoAttachmentPointer?

    @objc public var title: String? {
        guard proto.hasTitle else {
            return nil
        }
        return proto.title
    }
    @objc public var hasTitle: Bool {
        return proto.hasTitle
    }

    private init(proto: SessionProtos_DataMessage.Preview,
                 url: String,
                 image: SNProtoAttachmentPointer?) {
        self.proto = proto
        self.url = url
        self.image = image
    }

    @objc
    public func serializedData() throws -> Data {
        return try self.proto.serializedData()
    }

    @objc public class func parseData(_ serializedData: Data) throws -> SNProtoDataMessagePreview {
        let proto = try SessionProtos_DataMessage.Preview(serializedData: serializedData)
        return try parseProto(proto)
    }

    fileprivate class func parseProto(_ proto: SessionProtos_DataMessage.Preview) throws -> SNProtoDataMessagePreview {
        guard proto.hasURL else {
            throw SNProtoError.invalidProtobuf(description: "\(logTag) missing required field: url")
        }
        let url = proto.url

        var image: SNProtoAttachmentPointer? = nil
        if proto.hasImage {
            image = try SNProtoAttachmentPointer.parseProto(proto.image)
        }

        // MARK: - Begin Validation Logic for SNProtoDataMessagePreview -

        // MARK: - End Validation Logic for SNProtoDataMessagePreview -

        let result = SNProtoDataMessagePreview(proto: proto,
                                               url: url,
                                               image: image)
        return result
    }

    @objc public override var debugDescription: String {
        return "\(proto)"
    }
}

#if DEBUG

extension SNProtoDataMessagePreview {
    @objc public func serializedDataIgnoringErrors() -> Data? {
        return try! self.serializedData()
    }
}

extension SNProtoDataMessagePreview.SNProtoDataMessagePreviewBuilder {
    @objc public func buildIgnoringErrors() -> SNProtoDataMessagePreview? {
        return try! self.build()
    }
}

#endif

// MARK: - SNProtoDataMessageLokiProfile

@objc public class SNProtoDataMessageLokiProfile: NSObject {

    // MARK: - SNProtoDataMessageLokiProfileBuilder

    @objc public class func builder() -> SNProtoDataMessageLokiProfileBuilder {
        return SNProtoDataMessageLokiProfileBuilder()
    }

    // asBuilder() constructs a builder that reflects the proto's contents.
    @objc public func asBuilder() -> SNProtoDataMessageLokiProfileBuilder {
        let builder = SNProtoDataMessageLokiProfileBuilder()
        if let _value = displayName {
            builder.setDisplayName(_value)
        }
        if let _value = profilePicture {
            builder.setProfilePicture(_value)
        }
        return builder
    }

    @objc public class SNProtoDataMessageLokiProfileBuilder: NSObject {

        private var proto = SessionProtos_DataMessage.LokiProfile()

        @objc fileprivate override init() {}

        @objc public func setDisplayName(_ valueParam: String) {
            proto.displayName = valueParam
        }

        @objc public func setProfilePicture(_ valueParam: String) {
            proto.profilePicture = valueParam
        }

        @objc public func build() throws -> SNProtoDataMessageLokiProfile {
            return try SNProtoDataMessageLokiProfile.parseProto(proto)
        }

        @objc public func buildSerializedData() throws -> Data {
            return try SNProtoDataMessageLokiProfile.parseProto(proto).serializedData()
        }
    }

    fileprivate let proto: SessionProtos_DataMessage.LokiProfile

    @objc public var displayName: String? {
        guard proto.hasDisplayName else {
            return nil
        }
        return proto.displayName
    }
    @objc public var hasDisplayName: Bool {
        return proto.hasDisplayName
    }

    @objc public var profilePicture: String? {
        guard proto.hasProfilePicture else {
            return nil
        }
        return proto.profilePicture
    }
    @objc public var hasProfilePicture: Bool {
        return proto.hasProfilePicture
    }

    private init(proto: SessionProtos_DataMessage.LokiProfile) {
        self.proto = proto
    }

    @objc
    public func serializedData() throws -> Data {
        return try self.proto.serializedData()
    }

    @objc public class func parseData(_ serializedData: Data) throws -> SNProtoDataMessageLokiProfile {
        let proto = try SessionProtos_DataMessage.LokiProfile(serializedData: serializedData)
        return try parseProto(proto)
    }

    fileprivate class func parseProto(_ proto: SessionProtos_DataMessage.LokiProfile) throws -> SNProtoDataMessageLokiProfile {
        // MARK: - Begin Validation Logic for SNProtoDataMessageLokiProfile -

        // MARK: - End Validation Logic for SNProtoDataMessageLokiProfile -

        let result = SNProtoDataMessageLokiProfile(proto: proto)
        return result
    }

    @objc public override var debugDescription: String {
        return "\(proto)"
    }
}

#if DEBUG

extension SNProtoDataMessageLokiProfile {
    @objc public func serializedDataIgnoringErrors() -> Data? {
        return try! self.serializedData()
    }
}

extension SNProtoDataMessageLokiProfile.SNProtoDataMessageLokiProfileBuilder {
    @objc public func buildIgnoringErrors() -> SNProtoDataMessageLokiProfile? {
        return try! self.build()
    }
}

#endif

// MARK: - SNProtoDataMessageOpenGroupInvitation

@objc public class SNProtoDataMessageOpenGroupInvitation: NSObject {

    // MARK: - SNProtoDataMessageOpenGroupInvitationBuilder

    @objc public class func builder(url: String, name: String) -> SNProtoDataMessageOpenGroupInvitationBuilder {
        return SNProtoDataMessageOpenGroupInvitationBuilder(url: url, name: name)
    }

    // asBuilder() constructs a builder that reflects the proto's contents.
    @objc public func asBuilder() -> SNProtoDataMessageOpenGroupInvitationBuilder {
        let builder = SNProtoDataMessageOpenGroupInvitationBuilder(url: url, name: name)
        return builder
    }

    @objc public class SNProtoDataMessageOpenGroupInvitationBuilder: NSObject {

        private var proto = SessionProtos_DataMessage.OpenGroupInvitation()

        @objc fileprivate override init() {}

        @objc fileprivate init(url: String, name: String) {
            super.init()

            setUrl(url)
            setName(name)
        }

        @objc public func setUrl(_ valueParam: String) {
            proto.url = valueParam
        }

        @objc public func setName(_ valueParam: String) {
            proto.name = valueParam
        }

        @objc public func build() throws -> SNProtoDataMessageOpenGroupInvitation {
            return try SNProtoDataMessageOpenGroupInvitation.parseProto(proto)
        }

        @objc public func buildSerializedData() throws -> Data {
            return try SNProtoDataMessageOpenGroupInvitation.parseProto(proto).serializedData()
        }
    }

    fileprivate let proto: SessionProtos_DataMessage.OpenGroupInvitation

    @objc public let url: String

    @objc public let name: String

    private init(proto: SessionProtos_DataMessage.OpenGroupInvitation,
                 url: String,
                 name: String) {
        self.proto = proto
        self.url = url
        self.name = name
    }

    @objc
    public func serializedData() throws -> Data {
        return try self.proto.serializedData()
    }

    @objc public class func parseData(_ serializedData: Data) throws -> SNProtoDataMessageOpenGroupInvitation {
        let proto = try SessionProtos_DataMessage.OpenGroupInvitation(serializedData: serializedData)
        return try parseProto(proto)
    }

    fileprivate class func parseProto(_ proto: SessionProtos_DataMessage.OpenGroupInvitation) throws -> SNProtoDataMessageOpenGroupInvitation {
        guard proto.hasURL else {
            throw SNProtoError.invalidProtobuf(description: "\(logTag) missing required field: url")
        }
        let url = proto.url

        guard proto.hasName else {
            throw SNProtoError.invalidProtobuf(description: "\(logTag) missing required field: name")
        }
        let name = proto.name

        // MARK: - Begin Validation Logic for SNProtoDataMessageOpenGroupInvitation -

        // MARK: - End Validation Logic for SNProtoDataMessageOpenGroupInvitation -

        let result = SNProtoDataMessageOpenGroupInvitation(proto: proto,
                                                           url: url,
                                                           name: name)
        return result
    }

    @objc public override var debugDescription: String {
        return "\(proto)"
    }
}

#if DEBUG

extension SNProtoDataMessageOpenGroupInvitation {
    @objc public func serializedDataIgnoringErrors() -> Data? {
        return try! self.serializedData()
    }
}

extension SNProtoDataMessageOpenGroupInvitation.SNProtoDataMessageOpenGroupInvitationBuilder {
    @objc public func buildIgnoringErrors() -> SNProtoDataMessageOpenGroupInvitation? {
        return try! self.build()
    }
}

#endif

// MARK: - SNProtoDataMessageClosedGroupControlMessageKeyPairWrapper

@objc public class SNProtoDataMessageClosedGroupControlMessageKeyPairWrapper: NSObject {

    // MARK: - SNProtoDataMessageClosedGroupControlMessageKeyPairWrapperBuilder

    @objc public class func builder(publicKey: Data, encryptedKeyPair: Data) -> SNProtoDataMessageClosedGroupControlMessageKeyPairWrapperBuilder {
        return SNProtoDataMessageClosedGroupControlMessageKeyPairWrapperBuilder(publicKey: publicKey, encryptedKeyPair: encryptedKeyPair)
    }

    // asBuilder() constructs a builder that reflects the proto's contents.
    @objc public func asBuilder() -> SNProtoDataMessageClosedGroupControlMessageKeyPairWrapperBuilder {
        let builder = SNProtoDataMessageClosedGroupControlMessageKeyPairWrapperBuilder(publicKey: publicKey, encryptedKeyPair: encryptedKeyPair)
        return builder
    }

    @objc public class SNProtoDataMessageClosedGroupControlMessageKeyPairWrapperBuilder: NSObject {

        private var proto = SessionProtos_DataMessage.ClosedGroupControlMessage.KeyPairWrapper()

        @objc fileprivate override init() {}

        @objc fileprivate init(publicKey: Data, encryptedKeyPair: Data) {
            super.init()

            setPublicKey(publicKey)
            setEncryptedKeyPair(encryptedKeyPair)
        }

        @objc public func setPublicKey(_ valueParam: Data) {
            proto.publicKey = valueParam
        }

        @objc public func setEncryptedKeyPair(_ valueParam: Data) {
            proto.encryptedKeyPair = valueParam
        }

        @objc public func build() throws -> SNProtoDataMessageClosedGroupControlMessageKeyPairWrapper {
            return try SNProtoDataMessageClosedGroupControlMessageKeyPairWrapper.parseProto(proto)
        }

        @objc public func buildSerializedData() throws -> Data {
            return try SNProtoDataMessageClosedGroupControlMessageKeyPairWrapper.parseProto(proto).serializedData()
        }
    }

    fileprivate let proto: SessionProtos_DataMessage.ClosedGroupControlMessage.KeyPairWrapper

    @objc public let publicKey: Data

    @objc public let encryptedKeyPair: Data

    private init(proto: SessionProtos_DataMessage.ClosedGroupControlMessage.KeyPairWrapper,
                 publicKey: Data,
                 encryptedKeyPair: Data) {
        self.proto = proto
        self.publicKey = publicKey
        self.encryptedKeyPair = encryptedKeyPair
    }

    @objc
    public func serializedData() throws -> Data {
        return try self.proto.serializedData()
    }

    @objc public class func parseData(_ serializedData: Data) throws -> SNProtoDataMessageClosedGroupControlMessageKeyPairWrapper {
        let proto = try SessionProtos_DataMessage.ClosedGroupControlMessage.KeyPairWrapper(serializedData: serializedData)
        return try parseProto(proto)
    }

    fileprivate class func parseProto(_ proto: SessionProtos_DataMessage.ClosedGroupControlMessage.KeyPairWrapper) throws -> SNProtoDataMessageClosedGroupControlMessageKeyPairWrapper {
        guard proto.hasPublicKey else {
            throw SNProtoError.invalidProtobuf(description: "\(logTag) missing required field: publicKey")
        }
        let publicKey = proto.publicKey

        guard proto.hasEncryptedKeyPair else {
            throw SNProtoError.invalidProtobuf(description: "\(logTag) missing required field: encryptedKeyPair")
        }
        let encryptedKeyPair = proto.encryptedKeyPair

        // MARK: - Begin Validation Logic for SNProtoDataMessageClosedGroupControlMessageKeyPairWrapper -

        // MARK: - End Validation Logic for SNProtoDataMessageClosedGroupControlMessageKeyPairWrapper -

        let result = SNProtoDataMessageClosedGroupControlMessageKeyPairWrapper(proto: proto,
                                                                               publicKey: publicKey,
                                                                               encryptedKeyPair: encryptedKeyPair)
        return result
    }

    @objc public override var debugDescription: String {
        return "\(proto)"
    }
}

#if DEBUG

extension SNProtoDataMessageClosedGroupControlMessageKeyPairWrapper {
    @objc public func serializedDataIgnoringErrors() -> Data? {
        return try! self.serializedData()
    }
}

extension SNProtoDataMessageClosedGroupControlMessageKeyPairWrapper.SNProtoDataMessageClosedGroupControlMessageKeyPairWrapperBuilder {
    @objc public func buildIgnoringErrors() -> SNProtoDataMessageClosedGroupControlMessageKeyPairWrapper? {
        return try! self.build()
    }
}

#endif

// MARK: - SNProtoDataMessageClosedGroupControlMessage

@objc public class SNProtoDataMessageClosedGroupControlMessage: NSObject {

    // MARK: - SNProtoDataMessageClosedGroupControlMessageType

    @objc public enum SNProtoDataMessageClosedGroupControlMessageType: Int32 {
        case new = 1
        case encryptionKeyPair = 3
        case nameChange = 4
        case membersAdded = 5
        case membersRemoved = 6
        case memberLeft = 7
        case encryptionKeyPairRequest = 8
    }

    private class func SNProtoDataMessageClosedGroupControlMessageTypeWrap(_ value: SessionProtos_DataMessage.ClosedGroupControlMessage.TypeEnum) -> SNProtoDataMessageClosedGroupControlMessageType {
        switch value {
        case .new: return .new
        case .encryptionKeyPair: return .encryptionKeyPair
        case .nameChange: return .nameChange
        case .membersAdded: return .membersAdded
        case .membersRemoved: return .membersRemoved
        case .memberLeft: return .memberLeft
        case .encryptionKeyPairRequest: return .encryptionKeyPairRequest
        }
    }

    private class func SNProtoDataMessageClosedGroupControlMessageTypeUnwrap(_ value: SNProtoDataMessageClosedGroupControlMessageType) -> SessionProtos_DataMessage.ClosedGroupControlMessage.TypeEnum {
        switch value {
        case .new: return .new
        case .encryptionKeyPair: return .encryptionKeyPair
        case .nameChange: return .nameChange
        case .membersAdded: return .membersAdded
        case .membersRemoved: return .membersRemoved
        case .memberLeft: return .memberLeft
        case .encryptionKeyPairRequest: return .encryptionKeyPairRequest
        }
    }

    // MARK: - SNProtoDataMessageClosedGroupControlMessageBuilder

    @objc public class func builder(type: SNProtoDataMessageClosedGroupControlMessageType) -> SNProtoDataMessageClosedGroupControlMessageBuilder {
        return SNProtoDataMessageClosedGroupControlMessageBuilder(type: type)
    }

    // asBuilder() constructs a builder that reflects the proto's contents.
    @objc public func asBuilder() -> SNProtoDataMessageClosedGroupControlMessageBuilder {
        let builder = SNProtoDataMessageClosedGroupControlMessageBuilder(type: type)
        if let _value = publicKey {
            builder.setPublicKey(_value)
        }
        if let _value = name {
            builder.setName(_value)
        }
        if let _value = encryptionKeyPair {
            builder.setEncryptionKeyPair(_value)
        }
        builder.setMembers(members)
        builder.setAdmins(admins)
        builder.setWrappers(wrappers)
        if hasExpirationTimer {
            builder.setExpirationTimer(expirationTimer)
        }
        return builder
    }

    @objc public class SNProtoDataMessageClosedGroupControlMessageBuilder: NSObject {

        private var proto = SessionProtos_DataMessage.ClosedGroupControlMessage()

        @objc fileprivate override init() {}

        @objc fileprivate init(type: SNProtoDataMessageClosedGroupControlMessageType) {
            super.init()

            setType(type)
        }

        @objc public func setType(_ valueParam: SNProtoDataMessageClosedGroupControlMessageType) {
            proto.type = SNProtoDataMessageClosedGroupControlMessageTypeUnwrap(valueParam)
        }

        @objc public func setPublicKey(_ valueParam: Data) {
            proto.publicKey = valueParam
        }

        @objc public func setName(_ valueParam: String) {
            proto.name = valueParam
        }

        @objc public func setEncryptionKeyPair(_ valueParam: SNProtoKeyPair) {
            proto.encryptionKeyPair = valueParam.proto
        }

        @objc public func addMembers(_ valueParam: Data) {
            var items = proto.members
            items.append(valueParam)
            proto.members = items
        }

        @objc public func setMembers(_ wrappedItems: [Data]) {
            proto.members = wrappedItems
        }

        @objc public func addAdmins(_ valueParam: Data) {
            var items = proto.admins
            items.append(valueParam)
            proto.admins = items
        }

        @objc public func setAdmins(_ wrappedItems: [Data]) {
            proto.admins = wrappedItems
        }

        @objc public func addWrappers(_ valueParam: SNProtoDataMessageClosedGroupControlMessageKeyPairWrapper) {
            var items = proto.wrappers
            items.append(valueParam.proto)
            proto.wrappers = items
        }

        @objc public func setWrappers(_ wrappedItems: [SNProtoDataMessageClosedGroupControlMessageKeyPairWrapper]) {
            proto.wrappers = wrappedItems.map { $0.proto }
        }

        @objc public func setExpirationTimer(_ valueParam: UInt32) {
            proto.expirationTimer = valueParam
        }

        @objc public func build() throws -> SNProtoDataMessageClosedGroupControlMessage {
            return try SNProtoDataMessageClosedGroupControlMessage.parseProto(proto)
        }

        @objc public func buildSerializedData() throws -> Data {
            return try SNProtoDataMessageClosedGroupControlMessage.parseProto(proto).serializedData()
        }
    }

    fileprivate let proto: SessionProtos_DataMessage.ClosedGroupControlMessage

    @objc public let type: SNProtoDataMessageClosedGroupControlMessageType

    @objc public let encryptionKeyPair: SNProtoKeyPair?

    @objc public let wrappers: [SNProtoDataMessageClosedGroupControlMessageKeyPairWrapper]

    @objc public var publicKey: Data? {
        guard proto.hasPublicKey else {
            return nil
        }
        return proto.publicKey
    }
    @objc public var hasPublicKey: Bool {
        return proto.hasPublicKey
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

    @objc public var members: [Data] {
        return proto.members
    }

    @objc public var admins: [Data] {
        return proto.admins
    }

    @objc public var expirationTimer: UInt32 {
        return proto.expirationTimer
    }
    @objc public var hasExpirationTimer: Bool {
        return proto.hasExpirationTimer
    }

    private init(proto: SessionProtos_DataMessage.ClosedGroupControlMessage,
                 type: SNProtoDataMessageClosedGroupControlMessageType,
                 encryptionKeyPair: SNProtoKeyPair?,
                 wrappers: [SNProtoDataMessageClosedGroupControlMessageKeyPairWrapper]) {
        self.proto = proto
        self.type = type
        self.encryptionKeyPair = encryptionKeyPair
        self.wrappers = wrappers
    }

    @objc
    public func serializedData() throws -> Data {
        return try self.proto.serializedData()
    }

    @objc public class func parseData(_ serializedData: Data) throws -> SNProtoDataMessageClosedGroupControlMessage {
        let proto = try SessionProtos_DataMessage.ClosedGroupControlMessage(serializedData: serializedData)
        return try parseProto(proto)
    }

    fileprivate class func parseProto(_ proto: SessionProtos_DataMessage.ClosedGroupControlMessage) throws -> SNProtoDataMessageClosedGroupControlMessage {
        guard proto.hasType else {
            throw SNProtoError.invalidProtobuf(description: "\(logTag) missing required field: type")
        }
        let type = SNProtoDataMessageClosedGroupControlMessageTypeWrap(proto.type)

        var encryptionKeyPair: SNProtoKeyPair? = nil
        if proto.hasEncryptionKeyPair {
            encryptionKeyPair = try SNProtoKeyPair.parseProto(proto.encryptionKeyPair)
        }

        var wrappers: [SNProtoDataMessageClosedGroupControlMessageKeyPairWrapper] = []
        wrappers = try proto.wrappers.map { try SNProtoDataMessageClosedGroupControlMessageKeyPairWrapper.parseProto($0) }

        // MARK: - Begin Validation Logic for SNProtoDataMessageClosedGroupControlMessage -

        // MARK: - End Validation Logic for SNProtoDataMessageClosedGroupControlMessage -

        let result = SNProtoDataMessageClosedGroupControlMessage(proto: proto,
                                                                 type: type,
                                                                 encryptionKeyPair: encryptionKeyPair,
                                                                 wrappers: wrappers)
        return result
    }

    @objc public override var debugDescription: String {
        return "\(proto)"
    }
}

#if DEBUG

extension SNProtoDataMessageClosedGroupControlMessage {
    @objc public func serializedDataIgnoringErrors() -> Data? {
        return try! self.serializedData()
    }
}

extension SNProtoDataMessageClosedGroupControlMessage.SNProtoDataMessageClosedGroupControlMessageBuilder {
    @objc public func buildIgnoringErrors() -> SNProtoDataMessageClosedGroupControlMessage? {
        return try! self.build()
    }
}

#endif

// MARK: - SNProtoDataMessage

@objc public class SNProtoDataMessage: NSObject {

    // MARK: - SNProtoDataMessageFlags

    @objc public enum SNProtoDataMessageFlags: Int32 {
        case expirationTimerUpdate = 2
    }

    private class func SNProtoDataMessageFlagsWrap(_ value: SessionProtos_DataMessage.Flags) -> SNProtoDataMessageFlags {
        switch value {
        case .expirationTimerUpdate: return .expirationTimerUpdate
        }
    }

    private class func SNProtoDataMessageFlagsUnwrap(_ value: SNProtoDataMessageFlags) -> SessionProtos_DataMessage.Flags {
        switch value {
        case .expirationTimerUpdate: return .expirationTimerUpdate
        }
    }

    // MARK: - SNProtoDataMessageBuilder

    @objc public class func builder() -> SNProtoDataMessageBuilder {
        return SNProtoDataMessageBuilder()
    }

    // asBuilder() constructs a builder that reflects the proto's contents.
    @objc public func asBuilder() -> SNProtoDataMessageBuilder {
        let builder = SNProtoDataMessageBuilder()
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
        builder.setPreview(preview)
        if let _value = profile {
            builder.setProfile(_value)
        }
        if let _value = openGroupInvitation {
            builder.setOpenGroupInvitation(_value)
        }
        if let _value = closedGroupControlMessage {
            builder.setClosedGroupControlMessage(_value)
        }
        if let _value = syncTarget {
            builder.setSyncTarget(_value)
        }
        return builder
    }

    @objc public class SNProtoDataMessageBuilder: NSObject {

        private var proto = SessionProtos_DataMessage()

        @objc fileprivate override init() {}

        @objc public func setBody(_ valueParam: String) {
            proto.body = valueParam
        }

        @objc public func addAttachments(_ valueParam: SNProtoAttachmentPointer) {
            var items = proto.attachments
            items.append(valueParam.proto)
            proto.attachments = items
        }

        @objc public func setAttachments(_ wrappedItems: [SNProtoAttachmentPointer]) {
            proto.attachments = wrappedItems.map { $0.proto }
        }

        @objc public func setGroup(_ valueParam: SNProtoGroupContext) {
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

        @objc public func setQuote(_ valueParam: SNProtoDataMessageQuote) {
            proto.quote = valueParam.proto
        }

        @objc public func addPreview(_ valueParam: SNProtoDataMessagePreview) {
            var items = proto.preview
            items.append(valueParam.proto)
            proto.preview = items
        }

        @objc public func setPreview(_ wrappedItems: [SNProtoDataMessagePreview]) {
            proto.preview = wrappedItems.map { $0.proto }
        }

        @objc public func setProfile(_ valueParam: SNProtoDataMessageLokiProfile) {
            proto.profile = valueParam.proto
        }

        @objc public func setOpenGroupInvitation(_ valueParam: SNProtoDataMessageOpenGroupInvitation) {
            proto.openGroupInvitation = valueParam.proto
        }

        @objc public func setClosedGroupControlMessage(_ valueParam: SNProtoDataMessageClosedGroupControlMessage) {
            proto.closedGroupControlMessage = valueParam.proto
        }

        @objc public func setSyncTarget(_ valueParam: String) {
            proto.syncTarget = valueParam
        }

        @objc public func build() throws -> SNProtoDataMessage {
            return try SNProtoDataMessage.parseProto(proto)
        }

        @objc public func buildSerializedData() throws -> Data {
            return try SNProtoDataMessage.parseProto(proto).serializedData()
        }
    }

    fileprivate let proto: SessionProtos_DataMessage

    @objc public let attachments: [SNProtoAttachmentPointer]

    @objc public let group: SNProtoGroupContext?

    @objc public let quote: SNProtoDataMessageQuote?

    @objc public let preview: [SNProtoDataMessagePreview]

    @objc public let profile: SNProtoDataMessageLokiProfile?

    @objc public let openGroupInvitation: SNProtoDataMessageOpenGroupInvitation?

    @objc public let closedGroupControlMessage: SNProtoDataMessageClosedGroupControlMessage?

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

    @objc public var syncTarget: String? {
        guard proto.hasSyncTarget else {
            return nil
        }
        return proto.syncTarget
    }
    @objc public var hasSyncTarget: Bool {
        return proto.hasSyncTarget
    }

    private init(proto: SessionProtos_DataMessage,
                 attachments: [SNProtoAttachmentPointer],
                 group: SNProtoGroupContext?,
                 quote: SNProtoDataMessageQuote?,
                 preview: [SNProtoDataMessagePreview],
                 profile: SNProtoDataMessageLokiProfile?,
                 openGroupInvitation: SNProtoDataMessageOpenGroupInvitation?,
                 closedGroupControlMessage: SNProtoDataMessageClosedGroupControlMessage?) {
        self.proto = proto
        self.attachments = attachments
        self.group = group
        self.quote = quote
        self.preview = preview
        self.profile = profile
        self.openGroupInvitation = openGroupInvitation
        self.closedGroupControlMessage = closedGroupControlMessage
    }

    @objc
    public func serializedData() throws -> Data {
        return try self.proto.serializedData()
    }

    @objc public class func parseData(_ serializedData: Data) throws -> SNProtoDataMessage {
        let proto = try SessionProtos_DataMessage(serializedData: serializedData)
        return try parseProto(proto)
    }

    fileprivate class func parseProto(_ proto: SessionProtos_DataMessage) throws -> SNProtoDataMessage {
        var attachments: [SNProtoAttachmentPointer] = []
        attachments = try proto.attachments.map { try SNProtoAttachmentPointer.parseProto($0) }

        var group: SNProtoGroupContext? = nil
        if proto.hasGroup {
            group = try SNProtoGroupContext.parseProto(proto.group)
        }

        var quote: SNProtoDataMessageQuote? = nil
        if proto.hasQuote {
            quote = try SNProtoDataMessageQuote.parseProto(proto.quote)
        }

        var preview: [SNProtoDataMessagePreview] = []
        preview = try proto.preview.map { try SNProtoDataMessagePreview.parseProto($0) }

        var profile: SNProtoDataMessageLokiProfile? = nil
        if proto.hasProfile {
            profile = try SNProtoDataMessageLokiProfile.parseProto(proto.profile)
        }

        var openGroupInvitation: SNProtoDataMessageOpenGroupInvitation? = nil
        if proto.hasOpenGroupInvitation {
            openGroupInvitation = try SNProtoDataMessageOpenGroupInvitation.parseProto(proto.openGroupInvitation)
        }

        var closedGroupControlMessage: SNProtoDataMessageClosedGroupControlMessage? = nil
        if proto.hasClosedGroupControlMessage {
            closedGroupControlMessage = try SNProtoDataMessageClosedGroupControlMessage.parseProto(proto.closedGroupControlMessage)
        }

        // MARK: - Begin Validation Logic for SNProtoDataMessage -

        // MARK: - End Validation Logic for SNProtoDataMessage -

        let result = SNProtoDataMessage(proto: proto,
                                        attachments: attachments,
                                        group: group,
                                        quote: quote,
                                        preview: preview,
                                        profile: profile,
                                        openGroupInvitation: openGroupInvitation,
                                        closedGroupControlMessage: closedGroupControlMessage)
        return result
    }

    @objc public override var debugDescription: String {
        return "\(proto)"
    }
}

#if DEBUG

extension SNProtoDataMessage {
    @objc public func serializedDataIgnoringErrors() -> Data? {
        return try! self.serializedData()
    }
}

extension SNProtoDataMessage.SNProtoDataMessageBuilder {
    @objc public func buildIgnoringErrors() -> SNProtoDataMessage? {
        return try! self.build()
    }
}

#endif

// MARK: - SNProtoConfigurationMessageClosedGroup

@objc public class SNProtoConfigurationMessageClosedGroup: NSObject {

    // MARK: - SNProtoConfigurationMessageClosedGroupBuilder

    @objc public class func builder() -> SNProtoConfigurationMessageClosedGroupBuilder {
        return SNProtoConfigurationMessageClosedGroupBuilder()
    }

    // asBuilder() constructs a builder that reflects the proto's contents.
    @objc public func asBuilder() -> SNProtoConfigurationMessageClosedGroupBuilder {
        let builder = SNProtoConfigurationMessageClosedGroupBuilder()
        if let _value = publicKey {
            builder.setPublicKey(_value)
        }
        if let _value = name {
            builder.setName(_value)
        }
        if let _value = encryptionKeyPair {
            builder.setEncryptionKeyPair(_value)
        }
        builder.setMembers(members)
        builder.setAdmins(admins)
        if hasExpirationTimer {
            builder.setExpirationTimer(expirationTimer)
        }
        return builder
    }

    @objc public class SNProtoConfigurationMessageClosedGroupBuilder: NSObject {

        private var proto = SessionProtos_ConfigurationMessage.ClosedGroup()

        @objc fileprivate override init() {}

        @objc public func setPublicKey(_ valueParam: Data) {
            proto.publicKey = valueParam
        }

        @objc public func setName(_ valueParam: String) {
            proto.name = valueParam
        }

        @objc public func setEncryptionKeyPair(_ valueParam: SNProtoKeyPair) {
            proto.encryptionKeyPair = valueParam.proto
        }

        @objc public func addMembers(_ valueParam: Data) {
            var items = proto.members
            items.append(valueParam)
            proto.members = items
        }

        @objc public func setMembers(_ wrappedItems: [Data]) {
            proto.members = wrappedItems
        }

        @objc public func addAdmins(_ valueParam: Data) {
            var items = proto.admins
            items.append(valueParam)
            proto.admins = items
        }

        @objc public func setAdmins(_ wrappedItems: [Data]) {
            proto.admins = wrappedItems
        }

        @objc public func setExpirationTimer(_ valueParam: UInt32) {
            proto.expirationTimer = valueParam
        }

        @objc public func build() throws -> SNProtoConfigurationMessageClosedGroup {
            return try SNProtoConfigurationMessageClosedGroup.parseProto(proto)
        }

        @objc public func buildSerializedData() throws -> Data {
            return try SNProtoConfigurationMessageClosedGroup.parseProto(proto).serializedData()
        }
    }

    fileprivate let proto: SessionProtos_ConfigurationMessage.ClosedGroup

    @objc public let encryptionKeyPair: SNProtoKeyPair?

    @objc public var publicKey: Data? {
        guard proto.hasPublicKey else {
            return nil
        }
        return proto.publicKey
    }
    @objc public var hasPublicKey: Bool {
        return proto.hasPublicKey
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

    @objc public var members: [Data] {
        return proto.members
    }

    @objc public var admins: [Data] {
        return proto.admins
    }

    @objc public var expirationTimer: UInt32 {
        return proto.expirationTimer
    }
    @objc public var hasExpirationTimer: Bool {
        return proto.hasExpirationTimer
    }

    private init(proto: SessionProtos_ConfigurationMessage.ClosedGroup,
                 encryptionKeyPair: SNProtoKeyPair?) {
        self.proto = proto
        self.encryptionKeyPair = encryptionKeyPair
    }

    @objc
    public func serializedData() throws -> Data {
        return try self.proto.serializedData()
    }

    @objc public class func parseData(_ serializedData: Data) throws -> SNProtoConfigurationMessageClosedGroup {
        let proto = try SessionProtos_ConfigurationMessage.ClosedGroup(serializedData: serializedData)
        return try parseProto(proto)
    }

    fileprivate class func parseProto(_ proto: SessionProtos_ConfigurationMessage.ClosedGroup) throws -> SNProtoConfigurationMessageClosedGroup {
        var encryptionKeyPair: SNProtoKeyPair? = nil
        if proto.hasEncryptionKeyPair {
            encryptionKeyPair = try SNProtoKeyPair.parseProto(proto.encryptionKeyPair)
        }

        // MARK: - Begin Validation Logic for SNProtoConfigurationMessageClosedGroup -

        // MARK: - End Validation Logic for SNProtoConfigurationMessageClosedGroup -

        let result = SNProtoConfigurationMessageClosedGroup(proto: proto,
                                                            encryptionKeyPair: encryptionKeyPair)
        return result
    }

    @objc public override var debugDescription: String {
        return "\(proto)"
    }
}

#if DEBUG

extension SNProtoConfigurationMessageClosedGroup {
    @objc public func serializedDataIgnoringErrors() -> Data? {
        return try! self.serializedData()
    }
}

extension SNProtoConfigurationMessageClosedGroup.SNProtoConfigurationMessageClosedGroupBuilder {
    @objc public func buildIgnoringErrors() -> SNProtoConfigurationMessageClosedGroup? {
        return try! self.build()
    }
}

#endif

// MARK: - SNProtoConfigurationMessageContact

@objc public class SNProtoConfigurationMessageContact: NSObject {

    // MARK: - SNProtoConfigurationMessageContactBuilder

    @objc public class func builder(publicKey: Data, name: String) -> SNProtoConfigurationMessageContactBuilder {
        return SNProtoConfigurationMessageContactBuilder(publicKey: publicKey, name: name)
    }

    // asBuilder() constructs a builder that reflects the proto's contents.
    @objc public func asBuilder() -> SNProtoConfigurationMessageContactBuilder {
        let builder = SNProtoConfigurationMessageContactBuilder(publicKey: publicKey, name: name)
        if let _value = profilePicture {
            builder.setProfilePicture(_value)
        }
        if let _value = profileKey {
            builder.setProfileKey(_value)
        }
        return builder
    }

    @objc public class SNProtoConfigurationMessageContactBuilder: NSObject {

        private var proto = SessionProtos_ConfigurationMessage.Contact()

        @objc fileprivate override init() {}

        @objc fileprivate init(publicKey: Data, name: String) {
            super.init()

            setPublicKey(publicKey)
            setName(name)
        }

        @objc public func setPublicKey(_ valueParam: Data) {
            proto.publicKey = valueParam
        }

        @objc public func setName(_ valueParam: String) {
            proto.name = valueParam
        }

        @objc public func setProfilePicture(_ valueParam: String) {
            proto.profilePicture = valueParam
        }

        @objc public func setProfileKey(_ valueParam: Data) {
            proto.profileKey = valueParam
        }

        @objc public func build() throws -> SNProtoConfigurationMessageContact {
            return try SNProtoConfigurationMessageContact.parseProto(proto)
        }

        @objc public func buildSerializedData() throws -> Data {
            return try SNProtoConfigurationMessageContact.parseProto(proto).serializedData()
        }
    }

    fileprivate let proto: SessionProtos_ConfigurationMessage.Contact

    @objc public let publicKey: Data

    @objc public let name: String

    @objc public var profilePicture: String? {
        guard proto.hasProfilePicture else {
            return nil
        }
        return proto.profilePicture
    }
    @objc public var hasProfilePicture: Bool {
        return proto.hasProfilePicture
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

    private init(proto: SessionProtos_ConfigurationMessage.Contact,
                 publicKey: Data,
                 name: String) {
        self.proto = proto
        self.publicKey = publicKey
        self.name = name
    }

    @objc
    public func serializedData() throws -> Data {
        return try self.proto.serializedData()
    }

    @objc public class func parseData(_ serializedData: Data) throws -> SNProtoConfigurationMessageContact {
        let proto = try SessionProtos_ConfigurationMessage.Contact(serializedData: serializedData)
        return try parseProto(proto)
    }

    fileprivate class func parseProto(_ proto: SessionProtos_ConfigurationMessage.Contact) throws -> SNProtoConfigurationMessageContact {
        guard proto.hasPublicKey else {
            throw SNProtoError.invalidProtobuf(description: "\(logTag) missing required field: publicKey")
        }
        let publicKey = proto.publicKey

        guard proto.hasName else {
            throw SNProtoError.invalidProtobuf(description: "\(logTag) missing required field: name")
        }
        let name = proto.name

        // MARK: - Begin Validation Logic for SNProtoConfigurationMessageContact -

        // MARK: - End Validation Logic for SNProtoConfigurationMessageContact -

        let result = SNProtoConfigurationMessageContact(proto: proto,
                                                        publicKey: publicKey,
                                                        name: name)
        return result
    }

    @objc public override var debugDescription: String {
        return "\(proto)"
    }
}

#if DEBUG

extension SNProtoConfigurationMessageContact {
    @objc public func serializedDataIgnoringErrors() -> Data? {
        return try! self.serializedData()
    }
}

extension SNProtoConfigurationMessageContact.SNProtoConfigurationMessageContactBuilder {
    @objc public func buildIgnoringErrors() -> SNProtoConfigurationMessageContact? {
        return try! self.build()
    }
}

#endif

// MARK: - SNProtoConfigurationMessage

@objc public class SNProtoConfigurationMessage: NSObject {

    // MARK: - SNProtoConfigurationMessageBuilder

    @objc public class func builder() -> SNProtoConfigurationMessageBuilder {
        return SNProtoConfigurationMessageBuilder()
    }

    // asBuilder() constructs a builder that reflects the proto's contents.
    @objc public func asBuilder() -> SNProtoConfigurationMessageBuilder {
        let builder = SNProtoConfigurationMessageBuilder()
        builder.setClosedGroups(closedGroups)
        builder.setOpenGroups(openGroups)
        if let _value = displayName {
            builder.setDisplayName(_value)
        }
        if let _value = profilePicture {
            builder.setProfilePicture(_value)
        }
        if let _value = profileKey {
            builder.setProfileKey(_value)
        }
        builder.setContacts(contacts)
        return builder
    }

    @objc public class SNProtoConfigurationMessageBuilder: NSObject {

        private var proto = SessionProtos_ConfigurationMessage()

        @objc fileprivate override init() {}

        @objc public func addClosedGroups(_ valueParam: SNProtoConfigurationMessageClosedGroup) {
            var items = proto.closedGroups
            items.append(valueParam.proto)
            proto.closedGroups = items
        }

        @objc public func setClosedGroups(_ wrappedItems: [SNProtoConfigurationMessageClosedGroup]) {
            proto.closedGroups = wrappedItems.map { $0.proto }
        }

        @objc public func addOpenGroups(_ valueParam: String) {
            var items = proto.openGroups
            items.append(valueParam)
            proto.openGroups = items
        }

        @objc public func setOpenGroups(_ wrappedItems: [String]) {
            proto.openGroups = wrappedItems
        }

        @objc public func setDisplayName(_ valueParam: String) {
            proto.displayName = valueParam
        }

        @objc public func setProfilePicture(_ valueParam: String) {
            proto.profilePicture = valueParam
        }

        @objc public func setProfileKey(_ valueParam: Data) {
            proto.profileKey = valueParam
        }

        @objc public func addContacts(_ valueParam: SNProtoConfigurationMessageContact) {
            var items = proto.contacts
            items.append(valueParam.proto)
            proto.contacts = items
        }

        @objc public func setContacts(_ wrappedItems: [SNProtoConfigurationMessageContact]) {
            proto.contacts = wrappedItems.map { $0.proto }
        }

        @objc public func build() throws -> SNProtoConfigurationMessage {
            return try SNProtoConfigurationMessage.parseProto(proto)
        }

        @objc public func buildSerializedData() throws -> Data {
            return try SNProtoConfigurationMessage.parseProto(proto).serializedData()
        }
    }

    fileprivate let proto: SessionProtos_ConfigurationMessage

    @objc public let closedGroups: [SNProtoConfigurationMessageClosedGroup]

    @objc public let contacts: [SNProtoConfigurationMessageContact]

    @objc public var openGroups: [String] {
        return proto.openGroups
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

    @objc public var profilePicture: String? {
        guard proto.hasProfilePicture else {
            return nil
        }
        return proto.profilePicture
    }
    @objc public var hasProfilePicture: Bool {
        return proto.hasProfilePicture
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

    private init(proto: SessionProtos_ConfigurationMessage,
                 closedGroups: [SNProtoConfigurationMessageClosedGroup],
                 contacts: [SNProtoConfigurationMessageContact]) {
        self.proto = proto
        self.closedGroups = closedGroups
        self.contacts = contacts
    }

    @objc
    public func serializedData() throws -> Data {
        return try self.proto.serializedData()
    }

    @objc public class func parseData(_ serializedData: Data) throws -> SNProtoConfigurationMessage {
        let proto = try SessionProtos_ConfigurationMessage(serializedData: serializedData)
        return try parseProto(proto)
    }

    fileprivate class func parseProto(_ proto: SessionProtos_ConfigurationMessage) throws -> SNProtoConfigurationMessage {
        var closedGroups: [SNProtoConfigurationMessageClosedGroup] = []
        closedGroups = try proto.closedGroups.map { try SNProtoConfigurationMessageClosedGroup.parseProto($0) }

        var contacts: [SNProtoConfigurationMessageContact] = []
        contacts = try proto.contacts.map { try SNProtoConfigurationMessageContact.parseProto($0) }

        // MARK: - Begin Validation Logic for SNProtoConfigurationMessage -

        // MARK: - End Validation Logic for SNProtoConfigurationMessage -

        let result = SNProtoConfigurationMessage(proto: proto,
                                                 closedGroups: closedGroups,
                                                 contacts: contacts)
        return result
    }

    @objc public override var debugDescription: String {
        return "\(proto)"
    }
}

#if DEBUG

extension SNProtoConfigurationMessage {
    @objc public func serializedDataIgnoringErrors() -> Data? {
        return try! self.serializedData()
    }
}

extension SNProtoConfigurationMessage.SNProtoConfigurationMessageBuilder {
    @objc public func buildIgnoringErrors() -> SNProtoConfigurationMessage? {
        return try! self.build()
    }
}

#endif

// MARK: - SNProtoReceiptMessage

@objc public class SNProtoReceiptMessage: NSObject {

    // MARK: - SNProtoReceiptMessageType

    @objc public enum SNProtoReceiptMessageType: Int32 {
        case delivery = 0
        case read = 1
    }

    private class func SNProtoReceiptMessageTypeWrap(_ value: SessionProtos_ReceiptMessage.TypeEnum) -> SNProtoReceiptMessageType {
        switch value {
        case .delivery: return .delivery
        case .read: return .read
        }
    }

    private class func SNProtoReceiptMessageTypeUnwrap(_ value: SNProtoReceiptMessageType) -> SessionProtos_ReceiptMessage.TypeEnum {
        switch value {
        case .delivery: return .delivery
        case .read: return .read
        }
    }

    // MARK: - SNProtoReceiptMessageBuilder

    @objc public class func builder(type: SNProtoReceiptMessageType) -> SNProtoReceiptMessageBuilder {
        return SNProtoReceiptMessageBuilder(type: type)
    }

    // asBuilder() constructs a builder that reflects the proto's contents.
    @objc public func asBuilder() -> SNProtoReceiptMessageBuilder {
        let builder = SNProtoReceiptMessageBuilder(type: type)
        builder.setTimestamp(timestamp)
        return builder
    }

    @objc public class SNProtoReceiptMessageBuilder: NSObject {

        private var proto = SessionProtos_ReceiptMessage()

        @objc fileprivate override init() {}

        @objc fileprivate init(type: SNProtoReceiptMessageType) {
            super.init()

            setType(type)
        }

        @objc public func setType(_ valueParam: SNProtoReceiptMessageType) {
            proto.type = SNProtoReceiptMessageTypeUnwrap(valueParam)
        }

        @objc public func addTimestamp(_ valueParam: UInt64) {
            var items = proto.timestamp
            items.append(valueParam)
            proto.timestamp = items
        }

        @objc public func setTimestamp(_ wrappedItems: [UInt64]) {
            proto.timestamp = wrappedItems
        }

        @objc public func build() throws -> SNProtoReceiptMessage {
            return try SNProtoReceiptMessage.parseProto(proto)
        }

        @objc public func buildSerializedData() throws -> Data {
            return try SNProtoReceiptMessage.parseProto(proto).serializedData()
        }
    }

    fileprivate let proto: SessionProtos_ReceiptMessage

    @objc public let type: SNProtoReceiptMessageType

    @objc public var timestamp: [UInt64] {
        return proto.timestamp
    }

    private init(proto: SessionProtos_ReceiptMessage,
                 type: SNProtoReceiptMessageType) {
        self.proto = proto
        self.type = type
    }

    @objc
    public func serializedData() throws -> Data {
        return try self.proto.serializedData()
    }

    @objc public class func parseData(_ serializedData: Data) throws -> SNProtoReceiptMessage {
        let proto = try SessionProtos_ReceiptMessage(serializedData: serializedData)
        return try parseProto(proto)
    }

    fileprivate class func parseProto(_ proto: SessionProtos_ReceiptMessage) throws -> SNProtoReceiptMessage {
        guard proto.hasType else {
            throw SNProtoError.invalidProtobuf(description: "\(logTag) missing required field: type")
        }
        let type = SNProtoReceiptMessageTypeWrap(proto.type)

        // MARK: - Begin Validation Logic for SNProtoReceiptMessage -

        // MARK: - End Validation Logic for SNProtoReceiptMessage -

        let result = SNProtoReceiptMessage(proto: proto,
                                           type: type)
        return result
    }

    @objc public override var debugDescription: String {
        return "\(proto)"
    }
}

#if DEBUG

extension SNProtoReceiptMessage {
    @objc public func serializedDataIgnoringErrors() -> Data? {
        return try! self.serializedData()
    }
}

extension SNProtoReceiptMessage.SNProtoReceiptMessageBuilder {
    @objc public func buildIgnoringErrors() -> SNProtoReceiptMessage? {
        return try! self.build()
    }
}

#endif

// MARK: - SNProtoAttachmentPointer

@objc public class SNProtoAttachmentPointer: NSObject {

    // MARK: - SNProtoAttachmentPointerFlags

    @objc public enum SNProtoAttachmentPointerFlags: Int32 {
        case voiceMessage = 1
    }

    private class func SNProtoAttachmentPointerFlagsWrap(_ value: SessionProtos_AttachmentPointer.Flags) -> SNProtoAttachmentPointerFlags {
        switch value {
        case .voiceMessage: return .voiceMessage
        }
    }

    private class func SNProtoAttachmentPointerFlagsUnwrap(_ value: SNProtoAttachmentPointerFlags) -> SessionProtos_AttachmentPointer.Flags {
        switch value {
        case .voiceMessage: return .voiceMessage
        }
    }

    // MARK: - SNProtoAttachmentPointerBuilder

    @objc public class func builder(id: UInt64) -> SNProtoAttachmentPointerBuilder {
        return SNProtoAttachmentPointerBuilder(id: id)
    }

    // asBuilder() constructs a builder that reflects the proto's contents.
    @objc public func asBuilder() -> SNProtoAttachmentPointerBuilder {
        let builder = SNProtoAttachmentPointerBuilder(id: id)
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
        if let _value = url {
            builder.setUrl(_value)
        }
        return builder
    }

    @objc public class SNProtoAttachmentPointerBuilder: NSObject {

        private var proto = SessionProtos_AttachmentPointer()

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

        @objc public func setUrl(_ valueParam: String) {
            proto.url = valueParam
        }

        @objc public func build() throws -> SNProtoAttachmentPointer {
            return try SNProtoAttachmentPointer.parseProto(proto)
        }

        @objc public func buildSerializedData() throws -> Data {
            return try SNProtoAttachmentPointer.parseProto(proto).serializedData()
        }
    }

    fileprivate let proto: SessionProtos_AttachmentPointer

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

    @objc public var url: String? {
        guard proto.hasURL else {
            return nil
        }
        return proto.url
    }
    @objc public var hasURL: Bool {
        return proto.hasURL
    }

    private init(proto: SessionProtos_AttachmentPointer,
                 id: UInt64) {
        self.proto = proto
        self.id = id
    }

    @objc
    public func serializedData() throws -> Data {
        return try self.proto.serializedData()
    }

    @objc public class func parseData(_ serializedData: Data) throws -> SNProtoAttachmentPointer {
        let proto = try SessionProtos_AttachmentPointer(serializedData: serializedData)
        return try parseProto(proto)
    }

    fileprivate class func parseProto(_ proto: SessionProtos_AttachmentPointer) throws -> SNProtoAttachmentPointer {
        guard proto.hasID else {
            throw SNProtoError.invalidProtobuf(description: "\(logTag) missing required field: id")
        }
        let id = proto.id

        // MARK: - Begin Validation Logic for SNProtoAttachmentPointer -

        // MARK: - End Validation Logic for SNProtoAttachmentPointer -

        let result = SNProtoAttachmentPointer(proto: proto,
                                              id: id)
        return result
    }

    @objc public override var debugDescription: String {
        return "\(proto)"
    }
}

#if DEBUG

extension SNProtoAttachmentPointer {
    @objc public func serializedDataIgnoringErrors() -> Data? {
        return try! self.serializedData()
    }
}

extension SNProtoAttachmentPointer.SNProtoAttachmentPointerBuilder {
    @objc public func buildIgnoringErrors() -> SNProtoAttachmentPointer? {
        return try! self.build()
    }
}

#endif

// MARK: - SNProtoGroupContext

@objc public class SNProtoGroupContext: NSObject {

    // MARK: - SNProtoGroupContextType

    @objc public enum SNProtoGroupContextType: Int32 {
        case unknown = 0
        case update = 1
        case deliver = 2
        case quit = 3
        case requestInfo = 4
    }

    private class func SNProtoGroupContextTypeWrap(_ value: SessionProtos_GroupContext.TypeEnum) -> SNProtoGroupContextType {
        switch value {
        case .unknown: return .unknown
        case .update: return .update
        case .deliver: return .deliver
        case .quit: return .quit
        case .requestInfo: return .requestInfo
        }
    }

    private class func SNProtoGroupContextTypeUnwrap(_ value: SNProtoGroupContextType) -> SessionProtos_GroupContext.TypeEnum {
        switch value {
        case .unknown: return .unknown
        case .update: return .update
        case .deliver: return .deliver
        case .quit: return .quit
        case .requestInfo: return .requestInfo
        }
    }

    // MARK: - SNProtoGroupContextBuilder

    @objc public class func builder(id: Data, type: SNProtoGroupContextType) -> SNProtoGroupContextBuilder {
        return SNProtoGroupContextBuilder(id: id, type: type)
    }

    // asBuilder() constructs a builder that reflects the proto's contents.
    @objc public func asBuilder() -> SNProtoGroupContextBuilder {
        let builder = SNProtoGroupContextBuilder(id: id, type: type)
        if let _value = name {
            builder.setName(_value)
        }
        builder.setMembers(members)
        if let _value = avatar {
            builder.setAvatar(_value)
        }
        builder.setAdmins(admins)
        return builder
    }

    @objc public class SNProtoGroupContextBuilder: NSObject {

        private var proto = SessionProtos_GroupContext()

        @objc fileprivate override init() {}

        @objc fileprivate init(id: Data, type: SNProtoGroupContextType) {
            super.init()

            setId(id)
            setType(type)
        }

        @objc public func setId(_ valueParam: Data) {
            proto.id = valueParam
        }

        @objc public func setType(_ valueParam: SNProtoGroupContextType) {
            proto.type = SNProtoGroupContextTypeUnwrap(valueParam)
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

        @objc public func setAvatar(_ valueParam: SNProtoAttachmentPointer) {
            proto.avatar = valueParam.proto
        }

        @objc public func addAdmins(_ valueParam: String) {
            var items = proto.admins
            items.append(valueParam)
            proto.admins = items
        }

        @objc public func setAdmins(_ wrappedItems: [String]) {
            proto.admins = wrappedItems
        }

        @objc public func build() throws -> SNProtoGroupContext {
            return try SNProtoGroupContext.parseProto(proto)
        }

        @objc public func buildSerializedData() throws -> Data {
            return try SNProtoGroupContext.parseProto(proto).serializedData()
        }
    }

    fileprivate let proto: SessionProtos_GroupContext

    @objc public let id: Data

    @objc public let type: SNProtoGroupContextType

    @objc public let avatar: SNProtoAttachmentPointer?

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

    @objc public var admins: [String] {
        return proto.admins
    }

    private init(proto: SessionProtos_GroupContext,
                 id: Data,
                 type: SNProtoGroupContextType,
                 avatar: SNProtoAttachmentPointer?) {
        self.proto = proto
        self.id = id
        self.type = type
        self.avatar = avatar
    }

    @objc
    public func serializedData() throws -> Data {
        return try self.proto.serializedData()
    }

    @objc public class func parseData(_ serializedData: Data) throws -> SNProtoGroupContext {
        let proto = try SessionProtos_GroupContext(serializedData: serializedData)
        return try parseProto(proto)
    }

    fileprivate class func parseProto(_ proto: SessionProtos_GroupContext) throws -> SNProtoGroupContext {
        guard proto.hasID else {
            throw SNProtoError.invalidProtobuf(description: "\(logTag) missing required field: id")
        }
        let id = proto.id

        guard proto.hasType else {
            throw SNProtoError.invalidProtobuf(description: "\(logTag) missing required field: type")
        }
        let type = SNProtoGroupContextTypeWrap(proto.type)

        var avatar: SNProtoAttachmentPointer? = nil
        if proto.hasAvatar {
            avatar = try SNProtoAttachmentPointer.parseProto(proto.avatar)
        }

        // MARK: - Begin Validation Logic for SNProtoGroupContext -

        // MARK: - End Validation Logic for SNProtoGroupContext -

        let result = SNProtoGroupContext(proto: proto,
                                         id: id,
                                         type: type,
                                         avatar: avatar)
        return result
    }

    @objc public override var debugDescription: String {
        return "\(proto)"
    }
}

#if DEBUG

extension SNProtoGroupContext {
    @objc public func serializedDataIgnoringErrors() -> Data? {
        return try! self.serializedData()
    }
}

extension SNProtoGroupContext.SNProtoGroupContextBuilder {
    @objc public func buildIgnoringErrors() -> SNProtoGroupContext? {
        return try! self.build()
    }
}

#endif
