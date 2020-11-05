//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

import Foundation

// WARNING: This code is generated. Only edit within the markers.

private let logTag = "SNProto"

public enum SNProtoError: Error {
    case invalidProtobuf(description: String)
}

// MARK: - SNProtoEnvelope

@objc public class SNProtoEnvelope: NSObject {

    // MARK: - SNProtoEnvelopeType

    @objc public enum SNProtoEnvelopeType: Int32 {
        case unknown = 0
        case ciphertext = 1
        case keyExchange = 2
        case prekeyBundle = 3
        case receipt = 5
        case unidentifiedSender = 6
        case closedGroupCiphertext = 7
        case fallbackMessage = 101
    }

    private class func SNProtoEnvelopeTypeWrap(_ value: SessionProtos_Envelope.TypeEnum) -> SNProtoEnvelopeType {
        switch value {
        case .unknown: return .unknown
        case .ciphertext: return .ciphertext
        case .keyExchange: return .keyExchange
        case .prekeyBundle: return .prekeyBundle
        case .receipt: return .receipt
        case .unidentifiedSender: return .unidentifiedSender
        case .closedGroupCiphertext: return .closedGroupCiphertext
        case .fallbackMessage: return .fallbackMessage
        }
    }

    private class func SNProtoEnvelopeTypeUnwrap(_ value: SNProtoEnvelopeType) -> SessionProtos_Envelope.TypeEnum {
        switch value {
        case .unknown: return .unknown
        case .ciphertext: return .ciphertext
        case .keyExchange: return .keyExchange
        case .prekeyBundle: return .prekeyBundle
        case .receipt: return .receipt
        case .unidentifiedSender: return .unidentifiedSender
        case .closedGroupCiphertext: return .closedGroupCiphertext
        case .fallbackMessage: return .fallbackMessage
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
        if let _value = groupID {
            builder.setGroupID(_value)
        }
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

        @objc public func setGroupID(_ valueParam: Data) {
            proto.groupID = valueParam
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

    @objc public var groupID: Data? {
        guard proto.hasGroupID else {
            return nil
        }
        return proto.groupID
    }
    @objc public var hasGroupID: Bool {
        return proto.hasGroupID
    }

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
        if let _value = prekeyBundleMessage {
            builder.setPrekeyBundleMessage(_value)
        }
        if let _value = lokiDeviceLinkMessage {
            builder.setLokiDeviceLinkMessage(_value)
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

        @objc public func setCallMessage(_ valueParam: SNProtoCallMessage) {
            proto.callMessage = valueParam.proto
        }

        @objc public func setNullMessage(_ valueParam: SNProtoNullMessage) {
            proto.nullMessage = valueParam.proto
        }

        @objc public func setReceiptMessage(_ valueParam: SNProtoReceiptMessage) {
            proto.receiptMessage = valueParam.proto
        }

        @objc public func setTypingMessage(_ valueParam: SNProtoTypingMessage) {
            proto.typingMessage = valueParam.proto
        }

        @objc public func setPrekeyBundleMessage(_ valueParam: SNProtoPrekeyBundleMessage) {
            proto.prekeyBundleMessage = valueParam.proto
        }

        @objc public func setLokiDeviceLinkMessage(_ valueParam: SNProtoLokiDeviceLinkMessage) {
            proto.lokiDeviceLinkMessage = valueParam.proto
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

    @objc public let callMessage: SNProtoCallMessage?

    @objc public let nullMessage: SNProtoNullMessage?

    @objc public let receiptMessage: SNProtoReceiptMessage?

    @objc public let typingMessage: SNProtoTypingMessage?

    @objc public let prekeyBundleMessage: SNProtoPrekeyBundleMessage?

    @objc public let lokiDeviceLinkMessage: SNProtoLokiDeviceLinkMessage?

    private init(proto: SessionProtos_Content,
                 dataMessage: SNProtoDataMessage?,
                 syncMessage: SNProtoSyncMessage?,
                 callMessage: SNProtoCallMessage?,
                 nullMessage: SNProtoNullMessage?,
                 receiptMessage: SNProtoReceiptMessage?,
                 typingMessage: SNProtoTypingMessage?,
                 prekeyBundleMessage: SNProtoPrekeyBundleMessage?,
                 lokiDeviceLinkMessage: SNProtoLokiDeviceLinkMessage?) {
        self.proto = proto
        self.dataMessage = dataMessage
        self.syncMessage = syncMessage
        self.callMessage = callMessage
        self.nullMessage = nullMessage
        self.receiptMessage = receiptMessage
        self.typingMessage = typingMessage
        self.prekeyBundleMessage = prekeyBundleMessage
        self.lokiDeviceLinkMessage = lokiDeviceLinkMessage
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

        var callMessage: SNProtoCallMessage? = nil
        if proto.hasCallMessage {
            callMessage = try SNProtoCallMessage.parseProto(proto.callMessage)
        }

        var nullMessage: SNProtoNullMessage? = nil
        if proto.hasNullMessage {
            nullMessage = try SNProtoNullMessage.parseProto(proto.nullMessage)
        }

        var receiptMessage: SNProtoReceiptMessage? = nil
        if proto.hasReceiptMessage {
            receiptMessage = try SNProtoReceiptMessage.parseProto(proto.receiptMessage)
        }

        var typingMessage: SNProtoTypingMessage? = nil
        if proto.hasTypingMessage {
            typingMessage = try SNProtoTypingMessage.parseProto(proto.typingMessage)
        }

        var prekeyBundleMessage: SNProtoPrekeyBundleMessage? = nil
        if proto.hasPrekeyBundleMessage {
            prekeyBundleMessage = try SNProtoPrekeyBundleMessage.parseProto(proto.prekeyBundleMessage)
        }

        var lokiDeviceLinkMessage: SNProtoLokiDeviceLinkMessage? = nil
        if proto.hasLokiDeviceLinkMessage {
            lokiDeviceLinkMessage = try SNProtoLokiDeviceLinkMessage.parseProto(proto.lokiDeviceLinkMessage)
        }

        // MARK: - Begin Validation Logic for SNProtoContent -

        // MARK: - End Validation Logic for SNProtoContent -

        let result = SNProtoContent(proto: proto,
                                    dataMessage: dataMessage,
                                    syncMessage: syncMessage,
                                    callMessage: callMessage,
                                    nullMessage: nullMessage,
                                    receiptMessage: receiptMessage,
                                    typingMessage: typingMessage,
                                    prekeyBundleMessage: prekeyBundleMessage,
                                    lokiDeviceLinkMessage: lokiDeviceLinkMessage)
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

// MARK: - SNProtoPrekeyBundleMessage

@objc public class SNProtoPrekeyBundleMessage: NSObject {

    // MARK: - SNProtoPrekeyBundleMessageBuilder

    @objc public class func builder() -> SNProtoPrekeyBundleMessageBuilder {
        return SNProtoPrekeyBundleMessageBuilder()
    }

    // asBuilder() constructs a builder that reflects the proto's contents.
    @objc public func asBuilder() -> SNProtoPrekeyBundleMessageBuilder {
        let builder = SNProtoPrekeyBundleMessageBuilder()
        if let _value = identityKey {
            builder.setIdentityKey(_value)
        }
        if hasDeviceID {
            builder.setDeviceID(deviceID)
        }
        if hasPrekeyID {
            builder.setPrekeyID(prekeyID)
        }
        if hasSignedKeyID {
            builder.setSignedKeyID(signedKeyID)
        }
        if let _value = prekey {
            builder.setPrekey(_value)
        }
        if let _value = signedKey {
            builder.setSignedKey(_value)
        }
        if let _value = signature {
            builder.setSignature(_value)
        }
        return builder
    }

    @objc public class SNProtoPrekeyBundleMessageBuilder: NSObject {

        private var proto = SessionProtos_PrekeyBundleMessage()

        @objc fileprivate override init() {}

        @objc public func setIdentityKey(_ valueParam: Data) {
            proto.identityKey = valueParam
        }

        @objc public func setDeviceID(_ valueParam: UInt32) {
            proto.deviceID = valueParam
        }

        @objc public func setPrekeyID(_ valueParam: UInt32) {
            proto.prekeyID = valueParam
        }

        @objc public func setSignedKeyID(_ valueParam: UInt32) {
            proto.signedKeyID = valueParam
        }

        @objc public func setPrekey(_ valueParam: Data) {
            proto.prekey = valueParam
        }

        @objc public func setSignedKey(_ valueParam: Data) {
            proto.signedKey = valueParam
        }

        @objc public func setSignature(_ valueParam: Data) {
            proto.signature = valueParam
        }

        @objc public func build() throws -> SNProtoPrekeyBundleMessage {
            return try SNProtoPrekeyBundleMessage.parseProto(proto)
        }

        @objc public func buildSerializedData() throws -> Data {
            return try SNProtoPrekeyBundleMessage.parseProto(proto).serializedData()
        }
    }

    fileprivate let proto: SessionProtos_PrekeyBundleMessage

    @objc public var identityKey: Data? {
        guard proto.hasIdentityKey else {
            return nil
        }
        return proto.identityKey
    }
    @objc public var hasIdentityKey: Bool {
        return proto.hasIdentityKey
    }

    @objc public var deviceID: UInt32 {
        return proto.deviceID
    }
    @objc public var hasDeviceID: Bool {
        return proto.hasDeviceID
    }

    @objc public var prekeyID: UInt32 {
        return proto.prekeyID
    }
    @objc public var hasPrekeyID: Bool {
        return proto.hasPrekeyID
    }

    @objc public var signedKeyID: UInt32 {
        return proto.signedKeyID
    }
    @objc public var hasSignedKeyID: Bool {
        return proto.hasSignedKeyID
    }

    @objc public var prekey: Data? {
        guard proto.hasPrekey else {
            return nil
        }
        return proto.prekey
    }
    @objc public var hasPrekey: Bool {
        return proto.hasPrekey
    }

    @objc public var signedKey: Data? {
        guard proto.hasSignedKey else {
            return nil
        }
        return proto.signedKey
    }
    @objc public var hasSignedKey: Bool {
        return proto.hasSignedKey
    }

    @objc public var signature: Data? {
        guard proto.hasSignature else {
            return nil
        }
        return proto.signature
    }
    @objc public var hasSignature: Bool {
        return proto.hasSignature
    }

    private init(proto: SessionProtos_PrekeyBundleMessage) {
        self.proto = proto
    }

    @objc
    public func serializedData() throws -> Data {
        return try self.proto.serializedData()
    }

    @objc public class func parseData(_ serializedData: Data) throws -> SNProtoPrekeyBundleMessage {
        let proto = try SessionProtos_PrekeyBundleMessage(serializedData: serializedData)
        return try parseProto(proto)
    }

    fileprivate class func parseProto(_ proto: SessionProtos_PrekeyBundleMessage) throws -> SNProtoPrekeyBundleMessage {
        // MARK: - Begin Validation Logic for SNProtoPrekeyBundleMessage -

        // MARK: - End Validation Logic for SNProtoPrekeyBundleMessage -

        let result = SNProtoPrekeyBundleMessage(proto: proto)
        return result
    }

    @objc public override var debugDescription: String {
        return "\(proto)"
    }
}

#if DEBUG

extension SNProtoPrekeyBundleMessage {
    @objc public func serializedDataIgnoringErrors() -> Data? {
        return try! self.serializedData()
    }
}

extension SNProtoPrekeyBundleMessage.SNProtoPrekeyBundleMessageBuilder {
    @objc public func buildIgnoringErrors() -> SNProtoPrekeyBundleMessage? {
        return try! self.build()
    }
}

#endif

// MARK: - SNProtoLokiDeviceLinkMessage

@objc public class SNProtoLokiDeviceLinkMessage: NSObject {

    // MARK: - SNProtoLokiDeviceLinkMessageBuilder

    @objc public class func builder() -> SNProtoLokiDeviceLinkMessageBuilder {
        return SNProtoLokiDeviceLinkMessageBuilder()
    }

    // asBuilder() constructs a builder that reflects the proto's contents.
    @objc public func asBuilder() -> SNProtoLokiDeviceLinkMessageBuilder {
        let builder = SNProtoLokiDeviceLinkMessageBuilder()
        if let _value = masterPublicKey {
            builder.setMasterPublicKey(_value)
        }
        if let _value = slavePublicKey {
            builder.setSlavePublicKey(_value)
        }
        if let _value = slaveSignature {
            builder.setSlaveSignature(_value)
        }
        if let _value = masterSignature {
            builder.setMasterSignature(_value)
        }
        return builder
    }

    @objc public class SNProtoLokiDeviceLinkMessageBuilder: NSObject {

        private var proto = SessionProtos_LokiDeviceLinkMessage()

        @objc fileprivate override init() {}

        @objc public func setMasterPublicKey(_ valueParam: String) {
            proto.masterPublicKey = valueParam
        }

        @objc public func setSlavePublicKey(_ valueParam: String) {
            proto.slavePublicKey = valueParam
        }

        @objc public func setSlaveSignature(_ valueParam: Data) {
            proto.slaveSignature = valueParam
        }

        @objc public func setMasterSignature(_ valueParam: Data) {
            proto.masterSignature = valueParam
        }

        @objc public func build() throws -> SNProtoLokiDeviceLinkMessage {
            return try SNProtoLokiDeviceLinkMessage.parseProto(proto)
        }

        @objc public func buildSerializedData() throws -> Data {
            return try SNProtoLokiDeviceLinkMessage.parseProto(proto).serializedData()
        }
    }

    fileprivate let proto: SessionProtos_LokiDeviceLinkMessage

    @objc public var masterPublicKey: String? {
        guard proto.hasMasterPublicKey else {
            return nil
        }
        return proto.masterPublicKey
    }
    @objc public var hasMasterPublicKey: Bool {
        return proto.hasMasterPublicKey
    }

    @objc public var slavePublicKey: String? {
        guard proto.hasSlavePublicKey else {
            return nil
        }
        return proto.slavePublicKey
    }
    @objc public var hasSlavePublicKey: Bool {
        return proto.hasSlavePublicKey
    }

    @objc public var slaveSignature: Data? {
        guard proto.hasSlaveSignature else {
            return nil
        }
        return proto.slaveSignature
    }
    @objc public var hasSlaveSignature: Bool {
        return proto.hasSlaveSignature
    }

    @objc public var masterSignature: Data? {
        guard proto.hasMasterSignature else {
            return nil
        }
        return proto.masterSignature
    }
    @objc public var hasMasterSignature: Bool {
        return proto.hasMasterSignature
    }

    private init(proto: SessionProtos_LokiDeviceLinkMessage) {
        self.proto = proto
    }

    @objc
    public func serializedData() throws -> Data {
        return try self.proto.serializedData()
    }

    @objc public class func parseData(_ serializedData: Data) throws -> SNProtoLokiDeviceLinkMessage {
        let proto = try SessionProtos_LokiDeviceLinkMessage(serializedData: serializedData)
        return try parseProto(proto)
    }

    fileprivate class func parseProto(_ proto: SessionProtos_LokiDeviceLinkMessage) throws -> SNProtoLokiDeviceLinkMessage {
        // MARK: - Begin Validation Logic for SNProtoLokiDeviceLinkMessage -

        // MARK: - End Validation Logic for SNProtoLokiDeviceLinkMessage -

        let result = SNProtoLokiDeviceLinkMessage(proto: proto)
        return result
    }

    @objc public override var debugDescription: String {
        return "\(proto)"
    }
}

#if DEBUG

extension SNProtoLokiDeviceLinkMessage {
    @objc public func serializedDataIgnoringErrors() -> Data? {
        return try! self.serializedData()
    }
}

extension SNProtoLokiDeviceLinkMessage.SNProtoLokiDeviceLinkMessageBuilder {
    @objc public func buildIgnoringErrors() -> SNProtoLokiDeviceLinkMessage? {
        return try! self.build()
    }
}

#endif

// MARK: - SNProtoCallMessageOffer

@objc public class SNProtoCallMessageOffer: NSObject {

    // MARK: - SNProtoCallMessageOfferBuilder

    @objc public class func builder(id: UInt64, sessionDescription: String) -> SNProtoCallMessageOfferBuilder {
        return SNProtoCallMessageOfferBuilder(id: id, sessionDescription: sessionDescription)
    }

    // asBuilder() constructs a builder that reflects the proto's contents.
    @objc public func asBuilder() -> SNProtoCallMessageOfferBuilder {
        let builder = SNProtoCallMessageOfferBuilder(id: id, sessionDescription: sessionDescription)
        return builder
    }

    @objc public class SNProtoCallMessageOfferBuilder: NSObject {

        private var proto = SessionProtos_CallMessage.Offer()

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

        @objc public func build() throws -> SNProtoCallMessageOffer {
            return try SNProtoCallMessageOffer.parseProto(proto)
        }

        @objc public func buildSerializedData() throws -> Data {
            return try SNProtoCallMessageOffer.parseProto(proto).serializedData()
        }
    }

    fileprivate let proto: SessionProtos_CallMessage.Offer

    @objc public let id: UInt64

    @objc public let sessionDescription: String

    private init(proto: SessionProtos_CallMessage.Offer,
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

    @objc public class func parseData(_ serializedData: Data) throws -> SNProtoCallMessageOffer {
        let proto = try SessionProtos_CallMessage.Offer(serializedData: serializedData)
        return try parseProto(proto)
    }

    fileprivate class func parseProto(_ proto: SessionProtos_CallMessage.Offer) throws -> SNProtoCallMessageOffer {
        guard proto.hasID else {
            throw SNProtoError.invalidProtobuf(description: "\(logTag) missing required field: id")
        }
        let id = proto.id

        guard proto.hasSessionDescription else {
            throw SNProtoError.invalidProtobuf(description: "\(logTag) missing required field: sessionDescription")
        }
        let sessionDescription = proto.sessionDescription

        // MARK: - Begin Validation Logic for SNProtoCallMessageOffer -

        // MARK: - End Validation Logic for SNProtoCallMessageOffer -

        let result = SNProtoCallMessageOffer(proto: proto,
                                             id: id,
                                             sessionDescription: sessionDescription)
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

    @objc public class func builder(id: UInt64, sessionDescription: String) -> SNProtoCallMessageAnswerBuilder {
        return SNProtoCallMessageAnswerBuilder(id: id, sessionDescription: sessionDescription)
    }

    // asBuilder() constructs a builder that reflects the proto's contents.
    @objc public func asBuilder() -> SNProtoCallMessageAnswerBuilder {
        let builder = SNProtoCallMessageAnswerBuilder(id: id, sessionDescription: sessionDescription)
        return builder
    }

    @objc public class SNProtoCallMessageAnswerBuilder: NSObject {

        private var proto = SessionProtos_CallMessage.Answer()

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

        @objc public func build() throws -> SNProtoCallMessageAnswer {
            return try SNProtoCallMessageAnswer.parseProto(proto)
        }

        @objc public func buildSerializedData() throws -> Data {
            return try SNProtoCallMessageAnswer.parseProto(proto).serializedData()
        }
    }

    fileprivate let proto: SessionProtos_CallMessage.Answer

    @objc public let id: UInt64

    @objc public let sessionDescription: String

    private init(proto: SessionProtos_CallMessage.Answer,
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

    @objc public class func parseData(_ serializedData: Data) throws -> SNProtoCallMessageAnswer {
        let proto = try SessionProtos_CallMessage.Answer(serializedData: serializedData)
        return try parseProto(proto)
    }

    fileprivate class func parseProto(_ proto: SessionProtos_CallMessage.Answer) throws -> SNProtoCallMessageAnswer {
        guard proto.hasID else {
            throw SNProtoError.invalidProtobuf(description: "\(logTag) missing required field: id")
        }
        let id = proto.id

        guard proto.hasSessionDescription else {
            throw SNProtoError.invalidProtobuf(description: "\(logTag) missing required field: sessionDescription")
        }
        let sessionDescription = proto.sessionDescription

        // MARK: - Begin Validation Logic for SNProtoCallMessageAnswer -

        // MARK: - End Validation Logic for SNProtoCallMessageAnswer -

        let result = SNProtoCallMessageAnswer(proto: proto,
                                              id: id,
                                              sessionDescription: sessionDescription)
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

    @objc public class func builder(id: UInt64, sdpMid: String, sdpMlineIndex: UInt32, sdp: String) -> SNProtoCallMessageIceUpdateBuilder {
        return SNProtoCallMessageIceUpdateBuilder(id: id, sdpMid: sdpMid, sdpMlineIndex: sdpMlineIndex, sdp: sdp)
    }

    // asBuilder() constructs a builder that reflects the proto's contents.
    @objc public func asBuilder() -> SNProtoCallMessageIceUpdateBuilder {
        let builder = SNProtoCallMessageIceUpdateBuilder(id: id, sdpMid: sdpMid, sdpMlineIndex: sdpMlineIndex, sdp: sdp)
        return builder
    }

    @objc public class SNProtoCallMessageIceUpdateBuilder: NSObject {

        private var proto = SessionProtos_CallMessage.IceUpdate()

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

        @objc public func build() throws -> SNProtoCallMessageIceUpdate {
            return try SNProtoCallMessageIceUpdate.parseProto(proto)
        }

        @objc public func buildSerializedData() throws -> Data {
            return try SNProtoCallMessageIceUpdate.parseProto(proto).serializedData()
        }
    }

    fileprivate let proto: SessionProtos_CallMessage.IceUpdate

    @objc public let id: UInt64

    @objc public let sdpMid: String

    @objc public let sdpMlineIndex: UInt32

    @objc public let sdp: String

    private init(proto: SessionProtos_CallMessage.IceUpdate,
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

    @objc public class func parseData(_ serializedData: Data) throws -> SNProtoCallMessageIceUpdate {
        let proto = try SessionProtos_CallMessage.IceUpdate(serializedData: serializedData)
        return try parseProto(proto)
    }

    fileprivate class func parseProto(_ proto: SessionProtos_CallMessage.IceUpdate) throws -> SNProtoCallMessageIceUpdate {
        guard proto.hasID else {
            throw SNProtoError.invalidProtobuf(description: "\(logTag) missing required field: id")
        }
        let id = proto.id

        guard proto.hasSdpMid else {
            throw SNProtoError.invalidProtobuf(description: "\(logTag) missing required field: sdpMid")
        }
        let sdpMid = proto.sdpMid

        guard proto.hasSdpMlineIndex else {
            throw SNProtoError.invalidProtobuf(description: "\(logTag) missing required field: sdpMlineIndex")
        }
        let sdpMlineIndex = proto.sdpMlineIndex

        guard proto.hasSdp else {
            throw SNProtoError.invalidProtobuf(description: "\(logTag) missing required field: sdp")
        }
        let sdp = proto.sdp

        // MARK: - Begin Validation Logic for SNProtoCallMessageIceUpdate -

        // MARK: - End Validation Logic for SNProtoCallMessageIceUpdate -

        let result = SNProtoCallMessageIceUpdate(proto: proto,
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

    // MARK: - SNProtoCallMessageHangupBuilder

    @objc public class func builder(id: UInt64) -> SNProtoCallMessageHangupBuilder {
        return SNProtoCallMessageHangupBuilder(id: id)
    }

    // asBuilder() constructs a builder that reflects the proto's contents.
    @objc public func asBuilder() -> SNProtoCallMessageHangupBuilder {
        let builder = SNProtoCallMessageHangupBuilder(id: id)
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

        @objc public func build() throws -> SNProtoCallMessageHangup {
            return try SNProtoCallMessageHangup.parseProto(proto)
        }

        @objc public func buildSerializedData() throws -> Data {
            return try SNProtoCallMessageHangup.parseProto(proto).serializedData()
        }
    }

    fileprivate let proto: SessionProtos_CallMessage.Hangup

    @objc public let id: UInt64

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

        @objc public func setHangup(_ valueParam: SNProtoCallMessageHangup) {
            proto.hangup = valueParam.proto
        }

        @objc public func setBusy(_ valueParam: SNProtoCallMessageBusy) {
            proto.busy = valueParam.proto
        }

        @objc public func setProfileKey(_ valueParam: Data) {
            proto.profileKey = valueParam
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

    @objc public let hangup: SNProtoCallMessageHangup?

    @objc public let busy: SNProtoCallMessageBusy?

    @objc public var profileKey: Data? {
        guard proto.hasProfileKey else {
            return nil
        }
        return proto.profileKey
    }
    @objc public var hasProfileKey: Bool {
        return proto.hasProfileKey
    }

    private init(proto: SessionProtos_CallMessage,
                 offer: SNProtoCallMessageOffer?,
                 answer: SNProtoCallMessageAnswer?,
                 iceUpdate: [SNProtoCallMessageIceUpdate],
                 hangup: SNProtoCallMessageHangup?,
                 busy: SNProtoCallMessageBusy?) {
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

        var hangup: SNProtoCallMessageHangup? = nil
        if proto.hasHangup {
            hangup = try SNProtoCallMessageHangup.parseProto(proto.hangup)
        }

        var busy: SNProtoCallMessageBusy? = nil
        if proto.hasBusy {
            busy = try SNProtoCallMessageBusy.parseProto(proto.busy)
        }

        // MARK: - Begin Validation Logic for SNProtoCallMessage -

        // MARK: - End Validation Logic for SNProtoCallMessage -

        let result = SNProtoCallMessage(proto: proto,
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

// MARK: - SNProtoDataMessageClosedGroupUpdateSenderKey

@objc public class SNProtoDataMessageClosedGroupUpdateSenderKey: NSObject {

    // MARK: - SNProtoDataMessageClosedGroupUpdateSenderKeyBuilder

    @objc public class func builder(chainKey: Data, keyIndex: UInt32, publicKey: Data) -> SNProtoDataMessageClosedGroupUpdateSenderKeyBuilder {
        return SNProtoDataMessageClosedGroupUpdateSenderKeyBuilder(chainKey: chainKey, keyIndex: keyIndex, publicKey: publicKey)
    }

    // asBuilder() constructs a builder that reflects the proto's contents.
    @objc public func asBuilder() -> SNProtoDataMessageClosedGroupUpdateSenderKeyBuilder {
        let builder = SNProtoDataMessageClosedGroupUpdateSenderKeyBuilder(chainKey: chainKey, keyIndex: keyIndex, publicKey: publicKey)
        return builder
    }

    @objc public class SNProtoDataMessageClosedGroupUpdateSenderKeyBuilder: NSObject {

        private var proto = SessionProtos_DataMessage.ClosedGroupUpdate.SenderKey()

        @objc fileprivate override init() {}

        @objc fileprivate init(chainKey: Data, keyIndex: UInt32, publicKey: Data) {
            super.init()

            setChainKey(chainKey)
            setKeyIndex(keyIndex)
            setPublicKey(publicKey)
        }

        @objc public func setChainKey(_ valueParam: Data) {
            proto.chainKey = valueParam
        }

        @objc public func setKeyIndex(_ valueParam: UInt32) {
            proto.keyIndex = valueParam
        }

        @objc public func setPublicKey(_ valueParam: Data) {
            proto.publicKey = valueParam
        }

        @objc public func build() throws -> SNProtoDataMessageClosedGroupUpdateSenderKey {
            return try SNProtoDataMessageClosedGroupUpdateSenderKey.parseProto(proto)
        }

        @objc public func buildSerializedData() throws -> Data {
            return try SNProtoDataMessageClosedGroupUpdateSenderKey.parseProto(proto).serializedData()
        }
    }

    fileprivate let proto: SessionProtos_DataMessage.ClosedGroupUpdate.SenderKey

    @objc public let chainKey: Data

    @objc public let keyIndex: UInt32

    @objc public let publicKey: Data

    private init(proto: SessionProtos_DataMessage.ClosedGroupUpdate.SenderKey,
                 chainKey: Data,
                 keyIndex: UInt32,
                 publicKey: Data) {
        self.proto = proto
        self.chainKey = chainKey
        self.keyIndex = keyIndex
        self.publicKey = publicKey
    }

    @objc
    public func serializedData() throws -> Data {
        return try self.proto.serializedData()
    }

    @objc public class func parseData(_ serializedData: Data) throws -> SNProtoDataMessageClosedGroupUpdateSenderKey {
        let proto = try SessionProtos_DataMessage.ClosedGroupUpdate.SenderKey(serializedData: serializedData)
        return try parseProto(proto)
    }

    fileprivate class func parseProto(_ proto: SessionProtos_DataMessage.ClosedGroupUpdate.SenderKey) throws -> SNProtoDataMessageClosedGroupUpdateSenderKey {
        guard proto.hasChainKey else {
            throw SNProtoError.invalidProtobuf(description: "\(logTag) missing required field: chainKey")
        }
        let chainKey = proto.chainKey

        guard proto.hasKeyIndex else {
            throw SNProtoError.invalidProtobuf(description: "\(logTag) missing required field: keyIndex")
        }
        let keyIndex = proto.keyIndex

        guard proto.hasPublicKey else {
            throw SNProtoError.invalidProtobuf(description: "\(logTag) missing required field: publicKey")
        }
        let publicKey = proto.publicKey

        // MARK: - Begin Validation Logic for SNProtoDataMessageClosedGroupUpdateSenderKey -

        // MARK: - End Validation Logic for SNProtoDataMessageClosedGroupUpdateSenderKey -

        let result = SNProtoDataMessageClosedGroupUpdateSenderKey(proto: proto,
                                                                  chainKey: chainKey,
                                                                  keyIndex: keyIndex,
                                                                  publicKey: publicKey)
        return result
    }

    @objc public override var debugDescription: String {
        return "\(proto)"
    }
}

#if DEBUG

extension SNProtoDataMessageClosedGroupUpdateSenderKey {
    @objc public func serializedDataIgnoringErrors() -> Data? {
        return try! self.serializedData()
    }
}

extension SNProtoDataMessageClosedGroupUpdateSenderKey.SNProtoDataMessageClosedGroupUpdateSenderKeyBuilder {
    @objc public func buildIgnoringErrors() -> SNProtoDataMessageClosedGroupUpdateSenderKey? {
        return try! self.build()
    }
}

#endif

// MARK: - SNProtoDataMessageClosedGroupUpdate

@objc public class SNProtoDataMessageClosedGroupUpdate: NSObject {

    // MARK: - SNProtoDataMessageClosedGroupUpdateType

    @objc public enum SNProtoDataMessageClosedGroupUpdateType: Int32 {
        case new = 0
        case info = 1
        case senderKeyRequest = 2
        case senderKey = 3
    }

    private class func SNProtoDataMessageClosedGroupUpdateTypeWrap(_ value: SessionProtos_DataMessage.ClosedGroupUpdate.TypeEnum) -> SNProtoDataMessageClosedGroupUpdateType {
        switch value {
        case .new: return .new
        case .info: return .info
        case .senderKeyRequest: return .senderKeyRequest
        case .senderKey: return .senderKey
        }
    }

    private class func SNProtoDataMessageClosedGroupUpdateTypeUnwrap(_ value: SNProtoDataMessageClosedGroupUpdateType) -> SessionProtos_DataMessage.ClosedGroupUpdate.TypeEnum {
        switch value {
        case .new: return .new
        case .info: return .info
        case .senderKeyRequest: return .senderKeyRequest
        case .senderKey: return .senderKey
        }
    }

    // MARK: - SNProtoDataMessageClosedGroupUpdateBuilder

    @objc public class func builder(groupPublicKey: Data, type: SNProtoDataMessageClosedGroupUpdateType) -> SNProtoDataMessageClosedGroupUpdateBuilder {
        return SNProtoDataMessageClosedGroupUpdateBuilder(groupPublicKey: groupPublicKey, type: type)
    }

    // asBuilder() constructs a builder that reflects the proto's contents.
    @objc public func asBuilder() -> SNProtoDataMessageClosedGroupUpdateBuilder {
        let builder = SNProtoDataMessageClosedGroupUpdateBuilder(groupPublicKey: groupPublicKey, type: type)
        if let _value = name {
            builder.setName(_value)
        }
        if let _value = groupPrivateKey {
            builder.setGroupPrivateKey(_value)
        }
        builder.setSenderKeys(senderKeys)
        builder.setMembers(members)
        builder.setAdmins(admins)
        return builder
    }

    @objc public class SNProtoDataMessageClosedGroupUpdateBuilder: NSObject {

        private var proto = SessionProtos_DataMessage.ClosedGroupUpdate()

        @objc fileprivate override init() {}

        @objc fileprivate init(groupPublicKey: Data, type: SNProtoDataMessageClosedGroupUpdateType) {
            super.init()

            setGroupPublicKey(groupPublicKey)
            setType(type)
        }

        @objc public func setName(_ valueParam: String) {
            proto.name = valueParam
        }

        @objc public func setGroupPublicKey(_ valueParam: Data) {
            proto.groupPublicKey = valueParam
        }

        @objc public func setGroupPrivateKey(_ valueParam: Data) {
            proto.groupPrivateKey = valueParam
        }

        @objc public func addSenderKeys(_ valueParam: SNProtoDataMessageClosedGroupUpdateSenderKey) {
            var items = proto.senderKeys
            items.append(valueParam.proto)
            proto.senderKeys = items
        }

        @objc public func setSenderKeys(_ wrappedItems: [SNProtoDataMessageClosedGroupUpdateSenderKey]) {
            proto.senderKeys = wrappedItems.map { $0.proto }
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

        @objc public func setType(_ valueParam: SNProtoDataMessageClosedGroupUpdateType) {
            proto.type = SNProtoDataMessageClosedGroupUpdateTypeUnwrap(valueParam)
        }

        @objc public func build() throws -> SNProtoDataMessageClosedGroupUpdate {
            return try SNProtoDataMessageClosedGroupUpdate.parseProto(proto)
        }

        @objc public func buildSerializedData() throws -> Data {
            return try SNProtoDataMessageClosedGroupUpdate.parseProto(proto).serializedData()
        }
    }

    fileprivate let proto: SessionProtos_DataMessage.ClosedGroupUpdate

    @objc public let groupPublicKey: Data

    @objc public let senderKeys: [SNProtoDataMessageClosedGroupUpdateSenderKey]

    @objc public let type: SNProtoDataMessageClosedGroupUpdateType

    @objc public var name: String? {
        guard proto.hasName else {
            return nil
        }
        return proto.name
    }
    @objc public var hasName: Bool {
        return proto.hasName
    }

    @objc public var groupPrivateKey: Data? {
        guard proto.hasGroupPrivateKey else {
            return nil
        }
        return proto.groupPrivateKey
    }
    @objc public var hasGroupPrivateKey: Bool {
        return proto.hasGroupPrivateKey
    }

    @objc public var members: [Data] {
        return proto.members
    }

    @objc public var admins: [Data] {
        return proto.admins
    }

    private init(proto: SessionProtos_DataMessage.ClosedGroupUpdate,
                 groupPublicKey: Data,
                 senderKeys: [SNProtoDataMessageClosedGroupUpdateSenderKey],
                 type: SNProtoDataMessageClosedGroupUpdateType) {
        self.proto = proto
        self.groupPublicKey = groupPublicKey
        self.senderKeys = senderKeys
        self.type = type
    }

    @objc
    public func serializedData() throws -> Data {
        return try self.proto.serializedData()
    }

    @objc public class func parseData(_ serializedData: Data) throws -> SNProtoDataMessageClosedGroupUpdate {
        let proto = try SessionProtos_DataMessage.ClosedGroupUpdate(serializedData: serializedData)
        return try parseProto(proto)
    }

    fileprivate class func parseProto(_ proto: SessionProtos_DataMessage.ClosedGroupUpdate) throws -> SNProtoDataMessageClosedGroupUpdate {
        guard proto.hasGroupPublicKey else {
            throw SNProtoError.invalidProtobuf(description: "\(logTag) missing required field: groupPublicKey")
        }
        let groupPublicKey = proto.groupPublicKey

        var senderKeys: [SNProtoDataMessageClosedGroupUpdateSenderKey] = []
        senderKeys = try proto.senderKeys.map { try SNProtoDataMessageClosedGroupUpdateSenderKey.parseProto($0) }

        guard proto.hasType else {
            throw SNProtoError.invalidProtobuf(description: "\(logTag) missing required field: type")
        }
        let type = SNProtoDataMessageClosedGroupUpdateTypeWrap(proto.type)

        // MARK: - Begin Validation Logic for SNProtoDataMessageClosedGroupUpdate -

        // MARK: - End Validation Logic for SNProtoDataMessageClosedGroupUpdate -

        let result = SNProtoDataMessageClosedGroupUpdate(proto: proto,
                                                         groupPublicKey: groupPublicKey,
                                                         senderKeys: senderKeys,
                                                         type: type)
        return result
    }

    @objc public override var debugDescription: String {
        return "\(proto)"
    }
}

#if DEBUG

extension SNProtoDataMessageClosedGroupUpdate {
    @objc public func serializedDataIgnoringErrors() -> Data? {
        return try! self.serializedData()
    }
}

extension SNProtoDataMessageClosedGroupUpdate.SNProtoDataMessageClosedGroupUpdateBuilder {
    @objc public func buildIgnoringErrors() -> SNProtoDataMessageClosedGroupUpdate? {
        return try! self.build()
    }
}

#endif

// MARK: - SNProtoDataMessage

@objc public class SNProtoDataMessage: NSObject {

    // MARK: - SNProtoDataMessageFlags

    @objc public enum SNProtoDataMessageFlags: Int32 {
        case endSession = 1
        case expirationTimerUpdate = 2
        case profileKeyUpdate = 4
        case unlinkDevice = 128
    }

    private class func SNProtoDataMessageFlagsWrap(_ value: SessionProtos_DataMessage.Flags) -> SNProtoDataMessageFlags {
        switch value {
        case .endSession: return .endSession
        case .expirationTimerUpdate: return .expirationTimerUpdate
        case .profileKeyUpdate: return .profileKeyUpdate
        case .unlinkDevice: return .unlinkDevice
        }
    }

    private class func SNProtoDataMessageFlagsUnwrap(_ value: SNProtoDataMessageFlags) -> SessionProtos_DataMessage.Flags {
        switch value {
        case .endSession: return .endSession
        case .expirationTimerUpdate: return .expirationTimerUpdate
        case .profileKeyUpdate: return .profileKeyUpdate
        case .unlinkDevice: return .unlinkDevice
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
        if let _value = closedGroupUpdate {
            builder.setClosedGroupUpdate(_value)
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

        @objc public func setClosedGroupUpdate(_ valueParam: SNProtoDataMessageClosedGroupUpdate) {
            proto.closedGroupUpdate = valueParam.proto
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

    @objc public let closedGroupUpdate: SNProtoDataMessageClosedGroupUpdate?

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
                 closedGroupUpdate: SNProtoDataMessageClosedGroupUpdate?,
                 publicChatInfo: SNProtoPublicChatInfo?) {
        self.proto = proto
        self.attachments = attachments
        self.group = group
        self.quote = quote
        self.contact = contact
        self.preview = preview
        self.profile = profile
        self.closedGroupUpdate = closedGroupUpdate
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

        var closedGroupUpdate: SNProtoDataMessageClosedGroupUpdate? = nil
        if proto.hasClosedGroupUpdate {
            closedGroupUpdate = try SNProtoDataMessageClosedGroupUpdate.parseProto(proto.closedGroupUpdate)
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
                                        closedGroupUpdate: closedGroupUpdate,
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

// MARK: - SNProtoNullMessage

@objc public class SNProtoNullMessage: NSObject {

    // MARK: - SNProtoNullMessageBuilder

    @objc public class func builder() -> SNProtoNullMessageBuilder {
        return SNProtoNullMessageBuilder()
    }

    // asBuilder() constructs a builder that reflects the proto's contents.
    @objc public func asBuilder() -> SNProtoNullMessageBuilder {
        let builder = SNProtoNullMessageBuilder()
        if let _value = padding {
            builder.setPadding(_value)
        }
        return builder
    }

    @objc public class SNProtoNullMessageBuilder: NSObject {

        private var proto = SessionProtos_NullMessage()

        @objc fileprivate override init() {}

        @objc public func setPadding(_ valueParam: Data) {
            proto.padding = valueParam
        }

        @objc public func build() throws -> SNProtoNullMessage {
            return try SNProtoNullMessage.parseProto(proto)
        }

        @objc public func buildSerializedData() throws -> Data {
            return try SNProtoNullMessage.parseProto(proto).serializedData()
        }
    }

    fileprivate let proto: SessionProtos_NullMessage

    @objc public var padding: Data? {
        guard proto.hasPadding else {
            return nil
        }
        return proto.padding
    }
    @objc public var hasPadding: Bool {
        return proto.hasPadding
    }

    private init(proto: SessionProtos_NullMessage) {
        self.proto = proto
    }

    @objc
    public func serializedData() throws -> Data {
        return try self.proto.serializedData()
    }

    @objc public class func parseData(_ serializedData: Data) throws -> SNProtoNullMessage {
        let proto = try SessionProtos_NullMessage(serializedData: serializedData)
        return try parseProto(proto)
    }

    fileprivate class func parseProto(_ proto: SessionProtos_NullMessage) throws -> SNProtoNullMessage {
        // MARK: - Begin Validation Logic for SNProtoNullMessage -

        // MARK: - End Validation Logic for SNProtoNullMessage -

        let result = SNProtoNullMessage(proto: proto)
        return result
    }

    @objc public override var debugDescription: String {
        return "\(proto)"
    }
}

#if DEBUG

extension SNProtoNullMessage {
    @objc public func serializedDataIgnoringErrors() -> Data? {
        return try! self.serializedData()
    }
}

extension SNProtoNullMessage.SNProtoNullMessageBuilder {
    @objc public func buildIgnoringErrors() -> SNProtoNullMessage? {
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

// MARK: - SNProtoVerified

@objc public class SNProtoVerified: NSObject {

    // MARK: - SNProtoVerifiedState

    @objc public enum SNProtoVerifiedState: Int32 {
        case `default` = 0
        case verified = 1
        case unverified = 2
    }

    private class func SNProtoVerifiedStateWrap(_ value: SessionProtos_Verified.State) -> SNProtoVerifiedState {
        switch value {
        case .default: return .default
        case .verified: return .verified
        case .unverified: return .unverified
        }
    }

    private class func SNProtoVerifiedStateUnwrap(_ value: SNProtoVerifiedState) -> SessionProtos_Verified.State {
        switch value {
        case .default: return .default
        case .verified: return .verified
        case .unverified: return .unverified
        }
    }

    // MARK: - SNProtoVerifiedBuilder

    @objc public class func builder(destination: String) -> SNProtoVerifiedBuilder {
        return SNProtoVerifiedBuilder(destination: destination)
    }

    // asBuilder() constructs a builder that reflects the proto's contents.
    @objc public func asBuilder() -> SNProtoVerifiedBuilder {
        let builder = SNProtoVerifiedBuilder(destination: destination)
        if let _value = identityKey {
            builder.setIdentityKey(_value)
        }
        if hasState {
            builder.setState(state)
        }
        if let _value = nullMessage {
            builder.setNullMessage(_value)
        }
        return builder
    }

    @objc public class SNProtoVerifiedBuilder: NSObject {

        private var proto = SessionProtos_Verified()

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

        @objc public func setState(_ valueParam: SNProtoVerifiedState) {
            proto.state = SNProtoVerifiedStateUnwrap(valueParam)
        }

        @objc public func setNullMessage(_ valueParam: Data) {
            proto.nullMessage = valueParam
        }

        @objc public func build() throws -> SNProtoVerified {
            return try SNProtoVerified.parseProto(proto)
        }

        @objc public func buildSerializedData() throws -> Data {
            return try SNProtoVerified.parseProto(proto).serializedData()
        }
    }

    fileprivate let proto: SessionProtos_Verified

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

    @objc public var state: SNProtoVerifiedState {
        return SNProtoVerified.SNProtoVerifiedStateWrap(proto.state)
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

    private init(proto: SessionProtos_Verified,
                 destination: String) {
        self.proto = proto
        self.destination = destination
    }

    @objc
    public func serializedData() throws -> Data {
        return try self.proto.serializedData()
    }

    @objc public class func parseData(_ serializedData: Data) throws -> SNProtoVerified {
        let proto = try SessionProtos_Verified(serializedData: serializedData)
        return try parseProto(proto)
    }

    fileprivate class func parseProto(_ proto: SessionProtos_Verified) throws -> SNProtoVerified {
        guard proto.hasDestination else {
            throw SNProtoError.invalidProtobuf(description: "\(logTag) missing required field: destination")
        }
        let destination = proto.destination

        // MARK: - Begin Validation Logic for SNProtoVerified -

        // MARK: - End Validation Logic for SNProtoVerified -

        let result = SNProtoVerified(proto: proto,
                                     destination: destination)
        return result
    }

    @objc public override var debugDescription: String {
        return "\(proto)"
    }
}

#if DEBUG

extension SNProtoVerified {
    @objc public func serializedDataIgnoringErrors() -> Data? {
        return try! self.serializedData()
    }
}

extension SNProtoVerified.SNProtoVerifiedBuilder {
    @objc public func buildIgnoringErrors() -> SNProtoVerified? {
        return try! self.build()
    }
}

#endif

// MARK: - SNProtoSyncMessageSentUnidentifiedDeliveryStatus

@objc public class SNProtoSyncMessageSentUnidentifiedDeliveryStatus: NSObject {

    // MARK: - SNProtoSyncMessageSentUnidentifiedDeliveryStatusBuilder

    @objc public class func builder() -> SNProtoSyncMessageSentUnidentifiedDeliveryStatusBuilder {
        return SNProtoSyncMessageSentUnidentifiedDeliveryStatusBuilder()
    }

    // asBuilder() constructs a builder that reflects the proto's contents.
    @objc public func asBuilder() -> SNProtoSyncMessageSentUnidentifiedDeliveryStatusBuilder {
        let builder = SNProtoSyncMessageSentUnidentifiedDeliveryStatusBuilder()
        if let _value = destination {
            builder.setDestination(_value)
        }
        if hasUnidentified {
            builder.setUnidentified(unidentified)
        }
        return builder
    }

    @objc public class SNProtoSyncMessageSentUnidentifiedDeliveryStatusBuilder: NSObject {

        private var proto = SessionProtos_SyncMessage.Sent.UnidentifiedDeliveryStatus()

        @objc fileprivate override init() {}

        @objc public func setDestination(_ valueParam: String) {
            proto.destination = valueParam
        }

        @objc public func setUnidentified(_ valueParam: Bool) {
            proto.unidentified = valueParam
        }

        @objc public func build() throws -> SNProtoSyncMessageSentUnidentifiedDeliveryStatus {
            return try SNProtoSyncMessageSentUnidentifiedDeliveryStatus.parseProto(proto)
        }

        @objc public func buildSerializedData() throws -> Data {
            return try SNProtoSyncMessageSentUnidentifiedDeliveryStatus.parseProto(proto).serializedData()
        }
    }

    fileprivate let proto: SessionProtos_SyncMessage.Sent.UnidentifiedDeliveryStatus

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

    private init(proto: SessionProtos_SyncMessage.Sent.UnidentifiedDeliveryStatus) {
        self.proto = proto
    }

    @objc
    public func serializedData() throws -> Data {
        return try self.proto.serializedData()
    }

    @objc public class func parseData(_ serializedData: Data) throws -> SNProtoSyncMessageSentUnidentifiedDeliveryStatus {
        let proto = try SessionProtos_SyncMessage.Sent.UnidentifiedDeliveryStatus(serializedData: serializedData)
        return try parseProto(proto)
    }

    fileprivate class func parseProto(_ proto: SessionProtos_SyncMessage.Sent.UnidentifiedDeliveryStatus) throws -> SNProtoSyncMessageSentUnidentifiedDeliveryStatus {
        // MARK: - Begin Validation Logic for SNProtoSyncMessageSentUnidentifiedDeliveryStatus -

        // MARK: - End Validation Logic for SNProtoSyncMessageSentUnidentifiedDeliveryStatus -

        let result = SNProtoSyncMessageSentUnidentifiedDeliveryStatus(proto: proto)
        return result
    }

    @objc public override var debugDescription: String {
        return "\(proto)"
    }
}

#if DEBUG

extension SNProtoSyncMessageSentUnidentifiedDeliveryStatus {
    @objc public func serializedDataIgnoringErrors() -> Data? {
        return try! self.serializedData()
    }
}

extension SNProtoSyncMessageSentUnidentifiedDeliveryStatus.SNProtoSyncMessageSentUnidentifiedDeliveryStatusBuilder {
    @objc public func buildIgnoringErrors() -> SNProtoSyncMessageSentUnidentifiedDeliveryStatus? {
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
        builder.setUnidentifiedStatus(unidentifiedStatus)
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

        @objc public func addUnidentifiedStatus(_ valueParam: SNProtoSyncMessageSentUnidentifiedDeliveryStatus) {
            var items = proto.unidentifiedStatus
            items.append(valueParam.proto)
            proto.unidentifiedStatus = items
        }

        @objc public func setUnidentifiedStatus(_ wrappedItems: [SNProtoSyncMessageSentUnidentifiedDeliveryStatus]) {
            proto.unidentifiedStatus = wrappedItems.map { $0.proto }
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

    @objc public let unidentifiedStatus: [SNProtoSyncMessageSentUnidentifiedDeliveryStatus]

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
                 message: SNProtoDataMessage?,
                 unidentifiedStatus: [SNProtoSyncMessageSentUnidentifiedDeliveryStatus]) {
        self.proto = proto
        self.message = message
        self.unidentifiedStatus = unidentifiedStatus
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

        var unidentifiedStatus: [SNProtoSyncMessageSentUnidentifiedDeliveryStatus] = []
        unidentifiedStatus = try proto.unidentifiedStatus.map { try SNProtoSyncMessageSentUnidentifiedDeliveryStatus.parseProto($0) }

        // MARK: - Begin Validation Logic for SNProtoSyncMessageSent -

        // MARK: - End Validation Logic for SNProtoSyncMessageSent -

        let result = SNProtoSyncMessageSent(proto: proto,
                                            message: message,
                                            unidentifiedStatus: unidentifiedStatus)
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

// MARK: - SNProtoSyncMessageContacts

@objc public class SNProtoSyncMessageContacts: NSObject {

    // MARK: - SNProtoSyncMessageContactsBuilder

    @objc public class func builder() -> SNProtoSyncMessageContactsBuilder {
        return SNProtoSyncMessageContactsBuilder()
    }

    // asBuilder() constructs a builder that reflects the proto's contents.
    @objc public func asBuilder() -> SNProtoSyncMessageContactsBuilder {
        let builder = SNProtoSyncMessageContactsBuilder()
        if let _value = blob {
            builder.setBlob(_value)
        }
        if hasIsComplete {
            builder.setIsComplete(isComplete)
        }
        if let _value = data {
            builder.setData(_value)
        }
        return builder
    }

    @objc public class SNProtoSyncMessageContactsBuilder: NSObject {

        private var proto = SessionProtos_SyncMessage.Contacts()

        @objc fileprivate override init() {}

        @objc public func setBlob(_ valueParam: SNProtoAttachmentPointer) {
            proto.blob = valueParam.proto
        }

        @objc public func setIsComplete(_ valueParam: Bool) {
            proto.isComplete = valueParam
        }

        @objc public func setData(_ valueParam: Data) {
            proto.data = valueParam
        }

        @objc public func build() throws -> SNProtoSyncMessageContacts {
            return try SNProtoSyncMessageContacts.parseProto(proto)
        }

        @objc public func buildSerializedData() throws -> Data {
            return try SNProtoSyncMessageContacts.parseProto(proto).serializedData()
        }
    }

    fileprivate let proto: SessionProtos_SyncMessage.Contacts

    @objc public let blob: SNProtoAttachmentPointer?

    @objc public var isComplete: Bool {
        return proto.isComplete
    }
    @objc public var hasIsComplete: Bool {
        return proto.hasIsComplete
    }

    @objc public var data: Data? {
        guard proto.hasData else {
            return nil
        }
        return proto.data
    }
    @objc public var hasData: Bool {
        return proto.hasData
    }

    private init(proto: SessionProtos_SyncMessage.Contacts,
                 blob: SNProtoAttachmentPointer?) {
        self.proto = proto
        self.blob = blob
    }

    @objc
    public func serializedData() throws -> Data {
        return try self.proto.serializedData()
    }

    @objc public class func parseData(_ serializedData: Data) throws -> SNProtoSyncMessageContacts {
        let proto = try SessionProtos_SyncMessage.Contacts(serializedData: serializedData)
        return try parseProto(proto)
    }

    fileprivate class func parseProto(_ proto: SessionProtos_SyncMessage.Contacts) throws -> SNProtoSyncMessageContacts {
        var blob: SNProtoAttachmentPointer? = nil
        if proto.hasBlob {
            blob = try SNProtoAttachmentPointer.parseProto(proto.blob)
        }

        // MARK: - Begin Validation Logic for SNProtoSyncMessageContacts -

        // MARK: - End Validation Logic for SNProtoSyncMessageContacts -

        let result = SNProtoSyncMessageContacts(proto: proto,
                                                blob: blob)
        return result
    }

    @objc public override var debugDescription: String {
        return "\(proto)"
    }
}

#if DEBUG

extension SNProtoSyncMessageContacts {
    @objc public func serializedDataIgnoringErrors() -> Data? {
        return try! self.serializedData()
    }
}

extension SNProtoSyncMessageContacts.SNProtoSyncMessageContactsBuilder {
    @objc public func buildIgnoringErrors() -> SNProtoSyncMessageContacts? {
        return try! self.build()
    }
}

#endif

// MARK: - SNProtoSyncMessageGroups

@objc public class SNProtoSyncMessageGroups: NSObject {

    // MARK: - SNProtoSyncMessageGroupsBuilder

    @objc public class func builder() -> SNProtoSyncMessageGroupsBuilder {
        return SNProtoSyncMessageGroupsBuilder()
    }

    // asBuilder() constructs a builder that reflects the proto's contents.
    @objc public func asBuilder() -> SNProtoSyncMessageGroupsBuilder {
        let builder = SNProtoSyncMessageGroupsBuilder()
        if let _value = blob {
            builder.setBlob(_value)
        }
        if let _value = data {
            builder.setData(_value)
        }
        return builder
    }

    @objc public class SNProtoSyncMessageGroupsBuilder: NSObject {

        private var proto = SessionProtos_SyncMessage.Groups()

        @objc fileprivate override init() {}

        @objc public func setBlob(_ valueParam: SNProtoAttachmentPointer) {
            proto.blob = valueParam.proto
        }

        @objc public func setData(_ valueParam: Data) {
            proto.data = valueParam
        }

        @objc public func build() throws -> SNProtoSyncMessageGroups {
            return try SNProtoSyncMessageGroups.parseProto(proto)
        }

        @objc public func buildSerializedData() throws -> Data {
            return try SNProtoSyncMessageGroups.parseProto(proto).serializedData()
        }
    }

    fileprivate let proto: SessionProtos_SyncMessage.Groups

    @objc public let blob: SNProtoAttachmentPointer?

    @objc public var data: Data? {
        guard proto.hasData else {
            return nil
        }
        return proto.data
    }
    @objc public var hasData: Bool {
        return proto.hasData
    }

    private init(proto: SessionProtos_SyncMessage.Groups,
                 blob: SNProtoAttachmentPointer?) {
        self.proto = proto
        self.blob = blob
    }

    @objc
    public func serializedData() throws -> Data {
        return try self.proto.serializedData()
    }

    @objc public class func parseData(_ serializedData: Data) throws -> SNProtoSyncMessageGroups {
        let proto = try SessionProtos_SyncMessage.Groups(serializedData: serializedData)
        return try parseProto(proto)
    }

    fileprivate class func parseProto(_ proto: SessionProtos_SyncMessage.Groups) throws -> SNProtoSyncMessageGroups {
        var blob: SNProtoAttachmentPointer? = nil
        if proto.hasBlob {
            blob = try SNProtoAttachmentPointer.parseProto(proto.blob)
        }

        // MARK: - Begin Validation Logic for SNProtoSyncMessageGroups -

        // MARK: - End Validation Logic for SNProtoSyncMessageGroups -

        let result = SNProtoSyncMessageGroups(proto: proto,
                                              blob: blob)
        return result
    }

    @objc public override var debugDescription: String {
        return "\(proto)"
    }
}

#if DEBUG

extension SNProtoSyncMessageGroups {
    @objc public func serializedDataIgnoringErrors() -> Data? {
        return try! self.serializedData()
    }
}

extension SNProtoSyncMessageGroups.SNProtoSyncMessageGroupsBuilder {
    @objc public func buildIgnoringErrors() -> SNProtoSyncMessageGroups? {
        return try! self.build()
    }
}

#endif

// MARK: - SNProtoSyncMessageOpenGroupDetails

@objc public class SNProtoSyncMessageOpenGroupDetails: NSObject {

    // MARK: - SNProtoSyncMessageOpenGroupDetailsBuilder

    @objc public class func builder(url: String, channelID: UInt64) -> SNProtoSyncMessageOpenGroupDetailsBuilder {
        return SNProtoSyncMessageOpenGroupDetailsBuilder(url: url, channelID: channelID)
    }

    // asBuilder() constructs a builder that reflects the proto's contents.
    @objc public func asBuilder() -> SNProtoSyncMessageOpenGroupDetailsBuilder {
        let builder = SNProtoSyncMessageOpenGroupDetailsBuilder(url: url, channelID: channelID)
        return builder
    }

    @objc public class SNProtoSyncMessageOpenGroupDetailsBuilder: NSObject {

        private var proto = SessionProtos_SyncMessage.OpenGroupDetails()

        @objc fileprivate override init() {}

        @objc fileprivate init(url: String, channelID: UInt64) {
            super.init()

            setUrl(url)
            setChannelID(channelID)
        }

        @objc public func setUrl(_ valueParam: String) {
            proto.url = valueParam
        }

        @objc public func setChannelID(_ valueParam: UInt64) {
            proto.channelID = valueParam
        }

        @objc public func build() throws -> SNProtoSyncMessageOpenGroupDetails {
            return try SNProtoSyncMessageOpenGroupDetails.parseProto(proto)
        }

        @objc public func buildSerializedData() throws -> Data {
            return try SNProtoSyncMessageOpenGroupDetails.parseProto(proto).serializedData()
        }
    }

    fileprivate let proto: SessionProtos_SyncMessage.OpenGroupDetails

    @objc public let url: String

    @objc public let channelID: UInt64

    private init(proto: SessionProtos_SyncMessage.OpenGroupDetails,
                 url: String,
                 channelID: UInt64) {
        self.proto = proto
        self.url = url
        self.channelID = channelID
    }

    @objc
    public func serializedData() throws -> Data {
        return try self.proto.serializedData()
    }

    @objc public class func parseData(_ serializedData: Data) throws -> SNProtoSyncMessageOpenGroupDetails {
        let proto = try SessionProtos_SyncMessage.OpenGroupDetails(serializedData: serializedData)
        return try parseProto(proto)
    }

    fileprivate class func parseProto(_ proto: SessionProtos_SyncMessage.OpenGroupDetails) throws -> SNProtoSyncMessageOpenGroupDetails {
        guard proto.hasURL else {
            throw SNProtoError.invalidProtobuf(description: "\(logTag) missing required field: url")
        }
        let url = proto.url

        guard proto.hasChannelID else {
            throw SNProtoError.invalidProtobuf(description: "\(logTag) missing required field: channelID")
        }
        let channelID = proto.channelID

        // MARK: - Begin Validation Logic for SNProtoSyncMessageOpenGroupDetails -

        // MARK: - End Validation Logic for SNProtoSyncMessageOpenGroupDetails -

        let result = SNProtoSyncMessageOpenGroupDetails(proto: proto,
                                                        url: url,
                                                        channelID: channelID)
        return result
    }

    @objc public override var debugDescription: String {
        return "\(proto)"
    }
}

#if DEBUG

extension SNProtoSyncMessageOpenGroupDetails {
    @objc public func serializedDataIgnoringErrors() -> Data? {
        return try! self.serializedData()
    }
}

extension SNProtoSyncMessageOpenGroupDetails.SNProtoSyncMessageOpenGroupDetailsBuilder {
    @objc public func buildIgnoringErrors() -> SNProtoSyncMessageOpenGroupDetails? {
        return try! self.build()
    }
}

#endif

// MARK: - SNProtoSyncMessageBlocked

@objc public class SNProtoSyncMessageBlocked: NSObject {

    // MARK: - SNProtoSyncMessageBlockedBuilder

    @objc public class func builder() -> SNProtoSyncMessageBlockedBuilder {
        return SNProtoSyncMessageBlockedBuilder()
    }

    // asBuilder() constructs a builder that reflects the proto's contents.
    @objc public func asBuilder() -> SNProtoSyncMessageBlockedBuilder {
        let builder = SNProtoSyncMessageBlockedBuilder()
        builder.setNumbers(numbers)
        builder.setGroupIds(groupIds)
        return builder
    }

    @objc public class SNProtoSyncMessageBlockedBuilder: NSObject {

        private var proto = SessionProtos_SyncMessage.Blocked()

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

        @objc public func build() throws -> SNProtoSyncMessageBlocked {
            return try SNProtoSyncMessageBlocked.parseProto(proto)
        }

        @objc public func buildSerializedData() throws -> Data {
            return try SNProtoSyncMessageBlocked.parseProto(proto).serializedData()
        }
    }

    fileprivate let proto: SessionProtos_SyncMessage.Blocked

    @objc public var numbers: [String] {
        return proto.numbers
    }

    @objc public var groupIds: [Data] {
        return proto.groupIds
    }

    private init(proto: SessionProtos_SyncMessage.Blocked) {
        self.proto = proto
    }

    @objc
    public func serializedData() throws -> Data {
        return try self.proto.serializedData()
    }

    @objc public class func parseData(_ serializedData: Data) throws -> SNProtoSyncMessageBlocked {
        let proto = try SessionProtos_SyncMessage.Blocked(serializedData: serializedData)
        return try parseProto(proto)
    }

    fileprivate class func parseProto(_ proto: SessionProtos_SyncMessage.Blocked) throws -> SNProtoSyncMessageBlocked {
        // MARK: - Begin Validation Logic for SNProtoSyncMessageBlocked -

        // MARK: - End Validation Logic for SNProtoSyncMessageBlocked -

        let result = SNProtoSyncMessageBlocked(proto: proto)
        return result
    }

    @objc public override var debugDescription: String {
        return "\(proto)"
    }
}

#if DEBUG

extension SNProtoSyncMessageBlocked {
    @objc public func serializedDataIgnoringErrors() -> Data? {
        return try! self.serializedData()
    }
}

extension SNProtoSyncMessageBlocked.SNProtoSyncMessageBlockedBuilder {
    @objc public func buildIgnoringErrors() -> SNProtoSyncMessageBlocked? {
        return try! self.build()
    }
}

#endif

// MARK: - SNProtoSyncMessageRequest

@objc public class SNProtoSyncMessageRequest: NSObject {

    // MARK: - SNProtoSyncMessageRequestType

    @objc public enum SNProtoSyncMessageRequestType: Int32 {
        case unknown = 0
        case contacts = 1
        case groups = 2
        case blocked = 3
        case configuration = 4
    }

    private class func SNProtoSyncMessageRequestTypeWrap(_ value: SessionProtos_SyncMessage.Request.TypeEnum) -> SNProtoSyncMessageRequestType {
        switch value {
        case .unknown: return .unknown
        case .contacts: return .contacts
        case .groups: return .groups
        case .blocked: return .blocked
        case .configuration: return .configuration
        }
    }

    private class func SNProtoSyncMessageRequestTypeUnwrap(_ value: SNProtoSyncMessageRequestType) -> SessionProtos_SyncMessage.Request.TypeEnum {
        switch value {
        case .unknown: return .unknown
        case .contacts: return .contacts
        case .groups: return .groups
        case .blocked: return .blocked
        case .configuration: return .configuration
        }
    }

    // MARK: - SNProtoSyncMessageRequestBuilder

    @objc public class func builder(type: SNProtoSyncMessageRequestType) -> SNProtoSyncMessageRequestBuilder {
        return SNProtoSyncMessageRequestBuilder(type: type)
    }

    // asBuilder() constructs a builder that reflects the proto's contents.
    @objc public func asBuilder() -> SNProtoSyncMessageRequestBuilder {
        let builder = SNProtoSyncMessageRequestBuilder(type: type)
        return builder
    }

    @objc public class SNProtoSyncMessageRequestBuilder: NSObject {

        private var proto = SessionProtos_SyncMessage.Request()

        @objc fileprivate override init() {}

        @objc fileprivate init(type: SNProtoSyncMessageRequestType) {
            super.init()

            setType(type)
        }

        @objc public func setType(_ valueParam: SNProtoSyncMessageRequestType) {
            proto.type = SNProtoSyncMessageRequestTypeUnwrap(valueParam)
        }

        @objc public func build() throws -> SNProtoSyncMessageRequest {
            return try SNProtoSyncMessageRequest.parseProto(proto)
        }

        @objc public func buildSerializedData() throws -> Data {
            return try SNProtoSyncMessageRequest.parseProto(proto).serializedData()
        }
    }

    fileprivate let proto: SessionProtos_SyncMessage.Request

    @objc public let type: SNProtoSyncMessageRequestType

    private init(proto: SessionProtos_SyncMessage.Request,
                 type: SNProtoSyncMessageRequestType) {
        self.proto = proto
        self.type = type
    }

    @objc
    public func serializedData() throws -> Data {
        return try self.proto.serializedData()
    }

    @objc public class func parseData(_ serializedData: Data) throws -> SNProtoSyncMessageRequest {
        let proto = try SessionProtos_SyncMessage.Request(serializedData: serializedData)
        return try parseProto(proto)
    }

    fileprivate class func parseProto(_ proto: SessionProtos_SyncMessage.Request) throws -> SNProtoSyncMessageRequest {
        guard proto.hasType else {
            throw SNProtoError.invalidProtobuf(description: "\(logTag) missing required field: type")
        }
        let type = SNProtoSyncMessageRequestTypeWrap(proto.type)

        // MARK: - Begin Validation Logic for SNProtoSyncMessageRequest -

        // MARK: - End Validation Logic for SNProtoSyncMessageRequest -

        let result = SNProtoSyncMessageRequest(proto: proto,
                                               type: type)
        return result
    }

    @objc public override var debugDescription: String {
        return "\(proto)"
    }
}

#if DEBUG

extension SNProtoSyncMessageRequest {
    @objc public func serializedDataIgnoringErrors() -> Data? {
        return try! self.serializedData()
    }
}

extension SNProtoSyncMessageRequest.SNProtoSyncMessageRequestBuilder {
    @objc public func buildIgnoringErrors() -> SNProtoSyncMessageRequest? {
        return try! self.build()
    }
}

#endif

// MARK: - SNProtoSyncMessageRead

@objc public class SNProtoSyncMessageRead: NSObject {

    // MARK: - SNProtoSyncMessageReadBuilder

    @objc public class func builder(sender: String, timestamp: UInt64) -> SNProtoSyncMessageReadBuilder {
        return SNProtoSyncMessageReadBuilder(sender: sender, timestamp: timestamp)
    }

    // asBuilder() constructs a builder that reflects the proto's contents.
    @objc public func asBuilder() -> SNProtoSyncMessageReadBuilder {
        let builder = SNProtoSyncMessageReadBuilder(sender: sender, timestamp: timestamp)
        return builder
    }

    @objc public class SNProtoSyncMessageReadBuilder: NSObject {

        private var proto = SessionProtos_SyncMessage.Read()

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

        @objc public func build() throws -> SNProtoSyncMessageRead {
            return try SNProtoSyncMessageRead.parseProto(proto)
        }

        @objc public func buildSerializedData() throws -> Data {
            return try SNProtoSyncMessageRead.parseProto(proto).serializedData()
        }
    }

    fileprivate let proto: SessionProtos_SyncMessage.Read

    @objc public let sender: String

    @objc public let timestamp: UInt64

    private init(proto: SessionProtos_SyncMessage.Read,
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

    @objc public class func parseData(_ serializedData: Data) throws -> SNProtoSyncMessageRead {
        let proto = try SessionProtos_SyncMessage.Read(serializedData: serializedData)
        return try parseProto(proto)
    }

    fileprivate class func parseProto(_ proto: SessionProtos_SyncMessage.Read) throws -> SNProtoSyncMessageRead {
        guard proto.hasSender else {
            throw SNProtoError.invalidProtobuf(description: "\(logTag) missing required field: sender")
        }
        let sender = proto.sender

        guard proto.hasTimestamp else {
            throw SNProtoError.invalidProtobuf(description: "\(logTag) missing required field: timestamp")
        }
        let timestamp = proto.timestamp

        // MARK: - Begin Validation Logic for SNProtoSyncMessageRead -

        // MARK: - End Validation Logic for SNProtoSyncMessageRead -

        let result = SNProtoSyncMessageRead(proto: proto,
                                            sender: sender,
                                            timestamp: timestamp)
        return result
    }

    @objc public override var debugDescription: String {
        return "\(proto)"
    }
}

#if DEBUG

extension SNProtoSyncMessageRead {
    @objc public func serializedDataIgnoringErrors() -> Data? {
        return try! self.serializedData()
    }
}

extension SNProtoSyncMessageRead.SNProtoSyncMessageReadBuilder {
    @objc public func buildIgnoringErrors() -> SNProtoSyncMessageRead? {
        return try! self.build()
    }
}

#endif

// MARK: - SNProtoSyncMessageConfiguration

@objc public class SNProtoSyncMessageConfiguration: NSObject {

    // MARK: - SNProtoSyncMessageConfigurationBuilder

    @objc public class func builder() -> SNProtoSyncMessageConfigurationBuilder {
        return SNProtoSyncMessageConfigurationBuilder()
    }

    // asBuilder() constructs a builder that reflects the proto's contents.
    @objc public func asBuilder() -> SNProtoSyncMessageConfigurationBuilder {
        let builder = SNProtoSyncMessageConfigurationBuilder()
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

    @objc public class SNProtoSyncMessageConfigurationBuilder: NSObject {

        private var proto = SessionProtos_SyncMessage.Configuration()

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

        @objc public func build() throws -> SNProtoSyncMessageConfiguration {
            return try SNProtoSyncMessageConfiguration.parseProto(proto)
        }

        @objc public func buildSerializedData() throws -> Data {
            return try SNProtoSyncMessageConfiguration.parseProto(proto).serializedData()
        }
    }

    fileprivate let proto: SessionProtos_SyncMessage.Configuration

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

    private init(proto: SessionProtos_SyncMessage.Configuration) {
        self.proto = proto
    }

    @objc
    public func serializedData() throws -> Data {
        return try self.proto.serializedData()
    }

    @objc public class func parseData(_ serializedData: Data) throws -> SNProtoSyncMessageConfiguration {
        let proto = try SessionProtos_SyncMessage.Configuration(serializedData: serializedData)
        return try parseProto(proto)
    }

    fileprivate class func parseProto(_ proto: SessionProtos_SyncMessage.Configuration) throws -> SNProtoSyncMessageConfiguration {
        // MARK: - Begin Validation Logic for SNProtoSyncMessageConfiguration -

        // MARK: - End Validation Logic for SNProtoSyncMessageConfiguration -

        let result = SNProtoSyncMessageConfiguration(proto: proto)
        return result
    }

    @objc public override var debugDescription: String {
        return "\(proto)"
    }
}

#if DEBUG

extension SNProtoSyncMessageConfiguration {
    @objc public func serializedDataIgnoringErrors() -> Data? {
        return try! self.serializedData()
    }
}

extension SNProtoSyncMessageConfiguration.SNProtoSyncMessageConfigurationBuilder {
    @objc public func buildIgnoringErrors() -> SNProtoSyncMessageConfiguration? {
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
        builder.setOpenGroups(openGroups)
        return builder
    }

    @objc public class SNProtoSyncMessageBuilder: NSObject {

        private var proto = SessionProtos_SyncMessage()

        @objc fileprivate override init() {}

        @objc public func setSent(_ valueParam: SNProtoSyncMessageSent) {
            proto.sent = valueParam.proto
        }

        @objc public func setContacts(_ valueParam: SNProtoSyncMessageContacts) {
            proto.contacts = valueParam.proto
        }

        @objc public func setGroups(_ valueParam: SNProtoSyncMessageGroups) {
            proto.groups = valueParam.proto
        }

        @objc public func setRequest(_ valueParam: SNProtoSyncMessageRequest) {
            proto.request = valueParam.proto
        }

        @objc public func addRead(_ valueParam: SNProtoSyncMessageRead) {
            var items = proto.read
            items.append(valueParam.proto)
            proto.read = items
        }

        @objc public func setRead(_ wrappedItems: [SNProtoSyncMessageRead]) {
            proto.read = wrappedItems.map { $0.proto }
        }

        @objc public func setBlocked(_ valueParam: SNProtoSyncMessageBlocked) {
            proto.blocked = valueParam.proto
        }

        @objc public func setVerified(_ valueParam: SNProtoVerified) {
            proto.verified = valueParam.proto
        }

        @objc public func setConfiguration(_ valueParam: SNProtoSyncMessageConfiguration) {
            proto.configuration = valueParam.proto
        }

        @objc public func setPadding(_ valueParam: Data) {
            proto.padding = valueParam
        }

        @objc public func addOpenGroups(_ valueParam: SNProtoSyncMessageOpenGroupDetails) {
            var items = proto.openGroups
            items.append(valueParam.proto)
            proto.openGroups = items
        }

        @objc public func setOpenGroups(_ wrappedItems: [SNProtoSyncMessageOpenGroupDetails]) {
            proto.openGroups = wrappedItems.map { $0.proto }
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

    @objc public let contacts: SNProtoSyncMessageContacts?

    @objc public let groups: SNProtoSyncMessageGroups?

    @objc public let request: SNProtoSyncMessageRequest?

    @objc public let read: [SNProtoSyncMessageRead]

    @objc public let blocked: SNProtoSyncMessageBlocked?

    @objc public let verified: SNProtoVerified?

    @objc public let configuration: SNProtoSyncMessageConfiguration?

    @objc public let openGroups: [SNProtoSyncMessageOpenGroupDetails]

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
                 sent: SNProtoSyncMessageSent?,
                 contacts: SNProtoSyncMessageContacts?,
                 groups: SNProtoSyncMessageGroups?,
                 request: SNProtoSyncMessageRequest?,
                 read: [SNProtoSyncMessageRead],
                 blocked: SNProtoSyncMessageBlocked?,
                 verified: SNProtoVerified?,
                 configuration: SNProtoSyncMessageConfiguration?,
                 openGroups: [SNProtoSyncMessageOpenGroupDetails]) {
        self.proto = proto
        self.sent = sent
        self.contacts = contacts
        self.groups = groups
        self.request = request
        self.read = read
        self.blocked = blocked
        self.verified = verified
        self.configuration = configuration
        self.openGroups = openGroups
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

        var contacts: SNProtoSyncMessageContacts? = nil
        if proto.hasContacts {
            contacts = try SNProtoSyncMessageContacts.parseProto(proto.contacts)
        }

        var groups: SNProtoSyncMessageGroups? = nil
        if proto.hasGroups {
            groups = try SNProtoSyncMessageGroups.parseProto(proto.groups)
        }

        var request: SNProtoSyncMessageRequest? = nil
        if proto.hasRequest {
            request = try SNProtoSyncMessageRequest.parseProto(proto.request)
        }

        var read: [SNProtoSyncMessageRead] = []
        read = try proto.read.map { try SNProtoSyncMessageRead.parseProto($0) }

        var blocked: SNProtoSyncMessageBlocked? = nil
        if proto.hasBlocked {
            blocked = try SNProtoSyncMessageBlocked.parseProto(proto.blocked)
        }

        var verified: SNProtoVerified? = nil
        if proto.hasVerified {
            verified = try SNProtoVerified.parseProto(proto.verified)
        }

        var configuration: SNProtoSyncMessageConfiguration? = nil
        if proto.hasConfiguration {
            configuration = try SNProtoSyncMessageConfiguration.parseProto(proto.configuration)
        }

        var openGroups: [SNProtoSyncMessageOpenGroupDetails] = []
        openGroups = try proto.openGroups.map { try SNProtoSyncMessageOpenGroupDetails.parseProto($0) }

        // MARK: - Begin Validation Logic for SNProtoSyncMessage -

        // MARK: - End Validation Logic for SNProtoSyncMessage -

        let result = SNProtoSyncMessage(proto: proto,
                                        sent: sent,
                                        contacts: contacts,
                                        groups: groups,
                                        request: request,
                                        read: read,
                                        blocked: blocked,
                                        verified: verified,
                                        configuration: configuration,
                                        openGroups: openGroups)
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

        @objc public func setVerified(_ valueParam: SNProtoVerified) {
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

    @objc public let verified: SNProtoVerified?

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
                 avatar: SNProtoContactDetailsAvatar?,
                 verified: SNProtoVerified?) {
        self.proto = proto
        self.number = number
        self.avatar = avatar
        self.verified = verified
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

        var verified: SNProtoVerified? = nil
        if proto.hasVerified {
            verified = try SNProtoVerified.parseProto(proto.verified)
        }

        // MARK: - Begin Validation Logic for SNProtoContactDetails -

        // MARK: - End Validation Logic for SNProtoContactDetails -

        let result = SNProtoContactDetails(proto: proto,
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
