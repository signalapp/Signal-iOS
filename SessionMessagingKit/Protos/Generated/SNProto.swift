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
        case unidentifiedSender = 6
        case closedGroupCiphertext = 7
    }

    private class func SNProtoEnvelopeTypeWrap(_ value: SessionProtos_Envelope.TypeEnum) -> SNProtoEnvelopeType {
        switch value {
        case .unidentifiedSender: return .unidentifiedSender
        case .closedGroupCiphertext: return .closedGroupCiphertext
        }
    }

    private class func SNProtoEnvelopeTypeUnwrap(_ value: SNProtoEnvelopeType) -> SessionProtos_Envelope.TypeEnum {
        switch value {
        case .unidentifiedSender: return .unidentifiedSender
        case .closedGroupCiphertext: return .closedGroupCiphertext
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
        if let _value = syncMessage {
            builder.setSyncMessage(_value)
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
        return builder
    }

    @objc public class SNProtoContentBuilder: NSObject {

        private var proto = SessionProtos_Content()

        @objc fileprivate override init() {}

        @objc public func setDataMessage(_ valueParam: SNProtoDataMessage) {
            proto.dataMessage = valueParam.proto
        }

        @objc public func setSyncMessage(_ valueParam: SNProtoSyncMessage) {
            proto.syncMessage = valueParam.proto
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

        @objc public func build() throws -> SNProtoContent {
            return try SNProtoContent.parseProto(proto)
        }

        @objc public func buildSerializedData() throws -> Data {
            return try SNProtoContent.parseProto(proto).serializedData()
        }
    }

    fileprivate let proto: SessionProtos_Content

    @objc public let dataMessage: SNProtoDataMessage?

    @objc public let syncMessage: SNProtoSyncMessage?

    @objc public let receiptMessage: SNProtoReceiptMessage?

    @objc public let typingMessage: SNProtoTypingMessage?

    @objc public let configurationMessage: SNProtoConfigurationMessage?

    private init(proto: SessionProtos_Content,
                 dataMessage: SNProtoDataMessage?,
                 syncMessage: SNProtoSyncMessage?,
                 receiptMessage: SNProtoReceiptMessage?,
                 typingMessage: SNProtoTypingMessage?,
                 configurationMessage: SNProtoConfigurationMessage?) {
        self.proto = proto
        self.dataMessage = dataMessage
        self.syncMessage = syncMessage
        self.receiptMessage = receiptMessage
        self.typingMessage = typingMessage
        self.configurationMessage = configurationMessage
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

        var syncMessage: SNProtoSyncMessage? = nil
        if proto.hasSyncMessage {
            syncMessage = try SNProtoSyncMessage.parseProto(proto.syncMessage)
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

        // MARK: - Begin Validation Logic for SNProtoContent -

        // MARK: - End Validation Logic for SNProtoContent -

        let result = SNProtoContent(proto: proto,
                                    dataMessage: dataMessage,
                                    syncMessage: syncMessage,
                                    receiptMessage: receiptMessage,
                                    typingMessage: typingMessage,
                                    configurationMessage: configurationMessage)
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

// MARK: - SNProtoClosedGroupCiphertextMessageWrapper

@objc public class SNProtoClosedGroupCiphertextMessageWrapper: NSObject {

    // MARK: - SNProtoClosedGroupCiphertextMessageWrapperBuilder

    @objc public class func builder(ciphertext: Data, ephemeralPublicKey: Data) -> SNProtoClosedGroupCiphertextMessageWrapperBuilder {
        return SNProtoClosedGroupCiphertextMessageWrapperBuilder(ciphertext: ciphertext, ephemeralPublicKey: ephemeralPublicKey)
    }

    // asBuilder() constructs a builder that reflects the proto's contents.
    @objc public func asBuilder() -> SNProtoClosedGroupCiphertextMessageWrapperBuilder {
        let builder = SNProtoClosedGroupCiphertextMessageWrapperBuilder(ciphertext: ciphertext, ephemeralPublicKey: ephemeralPublicKey)
        return builder
    }

    @objc public class SNProtoClosedGroupCiphertextMessageWrapperBuilder: NSObject {

        private var proto = SessionProtos_ClosedGroupCiphertextMessageWrapper()

        @objc fileprivate override init() {}

        @objc fileprivate init(ciphertext: Data, ephemeralPublicKey: Data) {
            super.init()

            setCiphertext(ciphertext)
            setEphemeralPublicKey(ephemeralPublicKey)
        }

        @objc public func setCiphertext(_ valueParam: Data) {
            proto.ciphertext = valueParam
        }

        @objc public func setEphemeralPublicKey(_ valueParam: Data) {
            proto.ephemeralPublicKey = valueParam
        }

        @objc public func build() throws -> SNProtoClosedGroupCiphertextMessageWrapper {
            return try SNProtoClosedGroupCiphertextMessageWrapper.parseProto(proto)
        }

        @objc public func buildSerializedData() throws -> Data {
            return try SNProtoClosedGroupCiphertextMessageWrapper.parseProto(proto).serializedData()
        }
    }

    fileprivate let proto: SessionProtos_ClosedGroupCiphertextMessageWrapper

    @objc public let ciphertext: Data

    @objc public let ephemeralPublicKey: Data

    private init(proto: SessionProtos_ClosedGroupCiphertextMessageWrapper,
                 ciphertext: Data,
                 ephemeralPublicKey: Data) {
        self.proto = proto
        self.ciphertext = ciphertext
        self.ephemeralPublicKey = ephemeralPublicKey
    }

    @objc
    public func serializedData() throws -> Data {
        return try self.proto.serializedData()
    }

    @objc public class func parseData(_ serializedData: Data) throws -> SNProtoClosedGroupCiphertextMessageWrapper {
        let proto = try SessionProtos_ClosedGroupCiphertextMessageWrapper(serializedData: serializedData)
        return try parseProto(proto)
    }

    fileprivate class func parseProto(_ proto: SessionProtos_ClosedGroupCiphertextMessageWrapper) throws -> SNProtoClosedGroupCiphertextMessageWrapper {
        guard proto.hasCiphertext else {
            throw SNProtoError.invalidProtobuf(description: "\(logTag) missing required field: ciphertext")
        }
        let ciphertext = proto.ciphertext

        guard proto.hasEphemeralPublicKey else {
            throw SNProtoError.invalidProtobuf(description: "\(logTag) missing required field: ephemeralPublicKey")
        }
        let ephemeralPublicKey = proto.ephemeralPublicKey

        // MARK: - Begin Validation Logic for SNProtoClosedGroupCiphertextMessageWrapper -

        // MARK: - End Validation Logic for SNProtoClosedGroupCiphertextMessageWrapper -

        let result = SNProtoClosedGroupCiphertextMessageWrapper(proto: proto,
                                                                ciphertext: ciphertext,
                                                                ephemeralPublicKey: ephemeralPublicKey)
        return result
    }

    @objc public override var debugDescription: String {
        return "\(proto)"
    }
}

#if DEBUG

extension SNProtoClosedGroupCiphertextMessageWrapper {
    @objc public func serializedDataIgnoringErrors() -> Data? {
        return try! self.serializedData()
    }
}

extension SNProtoClosedGroupCiphertextMessageWrapper.SNProtoClosedGroupCiphertextMessageWrapperBuilder {
    @objc public func buildIgnoringErrors() -> SNProtoClosedGroupCiphertextMessageWrapper? {
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

// MARK: - SNProtoDataMessageContactName

@objc public class SNProtoDataMessageContactName: NSObject {

    // MARK: - SNProtoDataMessageContactNameBuilder

    @objc public class func builder() -> SNProtoDataMessageContactNameBuilder {
        return SNProtoDataMessageContactNameBuilder()
    }

    // asBuilder() constructs a builder that reflects the proto's contents.
    @objc public func asBuilder() -> SNProtoDataMessageContactNameBuilder {
        let builder = SNProtoDataMessageContactNameBuilder()
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

    @objc public class SNProtoDataMessageContactNameBuilder: NSObject {

        private var proto = SessionProtos_DataMessage.Contact.Name()

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

        @objc public func build() throws -> SNProtoDataMessageContactName {
            return try SNProtoDataMessageContactName.parseProto(proto)
        }

        @objc public func buildSerializedData() throws -> Data {
            return try SNProtoDataMessageContactName.parseProto(proto).serializedData()
        }
    }

    fileprivate let proto: SessionProtos_DataMessage.Contact.Name

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

    private init(proto: SessionProtos_DataMessage.Contact.Name) {
        self.proto = proto
    }

    @objc
    public func serializedData() throws -> Data {
        return try self.proto.serializedData()
    }

    @objc public class func parseData(_ serializedData: Data) throws -> SNProtoDataMessageContactName {
        let proto = try SessionProtos_DataMessage.Contact.Name(serializedData: serializedData)
        return try parseProto(proto)
    }

    fileprivate class func parseProto(_ proto: SessionProtos_DataMessage.Contact.Name) throws -> SNProtoDataMessageContactName {
        // MARK: - Begin Validation Logic for SNProtoDataMessageContactName -

        // MARK: - End Validation Logic for SNProtoDataMessageContactName -

        let result = SNProtoDataMessageContactName(proto: proto)
        return result
    }

    @objc public override var debugDescription: String {
        return "\(proto)"
    }
}

#if DEBUG

extension SNProtoDataMessageContactName {
    @objc public func serializedDataIgnoringErrors() -> Data? {
        return try! self.serializedData()
    }
}

extension SNProtoDataMessageContactName.SNProtoDataMessageContactNameBuilder {
    @objc public func buildIgnoringErrors() -> SNProtoDataMessageContactName? {
        return try! self.build()
    }
}

#endif

// MARK: - SNProtoDataMessageContactPhone

@objc public class SNProtoDataMessageContactPhone: NSObject {

    // MARK: - SNProtoDataMessageContactPhoneType

    @objc public enum SNProtoDataMessageContactPhoneType: Int32 {
        case home = 1
        case mobile = 2
        case work = 3
        case custom = 4
    }

    private class func SNProtoDataMessageContactPhoneTypeWrap(_ value: SessionProtos_DataMessage.Contact.Phone.TypeEnum) -> SNProtoDataMessageContactPhoneType {
        switch value {
        case .home: return .home
        case .mobile: return .mobile
        case .work: return .work
        case .custom: return .custom
        }
    }

    private class func SNProtoDataMessageContactPhoneTypeUnwrap(_ value: SNProtoDataMessageContactPhoneType) -> SessionProtos_DataMessage.Contact.Phone.TypeEnum {
        switch value {
        case .home: return .home
        case .mobile: return .mobile
        case .work: return .work
        case .custom: return .custom
        }
    }

    // MARK: - SNProtoDataMessageContactPhoneBuilder

    @objc public class func builder() -> SNProtoDataMessageContactPhoneBuilder {
        return SNProtoDataMessageContactPhoneBuilder()
    }

    // asBuilder() constructs a builder that reflects the proto's contents.
    @objc public func asBuilder() -> SNProtoDataMessageContactPhoneBuilder {
        let builder = SNProtoDataMessageContactPhoneBuilder()
        if let _value = value {
            builder.setValue(_value)
        }
        if hasType {
            builder.setType(type)
        }
        if let _value = label {
            builder.setLabel(_value)
        }
        return builder
    }

    @objc public class SNProtoDataMessageContactPhoneBuilder: NSObject {

        private var proto = SessionProtos_DataMessage.Contact.Phone()

        @objc fileprivate override init() {}

        @objc public func setValue(_ valueParam: String) {
            proto.value = valueParam
        }

        @objc public func setType(_ valueParam: SNProtoDataMessageContactPhoneType) {
            proto.type = SNProtoDataMessageContactPhoneTypeUnwrap(valueParam)
        }

        @objc public func setLabel(_ valueParam: String) {
            proto.label = valueParam
        }

        @objc public func build() throws -> SNProtoDataMessageContactPhone {
            return try SNProtoDataMessageContactPhone.parseProto(proto)
        }

        @objc public func buildSerializedData() throws -> Data {
            return try SNProtoDataMessageContactPhone.parseProto(proto).serializedData()
        }
    }

    fileprivate let proto: SessionProtos_DataMessage.Contact.Phone

    @objc public var value: String? {
        guard proto.hasValue else {
            return nil
        }
        return proto.value
    }
    @objc public var hasValue: Bool {
        return proto.hasValue
    }

    @objc public var type: SNProtoDataMessageContactPhoneType {
        return SNProtoDataMessageContactPhone.SNProtoDataMessageContactPhoneTypeWrap(proto.type)
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

    private init(proto: SessionProtos_DataMessage.Contact.Phone) {
        self.proto = proto
    }

    @objc
    public func serializedData() throws -> Data {
        return try self.proto.serializedData()
    }

    @objc public class func parseData(_ serializedData: Data) throws -> SNProtoDataMessageContactPhone {
        let proto = try SessionProtos_DataMessage.Contact.Phone(serializedData: serializedData)
        return try parseProto(proto)
    }

    fileprivate class func parseProto(_ proto: SessionProtos_DataMessage.Contact.Phone) throws -> SNProtoDataMessageContactPhone {
        // MARK: - Begin Validation Logic for SNProtoDataMessageContactPhone -

        // MARK: - End Validation Logic for SNProtoDataMessageContactPhone -

        let result = SNProtoDataMessageContactPhone(proto: proto)
        return result
    }

    @objc public override var debugDescription: String {
        return "\(proto)"
    }
}

#if DEBUG

extension SNProtoDataMessageContactPhone {
    @objc public func serializedDataIgnoringErrors() -> Data? {
        return try! self.serializedData()
    }
}

extension SNProtoDataMessageContactPhone.SNProtoDataMessageContactPhoneBuilder {
    @objc public func buildIgnoringErrors() -> SNProtoDataMessageContactPhone? {
        return try! self.build()
    }
}

#endif

// MARK: - SNProtoDataMessageContactEmail

@objc public class SNProtoDataMessageContactEmail: NSObject {

    // MARK: - SNProtoDataMessageContactEmailType

    @objc public enum SNProtoDataMessageContactEmailType: Int32 {
        case home = 1
        case mobile = 2
        case work = 3
        case custom = 4
    }

    private class func SNProtoDataMessageContactEmailTypeWrap(_ value: SessionProtos_DataMessage.Contact.Email.TypeEnum) -> SNProtoDataMessageContactEmailType {
        switch value {
        case .home: return .home
        case .mobile: return .mobile
        case .work: return .work
        case .custom: return .custom
        }
    }

    private class func SNProtoDataMessageContactEmailTypeUnwrap(_ value: SNProtoDataMessageContactEmailType) -> SessionProtos_DataMessage.Contact.Email.TypeEnum {
        switch value {
        case .home: return .home
        case .mobile: return .mobile
        case .work: return .work
        case .custom: return .custom
        }
    }

    // MARK: - SNProtoDataMessageContactEmailBuilder

    @objc public class func builder() -> SNProtoDataMessageContactEmailBuilder {
        return SNProtoDataMessageContactEmailBuilder()
    }

    // asBuilder() constructs a builder that reflects the proto's contents.
    @objc public func asBuilder() -> SNProtoDataMessageContactEmailBuilder {
        let builder = SNProtoDataMessageContactEmailBuilder()
        if let _value = value {
            builder.setValue(_value)
        }
        if hasType {
            builder.setType(type)
        }
        if let _value = label {
            builder.setLabel(_value)
        }
        return builder
    }

    @objc public class SNProtoDataMessageContactEmailBuilder: NSObject {

        private var proto = SessionProtos_DataMessage.Contact.Email()

        @objc fileprivate override init() {}

        @objc public func setValue(_ valueParam: String) {
            proto.value = valueParam
        }

        @objc public func setType(_ valueParam: SNProtoDataMessageContactEmailType) {
            proto.type = SNProtoDataMessageContactEmailTypeUnwrap(valueParam)
        }

        @objc public func setLabel(_ valueParam: String) {
            proto.label = valueParam
        }

        @objc public func build() throws -> SNProtoDataMessageContactEmail {
            return try SNProtoDataMessageContactEmail.parseProto(proto)
        }

        @objc public func buildSerializedData() throws -> Data {
            return try SNProtoDataMessageContactEmail.parseProto(proto).serializedData()
        }
    }

    fileprivate let proto: SessionProtos_DataMessage.Contact.Email

    @objc public var value: String? {
        guard proto.hasValue else {
            return nil
        }
        return proto.value
    }
    @objc public var hasValue: Bool {
        return proto.hasValue
    }

    @objc public var type: SNProtoDataMessageContactEmailType {
        return SNProtoDataMessageContactEmail.SNProtoDataMessageContactEmailTypeWrap(proto.type)
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

    private init(proto: SessionProtos_DataMessage.Contact.Email) {
        self.proto = proto
    }

    @objc
    public func serializedData() throws -> Data {
        return try self.proto.serializedData()
    }

    @objc public class func parseData(_ serializedData: Data) throws -> SNProtoDataMessageContactEmail {
        let proto = try SessionProtos_DataMessage.Contact.Email(serializedData: serializedData)
        return try parseProto(proto)
    }

    fileprivate class func parseProto(_ proto: SessionProtos_DataMessage.Contact.Email) throws -> SNProtoDataMessageContactEmail {
        // MARK: - Begin Validation Logic for SNProtoDataMessageContactEmail -

        // MARK: - End Validation Logic for SNProtoDataMessageContactEmail -

        let result = SNProtoDataMessageContactEmail(proto: proto)
        return result
    }

    @objc public override var debugDescription: String {
        return "\(proto)"
    }
}

#if DEBUG

extension SNProtoDataMessageContactEmail {
    @objc public func serializedDataIgnoringErrors() -> Data? {
        return try! self.serializedData()
    }
}

extension SNProtoDataMessageContactEmail.SNProtoDataMessageContactEmailBuilder {
    @objc public func buildIgnoringErrors() -> SNProtoDataMessageContactEmail? {
        return try! self.build()
    }
}

#endif

// MARK: - SNProtoDataMessageContactPostalAddress

@objc public class SNProtoDataMessageContactPostalAddress: NSObject {

    // MARK: - SNProtoDataMessageContactPostalAddressType

    @objc public enum SNProtoDataMessageContactPostalAddressType: Int32 {
        case home = 1
        case work = 2
        case custom = 3
    }

    private class func SNProtoDataMessageContactPostalAddressTypeWrap(_ value: SessionProtos_DataMessage.Contact.PostalAddress.TypeEnum) -> SNProtoDataMessageContactPostalAddressType {
        switch value {
        case .home: return .home
        case .work: return .work
        case .custom: return .custom
        }
    }

    private class func SNProtoDataMessageContactPostalAddressTypeUnwrap(_ value: SNProtoDataMessageContactPostalAddressType) -> SessionProtos_DataMessage.Contact.PostalAddress.TypeEnum {
        switch value {
        case .home: return .home
        case .work: return .work
        case .custom: return .custom
        }
    }

    // MARK: - SNProtoDataMessageContactPostalAddressBuilder

    @objc public class func builder() -> SNProtoDataMessageContactPostalAddressBuilder {
        return SNProtoDataMessageContactPostalAddressBuilder()
    }

    // asBuilder() constructs a builder that reflects the proto's contents.
    @objc public func asBuilder() -> SNProtoDataMessageContactPostalAddressBuilder {
        let builder = SNProtoDataMessageContactPostalAddressBuilder()
        if hasType {
            builder.setType(type)
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

    @objc public class SNProtoDataMessageContactPostalAddressBuilder: NSObject {

        private var proto = SessionProtos_DataMessage.Contact.PostalAddress()

        @objc fileprivate override init() {}

        @objc public func setType(_ valueParam: SNProtoDataMessageContactPostalAddressType) {
            proto.type = SNProtoDataMessageContactPostalAddressTypeUnwrap(valueParam)
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

        @objc public func build() throws -> SNProtoDataMessageContactPostalAddress {
            return try SNProtoDataMessageContactPostalAddress.parseProto(proto)
        }

        @objc public func buildSerializedData() throws -> Data {
            return try SNProtoDataMessageContactPostalAddress.parseProto(proto).serializedData()
        }
    }

    fileprivate let proto: SessionProtos_DataMessage.Contact.PostalAddress

    @objc public var type: SNProtoDataMessageContactPostalAddressType {
        return SNProtoDataMessageContactPostalAddress.SNProtoDataMessageContactPostalAddressTypeWrap(proto.type)
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

    private init(proto: SessionProtos_DataMessage.Contact.PostalAddress) {
        self.proto = proto
    }

    @objc
    public func serializedData() throws -> Data {
        return try self.proto.serializedData()
    }

    @objc public class func parseData(_ serializedData: Data) throws -> SNProtoDataMessageContactPostalAddress {
        let proto = try SessionProtos_DataMessage.Contact.PostalAddress(serializedData: serializedData)
        return try parseProto(proto)
    }

    fileprivate class func parseProto(_ proto: SessionProtos_DataMessage.Contact.PostalAddress) throws -> SNProtoDataMessageContactPostalAddress {
        // MARK: - Begin Validation Logic for SNProtoDataMessageContactPostalAddress -

        // MARK: - End Validation Logic for SNProtoDataMessageContactPostalAddress -

        let result = SNProtoDataMessageContactPostalAddress(proto: proto)
        return result
    }

    @objc public override var debugDescription: String {
        return "\(proto)"
    }
}

#if DEBUG

extension SNProtoDataMessageContactPostalAddress {
    @objc public func serializedDataIgnoringErrors() -> Data? {
        return try! self.serializedData()
    }
}

extension SNProtoDataMessageContactPostalAddress.SNProtoDataMessageContactPostalAddressBuilder {
    @objc public func buildIgnoringErrors() -> SNProtoDataMessageContactPostalAddress? {
        return try! self.build()
    }
}

#endif

// MARK: - SNProtoDataMessageContactAvatar

@objc public class SNProtoDataMessageContactAvatar: NSObject {

    // MARK: - SNProtoDataMessageContactAvatarBuilder

    @objc public class func builder() -> SNProtoDataMessageContactAvatarBuilder {
        return SNProtoDataMessageContactAvatarBuilder()
    }

    // asBuilder() constructs a builder that reflects the proto's contents.
    @objc public func asBuilder() -> SNProtoDataMessageContactAvatarBuilder {
        let builder = SNProtoDataMessageContactAvatarBuilder()
        if let _value = avatar {
            builder.setAvatar(_value)
        }
        if hasIsProfile {
            builder.setIsProfile(isProfile)
        }
        return builder
    }

    @objc public class SNProtoDataMessageContactAvatarBuilder: NSObject {

        private var proto = SessionProtos_DataMessage.Contact.Avatar()

        @objc fileprivate override init() {}

        @objc public func setAvatar(_ valueParam: SNProtoAttachmentPointer) {
            proto.avatar = valueParam.proto
        }

        @objc public func setIsProfile(_ valueParam: Bool) {
            proto.isProfile = valueParam
        }

        @objc public func build() throws -> SNProtoDataMessageContactAvatar {
            return try SNProtoDataMessageContactAvatar.parseProto(proto)
        }

        @objc public func buildSerializedData() throws -> Data {
            return try SNProtoDataMessageContactAvatar.parseProto(proto).serializedData()
        }
    }

    fileprivate let proto: SessionProtos_DataMessage.Contact.Avatar

    @objc public let avatar: SNProtoAttachmentPointer?

    @objc public var isProfile: Bool {
        return proto.isProfile
    }
    @objc public var hasIsProfile: Bool {
        return proto.hasIsProfile
    }

    private init(proto: SessionProtos_DataMessage.Contact.Avatar,
                 avatar: SNProtoAttachmentPointer?) {
        self.proto = proto
        self.avatar = avatar
    }

    @objc
    public func serializedData() throws -> Data {
        return try self.proto.serializedData()
    }

    @objc public class func parseData(_ serializedData: Data) throws -> SNProtoDataMessageContactAvatar {
        let proto = try SessionProtos_DataMessage.Contact.Avatar(serializedData: serializedData)
        return try parseProto(proto)
    }

    fileprivate class func parseProto(_ proto: SessionProtos_DataMessage.Contact.Avatar) throws -> SNProtoDataMessageContactAvatar {
        var avatar: SNProtoAttachmentPointer? = nil
        if proto.hasAvatar {
            avatar = try SNProtoAttachmentPointer.parseProto(proto.avatar)
        }

        // MARK: - Begin Validation Logic for SNProtoDataMessageContactAvatar -

        // MARK: - End Validation Logic for SNProtoDataMessageContactAvatar -

        let result = SNProtoDataMessageContactAvatar(proto: proto,
                                                     avatar: avatar)
        return result
    }

    @objc public override var debugDescription: String {
        return "\(proto)"
    }
}

#if DEBUG

extension SNProtoDataMessageContactAvatar {
    @objc public func serializedDataIgnoringErrors() -> Data? {
        return try! self.serializedData()
    }
}

extension SNProtoDataMessageContactAvatar.SNProtoDataMessageContactAvatarBuilder {
    @objc public func buildIgnoringErrors() -> SNProtoDataMessageContactAvatar? {
        return try! self.build()
    }
}

#endif

// MARK: - SNProtoDataMessageContact

@objc public class SNProtoDataMessageContact: NSObject {

    // MARK: - SNProtoDataMessageContactBuilder

    @objc public class func builder() -> SNProtoDataMessageContactBuilder {
        return SNProtoDataMessageContactBuilder()
    }

    // asBuilder() constructs a builder that reflects the proto's contents.
    @objc public func asBuilder() -> SNProtoDataMessageContactBuilder {
        let builder = SNProtoDataMessageContactBuilder()
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

    @objc public class SNProtoDataMessageContactBuilder: NSObject {

        private var proto = SessionProtos_DataMessage.Contact()

        @objc fileprivate override init() {}

        @objc public func setName(_ valueParam: SNProtoDataMessageContactName) {
            proto.name = valueParam.proto
        }

        @objc public func addNumber(_ valueParam: SNProtoDataMessageContactPhone) {
            var items = proto.number
            items.append(valueParam.proto)
            proto.number = items
        }

        @objc public func setNumber(_ wrappedItems: [SNProtoDataMessageContactPhone]) {
            proto.number = wrappedItems.map { $0.proto }
        }

        @objc public func addEmail(_ valueParam: SNProtoDataMessageContactEmail) {
            var items = proto.email
            items.append(valueParam.proto)
            proto.email = items
        }

        @objc public func setEmail(_ wrappedItems: [SNProtoDataMessageContactEmail]) {
            proto.email = wrappedItems.map { $0.proto }
        }

        @objc public func addAddress(_ valueParam: SNProtoDataMessageContactPostalAddress) {
            var items = proto.address
            items.append(valueParam.proto)
            proto.address = items
        }

        @objc public func setAddress(_ wrappedItems: [SNProtoDataMessageContactPostalAddress]) {
            proto.address = wrappedItems.map { $0.proto }
        }

        @objc public func setAvatar(_ valueParam: SNProtoDataMessageContactAvatar) {
            proto.avatar = valueParam.proto
        }

        @objc public func setOrganization(_ valueParam: String) {
            proto.organization = valueParam
        }

        @objc public func build() throws -> SNProtoDataMessageContact {
            return try SNProtoDataMessageContact.parseProto(proto)
        }

        @objc public func buildSerializedData() throws -> Data {
            return try SNProtoDataMessageContact.parseProto(proto).serializedData()
        }
    }

    fileprivate let proto: SessionProtos_DataMessage.Contact

    @objc public let name: SNProtoDataMessageContactName?

    @objc public let number: [SNProtoDataMessageContactPhone]

    @objc public let email: [SNProtoDataMessageContactEmail]

    @objc public let address: [SNProtoDataMessageContactPostalAddress]

    @objc public let avatar: SNProtoDataMessageContactAvatar?

    @objc public var organization: String? {
        guard proto.hasOrganization else {
            return nil
        }
        return proto.organization
    }
    @objc public var hasOrganization: Bool {
        return proto.hasOrganization
    }

    private init(proto: SessionProtos_DataMessage.Contact,
                 name: SNProtoDataMessageContactName?,
                 number: [SNProtoDataMessageContactPhone],
                 email: [SNProtoDataMessageContactEmail],
                 address: [SNProtoDataMessageContactPostalAddress],
                 avatar: SNProtoDataMessageContactAvatar?) {
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

    @objc public class func parseData(_ serializedData: Data) throws -> SNProtoDataMessageContact {
        let proto = try SessionProtos_DataMessage.Contact(serializedData: serializedData)
        return try parseProto(proto)
    }

    fileprivate class func parseProto(_ proto: SessionProtos_DataMessage.Contact) throws -> SNProtoDataMessageContact {
        var name: SNProtoDataMessageContactName? = nil
        if proto.hasName {
            name = try SNProtoDataMessageContactName.parseProto(proto.name)
        }

        var number: [SNProtoDataMessageContactPhone] = []
        number = try proto.number.map { try SNProtoDataMessageContactPhone.parseProto($0) }

        var email: [SNProtoDataMessageContactEmail] = []
        email = try proto.email.map { try SNProtoDataMessageContactEmail.parseProto($0) }

        var address: [SNProtoDataMessageContactPostalAddress] = []
        address = try proto.address.map { try SNProtoDataMessageContactPostalAddress.parseProto($0) }

        var avatar: SNProtoDataMessageContactAvatar? = nil
        if proto.hasAvatar {
            avatar = try SNProtoDataMessageContactAvatar.parseProto(proto.avatar)
        }

        // MARK: - Begin Validation Logic for SNProtoDataMessageContact -

        // MARK: - End Validation Logic for SNProtoDataMessageContact -

        let result = SNProtoDataMessageContact(proto: proto,
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

extension SNProtoDataMessageContact {
    @objc public func serializedDataIgnoringErrors() -> Data? {
        return try! self.serializedData()
    }
}

extension SNProtoDataMessageContact.SNProtoDataMessageContactBuilder {
    @objc public func buildIgnoringErrors() -> SNProtoDataMessageContact? {
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

// MARK: - SNProtoDataMessageClosedGroupUpdateV2KeyPairWrapper

@objc public class SNProtoDataMessageClosedGroupUpdateV2KeyPairWrapper: NSObject {

    // MARK: - SNProtoDataMessageClosedGroupUpdateV2KeyPairWrapperBuilder

    @objc public class func builder(publicKey: Data, encryptedKeyPair: Data) -> SNProtoDataMessageClosedGroupUpdateV2KeyPairWrapperBuilder {
        return SNProtoDataMessageClosedGroupUpdateV2KeyPairWrapperBuilder(publicKey: publicKey, encryptedKeyPair: encryptedKeyPair)
    }

    // asBuilder() constructs a builder that reflects the proto's contents.
    @objc public func asBuilder() -> SNProtoDataMessageClosedGroupUpdateV2KeyPairWrapperBuilder {
        let builder = SNProtoDataMessageClosedGroupUpdateV2KeyPairWrapperBuilder(publicKey: publicKey, encryptedKeyPair: encryptedKeyPair)
        return builder
    }

    @objc public class SNProtoDataMessageClosedGroupUpdateV2KeyPairWrapperBuilder: NSObject {

        private var proto = SessionProtos_DataMessage.ClosedGroupUpdateV2.KeyPairWrapper()

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

        @objc public func build() throws -> SNProtoDataMessageClosedGroupUpdateV2KeyPairWrapper {
            return try SNProtoDataMessageClosedGroupUpdateV2KeyPairWrapper.parseProto(proto)
        }

        @objc public func buildSerializedData() throws -> Data {
            return try SNProtoDataMessageClosedGroupUpdateV2KeyPairWrapper.parseProto(proto).serializedData()
        }
    }

    fileprivate let proto: SessionProtos_DataMessage.ClosedGroupUpdateV2.KeyPairWrapper

    @objc public let publicKey: Data

    @objc public let encryptedKeyPair: Data

    private init(proto: SessionProtos_DataMessage.ClosedGroupUpdateV2.KeyPairWrapper,
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

    @objc public class func parseData(_ serializedData: Data) throws -> SNProtoDataMessageClosedGroupUpdateV2KeyPairWrapper {
        let proto = try SessionProtos_DataMessage.ClosedGroupUpdateV2.KeyPairWrapper(serializedData: serializedData)
        return try parseProto(proto)
    }

    fileprivate class func parseProto(_ proto: SessionProtos_DataMessage.ClosedGroupUpdateV2.KeyPairWrapper) throws -> SNProtoDataMessageClosedGroupUpdateV2KeyPairWrapper {
        guard proto.hasPublicKey else {
            throw SNProtoError.invalidProtobuf(description: "\(logTag) missing required field: publicKey")
        }
        let publicKey = proto.publicKey

        guard proto.hasEncryptedKeyPair else {
            throw SNProtoError.invalidProtobuf(description: "\(logTag) missing required field: encryptedKeyPair")
        }
        let encryptedKeyPair = proto.encryptedKeyPair

        // MARK: - Begin Validation Logic for SNProtoDataMessageClosedGroupUpdateV2KeyPairWrapper -

        // MARK: - End Validation Logic for SNProtoDataMessageClosedGroupUpdateV2KeyPairWrapper -

        let result = SNProtoDataMessageClosedGroupUpdateV2KeyPairWrapper(proto: proto,
                                                                         publicKey: publicKey,
                                                                         encryptedKeyPair: encryptedKeyPair)
        return result
    }

    @objc public override var debugDescription: String {
        return "\(proto)"
    }
}

#if DEBUG

extension SNProtoDataMessageClosedGroupUpdateV2KeyPairWrapper {
    @objc public func serializedDataIgnoringErrors() -> Data? {
        return try! self.serializedData()
    }
}

extension SNProtoDataMessageClosedGroupUpdateV2KeyPairWrapper.SNProtoDataMessageClosedGroupUpdateV2KeyPairWrapperBuilder {
    @objc public func buildIgnoringErrors() -> SNProtoDataMessageClosedGroupUpdateV2KeyPairWrapper? {
        return try! self.build()
    }
}

#endif

// MARK: - SNProtoDataMessageClosedGroupUpdateV2

@objc public class SNProtoDataMessageClosedGroupUpdateV2: NSObject {

    // MARK: - SNProtoDataMessageClosedGroupUpdateV2Type

    @objc public enum SNProtoDataMessageClosedGroupUpdateV2Type: Int32 {
        case new = 1
        case update = 2
        case encryptionKeyPair = 3
    }

    private class func SNProtoDataMessageClosedGroupUpdateV2TypeWrap(_ value: SessionProtos_DataMessage.ClosedGroupUpdateV2.TypeEnum) -> SNProtoDataMessageClosedGroupUpdateV2Type {
        switch value {
        case .new: return .new
        case .update: return .update
        case .encryptionKeyPair: return .encryptionKeyPair
        }
    }

    private class func SNProtoDataMessageClosedGroupUpdateV2TypeUnwrap(_ value: SNProtoDataMessageClosedGroupUpdateV2Type) -> SessionProtos_DataMessage.ClosedGroupUpdateV2.TypeEnum {
        switch value {
        case .new: return .new
        case .update: return .update
        case .encryptionKeyPair: return .encryptionKeyPair
        }
    }

    // MARK: - SNProtoDataMessageClosedGroupUpdateV2Builder

    @objc public class func builder(type: SNProtoDataMessageClosedGroupUpdateV2Type) -> SNProtoDataMessageClosedGroupUpdateV2Builder {
        return SNProtoDataMessageClosedGroupUpdateV2Builder(type: type)
    }

    // asBuilder() constructs a builder that reflects the proto's contents.
    @objc public func asBuilder() -> SNProtoDataMessageClosedGroupUpdateV2Builder {
        let builder = SNProtoDataMessageClosedGroupUpdateV2Builder(type: type)
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
        return builder
    }

    @objc public class SNProtoDataMessageClosedGroupUpdateV2Builder: NSObject {

        private var proto = SessionProtos_DataMessage.ClosedGroupUpdateV2()

        @objc fileprivate override init() {}

        @objc fileprivate init(type: SNProtoDataMessageClosedGroupUpdateV2Type) {
            super.init()

            setType(type)
        }

        @objc public func setType(_ valueParam: SNProtoDataMessageClosedGroupUpdateV2Type) {
            proto.type = SNProtoDataMessageClosedGroupUpdateV2TypeUnwrap(valueParam)
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

        @objc public func addWrappers(_ valueParam: SNProtoDataMessageClosedGroupUpdateV2KeyPairWrapper) {
            var items = proto.wrappers
            items.append(valueParam.proto)
            proto.wrappers = items
        }

        @objc public func setWrappers(_ wrappedItems: [SNProtoDataMessageClosedGroupUpdateV2KeyPairWrapper]) {
            proto.wrappers = wrappedItems.map { $0.proto }
        }

        @objc public func build() throws -> SNProtoDataMessageClosedGroupUpdateV2 {
            return try SNProtoDataMessageClosedGroupUpdateV2.parseProto(proto)
        }

        @objc public func buildSerializedData() throws -> Data {
            return try SNProtoDataMessageClosedGroupUpdateV2.parseProto(proto).serializedData()
        }
    }

    fileprivate let proto: SessionProtos_DataMessage.ClosedGroupUpdateV2

    @objc public let type: SNProtoDataMessageClosedGroupUpdateV2Type

    @objc public let encryptionKeyPair: SNProtoKeyPair?

    @objc public let wrappers: [SNProtoDataMessageClosedGroupUpdateV2KeyPairWrapper]

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

    private init(proto: SessionProtos_DataMessage.ClosedGroupUpdateV2,
                 type: SNProtoDataMessageClosedGroupUpdateV2Type,
                 encryptionKeyPair: SNProtoKeyPair?,
                 wrappers: [SNProtoDataMessageClosedGroupUpdateV2KeyPairWrapper]) {
        self.proto = proto
        self.type = type
        self.encryptionKeyPair = encryptionKeyPair
        self.wrappers = wrappers
    }

    @objc
    public func serializedData() throws -> Data {
        return try self.proto.serializedData()
    }

    @objc public class func parseData(_ serializedData: Data) throws -> SNProtoDataMessageClosedGroupUpdateV2 {
        let proto = try SessionProtos_DataMessage.ClosedGroupUpdateV2(serializedData: serializedData)
        return try parseProto(proto)
    }

    fileprivate class func parseProto(_ proto: SessionProtos_DataMessage.ClosedGroupUpdateV2) throws -> SNProtoDataMessageClosedGroupUpdateV2 {
        guard proto.hasType else {
            throw SNProtoError.invalidProtobuf(description: "\(logTag) missing required field: type")
        }
        let type = SNProtoDataMessageClosedGroupUpdateV2TypeWrap(proto.type)

        var encryptionKeyPair: SNProtoKeyPair? = nil
        if proto.hasEncryptionKeyPair {
            encryptionKeyPair = try SNProtoKeyPair.parseProto(proto.encryptionKeyPair)
        }

        var wrappers: [SNProtoDataMessageClosedGroupUpdateV2KeyPairWrapper] = []
        wrappers = try proto.wrappers.map { try SNProtoDataMessageClosedGroupUpdateV2KeyPairWrapper.parseProto($0) }

        // MARK: - Begin Validation Logic for SNProtoDataMessageClosedGroupUpdateV2 -

        // MARK: - End Validation Logic for SNProtoDataMessageClosedGroupUpdateV2 -

        let result = SNProtoDataMessageClosedGroupUpdateV2(proto: proto,
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

extension SNProtoDataMessageClosedGroupUpdateV2 {
    @objc public func serializedDataIgnoringErrors() -> Data? {
        return try! self.serializedData()
    }
}

extension SNProtoDataMessageClosedGroupUpdateV2.SNProtoDataMessageClosedGroupUpdateV2Builder {
    @objc public func buildIgnoringErrors() -> SNProtoDataMessageClosedGroupUpdateV2? {
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
        builder.setContact(contact)
        builder.setPreview(preview)
        if let _value = profile {
            builder.setProfile(_value)
        }
        if let _value = closedGroupUpdateV2 {
            builder.setClosedGroupUpdateV2(_value)
        }
        if let _value = publicChatInfo {
            builder.setPublicChatInfo(_value)
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

        @objc public func addContact(_ valueParam: SNProtoDataMessageContact) {
            var items = proto.contact
            items.append(valueParam.proto)
            proto.contact = items
        }

        @objc public func setContact(_ wrappedItems: [SNProtoDataMessageContact]) {
            proto.contact = wrappedItems.map { $0.proto }
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

        @objc public func setClosedGroupUpdateV2(_ valueParam: SNProtoDataMessageClosedGroupUpdateV2) {
            proto.closedGroupUpdateV2 = valueParam.proto
        }

        @objc public func setPublicChatInfo(_ valueParam: SNProtoPublicChatInfo) {
            proto.publicChatInfo = valueParam.proto
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

    @objc public let contact: [SNProtoDataMessageContact]

    @objc public let preview: [SNProtoDataMessagePreview]

    @objc public let profile: SNProtoDataMessageLokiProfile?

    @objc public let closedGroupUpdateV2: SNProtoDataMessageClosedGroupUpdateV2?

    @objc public let publicChatInfo: SNProtoPublicChatInfo?

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

    private init(proto: SessionProtos_DataMessage,
                 attachments: [SNProtoAttachmentPointer],
                 group: SNProtoGroupContext?,
                 quote: SNProtoDataMessageQuote?,
                 contact: [SNProtoDataMessageContact],
                 preview: [SNProtoDataMessagePreview],
                 profile: SNProtoDataMessageLokiProfile?,
                 closedGroupUpdateV2: SNProtoDataMessageClosedGroupUpdateV2?,
                 publicChatInfo: SNProtoPublicChatInfo?) {
        self.proto = proto
        self.attachments = attachments
        self.group = group
        self.quote = quote
        self.contact = contact
        self.preview = preview
        self.profile = profile
        self.closedGroupUpdateV2 = closedGroupUpdateV2
        self.publicChatInfo = publicChatInfo
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

        var contact: [SNProtoDataMessageContact] = []
        contact = try proto.contact.map { try SNProtoDataMessageContact.parseProto($0) }

        var preview: [SNProtoDataMessagePreview] = []
        preview = try proto.preview.map { try SNProtoDataMessagePreview.parseProto($0) }

        var profile: SNProtoDataMessageLokiProfile? = nil
        if proto.hasProfile {
            profile = try SNProtoDataMessageLokiProfile.parseProto(proto.profile)
        }

        var closedGroupUpdateV2: SNProtoDataMessageClosedGroupUpdateV2? = nil
        if proto.hasClosedGroupUpdateV2 {
            closedGroupUpdateV2 = try SNProtoDataMessageClosedGroupUpdateV2.parseProto(proto.closedGroupUpdateV2)
        }

        var publicChatInfo: SNProtoPublicChatInfo? = nil
        if proto.hasPublicChatInfo {
            publicChatInfo = try SNProtoPublicChatInfo.parseProto(proto.publicChatInfo)
        }

        // MARK: - Begin Validation Logic for SNProtoDataMessage -

        // MARK: - End Validation Logic for SNProtoDataMessage -

        let result = SNProtoDataMessage(proto: proto,
                                        attachments: attachments,
                                        group: group,
                                        quote: quote,
                                        contact: contact,
                                        preview: preview,
                                        profile: profile,
                                        closedGroupUpdateV2: closedGroupUpdateV2,
                                        publicChatInfo: publicChatInfo)
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

        @objc public func build() throws -> SNProtoConfigurationMessage {
            return try SNProtoConfigurationMessage.parseProto(proto)
        }

        @objc public func buildSerializedData() throws -> Data {
            return try SNProtoConfigurationMessage.parseProto(proto).serializedData()
        }
    }

    fileprivate let proto: SessionProtos_ConfigurationMessage

    @objc public let closedGroups: [SNProtoConfigurationMessageClosedGroup]

    @objc public var openGroups: [String] {
        return proto.openGroups
    }

    private init(proto: SessionProtos_ConfigurationMessage,
                 closedGroups: [SNProtoConfigurationMessageClosedGroup]) {
        self.proto = proto
        self.closedGroups = closedGroups
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

        // MARK: - Begin Validation Logic for SNProtoConfigurationMessage -

        // MARK: - End Validation Logic for SNProtoConfigurationMessage -

        let result = SNProtoConfigurationMessage(proto: proto,
                                                 closedGroups: closedGroups)
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

// MARK: - SNProtoSyncMessageSent

@objc public class SNProtoSyncMessageSent: NSObject {

    // MARK: - SNProtoSyncMessageSentBuilder

    @objc public class func builder() -> SNProtoSyncMessageSentBuilder {
        return SNProtoSyncMessageSentBuilder()
    }

    // asBuilder() constructs a builder that reflects the proto's contents.
    @objc public func asBuilder() -> SNProtoSyncMessageSentBuilder {
        let builder = SNProtoSyncMessageSentBuilder()
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
        if hasIsRecipientUpdate {
            builder.setIsRecipientUpdate(isRecipientUpdate)
        }
        return builder
    }

    @objc public class SNProtoSyncMessageSentBuilder: NSObject {

        private var proto = SessionProtos_SyncMessage.Sent()

        @objc fileprivate override init() {}

        @objc public func setDestination(_ valueParam: String) {
            proto.destination = valueParam
        }

        @objc public func setTimestamp(_ valueParam: UInt64) {
            proto.timestamp = valueParam
        }

        @objc public func setMessage(_ valueParam: SNProtoDataMessage) {
            proto.message = valueParam.proto
        }

        @objc public func setExpirationStartTimestamp(_ valueParam: UInt64) {
            proto.expirationStartTimestamp = valueParam
        }

        @objc public func setIsRecipientUpdate(_ valueParam: Bool) {
            proto.isRecipientUpdate = valueParam
        }

        @objc public func build() throws -> SNProtoSyncMessageSent {
            return try SNProtoSyncMessageSent.parseProto(proto)
        }

        @objc public func buildSerializedData() throws -> Data {
            return try SNProtoSyncMessageSent.parseProto(proto).serializedData()
        }
    }

    fileprivate let proto: SessionProtos_SyncMessage.Sent

    @objc public let message: SNProtoDataMessage?

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

    private init(proto: SessionProtos_SyncMessage.Sent,
                 message: SNProtoDataMessage?) {
        self.proto = proto
        self.message = message
    }

    @objc
    public func serializedData() throws -> Data {
        return try self.proto.serializedData()
    }

    @objc public class func parseData(_ serializedData: Data) throws -> SNProtoSyncMessageSent {
        let proto = try SessionProtos_SyncMessage.Sent(serializedData: serializedData)
        return try parseProto(proto)
    }

    fileprivate class func parseProto(_ proto: SessionProtos_SyncMessage.Sent) throws -> SNProtoSyncMessageSent {
        var message: SNProtoDataMessage? = nil
        if proto.hasMessage {
            message = try SNProtoDataMessage.parseProto(proto.message)
        }

        // MARK: - Begin Validation Logic for SNProtoSyncMessageSent -

        // MARK: - End Validation Logic for SNProtoSyncMessageSent -

        let result = SNProtoSyncMessageSent(proto: proto,
                                            message: message)
        return result
    }

    @objc public override var debugDescription: String {
        return "\(proto)"
    }
}

#if DEBUG

extension SNProtoSyncMessageSent {
    @objc public func serializedDataIgnoringErrors() -> Data? {
        return try! self.serializedData()
    }
}

extension SNProtoSyncMessageSent.SNProtoSyncMessageSentBuilder {
    @objc public func buildIgnoringErrors() -> SNProtoSyncMessageSent? {
        return try! self.build()
    }
}

#endif

// MARK: - SNProtoSyncMessage

@objc public class SNProtoSyncMessage: NSObject {

    // MARK: - SNProtoSyncMessageBuilder

    @objc public class func builder() -> SNProtoSyncMessageBuilder {
        return SNProtoSyncMessageBuilder()
    }

    // asBuilder() constructs a builder that reflects the proto's contents.
    @objc public func asBuilder() -> SNProtoSyncMessageBuilder {
        let builder = SNProtoSyncMessageBuilder()
        if let _value = sent {
            builder.setSent(_value)
        }
        if let _value = padding {
            builder.setPadding(_value)
        }
        return builder
    }

    @objc public class SNProtoSyncMessageBuilder: NSObject {

        private var proto = SessionProtos_SyncMessage()

        @objc fileprivate override init() {}

        @objc public func setSent(_ valueParam: SNProtoSyncMessageSent) {
            proto.sent = valueParam.proto
        }

        @objc public func setPadding(_ valueParam: Data) {
            proto.padding = valueParam
        }

        @objc public func build() throws -> SNProtoSyncMessage {
            return try SNProtoSyncMessage.parseProto(proto)
        }

        @objc public func buildSerializedData() throws -> Data {
            return try SNProtoSyncMessage.parseProto(proto).serializedData()
        }
    }

    fileprivate let proto: SessionProtos_SyncMessage

    @objc public let sent: SNProtoSyncMessageSent?

    @objc public var padding: Data? {
        guard proto.hasPadding else {
            return nil
        }
        return proto.padding
    }
    @objc public var hasPadding: Bool {
        return proto.hasPadding
    }

    private init(proto: SessionProtos_SyncMessage,
                 sent: SNProtoSyncMessageSent?) {
        self.proto = proto
        self.sent = sent
    }

    @objc
    public func serializedData() throws -> Data {
        return try self.proto.serializedData()
    }

    @objc public class func parseData(_ serializedData: Data) throws -> SNProtoSyncMessage {
        let proto = try SessionProtos_SyncMessage(serializedData: serializedData)
        return try parseProto(proto)
    }

    fileprivate class func parseProto(_ proto: SessionProtos_SyncMessage) throws -> SNProtoSyncMessage {
        var sent: SNProtoSyncMessageSent? = nil
        if proto.hasSent {
            sent = try SNProtoSyncMessageSent.parseProto(proto.sent)
        }

        // MARK: - Begin Validation Logic for SNProtoSyncMessage -

        // MARK: - End Validation Logic for SNProtoSyncMessage -

        let result = SNProtoSyncMessage(proto: proto,
                                        sent: sent)
        return result
    }

    @objc public override var debugDescription: String {
        return "\(proto)"
    }
}

#if DEBUG

extension SNProtoSyncMessage {
    @objc public func serializedDataIgnoringErrors() -> Data? {
        return try! self.serializedData()
    }
}

extension SNProtoSyncMessage.SNProtoSyncMessageBuilder {
    @objc public func buildIgnoringErrors() -> SNProtoSyncMessage? {
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

// MARK: - SNProtoContactDetailsAvatar

@objc public class SNProtoContactDetailsAvatar: NSObject {

    // MARK: - SNProtoContactDetailsAvatarBuilder

    @objc public class func builder() -> SNProtoContactDetailsAvatarBuilder {
        return SNProtoContactDetailsAvatarBuilder()
    }

    // asBuilder() constructs a builder that reflects the proto's contents.
    @objc public func asBuilder() -> SNProtoContactDetailsAvatarBuilder {
        let builder = SNProtoContactDetailsAvatarBuilder()
        if let _value = contentType {
            builder.setContentType(_value)
        }
        if hasLength {
            builder.setLength(length)
        }
        return builder
    }

    @objc public class SNProtoContactDetailsAvatarBuilder: NSObject {

        private var proto = SessionProtos_ContactDetails.Avatar()

        @objc fileprivate override init() {}

        @objc public func setContentType(_ valueParam: String) {
            proto.contentType = valueParam
        }

        @objc public func setLength(_ valueParam: UInt32) {
            proto.length = valueParam
        }

        @objc public func build() throws -> SNProtoContactDetailsAvatar {
            return try SNProtoContactDetailsAvatar.parseProto(proto)
        }

        @objc public func buildSerializedData() throws -> Data {
            return try SNProtoContactDetailsAvatar.parseProto(proto).serializedData()
        }
    }

    fileprivate let proto: SessionProtos_ContactDetails.Avatar

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

    private init(proto: SessionProtos_ContactDetails.Avatar) {
        self.proto = proto
    }

    @objc
    public func serializedData() throws -> Data {
        return try self.proto.serializedData()
    }

    @objc public class func parseData(_ serializedData: Data) throws -> SNProtoContactDetailsAvatar {
        let proto = try SessionProtos_ContactDetails.Avatar(serializedData: serializedData)
        return try parseProto(proto)
    }

    fileprivate class func parseProto(_ proto: SessionProtos_ContactDetails.Avatar) throws -> SNProtoContactDetailsAvatar {
        // MARK: - Begin Validation Logic for SNProtoContactDetailsAvatar -

        // MARK: - End Validation Logic for SNProtoContactDetailsAvatar -

        let result = SNProtoContactDetailsAvatar(proto: proto)
        return result
    }

    @objc public override var debugDescription: String {
        return "\(proto)"
    }
}

#if DEBUG

extension SNProtoContactDetailsAvatar {
    @objc public func serializedDataIgnoringErrors() -> Data? {
        return try! self.serializedData()
    }
}

extension SNProtoContactDetailsAvatar.SNProtoContactDetailsAvatarBuilder {
    @objc public func buildIgnoringErrors() -> SNProtoContactDetailsAvatar? {
        return try! self.build()
    }
}

#endif

// MARK: - SNProtoContactDetails

@objc public class SNProtoContactDetails: NSObject {

    // MARK: - SNProtoContactDetailsBuilder

    @objc public class func builder(number: String) -> SNProtoContactDetailsBuilder {
        return SNProtoContactDetailsBuilder(number: number)
    }

    // asBuilder() constructs a builder that reflects the proto's contents.
    @objc public func asBuilder() -> SNProtoContactDetailsBuilder {
        let builder = SNProtoContactDetailsBuilder(number: number)
        if let _value = name {
            builder.setName(_value)
        }
        if let _value = avatar {
            builder.setAvatar(_value)
        }
        if let _value = color {
            builder.setColor(_value)
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
        if let _value = nickname {
            builder.setNickname(_value)
        }
        return builder
    }

    @objc public class SNProtoContactDetailsBuilder: NSObject {

        private var proto = SessionProtos_ContactDetails()

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

        @objc public func setAvatar(_ valueParam: SNProtoContactDetailsAvatar) {
            proto.avatar = valueParam.proto
        }

        @objc public func setColor(_ valueParam: String) {
            proto.color = valueParam
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

        @objc public func setNickname(_ valueParam: String) {
            proto.nickname = valueParam
        }

        @objc public func build() throws -> SNProtoContactDetails {
            return try SNProtoContactDetails.parseProto(proto)
        }

        @objc public func buildSerializedData() throws -> Data {
            return try SNProtoContactDetails.parseProto(proto).serializedData()
        }
    }

    fileprivate let proto: SessionProtos_ContactDetails

    @objc public let number: String

    @objc public let avatar: SNProtoContactDetailsAvatar?

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

    @objc public var nickname: String? {
        guard proto.hasNickname else {
            return nil
        }
        return proto.nickname
    }
    @objc public var hasNickname: Bool {
        return proto.hasNickname
    }

    private init(proto: SessionProtos_ContactDetails,
                 number: String,
                 avatar: SNProtoContactDetailsAvatar?) {
        self.proto = proto
        self.number = number
        self.avatar = avatar
    }

    @objc
    public func serializedData() throws -> Data {
        return try self.proto.serializedData()
    }

    @objc public class func parseData(_ serializedData: Data) throws -> SNProtoContactDetails {
        let proto = try SessionProtos_ContactDetails(serializedData: serializedData)
        return try parseProto(proto)
    }

    fileprivate class func parseProto(_ proto: SessionProtos_ContactDetails) throws -> SNProtoContactDetails {
        guard proto.hasNumber else {
            throw SNProtoError.invalidProtobuf(description: "\(logTag) missing required field: number")
        }
        let number = proto.number

        var avatar: SNProtoContactDetailsAvatar? = nil
        if proto.hasAvatar {
            avatar = try SNProtoContactDetailsAvatar.parseProto(proto.avatar)
        }

        // MARK: - Begin Validation Logic for SNProtoContactDetails -

        // MARK: - End Validation Logic for SNProtoContactDetails -

        let result = SNProtoContactDetails(proto: proto,
                                           number: number,
                                           avatar: avatar)
        return result
    }

    @objc public override var debugDescription: String {
        return "\(proto)"
    }
}

#if DEBUG

extension SNProtoContactDetails {
    @objc public func serializedDataIgnoringErrors() -> Data? {
        return try! self.serializedData()
    }
}

extension SNProtoContactDetails.SNProtoContactDetailsBuilder {
    @objc public func buildIgnoringErrors() -> SNProtoContactDetails? {
        return try! self.build()
    }
}

#endif

// MARK: - SNProtoGroupDetailsAvatar

@objc public class SNProtoGroupDetailsAvatar: NSObject {

    // MARK: - SNProtoGroupDetailsAvatarBuilder

    @objc public class func builder() -> SNProtoGroupDetailsAvatarBuilder {
        return SNProtoGroupDetailsAvatarBuilder()
    }

    // asBuilder() constructs a builder that reflects the proto's contents.
    @objc public func asBuilder() -> SNProtoGroupDetailsAvatarBuilder {
        let builder = SNProtoGroupDetailsAvatarBuilder()
        if let _value = contentType {
            builder.setContentType(_value)
        }
        if hasLength {
            builder.setLength(length)
        }
        return builder
    }

    @objc public class SNProtoGroupDetailsAvatarBuilder: NSObject {

        private var proto = SessionProtos_GroupDetails.Avatar()

        @objc fileprivate override init() {}

        @objc public func setContentType(_ valueParam: String) {
            proto.contentType = valueParam
        }

        @objc public func setLength(_ valueParam: UInt32) {
            proto.length = valueParam
        }

        @objc public func build() throws -> SNProtoGroupDetailsAvatar {
            return try SNProtoGroupDetailsAvatar.parseProto(proto)
        }

        @objc public func buildSerializedData() throws -> Data {
            return try SNProtoGroupDetailsAvatar.parseProto(proto).serializedData()
        }
    }

    fileprivate let proto: SessionProtos_GroupDetails.Avatar

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

    private init(proto: SessionProtos_GroupDetails.Avatar) {
        self.proto = proto
    }

    @objc
    public func serializedData() throws -> Data {
        return try self.proto.serializedData()
    }

    @objc public class func parseData(_ serializedData: Data) throws -> SNProtoGroupDetailsAvatar {
        let proto = try SessionProtos_GroupDetails.Avatar(serializedData: serializedData)
        return try parseProto(proto)
    }

    fileprivate class func parseProto(_ proto: SessionProtos_GroupDetails.Avatar) throws -> SNProtoGroupDetailsAvatar {
        // MARK: - Begin Validation Logic for SNProtoGroupDetailsAvatar -

        // MARK: - End Validation Logic for SNProtoGroupDetailsAvatar -

        let result = SNProtoGroupDetailsAvatar(proto: proto)
        return result
    }

    @objc public override var debugDescription: String {
        return "\(proto)"
    }
}

#if DEBUG

extension SNProtoGroupDetailsAvatar {
    @objc public func serializedDataIgnoringErrors() -> Data? {
        return try! self.serializedData()
    }
}

extension SNProtoGroupDetailsAvatar.SNProtoGroupDetailsAvatarBuilder {
    @objc public func buildIgnoringErrors() -> SNProtoGroupDetailsAvatar? {
        return try! self.build()
    }
}

#endif

// MARK: - SNProtoGroupDetails

@objc public class SNProtoGroupDetails: NSObject {

    // MARK: - SNProtoGroupDetailsBuilder

    @objc public class func builder(id: Data) -> SNProtoGroupDetailsBuilder {
        return SNProtoGroupDetailsBuilder(id: id)
    }

    // asBuilder() constructs a builder that reflects the proto's contents.
    @objc public func asBuilder() -> SNProtoGroupDetailsBuilder {
        let builder = SNProtoGroupDetailsBuilder(id: id)
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
        builder.setAdmins(admins)
        return builder
    }

    @objc public class SNProtoGroupDetailsBuilder: NSObject {

        private var proto = SessionProtos_GroupDetails()

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

        @objc public func setAvatar(_ valueParam: SNProtoGroupDetailsAvatar) {
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

        @objc public func addAdmins(_ valueParam: String) {
            var items = proto.admins
            items.append(valueParam)
            proto.admins = items
        }

        @objc public func setAdmins(_ wrappedItems: [String]) {
            proto.admins = wrappedItems
        }

        @objc public func build() throws -> SNProtoGroupDetails {
            return try SNProtoGroupDetails.parseProto(proto)
        }

        @objc public func buildSerializedData() throws -> Data {
            return try SNProtoGroupDetails.parseProto(proto).serializedData()
        }
    }

    fileprivate let proto: SessionProtos_GroupDetails

    @objc public let id: Data

    @objc public let avatar: SNProtoGroupDetailsAvatar?

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

    @objc public var admins: [String] {
        return proto.admins
    }

    private init(proto: SessionProtos_GroupDetails,
                 id: Data,
                 avatar: SNProtoGroupDetailsAvatar?) {
        self.proto = proto
        self.id = id
        self.avatar = avatar
    }

    @objc
    public func serializedData() throws -> Data {
        return try self.proto.serializedData()
    }

    @objc public class func parseData(_ serializedData: Data) throws -> SNProtoGroupDetails {
        let proto = try SessionProtos_GroupDetails(serializedData: serializedData)
        return try parseProto(proto)
    }

    fileprivate class func parseProto(_ proto: SessionProtos_GroupDetails) throws -> SNProtoGroupDetails {
        guard proto.hasID else {
            throw SNProtoError.invalidProtobuf(description: "\(logTag) missing required field: id")
        }
        let id = proto.id

        var avatar: SNProtoGroupDetailsAvatar? = nil
        if proto.hasAvatar {
            avatar = try SNProtoGroupDetailsAvatar.parseProto(proto.avatar)
        }

        // MARK: - Begin Validation Logic for SNProtoGroupDetails -

        // MARK: - End Validation Logic for SNProtoGroupDetails -

        let result = SNProtoGroupDetails(proto: proto,
                                         id: id,
                                         avatar: avatar)
        return result
    }

    @objc public override var debugDescription: String {
        return "\(proto)"
    }
}

#if DEBUG

extension SNProtoGroupDetails {
    @objc public func serializedDataIgnoringErrors() -> Data? {
        return try! self.serializedData()
    }
}

extension SNProtoGroupDetails.SNProtoGroupDetailsBuilder {
    @objc public func buildIgnoringErrors() -> SNProtoGroupDetails? {
        return try! self.build()
    }
}

#endif

// MARK: - SNProtoPublicChatInfo

@objc public class SNProtoPublicChatInfo: NSObject {

    // MARK: - SNProtoPublicChatInfoBuilder

    @objc public class func builder() -> SNProtoPublicChatInfoBuilder {
        return SNProtoPublicChatInfoBuilder()
    }

    // asBuilder() constructs a builder that reflects the proto's contents.
    @objc public func asBuilder() -> SNProtoPublicChatInfoBuilder {
        let builder = SNProtoPublicChatInfoBuilder()
        if hasServerID {
            builder.setServerID(serverID)
        }
        return builder
    }

    @objc public class SNProtoPublicChatInfoBuilder: NSObject {

        private var proto = SessionProtos_PublicChatInfo()

        @objc fileprivate override init() {}

        @objc public func setServerID(_ valueParam: UInt64) {
            proto.serverID = valueParam
        }

        @objc public func build() throws -> SNProtoPublicChatInfo {
            return try SNProtoPublicChatInfo.parseProto(proto)
        }

        @objc public func buildSerializedData() throws -> Data {
            return try SNProtoPublicChatInfo.parseProto(proto).serializedData()
        }
    }

    fileprivate let proto: SessionProtos_PublicChatInfo

    @objc public var serverID: UInt64 {
        return proto.serverID
    }
    @objc public var hasServerID: Bool {
        return proto.hasServerID
    }

    private init(proto: SessionProtos_PublicChatInfo) {
        self.proto = proto
    }

    @objc
    public func serializedData() throws -> Data {
        return try self.proto.serializedData()
    }

    @objc public class func parseData(_ serializedData: Data) throws -> SNProtoPublicChatInfo {
        let proto = try SessionProtos_PublicChatInfo(serializedData: serializedData)
        return try parseProto(proto)
    }

    fileprivate class func parseProto(_ proto: SessionProtos_PublicChatInfo) throws -> SNProtoPublicChatInfo {
        // MARK: - Begin Validation Logic for SNProtoPublicChatInfo -

        // MARK: - End Validation Logic for SNProtoPublicChatInfo -

        let result = SNProtoPublicChatInfo(proto: proto)
        return result
    }

    @objc public override var debugDescription: String {
        return "\(proto)"
    }
}

#if DEBUG

extension SNProtoPublicChatInfo {
    @objc public func serializedDataIgnoringErrors() -> Data? {
        return try! self.serializedData()
    }
}

extension SNProtoPublicChatInfo.SNProtoPublicChatInfoBuilder {
    @objc public func buildIgnoringErrors() -> SNProtoPublicChatInfo? {
        return try! self.build()
    }
}

#endif
