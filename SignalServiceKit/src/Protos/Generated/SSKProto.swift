//
// Copyright 2022 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import SignalCoreKit
import SwiftProtobuf

// WARNING: This code is generated. Only edit within the markers.

public enum SSKProtoError: Error {
    case invalidProtobuf(description: String)
}

// MARK: - SSKProtoEnvelopeType

@objc
public enum SSKProtoEnvelopeType: Int32 {
    case unknown = 0
    case ciphertext = 1
    case keyExchange = 2
    case prekeyBundle = 3
    case receipt = 5
    case unidentifiedSender = 6
    case senderkeyMessage = 7
    case plaintextContent = 8
}

private func SSKProtoEnvelopeTypeWrap(_ value: SignalServiceProtos_Envelope.TypeEnum) -> SSKProtoEnvelopeType {
    switch value {
    case .unknown: return .unknown
    case .ciphertext: return .ciphertext
    case .keyExchange: return .keyExchange
    case .prekeyBundle: return .prekeyBundle
    case .receipt: return .receipt
    case .unidentifiedSender: return .unidentifiedSender
    case .senderkeyMessage: return .senderkeyMessage
    case .plaintextContent: return .plaintextContent
    }
}

private func SSKProtoEnvelopeTypeUnwrap(_ value: SSKProtoEnvelopeType) -> SignalServiceProtos_Envelope.TypeEnum {
    switch value {
    case .unknown: return .unknown
    case .ciphertext: return .ciphertext
    case .keyExchange: return .keyExchange
    case .prekeyBundle: return .prekeyBundle
    case .receipt: return .receipt
    case .unidentifiedSender: return .unidentifiedSender
    case .senderkeyMessage: return .senderkeyMessage
    case .plaintextContent: return .plaintextContent
    }
}

// MARK: - SSKProtoEnvelope

@objc
public class SSKProtoEnvelope: NSObject, Codable, NSSecureCoding {

    fileprivate let proto: SignalServiceProtos_Envelope

    @objc
    public let timestamp: UInt64

    public var type: SSKProtoEnvelopeType? {
        guard hasType else {
            return nil
        }
        return SSKProtoEnvelopeTypeWrap(proto.type)
    }
    // This "unwrapped" accessor should only be used if the "has value" accessor has already been checked.
    @objc
    public var unwrappedType: SSKProtoEnvelopeType {
        if !hasType {
            // TODO: We could make this a crashing assert.
            owsFailDebug("Unsafe unwrap of missing optional: Envelope.type.")
        }
        return SSKProtoEnvelopeTypeWrap(proto.type)
    }
    @objc
    public var hasType: Bool {
        return proto.hasType
    }

    @objc
    public var sourceDevice: UInt32 {
        return proto.sourceDevice
    }
    @objc
    public var hasSourceDevice: Bool {
        return proto.hasSourceDevice
    }

    @objc
    public var destinationServiceID: String? {
        guard hasDestinationServiceID else {
            return nil
        }
        return proto.destinationServiceID
    }
    @objc
    public var hasDestinationServiceID: Bool {
        return proto.hasDestinationServiceID
    }

    @objc
    public var content: Data? {
        guard hasContent else {
            return nil
        }
        return proto.content
    }
    @objc
    public var hasContent: Bool {
        return proto.hasContent
    }

    @objc
    public var serverGuid: String? {
        guard hasServerGuid else {
            return nil
        }
        return proto.serverGuid
    }
    @objc
    public var hasServerGuid: Bool {
        return proto.hasServerGuid
    }

    @objc
    public var serverTimestamp: UInt64 {
        return proto.serverTimestamp
    }
    @objc
    public var hasServerTimestamp: Bool {
        return proto.hasServerTimestamp
    }

    @objc
    public var sourceServiceID: String? {
        guard hasSourceServiceID else {
            return nil
        }
        return proto.sourceServiceID
    }
    @objc
    public var hasSourceServiceID: Bool {
        return proto.hasSourceServiceID
    }

    @objc
    public var updatedPni: String? {
        guard hasUpdatedPni else {
            return nil
        }
        return proto.updatedPni
    }
    @objc
    public var hasUpdatedPni: Bool {
        return proto.hasUpdatedPni
    }

    @objc
    public var story: Bool {
        return proto.story
    }
    @objc
    public var hasStory: Bool {
        return proto.hasStory
    }

    @objc
    public var spamReportingToken: Data? {
        guard hasSpamReportingToken else {
            return nil
        }
        return proto.spamReportingToken
    }
    @objc
    public var hasSpamReportingToken: Bool {
        return proto.hasSpamReportingToken
    }

    public var hasUnknownFields: Bool {
        return !proto.unknownFields.data.isEmpty
    }
    public var unknownFields: SwiftProtobuf.UnknownStorage? {
        guard hasUnknownFields else { return nil }
        return proto.unknownFields
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

    @objc
    public convenience init(serializedData: Data) throws {
        let proto = try SignalServiceProtos_Envelope(serializedData: serializedData)
        try self.init(proto)
    }

    fileprivate convenience init(_ proto: SignalServiceProtos_Envelope) throws {
        guard proto.hasTimestamp else {
            throw SSKProtoError.invalidProtobuf(description: "\(Self.logTag()) missing required field: timestamp")
        }
        let timestamp = proto.timestamp

        self.init(proto: proto,
                  timestamp: timestamp)
    }

    public required convenience init(from decoder: Swift.Decoder) throws {
        let singleValueContainer = try decoder.singleValueContainer()
        let serializedData = try singleValueContainer.decode(Data.self)
        try self.init(serializedData: serializedData)
    }
    public func encode(to encoder: Swift.Encoder) throws {
        var singleValueContainer = encoder.singleValueContainer()
        try singleValueContainer.encode(try serializedData())
    }

    public static var supportsSecureCoding: Bool { true }

    public required convenience init?(coder: NSCoder) {
        guard let serializedData = coder.decodeData() else { return nil }
        do {
            try self.init(serializedData: serializedData)
        } catch {
            owsFailDebug("Failed to decode serialized data \(error)")
            return nil
        }
    }

    public func encode(with coder: NSCoder) {
        do {
            coder.encode(try serializedData())
        } catch {
            owsFailDebug("Failed to encode serialized data \(error)")
        }
    }

    @objc
    public override var debugDescription: String {
        return "\(proto)"
    }
}

extension SSKProtoEnvelope {
    @objc
    public static func builder(timestamp: UInt64) -> SSKProtoEnvelopeBuilder {
        return SSKProtoEnvelopeBuilder(timestamp: timestamp)
    }

    // asBuilder() constructs a builder that reflects the proto's contents.
    @objc
    public func asBuilder() -> SSKProtoEnvelopeBuilder {
        let builder = SSKProtoEnvelopeBuilder(timestamp: timestamp)
        if let _value = type {
            builder.setType(_value)
        }
        if hasSourceDevice {
            builder.setSourceDevice(sourceDevice)
        }
        if let _value = destinationServiceID {
            builder.setDestinationServiceID(_value)
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
        if let _value = sourceServiceID {
            builder.setSourceServiceID(_value)
        }
        if let _value = updatedPni {
            builder.setUpdatedPni(_value)
        }
        if hasStory {
            builder.setStory(story)
        }
        if let _value = spamReportingToken {
            builder.setSpamReportingToken(_value)
        }
        if let _value = unknownFields {
            builder.setUnknownFields(_value)
        }
        return builder
    }
}

@objc
public class SSKProtoEnvelopeBuilder: NSObject {

    private var proto = SignalServiceProtos_Envelope()

    @objc
    fileprivate override init() {}

    @objc
    fileprivate init(timestamp: UInt64) {
        super.init()

        setTimestamp(timestamp)
    }

    @objc
    public func setType(_ valueParam: SSKProtoEnvelopeType) {
        proto.type = SSKProtoEnvelopeTypeUnwrap(valueParam)
    }

    @objc
    public func setSourceDevice(_ valueParam: UInt32) {
        proto.sourceDevice = valueParam
    }

    @objc
    @available(swift, obsoleted: 1.0)
    public func setDestinationServiceID(_ valueParam: String?) {
        guard let valueParam = valueParam else { return }
        proto.destinationServiceID = valueParam
    }

    public func setDestinationServiceID(_ valueParam: String) {
        proto.destinationServiceID = valueParam
    }

    @objc
    public func setTimestamp(_ valueParam: UInt64) {
        proto.timestamp = valueParam
    }

    @objc
    @available(swift, obsoleted: 1.0)
    public func setContent(_ valueParam: Data?) {
        guard let valueParam = valueParam else { return }
        proto.content = valueParam
    }

    public func setContent(_ valueParam: Data) {
        proto.content = valueParam
    }

    @objc
    @available(swift, obsoleted: 1.0)
    public func setServerGuid(_ valueParam: String?) {
        guard let valueParam = valueParam else { return }
        proto.serverGuid = valueParam
    }

    public func setServerGuid(_ valueParam: String) {
        proto.serverGuid = valueParam
    }

    @objc
    public func setServerTimestamp(_ valueParam: UInt64) {
        proto.serverTimestamp = valueParam
    }

    @objc
    @available(swift, obsoleted: 1.0)
    public func setSourceServiceID(_ valueParam: String?) {
        guard let valueParam = valueParam else { return }
        proto.sourceServiceID = valueParam
    }

    public func setSourceServiceID(_ valueParam: String) {
        proto.sourceServiceID = valueParam
    }

    @objc
    @available(swift, obsoleted: 1.0)
    public func setUpdatedPni(_ valueParam: String?) {
        guard let valueParam = valueParam else { return }
        proto.updatedPni = valueParam
    }

    public func setUpdatedPni(_ valueParam: String) {
        proto.updatedPni = valueParam
    }

    @objc
    public func setStory(_ valueParam: Bool) {
        proto.story = valueParam
    }

    @objc
    @available(swift, obsoleted: 1.0)
    public func setSpamReportingToken(_ valueParam: Data?) {
        guard let valueParam = valueParam else { return }
        proto.spamReportingToken = valueParam
    }

    public func setSpamReportingToken(_ valueParam: Data) {
        proto.spamReportingToken = valueParam
    }

    public func setUnknownFields(_ unknownFields: SwiftProtobuf.UnknownStorage) {
        proto.unknownFields = unknownFields
    }

    @objc
    public func build() throws -> SSKProtoEnvelope {
        return try SSKProtoEnvelope(proto)
    }

    @objc
    public func buildSerializedData() throws -> Data {
        return try SSKProtoEnvelope(proto).serializedData()
    }
}

#if TESTABLE_BUILD

extension SSKProtoEnvelope {
    @objc
    public func serializedDataIgnoringErrors() -> Data? {
        return try! self.serializedData()
    }
}

extension SSKProtoEnvelopeBuilder {
    @objc
    public func buildIgnoringErrors() -> SSKProtoEnvelope? {
        return try! self.build()
    }
}

#endif

// MARK: - SSKProtoTypingMessageAction

@objc
public enum SSKProtoTypingMessageAction: Int32 {
    case started = 0
    case stopped = 1
}

private func SSKProtoTypingMessageActionWrap(_ value: SignalServiceProtos_TypingMessage.Action) -> SSKProtoTypingMessageAction {
    switch value {
    case .started: return .started
    case .stopped: return .stopped
    }
}

private func SSKProtoTypingMessageActionUnwrap(_ value: SSKProtoTypingMessageAction) -> SignalServiceProtos_TypingMessage.Action {
    switch value {
    case .started: return .started
    case .stopped: return .stopped
    }
}

// MARK: - SSKProtoTypingMessage

@objc
public class SSKProtoTypingMessage: NSObject, Codable, NSSecureCoding {

    fileprivate let proto: SignalServiceProtos_TypingMessage

    @objc
    public let timestamp: UInt64

    public var action: SSKProtoTypingMessageAction? {
        guard hasAction else {
            return nil
        }
        return SSKProtoTypingMessageActionWrap(proto.action)
    }
    // This "unwrapped" accessor should only be used if the "has value" accessor has already been checked.
    @objc
    public var unwrappedAction: SSKProtoTypingMessageAction {
        if !hasAction {
            // TODO: We could make this a crashing assert.
            owsFailDebug("Unsafe unwrap of missing optional: TypingMessage.action.")
        }
        return SSKProtoTypingMessageActionWrap(proto.action)
    }
    @objc
    public var hasAction: Bool {
        return proto.hasAction
    }

    @objc
    public var groupID: Data? {
        guard hasGroupID else {
            return nil
        }
        return proto.groupID
    }
    @objc
    public var hasGroupID: Bool {
        return proto.hasGroupID
    }

    public var hasUnknownFields: Bool {
        return !proto.unknownFields.data.isEmpty
    }
    public var unknownFields: SwiftProtobuf.UnknownStorage? {
        guard hasUnknownFields else { return nil }
        return proto.unknownFields
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

    @objc
    public convenience init(serializedData: Data) throws {
        let proto = try SignalServiceProtos_TypingMessage(serializedData: serializedData)
        try self.init(proto)
    }

    fileprivate convenience init(_ proto: SignalServiceProtos_TypingMessage) throws {
        guard proto.hasTimestamp else {
            throw SSKProtoError.invalidProtobuf(description: "\(Self.logTag()) missing required field: timestamp")
        }
        let timestamp = proto.timestamp

        self.init(proto: proto,
                  timestamp: timestamp)
    }

    public required convenience init(from decoder: Swift.Decoder) throws {
        let singleValueContainer = try decoder.singleValueContainer()
        let serializedData = try singleValueContainer.decode(Data.self)
        try self.init(serializedData: serializedData)
    }
    public func encode(to encoder: Swift.Encoder) throws {
        var singleValueContainer = encoder.singleValueContainer()
        try singleValueContainer.encode(try serializedData())
    }

    public static var supportsSecureCoding: Bool { true }

    public required convenience init?(coder: NSCoder) {
        guard let serializedData = coder.decodeData() else { return nil }
        do {
            try self.init(serializedData: serializedData)
        } catch {
            owsFailDebug("Failed to decode serialized data \(error)")
            return nil
        }
    }

    public func encode(with coder: NSCoder) {
        do {
            coder.encode(try serializedData())
        } catch {
            owsFailDebug("Failed to encode serialized data \(error)")
        }
    }

    @objc
    public override var debugDescription: String {
        return "\(proto)"
    }
}

extension SSKProtoTypingMessage {
    @objc
    public static func builder(timestamp: UInt64) -> SSKProtoTypingMessageBuilder {
        return SSKProtoTypingMessageBuilder(timestamp: timestamp)
    }

    // asBuilder() constructs a builder that reflects the proto's contents.
    @objc
    public func asBuilder() -> SSKProtoTypingMessageBuilder {
        let builder = SSKProtoTypingMessageBuilder(timestamp: timestamp)
        if let _value = action {
            builder.setAction(_value)
        }
        if let _value = groupID {
            builder.setGroupID(_value)
        }
        if let _value = unknownFields {
            builder.setUnknownFields(_value)
        }
        return builder
    }
}

@objc
public class SSKProtoTypingMessageBuilder: NSObject {

    private var proto = SignalServiceProtos_TypingMessage()

    @objc
    fileprivate override init() {}

    @objc
    fileprivate init(timestamp: UInt64) {
        super.init()

        setTimestamp(timestamp)
    }

    @objc
    public func setTimestamp(_ valueParam: UInt64) {
        proto.timestamp = valueParam
    }

    @objc
    public func setAction(_ valueParam: SSKProtoTypingMessageAction) {
        proto.action = SSKProtoTypingMessageActionUnwrap(valueParam)
    }

    @objc
    @available(swift, obsoleted: 1.0)
    public func setGroupID(_ valueParam: Data?) {
        guard let valueParam = valueParam else { return }
        proto.groupID = valueParam
    }

    public func setGroupID(_ valueParam: Data) {
        proto.groupID = valueParam
    }

    public func setUnknownFields(_ unknownFields: SwiftProtobuf.UnknownStorage) {
        proto.unknownFields = unknownFields
    }

    @objc
    public func build() throws -> SSKProtoTypingMessage {
        return try SSKProtoTypingMessage(proto)
    }

    @objc
    public func buildSerializedData() throws -> Data {
        return try SSKProtoTypingMessage(proto).serializedData()
    }
}

#if TESTABLE_BUILD

extension SSKProtoTypingMessage {
    @objc
    public func serializedDataIgnoringErrors() -> Data? {
        return try! self.serializedData()
    }
}

extension SSKProtoTypingMessageBuilder {
    @objc
    public func buildIgnoringErrors() -> SSKProtoTypingMessage? {
        return try! self.build()
    }
}

#endif

// MARK: - SSKProtoStoryMessage

@objc
public class SSKProtoStoryMessage: NSObject, Codable, NSSecureCoding {

    fileprivate let proto: SignalServiceProtos_StoryMessage

    @objc
    public let group: SSKProtoGroupContextV2?

    @objc
    public let fileAttachment: SSKProtoAttachmentPointer?

    @objc
    public let textAttachment: SSKProtoTextAttachment?

    @objc
    public let bodyRanges: [SSKProtoBodyRange]

    @objc
    public var profileKey: Data? {
        guard hasProfileKey else {
            return nil
        }
        return proto.profileKey
    }
    @objc
    public var hasProfileKey: Bool {
        return proto.hasProfileKey
    }

    @objc
    public var allowsReplies: Bool {
        return proto.allowsReplies
    }
    @objc
    public var hasAllowsReplies: Bool {
        return proto.hasAllowsReplies
    }

    public var hasUnknownFields: Bool {
        return !proto.unknownFields.data.isEmpty
    }
    public var unknownFields: SwiftProtobuf.UnknownStorage? {
        guard hasUnknownFields else { return nil }
        return proto.unknownFields
    }

    private init(proto: SignalServiceProtos_StoryMessage,
                 group: SSKProtoGroupContextV2?,
                 fileAttachment: SSKProtoAttachmentPointer?,
                 textAttachment: SSKProtoTextAttachment?,
                 bodyRanges: [SSKProtoBodyRange]) {
        self.proto = proto
        self.group = group
        self.fileAttachment = fileAttachment
        self.textAttachment = textAttachment
        self.bodyRanges = bodyRanges
    }

    @objc
    public func serializedData() throws -> Data {
        return try self.proto.serializedData()
    }

    @objc
    public convenience init(serializedData: Data) throws {
        let proto = try SignalServiceProtos_StoryMessage(serializedData: serializedData)
        try self.init(proto)
    }

    fileprivate convenience init(_ proto: SignalServiceProtos_StoryMessage) throws {
        var group: SSKProtoGroupContextV2?
        if proto.hasGroup {
            group = SSKProtoGroupContextV2(proto.group)
        }

        var fileAttachment: SSKProtoAttachmentPointer?
        if proto.hasFileAttachment {
            fileAttachment = SSKProtoAttachmentPointer(proto.fileAttachment)
        }

        var textAttachment: SSKProtoTextAttachment?
        if proto.hasTextAttachment {
            textAttachment = try SSKProtoTextAttachment(proto.textAttachment)
        }

        var bodyRanges: [SSKProtoBodyRange] = []
        bodyRanges = proto.bodyRanges.map { SSKProtoBodyRange($0) }

        self.init(proto: proto,
                  group: group,
                  fileAttachment: fileAttachment,
                  textAttachment: textAttachment,
                  bodyRanges: bodyRanges)
    }

    public required convenience init(from decoder: Swift.Decoder) throws {
        let singleValueContainer = try decoder.singleValueContainer()
        let serializedData = try singleValueContainer.decode(Data.self)
        try self.init(serializedData: serializedData)
    }
    public func encode(to encoder: Swift.Encoder) throws {
        var singleValueContainer = encoder.singleValueContainer()
        try singleValueContainer.encode(try serializedData())
    }

    public static var supportsSecureCoding: Bool { true }

    public required convenience init?(coder: NSCoder) {
        guard let serializedData = coder.decodeData() else { return nil }
        do {
            try self.init(serializedData: serializedData)
        } catch {
            owsFailDebug("Failed to decode serialized data \(error)")
            return nil
        }
    }

    public func encode(with coder: NSCoder) {
        do {
            coder.encode(try serializedData())
        } catch {
            owsFailDebug("Failed to encode serialized data \(error)")
        }
    }

    @objc
    public override var debugDescription: String {
        return "\(proto)"
    }
}

extension SSKProtoStoryMessage {
    @objc
    public static func builder() -> SSKProtoStoryMessageBuilder {
        return SSKProtoStoryMessageBuilder()
    }

    // asBuilder() constructs a builder that reflects the proto's contents.
    @objc
    public func asBuilder() -> SSKProtoStoryMessageBuilder {
        let builder = SSKProtoStoryMessageBuilder()
        if let _value = profileKey {
            builder.setProfileKey(_value)
        }
        if let _value = group {
            builder.setGroup(_value)
        }
        if let _value = fileAttachment {
            builder.setFileAttachment(_value)
        }
        if let _value = textAttachment {
            builder.setTextAttachment(_value)
        }
        if hasAllowsReplies {
            builder.setAllowsReplies(allowsReplies)
        }
        builder.setBodyRanges(bodyRanges)
        if let _value = unknownFields {
            builder.setUnknownFields(_value)
        }
        return builder
    }
}

@objc
public class SSKProtoStoryMessageBuilder: NSObject {

    private var proto = SignalServiceProtos_StoryMessage()

    @objc
    fileprivate override init() {}

    @objc
    @available(swift, obsoleted: 1.0)
    public func setProfileKey(_ valueParam: Data?) {
        guard let valueParam = valueParam else { return }
        proto.profileKey = valueParam
    }

    public func setProfileKey(_ valueParam: Data) {
        proto.profileKey = valueParam
    }

    @objc
    @available(swift, obsoleted: 1.0)
    public func setGroup(_ valueParam: SSKProtoGroupContextV2?) {
        guard let valueParam = valueParam else { return }
        proto.group = valueParam.proto
    }

    public func setGroup(_ valueParam: SSKProtoGroupContextV2) {
        proto.group = valueParam.proto
    }

    @objc
    @available(swift, obsoleted: 1.0)
    public func setFileAttachment(_ valueParam: SSKProtoAttachmentPointer?) {
        guard let valueParam = valueParam else { return }
        proto.fileAttachment = valueParam.proto
    }

    public func setFileAttachment(_ valueParam: SSKProtoAttachmentPointer) {
        proto.fileAttachment = valueParam.proto
    }

    @objc
    @available(swift, obsoleted: 1.0)
    public func setTextAttachment(_ valueParam: SSKProtoTextAttachment?) {
        guard let valueParam = valueParam else { return }
        proto.textAttachment = valueParam.proto
    }

    public func setTextAttachment(_ valueParam: SSKProtoTextAttachment) {
        proto.textAttachment = valueParam.proto
    }

    @objc
    public func setAllowsReplies(_ valueParam: Bool) {
        proto.allowsReplies = valueParam
    }

    @objc
    public func addBodyRanges(_ valueParam: SSKProtoBodyRange) {
        proto.bodyRanges.append(valueParam.proto)
    }

    @objc
    public func setBodyRanges(_ wrappedItems: [SSKProtoBodyRange]) {
        proto.bodyRanges = wrappedItems.map { $0.proto }
    }

    public func setUnknownFields(_ unknownFields: SwiftProtobuf.UnknownStorage) {
        proto.unknownFields = unknownFields
    }

    @objc
    public func build() throws -> SSKProtoStoryMessage {
        return try SSKProtoStoryMessage(proto)
    }

    @objc
    public func buildSerializedData() throws -> Data {
        return try SSKProtoStoryMessage(proto).serializedData()
    }
}

#if TESTABLE_BUILD

extension SSKProtoStoryMessage {
    @objc
    public func serializedDataIgnoringErrors() -> Data? {
        return try! self.serializedData()
    }
}

extension SSKProtoStoryMessageBuilder {
    @objc
    public func buildIgnoringErrors() -> SSKProtoStoryMessage? {
        return try! self.build()
    }
}

#endif

// MARK: - SSKProtoPreview

@objc
public class SSKProtoPreview: NSObject, Codable, NSSecureCoding {

    fileprivate let proto: SignalServiceProtos_Preview

    @objc
    public let url: String

    @objc
    public let image: SSKProtoAttachmentPointer?

    @objc
    public var title: String? {
        guard hasTitle else {
            return nil
        }
        return proto.title
    }
    @objc
    public var hasTitle: Bool {
        return proto.hasTitle
    }

    @objc
    public var previewDescription: String? {
        guard hasPreviewDescription else {
            return nil
        }
        return proto.previewDescription
    }
    @objc
    public var hasPreviewDescription: Bool {
        return proto.hasPreviewDescription
    }

    @objc
    public var date: UInt64 {
        return proto.date
    }
    @objc
    public var hasDate: Bool {
        return proto.hasDate
    }

    public var hasUnknownFields: Bool {
        return !proto.unknownFields.data.isEmpty
    }
    public var unknownFields: SwiftProtobuf.UnknownStorage? {
        guard hasUnknownFields else { return nil }
        return proto.unknownFields
    }

    private init(proto: SignalServiceProtos_Preview,
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

    @objc
    public convenience init(serializedData: Data) throws {
        let proto = try SignalServiceProtos_Preview(serializedData: serializedData)
        try self.init(proto)
    }

    fileprivate convenience init(_ proto: SignalServiceProtos_Preview) throws {
        guard proto.hasURL else {
            throw SSKProtoError.invalidProtobuf(description: "\(Self.logTag()) missing required field: url")
        }
        let url = proto.url

        var image: SSKProtoAttachmentPointer?
        if proto.hasImage {
            image = SSKProtoAttachmentPointer(proto.image)
        }

        self.init(proto: proto,
                  url: url,
                  image: image)
    }

    public required convenience init(from decoder: Swift.Decoder) throws {
        let singleValueContainer = try decoder.singleValueContainer()
        let serializedData = try singleValueContainer.decode(Data.self)
        try self.init(serializedData: serializedData)
    }
    public func encode(to encoder: Swift.Encoder) throws {
        var singleValueContainer = encoder.singleValueContainer()
        try singleValueContainer.encode(try serializedData())
    }

    public static var supportsSecureCoding: Bool { true }

    public required convenience init?(coder: NSCoder) {
        guard let serializedData = coder.decodeData() else { return nil }
        do {
            try self.init(serializedData: serializedData)
        } catch {
            owsFailDebug("Failed to decode serialized data \(error)")
            return nil
        }
    }

    public func encode(with coder: NSCoder) {
        do {
            coder.encode(try serializedData())
        } catch {
            owsFailDebug("Failed to encode serialized data \(error)")
        }
    }

    @objc
    public override var debugDescription: String {
        return "\(proto)"
    }
}

extension SSKProtoPreview {
    @objc
    public static func builder(url: String) -> SSKProtoPreviewBuilder {
        return SSKProtoPreviewBuilder(url: url)
    }

    // asBuilder() constructs a builder that reflects the proto's contents.
    @objc
    public func asBuilder() -> SSKProtoPreviewBuilder {
        let builder = SSKProtoPreviewBuilder(url: url)
        if let _value = title {
            builder.setTitle(_value)
        }
        if let _value = image {
            builder.setImage(_value)
        }
        if let _value = previewDescription {
            builder.setPreviewDescription(_value)
        }
        if hasDate {
            builder.setDate(date)
        }
        if let _value = unknownFields {
            builder.setUnknownFields(_value)
        }
        return builder
    }
}

@objc
public class SSKProtoPreviewBuilder: NSObject {

    private var proto = SignalServiceProtos_Preview()

    @objc
    fileprivate override init() {}

    @objc
    fileprivate init(url: String) {
        super.init()

        setUrl(url)
    }

    @objc
    @available(swift, obsoleted: 1.0)
    public func setUrl(_ valueParam: String?) {
        guard let valueParam = valueParam else { return }
        proto.url = valueParam
    }

    public func setUrl(_ valueParam: String) {
        proto.url = valueParam
    }

    @objc
    @available(swift, obsoleted: 1.0)
    public func setTitle(_ valueParam: String?) {
        guard let valueParam = valueParam else { return }
        proto.title = valueParam
    }

    public func setTitle(_ valueParam: String) {
        proto.title = valueParam
    }

    @objc
    @available(swift, obsoleted: 1.0)
    public func setImage(_ valueParam: SSKProtoAttachmentPointer?) {
        guard let valueParam = valueParam else { return }
        proto.image = valueParam.proto
    }

    public func setImage(_ valueParam: SSKProtoAttachmentPointer) {
        proto.image = valueParam.proto
    }

    @objc
    @available(swift, obsoleted: 1.0)
    public func setPreviewDescription(_ valueParam: String?) {
        guard let valueParam = valueParam else { return }
        proto.previewDescription = valueParam
    }

    public func setPreviewDescription(_ valueParam: String) {
        proto.previewDescription = valueParam
    }

    @objc
    public func setDate(_ valueParam: UInt64) {
        proto.date = valueParam
    }

    public func setUnknownFields(_ unknownFields: SwiftProtobuf.UnknownStorage) {
        proto.unknownFields = unknownFields
    }

    @objc
    public func build() throws -> SSKProtoPreview {
        return try SSKProtoPreview(proto)
    }

    @objc
    public func buildSerializedData() throws -> Data {
        return try SSKProtoPreview(proto).serializedData()
    }
}

#if TESTABLE_BUILD

extension SSKProtoPreview {
    @objc
    public func serializedDataIgnoringErrors() -> Data? {
        return try! self.serializedData()
    }
}

extension SSKProtoPreviewBuilder {
    @objc
    public func buildIgnoringErrors() -> SSKProtoPreview? {
        return try! self.build()
    }
}

#endif

// MARK: - SSKProtoTextAttachmentGradient

@objc
public class SSKProtoTextAttachmentGradient: NSObject, Codable, NSSecureCoding {

    fileprivate let proto: SignalServiceProtos_TextAttachment.Gradient

    @objc
    public var startColor: UInt32 {
        return proto.startColor
    }
    @objc
    public var hasStartColor: Bool {
        return proto.hasStartColor
    }

    @objc
    public var endColor: UInt32 {
        return proto.endColor
    }
    @objc
    public var hasEndColor: Bool {
        return proto.hasEndColor
    }

    @objc
    public var angle: UInt32 {
        return proto.angle
    }
    @objc
    public var hasAngle: Bool {
        return proto.hasAngle
    }

    @objc
    public var colors: [UInt32] {
        return proto.colors
    }

    @objc
    public var positions: [Float] {
        return proto.positions
    }

    public var hasUnknownFields: Bool {
        return !proto.unknownFields.data.isEmpty
    }
    public var unknownFields: SwiftProtobuf.UnknownStorage? {
        guard hasUnknownFields else { return nil }
        return proto.unknownFields
    }

    private init(proto: SignalServiceProtos_TextAttachment.Gradient) {
        self.proto = proto
    }

    @objc
    public func serializedData() throws -> Data {
        return try self.proto.serializedData()
    }

    @objc
    public convenience init(serializedData: Data) throws {
        let proto = try SignalServiceProtos_TextAttachment.Gradient(serializedData: serializedData)
        self.init(proto)
    }

    fileprivate convenience init(_ proto: SignalServiceProtos_TextAttachment.Gradient) {
        self.init(proto: proto)
    }

    public required convenience init(from decoder: Swift.Decoder) throws {
        let singleValueContainer = try decoder.singleValueContainer()
        let serializedData = try singleValueContainer.decode(Data.self)
        try self.init(serializedData: serializedData)
    }
    public func encode(to encoder: Swift.Encoder) throws {
        var singleValueContainer = encoder.singleValueContainer()
        try singleValueContainer.encode(try serializedData())
    }

    public static var supportsSecureCoding: Bool { true }

    public required convenience init?(coder: NSCoder) {
        guard let serializedData = coder.decodeData() else { return nil }
        do {
            try self.init(serializedData: serializedData)
        } catch {
            owsFailDebug("Failed to decode serialized data \(error)")
            return nil
        }
    }

    public func encode(with coder: NSCoder) {
        do {
            coder.encode(try serializedData())
        } catch {
            owsFailDebug("Failed to encode serialized data \(error)")
        }
    }

    @objc
    public override var debugDescription: String {
        return "\(proto)"
    }
}

extension SSKProtoTextAttachmentGradient {
    @objc
    public static func builder() -> SSKProtoTextAttachmentGradientBuilder {
        return SSKProtoTextAttachmentGradientBuilder()
    }

    // asBuilder() constructs a builder that reflects the proto's contents.
    @objc
    public func asBuilder() -> SSKProtoTextAttachmentGradientBuilder {
        let builder = SSKProtoTextAttachmentGradientBuilder()
        if hasStartColor {
            builder.setStartColor(startColor)
        }
        if hasEndColor {
            builder.setEndColor(endColor)
        }
        if hasAngle {
            builder.setAngle(angle)
        }
        builder.setColors(colors)
        builder.setPositions(positions)
        if let _value = unknownFields {
            builder.setUnknownFields(_value)
        }
        return builder
    }
}

@objc
public class SSKProtoTextAttachmentGradientBuilder: NSObject {

    private var proto = SignalServiceProtos_TextAttachment.Gradient()

    @objc
    fileprivate override init() {}

    @objc
    public func setStartColor(_ valueParam: UInt32) {
        proto.startColor = valueParam
    }

    @objc
    public func setEndColor(_ valueParam: UInt32) {
        proto.endColor = valueParam
    }

    @objc
    public func setAngle(_ valueParam: UInt32) {
        proto.angle = valueParam
    }

    @objc
    public func addColors(_ valueParam: UInt32) {
        proto.colors.append(valueParam)
    }

    @objc
    public func setColors(_ wrappedItems: [UInt32]) {
        proto.colors = wrappedItems
    }

    @objc
    public func addPositions(_ valueParam: Float) {
        proto.positions.append(valueParam)
    }

    @objc
    public func setPositions(_ wrappedItems: [Float]) {
        proto.positions = wrappedItems
    }

    public func setUnknownFields(_ unknownFields: SwiftProtobuf.UnknownStorage) {
        proto.unknownFields = unknownFields
    }

    @objc
    public func build() throws -> SSKProtoTextAttachmentGradient {
        return SSKProtoTextAttachmentGradient(proto)
    }

    @objc
    public func buildInfallibly() -> SSKProtoTextAttachmentGradient {
        return SSKProtoTextAttachmentGradient(proto)
    }

    @objc
    public func buildSerializedData() throws -> Data {
        return try SSKProtoTextAttachmentGradient(proto).serializedData()
    }
}

#if TESTABLE_BUILD

extension SSKProtoTextAttachmentGradient {
    @objc
    public func serializedDataIgnoringErrors() -> Data? {
        return try! self.serializedData()
    }
}

extension SSKProtoTextAttachmentGradientBuilder {
    @objc
    public func buildIgnoringErrors() -> SSKProtoTextAttachmentGradient? {
        return self.buildInfallibly()
    }
}

#endif

// MARK: - SSKProtoTextAttachmentStyle

@objc
public enum SSKProtoTextAttachmentStyle: Int32 {
    case `default` = 0
    case regular = 1
    case bold = 2
    case serif = 3
    case script = 4
    case condensed = 5
}

private func SSKProtoTextAttachmentStyleWrap(_ value: SignalServiceProtos_TextAttachment.Style) -> SSKProtoTextAttachmentStyle {
    switch value {
    case .default: return .default
    case .regular: return .regular
    case .bold: return .bold
    case .serif: return .serif
    case .script: return .script
    case .condensed: return .condensed
    }
}

private func SSKProtoTextAttachmentStyleUnwrap(_ value: SSKProtoTextAttachmentStyle) -> SignalServiceProtos_TextAttachment.Style {
    switch value {
    case .default: return .default
    case .regular: return .regular
    case .bold: return .bold
    case .serif: return .serif
    case .script: return .script
    case .condensed: return .condensed
    }
}

// MARK: - SSKProtoTextAttachment

@objc
public class SSKProtoTextAttachment: NSObject, Codable, NSSecureCoding {

    fileprivate let proto: SignalServiceProtos_TextAttachment

    @objc
    public let preview: SSKProtoPreview?

    @objc
    public let gradient: SSKProtoTextAttachmentGradient?

    @objc
    public var text: String? {
        guard hasText else {
            return nil
        }
        return proto.text
    }
    @objc
    public var hasText: Bool {
        return proto.hasText
    }

    public var textStyle: SSKProtoTextAttachmentStyle? {
        guard hasTextStyle else {
            return nil
        }
        return SSKProtoTextAttachmentStyleWrap(proto.textStyle)
    }
    // This "unwrapped" accessor should only be used if the "has value" accessor has already been checked.
    @objc
    public var unwrappedTextStyle: SSKProtoTextAttachmentStyle {
        if !hasTextStyle {
            // TODO: We could make this a crashing assert.
            owsFailDebug("Unsafe unwrap of missing optional: TextAttachment.textStyle.")
        }
        return SSKProtoTextAttachmentStyleWrap(proto.textStyle)
    }
    @objc
    public var hasTextStyle: Bool {
        return proto.hasTextStyle
    }

    @objc
    public var textForegroundColor: UInt32 {
        return proto.textForegroundColor
    }
    @objc
    public var hasTextForegroundColor: Bool {
        return proto.hasTextForegroundColor
    }

    @objc
    public var textBackgroundColor: UInt32 {
        return proto.textBackgroundColor
    }
    @objc
    public var hasTextBackgroundColor: Bool {
        return proto.hasTextBackgroundColor
    }

    @objc
    public var color: UInt32 {
        return proto.color
    }
    @objc
    public var hasColor: Bool {
        return proto.hasColor
    }

    public var hasUnknownFields: Bool {
        return !proto.unknownFields.data.isEmpty
    }
    public var unknownFields: SwiftProtobuf.UnknownStorage? {
        guard hasUnknownFields else { return nil }
        return proto.unknownFields
    }

    private init(proto: SignalServiceProtos_TextAttachment,
                 preview: SSKProtoPreview?,
                 gradient: SSKProtoTextAttachmentGradient?) {
        self.proto = proto
        self.preview = preview
        self.gradient = gradient
    }

    @objc
    public func serializedData() throws -> Data {
        return try self.proto.serializedData()
    }

    @objc
    public convenience init(serializedData: Data) throws {
        let proto = try SignalServiceProtos_TextAttachment(serializedData: serializedData)
        try self.init(proto)
    }

    fileprivate convenience init(_ proto: SignalServiceProtos_TextAttachment) throws {
        var preview: SSKProtoPreview?
        if proto.hasPreview {
            preview = try SSKProtoPreview(proto.preview)
        }

        var gradient: SSKProtoTextAttachmentGradient?
        if proto.hasGradient {
            gradient = SSKProtoTextAttachmentGradient(proto.gradient)
        }

        self.init(proto: proto,
                  preview: preview,
                  gradient: gradient)
    }

    public required convenience init(from decoder: Swift.Decoder) throws {
        let singleValueContainer = try decoder.singleValueContainer()
        let serializedData = try singleValueContainer.decode(Data.self)
        try self.init(serializedData: serializedData)
    }
    public func encode(to encoder: Swift.Encoder) throws {
        var singleValueContainer = encoder.singleValueContainer()
        try singleValueContainer.encode(try serializedData())
    }

    public static var supportsSecureCoding: Bool { true }

    public required convenience init?(coder: NSCoder) {
        guard let serializedData = coder.decodeData() else { return nil }
        do {
            try self.init(serializedData: serializedData)
        } catch {
            owsFailDebug("Failed to decode serialized data \(error)")
            return nil
        }
    }

    public func encode(with coder: NSCoder) {
        do {
            coder.encode(try serializedData())
        } catch {
            owsFailDebug("Failed to encode serialized data \(error)")
        }
    }

    @objc
    public override var debugDescription: String {
        return "\(proto)"
    }
}

extension SSKProtoTextAttachment {
    @objc
    public static func builder() -> SSKProtoTextAttachmentBuilder {
        return SSKProtoTextAttachmentBuilder()
    }

    // asBuilder() constructs a builder that reflects the proto's contents.
    @objc
    public func asBuilder() -> SSKProtoTextAttachmentBuilder {
        let builder = SSKProtoTextAttachmentBuilder()
        if let _value = text {
            builder.setText(_value)
        }
        if let _value = textStyle {
            builder.setTextStyle(_value)
        }
        if hasTextForegroundColor {
            builder.setTextForegroundColor(textForegroundColor)
        }
        if hasTextBackgroundColor {
            builder.setTextBackgroundColor(textBackgroundColor)
        }
        if let _value = preview {
            builder.setPreview(_value)
        }
        if let _value = gradient {
            builder.setGradient(_value)
        }
        if hasColor {
            builder.setColor(color)
        }
        if let _value = unknownFields {
            builder.setUnknownFields(_value)
        }
        return builder
    }
}

@objc
public class SSKProtoTextAttachmentBuilder: NSObject {

    private var proto = SignalServiceProtos_TextAttachment()

    @objc
    fileprivate override init() {}

    @objc
    @available(swift, obsoleted: 1.0)
    public func setText(_ valueParam: String?) {
        guard let valueParam = valueParam else { return }
        proto.text = valueParam
    }

    public func setText(_ valueParam: String) {
        proto.text = valueParam
    }

    @objc
    public func setTextStyle(_ valueParam: SSKProtoTextAttachmentStyle) {
        proto.textStyle = SSKProtoTextAttachmentStyleUnwrap(valueParam)
    }

    @objc
    public func setTextForegroundColor(_ valueParam: UInt32) {
        proto.textForegroundColor = valueParam
    }

    @objc
    public func setTextBackgroundColor(_ valueParam: UInt32) {
        proto.textBackgroundColor = valueParam
    }

    @objc
    @available(swift, obsoleted: 1.0)
    public func setPreview(_ valueParam: SSKProtoPreview?) {
        guard let valueParam = valueParam else { return }
        proto.preview = valueParam.proto
    }

    public func setPreview(_ valueParam: SSKProtoPreview) {
        proto.preview = valueParam.proto
    }

    @objc
    @available(swift, obsoleted: 1.0)
    public func setGradient(_ valueParam: SSKProtoTextAttachmentGradient?) {
        guard let valueParam = valueParam else { return }
        proto.gradient = valueParam.proto
    }

    public func setGradient(_ valueParam: SSKProtoTextAttachmentGradient) {
        proto.gradient = valueParam.proto
    }

    @objc
    public func setColor(_ valueParam: UInt32) {
        proto.color = valueParam
    }

    public func setUnknownFields(_ unknownFields: SwiftProtobuf.UnknownStorage) {
        proto.unknownFields = unknownFields
    }

    @objc
    public func build() throws -> SSKProtoTextAttachment {
        return try SSKProtoTextAttachment(proto)
    }

    @objc
    public func buildSerializedData() throws -> Data {
        return try SSKProtoTextAttachment(proto).serializedData()
    }
}

#if TESTABLE_BUILD

extension SSKProtoTextAttachment {
    @objc
    public func serializedDataIgnoringErrors() -> Data? {
        return try! self.serializedData()
    }
}

extension SSKProtoTextAttachmentBuilder {
    @objc
    public func buildIgnoringErrors() -> SSKProtoTextAttachment? {
        return try! self.build()
    }
}

#endif

// MARK: - SSKProtoContent

@objc
public class SSKProtoContent: NSObject, Codable, NSSecureCoding {

    fileprivate let proto: SignalServiceProtos_Content

    @objc
    public let dataMessage: SSKProtoDataMessage?

    @objc
    public let syncMessage: SSKProtoSyncMessage?

    @objc
    public let callMessage: SSKProtoCallMessage?

    @objc
    public let nullMessage: SSKProtoNullMessage?

    @objc
    public let receiptMessage: SSKProtoReceiptMessage?

    @objc
    public let typingMessage: SSKProtoTypingMessage?

    @objc
    public let storyMessage: SSKProtoStoryMessage?

    @objc
    public let pniSignatureMessage: SSKProtoPniSignatureMessage?

    @objc
    public let editMessage: SSKProtoEditMessage?

    @objc
    public var senderKeyDistributionMessage: Data? {
        guard hasSenderKeyDistributionMessage else {
            return nil
        }
        return proto.senderKeyDistributionMessage
    }
    @objc
    public var hasSenderKeyDistributionMessage: Bool {
        return proto.hasSenderKeyDistributionMessage
    }

    @objc
    public var decryptionErrorMessage: Data? {
        guard hasDecryptionErrorMessage else {
            return nil
        }
        return proto.decryptionErrorMessage
    }
    @objc
    public var hasDecryptionErrorMessage: Bool {
        return proto.hasDecryptionErrorMessage
    }

    public var hasUnknownFields: Bool {
        return !proto.unknownFields.data.isEmpty
    }
    public var unknownFields: SwiftProtobuf.UnknownStorage? {
        guard hasUnknownFields else { return nil }
        return proto.unknownFields
    }

    private init(proto: SignalServiceProtos_Content,
                 dataMessage: SSKProtoDataMessage?,
                 syncMessage: SSKProtoSyncMessage?,
                 callMessage: SSKProtoCallMessage?,
                 nullMessage: SSKProtoNullMessage?,
                 receiptMessage: SSKProtoReceiptMessage?,
                 typingMessage: SSKProtoTypingMessage?,
                 storyMessage: SSKProtoStoryMessage?,
                 pniSignatureMessage: SSKProtoPniSignatureMessage?,
                 editMessage: SSKProtoEditMessage?) {
        self.proto = proto
        self.dataMessage = dataMessage
        self.syncMessage = syncMessage
        self.callMessage = callMessage
        self.nullMessage = nullMessage
        self.receiptMessage = receiptMessage
        self.typingMessage = typingMessage
        self.storyMessage = storyMessage
        self.pniSignatureMessage = pniSignatureMessage
        self.editMessage = editMessage
    }

    @objc
    public func serializedData() throws -> Data {
        return try self.proto.serializedData()
    }

    @objc
    public convenience init(serializedData: Data) throws {
        let proto = try SignalServiceProtos_Content(serializedData: serializedData)
        try self.init(proto)
    }

    fileprivate convenience init(_ proto: SignalServiceProtos_Content) throws {
        var dataMessage: SSKProtoDataMessage?
        if proto.hasDataMessage {
            dataMessage = try SSKProtoDataMessage(proto.dataMessage)
        }

        var syncMessage: SSKProtoSyncMessage?
        if proto.hasSyncMessage {
            syncMessage = try SSKProtoSyncMessage(proto.syncMessage)
        }

        var callMessage: SSKProtoCallMessage?
        if proto.hasCallMessage {
            callMessage = try SSKProtoCallMessage(proto.callMessage)
        }

        var nullMessage: SSKProtoNullMessage?
        if proto.hasNullMessage {
            nullMessage = SSKProtoNullMessage(proto.nullMessage)
        }

        var receiptMessage: SSKProtoReceiptMessage?
        if proto.hasReceiptMessage {
            receiptMessage = SSKProtoReceiptMessage(proto.receiptMessage)
        }

        var typingMessage: SSKProtoTypingMessage?
        if proto.hasTypingMessage {
            typingMessage = try SSKProtoTypingMessage(proto.typingMessage)
        }

        var storyMessage: SSKProtoStoryMessage?
        if proto.hasStoryMessage {
            storyMessage = try SSKProtoStoryMessage(proto.storyMessage)
        }

        var pniSignatureMessage: SSKProtoPniSignatureMessage?
        if proto.hasPniSignatureMessage {
            pniSignatureMessage = SSKProtoPniSignatureMessage(proto.pniSignatureMessage)
        }

        var editMessage: SSKProtoEditMessage?
        if proto.hasEditMessage {
            editMessage = try SSKProtoEditMessage(proto.editMessage)
        }

        self.init(proto: proto,
                  dataMessage: dataMessage,
                  syncMessage: syncMessage,
                  callMessage: callMessage,
                  nullMessage: nullMessage,
                  receiptMessage: receiptMessage,
                  typingMessage: typingMessage,
                  storyMessage: storyMessage,
                  pniSignatureMessage: pniSignatureMessage,
                  editMessage: editMessage)
    }

    public required convenience init(from decoder: Swift.Decoder) throws {
        let singleValueContainer = try decoder.singleValueContainer()
        let serializedData = try singleValueContainer.decode(Data.self)
        try self.init(serializedData: serializedData)
    }
    public func encode(to encoder: Swift.Encoder) throws {
        var singleValueContainer = encoder.singleValueContainer()
        try singleValueContainer.encode(try serializedData())
    }

    public static var supportsSecureCoding: Bool { true }

    public required convenience init?(coder: NSCoder) {
        guard let serializedData = coder.decodeData() else { return nil }
        do {
            try self.init(serializedData: serializedData)
        } catch {
            owsFailDebug("Failed to decode serialized data \(error)")
            return nil
        }
    }

    public func encode(with coder: NSCoder) {
        do {
            coder.encode(try serializedData())
        } catch {
            owsFailDebug("Failed to encode serialized data \(error)")
        }
    }

    @objc
    public override var debugDescription: String {
        return "\(proto)"
    }
}

extension SSKProtoContent {
    @objc
    public static func builder() -> SSKProtoContentBuilder {
        return SSKProtoContentBuilder()
    }

    // asBuilder() constructs a builder that reflects the proto's contents.
    @objc
    public func asBuilder() -> SSKProtoContentBuilder {
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
        if let _value = senderKeyDistributionMessage {
            builder.setSenderKeyDistributionMessage(_value)
        }
        if let _value = decryptionErrorMessage {
            builder.setDecryptionErrorMessage(_value)
        }
        if let _value = storyMessage {
            builder.setStoryMessage(_value)
        }
        if let _value = pniSignatureMessage {
            builder.setPniSignatureMessage(_value)
        }
        if let _value = editMessage {
            builder.setEditMessage(_value)
        }
        if let _value = unknownFields {
            builder.setUnknownFields(_value)
        }
        return builder
    }
}

@objc
public class SSKProtoContentBuilder: NSObject {

    private var proto = SignalServiceProtos_Content()

    @objc
    fileprivate override init() {}

    @objc
    @available(swift, obsoleted: 1.0)
    public func setDataMessage(_ valueParam: SSKProtoDataMessage?) {
        guard let valueParam = valueParam else { return }
        proto.dataMessage = valueParam.proto
    }

    public func setDataMessage(_ valueParam: SSKProtoDataMessage) {
        proto.dataMessage = valueParam.proto
    }

    @objc
    @available(swift, obsoleted: 1.0)
    public func setSyncMessage(_ valueParam: SSKProtoSyncMessage?) {
        guard let valueParam = valueParam else { return }
        proto.syncMessage = valueParam.proto
    }

    public func setSyncMessage(_ valueParam: SSKProtoSyncMessage) {
        proto.syncMessage = valueParam.proto
    }

    @objc
    @available(swift, obsoleted: 1.0)
    public func setCallMessage(_ valueParam: SSKProtoCallMessage?) {
        guard let valueParam = valueParam else { return }
        proto.callMessage = valueParam.proto
    }

    public func setCallMessage(_ valueParam: SSKProtoCallMessage) {
        proto.callMessage = valueParam.proto
    }

    @objc
    @available(swift, obsoleted: 1.0)
    public func setNullMessage(_ valueParam: SSKProtoNullMessage?) {
        guard let valueParam = valueParam else { return }
        proto.nullMessage = valueParam.proto
    }

    public func setNullMessage(_ valueParam: SSKProtoNullMessage) {
        proto.nullMessage = valueParam.proto
    }

    @objc
    @available(swift, obsoleted: 1.0)
    public func setReceiptMessage(_ valueParam: SSKProtoReceiptMessage?) {
        guard let valueParam = valueParam else { return }
        proto.receiptMessage = valueParam.proto
    }

    public func setReceiptMessage(_ valueParam: SSKProtoReceiptMessage) {
        proto.receiptMessage = valueParam.proto
    }

    @objc
    @available(swift, obsoleted: 1.0)
    public func setTypingMessage(_ valueParam: SSKProtoTypingMessage?) {
        guard let valueParam = valueParam else { return }
        proto.typingMessage = valueParam.proto
    }

    public func setTypingMessage(_ valueParam: SSKProtoTypingMessage) {
        proto.typingMessage = valueParam.proto
    }

    @objc
    @available(swift, obsoleted: 1.0)
    public func setSenderKeyDistributionMessage(_ valueParam: Data?) {
        guard let valueParam = valueParam else { return }
        proto.senderKeyDistributionMessage = valueParam
    }

    public func setSenderKeyDistributionMessage(_ valueParam: Data) {
        proto.senderKeyDistributionMessage = valueParam
    }

    @objc
    @available(swift, obsoleted: 1.0)
    public func setDecryptionErrorMessage(_ valueParam: Data?) {
        guard let valueParam = valueParam else { return }
        proto.decryptionErrorMessage = valueParam
    }

    public func setDecryptionErrorMessage(_ valueParam: Data) {
        proto.decryptionErrorMessage = valueParam
    }

    @objc
    @available(swift, obsoleted: 1.0)
    public func setStoryMessage(_ valueParam: SSKProtoStoryMessage?) {
        guard let valueParam = valueParam else { return }
        proto.storyMessage = valueParam.proto
    }

    public func setStoryMessage(_ valueParam: SSKProtoStoryMessage) {
        proto.storyMessage = valueParam.proto
    }

    @objc
    @available(swift, obsoleted: 1.0)
    public func setPniSignatureMessage(_ valueParam: SSKProtoPniSignatureMessage?) {
        guard let valueParam = valueParam else { return }
        proto.pniSignatureMessage = valueParam.proto
    }

    public func setPniSignatureMessage(_ valueParam: SSKProtoPniSignatureMessage) {
        proto.pniSignatureMessage = valueParam.proto
    }

    @objc
    @available(swift, obsoleted: 1.0)
    public func setEditMessage(_ valueParam: SSKProtoEditMessage?) {
        guard let valueParam = valueParam else { return }
        proto.editMessage = valueParam.proto
    }

    public func setEditMessage(_ valueParam: SSKProtoEditMessage) {
        proto.editMessage = valueParam.proto
    }

    public func setUnknownFields(_ unknownFields: SwiftProtobuf.UnknownStorage) {
        proto.unknownFields = unknownFields
    }

    @objc
    public func build() throws -> SSKProtoContent {
        return try SSKProtoContent(proto)
    }

    @objc
    public func buildSerializedData() throws -> Data {
        return try SSKProtoContent(proto).serializedData()
    }
}

#if TESTABLE_BUILD

extension SSKProtoContent {
    @objc
    public func serializedDataIgnoringErrors() -> Data? {
        return try! self.serializedData()
    }
}

extension SSKProtoContentBuilder {
    @objc
    public func buildIgnoringErrors() -> SSKProtoContent? {
        return try! self.build()
    }
}

#endif

// MARK: - SSKProtoCallMessageOfferType

@objc
public enum SSKProtoCallMessageOfferType: Int32 {
    case offerAudioCall = 0
    case offerVideoCall = 1
}

private func SSKProtoCallMessageOfferTypeWrap(_ value: SignalServiceProtos_CallMessage.Offer.TypeEnum) -> SSKProtoCallMessageOfferType {
    switch value {
    case .offerAudioCall: return .offerAudioCall
    case .offerVideoCall: return .offerVideoCall
    }
}

private func SSKProtoCallMessageOfferTypeUnwrap(_ value: SSKProtoCallMessageOfferType) -> SignalServiceProtos_CallMessage.Offer.TypeEnum {
    switch value {
    case .offerAudioCall: return .offerAudioCall
    case .offerVideoCall: return .offerVideoCall
    }
}

// MARK: - SSKProtoCallMessageOffer

@objc
public class SSKProtoCallMessageOffer: NSObject, Codable, NSSecureCoding {

    fileprivate let proto: SignalServiceProtos_CallMessage.Offer

    @objc
    public let id: UInt64

    public var type: SSKProtoCallMessageOfferType? {
        guard hasType else {
            return nil
        }
        return SSKProtoCallMessageOfferTypeWrap(proto.type)
    }
    // This "unwrapped" accessor should only be used if the "has value" accessor has already been checked.
    @objc
    public var unwrappedType: SSKProtoCallMessageOfferType {
        if !hasType {
            // TODO: We could make this a crashing assert.
            owsFailDebug("Unsafe unwrap of missing optional: Offer.type.")
        }
        return SSKProtoCallMessageOfferTypeWrap(proto.type)
    }
    @objc
    public var hasType: Bool {
        return proto.hasType
    }

    @objc
    public var opaque: Data? {
        guard hasOpaque else {
            return nil
        }
        return proto.opaque
    }
    @objc
    public var hasOpaque: Bool {
        return proto.hasOpaque
    }

    public var hasUnknownFields: Bool {
        return !proto.unknownFields.data.isEmpty
    }
    public var unknownFields: SwiftProtobuf.UnknownStorage? {
        guard hasUnknownFields else { return nil }
        return proto.unknownFields
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

    @objc
    public convenience init(serializedData: Data) throws {
        let proto = try SignalServiceProtos_CallMessage.Offer(serializedData: serializedData)
        try self.init(proto)
    }

    fileprivate convenience init(_ proto: SignalServiceProtos_CallMessage.Offer) throws {
        guard proto.hasID else {
            throw SSKProtoError.invalidProtobuf(description: "\(Self.logTag()) missing required field: id")
        }
        let id = proto.id

        self.init(proto: proto,
                  id: id)
    }

    public required convenience init(from decoder: Swift.Decoder) throws {
        let singleValueContainer = try decoder.singleValueContainer()
        let serializedData = try singleValueContainer.decode(Data.self)
        try self.init(serializedData: serializedData)
    }
    public func encode(to encoder: Swift.Encoder) throws {
        var singleValueContainer = encoder.singleValueContainer()
        try singleValueContainer.encode(try serializedData())
    }

    public static var supportsSecureCoding: Bool { true }

    public required convenience init?(coder: NSCoder) {
        guard let serializedData = coder.decodeData() else { return nil }
        do {
            try self.init(serializedData: serializedData)
        } catch {
            owsFailDebug("Failed to decode serialized data \(error)")
            return nil
        }
    }

    public func encode(with coder: NSCoder) {
        do {
            coder.encode(try serializedData())
        } catch {
            owsFailDebug("Failed to encode serialized data \(error)")
        }
    }

    @objc
    public override var debugDescription: String {
        return "\(proto)"
    }
}

extension SSKProtoCallMessageOffer {
    @objc
    public static func builder(id: UInt64) -> SSKProtoCallMessageOfferBuilder {
        return SSKProtoCallMessageOfferBuilder(id: id)
    }

    // asBuilder() constructs a builder that reflects the proto's contents.
    @objc
    public func asBuilder() -> SSKProtoCallMessageOfferBuilder {
        let builder = SSKProtoCallMessageOfferBuilder(id: id)
        if let _value = type {
            builder.setType(_value)
        }
        if let _value = opaque {
            builder.setOpaque(_value)
        }
        if let _value = unknownFields {
            builder.setUnknownFields(_value)
        }
        return builder
    }
}

@objc
public class SSKProtoCallMessageOfferBuilder: NSObject {

    private var proto = SignalServiceProtos_CallMessage.Offer()

    @objc
    fileprivate override init() {}

    @objc
    fileprivate init(id: UInt64) {
        super.init()

        setId(id)
    }

    @objc
    public func setId(_ valueParam: UInt64) {
        proto.id = valueParam
    }

    @objc
    public func setType(_ valueParam: SSKProtoCallMessageOfferType) {
        proto.type = SSKProtoCallMessageOfferTypeUnwrap(valueParam)
    }

    @objc
    @available(swift, obsoleted: 1.0)
    public func setOpaque(_ valueParam: Data?) {
        guard let valueParam = valueParam else { return }
        proto.opaque = valueParam
    }

    public func setOpaque(_ valueParam: Data) {
        proto.opaque = valueParam
    }

    public func setUnknownFields(_ unknownFields: SwiftProtobuf.UnknownStorage) {
        proto.unknownFields = unknownFields
    }

    @objc
    public func build() throws -> SSKProtoCallMessageOffer {
        return try SSKProtoCallMessageOffer(proto)
    }

    @objc
    public func buildSerializedData() throws -> Data {
        return try SSKProtoCallMessageOffer(proto).serializedData()
    }
}

#if TESTABLE_BUILD

extension SSKProtoCallMessageOffer {
    @objc
    public func serializedDataIgnoringErrors() -> Data? {
        return try! self.serializedData()
    }
}

extension SSKProtoCallMessageOfferBuilder {
    @objc
    public func buildIgnoringErrors() -> SSKProtoCallMessageOffer? {
        return try! self.build()
    }
}

#endif

// MARK: - SSKProtoCallMessageAnswer

@objc
public class SSKProtoCallMessageAnswer: NSObject, Codable, NSSecureCoding {

    fileprivate let proto: SignalServiceProtos_CallMessage.Answer

    @objc
    public let id: UInt64

    @objc
    public var opaque: Data? {
        guard hasOpaque else {
            return nil
        }
        return proto.opaque
    }
    @objc
    public var hasOpaque: Bool {
        return proto.hasOpaque
    }

    public var hasUnknownFields: Bool {
        return !proto.unknownFields.data.isEmpty
    }
    public var unknownFields: SwiftProtobuf.UnknownStorage? {
        guard hasUnknownFields else { return nil }
        return proto.unknownFields
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

    @objc
    public convenience init(serializedData: Data) throws {
        let proto = try SignalServiceProtos_CallMessage.Answer(serializedData: serializedData)
        try self.init(proto)
    }

    fileprivate convenience init(_ proto: SignalServiceProtos_CallMessage.Answer) throws {
        guard proto.hasID else {
            throw SSKProtoError.invalidProtobuf(description: "\(Self.logTag()) missing required field: id")
        }
        let id = proto.id

        self.init(proto: proto,
                  id: id)
    }

    public required convenience init(from decoder: Swift.Decoder) throws {
        let singleValueContainer = try decoder.singleValueContainer()
        let serializedData = try singleValueContainer.decode(Data.self)
        try self.init(serializedData: serializedData)
    }
    public func encode(to encoder: Swift.Encoder) throws {
        var singleValueContainer = encoder.singleValueContainer()
        try singleValueContainer.encode(try serializedData())
    }

    public static var supportsSecureCoding: Bool { true }

    public required convenience init?(coder: NSCoder) {
        guard let serializedData = coder.decodeData() else { return nil }
        do {
            try self.init(serializedData: serializedData)
        } catch {
            owsFailDebug("Failed to decode serialized data \(error)")
            return nil
        }
    }

    public func encode(with coder: NSCoder) {
        do {
            coder.encode(try serializedData())
        } catch {
            owsFailDebug("Failed to encode serialized data \(error)")
        }
    }

    @objc
    public override var debugDescription: String {
        return "\(proto)"
    }
}

extension SSKProtoCallMessageAnswer {
    @objc
    public static func builder(id: UInt64) -> SSKProtoCallMessageAnswerBuilder {
        return SSKProtoCallMessageAnswerBuilder(id: id)
    }

    // asBuilder() constructs a builder that reflects the proto's contents.
    @objc
    public func asBuilder() -> SSKProtoCallMessageAnswerBuilder {
        let builder = SSKProtoCallMessageAnswerBuilder(id: id)
        if let _value = opaque {
            builder.setOpaque(_value)
        }
        if let _value = unknownFields {
            builder.setUnknownFields(_value)
        }
        return builder
    }
}

@objc
public class SSKProtoCallMessageAnswerBuilder: NSObject {

    private var proto = SignalServiceProtos_CallMessage.Answer()

    @objc
    fileprivate override init() {}

    @objc
    fileprivate init(id: UInt64) {
        super.init()

        setId(id)
    }

    @objc
    public func setId(_ valueParam: UInt64) {
        proto.id = valueParam
    }

    @objc
    @available(swift, obsoleted: 1.0)
    public func setOpaque(_ valueParam: Data?) {
        guard let valueParam = valueParam else { return }
        proto.opaque = valueParam
    }

    public func setOpaque(_ valueParam: Data) {
        proto.opaque = valueParam
    }

    public func setUnknownFields(_ unknownFields: SwiftProtobuf.UnknownStorage) {
        proto.unknownFields = unknownFields
    }

    @objc
    public func build() throws -> SSKProtoCallMessageAnswer {
        return try SSKProtoCallMessageAnswer(proto)
    }

    @objc
    public func buildSerializedData() throws -> Data {
        return try SSKProtoCallMessageAnswer(proto).serializedData()
    }
}

#if TESTABLE_BUILD

extension SSKProtoCallMessageAnswer {
    @objc
    public func serializedDataIgnoringErrors() -> Data? {
        return try! self.serializedData()
    }
}

extension SSKProtoCallMessageAnswerBuilder {
    @objc
    public func buildIgnoringErrors() -> SSKProtoCallMessageAnswer? {
        return try! self.build()
    }
}

#endif

// MARK: - SSKProtoCallMessageIceUpdate

@objc
public class SSKProtoCallMessageIceUpdate: NSObject, Codable, NSSecureCoding {

    fileprivate let proto: SignalServiceProtos_CallMessage.IceUpdate

    @objc
    public let id: UInt64

    @objc
    public var opaque: Data? {
        guard hasOpaque else {
            return nil
        }
        return proto.opaque
    }
    @objc
    public var hasOpaque: Bool {
        return proto.hasOpaque
    }

    public var hasUnknownFields: Bool {
        return !proto.unknownFields.data.isEmpty
    }
    public var unknownFields: SwiftProtobuf.UnknownStorage? {
        guard hasUnknownFields else { return nil }
        return proto.unknownFields
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

    @objc
    public convenience init(serializedData: Data) throws {
        let proto = try SignalServiceProtos_CallMessage.IceUpdate(serializedData: serializedData)
        try self.init(proto)
    }

    fileprivate convenience init(_ proto: SignalServiceProtos_CallMessage.IceUpdate) throws {
        guard proto.hasID else {
            throw SSKProtoError.invalidProtobuf(description: "\(Self.logTag()) missing required field: id")
        }
        let id = proto.id

        self.init(proto: proto,
                  id: id)
    }

    public required convenience init(from decoder: Swift.Decoder) throws {
        let singleValueContainer = try decoder.singleValueContainer()
        let serializedData = try singleValueContainer.decode(Data.self)
        try self.init(serializedData: serializedData)
    }
    public func encode(to encoder: Swift.Encoder) throws {
        var singleValueContainer = encoder.singleValueContainer()
        try singleValueContainer.encode(try serializedData())
    }

    public static var supportsSecureCoding: Bool { true }

    public required convenience init?(coder: NSCoder) {
        guard let serializedData = coder.decodeData() else { return nil }
        do {
            try self.init(serializedData: serializedData)
        } catch {
            owsFailDebug("Failed to decode serialized data \(error)")
            return nil
        }
    }

    public func encode(with coder: NSCoder) {
        do {
            coder.encode(try serializedData())
        } catch {
            owsFailDebug("Failed to encode serialized data \(error)")
        }
    }

    @objc
    public override var debugDescription: String {
        return "\(proto)"
    }
}

extension SSKProtoCallMessageIceUpdate {
    @objc
    public static func builder(id: UInt64) -> SSKProtoCallMessageIceUpdateBuilder {
        return SSKProtoCallMessageIceUpdateBuilder(id: id)
    }

    // asBuilder() constructs a builder that reflects the proto's contents.
    @objc
    public func asBuilder() -> SSKProtoCallMessageIceUpdateBuilder {
        let builder = SSKProtoCallMessageIceUpdateBuilder(id: id)
        if let _value = opaque {
            builder.setOpaque(_value)
        }
        if let _value = unknownFields {
            builder.setUnknownFields(_value)
        }
        return builder
    }
}

@objc
public class SSKProtoCallMessageIceUpdateBuilder: NSObject {

    private var proto = SignalServiceProtos_CallMessage.IceUpdate()

    @objc
    fileprivate override init() {}

    @objc
    fileprivate init(id: UInt64) {
        super.init()

        setId(id)
    }

    @objc
    public func setId(_ valueParam: UInt64) {
        proto.id = valueParam
    }

    @objc
    @available(swift, obsoleted: 1.0)
    public func setOpaque(_ valueParam: Data?) {
        guard let valueParam = valueParam else { return }
        proto.opaque = valueParam
    }

    public func setOpaque(_ valueParam: Data) {
        proto.opaque = valueParam
    }

    public func setUnknownFields(_ unknownFields: SwiftProtobuf.UnknownStorage) {
        proto.unknownFields = unknownFields
    }

    @objc
    public func build() throws -> SSKProtoCallMessageIceUpdate {
        return try SSKProtoCallMessageIceUpdate(proto)
    }

    @objc
    public func buildSerializedData() throws -> Data {
        return try SSKProtoCallMessageIceUpdate(proto).serializedData()
    }
}

#if TESTABLE_BUILD

extension SSKProtoCallMessageIceUpdate {
    @objc
    public func serializedDataIgnoringErrors() -> Data? {
        return try! self.serializedData()
    }
}

extension SSKProtoCallMessageIceUpdateBuilder {
    @objc
    public func buildIgnoringErrors() -> SSKProtoCallMessageIceUpdate? {
        return try! self.build()
    }
}

#endif

// MARK: - SSKProtoCallMessageBusy

@objc
public class SSKProtoCallMessageBusy: NSObject, Codable, NSSecureCoding {

    fileprivate let proto: SignalServiceProtos_CallMessage.Busy

    @objc
    public let id: UInt64

    public var hasUnknownFields: Bool {
        return !proto.unknownFields.data.isEmpty
    }
    public var unknownFields: SwiftProtobuf.UnknownStorage? {
        guard hasUnknownFields else { return nil }
        return proto.unknownFields
    }

    private init(proto: SignalServiceProtos_CallMessage.Busy,
                 id: UInt64) {
        self.proto = proto
        self.id = id
    }

    @objc
    public func serializedData() throws -> Data {
        return try self.proto.serializedData()
    }

    @objc
    public convenience init(serializedData: Data) throws {
        let proto = try SignalServiceProtos_CallMessage.Busy(serializedData: serializedData)
        try self.init(proto)
    }

    fileprivate convenience init(_ proto: SignalServiceProtos_CallMessage.Busy) throws {
        guard proto.hasID else {
            throw SSKProtoError.invalidProtobuf(description: "\(Self.logTag()) missing required field: id")
        }
        let id = proto.id

        self.init(proto: proto,
                  id: id)
    }

    public required convenience init(from decoder: Swift.Decoder) throws {
        let singleValueContainer = try decoder.singleValueContainer()
        let serializedData = try singleValueContainer.decode(Data.self)
        try self.init(serializedData: serializedData)
    }
    public func encode(to encoder: Swift.Encoder) throws {
        var singleValueContainer = encoder.singleValueContainer()
        try singleValueContainer.encode(try serializedData())
    }

    public static var supportsSecureCoding: Bool { true }

    public required convenience init?(coder: NSCoder) {
        guard let serializedData = coder.decodeData() else { return nil }
        do {
            try self.init(serializedData: serializedData)
        } catch {
            owsFailDebug("Failed to decode serialized data \(error)")
            return nil
        }
    }

    public func encode(with coder: NSCoder) {
        do {
            coder.encode(try serializedData())
        } catch {
            owsFailDebug("Failed to encode serialized data \(error)")
        }
    }

    @objc
    public override var debugDescription: String {
        return "\(proto)"
    }
}

extension SSKProtoCallMessageBusy {
    @objc
    public static func builder(id: UInt64) -> SSKProtoCallMessageBusyBuilder {
        return SSKProtoCallMessageBusyBuilder(id: id)
    }

    // asBuilder() constructs a builder that reflects the proto's contents.
    @objc
    public func asBuilder() -> SSKProtoCallMessageBusyBuilder {
        let builder = SSKProtoCallMessageBusyBuilder(id: id)
        if let _value = unknownFields {
            builder.setUnknownFields(_value)
        }
        return builder
    }
}

@objc
public class SSKProtoCallMessageBusyBuilder: NSObject {

    private var proto = SignalServiceProtos_CallMessage.Busy()

    @objc
    fileprivate override init() {}

    @objc
    fileprivate init(id: UInt64) {
        super.init()

        setId(id)
    }

    @objc
    public func setId(_ valueParam: UInt64) {
        proto.id = valueParam
    }

    public func setUnknownFields(_ unknownFields: SwiftProtobuf.UnknownStorage) {
        proto.unknownFields = unknownFields
    }

    @objc
    public func build() throws -> SSKProtoCallMessageBusy {
        return try SSKProtoCallMessageBusy(proto)
    }

    @objc
    public func buildSerializedData() throws -> Data {
        return try SSKProtoCallMessageBusy(proto).serializedData()
    }
}

#if TESTABLE_BUILD

extension SSKProtoCallMessageBusy {
    @objc
    public func serializedDataIgnoringErrors() -> Data? {
        return try! self.serializedData()
    }
}

extension SSKProtoCallMessageBusyBuilder {
    @objc
    public func buildIgnoringErrors() -> SSKProtoCallMessageBusy? {
        return try! self.build()
    }
}

#endif

// MARK: - SSKProtoCallMessageHangupType

@objc
public enum SSKProtoCallMessageHangupType: Int32 {
    case hangupNormal = 0
    case hangupAccepted = 1
    case hangupDeclined = 2
    case hangupBusy = 3
    case hangupNeedPermission = 4
}

private func SSKProtoCallMessageHangupTypeWrap(_ value: SignalServiceProtos_CallMessage.Hangup.TypeEnum) -> SSKProtoCallMessageHangupType {
    switch value {
    case .hangupNormal: return .hangupNormal
    case .hangupAccepted: return .hangupAccepted
    case .hangupDeclined: return .hangupDeclined
    case .hangupBusy: return .hangupBusy
    case .hangupNeedPermission: return .hangupNeedPermission
    }
}

private func SSKProtoCallMessageHangupTypeUnwrap(_ value: SSKProtoCallMessageHangupType) -> SignalServiceProtos_CallMessage.Hangup.TypeEnum {
    switch value {
    case .hangupNormal: return .hangupNormal
    case .hangupAccepted: return .hangupAccepted
    case .hangupDeclined: return .hangupDeclined
    case .hangupBusy: return .hangupBusy
    case .hangupNeedPermission: return .hangupNeedPermission
    }
}

// MARK: - SSKProtoCallMessageHangup

@objc
public class SSKProtoCallMessageHangup: NSObject, Codable, NSSecureCoding {

    fileprivate let proto: SignalServiceProtos_CallMessage.Hangup

    @objc
    public let id: UInt64

    public var type: SSKProtoCallMessageHangupType? {
        guard hasType else {
            return nil
        }
        return SSKProtoCallMessageHangupTypeWrap(proto.type)
    }
    // This "unwrapped" accessor should only be used if the "has value" accessor has already been checked.
    @objc
    public var unwrappedType: SSKProtoCallMessageHangupType {
        if !hasType {
            // TODO: We could make this a crashing assert.
            owsFailDebug("Unsafe unwrap of missing optional: Hangup.type.")
        }
        return SSKProtoCallMessageHangupTypeWrap(proto.type)
    }
    @objc
    public var hasType: Bool {
        return proto.hasType
    }

    @objc
    public var deviceID: UInt32 {
        return proto.deviceID
    }
    @objc
    public var hasDeviceID: Bool {
        return proto.hasDeviceID
    }

    public var hasUnknownFields: Bool {
        return !proto.unknownFields.data.isEmpty
    }
    public var unknownFields: SwiftProtobuf.UnknownStorage? {
        guard hasUnknownFields else { return nil }
        return proto.unknownFields
    }

    private init(proto: SignalServiceProtos_CallMessage.Hangup,
                 id: UInt64) {
        self.proto = proto
        self.id = id
    }

    @objc
    public func serializedData() throws -> Data {
        return try self.proto.serializedData()
    }

    @objc
    public convenience init(serializedData: Data) throws {
        let proto = try SignalServiceProtos_CallMessage.Hangup(serializedData: serializedData)
        try self.init(proto)
    }

    fileprivate convenience init(_ proto: SignalServiceProtos_CallMessage.Hangup) throws {
        guard proto.hasID else {
            throw SSKProtoError.invalidProtobuf(description: "\(Self.logTag()) missing required field: id")
        }
        let id = proto.id

        self.init(proto: proto,
                  id: id)
    }

    public required convenience init(from decoder: Swift.Decoder) throws {
        let singleValueContainer = try decoder.singleValueContainer()
        let serializedData = try singleValueContainer.decode(Data.self)
        try self.init(serializedData: serializedData)
    }
    public func encode(to encoder: Swift.Encoder) throws {
        var singleValueContainer = encoder.singleValueContainer()
        try singleValueContainer.encode(try serializedData())
    }

    public static var supportsSecureCoding: Bool { true }

    public required convenience init?(coder: NSCoder) {
        guard let serializedData = coder.decodeData() else { return nil }
        do {
            try self.init(serializedData: serializedData)
        } catch {
            owsFailDebug("Failed to decode serialized data \(error)")
            return nil
        }
    }

    public func encode(with coder: NSCoder) {
        do {
            coder.encode(try serializedData())
        } catch {
            owsFailDebug("Failed to encode serialized data \(error)")
        }
    }

    @objc
    public override var debugDescription: String {
        return "\(proto)"
    }
}

extension SSKProtoCallMessageHangup {
    @objc
    public static func builder(id: UInt64) -> SSKProtoCallMessageHangupBuilder {
        return SSKProtoCallMessageHangupBuilder(id: id)
    }

    // asBuilder() constructs a builder that reflects the proto's contents.
    @objc
    public func asBuilder() -> SSKProtoCallMessageHangupBuilder {
        let builder = SSKProtoCallMessageHangupBuilder(id: id)
        if let _value = type {
            builder.setType(_value)
        }
        if hasDeviceID {
            builder.setDeviceID(deviceID)
        }
        if let _value = unknownFields {
            builder.setUnknownFields(_value)
        }
        return builder
    }
}

@objc
public class SSKProtoCallMessageHangupBuilder: NSObject {

    private var proto = SignalServiceProtos_CallMessage.Hangup()

    @objc
    fileprivate override init() {}

    @objc
    fileprivate init(id: UInt64) {
        super.init()

        setId(id)
    }

    @objc
    public func setId(_ valueParam: UInt64) {
        proto.id = valueParam
    }

    @objc
    public func setType(_ valueParam: SSKProtoCallMessageHangupType) {
        proto.type = SSKProtoCallMessageHangupTypeUnwrap(valueParam)
    }

    @objc
    public func setDeviceID(_ valueParam: UInt32) {
        proto.deviceID = valueParam
    }

    public func setUnknownFields(_ unknownFields: SwiftProtobuf.UnknownStorage) {
        proto.unknownFields = unknownFields
    }

    @objc
    public func build() throws -> SSKProtoCallMessageHangup {
        return try SSKProtoCallMessageHangup(proto)
    }

    @objc
    public func buildSerializedData() throws -> Data {
        return try SSKProtoCallMessageHangup(proto).serializedData()
    }
}

#if TESTABLE_BUILD

extension SSKProtoCallMessageHangup {
    @objc
    public func serializedDataIgnoringErrors() -> Data? {
        return try! self.serializedData()
    }
}

extension SSKProtoCallMessageHangupBuilder {
    @objc
    public func buildIgnoringErrors() -> SSKProtoCallMessageHangup? {
        return try! self.build()
    }
}

#endif

// MARK: - SSKProtoCallMessageOpaqueUrgency

@objc
public enum SSKProtoCallMessageOpaqueUrgency: Int32 {
    case droppable = 0
    case handleImmediately = 1
}

private func SSKProtoCallMessageOpaqueUrgencyWrap(_ value: SignalServiceProtos_CallMessage.Opaque.Urgency) -> SSKProtoCallMessageOpaqueUrgency {
    switch value {
    case .droppable: return .droppable
    case .handleImmediately: return .handleImmediately
    }
}

private func SSKProtoCallMessageOpaqueUrgencyUnwrap(_ value: SSKProtoCallMessageOpaqueUrgency) -> SignalServiceProtos_CallMessage.Opaque.Urgency {
    switch value {
    case .droppable: return .droppable
    case .handleImmediately: return .handleImmediately
    }
}

// MARK: - SSKProtoCallMessageOpaque

@objc
public class SSKProtoCallMessageOpaque: NSObject, Codable, NSSecureCoding {

    fileprivate let proto: SignalServiceProtos_CallMessage.Opaque

    @objc
    public var data: Data? {
        guard hasData else {
            return nil
        }
        return proto.data
    }
    @objc
    public var hasData: Bool {
        return proto.hasData
    }

    public var urgency: SSKProtoCallMessageOpaqueUrgency? {
        guard hasUrgency else {
            return nil
        }
        return SSKProtoCallMessageOpaqueUrgencyWrap(proto.urgency)
    }
    // This "unwrapped" accessor should only be used if the "has value" accessor has already been checked.
    @objc
    public var unwrappedUrgency: SSKProtoCallMessageOpaqueUrgency {
        if !hasUrgency {
            // TODO: We could make this a crashing assert.
            owsFailDebug("Unsafe unwrap of missing optional: Opaque.urgency.")
        }
        return SSKProtoCallMessageOpaqueUrgencyWrap(proto.urgency)
    }
    @objc
    public var hasUrgency: Bool {
        return proto.hasUrgency
    }

    public var hasUnknownFields: Bool {
        return !proto.unknownFields.data.isEmpty
    }
    public var unknownFields: SwiftProtobuf.UnknownStorage? {
        guard hasUnknownFields else { return nil }
        return proto.unknownFields
    }

    private init(proto: SignalServiceProtos_CallMessage.Opaque) {
        self.proto = proto
    }

    @objc
    public func serializedData() throws -> Data {
        return try self.proto.serializedData()
    }

    @objc
    public convenience init(serializedData: Data) throws {
        let proto = try SignalServiceProtos_CallMessage.Opaque(serializedData: serializedData)
        self.init(proto)
    }

    fileprivate convenience init(_ proto: SignalServiceProtos_CallMessage.Opaque) {
        self.init(proto: proto)
    }

    public required convenience init(from decoder: Swift.Decoder) throws {
        let singleValueContainer = try decoder.singleValueContainer()
        let serializedData = try singleValueContainer.decode(Data.self)
        try self.init(serializedData: serializedData)
    }
    public func encode(to encoder: Swift.Encoder) throws {
        var singleValueContainer = encoder.singleValueContainer()
        try singleValueContainer.encode(try serializedData())
    }

    public static var supportsSecureCoding: Bool { true }

    public required convenience init?(coder: NSCoder) {
        guard let serializedData = coder.decodeData() else { return nil }
        do {
            try self.init(serializedData: serializedData)
        } catch {
            owsFailDebug("Failed to decode serialized data \(error)")
            return nil
        }
    }

    public func encode(with coder: NSCoder) {
        do {
            coder.encode(try serializedData())
        } catch {
            owsFailDebug("Failed to encode serialized data \(error)")
        }
    }

    @objc
    public override var debugDescription: String {
        return "\(proto)"
    }
}

extension SSKProtoCallMessageOpaque {
    @objc
    public static func builder() -> SSKProtoCallMessageOpaqueBuilder {
        return SSKProtoCallMessageOpaqueBuilder()
    }

    // asBuilder() constructs a builder that reflects the proto's contents.
    @objc
    public func asBuilder() -> SSKProtoCallMessageOpaqueBuilder {
        let builder = SSKProtoCallMessageOpaqueBuilder()
        if let _value = data {
            builder.setData(_value)
        }
        if let _value = urgency {
            builder.setUrgency(_value)
        }
        if let _value = unknownFields {
            builder.setUnknownFields(_value)
        }
        return builder
    }
}

@objc
public class SSKProtoCallMessageOpaqueBuilder: NSObject {

    private var proto = SignalServiceProtos_CallMessage.Opaque()

    @objc
    fileprivate override init() {}

    @objc
    @available(swift, obsoleted: 1.0)
    public func setData(_ valueParam: Data?) {
        guard let valueParam = valueParam else { return }
        proto.data = valueParam
    }

    public func setData(_ valueParam: Data) {
        proto.data = valueParam
    }

    @objc
    public func setUrgency(_ valueParam: SSKProtoCallMessageOpaqueUrgency) {
        proto.urgency = SSKProtoCallMessageOpaqueUrgencyUnwrap(valueParam)
    }

    public func setUnknownFields(_ unknownFields: SwiftProtobuf.UnknownStorage) {
        proto.unknownFields = unknownFields
    }

    @objc
    public func build() throws -> SSKProtoCallMessageOpaque {
        return SSKProtoCallMessageOpaque(proto)
    }

    @objc
    public func buildInfallibly() -> SSKProtoCallMessageOpaque {
        return SSKProtoCallMessageOpaque(proto)
    }

    @objc
    public func buildSerializedData() throws -> Data {
        return try SSKProtoCallMessageOpaque(proto).serializedData()
    }
}

#if TESTABLE_BUILD

extension SSKProtoCallMessageOpaque {
    @objc
    public func serializedDataIgnoringErrors() -> Data? {
        return try! self.serializedData()
    }
}

extension SSKProtoCallMessageOpaqueBuilder {
    @objc
    public func buildIgnoringErrors() -> SSKProtoCallMessageOpaque? {
        return self.buildInfallibly()
    }
}

#endif

// MARK: - SSKProtoCallMessage

@objc
public class SSKProtoCallMessage: NSObject, Codable, NSSecureCoding {

    fileprivate let proto: SignalServiceProtos_CallMessage

    @objc
    public let offer: SSKProtoCallMessageOffer?

    @objc
    public let answer: SSKProtoCallMessageAnswer?

    @objc
    public let iceUpdate: [SSKProtoCallMessageIceUpdate]

    @objc
    public let busy: SSKProtoCallMessageBusy?

    @objc
    public let hangup: SSKProtoCallMessageHangup?

    @objc
    public let opaque: SSKProtoCallMessageOpaque?

    @objc
    public var profileKey: Data? {
        guard hasProfileKey else {
            return nil
        }
        return proto.profileKey
    }
    @objc
    public var hasProfileKey: Bool {
        return proto.hasProfileKey
    }

    @objc
    public var destinationDeviceID: UInt32 {
        return proto.destinationDeviceID
    }
    @objc
    public var hasDestinationDeviceID: Bool {
        return proto.hasDestinationDeviceID
    }

    public var hasUnknownFields: Bool {
        return !proto.unknownFields.data.isEmpty
    }
    public var unknownFields: SwiftProtobuf.UnknownStorage? {
        guard hasUnknownFields else { return nil }
        return proto.unknownFields
    }

    private init(proto: SignalServiceProtos_CallMessage,
                 offer: SSKProtoCallMessageOffer?,
                 answer: SSKProtoCallMessageAnswer?,
                 iceUpdate: [SSKProtoCallMessageIceUpdate],
                 busy: SSKProtoCallMessageBusy?,
                 hangup: SSKProtoCallMessageHangup?,
                 opaque: SSKProtoCallMessageOpaque?) {
        self.proto = proto
        self.offer = offer
        self.answer = answer
        self.iceUpdate = iceUpdate
        self.busy = busy
        self.hangup = hangup
        self.opaque = opaque
    }

    @objc
    public func serializedData() throws -> Data {
        return try self.proto.serializedData()
    }

    @objc
    public convenience init(serializedData: Data) throws {
        let proto = try SignalServiceProtos_CallMessage(serializedData: serializedData)
        try self.init(proto)
    }

    fileprivate convenience init(_ proto: SignalServiceProtos_CallMessage) throws {
        var offer: SSKProtoCallMessageOffer?
        if proto.hasOffer {
            offer = try SSKProtoCallMessageOffer(proto.offer)
        }

        var answer: SSKProtoCallMessageAnswer?
        if proto.hasAnswer {
            answer = try SSKProtoCallMessageAnswer(proto.answer)
        }

        var iceUpdate: [SSKProtoCallMessageIceUpdate] = []
        iceUpdate = try proto.iceUpdate.map { try SSKProtoCallMessageIceUpdate($0) }

        var busy: SSKProtoCallMessageBusy?
        if proto.hasBusy {
            busy = try SSKProtoCallMessageBusy(proto.busy)
        }

        var hangup: SSKProtoCallMessageHangup?
        if proto.hasHangup {
            hangup = try SSKProtoCallMessageHangup(proto.hangup)
        }

        var opaque: SSKProtoCallMessageOpaque?
        if proto.hasOpaque {
            opaque = SSKProtoCallMessageOpaque(proto.opaque)
        }

        self.init(proto: proto,
                  offer: offer,
                  answer: answer,
                  iceUpdate: iceUpdate,
                  busy: busy,
                  hangup: hangup,
                  opaque: opaque)
    }

    public required convenience init(from decoder: Swift.Decoder) throws {
        let singleValueContainer = try decoder.singleValueContainer()
        let serializedData = try singleValueContainer.decode(Data.self)
        try self.init(serializedData: serializedData)
    }
    public func encode(to encoder: Swift.Encoder) throws {
        var singleValueContainer = encoder.singleValueContainer()
        try singleValueContainer.encode(try serializedData())
    }

    public static var supportsSecureCoding: Bool { true }

    public required convenience init?(coder: NSCoder) {
        guard let serializedData = coder.decodeData() else { return nil }
        do {
            try self.init(serializedData: serializedData)
        } catch {
            owsFailDebug("Failed to decode serialized data \(error)")
            return nil
        }
    }

    public func encode(with coder: NSCoder) {
        do {
            coder.encode(try serializedData())
        } catch {
            owsFailDebug("Failed to encode serialized data \(error)")
        }
    }

    @objc
    public override var debugDescription: String {
        return "\(proto)"
    }
}

extension SSKProtoCallMessage {
    @objc
    public static func builder() -> SSKProtoCallMessageBuilder {
        return SSKProtoCallMessageBuilder()
    }

    // asBuilder() constructs a builder that reflects the proto's contents.
    @objc
    public func asBuilder() -> SSKProtoCallMessageBuilder {
        let builder = SSKProtoCallMessageBuilder()
        if let _value = offer {
            builder.setOffer(_value)
        }
        if let _value = answer {
            builder.setAnswer(_value)
        }
        builder.setIceUpdate(iceUpdate)
        if let _value = busy {
            builder.setBusy(_value)
        }
        if let _value = profileKey {
            builder.setProfileKey(_value)
        }
        if let _value = hangup {
            builder.setHangup(_value)
        }
        if hasDestinationDeviceID {
            builder.setDestinationDeviceID(destinationDeviceID)
        }
        if let _value = opaque {
            builder.setOpaque(_value)
        }
        if let _value = unknownFields {
            builder.setUnknownFields(_value)
        }
        return builder
    }
}

@objc
public class SSKProtoCallMessageBuilder: NSObject {

    private var proto = SignalServiceProtos_CallMessage()

    @objc
    fileprivate override init() {}

    @objc
    @available(swift, obsoleted: 1.0)
    public func setOffer(_ valueParam: SSKProtoCallMessageOffer?) {
        guard let valueParam = valueParam else { return }
        proto.offer = valueParam.proto
    }

    public func setOffer(_ valueParam: SSKProtoCallMessageOffer) {
        proto.offer = valueParam.proto
    }

    @objc
    @available(swift, obsoleted: 1.0)
    public func setAnswer(_ valueParam: SSKProtoCallMessageAnswer?) {
        guard let valueParam = valueParam else { return }
        proto.answer = valueParam.proto
    }

    public func setAnswer(_ valueParam: SSKProtoCallMessageAnswer) {
        proto.answer = valueParam.proto
    }

    @objc
    public func addIceUpdate(_ valueParam: SSKProtoCallMessageIceUpdate) {
        proto.iceUpdate.append(valueParam.proto)
    }

    @objc
    public func setIceUpdate(_ wrappedItems: [SSKProtoCallMessageIceUpdate]) {
        proto.iceUpdate = wrappedItems.map { $0.proto }
    }

    @objc
    @available(swift, obsoleted: 1.0)
    public func setBusy(_ valueParam: SSKProtoCallMessageBusy?) {
        guard let valueParam = valueParam else { return }
        proto.busy = valueParam.proto
    }

    public func setBusy(_ valueParam: SSKProtoCallMessageBusy) {
        proto.busy = valueParam.proto
    }

    @objc
    @available(swift, obsoleted: 1.0)
    public func setProfileKey(_ valueParam: Data?) {
        guard let valueParam = valueParam else { return }
        proto.profileKey = valueParam
    }

    public func setProfileKey(_ valueParam: Data) {
        proto.profileKey = valueParam
    }

    @objc
    @available(swift, obsoleted: 1.0)
    public func setHangup(_ valueParam: SSKProtoCallMessageHangup?) {
        guard let valueParam = valueParam else { return }
        proto.hangup = valueParam.proto
    }

    public func setHangup(_ valueParam: SSKProtoCallMessageHangup) {
        proto.hangup = valueParam.proto
    }

    @objc
    public func setDestinationDeviceID(_ valueParam: UInt32) {
        proto.destinationDeviceID = valueParam
    }

    @objc
    @available(swift, obsoleted: 1.0)
    public func setOpaque(_ valueParam: SSKProtoCallMessageOpaque?) {
        guard let valueParam = valueParam else { return }
        proto.opaque = valueParam.proto
    }

    public func setOpaque(_ valueParam: SSKProtoCallMessageOpaque) {
        proto.opaque = valueParam.proto
    }

    public func setUnknownFields(_ unknownFields: SwiftProtobuf.UnknownStorage) {
        proto.unknownFields = unknownFields
    }

    @objc
    public func build() throws -> SSKProtoCallMessage {
        return try SSKProtoCallMessage(proto)
    }

    @objc
    public func buildSerializedData() throws -> Data {
        return try SSKProtoCallMessage(proto).serializedData()
    }
}

#if TESTABLE_BUILD

extension SSKProtoCallMessage {
    @objc
    public func serializedDataIgnoringErrors() -> Data? {
        return try! self.serializedData()
    }
}

extension SSKProtoCallMessageBuilder {
    @objc
    public func buildIgnoringErrors() -> SSKProtoCallMessage? {
        return try! self.build()
    }
}

#endif

// MARK: - SSKProtoDataMessageQuoteQuotedAttachment

@objc
public class SSKProtoDataMessageQuoteQuotedAttachment: NSObject, Codable, NSSecureCoding {

    fileprivate let proto: SignalServiceProtos_DataMessage.Quote.QuotedAttachment

    @objc
    public let thumbnail: SSKProtoAttachmentPointer?

    @objc
    public var contentType: String? {
        guard hasContentType else {
            return nil
        }
        return proto.contentType
    }
    @objc
    public var hasContentType: Bool {
        return proto.hasContentType
    }

    @objc
    public var fileName: String? {
        guard hasFileName else {
            return nil
        }
        return proto.fileName
    }
    @objc
    public var hasFileName: Bool {
        return proto.hasFileName
    }

    public var hasUnknownFields: Bool {
        return !proto.unknownFields.data.isEmpty
    }
    public var unknownFields: SwiftProtobuf.UnknownStorage? {
        guard hasUnknownFields else { return nil }
        return proto.unknownFields
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

    @objc
    public convenience init(serializedData: Data) throws {
        let proto = try SignalServiceProtos_DataMessage.Quote.QuotedAttachment(serializedData: serializedData)
        self.init(proto)
    }

    fileprivate convenience init(_ proto: SignalServiceProtos_DataMessage.Quote.QuotedAttachment) {
        var thumbnail: SSKProtoAttachmentPointer?
        if proto.hasThumbnail {
            thumbnail = SSKProtoAttachmentPointer(proto.thumbnail)
        }

        self.init(proto: proto,
                  thumbnail: thumbnail)
    }

    public required convenience init(from decoder: Swift.Decoder) throws {
        let singleValueContainer = try decoder.singleValueContainer()
        let serializedData = try singleValueContainer.decode(Data.self)
        try self.init(serializedData: serializedData)
    }
    public func encode(to encoder: Swift.Encoder) throws {
        var singleValueContainer = encoder.singleValueContainer()
        try singleValueContainer.encode(try serializedData())
    }

    public static var supportsSecureCoding: Bool { true }

    public required convenience init?(coder: NSCoder) {
        guard let serializedData = coder.decodeData() else { return nil }
        do {
            try self.init(serializedData: serializedData)
        } catch {
            owsFailDebug("Failed to decode serialized data \(error)")
            return nil
        }
    }

    public func encode(with coder: NSCoder) {
        do {
            coder.encode(try serializedData())
        } catch {
            owsFailDebug("Failed to encode serialized data \(error)")
        }
    }

    @objc
    public override var debugDescription: String {
        return "\(proto)"
    }
}

extension SSKProtoDataMessageQuoteQuotedAttachment {
    @objc
    public static func builder() -> SSKProtoDataMessageQuoteQuotedAttachmentBuilder {
        return SSKProtoDataMessageQuoteQuotedAttachmentBuilder()
    }

    // asBuilder() constructs a builder that reflects the proto's contents.
    @objc
    public func asBuilder() -> SSKProtoDataMessageQuoteQuotedAttachmentBuilder {
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
        if let _value = unknownFields {
            builder.setUnknownFields(_value)
        }
        return builder
    }
}

@objc
public class SSKProtoDataMessageQuoteQuotedAttachmentBuilder: NSObject {

    private var proto = SignalServiceProtos_DataMessage.Quote.QuotedAttachment()

    @objc
    fileprivate override init() {}

    @objc
    @available(swift, obsoleted: 1.0)
    public func setContentType(_ valueParam: String?) {
        guard let valueParam = valueParam else { return }
        proto.contentType = valueParam
    }

    public func setContentType(_ valueParam: String) {
        proto.contentType = valueParam
    }

    @objc
    @available(swift, obsoleted: 1.0)
    public func setFileName(_ valueParam: String?) {
        guard let valueParam = valueParam else { return }
        proto.fileName = valueParam
    }

    public func setFileName(_ valueParam: String) {
        proto.fileName = valueParam
    }

    @objc
    @available(swift, obsoleted: 1.0)
    public func setThumbnail(_ valueParam: SSKProtoAttachmentPointer?) {
        guard let valueParam = valueParam else { return }
        proto.thumbnail = valueParam.proto
    }

    public func setThumbnail(_ valueParam: SSKProtoAttachmentPointer) {
        proto.thumbnail = valueParam.proto
    }

    public func setUnknownFields(_ unknownFields: SwiftProtobuf.UnknownStorage) {
        proto.unknownFields = unknownFields
    }

    @objc
    public func build() throws -> SSKProtoDataMessageQuoteQuotedAttachment {
        return SSKProtoDataMessageQuoteQuotedAttachment(proto)
    }

    @objc
    public func buildInfallibly() -> SSKProtoDataMessageQuoteQuotedAttachment {
        return SSKProtoDataMessageQuoteQuotedAttachment(proto)
    }

    @objc
    public func buildSerializedData() throws -> Data {
        return try SSKProtoDataMessageQuoteQuotedAttachment(proto).serializedData()
    }
}

#if TESTABLE_BUILD

extension SSKProtoDataMessageQuoteQuotedAttachment {
    @objc
    public func serializedDataIgnoringErrors() -> Data? {
        return try! self.serializedData()
    }
}

extension SSKProtoDataMessageQuoteQuotedAttachmentBuilder {
    @objc
    public func buildIgnoringErrors() -> SSKProtoDataMessageQuoteQuotedAttachment? {
        return self.buildInfallibly()
    }
}

#endif

// MARK: - SSKProtoDataMessageQuoteType

@objc
public enum SSKProtoDataMessageQuoteType: Int32 {
    case normal = 0
    case giftBadge = 1
}

private func SSKProtoDataMessageQuoteTypeWrap(_ value: SignalServiceProtos_DataMessage.Quote.TypeEnum) -> SSKProtoDataMessageQuoteType {
    switch value {
    case .normal: return .normal
    case .giftBadge: return .giftBadge
    }
}

private func SSKProtoDataMessageQuoteTypeUnwrap(_ value: SSKProtoDataMessageQuoteType) -> SignalServiceProtos_DataMessage.Quote.TypeEnum {
    switch value {
    case .normal: return .normal
    case .giftBadge: return .giftBadge
    }
}

// MARK: - SSKProtoDataMessageQuote

@objc
public class SSKProtoDataMessageQuote: NSObject, Codable, NSSecureCoding {

    fileprivate let proto: SignalServiceProtos_DataMessage.Quote

    @objc
    public let id: UInt64

    @objc
    public let attachments: [SSKProtoDataMessageQuoteQuotedAttachment]

    @objc
    public let bodyRanges: [SSKProtoBodyRange]

    @objc
    public var authorAci: String? {
        guard hasAuthorAci else {
            return nil
        }
        return proto.authorAci
    }
    @objc
    public var hasAuthorAci: Bool {
        return proto.hasAuthorAci
    }

    @objc
    public var text: String? {
        guard hasText else {
            return nil
        }
        return proto.text
    }
    @objc
    public var hasText: Bool {
        return proto.hasText
    }

    public var type: SSKProtoDataMessageQuoteType? {
        guard hasType else {
            return nil
        }
        return SSKProtoDataMessageQuoteTypeWrap(proto.type)
    }
    // This "unwrapped" accessor should only be used if the "has value" accessor has already been checked.
    @objc
    public var unwrappedType: SSKProtoDataMessageQuoteType {
        if !hasType {
            // TODO: We could make this a crashing assert.
            owsFailDebug("Unsafe unwrap of missing optional: Quote.type.")
        }
        return SSKProtoDataMessageQuoteTypeWrap(proto.type)
    }
    @objc
    public var hasType: Bool {
        return proto.hasType
    }

    public var hasUnknownFields: Bool {
        return !proto.unknownFields.data.isEmpty
    }
    public var unknownFields: SwiftProtobuf.UnknownStorage? {
        guard hasUnknownFields else { return nil }
        return proto.unknownFields
    }

    private init(proto: SignalServiceProtos_DataMessage.Quote,
                 id: UInt64,
                 attachments: [SSKProtoDataMessageQuoteQuotedAttachment],
                 bodyRanges: [SSKProtoBodyRange]) {
        self.proto = proto
        self.id = id
        self.attachments = attachments
        self.bodyRanges = bodyRanges
    }

    @objc
    public func serializedData() throws -> Data {
        return try self.proto.serializedData()
    }

    @objc
    public convenience init(serializedData: Data) throws {
        let proto = try SignalServiceProtos_DataMessage.Quote(serializedData: serializedData)
        try self.init(proto)
    }

    fileprivate convenience init(_ proto: SignalServiceProtos_DataMessage.Quote) throws {
        guard proto.hasID else {
            throw SSKProtoError.invalidProtobuf(description: "\(Self.logTag()) missing required field: id")
        }
        let id = proto.id

        var attachments: [SSKProtoDataMessageQuoteQuotedAttachment] = []
        attachments = proto.attachments.map { SSKProtoDataMessageQuoteQuotedAttachment($0) }

        var bodyRanges: [SSKProtoBodyRange] = []
        bodyRanges = proto.bodyRanges.map { SSKProtoBodyRange($0) }

        self.init(proto: proto,
                  id: id,
                  attachments: attachments,
                  bodyRanges: bodyRanges)
    }

    public required convenience init(from decoder: Swift.Decoder) throws {
        let singleValueContainer = try decoder.singleValueContainer()
        let serializedData = try singleValueContainer.decode(Data.self)
        try self.init(serializedData: serializedData)
    }
    public func encode(to encoder: Swift.Encoder) throws {
        var singleValueContainer = encoder.singleValueContainer()
        try singleValueContainer.encode(try serializedData())
    }

    public static var supportsSecureCoding: Bool { true }

    public required convenience init?(coder: NSCoder) {
        guard let serializedData = coder.decodeData() else { return nil }
        do {
            try self.init(serializedData: serializedData)
        } catch {
            owsFailDebug("Failed to decode serialized data \(error)")
            return nil
        }
    }

    public func encode(with coder: NSCoder) {
        do {
            coder.encode(try serializedData())
        } catch {
            owsFailDebug("Failed to encode serialized data \(error)")
        }
    }

    @objc
    public override var debugDescription: String {
        return "\(proto)"
    }
}

extension SSKProtoDataMessageQuote {
    @objc
    public static func builder(id: UInt64) -> SSKProtoDataMessageQuoteBuilder {
        return SSKProtoDataMessageQuoteBuilder(id: id)
    }

    // asBuilder() constructs a builder that reflects the proto's contents.
    @objc
    public func asBuilder() -> SSKProtoDataMessageQuoteBuilder {
        let builder = SSKProtoDataMessageQuoteBuilder(id: id)
        if let _value = authorAci {
            builder.setAuthorAci(_value)
        }
        if let _value = text {
            builder.setText(_value)
        }
        builder.setAttachments(attachments)
        builder.setBodyRanges(bodyRanges)
        if let _value = type {
            builder.setType(_value)
        }
        if let _value = unknownFields {
            builder.setUnknownFields(_value)
        }
        return builder
    }
}

@objc
public class SSKProtoDataMessageQuoteBuilder: NSObject {

    private var proto = SignalServiceProtos_DataMessage.Quote()

    @objc
    fileprivate override init() {}

    @objc
    fileprivate init(id: UInt64) {
        super.init()

        setId(id)
    }

    @objc
    public func setId(_ valueParam: UInt64) {
        proto.id = valueParam
    }

    @objc
    @available(swift, obsoleted: 1.0)
    public func setAuthorAci(_ valueParam: String?) {
        guard let valueParam = valueParam else { return }
        proto.authorAci = valueParam
    }

    public func setAuthorAci(_ valueParam: String) {
        proto.authorAci = valueParam
    }

    @objc
    @available(swift, obsoleted: 1.0)
    public func setText(_ valueParam: String?) {
        guard let valueParam = valueParam else { return }
        proto.text = valueParam
    }

    public func setText(_ valueParam: String) {
        proto.text = valueParam
    }

    @objc
    public func addAttachments(_ valueParam: SSKProtoDataMessageQuoteQuotedAttachment) {
        proto.attachments.append(valueParam.proto)
    }

    @objc
    public func setAttachments(_ wrappedItems: [SSKProtoDataMessageQuoteQuotedAttachment]) {
        proto.attachments = wrappedItems.map { $0.proto }
    }

    @objc
    public func addBodyRanges(_ valueParam: SSKProtoBodyRange) {
        proto.bodyRanges.append(valueParam.proto)
    }

    @objc
    public func setBodyRanges(_ wrappedItems: [SSKProtoBodyRange]) {
        proto.bodyRanges = wrappedItems.map { $0.proto }
    }

    @objc
    public func setType(_ valueParam: SSKProtoDataMessageQuoteType) {
        proto.type = SSKProtoDataMessageQuoteTypeUnwrap(valueParam)
    }

    public func setUnknownFields(_ unknownFields: SwiftProtobuf.UnknownStorage) {
        proto.unknownFields = unknownFields
    }

    @objc
    public func build() throws -> SSKProtoDataMessageQuote {
        return try SSKProtoDataMessageQuote(proto)
    }

    @objc
    public func buildSerializedData() throws -> Data {
        return try SSKProtoDataMessageQuote(proto).serializedData()
    }
}

#if TESTABLE_BUILD

extension SSKProtoDataMessageQuote {
    @objc
    public func serializedDataIgnoringErrors() -> Data? {
        return try! self.serializedData()
    }
}

extension SSKProtoDataMessageQuoteBuilder {
    @objc
    public func buildIgnoringErrors() -> SSKProtoDataMessageQuote? {
        return try! self.build()
    }
}

#endif

// MARK: - SSKProtoDataMessageContactName

@objc
public class SSKProtoDataMessageContactName: NSObject, Codable, NSSecureCoding {

    fileprivate let proto: SignalServiceProtos_DataMessage.Contact.Name

    @objc
    public var givenName: String? {
        guard hasGivenName else {
            return nil
        }
        return proto.givenName
    }
    @objc
    public var hasGivenName: Bool {
        return proto.hasGivenName
    }

    @objc
    public var familyName: String? {
        guard hasFamilyName else {
            return nil
        }
        return proto.familyName
    }
    @objc
    public var hasFamilyName: Bool {
        return proto.hasFamilyName
    }

    @objc
    public var prefix: String? {
        guard hasPrefix else {
            return nil
        }
        return proto.prefix
    }
    @objc
    public var hasPrefix: Bool {
        return proto.hasPrefix
    }

    @objc
    public var suffix: String? {
        guard hasSuffix else {
            return nil
        }
        return proto.suffix
    }
    @objc
    public var hasSuffix: Bool {
        return proto.hasSuffix
    }

    @objc
    public var middleName: String? {
        guard hasMiddleName else {
            return nil
        }
        return proto.middleName
    }
    @objc
    public var hasMiddleName: Bool {
        return proto.hasMiddleName
    }

    @objc
    public var displayName: String? {
        guard hasDisplayName else {
            return nil
        }
        return proto.displayName
    }
    @objc
    public var hasDisplayName: Bool {
        return proto.hasDisplayName
    }

    public var hasUnknownFields: Bool {
        return !proto.unknownFields.data.isEmpty
    }
    public var unknownFields: SwiftProtobuf.UnknownStorage? {
        guard hasUnknownFields else { return nil }
        return proto.unknownFields
    }

    private init(proto: SignalServiceProtos_DataMessage.Contact.Name) {
        self.proto = proto
    }

    @objc
    public func serializedData() throws -> Data {
        return try self.proto.serializedData()
    }

    @objc
    public convenience init(serializedData: Data) throws {
        let proto = try SignalServiceProtos_DataMessage.Contact.Name(serializedData: serializedData)
        self.init(proto)
    }

    fileprivate convenience init(_ proto: SignalServiceProtos_DataMessage.Contact.Name) {
        self.init(proto: proto)
    }

    public required convenience init(from decoder: Swift.Decoder) throws {
        let singleValueContainer = try decoder.singleValueContainer()
        let serializedData = try singleValueContainer.decode(Data.self)
        try self.init(serializedData: serializedData)
    }
    public func encode(to encoder: Swift.Encoder) throws {
        var singleValueContainer = encoder.singleValueContainer()
        try singleValueContainer.encode(try serializedData())
    }

    public static var supportsSecureCoding: Bool { true }

    public required convenience init?(coder: NSCoder) {
        guard let serializedData = coder.decodeData() else { return nil }
        do {
            try self.init(serializedData: serializedData)
        } catch {
            owsFailDebug("Failed to decode serialized data \(error)")
            return nil
        }
    }

    public func encode(with coder: NSCoder) {
        do {
            coder.encode(try serializedData())
        } catch {
            owsFailDebug("Failed to encode serialized data \(error)")
        }
    }

    @objc
    public override var debugDescription: String {
        return "\(proto)"
    }
}

extension SSKProtoDataMessageContactName {
    @objc
    public static func builder() -> SSKProtoDataMessageContactNameBuilder {
        return SSKProtoDataMessageContactNameBuilder()
    }

    // asBuilder() constructs a builder that reflects the proto's contents.
    @objc
    public func asBuilder() -> SSKProtoDataMessageContactNameBuilder {
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
        if let _value = unknownFields {
            builder.setUnknownFields(_value)
        }
        return builder
    }
}

@objc
public class SSKProtoDataMessageContactNameBuilder: NSObject {

    private var proto = SignalServiceProtos_DataMessage.Contact.Name()

    @objc
    fileprivate override init() {}

    @objc
    @available(swift, obsoleted: 1.0)
    public func setGivenName(_ valueParam: String?) {
        guard let valueParam = valueParam else { return }
        proto.givenName = valueParam
    }

    public func setGivenName(_ valueParam: String) {
        proto.givenName = valueParam
    }

    @objc
    @available(swift, obsoleted: 1.0)
    public func setFamilyName(_ valueParam: String?) {
        guard let valueParam = valueParam else { return }
        proto.familyName = valueParam
    }

    public func setFamilyName(_ valueParam: String) {
        proto.familyName = valueParam
    }

    @objc
    @available(swift, obsoleted: 1.0)
    public func setPrefix(_ valueParam: String?) {
        guard let valueParam = valueParam else { return }
        proto.prefix = valueParam
    }

    public func setPrefix(_ valueParam: String) {
        proto.prefix = valueParam
    }

    @objc
    @available(swift, obsoleted: 1.0)
    public func setSuffix(_ valueParam: String?) {
        guard let valueParam = valueParam else { return }
        proto.suffix = valueParam
    }

    public func setSuffix(_ valueParam: String) {
        proto.suffix = valueParam
    }

    @objc
    @available(swift, obsoleted: 1.0)
    public func setMiddleName(_ valueParam: String?) {
        guard let valueParam = valueParam else { return }
        proto.middleName = valueParam
    }

    public func setMiddleName(_ valueParam: String) {
        proto.middleName = valueParam
    }

    @objc
    @available(swift, obsoleted: 1.0)
    public func setDisplayName(_ valueParam: String?) {
        guard let valueParam = valueParam else { return }
        proto.displayName = valueParam
    }

    public func setDisplayName(_ valueParam: String) {
        proto.displayName = valueParam
    }

    public func setUnknownFields(_ unknownFields: SwiftProtobuf.UnknownStorage) {
        proto.unknownFields = unknownFields
    }

    @objc
    public func build() throws -> SSKProtoDataMessageContactName {
        return SSKProtoDataMessageContactName(proto)
    }

    @objc
    public func buildInfallibly() -> SSKProtoDataMessageContactName {
        return SSKProtoDataMessageContactName(proto)
    }

    @objc
    public func buildSerializedData() throws -> Data {
        return try SSKProtoDataMessageContactName(proto).serializedData()
    }
}

#if TESTABLE_BUILD

extension SSKProtoDataMessageContactName {
    @objc
    public func serializedDataIgnoringErrors() -> Data? {
        return try! self.serializedData()
    }
}

extension SSKProtoDataMessageContactNameBuilder {
    @objc
    public func buildIgnoringErrors() -> SSKProtoDataMessageContactName? {
        return self.buildInfallibly()
    }
}

#endif

// MARK: - SSKProtoDataMessageContactPhoneType

@objc
public enum SSKProtoDataMessageContactPhoneType: Int32 {
    case home = 1
    case mobile = 2
    case work = 3
    case custom = 4
}

private func SSKProtoDataMessageContactPhoneTypeWrap(_ value: SignalServiceProtos_DataMessage.Contact.Phone.TypeEnum) -> SSKProtoDataMessageContactPhoneType {
    switch value {
    case .home: return .home
    case .mobile: return .mobile
    case .work: return .work
    case .custom: return .custom
    }
}

private func SSKProtoDataMessageContactPhoneTypeUnwrap(_ value: SSKProtoDataMessageContactPhoneType) -> SignalServiceProtos_DataMessage.Contact.Phone.TypeEnum {
    switch value {
    case .home: return .home
    case .mobile: return .mobile
    case .work: return .work
    case .custom: return .custom
    }
}

// MARK: - SSKProtoDataMessageContactPhone

@objc
public class SSKProtoDataMessageContactPhone: NSObject, Codable, NSSecureCoding {

    fileprivate let proto: SignalServiceProtos_DataMessage.Contact.Phone

    @objc
    public var value: String? {
        guard hasValue else {
            return nil
        }
        return proto.value
    }
    @objc
    public var hasValue: Bool {
        return proto.hasValue
    }

    public var type: SSKProtoDataMessageContactPhoneType? {
        guard hasType else {
            return nil
        }
        return SSKProtoDataMessageContactPhoneTypeWrap(proto.type)
    }
    // This "unwrapped" accessor should only be used if the "has value" accessor has already been checked.
    @objc
    public var unwrappedType: SSKProtoDataMessageContactPhoneType {
        if !hasType {
            // TODO: We could make this a crashing assert.
            owsFailDebug("Unsafe unwrap of missing optional: Phone.type.")
        }
        return SSKProtoDataMessageContactPhoneTypeWrap(proto.type)
    }
    @objc
    public var hasType: Bool {
        return proto.hasType
    }

    @objc
    public var label: String? {
        guard hasLabel else {
            return nil
        }
        return proto.label
    }
    @objc
    public var hasLabel: Bool {
        return proto.hasLabel
    }

    public var hasUnknownFields: Bool {
        return !proto.unknownFields.data.isEmpty
    }
    public var unknownFields: SwiftProtobuf.UnknownStorage? {
        guard hasUnknownFields else { return nil }
        return proto.unknownFields
    }

    private init(proto: SignalServiceProtos_DataMessage.Contact.Phone) {
        self.proto = proto
    }

    @objc
    public func serializedData() throws -> Data {
        return try self.proto.serializedData()
    }

    @objc
    public convenience init(serializedData: Data) throws {
        let proto = try SignalServiceProtos_DataMessage.Contact.Phone(serializedData: serializedData)
        self.init(proto)
    }

    fileprivate convenience init(_ proto: SignalServiceProtos_DataMessage.Contact.Phone) {
        self.init(proto: proto)
    }

    public required convenience init(from decoder: Swift.Decoder) throws {
        let singleValueContainer = try decoder.singleValueContainer()
        let serializedData = try singleValueContainer.decode(Data.self)
        try self.init(serializedData: serializedData)
    }
    public func encode(to encoder: Swift.Encoder) throws {
        var singleValueContainer = encoder.singleValueContainer()
        try singleValueContainer.encode(try serializedData())
    }

    public static var supportsSecureCoding: Bool { true }

    public required convenience init?(coder: NSCoder) {
        guard let serializedData = coder.decodeData() else { return nil }
        do {
            try self.init(serializedData: serializedData)
        } catch {
            owsFailDebug("Failed to decode serialized data \(error)")
            return nil
        }
    }

    public func encode(with coder: NSCoder) {
        do {
            coder.encode(try serializedData())
        } catch {
            owsFailDebug("Failed to encode serialized data \(error)")
        }
    }

    @objc
    public override var debugDescription: String {
        return "\(proto)"
    }
}

extension SSKProtoDataMessageContactPhone {
    @objc
    public static func builder() -> SSKProtoDataMessageContactPhoneBuilder {
        return SSKProtoDataMessageContactPhoneBuilder()
    }

    // asBuilder() constructs a builder that reflects the proto's contents.
    @objc
    public func asBuilder() -> SSKProtoDataMessageContactPhoneBuilder {
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
        if let _value = unknownFields {
            builder.setUnknownFields(_value)
        }
        return builder
    }
}

@objc
public class SSKProtoDataMessageContactPhoneBuilder: NSObject {

    private var proto = SignalServiceProtos_DataMessage.Contact.Phone()

    @objc
    fileprivate override init() {}

    @objc
    @available(swift, obsoleted: 1.0)
    public func setValue(_ valueParam: String?) {
        guard let valueParam = valueParam else { return }
        proto.value = valueParam
    }

    public func setValue(_ valueParam: String) {
        proto.value = valueParam
    }

    @objc
    public func setType(_ valueParam: SSKProtoDataMessageContactPhoneType) {
        proto.type = SSKProtoDataMessageContactPhoneTypeUnwrap(valueParam)
    }

    @objc
    @available(swift, obsoleted: 1.0)
    public func setLabel(_ valueParam: String?) {
        guard let valueParam = valueParam else { return }
        proto.label = valueParam
    }

    public func setLabel(_ valueParam: String) {
        proto.label = valueParam
    }

    public func setUnknownFields(_ unknownFields: SwiftProtobuf.UnknownStorage) {
        proto.unknownFields = unknownFields
    }

    @objc
    public func build() throws -> SSKProtoDataMessageContactPhone {
        return SSKProtoDataMessageContactPhone(proto)
    }

    @objc
    public func buildInfallibly() -> SSKProtoDataMessageContactPhone {
        return SSKProtoDataMessageContactPhone(proto)
    }

    @objc
    public func buildSerializedData() throws -> Data {
        return try SSKProtoDataMessageContactPhone(proto).serializedData()
    }
}

#if TESTABLE_BUILD

extension SSKProtoDataMessageContactPhone {
    @objc
    public func serializedDataIgnoringErrors() -> Data? {
        return try! self.serializedData()
    }
}

extension SSKProtoDataMessageContactPhoneBuilder {
    @objc
    public func buildIgnoringErrors() -> SSKProtoDataMessageContactPhone? {
        return self.buildInfallibly()
    }
}

#endif

// MARK: - SSKProtoDataMessageContactEmailType

@objc
public enum SSKProtoDataMessageContactEmailType: Int32 {
    case home = 1
    case mobile = 2
    case work = 3
    case custom = 4
}

private func SSKProtoDataMessageContactEmailTypeWrap(_ value: SignalServiceProtos_DataMessage.Contact.Email.TypeEnum) -> SSKProtoDataMessageContactEmailType {
    switch value {
    case .home: return .home
    case .mobile: return .mobile
    case .work: return .work
    case .custom: return .custom
    }
}

private func SSKProtoDataMessageContactEmailTypeUnwrap(_ value: SSKProtoDataMessageContactEmailType) -> SignalServiceProtos_DataMessage.Contact.Email.TypeEnum {
    switch value {
    case .home: return .home
    case .mobile: return .mobile
    case .work: return .work
    case .custom: return .custom
    }
}

// MARK: - SSKProtoDataMessageContactEmail

@objc
public class SSKProtoDataMessageContactEmail: NSObject, Codable, NSSecureCoding {

    fileprivate let proto: SignalServiceProtos_DataMessage.Contact.Email

    @objc
    public var value: String? {
        guard hasValue else {
            return nil
        }
        return proto.value
    }
    @objc
    public var hasValue: Bool {
        return proto.hasValue
    }

    public var type: SSKProtoDataMessageContactEmailType? {
        guard hasType else {
            return nil
        }
        return SSKProtoDataMessageContactEmailTypeWrap(proto.type)
    }
    // This "unwrapped" accessor should only be used if the "has value" accessor has already been checked.
    @objc
    public var unwrappedType: SSKProtoDataMessageContactEmailType {
        if !hasType {
            // TODO: We could make this a crashing assert.
            owsFailDebug("Unsafe unwrap of missing optional: Email.type.")
        }
        return SSKProtoDataMessageContactEmailTypeWrap(proto.type)
    }
    @objc
    public var hasType: Bool {
        return proto.hasType
    }

    @objc
    public var label: String? {
        guard hasLabel else {
            return nil
        }
        return proto.label
    }
    @objc
    public var hasLabel: Bool {
        return proto.hasLabel
    }

    public var hasUnknownFields: Bool {
        return !proto.unknownFields.data.isEmpty
    }
    public var unknownFields: SwiftProtobuf.UnknownStorage? {
        guard hasUnknownFields else { return nil }
        return proto.unknownFields
    }

    private init(proto: SignalServiceProtos_DataMessage.Contact.Email) {
        self.proto = proto
    }

    @objc
    public func serializedData() throws -> Data {
        return try self.proto.serializedData()
    }

    @objc
    public convenience init(serializedData: Data) throws {
        let proto = try SignalServiceProtos_DataMessage.Contact.Email(serializedData: serializedData)
        self.init(proto)
    }

    fileprivate convenience init(_ proto: SignalServiceProtos_DataMessage.Contact.Email) {
        self.init(proto: proto)
    }

    public required convenience init(from decoder: Swift.Decoder) throws {
        let singleValueContainer = try decoder.singleValueContainer()
        let serializedData = try singleValueContainer.decode(Data.self)
        try self.init(serializedData: serializedData)
    }
    public func encode(to encoder: Swift.Encoder) throws {
        var singleValueContainer = encoder.singleValueContainer()
        try singleValueContainer.encode(try serializedData())
    }

    public static var supportsSecureCoding: Bool { true }

    public required convenience init?(coder: NSCoder) {
        guard let serializedData = coder.decodeData() else { return nil }
        do {
            try self.init(serializedData: serializedData)
        } catch {
            owsFailDebug("Failed to decode serialized data \(error)")
            return nil
        }
    }

    public func encode(with coder: NSCoder) {
        do {
            coder.encode(try serializedData())
        } catch {
            owsFailDebug("Failed to encode serialized data \(error)")
        }
    }

    @objc
    public override var debugDescription: String {
        return "\(proto)"
    }
}

extension SSKProtoDataMessageContactEmail {
    @objc
    public static func builder() -> SSKProtoDataMessageContactEmailBuilder {
        return SSKProtoDataMessageContactEmailBuilder()
    }

    // asBuilder() constructs a builder that reflects the proto's contents.
    @objc
    public func asBuilder() -> SSKProtoDataMessageContactEmailBuilder {
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
        if let _value = unknownFields {
            builder.setUnknownFields(_value)
        }
        return builder
    }
}

@objc
public class SSKProtoDataMessageContactEmailBuilder: NSObject {

    private var proto = SignalServiceProtos_DataMessage.Contact.Email()

    @objc
    fileprivate override init() {}

    @objc
    @available(swift, obsoleted: 1.0)
    public func setValue(_ valueParam: String?) {
        guard let valueParam = valueParam else { return }
        proto.value = valueParam
    }

    public func setValue(_ valueParam: String) {
        proto.value = valueParam
    }

    @objc
    public func setType(_ valueParam: SSKProtoDataMessageContactEmailType) {
        proto.type = SSKProtoDataMessageContactEmailTypeUnwrap(valueParam)
    }

    @objc
    @available(swift, obsoleted: 1.0)
    public func setLabel(_ valueParam: String?) {
        guard let valueParam = valueParam else { return }
        proto.label = valueParam
    }

    public func setLabel(_ valueParam: String) {
        proto.label = valueParam
    }

    public func setUnknownFields(_ unknownFields: SwiftProtobuf.UnknownStorage) {
        proto.unknownFields = unknownFields
    }

    @objc
    public func build() throws -> SSKProtoDataMessageContactEmail {
        return SSKProtoDataMessageContactEmail(proto)
    }

    @objc
    public func buildInfallibly() -> SSKProtoDataMessageContactEmail {
        return SSKProtoDataMessageContactEmail(proto)
    }

    @objc
    public func buildSerializedData() throws -> Data {
        return try SSKProtoDataMessageContactEmail(proto).serializedData()
    }
}

#if TESTABLE_BUILD

extension SSKProtoDataMessageContactEmail {
    @objc
    public func serializedDataIgnoringErrors() -> Data? {
        return try! self.serializedData()
    }
}

extension SSKProtoDataMessageContactEmailBuilder {
    @objc
    public func buildIgnoringErrors() -> SSKProtoDataMessageContactEmail? {
        return self.buildInfallibly()
    }
}

#endif

// MARK: - SSKProtoDataMessageContactPostalAddressType

@objc
public enum SSKProtoDataMessageContactPostalAddressType: Int32 {
    case home = 1
    case work = 2
    case custom = 3
}

private func SSKProtoDataMessageContactPostalAddressTypeWrap(_ value: SignalServiceProtos_DataMessage.Contact.PostalAddress.TypeEnum) -> SSKProtoDataMessageContactPostalAddressType {
    switch value {
    case .home: return .home
    case .work: return .work
    case .custom: return .custom
    }
}

private func SSKProtoDataMessageContactPostalAddressTypeUnwrap(_ value: SSKProtoDataMessageContactPostalAddressType) -> SignalServiceProtos_DataMessage.Contact.PostalAddress.TypeEnum {
    switch value {
    case .home: return .home
    case .work: return .work
    case .custom: return .custom
    }
}

// MARK: - SSKProtoDataMessageContactPostalAddress

@objc
public class SSKProtoDataMessageContactPostalAddress: NSObject, Codable, NSSecureCoding {

    fileprivate let proto: SignalServiceProtos_DataMessage.Contact.PostalAddress

    public var type: SSKProtoDataMessageContactPostalAddressType? {
        guard hasType else {
            return nil
        }
        return SSKProtoDataMessageContactPostalAddressTypeWrap(proto.type)
    }
    // This "unwrapped" accessor should only be used if the "has value" accessor has already been checked.
    @objc
    public var unwrappedType: SSKProtoDataMessageContactPostalAddressType {
        if !hasType {
            // TODO: We could make this a crashing assert.
            owsFailDebug("Unsafe unwrap of missing optional: PostalAddress.type.")
        }
        return SSKProtoDataMessageContactPostalAddressTypeWrap(proto.type)
    }
    @objc
    public var hasType: Bool {
        return proto.hasType
    }

    @objc
    public var label: String? {
        guard hasLabel else {
            return nil
        }
        return proto.label
    }
    @objc
    public var hasLabel: Bool {
        return proto.hasLabel
    }

    @objc
    public var street: String? {
        guard hasStreet else {
            return nil
        }
        return proto.street
    }
    @objc
    public var hasStreet: Bool {
        return proto.hasStreet
    }

    @objc
    public var pobox: String? {
        guard hasPobox else {
            return nil
        }
        return proto.pobox
    }
    @objc
    public var hasPobox: Bool {
        return proto.hasPobox
    }

    @objc
    public var neighborhood: String? {
        guard hasNeighborhood else {
            return nil
        }
        return proto.neighborhood
    }
    @objc
    public var hasNeighborhood: Bool {
        return proto.hasNeighborhood
    }

    @objc
    public var city: String? {
        guard hasCity else {
            return nil
        }
        return proto.city
    }
    @objc
    public var hasCity: Bool {
        return proto.hasCity
    }

    @objc
    public var region: String? {
        guard hasRegion else {
            return nil
        }
        return proto.region
    }
    @objc
    public var hasRegion: Bool {
        return proto.hasRegion
    }

    @objc
    public var postcode: String? {
        guard hasPostcode else {
            return nil
        }
        return proto.postcode
    }
    @objc
    public var hasPostcode: Bool {
        return proto.hasPostcode
    }

    @objc
    public var country: String? {
        guard hasCountry else {
            return nil
        }
        return proto.country
    }
    @objc
    public var hasCountry: Bool {
        return proto.hasCountry
    }

    public var hasUnknownFields: Bool {
        return !proto.unknownFields.data.isEmpty
    }
    public var unknownFields: SwiftProtobuf.UnknownStorage? {
        guard hasUnknownFields else { return nil }
        return proto.unknownFields
    }

    private init(proto: SignalServiceProtos_DataMessage.Contact.PostalAddress) {
        self.proto = proto
    }

    @objc
    public func serializedData() throws -> Data {
        return try self.proto.serializedData()
    }

    @objc
    public convenience init(serializedData: Data) throws {
        let proto = try SignalServiceProtos_DataMessage.Contact.PostalAddress(serializedData: serializedData)
        self.init(proto)
    }

    fileprivate convenience init(_ proto: SignalServiceProtos_DataMessage.Contact.PostalAddress) {
        self.init(proto: proto)
    }

    public required convenience init(from decoder: Swift.Decoder) throws {
        let singleValueContainer = try decoder.singleValueContainer()
        let serializedData = try singleValueContainer.decode(Data.self)
        try self.init(serializedData: serializedData)
    }
    public func encode(to encoder: Swift.Encoder) throws {
        var singleValueContainer = encoder.singleValueContainer()
        try singleValueContainer.encode(try serializedData())
    }

    public static var supportsSecureCoding: Bool { true }

    public required convenience init?(coder: NSCoder) {
        guard let serializedData = coder.decodeData() else { return nil }
        do {
            try self.init(serializedData: serializedData)
        } catch {
            owsFailDebug("Failed to decode serialized data \(error)")
            return nil
        }
    }

    public func encode(with coder: NSCoder) {
        do {
            coder.encode(try serializedData())
        } catch {
            owsFailDebug("Failed to encode serialized data \(error)")
        }
    }

    @objc
    public override var debugDescription: String {
        return "\(proto)"
    }
}

extension SSKProtoDataMessageContactPostalAddress {
    @objc
    public static func builder() -> SSKProtoDataMessageContactPostalAddressBuilder {
        return SSKProtoDataMessageContactPostalAddressBuilder()
    }

    // asBuilder() constructs a builder that reflects the proto's contents.
    @objc
    public func asBuilder() -> SSKProtoDataMessageContactPostalAddressBuilder {
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
        if let _value = unknownFields {
            builder.setUnknownFields(_value)
        }
        return builder
    }
}

@objc
public class SSKProtoDataMessageContactPostalAddressBuilder: NSObject {

    private var proto = SignalServiceProtos_DataMessage.Contact.PostalAddress()

    @objc
    fileprivate override init() {}

    @objc
    public func setType(_ valueParam: SSKProtoDataMessageContactPostalAddressType) {
        proto.type = SSKProtoDataMessageContactPostalAddressTypeUnwrap(valueParam)
    }

    @objc
    @available(swift, obsoleted: 1.0)
    public func setLabel(_ valueParam: String?) {
        guard let valueParam = valueParam else { return }
        proto.label = valueParam
    }

    public func setLabel(_ valueParam: String) {
        proto.label = valueParam
    }

    @objc
    @available(swift, obsoleted: 1.0)
    public func setStreet(_ valueParam: String?) {
        guard let valueParam = valueParam else { return }
        proto.street = valueParam
    }

    public func setStreet(_ valueParam: String) {
        proto.street = valueParam
    }

    @objc
    @available(swift, obsoleted: 1.0)
    public func setPobox(_ valueParam: String?) {
        guard let valueParam = valueParam else { return }
        proto.pobox = valueParam
    }

    public func setPobox(_ valueParam: String) {
        proto.pobox = valueParam
    }

    @objc
    @available(swift, obsoleted: 1.0)
    public func setNeighborhood(_ valueParam: String?) {
        guard let valueParam = valueParam else { return }
        proto.neighborhood = valueParam
    }

    public func setNeighborhood(_ valueParam: String) {
        proto.neighborhood = valueParam
    }

    @objc
    @available(swift, obsoleted: 1.0)
    public func setCity(_ valueParam: String?) {
        guard let valueParam = valueParam else { return }
        proto.city = valueParam
    }

    public func setCity(_ valueParam: String) {
        proto.city = valueParam
    }

    @objc
    @available(swift, obsoleted: 1.0)
    public func setRegion(_ valueParam: String?) {
        guard let valueParam = valueParam else { return }
        proto.region = valueParam
    }

    public func setRegion(_ valueParam: String) {
        proto.region = valueParam
    }

    @objc
    @available(swift, obsoleted: 1.0)
    public func setPostcode(_ valueParam: String?) {
        guard let valueParam = valueParam else { return }
        proto.postcode = valueParam
    }

    public func setPostcode(_ valueParam: String) {
        proto.postcode = valueParam
    }

    @objc
    @available(swift, obsoleted: 1.0)
    public func setCountry(_ valueParam: String?) {
        guard let valueParam = valueParam else { return }
        proto.country = valueParam
    }

    public func setCountry(_ valueParam: String) {
        proto.country = valueParam
    }

    public func setUnknownFields(_ unknownFields: SwiftProtobuf.UnknownStorage) {
        proto.unknownFields = unknownFields
    }

    @objc
    public func build() throws -> SSKProtoDataMessageContactPostalAddress {
        return SSKProtoDataMessageContactPostalAddress(proto)
    }

    @objc
    public func buildInfallibly() -> SSKProtoDataMessageContactPostalAddress {
        return SSKProtoDataMessageContactPostalAddress(proto)
    }

    @objc
    public func buildSerializedData() throws -> Data {
        return try SSKProtoDataMessageContactPostalAddress(proto).serializedData()
    }
}

#if TESTABLE_BUILD

extension SSKProtoDataMessageContactPostalAddress {
    @objc
    public func serializedDataIgnoringErrors() -> Data? {
        return try! self.serializedData()
    }
}

extension SSKProtoDataMessageContactPostalAddressBuilder {
    @objc
    public func buildIgnoringErrors() -> SSKProtoDataMessageContactPostalAddress? {
        return self.buildInfallibly()
    }
}

#endif

// MARK: - SSKProtoDataMessageContactAvatar

@objc
public class SSKProtoDataMessageContactAvatar: NSObject, Codable, NSSecureCoding {

    fileprivate let proto: SignalServiceProtos_DataMessage.Contact.Avatar

    @objc
    public let avatar: SSKProtoAttachmentPointer?

    @objc
    public var isProfile: Bool {
        return proto.isProfile
    }
    @objc
    public var hasIsProfile: Bool {
        return proto.hasIsProfile
    }

    public var hasUnknownFields: Bool {
        return !proto.unknownFields.data.isEmpty
    }
    public var unknownFields: SwiftProtobuf.UnknownStorage? {
        guard hasUnknownFields else { return nil }
        return proto.unknownFields
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

    @objc
    public convenience init(serializedData: Data) throws {
        let proto = try SignalServiceProtos_DataMessage.Contact.Avatar(serializedData: serializedData)
        self.init(proto)
    }

    fileprivate convenience init(_ proto: SignalServiceProtos_DataMessage.Contact.Avatar) {
        var avatar: SSKProtoAttachmentPointer?
        if proto.hasAvatar {
            avatar = SSKProtoAttachmentPointer(proto.avatar)
        }

        self.init(proto: proto,
                  avatar: avatar)
    }

    public required convenience init(from decoder: Swift.Decoder) throws {
        let singleValueContainer = try decoder.singleValueContainer()
        let serializedData = try singleValueContainer.decode(Data.self)
        try self.init(serializedData: serializedData)
    }
    public func encode(to encoder: Swift.Encoder) throws {
        var singleValueContainer = encoder.singleValueContainer()
        try singleValueContainer.encode(try serializedData())
    }

    public static var supportsSecureCoding: Bool { true }

    public required convenience init?(coder: NSCoder) {
        guard let serializedData = coder.decodeData() else { return nil }
        do {
            try self.init(serializedData: serializedData)
        } catch {
            owsFailDebug("Failed to decode serialized data \(error)")
            return nil
        }
    }

    public func encode(with coder: NSCoder) {
        do {
            coder.encode(try serializedData())
        } catch {
            owsFailDebug("Failed to encode serialized data \(error)")
        }
    }

    @objc
    public override var debugDescription: String {
        return "\(proto)"
    }
}

extension SSKProtoDataMessageContactAvatar {
    @objc
    public static func builder() -> SSKProtoDataMessageContactAvatarBuilder {
        return SSKProtoDataMessageContactAvatarBuilder()
    }

    // asBuilder() constructs a builder that reflects the proto's contents.
    @objc
    public func asBuilder() -> SSKProtoDataMessageContactAvatarBuilder {
        let builder = SSKProtoDataMessageContactAvatarBuilder()
        if let _value = avatar {
            builder.setAvatar(_value)
        }
        if hasIsProfile {
            builder.setIsProfile(isProfile)
        }
        if let _value = unknownFields {
            builder.setUnknownFields(_value)
        }
        return builder
    }
}

@objc
public class SSKProtoDataMessageContactAvatarBuilder: NSObject {

    private var proto = SignalServiceProtos_DataMessage.Contact.Avatar()

    @objc
    fileprivate override init() {}

    @objc
    @available(swift, obsoleted: 1.0)
    public func setAvatar(_ valueParam: SSKProtoAttachmentPointer?) {
        guard let valueParam = valueParam else { return }
        proto.avatar = valueParam.proto
    }

    public func setAvatar(_ valueParam: SSKProtoAttachmentPointer) {
        proto.avatar = valueParam.proto
    }

    @objc
    public func setIsProfile(_ valueParam: Bool) {
        proto.isProfile = valueParam
    }

    public func setUnknownFields(_ unknownFields: SwiftProtobuf.UnknownStorage) {
        proto.unknownFields = unknownFields
    }

    @objc
    public func build() throws -> SSKProtoDataMessageContactAvatar {
        return SSKProtoDataMessageContactAvatar(proto)
    }

    @objc
    public func buildInfallibly() -> SSKProtoDataMessageContactAvatar {
        return SSKProtoDataMessageContactAvatar(proto)
    }

    @objc
    public func buildSerializedData() throws -> Data {
        return try SSKProtoDataMessageContactAvatar(proto).serializedData()
    }
}

#if TESTABLE_BUILD

extension SSKProtoDataMessageContactAvatar {
    @objc
    public func serializedDataIgnoringErrors() -> Data? {
        return try! self.serializedData()
    }
}

extension SSKProtoDataMessageContactAvatarBuilder {
    @objc
    public func buildIgnoringErrors() -> SSKProtoDataMessageContactAvatar? {
        return self.buildInfallibly()
    }
}

#endif

// MARK: - SSKProtoDataMessageContact

@objc
public class SSKProtoDataMessageContact: NSObject, Codable, NSSecureCoding {

    fileprivate let proto: SignalServiceProtos_DataMessage.Contact

    @objc
    public let name: SSKProtoDataMessageContactName?

    @objc
    public let number: [SSKProtoDataMessageContactPhone]

    @objc
    public let email: [SSKProtoDataMessageContactEmail]

    @objc
    public let address: [SSKProtoDataMessageContactPostalAddress]

    @objc
    public let avatar: SSKProtoDataMessageContactAvatar?

    @objc
    public var organization: String? {
        guard hasOrganization else {
            return nil
        }
        return proto.organization
    }
    @objc
    public var hasOrganization: Bool {
        return proto.hasOrganization
    }

    public var hasUnknownFields: Bool {
        return !proto.unknownFields.data.isEmpty
    }
    public var unknownFields: SwiftProtobuf.UnknownStorage? {
        guard hasUnknownFields else { return nil }
        return proto.unknownFields
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

    @objc
    public convenience init(serializedData: Data) throws {
        let proto = try SignalServiceProtos_DataMessage.Contact(serializedData: serializedData)
        self.init(proto)
    }

    fileprivate convenience init(_ proto: SignalServiceProtos_DataMessage.Contact) {
        var name: SSKProtoDataMessageContactName?
        if proto.hasName {
            name = SSKProtoDataMessageContactName(proto.name)
        }

        var number: [SSKProtoDataMessageContactPhone] = []
        number = proto.number.map { SSKProtoDataMessageContactPhone($0) }

        var email: [SSKProtoDataMessageContactEmail] = []
        email = proto.email.map { SSKProtoDataMessageContactEmail($0) }

        var address: [SSKProtoDataMessageContactPostalAddress] = []
        address = proto.address.map { SSKProtoDataMessageContactPostalAddress($0) }

        var avatar: SSKProtoDataMessageContactAvatar?
        if proto.hasAvatar {
            avatar = SSKProtoDataMessageContactAvatar(proto.avatar)
        }

        self.init(proto: proto,
                  name: name,
                  number: number,
                  email: email,
                  address: address,
                  avatar: avatar)
    }

    public required convenience init(from decoder: Swift.Decoder) throws {
        let singleValueContainer = try decoder.singleValueContainer()
        let serializedData = try singleValueContainer.decode(Data.self)
        try self.init(serializedData: serializedData)
    }
    public func encode(to encoder: Swift.Encoder) throws {
        var singleValueContainer = encoder.singleValueContainer()
        try singleValueContainer.encode(try serializedData())
    }

    public static var supportsSecureCoding: Bool { true }

    public required convenience init?(coder: NSCoder) {
        guard let serializedData = coder.decodeData() else { return nil }
        do {
            try self.init(serializedData: serializedData)
        } catch {
            owsFailDebug("Failed to decode serialized data \(error)")
            return nil
        }
    }

    public func encode(with coder: NSCoder) {
        do {
            coder.encode(try serializedData())
        } catch {
            owsFailDebug("Failed to encode serialized data \(error)")
        }
    }

    @objc
    public override var debugDescription: String {
        return "\(proto)"
    }
}

extension SSKProtoDataMessageContact {
    @objc
    public static func builder() -> SSKProtoDataMessageContactBuilder {
        return SSKProtoDataMessageContactBuilder()
    }

    // asBuilder() constructs a builder that reflects the proto's contents.
    @objc
    public func asBuilder() -> SSKProtoDataMessageContactBuilder {
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
        if let _value = unknownFields {
            builder.setUnknownFields(_value)
        }
        return builder
    }
}

@objc
public class SSKProtoDataMessageContactBuilder: NSObject {

    private var proto = SignalServiceProtos_DataMessage.Contact()

    @objc
    fileprivate override init() {}

    @objc
    @available(swift, obsoleted: 1.0)
    public func setName(_ valueParam: SSKProtoDataMessageContactName?) {
        guard let valueParam = valueParam else { return }
        proto.name = valueParam.proto
    }

    public func setName(_ valueParam: SSKProtoDataMessageContactName) {
        proto.name = valueParam.proto
    }

    @objc
    public func addNumber(_ valueParam: SSKProtoDataMessageContactPhone) {
        proto.number.append(valueParam.proto)
    }

    @objc
    public func setNumber(_ wrappedItems: [SSKProtoDataMessageContactPhone]) {
        proto.number = wrappedItems.map { $0.proto }
    }

    @objc
    public func addEmail(_ valueParam: SSKProtoDataMessageContactEmail) {
        proto.email.append(valueParam.proto)
    }

    @objc
    public func setEmail(_ wrappedItems: [SSKProtoDataMessageContactEmail]) {
        proto.email = wrappedItems.map { $0.proto }
    }

    @objc
    public func addAddress(_ valueParam: SSKProtoDataMessageContactPostalAddress) {
        proto.address.append(valueParam.proto)
    }

    @objc
    public func setAddress(_ wrappedItems: [SSKProtoDataMessageContactPostalAddress]) {
        proto.address = wrappedItems.map { $0.proto }
    }

    @objc
    @available(swift, obsoleted: 1.0)
    public func setAvatar(_ valueParam: SSKProtoDataMessageContactAvatar?) {
        guard let valueParam = valueParam else { return }
        proto.avatar = valueParam.proto
    }

    public func setAvatar(_ valueParam: SSKProtoDataMessageContactAvatar) {
        proto.avatar = valueParam.proto
    }

    @objc
    @available(swift, obsoleted: 1.0)
    public func setOrganization(_ valueParam: String?) {
        guard let valueParam = valueParam else { return }
        proto.organization = valueParam
    }

    public func setOrganization(_ valueParam: String) {
        proto.organization = valueParam
    }

    public func setUnknownFields(_ unknownFields: SwiftProtobuf.UnknownStorage) {
        proto.unknownFields = unknownFields
    }

    @objc
    public func build() throws -> SSKProtoDataMessageContact {
        return SSKProtoDataMessageContact(proto)
    }

    @objc
    public func buildInfallibly() -> SSKProtoDataMessageContact {
        return SSKProtoDataMessageContact(proto)
    }

    @objc
    public func buildSerializedData() throws -> Data {
        return try SSKProtoDataMessageContact(proto).serializedData()
    }
}

#if TESTABLE_BUILD

extension SSKProtoDataMessageContact {
    @objc
    public func serializedDataIgnoringErrors() -> Data? {
        return try! self.serializedData()
    }
}

extension SSKProtoDataMessageContactBuilder {
    @objc
    public func buildIgnoringErrors() -> SSKProtoDataMessageContact? {
        return self.buildInfallibly()
    }
}

#endif

// MARK: - SSKProtoDataMessageSticker

@objc
public class SSKProtoDataMessageSticker: NSObject, Codable, NSSecureCoding {

    fileprivate let proto: SignalServiceProtos_DataMessage.Sticker

    @objc
    public let packID: Data

    @objc
    public let packKey: Data

    @objc
    public let stickerID: UInt32

    @objc
    public let data: SSKProtoAttachmentPointer

    @objc
    public var emoji: String? {
        guard hasEmoji else {
            return nil
        }
        return proto.emoji
    }
    @objc
    public var hasEmoji: Bool {
        return proto.hasEmoji
    }

    public var hasUnknownFields: Bool {
        return !proto.unknownFields.data.isEmpty
    }
    public var unknownFields: SwiftProtobuf.UnknownStorage? {
        guard hasUnknownFields else { return nil }
        return proto.unknownFields
    }

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

    @objc
    public convenience init(serializedData: Data) throws {
        let proto = try SignalServiceProtos_DataMessage.Sticker(serializedData: serializedData)
        try self.init(proto)
    }

    fileprivate convenience init(_ proto: SignalServiceProtos_DataMessage.Sticker) throws {
        guard proto.hasPackID else {
            throw SSKProtoError.invalidProtobuf(description: "\(Self.logTag()) missing required field: packID")
        }
        let packID = proto.packID

        guard proto.hasPackKey else {
            throw SSKProtoError.invalidProtobuf(description: "\(Self.logTag()) missing required field: packKey")
        }
        let packKey = proto.packKey

        guard proto.hasStickerID else {
            throw SSKProtoError.invalidProtobuf(description: "\(Self.logTag()) missing required field: stickerID")
        }
        let stickerID = proto.stickerID

        guard proto.hasData else {
            throw SSKProtoError.invalidProtobuf(description: "\(Self.logTag()) missing required field: data")
        }
        let data = SSKProtoAttachmentPointer(proto.data)

        self.init(proto: proto,
                  packID: packID,
                  packKey: packKey,
                  stickerID: stickerID,
                  data: data)
    }

    public required convenience init(from decoder: Swift.Decoder) throws {
        let singleValueContainer = try decoder.singleValueContainer()
        let serializedData = try singleValueContainer.decode(Data.self)
        try self.init(serializedData: serializedData)
    }
    public func encode(to encoder: Swift.Encoder) throws {
        var singleValueContainer = encoder.singleValueContainer()
        try singleValueContainer.encode(try serializedData())
    }

    public static var supportsSecureCoding: Bool { true }

    public required convenience init?(coder: NSCoder) {
        guard let serializedData = coder.decodeData() else { return nil }
        do {
            try self.init(serializedData: serializedData)
        } catch {
            owsFailDebug("Failed to decode serialized data \(error)")
            return nil
        }
    }

    public func encode(with coder: NSCoder) {
        do {
            coder.encode(try serializedData())
        } catch {
            owsFailDebug("Failed to encode serialized data \(error)")
        }
    }

    @objc
    public override var debugDescription: String {
        return "\(proto)"
    }
}

extension SSKProtoDataMessageSticker {
    @objc
    public static func builder(packID: Data, packKey: Data, stickerID: UInt32, data: SSKProtoAttachmentPointer) -> SSKProtoDataMessageStickerBuilder {
        return SSKProtoDataMessageStickerBuilder(packID: packID, packKey: packKey, stickerID: stickerID, data: data)
    }

    // asBuilder() constructs a builder that reflects the proto's contents.
    @objc
    public func asBuilder() -> SSKProtoDataMessageStickerBuilder {
        let builder = SSKProtoDataMessageStickerBuilder(packID: packID, packKey: packKey, stickerID: stickerID, data: data)
        if let _value = emoji {
            builder.setEmoji(_value)
        }
        if let _value = unknownFields {
            builder.setUnknownFields(_value)
        }
        return builder
    }
}

@objc
public class SSKProtoDataMessageStickerBuilder: NSObject {

    private var proto = SignalServiceProtos_DataMessage.Sticker()

    @objc
    fileprivate override init() {}

    @objc
    fileprivate init(packID: Data, packKey: Data, stickerID: UInt32, data: SSKProtoAttachmentPointer) {
        super.init()

        setPackID(packID)
        setPackKey(packKey)
        setStickerID(stickerID)
        setData(data)
    }

    @objc
    @available(swift, obsoleted: 1.0)
    public func setPackID(_ valueParam: Data?) {
        guard let valueParam = valueParam else { return }
        proto.packID = valueParam
    }

    public func setPackID(_ valueParam: Data) {
        proto.packID = valueParam
    }

    @objc
    @available(swift, obsoleted: 1.0)
    public func setPackKey(_ valueParam: Data?) {
        guard let valueParam = valueParam else { return }
        proto.packKey = valueParam
    }

    public func setPackKey(_ valueParam: Data) {
        proto.packKey = valueParam
    }

    @objc
    public func setStickerID(_ valueParam: UInt32) {
        proto.stickerID = valueParam
    }

    @objc
    @available(swift, obsoleted: 1.0)
    public func setData(_ valueParam: SSKProtoAttachmentPointer?) {
        guard let valueParam = valueParam else { return }
        proto.data = valueParam.proto
    }

    public func setData(_ valueParam: SSKProtoAttachmentPointer) {
        proto.data = valueParam.proto
    }

    @objc
    @available(swift, obsoleted: 1.0)
    public func setEmoji(_ valueParam: String?) {
        guard let valueParam = valueParam else { return }
        proto.emoji = valueParam
    }

    public func setEmoji(_ valueParam: String) {
        proto.emoji = valueParam
    }

    public func setUnknownFields(_ unknownFields: SwiftProtobuf.UnknownStorage) {
        proto.unknownFields = unknownFields
    }

    @objc
    public func build() throws -> SSKProtoDataMessageSticker {
        return try SSKProtoDataMessageSticker(proto)
    }

    @objc
    public func buildSerializedData() throws -> Data {
        return try SSKProtoDataMessageSticker(proto).serializedData()
    }
}

#if TESTABLE_BUILD

extension SSKProtoDataMessageSticker {
    @objc
    public func serializedDataIgnoringErrors() -> Data? {
        return try! self.serializedData()
    }
}

extension SSKProtoDataMessageStickerBuilder {
    @objc
    public func buildIgnoringErrors() -> SSKProtoDataMessageSticker? {
        return try! self.build()
    }
}

#endif

// MARK: - SSKProtoDataMessageReaction

@objc
public class SSKProtoDataMessageReaction: NSObject, Codable, NSSecureCoding {

    fileprivate let proto: SignalServiceProtos_DataMessage.Reaction

    @objc
    public let emoji: String

    @objc
    public let timestamp: UInt64

    @objc
    public var remove: Bool {
        return proto.remove
    }
    @objc
    public var hasRemove: Bool {
        return proto.hasRemove
    }

    @objc
    public var targetAuthorAci: String? {
        guard hasTargetAuthorAci else {
            return nil
        }
        return proto.targetAuthorAci
    }
    @objc
    public var hasTargetAuthorAci: Bool {
        return proto.hasTargetAuthorAci
    }

    public var hasUnknownFields: Bool {
        return !proto.unknownFields.data.isEmpty
    }
    public var unknownFields: SwiftProtobuf.UnknownStorage? {
        guard hasUnknownFields else { return nil }
        return proto.unknownFields
    }

    private init(proto: SignalServiceProtos_DataMessage.Reaction,
                 emoji: String,
                 timestamp: UInt64) {
        self.proto = proto
        self.emoji = emoji
        self.timestamp = timestamp
    }

    @objc
    public func serializedData() throws -> Data {
        return try self.proto.serializedData()
    }

    @objc
    public convenience init(serializedData: Data) throws {
        let proto = try SignalServiceProtos_DataMessage.Reaction(serializedData: serializedData)
        try self.init(proto)
    }

    fileprivate convenience init(_ proto: SignalServiceProtos_DataMessage.Reaction) throws {
        guard proto.hasEmoji else {
            throw SSKProtoError.invalidProtobuf(description: "\(Self.logTag()) missing required field: emoji")
        }
        let emoji = proto.emoji

        guard proto.hasTimestamp else {
            throw SSKProtoError.invalidProtobuf(description: "\(Self.logTag()) missing required field: timestamp")
        }
        let timestamp = proto.timestamp

        self.init(proto: proto,
                  emoji: emoji,
                  timestamp: timestamp)
    }

    public required convenience init(from decoder: Swift.Decoder) throws {
        let singleValueContainer = try decoder.singleValueContainer()
        let serializedData = try singleValueContainer.decode(Data.self)
        try self.init(serializedData: serializedData)
    }
    public func encode(to encoder: Swift.Encoder) throws {
        var singleValueContainer = encoder.singleValueContainer()
        try singleValueContainer.encode(try serializedData())
    }

    public static var supportsSecureCoding: Bool { true }

    public required convenience init?(coder: NSCoder) {
        guard let serializedData = coder.decodeData() else { return nil }
        do {
            try self.init(serializedData: serializedData)
        } catch {
            owsFailDebug("Failed to decode serialized data \(error)")
            return nil
        }
    }

    public func encode(with coder: NSCoder) {
        do {
            coder.encode(try serializedData())
        } catch {
            owsFailDebug("Failed to encode serialized data \(error)")
        }
    }

    @objc
    public override var debugDescription: String {
        return "\(proto)"
    }
}

extension SSKProtoDataMessageReaction {
    @objc
    public static func builder(emoji: String, timestamp: UInt64) -> SSKProtoDataMessageReactionBuilder {
        return SSKProtoDataMessageReactionBuilder(emoji: emoji, timestamp: timestamp)
    }

    // asBuilder() constructs a builder that reflects the proto's contents.
    @objc
    public func asBuilder() -> SSKProtoDataMessageReactionBuilder {
        let builder = SSKProtoDataMessageReactionBuilder(emoji: emoji, timestamp: timestamp)
        if hasRemove {
            builder.setRemove(remove)
        }
        if let _value = targetAuthorAci {
            builder.setTargetAuthorAci(_value)
        }
        if let _value = unknownFields {
            builder.setUnknownFields(_value)
        }
        return builder
    }
}

@objc
public class SSKProtoDataMessageReactionBuilder: NSObject {

    private var proto = SignalServiceProtos_DataMessage.Reaction()

    @objc
    fileprivate override init() {}

    @objc
    fileprivate init(emoji: String, timestamp: UInt64) {
        super.init()

        setEmoji(emoji)
        setTimestamp(timestamp)
    }

    @objc
    @available(swift, obsoleted: 1.0)
    public func setEmoji(_ valueParam: String?) {
        guard let valueParam = valueParam else { return }
        proto.emoji = valueParam
    }

    public func setEmoji(_ valueParam: String) {
        proto.emoji = valueParam
    }

    @objc
    public func setRemove(_ valueParam: Bool) {
        proto.remove = valueParam
    }

    @objc
    @available(swift, obsoleted: 1.0)
    public func setTargetAuthorAci(_ valueParam: String?) {
        guard let valueParam = valueParam else { return }
        proto.targetAuthorAci = valueParam
    }

    public func setTargetAuthorAci(_ valueParam: String) {
        proto.targetAuthorAci = valueParam
    }

    @objc
    public func setTimestamp(_ valueParam: UInt64) {
        proto.timestamp = valueParam
    }

    public func setUnknownFields(_ unknownFields: SwiftProtobuf.UnknownStorage) {
        proto.unknownFields = unknownFields
    }

    @objc
    public func build() throws -> SSKProtoDataMessageReaction {
        return try SSKProtoDataMessageReaction(proto)
    }

    @objc
    public func buildSerializedData() throws -> Data {
        return try SSKProtoDataMessageReaction(proto).serializedData()
    }
}

#if TESTABLE_BUILD

extension SSKProtoDataMessageReaction {
    @objc
    public func serializedDataIgnoringErrors() -> Data? {
        return try! self.serializedData()
    }
}

extension SSKProtoDataMessageReactionBuilder {
    @objc
    public func buildIgnoringErrors() -> SSKProtoDataMessageReaction? {
        return try! self.build()
    }
}

#endif

// MARK: - SSKProtoDataMessageDelete

@objc
public class SSKProtoDataMessageDelete: NSObject, Codable, NSSecureCoding {

    fileprivate let proto: SignalServiceProtos_DataMessage.Delete

    @objc
    public let targetSentTimestamp: UInt64

    public var hasUnknownFields: Bool {
        return !proto.unknownFields.data.isEmpty
    }
    public var unknownFields: SwiftProtobuf.UnknownStorage? {
        guard hasUnknownFields else { return nil }
        return proto.unknownFields
    }

    private init(proto: SignalServiceProtos_DataMessage.Delete,
                 targetSentTimestamp: UInt64) {
        self.proto = proto
        self.targetSentTimestamp = targetSentTimestamp
    }

    @objc
    public func serializedData() throws -> Data {
        return try self.proto.serializedData()
    }

    @objc
    public convenience init(serializedData: Data) throws {
        let proto = try SignalServiceProtos_DataMessage.Delete(serializedData: serializedData)
        try self.init(proto)
    }

    fileprivate convenience init(_ proto: SignalServiceProtos_DataMessage.Delete) throws {
        guard proto.hasTargetSentTimestamp else {
            throw SSKProtoError.invalidProtobuf(description: "\(Self.logTag()) missing required field: targetSentTimestamp")
        }
        let targetSentTimestamp = proto.targetSentTimestamp

        self.init(proto: proto,
                  targetSentTimestamp: targetSentTimestamp)
    }

    public required convenience init(from decoder: Swift.Decoder) throws {
        let singleValueContainer = try decoder.singleValueContainer()
        let serializedData = try singleValueContainer.decode(Data.self)
        try self.init(serializedData: serializedData)
    }
    public func encode(to encoder: Swift.Encoder) throws {
        var singleValueContainer = encoder.singleValueContainer()
        try singleValueContainer.encode(try serializedData())
    }

    public static var supportsSecureCoding: Bool { true }

    public required convenience init?(coder: NSCoder) {
        guard let serializedData = coder.decodeData() else { return nil }
        do {
            try self.init(serializedData: serializedData)
        } catch {
            owsFailDebug("Failed to decode serialized data \(error)")
            return nil
        }
    }

    public func encode(with coder: NSCoder) {
        do {
            coder.encode(try serializedData())
        } catch {
            owsFailDebug("Failed to encode serialized data \(error)")
        }
    }

    @objc
    public override var debugDescription: String {
        return "\(proto)"
    }
}

extension SSKProtoDataMessageDelete {
    @objc
    public static func builder(targetSentTimestamp: UInt64) -> SSKProtoDataMessageDeleteBuilder {
        return SSKProtoDataMessageDeleteBuilder(targetSentTimestamp: targetSentTimestamp)
    }

    // asBuilder() constructs a builder that reflects the proto's contents.
    @objc
    public func asBuilder() -> SSKProtoDataMessageDeleteBuilder {
        let builder = SSKProtoDataMessageDeleteBuilder(targetSentTimestamp: targetSentTimestamp)
        if let _value = unknownFields {
            builder.setUnknownFields(_value)
        }
        return builder
    }
}

@objc
public class SSKProtoDataMessageDeleteBuilder: NSObject {

    private var proto = SignalServiceProtos_DataMessage.Delete()

    @objc
    fileprivate override init() {}

    @objc
    fileprivate init(targetSentTimestamp: UInt64) {
        super.init()

        setTargetSentTimestamp(targetSentTimestamp)
    }

    @objc
    public func setTargetSentTimestamp(_ valueParam: UInt64) {
        proto.targetSentTimestamp = valueParam
    }

    public func setUnknownFields(_ unknownFields: SwiftProtobuf.UnknownStorage) {
        proto.unknownFields = unknownFields
    }

    @objc
    public func build() throws -> SSKProtoDataMessageDelete {
        return try SSKProtoDataMessageDelete(proto)
    }

    @objc
    public func buildSerializedData() throws -> Data {
        return try SSKProtoDataMessageDelete(proto).serializedData()
    }
}

#if TESTABLE_BUILD

extension SSKProtoDataMessageDelete {
    @objc
    public func serializedDataIgnoringErrors() -> Data? {
        return try! self.serializedData()
    }
}

extension SSKProtoDataMessageDeleteBuilder {
    @objc
    public func buildIgnoringErrors() -> SSKProtoDataMessageDelete? {
        return try! self.build()
    }
}

#endif

// MARK: - SSKProtoDataMessageGroupCallUpdate

@objc
public class SSKProtoDataMessageGroupCallUpdate: NSObject, Codable, NSSecureCoding {

    fileprivate let proto: SignalServiceProtos_DataMessage.GroupCallUpdate

    @objc
    public var eraID: String? {
        guard hasEraID else {
            return nil
        }
        return proto.eraID
    }
    @objc
    public var hasEraID: Bool {
        return proto.hasEraID
    }

    public var hasUnknownFields: Bool {
        return !proto.unknownFields.data.isEmpty
    }
    public var unknownFields: SwiftProtobuf.UnknownStorage? {
        guard hasUnknownFields else { return nil }
        return proto.unknownFields
    }

    private init(proto: SignalServiceProtos_DataMessage.GroupCallUpdate) {
        self.proto = proto
    }

    @objc
    public func serializedData() throws -> Data {
        return try self.proto.serializedData()
    }

    @objc
    public convenience init(serializedData: Data) throws {
        let proto = try SignalServiceProtos_DataMessage.GroupCallUpdate(serializedData: serializedData)
        self.init(proto)
    }

    fileprivate convenience init(_ proto: SignalServiceProtos_DataMessage.GroupCallUpdate) {
        self.init(proto: proto)
    }

    public required convenience init(from decoder: Swift.Decoder) throws {
        let singleValueContainer = try decoder.singleValueContainer()
        let serializedData = try singleValueContainer.decode(Data.self)
        try self.init(serializedData: serializedData)
    }
    public func encode(to encoder: Swift.Encoder) throws {
        var singleValueContainer = encoder.singleValueContainer()
        try singleValueContainer.encode(try serializedData())
    }

    public static var supportsSecureCoding: Bool { true }

    public required convenience init?(coder: NSCoder) {
        guard let serializedData = coder.decodeData() else { return nil }
        do {
            try self.init(serializedData: serializedData)
        } catch {
            owsFailDebug("Failed to decode serialized data \(error)")
            return nil
        }
    }

    public func encode(with coder: NSCoder) {
        do {
            coder.encode(try serializedData())
        } catch {
            owsFailDebug("Failed to encode serialized data \(error)")
        }
    }

    @objc
    public override var debugDescription: String {
        return "\(proto)"
    }
}

extension SSKProtoDataMessageGroupCallUpdate {
    @objc
    public static func builder() -> SSKProtoDataMessageGroupCallUpdateBuilder {
        return SSKProtoDataMessageGroupCallUpdateBuilder()
    }

    // asBuilder() constructs a builder that reflects the proto's contents.
    @objc
    public func asBuilder() -> SSKProtoDataMessageGroupCallUpdateBuilder {
        let builder = SSKProtoDataMessageGroupCallUpdateBuilder()
        if let _value = eraID {
            builder.setEraID(_value)
        }
        if let _value = unknownFields {
            builder.setUnknownFields(_value)
        }
        return builder
    }
}

@objc
public class SSKProtoDataMessageGroupCallUpdateBuilder: NSObject {

    private var proto = SignalServiceProtos_DataMessage.GroupCallUpdate()

    @objc
    fileprivate override init() {}

    @objc
    @available(swift, obsoleted: 1.0)
    public func setEraID(_ valueParam: String?) {
        guard let valueParam = valueParam else { return }
        proto.eraID = valueParam
    }

    public func setEraID(_ valueParam: String) {
        proto.eraID = valueParam
    }

    public func setUnknownFields(_ unknownFields: SwiftProtobuf.UnknownStorage) {
        proto.unknownFields = unknownFields
    }

    @objc
    public func build() throws -> SSKProtoDataMessageGroupCallUpdate {
        return SSKProtoDataMessageGroupCallUpdate(proto)
    }

    @objc
    public func buildInfallibly() -> SSKProtoDataMessageGroupCallUpdate {
        return SSKProtoDataMessageGroupCallUpdate(proto)
    }

    @objc
    public func buildSerializedData() throws -> Data {
        return try SSKProtoDataMessageGroupCallUpdate(proto).serializedData()
    }
}

#if TESTABLE_BUILD

extension SSKProtoDataMessageGroupCallUpdate {
    @objc
    public func serializedDataIgnoringErrors() -> Data? {
        return try! self.serializedData()
    }
}

extension SSKProtoDataMessageGroupCallUpdateBuilder {
    @objc
    public func buildIgnoringErrors() -> SSKProtoDataMessageGroupCallUpdate? {
        return self.buildInfallibly()
    }
}

#endif

// MARK: - SSKProtoDataMessagePaymentAmountMobileCoin

@objc
public class SSKProtoDataMessagePaymentAmountMobileCoin: NSObject, Codable, NSSecureCoding {

    fileprivate let proto: SignalServiceProtos_DataMessage.Payment.Amount.MobileCoin

    @objc
    public let picoMob: UInt64

    public var hasUnknownFields: Bool {
        return !proto.unknownFields.data.isEmpty
    }
    public var unknownFields: SwiftProtobuf.UnknownStorage? {
        guard hasUnknownFields else { return nil }
        return proto.unknownFields
    }

    private init(proto: SignalServiceProtos_DataMessage.Payment.Amount.MobileCoin,
                 picoMob: UInt64) {
        self.proto = proto
        self.picoMob = picoMob
    }

    @objc
    public func serializedData() throws -> Data {
        return try self.proto.serializedData()
    }

    @objc
    public convenience init(serializedData: Data) throws {
        let proto = try SignalServiceProtos_DataMessage.Payment.Amount.MobileCoin(serializedData: serializedData)
        try self.init(proto)
    }

    fileprivate convenience init(_ proto: SignalServiceProtos_DataMessage.Payment.Amount.MobileCoin) throws {
        guard proto.hasPicoMob else {
            throw SSKProtoError.invalidProtobuf(description: "\(Self.logTag()) missing required field: picoMob")
        }
        let picoMob = proto.picoMob

        self.init(proto: proto,
                  picoMob: picoMob)
    }

    public required convenience init(from decoder: Swift.Decoder) throws {
        let singleValueContainer = try decoder.singleValueContainer()
        let serializedData = try singleValueContainer.decode(Data.self)
        try self.init(serializedData: serializedData)
    }
    public func encode(to encoder: Swift.Encoder) throws {
        var singleValueContainer = encoder.singleValueContainer()
        try singleValueContainer.encode(try serializedData())
    }

    public static var supportsSecureCoding: Bool { true }

    public required convenience init?(coder: NSCoder) {
        guard let serializedData = coder.decodeData() else { return nil }
        do {
            try self.init(serializedData: serializedData)
        } catch {
            owsFailDebug("Failed to decode serialized data \(error)")
            return nil
        }
    }

    public func encode(with coder: NSCoder) {
        do {
            coder.encode(try serializedData())
        } catch {
            owsFailDebug("Failed to encode serialized data \(error)")
        }
    }

    @objc
    public override var debugDescription: String {
        return "\(proto)"
    }
}

extension SSKProtoDataMessagePaymentAmountMobileCoin {
    @objc
    public static func builder(picoMob: UInt64) -> SSKProtoDataMessagePaymentAmountMobileCoinBuilder {
        return SSKProtoDataMessagePaymentAmountMobileCoinBuilder(picoMob: picoMob)
    }

    // asBuilder() constructs a builder that reflects the proto's contents.
    @objc
    public func asBuilder() -> SSKProtoDataMessagePaymentAmountMobileCoinBuilder {
        let builder = SSKProtoDataMessagePaymentAmountMobileCoinBuilder(picoMob: picoMob)
        if let _value = unknownFields {
            builder.setUnknownFields(_value)
        }
        return builder
    }
}

@objc
public class SSKProtoDataMessagePaymentAmountMobileCoinBuilder: NSObject {

    private var proto = SignalServiceProtos_DataMessage.Payment.Amount.MobileCoin()

    @objc
    fileprivate override init() {}

    @objc
    fileprivate init(picoMob: UInt64) {
        super.init()

        setPicoMob(picoMob)
    }

    @objc
    public func setPicoMob(_ valueParam: UInt64) {
        proto.picoMob = valueParam
    }

    public func setUnknownFields(_ unknownFields: SwiftProtobuf.UnknownStorage) {
        proto.unknownFields = unknownFields
    }

    @objc
    public func build() throws -> SSKProtoDataMessagePaymentAmountMobileCoin {
        return try SSKProtoDataMessagePaymentAmountMobileCoin(proto)
    }

    @objc
    public func buildSerializedData() throws -> Data {
        return try SSKProtoDataMessagePaymentAmountMobileCoin(proto).serializedData()
    }
}

#if TESTABLE_BUILD

extension SSKProtoDataMessagePaymentAmountMobileCoin {
    @objc
    public func serializedDataIgnoringErrors() -> Data? {
        return try! self.serializedData()
    }
}

extension SSKProtoDataMessagePaymentAmountMobileCoinBuilder {
    @objc
    public func buildIgnoringErrors() -> SSKProtoDataMessagePaymentAmountMobileCoin? {
        return try! self.build()
    }
}

#endif

// MARK: - SSKProtoDataMessagePaymentAmount

@objc
public class SSKProtoDataMessagePaymentAmount: NSObject, Codable, NSSecureCoding {

    fileprivate let proto: SignalServiceProtos_DataMessage.Payment.Amount

    @objc
    public let mobileCoin: SSKProtoDataMessagePaymentAmountMobileCoin?

    public var hasUnknownFields: Bool {
        return !proto.unknownFields.data.isEmpty
    }
    public var unknownFields: SwiftProtobuf.UnknownStorage? {
        guard hasUnknownFields else { return nil }
        return proto.unknownFields
    }

    private init(proto: SignalServiceProtos_DataMessage.Payment.Amount,
                 mobileCoin: SSKProtoDataMessagePaymentAmountMobileCoin?) {
        self.proto = proto
        self.mobileCoin = mobileCoin
    }

    @objc
    public func serializedData() throws -> Data {
        return try self.proto.serializedData()
    }

    @objc
    public convenience init(serializedData: Data) throws {
        let proto = try SignalServiceProtos_DataMessage.Payment.Amount(serializedData: serializedData)
        try self.init(proto)
    }

    fileprivate convenience init(_ proto: SignalServiceProtos_DataMessage.Payment.Amount) throws {
        var mobileCoin: SSKProtoDataMessagePaymentAmountMobileCoin?
        if proto.hasMobileCoin {
            mobileCoin = try SSKProtoDataMessagePaymentAmountMobileCoin(proto.mobileCoin)
        }

        self.init(proto: proto,
                  mobileCoin: mobileCoin)
    }

    public required convenience init(from decoder: Swift.Decoder) throws {
        let singleValueContainer = try decoder.singleValueContainer()
        let serializedData = try singleValueContainer.decode(Data.self)
        try self.init(serializedData: serializedData)
    }
    public func encode(to encoder: Swift.Encoder) throws {
        var singleValueContainer = encoder.singleValueContainer()
        try singleValueContainer.encode(try serializedData())
    }

    public static var supportsSecureCoding: Bool { true }

    public required convenience init?(coder: NSCoder) {
        guard let serializedData = coder.decodeData() else { return nil }
        do {
            try self.init(serializedData: serializedData)
        } catch {
            owsFailDebug("Failed to decode serialized data \(error)")
            return nil
        }
    }

    public func encode(with coder: NSCoder) {
        do {
            coder.encode(try serializedData())
        } catch {
            owsFailDebug("Failed to encode serialized data \(error)")
        }
    }

    @objc
    public override var debugDescription: String {
        return "\(proto)"
    }
}

extension SSKProtoDataMessagePaymentAmount {
    @objc
    public static func builder() -> SSKProtoDataMessagePaymentAmountBuilder {
        return SSKProtoDataMessagePaymentAmountBuilder()
    }

    // asBuilder() constructs a builder that reflects the proto's contents.
    @objc
    public func asBuilder() -> SSKProtoDataMessagePaymentAmountBuilder {
        let builder = SSKProtoDataMessagePaymentAmountBuilder()
        if let _value = mobileCoin {
            builder.setMobileCoin(_value)
        }
        if let _value = unknownFields {
            builder.setUnknownFields(_value)
        }
        return builder
    }
}

@objc
public class SSKProtoDataMessagePaymentAmountBuilder: NSObject {

    private var proto = SignalServiceProtos_DataMessage.Payment.Amount()

    @objc
    fileprivate override init() {}

    @objc
    @available(swift, obsoleted: 1.0)
    public func setMobileCoin(_ valueParam: SSKProtoDataMessagePaymentAmountMobileCoin?) {
        guard let valueParam = valueParam else { return }
        proto.mobileCoin = valueParam.proto
    }

    public func setMobileCoin(_ valueParam: SSKProtoDataMessagePaymentAmountMobileCoin) {
        proto.mobileCoin = valueParam.proto
    }

    public func setUnknownFields(_ unknownFields: SwiftProtobuf.UnknownStorage) {
        proto.unknownFields = unknownFields
    }

    @objc
    public func build() throws -> SSKProtoDataMessagePaymentAmount {
        return try SSKProtoDataMessagePaymentAmount(proto)
    }

    @objc
    public func buildSerializedData() throws -> Data {
        return try SSKProtoDataMessagePaymentAmount(proto).serializedData()
    }
}

#if TESTABLE_BUILD

extension SSKProtoDataMessagePaymentAmount {
    @objc
    public func serializedDataIgnoringErrors() -> Data? {
        return try! self.serializedData()
    }
}

extension SSKProtoDataMessagePaymentAmountBuilder {
    @objc
    public func buildIgnoringErrors() -> SSKProtoDataMessagePaymentAmount? {
        return try! self.build()
    }
}

#endif

// MARK: - SSKProtoDataMessagePaymentNotificationMobileCoin

@objc
public class SSKProtoDataMessagePaymentNotificationMobileCoin: NSObject, Codable, NSSecureCoding {

    fileprivate let proto: SignalServiceProtos_DataMessage.Payment.Notification.MobileCoin

    @objc
    public let receipt: Data

    public var hasUnknownFields: Bool {
        return !proto.unknownFields.data.isEmpty
    }
    public var unknownFields: SwiftProtobuf.UnknownStorage? {
        guard hasUnknownFields else { return nil }
        return proto.unknownFields
    }

    private init(proto: SignalServiceProtos_DataMessage.Payment.Notification.MobileCoin,
                 receipt: Data) {
        self.proto = proto
        self.receipt = receipt
    }

    @objc
    public func serializedData() throws -> Data {
        return try self.proto.serializedData()
    }

    @objc
    public convenience init(serializedData: Data) throws {
        let proto = try SignalServiceProtos_DataMessage.Payment.Notification.MobileCoin(serializedData: serializedData)
        try self.init(proto)
    }

    fileprivate convenience init(_ proto: SignalServiceProtos_DataMessage.Payment.Notification.MobileCoin) throws {
        guard proto.hasReceipt else {
            throw SSKProtoError.invalidProtobuf(description: "\(Self.logTag()) missing required field: receipt")
        }
        let receipt = proto.receipt

        self.init(proto: proto,
                  receipt: receipt)
    }

    public required convenience init(from decoder: Swift.Decoder) throws {
        let singleValueContainer = try decoder.singleValueContainer()
        let serializedData = try singleValueContainer.decode(Data.self)
        try self.init(serializedData: serializedData)
    }
    public func encode(to encoder: Swift.Encoder) throws {
        var singleValueContainer = encoder.singleValueContainer()
        try singleValueContainer.encode(try serializedData())
    }

    public static var supportsSecureCoding: Bool { true }

    public required convenience init?(coder: NSCoder) {
        guard let serializedData = coder.decodeData() else { return nil }
        do {
            try self.init(serializedData: serializedData)
        } catch {
            owsFailDebug("Failed to decode serialized data \(error)")
            return nil
        }
    }

    public func encode(with coder: NSCoder) {
        do {
            coder.encode(try serializedData())
        } catch {
            owsFailDebug("Failed to encode serialized data \(error)")
        }
    }

    @objc
    public override var debugDescription: String {
        return "\(proto)"
    }
}

extension SSKProtoDataMessagePaymentNotificationMobileCoin {
    @objc
    public static func builder(receipt: Data) -> SSKProtoDataMessagePaymentNotificationMobileCoinBuilder {
        return SSKProtoDataMessagePaymentNotificationMobileCoinBuilder(receipt: receipt)
    }

    // asBuilder() constructs a builder that reflects the proto's contents.
    @objc
    public func asBuilder() -> SSKProtoDataMessagePaymentNotificationMobileCoinBuilder {
        let builder = SSKProtoDataMessagePaymentNotificationMobileCoinBuilder(receipt: receipt)
        if let _value = unknownFields {
            builder.setUnknownFields(_value)
        }
        return builder
    }
}

@objc
public class SSKProtoDataMessagePaymentNotificationMobileCoinBuilder: NSObject {

    private var proto = SignalServiceProtos_DataMessage.Payment.Notification.MobileCoin()

    @objc
    fileprivate override init() {}

    @objc
    fileprivate init(receipt: Data) {
        super.init()

        setReceipt(receipt)
    }

    @objc
    @available(swift, obsoleted: 1.0)
    public func setReceipt(_ valueParam: Data?) {
        guard let valueParam = valueParam else { return }
        proto.receipt = valueParam
    }

    public func setReceipt(_ valueParam: Data) {
        proto.receipt = valueParam
    }

    public func setUnknownFields(_ unknownFields: SwiftProtobuf.UnknownStorage) {
        proto.unknownFields = unknownFields
    }

    @objc
    public func build() throws -> SSKProtoDataMessagePaymentNotificationMobileCoin {
        return try SSKProtoDataMessagePaymentNotificationMobileCoin(proto)
    }

    @objc
    public func buildSerializedData() throws -> Data {
        return try SSKProtoDataMessagePaymentNotificationMobileCoin(proto).serializedData()
    }
}

#if TESTABLE_BUILD

extension SSKProtoDataMessagePaymentNotificationMobileCoin {
    @objc
    public func serializedDataIgnoringErrors() -> Data? {
        return try! self.serializedData()
    }
}

extension SSKProtoDataMessagePaymentNotificationMobileCoinBuilder {
    @objc
    public func buildIgnoringErrors() -> SSKProtoDataMessagePaymentNotificationMobileCoin? {
        return try! self.build()
    }
}

#endif

// MARK: - SSKProtoDataMessagePaymentNotification

@objc
public class SSKProtoDataMessagePaymentNotification: NSObject, Codable, NSSecureCoding {

    fileprivate let proto: SignalServiceProtos_DataMessage.Payment.Notification

    @objc
    public let mobileCoin: SSKProtoDataMessagePaymentNotificationMobileCoin?

    @objc
    public var note: String? {
        guard hasNote else {
            return nil
        }
        return proto.note
    }
    @objc
    public var hasNote: Bool {
        return proto.hasNote
    }

    public var hasUnknownFields: Bool {
        return !proto.unknownFields.data.isEmpty
    }
    public var unknownFields: SwiftProtobuf.UnknownStorage? {
        guard hasUnknownFields else { return nil }
        return proto.unknownFields
    }

    private init(proto: SignalServiceProtos_DataMessage.Payment.Notification,
                 mobileCoin: SSKProtoDataMessagePaymentNotificationMobileCoin?) {
        self.proto = proto
        self.mobileCoin = mobileCoin
    }

    @objc
    public func serializedData() throws -> Data {
        return try self.proto.serializedData()
    }

    @objc
    public convenience init(serializedData: Data) throws {
        let proto = try SignalServiceProtos_DataMessage.Payment.Notification(serializedData: serializedData)
        try self.init(proto)
    }

    fileprivate convenience init(_ proto: SignalServiceProtos_DataMessage.Payment.Notification) throws {
        var mobileCoin: SSKProtoDataMessagePaymentNotificationMobileCoin?
        if proto.hasMobileCoin {
            mobileCoin = try SSKProtoDataMessagePaymentNotificationMobileCoin(proto.mobileCoin)
        }

        self.init(proto: proto,
                  mobileCoin: mobileCoin)
    }

    public required convenience init(from decoder: Swift.Decoder) throws {
        let singleValueContainer = try decoder.singleValueContainer()
        let serializedData = try singleValueContainer.decode(Data.self)
        try self.init(serializedData: serializedData)
    }
    public func encode(to encoder: Swift.Encoder) throws {
        var singleValueContainer = encoder.singleValueContainer()
        try singleValueContainer.encode(try serializedData())
    }

    public static var supportsSecureCoding: Bool { true }

    public required convenience init?(coder: NSCoder) {
        guard let serializedData = coder.decodeData() else { return nil }
        do {
            try self.init(serializedData: serializedData)
        } catch {
            owsFailDebug("Failed to decode serialized data \(error)")
            return nil
        }
    }

    public func encode(with coder: NSCoder) {
        do {
            coder.encode(try serializedData())
        } catch {
            owsFailDebug("Failed to encode serialized data \(error)")
        }
    }

    @objc
    public override var debugDescription: String {
        return "\(proto)"
    }
}

extension SSKProtoDataMessagePaymentNotification {
    @objc
    public static func builder() -> SSKProtoDataMessagePaymentNotificationBuilder {
        return SSKProtoDataMessagePaymentNotificationBuilder()
    }

    // asBuilder() constructs a builder that reflects the proto's contents.
    @objc
    public func asBuilder() -> SSKProtoDataMessagePaymentNotificationBuilder {
        let builder = SSKProtoDataMessagePaymentNotificationBuilder()
        if let _value = mobileCoin {
            builder.setMobileCoin(_value)
        }
        if let _value = note {
            builder.setNote(_value)
        }
        if let _value = unknownFields {
            builder.setUnknownFields(_value)
        }
        return builder
    }
}

@objc
public class SSKProtoDataMessagePaymentNotificationBuilder: NSObject {

    private var proto = SignalServiceProtos_DataMessage.Payment.Notification()

    @objc
    fileprivate override init() {}

    @objc
    @available(swift, obsoleted: 1.0)
    public func setMobileCoin(_ valueParam: SSKProtoDataMessagePaymentNotificationMobileCoin?) {
        guard let valueParam = valueParam else { return }
        proto.mobileCoin = valueParam.proto
    }

    public func setMobileCoin(_ valueParam: SSKProtoDataMessagePaymentNotificationMobileCoin) {
        proto.mobileCoin = valueParam.proto
    }

    @objc
    @available(swift, obsoleted: 1.0)
    public func setNote(_ valueParam: String?) {
        guard let valueParam = valueParam else { return }
        proto.note = valueParam
    }

    public func setNote(_ valueParam: String) {
        proto.note = valueParam
    }

    public func setUnknownFields(_ unknownFields: SwiftProtobuf.UnknownStorage) {
        proto.unknownFields = unknownFields
    }

    @objc
    public func build() throws -> SSKProtoDataMessagePaymentNotification {
        return try SSKProtoDataMessagePaymentNotification(proto)
    }

    @objc
    public func buildSerializedData() throws -> Data {
        return try SSKProtoDataMessagePaymentNotification(proto).serializedData()
    }
}

#if TESTABLE_BUILD

extension SSKProtoDataMessagePaymentNotification {
    @objc
    public func serializedDataIgnoringErrors() -> Data? {
        return try! self.serializedData()
    }
}

extension SSKProtoDataMessagePaymentNotificationBuilder {
    @objc
    public func buildIgnoringErrors() -> SSKProtoDataMessagePaymentNotification? {
        return try! self.build()
    }
}

#endif

// MARK: - SSKProtoDataMessagePaymentActivationType

@objc
public enum SSKProtoDataMessagePaymentActivationType: Int32 {
    case request = 0
    case activated = 1
}

private func SSKProtoDataMessagePaymentActivationTypeWrap(_ value: SignalServiceProtos_DataMessage.Payment.Activation.TypeEnum) -> SSKProtoDataMessagePaymentActivationType {
    switch value {
    case .request: return .request
    case .activated: return .activated
    }
}

private func SSKProtoDataMessagePaymentActivationTypeUnwrap(_ value: SSKProtoDataMessagePaymentActivationType) -> SignalServiceProtos_DataMessage.Payment.Activation.TypeEnum {
    switch value {
    case .request: return .request
    case .activated: return .activated
    }
}

// MARK: - SSKProtoDataMessagePaymentActivation

@objc
public class SSKProtoDataMessagePaymentActivation: NSObject, Codable, NSSecureCoding {

    fileprivate let proto: SignalServiceProtos_DataMessage.Payment.Activation

    public var type: SSKProtoDataMessagePaymentActivationType? {
        guard hasType else {
            return nil
        }
        return SSKProtoDataMessagePaymentActivationTypeWrap(proto.type)
    }
    // This "unwrapped" accessor should only be used if the "has value" accessor has already been checked.
    @objc
    public var unwrappedType: SSKProtoDataMessagePaymentActivationType {
        if !hasType {
            // TODO: We could make this a crashing assert.
            owsFailDebug("Unsafe unwrap of missing optional: Activation.type.")
        }
        return SSKProtoDataMessagePaymentActivationTypeWrap(proto.type)
    }
    @objc
    public var hasType: Bool {
        return proto.hasType
    }

    public var hasUnknownFields: Bool {
        return !proto.unknownFields.data.isEmpty
    }
    public var unknownFields: SwiftProtobuf.UnknownStorage? {
        guard hasUnknownFields else { return nil }
        return proto.unknownFields
    }

    private init(proto: SignalServiceProtos_DataMessage.Payment.Activation) {
        self.proto = proto
    }

    @objc
    public func serializedData() throws -> Data {
        return try self.proto.serializedData()
    }

    @objc
    public convenience init(serializedData: Data) throws {
        let proto = try SignalServiceProtos_DataMessage.Payment.Activation(serializedData: serializedData)
        self.init(proto)
    }

    fileprivate convenience init(_ proto: SignalServiceProtos_DataMessage.Payment.Activation) {
        self.init(proto: proto)
    }

    public required convenience init(from decoder: Swift.Decoder) throws {
        let singleValueContainer = try decoder.singleValueContainer()
        let serializedData = try singleValueContainer.decode(Data.self)
        try self.init(serializedData: serializedData)
    }
    public func encode(to encoder: Swift.Encoder) throws {
        var singleValueContainer = encoder.singleValueContainer()
        try singleValueContainer.encode(try serializedData())
    }

    public static var supportsSecureCoding: Bool { true }

    public required convenience init?(coder: NSCoder) {
        guard let serializedData = coder.decodeData() else { return nil }
        do {
            try self.init(serializedData: serializedData)
        } catch {
            owsFailDebug("Failed to decode serialized data \(error)")
            return nil
        }
    }

    public func encode(with coder: NSCoder) {
        do {
            coder.encode(try serializedData())
        } catch {
            owsFailDebug("Failed to encode serialized data \(error)")
        }
    }

    @objc
    public override var debugDescription: String {
        return "\(proto)"
    }
}

extension SSKProtoDataMessagePaymentActivation {
    @objc
    public static func builder() -> SSKProtoDataMessagePaymentActivationBuilder {
        return SSKProtoDataMessagePaymentActivationBuilder()
    }

    // asBuilder() constructs a builder that reflects the proto's contents.
    @objc
    public func asBuilder() -> SSKProtoDataMessagePaymentActivationBuilder {
        let builder = SSKProtoDataMessagePaymentActivationBuilder()
        if let _value = type {
            builder.setType(_value)
        }
        if let _value = unknownFields {
            builder.setUnknownFields(_value)
        }
        return builder
    }
}

@objc
public class SSKProtoDataMessagePaymentActivationBuilder: NSObject {

    private var proto = SignalServiceProtos_DataMessage.Payment.Activation()

    @objc
    fileprivate override init() {}

    @objc
    public func setType(_ valueParam: SSKProtoDataMessagePaymentActivationType) {
        proto.type = SSKProtoDataMessagePaymentActivationTypeUnwrap(valueParam)
    }

    public func setUnknownFields(_ unknownFields: SwiftProtobuf.UnknownStorage) {
        proto.unknownFields = unknownFields
    }

    @objc
    public func build() throws -> SSKProtoDataMessagePaymentActivation {
        return SSKProtoDataMessagePaymentActivation(proto)
    }

    @objc
    public func buildInfallibly() -> SSKProtoDataMessagePaymentActivation {
        return SSKProtoDataMessagePaymentActivation(proto)
    }

    @objc
    public func buildSerializedData() throws -> Data {
        return try SSKProtoDataMessagePaymentActivation(proto).serializedData()
    }
}

#if TESTABLE_BUILD

extension SSKProtoDataMessagePaymentActivation {
    @objc
    public func serializedDataIgnoringErrors() -> Data? {
        return try! self.serializedData()
    }
}

extension SSKProtoDataMessagePaymentActivationBuilder {
    @objc
    public func buildIgnoringErrors() -> SSKProtoDataMessagePaymentActivation? {
        return self.buildInfallibly()
    }
}

#endif

// MARK: - SSKProtoDataMessagePayment

@objc
public class SSKProtoDataMessagePayment: NSObject, Codable, NSSecureCoding {

    fileprivate let proto: SignalServiceProtos_DataMessage.Payment

    @objc
    public let notification: SSKProtoDataMessagePaymentNotification?

    @objc
    public let activation: SSKProtoDataMessagePaymentActivation?

    public var hasUnknownFields: Bool {
        return !proto.unknownFields.data.isEmpty
    }
    public var unknownFields: SwiftProtobuf.UnknownStorage? {
        guard hasUnknownFields else { return nil }
        return proto.unknownFields
    }

    private init(proto: SignalServiceProtos_DataMessage.Payment,
                 notification: SSKProtoDataMessagePaymentNotification?,
                 activation: SSKProtoDataMessagePaymentActivation?) {
        self.proto = proto
        self.notification = notification
        self.activation = activation
    }

    @objc
    public func serializedData() throws -> Data {
        return try self.proto.serializedData()
    }

    @objc
    public convenience init(serializedData: Data) throws {
        let proto = try SignalServiceProtos_DataMessage.Payment(serializedData: serializedData)
        try self.init(proto)
    }

    fileprivate convenience init(_ proto: SignalServiceProtos_DataMessage.Payment) throws {
        var notification: SSKProtoDataMessagePaymentNotification?
        if proto.hasNotification {
            notification = try SSKProtoDataMessagePaymentNotification(proto.notification)
        }

        var activation: SSKProtoDataMessagePaymentActivation?
        if proto.hasActivation {
            activation = SSKProtoDataMessagePaymentActivation(proto.activation)
        }

        self.init(proto: proto,
                  notification: notification,
                  activation: activation)
    }

    public required convenience init(from decoder: Swift.Decoder) throws {
        let singleValueContainer = try decoder.singleValueContainer()
        let serializedData = try singleValueContainer.decode(Data.self)
        try self.init(serializedData: serializedData)
    }
    public func encode(to encoder: Swift.Encoder) throws {
        var singleValueContainer = encoder.singleValueContainer()
        try singleValueContainer.encode(try serializedData())
    }

    public static var supportsSecureCoding: Bool { true }

    public required convenience init?(coder: NSCoder) {
        guard let serializedData = coder.decodeData() else { return nil }
        do {
            try self.init(serializedData: serializedData)
        } catch {
            owsFailDebug("Failed to decode serialized data \(error)")
            return nil
        }
    }

    public func encode(with coder: NSCoder) {
        do {
            coder.encode(try serializedData())
        } catch {
            owsFailDebug("Failed to encode serialized data \(error)")
        }
    }

    @objc
    public override var debugDescription: String {
        return "\(proto)"
    }
}

extension SSKProtoDataMessagePayment {
    @objc
    public static func builder() -> SSKProtoDataMessagePaymentBuilder {
        return SSKProtoDataMessagePaymentBuilder()
    }

    // asBuilder() constructs a builder that reflects the proto's contents.
    @objc
    public func asBuilder() -> SSKProtoDataMessagePaymentBuilder {
        let builder = SSKProtoDataMessagePaymentBuilder()
        if let _value = notification {
            builder.setNotification(_value)
        }
        if let _value = activation {
            builder.setActivation(_value)
        }
        if let _value = unknownFields {
            builder.setUnknownFields(_value)
        }
        return builder
    }
}

@objc
public class SSKProtoDataMessagePaymentBuilder: NSObject {

    private var proto = SignalServiceProtos_DataMessage.Payment()

    @objc
    fileprivate override init() {}

    @objc
    @available(swift, obsoleted: 1.0)
    public func setNotification(_ valueParam: SSKProtoDataMessagePaymentNotification?) {
        guard let valueParam = valueParam else { return }
        proto.notification = valueParam.proto
    }

    public func setNotification(_ valueParam: SSKProtoDataMessagePaymentNotification) {
        proto.notification = valueParam.proto
    }

    @objc
    @available(swift, obsoleted: 1.0)
    public func setActivation(_ valueParam: SSKProtoDataMessagePaymentActivation?) {
        guard let valueParam = valueParam else { return }
        proto.activation = valueParam.proto
    }

    public func setActivation(_ valueParam: SSKProtoDataMessagePaymentActivation) {
        proto.activation = valueParam.proto
    }

    public func setUnknownFields(_ unknownFields: SwiftProtobuf.UnknownStorage) {
        proto.unknownFields = unknownFields
    }

    @objc
    public func build() throws -> SSKProtoDataMessagePayment {
        return try SSKProtoDataMessagePayment(proto)
    }

    @objc
    public func buildSerializedData() throws -> Data {
        return try SSKProtoDataMessagePayment(proto).serializedData()
    }
}

#if TESTABLE_BUILD

extension SSKProtoDataMessagePayment {
    @objc
    public func serializedDataIgnoringErrors() -> Data? {
        return try! self.serializedData()
    }
}

extension SSKProtoDataMessagePaymentBuilder {
    @objc
    public func buildIgnoringErrors() -> SSKProtoDataMessagePayment? {
        return try! self.build()
    }
}

#endif

// MARK: - SSKProtoDataMessageStoryContext

@objc
public class SSKProtoDataMessageStoryContext: NSObject, Codable, NSSecureCoding {

    fileprivate let proto: SignalServiceProtos_DataMessage.StoryContext

    @objc
    public var authorAci: String? {
        guard hasAuthorAci else {
            return nil
        }
        return proto.authorAci
    }
    @objc
    public var hasAuthorAci: Bool {
        return proto.hasAuthorAci
    }

    @objc
    public var sentTimestamp: UInt64 {
        return proto.sentTimestamp
    }
    @objc
    public var hasSentTimestamp: Bool {
        return proto.hasSentTimestamp
    }

    public var hasUnknownFields: Bool {
        return !proto.unknownFields.data.isEmpty
    }
    public var unknownFields: SwiftProtobuf.UnknownStorage? {
        guard hasUnknownFields else { return nil }
        return proto.unknownFields
    }

    private init(proto: SignalServiceProtos_DataMessage.StoryContext) {
        self.proto = proto
    }

    @objc
    public func serializedData() throws -> Data {
        return try self.proto.serializedData()
    }

    @objc
    public convenience init(serializedData: Data) throws {
        let proto = try SignalServiceProtos_DataMessage.StoryContext(serializedData: serializedData)
        self.init(proto)
    }

    fileprivate convenience init(_ proto: SignalServiceProtos_DataMessage.StoryContext) {
        self.init(proto: proto)
    }

    public required convenience init(from decoder: Swift.Decoder) throws {
        let singleValueContainer = try decoder.singleValueContainer()
        let serializedData = try singleValueContainer.decode(Data.self)
        try self.init(serializedData: serializedData)
    }
    public func encode(to encoder: Swift.Encoder) throws {
        var singleValueContainer = encoder.singleValueContainer()
        try singleValueContainer.encode(try serializedData())
    }

    public static var supportsSecureCoding: Bool { true }

    public required convenience init?(coder: NSCoder) {
        guard let serializedData = coder.decodeData() else { return nil }
        do {
            try self.init(serializedData: serializedData)
        } catch {
            owsFailDebug("Failed to decode serialized data \(error)")
            return nil
        }
    }

    public func encode(with coder: NSCoder) {
        do {
            coder.encode(try serializedData())
        } catch {
            owsFailDebug("Failed to encode serialized data \(error)")
        }
    }

    @objc
    public override var debugDescription: String {
        return "\(proto)"
    }
}

extension SSKProtoDataMessageStoryContext {
    @objc
    public static func builder() -> SSKProtoDataMessageStoryContextBuilder {
        return SSKProtoDataMessageStoryContextBuilder()
    }

    // asBuilder() constructs a builder that reflects the proto's contents.
    @objc
    public func asBuilder() -> SSKProtoDataMessageStoryContextBuilder {
        let builder = SSKProtoDataMessageStoryContextBuilder()
        if let _value = authorAci {
            builder.setAuthorAci(_value)
        }
        if hasSentTimestamp {
            builder.setSentTimestamp(sentTimestamp)
        }
        if let _value = unknownFields {
            builder.setUnknownFields(_value)
        }
        return builder
    }
}

@objc
public class SSKProtoDataMessageStoryContextBuilder: NSObject {

    private var proto = SignalServiceProtos_DataMessage.StoryContext()

    @objc
    fileprivate override init() {}

    @objc
    @available(swift, obsoleted: 1.0)
    public func setAuthorAci(_ valueParam: String?) {
        guard let valueParam = valueParam else { return }
        proto.authorAci = valueParam
    }

    public func setAuthorAci(_ valueParam: String) {
        proto.authorAci = valueParam
    }

    @objc
    public func setSentTimestamp(_ valueParam: UInt64) {
        proto.sentTimestamp = valueParam
    }

    public func setUnknownFields(_ unknownFields: SwiftProtobuf.UnknownStorage) {
        proto.unknownFields = unknownFields
    }

    @objc
    public func build() throws -> SSKProtoDataMessageStoryContext {
        return SSKProtoDataMessageStoryContext(proto)
    }

    @objc
    public func buildInfallibly() -> SSKProtoDataMessageStoryContext {
        return SSKProtoDataMessageStoryContext(proto)
    }

    @objc
    public func buildSerializedData() throws -> Data {
        return try SSKProtoDataMessageStoryContext(proto).serializedData()
    }
}

#if TESTABLE_BUILD

extension SSKProtoDataMessageStoryContext {
    @objc
    public func serializedDataIgnoringErrors() -> Data? {
        return try! self.serializedData()
    }
}

extension SSKProtoDataMessageStoryContextBuilder {
    @objc
    public func buildIgnoringErrors() -> SSKProtoDataMessageStoryContext? {
        return self.buildInfallibly()
    }
}

#endif

// MARK: - SSKProtoDataMessageGiftBadge

@objc
public class SSKProtoDataMessageGiftBadge: NSObject, Codable, NSSecureCoding {

    fileprivate let proto: SignalServiceProtos_DataMessage.GiftBadge

    @objc
    public var receiptCredentialPresentation: Data? {
        guard hasReceiptCredentialPresentation else {
            return nil
        }
        return proto.receiptCredentialPresentation
    }
    @objc
    public var hasReceiptCredentialPresentation: Bool {
        return proto.hasReceiptCredentialPresentation
    }

    public var hasUnknownFields: Bool {
        return !proto.unknownFields.data.isEmpty
    }
    public var unknownFields: SwiftProtobuf.UnknownStorage? {
        guard hasUnknownFields else { return nil }
        return proto.unknownFields
    }

    private init(proto: SignalServiceProtos_DataMessage.GiftBadge) {
        self.proto = proto
    }

    @objc
    public func serializedData() throws -> Data {
        return try self.proto.serializedData()
    }

    @objc
    public convenience init(serializedData: Data) throws {
        let proto = try SignalServiceProtos_DataMessage.GiftBadge(serializedData: serializedData)
        self.init(proto)
    }

    fileprivate convenience init(_ proto: SignalServiceProtos_DataMessage.GiftBadge) {
        self.init(proto: proto)
    }

    public required convenience init(from decoder: Swift.Decoder) throws {
        let singleValueContainer = try decoder.singleValueContainer()
        let serializedData = try singleValueContainer.decode(Data.self)
        try self.init(serializedData: serializedData)
    }
    public func encode(to encoder: Swift.Encoder) throws {
        var singleValueContainer = encoder.singleValueContainer()
        try singleValueContainer.encode(try serializedData())
    }

    public static var supportsSecureCoding: Bool { true }

    public required convenience init?(coder: NSCoder) {
        guard let serializedData = coder.decodeData() else { return nil }
        do {
            try self.init(serializedData: serializedData)
        } catch {
            owsFailDebug("Failed to decode serialized data \(error)")
            return nil
        }
    }

    public func encode(with coder: NSCoder) {
        do {
            coder.encode(try serializedData())
        } catch {
            owsFailDebug("Failed to encode serialized data \(error)")
        }
    }

    @objc
    public override var debugDescription: String {
        return "\(proto)"
    }
}

extension SSKProtoDataMessageGiftBadge {
    @objc
    public static func builder() -> SSKProtoDataMessageGiftBadgeBuilder {
        return SSKProtoDataMessageGiftBadgeBuilder()
    }

    // asBuilder() constructs a builder that reflects the proto's contents.
    @objc
    public func asBuilder() -> SSKProtoDataMessageGiftBadgeBuilder {
        let builder = SSKProtoDataMessageGiftBadgeBuilder()
        if let _value = receiptCredentialPresentation {
            builder.setReceiptCredentialPresentation(_value)
        }
        if let _value = unknownFields {
            builder.setUnknownFields(_value)
        }
        return builder
    }
}

@objc
public class SSKProtoDataMessageGiftBadgeBuilder: NSObject {

    private var proto = SignalServiceProtos_DataMessage.GiftBadge()

    @objc
    fileprivate override init() {}

    @objc
    @available(swift, obsoleted: 1.0)
    public func setReceiptCredentialPresentation(_ valueParam: Data?) {
        guard let valueParam = valueParam else { return }
        proto.receiptCredentialPresentation = valueParam
    }

    public func setReceiptCredentialPresentation(_ valueParam: Data) {
        proto.receiptCredentialPresentation = valueParam
    }

    public func setUnknownFields(_ unknownFields: SwiftProtobuf.UnknownStorage) {
        proto.unknownFields = unknownFields
    }

    @objc
    public func build() throws -> SSKProtoDataMessageGiftBadge {
        return SSKProtoDataMessageGiftBadge(proto)
    }

    @objc
    public func buildInfallibly() -> SSKProtoDataMessageGiftBadge {
        return SSKProtoDataMessageGiftBadge(proto)
    }

    @objc
    public func buildSerializedData() throws -> Data {
        return try SSKProtoDataMessageGiftBadge(proto).serializedData()
    }
}

#if TESTABLE_BUILD

extension SSKProtoDataMessageGiftBadge {
    @objc
    public func serializedDataIgnoringErrors() -> Data? {
        return try! self.serializedData()
    }
}

extension SSKProtoDataMessageGiftBadgeBuilder {
    @objc
    public func buildIgnoringErrors() -> SSKProtoDataMessageGiftBadge? {
        return self.buildInfallibly()
    }
}

#endif

// MARK: - SSKProtoDataMessageFlags

@objc
public enum SSKProtoDataMessageFlags: Int32 {
    case endSession = 1
    case expirationTimerUpdate = 2
    case profileKeyUpdate = 4
}

private func SSKProtoDataMessageFlagsWrap(_ value: SignalServiceProtos_DataMessage.Flags) -> SSKProtoDataMessageFlags {
    switch value {
    case .endSession: return .endSession
    case .expirationTimerUpdate: return .expirationTimerUpdate
    case .profileKeyUpdate: return .profileKeyUpdate
    }
}

private func SSKProtoDataMessageFlagsUnwrap(_ value: SSKProtoDataMessageFlags) -> SignalServiceProtos_DataMessage.Flags {
    switch value {
    case .endSession: return .endSession
    case .expirationTimerUpdate: return .expirationTimerUpdate
    case .profileKeyUpdate: return .profileKeyUpdate
    }
}

// MARK: - SSKProtoDataMessageProtocolVersion

@objc
public enum SSKProtoDataMessageProtocolVersion: Int32 {
    case initial = 0
    case messageTimers = 1
    case viewOnce = 2
    case viewOnceVideo = 3
    case reactions = 4
    case cdnSelectorAttachments = 5
    case mentions = 6
    case payments = 7
}

private func SSKProtoDataMessageProtocolVersionWrap(_ value: SignalServiceProtos_DataMessage.ProtocolVersion) -> SSKProtoDataMessageProtocolVersion {
    switch value {
    case .initial: return .initial
    case .messageTimers: return .messageTimers
    case .viewOnce: return .viewOnce
    case .viewOnceVideo: return .viewOnceVideo
    case .reactions: return .reactions
    case .cdnSelectorAttachments: return .cdnSelectorAttachments
    case .mentions: return .mentions
    case .payments: return .payments
    }
}

private func SSKProtoDataMessageProtocolVersionUnwrap(_ value: SSKProtoDataMessageProtocolVersion) -> SignalServiceProtos_DataMessage.ProtocolVersion {
    switch value {
    case .initial: return .initial
    case .messageTimers: return .messageTimers
    case .viewOnce: return .viewOnce
    case .viewOnceVideo: return .viewOnceVideo
    case .reactions: return .reactions
    case .cdnSelectorAttachments: return .cdnSelectorAttachments
    case .mentions: return .mentions
    case .payments: return .payments
    }
}

// MARK: - SSKProtoDataMessage

@objc
public class SSKProtoDataMessage: NSObject, Codable, NSSecureCoding {

    fileprivate let proto: SignalServiceProtos_DataMessage

    @objc
    public let attachments: [SSKProtoAttachmentPointer]

    @objc
    public let groupV2: SSKProtoGroupContextV2?

    @objc
    public let quote: SSKProtoDataMessageQuote?

    @objc
    public let contact: [SSKProtoDataMessageContact]

    @objc
    public let preview: [SSKProtoPreview]

    @objc
    public let sticker: SSKProtoDataMessageSticker?

    @objc
    public let reaction: SSKProtoDataMessageReaction?

    @objc
    public let delete: SSKProtoDataMessageDelete?

    @objc
    public let bodyRanges: [SSKProtoBodyRange]

    @objc
    public let groupCallUpdate: SSKProtoDataMessageGroupCallUpdate?

    @objc
    public let payment: SSKProtoDataMessagePayment?

    @objc
    public let storyContext: SSKProtoDataMessageStoryContext?

    @objc
    public let giftBadge: SSKProtoDataMessageGiftBadge?

    @objc
    public var body: String? {
        guard hasBody else {
            return nil
        }
        return proto.body
    }
    @objc
    public var hasBody: Bool {
        return proto.hasBody
    }

    @objc
    public var flags: UInt32 {
        return proto.flags
    }
    @objc
    public var hasFlags: Bool {
        return proto.hasFlags
    }

    @objc
    public var expireTimer: UInt32 {
        return proto.expireTimer
    }
    @objc
    public var hasExpireTimer: Bool {
        return proto.hasExpireTimer
    }

    @objc
    public var profileKey: Data? {
        guard hasProfileKey else {
            return nil
        }
        return proto.profileKey
    }
    @objc
    public var hasProfileKey: Bool {
        return proto.hasProfileKey
    }

    @objc
    public var timestamp: UInt64 {
        return proto.timestamp
    }
    @objc
    public var hasTimestamp: Bool {
        return proto.hasTimestamp
    }

    @objc
    public var requiredProtocolVersion: UInt32 {
        return proto.requiredProtocolVersion
    }
    @objc
    public var hasRequiredProtocolVersion: Bool {
        return proto.hasRequiredProtocolVersion
    }

    @objc
    public var isViewOnce: Bool {
        return proto.isViewOnce
    }
    @objc
    public var hasIsViewOnce: Bool {
        return proto.hasIsViewOnce
    }

    public var hasUnknownFields: Bool {
        return !proto.unknownFields.data.isEmpty
    }
    public var unknownFields: SwiftProtobuf.UnknownStorage? {
        guard hasUnknownFields else { return nil }
        return proto.unknownFields
    }

    private init(proto: SignalServiceProtos_DataMessage,
                 attachments: [SSKProtoAttachmentPointer],
                 groupV2: SSKProtoGroupContextV2?,
                 quote: SSKProtoDataMessageQuote?,
                 contact: [SSKProtoDataMessageContact],
                 preview: [SSKProtoPreview],
                 sticker: SSKProtoDataMessageSticker?,
                 reaction: SSKProtoDataMessageReaction?,
                 delete: SSKProtoDataMessageDelete?,
                 bodyRanges: [SSKProtoBodyRange],
                 groupCallUpdate: SSKProtoDataMessageGroupCallUpdate?,
                 payment: SSKProtoDataMessagePayment?,
                 storyContext: SSKProtoDataMessageStoryContext?,
                 giftBadge: SSKProtoDataMessageGiftBadge?) {
        self.proto = proto
        self.attachments = attachments
        self.groupV2 = groupV2
        self.quote = quote
        self.contact = contact
        self.preview = preview
        self.sticker = sticker
        self.reaction = reaction
        self.delete = delete
        self.bodyRanges = bodyRanges
        self.groupCallUpdate = groupCallUpdate
        self.payment = payment
        self.storyContext = storyContext
        self.giftBadge = giftBadge
    }

    @objc
    public func serializedData() throws -> Data {
        return try self.proto.serializedData()
    }

    @objc
    public convenience init(serializedData: Data) throws {
        let proto = try SignalServiceProtos_DataMessage(serializedData: serializedData)
        try self.init(proto)
    }

    fileprivate convenience init(_ proto: SignalServiceProtos_DataMessage) throws {
        var attachments: [SSKProtoAttachmentPointer] = []
        attachments = proto.attachments.map { SSKProtoAttachmentPointer($0) }

        var groupV2: SSKProtoGroupContextV2?
        if proto.hasGroupV2 {
            groupV2 = SSKProtoGroupContextV2(proto.groupV2)
        }

        var quote: SSKProtoDataMessageQuote?
        if proto.hasQuote {
            quote = try SSKProtoDataMessageQuote(proto.quote)
        }

        var contact: [SSKProtoDataMessageContact] = []
        contact = proto.contact.map { SSKProtoDataMessageContact($0) }

        var preview: [SSKProtoPreview] = []
        preview = try proto.preview.map { try SSKProtoPreview($0) }

        var sticker: SSKProtoDataMessageSticker?
        if proto.hasSticker {
            sticker = try SSKProtoDataMessageSticker(proto.sticker)
        }

        var reaction: SSKProtoDataMessageReaction?
        if proto.hasReaction {
            reaction = try SSKProtoDataMessageReaction(proto.reaction)
        }

        var delete: SSKProtoDataMessageDelete?
        if proto.hasDelete {
            delete = try SSKProtoDataMessageDelete(proto.delete)
        }

        var bodyRanges: [SSKProtoBodyRange] = []
        bodyRanges = proto.bodyRanges.map { SSKProtoBodyRange($0) }

        var groupCallUpdate: SSKProtoDataMessageGroupCallUpdate?
        if proto.hasGroupCallUpdate {
            groupCallUpdate = SSKProtoDataMessageGroupCallUpdate(proto.groupCallUpdate)
        }

        var payment: SSKProtoDataMessagePayment?
        if proto.hasPayment {
            payment = try SSKProtoDataMessagePayment(proto.payment)
        }

        var storyContext: SSKProtoDataMessageStoryContext?
        if proto.hasStoryContext {
            storyContext = SSKProtoDataMessageStoryContext(proto.storyContext)
        }

        var giftBadge: SSKProtoDataMessageGiftBadge?
        if proto.hasGiftBadge {
            giftBadge = SSKProtoDataMessageGiftBadge(proto.giftBadge)
        }

        self.init(proto: proto,
                  attachments: attachments,
                  groupV2: groupV2,
                  quote: quote,
                  contact: contact,
                  preview: preview,
                  sticker: sticker,
                  reaction: reaction,
                  delete: delete,
                  bodyRanges: bodyRanges,
                  groupCallUpdate: groupCallUpdate,
                  payment: payment,
                  storyContext: storyContext,
                  giftBadge: giftBadge)
    }

    public required convenience init(from decoder: Swift.Decoder) throws {
        let singleValueContainer = try decoder.singleValueContainer()
        let serializedData = try singleValueContainer.decode(Data.self)
        try self.init(serializedData: serializedData)
    }
    public func encode(to encoder: Swift.Encoder) throws {
        var singleValueContainer = encoder.singleValueContainer()
        try singleValueContainer.encode(try serializedData())
    }

    public static var supportsSecureCoding: Bool { true }

    public required convenience init?(coder: NSCoder) {
        guard let serializedData = coder.decodeData() else { return nil }
        do {
            try self.init(serializedData: serializedData)
        } catch {
            owsFailDebug("Failed to decode serialized data \(error)")
            return nil
        }
    }

    public func encode(with coder: NSCoder) {
        do {
            coder.encode(try serializedData())
        } catch {
            owsFailDebug("Failed to encode serialized data \(error)")
        }
    }

    @objc
    public override var debugDescription: String {
        return "\(proto)"
    }
}

extension SSKProtoDataMessage {
    @objc
    public static func builder() -> SSKProtoDataMessageBuilder {
        return SSKProtoDataMessageBuilder()
    }

    // asBuilder() constructs a builder that reflects the proto's contents.
    @objc
    public func asBuilder() -> SSKProtoDataMessageBuilder {
        let builder = SSKProtoDataMessageBuilder()
        if let _value = body {
            builder.setBody(_value)
        }
        builder.setAttachments(attachments)
        if let _value = groupV2 {
            builder.setGroupV2(_value)
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
        if hasIsViewOnce {
            builder.setIsViewOnce(isViewOnce)
        }
        if let _value = reaction {
            builder.setReaction(_value)
        }
        if let _value = delete {
            builder.setDelete(_value)
        }
        builder.setBodyRanges(bodyRanges)
        if let _value = groupCallUpdate {
            builder.setGroupCallUpdate(_value)
        }
        if let _value = payment {
            builder.setPayment(_value)
        }
        if let _value = storyContext {
            builder.setStoryContext(_value)
        }
        if let _value = giftBadge {
            builder.setGiftBadge(_value)
        }
        if let _value = unknownFields {
            builder.setUnknownFields(_value)
        }
        return builder
    }
}

@objc
public class SSKProtoDataMessageBuilder: NSObject {

    private var proto = SignalServiceProtos_DataMessage()

    @objc
    fileprivate override init() {}

    @objc
    @available(swift, obsoleted: 1.0)
    public func setBody(_ valueParam: String?) {
        guard let valueParam = valueParam else { return }
        proto.body = valueParam
    }

    public func setBody(_ valueParam: String) {
        proto.body = valueParam
    }

    @objc
    public func addAttachments(_ valueParam: SSKProtoAttachmentPointer) {
        proto.attachments.append(valueParam.proto)
    }

    @objc
    public func setAttachments(_ wrappedItems: [SSKProtoAttachmentPointer]) {
        proto.attachments = wrappedItems.map { $0.proto }
    }

    @objc
    @available(swift, obsoleted: 1.0)
    public func setGroupV2(_ valueParam: SSKProtoGroupContextV2?) {
        guard let valueParam = valueParam else { return }
        proto.groupV2 = valueParam.proto
    }

    public func setGroupV2(_ valueParam: SSKProtoGroupContextV2) {
        proto.groupV2 = valueParam.proto
    }

    @objc
    public func setFlags(_ valueParam: UInt32) {
        proto.flags = valueParam
    }

    @objc
    public func setExpireTimer(_ valueParam: UInt32) {
        proto.expireTimer = valueParam
    }

    @objc
    @available(swift, obsoleted: 1.0)
    public func setProfileKey(_ valueParam: Data?) {
        guard let valueParam = valueParam else { return }
        proto.profileKey = valueParam
    }

    public func setProfileKey(_ valueParam: Data) {
        proto.profileKey = valueParam
    }

    @objc
    public func setTimestamp(_ valueParam: UInt64) {
        proto.timestamp = valueParam
    }

    @objc
    @available(swift, obsoleted: 1.0)
    public func setQuote(_ valueParam: SSKProtoDataMessageQuote?) {
        guard let valueParam = valueParam else { return }
        proto.quote = valueParam.proto
    }

    public func setQuote(_ valueParam: SSKProtoDataMessageQuote) {
        proto.quote = valueParam.proto
    }

    @objc
    public func addContact(_ valueParam: SSKProtoDataMessageContact) {
        proto.contact.append(valueParam.proto)
    }

    @objc
    public func setContact(_ wrappedItems: [SSKProtoDataMessageContact]) {
        proto.contact = wrappedItems.map { $0.proto }
    }

    @objc
    public func addPreview(_ valueParam: SSKProtoPreview) {
        proto.preview.append(valueParam.proto)
    }

    @objc
    public func setPreview(_ wrappedItems: [SSKProtoPreview]) {
        proto.preview = wrappedItems.map { $0.proto }
    }

    @objc
    @available(swift, obsoleted: 1.0)
    public func setSticker(_ valueParam: SSKProtoDataMessageSticker?) {
        guard let valueParam = valueParam else { return }
        proto.sticker = valueParam.proto
    }

    public func setSticker(_ valueParam: SSKProtoDataMessageSticker) {
        proto.sticker = valueParam.proto
    }

    @objc
    public func setRequiredProtocolVersion(_ valueParam: UInt32) {
        proto.requiredProtocolVersion = valueParam
    }

    @objc
    public func setIsViewOnce(_ valueParam: Bool) {
        proto.isViewOnce = valueParam
    }

    @objc
    @available(swift, obsoleted: 1.0)
    public func setReaction(_ valueParam: SSKProtoDataMessageReaction?) {
        guard let valueParam = valueParam else { return }
        proto.reaction = valueParam.proto
    }

    public func setReaction(_ valueParam: SSKProtoDataMessageReaction) {
        proto.reaction = valueParam.proto
    }

    @objc
    @available(swift, obsoleted: 1.0)
    public func setDelete(_ valueParam: SSKProtoDataMessageDelete?) {
        guard let valueParam = valueParam else { return }
        proto.delete = valueParam.proto
    }

    public func setDelete(_ valueParam: SSKProtoDataMessageDelete) {
        proto.delete = valueParam.proto
    }

    @objc
    public func addBodyRanges(_ valueParam: SSKProtoBodyRange) {
        proto.bodyRanges.append(valueParam.proto)
    }

    @objc
    public func setBodyRanges(_ wrappedItems: [SSKProtoBodyRange]) {
        proto.bodyRanges = wrappedItems.map { $0.proto }
    }

    @objc
    @available(swift, obsoleted: 1.0)
    public func setGroupCallUpdate(_ valueParam: SSKProtoDataMessageGroupCallUpdate?) {
        guard let valueParam = valueParam else { return }
        proto.groupCallUpdate = valueParam.proto
    }

    public func setGroupCallUpdate(_ valueParam: SSKProtoDataMessageGroupCallUpdate) {
        proto.groupCallUpdate = valueParam.proto
    }

    @objc
    @available(swift, obsoleted: 1.0)
    public func setPayment(_ valueParam: SSKProtoDataMessagePayment?) {
        guard let valueParam = valueParam else { return }
        proto.payment = valueParam.proto
    }

    public func setPayment(_ valueParam: SSKProtoDataMessagePayment) {
        proto.payment = valueParam.proto
    }

    @objc
    @available(swift, obsoleted: 1.0)
    public func setStoryContext(_ valueParam: SSKProtoDataMessageStoryContext?) {
        guard let valueParam = valueParam else { return }
        proto.storyContext = valueParam.proto
    }

    public func setStoryContext(_ valueParam: SSKProtoDataMessageStoryContext) {
        proto.storyContext = valueParam.proto
    }

    @objc
    @available(swift, obsoleted: 1.0)
    public func setGiftBadge(_ valueParam: SSKProtoDataMessageGiftBadge?) {
        guard let valueParam = valueParam else { return }
        proto.giftBadge = valueParam.proto
    }

    public func setGiftBadge(_ valueParam: SSKProtoDataMessageGiftBadge) {
        proto.giftBadge = valueParam.proto
    }

    public func setUnknownFields(_ unknownFields: SwiftProtobuf.UnknownStorage) {
        proto.unknownFields = unknownFields
    }

    @objc
    public func build() throws -> SSKProtoDataMessage {
        return try SSKProtoDataMessage(proto)
    }

    @objc
    public func buildSerializedData() throws -> Data {
        return try SSKProtoDataMessage(proto).serializedData()
    }
}

#if TESTABLE_BUILD

extension SSKProtoDataMessage {
    @objc
    public func serializedDataIgnoringErrors() -> Data? {
        return try! self.serializedData()
    }
}

extension SSKProtoDataMessageBuilder {
    @objc
    public func buildIgnoringErrors() -> SSKProtoDataMessage? {
        return try! self.build()
    }
}

#endif

// MARK: - SSKProtoNullMessage

@objc
public class SSKProtoNullMessage: NSObject, Codable, NSSecureCoding {

    fileprivate let proto: SignalServiceProtos_NullMessage

    @objc
    public var padding: Data? {
        guard hasPadding else {
            return nil
        }
        return proto.padding
    }
    @objc
    public var hasPadding: Bool {
        return proto.hasPadding
    }

    public var hasUnknownFields: Bool {
        return !proto.unknownFields.data.isEmpty
    }
    public var unknownFields: SwiftProtobuf.UnknownStorage? {
        guard hasUnknownFields else { return nil }
        return proto.unknownFields
    }

    private init(proto: SignalServiceProtos_NullMessage) {
        self.proto = proto
    }

    @objc
    public func serializedData() throws -> Data {
        return try self.proto.serializedData()
    }

    @objc
    public convenience init(serializedData: Data) throws {
        let proto = try SignalServiceProtos_NullMessage(serializedData: serializedData)
        self.init(proto)
    }

    fileprivate convenience init(_ proto: SignalServiceProtos_NullMessage) {
        self.init(proto: proto)
    }

    public required convenience init(from decoder: Swift.Decoder) throws {
        let singleValueContainer = try decoder.singleValueContainer()
        let serializedData = try singleValueContainer.decode(Data.self)
        try self.init(serializedData: serializedData)
    }
    public func encode(to encoder: Swift.Encoder) throws {
        var singleValueContainer = encoder.singleValueContainer()
        try singleValueContainer.encode(try serializedData())
    }

    public static var supportsSecureCoding: Bool { true }

    public required convenience init?(coder: NSCoder) {
        guard let serializedData = coder.decodeData() else { return nil }
        do {
            try self.init(serializedData: serializedData)
        } catch {
            owsFailDebug("Failed to decode serialized data \(error)")
            return nil
        }
    }

    public func encode(with coder: NSCoder) {
        do {
            coder.encode(try serializedData())
        } catch {
            owsFailDebug("Failed to encode serialized data \(error)")
        }
    }

    @objc
    public override var debugDescription: String {
        return "\(proto)"
    }
}

extension SSKProtoNullMessage {
    @objc
    public static func builder() -> SSKProtoNullMessageBuilder {
        return SSKProtoNullMessageBuilder()
    }

    // asBuilder() constructs a builder that reflects the proto's contents.
    @objc
    public func asBuilder() -> SSKProtoNullMessageBuilder {
        let builder = SSKProtoNullMessageBuilder()
        if let _value = padding {
            builder.setPadding(_value)
        }
        if let _value = unknownFields {
            builder.setUnknownFields(_value)
        }
        return builder
    }
}

@objc
public class SSKProtoNullMessageBuilder: NSObject {

    private var proto = SignalServiceProtos_NullMessage()

    @objc
    fileprivate override init() {}

    @objc
    @available(swift, obsoleted: 1.0)
    public func setPadding(_ valueParam: Data?) {
        guard let valueParam = valueParam else { return }
        proto.padding = valueParam
    }

    public func setPadding(_ valueParam: Data) {
        proto.padding = valueParam
    }

    public func setUnknownFields(_ unknownFields: SwiftProtobuf.UnknownStorage) {
        proto.unknownFields = unknownFields
    }

    @objc
    public func build() throws -> SSKProtoNullMessage {
        return SSKProtoNullMessage(proto)
    }

    @objc
    public func buildInfallibly() -> SSKProtoNullMessage {
        return SSKProtoNullMessage(proto)
    }

    @objc
    public func buildSerializedData() throws -> Data {
        return try SSKProtoNullMessage(proto).serializedData()
    }
}

#if TESTABLE_BUILD

extension SSKProtoNullMessage {
    @objc
    public func serializedDataIgnoringErrors() -> Data? {
        return try! self.serializedData()
    }
}

extension SSKProtoNullMessageBuilder {
    @objc
    public func buildIgnoringErrors() -> SSKProtoNullMessage? {
        return self.buildInfallibly()
    }
}

#endif

// MARK: - SSKProtoReceiptMessageType

@objc
public enum SSKProtoReceiptMessageType: Int32 {
    case delivery = 0
    case read = 1
    case viewed = 2
}

private func SSKProtoReceiptMessageTypeWrap(_ value: SignalServiceProtos_ReceiptMessage.TypeEnum) -> SSKProtoReceiptMessageType {
    switch value {
    case .delivery: return .delivery
    case .read: return .read
    case .viewed: return .viewed
    }
}

private func SSKProtoReceiptMessageTypeUnwrap(_ value: SSKProtoReceiptMessageType) -> SignalServiceProtos_ReceiptMessage.TypeEnum {
    switch value {
    case .delivery: return .delivery
    case .read: return .read
    case .viewed: return .viewed
    }
}

// MARK: - SSKProtoReceiptMessage

@objc
public class SSKProtoReceiptMessage: NSObject, Codable, NSSecureCoding {

    fileprivate let proto: SignalServiceProtos_ReceiptMessage

    public var type: SSKProtoReceiptMessageType? {
        guard hasType else {
            return nil
        }
        return SSKProtoReceiptMessageTypeWrap(proto.type)
    }
    // This "unwrapped" accessor should only be used if the "has value" accessor has already been checked.
    @objc
    public var unwrappedType: SSKProtoReceiptMessageType {
        if !hasType {
            // TODO: We could make this a crashing assert.
            owsFailDebug("Unsafe unwrap of missing optional: ReceiptMessage.type.")
        }
        return SSKProtoReceiptMessageTypeWrap(proto.type)
    }
    @objc
    public var hasType: Bool {
        return proto.hasType
    }

    @objc
    public var timestamp: [UInt64] {
        return proto.timestamp
    }

    public var hasUnknownFields: Bool {
        return !proto.unknownFields.data.isEmpty
    }
    public var unknownFields: SwiftProtobuf.UnknownStorage? {
        guard hasUnknownFields else { return nil }
        return proto.unknownFields
    }

    private init(proto: SignalServiceProtos_ReceiptMessage) {
        self.proto = proto
    }

    @objc
    public func serializedData() throws -> Data {
        return try self.proto.serializedData()
    }

    @objc
    public convenience init(serializedData: Data) throws {
        let proto = try SignalServiceProtos_ReceiptMessage(serializedData: serializedData)
        self.init(proto)
    }

    fileprivate convenience init(_ proto: SignalServiceProtos_ReceiptMessage) {
        self.init(proto: proto)
    }

    public required convenience init(from decoder: Swift.Decoder) throws {
        let singleValueContainer = try decoder.singleValueContainer()
        let serializedData = try singleValueContainer.decode(Data.self)
        try self.init(serializedData: serializedData)
    }
    public func encode(to encoder: Swift.Encoder) throws {
        var singleValueContainer = encoder.singleValueContainer()
        try singleValueContainer.encode(try serializedData())
    }

    public static var supportsSecureCoding: Bool { true }

    public required convenience init?(coder: NSCoder) {
        guard let serializedData = coder.decodeData() else { return nil }
        do {
            try self.init(serializedData: serializedData)
        } catch {
            owsFailDebug("Failed to decode serialized data \(error)")
            return nil
        }
    }

    public func encode(with coder: NSCoder) {
        do {
            coder.encode(try serializedData())
        } catch {
            owsFailDebug("Failed to encode serialized data \(error)")
        }
    }

    @objc
    public override var debugDescription: String {
        return "\(proto)"
    }
}

extension SSKProtoReceiptMessage {
    @objc
    public static func builder() -> SSKProtoReceiptMessageBuilder {
        return SSKProtoReceiptMessageBuilder()
    }

    // asBuilder() constructs a builder that reflects the proto's contents.
    @objc
    public func asBuilder() -> SSKProtoReceiptMessageBuilder {
        let builder = SSKProtoReceiptMessageBuilder()
        if let _value = type {
            builder.setType(_value)
        }
        builder.setTimestamp(timestamp)
        if let _value = unknownFields {
            builder.setUnknownFields(_value)
        }
        return builder
    }
}

@objc
public class SSKProtoReceiptMessageBuilder: NSObject {

    private var proto = SignalServiceProtos_ReceiptMessage()

    @objc
    fileprivate override init() {}

    @objc
    public func setType(_ valueParam: SSKProtoReceiptMessageType) {
        proto.type = SSKProtoReceiptMessageTypeUnwrap(valueParam)
    }

    @objc
    public func addTimestamp(_ valueParam: UInt64) {
        proto.timestamp.append(valueParam)
    }

    @objc
    public func setTimestamp(_ wrappedItems: [UInt64]) {
        proto.timestamp = wrappedItems
    }

    public func setUnknownFields(_ unknownFields: SwiftProtobuf.UnknownStorage) {
        proto.unknownFields = unknownFields
    }

    @objc
    public func build() throws -> SSKProtoReceiptMessage {
        return SSKProtoReceiptMessage(proto)
    }

    @objc
    public func buildInfallibly() -> SSKProtoReceiptMessage {
        return SSKProtoReceiptMessage(proto)
    }

    @objc
    public func buildSerializedData() throws -> Data {
        return try SSKProtoReceiptMessage(proto).serializedData()
    }
}

#if TESTABLE_BUILD

extension SSKProtoReceiptMessage {
    @objc
    public func serializedDataIgnoringErrors() -> Data? {
        return try! self.serializedData()
    }
}

extension SSKProtoReceiptMessageBuilder {
    @objc
    public func buildIgnoringErrors() -> SSKProtoReceiptMessage? {
        return self.buildInfallibly()
    }
}

#endif

// MARK: - SSKProtoVerifiedState

@objc
public enum SSKProtoVerifiedState: Int32 {
    case `default` = 0
    case verified = 1
    case unverified = 2
}

private func SSKProtoVerifiedStateWrap(_ value: SignalServiceProtos_Verified.State) -> SSKProtoVerifiedState {
    switch value {
    case .default: return .default
    case .verified: return .verified
    case .unverified: return .unverified
    }
}

private func SSKProtoVerifiedStateUnwrap(_ value: SSKProtoVerifiedState) -> SignalServiceProtos_Verified.State {
    switch value {
    case .default: return .default
    case .verified: return .verified
    case .unverified: return .unverified
    }
}

// MARK: - SSKProtoVerified

@objc
public class SSKProtoVerified: NSObject, Codable, NSSecureCoding {

    fileprivate let proto: SignalServiceProtos_Verified

    @objc
    public var destinationAci: String? {
        guard hasDestinationAci else {
            return nil
        }
        return proto.destinationAci
    }
    @objc
    public var hasDestinationAci: Bool {
        return proto.hasDestinationAci
    }

    @objc
    public var identityKey: Data? {
        guard hasIdentityKey else {
            return nil
        }
        return proto.identityKey
    }
    @objc
    public var hasIdentityKey: Bool {
        return proto.hasIdentityKey
    }

    public var state: SSKProtoVerifiedState? {
        guard hasState else {
            return nil
        }
        return SSKProtoVerifiedStateWrap(proto.state)
    }
    // This "unwrapped" accessor should only be used if the "has value" accessor has already been checked.
    @objc
    public var unwrappedState: SSKProtoVerifiedState {
        if !hasState {
            // TODO: We could make this a crashing assert.
            owsFailDebug("Unsafe unwrap of missing optional: Verified.state.")
        }
        return SSKProtoVerifiedStateWrap(proto.state)
    }
    @objc
    public var hasState: Bool {
        return proto.hasState
    }

    @objc
    public var nullMessage: Data? {
        guard hasNullMessage else {
            return nil
        }
        return proto.nullMessage
    }
    @objc
    public var hasNullMessage: Bool {
        return proto.hasNullMessage
    }

    public var hasUnknownFields: Bool {
        return !proto.unknownFields.data.isEmpty
    }
    public var unknownFields: SwiftProtobuf.UnknownStorage? {
        guard hasUnknownFields else { return nil }
        return proto.unknownFields
    }

    private init(proto: SignalServiceProtos_Verified) {
        self.proto = proto
    }

    @objc
    public func serializedData() throws -> Data {
        return try self.proto.serializedData()
    }

    @objc
    public convenience init(serializedData: Data) throws {
        let proto = try SignalServiceProtos_Verified(serializedData: serializedData)
        self.init(proto)
    }

    fileprivate convenience init(_ proto: SignalServiceProtos_Verified) {
        self.init(proto: proto)
    }

    public required convenience init(from decoder: Swift.Decoder) throws {
        let singleValueContainer = try decoder.singleValueContainer()
        let serializedData = try singleValueContainer.decode(Data.self)
        try self.init(serializedData: serializedData)
    }
    public func encode(to encoder: Swift.Encoder) throws {
        var singleValueContainer = encoder.singleValueContainer()
        try singleValueContainer.encode(try serializedData())
    }

    public static var supportsSecureCoding: Bool { true }

    public required convenience init?(coder: NSCoder) {
        guard let serializedData = coder.decodeData() else { return nil }
        do {
            try self.init(serializedData: serializedData)
        } catch {
            owsFailDebug("Failed to decode serialized data \(error)")
            return nil
        }
    }

    public func encode(with coder: NSCoder) {
        do {
            coder.encode(try serializedData())
        } catch {
            owsFailDebug("Failed to encode serialized data \(error)")
        }
    }

    @objc
    public override var debugDescription: String {
        return "\(proto)"
    }
}

extension SSKProtoVerified {
    @objc
    public static func builder() -> SSKProtoVerifiedBuilder {
        return SSKProtoVerifiedBuilder()
    }

    // asBuilder() constructs a builder that reflects the proto's contents.
    @objc
    public func asBuilder() -> SSKProtoVerifiedBuilder {
        let builder = SSKProtoVerifiedBuilder()
        if let _value = destinationAci {
            builder.setDestinationAci(_value)
        }
        if let _value = identityKey {
            builder.setIdentityKey(_value)
        }
        if let _value = state {
            builder.setState(_value)
        }
        if let _value = nullMessage {
            builder.setNullMessage(_value)
        }
        if let _value = unknownFields {
            builder.setUnknownFields(_value)
        }
        return builder
    }
}

@objc
public class SSKProtoVerifiedBuilder: NSObject {

    private var proto = SignalServiceProtos_Verified()

    @objc
    fileprivate override init() {}

    @objc
    @available(swift, obsoleted: 1.0)
    public func setDestinationAci(_ valueParam: String?) {
        guard let valueParam = valueParam else { return }
        proto.destinationAci = valueParam
    }

    public func setDestinationAci(_ valueParam: String) {
        proto.destinationAci = valueParam
    }

    @objc
    @available(swift, obsoleted: 1.0)
    public func setIdentityKey(_ valueParam: Data?) {
        guard let valueParam = valueParam else { return }
        proto.identityKey = valueParam
    }

    public func setIdentityKey(_ valueParam: Data) {
        proto.identityKey = valueParam
    }

    @objc
    public func setState(_ valueParam: SSKProtoVerifiedState) {
        proto.state = SSKProtoVerifiedStateUnwrap(valueParam)
    }

    @objc
    @available(swift, obsoleted: 1.0)
    public func setNullMessage(_ valueParam: Data?) {
        guard let valueParam = valueParam else { return }
        proto.nullMessage = valueParam
    }

    public func setNullMessage(_ valueParam: Data) {
        proto.nullMessage = valueParam
    }

    public func setUnknownFields(_ unknownFields: SwiftProtobuf.UnknownStorage) {
        proto.unknownFields = unknownFields
    }

    @objc
    public func build() throws -> SSKProtoVerified {
        return SSKProtoVerified(proto)
    }

    @objc
    public func buildInfallibly() -> SSKProtoVerified {
        return SSKProtoVerified(proto)
    }

    @objc
    public func buildSerializedData() throws -> Data {
        return try SSKProtoVerified(proto).serializedData()
    }
}

#if TESTABLE_BUILD

extension SSKProtoVerified {
    @objc
    public func serializedDataIgnoringErrors() -> Data? {
        return try! self.serializedData()
    }
}

extension SSKProtoVerifiedBuilder {
    @objc
    public func buildIgnoringErrors() -> SSKProtoVerified? {
        return self.buildInfallibly()
    }
}

#endif

// MARK: - SSKProtoSyncMessageSentUnidentifiedDeliveryStatus

@objc
public class SSKProtoSyncMessageSentUnidentifiedDeliveryStatus: NSObject, Codable, NSSecureCoding {

    fileprivate let proto: SignalServiceProtos_SyncMessage.Sent.UnidentifiedDeliveryStatus

    @objc
    public var destinationServiceID: String? {
        guard hasDestinationServiceID else {
            return nil
        }
        return proto.destinationServiceID
    }
    @objc
    public var hasDestinationServiceID: Bool {
        return proto.hasDestinationServiceID
    }

    @objc
    public var unidentified: Bool {
        return proto.unidentified
    }
    @objc
    public var hasUnidentified: Bool {
        return proto.hasUnidentified
    }

    public var hasUnknownFields: Bool {
        return !proto.unknownFields.data.isEmpty
    }
    public var unknownFields: SwiftProtobuf.UnknownStorage? {
        guard hasUnknownFields else { return nil }
        return proto.unknownFields
    }

    private init(proto: SignalServiceProtos_SyncMessage.Sent.UnidentifiedDeliveryStatus) {
        self.proto = proto
    }

    @objc
    public func serializedData() throws -> Data {
        return try self.proto.serializedData()
    }

    @objc
    public convenience init(serializedData: Data) throws {
        let proto = try SignalServiceProtos_SyncMessage.Sent.UnidentifiedDeliveryStatus(serializedData: serializedData)
        self.init(proto)
    }

    fileprivate convenience init(_ proto: SignalServiceProtos_SyncMessage.Sent.UnidentifiedDeliveryStatus) {
        self.init(proto: proto)
    }

    public required convenience init(from decoder: Swift.Decoder) throws {
        let singleValueContainer = try decoder.singleValueContainer()
        let serializedData = try singleValueContainer.decode(Data.self)
        try self.init(serializedData: serializedData)
    }
    public func encode(to encoder: Swift.Encoder) throws {
        var singleValueContainer = encoder.singleValueContainer()
        try singleValueContainer.encode(try serializedData())
    }

    public static var supportsSecureCoding: Bool { true }

    public required convenience init?(coder: NSCoder) {
        guard let serializedData = coder.decodeData() else { return nil }
        do {
            try self.init(serializedData: serializedData)
        } catch {
            owsFailDebug("Failed to decode serialized data \(error)")
            return nil
        }
    }

    public func encode(with coder: NSCoder) {
        do {
            coder.encode(try serializedData())
        } catch {
            owsFailDebug("Failed to encode serialized data \(error)")
        }
    }

    @objc
    public override var debugDescription: String {
        return "\(proto)"
    }
}

extension SSKProtoSyncMessageSentUnidentifiedDeliveryStatus {
    @objc
    public static func builder() -> SSKProtoSyncMessageSentUnidentifiedDeliveryStatusBuilder {
        return SSKProtoSyncMessageSentUnidentifiedDeliveryStatusBuilder()
    }

    // asBuilder() constructs a builder that reflects the proto's contents.
    @objc
    public func asBuilder() -> SSKProtoSyncMessageSentUnidentifiedDeliveryStatusBuilder {
        let builder = SSKProtoSyncMessageSentUnidentifiedDeliveryStatusBuilder()
        if let _value = destinationServiceID {
            builder.setDestinationServiceID(_value)
        }
        if hasUnidentified {
            builder.setUnidentified(unidentified)
        }
        if let _value = unknownFields {
            builder.setUnknownFields(_value)
        }
        return builder
    }
}

@objc
public class SSKProtoSyncMessageSentUnidentifiedDeliveryStatusBuilder: NSObject {

    private var proto = SignalServiceProtos_SyncMessage.Sent.UnidentifiedDeliveryStatus()

    @objc
    fileprivate override init() {}

    @objc
    @available(swift, obsoleted: 1.0)
    public func setDestinationServiceID(_ valueParam: String?) {
        guard let valueParam = valueParam else { return }
        proto.destinationServiceID = valueParam
    }

    public func setDestinationServiceID(_ valueParam: String) {
        proto.destinationServiceID = valueParam
    }

    @objc
    public func setUnidentified(_ valueParam: Bool) {
        proto.unidentified = valueParam
    }

    public func setUnknownFields(_ unknownFields: SwiftProtobuf.UnknownStorage) {
        proto.unknownFields = unknownFields
    }

    @objc
    public func build() throws -> SSKProtoSyncMessageSentUnidentifiedDeliveryStatus {
        return SSKProtoSyncMessageSentUnidentifiedDeliveryStatus(proto)
    }

    @objc
    public func buildInfallibly() -> SSKProtoSyncMessageSentUnidentifiedDeliveryStatus {
        return SSKProtoSyncMessageSentUnidentifiedDeliveryStatus(proto)
    }

    @objc
    public func buildSerializedData() throws -> Data {
        return try SSKProtoSyncMessageSentUnidentifiedDeliveryStatus(proto).serializedData()
    }
}

#if TESTABLE_BUILD

extension SSKProtoSyncMessageSentUnidentifiedDeliveryStatus {
    @objc
    public func serializedDataIgnoringErrors() -> Data? {
        return try! self.serializedData()
    }
}

extension SSKProtoSyncMessageSentUnidentifiedDeliveryStatusBuilder {
    @objc
    public func buildIgnoringErrors() -> SSKProtoSyncMessageSentUnidentifiedDeliveryStatus? {
        return self.buildInfallibly()
    }
}

#endif

// MARK: - SSKProtoSyncMessageSentStoryMessageRecipient

@objc
public class SSKProtoSyncMessageSentStoryMessageRecipient: NSObject, Codable, NSSecureCoding {

    fileprivate let proto: SignalServiceProtos_SyncMessage.Sent.StoryMessageRecipient

    @objc
    public var destinationServiceID: String? {
        guard hasDestinationServiceID else {
            return nil
        }
        return proto.destinationServiceID
    }
    @objc
    public var hasDestinationServiceID: Bool {
        return proto.hasDestinationServiceID
    }

    @objc
    public var distributionListIds: [String] {
        return proto.distributionListIds
    }

    @objc
    public var isAllowedToReply: Bool {
        return proto.isAllowedToReply
    }
    @objc
    public var hasIsAllowedToReply: Bool {
        return proto.hasIsAllowedToReply
    }

    public var hasUnknownFields: Bool {
        return !proto.unknownFields.data.isEmpty
    }
    public var unknownFields: SwiftProtobuf.UnknownStorage? {
        guard hasUnknownFields else { return nil }
        return proto.unknownFields
    }

    private init(proto: SignalServiceProtos_SyncMessage.Sent.StoryMessageRecipient) {
        self.proto = proto
    }

    @objc
    public func serializedData() throws -> Data {
        return try self.proto.serializedData()
    }

    @objc
    public convenience init(serializedData: Data) throws {
        let proto = try SignalServiceProtos_SyncMessage.Sent.StoryMessageRecipient(serializedData: serializedData)
        self.init(proto)
    }

    fileprivate convenience init(_ proto: SignalServiceProtos_SyncMessage.Sent.StoryMessageRecipient) {
        self.init(proto: proto)
    }

    public required convenience init(from decoder: Swift.Decoder) throws {
        let singleValueContainer = try decoder.singleValueContainer()
        let serializedData = try singleValueContainer.decode(Data.self)
        try self.init(serializedData: serializedData)
    }
    public func encode(to encoder: Swift.Encoder) throws {
        var singleValueContainer = encoder.singleValueContainer()
        try singleValueContainer.encode(try serializedData())
    }

    public static var supportsSecureCoding: Bool { true }

    public required convenience init?(coder: NSCoder) {
        guard let serializedData = coder.decodeData() else { return nil }
        do {
            try self.init(serializedData: serializedData)
        } catch {
            owsFailDebug("Failed to decode serialized data \(error)")
            return nil
        }
    }

    public func encode(with coder: NSCoder) {
        do {
            coder.encode(try serializedData())
        } catch {
            owsFailDebug("Failed to encode serialized data \(error)")
        }
    }

    @objc
    public override var debugDescription: String {
        return "\(proto)"
    }
}

extension SSKProtoSyncMessageSentStoryMessageRecipient {
    @objc
    public static func builder() -> SSKProtoSyncMessageSentStoryMessageRecipientBuilder {
        return SSKProtoSyncMessageSentStoryMessageRecipientBuilder()
    }

    // asBuilder() constructs a builder that reflects the proto's contents.
    @objc
    public func asBuilder() -> SSKProtoSyncMessageSentStoryMessageRecipientBuilder {
        let builder = SSKProtoSyncMessageSentStoryMessageRecipientBuilder()
        if let _value = destinationServiceID {
            builder.setDestinationServiceID(_value)
        }
        builder.setDistributionListIds(distributionListIds)
        if hasIsAllowedToReply {
            builder.setIsAllowedToReply(isAllowedToReply)
        }
        if let _value = unknownFields {
            builder.setUnknownFields(_value)
        }
        return builder
    }
}

@objc
public class SSKProtoSyncMessageSentStoryMessageRecipientBuilder: NSObject {

    private var proto = SignalServiceProtos_SyncMessage.Sent.StoryMessageRecipient()

    @objc
    fileprivate override init() {}

    @objc
    @available(swift, obsoleted: 1.0)
    public func setDestinationServiceID(_ valueParam: String?) {
        guard let valueParam = valueParam else { return }
        proto.destinationServiceID = valueParam
    }

    public func setDestinationServiceID(_ valueParam: String) {
        proto.destinationServiceID = valueParam
    }

    @objc
    public func addDistributionListIds(_ valueParam: String) {
        proto.distributionListIds.append(valueParam)
    }

    @objc
    public func setDistributionListIds(_ wrappedItems: [String]) {
        proto.distributionListIds = wrappedItems
    }

    @objc
    public func setIsAllowedToReply(_ valueParam: Bool) {
        proto.isAllowedToReply = valueParam
    }

    public func setUnknownFields(_ unknownFields: SwiftProtobuf.UnknownStorage) {
        proto.unknownFields = unknownFields
    }

    @objc
    public func build() throws -> SSKProtoSyncMessageSentStoryMessageRecipient {
        return SSKProtoSyncMessageSentStoryMessageRecipient(proto)
    }

    @objc
    public func buildInfallibly() -> SSKProtoSyncMessageSentStoryMessageRecipient {
        return SSKProtoSyncMessageSentStoryMessageRecipient(proto)
    }

    @objc
    public func buildSerializedData() throws -> Data {
        return try SSKProtoSyncMessageSentStoryMessageRecipient(proto).serializedData()
    }
}

#if TESTABLE_BUILD

extension SSKProtoSyncMessageSentStoryMessageRecipient {
    @objc
    public func serializedDataIgnoringErrors() -> Data? {
        return try! self.serializedData()
    }
}

extension SSKProtoSyncMessageSentStoryMessageRecipientBuilder {
    @objc
    public func buildIgnoringErrors() -> SSKProtoSyncMessageSentStoryMessageRecipient? {
        return self.buildInfallibly()
    }
}

#endif

// MARK: - SSKProtoSyncMessageSent

@objc
public class SSKProtoSyncMessageSent: NSObject, Codable, NSSecureCoding {

    fileprivate let proto: SignalServiceProtos_SyncMessage.Sent

    @objc
    public let message: SSKProtoDataMessage?

    @objc
    public let unidentifiedStatus: [SSKProtoSyncMessageSentUnidentifiedDeliveryStatus]

    @objc
    public let storyMessage: SSKProtoStoryMessage?

    @objc
    public let storyMessageRecipients: [SSKProtoSyncMessageSentStoryMessageRecipient]

    @objc
    public let editMessage: SSKProtoEditMessage?

    @objc
    public var destinationE164: String? {
        guard hasDestinationE164 else {
            return nil
        }
        return proto.destinationE164
    }
    @objc
    public var hasDestinationE164: Bool {
        return proto.hasDestinationE164 && !proto.destinationE164.isEmpty
    }

    @objc
    public var destinationServiceID: String? {
        guard hasDestinationServiceID else {
            return nil
        }
        return proto.destinationServiceID
    }
    @objc
    public var hasDestinationServiceID: Bool {
        return proto.hasDestinationServiceID
    }

    @objc
    public var timestamp: UInt64 {
        return proto.timestamp
    }
    @objc
    public var hasTimestamp: Bool {
        return proto.hasTimestamp
    }

    @objc
    public var expirationStartTimestamp: UInt64 {
        return proto.expirationStartTimestamp
    }
    @objc
    public var hasExpirationStartTimestamp: Bool {
        return proto.hasExpirationStartTimestamp
    }

    @objc
    public var isRecipientUpdate: Bool {
        return proto.isRecipientUpdate
    }
    @objc
    public var hasIsRecipientUpdate: Bool {
        return proto.hasIsRecipientUpdate
    }

    public var hasUnknownFields: Bool {
        return !proto.unknownFields.data.isEmpty
    }
    public var unknownFields: SwiftProtobuf.UnknownStorage? {
        guard hasUnknownFields else { return nil }
        return proto.unknownFields
    }

    private init(proto: SignalServiceProtos_SyncMessage.Sent,
                 message: SSKProtoDataMessage?,
                 unidentifiedStatus: [SSKProtoSyncMessageSentUnidentifiedDeliveryStatus],
                 storyMessage: SSKProtoStoryMessage?,
                 storyMessageRecipients: [SSKProtoSyncMessageSentStoryMessageRecipient],
                 editMessage: SSKProtoEditMessage?) {
        self.proto = proto
        self.message = message
        self.unidentifiedStatus = unidentifiedStatus
        self.storyMessage = storyMessage
        self.storyMessageRecipients = storyMessageRecipients
        self.editMessage = editMessage
    }

    @objc
    public func serializedData() throws -> Data {
        return try self.proto.serializedData()
    }

    @objc
    public convenience init(serializedData: Data) throws {
        let proto = try SignalServiceProtos_SyncMessage.Sent(serializedData: serializedData)
        try self.init(proto)
    }

    fileprivate convenience init(_ proto: SignalServiceProtos_SyncMessage.Sent) throws {
        var message: SSKProtoDataMessage?
        if proto.hasMessage {
            message = try SSKProtoDataMessage(proto.message)
        }

        var unidentifiedStatus: [SSKProtoSyncMessageSentUnidentifiedDeliveryStatus] = []
        unidentifiedStatus = proto.unidentifiedStatus.map { SSKProtoSyncMessageSentUnidentifiedDeliveryStatus($0) }

        var storyMessage: SSKProtoStoryMessage?
        if proto.hasStoryMessage {
            storyMessage = try SSKProtoStoryMessage(proto.storyMessage)
        }

        var storyMessageRecipients: [SSKProtoSyncMessageSentStoryMessageRecipient] = []
        storyMessageRecipients = proto.storyMessageRecipients.map { SSKProtoSyncMessageSentStoryMessageRecipient($0) }

        var editMessage: SSKProtoEditMessage?
        if proto.hasEditMessage {
            editMessage = try SSKProtoEditMessage(proto.editMessage)
        }

        self.init(proto: proto,
                  message: message,
                  unidentifiedStatus: unidentifiedStatus,
                  storyMessage: storyMessage,
                  storyMessageRecipients: storyMessageRecipients,
                  editMessage: editMessage)
    }

    public required convenience init(from decoder: Swift.Decoder) throws {
        let singleValueContainer = try decoder.singleValueContainer()
        let serializedData = try singleValueContainer.decode(Data.self)
        try self.init(serializedData: serializedData)
    }
    public func encode(to encoder: Swift.Encoder) throws {
        var singleValueContainer = encoder.singleValueContainer()
        try singleValueContainer.encode(try serializedData())
    }

    public static var supportsSecureCoding: Bool { true }

    public required convenience init?(coder: NSCoder) {
        guard let serializedData = coder.decodeData() else { return nil }
        do {
            try self.init(serializedData: serializedData)
        } catch {
            owsFailDebug("Failed to decode serialized data \(error)")
            return nil
        }
    }

    public func encode(with coder: NSCoder) {
        do {
            coder.encode(try serializedData())
        } catch {
            owsFailDebug("Failed to encode serialized data \(error)")
        }
    }

    @objc
    public override var debugDescription: String {
        return "\(proto)"
    }
}

extension SSKProtoSyncMessageSent {
    @objc
    public static func builder() -> SSKProtoSyncMessageSentBuilder {
        return SSKProtoSyncMessageSentBuilder()
    }

    // asBuilder() constructs a builder that reflects the proto's contents.
    @objc
    public func asBuilder() -> SSKProtoSyncMessageSentBuilder {
        let builder = SSKProtoSyncMessageSentBuilder()
        if let _value = destinationE164 {
            builder.setDestinationE164(_value)
        }
        if let _value = destinationServiceID {
            builder.setDestinationServiceID(_value)
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
        if let _value = storyMessage {
            builder.setStoryMessage(_value)
        }
        builder.setStoryMessageRecipients(storyMessageRecipients)
        if let _value = editMessage {
            builder.setEditMessage(_value)
        }
        if let _value = unknownFields {
            builder.setUnknownFields(_value)
        }
        return builder
    }
}

@objc
public class SSKProtoSyncMessageSentBuilder: NSObject {

    private var proto = SignalServiceProtos_SyncMessage.Sent()

    @objc
    fileprivate override init() {}

    @objc
    @available(swift, obsoleted: 1.0)
    public func setDestinationE164(_ valueParam: String?) {
        guard let valueParam = valueParam else { return }
        if let valueParam = valueParam.nilIfEmpty {
            owsAssertDebug(valueParam.isStructurallyValidE164)
        }

        proto.destinationE164 = valueParam
    }

    public func setDestinationE164(_ valueParam: String) {
        if let valueParam = valueParam.nilIfEmpty {
            owsAssertDebug(valueParam.isStructurallyValidE164)
        }

        proto.destinationE164 = valueParam
    }

    @objc
    @available(swift, obsoleted: 1.0)
    public func setDestinationServiceID(_ valueParam: String?) {
        guard let valueParam = valueParam else { return }
        proto.destinationServiceID = valueParam
    }

    public func setDestinationServiceID(_ valueParam: String) {
        proto.destinationServiceID = valueParam
    }

    @objc
    public func setTimestamp(_ valueParam: UInt64) {
        proto.timestamp = valueParam
    }

    @objc
    @available(swift, obsoleted: 1.0)
    public func setMessage(_ valueParam: SSKProtoDataMessage?) {
        guard let valueParam = valueParam else { return }
        proto.message = valueParam.proto
    }

    public func setMessage(_ valueParam: SSKProtoDataMessage) {
        proto.message = valueParam.proto
    }

    @objc
    public func setExpirationStartTimestamp(_ valueParam: UInt64) {
        proto.expirationStartTimestamp = valueParam
    }

    @objc
    public func addUnidentifiedStatus(_ valueParam: SSKProtoSyncMessageSentUnidentifiedDeliveryStatus) {
        proto.unidentifiedStatus.append(valueParam.proto)
    }

    @objc
    public func setUnidentifiedStatus(_ wrappedItems: [SSKProtoSyncMessageSentUnidentifiedDeliveryStatus]) {
        proto.unidentifiedStatus = wrappedItems.map { $0.proto }
    }

    @objc
    public func setIsRecipientUpdate(_ valueParam: Bool) {
        proto.isRecipientUpdate = valueParam
    }

    @objc
    @available(swift, obsoleted: 1.0)
    public func setStoryMessage(_ valueParam: SSKProtoStoryMessage?) {
        guard let valueParam = valueParam else { return }
        proto.storyMessage = valueParam.proto
    }

    public func setStoryMessage(_ valueParam: SSKProtoStoryMessage) {
        proto.storyMessage = valueParam.proto
    }

    @objc
    public func addStoryMessageRecipients(_ valueParam: SSKProtoSyncMessageSentStoryMessageRecipient) {
        proto.storyMessageRecipients.append(valueParam.proto)
    }

    @objc
    public func setStoryMessageRecipients(_ wrappedItems: [SSKProtoSyncMessageSentStoryMessageRecipient]) {
        proto.storyMessageRecipients = wrappedItems.map { $0.proto }
    }

    @objc
    @available(swift, obsoleted: 1.0)
    public func setEditMessage(_ valueParam: SSKProtoEditMessage?) {
        guard let valueParam = valueParam else { return }
        proto.editMessage = valueParam.proto
    }

    public func setEditMessage(_ valueParam: SSKProtoEditMessage) {
        proto.editMessage = valueParam.proto
    }

    public func setUnknownFields(_ unknownFields: SwiftProtobuf.UnknownStorage) {
        proto.unknownFields = unknownFields
    }

    @objc
    public func build() throws -> SSKProtoSyncMessageSent {
        return try SSKProtoSyncMessageSent(proto)
    }

    @objc
    public func buildSerializedData() throws -> Data {
        return try SSKProtoSyncMessageSent(proto).serializedData()
    }
}

#if TESTABLE_BUILD

extension SSKProtoSyncMessageSent {
    @objc
    public func serializedDataIgnoringErrors() -> Data? {
        return try! self.serializedData()
    }
}

extension SSKProtoSyncMessageSentBuilder {
    @objc
    public func buildIgnoringErrors() -> SSKProtoSyncMessageSent? {
        return try! self.build()
    }
}

#endif

// MARK: - SSKProtoSyncMessageContacts

@objc
public class SSKProtoSyncMessageContacts: NSObject, Codable, NSSecureCoding {

    fileprivate let proto: SignalServiceProtos_SyncMessage.Contacts

    @objc
    public let blob: SSKProtoAttachmentPointer

    @objc
    public var isComplete: Bool {
        return proto.isComplete
    }
    @objc
    public var hasIsComplete: Bool {
        return proto.hasIsComplete
    }

    public var hasUnknownFields: Bool {
        return !proto.unknownFields.data.isEmpty
    }
    public var unknownFields: SwiftProtobuf.UnknownStorage? {
        guard hasUnknownFields else { return nil }
        return proto.unknownFields
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

    @objc
    public convenience init(serializedData: Data) throws {
        let proto = try SignalServiceProtos_SyncMessage.Contacts(serializedData: serializedData)
        try self.init(proto)
    }

    fileprivate convenience init(_ proto: SignalServiceProtos_SyncMessage.Contacts) throws {
        guard proto.hasBlob else {
            throw SSKProtoError.invalidProtobuf(description: "\(Self.logTag()) missing required field: blob")
        }
        let blob = SSKProtoAttachmentPointer(proto.blob)

        self.init(proto: proto,
                  blob: blob)
    }

    public required convenience init(from decoder: Swift.Decoder) throws {
        let singleValueContainer = try decoder.singleValueContainer()
        let serializedData = try singleValueContainer.decode(Data.self)
        try self.init(serializedData: serializedData)
    }
    public func encode(to encoder: Swift.Encoder) throws {
        var singleValueContainer = encoder.singleValueContainer()
        try singleValueContainer.encode(try serializedData())
    }

    public static var supportsSecureCoding: Bool { true }

    public required convenience init?(coder: NSCoder) {
        guard let serializedData = coder.decodeData() else { return nil }
        do {
            try self.init(serializedData: serializedData)
        } catch {
            owsFailDebug("Failed to decode serialized data \(error)")
            return nil
        }
    }

    public func encode(with coder: NSCoder) {
        do {
            coder.encode(try serializedData())
        } catch {
            owsFailDebug("Failed to encode serialized data \(error)")
        }
    }

    @objc
    public override var debugDescription: String {
        return "\(proto)"
    }
}

extension SSKProtoSyncMessageContacts {
    @objc
    public static func builder(blob: SSKProtoAttachmentPointer) -> SSKProtoSyncMessageContactsBuilder {
        return SSKProtoSyncMessageContactsBuilder(blob: blob)
    }

    // asBuilder() constructs a builder that reflects the proto's contents.
    @objc
    public func asBuilder() -> SSKProtoSyncMessageContactsBuilder {
        let builder = SSKProtoSyncMessageContactsBuilder(blob: blob)
        if hasIsComplete {
            builder.setIsComplete(isComplete)
        }
        if let _value = unknownFields {
            builder.setUnknownFields(_value)
        }
        return builder
    }
}

@objc
public class SSKProtoSyncMessageContactsBuilder: NSObject {

    private var proto = SignalServiceProtos_SyncMessage.Contacts()

    @objc
    fileprivate override init() {}

    @objc
    fileprivate init(blob: SSKProtoAttachmentPointer) {
        super.init()

        setBlob(blob)
    }

    @objc
    @available(swift, obsoleted: 1.0)
    public func setBlob(_ valueParam: SSKProtoAttachmentPointer?) {
        guard let valueParam = valueParam else { return }
        proto.blob = valueParam.proto
    }

    public func setBlob(_ valueParam: SSKProtoAttachmentPointer) {
        proto.blob = valueParam.proto
    }

    @objc
    public func setIsComplete(_ valueParam: Bool) {
        proto.isComplete = valueParam
    }

    public func setUnknownFields(_ unknownFields: SwiftProtobuf.UnknownStorage) {
        proto.unknownFields = unknownFields
    }

    @objc
    public func build() throws -> SSKProtoSyncMessageContacts {
        return try SSKProtoSyncMessageContacts(proto)
    }

    @objc
    public func buildSerializedData() throws -> Data {
        return try SSKProtoSyncMessageContacts(proto).serializedData()
    }
}

#if TESTABLE_BUILD

extension SSKProtoSyncMessageContacts {
    @objc
    public func serializedDataIgnoringErrors() -> Data? {
        return try! self.serializedData()
    }
}

extension SSKProtoSyncMessageContactsBuilder {
    @objc
    public func buildIgnoringErrors() -> SSKProtoSyncMessageContacts? {
        return try! self.build()
    }
}

#endif

// MARK: - SSKProtoSyncMessageBlocked

@objc
public class SSKProtoSyncMessageBlocked: NSObject, Codable, NSSecureCoding {

    fileprivate let proto: SignalServiceProtos_SyncMessage.Blocked

    @objc
    public var numbers: [String] {
        return proto.numbers
    }

    @objc
    public var acis: [String] {
        return proto.acis
    }

    @objc
    public var groupIds: [Data] {
        return proto.groupIds
    }

    public var hasUnknownFields: Bool {
        return !proto.unknownFields.data.isEmpty
    }
    public var unknownFields: SwiftProtobuf.UnknownStorage? {
        guard hasUnknownFields else { return nil }
        return proto.unknownFields
    }

    private init(proto: SignalServiceProtos_SyncMessage.Blocked) {
        self.proto = proto
    }

    @objc
    public func serializedData() throws -> Data {
        return try self.proto.serializedData()
    }

    @objc
    public convenience init(serializedData: Data) throws {
        let proto = try SignalServiceProtos_SyncMessage.Blocked(serializedData: serializedData)
        self.init(proto)
    }

    fileprivate convenience init(_ proto: SignalServiceProtos_SyncMessage.Blocked) {
        self.init(proto: proto)
    }

    public required convenience init(from decoder: Swift.Decoder) throws {
        let singleValueContainer = try decoder.singleValueContainer()
        let serializedData = try singleValueContainer.decode(Data.self)
        try self.init(serializedData: serializedData)
    }
    public func encode(to encoder: Swift.Encoder) throws {
        var singleValueContainer = encoder.singleValueContainer()
        try singleValueContainer.encode(try serializedData())
    }

    public static var supportsSecureCoding: Bool { true }

    public required convenience init?(coder: NSCoder) {
        guard let serializedData = coder.decodeData() else { return nil }
        do {
            try self.init(serializedData: serializedData)
        } catch {
            owsFailDebug("Failed to decode serialized data \(error)")
            return nil
        }
    }

    public func encode(with coder: NSCoder) {
        do {
            coder.encode(try serializedData())
        } catch {
            owsFailDebug("Failed to encode serialized data \(error)")
        }
    }

    @objc
    public override var debugDescription: String {
        return "\(proto)"
    }
}

extension SSKProtoSyncMessageBlocked {
    @objc
    public static func builder() -> SSKProtoSyncMessageBlockedBuilder {
        return SSKProtoSyncMessageBlockedBuilder()
    }

    // asBuilder() constructs a builder that reflects the proto's contents.
    @objc
    public func asBuilder() -> SSKProtoSyncMessageBlockedBuilder {
        let builder = SSKProtoSyncMessageBlockedBuilder()
        builder.setNumbers(numbers)
        builder.setAcis(acis)
        builder.setGroupIds(groupIds)
        if let _value = unknownFields {
            builder.setUnknownFields(_value)
        }
        return builder
    }
}

@objc
public class SSKProtoSyncMessageBlockedBuilder: NSObject {

    private var proto = SignalServiceProtos_SyncMessage.Blocked()

    @objc
    fileprivate override init() {}

    @objc
    public func addNumbers(_ valueParam: String) {
        proto.numbers.append(valueParam)
    }

    @objc
    public func setNumbers(_ wrappedItems: [String]) {
        proto.numbers = wrappedItems
    }

    @objc
    public func addAcis(_ valueParam: String) {
        proto.acis.append(valueParam)
    }

    @objc
    public func setAcis(_ wrappedItems: [String]) {
        proto.acis = wrappedItems
    }

    @objc
    public func addGroupIds(_ valueParam: Data) {
        proto.groupIds.append(valueParam)
    }

    @objc
    public func setGroupIds(_ wrappedItems: [Data]) {
        proto.groupIds = wrappedItems
    }

    public func setUnknownFields(_ unknownFields: SwiftProtobuf.UnknownStorage) {
        proto.unknownFields = unknownFields
    }

    @objc
    public func build() throws -> SSKProtoSyncMessageBlocked {
        return SSKProtoSyncMessageBlocked(proto)
    }

    @objc
    public func buildInfallibly() -> SSKProtoSyncMessageBlocked {
        return SSKProtoSyncMessageBlocked(proto)
    }

    @objc
    public func buildSerializedData() throws -> Data {
        return try SSKProtoSyncMessageBlocked(proto).serializedData()
    }
}

#if TESTABLE_BUILD

extension SSKProtoSyncMessageBlocked {
    @objc
    public func serializedDataIgnoringErrors() -> Data? {
        return try! self.serializedData()
    }
}

extension SSKProtoSyncMessageBlockedBuilder {
    @objc
    public func buildIgnoringErrors() -> SSKProtoSyncMessageBlocked? {
        return self.buildInfallibly()
    }
}

#endif

// MARK: - SSKProtoSyncMessageRequestType

@objc
public enum SSKProtoSyncMessageRequestType: Int32 {
    case unknown = 0
    case contacts = 1
    case blocked = 3
    case configuration = 4
    case keys = 5
}

private func SSKProtoSyncMessageRequestTypeWrap(_ value: SignalServiceProtos_SyncMessage.Request.TypeEnum) -> SSKProtoSyncMessageRequestType {
    switch value {
    case .unknown: return .unknown
    case .contacts: return .contacts
    case .blocked: return .blocked
    case .configuration: return .configuration
    case .keys: return .keys
    }
}

private func SSKProtoSyncMessageRequestTypeUnwrap(_ value: SSKProtoSyncMessageRequestType) -> SignalServiceProtos_SyncMessage.Request.TypeEnum {
    switch value {
    case .unknown: return .unknown
    case .contacts: return .contacts
    case .blocked: return .blocked
    case .configuration: return .configuration
    case .keys: return .keys
    }
}

// MARK: - SSKProtoSyncMessageRequest

@objc
public class SSKProtoSyncMessageRequest: NSObject, Codable, NSSecureCoding {

    fileprivate let proto: SignalServiceProtos_SyncMessage.Request

    public var type: SSKProtoSyncMessageRequestType? {
        guard hasType else {
            return nil
        }
        return SSKProtoSyncMessageRequestTypeWrap(proto.type)
    }
    // This "unwrapped" accessor should only be used if the "has value" accessor has already been checked.
    @objc
    public var unwrappedType: SSKProtoSyncMessageRequestType {
        if !hasType {
            // TODO: We could make this a crashing assert.
            owsFailDebug("Unsafe unwrap of missing optional: Request.type.")
        }
        return SSKProtoSyncMessageRequestTypeWrap(proto.type)
    }
    @objc
    public var hasType: Bool {
        return proto.hasType
    }

    public var hasUnknownFields: Bool {
        return !proto.unknownFields.data.isEmpty
    }
    public var unknownFields: SwiftProtobuf.UnknownStorage? {
        guard hasUnknownFields else { return nil }
        return proto.unknownFields
    }

    private init(proto: SignalServiceProtos_SyncMessage.Request) {
        self.proto = proto
    }

    @objc
    public func serializedData() throws -> Data {
        return try self.proto.serializedData()
    }

    @objc
    public convenience init(serializedData: Data) throws {
        let proto = try SignalServiceProtos_SyncMessage.Request(serializedData: serializedData)
        self.init(proto)
    }

    fileprivate convenience init(_ proto: SignalServiceProtos_SyncMessage.Request) {
        self.init(proto: proto)
    }

    public required convenience init(from decoder: Swift.Decoder) throws {
        let singleValueContainer = try decoder.singleValueContainer()
        let serializedData = try singleValueContainer.decode(Data.self)
        try self.init(serializedData: serializedData)
    }
    public func encode(to encoder: Swift.Encoder) throws {
        var singleValueContainer = encoder.singleValueContainer()
        try singleValueContainer.encode(try serializedData())
    }

    public static var supportsSecureCoding: Bool { true }

    public required convenience init?(coder: NSCoder) {
        guard let serializedData = coder.decodeData() else { return nil }
        do {
            try self.init(serializedData: serializedData)
        } catch {
            owsFailDebug("Failed to decode serialized data \(error)")
            return nil
        }
    }

    public func encode(with coder: NSCoder) {
        do {
            coder.encode(try serializedData())
        } catch {
            owsFailDebug("Failed to encode serialized data \(error)")
        }
    }

    @objc
    public override var debugDescription: String {
        return "\(proto)"
    }
}

extension SSKProtoSyncMessageRequest {
    @objc
    public static func builder() -> SSKProtoSyncMessageRequestBuilder {
        return SSKProtoSyncMessageRequestBuilder()
    }

    // asBuilder() constructs a builder that reflects the proto's contents.
    @objc
    public func asBuilder() -> SSKProtoSyncMessageRequestBuilder {
        let builder = SSKProtoSyncMessageRequestBuilder()
        if let _value = type {
            builder.setType(_value)
        }
        if let _value = unknownFields {
            builder.setUnknownFields(_value)
        }
        return builder
    }
}

@objc
public class SSKProtoSyncMessageRequestBuilder: NSObject {

    private var proto = SignalServiceProtos_SyncMessage.Request()

    @objc
    fileprivate override init() {}

    @objc
    public func setType(_ valueParam: SSKProtoSyncMessageRequestType) {
        proto.type = SSKProtoSyncMessageRequestTypeUnwrap(valueParam)
    }

    public func setUnknownFields(_ unknownFields: SwiftProtobuf.UnknownStorage) {
        proto.unknownFields = unknownFields
    }

    @objc
    public func build() throws -> SSKProtoSyncMessageRequest {
        return SSKProtoSyncMessageRequest(proto)
    }

    @objc
    public func buildInfallibly() -> SSKProtoSyncMessageRequest {
        return SSKProtoSyncMessageRequest(proto)
    }

    @objc
    public func buildSerializedData() throws -> Data {
        return try SSKProtoSyncMessageRequest(proto).serializedData()
    }
}

#if TESTABLE_BUILD

extension SSKProtoSyncMessageRequest {
    @objc
    public func serializedDataIgnoringErrors() -> Data? {
        return try! self.serializedData()
    }
}

extension SSKProtoSyncMessageRequestBuilder {
    @objc
    public func buildIgnoringErrors() -> SSKProtoSyncMessageRequest? {
        return self.buildInfallibly()
    }
}

#endif

// MARK: - SSKProtoSyncMessageRead

@objc
public class SSKProtoSyncMessageRead: NSObject, Codable, NSSecureCoding {

    fileprivate let proto: SignalServiceProtos_SyncMessage.Read

    @objc
    public let timestamp: UInt64

    @objc
    public var senderAci: String? {
        guard hasSenderAci else {
            return nil
        }
        return proto.senderAci
    }
    @objc
    public var hasSenderAci: Bool {
        return proto.hasSenderAci
    }

    public var hasUnknownFields: Bool {
        return !proto.unknownFields.data.isEmpty
    }
    public var unknownFields: SwiftProtobuf.UnknownStorage? {
        guard hasUnknownFields else { return nil }
        return proto.unknownFields
    }

    private init(proto: SignalServiceProtos_SyncMessage.Read,
                 timestamp: UInt64) {
        self.proto = proto
        self.timestamp = timestamp
    }

    @objc
    public func serializedData() throws -> Data {
        return try self.proto.serializedData()
    }

    @objc
    public convenience init(serializedData: Data) throws {
        let proto = try SignalServiceProtos_SyncMessage.Read(serializedData: serializedData)
        try self.init(proto)
    }

    fileprivate convenience init(_ proto: SignalServiceProtos_SyncMessage.Read) throws {
        guard proto.hasTimestamp else {
            throw SSKProtoError.invalidProtobuf(description: "\(Self.logTag()) missing required field: timestamp")
        }
        let timestamp = proto.timestamp

        self.init(proto: proto,
                  timestamp: timestamp)
    }

    public required convenience init(from decoder: Swift.Decoder) throws {
        let singleValueContainer = try decoder.singleValueContainer()
        let serializedData = try singleValueContainer.decode(Data.self)
        try self.init(serializedData: serializedData)
    }
    public func encode(to encoder: Swift.Encoder) throws {
        var singleValueContainer = encoder.singleValueContainer()
        try singleValueContainer.encode(try serializedData())
    }

    public static var supportsSecureCoding: Bool { true }

    public required convenience init?(coder: NSCoder) {
        guard let serializedData = coder.decodeData() else { return nil }
        do {
            try self.init(serializedData: serializedData)
        } catch {
            owsFailDebug("Failed to decode serialized data \(error)")
            return nil
        }
    }

    public func encode(with coder: NSCoder) {
        do {
            coder.encode(try serializedData())
        } catch {
            owsFailDebug("Failed to encode serialized data \(error)")
        }
    }

    @objc
    public override var debugDescription: String {
        return "\(proto)"
    }
}

extension SSKProtoSyncMessageRead {
    @objc
    public static func builder(timestamp: UInt64) -> SSKProtoSyncMessageReadBuilder {
        return SSKProtoSyncMessageReadBuilder(timestamp: timestamp)
    }

    // asBuilder() constructs a builder that reflects the proto's contents.
    @objc
    public func asBuilder() -> SSKProtoSyncMessageReadBuilder {
        let builder = SSKProtoSyncMessageReadBuilder(timestamp: timestamp)
        if let _value = senderAci {
            builder.setSenderAci(_value)
        }
        if let _value = unknownFields {
            builder.setUnknownFields(_value)
        }
        return builder
    }
}

@objc
public class SSKProtoSyncMessageReadBuilder: NSObject {

    private var proto = SignalServiceProtos_SyncMessage.Read()

    @objc
    fileprivate override init() {}

    @objc
    fileprivate init(timestamp: UInt64) {
        super.init()

        setTimestamp(timestamp)
    }

    @objc
    @available(swift, obsoleted: 1.0)
    public func setSenderAci(_ valueParam: String?) {
        guard let valueParam = valueParam else { return }
        proto.senderAci = valueParam
    }

    public func setSenderAci(_ valueParam: String) {
        proto.senderAci = valueParam
    }

    @objc
    public func setTimestamp(_ valueParam: UInt64) {
        proto.timestamp = valueParam
    }

    public func setUnknownFields(_ unknownFields: SwiftProtobuf.UnknownStorage) {
        proto.unknownFields = unknownFields
    }

    @objc
    public func build() throws -> SSKProtoSyncMessageRead {
        return try SSKProtoSyncMessageRead(proto)
    }

    @objc
    public func buildSerializedData() throws -> Data {
        return try SSKProtoSyncMessageRead(proto).serializedData()
    }
}

#if TESTABLE_BUILD

extension SSKProtoSyncMessageRead {
    @objc
    public func serializedDataIgnoringErrors() -> Data? {
        return try! self.serializedData()
    }
}

extension SSKProtoSyncMessageReadBuilder {
    @objc
    public func buildIgnoringErrors() -> SSKProtoSyncMessageRead? {
        return try! self.build()
    }
}

#endif

// MARK: - SSKProtoSyncMessageViewed

@objc
public class SSKProtoSyncMessageViewed: NSObject, Codable, NSSecureCoding {

    fileprivate let proto: SignalServiceProtos_SyncMessage.Viewed

    @objc
    public let timestamp: UInt64

    @objc
    public var senderAci: String? {
        guard hasSenderAci else {
            return nil
        }
        return proto.senderAci
    }
    @objc
    public var hasSenderAci: Bool {
        return proto.hasSenderAci
    }

    public var hasUnknownFields: Bool {
        return !proto.unknownFields.data.isEmpty
    }
    public var unknownFields: SwiftProtobuf.UnknownStorage? {
        guard hasUnknownFields else { return nil }
        return proto.unknownFields
    }

    private init(proto: SignalServiceProtos_SyncMessage.Viewed,
                 timestamp: UInt64) {
        self.proto = proto
        self.timestamp = timestamp
    }

    @objc
    public func serializedData() throws -> Data {
        return try self.proto.serializedData()
    }

    @objc
    public convenience init(serializedData: Data) throws {
        let proto = try SignalServiceProtos_SyncMessage.Viewed(serializedData: serializedData)
        try self.init(proto)
    }

    fileprivate convenience init(_ proto: SignalServiceProtos_SyncMessage.Viewed) throws {
        guard proto.hasTimestamp else {
            throw SSKProtoError.invalidProtobuf(description: "\(Self.logTag()) missing required field: timestamp")
        }
        let timestamp = proto.timestamp

        self.init(proto: proto,
                  timestamp: timestamp)
    }

    public required convenience init(from decoder: Swift.Decoder) throws {
        let singleValueContainer = try decoder.singleValueContainer()
        let serializedData = try singleValueContainer.decode(Data.self)
        try self.init(serializedData: serializedData)
    }
    public func encode(to encoder: Swift.Encoder) throws {
        var singleValueContainer = encoder.singleValueContainer()
        try singleValueContainer.encode(try serializedData())
    }

    public static var supportsSecureCoding: Bool { true }

    public required convenience init?(coder: NSCoder) {
        guard let serializedData = coder.decodeData() else { return nil }
        do {
            try self.init(serializedData: serializedData)
        } catch {
            owsFailDebug("Failed to decode serialized data \(error)")
            return nil
        }
    }

    public func encode(with coder: NSCoder) {
        do {
            coder.encode(try serializedData())
        } catch {
            owsFailDebug("Failed to encode serialized data \(error)")
        }
    }

    @objc
    public override var debugDescription: String {
        return "\(proto)"
    }
}

extension SSKProtoSyncMessageViewed {
    @objc
    public static func builder(timestamp: UInt64) -> SSKProtoSyncMessageViewedBuilder {
        return SSKProtoSyncMessageViewedBuilder(timestamp: timestamp)
    }

    // asBuilder() constructs a builder that reflects the proto's contents.
    @objc
    public func asBuilder() -> SSKProtoSyncMessageViewedBuilder {
        let builder = SSKProtoSyncMessageViewedBuilder(timestamp: timestamp)
        if let _value = senderAci {
            builder.setSenderAci(_value)
        }
        if let _value = unknownFields {
            builder.setUnknownFields(_value)
        }
        return builder
    }
}

@objc
public class SSKProtoSyncMessageViewedBuilder: NSObject {

    private var proto = SignalServiceProtos_SyncMessage.Viewed()

    @objc
    fileprivate override init() {}

    @objc
    fileprivate init(timestamp: UInt64) {
        super.init()

        setTimestamp(timestamp)
    }

    @objc
    @available(swift, obsoleted: 1.0)
    public func setSenderAci(_ valueParam: String?) {
        guard let valueParam = valueParam else { return }
        proto.senderAci = valueParam
    }

    public func setSenderAci(_ valueParam: String) {
        proto.senderAci = valueParam
    }

    @objc
    public func setTimestamp(_ valueParam: UInt64) {
        proto.timestamp = valueParam
    }

    public func setUnknownFields(_ unknownFields: SwiftProtobuf.UnknownStorage) {
        proto.unknownFields = unknownFields
    }

    @objc
    public func build() throws -> SSKProtoSyncMessageViewed {
        return try SSKProtoSyncMessageViewed(proto)
    }

    @objc
    public func buildSerializedData() throws -> Data {
        return try SSKProtoSyncMessageViewed(proto).serializedData()
    }
}

#if TESTABLE_BUILD

extension SSKProtoSyncMessageViewed {
    @objc
    public func serializedDataIgnoringErrors() -> Data? {
        return try! self.serializedData()
    }
}

extension SSKProtoSyncMessageViewedBuilder {
    @objc
    public func buildIgnoringErrors() -> SSKProtoSyncMessageViewed? {
        return try! self.build()
    }
}

#endif

// MARK: - SSKProtoSyncMessageConfiguration

@objc
public class SSKProtoSyncMessageConfiguration: NSObject, Codable, NSSecureCoding {

    fileprivate let proto: SignalServiceProtos_SyncMessage.Configuration

    @objc
    public var readReceipts: Bool {
        return proto.readReceipts
    }
    @objc
    public var hasReadReceipts: Bool {
        return proto.hasReadReceipts
    }

    @objc
    public var unidentifiedDeliveryIndicators: Bool {
        return proto.unidentifiedDeliveryIndicators
    }
    @objc
    public var hasUnidentifiedDeliveryIndicators: Bool {
        return proto.hasUnidentifiedDeliveryIndicators
    }

    @objc
    public var typingIndicators: Bool {
        return proto.typingIndicators
    }
    @objc
    public var hasTypingIndicators: Bool {
        return proto.hasTypingIndicators
    }

    @objc
    public var provisioningVersion: UInt32 {
        return proto.provisioningVersion
    }
    @objc
    public var hasProvisioningVersion: Bool {
        return proto.hasProvisioningVersion
    }

    @objc
    public var linkPreviews: Bool {
        return proto.linkPreviews
    }
    @objc
    public var hasLinkPreviews: Bool {
        return proto.hasLinkPreviews
    }

    public var hasUnknownFields: Bool {
        return !proto.unknownFields.data.isEmpty
    }
    public var unknownFields: SwiftProtobuf.UnknownStorage? {
        guard hasUnknownFields else { return nil }
        return proto.unknownFields
    }

    private init(proto: SignalServiceProtos_SyncMessage.Configuration) {
        self.proto = proto
    }

    @objc
    public func serializedData() throws -> Data {
        return try self.proto.serializedData()
    }

    @objc
    public convenience init(serializedData: Data) throws {
        let proto = try SignalServiceProtos_SyncMessage.Configuration(serializedData: serializedData)
        self.init(proto)
    }

    fileprivate convenience init(_ proto: SignalServiceProtos_SyncMessage.Configuration) {
        self.init(proto: proto)
    }

    public required convenience init(from decoder: Swift.Decoder) throws {
        let singleValueContainer = try decoder.singleValueContainer()
        let serializedData = try singleValueContainer.decode(Data.self)
        try self.init(serializedData: serializedData)
    }
    public func encode(to encoder: Swift.Encoder) throws {
        var singleValueContainer = encoder.singleValueContainer()
        try singleValueContainer.encode(try serializedData())
    }

    public static var supportsSecureCoding: Bool { true }

    public required convenience init?(coder: NSCoder) {
        guard let serializedData = coder.decodeData() else { return nil }
        do {
            try self.init(serializedData: serializedData)
        } catch {
            owsFailDebug("Failed to decode serialized data \(error)")
            return nil
        }
    }

    public func encode(with coder: NSCoder) {
        do {
            coder.encode(try serializedData())
        } catch {
            owsFailDebug("Failed to encode serialized data \(error)")
        }
    }

    @objc
    public override var debugDescription: String {
        return "\(proto)"
    }
}

extension SSKProtoSyncMessageConfiguration {
    @objc
    public static func builder() -> SSKProtoSyncMessageConfigurationBuilder {
        return SSKProtoSyncMessageConfigurationBuilder()
    }

    // asBuilder() constructs a builder that reflects the proto's contents.
    @objc
    public func asBuilder() -> SSKProtoSyncMessageConfigurationBuilder {
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
        if hasProvisioningVersion {
            builder.setProvisioningVersion(provisioningVersion)
        }
        if hasLinkPreviews {
            builder.setLinkPreviews(linkPreviews)
        }
        if let _value = unknownFields {
            builder.setUnknownFields(_value)
        }
        return builder
    }
}

@objc
public class SSKProtoSyncMessageConfigurationBuilder: NSObject {

    private var proto = SignalServiceProtos_SyncMessage.Configuration()

    @objc
    fileprivate override init() {}

    @objc
    public func setReadReceipts(_ valueParam: Bool) {
        proto.readReceipts = valueParam
    }

    @objc
    public func setUnidentifiedDeliveryIndicators(_ valueParam: Bool) {
        proto.unidentifiedDeliveryIndicators = valueParam
    }

    @objc
    public func setTypingIndicators(_ valueParam: Bool) {
        proto.typingIndicators = valueParam
    }

    @objc
    public func setProvisioningVersion(_ valueParam: UInt32) {
        proto.provisioningVersion = valueParam
    }

    @objc
    public func setLinkPreviews(_ valueParam: Bool) {
        proto.linkPreviews = valueParam
    }

    public func setUnknownFields(_ unknownFields: SwiftProtobuf.UnknownStorage) {
        proto.unknownFields = unknownFields
    }

    @objc
    public func build() throws -> SSKProtoSyncMessageConfiguration {
        return SSKProtoSyncMessageConfiguration(proto)
    }

    @objc
    public func buildInfallibly() -> SSKProtoSyncMessageConfiguration {
        return SSKProtoSyncMessageConfiguration(proto)
    }

    @objc
    public func buildSerializedData() throws -> Data {
        return try SSKProtoSyncMessageConfiguration(proto).serializedData()
    }
}

#if TESTABLE_BUILD

extension SSKProtoSyncMessageConfiguration {
    @objc
    public func serializedDataIgnoringErrors() -> Data? {
        return try! self.serializedData()
    }
}

extension SSKProtoSyncMessageConfigurationBuilder {
    @objc
    public func buildIgnoringErrors() -> SSKProtoSyncMessageConfiguration? {
        return self.buildInfallibly()
    }
}

#endif

// MARK: - SSKProtoSyncMessageStickerPackOperationType

@objc
public enum SSKProtoSyncMessageStickerPackOperationType: Int32 {
    case install = 0
    case remove = 1
}

private func SSKProtoSyncMessageStickerPackOperationTypeWrap(_ value: SignalServiceProtos_SyncMessage.StickerPackOperation.TypeEnum) -> SSKProtoSyncMessageStickerPackOperationType {
    switch value {
    case .install: return .install
    case .remove: return .remove
    }
}

private func SSKProtoSyncMessageStickerPackOperationTypeUnwrap(_ value: SSKProtoSyncMessageStickerPackOperationType) -> SignalServiceProtos_SyncMessage.StickerPackOperation.TypeEnum {
    switch value {
    case .install: return .install
    case .remove: return .remove
    }
}

// MARK: - SSKProtoSyncMessageStickerPackOperation

@objc
public class SSKProtoSyncMessageStickerPackOperation: NSObject, Codable, NSSecureCoding {

    fileprivate let proto: SignalServiceProtos_SyncMessage.StickerPackOperation

    @objc
    public let packID: Data

    @objc
    public let packKey: Data

    public var type: SSKProtoSyncMessageStickerPackOperationType? {
        guard hasType else {
            return nil
        }
        return SSKProtoSyncMessageStickerPackOperationTypeWrap(proto.type)
    }
    // This "unwrapped" accessor should only be used if the "has value" accessor has already been checked.
    @objc
    public var unwrappedType: SSKProtoSyncMessageStickerPackOperationType {
        if !hasType {
            // TODO: We could make this a crashing assert.
            owsFailDebug("Unsafe unwrap of missing optional: StickerPackOperation.type.")
        }
        return SSKProtoSyncMessageStickerPackOperationTypeWrap(proto.type)
    }
    @objc
    public var hasType: Bool {
        return proto.hasType
    }

    public var hasUnknownFields: Bool {
        return !proto.unknownFields.data.isEmpty
    }
    public var unknownFields: SwiftProtobuf.UnknownStorage? {
        guard hasUnknownFields else { return nil }
        return proto.unknownFields
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

    @objc
    public convenience init(serializedData: Data) throws {
        let proto = try SignalServiceProtos_SyncMessage.StickerPackOperation(serializedData: serializedData)
        try self.init(proto)
    }

    fileprivate convenience init(_ proto: SignalServiceProtos_SyncMessage.StickerPackOperation) throws {
        guard proto.hasPackID else {
            throw SSKProtoError.invalidProtobuf(description: "\(Self.logTag()) missing required field: packID")
        }
        let packID = proto.packID

        guard proto.hasPackKey else {
            throw SSKProtoError.invalidProtobuf(description: "\(Self.logTag()) missing required field: packKey")
        }
        let packKey = proto.packKey

        self.init(proto: proto,
                  packID: packID,
                  packKey: packKey)
    }

    public required convenience init(from decoder: Swift.Decoder) throws {
        let singleValueContainer = try decoder.singleValueContainer()
        let serializedData = try singleValueContainer.decode(Data.self)
        try self.init(serializedData: serializedData)
    }
    public func encode(to encoder: Swift.Encoder) throws {
        var singleValueContainer = encoder.singleValueContainer()
        try singleValueContainer.encode(try serializedData())
    }

    public static var supportsSecureCoding: Bool { true }

    public required convenience init?(coder: NSCoder) {
        guard let serializedData = coder.decodeData() else { return nil }
        do {
            try self.init(serializedData: serializedData)
        } catch {
            owsFailDebug("Failed to decode serialized data \(error)")
            return nil
        }
    }

    public func encode(with coder: NSCoder) {
        do {
            coder.encode(try serializedData())
        } catch {
            owsFailDebug("Failed to encode serialized data \(error)")
        }
    }

    @objc
    public override var debugDescription: String {
        return "\(proto)"
    }
}

extension SSKProtoSyncMessageStickerPackOperation {
    @objc
    public static func builder(packID: Data, packKey: Data) -> SSKProtoSyncMessageStickerPackOperationBuilder {
        return SSKProtoSyncMessageStickerPackOperationBuilder(packID: packID, packKey: packKey)
    }

    // asBuilder() constructs a builder that reflects the proto's contents.
    @objc
    public func asBuilder() -> SSKProtoSyncMessageStickerPackOperationBuilder {
        let builder = SSKProtoSyncMessageStickerPackOperationBuilder(packID: packID, packKey: packKey)
        if let _value = type {
            builder.setType(_value)
        }
        if let _value = unknownFields {
            builder.setUnknownFields(_value)
        }
        return builder
    }
}

@objc
public class SSKProtoSyncMessageStickerPackOperationBuilder: NSObject {

    private var proto = SignalServiceProtos_SyncMessage.StickerPackOperation()

    @objc
    fileprivate override init() {}

    @objc
    fileprivate init(packID: Data, packKey: Data) {
        super.init()

        setPackID(packID)
        setPackKey(packKey)
    }

    @objc
    @available(swift, obsoleted: 1.0)
    public func setPackID(_ valueParam: Data?) {
        guard let valueParam = valueParam else { return }
        proto.packID = valueParam
    }

    public func setPackID(_ valueParam: Data) {
        proto.packID = valueParam
    }

    @objc
    @available(swift, obsoleted: 1.0)
    public func setPackKey(_ valueParam: Data?) {
        guard let valueParam = valueParam else { return }
        proto.packKey = valueParam
    }

    public func setPackKey(_ valueParam: Data) {
        proto.packKey = valueParam
    }

    @objc
    public func setType(_ valueParam: SSKProtoSyncMessageStickerPackOperationType) {
        proto.type = SSKProtoSyncMessageStickerPackOperationTypeUnwrap(valueParam)
    }

    public func setUnknownFields(_ unknownFields: SwiftProtobuf.UnknownStorage) {
        proto.unknownFields = unknownFields
    }

    @objc
    public func build() throws -> SSKProtoSyncMessageStickerPackOperation {
        return try SSKProtoSyncMessageStickerPackOperation(proto)
    }

    @objc
    public func buildSerializedData() throws -> Data {
        return try SSKProtoSyncMessageStickerPackOperation(proto).serializedData()
    }
}

#if TESTABLE_BUILD

extension SSKProtoSyncMessageStickerPackOperation {
    @objc
    public func serializedDataIgnoringErrors() -> Data? {
        return try! self.serializedData()
    }
}

extension SSKProtoSyncMessageStickerPackOperationBuilder {
    @objc
    public func buildIgnoringErrors() -> SSKProtoSyncMessageStickerPackOperation? {
        return try! self.build()
    }
}

#endif

// MARK: - SSKProtoSyncMessageViewOnceOpen

@objc
public class SSKProtoSyncMessageViewOnceOpen: NSObject, Codable, NSSecureCoding {

    fileprivate let proto: SignalServiceProtos_SyncMessage.ViewOnceOpen

    @objc
    public let timestamp: UInt64

    @objc
    public var senderAci: String? {
        guard hasSenderAci else {
            return nil
        }
        return proto.senderAci
    }
    @objc
    public var hasSenderAci: Bool {
        return proto.hasSenderAci
    }

    public var hasUnknownFields: Bool {
        return !proto.unknownFields.data.isEmpty
    }
    public var unknownFields: SwiftProtobuf.UnknownStorage? {
        guard hasUnknownFields else { return nil }
        return proto.unknownFields
    }

    private init(proto: SignalServiceProtos_SyncMessage.ViewOnceOpen,
                 timestamp: UInt64) {
        self.proto = proto
        self.timestamp = timestamp
    }

    @objc
    public func serializedData() throws -> Data {
        return try self.proto.serializedData()
    }

    @objc
    public convenience init(serializedData: Data) throws {
        let proto = try SignalServiceProtos_SyncMessage.ViewOnceOpen(serializedData: serializedData)
        try self.init(proto)
    }

    fileprivate convenience init(_ proto: SignalServiceProtos_SyncMessage.ViewOnceOpen) throws {
        guard proto.hasTimestamp else {
            throw SSKProtoError.invalidProtobuf(description: "\(Self.logTag()) missing required field: timestamp")
        }
        let timestamp = proto.timestamp

        self.init(proto: proto,
                  timestamp: timestamp)
    }

    public required convenience init(from decoder: Swift.Decoder) throws {
        let singleValueContainer = try decoder.singleValueContainer()
        let serializedData = try singleValueContainer.decode(Data.self)
        try self.init(serializedData: serializedData)
    }
    public func encode(to encoder: Swift.Encoder) throws {
        var singleValueContainer = encoder.singleValueContainer()
        try singleValueContainer.encode(try serializedData())
    }

    public static var supportsSecureCoding: Bool { true }

    public required convenience init?(coder: NSCoder) {
        guard let serializedData = coder.decodeData() else { return nil }
        do {
            try self.init(serializedData: serializedData)
        } catch {
            owsFailDebug("Failed to decode serialized data \(error)")
            return nil
        }
    }

    public func encode(with coder: NSCoder) {
        do {
            coder.encode(try serializedData())
        } catch {
            owsFailDebug("Failed to encode serialized data \(error)")
        }
    }

    @objc
    public override var debugDescription: String {
        return "\(proto)"
    }
}

extension SSKProtoSyncMessageViewOnceOpen {
    @objc
    public static func builder(timestamp: UInt64) -> SSKProtoSyncMessageViewOnceOpenBuilder {
        return SSKProtoSyncMessageViewOnceOpenBuilder(timestamp: timestamp)
    }

    // asBuilder() constructs a builder that reflects the proto's contents.
    @objc
    public func asBuilder() -> SSKProtoSyncMessageViewOnceOpenBuilder {
        let builder = SSKProtoSyncMessageViewOnceOpenBuilder(timestamp: timestamp)
        if let _value = senderAci {
            builder.setSenderAci(_value)
        }
        if let _value = unknownFields {
            builder.setUnknownFields(_value)
        }
        return builder
    }
}

@objc
public class SSKProtoSyncMessageViewOnceOpenBuilder: NSObject {

    private var proto = SignalServiceProtos_SyncMessage.ViewOnceOpen()

    @objc
    fileprivate override init() {}

    @objc
    fileprivate init(timestamp: UInt64) {
        super.init()

        setTimestamp(timestamp)
    }

    @objc
    @available(swift, obsoleted: 1.0)
    public func setSenderAci(_ valueParam: String?) {
        guard let valueParam = valueParam else { return }
        proto.senderAci = valueParam
    }

    public func setSenderAci(_ valueParam: String) {
        proto.senderAci = valueParam
    }

    @objc
    public func setTimestamp(_ valueParam: UInt64) {
        proto.timestamp = valueParam
    }

    public func setUnknownFields(_ unknownFields: SwiftProtobuf.UnknownStorage) {
        proto.unknownFields = unknownFields
    }

    @objc
    public func build() throws -> SSKProtoSyncMessageViewOnceOpen {
        return try SSKProtoSyncMessageViewOnceOpen(proto)
    }

    @objc
    public func buildSerializedData() throws -> Data {
        return try SSKProtoSyncMessageViewOnceOpen(proto).serializedData()
    }
}

#if TESTABLE_BUILD

extension SSKProtoSyncMessageViewOnceOpen {
    @objc
    public func serializedDataIgnoringErrors() -> Data? {
        return try! self.serializedData()
    }
}

extension SSKProtoSyncMessageViewOnceOpenBuilder {
    @objc
    public func buildIgnoringErrors() -> SSKProtoSyncMessageViewOnceOpen? {
        return try! self.build()
    }
}

#endif

// MARK: - SSKProtoSyncMessageFetchLatestType

@objc
public enum SSKProtoSyncMessageFetchLatestType: Int32 {
    case unknown = 0
    case localProfile = 1
    case storageManifest = 2
    case subscriptionStatus = 3
}

private func SSKProtoSyncMessageFetchLatestTypeWrap(_ value: SignalServiceProtos_SyncMessage.FetchLatest.TypeEnum) -> SSKProtoSyncMessageFetchLatestType {
    switch value {
    case .unknown: return .unknown
    case .localProfile: return .localProfile
    case .storageManifest: return .storageManifest
    case .subscriptionStatus: return .subscriptionStatus
    }
}

private func SSKProtoSyncMessageFetchLatestTypeUnwrap(_ value: SSKProtoSyncMessageFetchLatestType) -> SignalServiceProtos_SyncMessage.FetchLatest.TypeEnum {
    switch value {
    case .unknown: return .unknown
    case .localProfile: return .localProfile
    case .storageManifest: return .storageManifest
    case .subscriptionStatus: return .subscriptionStatus
    }
}

// MARK: - SSKProtoSyncMessageFetchLatest

@objc
public class SSKProtoSyncMessageFetchLatest: NSObject, Codable, NSSecureCoding {

    fileprivate let proto: SignalServiceProtos_SyncMessage.FetchLatest

    public var type: SSKProtoSyncMessageFetchLatestType? {
        guard hasType else {
            return nil
        }
        return SSKProtoSyncMessageFetchLatestTypeWrap(proto.type)
    }
    // This "unwrapped" accessor should only be used if the "has value" accessor has already been checked.
    @objc
    public var unwrappedType: SSKProtoSyncMessageFetchLatestType {
        if !hasType {
            // TODO: We could make this a crashing assert.
            owsFailDebug("Unsafe unwrap of missing optional: FetchLatest.type.")
        }
        return SSKProtoSyncMessageFetchLatestTypeWrap(proto.type)
    }
    @objc
    public var hasType: Bool {
        return proto.hasType
    }

    public var hasUnknownFields: Bool {
        return !proto.unknownFields.data.isEmpty
    }
    public var unknownFields: SwiftProtobuf.UnknownStorage? {
        guard hasUnknownFields else { return nil }
        return proto.unknownFields
    }

    private init(proto: SignalServiceProtos_SyncMessage.FetchLatest) {
        self.proto = proto
    }

    @objc
    public func serializedData() throws -> Data {
        return try self.proto.serializedData()
    }

    @objc
    public convenience init(serializedData: Data) throws {
        let proto = try SignalServiceProtos_SyncMessage.FetchLatest(serializedData: serializedData)
        self.init(proto)
    }

    fileprivate convenience init(_ proto: SignalServiceProtos_SyncMessage.FetchLatest) {
        self.init(proto: proto)
    }

    public required convenience init(from decoder: Swift.Decoder) throws {
        let singleValueContainer = try decoder.singleValueContainer()
        let serializedData = try singleValueContainer.decode(Data.self)
        try self.init(serializedData: serializedData)
    }
    public func encode(to encoder: Swift.Encoder) throws {
        var singleValueContainer = encoder.singleValueContainer()
        try singleValueContainer.encode(try serializedData())
    }

    public static var supportsSecureCoding: Bool { true }

    public required convenience init?(coder: NSCoder) {
        guard let serializedData = coder.decodeData() else { return nil }
        do {
            try self.init(serializedData: serializedData)
        } catch {
            owsFailDebug("Failed to decode serialized data \(error)")
            return nil
        }
    }

    public func encode(with coder: NSCoder) {
        do {
            coder.encode(try serializedData())
        } catch {
            owsFailDebug("Failed to encode serialized data \(error)")
        }
    }

    @objc
    public override var debugDescription: String {
        return "\(proto)"
    }
}

extension SSKProtoSyncMessageFetchLatest {
    @objc
    public static func builder() -> SSKProtoSyncMessageFetchLatestBuilder {
        return SSKProtoSyncMessageFetchLatestBuilder()
    }

    // asBuilder() constructs a builder that reflects the proto's contents.
    @objc
    public func asBuilder() -> SSKProtoSyncMessageFetchLatestBuilder {
        let builder = SSKProtoSyncMessageFetchLatestBuilder()
        if let _value = type {
            builder.setType(_value)
        }
        if let _value = unknownFields {
            builder.setUnknownFields(_value)
        }
        return builder
    }
}

@objc
public class SSKProtoSyncMessageFetchLatestBuilder: NSObject {

    private var proto = SignalServiceProtos_SyncMessage.FetchLatest()

    @objc
    fileprivate override init() {}

    @objc
    public func setType(_ valueParam: SSKProtoSyncMessageFetchLatestType) {
        proto.type = SSKProtoSyncMessageFetchLatestTypeUnwrap(valueParam)
    }

    public func setUnknownFields(_ unknownFields: SwiftProtobuf.UnknownStorage) {
        proto.unknownFields = unknownFields
    }

    @objc
    public func build() throws -> SSKProtoSyncMessageFetchLatest {
        return SSKProtoSyncMessageFetchLatest(proto)
    }

    @objc
    public func buildInfallibly() -> SSKProtoSyncMessageFetchLatest {
        return SSKProtoSyncMessageFetchLatest(proto)
    }

    @objc
    public func buildSerializedData() throws -> Data {
        return try SSKProtoSyncMessageFetchLatest(proto).serializedData()
    }
}

#if TESTABLE_BUILD

extension SSKProtoSyncMessageFetchLatest {
    @objc
    public func serializedDataIgnoringErrors() -> Data? {
        return try! self.serializedData()
    }
}

extension SSKProtoSyncMessageFetchLatestBuilder {
    @objc
    public func buildIgnoringErrors() -> SSKProtoSyncMessageFetchLatest? {
        return self.buildInfallibly()
    }
}

#endif

// MARK: - SSKProtoSyncMessageKeys

@objc
public class SSKProtoSyncMessageKeys: NSObject, Codable, NSSecureCoding {

    fileprivate let proto: SignalServiceProtos_SyncMessage.Keys

    @objc
    public var storageService: Data? {
        guard hasStorageService else {
            return nil
        }
        return proto.storageService
    }
    @objc
    public var hasStorageService: Bool {
        return proto.hasStorageService
    }

    @objc
    public var master: Data? {
        guard hasMaster else {
            return nil
        }
        return proto.master
    }
    @objc
    public var hasMaster: Bool {
        return proto.hasMaster
    }

    public var hasUnknownFields: Bool {
        return !proto.unknownFields.data.isEmpty
    }
    public var unknownFields: SwiftProtobuf.UnknownStorage? {
        guard hasUnknownFields else { return nil }
        return proto.unknownFields
    }

    private init(proto: SignalServiceProtos_SyncMessage.Keys) {
        self.proto = proto
    }

    @objc
    public func serializedData() throws -> Data {
        return try self.proto.serializedData()
    }

    @objc
    public convenience init(serializedData: Data) throws {
        let proto = try SignalServiceProtos_SyncMessage.Keys(serializedData: serializedData)
        self.init(proto)
    }

    fileprivate convenience init(_ proto: SignalServiceProtos_SyncMessage.Keys) {
        self.init(proto: proto)
    }

    public required convenience init(from decoder: Swift.Decoder) throws {
        let singleValueContainer = try decoder.singleValueContainer()
        let serializedData = try singleValueContainer.decode(Data.self)
        try self.init(serializedData: serializedData)
    }
    public func encode(to encoder: Swift.Encoder) throws {
        var singleValueContainer = encoder.singleValueContainer()
        try singleValueContainer.encode(try serializedData())
    }

    public static var supportsSecureCoding: Bool { true }

    public required convenience init?(coder: NSCoder) {
        guard let serializedData = coder.decodeData() else { return nil }
        do {
            try self.init(serializedData: serializedData)
        } catch {
            owsFailDebug("Failed to decode serialized data \(error)")
            return nil
        }
    }

    public func encode(with coder: NSCoder) {
        do {
            coder.encode(try serializedData())
        } catch {
            owsFailDebug("Failed to encode serialized data \(error)")
        }
    }

    @objc
    public override var debugDescription: String {
        return "\(proto)"
    }
}

extension SSKProtoSyncMessageKeys {
    @objc
    public static func builder() -> SSKProtoSyncMessageKeysBuilder {
        return SSKProtoSyncMessageKeysBuilder()
    }

    // asBuilder() constructs a builder that reflects the proto's contents.
    @objc
    public func asBuilder() -> SSKProtoSyncMessageKeysBuilder {
        let builder = SSKProtoSyncMessageKeysBuilder()
        if let _value = storageService {
            builder.setStorageService(_value)
        }
        if let _value = master {
            builder.setMaster(_value)
        }
        if let _value = unknownFields {
            builder.setUnknownFields(_value)
        }
        return builder
    }
}

@objc
public class SSKProtoSyncMessageKeysBuilder: NSObject {

    private var proto = SignalServiceProtos_SyncMessage.Keys()

    @objc
    fileprivate override init() {}

    @objc
    @available(swift, obsoleted: 1.0)
    public func setStorageService(_ valueParam: Data?) {
        guard let valueParam = valueParam else { return }
        proto.storageService = valueParam
    }

    public func setStorageService(_ valueParam: Data) {
        proto.storageService = valueParam
    }

    @objc
    @available(swift, obsoleted: 1.0)
    public func setMaster(_ valueParam: Data?) {
        guard let valueParam = valueParam else { return }
        proto.master = valueParam
    }

    public func setMaster(_ valueParam: Data) {
        proto.master = valueParam
    }

    public func setUnknownFields(_ unknownFields: SwiftProtobuf.UnknownStorage) {
        proto.unknownFields = unknownFields
    }

    @objc
    public func build() throws -> SSKProtoSyncMessageKeys {
        return SSKProtoSyncMessageKeys(proto)
    }

    @objc
    public func buildInfallibly() -> SSKProtoSyncMessageKeys {
        return SSKProtoSyncMessageKeys(proto)
    }

    @objc
    public func buildSerializedData() throws -> Data {
        return try SSKProtoSyncMessageKeys(proto).serializedData()
    }
}

#if TESTABLE_BUILD

extension SSKProtoSyncMessageKeys {
    @objc
    public func serializedDataIgnoringErrors() -> Data? {
        return try! self.serializedData()
    }
}

extension SSKProtoSyncMessageKeysBuilder {
    @objc
    public func buildIgnoringErrors() -> SSKProtoSyncMessageKeys? {
        return self.buildInfallibly()
    }
}

#endif

// MARK: - SSKProtoSyncMessageMessageRequestResponseType

@objc
public enum SSKProtoSyncMessageMessageRequestResponseType: Int32 {
    case unknown = 0
    case accept = 1
    case delete = 2
    case block = 3
    case blockAndDelete = 4
}

private func SSKProtoSyncMessageMessageRequestResponseTypeWrap(_ value: SignalServiceProtos_SyncMessage.MessageRequestResponse.TypeEnum) -> SSKProtoSyncMessageMessageRequestResponseType {
    switch value {
    case .unknown: return .unknown
    case .accept: return .accept
    case .delete: return .delete
    case .block: return .block
    case .blockAndDelete: return .blockAndDelete
    }
}

private func SSKProtoSyncMessageMessageRequestResponseTypeUnwrap(_ value: SSKProtoSyncMessageMessageRequestResponseType) -> SignalServiceProtos_SyncMessage.MessageRequestResponse.TypeEnum {
    switch value {
    case .unknown: return .unknown
    case .accept: return .accept
    case .delete: return .delete
    case .block: return .block
    case .blockAndDelete: return .blockAndDelete
    }
}

// MARK: - SSKProtoSyncMessageMessageRequestResponse

@objc
public class SSKProtoSyncMessageMessageRequestResponse: NSObject, Codable, NSSecureCoding {

    fileprivate let proto: SignalServiceProtos_SyncMessage.MessageRequestResponse

    @objc
    public var threadAci: String? {
        guard hasThreadAci else {
            return nil
        }
        return proto.threadAci
    }
    @objc
    public var hasThreadAci: Bool {
        return proto.hasThreadAci
    }

    @objc
    public var groupID: Data? {
        guard hasGroupID else {
            return nil
        }
        return proto.groupID
    }
    @objc
    public var hasGroupID: Bool {
        return proto.hasGroupID
    }

    public var type: SSKProtoSyncMessageMessageRequestResponseType? {
        guard hasType else {
            return nil
        }
        return SSKProtoSyncMessageMessageRequestResponseTypeWrap(proto.type)
    }
    // This "unwrapped" accessor should only be used if the "has value" accessor has already been checked.
    @objc
    public var unwrappedType: SSKProtoSyncMessageMessageRequestResponseType {
        if !hasType {
            // TODO: We could make this a crashing assert.
            owsFailDebug("Unsafe unwrap of missing optional: MessageRequestResponse.type.")
        }
        return SSKProtoSyncMessageMessageRequestResponseTypeWrap(proto.type)
    }
    @objc
    public var hasType: Bool {
        return proto.hasType
    }

    public var hasUnknownFields: Bool {
        return !proto.unknownFields.data.isEmpty
    }
    public var unknownFields: SwiftProtobuf.UnknownStorage? {
        guard hasUnknownFields else { return nil }
        return proto.unknownFields
    }

    private init(proto: SignalServiceProtos_SyncMessage.MessageRequestResponse) {
        self.proto = proto
    }

    @objc
    public func serializedData() throws -> Data {
        return try self.proto.serializedData()
    }

    @objc
    public convenience init(serializedData: Data) throws {
        let proto = try SignalServiceProtos_SyncMessage.MessageRequestResponse(serializedData: serializedData)
        self.init(proto)
    }

    fileprivate convenience init(_ proto: SignalServiceProtos_SyncMessage.MessageRequestResponse) {
        self.init(proto: proto)
    }

    public required convenience init(from decoder: Swift.Decoder) throws {
        let singleValueContainer = try decoder.singleValueContainer()
        let serializedData = try singleValueContainer.decode(Data.self)
        try self.init(serializedData: serializedData)
    }
    public func encode(to encoder: Swift.Encoder) throws {
        var singleValueContainer = encoder.singleValueContainer()
        try singleValueContainer.encode(try serializedData())
    }

    public static var supportsSecureCoding: Bool { true }

    public required convenience init?(coder: NSCoder) {
        guard let serializedData = coder.decodeData() else { return nil }
        do {
            try self.init(serializedData: serializedData)
        } catch {
            owsFailDebug("Failed to decode serialized data \(error)")
            return nil
        }
    }

    public func encode(with coder: NSCoder) {
        do {
            coder.encode(try serializedData())
        } catch {
            owsFailDebug("Failed to encode serialized data \(error)")
        }
    }

    @objc
    public override var debugDescription: String {
        return "\(proto)"
    }
}

extension SSKProtoSyncMessageMessageRequestResponse {
    @objc
    public static func builder() -> SSKProtoSyncMessageMessageRequestResponseBuilder {
        return SSKProtoSyncMessageMessageRequestResponseBuilder()
    }

    // asBuilder() constructs a builder that reflects the proto's contents.
    @objc
    public func asBuilder() -> SSKProtoSyncMessageMessageRequestResponseBuilder {
        let builder = SSKProtoSyncMessageMessageRequestResponseBuilder()
        if let _value = threadAci {
            builder.setThreadAci(_value)
        }
        if let _value = groupID {
            builder.setGroupID(_value)
        }
        if let _value = type {
            builder.setType(_value)
        }
        if let _value = unknownFields {
            builder.setUnknownFields(_value)
        }
        return builder
    }
}

@objc
public class SSKProtoSyncMessageMessageRequestResponseBuilder: NSObject {

    private var proto = SignalServiceProtos_SyncMessage.MessageRequestResponse()

    @objc
    fileprivate override init() {}

    @objc
    @available(swift, obsoleted: 1.0)
    public func setThreadAci(_ valueParam: String?) {
        guard let valueParam = valueParam else { return }
        proto.threadAci = valueParam
    }

    public func setThreadAci(_ valueParam: String) {
        proto.threadAci = valueParam
    }

    @objc
    @available(swift, obsoleted: 1.0)
    public func setGroupID(_ valueParam: Data?) {
        guard let valueParam = valueParam else { return }
        proto.groupID = valueParam
    }

    public func setGroupID(_ valueParam: Data) {
        proto.groupID = valueParam
    }

    @objc
    public func setType(_ valueParam: SSKProtoSyncMessageMessageRequestResponseType) {
        proto.type = SSKProtoSyncMessageMessageRequestResponseTypeUnwrap(valueParam)
    }

    public func setUnknownFields(_ unknownFields: SwiftProtobuf.UnknownStorage) {
        proto.unknownFields = unknownFields
    }

    @objc
    public func build() throws -> SSKProtoSyncMessageMessageRequestResponse {
        return SSKProtoSyncMessageMessageRequestResponse(proto)
    }

    @objc
    public func buildInfallibly() -> SSKProtoSyncMessageMessageRequestResponse {
        return SSKProtoSyncMessageMessageRequestResponse(proto)
    }

    @objc
    public func buildSerializedData() throws -> Data {
        return try SSKProtoSyncMessageMessageRequestResponse(proto).serializedData()
    }
}

#if TESTABLE_BUILD

extension SSKProtoSyncMessageMessageRequestResponse {
    @objc
    public func serializedDataIgnoringErrors() -> Data? {
        return try! self.serializedData()
    }
}

extension SSKProtoSyncMessageMessageRequestResponseBuilder {
    @objc
    public func buildIgnoringErrors() -> SSKProtoSyncMessageMessageRequestResponse? {
        return self.buildInfallibly()
    }
}

#endif

// MARK: - SSKProtoSyncMessageOutgoingPaymentMobileCoin

@objc
public class SSKProtoSyncMessageOutgoingPaymentMobileCoin: NSObject, Codable, NSSecureCoding {

    fileprivate let proto: SignalServiceProtos_SyncMessage.OutgoingPayment.MobileCoin

    @objc
    public let amountPicoMob: UInt64

    @objc
    public let feePicoMob: UInt64

    @objc
    public let ledgerBlockIndex: UInt64

    @objc
    public var recipientAddress: Data? {
        guard hasRecipientAddress else {
            return nil
        }
        return proto.recipientAddress
    }
    @objc
    public var hasRecipientAddress: Bool {
        return proto.hasRecipientAddress
    }

    @objc
    public var receipt: Data? {
        guard hasReceipt else {
            return nil
        }
        return proto.receipt
    }
    @objc
    public var hasReceipt: Bool {
        return proto.hasReceipt
    }

    @objc
    public var ledgerBlockTimestamp: UInt64 {
        return proto.ledgerBlockTimestamp
    }
    @objc
    public var hasLedgerBlockTimestamp: Bool {
        return proto.hasLedgerBlockTimestamp
    }

    @objc
    public var spentKeyImages: [Data] {
        return proto.spentKeyImages
    }

    @objc
    public var outputPublicKeys: [Data] {
        return proto.outputPublicKeys
    }

    public var hasUnknownFields: Bool {
        return !proto.unknownFields.data.isEmpty
    }
    public var unknownFields: SwiftProtobuf.UnknownStorage? {
        guard hasUnknownFields else { return nil }
        return proto.unknownFields
    }

    private init(proto: SignalServiceProtos_SyncMessage.OutgoingPayment.MobileCoin,
                 amountPicoMob: UInt64,
                 feePicoMob: UInt64,
                 ledgerBlockIndex: UInt64) {
        self.proto = proto
        self.amountPicoMob = amountPicoMob
        self.feePicoMob = feePicoMob
        self.ledgerBlockIndex = ledgerBlockIndex
    }

    @objc
    public func serializedData() throws -> Data {
        return try self.proto.serializedData()
    }

    @objc
    public convenience init(serializedData: Data) throws {
        let proto = try SignalServiceProtos_SyncMessage.OutgoingPayment.MobileCoin(serializedData: serializedData)
        try self.init(proto)
    }

    fileprivate convenience init(_ proto: SignalServiceProtos_SyncMessage.OutgoingPayment.MobileCoin) throws {
        guard proto.hasAmountPicoMob else {
            throw SSKProtoError.invalidProtobuf(description: "\(Self.logTag()) missing required field: amountPicoMob")
        }
        let amountPicoMob = proto.amountPicoMob

        guard proto.hasFeePicoMob else {
            throw SSKProtoError.invalidProtobuf(description: "\(Self.logTag()) missing required field: feePicoMob")
        }
        let feePicoMob = proto.feePicoMob

        guard proto.hasLedgerBlockIndex else {
            throw SSKProtoError.invalidProtobuf(description: "\(Self.logTag()) missing required field: ledgerBlockIndex")
        }
        let ledgerBlockIndex = proto.ledgerBlockIndex

        self.init(proto: proto,
                  amountPicoMob: amountPicoMob,
                  feePicoMob: feePicoMob,
                  ledgerBlockIndex: ledgerBlockIndex)
    }

    public required convenience init(from decoder: Swift.Decoder) throws {
        let singleValueContainer = try decoder.singleValueContainer()
        let serializedData = try singleValueContainer.decode(Data.self)
        try self.init(serializedData: serializedData)
    }
    public func encode(to encoder: Swift.Encoder) throws {
        var singleValueContainer = encoder.singleValueContainer()
        try singleValueContainer.encode(try serializedData())
    }

    public static var supportsSecureCoding: Bool { true }

    public required convenience init?(coder: NSCoder) {
        guard let serializedData = coder.decodeData() else { return nil }
        do {
            try self.init(serializedData: serializedData)
        } catch {
            owsFailDebug("Failed to decode serialized data \(error)")
            return nil
        }
    }

    public func encode(with coder: NSCoder) {
        do {
            coder.encode(try serializedData())
        } catch {
            owsFailDebug("Failed to encode serialized data \(error)")
        }
    }

    @objc
    public override var debugDescription: String {
        return "\(proto)"
    }
}

extension SSKProtoSyncMessageOutgoingPaymentMobileCoin {
    @objc
    public static func builder(amountPicoMob: UInt64, feePicoMob: UInt64, ledgerBlockIndex: UInt64) -> SSKProtoSyncMessageOutgoingPaymentMobileCoinBuilder {
        return SSKProtoSyncMessageOutgoingPaymentMobileCoinBuilder(amountPicoMob: amountPicoMob, feePicoMob: feePicoMob, ledgerBlockIndex: ledgerBlockIndex)
    }

    // asBuilder() constructs a builder that reflects the proto's contents.
    @objc
    public func asBuilder() -> SSKProtoSyncMessageOutgoingPaymentMobileCoinBuilder {
        let builder = SSKProtoSyncMessageOutgoingPaymentMobileCoinBuilder(amountPicoMob: amountPicoMob, feePicoMob: feePicoMob, ledgerBlockIndex: ledgerBlockIndex)
        if let _value = recipientAddress {
            builder.setRecipientAddress(_value)
        }
        if let _value = receipt {
            builder.setReceipt(_value)
        }
        if hasLedgerBlockTimestamp {
            builder.setLedgerBlockTimestamp(ledgerBlockTimestamp)
        }
        builder.setSpentKeyImages(spentKeyImages)
        builder.setOutputPublicKeys(outputPublicKeys)
        if let _value = unknownFields {
            builder.setUnknownFields(_value)
        }
        return builder
    }
}

@objc
public class SSKProtoSyncMessageOutgoingPaymentMobileCoinBuilder: NSObject {

    private var proto = SignalServiceProtos_SyncMessage.OutgoingPayment.MobileCoin()

    @objc
    fileprivate override init() {}

    @objc
    fileprivate init(amountPicoMob: UInt64, feePicoMob: UInt64, ledgerBlockIndex: UInt64) {
        super.init()

        setAmountPicoMob(amountPicoMob)
        setFeePicoMob(feePicoMob)
        setLedgerBlockIndex(ledgerBlockIndex)
    }

    @objc
    @available(swift, obsoleted: 1.0)
    public func setRecipientAddress(_ valueParam: Data?) {
        guard let valueParam = valueParam else { return }
        proto.recipientAddress = valueParam
    }

    public func setRecipientAddress(_ valueParam: Data) {
        proto.recipientAddress = valueParam
    }

    @objc
    public func setAmountPicoMob(_ valueParam: UInt64) {
        proto.amountPicoMob = valueParam
    }

    @objc
    public func setFeePicoMob(_ valueParam: UInt64) {
        proto.feePicoMob = valueParam
    }

    @objc
    @available(swift, obsoleted: 1.0)
    public func setReceipt(_ valueParam: Data?) {
        guard let valueParam = valueParam else { return }
        proto.receipt = valueParam
    }

    public func setReceipt(_ valueParam: Data) {
        proto.receipt = valueParam
    }

    @objc
    public func setLedgerBlockTimestamp(_ valueParam: UInt64) {
        proto.ledgerBlockTimestamp = valueParam
    }

    @objc
    public func setLedgerBlockIndex(_ valueParam: UInt64) {
        proto.ledgerBlockIndex = valueParam
    }

    @objc
    public func addSpentKeyImages(_ valueParam: Data) {
        proto.spentKeyImages.append(valueParam)
    }

    @objc
    public func setSpentKeyImages(_ wrappedItems: [Data]) {
        proto.spentKeyImages = wrappedItems
    }

    @objc
    public func addOutputPublicKeys(_ valueParam: Data) {
        proto.outputPublicKeys.append(valueParam)
    }

    @objc
    public func setOutputPublicKeys(_ wrappedItems: [Data]) {
        proto.outputPublicKeys = wrappedItems
    }

    public func setUnknownFields(_ unknownFields: SwiftProtobuf.UnknownStorage) {
        proto.unknownFields = unknownFields
    }

    @objc
    public func build() throws -> SSKProtoSyncMessageOutgoingPaymentMobileCoin {
        return try SSKProtoSyncMessageOutgoingPaymentMobileCoin(proto)
    }

    @objc
    public func buildSerializedData() throws -> Data {
        return try SSKProtoSyncMessageOutgoingPaymentMobileCoin(proto).serializedData()
    }
}

#if TESTABLE_BUILD

extension SSKProtoSyncMessageOutgoingPaymentMobileCoin {
    @objc
    public func serializedDataIgnoringErrors() -> Data? {
        return try! self.serializedData()
    }
}

extension SSKProtoSyncMessageOutgoingPaymentMobileCoinBuilder {
    @objc
    public func buildIgnoringErrors() -> SSKProtoSyncMessageOutgoingPaymentMobileCoin? {
        return try! self.build()
    }
}

#endif

// MARK: - SSKProtoSyncMessageOutgoingPayment

@objc
public class SSKProtoSyncMessageOutgoingPayment: NSObject, Codable, NSSecureCoding {

    fileprivate let proto: SignalServiceProtos_SyncMessage.OutgoingPayment

    @objc
    public let mobileCoin: SSKProtoSyncMessageOutgoingPaymentMobileCoin?

    @objc
    public var recipientServiceID: String? {
        guard hasRecipientServiceID else {
            return nil
        }
        return proto.recipientServiceID
    }
    @objc
    public var hasRecipientServiceID: Bool {
        return proto.hasRecipientServiceID
    }

    @objc
    public var note: String? {
        guard hasNote else {
            return nil
        }
        return proto.note
    }
    @objc
    public var hasNote: Bool {
        return proto.hasNote
    }

    public var hasUnknownFields: Bool {
        return !proto.unknownFields.data.isEmpty
    }
    public var unknownFields: SwiftProtobuf.UnknownStorage? {
        guard hasUnknownFields else { return nil }
        return proto.unknownFields
    }

    private init(proto: SignalServiceProtos_SyncMessage.OutgoingPayment,
                 mobileCoin: SSKProtoSyncMessageOutgoingPaymentMobileCoin?) {
        self.proto = proto
        self.mobileCoin = mobileCoin
    }

    @objc
    public func serializedData() throws -> Data {
        return try self.proto.serializedData()
    }

    @objc
    public convenience init(serializedData: Data) throws {
        let proto = try SignalServiceProtos_SyncMessage.OutgoingPayment(serializedData: serializedData)
        try self.init(proto)
    }

    fileprivate convenience init(_ proto: SignalServiceProtos_SyncMessage.OutgoingPayment) throws {
        var mobileCoin: SSKProtoSyncMessageOutgoingPaymentMobileCoin?
        if proto.hasMobileCoin {
            mobileCoin = try SSKProtoSyncMessageOutgoingPaymentMobileCoin(proto.mobileCoin)
        }

        self.init(proto: proto,
                  mobileCoin: mobileCoin)
    }

    public required convenience init(from decoder: Swift.Decoder) throws {
        let singleValueContainer = try decoder.singleValueContainer()
        let serializedData = try singleValueContainer.decode(Data.self)
        try self.init(serializedData: serializedData)
    }
    public func encode(to encoder: Swift.Encoder) throws {
        var singleValueContainer = encoder.singleValueContainer()
        try singleValueContainer.encode(try serializedData())
    }

    public static var supportsSecureCoding: Bool { true }

    public required convenience init?(coder: NSCoder) {
        guard let serializedData = coder.decodeData() else { return nil }
        do {
            try self.init(serializedData: serializedData)
        } catch {
            owsFailDebug("Failed to decode serialized data \(error)")
            return nil
        }
    }

    public func encode(with coder: NSCoder) {
        do {
            coder.encode(try serializedData())
        } catch {
            owsFailDebug("Failed to encode serialized data \(error)")
        }
    }

    @objc
    public override var debugDescription: String {
        return "\(proto)"
    }
}

extension SSKProtoSyncMessageOutgoingPayment {
    @objc
    public static func builder() -> SSKProtoSyncMessageOutgoingPaymentBuilder {
        return SSKProtoSyncMessageOutgoingPaymentBuilder()
    }

    // asBuilder() constructs a builder that reflects the proto's contents.
    @objc
    public func asBuilder() -> SSKProtoSyncMessageOutgoingPaymentBuilder {
        let builder = SSKProtoSyncMessageOutgoingPaymentBuilder()
        if let _value = recipientServiceID {
            builder.setRecipientServiceID(_value)
        }
        if let _value = note {
            builder.setNote(_value)
        }
        if let _value = mobileCoin {
            builder.setMobileCoin(_value)
        }
        if let _value = unknownFields {
            builder.setUnknownFields(_value)
        }
        return builder
    }
}

@objc
public class SSKProtoSyncMessageOutgoingPaymentBuilder: NSObject {

    private var proto = SignalServiceProtos_SyncMessage.OutgoingPayment()

    @objc
    fileprivate override init() {}

    @objc
    @available(swift, obsoleted: 1.0)
    public func setRecipientServiceID(_ valueParam: String?) {
        guard let valueParam = valueParam else { return }
        proto.recipientServiceID = valueParam
    }

    public func setRecipientServiceID(_ valueParam: String) {
        proto.recipientServiceID = valueParam
    }

    @objc
    @available(swift, obsoleted: 1.0)
    public func setNote(_ valueParam: String?) {
        guard let valueParam = valueParam else { return }
        proto.note = valueParam
    }

    public func setNote(_ valueParam: String) {
        proto.note = valueParam
    }

    @objc
    @available(swift, obsoleted: 1.0)
    public func setMobileCoin(_ valueParam: SSKProtoSyncMessageOutgoingPaymentMobileCoin?) {
        guard let valueParam = valueParam else { return }
        proto.mobileCoin = valueParam.proto
    }

    public func setMobileCoin(_ valueParam: SSKProtoSyncMessageOutgoingPaymentMobileCoin) {
        proto.mobileCoin = valueParam.proto
    }

    public func setUnknownFields(_ unknownFields: SwiftProtobuf.UnknownStorage) {
        proto.unknownFields = unknownFields
    }

    @objc
    public func build() throws -> SSKProtoSyncMessageOutgoingPayment {
        return try SSKProtoSyncMessageOutgoingPayment(proto)
    }

    @objc
    public func buildSerializedData() throws -> Data {
        return try SSKProtoSyncMessageOutgoingPayment(proto).serializedData()
    }
}

#if TESTABLE_BUILD

extension SSKProtoSyncMessageOutgoingPayment {
    @objc
    public func serializedDataIgnoringErrors() -> Data? {
        return try! self.serializedData()
    }
}

extension SSKProtoSyncMessageOutgoingPaymentBuilder {
    @objc
    public func buildIgnoringErrors() -> SSKProtoSyncMessageOutgoingPayment? {
        return try! self.build()
    }
}

#endif

// MARK: - SSKProtoSyncMessageCallEventType

@objc
public enum SSKProtoSyncMessageCallEventType: Int32 {
    case unknownType = 0
    case audioCall = 1
    case videoCall = 2
    case groupCall = 3
}

private func SSKProtoSyncMessageCallEventTypeWrap(_ value: SignalServiceProtos_SyncMessage.CallEvent.TypeEnum) -> SSKProtoSyncMessageCallEventType {
    switch value {
    case .unknownType: return .unknownType
    case .audioCall: return .audioCall
    case .videoCall: return .videoCall
    case .groupCall: return .groupCall
    }
}

private func SSKProtoSyncMessageCallEventTypeUnwrap(_ value: SSKProtoSyncMessageCallEventType) -> SignalServiceProtos_SyncMessage.CallEvent.TypeEnum {
    switch value {
    case .unknownType: return .unknownType
    case .audioCall: return .audioCall
    case .videoCall: return .videoCall
    case .groupCall: return .groupCall
    }
}

// MARK: - SSKProtoSyncMessageCallEventDirection

@objc
public enum SSKProtoSyncMessageCallEventDirection: Int32 {
    case unknownDirection = 0
    case incoming = 1
    case outgoing = 2
}

private func SSKProtoSyncMessageCallEventDirectionWrap(_ value: SignalServiceProtos_SyncMessage.CallEvent.Direction) -> SSKProtoSyncMessageCallEventDirection {
    switch value {
    case .unknownDirection: return .unknownDirection
    case .incoming: return .incoming
    case .outgoing: return .outgoing
    }
}

private func SSKProtoSyncMessageCallEventDirectionUnwrap(_ value: SSKProtoSyncMessageCallEventDirection) -> SignalServiceProtos_SyncMessage.CallEvent.Direction {
    switch value {
    case .unknownDirection: return .unknownDirection
    case .incoming: return .incoming
    case .outgoing: return .outgoing
    }
}

// MARK: - SSKProtoSyncMessageCallEventEvent

@objc
public enum SSKProtoSyncMessageCallEventEvent: Int32 {
    case unknownAction = 0
    case accepted = 1
    case notAccepted = 2
    case deleted = 3
}

private func SSKProtoSyncMessageCallEventEventWrap(_ value: SignalServiceProtos_SyncMessage.CallEvent.Event) -> SSKProtoSyncMessageCallEventEvent {
    switch value {
    case .unknownAction: return .unknownAction
    case .accepted: return .accepted
    case .notAccepted: return .notAccepted
    case .deleted: return .deleted
    }
}

private func SSKProtoSyncMessageCallEventEventUnwrap(_ value: SSKProtoSyncMessageCallEventEvent) -> SignalServiceProtos_SyncMessage.CallEvent.Event {
    switch value {
    case .unknownAction: return .unknownAction
    case .accepted: return .accepted
    case .notAccepted: return .notAccepted
    case .deleted: return .deleted
    }
}

// MARK: - SSKProtoSyncMessageCallEvent

@objc
public class SSKProtoSyncMessageCallEvent: NSObject, Codable, NSSecureCoding {

    fileprivate let proto: SignalServiceProtos_SyncMessage.CallEvent

    @objc
    public var conversationID: Data? {
        guard hasConversationID else {
            return nil
        }
        return proto.conversationID
    }
    @objc
    public var hasConversationID: Bool {
        return proto.hasConversationID
    }

    @objc
    public var callID: UInt64 {
        return proto.callID
    }
    @objc
    public var hasCallID: Bool {
        return proto.hasCallID
    }

    @objc
    public var timestamp: UInt64 {
        return proto.timestamp
    }
    @objc
    public var hasTimestamp: Bool {
        return proto.hasTimestamp
    }

    public var type: SSKProtoSyncMessageCallEventType? {
        guard hasType else {
            return nil
        }
        return SSKProtoSyncMessageCallEventTypeWrap(proto.type)
    }
    // This "unwrapped" accessor should only be used if the "has value" accessor has already been checked.
    @objc
    public var unwrappedType: SSKProtoSyncMessageCallEventType {
        if !hasType {
            // TODO: We could make this a crashing assert.
            owsFailDebug("Unsafe unwrap of missing optional: CallEvent.type.")
        }
        return SSKProtoSyncMessageCallEventTypeWrap(proto.type)
    }
    @objc
    public var hasType: Bool {
        return proto.hasType
    }

    public var direction: SSKProtoSyncMessageCallEventDirection? {
        guard hasDirection else {
            return nil
        }
        return SSKProtoSyncMessageCallEventDirectionWrap(proto.direction)
    }
    // This "unwrapped" accessor should only be used if the "has value" accessor has already been checked.
    @objc
    public var unwrappedDirection: SSKProtoSyncMessageCallEventDirection {
        if !hasDirection {
            // TODO: We could make this a crashing assert.
            owsFailDebug("Unsafe unwrap of missing optional: CallEvent.direction.")
        }
        return SSKProtoSyncMessageCallEventDirectionWrap(proto.direction)
    }
    @objc
    public var hasDirection: Bool {
        return proto.hasDirection
    }

    public var event: SSKProtoSyncMessageCallEventEvent? {
        guard hasEvent else {
            return nil
        }
        return SSKProtoSyncMessageCallEventEventWrap(proto.event)
    }
    // This "unwrapped" accessor should only be used if the "has value" accessor has already been checked.
    @objc
    public var unwrappedEvent: SSKProtoSyncMessageCallEventEvent {
        if !hasEvent {
            // TODO: We could make this a crashing assert.
            owsFailDebug("Unsafe unwrap of missing optional: CallEvent.event.")
        }
        return SSKProtoSyncMessageCallEventEventWrap(proto.event)
    }
    @objc
    public var hasEvent: Bool {
        return proto.hasEvent
    }

    public var hasUnknownFields: Bool {
        return !proto.unknownFields.data.isEmpty
    }
    public var unknownFields: SwiftProtobuf.UnknownStorage? {
        guard hasUnknownFields else { return nil }
        return proto.unknownFields
    }

    private init(proto: SignalServiceProtos_SyncMessage.CallEvent) {
        self.proto = proto
    }

    @objc
    public func serializedData() throws -> Data {
        return try self.proto.serializedData()
    }

    @objc
    public convenience init(serializedData: Data) throws {
        let proto = try SignalServiceProtos_SyncMessage.CallEvent(serializedData: serializedData)
        self.init(proto)
    }

    fileprivate convenience init(_ proto: SignalServiceProtos_SyncMessage.CallEvent) {
        self.init(proto: proto)
    }

    public required convenience init(from decoder: Swift.Decoder) throws {
        let singleValueContainer = try decoder.singleValueContainer()
        let serializedData = try singleValueContainer.decode(Data.self)
        try self.init(serializedData: serializedData)
    }
    public func encode(to encoder: Swift.Encoder) throws {
        var singleValueContainer = encoder.singleValueContainer()
        try singleValueContainer.encode(try serializedData())
    }

    public static var supportsSecureCoding: Bool { true }

    public required convenience init?(coder: NSCoder) {
        guard let serializedData = coder.decodeData() else { return nil }
        do {
            try self.init(serializedData: serializedData)
        } catch {
            owsFailDebug("Failed to decode serialized data \(error)")
            return nil
        }
    }

    public func encode(with coder: NSCoder) {
        do {
            coder.encode(try serializedData())
        } catch {
            owsFailDebug("Failed to encode serialized data \(error)")
        }
    }

    @objc
    public override var debugDescription: String {
        return "\(proto)"
    }
}

extension SSKProtoSyncMessageCallEvent {
    @objc
    public static func builder() -> SSKProtoSyncMessageCallEventBuilder {
        return SSKProtoSyncMessageCallEventBuilder()
    }

    // asBuilder() constructs a builder that reflects the proto's contents.
    @objc
    public func asBuilder() -> SSKProtoSyncMessageCallEventBuilder {
        let builder = SSKProtoSyncMessageCallEventBuilder()
        if let _value = conversationID {
            builder.setConversationID(_value)
        }
        if hasCallID {
            builder.setCallID(callID)
        }
        if hasTimestamp {
            builder.setTimestamp(timestamp)
        }
        if let _value = type {
            builder.setType(_value)
        }
        if let _value = direction {
            builder.setDirection(_value)
        }
        if let _value = event {
            builder.setEvent(_value)
        }
        if let _value = unknownFields {
            builder.setUnknownFields(_value)
        }
        return builder
    }
}

@objc
public class SSKProtoSyncMessageCallEventBuilder: NSObject {

    private var proto = SignalServiceProtos_SyncMessage.CallEvent()

    @objc
    fileprivate override init() {}

    @objc
    @available(swift, obsoleted: 1.0)
    public func setConversationID(_ valueParam: Data?) {
        guard let valueParam = valueParam else { return }
        proto.conversationID = valueParam
    }

    public func setConversationID(_ valueParam: Data) {
        proto.conversationID = valueParam
    }

    @objc
    public func setCallID(_ valueParam: UInt64) {
        proto.callID = valueParam
    }

    @objc
    public func setTimestamp(_ valueParam: UInt64) {
        proto.timestamp = valueParam
    }

    @objc
    public func setType(_ valueParam: SSKProtoSyncMessageCallEventType) {
        proto.type = SSKProtoSyncMessageCallEventTypeUnwrap(valueParam)
    }

    @objc
    public func setDirection(_ valueParam: SSKProtoSyncMessageCallEventDirection) {
        proto.direction = SSKProtoSyncMessageCallEventDirectionUnwrap(valueParam)
    }

    @objc
    public func setEvent(_ valueParam: SSKProtoSyncMessageCallEventEvent) {
        proto.event = SSKProtoSyncMessageCallEventEventUnwrap(valueParam)
    }

    public func setUnknownFields(_ unknownFields: SwiftProtobuf.UnknownStorage) {
        proto.unknownFields = unknownFields
    }

    @objc
    public func build() throws -> SSKProtoSyncMessageCallEvent {
        return SSKProtoSyncMessageCallEvent(proto)
    }

    @objc
    public func buildInfallibly() -> SSKProtoSyncMessageCallEvent {
        return SSKProtoSyncMessageCallEvent(proto)
    }

    @objc
    public func buildSerializedData() throws -> Data {
        return try SSKProtoSyncMessageCallEvent(proto).serializedData()
    }
}

#if TESTABLE_BUILD

extension SSKProtoSyncMessageCallEvent {
    @objc
    public func serializedDataIgnoringErrors() -> Data? {
        return try! self.serializedData()
    }
}

extension SSKProtoSyncMessageCallEventBuilder {
    @objc
    public func buildIgnoringErrors() -> SSKProtoSyncMessageCallEvent? {
        return self.buildInfallibly()
    }
}

#endif

// MARK: - SSKProtoSyncMessagePniChangeNumber

@objc
public class SSKProtoSyncMessagePniChangeNumber: NSObject, Codable, NSSecureCoding {

    fileprivate let proto: SignalServiceProtos_SyncMessage.PniChangeNumber

    @objc
    public var identityKeyPair: Data? {
        guard hasIdentityKeyPair else {
            return nil
        }
        return proto.identityKeyPair
    }
    @objc
    public var hasIdentityKeyPair: Bool {
        return proto.hasIdentityKeyPair
    }

    @objc
    public var signedPreKey: Data? {
        guard hasSignedPreKey else {
            return nil
        }
        return proto.signedPreKey
    }
    @objc
    public var hasSignedPreKey: Bool {
        return proto.hasSignedPreKey
    }

    @objc
    public var lastResortKyberPreKey: Data? {
        guard hasLastResortKyberPreKey else {
            return nil
        }
        return proto.lastResortKyberPreKey
    }
    @objc
    public var hasLastResortKyberPreKey: Bool {
        return proto.hasLastResortKyberPreKey
    }

    @objc
    public var registrationID: UInt32 {
        return proto.registrationID
    }
    @objc
    public var hasRegistrationID: Bool {
        return proto.hasRegistrationID
    }

    @objc
    public var newE164: String? {
        guard hasNewE164 else {
            return nil
        }
        return proto.newE164
    }
    @objc
    public var hasNewE164: Bool {
        return proto.hasNewE164 && !proto.newE164.isEmpty
    }

    public var hasUnknownFields: Bool {
        return !proto.unknownFields.data.isEmpty
    }
    public var unknownFields: SwiftProtobuf.UnknownStorage? {
        guard hasUnknownFields else { return nil }
        return proto.unknownFields
    }

    private init(proto: SignalServiceProtos_SyncMessage.PniChangeNumber) {
        self.proto = proto
    }

    @objc
    public func serializedData() throws -> Data {
        return try self.proto.serializedData()
    }

    @objc
    public convenience init(serializedData: Data) throws {
        let proto = try SignalServiceProtos_SyncMessage.PniChangeNumber(serializedData: serializedData)
        self.init(proto)
    }

    fileprivate convenience init(_ proto: SignalServiceProtos_SyncMessage.PniChangeNumber) {
        self.init(proto: proto)
    }

    public required convenience init(from decoder: Swift.Decoder) throws {
        let singleValueContainer = try decoder.singleValueContainer()
        let serializedData = try singleValueContainer.decode(Data.self)
        try self.init(serializedData: serializedData)
    }
    public func encode(to encoder: Swift.Encoder) throws {
        var singleValueContainer = encoder.singleValueContainer()
        try singleValueContainer.encode(try serializedData())
    }

    public static var supportsSecureCoding: Bool { true }

    public required convenience init?(coder: NSCoder) {
        guard let serializedData = coder.decodeData() else { return nil }
        do {
            try self.init(serializedData: serializedData)
        } catch {
            owsFailDebug("Failed to decode serialized data \(error)")
            return nil
        }
    }

    public func encode(with coder: NSCoder) {
        do {
            coder.encode(try serializedData())
        } catch {
            owsFailDebug("Failed to encode serialized data \(error)")
        }
    }

    @objc
    public override var debugDescription: String {
        return "\(proto)"
    }
}

extension SSKProtoSyncMessagePniChangeNumber {
    @objc
    public static func builder() -> SSKProtoSyncMessagePniChangeNumberBuilder {
        return SSKProtoSyncMessagePniChangeNumberBuilder()
    }

    // asBuilder() constructs a builder that reflects the proto's contents.
    @objc
    public func asBuilder() -> SSKProtoSyncMessagePniChangeNumberBuilder {
        let builder = SSKProtoSyncMessagePniChangeNumberBuilder()
        if let _value = identityKeyPair {
            builder.setIdentityKeyPair(_value)
        }
        if let _value = signedPreKey {
            builder.setSignedPreKey(_value)
        }
        if let _value = lastResortKyberPreKey {
            builder.setLastResortKyberPreKey(_value)
        }
        if hasRegistrationID {
            builder.setRegistrationID(registrationID)
        }
        if let _value = newE164 {
            builder.setNewE164(_value)
        }
        if let _value = unknownFields {
            builder.setUnknownFields(_value)
        }
        return builder
    }
}

@objc
public class SSKProtoSyncMessagePniChangeNumberBuilder: NSObject {

    private var proto = SignalServiceProtos_SyncMessage.PniChangeNumber()

    @objc
    fileprivate override init() {}

    @objc
    @available(swift, obsoleted: 1.0)
    public func setIdentityKeyPair(_ valueParam: Data?) {
        guard let valueParam = valueParam else { return }
        proto.identityKeyPair = valueParam
    }

    public func setIdentityKeyPair(_ valueParam: Data) {
        proto.identityKeyPair = valueParam
    }

    @objc
    @available(swift, obsoleted: 1.0)
    public func setSignedPreKey(_ valueParam: Data?) {
        guard let valueParam = valueParam else { return }
        proto.signedPreKey = valueParam
    }

    public func setSignedPreKey(_ valueParam: Data) {
        proto.signedPreKey = valueParam
    }

    @objc
    @available(swift, obsoleted: 1.0)
    public func setLastResortKyberPreKey(_ valueParam: Data?) {
        guard let valueParam = valueParam else { return }
        proto.lastResortKyberPreKey = valueParam
    }

    public func setLastResortKyberPreKey(_ valueParam: Data) {
        proto.lastResortKyberPreKey = valueParam
    }

    @objc
    public func setRegistrationID(_ valueParam: UInt32) {
        proto.registrationID = valueParam
    }

    @objc
    @available(swift, obsoleted: 1.0)
    public func setNewE164(_ valueParam: String?) {
        guard let valueParam = valueParam else { return }
        if let valueParam = valueParam.nilIfEmpty {
            owsAssertDebug(valueParam.isStructurallyValidE164)
        }

        proto.newE164 = valueParam
    }

    public func setNewE164(_ valueParam: String) {
        if let valueParam = valueParam.nilIfEmpty {
            owsAssertDebug(valueParam.isStructurallyValidE164)
        }

        proto.newE164 = valueParam
    }

    public func setUnknownFields(_ unknownFields: SwiftProtobuf.UnknownStorage) {
        proto.unknownFields = unknownFields
    }

    @objc
    public func build() throws -> SSKProtoSyncMessagePniChangeNumber {
        return SSKProtoSyncMessagePniChangeNumber(proto)
    }

    @objc
    public func buildInfallibly() -> SSKProtoSyncMessagePniChangeNumber {
        return SSKProtoSyncMessagePniChangeNumber(proto)
    }

    @objc
    public func buildSerializedData() throws -> Data {
        return try SSKProtoSyncMessagePniChangeNumber(proto).serializedData()
    }
}

#if TESTABLE_BUILD

extension SSKProtoSyncMessagePniChangeNumber {
    @objc
    public func serializedDataIgnoringErrors() -> Data? {
        return try! self.serializedData()
    }
}

extension SSKProtoSyncMessagePniChangeNumberBuilder {
    @objc
    public func buildIgnoringErrors() -> SSKProtoSyncMessagePniChangeNumber? {
        return self.buildInfallibly()
    }
}

#endif

// MARK: - SSKProtoSyncMessage

@objc
public class SSKProtoSyncMessage: NSObject, Codable, NSSecureCoding {

    fileprivate let proto: SignalServiceProtos_SyncMessage

    @objc
    public let sent: SSKProtoSyncMessageSent?

    @objc
    public let contacts: SSKProtoSyncMessageContacts?

    @objc
    public let request: SSKProtoSyncMessageRequest?

    @objc
    public let read: [SSKProtoSyncMessageRead]

    @objc
    public let blocked: SSKProtoSyncMessageBlocked?

    @objc
    public let verified: SSKProtoVerified?

    @objc
    public let configuration: SSKProtoSyncMessageConfiguration?

    @objc
    public let stickerPackOperation: [SSKProtoSyncMessageStickerPackOperation]

    @objc
    public let viewOnceOpen: SSKProtoSyncMessageViewOnceOpen?

    @objc
    public let fetchLatest: SSKProtoSyncMessageFetchLatest?

    @objc
    public let keys: SSKProtoSyncMessageKeys?

    @objc
    public let messageRequestResponse: SSKProtoSyncMessageMessageRequestResponse?

    @objc
    public let outgoingPayment: SSKProtoSyncMessageOutgoingPayment?

    @objc
    public let viewed: [SSKProtoSyncMessageViewed]

    @objc
    public let pniChangeNumber: SSKProtoSyncMessagePniChangeNumber?

    @objc
    public let callEvent: SSKProtoSyncMessageCallEvent?

    @objc
    public var padding: Data? {
        guard hasPadding else {
            return nil
        }
        return proto.padding
    }
    @objc
    public var hasPadding: Bool {
        return proto.hasPadding
    }

    public var hasUnknownFields: Bool {
        return !proto.unknownFields.data.isEmpty
    }
    public var unknownFields: SwiftProtobuf.UnknownStorage? {
        guard hasUnknownFields else { return nil }
        return proto.unknownFields
    }

    private init(proto: SignalServiceProtos_SyncMessage,
                 sent: SSKProtoSyncMessageSent?,
                 contacts: SSKProtoSyncMessageContacts?,
                 request: SSKProtoSyncMessageRequest?,
                 read: [SSKProtoSyncMessageRead],
                 blocked: SSKProtoSyncMessageBlocked?,
                 verified: SSKProtoVerified?,
                 configuration: SSKProtoSyncMessageConfiguration?,
                 stickerPackOperation: [SSKProtoSyncMessageStickerPackOperation],
                 viewOnceOpen: SSKProtoSyncMessageViewOnceOpen?,
                 fetchLatest: SSKProtoSyncMessageFetchLatest?,
                 keys: SSKProtoSyncMessageKeys?,
                 messageRequestResponse: SSKProtoSyncMessageMessageRequestResponse?,
                 outgoingPayment: SSKProtoSyncMessageOutgoingPayment?,
                 viewed: [SSKProtoSyncMessageViewed],
                 pniChangeNumber: SSKProtoSyncMessagePniChangeNumber?,
                 callEvent: SSKProtoSyncMessageCallEvent?) {
        self.proto = proto
        self.sent = sent
        self.contacts = contacts
        self.request = request
        self.read = read
        self.blocked = blocked
        self.verified = verified
        self.configuration = configuration
        self.stickerPackOperation = stickerPackOperation
        self.viewOnceOpen = viewOnceOpen
        self.fetchLatest = fetchLatest
        self.keys = keys
        self.messageRequestResponse = messageRequestResponse
        self.outgoingPayment = outgoingPayment
        self.viewed = viewed
        self.pniChangeNumber = pniChangeNumber
        self.callEvent = callEvent
    }

    @objc
    public func serializedData() throws -> Data {
        return try self.proto.serializedData()
    }

    @objc
    public convenience init(serializedData: Data) throws {
        let proto = try SignalServiceProtos_SyncMessage(serializedData: serializedData)
        try self.init(proto)
    }

    fileprivate convenience init(_ proto: SignalServiceProtos_SyncMessage) throws {
        var sent: SSKProtoSyncMessageSent?
        if proto.hasSent {
            sent = try SSKProtoSyncMessageSent(proto.sent)
        }

        var contacts: SSKProtoSyncMessageContacts?
        if proto.hasContacts {
            contacts = try SSKProtoSyncMessageContacts(proto.contacts)
        }

        var request: SSKProtoSyncMessageRequest?
        if proto.hasRequest {
            request = SSKProtoSyncMessageRequest(proto.request)
        }

        var read: [SSKProtoSyncMessageRead] = []
        read = try proto.read.map { try SSKProtoSyncMessageRead($0) }

        var blocked: SSKProtoSyncMessageBlocked?
        if proto.hasBlocked {
            blocked = SSKProtoSyncMessageBlocked(proto.blocked)
        }

        var verified: SSKProtoVerified?
        if proto.hasVerified {
            verified = SSKProtoVerified(proto.verified)
        }

        var configuration: SSKProtoSyncMessageConfiguration?
        if proto.hasConfiguration {
            configuration = SSKProtoSyncMessageConfiguration(proto.configuration)
        }

        var stickerPackOperation: [SSKProtoSyncMessageStickerPackOperation] = []
        stickerPackOperation = try proto.stickerPackOperation.map { try SSKProtoSyncMessageStickerPackOperation($0) }

        var viewOnceOpen: SSKProtoSyncMessageViewOnceOpen?
        if proto.hasViewOnceOpen {
            viewOnceOpen = try SSKProtoSyncMessageViewOnceOpen(proto.viewOnceOpen)
        }

        var fetchLatest: SSKProtoSyncMessageFetchLatest?
        if proto.hasFetchLatest {
            fetchLatest = SSKProtoSyncMessageFetchLatest(proto.fetchLatest)
        }

        var keys: SSKProtoSyncMessageKeys?
        if proto.hasKeys {
            keys = SSKProtoSyncMessageKeys(proto.keys)
        }

        var messageRequestResponse: SSKProtoSyncMessageMessageRequestResponse?
        if proto.hasMessageRequestResponse {
            messageRequestResponse = SSKProtoSyncMessageMessageRequestResponse(proto.messageRequestResponse)
        }

        var outgoingPayment: SSKProtoSyncMessageOutgoingPayment?
        if proto.hasOutgoingPayment {
            outgoingPayment = try SSKProtoSyncMessageOutgoingPayment(proto.outgoingPayment)
        }

        var viewed: [SSKProtoSyncMessageViewed] = []
        viewed = try proto.viewed.map { try SSKProtoSyncMessageViewed($0) }

        var pniChangeNumber: SSKProtoSyncMessagePniChangeNumber?
        if proto.hasPniChangeNumber {
            pniChangeNumber = SSKProtoSyncMessagePniChangeNumber(proto.pniChangeNumber)
        }

        var callEvent: SSKProtoSyncMessageCallEvent?
        if proto.hasCallEvent {
            callEvent = SSKProtoSyncMessageCallEvent(proto.callEvent)
        }

        self.init(proto: proto,
                  sent: sent,
                  contacts: contacts,
                  request: request,
                  read: read,
                  blocked: blocked,
                  verified: verified,
                  configuration: configuration,
                  stickerPackOperation: stickerPackOperation,
                  viewOnceOpen: viewOnceOpen,
                  fetchLatest: fetchLatest,
                  keys: keys,
                  messageRequestResponse: messageRequestResponse,
                  outgoingPayment: outgoingPayment,
                  viewed: viewed,
                  pniChangeNumber: pniChangeNumber,
                  callEvent: callEvent)
    }

    public required convenience init(from decoder: Swift.Decoder) throws {
        let singleValueContainer = try decoder.singleValueContainer()
        let serializedData = try singleValueContainer.decode(Data.self)
        try self.init(serializedData: serializedData)
    }
    public func encode(to encoder: Swift.Encoder) throws {
        var singleValueContainer = encoder.singleValueContainer()
        try singleValueContainer.encode(try serializedData())
    }

    public static var supportsSecureCoding: Bool { true }

    public required convenience init?(coder: NSCoder) {
        guard let serializedData = coder.decodeData() else { return nil }
        do {
            try self.init(serializedData: serializedData)
        } catch {
            owsFailDebug("Failed to decode serialized data \(error)")
            return nil
        }
    }

    public func encode(with coder: NSCoder) {
        do {
            coder.encode(try serializedData())
        } catch {
            owsFailDebug("Failed to encode serialized data \(error)")
        }
    }

    @objc
    public override var debugDescription: String {
        return "\(proto)"
    }
}

extension SSKProtoSyncMessage {
    @objc
    public static func builder() -> SSKProtoSyncMessageBuilder {
        return SSKProtoSyncMessageBuilder()
    }

    // asBuilder() constructs a builder that reflects the proto's contents.
    @objc
    public func asBuilder() -> SSKProtoSyncMessageBuilder {
        let builder = SSKProtoSyncMessageBuilder()
        if let _value = sent {
            builder.setSent(_value)
        }
        if let _value = contacts {
            builder.setContacts(_value)
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
        if let _value = viewOnceOpen {
            builder.setViewOnceOpen(_value)
        }
        if let _value = fetchLatest {
            builder.setFetchLatest(_value)
        }
        if let _value = keys {
            builder.setKeys(_value)
        }
        if let _value = messageRequestResponse {
            builder.setMessageRequestResponse(_value)
        }
        if let _value = outgoingPayment {
            builder.setOutgoingPayment(_value)
        }
        builder.setViewed(viewed)
        if let _value = pniChangeNumber {
            builder.setPniChangeNumber(_value)
        }
        if let _value = callEvent {
            builder.setCallEvent(_value)
        }
        if let _value = unknownFields {
            builder.setUnknownFields(_value)
        }
        return builder
    }
}

@objc
public class SSKProtoSyncMessageBuilder: NSObject {

    private var proto = SignalServiceProtos_SyncMessage()

    @objc
    fileprivate override init() {}

    @objc
    @available(swift, obsoleted: 1.0)
    public func setSent(_ valueParam: SSKProtoSyncMessageSent?) {
        guard let valueParam = valueParam else { return }
        proto.sent = valueParam.proto
    }

    public func setSent(_ valueParam: SSKProtoSyncMessageSent) {
        proto.sent = valueParam.proto
    }

    @objc
    @available(swift, obsoleted: 1.0)
    public func setContacts(_ valueParam: SSKProtoSyncMessageContacts?) {
        guard let valueParam = valueParam else { return }
        proto.contacts = valueParam.proto
    }

    public func setContacts(_ valueParam: SSKProtoSyncMessageContacts) {
        proto.contacts = valueParam.proto
    }

    @objc
    @available(swift, obsoleted: 1.0)
    public func setRequest(_ valueParam: SSKProtoSyncMessageRequest?) {
        guard let valueParam = valueParam else { return }
        proto.request = valueParam.proto
    }

    public func setRequest(_ valueParam: SSKProtoSyncMessageRequest) {
        proto.request = valueParam.proto
    }

    @objc
    public func addRead(_ valueParam: SSKProtoSyncMessageRead) {
        proto.read.append(valueParam.proto)
    }

    @objc
    public func setRead(_ wrappedItems: [SSKProtoSyncMessageRead]) {
        proto.read = wrappedItems.map { $0.proto }
    }

    @objc
    @available(swift, obsoleted: 1.0)
    public func setBlocked(_ valueParam: SSKProtoSyncMessageBlocked?) {
        guard let valueParam = valueParam else { return }
        proto.blocked = valueParam.proto
    }

    public func setBlocked(_ valueParam: SSKProtoSyncMessageBlocked) {
        proto.blocked = valueParam.proto
    }

    @objc
    @available(swift, obsoleted: 1.0)
    public func setVerified(_ valueParam: SSKProtoVerified?) {
        guard let valueParam = valueParam else { return }
        proto.verified = valueParam.proto
    }

    public func setVerified(_ valueParam: SSKProtoVerified) {
        proto.verified = valueParam.proto
    }

    @objc
    @available(swift, obsoleted: 1.0)
    public func setConfiguration(_ valueParam: SSKProtoSyncMessageConfiguration?) {
        guard let valueParam = valueParam else { return }
        proto.configuration = valueParam.proto
    }

    public func setConfiguration(_ valueParam: SSKProtoSyncMessageConfiguration) {
        proto.configuration = valueParam.proto
    }

    @objc
    @available(swift, obsoleted: 1.0)
    public func setPadding(_ valueParam: Data?) {
        guard let valueParam = valueParam else { return }
        proto.padding = valueParam
    }

    public func setPadding(_ valueParam: Data) {
        proto.padding = valueParam
    }

    @objc
    public func addStickerPackOperation(_ valueParam: SSKProtoSyncMessageStickerPackOperation) {
        proto.stickerPackOperation.append(valueParam.proto)
    }

    @objc
    public func setStickerPackOperation(_ wrappedItems: [SSKProtoSyncMessageStickerPackOperation]) {
        proto.stickerPackOperation = wrappedItems.map { $0.proto }
    }

    @objc
    @available(swift, obsoleted: 1.0)
    public func setViewOnceOpen(_ valueParam: SSKProtoSyncMessageViewOnceOpen?) {
        guard let valueParam = valueParam else { return }
        proto.viewOnceOpen = valueParam.proto
    }

    public func setViewOnceOpen(_ valueParam: SSKProtoSyncMessageViewOnceOpen) {
        proto.viewOnceOpen = valueParam.proto
    }

    @objc
    @available(swift, obsoleted: 1.0)
    public func setFetchLatest(_ valueParam: SSKProtoSyncMessageFetchLatest?) {
        guard let valueParam = valueParam else { return }
        proto.fetchLatest = valueParam.proto
    }

    public func setFetchLatest(_ valueParam: SSKProtoSyncMessageFetchLatest) {
        proto.fetchLatest = valueParam.proto
    }

    @objc
    @available(swift, obsoleted: 1.0)
    public func setKeys(_ valueParam: SSKProtoSyncMessageKeys?) {
        guard let valueParam = valueParam else { return }
        proto.keys = valueParam.proto
    }

    public func setKeys(_ valueParam: SSKProtoSyncMessageKeys) {
        proto.keys = valueParam.proto
    }

    @objc
    @available(swift, obsoleted: 1.0)
    public func setMessageRequestResponse(_ valueParam: SSKProtoSyncMessageMessageRequestResponse?) {
        guard let valueParam = valueParam else { return }
        proto.messageRequestResponse = valueParam.proto
    }

    public func setMessageRequestResponse(_ valueParam: SSKProtoSyncMessageMessageRequestResponse) {
        proto.messageRequestResponse = valueParam.proto
    }

    @objc
    @available(swift, obsoleted: 1.0)
    public func setOutgoingPayment(_ valueParam: SSKProtoSyncMessageOutgoingPayment?) {
        guard let valueParam = valueParam else { return }
        proto.outgoingPayment = valueParam.proto
    }

    public func setOutgoingPayment(_ valueParam: SSKProtoSyncMessageOutgoingPayment) {
        proto.outgoingPayment = valueParam.proto
    }

    @objc
    public func addViewed(_ valueParam: SSKProtoSyncMessageViewed) {
        proto.viewed.append(valueParam.proto)
    }

    @objc
    public func setViewed(_ wrappedItems: [SSKProtoSyncMessageViewed]) {
        proto.viewed = wrappedItems.map { $0.proto }
    }

    @objc
    @available(swift, obsoleted: 1.0)
    public func setPniChangeNumber(_ valueParam: SSKProtoSyncMessagePniChangeNumber?) {
        guard let valueParam = valueParam else { return }
        proto.pniChangeNumber = valueParam.proto
    }

    public func setPniChangeNumber(_ valueParam: SSKProtoSyncMessagePniChangeNumber) {
        proto.pniChangeNumber = valueParam.proto
    }

    @objc
    @available(swift, obsoleted: 1.0)
    public func setCallEvent(_ valueParam: SSKProtoSyncMessageCallEvent?) {
        guard let valueParam = valueParam else { return }
        proto.callEvent = valueParam.proto
    }

    public func setCallEvent(_ valueParam: SSKProtoSyncMessageCallEvent) {
        proto.callEvent = valueParam.proto
    }

    public func setUnknownFields(_ unknownFields: SwiftProtobuf.UnknownStorage) {
        proto.unknownFields = unknownFields
    }

    @objc
    public func build() throws -> SSKProtoSyncMessage {
        return try SSKProtoSyncMessage(proto)
    }

    @objc
    public func buildSerializedData() throws -> Data {
        return try SSKProtoSyncMessage(proto).serializedData()
    }
}

#if TESTABLE_BUILD

extension SSKProtoSyncMessage {
    @objc
    public func serializedDataIgnoringErrors() -> Data? {
        return try! self.serializedData()
    }
}

extension SSKProtoSyncMessageBuilder {
    @objc
    public func buildIgnoringErrors() -> SSKProtoSyncMessage? {
        return try! self.build()
    }
}

#endif

// MARK: - SSKProtoAttachmentPointerFlags

@objc
public enum SSKProtoAttachmentPointerFlags: Int32 {
    case voiceMessage = 1
    case borderless = 2
    case gif = 8
}

private func SSKProtoAttachmentPointerFlagsWrap(_ value: SignalServiceProtos_AttachmentPointer.Flags) -> SSKProtoAttachmentPointerFlags {
    switch value {
    case .voiceMessage: return .voiceMessage
    case .borderless: return .borderless
    case .gif: return .gif
    }
}

private func SSKProtoAttachmentPointerFlagsUnwrap(_ value: SSKProtoAttachmentPointerFlags) -> SignalServiceProtos_AttachmentPointer.Flags {
    switch value {
    case .voiceMessage: return .voiceMessage
    case .borderless: return .borderless
    case .gif: return .gif
    }
}

// MARK: - SSKProtoAttachmentPointer

@objc
public class SSKProtoAttachmentPointer: NSObject, Codable, NSSecureCoding {

    fileprivate let proto: SignalServiceProtos_AttachmentPointer

    @objc
    public var cdnID: UInt64 {
        return proto.cdnID
    }
    @objc
    public var hasCdnID: Bool {
        return proto.hasCdnID
    }

    @objc
    public var cdnKey: String? {
        guard hasCdnKey else {
            return nil
        }
        return proto.cdnKey
    }
    @objc
    public var hasCdnKey: Bool {
        return proto.hasCdnKey
    }

    @objc
    public var contentType: String? {
        guard hasContentType else {
            return nil
        }
        return proto.contentType
    }
    @objc
    public var hasContentType: Bool {
        return proto.hasContentType
    }

    @objc
    public var key: Data? {
        guard hasKey else {
            return nil
        }
        return proto.key
    }
    @objc
    public var hasKey: Bool {
        return proto.hasKey
    }

    @objc
    public var size: UInt32 {
        return proto.size
    }
    @objc
    public var hasSize: Bool {
        return proto.hasSize
    }

    @objc
    public var thumbnail: Data? {
        guard hasThumbnail else {
            return nil
        }
        return proto.thumbnail
    }
    @objc
    public var hasThumbnail: Bool {
        return proto.hasThumbnail
    }

    @objc
    public var digest: Data? {
        guard hasDigest else {
            return nil
        }
        return proto.digest
    }
    @objc
    public var hasDigest: Bool {
        return proto.hasDigest
    }

    @objc
    public var fileName: String? {
        guard hasFileName else {
            return nil
        }
        return proto.fileName
    }
    @objc
    public var hasFileName: Bool {
        return proto.hasFileName
    }

    @objc
    public var flags: UInt32 {
        return proto.flags
    }
    @objc
    public var hasFlags: Bool {
        return proto.hasFlags
    }

    @objc
    public var width: UInt32 {
        return proto.width
    }
    @objc
    public var hasWidth: Bool {
        return proto.hasWidth
    }

    @objc
    public var height: UInt32 {
        return proto.height
    }
    @objc
    public var hasHeight: Bool {
        return proto.hasHeight
    }

    @objc
    public var caption: String? {
        guard hasCaption else {
            return nil
        }
        return proto.caption
    }
    @objc
    public var hasCaption: Bool {
        return proto.hasCaption
    }

    @objc
    public var blurHash: String? {
        guard hasBlurHash else {
            return nil
        }
        return proto.blurHash
    }
    @objc
    public var hasBlurHash: Bool {
        return proto.hasBlurHash
    }

    @objc
    public var uploadTimestamp: UInt64 {
        return proto.uploadTimestamp
    }
    @objc
    public var hasUploadTimestamp: Bool {
        return proto.hasUploadTimestamp
    }

    @objc
    public var cdnNumber: UInt32 {
        return proto.cdnNumber
    }
    @objc
    public var hasCdnNumber: Bool {
        return proto.hasCdnNumber
    }

    public var hasUnknownFields: Bool {
        return !proto.unknownFields.data.isEmpty
    }
    public var unknownFields: SwiftProtobuf.UnknownStorage? {
        guard hasUnknownFields else { return nil }
        return proto.unknownFields
    }

    private init(proto: SignalServiceProtos_AttachmentPointer) {
        self.proto = proto
    }

    @objc
    public func serializedData() throws -> Data {
        return try self.proto.serializedData()
    }

    @objc
    public convenience init(serializedData: Data) throws {
        let proto = try SignalServiceProtos_AttachmentPointer(serializedData: serializedData)
        self.init(proto)
    }

    fileprivate convenience init(_ proto: SignalServiceProtos_AttachmentPointer) {
        self.init(proto: proto)
    }

    public required convenience init(from decoder: Swift.Decoder) throws {
        let singleValueContainer = try decoder.singleValueContainer()
        let serializedData = try singleValueContainer.decode(Data.self)
        try self.init(serializedData: serializedData)
    }
    public func encode(to encoder: Swift.Encoder) throws {
        var singleValueContainer = encoder.singleValueContainer()
        try singleValueContainer.encode(try serializedData())
    }

    public static var supportsSecureCoding: Bool { true }

    public required convenience init?(coder: NSCoder) {
        guard let serializedData = coder.decodeData() else { return nil }
        do {
            try self.init(serializedData: serializedData)
        } catch {
            owsFailDebug("Failed to decode serialized data \(error)")
            return nil
        }
    }

    public func encode(with coder: NSCoder) {
        do {
            coder.encode(try serializedData())
        } catch {
            owsFailDebug("Failed to encode serialized data \(error)")
        }
    }

    @objc
    public override var debugDescription: String {
        return "\(proto)"
    }
}

extension SSKProtoAttachmentPointer {
    @objc
    public static func builder() -> SSKProtoAttachmentPointerBuilder {
        return SSKProtoAttachmentPointerBuilder()
    }

    // asBuilder() constructs a builder that reflects the proto's contents.
    @objc
    public func asBuilder() -> SSKProtoAttachmentPointerBuilder {
        let builder = SSKProtoAttachmentPointerBuilder()
        if hasCdnID {
            builder.setCdnID(cdnID)
        }
        if let _value = cdnKey {
            builder.setCdnKey(_value)
        }
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
        if let _value = blurHash {
            builder.setBlurHash(_value)
        }
        if hasUploadTimestamp {
            builder.setUploadTimestamp(uploadTimestamp)
        }
        if hasCdnNumber {
            builder.setCdnNumber(cdnNumber)
        }
        if let _value = unknownFields {
            builder.setUnknownFields(_value)
        }
        return builder
    }
}

@objc
public class SSKProtoAttachmentPointerBuilder: NSObject {

    private var proto = SignalServiceProtos_AttachmentPointer()

    @objc
    fileprivate override init() {}

    @objc
    public func setCdnID(_ valueParam: UInt64) {
        proto.cdnID = valueParam
    }

    @objc
    @available(swift, obsoleted: 1.0)
    public func setCdnKey(_ valueParam: String?) {
        guard let valueParam = valueParam else { return }
        proto.cdnKey = valueParam
    }

    public func setCdnKey(_ valueParam: String) {
        proto.cdnKey = valueParam
    }

    @objc
    @available(swift, obsoleted: 1.0)
    public func setContentType(_ valueParam: String?) {
        guard let valueParam = valueParam else { return }
        proto.contentType = valueParam
    }

    public func setContentType(_ valueParam: String) {
        proto.contentType = valueParam
    }

    @objc
    @available(swift, obsoleted: 1.0)
    public func setKey(_ valueParam: Data?) {
        guard let valueParam = valueParam else { return }
        proto.key = valueParam
    }

    public func setKey(_ valueParam: Data) {
        proto.key = valueParam
    }

    @objc
    public func setSize(_ valueParam: UInt32) {
        proto.size = valueParam
    }

    @objc
    @available(swift, obsoleted: 1.0)
    public func setThumbnail(_ valueParam: Data?) {
        guard let valueParam = valueParam else { return }
        proto.thumbnail = valueParam
    }

    public func setThumbnail(_ valueParam: Data) {
        proto.thumbnail = valueParam
    }

    @objc
    @available(swift, obsoleted: 1.0)
    public func setDigest(_ valueParam: Data?) {
        guard let valueParam = valueParam else { return }
        proto.digest = valueParam
    }

    public func setDigest(_ valueParam: Data) {
        proto.digest = valueParam
    }

    @objc
    @available(swift, obsoleted: 1.0)
    public func setFileName(_ valueParam: String?) {
        guard let valueParam = valueParam else { return }
        proto.fileName = valueParam
    }

    public func setFileName(_ valueParam: String) {
        proto.fileName = valueParam
    }

    @objc
    public func setFlags(_ valueParam: UInt32) {
        proto.flags = valueParam
    }

    @objc
    public func setWidth(_ valueParam: UInt32) {
        proto.width = valueParam
    }

    @objc
    public func setHeight(_ valueParam: UInt32) {
        proto.height = valueParam
    }

    @objc
    @available(swift, obsoleted: 1.0)
    public func setCaption(_ valueParam: String?) {
        guard let valueParam = valueParam else { return }
        proto.caption = valueParam
    }

    public func setCaption(_ valueParam: String) {
        proto.caption = valueParam
    }

    @objc
    @available(swift, obsoleted: 1.0)
    public func setBlurHash(_ valueParam: String?) {
        guard let valueParam = valueParam else { return }
        proto.blurHash = valueParam
    }

    public func setBlurHash(_ valueParam: String) {
        proto.blurHash = valueParam
    }

    @objc
    public func setUploadTimestamp(_ valueParam: UInt64) {
        proto.uploadTimestamp = valueParam
    }

    @objc
    public func setCdnNumber(_ valueParam: UInt32) {
        proto.cdnNumber = valueParam
    }

    public func setUnknownFields(_ unknownFields: SwiftProtobuf.UnknownStorage) {
        proto.unknownFields = unknownFields
    }

    @objc
    public func build() throws -> SSKProtoAttachmentPointer {
        return SSKProtoAttachmentPointer(proto)
    }

    @objc
    public func buildInfallibly() -> SSKProtoAttachmentPointer {
        return SSKProtoAttachmentPointer(proto)
    }

    @objc
    public func buildSerializedData() throws -> Data {
        return try SSKProtoAttachmentPointer(proto).serializedData()
    }
}

#if TESTABLE_BUILD

extension SSKProtoAttachmentPointer {
    @objc
    public func serializedDataIgnoringErrors() -> Data? {
        return try! self.serializedData()
    }
}

extension SSKProtoAttachmentPointerBuilder {
    @objc
    public func buildIgnoringErrors() -> SSKProtoAttachmentPointer? {
        return self.buildInfallibly()
    }
}

#endif

// MARK: - SSKProtoGroupContextV2

@objc
public class SSKProtoGroupContextV2: NSObject, Codable, NSSecureCoding {

    fileprivate let proto: SignalServiceProtos_GroupContextV2

    @objc
    public var masterKey: Data? {
        guard hasMasterKey else {
            return nil
        }
        return proto.masterKey
    }
    @objc
    public var hasMasterKey: Bool {
        return proto.hasMasterKey
    }

    @objc
    public var revision: UInt32 {
        return proto.revision
    }
    @objc
    public var hasRevision: Bool {
        return proto.hasRevision
    }

    @objc
    public var groupChange: Data? {
        guard hasGroupChange else {
            return nil
        }
        return proto.groupChange
    }
    @objc
    public var hasGroupChange: Bool {
        return proto.hasGroupChange
    }

    public var hasUnknownFields: Bool {
        return !proto.unknownFields.data.isEmpty
    }
    public var unknownFields: SwiftProtobuf.UnknownStorage? {
        guard hasUnknownFields else { return nil }
        return proto.unknownFields
    }

    private init(proto: SignalServiceProtos_GroupContextV2) {
        self.proto = proto
    }

    @objc
    public func serializedData() throws -> Data {
        return try self.proto.serializedData()
    }

    @objc
    public convenience init(serializedData: Data) throws {
        let proto = try SignalServiceProtos_GroupContextV2(serializedData: serializedData)
        self.init(proto)
    }

    fileprivate convenience init(_ proto: SignalServiceProtos_GroupContextV2) {
        self.init(proto: proto)
    }

    public required convenience init(from decoder: Swift.Decoder) throws {
        let singleValueContainer = try decoder.singleValueContainer()
        let serializedData = try singleValueContainer.decode(Data.self)
        try self.init(serializedData: serializedData)
    }
    public func encode(to encoder: Swift.Encoder) throws {
        var singleValueContainer = encoder.singleValueContainer()
        try singleValueContainer.encode(try serializedData())
    }

    public static var supportsSecureCoding: Bool { true }

    public required convenience init?(coder: NSCoder) {
        guard let serializedData = coder.decodeData() else { return nil }
        do {
            try self.init(serializedData: serializedData)
        } catch {
            owsFailDebug("Failed to decode serialized data \(error)")
            return nil
        }
    }

    public func encode(with coder: NSCoder) {
        do {
            coder.encode(try serializedData())
        } catch {
            owsFailDebug("Failed to encode serialized data \(error)")
        }
    }

    @objc
    public override var debugDescription: String {
        return "\(proto)"
    }
}

extension SSKProtoGroupContextV2 {
    @objc
    public static func builder() -> SSKProtoGroupContextV2Builder {
        return SSKProtoGroupContextV2Builder()
    }

    // asBuilder() constructs a builder that reflects the proto's contents.
    @objc
    public func asBuilder() -> SSKProtoGroupContextV2Builder {
        let builder = SSKProtoGroupContextV2Builder()
        if let _value = masterKey {
            builder.setMasterKey(_value)
        }
        if hasRevision {
            builder.setRevision(revision)
        }
        if let _value = groupChange {
            builder.setGroupChange(_value)
        }
        if let _value = unknownFields {
            builder.setUnknownFields(_value)
        }
        return builder
    }
}

@objc
public class SSKProtoGroupContextV2Builder: NSObject {

    private var proto = SignalServiceProtos_GroupContextV2()

    @objc
    fileprivate override init() {}

    @objc
    @available(swift, obsoleted: 1.0)
    public func setMasterKey(_ valueParam: Data?) {
        guard let valueParam = valueParam else { return }
        proto.masterKey = valueParam
    }

    public func setMasterKey(_ valueParam: Data) {
        proto.masterKey = valueParam
    }

    @objc
    public func setRevision(_ valueParam: UInt32) {
        proto.revision = valueParam
    }

    @objc
    @available(swift, obsoleted: 1.0)
    public func setGroupChange(_ valueParam: Data?) {
        guard let valueParam = valueParam else { return }
        proto.groupChange = valueParam
    }

    public func setGroupChange(_ valueParam: Data) {
        proto.groupChange = valueParam
    }

    public func setUnknownFields(_ unknownFields: SwiftProtobuf.UnknownStorage) {
        proto.unknownFields = unknownFields
    }

    @objc
    public func build() throws -> SSKProtoGroupContextV2 {
        return SSKProtoGroupContextV2(proto)
    }

    @objc
    public func buildInfallibly() -> SSKProtoGroupContextV2 {
        return SSKProtoGroupContextV2(proto)
    }

    @objc
    public func buildSerializedData() throws -> Data {
        return try SSKProtoGroupContextV2(proto).serializedData()
    }
}

#if TESTABLE_BUILD

extension SSKProtoGroupContextV2 {
    @objc
    public func serializedDataIgnoringErrors() -> Data? {
        return try! self.serializedData()
    }
}

extension SSKProtoGroupContextV2Builder {
    @objc
    public func buildIgnoringErrors() -> SSKProtoGroupContextV2? {
        return self.buildInfallibly()
    }
}

#endif

// MARK: - SSKProtoContactDetailsAvatar

@objc
public class SSKProtoContactDetailsAvatar: NSObject, Codable, NSSecureCoding {

    fileprivate let proto: SignalServiceProtos_ContactDetails.Avatar

    @objc
    public var contentType: String? {
        guard hasContentType else {
            return nil
        }
        return proto.contentType
    }
    @objc
    public var hasContentType: Bool {
        return proto.hasContentType
    }

    @objc
    public var length: UInt32 {
        return proto.length
    }
    @objc
    public var hasLength: Bool {
        return proto.hasLength
    }

    public var hasUnknownFields: Bool {
        return !proto.unknownFields.data.isEmpty
    }
    public var unknownFields: SwiftProtobuf.UnknownStorage? {
        guard hasUnknownFields else { return nil }
        return proto.unknownFields
    }

    private init(proto: SignalServiceProtos_ContactDetails.Avatar) {
        self.proto = proto
    }

    @objc
    public func serializedData() throws -> Data {
        return try self.proto.serializedData()
    }

    @objc
    public convenience init(serializedData: Data) throws {
        let proto = try SignalServiceProtos_ContactDetails.Avatar(serializedData: serializedData)
        self.init(proto)
    }

    fileprivate convenience init(_ proto: SignalServiceProtos_ContactDetails.Avatar) {
        self.init(proto: proto)
    }

    public required convenience init(from decoder: Swift.Decoder) throws {
        let singleValueContainer = try decoder.singleValueContainer()
        let serializedData = try singleValueContainer.decode(Data.self)
        try self.init(serializedData: serializedData)
    }
    public func encode(to encoder: Swift.Encoder) throws {
        var singleValueContainer = encoder.singleValueContainer()
        try singleValueContainer.encode(try serializedData())
    }

    public static var supportsSecureCoding: Bool { true }

    public required convenience init?(coder: NSCoder) {
        guard let serializedData = coder.decodeData() else { return nil }
        do {
            try self.init(serializedData: serializedData)
        } catch {
            owsFailDebug("Failed to decode serialized data \(error)")
            return nil
        }
    }

    public func encode(with coder: NSCoder) {
        do {
            coder.encode(try serializedData())
        } catch {
            owsFailDebug("Failed to encode serialized data \(error)")
        }
    }

    @objc
    public override var debugDescription: String {
        return "\(proto)"
    }
}

extension SSKProtoContactDetailsAvatar {
    @objc
    public static func builder() -> SSKProtoContactDetailsAvatarBuilder {
        return SSKProtoContactDetailsAvatarBuilder()
    }

    // asBuilder() constructs a builder that reflects the proto's contents.
    @objc
    public func asBuilder() -> SSKProtoContactDetailsAvatarBuilder {
        let builder = SSKProtoContactDetailsAvatarBuilder()
        if let _value = contentType {
            builder.setContentType(_value)
        }
        if hasLength {
            builder.setLength(length)
        }
        if let _value = unknownFields {
            builder.setUnknownFields(_value)
        }
        return builder
    }
}

@objc
public class SSKProtoContactDetailsAvatarBuilder: NSObject {

    private var proto = SignalServiceProtos_ContactDetails.Avatar()

    @objc
    fileprivate override init() {}

    @objc
    @available(swift, obsoleted: 1.0)
    public func setContentType(_ valueParam: String?) {
        guard let valueParam = valueParam else { return }
        proto.contentType = valueParam
    }

    public func setContentType(_ valueParam: String) {
        proto.contentType = valueParam
    }

    @objc
    public func setLength(_ valueParam: UInt32) {
        proto.length = valueParam
    }

    public func setUnknownFields(_ unknownFields: SwiftProtobuf.UnknownStorage) {
        proto.unknownFields = unknownFields
    }

    @objc
    public func build() throws -> SSKProtoContactDetailsAvatar {
        return SSKProtoContactDetailsAvatar(proto)
    }

    @objc
    public func buildInfallibly() -> SSKProtoContactDetailsAvatar {
        return SSKProtoContactDetailsAvatar(proto)
    }

    @objc
    public func buildSerializedData() throws -> Data {
        return try SSKProtoContactDetailsAvatar(proto).serializedData()
    }
}

#if TESTABLE_BUILD

extension SSKProtoContactDetailsAvatar {
    @objc
    public func serializedDataIgnoringErrors() -> Data? {
        return try! self.serializedData()
    }
}

extension SSKProtoContactDetailsAvatarBuilder {
    @objc
    public func buildIgnoringErrors() -> SSKProtoContactDetailsAvatar? {
        return self.buildInfallibly()
    }
}

#endif

// MARK: - SSKProtoContactDetails

@objc
public class SSKProtoContactDetails: NSObject, Codable, NSSecureCoding {

    fileprivate let proto: SignalServiceProtos_ContactDetails

    @objc
    public let avatar: SSKProtoContactDetailsAvatar?

    @objc
    public var contactE164: String? {
        guard hasContactE164 else {
            return nil
        }
        return proto.contactE164
    }
    @objc
    public var hasContactE164: Bool {
        return proto.hasContactE164 && !proto.contactE164.isEmpty
    }

    @objc
    public var aci: String? {
        guard hasAci else {
            return nil
        }
        return proto.aci
    }
    @objc
    public var hasAci: Bool {
        return proto.hasAci
    }

    @objc
    public var name: String? {
        guard hasName else {
            return nil
        }
        return proto.name
    }
    @objc
    public var hasName: Bool {
        return proto.hasName
    }

    @objc
    public var blocked: Bool {
        return proto.blocked
    }
    @objc
    public var hasBlocked: Bool {
        return proto.hasBlocked
    }

    @objc
    public var expireTimer: UInt32 {
        return proto.expireTimer
    }
    @objc
    public var hasExpireTimer: Bool {
        return proto.hasExpireTimer
    }

    @objc
    public var inboxPosition: UInt32 {
        return proto.inboxPosition
    }
    @objc
    public var hasInboxPosition: Bool {
        return proto.hasInboxPosition
    }

    public var hasUnknownFields: Bool {
        return !proto.unknownFields.data.isEmpty
    }
    public var unknownFields: SwiftProtobuf.UnknownStorage? {
        guard hasUnknownFields else { return nil }
        return proto.unknownFields
    }

    private init(proto: SignalServiceProtos_ContactDetails,
                 avatar: SSKProtoContactDetailsAvatar?) {
        self.proto = proto
        self.avatar = avatar
    }

    @objc
    public func serializedData() throws -> Data {
        return try self.proto.serializedData()
    }

    @objc
    public convenience init(serializedData: Data) throws {
        let proto = try SignalServiceProtos_ContactDetails(serializedData: serializedData)
        self.init(proto)
    }

    fileprivate convenience init(_ proto: SignalServiceProtos_ContactDetails) {
        var avatar: SSKProtoContactDetailsAvatar?
        if proto.hasAvatar {
            avatar = SSKProtoContactDetailsAvatar(proto.avatar)
        }

        self.init(proto: proto,
                  avatar: avatar)
    }

    public required convenience init(from decoder: Swift.Decoder) throws {
        let singleValueContainer = try decoder.singleValueContainer()
        let serializedData = try singleValueContainer.decode(Data.self)
        try self.init(serializedData: serializedData)
    }
    public func encode(to encoder: Swift.Encoder) throws {
        var singleValueContainer = encoder.singleValueContainer()
        try singleValueContainer.encode(try serializedData())
    }

    public static var supportsSecureCoding: Bool { true }

    public required convenience init?(coder: NSCoder) {
        guard let serializedData = coder.decodeData() else { return nil }
        do {
            try self.init(serializedData: serializedData)
        } catch {
            owsFailDebug("Failed to decode serialized data \(error)")
            return nil
        }
    }

    public func encode(with coder: NSCoder) {
        do {
            coder.encode(try serializedData())
        } catch {
            owsFailDebug("Failed to encode serialized data \(error)")
        }
    }

    @objc
    public override var debugDescription: String {
        return "\(proto)"
    }
}

extension SSKProtoContactDetails {
    @objc
    public static func builder() -> SSKProtoContactDetailsBuilder {
        return SSKProtoContactDetailsBuilder()
    }

    // asBuilder() constructs a builder that reflects the proto's contents.
    @objc
    public func asBuilder() -> SSKProtoContactDetailsBuilder {
        let builder = SSKProtoContactDetailsBuilder()
        if let _value = contactE164 {
            builder.setContactE164(_value)
        }
        if let _value = aci {
            builder.setAci(_value)
        }
        if let _value = name {
            builder.setName(_value)
        }
        if let _value = avatar {
            builder.setAvatar(_value)
        }
        if hasBlocked {
            builder.setBlocked(blocked)
        }
        if hasExpireTimer {
            builder.setExpireTimer(expireTimer)
        }
        if hasInboxPosition {
            builder.setInboxPosition(inboxPosition)
        }
        if let _value = unknownFields {
            builder.setUnknownFields(_value)
        }
        return builder
    }
}

@objc
public class SSKProtoContactDetailsBuilder: NSObject {

    private var proto = SignalServiceProtos_ContactDetails()

    @objc
    fileprivate override init() {}

    @objc
    @available(swift, obsoleted: 1.0)
    public func setContactE164(_ valueParam: String?) {
        guard let valueParam = valueParam else { return }
        if let valueParam = valueParam.nilIfEmpty {
            owsAssertDebug(valueParam.isStructurallyValidE164)
        }

        proto.contactE164 = valueParam
    }

    public func setContactE164(_ valueParam: String) {
        if let valueParam = valueParam.nilIfEmpty {
            owsAssertDebug(valueParam.isStructurallyValidE164)
        }

        proto.contactE164 = valueParam
    }

    @objc
    @available(swift, obsoleted: 1.0)
    public func setAci(_ valueParam: String?) {
        guard let valueParam = valueParam else { return }
        proto.aci = valueParam
    }

    public func setAci(_ valueParam: String) {
        proto.aci = valueParam
    }

    @objc
    @available(swift, obsoleted: 1.0)
    public func setName(_ valueParam: String?) {
        guard let valueParam = valueParam else { return }
        proto.name = valueParam
    }

    public func setName(_ valueParam: String) {
        proto.name = valueParam
    }

    @objc
    @available(swift, obsoleted: 1.0)
    public func setAvatar(_ valueParam: SSKProtoContactDetailsAvatar?) {
        guard let valueParam = valueParam else { return }
        proto.avatar = valueParam.proto
    }

    public func setAvatar(_ valueParam: SSKProtoContactDetailsAvatar) {
        proto.avatar = valueParam.proto
    }

    @objc
    public func setBlocked(_ valueParam: Bool) {
        proto.blocked = valueParam
    }

    @objc
    public func setExpireTimer(_ valueParam: UInt32) {
        proto.expireTimer = valueParam
    }

    @objc
    public func setInboxPosition(_ valueParam: UInt32) {
        proto.inboxPosition = valueParam
    }

    public func setUnknownFields(_ unknownFields: SwiftProtobuf.UnknownStorage) {
        proto.unknownFields = unknownFields
    }

    @objc
    public func build() throws -> SSKProtoContactDetails {
        return SSKProtoContactDetails(proto)
    }

    @objc
    public func buildInfallibly() -> SSKProtoContactDetails {
        return SSKProtoContactDetails(proto)
    }

    @objc
    public func buildSerializedData() throws -> Data {
        return try SSKProtoContactDetails(proto).serializedData()
    }
}

#if TESTABLE_BUILD

extension SSKProtoContactDetails {
    @objc
    public func serializedDataIgnoringErrors() -> Data? {
        return try! self.serializedData()
    }
}

extension SSKProtoContactDetailsBuilder {
    @objc
    public func buildIgnoringErrors() -> SSKProtoContactDetails? {
        return self.buildInfallibly()
    }
}

#endif

// MARK: - SSKProtoPackSticker

@objc
public class SSKProtoPackSticker: NSObject, Codable, NSSecureCoding {

    fileprivate let proto: SignalServiceProtos_Pack.Sticker

    @objc
    public let id: UInt32

    @objc
    public var emoji: String? {
        guard hasEmoji else {
            return nil
        }
        return proto.emoji
    }
    @objc
    public var hasEmoji: Bool {
        return proto.hasEmoji
    }

    @objc
    public var contentType: String? {
        guard hasContentType else {
            return nil
        }
        return proto.contentType
    }
    @objc
    public var hasContentType: Bool {
        return proto.hasContentType
    }

    public var hasUnknownFields: Bool {
        return !proto.unknownFields.data.isEmpty
    }
    public var unknownFields: SwiftProtobuf.UnknownStorage? {
        guard hasUnknownFields else { return nil }
        return proto.unknownFields
    }

    private init(proto: SignalServiceProtos_Pack.Sticker,
                 id: UInt32) {
        self.proto = proto
        self.id = id
    }

    @objc
    public func serializedData() throws -> Data {
        return try self.proto.serializedData()
    }

    @objc
    public convenience init(serializedData: Data) throws {
        let proto = try SignalServiceProtos_Pack.Sticker(serializedData: serializedData)
        try self.init(proto)
    }

    fileprivate convenience init(_ proto: SignalServiceProtos_Pack.Sticker) throws {
        guard proto.hasID else {
            throw SSKProtoError.invalidProtobuf(description: "\(Self.logTag()) missing required field: id")
        }
        let id = proto.id

        self.init(proto: proto,
                  id: id)
    }

    public required convenience init(from decoder: Swift.Decoder) throws {
        let singleValueContainer = try decoder.singleValueContainer()
        let serializedData = try singleValueContainer.decode(Data.self)
        try self.init(serializedData: serializedData)
    }
    public func encode(to encoder: Swift.Encoder) throws {
        var singleValueContainer = encoder.singleValueContainer()
        try singleValueContainer.encode(try serializedData())
    }

    public static var supportsSecureCoding: Bool { true }

    public required convenience init?(coder: NSCoder) {
        guard let serializedData = coder.decodeData() else { return nil }
        do {
            try self.init(serializedData: serializedData)
        } catch {
            owsFailDebug("Failed to decode serialized data \(error)")
            return nil
        }
    }

    public func encode(with coder: NSCoder) {
        do {
            coder.encode(try serializedData())
        } catch {
            owsFailDebug("Failed to encode serialized data \(error)")
        }
    }

    @objc
    public override var debugDescription: String {
        return "\(proto)"
    }
}

extension SSKProtoPackSticker {
    @objc
    public static func builder(id: UInt32) -> SSKProtoPackStickerBuilder {
        return SSKProtoPackStickerBuilder(id: id)
    }

    // asBuilder() constructs a builder that reflects the proto's contents.
    @objc
    public func asBuilder() -> SSKProtoPackStickerBuilder {
        let builder = SSKProtoPackStickerBuilder(id: id)
        if let _value = emoji {
            builder.setEmoji(_value)
        }
        if let _value = contentType {
            builder.setContentType(_value)
        }
        if let _value = unknownFields {
            builder.setUnknownFields(_value)
        }
        return builder
    }
}

@objc
public class SSKProtoPackStickerBuilder: NSObject {

    private var proto = SignalServiceProtos_Pack.Sticker()

    @objc
    fileprivate override init() {}

    @objc
    fileprivate init(id: UInt32) {
        super.init()

        setId(id)
    }

    @objc
    public func setId(_ valueParam: UInt32) {
        proto.id = valueParam
    }

    @objc
    @available(swift, obsoleted: 1.0)
    public func setEmoji(_ valueParam: String?) {
        guard let valueParam = valueParam else { return }
        proto.emoji = valueParam
    }

    public func setEmoji(_ valueParam: String) {
        proto.emoji = valueParam
    }

    @objc
    @available(swift, obsoleted: 1.0)
    public func setContentType(_ valueParam: String?) {
        guard let valueParam = valueParam else { return }
        proto.contentType = valueParam
    }

    public func setContentType(_ valueParam: String) {
        proto.contentType = valueParam
    }

    public func setUnknownFields(_ unknownFields: SwiftProtobuf.UnknownStorage) {
        proto.unknownFields = unknownFields
    }

    @objc
    public func build() throws -> SSKProtoPackSticker {
        return try SSKProtoPackSticker(proto)
    }

    @objc
    public func buildSerializedData() throws -> Data {
        return try SSKProtoPackSticker(proto).serializedData()
    }
}

#if TESTABLE_BUILD

extension SSKProtoPackSticker {
    @objc
    public func serializedDataIgnoringErrors() -> Data? {
        return try! self.serializedData()
    }
}

extension SSKProtoPackStickerBuilder {
    @objc
    public func buildIgnoringErrors() -> SSKProtoPackSticker? {
        return try! self.build()
    }
}

#endif

// MARK: - SSKProtoPack

@objc
public class SSKProtoPack: NSObject, Codable, NSSecureCoding {

    fileprivate let proto: SignalServiceProtos_Pack

    @objc
    public let cover: SSKProtoPackSticker?

    @objc
    public let stickers: [SSKProtoPackSticker]

    @objc
    public var title: String? {
        guard hasTitle else {
            return nil
        }
        return proto.title
    }
    @objc
    public var hasTitle: Bool {
        return proto.hasTitle
    }

    @objc
    public var author: String? {
        guard hasAuthor else {
            return nil
        }
        return proto.author
    }
    @objc
    public var hasAuthor: Bool {
        return proto.hasAuthor
    }

    public var hasUnknownFields: Bool {
        return !proto.unknownFields.data.isEmpty
    }
    public var unknownFields: SwiftProtobuf.UnknownStorage? {
        guard hasUnknownFields else { return nil }
        return proto.unknownFields
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

    @objc
    public convenience init(serializedData: Data) throws {
        let proto = try SignalServiceProtos_Pack(serializedData: serializedData)
        try self.init(proto)
    }

    fileprivate convenience init(_ proto: SignalServiceProtos_Pack) throws {
        var cover: SSKProtoPackSticker?
        if proto.hasCover {
            cover = try SSKProtoPackSticker(proto.cover)
        }

        var stickers: [SSKProtoPackSticker] = []
        stickers = try proto.stickers.map { try SSKProtoPackSticker($0) }

        self.init(proto: proto,
                  cover: cover,
                  stickers: stickers)
    }

    public required convenience init(from decoder: Swift.Decoder) throws {
        let singleValueContainer = try decoder.singleValueContainer()
        let serializedData = try singleValueContainer.decode(Data.self)
        try self.init(serializedData: serializedData)
    }
    public func encode(to encoder: Swift.Encoder) throws {
        var singleValueContainer = encoder.singleValueContainer()
        try singleValueContainer.encode(try serializedData())
    }

    public static var supportsSecureCoding: Bool { true }

    public required convenience init?(coder: NSCoder) {
        guard let serializedData = coder.decodeData() else { return nil }
        do {
            try self.init(serializedData: serializedData)
        } catch {
            owsFailDebug("Failed to decode serialized data \(error)")
            return nil
        }
    }

    public func encode(with coder: NSCoder) {
        do {
            coder.encode(try serializedData())
        } catch {
            owsFailDebug("Failed to encode serialized data \(error)")
        }
    }

    @objc
    public override var debugDescription: String {
        return "\(proto)"
    }
}

extension SSKProtoPack {
    @objc
    public static func builder() -> SSKProtoPackBuilder {
        return SSKProtoPackBuilder()
    }

    // asBuilder() constructs a builder that reflects the proto's contents.
    @objc
    public func asBuilder() -> SSKProtoPackBuilder {
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
        if let _value = unknownFields {
            builder.setUnknownFields(_value)
        }
        return builder
    }
}

@objc
public class SSKProtoPackBuilder: NSObject {

    private var proto = SignalServiceProtos_Pack()

    @objc
    fileprivate override init() {}

    @objc
    @available(swift, obsoleted: 1.0)
    public func setTitle(_ valueParam: String?) {
        guard let valueParam = valueParam else { return }
        proto.title = valueParam
    }

    public func setTitle(_ valueParam: String) {
        proto.title = valueParam
    }

    @objc
    @available(swift, obsoleted: 1.0)
    public func setAuthor(_ valueParam: String?) {
        guard let valueParam = valueParam else { return }
        proto.author = valueParam
    }

    public func setAuthor(_ valueParam: String) {
        proto.author = valueParam
    }

    @objc
    @available(swift, obsoleted: 1.0)
    public func setCover(_ valueParam: SSKProtoPackSticker?) {
        guard let valueParam = valueParam else { return }
        proto.cover = valueParam.proto
    }

    public func setCover(_ valueParam: SSKProtoPackSticker) {
        proto.cover = valueParam.proto
    }

    @objc
    public func addStickers(_ valueParam: SSKProtoPackSticker) {
        proto.stickers.append(valueParam.proto)
    }

    @objc
    public func setStickers(_ wrappedItems: [SSKProtoPackSticker]) {
        proto.stickers = wrappedItems.map { $0.proto }
    }

    public func setUnknownFields(_ unknownFields: SwiftProtobuf.UnknownStorage) {
        proto.unknownFields = unknownFields
    }

    @objc
    public func build() throws -> SSKProtoPack {
        return try SSKProtoPack(proto)
    }

    @objc
    public func buildSerializedData() throws -> Data {
        return try SSKProtoPack(proto).serializedData()
    }
}

#if TESTABLE_BUILD

extension SSKProtoPack {
    @objc
    public func serializedDataIgnoringErrors() -> Data? {
        return try! self.serializedData()
    }
}

extension SSKProtoPackBuilder {
    @objc
    public func buildIgnoringErrors() -> SSKProtoPack? {
        return try! self.build()
    }
}

#endif

// MARK: - SSKProtoPaymentAddressMobileCoin

@objc
public class SSKProtoPaymentAddressMobileCoin: NSObject, Codable, NSSecureCoding {

    fileprivate let proto: SignalServiceProtos_PaymentAddress.MobileCoin

    @objc
    public let publicAddress: Data

    @objc
    public let signature: Data

    public var hasUnknownFields: Bool {
        return !proto.unknownFields.data.isEmpty
    }
    public var unknownFields: SwiftProtobuf.UnknownStorage? {
        guard hasUnknownFields else { return nil }
        return proto.unknownFields
    }

    private init(proto: SignalServiceProtos_PaymentAddress.MobileCoin,
                 publicAddress: Data,
                 signature: Data) {
        self.proto = proto
        self.publicAddress = publicAddress
        self.signature = signature
    }

    @objc
    public func serializedData() throws -> Data {
        return try self.proto.serializedData()
    }

    @objc
    public convenience init(serializedData: Data) throws {
        let proto = try SignalServiceProtos_PaymentAddress.MobileCoin(serializedData: serializedData)
        try self.init(proto)
    }

    fileprivate convenience init(_ proto: SignalServiceProtos_PaymentAddress.MobileCoin) throws {
        guard proto.hasPublicAddress else {
            throw SSKProtoError.invalidProtobuf(description: "\(Self.logTag()) missing required field: publicAddress")
        }
        let publicAddress = proto.publicAddress

        guard proto.hasSignature else {
            throw SSKProtoError.invalidProtobuf(description: "\(Self.logTag()) missing required field: signature")
        }
        let signature = proto.signature

        self.init(proto: proto,
                  publicAddress: publicAddress,
                  signature: signature)
    }

    public required convenience init(from decoder: Swift.Decoder) throws {
        let singleValueContainer = try decoder.singleValueContainer()
        let serializedData = try singleValueContainer.decode(Data.self)
        try self.init(serializedData: serializedData)
    }
    public func encode(to encoder: Swift.Encoder) throws {
        var singleValueContainer = encoder.singleValueContainer()
        try singleValueContainer.encode(try serializedData())
    }

    public static var supportsSecureCoding: Bool { true }

    public required convenience init?(coder: NSCoder) {
        guard let serializedData = coder.decodeData() else { return nil }
        do {
            try self.init(serializedData: serializedData)
        } catch {
            owsFailDebug("Failed to decode serialized data \(error)")
            return nil
        }
    }

    public func encode(with coder: NSCoder) {
        do {
            coder.encode(try serializedData())
        } catch {
            owsFailDebug("Failed to encode serialized data \(error)")
        }
    }

    @objc
    public override var debugDescription: String {
        return "\(proto)"
    }
}

extension SSKProtoPaymentAddressMobileCoin {
    @objc
    public static func builder(publicAddress: Data, signature: Data) -> SSKProtoPaymentAddressMobileCoinBuilder {
        return SSKProtoPaymentAddressMobileCoinBuilder(publicAddress: publicAddress, signature: signature)
    }

    // asBuilder() constructs a builder that reflects the proto's contents.
    @objc
    public func asBuilder() -> SSKProtoPaymentAddressMobileCoinBuilder {
        let builder = SSKProtoPaymentAddressMobileCoinBuilder(publicAddress: publicAddress, signature: signature)
        if let _value = unknownFields {
            builder.setUnknownFields(_value)
        }
        return builder
    }
}

@objc
public class SSKProtoPaymentAddressMobileCoinBuilder: NSObject {

    private var proto = SignalServiceProtos_PaymentAddress.MobileCoin()

    @objc
    fileprivate override init() {}

    @objc
    fileprivate init(publicAddress: Data, signature: Data) {
        super.init()

        setPublicAddress(publicAddress)
        setSignature(signature)
    }

    @objc
    @available(swift, obsoleted: 1.0)
    public func setPublicAddress(_ valueParam: Data?) {
        guard let valueParam = valueParam else { return }
        proto.publicAddress = valueParam
    }

    public func setPublicAddress(_ valueParam: Data) {
        proto.publicAddress = valueParam
    }

    @objc
    @available(swift, obsoleted: 1.0)
    public func setSignature(_ valueParam: Data?) {
        guard let valueParam = valueParam else { return }
        proto.signature = valueParam
    }

    public func setSignature(_ valueParam: Data) {
        proto.signature = valueParam
    }

    public func setUnknownFields(_ unknownFields: SwiftProtobuf.UnknownStorage) {
        proto.unknownFields = unknownFields
    }

    @objc
    public func build() throws -> SSKProtoPaymentAddressMobileCoin {
        return try SSKProtoPaymentAddressMobileCoin(proto)
    }

    @objc
    public func buildSerializedData() throws -> Data {
        return try SSKProtoPaymentAddressMobileCoin(proto).serializedData()
    }
}

#if TESTABLE_BUILD

extension SSKProtoPaymentAddressMobileCoin {
    @objc
    public func serializedDataIgnoringErrors() -> Data? {
        return try! self.serializedData()
    }
}

extension SSKProtoPaymentAddressMobileCoinBuilder {
    @objc
    public func buildIgnoringErrors() -> SSKProtoPaymentAddressMobileCoin? {
        return try! self.build()
    }
}

#endif

// MARK: - SSKProtoPaymentAddress

@objc
public class SSKProtoPaymentAddress: NSObject, Codable, NSSecureCoding {

    fileprivate let proto: SignalServiceProtos_PaymentAddress

    @objc
    public let mobileCoin: SSKProtoPaymentAddressMobileCoin?

    public var hasUnknownFields: Bool {
        return !proto.unknownFields.data.isEmpty
    }
    public var unknownFields: SwiftProtobuf.UnknownStorage? {
        guard hasUnknownFields else { return nil }
        return proto.unknownFields
    }

    private init(proto: SignalServiceProtos_PaymentAddress,
                 mobileCoin: SSKProtoPaymentAddressMobileCoin?) {
        self.proto = proto
        self.mobileCoin = mobileCoin
    }

    @objc
    public func serializedData() throws -> Data {
        return try self.proto.serializedData()
    }

    @objc
    public convenience init(serializedData: Data) throws {
        let proto = try SignalServiceProtos_PaymentAddress(serializedData: serializedData)
        try self.init(proto)
    }

    fileprivate convenience init(_ proto: SignalServiceProtos_PaymentAddress) throws {
        var mobileCoin: SSKProtoPaymentAddressMobileCoin?
        if proto.hasMobileCoin {
            mobileCoin = try SSKProtoPaymentAddressMobileCoin(proto.mobileCoin)
        }

        self.init(proto: proto,
                  mobileCoin: mobileCoin)
    }

    public required convenience init(from decoder: Swift.Decoder) throws {
        let singleValueContainer = try decoder.singleValueContainer()
        let serializedData = try singleValueContainer.decode(Data.self)
        try self.init(serializedData: serializedData)
    }
    public func encode(to encoder: Swift.Encoder) throws {
        var singleValueContainer = encoder.singleValueContainer()
        try singleValueContainer.encode(try serializedData())
    }

    public static var supportsSecureCoding: Bool { true }

    public required convenience init?(coder: NSCoder) {
        guard let serializedData = coder.decodeData() else { return nil }
        do {
            try self.init(serializedData: serializedData)
        } catch {
            owsFailDebug("Failed to decode serialized data \(error)")
            return nil
        }
    }

    public func encode(with coder: NSCoder) {
        do {
            coder.encode(try serializedData())
        } catch {
            owsFailDebug("Failed to encode serialized data \(error)")
        }
    }

    @objc
    public override var debugDescription: String {
        return "\(proto)"
    }
}

extension SSKProtoPaymentAddress {
    @objc
    public static func builder() -> SSKProtoPaymentAddressBuilder {
        return SSKProtoPaymentAddressBuilder()
    }

    // asBuilder() constructs a builder that reflects the proto's contents.
    @objc
    public func asBuilder() -> SSKProtoPaymentAddressBuilder {
        let builder = SSKProtoPaymentAddressBuilder()
        if let _value = mobileCoin {
            builder.setMobileCoin(_value)
        }
        if let _value = unknownFields {
            builder.setUnknownFields(_value)
        }
        return builder
    }
}

@objc
public class SSKProtoPaymentAddressBuilder: NSObject {

    private var proto = SignalServiceProtos_PaymentAddress()

    @objc
    fileprivate override init() {}

    @objc
    @available(swift, obsoleted: 1.0)
    public func setMobileCoin(_ valueParam: SSKProtoPaymentAddressMobileCoin?) {
        guard let valueParam = valueParam else { return }
        proto.mobileCoin = valueParam.proto
    }

    public func setMobileCoin(_ valueParam: SSKProtoPaymentAddressMobileCoin) {
        proto.mobileCoin = valueParam.proto
    }

    public func setUnknownFields(_ unknownFields: SwiftProtobuf.UnknownStorage) {
        proto.unknownFields = unknownFields
    }

    @objc
    public func build() throws -> SSKProtoPaymentAddress {
        return try SSKProtoPaymentAddress(proto)
    }

    @objc
    public func buildSerializedData() throws -> Data {
        return try SSKProtoPaymentAddress(proto).serializedData()
    }
}

#if TESTABLE_BUILD

extension SSKProtoPaymentAddress {
    @objc
    public func serializedDataIgnoringErrors() -> Data? {
        return try! self.serializedData()
    }
}

extension SSKProtoPaymentAddressBuilder {
    @objc
    public func buildIgnoringErrors() -> SSKProtoPaymentAddress? {
        return try! self.build()
    }
}

#endif

// MARK: - SSKProtoDecryptionErrorMessage

@objc
public class SSKProtoDecryptionErrorMessage: NSObject, Codable, NSSecureCoding {

    fileprivate let proto: SignalServiceProtos_DecryptionErrorMessage

    @objc
    public var ratchetKey: Data? {
        guard hasRatchetKey else {
            return nil
        }
        return proto.ratchetKey
    }
    @objc
    public var hasRatchetKey: Bool {
        return proto.hasRatchetKey
    }

    @objc
    public var timestamp: UInt64 {
        return proto.timestamp
    }
    @objc
    public var hasTimestamp: Bool {
        return proto.hasTimestamp
    }

    @objc
    public var deviceID: UInt32 {
        return proto.deviceID
    }
    @objc
    public var hasDeviceID: Bool {
        return proto.hasDeviceID
    }

    public var hasUnknownFields: Bool {
        return !proto.unknownFields.data.isEmpty
    }
    public var unknownFields: SwiftProtobuf.UnknownStorage? {
        guard hasUnknownFields else { return nil }
        return proto.unknownFields
    }

    private init(proto: SignalServiceProtos_DecryptionErrorMessage) {
        self.proto = proto
    }

    @objc
    public func serializedData() throws -> Data {
        return try self.proto.serializedData()
    }

    @objc
    public convenience init(serializedData: Data) throws {
        let proto = try SignalServiceProtos_DecryptionErrorMessage(serializedData: serializedData)
        self.init(proto)
    }

    fileprivate convenience init(_ proto: SignalServiceProtos_DecryptionErrorMessage) {
        self.init(proto: proto)
    }

    public required convenience init(from decoder: Swift.Decoder) throws {
        let singleValueContainer = try decoder.singleValueContainer()
        let serializedData = try singleValueContainer.decode(Data.self)
        try self.init(serializedData: serializedData)
    }
    public func encode(to encoder: Swift.Encoder) throws {
        var singleValueContainer = encoder.singleValueContainer()
        try singleValueContainer.encode(try serializedData())
    }

    public static var supportsSecureCoding: Bool { true }

    public required convenience init?(coder: NSCoder) {
        guard let serializedData = coder.decodeData() else { return nil }
        do {
            try self.init(serializedData: serializedData)
        } catch {
            owsFailDebug("Failed to decode serialized data \(error)")
            return nil
        }
    }

    public func encode(with coder: NSCoder) {
        do {
            coder.encode(try serializedData())
        } catch {
            owsFailDebug("Failed to encode serialized data \(error)")
        }
    }

    @objc
    public override var debugDescription: String {
        return "\(proto)"
    }
}

extension SSKProtoDecryptionErrorMessage {
    @objc
    public static func builder() -> SSKProtoDecryptionErrorMessageBuilder {
        return SSKProtoDecryptionErrorMessageBuilder()
    }

    // asBuilder() constructs a builder that reflects the proto's contents.
    @objc
    public func asBuilder() -> SSKProtoDecryptionErrorMessageBuilder {
        let builder = SSKProtoDecryptionErrorMessageBuilder()
        if let _value = ratchetKey {
            builder.setRatchetKey(_value)
        }
        if hasTimestamp {
            builder.setTimestamp(timestamp)
        }
        if hasDeviceID {
            builder.setDeviceID(deviceID)
        }
        if let _value = unknownFields {
            builder.setUnknownFields(_value)
        }
        return builder
    }
}

@objc
public class SSKProtoDecryptionErrorMessageBuilder: NSObject {

    private var proto = SignalServiceProtos_DecryptionErrorMessage()

    @objc
    fileprivate override init() {}

    @objc
    @available(swift, obsoleted: 1.0)
    public func setRatchetKey(_ valueParam: Data?) {
        guard let valueParam = valueParam else { return }
        proto.ratchetKey = valueParam
    }

    public func setRatchetKey(_ valueParam: Data) {
        proto.ratchetKey = valueParam
    }

    @objc
    public func setTimestamp(_ valueParam: UInt64) {
        proto.timestamp = valueParam
    }

    @objc
    public func setDeviceID(_ valueParam: UInt32) {
        proto.deviceID = valueParam
    }

    public func setUnknownFields(_ unknownFields: SwiftProtobuf.UnknownStorage) {
        proto.unknownFields = unknownFields
    }

    @objc
    public func build() throws -> SSKProtoDecryptionErrorMessage {
        return SSKProtoDecryptionErrorMessage(proto)
    }

    @objc
    public func buildInfallibly() -> SSKProtoDecryptionErrorMessage {
        return SSKProtoDecryptionErrorMessage(proto)
    }

    @objc
    public func buildSerializedData() throws -> Data {
        return try SSKProtoDecryptionErrorMessage(proto).serializedData()
    }
}

#if TESTABLE_BUILD

extension SSKProtoDecryptionErrorMessage {
    @objc
    public func serializedDataIgnoringErrors() -> Data? {
        return try! self.serializedData()
    }
}

extension SSKProtoDecryptionErrorMessageBuilder {
    @objc
    public func buildIgnoringErrors() -> SSKProtoDecryptionErrorMessage? {
        return self.buildInfallibly()
    }
}

#endif

// MARK: - SSKProtoPniSignatureMessage

@objc
public class SSKProtoPniSignatureMessage: NSObject, Codable, NSSecureCoding {

    fileprivate let proto: SignalServiceProtos_PniSignatureMessage

    @objc
    public var pni: Data? {
        guard hasPni else {
            return nil
        }
        return proto.pni
    }
    @objc
    public var hasPni: Bool {
        return proto.hasPni
    }

    @objc
    public var signature: Data? {
        guard hasSignature else {
            return nil
        }
        return proto.signature
    }
    @objc
    public var hasSignature: Bool {
        return proto.hasSignature
    }

    public var hasUnknownFields: Bool {
        return !proto.unknownFields.data.isEmpty
    }
    public var unknownFields: SwiftProtobuf.UnknownStorage? {
        guard hasUnknownFields else { return nil }
        return proto.unknownFields
    }

    private init(proto: SignalServiceProtos_PniSignatureMessage) {
        self.proto = proto
    }

    @objc
    public func serializedData() throws -> Data {
        return try self.proto.serializedData()
    }

    @objc
    public convenience init(serializedData: Data) throws {
        let proto = try SignalServiceProtos_PniSignatureMessage(serializedData: serializedData)
        self.init(proto)
    }

    fileprivate convenience init(_ proto: SignalServiceProtos_PniSignatureMessage) {
        self.init(proto: proto)
    }

    public required convenience init(from decoder: Swift.Decoder) throws {
        let singleValueContainer = try decoder.singleValueContainer()
        let serializedData = try singleValueContainer.decode(Data.self)
        try self.init(serializedData: serializedData)
    }
    public func encode(to encoder: Swift.Encoder) throws {
        var singleValueContainer = encoder.singleValueContainer()
        try singleValueContainer.encode(try serializedData())
    }

    public static var supportsSecureCoding: Bool { true }

    public required convenience init?(coder: NSCoder) {
        guard let serializedData = coder.decodeData() else { return nil }
        do {
            try self.init(serializedData: serializedData)
        } catch {
            owsFailDebug("Failed to decode serialized data \(error)")
            return nil
        }
    }

    public func encode(with coder: NSCoder) {
        do {
            coder.encode(try serializedData())
        } catch {
            owsFailDebug("Failed to encode serialized data \(error)")
        }
    }

    @objc
    public override var debugDescription: String {
        return "\(proto)"
    }
}

extension SSKProtoPniSignatureMessage {
    @objc
    public static func builder() -> SSKProtoPniSignatureMessageBuilder {
        return SSKProtoPniSignatureMessageBuilder()
    }

    // asBuilder() constructs a builder that reflects the proto's contents.
    @objc
    public func asBuilder() -> SSKProtoPniSignatureMessageBuilder {
        let builder = SSKProtoPniSignatureMessageBuilder()
        if let _value = pni {
            builder.setPni(_value)
        }
        if let _value = signature {
            builder.setSignature(_value)
        }
        if let _value = unknownFields {
            builder.setUnknownFields(_value)
        }
        return builder
    }
}

@objc
public class SSKProtoPniSignatureMessageBuilder: NSObject {

    private var proto = SignalServiceProtos_PniSignatureMessage()

    @objc
    fileprivate override init() {}

    @objc
    @available(swift, obsoleted: 1.0)
    public func setPni(_ valueParam: Data?) {
        guard let valueParam = valueParam else { return }
        proto.pni = valueParam
    }

    public func setPni(_ valueParam: Data) {
        proto.pni = valueParam
    }

    @objc
    @available(swift, obsoleted: 1.0)
    public func setSignature(_ valueParam: Data?) {
        guard let valueParam = valueParam else { return }
        proto.signature = valueParam
    }

    public func setSignature(_ valueParam: Data) {
        proto.signature = valueParam
    }

    public func setUnknownFields(_ unknownFields: SwiftProtobuf.UnknownStorage) {
        proto.unknownFields = unknownFields
    }

    @objc
    public func build() throws -> SSKProtoPniSignatureMessage {
        return SSKProtoPniSignatureMessage(proto)
    }

    @objc
    public func buildInfallibly() -> SSKProtoPniSignatureMessage {
        return SSKProtoPniSignatureMessage(proto)
    }

    @objc
    public func buildSerializedData() throws -> Data {
        return try SSKProtoPniSignatureMessage(proto).serializedData()
    }
}

#if TESTABLE_BUILD

extension SSKProtoPniSignatureMessage {
    @objc
    public func serializedDataIgnoringErrors() -> Data? {
        return try! self.serializedData()
    }
}

extension SSKProtoPniSignatureMessageBuilder {
    @objc
    public func buildIgnoringErrors() -> SSKProtoPniSignatureMessage? {
        return self.buildInfallibly()
    }
}

#endif

// MARK: - SSKProtoBodyRangeStyle

@objc
public enum SSKProtoBodyRangeStyle: Int32 {
    case none = 0
    case bold = 1
    case italic = 2
    case spoiler = 3
    case strikethrough = 4
    case monospace = 5
}

private func SSKProtoBodyRangeStyleWrap(_ value: SignalServiceProtos_BodyRange.Style) -> SSKProtoBodyRangeStyle {
    switch value {
    case .none: return .none
    case .bold: return .bold
    case .italic: return .italic
    case .spoiler: return .spoiler
    case .strikethrough: return .strikethrough
    case .monospace: return .monospace
    }
}

private func SSKProtoBodyRangeStyleUnwrap(_ value: SSKProtoBodyRangeStyle) -> SignalServiceProtos_BodyRange.Style {
    switch value {
    case .none: return .none
    case .bold: return .bold
    case .italic: return .italic
    case .spoiler: return .spoiler
    case .strikethrough: return .strikethrough
    case .monospace: return .monospace
    }
}

// MARK: - SSKProtoBodyRange

@objc
public class SSKProtoBodyRange: NSObject, Codable, NSSecureCoding {

    fileprivate let proto: SignalServiceProtos_BodyRange

    @objc
    public var start: UInt32 {
        return proto.start
    }
    @objc
    public var hasStart: Bool {
        return proto.hasStart
    }

    @objc
    public var length: UInt32 {
        return proto.length
    }
    @objc
    public var hasLength: Bool {
        return proto.hasLength
    }

    @objc
    public var mentionAci: String? {
        guard hasMentionAci else {
            return nil
        }
        return proto.mentionAci
    }
    @objc
    public var hasMentionAci: Bool {
        return proto.hasMentionAci
    }

    public var style: SSKProtoBodyRangeStyle? {
        guard hasStyle else {
            return nil
        }
        return SSKProtoBodyRangeStyleWrap(proto.style)
    }
    // This "unwrapped" accessor should only be used if the "has value" accessor has already been checked.
    @objc
    public var unwrappedStyle: SSKProtoBodyRangeStyle {
        if !hasStyle {
            // TODO: We could make this a crashing assert.
            owsFailDebug("Unsafe unwrap of missing optional: BodyRange.style.")
        }
        return SSKProtoBodyRangeStyleWrap(proto.style)
    }
    @objc
    public var hasStyle: Bool {
        return proto.hasStyle
    }

    public var hasUnknownFields: Bool {
        return !proto.unknownFields.data.isEmpty
    }
    public var unknownFields: SwiftProtobuf.UnknownStorage? {
        guard hasUnknownFields else { return nil }
        return proto.unknownFields
    }

    private init(proto: SignalServiceProtos_BodyRange) {
        self.proto = proto
    }

    @objc
    public func serializedData() throws -> Data {
        return try self.proto.serializedData()
    }

    @objc
    public convenience init(serializedData: Data) throws {
        let proto = try SignalServiceProtos_BodyRange(serializedData: serializedData)
        self.init(proto)
    }

    fileprivate convenience init(_ proto: SignalServiceProtos_BodyRange) {
        self.init(proto: proto)
    }

    public required convenience init(from decoder: Swift.Decoder) throws {
        let singleValueContainer = try decoder.singleValueContainer()
        let serializedData = try singleValueContainer.decode(Data.self)
        try self.init(serializedData: serializedData)
    }
    public func encode(to encoder: Swift.Encoder) throws {
        var singleValueContainer = encoder.singleValueContainer()
        try singleValueContainer.encode(try serializedData())
    }

    public static var supportsSecureCoding: Bool { true }

    public required convenience init?(coder: NSCoder) {
        guard let serializedData = coder.decodeData() else { return nil }
        do {
            try self.init(serializedData: serializedData)
        } catch {
            owsFailDebug("Failed to decode serialized data \(error)")
            return nil
        }
    }

    public func encode(with coder: NSCoder) {
        do {
            coder.encode(try serializedData())
        } catch {
            owsFailDebug("Failed to encode serialized data \(error)")
        }
    }

    @objc
    public override var debugDescription: String {
        return "\(proto)"
    }
}

extension SSKProtoBodyRange {
    @objc
    public static func builder() -> SSKProtoBodyRangeBuilder {
        return SSKProtoBodyRangeBuilder()
    }

    // asBuilder() constructs a builder that reflects the proto's contents.
    @objc
    public func asBuilder() -> SSKProtoBodyRangeBuilder {
        let builder = SSKProtoBodyRangeBuilder()
        if hasStart {
            builder.setStart(start)
        }
        if hasLength {
            builder.setLength(length)
        }
        if let _value = mentionAci {
            builder.setMentionAci(_value)
        }
        if let _value = style {
            builder.setStyle(_value)
        }
        if let _value = unknownFields {
            builder.setUnknownFields(_value)
        }
        return builder
    }
}

@objc
public class SSKProtoBodyRangeBuilder: NSObject {

    private var proto = SignalServiceProtos_BodyRange()

    @objc
    fileprivate override init() {}

    @objc
    public func setStart(_ valueParam: UInt32) {
        proto.start = valueParam
    }

    @objc
    public func setLength(_ valueParam: UInt32) {
        proto.length = valueParam
    }

    @objc
    @available(swift, obsoleted: 1.0)
    public func setMentionAci(_ valueParam: String?) {
        guard let valueParam = valueParam else { return }
        proto.mentionAci = valueParam
    }

    public func setMentionAci(_ valueParam: String) {
        proto.mentionAci = valueParam
    }

    @objc
    public func setStyle(_ valueParam: SSKProtoBodyRangeStyle) {
        proto.style = SSKProtoBodyRangeStyleUnwrap(valueParam)
    }

    public func setUnknownFields(_ unknownFields: SwiftProtobuf.UnknownStorage) {
        proto.unknownFields = unknownFields
    }

    @objc
    public func build() throws -> SSKProtoBodyRange {
        return SSKProtoBodyRange(proto)
    }

    @objc
    public func buildInfallibly() -> SSKProtoBodyRange {
        return SSKProtoBodyRange(proto)
    }

    @objc
    public func buildSerializedData() throws -> Data {
        return try SSKProtoBodyRange(proto).serializedData()
    }
}

#if TESTABLE_BUILD

extension SSKProtoBodyRange {
    @objc
    public func serializedDataIgnoringErrors() -> Data? {
        return try! self.serializedData()
    }
}

extension SSKProtoBodyRangeBuilder {
    @objc
    public func buildIgnoringErrors() -> SSKProtoBodyRange? {
        return self.buildInfallibly()
    }
}

#endif

// MARK: - SSKProtoEditMessage

@objc
public class SSKProtoEditMessage: NSObject, Codable, NSSecureCoding {

    fileprivate let proto: SignalServiceProtos_EditMessage

    @objc
    public let dataMessage: SSKProtoDataMessage?

    @objc
    public var targetSentTimestamp: UInt64 {
        return proto.targetSentTimestamp
    }
    @objc
    public var hasTargetSentTimestamp: Bool {
        return proto.hasTargetSentTimestamp
    }

    public var hasUnknownFields: Bool {
        return !proto.unknownFields.data.isEmpty
    }
    public var unknownFields: SwiftProtobuf.UnknownStorage? {
        guard hasUnknownFields else { return nil }
        return proto.unknownFields
    }

    private init(proto: SignalServiceProtos_EditMessage,
                 dataMessage: SSKProtoDataMessage?) {
        self.proto = proto
        self.dataMessage = dataMessage
    }

    @objc
    public func serializedData() throws -> Data {
        return try self.proto.serializedData()
    }

    @objc
    public convenience init(serializedData: Data) throws {
        let proto = try SignalServiceProtos_EditMessage(serializedData: serializedData)
        try self.init(proto)
    }

    fileprivate convenience init(_ proto: SignalServiceProtos_EditMessage) throws {
        var dataMessage: SSKProtoDataMessage?
        if proto.hasDataMessage {
            dataMessage = try SSKProtoDataMessage(proto.dataMessage)
        }

        self.init(proto: proto,
                  dataMessage: dataMessage)
    }

    public required convenience init(from decoder: Swift.Decoder) throws {
        let singleValueContainer = try decoder.singleValueContainer()
        let serializedData = try singleValueContainer.decode(Data.self)
        try self.init(serializedData: serializedData)
    }
    public func encode(to encoder: Swift.Encoder) throws {
        var singleValueContainer = encoder.singleValueContainer()
        try singleValueContainer.encode(try serializedData())
    }

    public static var supportsSecureCoding: Bool { true }

    public required convenience init?(coder: NSCoder) {
        guard let serializedData = coder.decodeData() else { return nil }
        do {
            try self.init(serializedData: serializedData)
        } catch {
            owsFailDebug("Failed to decode serialized data \(error)")
            return nil
        }
    }

    public func encode(with coder: NSCoder) {
        do {
            coder.encode(try serializedData())
        } catch {
            owsFailDebug("Failed to encode serialized data \(error)")
        }
    }

    @objc
    public override var debugDescription: String {
        return "\(proto)"
    }
}

extension SSKProtoEditMessage {
    @objc
    public static func builder() -> SSKProtoEditMessageBuilder {
        return SSKProtoEditMessageBuilder()
    }

    // asBuilder() constructs a builder that reflects the proto's contents.
    @objc
    public func asBuilder() -> SSKProtoEditMessageBuilder {
        let builder = SSKProtoEditMessageBuilder()
        if hasTargetSentTimestamp {
            builder.setTargetSentTimestamp(targetSentTimestamp)
        }
        if let _value = dataMessage {
            builder.setDataMessage(_value)
        }
        if let _value = unknownFields {
            builder.setUnknownFields(_value)
        }
        return builder
    }
}

@objc
public class SSKProtoEditMessageBuilder: NSObject {

    private var proto = SignalServiceProtos_EditMessage()

    @objc
    fileprivate override init() {}

    @objc
    public func setTargetSentTimestamp(_ valueParam: UInt64) {
        proto.targetSentTimestamp = valueParam
    }

    @objc
    @available(swift, obsoleted: 1.0)
    public func setDataMessage(_ valueParam: SSKProtoDataMessage?) {
        guard let valueParam = valueParam else { return }
        proto.dataMessage = valueParam.proto
    }

    public func setDataMessage(_ valueParam: SSKProtoDataMessage) {
        proto.dataMessage = valueParam.proto
    }

    public func setUnknownFields(_ unknownFields: SwiftProtobuf.UnknownStorage) {
        proto.unknownFields = unknownFields
    }

    @objc
    public func build() throws -> SSKProtoEditMessage {
        return try SSKProtoEditMessage(proto)
    }

    @objc
    public func buildSerializedData() throws -> Data {
        return try SSKProtoEditMessage(proto).serializedData()
    }
}

#if TESTABLE_BUILD

extension SSKProtoEditMessage {
    @objc
    public func serializedDataIgnoringErrors() -> Data? {
        return try! self.serializedData()
    }
}

extension SSKProtoEditMessageBuilder {
    @objc
    public func buildIgnoringErrors() -> SSKProtoEditMessage? {
        return try! self.build()
    }
}

#endif
