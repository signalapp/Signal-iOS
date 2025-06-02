//
// Copyright 2022 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
public import SwiftProtobuf

// WARNING: This code is generated. Only edit within the markers.

public enum SignalServiceProtosError: Error {
    case invalidProtobuf(description: String)
}

// MARK: - SignalServiceProtosEnvelopeType

@objc
public enum SignalServiceProtosEnvelopeType: Int32 {
    case unknown = 0
    case ciphertext = 1
    case prekeyBundle = 3
    case receipt = 5
    case unidentifiedSender = 6
    case plaintextContent = 8
}

private func SignalServiceProtosEnvelopeTypeWrap(_ value: SignalServiceProtos_Envelope.TypeEnum) -> SignalServiceProtosEnvelopeType {
    switch value {
    case .unknown: return .unknown
    case .ciphertext: return .ciphertext
    case .prekeyBundle: return .prekeyBundle
    case .receipt: return .receipt
    case .unidentifiedSender: return .unidentifiedSender
    case .plaintextContent: return .plaintextContent
    }
}

private func SignalServiceProtosEnvelopeTypeUnwrap(_ value: SignalServiceProtosEnvelopeType) -> SignalServiceProtos_Envelope.TypeEnum {
    switch value {
    case .unknown: return .unknown
    case .ciphertext: return .ciphertext
    case .prekeyBundle: return .prekeyBundle
    case .receipt: return .receipt
    case .unidentifiedSender: return .unidentifiedSender
    case .plaintextContent: return .plaintextContent
    }
}

// MARK: - SignalServiceProtosEnvelope

@objc
public class SignalServiceProtosEnvelope: NSObject, Codable, NSSecureCoding {

    fileprivate let proto: SignalServiceProtos_Envelope

    @objc
    public let timestamp: UInt64

    public var type: SignalServiceProtosEnvelopeType? {
        guard hasType else {
            return nil
        }
        return SignalServiceProtosEnvelopeTypeWrap(proto.type)
    }
    // This "unwrapped" accessor should only be used if the "has value" accessor has already been checked.
    @objc
    public var unwrappedType: SignalServiceProtosEnvelopeType {
        if !hasType {
            // TODO: We could make this a crashing assert.
            owsFailDebug("Unsafe unwrap of missing optional: Envelope.type.")
        }
        return SignalServiceProtosEnvelopeTypeWrap(proto.type)
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

    @objc
    public var extraLockRequired: Bool {
        return proto.extraLockRequired
    }
    @objc
    public var hasExtraLockRequired: Bool {
        return proto.hasExtraLockRequired
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
    public required convenience init(serializedData: Data) throws {
        let proto = try SignalServiceProtos_Envelope(serializedBytes: serializedData)
        try self.init(proto)
    }

    fileprivate convenience init(_ proto: SignalServiceProtos_Envelope) throws {
        guard proto.hasTimestamp else {
            throw SignalServiceProtosError.invalidProtobuf(description: "[\(Self.self)] missing required field: timestamp")
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

extension SignalServiceProtosEnvelope {
    @objc
    public static func builder(timestamp: UInt64) -> SignalServiceProtosEnvelopeBuilder {
        return SignalServiceProtosEnvelopeBuilder(timestamp: timestamp)
    }

    // asBuilder() constructs a builder that reflects the proto's contents.
    @objc
    public func asBuilder() -> SignalServiceProtosEnvelopeBuilder {
        let builder = SignalServiceProtosEnvelopeBuilder(timestamp: timestamp)
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
        if hasExtraLockRequired {
            builder.setExtraLockRequired(extraLockRequired)
        }
        if let _value = unknownFields {
            builder.setUnknownFields(_value)
        }
        return builder
    }
}

@objc
public class SignalServiceProtosEnvelopeBuilder: NSObject {

    private var proto = SignalServiceProtos_Envelope()

    @objc
    fileprivate override init() {}

    @objc
    fileprivate init(timestamp: UInt64) {
        super.init()

        setTimestamp(timestamp)
    }

    @objc
    public func setType(_ valueParam: SignalServiceProtosEnvelopeType) {
        proto.type = SignalServiceProtosEnvelopeTypeUnwrap(valueParam)
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

    @objc
    public func setExtraLockRequired(_ valueParam: Bool) {
        proto.extraLockRequired = valueParam
    }

    public func setUnknownFields(_ unknownFields: SwiftProtobuf.UnknownStorage) {
        proto.unknownFields = unknownFields
    }

    @objc
    public func build() throws -> SignalServiceProtosEnvelope {
        return try SignalServiceProtosEnvelope(proto)
    }

    @objc
    public func buildSerializedData() throws -> Data {
        return try SignalServiceProtosEnvelope(proto).serializedData()
    }
}

#if TESTABLE_BUILD

extension SignalServiceProtosEnvelope {
    @objc
    public func serializedDataIgnoringErrors() -> Data? {
        return try! self.serializedData()
    }
}

extension SignalServiceProtosEnvelopeBuilder {
    @objc
    public func buildIgnoringErrors() -> SignalServiceProtosEnvelope? {
        return try! self.build()
    }
}

#endif

// MARK: - SignalServiceProtosTypingMessageAction

@objc
public enum SignalServiceProtosTypingMessageAction: Int32 {
    case started = 0
    case stopped = 1
}

private func SignalServiceProtosTypingMessageActionWrap(_ value: SignalServiceProtos_TypingMessage.Action) -> SignalServiceProtosTypingMessageAction {
    switch value {
    case .started: return .started
    case .stopped: return .stopped
    }
}

private func SignalServiceProtosTypingMessageActionUnwrap(_ value: SignalServiceProtosTypingMessageAction) -> SignalServiceProtos_TypingMessage.Action {
    switch value {
    case .started: return .started
    case .stopped: return .stopped
    }
}

// MARK: - SignalServiceProtosTypingMessage

@objc
public class SignalServiceProtosTypingMessage: NSObject, Codable, NSSecureCoding {

    fileprivate let proto: SignalServiceProtos_TypingMessage

    @objc
    public let timestamp: UInt64

    public var action: SignalServiceProtosTypingMessageAction? {
        guard hasAction else {
            return nil
        }
        return SignalServiceProtosTypingMessageActionWrap(proto.action)
    }
    // This "unwrapped" accessor should only be used if the "has value" accessor has already been checked.
    @objc
    public var unwrappedAction: SignalServiceProtosTypingMessageAction {
        if !hasAction {
            // TODO: We could make this a crashing assert.
            owsFailDebug("Unsafe unwrap of missing optional: TypingMessage.action.")
        }
        return SignalServiceProtosTypingMessageActionWrap(proto.action)
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
    public required convenience init(serializedData: Data) throws {
        let proto = try SignalServiceProtos_TypingMessage(serializedBytes: serializedData)
        try self.init(proto)
    }

    fileprivate convenience init(_ proto: SignalServiceProtos_TypingMessage) throws {
        guard proto.hasTimestamp else {
            throw SignalServiceProtosError.invalidProtobuf(description: "[\(Self.self)] missing required field: timestamp")
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

extension SignalServiceProtosTypingMessage {
    @objc
    public static func builder(timestamp: UInt64) -> SignalServiceProtosTypingMessageBuilder {
        return SignalServiceProtosTypingMessageBuilder(timestamp: timestamp)
    }

    // asBuilder() constructs a builder that reflects the proto's contents.
    @objc
    public func asBuilder() -> SignalServiceProtosTypingMessageBuilder {
        let builder = SignalServiceProtosTypingMessageBuilder(timestamp: timestamp)
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
public class SignalServiceProtosTypingMessageBuilder: NSObject {

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
    public func setAction(_ valueParam: SignalServiceProtosTypingMessageAction) {
        proto.action = SignalServiceProtosTypingMessageActionUnwrap(valueParam)
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
    public func build() throws -> SignalServiceProtosTypingMessage {
        return try SignalServiceProtosTypingMessage(proto)
    }

    @objc
    public func buildSerializedData() throws -> Data {
        return try SignalServiceProtosTypingMessage(proto).serializedData()
    }
}

#if TESTABLE_BUILD

extension SignalServiceProtosTypingMessage {
    @objc
    public func serializedDataIgnoringErrors() -> Data? {
        return try! self.serializedData()
    }
}

extension SignalServiceProtosTypingMessageBuilder {
    @objc
    public func buildIgnoringErrors() -> SignalServiceProtosTypingMessage? {
        return try! self.build()
    }
}

#endif

// MARK: - SignalServiceProtosStoryMessage

@objc
public class SignalServiceProtosStoryMessage: NSObject, Codable, NSSecureCoding {

    fileprivate let proto: SignalServiceProtos_StoryMessage

    @objc
    public let group: SignalServiceProtosGroupContextV2?

    @objc
    public let fileAttachment: SignalServiceProtosAttachmentPointer?

    @objc
    public let textAttachment: SignalServiceProtosTextAttachment?

    @objc
    public let bodyRanges: [SignalServiceProtosBodyRange]

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
                 group: SignalServiceProtosGroupContextV2?,
                 fileAttachment: SignalServiceProtosAttachmentPointer?,
                 textAttachment: SignalServiceProtosTextAttachment?,
                 bodyRanges: [SignalServiceProtosBodyRange]) {
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
    public required convenience init(serializedData: Data) throws {
        let proto = try SignalServiceProtos_StoryMessage(serializedBytes: serializedData)
        try self.init(proto)
    }

    fileprivate convenience init(_ proto: SignalServiceProtos_StoryMessage) throws {
        var group: SignalServiceProtosGroupContextV2?
        if proto.hasGroup {
            group = SignalServiceProtosGroupContextV2(proto.group)
        }

        var fileAttachment: SignalServiceProtosAttachmentPointer?
        if proto.hasFileAttachment {
            fileAttachment = SignalServiceProtosAttachmentPointer(proto.fileAttachment)
        }

        var textAttachment: SignalServiceProtosTextAttachment?
        if proto.hasTextAttachment {
            textAttachment = try SignalServiceProtosTextAttachment(proto.textAttachment)
        }

        var bodyRanges: [SignalServiceProtosBodyRange] = []
        bodyRanges = proto.bodyRanges.map { SignalServiceProtosBodyRange($0) }

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

extension SignalServiceProtosStoryMessage {
    @objc
    public static func builder() -> SignalServiceProtosStoryMessageBuilder {
        return SignalServiceProtosStoryMessageBuilder()
    }

    // asBuilder() constructs a builder that reflects the proto's contents.
    @objc
    public func asBuilder() -> SignalServiceProtosStoryMessageBuilder {
        let builder = SignalServiceProtosStoryMessageBuilder()
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
public class SignalServiceProtosStoryMessageBuilder: NSObject {

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
    public func setGroup(_ valueParam: SignalServiceProtosGroupContextV2?) {
        guard let valueParam = valueParam else { return }
        proto.group = valueParam.proto
    }

    public func setGroup(_ valueParam: SignalServiceProtosGroupContextV2) {
        proto.group = valueParam.proto
    }

    @objc
    @available(swift, obsoleted: 1.0)
    public func setFileAttachment(_ valueParam: SignalServiceProtosAttachmentPointer?) {
        guard let valueParam = valueParam else { return }
        proto.fileAttachment = valueParam.proto
    }

    public func setFileAttachment(_ valueParam: SignalServiceProtosAttachmentPointer) {
        proto.fileAttachment = valueParam.proto
    }

    @objc
    @available(swift, obsoleted: 1.0)
    public func setTextAttachment(_ valueParam: SignalServiceProtosTextAttachment?) {
        guard let valueParam = valueParam else { return }
        proto.textAttachment = valueParam.proto
    }

    public func setTextAttachment(_ valueParam: SignalServiceProtosTextAttachment) {
        proto.textAttachment = valueParam.proto
    }

    @objc
    public func setAllowsReplies(_ valueParam: Bool) {
        proto.allowsReplies = valueParam
    }

    @objc
    public func addBodyRanges(_ valueParam: SignalServiceProtosBodyRange) {
        proto.bodyRanges.append(valueParam.proto)
    }

    @objc
    public func setBodyRanges(_ wrappedItems: [SignalServiceProtosBodyRange]) {
        proto.bodyRanges = wrappedItems.map { $0.proto }
    }

    public func setUnknownFields(_ unknownFields: SwiftProtobuf.UnknownStorage) {
        proto.unknownFields = unknownFields
    }

    @objc
    public func build() throws -> SignalServiceProtosStoryMessage {
        return try SignalServiceProtosStoryMessage(proto)
    }

    @objc
    public func buildSerializedData() throws -> Data {
        return try SignalServiceProtosStoryMessage(proto).serializedData()
    }
}

#if TESTABLE_BUILD

extension SignalServiceProtosStoryMessage {
    @objc
    public func serializedDataIgnoringErrors() -> Data? {
        return try! self.serializedData()
    }
}

extension SignalServiceProtosStoryMessageBuilder {
    @objc
    public func buildIgnoringErrors() -> SignalServiceProtosStoryMessage? {
        return try! self.build()
    }
}

#endif

// MARK: - SignalServiceProtosPreview

@objc
public class SignalServiceProtosPreview: NSObject, Codable, NSSecureCoding {

    fileprivate let proto: SignalServiceProtos_Preview

    @objc
    public let url: String

    @objc
    public let image: SignalServiceProtosAttachmentPointer?

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
                 image: SignalServiceProtosAttachmentPointer?) {
        self.proto = proto
        self.url = url
        self.image = image
    }

    @objc
    public func serializedData() throws -> Data {
        return try self.proto.serializedData()
    }

    @objc
    public required convenience init(serializedData: Data) throws {
        let proto = try SignalServiceProtos_Preview(serializedBytes: serializedData)
        try self.init(proto)
    }

    fileprivate convenience init(_ proto: SignalServiceProtos_Preview) throws {
        guard proto.hasURL else {
            throw SignalServiceProtosError.invalidProtobuf(description: "[\(Self.self)] missing required field: url")
        }
        let url = proto.url

        var image: SignalServiceProtosAttachmentPointer?
        if proto.hasImage {
            image = SignalServiceProtosAttachmentPointer(proto.image)
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

extension SignalServiceProtosPreview {
    @objc
    public static func builder(url: String) -> SignalServiceProtosPreviewBuilder {
        return SignalServiceProtosPreviewBuilder(url: url)
    }

    // asBuilder() constructs a builder that reflects the proto's contents.
    @objc
    public func asBuilder() -> SignalServiceProtosPreviewBuilder {
        let builder = SignalServiceProtosPreviewBuilder(url: url)
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
public class SignalServiceProtosPreviewBuilder: NSObject {

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
    public func setImage(_ valueParam: SignalServiceProtosAttachmentPointer?) {
        guard let valueParam = valueParam else { return }
        proto.image = valueParam.proto
    }

    public func setImage(_ valueParam: SignalServiceProtosAttachmentPointer) {
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
    public func build() throws -> SignalServiceProtosPreview {
        return try SignalServiceProtosPreview(proto)
    }

    @objc
    public func buildSerializedData() throws -> Data {
        return try SignalServiceProtosPreview(proto).serializedData()
    }
}

#if TESTABLE_BUILD

extension SignalServiceProtosPreview {
    @objc
    public func serializedDataIgnoringErrors() -> Data? {
        return try! self.serializedData()
    }
}

extension SignalServiceProtosPreviewBuilder {
    @objc
    public func buildIgnoringErrors() -> SignalServiceProtosPreview? {
        return try! self.build()
    }
}

#endif

// MARK: - SignalServiceProtosTextAttachmentGradient

@objc
public class SignalServiceProtosTextAttachmentGradient: NSObject, Codable, NSSecureCoding {

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
    public required convenience init(serializedData: Data) throws {
        let proto = try SignalServiceProtos_TextAttachment.Gradient(serializedBytes: serializedData)
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

extension SignalServiceProtosTextAttachmentGradient {
    @objc
    public static func builder() -> SignalServiceProtosTextAttachmentGradientBuilder {
        return SignalServiceProtosTextAttachmentGradientBuilder()
    }

    // asBuilder() constructs a builder that reflects the proto's contents.
    @objc
    public func asBuilder() -> SignalServiceProtosTextAttachmentGradientBuilder {
        let builder = SignalServiceProtosTextAttachmentGradientBuilder()
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
public class SignalServiceProtosTextAttachmentGradientBuilder: NSObject {

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
    public func buildInfallibly() -> SignalServiceProtosTextAttachmentGradient {
        return SignalServiceProtosTextAttachmentGradient(proto)
    }

    @objc
    public func buildSerializedData() throws -> Data {
        return try SignalServiceProtosTextAttachmentGradient(proto).serializedData()
    }
}

#if TESTABLE_BUILD

extension SignalServiceProtosTextAttachmentGradient {
    @objc
    public func serializedDataIgnoringErrors() -> Data? {
        return try! self.serializedData()
    }
}

extension SignalServiceProtosTextAttachmentGradientBuilder {
    @objc
    public func buildIgnoringErrors() -> SignalServiceProtosTextAttachmentGradient? {
        return self.buildInfallibly()
    }
}

#endif

// MARK: - SignalServiceProtosTextAttachmentStyle

@objc
public enum SignalServiceProtosTextAttachmentStyle: Int32 {
    case `default` = 0
    case regular = 1
    case bold = 2
    case serif = 3
    case script = 4
    case condensed = 5
}

private func SignalServiceProtosTextAttachmentStyleWrap(_ value: SignalServiceProtos_TextAttachment.Style) -> SignalServiceProtosTextAttachmentStyle {
    switch value {
    case .default: return .default
    case .regular: return .regular
    case .bold: return .bold
    case .serif: return .serif
    case .script: return .script
    case .condensed: return .condensed
    }
}

private func SignalServiceProtosTextAttachmentStyleUnwrap(_ value: SignalServiceProtosTextAttachmentStyle) -> SignalServiceProtos_TextAttachment.Style {
    switch value {
    case .default: return .default
    case .regular: return .regular
    case .bold: return .bold
    case .serif: return .serif
    case .script: return .script
    case .condensed: return .condensed
    }
}

// MARK: - SignalServiceProtosTextAttachment

@objc
public class SignalServiceProtosTextAttachment: NSObject, Codable, NSSecureCoding {

    fileprivate let proto: SignalServiceProtos_TextAttachment

    @objc
    public let preview: SignalServiceProtosPreview?

    @objc
    public let gradient: SignalServiceProtosTextAttachmentGradient?

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

    public var textStyle: SignalServiceProtosTextAttachmentStyle? {
        guard hasTextStyle else {
            return nil
        }
        return SignalServiceProtosTextAttachmentStyleWrap(proto.textStyle)
    }
    // This "unwrapped" accessor should only be used if the "has value" accessor has already been checked.
    @objc
    public var unwrappedTextStyle: SignalServiceProtosTextAttachmentStyle {
        if !hasTextStyle {
            // TODO: We could make this a crashing assert.
            owsFailDebug("Unsafe unwrap of missing optional: TextAttachment.textStyle.")
        }
        return SignalServiceProtosTextAttachmentStyleWrap(proto.textStyle)
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
                 preview: SignalServiceProtosPreview?,
                 gradient: SignalServiceProtosTextAttachmentGradient?) {
        self.proto = proto
        self.preview = preview
        self.gradient = gradient
    }

    @objc
    public func serializedData() throws -> Data {
        return try self.proto.serializedData()
    }

    @objc
    public required convenience init(serializedData: Data) throws {
        let proto = try SignalServiceProtos_TextAttachment(serializedBytes: serializedData)
        try self.init(proto)
    }

    fileprivate convenience init(_ proto: SignalServiceProtos_TextAttachment) throws {
        var preview: SignalServiceProtosPreview?
        if proto.hasPreview {
            preview = try SignalServiceProtosPreview(proto.preview)
        }

        var gradient: SignalServiceProtosTextAttachmentGradient?
        if proto.hasGradient {
            gradient = SignalServiceProtosTextAttachmentGradient(proto.gradient)
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

extension SignalServiceProtosTextAttachment {
    @objc
    public static func builder() -> SignalServiceProtosTextAttachmentBuilder {
        return SignalServiceProtosTextAttachmentBuilder()
    }

    // asBuilder() constructs a builder that reflects the proto's contents.
    @objc
    public func asBuilder() -> SignalServiceProtosTextAttachmentBuilder {
        let builder = SignalServiceProtosTextAttachmentBuilder()
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
public class SignalServiceProtosTextAttachmentBuilder: NSObject {

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
    public func setTextStyle(_ valueParam: SignalServiceProtosTextAttachmentStyle) {
        proto.textStyle = SignalServiceProtosTextAttachmentStyleUnwrap(valueParam)
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
    public func setPreview(_ valueParam: SignalServiceProtosPreview?) {
        guard let valueParam = valueParam else { return }
        proto.preview = valueParam.proto
    }

    public func setPreview(_ valueParam: SignalServiceProtosPreview) {
        proto.preview = valueParam.proto
    }

    @objc
    @available(swift, obsoleted: 1.0)
    public func setGradient(_ valueParam: SignalServiceProtosTextAttachmentGradient?) {
        guard let valueParam = valueParam else { return }
        proto.gradient = valueParam.proto
    }

    public func setGradient(_ valueParam: SignalServiceProtosTextAttachmentGradient) {
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
    public func build() throws -> SignalServiceProtosTextAttachment {
        return try SignalServiceProtosTextAttachment(proto)
    }

    @objc
    public func buildSerializedData() throws -> Data {
        return try SignalServiceProtosTextAttachment(proto).serializedData()
    }
}

#if TESTABLE_BUILD

extension SignalServiceProtosTextAttachment {
    @objc
    public func serializedDataIgnoringErrors() -> Data? {
        return try! self.serializedData()
    }
}

extension SignalServiceProtosTextAttachmentBuilder {
    @objc
    public func buildIgnoringErrors() -> SignalServiceProtosTextAttachment? {
        return try! self.build()
    }
}

#endif

// MARK: - SignalServiceProtosContent

@objc
public class SignalServiceProtosContent: NSObject, Codable, NSSecureCoding {

    fileprivate let proto: SignalServiceProtos_Content

    @objc
    public let dataMessage: SignalServiceProtosDataMessage?

    @objc
    public let syncMessage: SignalServiceProtosSyncMessage?

    @objc
    public let callMessage: SignalServiceProtosCallMessage?

    @objc
    public let nullMessage: SignalServiceProtosNullMessage?

    @objc
    public let receiptMessage: SignalServiceProtosReceiptMessage?

    @objc
    public let typingMessage: SignalServiceProtosTypingMessage?

    @objc
    public let storyMessage: SignalServiceProtosStoryMessage?

    @objc
    public let pniSignatureMessage: SignalServiceProtosPniSignatureMessage?

    @objc
    public let editMessage: SignalServiceProtosEditMessage?

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
                 dataMessage: SignalServiceProtosDataMessage?,
                 syncMessage: SignalServiceProtosSyncMessage?,
                 callMessage: SignalServiceProtosCallMessage?,
                 nullMessage: SignalServiceProtosNullMessage?,
                 receiptMessage: SignalServiceProtosReceiptMessage?,
                 typingMessage: SignalServiceProtosTypingMessage?,
                 storyMessage: SignalServiceProtosStoryMessage?,
                 pniSignatureMessage: SignalServiceProtosPniSignatureMessage?,
                 editMessage: SignalServiceProtosEditMessage?) {
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
    public required convenience init(serializedData: Data) throws {
        let proto = try SignalServiceProtos_Content(serializedBytes: serializedData)
        try self.init(proto)
    }

    fileprivate convenience init(_ proto: SignalServiceProtos_Content) throws {
        var dataMessage: SignalServiceProtosDataMessage?
        if proto.hasDataMessage {
            dataMessage = try SignalServiceProtosDataMessage(proto.dataMessage)
        }

        var syncMessage: SignalServiceProtosSyncMessage?
        if proto.hasSyncMessage {
            syncMessage = try SignalServiceProtosSyncMessage(proto.syncMessage)
        }

        var callMessage: SignalServiceProtosCallMessage?
        if proto.hasCallMessage {
            callMessage = try SignalServiceProtosCallMessage(proto.callMessage)
        }

        var nullMessage: SignalServiceProtosNullMessage?
        if proto.hasNullMessage {
            nullMessage = SignalServiceProtosNullMessage(proto.nullMessage)
        }

        var receiptMessage: SignalServiceProtosReceiptMessage?
        if proto.hasReceiptMessage {
            receiptMessage = SignalServiceProtosReceiptMessage(proto.receiptMessage)
        }

        var typingMessage: SignalServiceProtosTypingMessage?
        if proto.hasTypingMessage {
            typingMessage = try SignalServiceProtosTypingMessage(proto.typingMessage)
        }

        var storyMessage: SignalServiceProtosStoryMessage?
        if proto.hasStoryMessage {
            storyMessage = try SignalServiceProtosStoryMessage(proto.storyMessage)
        }

        var pniSignatureMessage: SignalServiceProtosPniSignatureMessage?
        if proto.hasPniSignatureMessage {
            pniSignatureMessage = SignalServiceProtosPniSignatureMessage(proto.pniSignatureMessage)
        }

        var editMessage: SignalServiceProtosEditMessage?
        if proto.hasEditMessage {
            editMessage = try SignalServiceProtosEditMessage(proto.editMessage)
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

extension SignalServiceProtosContent {
    @objc
    public static func builder() -> SignalServiceProtosContentBuilder {
        return SignalServiceProtosContentBuilder()
    }

    // asBuilder() constructs a builder that reflects the proto's contents.
    @objc
    public func asBuilder() -> SignalServiceProtosContentBuilder {
        let builder = SignalServiceProtosContentBuilder()
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
public class SignalServiceProtosContentBuilder: NSObject {

    private var proto = SignalServiceProtos_Content()

    @objc
    fileprivate override init() {}

    @objc
    @available(swift, obsoleted: 1.0)
    public func setDataMessage(_ valueParam: SignalServiceProtosDataMessage?) {
        guard let valueParam = valueParam else { return }
        proto.dataMessage = valueParam.proto
    }

    public func setDataMessage(_ valueParam: SignalServiceProtosDataMessage) {
        proto.dataMessage = valueParam.proto
    }

    @objc
    @available(swift, obsoleted: 1.0)
    public func setSyncMessage(_ valueParam: SignalServiceProtosSyncMessage?) {
        guard let valueParam = valueParam else { return }
        proto.syncMessage = valueParam.proto
    }

    public func setSyncMessage(_ valueParam: SignalServiceProtosSyncMessage) {
        proto.syncMessage = valueParam.proto
    }

    @objc
    @available(swift, obsoleted: 1.0)
    public func setCallMessage(_ valueParam: SignalServiceProtosCallMessage?) {
        guard let valueParam = valueParam else { return }
        proto.callMessage = valueParam.proto
    }

    public func setCallMessage(_ valueParam: SignalServiceProtosCallMessage) {
        proto.callMessage = valueParam.proto
    }

    @objc
    @available(swift, obsoleted: 1.0)
    public func setNullMessage(_ valueParam: SignalServiceProtosNullMessage?) {
        guard let valueParam = valueParam else { return }
        proto.nullMessage = valueParam.proto
    }

    public func setNullMessage(_ valueParam: SignalServiceProtosNullMessage) {
        proto.nullMessage = valueParam.proto
    }

    @objc
    @available(swift, obsoleted: 1.0)
    public func setReceiptMessage(_ valueParam: SignalServiceProtosReceiptMessage?) {
        guard let valueParam = valueParam else { return }
        proto.receiptMessage = valueParam.proto
    }

    public func setReceiptMessage(_ valueParam: SignalServiceProtosReceiptMessage) {
        proto.receiptMessage = valueParam.proto
    }

    @objc
    @available(swift, obsoleted: 1.0)
    public func setTypingMessage(_ valueParam: SignalServiceProtosTypingMessage?) {
        guard let valueParam = valueParam else { return }
        proto.typingMessage = valueParam.proto
    }

    public func setTypingMessage(_ valueParam: SignalServiceProtosTypingMessage) {
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
    public func setStoryMessage(_ valueParam: SignalServiceProtosStoryMessage?) {
        guard let valueParam = valueParam else { return }
        proto.storyMessage = valueParam.proto
    }

    public func setStoryMessage(_ valueParam: SignalServiceProtosStoryMessage) {
        proto.storyMessage = valueParam.proto
    }

    @objc
    @available(swift, obsoleted: 1.0)
    public func setPniSignatureMessage(_ valueParam: SignalServiceProtosPniSignatureMessage?) {
        guard let valueParam = valueParam else { return }
        proto.pniSignatureMessage = valueParam.proto
    }

    public func setPniSignatureMessage(_ valueParam: SignalServiceProtosPniSignatureMessage) {
        proto.pniSignatureMessage = valueParam.proto
    }

    @objc
    @available(swift, obsoleted: 1.0)
    public func setEditMessage(_ valueParam: SignalServiceProtosEditMessage?) {
        guard let valueParam = valueParam else { return }
        proto.editMessage = valueParam.proto
    }

    public func setEditMessage(_ valueParam: SignalServiceProtosEditMessage) {
        proto.editMessage = valueParam.proto
    }

    public func setUnknownFields(_ unknownFields: SwiftProtobuf.UnknownStorage) {
        proto.unknownFields = unknownFields
    }

    @objc
    public func build() throws -> SignalServiceProtosContent {
        return try SignalServiceProtosContent(proto)
    }

    @objc
    public func buildSerializedData() throws -> Data {
        return try SignalServiceProtosContent(proto).serializedData()
    }
}

#if TESTABLE_BUILD

extension SignalServiceProtosContent {
    @objc
    public func serializedDataIgnoringErrors() -> Data? {
        return try! self.serializedData()
    }
}

extension SignalServiceProtosContentBuilder {
    @objc
    public func buildIgnoringErrors() -> SignalServiceProtosContent? {
        return try! self.build()
    }
}

#endif

// MARK: - SignalServiceProtosCallMessageOfferType

@objc
public enum SignalServiceProtosCallMessageOfferType: Int32 {
    case offerAudioCall = 0
    case offerVideoCall = 1
}

private func SignalServiceProtosCallMessageOfferTypeWrap(_ value: SignalServiceProtos_CallMessage.Offer.TypeEnum) -> SignalServiceProtosCallMessageOfferType {
    switch value {
    case .offerAudioCall: return .offerAudioCall
    case .offerVideoCall: return .offerVideoCall
    }
}

private func SignalServiceProtosCallMessageOfferTypeUnwrap(_ value: SignalServiceProtosCallMessageOfferType) -> SignalServiceProtos_CallMessage.Offer.TypeEnum {
    switch value {
    case .offerAudioCall: return .offerAudioCall
    case .offerVideoCall: return .offerVideoCall
    }
}

// MARK: - SignalServiceProtosCallMessageOffer

@objc
public class SignalServiceProtosCallMessageOffer: NSObject, Codable, NSSecureCoding {

    fileprivate let proto: SignalServiceProtos_CallMessage.Offer

    @objc
    public let id: UInt64

    public var type: SignalServiceProtosCallMessageOfferType? {
        guard hasType else {
            return nil
        }
        return SignalServiceProtosCallMessageOfferTypeWrap(proto.type)
    }
    // This "unwrapped" accessor should only be used if the "has value" accessor has already been checked.
    @objc
    public var unwrappedType: SignalServiceProtosCallMessageOfferType {
        if !hasType {
            // TODO: We could make this a crashing assert.
            owsFailDebug("Unsafe unwrap of missing optional: Offer.type.")
        }
        return SignalServiceProtosCallMessageOfferTypeWrap(proto.type)
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
    public required convenience init(serializedData: Data) throws {
        let proto = try SignalServiceProtos_CallMessage.Offer(serializedBytes: serializedData)
        try self.init(proto)
    }

    fileprivate convenience init(_ proto: SignalServiceProtos_CallMessage.Offer) throws {
        guard proto.hasID else {
            throw SignalServiceProtosError.invalidProtobuf(description: "[\(Self.self)] missing required field: id")
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

extension SignalServiceProtosCallMessageOffer {
    @objc
    public static func builder(id: UInt64) -> SignalServiceProtosCallMessageOfferBuilder {
        return SignalServiceProtosCallMessageOfferBuilder(id: id)
    }

    // asBuilder() constructs a builder that reflects the proto's contents.
    @objc
    public func asBuilder() -> SignalServiceProtosCallMessageOfferBuilder {
        let builder = SignalServiceProtosCallMessageOfferBuilder(id: id)
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
public class SignalServiceProtosCallMessageOfferBuilder: NSObject {

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
    public func setType(_ valueParam: SignalServiceProtosCallMessageOfferType) {
        proto.type = SignalServiceProtosCallMessageOfferTypeUnwrap(valueParam)
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
    public func build() throws -> SignalServiceProtosCallMessageOffer {
        return try SignalServiceProtosCallMessageOffer(proto)
    }

    @objc
    public func buildSerializedData() throws -> Data {
        return try SignalServiceProtosCallMessageOffer(proto).serializedData()
    }
}

#if TESTABLE_BUILD

extension SignalServiceProtosCallMessageOffer {
    @objc
    public func serializedDataIgnoringErrors() -> Data? {
        return try! self.serializedData()
    }
}

extension SignalServiceProtosCallMessageOfferBuilder {
    @objc
    public func buildIgnoringErrors() -> SignalServiceProtosCallMessageOffer? {
        return try! self.build()
    }
}

#endif

// MARK: - SignalServiceProtosCallMessageAnswer

@objc
public class SignalServiceProtosCallMessageAnswer: NSObject, Codable, NSSecureCoding {

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
    public required convenience init(serializedData: Data) throws {
        let proto = try SignalServiceProtos_CallMessage.Answer(serializedBytes: serializedData)
        try self.init(proto)
    }

    fileprivate convenience init(_ proto: SignalServiceProtos_CallMessage.Answer) throws {
        guard proto.hasID else {
            throw SignalServiceProtosError.invalidProtobuf(description: "[\(Self.self)] missing required field: id")
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

extension SignalServiceProtosCallMessageAnswer {
    @objc
    public static func builder(id: UInt64) -> SignalServiceProtosCallMessageAnswerBuilder {
        return SignalServiceProtosCallMessageAnswerBuilder(id: id)
    }

    // asBuilder() constructs a builder that reflects the proto's contents.
    @objc
    public func asBuilder() -> SignalServiceProtosCallMessageAnswerBuilder {
        let builder = SignalServiceProtosCallMessageAnswerBuilder(id: id)
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
public class SignalServiceProtosCallMessageAnswerBuilder: NSObject {

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
    public func build() throws -> SignalServiceProtosCallMessageAnswer {
        return try SignalServiceProtosCallMessageAnswer(proto)
    }

    @objc
    public func buildSerializedData() throws -> Data {
        return try SignalServiceProtosCallMessageAnswer(proto).serializedData()
    }
}

#if TESTABLE_BUILD

extension SignalServiceProtosCallMessageAnswer {
    @objc
    public func serializedDataIgnoringErrors() -> Data? {
        return try! self.serializedData()
    }
}

extension SignalServiceProtosCallMessageAnswerBuilder {
    @objc
    public func buildIgnoringErrors() -> SignalServiceProtosCallMessageAnswer? {
        return try! self.build()
    }
}

#endif

// MARK: - SignalServiceProtosCallMessageIceUpdate

@objc
public class SignalServiceProtosCallMessageIceUpdate: NSObject, Codable, NSSecureCoding {

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
    public required convenience init(serializedData: Data) throws {
        let proto = try SignalServiceProtos_CallMessage.IceUpdate(serializedBytes: serializedData)
        try self.init(proto)
    }

    fileprivate convenience init(_ proto: SignalServiceProtos_CallMessage.IceUpdate) throws {
        guard proto.hasID else {
            throw SignalServiceProtosError.invalidProtobuf(description: "[\(Self.self)] missing required field: id")
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

extension SignalServiceProtosCallMessageIceUpdate {
    @objc
    public static func builder(id: UInt64) -> SignalServiceProtosCallMessageIceUpdateBuilder {
        return SignalServiceProtosCallMessageIceUpdateBuilder(id: id)
    }

    // asBuilder() constructs a builder that reflects the proto's contents.
    @objc
    public func asBuilder() -> SignalServiceProtosCallMessageIceUpdateBuilder {
        let builder = SignalServiceProtosCallMessageIceUpdateBuilder(id: id)
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
public class SignalServiceProtosCallMessageIceUpdateBuilder: NSObject {

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
    public func build() throws -> SignalServiceProtosCallMessageIceUpdate {
        return try SignalServiceProtosCallMessageIceUpdate(proto)
    }

    @objc
    public func buildSerializedData() throws -> Data {
        return try SignalServiceProtosCallMessageIceUpdate(proto).serializedData()
    }
}

#if TESTABLE_BUILD

extension SignalServiceProtosCallMessageIceUpdate {
    @objc
    public func serializedDataIgnoringErrors() -> Data? {
        return try! self.serializedData()
    }
}

extension SignalServiceProtosCallMessageIceUpdateBuilder {
    @objc
    public func buildIgnoringErrors() -> SignalServiceProtosCallMessageIceUpdate? {
        return try! self.build()
    }
}

#endif

// MARK: - SignalServiceProtosCallMessageBusy

@objc
public class SignalServiceProtosCallMessageBusy: NSObject, Codable, NSSecureCoding {

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
    public required convenience init(serializedData: Data) throws {
        let proto = try SignalServiceProtos_CallMessage.Busy(serializedBytes: serializedData)
        try self.init(proto)
    }

    fileprivate convenience init(_ proto: SignalServiceProtos_CallMessage.Busy) throws {
        guard proto.hasID else {
            throw SignalServiceProtosError.invalidProtobuf(description: "[\(Self.self)] missing required field: id")
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

extension SignalServiceProtosCallMessageBusy {
    @objc
    public static func builder(id: UInt64) -> SignalServiceProtosCallMessageBusyBuilder {
        return SignalServiceProtosCallMessageBusyBuilder(id: id)
    }

    // asBuilder() constructs a builder that reflects the proto's contents.
    @objc
    public func asBuilder() -> SignalServiceProtosCallMessageBusyBuilder {
        let builder = SignalServiceProtosCallMessageBusyBuilder(id: id)
        if let _value = unknownFields {
            builder.setUnknownFields(_value)
        }
        return builder
    }
}

@objc
public class SignalServiceProtosCallMessageBusyBuilder: NSObject {

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
    public func build() throws -> SignalServiceProtosCallMessageBusy {
        return try SignalServiceProtosCallMessageBusy(proto)
    }

    @objc
    public func buildSerializedData() throws -> Data {
        return try SignalServiceProtosCallMessageBusy(proto).serializedData()
    }
}

#if TESTABLE_BUILD

extension SignalServiceProtosCallMessageBusy {
    @objc
    public func serializedDataIgnoringErrors() -> Data? {
        return try! self.serializedData()
    }
}

extension SignalServiceProtosCallMessageBusyBuilder {
    @objc
    public func buildIgnoringErrors() -> SignalServiceProtosCallMessageBusy? {
        return try! self.build()
    }
}

#endif

// MARK: - SignalServiceProtosCallMessageHangupType

@objc
public enum SignalServiceProtosCallMessageHangupType: Int32 {
    case hangupNormal = 0
    case hangupAccepted = 1
    case hangupDeclined = 2
    case hangupBusy = 3
    case hangupNeedPermission = 4
}

private func SignalServiceProtosCallMessageHangupTypeWrap(_ value: SignalServiceProtos_CallMessage.Hangup.TypeEnum) -> SignalServiceProtosCallMessageHangupType {
    switch value {
    case .hangupNormal: return .hangupNormal
    case .hangupAccepted: return .hangupAccepted
    case .hangupDeclined: return .hangupDeclined
    case .hangupBusy: return .hangupBusy
    case .hangupNeedPermission: return .hangupNeedPermission
    }
}

private func SignalServiceProtosCallMessageHangupTypeUnwrap(_ value: SignalServiceProtosCallMessageHangupType) -> SignalServiceProtos_CallMessage.Hangup.TypeEnum {
    switch value {
    case .hangupNormal: return .hangupNormal
    case .hangupAccepted: return .hangupAccepted
    case .hangupDeclined: return .hangupDeclined
    case .hangupBusy: return .hangupBusy
    case .hangupNeedPermission: return .hangupNeedPermission
    }
}

// MARK: - SignalServiceProtosCallMessageHangup

@objc
public class SignalServiceProtosCallMessageHangup: NSObject, Codable, NSSecureCoding {

    fileprivate let proto: SignalServiceProtos_CallMessage.Hangup

    @objc
    public let id: UInt64

    public var type: SignalServiceProtosCallMessageHangupType? {
        guard hasType else {
            return nil
        }
        return SignalServiceProtosCallMessageHangupTypeWrap(proto.type)
    }
    // This "unwrapped" accessor should only be used if the "has value" accessor has already been checked.
    @objc
    public var unwrappedType: SignalServiceProtosCallMessageHangupType {
        if !hasType {
            // TODO: We could make this a crashing assert.
            owsFailDebug("Unsafe unwrap of missing optional: Hangup.type.")
        }
        return SignalServiceProtosCallMessageHangupTypeWrap(proto.type)
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
    public required convenience init(serializedData: Data) throws {
        let proto = try SignalServiceProtos_CallMessage.Hangup(serializedBytes: serializedData)
        try self.init(proto)
    }

    fileprivate convenience init(_ proto: SignalServiceProtos_CallMessage.Hangup) throws {
        guard proto.hasID else {
            throw SignalServiceProtosError.invalidProtobuf(description: "[\(Self.self)] missing required field: id")
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

extension SignalServiceProtosCallMessageHangup {
    @objc
    public static func builder(id: UInt64) -> SignalServiceProtosCallMessageHangupBuilder {
        return SignalServiceProtosCallMessageHangupBuilder(id: id)
    }

    // asBuilder() constructs a builder that reflects the proto's contents.
    @objc
    public func asBuilder() -> SignalServiceProtosCallMessageHangupBuilder {
        let builder = SignalServiceProtosCallMessageHangupBuilder(id: id)
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
public class SignalServiceProtosCallMessageHangupBuilder: NSObject {

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
    public func setType(_ valueParam: SignalServiceProtosCallMessageHangupType) {
        proto.type = SignalServiceProtosCallMessageHangupTypeUnwrap(valueParam)
    }

    @objc
    public func setDeviceID(_ valueParam: UInt32) {
        proto.deviceID = valueParam
    }

    public func setUnknownFields(_ unknownFields: SwiftProtobuf.UnknownStorage) {
        proto.unknownFields = unknownFields
    }

    @objc
    public func build() throws -> SignalServiceProtosCallMessageHangup {
        return try SignalServiceProtosCallMessageHangup(proto)
    }

    @objc
    public func buildSerializedData() throws -> Data {
        return try SignalServiceProtosCallMessageHangup(proto).serializedData()
    }
}

#if TESTABLE_BUILD

extension SignalServiceProtosCallMessageHangup {
    @objc
    public func serializedDataIgnoringErrors() -> Data? {
        return try! self.serializedData()
    }
}

extension SignalServiceProtosCallMessageHangupBuilder {
    @objc
    public func buildIgnoringErrors() -> SignalServiceProtosCallMessageHangup? {
        return try! self.build()
    }
}

#endif

// MARK: - SignalServiceProtosCallMessageOpaqueUrgency

@objc
public enum SignalServiceProtosCallMessageOpaqueUrgency: Int32 {
    case droppable = 0
    case handleImmediately = 1
}

private func SignalServiceProtosCallMessageOpaqueUrgencyWrap(_ value: SignalServiceProtos_CallMessage.Opaque.Urgency) -> SignalServiceProtosCallMessageOpaqueUrgency {
    switch value {
    case .droppable: return .droppable
    case .handleImmediately: return .handleImmediately
    }
}

private func SignalServiceProtosCallMessageOpaqueUrgencyUnwrap(_ value: SignalServiceProtosCallMessageOpaqueUrgency) -> SignalServiceProtos_CallMessage.Opaque.Urgency {
    switch value {
    case .droppable: return .droppable
    case .handleImmediately: return .handleImmediately
    }
}

// MARK: - SignalServiceProtosCallMessageOpaque

@objc
public class SignalServiceProtosCallMessageOpaque: NSObject, Codable, NSSecureCoding {

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

    public var urgency: SignalServiceProtosCallMessageOpaqueUrgency? {
        guard hasUrgency else {
            return nil
        }
        return SignalServiceProtosCallMessageOpaqueUrgencyWrap(proto.urgency)
    }
    // This "unwrapped" accessor should only be used if the "has value" accessor has already been checked.
    @objc
    public var unwrappedUrgency: SignalServiceProtosCallMessageOpaqueUrgency {
        if !hasUrgency {
            // TODO: We could make this a crashing assert.
            owsFailDebug("Unsafe unwrap of missing optional: Opaque.urgency.")
        }
        return SignalServiceProtosCallMessageOpaqueUrgencyWrap(proto.urgency)
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
    public required convenience init(serializedData: Data) throws {
        let proto = try SignalServiceProtos_CallMessage.Opaque(serializedBytes: serializedData)
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

extension SignalServiceProtosCallMessageOpaque {
    @objc
    public static func builder() -> SignalServiceProtosCallMessageOpaqueBuilder {
        return SignalServiceProtosCallMessageOpaqueBuilder()
    }

    // asBuilder() constructs a builder that reflects the proto's contents.
    @objc
    public func asBuilder() -> SignalServiceProtosCallMessageOpaqueBuilder {
        let builder = SignalServiceProtosCallMessageOpaqueBuilder()
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
public class SignalServiceProtosCallMessageOpaqueBuilder: NSObject {

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
    public func setUrgency(_ valueParam: SignalServiceProtosCallMessageOpaqueUrgency) {
        proto.urgency = SignalServiceProtosCallMessageOpaqueUrgencyUnwrap(valueParam)
    }

    public func setUnknownFields(_ unknownFields: SwiftProtobuf.UnknownStorage) {
        proto.unknownFields = unknownFields
    }

    @objc
    public func buildInfallibly() -> SignalServiceProtosCallMessageOpaque {
        return SignalServiceProtosCallMessageOpaque(proto)
    }

    @objc
    public func buildSerializedData() throws -> Data {
        return try SignalServiceProtosCallMessageOpaque(proto).serializedData()
    }
}

#if TESTABLE_BUILD

extension SignalServiceProtosCallMessageOpaque {
    @objc
    public func serializedDataIgnoringErrors() -> Data? {
        return try! self.serializedData()
    }
}

extension SignalServiceProtosCallMessageOpaqueBuilder {
    @objc
    public func buildIgnoringErrors() -> SignalServiceProtosCallMessageOpaque? {
        return self.buildInfallibly()
    }
}

#endif

// MARK: - SignalServiceProtosCallMessage

@objc
public class SignalServiceProtosCallMessage: NSObject, Codable, NSSecureCoding {

    fileprivate let proto: SignalServiceProtos_CallMessage

    @objc
    public let offer: SignalServiceProtosCallMessageOffer?

    @objc
    public let answer: SignalServiceProtosCallMessageAnswer?

    @objc
    public let iceUpdate: [SignalServiceProtosCallMessageIceUpdate]

    @objc
    public let busy: SignalServiceProtosCallMessageBusy?

    @objc
    public let hangup: SignalServiceProtosCallMessageHangup?

    @objc
    public let opaque: SignalServiceProtosCallMessageOpaque?

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
                 offer: SignalServiceProtosCallMessageOffer?,
                 answer: SignalServiceProtosCallMessageAnswer?,
                 iceUpdate: [SignalServiceProtosCallMessageIceUpdate],
                 busy: SignalServiceProtosCallMessageBusy?,
                 hangup: SignalServiceProtosCallMessageHangup?,
                 opaque: SignalServiceProtosCallMessageOpaque?) {
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
    public required convenience init(serializedData: Data) throws {
        let proto = try SignalServiceProtos_CallMessage(serializedBytes: serializedData)
        try self.init(proto)
    }

    fileprivate convenience init(_ proto: SignalServiceProtos_CallMessage) throws {
        var offer: SignalServiceProtosCallMessageOffer?
        if proto.hasOffer {
            offer = try SignalServiceProtosCallMessageOffer(proto.offer)
        }

        var answer: SignalServiceProtosCallMessageAnswer?
        if proto.hasAnswer {
            answer = try SignalServiceProtosCallMessageAnswer(proto.answer)
        }

        var iceUpdate: [SignalServiceProtosCallMessageIceUpdate] = []
        iceUpdate = try proto.iceUpdate.map { try SignalServiceProtosCallMessageIceUpdate($0) }

        var busy: SignalServiceProtosCallMessageBusy?
        if proto.hasBusy {
            busy = try SignalServiceProtosCallMessageBusy(proto.busy)
        }

        var hangup: SignalServiceProtosCallMessageHangup?
        if proto.hasHangup {
            hangup = try SignalServiceProtosCallMessageHangup(proto.hangup)
        }

        var opaque: SignalServiceProtosCallMessageOpaque?
        if proto.hasOpaque {
            opaque = SignalServiceProtosCallMessageOpaque(proto.opaque)
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

extension SignalServiceProtosCallMessage {
    @objc
    public static func builder() -> SignalServiceProtosCallMessageBuilder {
        return SignalServiceProtosCallMessageBuilder()
    }

    // asBuilder() constructs a builder that reflects the proto's contents.
    @objc
    public func asBuilder() -> SignalServiceProtosCallMessageBuilder {
        let builder = SignalServiceProtosCallMessageBuilder()
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
public class SignalServiceProtosCallMessageBuilder: NSObject {

    private var proto = SignalServiceProtos_CallMessage()

    @objc
    fileprivate override init() {}

    @objc
    @available(swift, obsoleted: 1.0)
    public func setOffer(_ valueParam: SignalServiceProtosCallMessageOffer?) {
        guard let valueParam = valueParam else { return }
        proto.offer = valueParam.proto
    }

    public func setOffer(_ valueParam: SignalServiceProtosCallMessageOffer) {
        proto.offer = valueParam.proto
    }

    @objc
    @available(swift, obsoleted: 1.0)
    public func setAnswer(_ valueParam: SignalServiceProtosCallMessageAnswer?) {
        guard let valueParam = valueParam else { return }
        proto.answer = valueParam.proto
    }

    public func setAnswer(_ valueParam: SignalServiceProtosCallMessageAnswer) {
        proto.answer = valueParam.proto
    }

    @objc
    public func addIceUpdate(_ valueParam: SignalServiceProtosCallMessageIceUpdate) {
        proto.iceUpdate.append(valueParam.proto)
    }

    @objc
    public func setIceUpdate(_ wrappedItems: [SignalServiceProtosCallMessageIceUpdate]) {
        proto.iceUpdate = wrappedItems.map { $0.proto }
    }

    @objc
    @available(swift, obsoleted: 1.0)
    public func setBusy(_ valueParam: SignalServiceProtosCallMessageBusy?) {
        guard let valueParam = valueParam else { return }
        proto.busy = valueParam.proto
    }

    public func setBusy(_ valueParam: SignalServiceProtosCallMessageBusy) {
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
    public func setHangup(_ valueParam: SignalServiceProtosCallMessageHangup?) {
        guard let valueParam = valueParam else { return }
        proto.hangup = valueParam.proto
    }

    public func setHangup(_ valueParam: SignalServiceProtosCallMessageHangup) {
        proto.hangup = valueParam.proto
    }

    @objc
    public func setDestinationDeviceID(_ valueParam: UInt32) {
        proto.destinationDeviceID = valueParam
    }

    @objc
    @available(swift, obsoleted: 1.0)
    public func setOpaque(_ valueParam: SignalServiceProtosCallMessageOpaque?) {
        guard let valueParam = valueParam else { return }
        proto.opaque = valueParam.proto
    }

    public func setOpaque(_ valueParam: SignalServiceProtosCallMessageOpaque) {
        proto.opaque = valueParam.proto
    }

    public func setUnknownFields(_ unknownFields: SwiftProtobuf.UnknownStorage) {
        proto.unknownFields = unknownFields
    }

    @objc
    public func build() throws -> SignalServiceProtosCallMessage {
        return try SignalServiceProtosCallMessage(proto)
    }

    @objc
    public func buildSerializedData() throws -> Data {
        return try SignalServiceProtosCallMessage(proto).serializedData()
    }
}

#if TESTABLE_BUILD

extension SignalServiceProtosCallMessage {
    @objc
    public func serializedDataIgnoringErrors() -> Data? {
        return try! self.serializedData()
    }
}

extension SignalServiceProtosCallMessageBuilder {
    @objc
    public func buildIgnoringErrors() -> SignalServiceProtosCallMessage? {
        return try! self.build()
    }
}

#endif

// MARK: - SignalServiceProtosDataMessageQuoteQuotedAttachment

@objc
public class SignalServiceProtosDataMessageQuoteQuotedAttachment: NSObject, Codable, NSSecureCoding {

    fileprivate let proto: SignalServiceProtos_DataMessage.Quote.QuotedAttachment

    @objc
    public let thumbnail: SignalServiceProtosAttachmentPointer?

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
                 thumbnail: SignalServiceProtosAttachmentPointer?) {
        self.proto = proto
        self.thumbnail = thumbnail
    }

    @objc
    public func serializedData() throws -> Data {
        return try self.proto.serializedData()
    }

    @objc
    public required convenience init(serializedData: Data) throws {
        let proto = try SignalServiceProtos_DataMessage.Quote.QuotedAttachment(serializedBytes: serializedData)
        self.init(proto)
    }

    fileprivate convenience init(_ proto: SignalServiceProtos_DataMessage.Quote.QuotedAttachment) {
        var thumbnail: SignalServiceProtosAttachmentPointer?
        if proto.hasThumbnail {
            thumbnail = SignalServiceProtosAttachmentPointer(proto.thumbnail)
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

extension SignalServiceProtosDataMessageQuoteQuotedAttachment {
    @objc
    public static func builder() -> SignalServiceProtosDataMessageQuoteQuotedAttachmentBuilder {
        return SignalServiceProtosDataMessageQuoteQuotedAttachmentBuilder()
    }

    // asBuilder() constructs a builder that reflects the proto's contents.
    @objc
    public func asBuilder() -> SignalServiceProtosDataMessageQuoteQuotedAttachmentBuilder {
        let builder = SignalServiceProtosDataMessageQuoteQuotedAttachmentBuilder()
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
public class SignalServiceProtosDataMessageQuoteQuotedAttachmentBuilder: NSObject {

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
    public func setThumbnail(_ valueParam: SignalServiceProtosAttachmentPointer?) {
        guard let valueParam = valueParam else { return }
        proto.thumbnail = valueParam.proto
    }

    public func setThumbnail(_ valueParam: SignalServiceProtosAttachmentPointer) {
        proto.thumbnail = valueParam.proto
    }

    public func setUnknownFields(_ unknownFields: SwiftProtobuf.UnknownStorage) {
        proto.unknownFields = unknownFields
    }

    @objc
    public func buildInfallibly() -> SignalServiceProtosDataMessageQuoteQuotedAttachment {
        return SignalServiceProtosDataMessageQuoteQuotedAttachment(proto)
    }

    @objc
    public func buildSerializedData() throws -> Data {
        return try SignalServiceProtosDataMessageQuoteQuotedAttachment(proto).serializedData()
    }
}

#if TESTABLE_BUILD

extension SignalServiceProtosDataMessageQuoteQuotedAttachment {
    @objc
    public func serializedDataIgnoringErrors() -> Data? {
        return try! self.serializedData()
    }
}

extension SignalServiceProtosDataMessageQuoteQuotedAttachmentBuilder {
    @objc
    public func buildIgnoringErrors() -> SignalServiceProtosDataMessageQuoteQuotedAttachment? {
        return self.buildInfallibly()
    }
}

#endif

// MARK: - SignalServiceProtosDataMessageQuoteType

@objc
public enum SignalServiceProtosDataMessageQuoteType: Int32 {
    case normal = 0
    case giftBadge = 1
}

private func SignalServiceProtosDataMessageQuoteTypeWrap(_ value: SignalServiceProtos_DataMessage.Quote.TypeEnum) -> SignalServiceProtosDataMessageQuoteType {
    switch value {
    case .normal: return .normal
    case .giftBadge: return .giftBadge
    }
}

private func SignalServiceProtosDataMessageQuoteTypeUnwrap(_ value: SignalServiceProtosDataMessageQuoteType) -> SignalServiceProtos_DataMessage.Quote.TypeEnum {
    switch value {
    case .normal: return .normal
    case .giftBadge: return .giftBadge
    }
}

// MARK: - SignalServiceProtosDataMessageQuote

@objc
public class SignalServiceProtosDataMessageQuote: NSObject, Codable, NSSecureCoding {

    fileprivate let proto: SignalServiceProtos_DataMessage.Quote

    @objc
    public let id: UInt64

    @objc
    public let attachments: [SignalServiceProtosDataMessageQuoteQuotedAttachment]

    @objc
    public let bodyRanges: [SignalServiceProtosBodyRange]

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

    public var type: SignalServiceProtosDataMessageQuoteType? {
        guard hasType else {
            return nil
        }
        return SignalServiceProtosDataMessageQuoteTypeWrap(proto.type)
    }
    // This "unwrapped" accessor should only be used if the "has value" accessor has already been checked.
    @objc
    public var unwrappedType: SignalServiceProtosDataMessageQuoteType {
        if !hasType {
            // TODO: We could make this a crashing assert.
            owsFailDebug("Unsafe unwrap of missing optional: Quote.type.")
        }
        return SignalServiceProtosDataMessageQuoteTypeWrap(proto.type)
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
                 attachments: [SignalServiceProtosDataMessageQuoteQuotedAttachment],
                 bodyRanges: [SignalServiceProtosBodyRange]) {
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
    public required convenience init(serializedData: Data) throws {
        let proto = try SignalServiceProtos_DataMessage.Quote(serializedBytes: serializedData)
        try self.init(proto)
    }

    fileprivate convenience init(_ proto: SignalServiceProtos_DataMessage.Quote) throws {
        guard proto.hasID else {
            throw SignalServiceProtosError.invalidProtobuf(description: "[\(Self.self)] missing required field: id")
        }
        let id = proto.id

        var attachments: [SignalServiceProtosDataMessageQuoteQuotedAttachment] = []
        attachments = proto.attachments.map { SignalServiceProtosDataMessageQuoteQuotedAttachment($0) }

        var bodyRanges: [SignalServiceProtosBodyRange] = []
        bodyRanges = proto.bodyRanges.map { SignalServiceProtosBodyRange($0) }

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

extension SignalServiceProtosDataMessageQuote {
    @objc
    public static func builder(id: UInt64) -> SignalServiceProtosDataMessageQuoteBuilder {
        return SignalServiceProtosDataMessageQuoteBuilder(id: id)
    }

    // asBuilder() constructs a builder that reflects the proto's contents.
    @objc
    public func asBuilder() -> SignalServiceProtosDataMessageQuoteBuilder {
        let builder = SignalServiceProtosDataMessageQuoteBuilder(id: id)
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
public class SignalServiceProtosDataMessageQuoteBuilder: NSObject {

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
    public func addAttachments(_ valueParam: SignalServiceProtosDataMessageQuoteQuotedAttachment) {
        proto.attachments.append(valueParam.proto)
    }

    @objc
    public func setAttachments(_ wrappedItems: [SignalServiceProtosDataMessageQuoteQuotedAttachment]) {
        proto.attachments = wrappedItems.map { $0.proto }
    }

    @objc
    public func addBodyRanges(_ valueParam: SignalServiceProtosBodyRange) {
        proto.bodyRanges.append(valueParam.proto)
    }

    @objc
    public func setBodyRanges(_ wrappedItems: [SignalServiceProtosBodyRange]) {
        proto.bodyRanges = wrappedItems.map { $0.proto }
    }

    @objc
    public func setType(_ valueParam: SignalServiceProtosDataMessageQuoteType) {
        proto.type = SignalServiceProtosDataMessageQuoteTypeUnwrap(valueParam)
    }

    public func setUnknownFields(_ unknownFields: SwiftProtobuf.UnknownStorage) {
        proto.unknownFields = unknownFields
    }

    @objc
    public func build() throws -> SignalServiceProtosDataMessageQuote {
        return try SignalServiceProtosDataMessageQuote(proto)
    }

    @objc
    public func buildSerializedData() throws -> Data {
        return try SignalServiceProtosDataMessageQuote(proto).serializedData()
    }
}

#if TESTABLE_BUILD

extension SignalServiceProtosDataMessageQuote {
    @objc
    public func serializedDataIgnoringErrors() -> Data? {
        return try! self.serializedData()
    }
}

extension SignalServiceProtosDataMessageQuoteBuilder {
    @objc
    public func buildIgnoringErrors() -> SignalServiceProtosDataMessageQuote? {
        return try! self.build()
    }
}

#endif

// MARK: - SignalServiceProtosDataMessageContactName

@objc
public class SignalServiceProtosDataMessageContactName: NSObject, Codable, NSSecureCoding {

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
    public required convenience init(serializedData: Data) throws {
        let proto = try SignalServiceProtos_DataMessage.Contact.Name(serializedBytes: serializedData)
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

extension SignalServiceProtosDataMessageContactName {
    @objc
    public static func builder() -> SignalServiceProtosDataMessageContactNameBuilder {
        return SignalServiceProtosDataMessageContactNameBuilder()
    }

    // asBuilder() constructs a builder that reflects the proto's contents.
    @objc
    public func asBuilder() -> SignalServiceProtosDataMessageContactNameBuilder {
        let builder = SignalServiceProtosDataMessageContactNameBuilder()
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
        if let _value = unknownFields {
            builder.setUnknownFields(_value)
        }
        return builder
    }
}

@objc
public class SignalServiceProtosDataMessageContactNameBuilder: NSObject {

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

    public func setUnknownFields(_ unknownFields: SwiftProtobuf.UnknownStorage) {
        proto.unknownFields = unknownFields
    }

    @objc
    public func buildInfallibly() -> SignalServiceProtosDataMessageContactName {
        return SignalServiceProtosDataMessageContactName(proto)
    }

    @objc
    public func buildSerializedData() throws -> Data {
        return try SignalServiceProtosDataMessageContactName(proto).serializedData()
    }
}

#if TESTABLE_BUILD

extension SignalServiceProtosDataMessageContactName {
    @objc
    public func serializedDataIgnoringErrors() -> Data? {
        return try! self.serializedData()
    }
}

extension SignalServiceProtosDataMessageContactNameBuilder {
    @objc
    public func buildIgnoringErrors() -> SignalServiceProtosDataMessageContactName? {
        return self.buildInfallibly()
    }
}

#endif

// MARK: - SignalServiceProtosDataMessageContactPhoneType

@objc
public enum SignalServiceProtosDataMessageContactPhoneType: Int32 {
    case home = 1
    case mobile = 2
    case work = 3
    case custom = 4
}

private func SignalServiceProtosDataMessageContactPhoneTypeWrap(_ value: SignalServiceProtos_DataMessage.Contact.Phone.TypeEnum) -> SignalServiceProtosDataMessageContactPhoneType {
    switch value {
    case .home: return .home
    case .mobile: return .mobile
    case .work: return .work
    case .custom: return .custom
    }
}

private func SignalServiceProtosDataMessageContactPhoneTypeUnwrap(_ value: SignalServiceProtosDataMessageContactPhoneType) -> SignalServiceProtos_DataMessage.Contact.Phone.TypeEnum {
    switch value {
    case .home: return .home
    case .mobile: return .mobile
    case .work: return .work
    case .custom: return .custom
    }
}

// MARK: - SignalServiceProtosDataMessageContactPhone

@objc
public class SignalServiceProtosDataMessageContactPhone: NSObject, Codable, NSSecureCoding {

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

    public var type: SignalServiceProtosDataMessageContactPhoneType? {
        guard hasType else {
            return nil
        }
        return SignalServiceProtosDataMessageContactPhoneTypeWrap(proto.type)
    }
    // This "unwrapped" accessor should only be used if the "has value" accessor has already been checked.
    @objc
    public var unwrappedType: SignalServiceProtosDataMessageContactPhoneType {
        if !hasType {
            // TODO: We could make this a crashing assert.
            owsFailDebug("Unsafe unwrap of missing optional: Phone.type.")
        }
        return SignalServiceProtosDataMessageContactPhoneTypeWrap(proto.type)
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
    public required convenience init(serializedData: Data) throws {
        let proto = try SignalServiceProtos_DataMessage.Contact.Phone(serializedBytes: serializedData)
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

extension SignalServiceProtosDataMessageContactPhone {
    @objc
    public static func builder() -> SignalServiceProtosDataMessageContactPhoneBuilder {
        return SignalServiceProtosDataMessageContactPhoneBuilder()
    }

    // asBuilder() constructs a builder that reflects the proto's contents.
    @objc
    public func asBuilder() -> SignalServiceProtosDataMessageContactPhoneBuilder {
        let builder = SignalServiceProtosDataMessageContactPhoneBuilder()
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
public class SignalServiceProtosDataMessageContactPhoneBuilder: NSObject {

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
    public func setType(_ valueParam: SignalServiceProtosDataMessageContactPhoneType) {
        proto.type = SignalServiceProtosDataMessageContactPhoneTypeUnwrap(valueParam)
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
    public func buildInfallibly() -> SignalServiceProtosDataMessageContactPhone {
        return SignalServiceProtosDataMessageContactPhone(proto)
    }

    @objc
    public func buildSerializedData() throws -> Data {
        return try SignalServiceProtosDataMessageContactPhone(proto).serializedData()
    }
}

#if TESTABLE_BUILD

extension SignalServiceProtosDataMessageContactPhone {
    @objc
    public func serializedDataIgnoringErrors() -> Data? {
        return try! self.serializedData()
    }
}

extension SignalServiceProtosDataMessageContactPhoneBuilder {
    @objc
    public func buildIgnoringErrors() -> SignalServiceProtosDataMessageContactPhone? {
        return self.buildInfallibly()
    }
}

#endif

// MARK: - SignalServiceProtosDataMessageContactEmailType

@objc
public enum SignalServiceProtosDataMessageContactEmailType: Int32 {
    case home = 1
    case mobile = 2
    case work = 3
    case custom = 4
}

private func SignalServiceProtosDataMessageContactEmailTypeWrap(_ value: SignalServiceProtos_DataMessage.Contact.Email.TypeEnum) -> SignalServiceProtosDataMessageContactEmailType {
    switch value {
    case .home: return .home
    case .mobile: return .mobile
    case .work: return .work
    case .custom: return .custom
    }
}

private func SignalServiceProtosDataMessageContactEmailTypeUnwrap(_ value: SignalServiceProtosDataMessageContactEmailType) -> SignalServiceProtos_DataMessage.Contact.Email.TypeEnum {
    switch value {
    case .home: return .home
    case .mobile: return .mobile
    case .work: return .work
    case .custom: return .custom
    }
}

// MARK: - SignalServiceProtosDataMessageContactEmail

@objc
public class SignalServiceProtosDataMessageContactEmail: NSObject, Codable, NSSecureCoding {

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

    public var type: SignalServiceProtosDataMessageContactEmailType? {
        guard hasType else {
            return nil
        }
        return SignalServiceProtosDataMessageContactEmailTypeWrap(proto.type)
    }
    // This "unwrapped" accessor should only be used if the "has value" accessor has already been checked.
    @objc
    public var unwrappedType: SignalServiceProtosDataMessageContactEmailType {
        if !hasType {
            // TODO: We could make this a crashing assert.
            owsFailDebug("Unsafe unwrap of missing optional: Email.type.")
        }
        return SignalServiceProtosDataMessageContactEmailTypeWrap(proto.type)
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
    public required convenience init(serializedData: Data) throws {
        let proto = try SignalServiceProtos_DataMessage.Contact.Email(serializedBytes: serializedData)
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

extension SignalServiceProtosDataMessageContactEmail {
    @objc
    public static func builder() -> SignalServiceProtosDataMessageContactEmailBuilder {
        return SignalServiceProtosDataMessageContactEmailBuilder()
    }

    // asBuilder() constructs a builder that reflects the proto's contents.
    @objc
    public func asBuilder() -> SignalServiceProtosDataMessageContactEmailBuilder {
        let builder = SignalServiceProtosDataMessageContactEmailBuilder()
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
public class SignalServiceProtosDataMessageContactEmailBuilder: NSObject {

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
    public func setType(_ valueParam: SignalServiceProtosDataMessageContactEmailType) {
        proto.type = SignalServiceProtosDataMessageContactEmailTypeUnwrap(valueParam)
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
    public func buildInfallibly() -> SignalServiceProtosDataMessageContactEmail {
        return SignalServiceProtosDataMessageContactEmail(proto)
    }

    @objc
    public func buildSerializedData() throws -> Data {
        return try SignalServiceProtosDataMessageContactEmail(proto).serializedData()
    }
}

#if TESTABLE_BUILD

extension SignalServiceProtosDataMessageContactEmail {
    @objc
    public func serializedDataIgnoringErrors() -> Data? {
        return try! self.serializedData()
    }
}

extension SignalServiceProtosDataMessageContactEmailBuilder {
    @objc
    public func buildIgnoringErrors() -> SignalServiceProtosDataMessageContactEmail? {
        return self.buildInfallibly()
    }
}

#endif

// MARK: - SignalServiceProtosDataMessageContactPostalAddressType

@objc
public enum SignalServiceProtosDataMessageContactPostalAddressType: Int32 {
    case home = 1
    case work = 2
    case custom = 3
}

private func SignalServiceProtosDataMessageContactPostalAddressTypeWrap(_ value: SignalServiceProtos_DataMessage.Contact.PostalAddress.TypeEnum) -> SignalServiceProtosDataMessageContactPostalAddressType {
    switch value {
    case .home: return .home
    case .work: return .work
    case .custom: return .custom
    }
}

private func SignalServiceProtosDataMessageContactPostalAddressTypeUnwrap(_ value: SignalServiceProtosDataMessageContactPostalAddressType) -> SignalServiceProtos_DataMessage.Contact.PostalAddress.TypeEnum {
    switch value {
    case .home: return .home
    case .work: return .work
    case .custom: return .custom
    }
}

// MARK: - SignalServiceProtosDataMessageContactPostalAddress

@objc
public class SignalServiceProtosDataMessageContactPostalAddress: NSObject, Codable, NSSecureCoding {

    fileprivate let proto: SignalServiceProtos_DataMessage.Contact.PostalAddress

    public var type: SignalServiceProtosDataMessageContactPostalAddressType? {
        guard hasType else {
            return nil
        }
        return SignalServiceProtosDataMessageContactPostalAddressTypeWrap(proto.type)
    }
    // This "unwrapped" accessor should only be used if the "has value" accessor has already been checked.
    @objc
    public var unwrappedType: SignalServiceProtosDataMessageContactPostalAddressType {
        if !hasType {
            // TODO: We could make this a crashing assert.
            owsFailDebug("Unsafe unwrap of missing optional: PostalAddress.type.")
        }
        return SignalServiceProtosDataMessageContactPostalAddressTypeWrap(proto.type)
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
    public required convenience init(serializedData: Data) throws {
        let proto = try SignalServiceProtos_DataMessage.Contact.PostalAddress(serializedBytes: serializedData)
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

extension SignalServiceProtosDataMessageContactPostalAddress {
    @objc
    public static func builder() -> SignalServiceProtosDataMessageContactPostalAddressBuilder {
        return SignalServiceProtosDataMessageContactPostalAddressBuilder()
    }

    // asBuilder() constructs a builder that reflects the proto's contents.
    @objc
    public func asBuilder() -> SignalServiceProtosDataMessageContactPostalAddressBuilder {
        let builder = SignalServiceProtosDataMessageContactPostalAddressBuilder()
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
public class SignalServiceProtosDataMessageContactPostalAddressBuilder: NSObject {

    private var proto = SignalServiceProtos_DataMessage.Contact.PostalAddress()

    @objc
    fileprivate override init() {}

    @objc
    public func setType(_ valueParam: SignalServiceProtosDataMessageContactPostalAddressType) {
        proto.type = SignalServiceProtosDataMessageContactPostalAddressTypeUnwrap(valueParam)
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
    public func buildInfallibly() -> SignalServiceProtosDataMessageContactPostalAddress {
        return SignalServiceProtosDataMessageContactPostalAddress(proto)
    }

    @objc
    public func buildSerializedData() throws -> Data {
        return try SignalServiceProtosDataMessageContactPostalAddress(proto).serializedData()
    }
}

#if TESTABLE_BUILD

extension SignalServiceProtosDataMessageContactPostalAddress {
    @objc
    public func serializedDataIgnoringErrors() -> Data? {
        return try! self.serializedData()
    }
}

extension SignalServiceProtosDataMessageContactPostalAddressBuilder {
    @objc
    public func buildIgnoringErrors() -> SignalServiceProtosDataMessageContactPostalAddress? {
        return self.buildInfallibly()
    }
}

#endif

// MARK: - SignalServiceProtosDataMessageContactAvatar

@objc
public class SignalServiceProtosDataMessageContactAvatar: NSObject, Codable, NSSecureCoding {

    fileprivate let proto: SignalServiceProtos_DataMessage.Contact.Avatar

    @objc
    public let avatar: SignalServiceProtosAttachmentPointer?

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
                 avatar: SignalServiceProtosAttachmentPointer?) {
        self.proto = proto
        self.avatar = avatar
    }

    @objc
    public func serializedData() throws -> Data {
        return try self.proto.serializedData()
    }

    @objc
    public required convenience init(serializedData: Data) throws {
        let proto = try SignalServiceProtos_DataMessage.Contact.Avatar(serializedBytes: serializedData)
        self.init(proto)
    }

    fileprivate convenience init(_ proto: SignalServiceProtos_DataMessage.Contact.Avatar) {
        var avatar: SignalServiceProtosAttachmentPointer?
        if proto.hasAvatar {
            avatar = SignalServiceProtosAttachmentPointer(proto.avatar)
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

extension SignalServiceProtosDataMessageContactAvatar {
    @objc
    public static func builder() -> SignalServiceProtosDataMessageContactAvatarBuilder {
        return SignalServiceProtosDataMessageContactAvatarBuilder()
    }

    // asBuilder() constructs a builder that reflects the proto's contents.
    @objc
    public func asBuilder() -> SignalServiceProtosDataMessageContactAvatarBuilder {
        let builder = SignalServiceProtosDataMessageContactAvatarBuilder()
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
public class SignalServiceProtosDataMessageContactAvatarBuilder: NSObject {

    private var proto = SignalServiceProtos_DataMessage.Contact.Avatar()

    @objc
    fileprivate override init() {}

    @objc
    @available(swift, obsoleted: 1.0)
    public func setAvatar(_ valueParam: SignalServiceProtosAttachmentPointer?) {
        guard let valueParam = valueParam else { return }
        proto.avatar = valueParam.proto
    }

    public func setAvatar(_ valueParam: SignalServiceProtosAttachmentPointer) {
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
    public func buildInfallibly() -> SignalServiceProtosDataMessageContactAvatar {
        return SignalServiceProtosDataMessageContactAvatar(proto)
    }

    @objc
    public func buildSerializedData() throws -> Data {
        return try SignalServiceProtosDataMessageContactAvatar(proto).serializedData()
    }
}

#if TESTABLE_BUILD

extension SignalServiceProtosDataMessageContactAvatar {
    @objc
    public func serializedDataIgnoringErrors() -> Data? {
        return try! self.serializedData()
    }
}

extension SignalServiceProtosDataMessageContactAvatarBuilder {
    @objc
    public func buildIgnoringErrors() -> SignalServiceProtosDataMessageContactAvatar? {
        return self.buildInfallibly()
    }
}

#endif

// MARK: - SignalServiceProtosDataMessageContact

@objc
public class SignalServiceProtosDataMessageContact: NSObject, Codable, NSSecureCoding {

    fileprivate let proto: SignalServiceProtos_DataMessage.Contact

    @objc
    public let name: SignalServiceProtosDataMessageContactName?

    @objc
    public let number: [SignalServiceProtosDataMessageContactPhone]

    @objc
    public let email: [SignalServiceProtosDataMessageContactEmail]

    @objc
    public let address: [SignalServiceProtosDataMessageContactPostalAddress]

    @objc
    public let avatar: SignalServiceProtosDataMessageContactAvatar?

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
                 name: SignalServiceProtosDataMessageContactName?,
                 number: [SignalServiceProtosDataMessageContactPhone],
                 email: [SignalServiceProtosDataMessageContactEmail],
                 address: [SignalServiceProtosDataMessageContactPostalAddress],
                 avatar: SignalServiceProtosDataMessageContactAvatar?) {
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
    public required convenience init(serializedData: Data) throws {
        let proto = try SignalServiceProtos_DataMessage.Contact(serializedBytes: serializedData)
        self.init(proto)
    }

    fileprivate convenience init(_ proto: SignalServiceProtos_DataMessage.Contact) {
        var name: SignalServiceProtosDataMessageContactName?
        if proto.hasName {
            name = SignalServiceProtosDataMessageContactName(proto.name)
        }

        var number: [SignalServiceProtosDataMessageContactPhone] = []
        number = proto.number.map { SignalServiceProtosDataMessageContactPhone($0) }

        var email: [SignalServiceProtosDataMessageContactEmail] = []
        email = proto.email.map { SignalServiceProtosDataMessageContactEmail($0) }

        var address: [SignalServiceProtosDataMessageContactPostalAddress] = []
        address = proto.address.map { SignalServiceProtosDataMessageContactPostalAddress($0) }

        var avatar: SignalServiceProtosDataMessageContactAvatar?
        if proto.hasAvatar {
            avatar = SignalServiceProtosDataMessageContactAvatar(proto.avatar)
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

extension SignalServiceProtosDataMessageContact {
    @objc
    public static func builder() -> SignalServiceProtosDataMessageContactBuilder {
        return SignalServiceProtosDataMessageContactBuilder()
    }

    // asBuilder() constructs a builder that reflects the proto's contents.
    @objc
    public func asBuilder() -> SignalServiceProtosDataMessageContactBuilder {
        let builder = SignalServiceProtosDataMessageContactBuilder()
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
public class SignalServiceProtosDataMessageContactBuilder: NSObject {

    private var proto = SignalServiceProtos_DataMessage.Contact()

    @objc
    fileprivate override init() {}

    @objc
    @available(swift, obsoleted: 1.0)
    public func setName(_ valueParam: SignalServiceProtosDataMessageContactName?) {
        guard let valueParam = valueParam else { return }
        proto.name = valueParam.proto
    }

    public func setName(_ valueParam: SignalServiceProtosDataMessageContactName) {
        proto.name = valueParam.proto
    }

    @objc
    public func addNumber(_ valueParam: SignalServiceProtosDataMessageContactPhone) {
        proto.number.append(valueParam.proto)
    }

    @objc
    public func setNumber(_ wrappedItems: [SignalServiceProtosDataMessageContactPhone]) {
        proto.number = wrappedItems.map { $0.proto }
    }

    @objc
    public func addEmail(_ valueParam: SignalServiceProtosDataMessageContactEmail) {
        proto.email.append(valueParam.proto)
    }

    @objc
    public func setEmail(_ wrappedItems: [SignalServiceProtosDataMessageContactEmail]) {
        proto.email = wrappedItems.map { $0.proto }
    }

    @objc
    public func addAddress(_ valueParam: SignalServiceProtosDataMessageContactPostalAddress) {
        proto.address.append(valueParam.proto)
    }

    @objc
    public func setAddress(_ wrappedItems: [SignalServiceProtosDataMessageContactPostalAddress]) {
        proto.address = wrappedItems.map { $0.proto }
    }

    @objc
    @available(swift, obsoleted: 1.0)
    public func setAvatar(_ valueParam: SignalServiceProtosDataMessageContactAvatar?) {
        guard let valueParam = valueParam else { return }
        proto.avatar = valueParam.proto
    }

    public func setAvatar(_ valueParam: SignalServiceProtosDataMessageContactAvatar) {
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
    public func buildInfallibly() -> SignalServiceProtosDataMessageContact {
        return SignalServiceProtosDataMessageContact(proto)
    }

    @objc
    public func buildSerializedData() throws -> Data {
        return try SignalServiceProtosDataMessageContact(proto).serializedData()
    }
}

#if TESTABLE_BUILD

extension SignalServiceProtosDataMessageContact {
    @objc
    public func serializedDataIgnoringErrors() -> Data? {
        return try! self.serializedData()
    }
}

extension SignalServiceProtosDataMessageContactBuilder {
    @objc
    public func buildIgnoringErrors() -> SignalServiceProtosDataMessageContact? {
        return self.buildInfallibly()
    }
}

#endif

// MARK: - SignalServiceProtosDataMessageSticker

@objc
public class SignalServiceProtosDataMessageSticker: NSObject, Codable, NSSecureCoding {

    fileprivate let proto: SignalServiceProtos_DataMessage.Sticker

    @objc
    public let packID: Data

    @objc
    public let packKey: Data

    @objc
    public let stickerID: UInt32

    @objc
    public let data: SignalServiceProtosAttachmentPointer

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
                 data: SignalServiceProtosAttachmentPointer) {
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
    public required convenience init(serializedData: Data) throws {
        let proto = try SignalServiceProtos_DataMessage.Sticker(serializedBytes: serializedData)
        try self.init(proto)
    }

    fileprivate convenience init(_ proto: SignalServiceProtos_DataMessage.Sticker) throws {
        guard proto.hasPackID else {
            throw SignalServiceProtosError.invalidProtobuf(description: "[\(Self.self)] missing required field: packID")
        }
        let packID = proto.packID

        guard proto.hasPackKey else {
            throw SignalServiceProtosError.invalidProtobuf(description: "[\(Self.self)] missing required field: packKey")
        }
        let packKey = proto.packKey

        guard proto.hasStickerID else {
            throw SignalServiceProtosError.invalidProtobuf(description: "[\(Self.self)] missing required field: stickerID")
        }
        let stickerID = proto.stickerID

        guard proto.hasData else {
            throw SignalServiceProtosError.invalidProtobuf(description: "[\(Self.self)] missing required field: data")
        }
        let data = SignalServiceProtosAttachmentPointer(proto.data)

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

extension SignalServiceProtosDataMessageSticker {
    @objc
    public static func builder(packID: Data, packKey: Data, stickerID: UInt32, data: SignalServiceProtosAttachmentPointer) -> SignalServiceProtosDataMessageStickerBuilder {
        return SignalServiceProtosDataMessageStickerBuilder(packID: packID, packKey: packKey, stickerID: stickerID, data: data)
    }

    // asBuilder() constructs a builder that reflects the proto's contents.
    @objc
    public func asBuilder() -> SignalServiceProtosDataMessageStickerBuilder {
        let builder = SignalServiceProtosDataMessageStickerBuilder(packID: packID, packKey: packKey, stickerID: stickerID, data: data)
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
public class SignalServiceProtosDataMessageStickerBuilder: NSObject {

    private var proto = SignalServiceProtos_DataMessage.Sticker()

    @objc
    fileprivate override init() {}

    @objc
    fileprivate init(packID: Data, packKey: Data, stickerID: UInt32, data: SignalServiceProtosAttachmentPointer) {
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
    public func setData(_ valueParam: SignalServiceProtosAttachmentPointer?) {
        guard let valueParam = valueParam else { return }
        proto.data = valueParam.proto
    }

    public func setData(_ valueParam: SignalServiceProtosAttachmentPointer) {
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
    public func build() throws -> SignalServiceProtosDataMessageSticker {
        return try SignalServiceProtosDataMessageSticker(proto)
    }

    @objc
    public func buildSerializedData() throws -> Data {
        return try SignalServiceProtosDataMessageSticker(proto).serializedData()
    }
}

#if TESTABLE_BUILD

extension SignalServiceProtosDataMessageSticker {
    @objc
    public func serializedDataIgnoringErrors() -> Data? {
        return try! self.serializedData()
    }
}

extension SignalServiceProtosDataMessageStickerBuilder {
    @objc
    public func buildIgnoringErrors() -> SignalServiceProtosDataMessageSticker? {
        return try! self.build()
    }
}

#endif

// MARK: - SignalServiceProtosDataMessageReaction

@objc
public class SignalServiceProtosDataMessageReaction: NSObject, Codable, NSSecureCoding {

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
    public required convenience init(serializedData: Data) throws {
        let proto = try SignalServiceProtos_DataMessage.Reaction(serializedBytes: serializedData)
        try self.init(proto)
    }

    fileprivate convenience init(_ proto: SignalServiceProtos_DataMessage.Reaction) throws {
        guard proto.hasEmoji else {
            throw SignalServiceProtosError.invalidProtobuf(description: "[\(Self.self)] missing required field: emoji")
        }
        let emoji = proto.emoji

        guard proto.hasTimestamp else {
            throw SignalServiceProtosError.invalidProtobuf(description: "[\(Self.self)] missing required field: timestamp")
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

extension SignalServiceProtosDataMessageReaction {
    @objc
    public static func builder(emoji: String, timestamp: UInt64) -> SignalServiceProtosDataMessageReactionBuilder {
        return SignalServiceProtosDataMessageReactionBuilder(emoji: emoji, timestamp: timestamp)
    }

    // asBuilder() constructs a builder that reflects the proto's contents.
    @objc
    public func asBuilder() -> SignalServiceProtosDataMessageReactionBuilder {
        let builder = SignalServiceProtosDataMessageReactionBuilder(emoji: emoji, timestamp: timestamp)
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
public class SignalServiceProtosDataMessageReactionBuilder: NSObject {

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
    public func build() throws -> SignalServiceProtosDataMessageReaction {
        return try SignalServiceProtosDataMessageReaction(proto)
    }

    @objc
    public func buildSerializedData() throws -> Data {
        return try SignalServiceProtosDataMessageReaction(proto).serializedData()
    }
}

#if TESTABLE_BUILD

extension SignalServiceProtosDataMessageReaction {
    @objc
    public func serializedDataIgnoringErrors() -> Data? {
        return try! self.serializedData()
    }
}

extension SignalServiceProtosDataMessageReactionBuilder {
    @objc
    public func buildIgnoringErrors() -> SignalServiceProtosDataMessageReaction? {
        return try! self.build()
    }
}

#endif

// MARK: - SignalServiceProtosDataMessageDelete

@objc
public class SignalServiceProtosDataMessageDelete: NSObject, Codable, NSSecureCoding {

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
    public required convenience init(serializedData: Data) throws {
        let proto = try SignalServiceProtos_DataMessage.Delete(serializedBytes: serializedData)
        try self.init(proto)
    }

    fileprivate convenience init(_ proto: SignalServiceProtos_DataMessage.Delete) throws {
        guard proto.hasTargetSentTimestamp else {
            throw SignalServiceProtosError.invalidProtobuf(description: "[\(Self.self)] missing required field: targetSentTimestamp")
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

extension SignalServiceProtosDataMessageDelete {
    @objc
    public static func builder(targetSentTimestamp: UInt64) -> SignalServiceProtosDataMessageDeleteBuilder {
        return SignalServiceProtosDataMessageDeleteBuilder(targetSentTimestamp: targetSentTimestamp)
    }

    // asBuilder() constructs a builder that reflects the proto's contents.
    @objc
    public func asBuilder() -> SignalServiceProtosDataMessageDeleteBuilder {
        let builder = SignalServiceProtosDataMessageDeleteBuilder(targetSentTimestamp: targetSentTimestamp)
        if let _value = unknownFields {
            builder.setUnknownFields(_value)
        }
        return builder
    }
}

@objc
public class SignalServiceProtosDataMessageDeleteBuilder: NSObject {

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
    public func build() throws -> SignalServiceProtosDataMessageDelete {
        return try SignalServiceProtosDataMessageDelete(proto)
    }

    @objc
    public func buildSerializedData() throws -> Data {
        return try SignalServiceProtosDataMessageDelete(proto).serializedData()
    }
}

#if TESTABLE_BUILD

extension SignalServiceProtosDataMessageDelete {
    @objc
    public func serializedDataIgnoringErrors() -> Data? {
        return try! self.serializedData()
    }
}

extension SignalServiceProtosDataMessageDeleteBuilder {
    @objc
    public func buildIgnoringErrors() -> SignalServiceProtosDataMessageDelete? {
        return try! self.build()
    }
}

#endif

// MARK: - SignalServiceProtosDataMessageGroupCallUpdate

@objc
public class SignalServiceProtosDataMessageGroupCallUpdate: NSObject, Codable, NSSecureCoding {

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
    public required convenience init(serializedData: Data) throws {
        let proto = try SignalServiceProtos_DataMessage.GroupCallUpdate(serializedBytes: serializedData)
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

extension SignalServiceProtosDataMessageGroupCallUpdate {
    @objc
    public static func builder() -> SignalServiceProtosDataMessageGroupCallUpdateBuilder {
        return SignalServiceProtosDataMessageGroupCallUpdateBuilder()
    }

    // asBuilder() constructs a builder that reflects the proto's contents.
    @objc
    public func asBuilder() -> SignalServiceProtosDataMessageGroupCallUpdateBuilder {
        let builder = SignalServiceProtosDataMessageGroupCallUpdateBuilder()
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
public class SignalServiceProtosDataMessageGroupCallUpdateBuilder: NSObject {

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
    public func buildInfallibly() -> SignalServiceProtosDataMessageGroupCallUpdate {
        return SignalServiceProtosDataMessageGroupCallUpdate(proto)
    }

    @objc
    public func buildSerializedData() throws -> Data {
        return try SignalServiceProtosDataMessageGroupCallUpdate(proto).serializedData()
    }
}

#if TESTABLE_BUILD

extension SignalServiceProtosDataMessageGroupCallUpdate {
    @objc
    public func serializedDataIgnoringErrors() -> Data? {
        return try! self.serializedData()
    }
}

extension SignalServiceProtosDataMessageGroupCallUpdateBuilder {
    @objc
    public func buildIgnoringErrors() -> SignalServiceProtosDataMessageGroupCallUpdate? {
        return self.buildInfallibly()
    }
}

#endif

// MARK: - SignalServiceProtosDataMessagePaymentAmountMobileCoin

@objc
public class SignalServiceProtosDataMessagePaymentAmountMobileCoin: NSObject, Codable, NSSecureCoding {

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
    public required convenience init(serializedData: Data) throws {
        let proto = try SignalServiceProtos_DataMessage.Payment.Amount.MobileCoin(serializedBytes: serializedData)
        try self.init(proto)
    }

    fileprivate convenience init(_ proto: SignalServiceProtos_DataMessage.Payment.Amount.MobileCoin) throws {
        guard proto.hasPicoMob else {
            throw SignalServiceProtosError.invalidProtobuf(description: "[\(Self.self)] missing required field: picoMob")
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

extension SignalServiceProtosDataMessagePaymentAmountMobileCoin {
    @objc
    public static func builder(picoMob: UInt64) -> SignalServiceProtosDataMessagePaymentAmountMobileCoinBuilder {
        return SignalServiceProtosDataMessagePaymentAmountMobileCoinBuilder(picoMob: picoMob)
    }

    // asBuilder() constructs a builder that reflects the proto's contents.
    @objc
    public func asBuilder() -> SignalServiceProtosDataMessagePaymentAmountMobileCoinBuilder {
        let builder = SignalServiceProtosDataMessagePaymentAmountMobileCoinBuilder(picoMob: picoMob)
        if let _value = unknownFields {
            builder.setUnknownFields(_value)
        }
        return builder
    }
}

@objc
public class SignalServiceProtosDataMessagePaymentAmountMobileCoinBuilder: NSObject {

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
    public func build() throws -> SignalServiceProtosDataMessagePaymentAmountMobileCoin {
        return try SignalServiceProtosDataMessagePaymentAmountMobileCoin(proto)
    }

    @objc
    public func buildSerializedData() throws -> Data {
        return try SignalServiceProtosDataMessagePaymentAmountMobileCoin(proto).serializedData()
    }
}

#if TESTABLE_BUILD

extension SignalServiceProtosDataMessagePaymentAmountMobileCoin {
    @objc
    public func serializedDataIgnoringErrors() -> Data? {
        return try! self.serializedData()
    }
}

extension SignalServiceProtosDataMessagePaymentAmountMobileCoinBuilder {
    @objc
    public func buildIgnoringErrors() -> SignalServiceProtosDataMessagePaymentAmountMobileCoin? {
        return try! self.build()
    }
}

#endif

// MARK: - SignalServiceProtosDataMessagePaymentAmount

@objc
public class SignalServiceProtosDataMessagePaymentAmount: NSObject, Codable, NSSecureCoding {

    fileprivate let proto: SignalServiceProtos_DataMessage.Payment.Amount

    @objc
    public let mobileCoin: SignalServiceProtosDataMessagePaymentAmountMobileCoin?

    public var hasUnknownFields: Bool {
        return !proto.unknownFields.data.isEmpty
    }
    public var unknownFields: SwiftProtobuf.UnknownStorage? {
        guard hasUnknownFields else { return nil }
        return proto.unknownFields
    }

    private init(proto: SignalServiceProtos_DataMessage.Payment.Amount,
                 mobileCoin: SignalServiceProtosDataMessagePaymentAmountMobileCoin?) {
        self.proto = proto
        self.mobileCoin = mobileCoin
    }

    @objc
    public func serializedData() throws -> Data {
        return try self.proto.serializedData()
    }

    @objc
    public required convenience init(serializedData: Data) throws {
        let proto = try SignalServiceProtos_DataMessage.Payment.Amount(serializedBytes: serializedData)
        try self.init(proto)
    }

    fileprivate convenience init(_ proto: SignalServiceProtos_DataMessage.Payment.Amount) throws {
        var mobileCoin: SignalServiceProtosDataMessagePaymentAmountMobileCoin?
        if proto.hasMobileCoin {
            mobileCoin = try SignalServiceProtosDataMessagePaymentAmountMobileCoin(proto.mobileCoin)
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

extension SignalServiceProtosDataMessagePaymentAmount {
    @objc
    public static func builder() -> SignalServiceProtosDataMessagePaymentAmountBuilder {
        return SignalServiceProtosDataMessagePaymentAmountBuilder()
    }

    // asBuilder() constructs a builder that reflects the proto's contents.
    @objc
    public func asBuilder() -> SignalServiceProtosDataMessagePaymentAmountBuilder {
        let builder = SignalServiceProtosDataMessagePaymentAmountBuilder()
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
public class SignalServiceProtosDataMessagePaymentAmountBuilder: NSObject {

    private var proto = SignalServiceProtos_DataMessage.Payment.Amount()

    @objc
    fileprivate override init() {}

    @objc
    @available(swift, obsoleted: 1.0)
    public func setMobileCoin(_ valueParam: SignalServiceProtosDataMessagePaymentAmountMobileCoin?) {
        guard let valueParam = valueParam else { return }
        proto.mobileCoin = valueParam.proto
    }

    public func setMobileCoin(_ valueParam: SignalServiceProtosDataMessagePaymentAmountMobileCoin) {
        proto.mobileCoin = valueParam.proto
    }

    public func setUnknownFields(_ unknownFields: SwiftProtobuf.UnknownStorage) {
        proto.unknownFields = unknownFields
    }

    @objc
    public func build() throws -> SignalServiceProtosDataMessagePaymentAmount {
        return try SignalServiceProtosDataMessagePaymentAmount(proto)
    }

    @objc
    public func buildSerializedData() throws -> Data {
        return try SignalServiceProtosDataMessagePaymentAmount(proto).serializedData()
    }
}

#if TESTABLE_BUILD

extension SignalServiceProtosDataMessagePaymentAmount {
    @objc
    public func serializedDataIgnoringErrors() -> Data? {
        return try! self.serializedData()
    }
}

extension SignalServiceProtosDataMessagePaymentAmountBuilder {
    @objc
    public func buildIgnoringErrors() -> SignalServiceProtosDataMessagePaymentAmount? {
        return try! self.build()
    }
}

#endif

// MARK: - SignalServiceProtosDataMessagePaymentNotificationMobileCoin

@objc
public class SignalServiceProtosDataMessagePaymentNotificationMobileCoin: NSObject, Codable, NSSecureCoding {

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
    public required convenience init(serializedData: Data) throws {
        let proto = try SignalServiceProtos_DataMessage.Payment.Notification.MobileCoin(serializedBytes: serializedData)
        try self.init(proto)
    }

    fileprivate convenience init(_ proto: SignalServiceProtos_DataMessage.Payment.Notification.MobileCoin) throws {
        guard proto.hasReceipt else {
            throw SignalServiceProtosError.invalidProtobuf(description: "[\(Self.self)] missing required field: receipt")
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

extension SignalServiceProtosDataMessagePaymentNotificationMobileCoin {
    @objc
    public static func builder(receipt: Data) -> SignalServiceProtosDataMessagePaymentNotificationMobileCoinBuilder {
        return SignalServiceProtosDataMessagePaymentNotificationMobileCoinBuilder(receipt: receipt)
    }

    // asBuilder() constructs a builder that reflects the proto's contents.
    @objc
    public func asBuilder() -> SignalServiceProtosDataMessagePaymentNotificationMobileCoinBuilder {
        let builder = SignalServiceProtosDataMessagePaymentNotificationMobileCoinBuilder(receipt: receipt)
        if let _value = unknownFields {
            builder.setUnknownFields(_value)
        }
        return builder
    }
}

@objc
public class SignalServiceProtosDataMessagePaymentNotificationMobileCoinBuilder: NSObject {

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
    public func build() throws -> SignalServiceProtosDataMessagePaymentNotificationMobileCoin {
        return try SignalServiceProtosDataMessagePaymentNotificationMobileCoin(proto)
    }

    @objc
    public func buildSerializedData() throws -> Data {
        return try SignalServiceProtosDataMessagePaymentNotificationMobileCoin(proto).serializedData()
    }
}

#if TESTABLE_BUILD

extension SignalServiceProtosDataMessagePaymentNotificationMobileCoin {
    @objc
    public func serializedDataIgnoringErrors() -> Data? {
        return try! self.serializedData()
    }
}

extension SignalServiceProtosDataMessagePaymentNotificationMobileCoinBuilder {
    @objc
    public func buildIgnoringErrors() -> SignalServiceProtosDataMessagePaymentNotificationMobileCoin? {
        return try! self.build()
    }
}

#endif

// MARK: - SignalServiceProtosDataMessagePaymentNotification

@objc
public class SignalServiceProtosDataMessagePaymentNotification: NSObject, Codable, NSSecureCoding {

    fileprivate let proto: SignalServiceProtos_DataMessage.Payment.Notification

    @objc
    public let mobileCoin: SignalServiceProtosDataMessagePaymentNotificationMobileCoin?

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
                 mobileCoin: SignalServiceProtosDataMessagePaymentNotificationMobileCoin?) {
        self.proto = proto
        self.mobileCoin = mobileCoin
    }

    @objc
    public func serializedData() throws -> Data {
        return try self.proto.serializedData()
    }

    @objc
    public required convenience init(serializedData: Data) throws {
        let proto = try SignalServiceProtos_DataMessage.Payment.Notification(serializedBytes: serializedData)
        try self.init(proto)
    }

    fileprivate convenience init(_ proto: SignalServiceProtos_DataMessage.Payment.Notification) throws {
        var mobileCoin: SignalServiceProtosDataMessagePaymentNotificationMobileCoin?
        if proto.hasMobileCoin {
            mobileCoin = try SignalServiceProtosDataMessagePaymentNotificationMobileCoin(proto.mobileCoin)
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

extension SignalServiceProtosDataMessagePaymentNotification {
    @objc
    public static func builder() -> SignalServiceProtosDataMessagePaymentNotificationBuilder {
        return SignalServiceProtosDataMessagePaymentNotificationBuilder()
    }

    // asBuilder() constructs a builder that reflects the proto's contents.
    @objc
    public func asBuilder() -> SignalServiceProtosDataMessagePaymentNotificationBuilder {
        let builder = SignalServiceProtosDataMessagePaymentNotificationBuilder()
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
public class SignalServiceProtosDataMessagePaymentNotificationBuilder: NSObject {

    private var proto = SignalServiceProtos_DataMessage.Payment.Notification()

    @objc
    fileprivate override init() {}

    @objc
    @available(swift, obsoleted: 1.0)
    public func setMobileCoin(_ valueParam: SignalServiceProtosDataMessagePaymentNotificationMobileCoin?) {
        guard let valueParam = valueParam else { return }
        proto.mobileCoin = valueParam.proto
    }

    public func setMobileCoin(_ valueParam: SignalServiceProtosDataMessagePaymentNotificationMobileCoin) {
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
    public func build() throws -> SignalServiceProtosDataMessagePaymentNotification {
        return try SignalServiceProtosDataMessagePaymentNotification(proto)
    }

    @objc
    public func buildSerializedData() throws -> Data {
        return try SignalServiceProtosDataMessagePaymentNotification(proto).serializedData()
    }
}

#if TESTABLE_BUILD

extension SignalServiceProtosDataMessagePaymentNotification {
    @objc
    public func serializedDataIgnoringErrors() -> Data? {
        return try! self.serializedData()
    }
}

extension SignalServiceProtosDataMessagePaymentNotificationBuilder {
    @objc
    public func buildIgnoringErrors() -> SignalServiceProtosDataMessagePaymentNotification? {
        return try! self.build()
    }
}

#endif

// MARK: - SignalServiceProtosDataMessagePaymentActivationType

@objc
public enum SignalServiceProtosDataMessagePaymentActivationType: Int32 {
    case request = 0
    case activated = 1
}

private func SignalServiceProtosDataMessagePaymentActivationTypeWrap(_ value: SignalServiceProtos_DataMessage.Payment.Activation.TypeEnum) -> SignalServiceProtosDataMessagePaymentActivationType {
    switch value {
    case .request: return .request
    case .activated: return .activated
    }
}

private func SignalServiceProtosDataMessagePaymentActivationTypeUnwrap(_ value: SignalServiceProtosDataMessagePaymentActivationType) -> SignalServiceProtos_DataMessage.Payment.Activation.TypeEnum {
    switch value {
    case .request: return .request
    case .activated: return .activated
    }
}

// MARK: - SignalServiceProtosDataMessagePaymentActivation

@objc
public class SignalServiceProtosDataMessagePaymentActivation: NSObject, Codable, NSSecureCoding {

    fileprivate let proto: SignalServiceProtos_DataMessage.Payment.Activation

    public var type: SignalServiceProtosDataMessagePaymentActivationType? {
        guard hasType else {
            return nil
        }
        return SignalServiceProtosDataMessagePaymentActivationTypeWrap(proto.type)
    }
    // This "unwrapped" accessor should only be used if the "has value" accessor has already been checked.
    @objc
    public var unwrappedType: SignalServiceProtosDataMessagePaymentActivationType {
        if !hasType {
            // TODO: We could make this a crashing assert.
            owsFailDebug("Unsafe unwrap of missing optional: Activation.type.")
        }
        return SignalServiceProtosDataMessagePaymentActivationTypeWrap(proto.type)
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
    public required convenience init(serializedData: Data) throws {
        let proto = try SignalServiceProtos_DataMessage.Payment.Activation(serializedBytes: serializedData)
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

extension SignalServiceProtosDataMessagePaymentActivation {
    @objc
    public static func builder() -> SignalServiceProtosDataMessagePaymentActivationBuilder {
        return SignalServiceProtosDataMessagePaymentActivationBuilder()
    }

    // asBuilder() constructs a builder that reflects the proto's contents.
    @objc
    public func asBuilder() -> SignalServiceProtosDataMessagePaymentActivationBuilder {
        let builder = SignalServiceProtosDataMessagePaymentActivationBuilder()
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
public class SignalServiceProtosDataMessagePaymentActivationBuilder: NSObject {

    private var proto = SignalServiceProtos_DataMessage.Payment.Activation()

    @objc
    fileprivate override init() {}

    @objc
    public func setType(_ valueParam: SignalServiceProtosDataMessagePaymentActivationType) {
        proto.type = SignalServiceProtosDataMessagePaymentActivationTypeUnwrap(valueParam)
    }

    public func setUnknownFields(_ unknownFields: SwiftProtobuf.UnknownStorage) {
        proto.unknownFields = unknownFields
    }

    @objc
    public func buildInfallibly() -> SignalServiceProtosDataMessagePaymentActivation {
        return SignalServiceProtosDataMessagePaymentActivation(proto)
    }

    @objc
    public func buildSerializedData() throws -> Data {
        return try SignalServiceProtosDataMessagePaymentActivation(proto).serializedData()
    }
}

#if TESTABLE_BUILD

extension SignalServiceProtosDataMessagePaymentActivation {
    @objc
    public func serializedDataIgnoringErrors() -> Data? {
        return try! self.serializedData()
    }
}

extension SignalServiceProtosDataMessagePaymentActivationBuilder {
    @objc
    public func buildIgnoringErrors() -> SignalServiceProtosDataMessagePaymentActivation? {
        return self.buildInfallibly()
    }
}

#endif

// MARK: - SignalServiceProtosDataMessagePayment

@objc
public class SignalServiceProtosDataMessagePayment: NSObject, Codable, NSSecureCoding {

    fileprivate let proto: SignalServiceProtos_DataMessage.Payment

    @objc
    public let notification: SignalServiceProtosDataMessagePaymentNotification?

    @objc
    public let activation: SignalServiceProtosDataMessagePaymentActivation?

    public var hasUnknownFields: Bool {
        return !proto.unknownFields.data.isEmpty
    }
    public var unknownFields: SwiftProtobuf.UnknownStorage? {
        guard hasUnknownFields else { return nil }
        return proto.unknownFields
    }

    private init(proto: SignalServiceProtos_DataMessage.Payment,
                 notification: SignalServiceProtosDataMessagePaymentNotification?,
                 activation: SignalServiceProtosDataMessagePaymentActivation?) {
        self.proto = proto
        self.notification = notification
        self.activation = activation
    }

    @objc
    public func serializedData() throws -> Data {
        return try self.proto.serializedData()
    }

    @objc
    public required convenience init(serializedData: Data) throws {
        let proto = try SignalServiceProtos_DataMessage.Payment(serializedBytes: serializedData)
        try self.init(proto)
    }

    fileprivate convenience init(_ proto: SignalServiceProtos_DataMessage.Payment) throws {
        var notification: SignalServiceProtosDataMessagePaymentNotification?
        if proto.hasNotification {
            notification = try SignalServiceProtosDataMessagePaymentNotification(proto.notification)
        }

        var activation: SignalServiceProtosDataMessagePaymentActivation?
        if proto.hasActivation {
            activation = SignalServiceProtosDataMessagePaymentActivation(proto.activation)
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

extension SignalServiceProtosDataMessagePayment {
    @objc
    public static func builder() -> SignalServiceProtosDataMessagePaymentBuilder {
        return SignalServiceProtosDataMessagePaymentBuilder()
    }

    // asBuilder() constructs a builder that reflects the proto's contents.
    @objc
    public func asBuilder() -> SignalServiceProtosDataMessagePaymentBuilder {
        let builder = SignalServiceProtosDataMessagePaymentBuilder()
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
public class SignalServiceProtosDataMessagePaymentBuilder: NSObject {

    private var proto = SignalServiceProtos_DataMessage.Payment()

    @objc
    fileprivate override init() {}

    @objc
    @available(swift, obsoleted: 1.0)
    public func setNotification(_ valueParam: SignalServiceProtosDataMessagePaymentNotification?) {
        guard let valueParam = valueParam else { return }
        proto.notification = valueParam.proto
    }

    public func setNotification(_ valueParam: SignalServiceProtosDataMessagePaymentNotification) {
        proto.notification = valueParam.proto
    }

    @objc
    @available(swift, obsoleted: 1.0)
    public func setActivation(_ valueParam: SignalServiceProtosDataMessagePaymentActivation?) {
        guard let valueParam = valueParam else { return }
        proto.activation = valueParam.proto
    }

    public func setActivation(_ valueParam: SignalServiceProtosDataMessagePaymentActivation) {
        proto.activation = valueParam.proto
    }

    public func setUnknownFields(_ unknownFields: SwiftProtobuf.UnknownStorage) {
        proto.unknownFields = unknownFields
    }

    @objc
    public func build() throws -> SignalServiceProtosDataMessagePayment {
        return try SignalServiceProtosDataMessagePayment(proto)
    }

    @objc
    public func buildSerializedData() throws -> Data {
        return try SignalServiceProtosDataMessagePayment(proto).serializedData()
    }
}

#if TESTABLE_BUILD

extension SignalServiceProtosDataMessagePayment {
    @objc
    public func serializedDataIgnoringErrors() -> Data? {
        return try! self.serializedData()
    }
}

extension SignalServiceProtosDataMessagePaymentBuilder {
    @objc
    public func buildIgnoringErrors() -> SignalServiceProtosDataMessagePayment? {
        return try! self.build()
    }
}

#endif

// MARK: - SignalServiceProtosDataMessageStoryContext

@objc
public class SignalServiceProtosDataMessageStoryContext: NSObject, Codable, NSSecureCoding {

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
    public required convenience init(serializedData: Data) throws {
        let proto = try SignalServiceProtos_DataMessage.StoryContext(serializedBytes: serializedData)
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

extension SignalServiceProtosDataMessageStoryContext {
    @objc
    public static func builder() -> SignalServiceProtosDataMessageStoryContextBuilder {
        return SignalServiceProtosDataMessageStoryContextBuilder()
    }

    // asBuilder() constructs a builder that reflects the proto's contents.
    @objc
    public func asBuilder() -> SignalServiceProtosDataMessageStoryContextBuilder {
        let builder = SignalServiceProtosDataMessageStoryContextBuilder()
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
public class SignalServiceProtosDataMessageStoryContextBuilder: NSObject {

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
    public func buildInfallibly() -> SignalServiceProtosDataMessageStoryContext {
        return SignalServiceProtosDataMessageStoryContext(proto)
    }

    @objc
    public func buildSerializedData() throws -> Data {
        return try SignalServiceProtosDataMessageStoryContext(proto).serializedData()
    }
}

#if TESTABLE_BUILD

extension SignalServiceProtosDataMessageStoryContext {
    @objc
    public func serializedDataIgnoringErrors() -> Data? {
        return try! self.serializedData()
    }
}

extension SignalServiceProtosDataMessageStoryContextBuilder {
    @objc
    public func buildIgnoringErrors() -> SignalServiceProtosDataMessageStoryContext? {
        return self.buildInfallibly()
    }
}

#endif

// MARK: - SignalServiceProtosDataMessageGiftBadge

@objc
public class SignalServiceProtosDataMessageGiftBadge: NSObject, Codable, NSSecureCoding {

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
    public required convenience init(serializedData: Data) throws {
        let proto = try SignalServiceProtos_DataMessage.GiftBadge(serializedBytes: serializedData)
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

extension SignalServiceProtosDataMessageGiftBadge {
    @objc
    public static func builder() -> SignalServiceProtosDataMessageGiftBadgeBuilder {
        return SignalServiceProtosDataMessageGiftBadgeBuilder()
    }

    // asBuilder() constructs a builder that reflects the proto's contents.
    @objc
    public func asBuilder() -> SignalServiceProtosDataMessageGiftBadgeBuilder {
        let builder = SignalServiceProtosDataMessageGiftBadgeBuilder()
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
public class SignalServiceProtosDataMessageGiftBadgeBuilder: NSObject {

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
    public func buildInfallibly() -> SignalServiceProtosDataMessageGiftBadge {
        return SignalServiceProtosDataMessageGiftBadge(proto)
    }

    @objc
    public func buildSerializedData() throws -> Data {
        return try SignalServiceProtosDataMessageGiftBadge(proto).serializedData()
    }
}

#if TESTABLE_BUILD

extension SignalServiceProtosDataMessageGiftBadge {
    @objc
    public func serializedDataIgnoringErrors() -> Data? {
        return try! self.serializedData()
    }
}

extension SignalServiceProtosDataMessageGiftBadgeBuilder {
    @objc
    public func buildIgnoringErrors() -> SignalServiceProtosDataMessageGiftBadge? {
        return self.buildInfallibly()
    }
}

#endif

// MARK: - SignalServiceProtosDataMessageFlags

@objc
public enum SignalServiceProtosDataMessageFlags: Int32 {
    case endSession = 1
    case expirationTimerUpdate = 2
    case profileKeyUpdate = 4
}

private func SignalServiceProtosDataMessageFlagsWrap(_ value: SignalServiceProtos_DataMessage.Flags) -> SignalServiceProtosDataMessageFlags {
    switch value {
    case .endSession: return .endSession
    case .expirationTimerUpdate: return .expirationTimerUpdate
    case .profileKeyUpdate: return .profileKeyUpdate
    }
}

private func SignalServiceProtosDataMessageFlagsUnwrap(_ value: SignalServiceProtosDataMessageFlags) -> SignalServiceProtos_DataMessage.Flags {
    switch value {
    case .endSession: return .endSession
    case .expirationTimerUpdate: return .expirationTimerUpdate
    case .profileKeyUpdate: return .profileKeyUpdate
    }
}

// MARK: - SignalServiceProtosDataMessageProtocolVersion

@objc
public enum SignalServiceProtosDataMessageProtocolVersion: Int32 {
    case initial = 0
    case messageTimers = 1
    case viewOnce = 2
    case viewOnceVideo = 3
    case reactions = 4
    case cdnSelectorAttachments = 5
    case mentions = 6
    case payments = 7
}

private func SignalServiceProtosDataMessageProtocolVersionWrap(_ value: SignalServiceProtos_DataMessage.ProtocolVersion) -> SignalServiceProtosDataMessageProtocolVersion {
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

private func SignalServiceProtosDataMessageProtocolVersionUnwrap(_ value: SignalServiceProtosDataMessageProtocolVersion) -> SignalServiceProtos_DataMessage.ProtocolVersion {
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

// MARK: - SignalServiceProtosDataMessage

@objc
public class SignalServiceProtosDataMessage: NSObject, Codable, NSSecureCoding {

    fileprivate let proto: SignalServiceProtos_DataMessage

    @objc
    public let attachments: [SignalServiceProtosAttachmentPointer]

    @objc
    public let groupV2: SignalServiceProtosGroupContextV2?

    @objc
    public let quote: SignalServiceProtosDataMessageQuote?

    @objc
    public let contact: [SignalServiceProtosDataMessageContact]

    @objc
    public let preview: [SignalServiceProtosPreview]

    @objc
    public let sticker: SignalServiceProtosDataMessageSticker?

    @objc
    public let reaction: SignalServiceProtosDataMessageReaction?

    @objc
    public let delete: SignalServiceProtosDataMessageDelete?

    @objc
    public let bodyRanges: [SignalServiceProtosBodyRange]

    @objc
    public let groupCallUpdate: SignalServiceProtosDataMessageGroupCallUpdate?

    @objc
    public let payment: SignalServiceProtosDataMessagePayment?

    @objc
    public let storyContext: SignalServiceProtosDataMessageStoryContext?

    @objc
    public let giftBadge: SignalServiceProtosDataMessageGiftBadge?

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
    public var expireTimerVersion: UInt32 {
        return proto.expireTimerVersion
    }
    @objc
    public var hasExpireTimerVersion: Bool {
        return proto.hasExpireTimerVersion
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
                 attachments: [SignalServiceProtosAttachmentPointer],
                 groupV2: SignalServiceProtosGroupContextV2?,
                 quote: SignalServiceProtosDataMessageQuote?,
                 contact: [SignalServiceProtosDataMessageContact],
                 preview: [SignalServiceProtosPreview],
                 sticker: SignalServiceProtosDataMessageSticker?,
                 reaction: SignalServiceProtosDataMessageReaction?,
                 delete: SignalServiceProtosDataMessageDelete?,
                 bodyRanges: [SignalServiceProtosBodyRange],
                 groupCallUpdate: SignalServiceProtosDataMessageGroupCallUpdate?,
                 payment: SignalServiceProtosDataMessagePayment?,
                 storyContext: SignalServiceProtosDataMessageStoryContext?,
                 giftBadge: SignalServiceProtosDataMessageGiftBadge?) {
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
    public required convenience init(serializedData: Data) throws {
        let proto = try SignalServiceProtos_DataMessage(serializedBytes: serializedData)
        try self.init(proto)
    }

    fileprivate convenience init(_ proto: SignalServiceProtos_DataMessage) throws {
        var attachments: [SignalServiceProtosAttachmentPointer] = []
        attachments = proto.attachments.map { SignalServiceProtosAttachmentPointer($0) }

        var groupV2: SignalServiceProtosGroupContextV2?
        if proto.hasGroupV2 {
            groupV2 = SignalServiceProtosGroupContextV2(proto.groupV2)
        }

        var quote: SignalServiceProtosDataMessageQuote?
        if proto.hasQuote {
            quote = try SignalServiceProtosDataMessageQuote(proto.quote)
        }

        var contact: [SignalServiceProtosDataMessageContact] = []
        contact = proto.contact.map { SignalServiceProtosDataMessageContact($0) }

        var preview: [SignalServiceProtosPreview] = []
        preview = try proto.preview.map { try SignalServiceProtosPreview($0) }

        var sticker: SignalServiceProtosDataMessageSticker?
        if proto.hasSticker {
            sticker = try SignalServiceProtosDataMessageSticker(proto.sticker)
        }

        var reaction: SignalServiceProtosDataMessageReaction?
        if proto.hasReaction {
            reaction = try SignalServiceProtosDataMessageReaction(proto.reaction)
        }

        var delete: SignalServiceProtosDataMessageDelete?
        if proto.hasDelete {
            delete = try SignalServiceProtosDataMessageDelete(proto.delete)
        }

        var bodyRanges: [SignalServiceProtosBodyRange] = []
        bodyRanges = proto.bodyRanges.map { SignalServiceProtosBodyRange($0) }

        var groupCallUpdate: SignalServiceProtosDataMessageGroupCallUpdate?
        if proto.hasGroupCallUpdate {
            groupCallUpdate = SignalServiceProtosDataMessageGroupCallUpdate(proto.groupCallUpdate)
        }

        var payment: SignalServiceProtosDataMessagePayment?
        if proto.hasPayment {
            payment = try SignalServiceProtosDataMessagePayment(proto.payment)
        }

        var storyContext: SignalServiceProtosDataMessageStoryContext?
        if proto.hasStoryContext {
            storyContext = SignalServiceProtosDataMessageStoryContext(proto.storyContext)
        }

        var giftBadge: SignalServiceProtosDataMessageGiftBadge?
        if proto.hasGiftBadge {
            giftBadge = SignalServiceProtosDataMessageGiftBadge(proto.giftBadge)
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

extension SignalServiceProtosDataMessage {
    @objc
    public static func builder() -> SignalServiceProtosDataMessageBuilder {
        return SignalServiceProtosDataMessageBuilder()
    }

    // asBuilder() constructs a builder that reflects the proto's contents.
    @objc
    public func asBuilder() -> SignalServiceProtosDataMessageBuilder {
        let builder = SignalServiceProtosDataMessageBuilder()
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
        if hasExpireTimerVersion {
            builder.setExpireTimerVersion(expireTimerVersion)
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
public class SignalServiceProtosDataMessageBuilder: NSObject {

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
    public func addAttachments(_ valueParam: SignalServiceProtosAttachmentPointer) {
        proto.attachments.append(valueParam.proto)
    }

    @objc
    public func setAttachments(_ wrappedItems: [SignalServiceProtosAttachmentPointer]) {
        proto.attachments = wrappedItems.map { $0.proto }
    }

    @objc
    @available(swift, obsoleted: 1.0)
    public func setGroupV2(_ valueParam: SignalServiceProtosGroupContextV2?) {
        guard let valueParam = valueParam else { return }
        proto.groupV2 = valueParam.proto
    }

    public func setGroupV2(_ valueParam: SignalServiceProtosGroupContextV2) {
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
    public func setExpireTimerVersion(_ valueParam: UInt32) {
        proto.expireTimerVersion = valueParam
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
    public func setQuote(_ valueParam: SignalServiceProtosDataMessageQuote?) {
        guard let valueParam = valueParam else { return }
        proto.quote = valueParam.proto
    }

    public func setQuote(_ valueParam: SignalServiceProtosDataMessageQuote) {
        proto.quote = valueParam.proto
    }

    @objc
    public func addContact(_ valueParam: SignalServiceProtosDataMessageContact) {
        proto.contact.append(valueParam.proto)
    }

    @objc
    public func setContact(_ wrappedItems: [SignalServiceProtosDataMessageContact]) {
        proto.contact = wrappedItems.map { $0.proto }
    }

    @objc
    public func addPreview(_ valueParam: SignalServiceProtosPreview) {
        proto.preview.append(valueParam.proto)
    }

    @objc
    public func setPreview(_ wrappedItems: [SignalServiceProtosPreview]) {
        proto.preview = wrappedItems.map { $0.proto }
    }

    @objc
    @available(swift, obsoleted: 1.0)
    public func setSticker(_ valueParam: SignalServiceProtosDataMessageSticker?) {
        guard let valueParam = valueParam else { return }
        proto.sticker = valueParam.proto
    }

    public func setSticker(_ valueParam: SignalServiceProtosDataMessageSticker) {
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
    public func setReaction(_ valueParam: SignalServiceProtosDataMessageReaction?) {
        guard let valueParam = valueParam else { return }
        proto.reaction = valueParam.proto
    }

    public func setReaction(_ valueParam: SignalServiceProtosDataMessageReaction) {
        proto.reaction = valueParam.proto
    }

    @objc
    @available(swift, obsoleted: 1.0)
    public func setDelete(_ valueParam: SignalServiceProtosDataMessageDelete?) {
        guard let valueParam = valueParam else { return }
        proto.delete = valueParam.proto
    }

    public func setDelete(_ valueParam: SignalServiceProtosDataMessageDelete) {
        proto.delete = valueParam.proto
    }

    @objc
    public func addBodyRanges(_ valueParam: SignalServiceProtosBodyRange) {
        proto.bodyRanges.append(valueParam.proto)
    }

    @objc
    public func setBodyRanges(_ wrappedItems: [SignalServiceProtosBodyRange]) {
        proto.bodyRanges = wrappedItems.map { $0.proto }
    }

    @objc
    @available(swift, obsoleted: 1.0)
    public func setGroupCallUpdate(_ valueParam: SignalServiceProtosDataMessageGroupCallUpdate?) {
        guard let valueParam = valueParam else { return }
        proto.groupCallUpdate = valueParam.proto
    }

    public func setGroupCallUpdate(_ valueParam: SignalServiceProtosDataMessageGroupCallUpdate) {
        proto.groupCallUpdate = valueParam.proto
    }

    @objc
    @available(swift, obsoleted: 1.0)
    public func setPayment(_ valueParam: SignalServiceProtosDataMessagePayment?) {
        guard let valueParam = valueParam else { return }
        proto.payment = valueParam.proto
    }

    public func setPayment(_ valueParam: SignalServiceProtosDataMessagePayment) {
        proto.payment = valueParam.proto
    }

    @objc
    @available(swift, obsoleted: 1.0)
    public func setStoryContext(_ valueParam: SignalServiceProtosDataMessageStoryContext?) {
        guard let valueParam = valueParam else { return }
        proto.storyContext = valueParam.proto
    }

    public func setStoryContext(_ valueParam: SignalServiceProtosDataMessageStoryContext) {
        proto.storyContext = valueParam.proto
    }

    @objc
    @available(swift, obsoleted: 1.0)
    public func setGiftBadge(_ valueParam: SignalServiceProtosDataMessageGiftBadge?) {
        guard let valueParam = valueParam else { return }
        proto.giftBadge = valueParam.proto
    }

    public func setGiftBadge(_ valueParam: SignalServiceProtosDataMessageGiftBadge) {
        proto.giftBadge = valueParam.proto
    }

    public func setUnknownFields(_ unknownFields: SwiftProtobuf.UnknownStorage) {
        proto.unknownFields = unknownFields
    }

    @objc
    public func build() throws -> SignalServiceProtosDataMessage {
        return try SignalServiceProtosDataMessage(proto)
    }

    @objc
    public func buildSerializedData() throws -> Data {
        return try SignalServiceProtosDataMessage(proto).serializedData()
    }
}

#if TESTABLE_BUILD

extension SignalServiceProtosDataMessage {
    @objc
    public func serializedDataIgnoringErrors() -> Data? {
        return try! self.serializedData()
    }
}

extension SignalServiceProtosDataMessageBuilder {
    @objc
    public func buildIgnoringErrors() -> SignalServiceProtosDataMessage? {
        return try! self.build()
    }
}

#endif

// MARK: - SignalServiceProtosNullMessage

@objc
public class SignalServiceProtosNullMessage: NSObject, Codable, NSSecureCoding {

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
    public required convenience init(serializedData: Data) throws {
        let proto = try SignalServiceProtos_NullMessage(serializedBytes: serializedData)
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

extension SignalServiceProtosNullMessage {
    @objc
    public static func builder() -> SignalServiceProtosNullMessageBuilder {
        return SignalServiceProtosNullMessageBuilder()
    }

    // asBuilder() constructs a builder that reflects the proto's contents.
    @objc
    public func asBuilder() -> SignalServiceProtosNullMessageBuilder {
        let builder = SignalServiceProtosNullMessageBuilder()
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
public class SignalServiceProtosNullMessageBuilder: NSObject {

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
    public func buildInfallibly() -> SignalServiceProtosNullMessage {
        return SignalServiceProtosNullMessage(proto)
    }

    @objc
    public func buildSerializedData() throws -> Data {
        return try SignalServiceProtosNullMessage(proto).serializedData()
    }
}

#if TESTABLE_BUILD

extension SignalServiceProtosNullMessage {
    @objc
    public func serializedDataIgnoringErrors() -> Data? {
        return try! self.serializedData()
    }
}

extension SignalServiceProtosNullMessageBuilder {
    @objc
    public func buildIgnoringErrors() -> SignalServiceProtosNullMessage? {
        return self.buildInfallibly()
    }
}

#endif

// MARK: - SignalServiceProtosReceiptMessageType

@objc
public enum SignalServiceProtosReceiptMessageType: Int32 {
    case delivery = 0
    case read = 1
    case viewed = 2
}

private func SignalServiceProtosReceiptMessageTypeWrap(_ value: SignalServiceProtos_ReceiptMessage.TypeEnum) -> SignalServiceProtosReceiptMessageType {
    switch value {
    case .delivery: return .delivery
    case .read: return .read
    case .viewed: return .viewed
    }
}

private func SignalServiceProtosReceiptMessageTypeUnwrap(_ value: SignalServiceProtosReceiptMessageType) -> SignalServiceProtos_ReceiptMessage.TypeEnum {
    switch value {
    case .delivery: return .delivery
    case .read: return .read
    case .viewed: return .viewed
    }
}

// MARK: - SignalServiceProtosReceiptMessage

@objc
public class SignalServiceProtosReceiptMessage: NSObject, Codable, NSSecureCoding {

    fileprivate let proto: SignalServiceProtos_ReceiptMessage

    public var type: SignalServiceProtosReceiptMessageType? {
        guard hasType else {
            return nil
        }
        return SignalServiceProtosReceiptMessageTypeWrap(proto.type)
    }
    // This "unwrapped" accessor should only be used if the "has value" accessor has already been checked.
    @objc
    public var unwrappedType: SignalServiceProtosReceiptMessageType {
        if !hasType {
            // TODO: We could make this a crashing assert.
            owsFailDebug("Unsafe unwrap of missing optional: ReceiptMessage.type.")
        }
        return SignalServiceProtosReceiptMessageTypeWrap(proto.type)
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
    public required convenience init(serializedData: Data) throws {
        let proto = try SignalServiceProtos_ReceiptMessage(serializedBytes: serializedData)
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

extension SignalServiceProtosReceiptMessage {
    @objc
    public static func builder() -> SignalServiceProtosReceiptMessageBuilder {
        return SignalServiceProtosReceiptMessageBuilder()
    }

    // asBuilder() constructs a builder that reflects the proto's contents.
    @objc
    public func asBuilder() -> SignalServiceProtosReceiptMessageBuilder {
        let builder = SignalServiceProtosReceiptMessageBuilder()
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
public class SignalServiceProtosReceiptMessageBuilder: NSObject {

    private var proto = SignalServiceProtos_ReceiptMessage()

    @objc
    fileprivate override init() {}

    @objc
    public func setType(_ valueParam: SignalServiceProtosReceiptMessageType) {
        proto.type = SignalServiceProtosReceiptMessageTypeUnwrap(valueParam)
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
    public func buildInfallibly() -> SignalServiceProtosReceiptMessage {
        return SignalServiceProtosReceiptMessage(proto)
    }

    @objc
    public func buildSerializedData() throws -> Data {
        return try SignalServiceProtosReceiptMessage(proto).serializedData()
    }
}

#if TESTABLE_BUILD

extension SignalServiceProtosReceiptMessage {
    @objc
    public func serializedDataIgnoringErrors() -> Data? {
        return try! self.serializedData()
    }
}

extension SignalServiceProtosReceiptMessageBuilder {
    @objc
    public func buildIgnoringErrors() -> SignalServiceProtosReceiptMessage? {
        return self.buildInfallibly()
    }
}

#endif

// MARK: - SignalServiceProtosVerifiedState

@objc
public enum SignalServiceProtosVerifiedState: Int32 {
    case `default` = 0
    case verified = 1
    case unverified = 2
}

private func SignalServiceProtosVerifiedStateWrap(_ value: SignalServiceProtos_Verified.State) -> SignalServiceProtosVerifiedState {
    switch value {
    case .default: return .default
    case .verified: return .verified
    case .unverified: return .unverified
    }
}

private func SignalServiceProtosVerifiedStateUnwrap(_ value: SignalServiceProtosVerifiedState) -> SignalServiceProtos_Verified.State {
    switch value {
    case .default: return .default
    case .verified: return .verified
    case .unverified: return .unverified
    }
}

// MARK: - SignalServiceProtosVerified

@objc
public class SignalServiceProtosVerified: NSObject, Codable, NSSecureCoding {

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

    public var state: SignalServiceProtosVerifiedState? {
        guard hasState else {
            return nil
        }
        return SignalServiceProtosVerifiedStateWrap(proto.state)
    }
    // This "unwrapped" accessor should only be used if the "has value" accessor has already been checked.
    @objc
    public var unwrappedState: SignalServiceProtosVerifiedState {
        if !hasState {
            // TODO: We could make this a crashing assert.
            owsFailDebug("Unsafe unwrap of missing optional: Verified.state.")
        }
        return SignalServiceProtosVerifiedStateWrap(proto.state)
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
    public required convenience init(serializedData: Data) throws {
        let proto = try SignalServiceProtos_Verified(serializedBytes: serializedData)
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

extension SignalServiceProtosVerified {
    @objc
    public static func builder() -> SignalServiceProtosVerifiedBuilder {
        return SignalServiceProtosVerifiedBuilder()
    }

    // asBuilder() constructs a builder that reflects the proto's contents.
    @objc
    public func asBuilder() -> SignalServiceProtosVerifiedBuilder {
        let builder = SignalServiceProtosVerifiedBuilder()
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
public class SignalServiceProtosVerifiedBuilder: NSObject {

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
    public func setState(_ valueParam: SignalServiceProtosVerifiedState) {
        proto.state = SignalServiceProtosVerifiedStateUnwrap(valueParam)
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
    public func buildInfallibly() -> SignalServiceProtosVerified {
        return SignalServiceProtosVerified(proto)
    }

    @objc
    public func buildSerializedData() throws -> Data {
        return try SignalServiceProtosVerified(proto).serializedData()
    }
}

#if TESTABLE_BUILD

extension SignalServiceProtosVerified {
    @objc
    public func serializedDataIgnoringErrors() -> Data? {
        return try! self.serializedData()
    }
}

extension SignalServiceProtosVerifiedBuilder {
    @objc
    public func buildIgnoringErrors() -> SignalServiceProtosVerified? {
        return self.buildInfallibly()
    }
}

#endif

// MARK: - SignalServiceProtosSyncMessageSentUnidentifiedDeliveryStatus

@objc
public class SignalServiceProtosSyncMessageSentUnidentifiedDeliveryStatus: NSObject, Codable, NSSecureCoding {

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
    public required convenience init(serializedData: Data) throws {
        let proto = try SignalServiceProtos_SyncMessage.Sent.UnidentifiedDeliveryStatus(serializedBytes: serializedData)
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

extension SignalServiceProtosSyncMessageSentUnidentifiedDeliveryStatus {
    @objc
    public static func builder() -> SignalServiceProtosSyncMessageSentUnidentifiedDeliveryStatusBuilder {
        return SignalServiceProtosSyncMessageSentUnidentifiedDeliveryStatusBuilder()
    }

    // asBuilder() constructs a builder that reflects the proto's contents.
    @objc
    public func asBuilder() -> SignalServiceProtosSyncMessageSentUnidentifiedDeliveryStatusBuilder {
        let builder = SignalServiceProtosSyncMessageSentUnidentifiedDeliveryStatusBuilder()
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
public class SignalServiceProtosSyncMessageSentUnidentifiedDeliveryStatusBuilder: NSObject {

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
    public func buildInfallibly() -> SignalServiceProtosSyncMessageSentUnidentifiedDeliveryStatus {
        return SignalServiceProtosSyncMessageSentUnidentifiedDeliveryStatus(proto)
    }

    @objc
    public func buildSerializedData() throws -> Data {
        return try SignalServiceProtosSyncMessageSentUnidentifiedDeliveryStatus(proto).serializedData()
    }
}

#if TESTABLE_BUILD

extension SignalServiceProtosSyncMessageSentUnidentifiedDeliveryStatus {
    @objc
    public func serializedDataIgnoringErrors() -> Data? {
        return try! self.serializedData()
    }
}

extension SignalServiceProtosSyncMessageSentUnidentifiedDeliveryStatusBuilder {
    @objc
    public func buildIgnoringErrors() -> SignalServiceProtosSyncMessageSentUnidentifiedDeliveryStatus? {
        return self.buildInfallibly()
    }
}

#endif

// MARK: - SignalServiceProtosSyncMessageSentStoryMessageRecipient

@objc
public class SignalServiceProtosSyncMessageSentStoryMessageRecipient: NSObject, Codable, NSSecureCoding {

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
    public required convenience init(serializedData: Data) throws {
        let proto = try SignalServiceProtos_SyncMessage.Sent.StoryMessageRecipient(serializedBytes: serializedData)
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

extension SignalServiceProtosSyncMessageSentStoryMessageRecipient {
    @objc
    public static func builder() -> SignalServiceProtosSyncMessageSentStoryMessageRecipientBuilder {
        return SignalServiceProtosSyncMessageSentStoryMessageRecipientBuilder()
    }

    // asBuilder() constructs a builder that reflects the proto's contents.
    @objc
    public func asBuilder() -> SignalServiceProtosSyncMessageSentStoryMessageRecipientBuilder {
        let builder = SignalServiceProtosSyncMessageSentStoryMessageRecipientBuilder()
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
public class SignalServiceProtosSyncMessageSentStoryMessageRecipientBuilder: NSObject {

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
    public func buildInfallibly() -> SignalServiceProtosSyncMessageSentStoryMessageRecipient {
        return SignalServiceProtosSyncMessageSentStoryMessageRecipient(proto)
    }

    @objc
    public func buildSerializedData() throws -> Data {
        return try SignalServiceProtosSyncMessageSentStoryMessageRecipient(proto).serializedData()
    }
}

#if TESTABLE_BUILD

extension SignalServiceProtosSyncMessageSentStoryMessageRecipient {
    @objc
    public func serializedDataIgnoringErrors() -> Data? {
        return try! self.serializedData()
    }
}

extension SignalServiceProtosSyncMessageSentStoryMessageRecipientBuilder {
    @objc
    public func buildIgnoringErrors() -> SignalServiceProtosSyncMessageSentStoryMessageRecipient? {
        return self.buildInfallibly()
    }
}

#endif

// MARK: - SignalServiceProtosSyncMessageSent

@objc
public class SignalServiceProtosSyncMessageSent: NSObject, Codable, NSSecureCoding {

    fileprivate let proto: SignalServiceProtos_SyncMessage.Sent

    @objc
    public let message: SignalServiceProtosDataMessage?

    @objc
    public let unidentifiedStatus: [SignalServiceProtosSyncMessageSentUnidentifiedDeliveryStatus]

    @objc
    public let storyMessage: SignalServiceProtosStoryMessage?

    @objc
    public let storyMessageRecipients: [SignalServiceProtosSyncMessageSentStoryMessageRecipient]

    @objc
    public let editMessage: SignalServiceProtosEditMessage?

    @objc
    public var destinationE164: String? {
        guard hasDestinationE164 else {
            return nil
        }
        return proto.destinationE164
    }
    @objc
    public var hasDestinationE164: Bool {
        return proto.hasDestinationE164
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
                 message: SignalServiceProtosDataMessage?,
                 unidentifiedStatus: [SignalServiceProtosSyncMessageSentUnidentifiedDeliveryStatus],
                 storyMessage: SignalServiceProtosStoryMessage?,
                 storyMessageRecipients: [SignalServiceProtosSyncMessageSentStoryMessageRecipient],
                 editMessage: SignalServiceProtosEditMessage?) {
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
    public required convenience init(serializedData: Data) throws {
        let proto = try SignalServiceProtos_SyncMessage.Sent(serializedBytes: serializedData)
        try self.init(proto)
    }

    fileprivate convenience init(_ proto: SignalServiceProtos_SyncMessage.Sent) throws {
        var message: SignalServiceProtosDataMessage?
        if proto.hasMessage {
            message = try SignalServiceProtosDataMessage(proto.message)
        }

        var unidentifiedStatus: [SignalServiceProtosSyncMessageSentUnidentifiedDeliveryStatus] = []
        unidentifiedStatus = proto.unidentifiedStatus.map { SignalServiceProtosSyncMessageSentUnidentifiedDeliveryStatus($0) }

        var storyMessage: SignalServiceProtosStoryMessage?
        if proto.hasStoryMessage {
            storyMessage = try SignalServiceProtosStoryMessage(proto.storyMessage)
        }

        var storyMessageRecipients: [SignalServiceProtosSyncMessageSentStoryMessageRecipient] = []
        storyMessageRecipients = proto.storyMessageRecipients.map { SignalServiceProtosSyncMessageSentStoryMessageRecipient($0) }

        var editMessage: SignalServiceProtosEditMessage?
        if proto.hasEditMessage {
            editMessage = try SignalServiceProtosEditMessage(proto.editMessage)
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

extension SignalServiceProtosSyncMessageSent {
    @objc
    public static func builder() -> SignalServiceProtosSyncMessageSentBuilder {
        return SignalServiceProtosSyncMessageSentBuilder()
    }

    // asBuilder() constructs a builder that reflects the proto's contents.
    @objc
    public func asBuilder() -> SignalServiceProtosSyncMessageSentBuilder {
        let builder = SignalServiceProtosSyncMessageSentBuilder()
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
public class SignalServiceProtosSyncMessageSentBuilder: NSObject {

    private var proto = SignalServiceProtos_SyncMessage.Sent()

    @objc
    fileprivate override init() {}

    @objc
    @available(swift, obsoleted: 1.0)
    public func setDestinationE164(_ valueParam: String?) {
        guard let valueParam = valueParam else { return }
        proto.destinationE164 = valueParam
    }

    public func setDestinationE164(_ valueParam: String) {
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
    public func setMessage(_ valueParam: SignalServiceProtosDataMessage?) {
        guard let valueParam = valueParam else { return }
        proto.message = valueParam.proto
    }

    public func setMessage(_ valueParam: SignalServiceProtosDataMessage) {
        proto.message = valueParam.proto
    }

    @objc
    public func setExpirationStartTimestamp(_ valueParam: UInt64) {
        proto.expirationStartTimestamp = valueParam
    }

    @objc
    public func addUnidentifiedStatus(_ valueParam: SignalServiceProtosSyncMessageSentUnidentifiedDeliveryStatus) {
        proto.unidentifiedStatus.append(valueParam.proto)
    }

    @objc
    public func setUnidentifiedStatus(_ wrappedItems: [SignalServiceProtosSyncMessageSentUnidentifiedDeliveryStatus]) {
        proto.unidentifiedStatus = wrappedItems.map { $0.proto }
    }

    @objc
    public func setIsRecipientUpdate(_ valueParam: Bool) {
        proto.isRecipientUpdate = valueParam
    }

    @objc
    @available(swift, obsoleted: 1.0)
    public func setStoryMessage(_ valueParam: SignalServiceProtosStoryMessage?) {
        guard let valueParam = valueParam else { return }
        proto.storyMessage = valueParam.proto
    }

    public func setStoryMessage(_ valueParam: SignalServiceProtosStoryMessage) {
        proto.storyMessage = valueParam.proto
    }

    @objc
    public func addStoryMessageRecipients(_ valueParam: SignalServiceProtosSyncMessageSentStoryMessageRecipient) {
        proto.storyMessageRecipients.append(valueParam.proto)
    }

    @objc
    public func setStoryMessageRecipients(_ wrappedItems: [SignalServiceProtosSyncMessageSentStoryMessageRecipient]) {
        proto.storyMessageRecipients = wrappedItems.map { $0.proto }
    }

    @objc
    @available(swift, obsoleted: 1.0)
    public func setEditMessage(_ valueParam: SignalServiceProtosEditMessage?) {
        guard let valueParam = valueParam else { return }
        proto.editMessage = valueParam.proto
    }

    public func setEditMessage(_ valueParam: SignalServiceProtosEditMessage) {
        proto.editMessage = valueParam.proto
    }

    public func setUnknownFields(_ unknownFields: SwiftProtobuf.UnknownStorage) {
        proto.unknownFields = unknownFields
    }

    @objc
    public func build() throws -> SignalServiceProtosSyncMessageSent {
        return try SignalServiceProtosSyncMessageSent(proto)
    }

    @objc
    public func buildSerializedData() throws -> Data {
        return try SignalServiceProtosSyncMessageSent(proto).serializedData()
    }
}

#if TESTABLE_BUILD

extension SignalServiceProtosSyncMessageSent {
    @objc
    public func serializedDataIgnoringErrors() -> Data? {
        return try! self.serializedData()
    }
}

extension SignalServiceProtosSyncMessageSentBuilder {
    @objc
    public func buildIgnoringErrors() -> SignalServiceProtosSyncMessageSent? {
        return try! self.build()
    }
}

#endif

// MARK: - SignalServiceProtosSyncMessageContacts

@objc
public class SignalServiceProtosSyncMessageContacts: NSObject, Codable, NSSecureCoding {

    fileprivate let proto: SignalServiceProtos_SyncMessage.Contacts

    @objc
    public let blob: SignalServiceProtosAttachmentPointer

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
                 blob: SignalServiceProtosAttachmentPointer) {
        self.proto = proto
        self.blob = blob
    }

    @objc
    public func serializedData() throws -> Data {
        return try self.proto.serializedData()
    }

    @objc
    public required convenience init(serializedData: Data) throws {
        let proto = try SignalServiceProtos_SyncMessage.Contacts(serializedBytes: serializedData)
        try self.init(proto)
    }

    fileprivate convenience init(_ proto: SignalServiceProtos_SyncMessage.Contacts) throws {
        guard proto.hasBlob else {
            throw SignalServiceProtosError.invalidProtobuf(description: "[\(Self.self)] missing required field: blob")
        }
        let blob = SignalServiceProtosAttachmentPointer(proto.blob)

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

extension SignalServiceProtosSyncMessageContacts {
    @objc
    public static func builder(blob: SignalServiceProtosAttachmentPointer) -> SignalServiceProtosSyncMessageContactsBuilder {
        return SignalServiceProtosSyncMessageContactsBuilder(blob: blob)
    }

    // asBuilder() constructs a builder that reflects the proto's contents.
    @objc
    public func asBuilder() -> SignalServiceProtosSyncMessageContactsBuilder {
        let builder = SignalServiceProtosSyncMessageContactsBuilder(blob: blob)
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
public class SignalServiceProtosSyncMessageContactsBuilder: NSObject {

    private var proto = SignalServiceProtos_SyncMessage.Contacts()

    @objc
    fileprivate override init() {}

    @objc
    fileprivate init(blob: SignalServiceProtosAttachmentPointer) {
        super.init()

        setBlob(blob)
    }

    @objc
    @available(swift, obsoleted: 1.0)
    public func setBlob(_ valueParam: SignalServiceProtosAttachmentPointer?) {
        guard let valueParam = valueParam else { return }
        proto.blob = valueParam.proto
    }

    public func setBlob(_ valueParam: SignalServiceProtosAttachmentPointer) {
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
    public func build() throws -> SignalServiceProtosSyncMessageContacts {
        return try SignalServiceProtosSyncMessageContacts(proto)
    }

    @objc
    public func buildSerializedData() throws -> Data {
        return try SignalServiceProtosSyncMessageContacts(proto).serializedData()
    }
}

#if TESTABLE_BUILD

extension SignalServiceProtosSyncMessageContacts {
    @objc
    public func serializedDataIgnoringErrors() -> Data? {
        return try! self.serializedData()
    }
}

extension SignalServiceProtosSyncMessageContactsBuilder {
    @objc
    public func buildIgnoringErrors() -> SignalServiceProtosSyncMessageContacts? {
        return try! self.build()
    }
}

#endif

// MARK: - SignalServiceProtosSyncMessageBlocked

@objc
public class SignalServiceProtosSyncMessageBlocked: NSObject, Codable, NSSecureCoding {

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
    public required convenience init(serializedData: Data) throws {
        let proto = try SignalServiceProtos_SyncMessage.Blocked(serializedBytes: serializedData)
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

extension SignalServiceProtosSyncMessageBlocked {
    @objc
    public static func builder() -> SignalServiceProtosSyncMessageBlockedBuilder {
        return SignalServiceProtosSyncMessageBlockedBuilder()
    }

    // asBuilder() constructs a builder that reflects the proto's contents.
    @objc
    public func asBuilder() -> SignalServiceProtosSyncMessageBlockedBuilder {
        let builder = SignalServiceProtosSyncMessageBlockedBuilder()
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
public class SignalServiceProtosSyncMessageBlockedBuilder: NSObject {

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
    public func buildInfallibly() -> SignalServiceProtosSyncMessageBlocked {
        return SignalServiceProtosSyncMessageBlocked(proto)
    }

    @objc
    public func buildSerializedData() throws -> Data {
        return try SignalServiceProtosSyncMessageBlocked(proto).serializedData()
    }
}

#if TESTABLE_BUILD

extension SignalServiceProtosSyncMessageBlocked {
    @objc
    public func serializedDataIgnoringErrors() -> Data? {
        return try! self.serializedData()
    }
}

extension SignalServiceProtosSyncMessageBlockedBuilder {
    @objc
    public func buildIgnoringErrors() -> SignalServiceProtosSyncMessageBlocked? {
        return self.buildInfallibly()
    }
}

#endif

// MARK: - SignalServiceProtosSyncMessageRequestType

@objc
public enum SignalServiceProtosSyncMessageRequestType: Int32 {
    case unknown = 0
    case contacts = 1
    case blocked = 3
    case configuration = 4
    case keys = 5
}

private func SignalServiceProtosSyncMessageRequestTypeWrap(_ value: SignalServiceProtos_SyncMessage.Request.TypeEnum) -> SignalServiceProtosSyncMessageRequestType {
    switch value {
    case .unknown: return .unknown
    case .contacts: return .contacts
    case .blocked: return .blocked
    case .configuration: return .configuration
    case .keys: return .keys
    }
}

private func SignalServiceProtosSyncMessageRequestTypeUnwrap(_ value: SignalServiceProtosSyncMessageRequestType) -> SignalServiceProtos_SyncMessage.Request.TypeEnum {
    switch value {
    case .unknown: return .unknown
    case .contacts: return .contacts
    case .blocked: return .blocked
    case .configuration: return .configuration
    case .keys: return .keys
    }
}

// MARK: - SignalServiceProtosSyncMessageRequest

@objc
public class SignalServiceProtosSyncMessageRequest: NSObject, Codable, NSSecureCoding {

    fileprivate let proto: SignalServiceProtos_SyncMessage.Request

    public var type: SignalServiceProtosSyncMessageRequestType? {
        guard hasType else {
            return nil
        }
        return SignalServiceProtosSyncMessageRequestTypeWrap(proto.type)
    }
    // This "unwrapped" accessor should only be used if the "has value" accessor has already been checked.
    @objc
    public var unwrappedType: SignalServiceProtosSyncMessageRequestType {
        if !hasType {
            // TODO: We could make this a crashing assert.
            owsFailDebug("Unsafe unwrap of missing optional: Request.type.")
        }
        return SignalServiceProtosSyncMessageRequestTypeWrap(proto.type)
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
    public required convenience init(serializedData: Data) throws {
        let proto = try SignalServiceProtos_SyncMessage.Request(serializedBytes: serializedData)
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

extension SignalServiceProtosSyncMessageRequest {
    @objc
    public static func builder() -> SignalServiceProtosSyncMessageRequestBuilder {
        return SignalServiceProtosSyncMessageRequestBuilder()
    }

    // asBuilder() constructs a builder that reflects the proto's contents.
    @objc
    public func asBuilder() -> SignalServiceProtosSyncMessageRequestBuilder {
        let builder = SignalServiceProtosSyncMessageRequestBuilder()
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
public class SignalServiceProtosSyncMessageRequestBuilder: NSObject {

    private var proto = SignalServiceProtos_SyncMessage.Request()

    @objc
    fileprivate override init() {}

    @objc
    public func setType(_ valueParam: SignalServiceProtosSyncMessageRequestType) {
        proto.type = SignalServiceProtosSyncMessageRequestTypeUnwrap(valueParam)
    }

    public func setUnknownFields(_ unknownFields: SwiftProtobuf.UnknownStorage) {
        proto.unknownFields = unknownFields
    }

    @objc
    public func buildInfallibly() -> SignalServiceProtosSyncMessageRequest {
        return SignalServiceProtosSyncMessageRequest(proto)
    }

    @objc
    public func buildSerializedData() throws -> Data {
        return try SignalServiceProtosSyncMessageRequest(proto).serializedData()
    }
}

#if TESTABLE_BUILD

extension SignalServiceProtosSyncMessageRequest {
    @objc
    public func serializedDataIgnoringErrors() -> Data? {
        return try! self.serializedData()
    }
}

extension SignalServiceProtosSyncMessageRequestBuilder {
    @objc
    public func buildIgnoringErrors() -> SignalServiceProtosSyncMessageRequest? {
        return self.buildInfallibly()
    }
}

#endif

// MARK: - SignalServiceProtosSyncMessageRead

@objc
public class SignalServiceProtosSyncMessageRead: NSObject, Codable, NSSecureCoding {

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
    public required convenience init(serializedData: Data) throws {
        let proto = try SignalServiceProtos_SyncMessage.Read(serializedBytes: serializedData)
        try self.init(proto)
    }

    fileprivate convenience init(_ proto: SignalServiceProtos_SyncMessage.Read) throws {
        guard proto.hasTimestamp else {
            throw SignalServiceProtosError.invalidProtobuf(description: "[\(Self.self)] missing required field: timestamp")
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

extension SignalServiceProtosSyncMessageRead {
    @objc
    public static func builder(timestamp: UInt64) -> SignalServiceProtosSyncMessageReadBuilder {
        return SignalServiceProtosSyncMessageReadBuilder(timestamp: timestamp)
    }

    // asBuilder() constructs a builder that reflects the proto's contents.
    @objc
    public func asBuilder() -> SignalServiceProtosSyncMessageReadBuilder {
        let builder = SignalServiceProtosSyncMessageReadBuilder(timestamp: timestamp)
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
public class SignalServiceProtosSyncMessageReadBuilder: NSObject {

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
    public func build() throws -> SignalServiceProtosSyncMessageRead {
        return try SignalServiceProtosSyncMessageRead(proto)
    }

    @objc
    public func buildSerializedData() throws -> Data {
        return try SignalServiceProtosSyncMessageRead(proto).serializedData()
    }
}

#if TESTABLE_BUILD

extension SignalServiceProtosSyncMessageRead {
    @objc
    public func serializedDataIgnoringErrors() -> Data? {
        return try! self.serializedData()
    }
}

extension SignalServiceProtosSyncMessageReadBuilder {
    @objc
    public func buildIgnoringErrors() -> SignalServiceProtosSyncMessageRead? {
        return try! self.build()
    }
}

#endif

// MARK: - SignalServiceProtosSyncMessageViewed

@objc
public class SignalServiceProtosSyncMessageViewed: NSObject, Codable, NSSecureCoding {

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
    public required convenience init(serializedData: Data) throws {
        let proto = try SignalServiceProtos_SyncMessage.Viewed(serializedBytes: serializedData)
        try self.init(proto)
    }

    fileprivate convenience init(_ proto: SignalServiceProtos_SyncMessage.Viewed) throws {
        guard proto.hasTimestamp else {
            throw SignalServiceProtosError.invalidProtobuf(description: "[\(Self.self)] missing required field: timestamp")
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

extension SignalServiceProtosSyncMessageViewed {
    @objc
    public static func builder(timestamp: UInt64) -> SignalServiceProtosSyncMessageViewedBuilder {
        return SignalServiceProtosSyncMessageViewedBuilder(timestamp: timestamp)
    }

    // asBuilder() constructs a builder that reflects the proto's contents.
    @objc
    public func asBuilder() -> SignalServiceProtosSyncMessageViewedBuilder {
        let builder = SignalServiceProtosSyncMessageViewedBuilder(timestamp: timestamp)
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
public class SignalServiceProtosSyncMessageViewedBuilder: NSObject {

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
    public func build() throws -> SignalServiceProtosSyncMessageViewed {
        return try SignalServiceProtosSyncMessageViewed(proto)
    }

    @objc
    public func buildSerializedData() throws -> Data {
        return try SignalServiceProtosSyncMessageViewed(proto).serializedData()
    }
}

#if TESTABLE_BUILD

extension SignalServiceProtosSyncMessageViewed {
    @objc
    public func serializedDataIgnoringErrors() -> Data? {
        return try! self.serializedData()
    }
}

extension SignalServiceProtosSyncMessageViewedBuilder {
    @objc
    public func buildIgnoringErrors() -> SignalServiceProtosSyncMessageViewed? {
        return try! self.build()
    }
}

#endif

// MARK: - SignalServiceProtosSyncMessageConfiguration

@objc
public class SignalServiceProtosSyncMessageConfiguration: NSObject, Codable, NSSecureCoding {

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
    public required convenience init(serializedData: Data) throws {
        let proto = try SignalServiceProtos_SyncMessage.Configuration(serializedBytes: serializedData)
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

extension SignalServiceProtosSyncMessageConfiguration {
    @objc
    public static func builder() -> SignalServiceProtosSyncMessageConfigurationBuilder {
        return SignalServiceProtosSyncMessageConfigurationBuilder()
    }

    // asBuilder() constructs a builder that reflects the proto's contents.
    @objc
    public func asBuilder() -> SignalServiceProtosSyncMessageConfigurationBuilder {
        let builder = SignalServiceProtosSyncMessageConfigurationBuilder()
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
public class SignalServiceProtosSyncMessageConfigurationBuilder: NSObject {

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
    public func buildInfallibly() -> SignalServiceProtosSyncMessageConfiguration {
        return SignalServiceProtosSyncMessageConfiguration(proto)
    }

    @objc
    public func buildSerializedData() throws -> Data {
        return try SignalServiceProtosSyncMessageConfiguration(proto).serializedData()
    }
}

#if TESTABLE_BUILD

extension SignalServiceProtosSyncMessageConfiguration {
    @objc
    public func serializedDataIgnoringErrors() -> Data? {
        return try! self.serializedData()
    }
}

extension SignalServiceProtosSyncMessageConfigurationBuilder {
    @objc
    public func buildIgnoringErrors() -> SignalServiceProtosSyncMessageConfiguration? {
        return self.buildInfallibly()
    }
}

#endif

// MARK: - SignalServiceProtosSyncMessageStickerPackOperationType

@objc
public enum SignalServiceProtosSyncMessageStickerPackOperationType: Int32 {
    case install = 0
    case remove = 1
}

private func SignalServiceProtosSyncMessageStickerPackOperationTypeWrap(_ value: SignalServiceProtos_SyncMessage.StickerPackOperation.TypeEnum) -> SignalServiceProtosSyncMessageStickerPackOperationType {
    switch value {
    case .install: return .install
    case .remove: return .remove
    }
}

private func SignalServiceProtosSyncMessageStickerPackOperationTypeUnwrap(_ value: SignalServiceProtosSyncMessageStickerPackOperationType) -> SignalServiceProtos_SyncMessage.StickerPackOperation.TypeEnum {
    switch value {
    case .install: return .install
    case .remove: return .remove
    }
}

// MARK: - SignalServiceProtosSyncMessageStickerPackOperation

@objc
public class SignalServiceProtosSyncMessageStickerPackOperation: NSObject, Codable, NSSecureCoding {

    fileprivate let proto: SignalServiceProtos_SyncMessage.StickerPackOperation

    @objc
    public let packID: Data

    @objc
    public let packKey: Data

    public var type: SignalServiceProtosSyncMessageStickerPackOperationType? {
        guard hasType else {
            return nil
        }
        return SignalServiceProtosSyncMessageStickerPackOperationTypeWrap(proto.type)
    }
    // This "unwrapped" accessor should only be used if the "has value" accessor has already been checked.
    @objc
    public var unwrappedType: SignalServiceProtosSyncMessageStickerPackOperationType {
        if !hasType {
            // TODO: We could make this a crashing assert.
            owsFailDebug("Unsafe unwrap of missing optional: StickerPackOperation.type.")
        }
        return SignalServiceProtosSyncMessageStickerPackOperationTypeWrap(proto.type)
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
    public required convenience init(serializedData: Data) throws {
        let proto = try SignalServiceProtos_SyncMessage.StickerPackOperation(serializedBytes: serializedData)
        try self.init(proto)
    }

    fileprivate convenience init(_ proto: SignalServiceProtos_SyncMessage.StickerPackOperation) throws {
        guard proto.hasPackID else {
            throw SignalServiceProtosError.invalidProtobuf(description: "[\(Self.self)] missing required field: packID")
        }
        let packID = proto.packID

        guard proto.hasPackKey else {
            throw SignalServiceProtosError.invalidProtobuf(description: "[\(Self.self)] missing required field: packKey")
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

extension SignalServiceProtosSyncMessageStickerPackOperation {
    @objc
    public static func builder(packID: Data, packKey: Data) -> SignalServiceProtosSyncMessageStickerPackOperationBuilder {
        return SignalServiceProtosSyncMessageStickerPackOperationBuilder(packID: packID, packKey: packKey)
    }

    // asBuilder() constructs a builder that reflects the proto's contents.
    @objc
    public func asBuilder() -> SignalServiceProtosSyncMessageStickerPackOperationBuilder {
        let builder = SignalServiceProtosSyncMessageStickerPackOperationBuilder(packID: packID, packKey: packKey)
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
public class SignalServiceProtosSyncMessageStickerPackOperationBuilder: NSObject {

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
    public func setType(_ valueParam: SignalServiceProtosSyncMessageStickerPackOperationType) {
        proto.type = SignalServiceProtosSyncMessageStickerPackOperationTypeUnwrap(valueParam)
    }

    public func setUnknownFields(_ unknownFields: SwiftProtobuf.UnknownStorage) {
        proto.unknownFields = unknownFields
    }

    @objc
    public func build() throws -> SignalServiceProtosSyncMessageStickerPackOperation {
        return try SignalServiceProtosSyncMessageStickerPackOperation(proto)
    }

    @objc
    public func buildSerializedData() throws -> Data {
        return try SignalServiceProtosSyncMessageStickerPackOperation(proto).serializedData()
    }
}

#if TESTABLE_BUILD

extension SignalServiceProtosSyncMessageStickerPackOperation {
    @objc
    public func serializedDataIgnoringErrors() -> Data? {
        return try! self.serializedData()
    }
}

extension SignalServiceProtosSyncMessageStickerPackOperationBuilder {
    @objc
    public func buildIgnoringErrors() -> SignalServiceProtosSyncMessageStickerPackOperation? {
        return try! self.build()
    }
}

#endif

// MARK: - SignalServiceProtosSyncMessageViewOnceOpen

@objc
public class SignalServiceProtosSyncMessageViewOnceOpen: NSObject, Codable, NSSecureCoding {

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
    public required convenience init(serializedData: Data) throws {
        let proto = try SignalServiceProtos_SyncMessage.ViewOnceOpen(serializedBytes: serializedData)
        try self.init(proto)
    }

    fileprivate convenience init(_ proto: SignalServiceProtos_SyncMessage.ViewOnceOpen) throws {
        guard proto.hasTimestamp else {
            throw SignalServiceProtosError.invalidProtobuf(description: "[\(Self.self)] missing required field: timestamp")
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

extension SignalServiceProtosSyncMessageViewOnceOpen {
    @objc
    public static func builder(timestamp: UInt64) -> SignalServiceProtosSyncMessageViewOnceOpenBuilder {
        return SignalServiceProtosSyncMessageViewOnceOpenBuilder(timestamp: timestamp)
    }

    // asBuilder() constructs a builder that reflects the proto's contents.
    @objc
    public func asBuilder() -> SignalServiceProtosSyncMessageViewOnceOpenBuilder {
        let builder = SignalServiceProtosSyncMessageViewOnceOpenBuilder(timestamp: timestamp)
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
public class SignalServiceProtosSyncMessageViewOnceOpenBuilder: NSObject {

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
    public func build() throws -> SignalServiceProtosSyncMessageViewOnceOpen {
        return try SignalServiceProtosSyncMessageViewOnceOpen(proto)
    }

    @objc
    public func buildSerializedData() throws -> Data {
        return try SignalServiceProtosSyncMessageViewOnceOpen(proto).serializedData()
    }
}

#if TESTABLE_BUILD

extension SignalServiceProtosSyncMessageViewOnceOpen {
    @objc
    public func serializedDataIgnoringErrors() -> Data? {
        return try! self.serializedData()
    }
}

extension SignalServiceProtosSyncMessageViewOnceOpenBuilder {
    @objc
    public func buildIgnoringErrors() -> SignalServiceProtosSyncMessageViewOnceOpen? {
        return try! self.build()
    }
}

#endif

// MARK: - SignalServiceProtosSyncMessageFetchLatestType

@objc
public enum SignalServiceProtosSyncMessageFetchLatestType: Int32 {
    case unknown = 0
    case localProfile = 1
    case storageManifest = 2
    case subscriptionStatus = 3
}

private func SignalServiceProtosSyncMessageFetchLatestTypeWrap(_ value: SignalServiceProtos_SyncMessage.FetchLatest.TypeEnum) -> SignalServiceProtosSyncMessageFetchLatestType {
    switch value {
    case .unknown: return .unknown
    case .localProfile: return .localProfile
    case .storageManifest: return .storageManifest
    case .subscriptionStatus: return .subscriptionStatus
    }
}

private func SignalServiceProtosSyncMessageFetchLatestTypeUnwrap(_ value: SignalServiceProtosSyncMessageFetchLatestType) -> SignalServiceProtos_SyncMessage.FetchLatest.TypeEnum {
    switch value {
    case .unknown: return .unknown
    case .localProfile: return .localProfile
    case .storageManifest: return .storageManifest
    case .subscriptionStatus: return .subscriptionStatus
    }
}

// MARK: - SignalServiceProtosSyncMessageFetchLatest

@objc
public class SignalServiceProtosSyncMessageFetchLatest: NSObject, Codable, NSSecureCoding {

    fileprivate let proto: SignalServiceProtos_SyncMessage.FetchLatest

    public var type: SignalServiceProtosSyncMessageFetchLatestType? {
        guard hasType else {
            return nil
        }
        return SignalServiceProtosSyncMessageFetchLatestTypeWrap(proto.type)
    }
    // This "unwrapped" accessor should only be used if the "has value" accessor has already been checked.
    @objc
    public var unwrappedType: SignalServiceProtosSyncMessageFetchLatestType {
        if !hasType {
            // TODO: We could make this a crashing assert.
            owsFailDebug("Unsafe unwrap of missing optional: FetchLatest.type.")
        }
        return SignalServiceProtosSyncMessageFetchLatestTypeWrap(proto.type)
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
    public required convenience init(serializedData: Data) throws {
        let proto = try SignalServiceProtos_SyncMessage.FetchLatest(serializedBytes: serializedData)
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

extension SignalServiceProtosSyncMessageFetchLatest {
    @objc
    public static func builder() -> SignalServiceProtosSyncMessageFetchLatestBuilder {
        return SignalServiceProtosSyncMessageFetchLatestBuilder()
    }

    // asBuilder() constructs a builder that reflects the proto's contents.
    @objc
    public func asBuilder() -> SignalServiceProtosSyncMessageFetchLatestBuilder {
        let builder = SignalServiceProtosSyncMessageFetchLatestBuilder()
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
public class SignalServiceProtosSyncMessageFetchLatestBuilder: NSObject {

    private var proto = SignalServiceProtos_SyncMessage.FetchLatest()

    @objc
    fileprivate override init() {}

    @objc
    public func setType(_ valueParam: SignalServiceProtosSyncMessageFetchLatestType) {
        proto.type = SignalServiceProtosSyncMessageFetchLatestTypeUnwrap(valueParam)
    }

    public func setUnknownFields(_ unknownFields: SwiftProtobuf.UnknownStorage) {
        proto.unknownFields = unknownFields
    }

    @objc
    public func buildInfallibly() -> SignalServiceProtosSyncMessageFetchLatest {
        return SignalServiceProtosSyncMessageFetchLatest(proto)
    }

    @objc
    public func buildSerializedData() throws -> Data {
        return try SignalServiceProtosSyncMessageFetchLatest(proto).serializedData()
    }
}

#if TESTABLE_BUILD

extension SignalServiceProtosSyncMessageFetchLatest {
    @objc
    public func serializedDataIgnoringErrors() -> Data? {
        return try! self.serializedData()
    }
}

extension SignalServiceProtosSyncMessageFetchLatestBuilder {
    @objc
    public func buildIgnoringErrors() -> SignalServiceProtosSyncMessageFetchLatest? {
        return self.buildInfallibly()
    }
}

#endif

// MARK: - SignalServiceProtosSyncMessageKeys

@objc
public class SignalServiceProtosSyncMessageKeys: NSObject, Codable, NSSecureCoding {

    fileprivate let proto: SignalServiceProtos_SyncMessage.Keys

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

    @objc
    public var accountEntropyPool: String? {
        guard hasAccountEntropyPool else {
            return nil
        }
        return proto.accountEntropyPool
    }
    @objc
    public var hasAccountEntropyPool: Bool {
        return proto.hasAccountEntropyPool
    }

    @objc
    public var mediaRootBackupKey: Data? {
        guard hasMediaRootBackupKey else {
            return nil
        }
        return proto.mediaRootBackupKey
    }
    @objc
    public var hasMediaRootBackupKey: Bool {
        return proto.hasMediaRootBackupKey
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
    public required convenience init(serializedData: Data) throws {
        let proto = try SignalServiceProtos_SyncMessage.Keys(serializedBytes: serializedData)
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

extension SignalServiceProtosSyncMessageKeys {
    @objc
    public static func builder() -> SignalServiceProtosSyncMessageKeysBuilder {
        return SignalServiceProtosSyncMessageKeysBuilder()
    }

    // asBuilder() constructs a builder that reflects the proto's contents.
    @objc
    public func asBuilder() -> SignalServiceProtosSyncMessageKeysBuilder {
        let builder = SignalServiceProtosSyncMessageKeysBuilder()
        if let _value = master {
            builder.setMaster(_value)
        }
        if let _value = accountEntropyPool {
            builder.setAccountEntropyPool(_value)
        }
        if let _value = mediaRootBackupKey {
            builder.setMediaRootBackupKey(_value)
        }
        if let _value = unknownFields {
            builder.setUnknownFields(_value)
        }
        return builder
    }
}

@objc
public class SignalServiceProtosSyncMessageKeysBuilder: NSObject {

    private var proto = SignalServiceProtos_SyncMessage.Keys()

    @objc
    fileprivate override init() {}

    @objc
    @available(swift, obsoleted: 1.0)
    public func setMaster(_ valueParam: Data?) {
        guard let valueParam = valueParam else { return }
        proto.master = valueParam
    }

    public func setMaster(_ valueParam: Data) {
        proto.master = valueParam
    }

    @objc
    @available(swift, obsoleted: 1.0)
    public func setAccountEntropyPool(_ valueParam: String?) {
        guard let valueParam = valueParam else { return }
        proto.accountEntropyPool = valueParam
    }

    public func setAccountEntropyPool(_ valueParam: String) {
        proto.accountEntropyPool = valueParam
    }

    @objc
    @available(swift, obsoleted: 1.0)
    public func setMediaRootBackupKey(_ valueParam: Data?) {
        guard let valueParam = valueParam else { return }
        proto.mediaRootBackupKey = valueParam
    }

    public func setMediaRootBackupKey(_ valueParam: Data) {
        proto.mediaRootBackupKey = valueParam
    }

    public func setUnknownFields(_ unknownFields: SwiftProtobuf.UnknownStorage) {
        proto.unknownFields = unknownFields
    }

    @objc
    public func buildInfallibly() -> SignalServiceProtosSyncMessageKeys {
        return SignalServiceProtosSyncMessageKeys(proto)
    }

    @objc
    public func buildSerializedData() throws -> Data {
        return try SignalServiceProtosSyncMessageKeys(proto).serializedData()
    }
}

#if TESTABLE_BUILD

extension SignalServiceProtosSyncMessageKeys {
    @objc
    public func serializedDataIgnoringErrors() -> Data? {
        return try! self.serializedData()
    }
}

extension SignalServiceProtosSyncMessageKeysBuilder {
    @objc
    public func buildIgnoringErrors() -> SignalServiceProtosSyncMessageKeys? {
        return self.buildInfallibly()
    }
}

#endif

// MARK: - SignalServiceProtosSyncMessageMessageRequestResponseType

@objc
public enum SignalServiceProtosSyncMessageMessageRequestResponseType: Int32 {
    case unknown = 0
    case accept = 1
    case delete = 2
    case block = 3
    case blockAndDelete = 4
    case spam = 5
    case blockAndSpam = 6
}

private func SignalServiceProtosSyncMessageMessageRequestResponseTypeWrap(_ value: SignalServiceProtos_SyncMessage.MessageRequestResponse.TypeEnum) -> SignalServiceProtosSyncMessageMessageRequestResponseType {
    switch value {
    case .unknown: return .unknown
    case .accept: return .accept
    case .delete: return .delete
    case .block: return .block
    case .blockAndDelete: return .blockAndDelete
    case .spam: return .spam
    case .blockAndSpam: return .blockAndSpam
    }
}

private func SignalServiceProtosSyncMessageMessageRequestResponseTypeUnwrap(_ value: SignalServiceProtosSyncMessageMessageRequestResponseType) -> SignalServiceProtos_SyncMessage.MessageRequestResponse.TypeEnum {
    switch value {
    case .unknown: return .unknown
    case .accept: return .accept
    case .delete: return .delete
    case .block: return .block
    case .blockAndDelete: return .blockAndDelete
    case .spam: return .spam
    case .blockAndSpam: return .blockAndSpam
    }
}

// MARK: - SignalServiceProtosSyncMessageMessageRequestResponse

@objc
public class SignalServiceProtosSyncMessageMessageRequestResponse: NSObject, Codable, NSSecureCoding {

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

    public var type: SignalServiceProtosSyncMessageMessageRequestResponseType? {
        guard hasType else {
            return nil
        }
        return SignalServiceProtosSyncMessageMessageRequestResponseTypeWrap(proto.type)
    }
    // This "unwrapped" accessor should only be used if the "has value" accessor has already been checked.
    @objc
    public var unwrappedType: SignalServiceProtosSyncMessageMessageRequestResponseType {
        if !hasType {
            // TODO: We could make this a crashing assert.
            owsFailDebug("Unsafe unwrap of missing optional: MessageRequestResponse.type.")
        }
        return SignalServiceProtosSyncMessageMessageRequestResponseTypeWrap(proto.type)
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
    public required convenience init(serializedData: Data) throws {
        let proto = try SignalServiceProtos_SyncMessage.MessageRequestResponse(serializedBytes: serializedData)
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

extension SignalServiceProtosSyncMessageMessageRequestResponse {
    @objc
    public static func builder() -> SignalServiceProtosSyncMessageMessageRequestResponseBuilder {
        return SignalServiceProtosSyncMessageMessageRequestResponseBuilder()
    }

    // asBuilder() constructs a builder that reflects the proto's contents.
    @objc
    public func asBuilder() -> SignalServiceProtosSyncMessageMessageRequestResponseBuilder {
        let builder = SignalServiceProtosSyncMessageMessageRequestResponseBuilder()
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
public class SignalServiceProtosSyncMessageMessageRequestResponseBuilder: NSObject {

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
    public func setType(_ valueParam: SignalServiceProtosSyncMessageMessageRequestResponseType) {
        proto.type = SignalServiceProtosSyncMessageMessageRequestResponseTypeUnwrap(valueParam)
    }

    public func setUnknownFields(_ unknownFields: SwiftProtobuf.UnknownStorage) {
        proto.unknownFields = unknownFields
    }

    @objc
    public func buildInfallibly() -> SignalServiceProtosSyncMessageMessageRequestResponse {
        return SignalServiceProtosSyncMessageMessageRequestResponse(proto)
    }

    @objc
    public func buildSerializedData() throws -> Data {
        return try SignalServiceProtosSyncMessageMessageRequestResponse(proto).serializedData()
    }
}

#if TESTABLE_BUILD

extension SignalServiceProtosSyncMessageMessageRequestResponse {
    @objc
    public func serializedDataIgnoringErrors() -> Data? {
        return try! self.serializedData()
    }
}

extension SignalServiceProtosSyncMessageMessageRequestResponseBuilder {
    @objc
    public func buildIgnoringErrors() -> SignalServiceProtosSyncMessageMessageRequestResponse? {
        return self.buildInfallibly()
    }
}

#endif

// MARK: - SignalServiceProtosSyncMessageOutgoingPaymentMobileCoin

@objc
public class SignalServiceProtosSyncMessageOutgoingPaymentMobileCoin: NSObject, Codable, NSSecureCoding {

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
    public required convenience init(serializedData: Data) throws {
        let proto = try SignalServiceProtos_SyncMessage.OutgoingPayment.MobileCoin(serializedBytes: serializedData)
        try self.init(proto)
    }

    fileprivate convenience init(_ proto: SignalServiceProtos_SyncMessage.OutgoingPayment.MobileCoin) throws {
        guard proto.hasAmountPicoMob else {
            throw SignalServiceProtosError.invalidProtobuf(description: "[\(Self.self)] missing required field: amountPicoMob")
        }
        let amountPicoMob = proto.amountPicoMob

        guard proto.hasFeePicoMob else {
            throw SignalServiceProtosError.invalidProtobuf(description: "[\(Self.self)] missing required field: feePicoMob")
        }
        let feePicoMob = proto.feePicoMob

        guard proto.hasLedgerBlockIndex else {
            throw SignalServiceProtosError.invalidProtobuf(description: "[\(Self.self)] missing required field: ledgerBlockIndex")
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

extension SignalServiceProtosSyncMessageOutgoingPaymentMobileCoin {
    @objc
    public static func builder(amountPicoMob: UInt64, feePicoMob: UInt64, ledgerBlockIndex: UInt64) -> SignalServiceProtosSyncMessageOutgoingPaymentMobileCoinBuilder {
        return SignalServiceProtosSyncMessageOutgoingPaymentMobileCoinBuilder(amountPicoMob: amountPicoMob, feePicoMob: feePicoMob, ledgerBlockIndex: ledgerBlockIndex)
    }

    // asBuilder() constructs a builder that reflects the proto's contents.
    @objc
    public func asBuilder() -> SignalServiceProtosSyncMessageOutgoingPaymentMobileCoinBuilder {
        let builder = SignalServiceProtosSyncMessageOutgoingPaymentMobileCoinBuilder(amountPicoMob: amountPicoMob, feePicoMob: feePicoMob, ledgerBlockIndex: ledgerBlockIndex)
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
public class SignalServiceProtosSyncMessageOutgoingPaymentMobileCoinBuilder: NSObject {

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
    public func build() throws -> SignalServiceProtosSyncMessageOutgoingPaymentMobileCoin {
        return try SignalServiceProtosSyncMessageOutgoingPaymentMobileCoin(proto)
    }

    @objc
    public func buildSerializedData() throws -> Data {
        return try SignalServiceProtosSyncMessageOutgoingPaymentMobileCoin(proto).serializedData()
    }
}

#if TESTABLE_BUILD

extension SignalServiceProtosSyncMessageOutgoingPaymentMobileCoin {
    @objc
    public func serializedDataIgnoringErrors() -> Data? {
        return try! self.serializedData()
    }
}

extension SignalServiceProtosSyncMessageOutgoingPaymentMobileCoinBuilder {
    @objc
    public func buildIgnoringErrors() -> SignalServiceProtosSyncMessageOutgoingPaymentMobileCoin? {
        return try! self.build()
    }
}

#endif

// MARK: - SignalServiceProtosSyncMessageOutgoingPayment

@objc
public class SignalServiceProtosSyncMessageOutgoingPayment: NSObject, Codable, NSSecureCoding {

    fileprivate let proto: SignalServiceProtos_SyncMessage.OutgoingPayment

    @objc
    public let mobileCoin: SignalServiceProtosSyncMessageOutgoingPaymentMobileCoin?

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
                 mobileCoin: SignalServiceProtosSyncMessageOutgoingPaymentMobileCoin?) {
        self.proto = proto
        self.mobileCoin = mobileCoin
    }

    @objc
    public func serializedData() throws -> Data {
        return try self.proto.serializedData()
    }

    @objc
    public required convenience init(serializedData: Data) throws {
        let proto = try SignalServiceProtos_SyncMessage.OutgoingPayment(serializedBytes: serializedData)
        try self.init(proto)
    }

    fileprivate convenience init(_ proto: SignalServiceProtos_SyncMessage.OutgoingPayment) throws {
        var mobileCoin: SignalServiceProtosSyncMessageOutgoingPaymentMobileCoin?
        if proto.hasMobileCoin {
            mobileCoin = try SignalServiceProtosSyncMessageOutgoingPaymentMobileCoin(proto.mobileCoin)
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

extension SignalServiceProtosSyncMessageOutgoingPayment {
    @objc
    public static func builder() -> SignalServiceProtosSyncMessageOutgoingPaymentBuilder {
        return SignalServiceProtosSyncMessageOutgoingPaymentBuilder()
    }

    // asBuilder() constructs a builder that reflects the proto's contents.
    @objc
    public func asBuilder() -> SignalServiceProtosSyncMessageOutgoingPaymentBuilder {
        let builder = SignalServiceProtosSyncMessageOutgoingPaymentBuilder()
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
public class SignalServiceProtosSyncMessageOutgoingPaymentBuilder: NSObject {

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
    public func setMobileCoin(_ valueParam: SignalServiceProtosSyncMessageOutgoingPaymentMobileCoin?) {
        guard let valueParam = valueParam else { return }
        proto.mobileCoin = valueParam.proto
    }

    public func setMobileCoin(_ valueParam: SignalServiceProtosSyncMessageOutgoingPaymentMobileCoin) {
        proto.mobileCoin = valueParam.proto
    }

    public func setUnknownFields(_ unknownFields: SwiftProtobuf.UnknownStorage) {
        proto.unknownFields = unknownFields
    }

    @objc
    public func build() throws -> SignalServiceProtosSyncMessageOutgoingPayment {
        return try SignalServiceProtosSyncMessageOutgoingPayment(proto)
    }

    @objc
    public func buildSerializedData() throws -> Data {
        return try SignalServiceProtosSyncMessageOutgoingPayment(proto).serializedData()
    }
}

#if TESTABLE_BUILD

extension SignalServiceProtosSyncMessageOutgoingPayment {
    @objc
    public func serializedDataIgnoringErrors() -> Data? {
        return try! self.serializedData()
    }
}

extension SignalServiceProtosSyncMessageOutgoingPaymentBuilder {
    @objc
    public func buildIgnoringErrors() -> SignalServiceProtosSyncMessageOutgoingPayment? {
        return try! self.build()
    }
}

#endif

// MARK: - SignalServiceProtosSyncMessagePniChangeNumber

@objc
public class SignalServiceProtosSyncMessagePniChangeNumber: NSObject, Codable, NSSecureCoding {

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
        return proto.hasNewE164
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
    public required convenience init(serializedData: Data) throws {
        let proto = try SignalServiceProtos_SyncMessage.PniChangeNumber(serializedBytes: serializedData)
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

extension SignalServiceProtosSyncMessagePniChangeNumber {
    @objc
    public static func builder() -> SignalServiceProtosSyncMessagePniChangeNumberBuilder {
        return SignalServiceProtosSyncMessagePniChangeNumberBuilder()
    }

    // asBuilder() constructs a builder that reflects the proto's contents.
    @objc
    public func asBuilder() -> SignalServiceProtosSyncMessagePniChangeNumberBuilder {
        let builder = SignalServiceProtosSyncMessagePniChangeNumberBuilder()
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
public class SignalServiceProtosSyncMessagePniChangeNumberBuilder: NSObject {

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
        proto.newE164 = valueParam
    }

    public func setNewE164(_ valueParam: String) {
        proto.newE164 = valueParam
    }

    public func setUnknownFields(_ unknownFields: SwiftProtobuf.UnknownStorage) {
        proto.unknownFields = unknownFields
    }

    @objc
    public func buildInfallibly() -> SignalServiceProtosSyncMessagePniChangeNumber {
        return SignalServiceProtosSyncMessagePniChangeNumber(proto)
    }

    @objc
    public func buildSerializedData() throws -> Data {
        return try SignalServiceProtosSyncMessagePniChangeNumber(proto).serializedData()
    }
}

#if TESTABLE_BUILD

extension SignalServiceProtosSyncMessagePniChangeNumber {
    @objc
    public func serializedDataIgnoringErrors() -> Data? {
        return try! self.serializedData()
    }
}

extension SignalServiceProtosSyncMessagePniChangeNumberBuilder {
    @objc
    public func buildIgnoringErrors() -> SignalServiceProtosSyncMessagePniChangeNumber? {
        return self.buildInfallibly()
    }
}

#endif

// MARK: - SignalServiceProtosSyncMessageCallEventType

@objc
public enum SignalServiceProtosSyncMessageCallEventType: Int32 {
    case unknownType = 0
    case audioCall = 1
    case videoCall = 2
    case groupCall = 3
    case adHocCall = 4
}

private func SignalServiceProtosSyncMessageCallEventTypeWrap(_ value: SignalServiceProtos_SyncMessage.CallEvent.TypeEnum) -> SignalServiceProtosSyncMessageCallEventType {
    switch value {
    case .unknownType: return .unknownType
    case .audioCall: return .audioCall
    case .videoCall: return .videoCall
    case .groupCall: return .groupCall
    case .adHocCall: return .adHocCall
    }
}

private func SignalServiceProtosSyncMessageCallEventTypeUnwrap(_ value: SignalServiceProtosSyncMessageCallEventType) -> SignalServiceProtos_SyncMessage.CallEvent.TypeEnum {
    switch value {
    case .unknownType: return .unknownType
    case .audioCall: return .audioCall
    case .videoCall: return .videoCall
    case .groupCall: return .groupCall
    case .adHocCall: return .adHocCall
    }
}

// MARK: - SignalServiceProtosSyncMessageCallEventDirection

@objc
public enum SignalServiceProtosSyncMessageCallEventDirection: Int32 {
    case unknownDirection = 0
    case incoming = 1
    case outgoing = 2
}

private func SignalServiceProtosSyncMessageCallEventDirectionWrap(_ value: SignalServiceProtos_SyncMessage.CallEvent.Direction) -> SignalServiceProtosSyncMessageCallEventDirection {
    switch value {
    case .unknownDirection: return .unknownDirection
    case .incoming: return .incoming
    case .outgoing: return .outgoing
    }
}

private func SignalServiceProtosSyncMessageCallEventDirectionUnwrap(_ value: SignalServiceProtosSyncMessageCallEventDirection) -> SignalServiceProtos_SyncMessage.CallEvent.Direction {
    switch value {
    case .unknownDirection: return .unknownDirection
    case .incoming: return .incoming
    case .outgoing: return .outgoing
    }
}

// MARK: - SignalServiceProtosSyncMessageCallEventEvent

@objc
public enum SignalServiceProtosSyncMessageCallEventEvent: Int32 {
    case unknownAction = 0
    case accepted = 1
    case notAccepted = 2
    case deleted = 3
    case observed = 4
}

private func SignalServiceProtosSyncMessageCallEventEventWrap(_ value: SignalServiceProtos_SyncMessage.CallEvent.Event) -> SignalServiceProtosSyncMessageCallEventEvent {
    switch value {
    case .unknownAction: return .unknownAction
    case .accepted: return .accepted
    case .notAccepted: return .notAccepted
    case .deleted: return .deleted
    case .observed: return .observed
    }
}

private func SignalServiceProtosSyncMessageCallEventEventUnwrap(_ value: SignalServiceProtosSyncMessageCallEventEvent) -> SignalServiceProtos_SyncMessage.CallEvent.Event {
    switch value {
    case .unknownAction: return .unknownAction
    case .accepted: return .accepted
    case .notAccepted: return .notAccepted
    case .deleted: return .deleted
    case .observed: return .observed
    }
}

// MARK: - SignalServiceProtosSyncMessageCallEvent

@objc
public class SignalServiceProtosSyncMessageCallEvent: NSObject, Codable, NSSecureCoding {

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

    public var type: SignalServiceProtosSyncMessageCallEventType? {
        guard hasType else {
            return nil
        }
        return SignalServiceProtosSyncMessageCallEventTypeWrap(proto.type)
    }
    // This "unwrapped" accessor should only be used if the "has value" accessor has already been checked.
    @objc
    public var unwrappedType: SignalServiceProtosSyncMessageCallEventType {
        if !hasType {
            // TODO: We could make this a crashing assert.
            owsFailDebug("Unsafe unwrap of missing optional: CallEvent.type.")
        }
        return SignalServiceProtosSyncMessageCallEventTypeWrap(proto.type)
    }
    @objc
    public var hasType: Bool {
        return proto.hasType
    }

    public var direction: SignalServiceProtosSyncMessageCallEventDirection? {
        guard hasDirection else {
            return nil
        }
        return SignalServiceProtosSyncMessageCallEventDirectionWrap(proto.direction)
    }
    // This "unwrapped" accessor should only be used if the "has value" accessor has already been checked.
    @objc
    public var unwrappedDirection: SignalServiceProtosSyncMessageCallEventDirection {
        if !hasDirection {
            // TODO: We could make this a crashing assert.
            owsFailDebug("Unsafe unwrap of missing optional: CallEvent.direction.")
        }
        return SignalServiceProtosSyncMessageCallEventDirectionWrap(proto.direction)
    }
    @objc
    public var hasDirection: Bool {
        return proto.hasDirection
    }

    public var event: SignalServiceProtosSyncMessageCallEventEvent? {
        guard hasEvent else {
            return nil
        }
        return SignalServiceProtosSyncMessageCallEventEventWrap(proto.event)
    }
    // This "unwrapped" accessor should only be used if the "has value" accessor has already been checked.
    @objc
    public var unwrappedEvent: SignalServiceProtosSyncMessageCallEventEvent {
        if !hasEvent {
            // TODO: We could make this a crashing assert.
            owsFailDebug("Unsafe unwrap of missing optional: CallEvent.event.")
        }
        return SignalServiceProtosSyncMessageCallEventEventWrap(proto.event)
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
    public required convenience init(serializedData: Data) throws {
        let proto = try SignalServiceProtos_SyncMessage.CallEvent(serializedBytes: serializedData)
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

extension SignalServiceProtosSyncMessageCallEvent {
    @objc
    public static func builder() -> SignalServiceProtosSyncMessageCallEventBuilder {
        return SignalServiceProtosSyncMessageCallEventBuilder()
    }

    // asBuilder() constructs a builder that reflects the proto's contents.
    @objc
    public func asBuilder() -> SignalServiceProtosSyncMessageCallEventBuilder {
        let builder = SignalServiceProtosSyncMessageCallEventBuilder()
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
public class SignalServiceProtosSyncMessageCallEventBuilder: NSObject {

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
    public func setType(_ valueParam: SignalServiceProtosSyncMessageCallEventType) {
        proto.type = SignalServiceProtosSyncMessageCallEventTypeUnwrap(valueParam)
    }

    @objc
    public func setDirection(_ valueParam: SignalServiceProtosSyncMessageCallEventDirection) {
        proto.direction = SignalServiceProtosSyncMessageCallEventDirectionUnwrap(valueParam)
    }

    @objc
    public func setEvent(_ valueParam: SignalServiceProtosSyncMessageCallEventEvent) {
        proto.event = SignalServiceProtosSyncMessageCallEventEventUnwrap(valueParam)
    }

    public func setUnknownFields(_ unknownFields: SwiftProtobuf.UnknownStorage) {
        proto.unknownFields = unknownFields
    }

    @objc
    public func buildInfallibly() -> SignalServiceProtosSyncMessageCallEvent {
        return SignalServiceProtosSyncMessageCallEvent(proto)
    }

    @objc
    public func buildSerializedData() throws -> Data {
        return try SignalServiceProtosSyncMessageCallEvent(proto).serializedData()
    }
}

#if TESTABLE_BUILD

extension SignalServiceProtosSyncMessageCallEvent {
    @objc
    public func serializedDataIgnoringErrors() -> Data? {
        return try! self.serializedData()
    }
}

extension SignalServiceProtosSyncMessageCallEventBuilder {
    @objc
    public func buildIgnoringErrors() -> SignalServiceProtosSyncMessageCallEvent? {
        return self.buildInfallibly()
    }
}

#endif

// MARK: - SignalServiceProtosSyncMessageCallLinkUpdateType

@objc
public enum SignalServiceProtosSyncMessageCallLinkUpdateType: Int32 {
    case update = 0
}

private func SignalServiceProtosSyncMessageCallLinkUpdateTypeWrap(_ value: SignalServiceProtos_SyncMessage.CallLinkUpdate.TypeEnum) -> SignalServiceProtosSyncMessageCallLinkUpdateType {
    switch value {
    case .update: return .update
    }
}

private func SignalServiceProtosSyncMessageCallLinkUpdateTypeUnwrap(_ value: SignalServiceProtosSyncMessageCallLinkUpdateType) -> SignalServiceProtos_SyncMessage.CallLinkUpdate.TypeEnum {
    switch value {
    case .update: return .update
    }
}

// MARK: - SignalServiceProtosSyncMessageCallLinkUpdate

@objc
public class SignalServiceProtosSyncMessageCallLinkUpdate: NSObject, Codable, NSSecureCoding {

    fileprivate let proto: SignalServiceProtos_SyncMessage.CallLinkUpdate

    @objc
    public var rootKey: Data? {
        guard hasRootKey else {
            return nil
        }
        return proto.rootKey
    }
    @objc
    public var hasRootKey: Bool {
        return proto.hasRootKey
    }

    @objc
    public var adminPasskey: Data? {
        guard hasAdminPasskey else {
            return nil
        }
        return proto.adminPasskey
    }
    @objc
    public var hasAdminPasskey: Bool {
        return proto.hasAdminPasskey
    }

    public var type: SignalServiceProtosSyncMessageCallLinkUpdateType? {
        guard hasType else {
            return nil
        }
        return SignalServiceProtosSyncMessageCallLinkUpdateTypeWrap(proto.type)
    }
    // This "unwrapped" accessor should only be used if the "has value" accessor has already been checked.
    @objc
    public var unwrappedType: SignalServiceProtosSyncMessageCallLinkUpdateType {
        if !hasType {
            // TODO: We could make this a crashing assert.
            owsFailDebug("Unsafe unwrap of missing optional: CallLinkUpdate.type.")
        }
        return SignalServiceProtosSyncMessageCallLinkUpdateTypeWrap(proto.type)
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

    private init(proto: SignalServiceProtos_SyncMessage.CallLinkUpdate) {
        self.proto = proto
    }

    @objc
    public func serializedData() throws -> Data {
        return try self.proto.serializedData()
    }

    @objc
    public required convenience init(serializedData: Data) throws {
        let proto = try SignalServiceProtos_SyncMessage.CallLinkUpdate(serializedBytes: serializedData)
        self.init(proto)
    }

    fileprivate convenience init(_ proto: SignalServiceProtos_SyncMessage.CallLinkUpdate) {
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

extension SignalServiceProtosSyncMessageCallLinkUpdate {
    @objc
    public static func builder() -> SignalServiceProtosSyncMessageCallLinkUpdateBuilder {
        return SignalServiceProtosSyncMessageCallLinkUpdateBuilder()
    }

    // asBuilder() constructs a builder that reflects the proto's contents.
    @objc
    public func asBuilder() -> SignalServiceProtosSyncMessageCallLinkUpdateBuilder {
        let builder = SignalServiceProtosSyncMessageCallLinkUpdateBuilder()
        if let _value = rootKey {
            builder.setRootKey(_value)
        }
        if let _value = adminPasskey {
            builder.setAdminPasskey(_value)
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
public class SignalServiceProtosSyncMessageCallLinkUpdateBuilder: NSObject {

    private var proto = SignalServiceProtos_SyncMessage.CallLinkUpdate()

    @objc
    fileprivate override init() {}

    @objc
    @available(swift, obsoleted: 1.0)
    public func setRootKey(_ valueParam: Data?) {
        guard let valueParam = valueParam else { return }
        proto.rootKey = valueParam
    }

    public func setRootKey(_ valueParam: Data) {
        proto.rootKey = valueParam
    }

    @objc
    @available(swift, obsoleted: 1.0)
    public func setAdminPasskey(_ valueParam: Data?) {
        guard let valueParam = valueParam else { return }
        proto.adminPasskey = valueParam
    }

    public func setAdminPasskey(_ valueParam: Data) {
        proto.adminPasskey = valueParam
    }

    @objc
    public func setType(_ valueParam: SignalServiceProtosSyncMessageCallLinkUpdateType) {
        proto.type = SignalServiceProtosSyncMessageCallLinkUpdateTypeUnwrap(valueParam)
    }

    public func setUnknownFields(_ unknownFields: SwiftProtobuf.UnknownStorage) {
        proto.unknownFields = unknownFields
    }

    @objc
    public func buildInfallibly() -> SignalServiceProtosSyncMessageCallLinkUpdate {
        return SignalServiceProtosSyncMessageCallLinkUpdate(proto)
    }

    @objc
    public func buildSerializedData() throws -> Data {
        return try SignalServiceProtosSyncMessageCallLinkUpdate(proto).serializedData()
    }
}

#if TESTABLE_BUILD

extension SignalServiceProtosSyncMessageCallLinkUpdate {
    @objc
    public func serializedDataIgnoringErrors() -> Data? {
        return try! self.serializedData()
    }
}

extension SignalServiceProtosSyncMessageCallLinkUpdateBuilder {
    @objc
    public func buildIgnoringErrors() -> SignalServiceProtosSyncMessageCallLinkUpdate? {
        return self.buildInfallibly()
    }
}

#endif

// MARK: - SignalServiceProtosSyncMessageCallLogEventType

@objc
public enum SignalServiceProtosSyncMessageCallLogEventType: Int32 {
    case cleared = 0
    case markedAsRead = 1
    case markedAsReadInConversation = 2
}

private func SignalServiceProtosSyncMessageCallLogEventTypeWrap(_ value: SignalServiceProtos_SyncMessage.CallLogEvent.TypeEnum) -> SignalServiceProtosSyncMessageCallLogEventType {
    switch value {
    case .cleared: return .cleared
    case .markedAsRead: return .markedAsRead
    case .markedAsReadInConversation: return .markedAsReadInConversation
    }
}

private func SignalServiceProtosSyncMessageCallLogEventTypeUnwrap(_ value: SignalServiceProtosSyncMessageCallLogEventType) -> SignalServiceProtos_SyncMessage.CallLogEvent.TypeEnum {
    switch value {
    case .cleared: return .cleared
    case .markedAsRead: return .markedAsRead
    case .markedAsReadInConversation: return .markedAsReadInConversation
    }
}

// MARK: - SignalServiceProtosSyncMessageCallLogEvent

@objc
public class SignalServiceProtosSyncMessageCallLogEvent: NSObject, Codable, NSSecureCoding {

    fileprivate let proto: SignalServiceProtos_SyncMessage.CallLogEvent

    public var type: SignalServiceProtosSyncMessageCallLogEventType? {
        guard hasType else {
            return nil
        }
        return SignalServiceProtosSyncMessageCallLogEventTypeWrap(proto.type)
    }
    // This "unwrapped" accessor should only be used if the "has value" accessor has already been checked.
    @objc
    public var unwrappedType: SignalServiceProtosSyncMessageCallLogEventType {
        if !hasType {
            // TODO: We could make this a crashing assert.
            owsFailDebug("Unsafe unwrap of missing optional: CallLogEvent.type.")
        }
        return SignalServiceProtosSyncMessageCallLogEventTypeWrap(proto.type)
    }
    @objc
    public var hasType: Bool {
        return proto.hasType
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

    public var hasUnknownFields: Bool {
        return !proto.unknownFields.data.isEmpty
    }
    public var unknownFields: SwiftProtobuf.UnknownStorage? {
        guard hasUnknownFields else { return nil }
        return proto.unknownFields
    }

    private init(proto: SignalServiceProtos_SyncMessage.CallLogEvent) {
        self.proto = proto
    }

    @objc
    public func serializedData() throws -> Data {
        return try self.proto.serializedData()
    }

    @objc
    public required convenience init(serializedData: Data) throws {
        let proto = try SignalServiceProtos_SyncMessage.CallLogEvent(serializedBytes: serializedData)
        self.init(proto)
    }

    fileprivate convenience init(_ proto: SignalServiceProtos_SyncMessage.CallLogEvent) {
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

extension SignalServiceProtosSyncMessageCallLogEvent {
    @objc
    public static func builder() -> SignalServiceProtosSyncMessageCallLogEventBuilder {
        return SignalServiceProtosSyncMessageCallLogEventBuilder()
    }

    // asBuilder() constructs a builder that reflects the proto's contents.
    @objc
    public func asBuilder() -> SignalServiceProtosSyncMessageCallLogEventBuilder {
        let builder = SignalServiceProtosSyncMessageCallLogEventBuilder()
        if let _value = type {
            builder.setType(_value)
        }
        if hasTimestamp {
            builder.setTimestamp(timestamp)
        }
        if let _value = conversationID {
            builder.setConversationID(_value)
        }
        if hasCallID {
            builder.setCallID(callID)
        }
        if let _value = unknownFields {
            builder.setUnknownFields(_value)
        }
        return builder
    }
}

@objc
public class SignalServiceProtosSyncMessageCallLogEventBuilder: NSObject {

    private var proto = SignalServiceProtos_SyncMessage.CallLogEvent()

    @objc
    fileprivate override init() {}

    @objc
    public func setType(_ valueParam: SignalServiceProtosSyncMessageCallLogEventType) {
        proto.type = SignalServiceProtosSyncMessageCallLogEventTypeUnwrap(valueParam)
    }

    @objc
    public func setTimestamp(_ valueParam: UInt64) {
        proto.timestamp = valueParam
    }

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

    public func setUnknownFields(_ unknownFields: SwiftProtobuf.UnknownStorage) {
        proto.unknownFields = unknownFields
    }

    @objc
    public func buildInfallibly() -> SignalServiceProtosSyncMessageCallLogEvent {
        return SignalServiceProtosSyncMessageCallLogEvent(proto)
    }

    @objc
    public func buildSerializedData() throws -> Data {
        return try SignalServiceProtosSyncMessageCallLogEvent(proto).serializedData()
    }
}

#if TESTABLE_BUILD

extension SignalServiceProtosSyncMessageCallLogEvent {
    @objc
    public func serializedDataIgnoringErrors() -> Data? {
        return try! self.serializedData()
    }
}

extension SignalServiceProtosSyncMessageCallLogEventBuilder {
    @objc
    public func buildIgnoringErrors() -> SignalServiceProtosSyncMessageCallLogEvent? {
        return self.buildInfallibly()
    }
}

#endif

// MARK: - SignalServiceProtosSyncMessageDeleteForMeConversationIdentifier

@objc
public class SignalServiceProtosSyncMessageDeleteForMeConversationIdentifier: NSObject, Codable, NSSecureCoding {

    fileprivate let proto: SignalServiceProtos_SyncMessage.DeleteForMe.ConversationIdentifier

    @objc
    public var threadServiceID: String? {
        guard hasThreadServiceID else {
            return nil
        }
        return proto.threadServiceID
    }
    @objc
    public var hasThreadServiceID: Bool {
        return proto.hasThreadServiceID
    }

    @objc
    public var threadGroupID: Data? {
        guard hasThreadGroupID else {
            return nil
        }
        return proto.threadGroupID
    }
    @objc
    public var hasThreadGroupID: Bool {
        return proto.hasThreadGroupID
    }

    @objc
    public var threadE164: String? {
        guard hasThreadE164 else {
            return nil
        }
        return proto.threadE164
    }
    @objc
    public var hasThreadE164: Bool {
        return proto.hasThreadE164
    }

    public var hasUnknownFields: Bool {
        return !proto.unknownFields.data.isEmpty
    }
    public var unknownFields: SwiftProtobuf.UnknownStorage? {
        guard hasUnknownFields else { return nil }
        return proto.unknownFields
    }

    private init(proto: SignalServiceProtos_SyncMessage.DeleteForMe.ConversationIdentifier) {
        self.proto = proto
    }

    @objc
    public func serializedData() throws -> Data {
        return try self.proto.serializedData()
    }

    @objc
    public required convenience init(serializedData: Data) throws {
        let proto = try SignalServiceProtos_SyncMessage.DeleteForMe.ConversationIdentifier(serializedBytes: serializedData)
        self.init(proto)
    }

    fileprivate convenience init(_ proto: SignalServiceProtos_SyncMessage.DeleteForMe.ConversationIdentifier) {
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

extension SignalServiceProtosSyncMessageDeleteForMeConversationIdentifier {
    @objc
    public static func builder() -> SignalServiceProtosSyncMessageDeleteForMeConversationIdentifierBuilder {
        return SignalServiceProtosSyncMessageDeleteForMeConversationIdentifierBuilder()
    }

    // asBuilder() constructs a builder that reflects the proto's contents.
    @objc
    public func asBuilder() -> SignalServiceProtosSyncMessageDeleteForMeConversationIdentifierBuilder {
        let builder = SignalServiceProtosSyncMessageDeleteForMeConversationIdentifierBuilder()
        if let _value = threadServiceID {
            builder.setThreadServiceID(_value)
        }
        if let _value = threadGroupID {
            builder.setThreadGroupID(_value)
        }
        if let _value = threadE164 {
            builder.setThreadE164(_value)
        }
        if let _value = unknownFields {
            builder.setUnknownFields(_value)
        }
        return builder
    }
}

@objc
public class SignalServiceProtosSyncMessageDeleteForMeConversationIdentifierBuilder: NSObject {

    private var proto = SignalServiceProtos_SyncMessage.DeleteForMe.ConversationIdentifier()

    @objc
    fileprivate override init() {}

    @objc
    @available(swift, obsoleted: 1.0)
    public func setThreadServiceID(_ valueParam: String?) {
        guard let valueParam = valueParam else { return }
        proto.threadServiceID = valueParam
    }

    public func setThreadServiceID(_ valueParam: String) {
        proto.threadServiceID = valueParam
    }

    @objc
    @available(swift, obsoleted: 1.0)
    public func setThreadGroupID(_ valueParam: Data?) {
        guard let valueParam = valueParam else { return }
        proto.threadGroupID = valueParam
    }

    public func setThreadGroupID(_ valueParam: Data) {
        proto.threadGroupID = valueParam
    }

    @objc
    @available(swift, obsoleted: 1.0)
    public func setThreadE164(_ valueParam: String?) {
        guard let valueParam = valueParam else { return }
        proto.threadE164 = valueParam
    }

    public func setThreadE164(_ valueParam: String) {
        proto.threadE164 = valueParam
    }

    public func setUnknownFields(_ unknownFields: SwiftProtobuf.UnknownStorage) {
        proto.unknownFields = unknownFields
    }

    @objc
    public func buildInfallibly() -> SignalServiceProtosSyncMessageDeleteForMeConversationIdentifier {
        return SignalServiceProtosSyncMessageDeleteForMeConversationIdentifier(proto)
    }

    @objc
    public func buildSerializedData() throws -> Data {
        return try SignalServiceProtosSyncMessageDeleteForMeConversationIdentifier(proto).serializedData()
    }
}

#if TESTABLE_BUILD

extension SignalServiceProtosSyncMessageDeleteForMeConversationIdentifier {
    @objc
    public func serializedDataIgnoringErrors() -> Data? {
        return try! self.serializedData()
    }
}

extension SignalServiceProtosSyncMessageDeleteForMeConversationIdentifierBuilder {
    @objc
    public func buildIgnoringErrors() -> SignalServiceProtosSyncMessageDeleteForMeConversationIdentifier? {
        return self.buildInfallibly()
    }
}

#endif

// MARK: - SignalServiceProtosSyncMessageDeleteForMeAddressableMessage

@objc
public class SignalServiceProtosSyncMessageDeleteForMeAddressableMessage: NSObject, Codable, NSSecureCoding {

    fileprivate let proto: SignalServiceProtos_SyncMessage.DeleteForMe.AddressableMessage

    @objc
    public var authorServiceID: String? {
        guard hasAuthorServiceID else {
            return nil
        }
        return proto.authorServiceID
    }
    @objc
    public var hasAuthorServiceID: Bool {
        return proto.hasAuthorServiceID
    }

    @objc
    public var authorE164: String? {
        guard hasAuthorE164 else {
            return nil
        }
        return proto.authorE164
    }
    @objc
    public var hasAuthorE164: Bool {
        return proto.hasAuthorE164
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

    private init(proto: SignalServiceProtos_SyncMessage.DeleteForMe.AddressableMessage) {
        self.proto = proto
    }

    @objc
    public func serializedData() throws -> Data {
        return try self.proto.serializedData()
    }

    @objc
    public required convenience init(serializedData: Data) throws {
        let proto = try SignalServiceProtos_SyncMessage.DeleteForMe.AddressableMessage(serializedBytes: serializedData)
        self.init(proto)
    }

    fileprivate convenience init(_ proto: SignalServiceProtos_SyncMessage.DeleteForMe.AddressableMessage) {
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

extension SignalServiceProtosSyncMessageDeleteForMeAddressableMessage {
    @objc
    public static func builder() -> SignalServiceProtosSyncMessageDeleteForMeAddressableMessageBuilder {
        return SignalServiceProtosSyncMessageDeleteForMeAddressableMessageBuilder()
    }

    // asBuilder() constructs a builder that reflects the proto's contents.
    @objc
    public func asBuilder() -> SignalServiceProtosSyncMessageDeleteForMeAddressableMessageBuilder {
        let builder = SignalServiceProtosSyncMessageDeleteForMeAddressableMessageBuilder()
        if let _value = authorServiceID {
            builder.setAuthorServiceID(_value)
        }
        if let _value = authorE164 {
            builder.setAuthorE164(_value)
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
public class SignalServiceProtosSyncMessageDeleteForMeAddressableMessageBuilder: NSObject {

    private var proto = SignalServiceProtos_SyncMessage.DeleteForMe.AddressableMessage()

    @objc
    fileprivate override init() {}

    @objc
    @available(swift, obsoleted: 1.0)
    public func setAuthorServiceID(_ valueParam: String?) {
        guard let valueParam = valueParam else { return }
        proto.authorServiceID = valueParam
    }

    public func setAuthorServiceID(_ valueParam: String) {
        proto.authorServiceID = valueParam
    }

    @objc
    @available(swift, obsoleted: 1.0)
    public func setAuthorE164(_ valueParam: String?) {
        guard let valueParam = valueParam else { return }
        proto.authorE164 = valueParam
    }

    public func setAuthorE164(_ valueParam: String) {
        proto.authorE164 = valueParam
    }

    @objc
    public func setSentTimestamp(_ valueParam: UInt64) {
        proto.sentTimestamp = valueParam
    }

    public func setUnknownFields(_ unknownFields: SwiftProtobuf.UnknownStorage) {
        proto.unknownFields = unknownFields
    }

    @objc
    public func buildInfallibly() -> SignalServiceProtosSyncMessageDeleteForMeAddressableMessage {
        return SignalServiceProtosSyncMessageDeleteForMeAddressableMessage(proto)
    }

    @objc
    public func buildSerializedData() throws -> Data {
        return try SignalServiceProtosSyncMessageDeleteForMeAddressableMessage(proto).serializedData()
    }
}

#if TESTABLE_BUILD

extension SignalServiceProtosSyncMessageDeleteForMeAddressableMessage {
    @objc
    public func serializedDataIgnoringErrors() -> Data? {
        return try! self.serializedData()
    }
}

extension SignalServiceProtosSyncMessageDeleteForMeAddressableMessageBuilder {
    @objc
    public func buildIgnoringErrors() -> SignalServiceProtosSyncMessageDeleteForMeAddressableMessage? {
        return self.buildInfallibly()
    }
}

#endif

// MARK: - SignalServiceProtosSyncMessageDeleteForMeMessageDeletes

@objc
public class SignalServiceProtosSyncMessageDeleteForMeMessageDeletes: NSObject, Codable, NSSecureCoding {

    fileprivate let proto: SignalServiceProtos_SyncMessage.DeleteForMe.MessageDeletes

    @objc
    public let conversation: SignalServiceProtosSyncMessageDeleteForMeConversationIdentifier?

    @objc
    public let messages: [SignalServiceProtosSyncMessageDeleteForMeAddressableMessage]

    public var hasUnknownFields: Bool {
        return !proto.unknownFields.data.isEmpty
    }
    public var unknownFields: SwiftProtobuf.UnknownStorage? {
        guard hasUnknownFields else { return nil }
        return proto.unknownFields
    }

    private init(proto: SignalServiceProtos_SyncMessage.DeleteForMe.MessageDeletes,
                 conversation: SignalServiceProtosSyncMessageDeleteForMeConversationIdentifier?,
                 messages: [SignalServiceProtosSyncMessageDeleteForMeAddressableMessage]) {
        self.proto = proto
        self.conversation = conversation
        self.messages = messages
    }

    @objc
    public func serializedData() throws -> Data {
        return try self.proto.serializedData()
    }

    @objc
    public required convenience init(serializedData: Data) throws {
        let proto = try SignalServiceProtos_SyncMessage.DeleteForMe.MessageDeletes(serializedBytes: serializedData)
        self.init(proto)
    }

    fileprivate convenience init(_ proto: SignalServiceProtos_SyncMessage.DeleteForMe.MessageDeletes) {
        var conversation: SignalServiceProtosSyncMessageDeleteForMeConversationIdentifier?
        if proto.hasConversation {
            conversation = SignalServiceProtosSyncMessageDeleteForMeConversationIdentifier(proto.conversation)
        }

        var messages: [SignalServiceProtosSyncMessageDeleteForMeAddressableMessage] = []
        messages = proto.messages.map { SignalServiceProtosSyncMessageDeleteForMeAddressableMessage($0) }

        self.init(proto: proto,
                  conversation: conversation,
                  messages: messages)
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

extension SignalServiceProtosSyncMessageDeleteForMeMessageDeletes {
    @objc
    public static func builder() -> SignalServiceProtosSyncMessageDeleteForMeMessageDeletesBuilder {
        return SignalServiceProtosSyncMessageDeleteForMeMessageDeletesBuilder()
    }

    // asBuilder() constructs a builder that reflects the proto's contents.
    @objc
    public func asBuilder() -> SignalServiceProtosSyncMessageDeleteForMeMessageDeletesBuilder {
        let builder = SignalServiceProtosSyncMessageDeleteForMeMessageDeletesBuilder()
        if let _value = conversation {
            builder.setConversation(_value)
        }
        builder.setMessages(messages)
        if let _value = unknownFields {
            builder.setUnknownFields(_value)
        }
        return builder
    }
}

@objc
public class SignalServiceProtosSyncMessageDeleteForMeMessageDeletesBuilder: NSObject {

    private var proto = SignalServiceProtos_SyncMessage.DeleteForMe.MessageDeletes()

    @objc
    fileprivate override init() {}

    @objc
    @available(swift, obsoleted: 1.0)
    public func setConversation(_ valueParam: SignalServiceProtosSyncMessageDeleteForMeConversationIdentifier?) {
        guard let valueParam = valueParam else { return }
        proto.conversation = valueParam.proto
    }

    public func setConversation(_ valueParam: SignalServiceProtosSyncMessageDeleteForMeConversationIdentifier) {
        proto.conversation = valueParam.proto
    }

    @objc
    public func addMessages(_ valueParam: SignalServiceProtosSyncMessageDeleteForMeAddressableMessage) {
        proto.messages.append(valueParam.proto)
    }

    @objc
    public func setMessages(_ wrappedItems: [SignalServiceProtosSyncMessageDeleteForMeAddressableMessage]) {
        proto.messages = wrappedItems.map { $0.proto }
    }

    public func setUnknownFields(_ unknownFields: SwiftProtobuf.UnknownStorage) {
        proto.unknownFields = unknownFields
    }

    @objc
    public func buildInfallibly() -> SignalServiceProtosSyncMessageDeleteForMeMessageDeletes {
        return SignalServiceProtosSyncMessageDeleteForMeMessageDeletes(proto)
    }

    @objc
    public func buildSerializedData() throws -> Data {
        return try SignalServiceProtosSyncMessageDeleteForMeMessageDeletes(proto).serializedData()
    }
}

#if TESTABLE_BUILD

extension SignalServiceProtosSyncMessageDeleteForMeMessageDeletes {
    @objc
    public func serializedDataIgnoringErrors() -> Data? {
        return try! self.serializedData()
    }
}

extension SignalServiceProtosSyncMessageDeleteForMeMessageDeletesBuilder {
    @objc
    public func buildIgnoringErrors() -> SignalServiceProtosSyncMessageDeleteForMeMessageDeletes? {
        return self.buildInfallibly()
    }
}

#endif

// MARK: - SignalServiceProtosSyncMessageDeleteForMeAttachmentDelete

@objc
public class SignalServiceProtosSyncMessageDeleteForMeAttachmentDelete: NSObject, Codable, NSSecureCoding {

    fileprivate let proto: SignalServiceProtos_SyncMessage.DeleteForMe.AttachmentDelete

    @objc
    public let conversation: SignalServiceProtosSyncMessageDeleteForMeConversationIdentifier?

    @objc
    public let targetMessage: SignalServiceProtosSyncMessageDeleteForMeAddressableMessage?

    @objc
    public var clientUuid: Data? {
        guard hasClientUuid else {
            return nil
        }
        return proto.clientUuid
    }
    @objc
    public var hasClientUuid: Bool {
        return proto.hasClientUuid
    }

    @objc
    public var fallbackDigest: Data? {
        guard hasFallbackDigest else {
            return nil
        }
        return proto.fallbackDigest
    }
    @objc
    public var hasFallbackDigest: Bool {
        return proto.hasFallbackDigest
    }

    @objc
    public var fallbackPlaintextHash: Data? {
        guard hasFallbackPlaintextHash else {
            return nil
        }
        return proto.fallbackPlaintextHash
    }
    @objc
    public var hasFallbackPlaintextHash: Bool {
        return proto.hasFallbackPlaintextHash
    }

    public var hasUnknownFields: Bool {
        return !proto.unknownFields.data.isEmpty
    }
    public var unknownFields: SwiftProtobuf.UnknownStorage? {
        guard hasUnknownFields else { return nil }
        return proto.unknownFields
    }

    private init(proto: SignalServiceProtos_SyncMessage.DeleteForMe.AttachmentDelete,
                 conversation: SignalServiceProtosSyncMessageDeleteForMeConversationIdentifier?,
                 targetMessage: SignalServiceProtosSyncMessageDeleteForMeAddressableMessage?) {
        self.proto = proto
        self.conversation = conversation
        self.targetMessage = targetMessage
    }

    @objc
    public func serializedData() throws -> Data {
        return try self.proto.serializedData()
    }

    @objc
    public required convenience init(serializedData: Data) throws {
        let proto = try SignalServiceProtos_SyncMessage.DeleteForMe.AttachmentDelete(serializedBytes: serializedData)
        self.init(proto)
    }

    fileprivate convenience init(_ proto: SignalServiceProtos_SyncMessage.DeleteForMe.AttachmentDelete) {
        var conversation: SignalServiceProtosSyncMessageDeleteForMeConversationIdentifier?
        if proto.hasConversation {
            conversation = SignalServiceProtosSyncMessageDeleteForMeConversationIdentifier(proto.conversation)
        }

        var targetMessage: SignalServiceProtosSyncMessageDeleteForMeAddressableMessage?
        if proto.hasTargetMessage {
            targetMessage = SignalServiceProtosSyncMessageDeleteForMeAddressableMessage(proto.targetMessage)
        }

        self.init(proto: proto,
                  conversation: conversation,
                  targetMessage: targetMessage)
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

extension SignalServiceProtosSyncMessageDeleteForMeAttachmentDelete {
    @objc
    public static func builder() -> SignalServiceProtosSyncMessageDeleteForMeAttachmentDeleteBuilder {
        return SignalServiceProtosSyncMessageDeleteForMeAttachmentDeleteBuilder()
    }

    // asBuilder() constructs a builder that reflects the proto's contents.
    @objc
    public func asBuilder() -> SignalServiceProtosSyncMessageDeleteForMeAttachmentDeleteBuilder {
        let builder = SignalServiceProtosSyncMessageDeleteForMeAttachmentDeleteBuilder()
        if let _value = conversation {
            builder.setConversation(_value)
        }
        if let _value = targetMessage {
            builder.setTargetMessage(_value)
        }
        if let _value = clientUuid {
            builder.setClientUuid(_value)
        }
        if let _value = fallbackDigest {
            builder.setFallbackDigest(_value)
        }
        if let _value = fallbackPlaintextHash {
            builder.setFallbackPlaintextHash(_value)
        }
        if let _value = unknownFields {
            builder.setUnknownFields(_value)
        }
        return builder
    }
}

@objc
public class SignalServiceProtosSyncMessageDeleteForMeAttachmentDeleteBuilder: NSObject {

    private var proto = SignalServiceProtos_SyncMessage.DeleteForMe.AttachmentDelete()

    @objc
    fileprivate override init() {}

    @objc
    @available(swift, obsoleted: 1.0)
    public func setConversation(_ valueParam: SignalServiceProtosSyncMessageDeleteForMeConversationIdentifier?) {
        guard let valueParam = valueParam else { return }
        proto.conversation = valueParam.proto
    }

    public func setConversation(_ valueParam: SignalServiceProtosSyncMessageDeleteForMeConversationIdentifier) {
        proto.conversation = valueParam.proto
    }

    @objc
    @available(swift, obsoleted: 1.0)
    public func setTargetMessage(_ valueParam: SignalServiceProtosSyncMessageDeleteForMeAddressableMessage?) {
        guard let valueParam = valueParam else { return }
        proto.targetMessage = valueParam.proto
    }

    public func setTargetMessage(_ valueParam: SignalServiceProtosSyncMessageDeleteForMeAddressableMessage) {
        proto.targetMessage = valueParam.proto
    }

    @objc
    @available(swift, obsoleted: 1.0)
    public func setClientUuid(_ valueParam: Data?) {
        guard let valueParam = valueParam else { return }
        proto.clientUuid = valueParam
    }

    public func setClientUuid(_ valueParam: Data) {
        proto.clientUuid = valueParam
    }

    @objc
    @available(swift, obsoleted: 1.0)
    public func setFallbackDigest(_ valueParam: Data?) {
        guard let valueParam = valueParam else { return }
        proto.fallbackDigest = valueParam
    }

    public func setFallbackDigest(_ valueParam: Data) {
        proto.fallbackDigest = valueParam
    }

    @objc
    @available(swift, obsoleted: 1.0)
    public func setFallbackPlaintextHash(_ valueParam: Data?) {
        guard let valueParam = valueParam else { return }
        proto.fallbackPlaintextHash = valueParam
    }

    public func setFallbackPlaintextHash(_ valueParam: Data) {
        proto.fallbackPlaintextHash = valueParam
    }

    public func setUnknownFields(_ unknownFields: SwiftProtobuf.UnknownStorage) {
        proto.unknownFields = unknownFields
    }

    @objc
    public func buildInfallibly() -> SignalServiceProtosSyncMessageDeleteForMeAttachmentDelete {
        return SignalServiceProtosSyncMessageDeleteForMeAttachmentDelete(proto)
    }

    @objc
    public func buildSerializedData() throws -> Data {
        return try SignalServiceProtosSyncMessageDeleteForMeAttachmentDelete(proto).serializedData()
    }
}

#if TESTABLE_BUILD

extension SignalServiceProtosSyncMessageDeleteForMeAttachmentDelete {
    @objc
    public func serializedDataIgnoringErrors() -> Data? {
        return try! self.serializedData()
    }
}

extension SignalServiceProtosSyncMessageDeleteForMeAttachmentDeleteBuilder {
    @objc
    public func buildIgnoringErrors() -> SignalServiceProtosSyncMessageDeleteForMeAttachmentDelete? {
        return self.buildInfallibly()
    }
}

#endif

// MARK: - SignalServiceProtosSyncMessageDeleteForMeConversationDelete

@objc
public class SignalServiceProtosSyncMessageDeleteForMeConversationDelete: NSObject, Codable, NSSecureCoding {

    fileprivate let proto: SignalServiceProtos_SyncMessage.DeleteForMe.ConversationDelete

    @objc
    public let conversation: SignalServiceProtosSyncMessageDeleteForMeConversationIdentifier?

    @objc
    public let mostRecentMessages: [SignalServiceProtosSyncMessageDeleteForMeAddressableMessage]

    @objc
    public let mostRecentNonExpiringMessages: [SignalServiceProtosSyncMessageDeleteForMeAddressableMessage]

    @objc
    public var isFullDelete: Bool {
        return proto.isFullDelete
    }
    @objc
    public var hasIsFullDelete: Bool {
        return proto.hasIsFullDelete
    }

    public var hasUnknownFields: Bool {
        return !proto.unknownFields.data.isEmpty
    }
    public var unknownFields: SwiftProtobuf.UnknownStorage? {
        guard hasUnknownFields else { return nil }
        return proto.unknownFields
    }

    private init(proto: SignalServiceProtos_SyncMessage.DeleteForMe.ConversationDelete,
                 conversation: SignalServiceProtosSyncMessageDeleteForMeConversationIdentifier?,
                 mostRecentMessages: [SignalServiceProtosSyncMessageDeleteForMeAddressableMessage],
                 mostRecentNonExpiringMessages: [SignalServiceProtosSyncMessageDeleteForMeAddressableMessage]) {
        self.proto = proto
        self.conversation = conversation
        self.mostRecentMessages = mostRecentMessages
        self.mostRecentNonExpiringMessages = mostRecentNonExpiringMessages
    }

    @objc
    public func serializedData() throws -> Data {
        return try self.proto.serializedData()
    }

    @objc
    public required convenience init(serializedData: Data) throws {
        let proto = try SignalServiceProtos_SyncMessage.DeleteForMe.ConversationDelete(serializedBytes: serializedData)
        self.init(proto)
    }

    fileprivate convenience init(_ proto: SignalServiceProtos_SyncMessage.DeleteForMe.ConversationDelete) {
        var conversation: SignalServiceProtosSyncMessageDeleteForMeConversationIdentifier?
        if proto.hasConversation {
            conversation = SignalServiceProtosSyncMessageDeleteForMeConversationIdentifier(proto.conversation)
        }

        var mostRecentMessages: [SignalServiceProtosSyncMessageDeleteForMeAddressableMessage] = []
        mostRecentMessages = proto.mostRecentMessages.map { SignalServiceProtosSyncMessageDeleteForMeAddressableMessage($0) }

        var mostRecentNonExpiringMessages: [SignalServiceProtosSyncMessageDeleteForMeAddressableMessage] = []
        mostRecentNonExpiringMessages = proto.mostRecentNonExpiringMessages.map { SignalServiceProtosSyncMessageDeleteForMeAddressableMessage($0) }

        self.init(proto: proto,
                  conversation: conversation,
                  mostRecentMessages: mostRecentMessages,
                  mostRecentNonExpiringMessages: mostRecentNonExpiringMessages)
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

extension SignalServiceProtosSyncMessageDeleteForMeConversationDelete {
    @objc
    public static func builder() -> SignalServiceProtosSyncMessageDeleteForMeConversationDeleteBuilder {
        return SignalServiceProtosSyncMessageDeleteForMeConversationDeleteBuilder()
    }

    // asBuilder() constructs a builder that reflects the proto's contents.
    @objc
    public func asBuilder() -> SignalServiceProtosSyncMessageDeleteForMeConversationDeleteBuilder {
        let builder = SignalServiceProtosSyncMessageDeleteForMeConversationDeleteBuilder()
        if let _value = conversation {
            builder.setConversation(_value)
        }
        builder.setMostRecentMessages(mostRecentMessages)
        builder.setMostRecentNonExpiringMessages(mostRecentNonExpiringMessages)
        if hasIsFullDelete {
            builder.setIsFullDelete(isFullDelete)
        }
        if let _value = unknownFields {
            builder.setUnknownFields(_value)
        }
        return builder
    }
}

@objc
public class SignalServiceProtosSyncMessageDeleteForMeConversationDeleteBuilder: NSObject {

    private var proto = SignalServiceProtos_SyncMessage.DeleteForMe.ConversationDelete()

    @objc
    fileprivate override init() {}

    @objc
    @available(swift, obsoleted: 1.0)
    public func setConversation(_ valueParam: SignalServiceProtosSyncMessageDeleteForMeConversationIdentifier?) {
        guard let valueParam = valueParam else { return }
        proto.conversation = valueParam.proto
    }

    public func setConversation(_ valueParam: SignalServiceProtosSyncMessageDeleteForMeConversationIdentifier) {
        proto.conversation = valueParam.proto
    }

    @objc
    public func addMostRecentMessages(_ valueParam: SignalServiceProtosSyncMessageDeleteForMeAddressableMessage) {
        proto.mostRecentMessages.append(valueParam.proto)
    }

    @objc
    public func setMostRecentMessages(_ wrappedItems: [SignalServiceProtosSyncMessageDeleteForMeAddressableMessage]) {
        proto.mostRecentMessages = wrappedItems.map { $0.proto }
    }

    @objc
    public func addMostRecentNonExpiringMessages(_ valueParam: SignalServiceProtosSyncMessageDeleteForMeAddressableMessage) {
        proto.mostRecentNonExpiringMessages.append(valueParam.proto)
    }

    @objc
    public func setMostRecentNonExpiringMessages(_ wrappedItems: [SignalServiceProtosSyncMessageDeleteForMeAddressableMessage]) {
        proto.mostRecentNonExpiringMessages = wrappedItems.map { $0.proto }
    }

    @objc
    public func setIsFullDelete(_ valueParam: Bool) {
        proto.isFullDelete = valueParam
    }

    public func setUnknownFields(_ unknownFields: SwiftProtobuf.UnknownStorage) {
        proto.unknownFields = unknownFields
    }

    @objc
    public func buildInfallibly() -> SignalServiceProtosSyncMessageDeleteForMeConversationDelete {
        return SignalServiceProtosSyncMessageDeleteForMeConversationDelete(proto)
    }

    @objc
    public func buildSerializedData() throws -> Data {
        return try SignalServiceProtosSyncMessageDeleteForMeConversationDelete(proto).serializedData()
    }
}

#if TESTABLE_BUILD

extension SignalServiceProtosSyncMessageDeleteForMeConversationDelete {
    @objc
    public func serializedDataIgnoringErrors() -> Data? {
        return try! self.serializedData()
    }
}

extension SignalServiceProtosSyncMessageDeleteForMeConversationDeleteBuilder {
    @objc
    public func buildIgnoringErrors() -> SignalServiceProtosSyncMessageDeleteForMeConversationDelete? {
        return self.buildInfallibly()
    }
}

#endif

// MARK: - SignalServiceProtosSyncMessageDeleteForMeLocalOnlyConversationDelete

@objc
public class SignalServiceProtosSyncMessageDeleteForMeLocalOnlyConversationDelete: NSObject, Codable, NSSecureCoding {

    fileprivate let proto: SignalServiceProtos_SyncMessage.DeleteForMe.LocalOnlyConversationDelete

    @objc
    public let conversation: SignalServiceProtosSyncMessageDeleteForMeConversationIdentifier?

    public var hasUnknownFields: Bool {
        return !proto.unknownFields.data.isEmpty
    }
    public var unknownFields: SwiftProtobuf.UnknownStorage? {
        guard hasUnknownFields else { return nil }
        return proto.unknownFields
    }

    private init(proto: SignalServiceProtos_SyncMessage.DeleteForMe.LocalOnlyConversationDelete,
                 conversation: SignalServiceProtosSyncMessageDeleteForMeConversationIdentifier?) {
        self.proto = proto
        self.conversation = conversation
    }

    @objc
    public func serializedData() throws -> Data {
        return try self.proto.serializedData()
    }

    @objc
    public required convenience init(serializedData: Data) throws {
        let proto = try SignalServiceProtos_SyncMessage.DeleteForMe.LocalOnlyConversationDelete(serializedBytes: serializedData)
        self.init(proto)
    }

    fileprivate convenience init(_ proto: SignalServiceProtos_SyncMessage.DeleteForMe.LocalOnlyConversationDelete) {
        var conversation: SignalServiceProtosSyncMessageDeleteForMeConversationIdentifier?
        if proto.hasConversation {
            conversation = SignalServiceProtosSyncMessageDeleteForMeConversationIdentifier(proto.conversation)
        }

        self.init(proto: proto,
                  conversation: conversation)
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

extension SignalServiceProtosSyncMessageDeleteForMeLocalOnlyConversationDelete {
    @objc
    public static func builder() -> SignalServiceProtosSyncMessageDeleteForMeLocalOnlyConversationDeleteBuilder {
        return SignalServiceProtosSyncMessageDeleteForMeLocalOnlyConversationDeleteBuilder()
    }

    // asBuilder() constructs a builder that reflects the proto's contents.
    @objc
    public func asBuilder() -> SignalServiceProtosSyncMessageDeleteForMeLocalOnlyConversationDeleteBuilder {
        let builder = SignalServiceProtosSyncMessageDeleteForMeLocalOnlyConversationDeleteBuilder()
        if let _value = conversation {
            builder.setConversation(_value)
        }
        if let _value = unknownFields {
            builder.setUnknownFields(_value)
        }
        return builder
    }
}

@objc
public class SignalServiceProtosSyncMessageDeleteForMeLocalOnlyConversationDeleteBuilder: NSObject {

    private var proto = SignalServiceProtos_SyncMessage.DeleteForMe.LocalOnlyConversationDelete()

    @objc
    fileprivate override init() {}

    @objc
    @available(swift, obsoleted: 1.0)
    public func setConversation(_ valueParam: SignalServiceProtosSyncMessageDeleteForMeConversationIdentifier?) {
        guard let valueParam = valueParam else { return }
        proto.conversation = valueParam.proto
    }

    public func setConversation(_ valueParam: SignalServiceProtosSyncMessageDeleteForMeConversationIdentifier) {
        proto.conversation = valueParam.proto
    }

    public func setUnknownFields(_ unknownFields: SwiftProtobuf.UnknownStorage) {
        proto.unknownFields = unknownFields
    }

    @objc
    public func buildInfallibly() -> SignalServiceProtosSyncMessageDeleteForMeLocalOnlyConversationDelete {
        return SignalServiceProtosSyncMessageDeleteForMeLocalOnlyConversationDelete(proto)
    }

    @objc
    public func buildSerializedData() throws -> Data {
        return try SignalServiceProtosSyncMessageDeleteForMeLocalOnlyConversationDelete(proto).serializedData()
    }
}

#if TESTABLE_BUILD

extension SignalServiceProtosSyncMessageDeleteForMeLocalOnlyConversationDelete {
    @objc
    public func serializedDataIgnoringErrors() -> Data? {
        return try! self.serializedData()
    }
}

extension SignalServiceProtosSyncMessageDeleteForMeLocalOnlyConversationDeleteBuilder {
    @objc
    public func buildIgnoringErrors() -> SignalServiceProtosSyncMessageDeleteForMeLocalOnlyConversationDelete? {
        return self.buildInfallibly()
    }
}

#endif

// MARK: - SignalServiceProtosSyncMessageDeleteForMe

@objc
public class SignalServiceProtosSyncMessageDeleteForMe: NSObject, Codable, NSSecureCoding {

    fileprivate let proto: SignalServiceProtos_SyncMessage.DeleteForMe

    @objc
    public let messageDeletes: [SignalServiceProtosSyncMessageDeleteForMeMessageDeletes]

    @objc
    public let conversationDeletes: [SignalServiceProtosSyncMessageDeleteForMeConversationDelete]

    @objc
    public let localOnlyConversationDeletes: [SignalServiceProtosSyncMessageDeleteForMeLocalOnlyConversationDelete]

    @objc
    public let attachmentDeletes: [SignalServiceProtosSyncMessageDeleteForMeAttachmentDelete]

    public var hasUnknownFields: Bool {
        return !proto.unknownFields.data.isEmpty
    }
    public var unknownFields: SwiftProtobuf.UnknownStorage? {
        guard hasUnknownFields else { return nil }
        return proto.unknownFields
    }

    private init(proto: SignalServiceProtos_SyncMessage.DeleteForMe,
                 messageDeletes: [SignalServiceProtosSyncMessageDeleteForMeMessageDeletes],
                 conversationDeletes: [SignalServiceProtosSyncMessageDeleteForMeConversationDelete],
                 localOnlyConversationDeletes: [SignalServiceProtosSyncMessageDeleteForMeLocalOnlyConversationDelete],
                 attachmentDeletes: [SignalServiceProtosSyncMessageDeleteForMeAttachmentDelete]) {
        self.proto = proto
        self.messageDeletes = messageDeletes
        self.conversationDeletes = conversationDeletes
        self.localOnlyConversationDeletes = localOnlyConversationDeletes
        self.attachmentDeletes = attachmentDeletes
    }

    @objc
    public func serializedData() throws -> Data {
        return try self.proto.serializedData()
    }

    @objc
    public required convenience init(serializedData: Data) throws {
        let proto = try SignalServiceProtos_SyncMessage.DeleteForMe(serializedBytes: serializedData)
        self.init(proto)
    }

    fileprivate convenience init(_ proto: SignalServiceProtos_SyncMessage.DeleteForMe) {
        var messageDeletes: [SignalServiceProtosSyncMessageDeleteForMeMessageDeletes] = []
        messageDeletes = proto.messageDeletes.map { SignalServiceProtosSyncMessageDeleteForMeMessageDeletes($0) }

        var conversationDeletes: [SignalServiceProtosSyncMessageDeleteForMeConversationDelete] = []
        conversationDeletes = proto.conversationDeletes.map { SignalServiceProtosSyncMessageDeleteForMeConversationDelete($0) }

        var localOnlyConversationDeletes: [SignalServiceProtosSyncMessageDeleteForMeLocalOnlyConversationDelete] = []
        localOnlyConversationDeletes = proto.localOnlyConversationDeletes.map { SignalServiceProtosSyncMessageDeleteForMeLocalOnlyConversationDelete($0) }

        var attachmentDeletes: [SignalServiceProtosSyncMessageDeleteForMeAttachmentDelete] = []
        attachmentDeletes = proto.attachmentDeletes.map { SignalServiceProtosSyncMessageDeleteForMeAttachmentDelete($0) }

        self.init(proto: proto,
                  messageDeletes: messageDeletes,
                  conversationDeletes: conversationDeletes,
                  localOnlyConversationDeletes: localOnlyConversationDeletes,
                  attachmentDeletes: attachmentDeletes)
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

extension SignalServiceProtosSyncMessageDeleteForMe {
    @objc
    public static func builder() -> SignalServiceProtosSyncMessageDeleteForMeBuilder {
        return SignalServiceProtosSyncMessageDeleteForMeBuilder()
    }

    // asBuilder() constructs a builder that reflects the proto's contents.
    @objc
    public func asBuilder() -> SignalServiceProtosSyncMessageDeleteForMeBuilder {
        let builder = SignalServiceProtosSyncMessageDeleteForMeBuilder()
        builder.setMessageDeletes(messageDeletes)
        builder.setConversationDeletes(conversationDeletes)
        builder.setLocalOnlyConversationDeletes(localOnlyConversationDeletes)
        builder.setAttachmentDeletes(attachmentDeletes)
        if let _value = unknownFields {
            builder.setUnknownFields(_value)
        }
        return builder
    }
}

@objc
public class SignalServiceProtosSyncMessageDeleteForMeBuilder: NSObject {

    private var proto = SignalServiceProtos_SyncMessage.DeleteForMe()

    @objc
    fileprivate override init() {}

    @objc
    public func addMessageDeletes(_ valueParam: SignalServiceProtosSyncMessageDeleteForMeMessageDeletes) {
        proto.messageDeletes.append(valueParam.proto)
    }

    @objc
    public func setMessageDeletes(_ wrappedItems: [SignalServiceProtosSyncMessageDeleteForMeMessageDeletes]) {
        proto.messageDeletes = wrappedItems.map { $0.proto }
    }

    @objc
    public func addConversationDeletes(_ valueParam: SignalServiceProtosSyncMessageDeleteForMeConversationDelete) {
        proto.conversationDeletes.append(valueParam.proto)
    }

    @objc
    public func setConversationDeletes(_ wrappedItems: [SignalServiceProtosSyncMessageDeleteForMeConversationDelete]) {
        proto.conversationDeletes = wrappedItems.map { $0.proto }
    }

    @objc
    public func addLocalOnlyConversationDeletes(_ valueParam: SignalServiceProtosSyncMessageDeleteForMeLocalOnlyConversationDelete) {
        proto.localOnlyConversationDeletes.append(valueParam.proto)
    }

    @objc
    public func setLocalOnlyConversationDeletes(_ wrappedItems: [SignalServiceProtosSyncMessageDeleteForMeLocalOnlyConversationDelete]) {
        proto.localOnlyConversationDeletes = wrappedItems.map { $0.proto }
    }

    @objc
    public func addAttachmentDeletes(_ valueParam: SignalServiceProtosSyncMessageDeleteForMeAttachmentDelete) {
        proto.attachmentDeletes.append(valueParam.proto)
    }

    @objc
    public func setAttachmentDeletes(_ wrappedItems: [SignalServiceProtosSyncMessageDeleteForMeAttachmentDelete]) {
        proto.attachmentDeletes = wrappedItems.map { $0.proto }
    }

    public func setUnknownFields(_ unknownFields: SwiftProtobuf.UnknownStorage) {
        proto.unknownFields = unknownFields
    }

    @objc
    public func buildInfallibly() -> SignalServiceProtosSyncMessageDeleteForMe {
        return SignalServiceProtosSyncMessageDeleteForMe(proto)
    }

    @objc
    public func buildSerializedData() throws -> Data {
        return try SignalServiceProtosSyncMessageDeleteForMe(proto).serializedData()
    }
}

#if TESTABLE_BUILD

extension SignalServiceProtosSyncMessageDeleteForMe {
    @objc
    public func serializedDataIgnoringErrors() -> Data? {
        return try! self.serializedData()
    }
}

extension SignalServiceProtosSyncMessageDeleteForMeBuilder {
    @objc
    public func buildIgnoringErrors() -> SignalServiceProtosSyncMessageDeleteForMe? {
        return self.buildInfallibly()
    }
}

#endif

// MARK: - SignalServiceProtosSyncMessageDeviceNameChange

@objc
public class SignalServiceProtosSyncMessageDeviceNameChange: NSObject, Codable, NSSecureCoding {

    fileprivate let proto: SignalServiceProtos_SyncMessage.DeviceNameChange

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

    private init(proto: SignalServiceProtos_SyncMessage.DeviceNameChange) {
        self.proto = proto
    }

    @objc
    public func serializedData() throws -> Data {
        return try self.proto.serializedData()
    }

    @objc
    public required convenience init(serializedData: Data) throws {
        let proto = try SignalServiceProtos_SyncMessage.DeviceNameChange(serializedBytes: serializedData)
        self.init(proto)
    }

    fileprivate convenience init(_ proto: SignalServiceProtos_SyncMessage.DeviceNameChange) {
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

extension SignalServiceProtosSyncMessageDeviceNameChange {
    @objc
    public static func builder() -> SignalServiceProtosSyncMessageDeviceNameChangeBuilder {
        return SignalServiceProtosSyncMessageDeviceNameChangeBuilder()
    }

    // asBuilder() constructs a builder that reflects the proto's contents.
    @objc
    public func asBuilder() -> SignalServiceProtosSyncMessageDeviceNameChangeBuilder {
        let builder = SignalServiceProtosSyncMessageDeviceNameChangeBuilder()
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
public class SignalServiceProtosSyncMessageDeviceNameChangeBuilder: NSObject {

    private var proto = SignalServiceProtos_SyncMessage.DeviceNameChange()

    @objc
    fileprivate override init() {}

    @objc
    public func setDeviceID(_ valueParam: UInt32) {
        proto.deviceID = valueParam
    }

    public func setUnknownFields(_ unknownFields: SwiftProtobuf.UnknownStorage) {
        proto.unknownFields = unknownFields
    }

    @objc
    public func buildInfallibly() -> SignalServiceProtosSyncMessageDeviceNameChange {
        return SignalServiceProtosSyncMessageDeviceNameChange(proto)
    }

    @objc
    public func buildSerializedData() throws -> Data {
        return try SignalServiceProtosSyncMessageDeviceNameChange(proto).serializedData()
    }
}

#if TESTABLE_BUILD

extension SignalServiceProtosSyncMessageDeviceNameChange {
    @objc
    public func serializedDataIgnoringErrors() -> Data? {
        return try! self.serializedData()
    }
}

extension SignalServiceProtosSyncMessageDeviceNameChangeBuilder {
    @objc
    public func buildIgnoringErrors() -> SignalServiceProtosSyncMessageDeviceNameChange? {
        return self.buildInfallibly()
    }
}

#endif

// MARK: - SignalServiceProtosSyncMessage

@objc
public class SignalServiceProtosSyncMessage: NSObject, Codable, NSSecureCoding {

    fileprivate let proto: SignalServiceProtos_SyncMessage

    @objc
    public let sent: SignalServiceProtosSyncMessageSent?

    @objc
    public let contacts: SignalServiceProtosSyncMessageContacts?

    @objc
    public let request: SignalServiceProtosSyncMessageRequest?

    @objc
    public let read: [SignalServiceProtosSyncMessageRead]

    @objc
    public let blocked: SignalServiceProtosSyncMessageBlocked?

    @objc
    public let verified: SignalServiceProtosVerified?

    @objc
    public let configuration: SignalServiceProtosSyncMessageConfiguration?

    @objc
    public let stickerPackOperation: [SignalServiceProtosSyncMessageStickerPackOperation]

    @objc
    public let viewOnceOpen: SignalServiceProtosSyncMessageViewOnceOpen?

    @objc
    public let fetchLatest: SignalServiceProtosSyncMessageFetchLatest?

    @objc
    public let keys: SignalServiceProtosSyncMessageKeys?

    @objc
    public let messageRequestResponse: SignalServiceProtosSyncMessageMessageRequestResponse?

    @objc
    public let outgoingPayment: SignalServiceProtosSyncMessageOutgoingPayment?

    @objc
    public let viewed: [SignalServiceProtosSyncMessageViewed]

    @objc
    public let pniChangeNumber: SignalServiceProtosSyncMessagePniChangeNumber?

    @objc
    public let callEvent: SignalServiceProtosSyncMessageCallEvent?

    @objc
    public let callLinkUpdate: SignalServiceProtosSyncMessageCallLinkUpdate?

    @objc
    public let callLogEvent: SignalServiceProtosSyncMessageCallLogEvent?

    @objc
    public let deleteForMe: SignalServiceProtosSyncMessageDeleteForMe?

    @objc
    public let deviceNameChange: SignalServiceProtosSyncMessageDeviceNameChange?

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
                 sent: SignalServiceProtosSyncMessageSent?,
                 contacts: SignalServiceProtosSyncMessageContacts?,
                 request: SignalServiceProtosSyncMessageRequest?,
                 read: [SignalServiceProtosSyncMessageRead],
                 blocked: SignalServiceProtosSyncMessageBlocked?,
                 verified: SignalServiceProtosVerified?,
                 configuration: SignalServiceProtosSyncMessageConfiguration?,
                 stickerPackOperation: [SignalServiceProtosSyncMessageStickerPackOperation],
                 viewOnceOpen: SignalServiceProtosSyncMessageViewOnceOpen?,
                 fetchLatest: SignalServiceProtosSyncMessageFetchLatest?,
                 keys: SignalServiceProtosSyncMessageKeys?,
                 messageRequestResponse: SignalServiceProtosSyncMessageMessageRequestResponse?,
                 outgoingPayment: SignalServiceProtosSyncMessageOutgoingPayment?,
                 viewed: [SignalServiceProtosSyncMessageViewed],
                 pniChangeNumber: SignalServiceProtosSyncMessagePniChangeNumber?,
                 callEvent: SignalServiceProtosSyncMessageCallEvent?,
                 callLinkUpdate: SignalServiceProtosSyncMessageCallLinkUpdate?,
                 callLogEvent: SignalServiceProtosSyncMessageCallLogEvent?,
                 deleteForMe: SignalServiceProtosSyncMessageDeleteForMe?,
                 deviceNameChange: SignalServiceProtosSyncMessageDeviceNameChange?) {
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
        self.callLinkUpdate = callLinkUpdate
        self.callLogEvent = callLogEvent
        self.deleteForMe = deleteForMe
        self.deviceNameChange = deviceNameChange
    }

    @objc
    public func serializedData() throws -> Data {
        return try self.proto.serializedData()
    }

    @objc
    public required convenience init(serializedData: Data) throws {
        let proto = try SignalServiceProtos_SyncMessage(serializedBytes: serializedData)
        try self.init(proto)
    }

    fileprivate convenience init(_ proto: SignalServiceProtos_SyncMessage) throws {
        var sent: SignalServiceProtosSyncMessageSent?
        if proto.hasSent {
            sent = try SignalServiceProtosSyncMessageSent(proto.sent)
        }

        var contacts: SignalServiceProtosSyncMessageContacts?
        if proto.hasContacts {
            contacts = try SignalServiceProtosSyncMessageContacts(proto.contacts)
        }

        var request: SignalServiceProtosSyncMessageRequest?
        if proto.hasRequest {
            request = SignalServiceProtosSyncMessageRequest(proto.request)
        }

        var read: [SignalServiceProtosSyncMessageRead] = []
        read = try proto.read.map { try SignalServiceProtosSyncMessageRead($0) }

        var blocked: SignalServiceProtosSyncMessageBlocked?
        if proto.hasBlocked {
            blocked = SignalServiceProtosSyncMessageBlocked(proto.blocked)
        }

        var verified: SignalServiceProtosVerified?
        if proto.hasVerified {
            verified = SignalServiceProtosVerified(proto.verified)
        }

        var configuration: SignalServiceProtosSyncMessageConfiguration?
        if proto.hasConfiguration {
            configuration = SignalServiceProtosSyncMessageConfiguration(proto.configuration)
        }

        var stickerPackOperation: [SignalServiceProtosSyncMessageStickerPackOperation] = []
        stickerPackOperation = try proto.stickerPackOperation.map { try SignalServiceProtosSyncMessageStickerPackOperation($0) }

        var viewOnceOpen: SignalServiceProtosSyncMessageViewOnceOpen?
        if proto.hasViewOnceOpen {
            viewOnceOpen = try SignalServiceProtosSyncMessageViewOnceOpen(proto.viewOnceOpen)
        }

        var fetchLatest: SignalServiceProtosSyncMessageFetchLatest?
        if proto.hasFetchLatest {
            fetchLatest = SignalServiceProtosSyncMessageFetchLatest(proto.fetchLatest)
        }

        var keys: SignalServiceProtosSyncMessageKeys?
        if proto.hasKeys {
            keys = SignalServiceProtosSyncMessageKeys(proto.keys)
        }

        var messageRequestResponse: SignalServiceProtosSyncMessageMessageRequestResponse?
        if proto.hasMessageRequestResponse {
            messageRequestResponse = SignalServiceProtosSyncMessageMessageRequestResponse(proto.messageRequestResponse)
        }

        var outgoingPayment: SignalServiceProtosSyncMessageOutgoingPayment?
        if proto.hasOutgoingPayment {
            outgoingPayment = try SignalServiceProtosSyncMessageOutgoingPayment(proto.outgoingPayment)
        }

        var viewed: [SignalServiceProtosSyncMessageViewed] = []
        viewed = try proto.viewed.map { try SignalServiceProtosSyncMessageViewed($0) }

        var pniChangeNumber: SignalServiceProtosSyncMessagePniChangeNumber?
        if proto.hasPniChangeNumber {
            pniChangeNumber = SignalServiceProtosSyncMessagePniChangeNumber(proto.pniChangeNumber)
        }

        var callEvent: SignalServiceProtosSyncMessageCallEvent?
        if proto.hasCallEvent {
            callEvent = SignalServiceProtosSyncMessageCallEvent(proto.callEvent)
        }

        var callLinkUpdate: SignalServiceProtosSyncMessageCallLinkUpdate?
        if proto.hasCallLinkUpdate {
            callLinkUpdate = SignalServiceProtosSyncMessageCallLinkUpdate(proto.callLinkUpdate)
        }

        var callLogEvent: SignalServiceProtosSyncMessageCallLogEvent?
        if proto.hasCallLogEvent {
            callLogEvent = SignalServiceProtosSyncMessageCallLogEvent(proto.callLogEvent)
        }

        var deleteForMe: SignalServiceProtosSyncMessageDeleteForMe?
        if proto.hasDeleteForMe {
            deleteForMe = SignalServiceProtosSyncMessageDeleteForMe(proto.deleteForMe)
        }

        var deviceNameChange: SignalServiceProtosSyncMessageDeviceNameChange?
        if proto.hasDeviceNameChange {
            deviceNameChange = SignalServiceProtosSyncMessageDeviceNameChange(proto.deviceNameChange)
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
                  callEvent: callEvent,
                  callLinkUpdate: callLinkUpdate,
                  callLogEvent: callLogEvent,
                  deleteForMe: deleteForMe,
                  deviceNameChange: deviceNameChange)
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

extension SignalServiceProtosSyncMessage {
    @objc
    public static func builder() -> SignalServiceProtosSyncMessageBuilder {
        return SignalServiceProtosSyncMessageBuilder()
    }

    // asBuilder() constructs a builder that reflects the proto's contents.
    @objc
    public func asBuilder() -> SignalServiceProtosSyncMessageBuilder {
        let builder = SignalServiceProtosSyncMessageBuilder()
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
        if let _value = callLinkUpdate {
            builder.setCallLinkUpdate(_value)
        }
        if let _value = callLogEvent {
            builder.setCallLogEvent(_value)
        }
        if let _value = deleteForMe {
            builder.setDeleteForMe(_value)
        }
        if let _value = deviceNameChange {
            builder.setDeviceNameChange(_value)
        }
        if let _value = unknownFields {
            builder.setUnknownFields(_value)
        }
        return builder
    }
}

@objc
public class SignalServiceProtosSyncMessageBuilder: NSObject {

    private var proto = SignalServiceProtos_SyncMessage()

    @objc
    fileprivate override init() {}

    @objc
    @available(swift, obsoleted: 1.0)
    public func setSent(_ valueParam: SignalServiceProtosSyncMessageSent?) {
        guard let valueParam = valueParam else { return }
        proto.sent = valueParam.proto
    }

    public func setSent(_ valueParam: SignalServiceProtosSyncMessageSent) {
        proto.sent = valueParam.proto
    }

    @objc
    @available(swift, obsoleted: 1.0)
    public func setContacts(_ valueParam: SignalServiceProtosSyncMessageContacts?) {
        guard let valueParam = valueParam else { return }
        proto.contacts = valueParam.proto
    }

    public func setContacts(_ valueParam: SignalServiceProtosSyncMessageContacts) {
        proto.contacts = valueParam.proto
    }

    @objc
    @available(swift, obsoleted: 1.0)
    public func setRequest(_ valueParam: SignalServiceProtosSyncMessageRequest?) {
        guard let valueParam = valueParam else { return }
        proto.request = valueParam.proto
    }

    public func setRequest(_ valueParam: SignalServiceProtosSyncMessageRequest) {
        proto.request = valueParam.proto
    }

    @objc
    public func addRead(_ valueParam: SignalServiceProtosSyncMessageRead) {
        proto.read.append(valueParam.proto)
    }

    @objc
    public func setRead(_ wrappedItems: [SignalServiceProtosSyncMessageRead]) {
        proto.read = wrappedItems.map { $0.proto }
    }

    @objc
    @available(swift, obsoleted: 1.0)
    public func setBlocked(_ valueParam: SignalServiceProtosSyncMessageBlocked?) {
        guard let valueParam = valueParam else { return }
        proto.blocked = valueParam.proto
    }

    public func setBlocked(_ valueParam: SignalServiceProtosSyncMessageBlocked) {
        proto.blocked = valueParam.proto
    }

    @objc
    @available(swift, obsoleted: 1.0)
    public func setVerified(_ valueParam: SignalServiceProtosVerified?) {
        guard let valueParam = valueParam else { return }
        proto.verified = valueParam.proto
    }

    public func setVerified(_ valueParam: SignalServiceProtosVerified) {
        proto.verified = valueParam.proto
    }

    @objc
    @available(swift, obsoleted: 1.0)
    public func setConfiguration(_ valueParam: SignalServiceProtosSyncMessageConfiguration?) {
        guard let valueParam = valueParam else { return }
        proto.configuration = valueParam.proto
    }

    public func setConfiguration(_ valueParam: SignalServiceProtosSyncMessageConfiguration) {
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
    public func addStickerPackOperation(_ valueParam: SignalServiceProtosSyncMessageStickerPackOperation) {
        proto.stickerPackOperation.append(valueParam.proto)
    }

    @objc
    public func setStickerPackOperation(_ wrappedItems: [SignalServiceProtosSyncMessageStickerPackOperation]) {
        proto.stickerPackOperation = wrappedItems.map { $0.proto }
    }

    @objc
    @available(swift, obsoleted: 1.0)
    public func setViewOnceOpen(_ valueParam: SignalServiceProtosSyncMessageViewOnceOpen?) {
        guard let valueParam = valueParam else { return }
        proto.viewOnceOpen = valueParam.proto
    }

    public func setViewOnceOpen(_ valueParam: SignalServiceProtosSyncMessageViewOnceOpen) {
        proto.viewOnceOpen = valueParam.proto
    }

    @objc
    @available(swift, obsoleted: 1.0)
    public func setFetchLatest(_ valueParam: SignalServiceProtosSyncMessageFetchLatest?) {
        guard let valueParam = valueParam else { return }
        proto.fetchLatest = valueParam.proto
    }

    public func setFetchLatest(_ valueParam: SignalServiceProtosSyncMessageFetchLatest) {
        proto.fetchLatest = valueParam.proto
    }

    @objc
    @available(swift, obsoleted: 1.0)
    public func setKeys(_ valueParam: SignalServiceProtosSyncMessageKeys?) {
        guard let valueParam = valueParam else { return }
        proto.keys = valueParam.proto
    }

    public func setKeys(_ valueParam: SignalServiceProtosSyncMessageKeys) {
        proto.keys = valueParam.proto
    }

    @objc
    @available(swift, obsoleted: 1.0)
    public func setMessageRequestResponse(_ valueParam: SignalServiceProtosSyncMessageMessageRequestResponse?) {
        guard let valueParam = valueParam else { return }
        proto.messageRequestResponse = valueParam.proto
    }

    public func setMessageRequestResponse(_ valueParam: SignalServiceProtosSyncMessageMessageRequestResponse) {
        proto.messageRequestResponse = valueParam.proto
    }

    @objc
    @available(swift, obsoleted: 1.0)
    public func setOutgoingPayment(_ valueParam: SignalServiceProtosSyncMessageOutgoingPayment?) {
        guard let valueParam = valueParam else { return }
        proto.outgoingPayment = valueParam.proto
    }

    public func setOutgoingPayment(_ valueParam: SignalServiceProtosSyncMessageOutgoingPayment) {
        proto.outgoingPayment = valueParam.proto
    }

    @objc
    public func addViewed(_ valueParam: SignalServiceProtosSyncMessageViewed) {
        proto.viewed.append(valueParam.proto)
    }

    @objc
    public func setViewed(_ wrappedItems: [SignalServiceProtosSyncMessageViewed]) {
        proto.viewed = wrappedItems.map { $0.proto }
    }

    @objc
    @available(swift, obsoleted: 1.0)
    public func setPniChangeNumber(_ valueParam: SignalServiceProtosSyncMessagePniChangeNumber?) {
        guard let valueParam = valueParam else { return }
        proto.pniChangeNumber = valueParam.proto
    }

    public func setPniChangeNumber(_ valueParam: SignalServiceProtosSyncMessagePniChangeNumber) {
        proto.pniChangeNumber = valueParam.proto
    }

    @objc
    @available(swift, obsoleted: 1.0)
    public func setCallEvent(_ valueParam: SignalServiceProtosSyncMessageCallEvent?) {
        guard let valueParam = valueParam else { return }
        proto.callEvent = valueParam.proto
    }

    public func setCallEvent(_ valueParam: SignalServiceProtosSyncMessageCallEvent) {
        proto.callEvent = valueParam.proto
    }

    @objc
    @available(swift, obsoleted: 1.0)
    public func setCallLinkUpdate(_ valueParam: SignalServiceProtosSyncMessageCallLinkUpdate?) {
        guard let valueParam = valueParam else { return }
        proto.callLinkUpdate = valueParam.proto
    }

    public func setCallLinkUpdate(_ valueParam: SignalServiceProtosSyncMessageCallLinkUpdate) {
        proto.callLinkUpdate = valueParam.proto
    }

    @objc
    @available(swift, obsoleted: 1.0)
    public func setCallLogEvent(_ valueParam: SignalServiceProtosSyncMessageCallLogEvent?) {
        guard let valueParam = valueParam else { return }
        proto.callLogEvent = valueParam.proto
    }

    public func setCallLogEvent(_ valueParam: SignalServiceProtosSyncMessageCallLogEvent) {
        proto.callLogEvent = valueParam.proto
    }

    @objc
    @available(swift, obsoleted: 1.0)
    public func setDeleteForMe(_ valueParam: SignalServiceProtosSyncMessageDeleteForMe?) {
        guard let valueParam = valueParam else { return }
        proto.deleteForMe = valueParam.proto
    }

    public func setDeleteForMe(_ valueParam: SignalServiceProtosSyncMessageDeleteForMe) {
        proto.deleteForMe = valueParam.proto
    }

    @objc
    @available(swift, obsoleted: 1.0)
    public func setDeviceNameChange(_ valueParam: SignalServiceProtosSyncMessageDeviceNameChange?) {
        guard let valueParam = valueParam else { return }
        proto.deviceNameChange = valueParam.proto
    }

    public func setDeviceNameChange(_ valueParam: SignalServiceProtosSyncMessageDeviceNameChange) {
        proto.deviceNameChange = valueParam.proto
    }

    public func setUnknownFields(_ unknownFields: SwiftProtobuf.UnknownStorage) {
        proto.unknownFields = unknownFields
    }

    @objc
    public func build() throws -> SignalServiceProtosSyncMessage {
        return try SignalServiceProtosSyncMessage(proto)
    }

    @objc
    public func buildSerializedData() throws -> Data {
        return try SignalServiceProtosSyncMessage(proto).serializedData()
    }
}

#if TESTABLE_BUILD

extension SignalServiceProtosSyncMessage {
    @objc
    public func serializedDataIgnoringErrors() -> Data? {
        return try! self.serializedData()
    }
}

extension SignalServiceProtosSyncMessageBuilder {
    @objc
    public func buildIgnoringErrors() -> SignalServiceProtosSyncMessage? {
        return try! self.build()
    }
}

#endif

// MARK: - SignalServiceProtosAttachmentPointerFlags

@objc
public enum SignalServiceProtosAttachmentPointerFlags: Int32 {
    case voiceMessage = 1
    case borderless = 2
    case gif = 8
}

private func SignalServiceProtosAttachmentPointerFlagsWrap(_ value: SignalServiceProtos_AttachmentPointer.Flags) -> SignalServiceProtosAttachmentPointerFlags {
    switch value {
    case .voiceMessage: return .voiceMessage
    case .borderless: return .borderless
    case .gif: return .gif
    }
}

private func SignalServiceProtosAttachmentPointerFlagsUnwrap(_ value: SignalServiceProtosAttachmentPointerFlags) -> SignalServiceProtos_AttachmentPointer.Flags {
    switch value {
    case .voiceMessage: return .voiceMessage
    case .borderless: return .borderless
    case .gif: return .gif
    }
}

// MARK: - SignalServiceProtosAttachmentPointer

@objc
public class SignalServiceProtosAttachmentPointer: NSObject, Codable, NSSecureCoding {

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
    public var clientUuid: Data? {
        guard hasClientUuid else {
            return nil
        }
        return proto.clientUuid
    }
    @objc
    public var hasClientUuid: Bool {
        return proto.hasClientUuid
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
    public required convenience init(serializedData: Data) throws {
        let proto = try SignalServiceProtos_AttachmentPointer(serializedBytes: serializedData)
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

extension SignalServiceProtosAttachmentPointer {
    @objc
    public static func builder() -> SignalServiceProtosAttachmentPointerBuilder {
        return SignalServiceProtosAttachmentPointerBuilder()
    }

    // asBuilder() constructs a builder that reflects the proto's contents.
    @objc
    public func asBuilder() -> SignalServiceProtosAttachmentPointerBuilder {
        let builder = SignalServiceProtosAttachmentPointerBuilder()
        if hasCdnID {
            builder.setCdnID(cdnID)
        }
        if let _value = cdnKey {
            builder.setCdnKey(_value)
        }
        if let _value = clientUuid {
            builder.setClientUuid(_value)
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
public class SignalServiceProtosAttachmentPointerBuilder: NSObject {

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
    public func setClientUuid(_ valueParam: Data?) {
        guard let valueParam = valueParam else { return }
        proto.clientUuid = valueParam
    }

    public func setClientUuid(_ valueParam: Data) {
        proto.clientUuid = valueParam
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
    public func buildInfallibly() -> SignalServiceProtosAttachmentPointer {
        return SignalServiceProtosAttachmentPointer(proto)
    }

    @objc
    public func buildSerializedData() throws -> Data {
        return try SignalServiceProtosAttachmentPointer(proto).serializedData()
    }
}

#if TESTABLE_BUILD

extension SignalServiceProtosAttachmentPointer {
    @objc
    public func serializedDataIgnoringErrors() -> Data? {
        return try! self.serializedData()
    }
}

extension SignalServiceProtosAttachmentPointerBuilder {
    @objc
    public func buildIgnoringErrors() -> SignalServiceProtosAttachmentPointer? {
        return self.buildInfallibly()
    }
}

#endif

// MARK: - SignalServiceProtosGroupContextV2

@objc
public class SignalServiceProtosGroupContextV2: NSObject, Codable, NSSecureCoding {

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
    public required convenience init(serializedData: Data) throws {
        let proto = try SignalServiceProtos_GroupContextV2(serializedBytes: serializedData)
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

extension SignalServiceProtosGroupContextV2 {
    @objc
    public static func builder() -> SignalServiceProtosGroupContextV2Builder {
        return SignalServiceProtosGroupContextV2Builder()
    }

    // asBuilder() constructs a builder that reflects the proto's contents.
    @objc
    public func asBuilder() -> SignalServiceProtosGroupContextV2Builder {
        let builder = SignalServiceProtosGroupContextV2Builder()
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
public class SignalServiceProtosGroupContextV2Builder: NSObject {

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
    public func buildInfallibly() -> SignalServiceProtosGroupContextV2 {
        return SignalServiceProtosGroupContextV2(proto)
    }

    @objc
    public func buildSerializedData() throws -> Data {
        return try SignalServiceProtosGroupContextV2(proto).serializedData()
    }
}

#if TESTABLE_BUILD

extension SignalServiceProtosGroupContextV2 {
    @objc
    public func serializedDataIgnoringErrors() -> Data? {
        return try! self.serializedData()
    }
}

extension SignalServiceProtosGroupContextV2Builder {
    @objc
    public func buildIgnoringErrors() -> SignalServiceProtosGroupContextV2? {
        return self.buildInfallibly()
    }
}

#endif

// MARK: - SignalServiceProtosContactDetailsAvatar

@objc
public class SignalServiceProtosContactDetailsAvatar: NSObject, Codable, NSSecureCoding {

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
    public required convenience init(serializedData: Data) throws {
        let proto = try SignalServiceProtos_ContactDetails.Avatar(serializedBytes: serializedData)
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

extension SignalServiceProtosContactDetailsAvatar {
    @objc
    public static func builder() -> SignalServiceProtosContactDetailsAvatarBuilder {
        return SignalServiceProtosContactDetailsAvatarBuilder()
    }

    // asBuilder() constructs a builder that reflects the proto's contents.
    @objc
    public func asBuilder() -> SignalServiceProtosContactDetailsAvatarBuilder {
        let builder = SignalServiceProtosContactDetailsAvatarBuilder()
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
public class SignalServiceProtosContactDetailsAvatarBuilder: NSObject {

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
    public func buildInfallibly() -> SignalServiceProtosContactDetailsAvatar {
        return SignalServiceProtosContactDetailsAvatar(proto)
    }

    @objc
    public func buildSerializedData() throws -> Data {
        return try SignalServiceProtosContactDetailsAvatar(proto).serializedData()
    }
}

#if TESTABLE_BUILD

extension SignalServiceProtosContactDetailsAvatar {
    @objc
    public func serializedDataIgnoringErrors() -> Data? {
        return try! self.serializedData()
    }
}

extension SignalServiceProtosContactDetailsAvatarBuilder {
    @objc
    public func buildIgnoringErrors() -> SignalServiceProtosContactDetailsAvatar? {
        return self.buildInfallibly()
    }
}

#endif

// MARK: - SignalServiceProtosContactDetails

@objc
public class SignalServiceProtosContactDetails: NSObject, Codable, NSSecureCoding {

    fileprivate let proto: SignalServiceProtos_ContactDetails

    @objc
    public let avatar: SignalServiceProtosContactDetailsAvatar?

    @objc
    public var contactE164: String? {
        guard hasContactE164 else {
            return nil
        }
        return proto.contactE164
    }
    @objc
    public var hasContactE164: Bool {
        return proto.hasContactE164
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
    public var expireTimer: UInt32 {
        return proto.expireTimer
    }
    @objc
    public var hasExpireTimer: Bool {
        return proto.hasExpireTimer
    }

    @objc
    public var expireTimerVersion: UInt32 {
        return proto.expireTimerVersion
    }
    @objc
    public var hasExpireTimerVersion: Bool {
        return proto.hasExpireTimerVersion
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
                 avatar: SignalServiceProtosContactDetailsAvatar?) {
        self.proto = proto
        self.avatar = avatar
    }

    @objc
    public func serializedData() throws -> Data {
        return try self.proto.serializedData()
    }

    @objc
    public required convenience init(serializedData: Data) throws {
        let proto = try SignalServiceProtos_ContactDetails(serializedBytes: serializedData)
        self.init(proto)
    }

    fileprivate convenience init(_ proto: SignalServiceProtos_ContactDetails) {
        var avatar: SignalServiceProtosContactDetailsAvatar?
        if proto.hasAvatar {
            avatar = SignalServiceProtosContactDetailsAvatar(proto.avatar)
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

extension SignalServiceProtosContactDetails {
    @objc
    public static func builder() -> SignalServiceProtosContactDetailsBuilder {
        return SignalServiceProtosContactDetailsBuilder()
    }

    // asBuilder() constructs a builder that reflects the proto's contents.
    @objc
    public func asBuilder() -> SignalServiceProtosContactDetailsBuilder {
        let builder = SignalServiceProtosContactDetailsBuilder()
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
        if hasExpireTimer {
            builder.setExpireTimer(expireTimer)
        }
        if hasExpireTimerVersion {
            builder.setExpireTimerVersion(expireTimerVersion)
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
public class SignalServiceProtosContactDetailsBuilder: NSObject {

    private var proto = SignalServiceProtos_ContactDetails()

    @objc
    fileprivate override init() {}

    @objc
    @available(swift, obsoleted: 1.0)
    public func setContactE164(_ valueParam: String?) {
        guard let valueParam = valueParam else { return }
        proto.contactE164 = valueParam
    }

    public func setContactE164(_ valueParam: String) {
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
    public func setAvatar(_ valueParam: SignalServiceProtosContactDetailsAvatar?) {
        guard let valueParam = valueParam else { return }
        proto.avatar = valueParam.proto
    }

    public func setAvatar(_ valueParam: SignalServiceProtosContactDetailsAvatar) {
        proto.avatar = valueParam.proto
    }

    @objc
    public func setExpireTimer(_ valueParam: UInt32) {
        proto.expireTimer = valueParam
    }

    @objc
    public func setExpireTimerVersion(_ valueParam: UInt32) {
        proto.expireTimerVersion = valueParam
    }

    @objc
    public func setInboxPosition(_ valueParam: UInt32) {
        proto.inboxPosition = valueParam
    }

    public func setUnknownFields(_ unknownFields: SwiftProtobuf.UnknownStorage) {
        proto.unknownFields = unknownFields
    }

    @objc
    public func buildInfallibly() -> SignalServiceProtosContactDetails {
        return SignalServiceProtosContactDetails(proto)
    }

    @objc
    public func buildSerializedData() throws -> Data {
        return try SignalServiceProtosContactDetails(proto).serializedData()
    }
}

#if TESTABLE_BUILD

extension SignalServiceProtosContactDetails {
    @objc
    public func serializedDataIgnoringErrors() -> Data? {
        return try! self.serializedData()
    }
}

extension SignalServiceProtosContactDetailsBuilder {
    @objc
    public func buildIgnoringErrors() -> SignalServiceProtosContactDetails? {
        return self.buildInfallibly()
    }
}

#endif

// MARK: - SignalServiceProtosPackSticker

@objc
public class SignalServiceProtosPackSticker: NSObject, Codable, NSSecureCoding {

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
    public required convenience init(serializedData: Data) throws {
        let proto = try SignalServiceProtos_Pack.Sticker(serializedBytes: serializedData)
        try self.init(proto)
    }

    fileprivate convenience init(_ proto: SignalServiceProtos_Pack.Sticker) throws {
        guard proto.hasID else {
            throw SignalServiceProtosError.invalidProtobuf(description: "[\(Self.self)] missing required field: id")
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

extension SignalServiceProtosPackSticker {
    @objc
    public static func builder(id: UInt32) -> SignalServiceProtosPackStickerBuilder {
        return SignalServiceProtosPackStickerBuilder(id: id)
    }

    // asBuilder() constructs a builder that reflects the proto's contents.
    @objc
    public func asBuilder() -> SignalServiceProtosPackStickerBuilder {
        let builder = SignalServiceProtosPackStickerBuilder(id: id)
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
public class SignalServiceProtosPackStickerBuilder: NSObject {

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
    public func build() throws -> SignalServiceProtosPackSticker {
        return try SignalServiceProtosPackSticker(proto)
    }

    @objc
    public func buildSerializedData() throws -> Data {
        return try SignalServiceProtosPackSticker(proto).serializedData()
    }
}

#if TESTABLE_BUILD

extension SignalServiceProtosPackSticker {
    @objc
    public func serializedDataIgnoringErrors() -> Data? {
        return try! self.serializedData()
    }
}

extension SignalServiceProtosPackStickerBuilder {
    @objc
    public func buildIgnoringErrors() -> SignalServiceProtosPackSticker? {
        return try! self.build()
    }
}

#endif

// MARK: - SignalServiceProtosPack

@objc
public class SignalServiceProtosPack: NSObject, Codable, NSSecureCoding {

    fileprivate let proto: SignalServiceProtos_Pack

    @objc
    public let cover: SignalServiceProtosPackSticker?

    @objc
    public let stickers: [SignalServiceProtosPackSticker]

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
                 cover: SignalServiceProtosPackSticker?,
                 stickers: [SignalServiceProtosPackSticker]) {
        self.proto = proto
        self.cover = cover
        self.stickers = stickers
    }

    @objc
    public func serializedData() throws -> Data {
        return try self.proto.serializedData()
    }

    @objc
    public required convenience init(serializedData: Data) throws {
        let proto = try SignalServiceProtos_Pack(serializedBytes: serializedData)
        try self.init(proto)
    }

    fileprivate convenience init(_ proto: SignalServiceProtos_Pack) throws {
        var cover: SignalServiceProtosPackSticker?
        if proto.hasCover {
            cover = try SignalServiceProtosPackSticker(proto.cover)
        }

        var stickers: [SignalServiceProtosPackSticker] = []
        stickers = try proto.stickers.map { try SignalServiceProtosPackSticker($0) }

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

extension SignalServiceProtosPack {
    @objc
    public static func builder() -> SignalServiceProtosPackBuilder {
        return SignalServiceProtosPackBuilder()
    }

    // asBuilder() constructs a builder that reflects the proto's contents.
    @objc
    public func asBuilder() -> SignalServiceProtosPackBuilder {
        let builder = SignalServiceProtosPackBuilder()
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
public class SignalServiceProtosPackBuilder: NSObject {

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
    public func setCover(_ valueParam: SignalServiceProtosPackSticker?) {
        guard let valueParam = valueParam else { return }
        proto.cover = valueParam.proto
    }

    public func setCover(_ valueParam: SignalServiceProtosPackSticker) {
        proto.cover = valueParam.proto
    }

    @objc
    public func addStickers(_ valueParam: SignalServiceProtosPackSticker) {
        proto.stickers.append(valueParam.proto)
    }

    @objc
    public func setStickers(_ wrappedItems: [SignalServiceProtosPackSticker]) {
        proto.stickers = wrappedItems.map { $0.proto }
    }

    public func setUnknownFields(_ unknownFields: SwiftProtobuf.UnknownStorage) {
        proto.unknownFields = unknownFields
    }

    @objc
    public func build() throws -> SignalServiceProtosPack {
        return try SignalServiceProtosPack(proto)
    }

    @objc
    public func buildSerializedData() throws -> Data {
        return try SignalServiceProtosPack(proto).serializedData()
    }
}

#if TESTABLE_BUILD

extension SignalServiceProtosPack {
    @objc
    public func serializedDataIgnoringErrors() -> Data? {
        return try! self.serializedData()
    }
}

extension SignalServiceProtosPackBuilder {
    @objc
    public func buildIgnoringErrors() -> SignalServiceProtosPack? {
        return try! self.build()
    }
}

#endif

// MARK: - SignalServiceProtosPaymentAddressMobileCoin

@objc
public class SignalServiceProtosPaymentAddressMobileCoin: NSObject, Codable, NSSecureCoding {

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
    public required convenience init(serializedData: Data) throws {
        let proto = try SignalServiceProtos_PaymentAddress.MobileCoin(serializedBytes: serializedData)
        try self.init(proto)
    }

    fileprivate convenience init(_ proto: SignalServiceProtos_PaymentAddress.MobileCoin) throws {
        guard proto.hasPublicAddress else {
            throw SignalServiceProtosError.invalidProtobuf(description: "[\(Self.self)] missing required field: publicAddress")
        }
        let publicAddress = proto.publicAddress

        guard proto.hasSignature else {
            throw SignalServiceProtosError.invalidProtobuf(description: "[\(Self.self)] missing required field: signature")
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

extension SignalServiceProtosPaymentAddressMobileCoin {
    @objc
    public static func builder(publicAddress: Data, signature: Data) -> SignalServiceProtosPaymentAddressMobileCoinBuilder {
        return SignalServiceProtosPaymentAddressMobileCoinBuilder(publicAddress: publicAddress, signature: signature)
    }

    // asBuilder() constructs a builder that reflects the proto's contents.
    @objc
    public func asBuilder() -> SignalServiceProtosPaymentAddressMobileCoinBuilder {
        let builder = SignalServiceProtosPaymentAddressMobileCoinBuilder(publicAddress: publicAddress, signature: signature)
        if let _value = unknownFields {
            builder.setUnknownFields(_value)
        }
        return builder
    }
}

@objc
public class SignalServiceProtosPaymentAddressMobileCoinBuilder: NSObject {

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
    public func build() throws -> SignalServiceProtosPaymentAddressMobileCoin {
        return try SignalServiceProtosPaymentAddressMobileCoin(proto)
    }

    @objc
    public func buildSerializedData() throws -> Data {
        return try SignalServiceProtosPaymentAddressMobileCoin(proto).serializedData()
    }
}

#if TESTABLE_BUILD

extension SignalServiceProtosPaymentAddressMobileCoin {
    @objc
    public func serializedDataIgnoringErrors() -> Data? {
        return try! self.serializedData()
    }
}

extension SignalServiceProtosPaymentAddressMobileCoinBuilder {
    @objc
    public func buildIgnoringErrors() -> SignalServiceProtosPaymentAddressMobileCoin? {
        return try! self.build()
    }
}

#endif

// MARK: - SignalServiceProtosPaymentAddress

@objc
public class SignalServiceProtosPaymentAddress: NSObject, Codable, NSSecureCoding {

    fileprivate let proto: SignalServiceProtos_PaymentAddress

    @objc
    public let mobileCoin: SignalServiceProtosPaymentAddressMobileCoin?

    public var hasUnknownFields: Bool {
        return !proto.unknownFields.data.isEmpty
    }
    public var unknownFields: SwiftProtobuf.UnknownStorage? {
        guard hasUnknownFields else { return nil }
        return proto.unknownFields
    }

    private init(proto: SignalServiceProtos_PaymentAddress,
                 mobileCoin: SignalServiceProtosPaymentAddressMobileCoin?) {
        self.proto = proto
        self.mobileCoin = mobileCoin
    }

    @objc
    public func serializedData() throws -> Data {
        return try self.proto.serializedData()
    }

    @objc
    public required convenience init(serializedData: Data) throws {
        let proto = try SignalServiceProtos_PaymentAddress(serializedBytes: serializedData)
        try self.init(proto)
    }

    fileprivate convenience init(_ proto: SignalServiceProtos_PaymentAddress) throws {
        var mobileCoin: SignalServiceProtosPaymentAddressMobileCoin?
        if proto.hasMobileCoin {
            mobileCoin = try SignalServiceProtosPaymentAddressMobileCoin(proto.mobileCoin)
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

extension SignalServiceProtosPaymentAddress {
    @objc
    public static func builder() -> SignalServiceProtosPaymentAddressBuilder {
        return SignalServiceProtosPaymentAddressBuilder()
    }

    // asBuilder() constructs a builder that reflects the proto's contents.
    @objc
    public func asBuilder() -> SignalServiceProtosPaymentAddressBuilder {
        let builder = SignalServiceProtosPaymentAddressBuilder()
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
public class SignalServiceProtosPaymentAddressBuilder: NSObject {

    private var proto = SignalServiceProtos_PaymentAddress()

    @objc
    fileprivate override init() {}

    @objc
    @available(swift, obsoleted: 1.0)
    public func setMobileCoin(_ valueParam: SignalServiceProtosPaymentAddressMobileCoin?) {
        guard let valueParam = valueParam else { return }
        proto.mobileCoin = valueParam.proto
    }

    public func setMobileCoin(_ valueParam: SignalServiceProtosPaymentAddressMobileCoin) {
        proto.mobileCoin = valueParam.proto
    }

    public func setUnknownFields(_ unknownFields: SwiftProtobuf.UnknownStorage) {
        proto.unknownFields = unknownFields
    }

    @objc
    public func build() throws -> SignalServiceProtosPaymentAddress {
        return try SignalServiceProtosPaymentAddress(proto)
    }

    @objc
    public func buildSerializedData() throws -> Data {
        return try SignalServiceProtosPaymentAddress(proto).serializedData()
    }
}

#if TESTABLE_BUILD

extension SignalServiceProtosPaymentAddress {
    @objc
    public func serializedDataIgnoringErrors() -> Data? {
        return try! self.serializedData()
    }
}

extension SignalServiceProtosPaymentAddressBuilder {
    @objc
    public func buildIgnoringErrors() -> SignalServiceProtosPaymentAddress? {
        return try! self.build()
    }
}

#endif

// MARK: - SignalServiceProtosDecryptionErrorMessage

@objc
public class SignalServiceProtosDecryptionErrorMessage: NSObject, Codable, NSSecureCoding {

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
    public required convenience init(serializedData: Data) throws {
        let proto = try SignalServiceProtos_DecryptionErrorMessage(serializedBytes: serializedData)
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

extension SignalServiceProtosDecryptionErrorMessage {
    @objc
    public static func builder() -> SignalServiceProtosDecryptionErrorMessageBuilder {
        return SignalServiceProtosDecryptionErrorMessageBuilder()
    }

    // asBuilder() constructs a builder that reflects the proto's contents.
    @objc
    public func asBuilder() -> SignalServiceProtosDecryptionErrorMessageBuilder {
        let builder = SignalServiceProtosDecryptionErrorMessageBuilder()
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
public class SignalServiceProtosDecryptionErrorMessageBuilder: NSObject {

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
    public func buildInfallibly() -> SignalServiceProtosDecryptionErrorMessage {
        return SignalServiceProtosDecryptionErrorMessage(proto)
    }

    @objc
    public func buildSerializedData() throws -> Data {
        return try SignalServiceProtosDecryptionErrorMessage(proto).serializedData()
    }
}

#if TESTABLE_BUILD

extension SignalServiceProtosDecryptionErrorMessage {
    @objc
    public func serializedDataIgnoringErrors() -> Data? {
        return try! self.serializedData()
    }
}

extension SignalServiceProtosDecryptionErrorMessageBuilder {
    @objc
    public func buildIgnoringErrors() -> SignalServiceProtosDecryptionErrorMessage? {
        return self.buildInfallibly()
    }
}

#endif

// MARK: - SignalServiceProtosPniSignatureMessage

@objc
public class SignalServiceProtosPniSignatureMessage: NSObject, Codable, NSSecureCoding {

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
    public required convenience init(serializedData: Data) throws {
        let proto = try SignalServiceProtos_PniSignatureMessage(serializedBytes: serializedData)
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

extension SignalServiceProtosPniSignatureMessage {
    @objc
    public static func builder() -> SignalServiceProtosPniSignatureMessageBuilder {
        return SignalServiceProtosPniSignatureMessageBuilder()
    }

    // asBuilder() constructs a builder that reflects the proto's contents.
    @objc
    public func asBuilder() -> SignalServiceProtosPniSignatureMessageBuilder {
        let builder = SignalServiceProtosPniSignatureMessageBuilder()
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
public class SignalServiceProtosPniSignatureMessageBuilder: NSObject {

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
    public func buildInfallibly() -> SignalServiceProtosPniSignatureMessage {
        return SignalServiceProtosPniSignatureMessage(proto)
    }

    @objc
    public func buildSerializedData() throws -> Data {
        return try SignalServiceProtosPniSignatureMessage(proto).serializedData()
    }
}

#if TESTABLE_BUILD

extension SignalServiceProtosPniSignatureMessage {
    @objc
    public func serializedDataIgnoringErrors() -> Data? {
        return try! self.serializedData()
    }
}

extension SignalServiceProtosPniSignatureMessageBuilder {
    @objc
    public func buildIgnoringErrors() -> SignalServiceProtosPniSignatureMessage? {
        return self.buildInfallibly()
    }
}

#endif

// MARK: - SignalServiceProtosBodyRangeStyle

@objc
public enum SignalServiceProtosBodyRangeStyle: Int32 {
    case none = 0
    case bold = 1
    case italic = 2
    case spoiler = 3
    case strikethrough = 4
    case monospace = 5
}

private func SignalServiceProtosBodyRangeStyleWrap(_ value: SignalServiceProtos_BodyRange.Style) -> SignalServiceProtosBodyRangeStyle {
    switch value {
    case .none: return .none
    case .bold: return .bold
    case .italic: return .italic
    case .spoiler: return .spoiler
    case .strikethrough: return .strikethrough
    case .monospace: return .monospace
    }
}

private func SignalServiceProtosBodyRangeStyleUnwrap(_ value: SignalServiceProtosBodyRangeStyle) -> SignalServiceProtos_BodyRange.Style {
    switch value {
    case .none: return .none
    case .bold: return .bold
    case .italic: return .italic
    case .spoiler: return .spoiler
    case .strikethrough: return .strikethrough
    case .monospace: return .monospace
    }
}

// MARK: - SignalServiceProtosBodyRange

@objc
public class SignalServiceProtosBodyRange: NSObject, Codable, NSSecureCoding {

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

    public var style: SignalServiceProtosBodyRangeStyle? {
        guard hasStyle else {
            return nil
        }
        return SignalServiceProtosBodyRangeStyleWrap(proto.style)
    }
    // This "unwrapped" accessor should only be used if the "has value" accessor has already been checked.
    @objc
    public var unwrappedStyle: SignalServiceProtosBodyRangeStyle {
        if !hasStyle {
            // TODO: We could make this a crashing assert.
            owsFailDebug("Unsafe unwrap of missing optional: BodyRange.style.")
        }
        return SignalServiceProtosBodyRangeStyleWrap(proto.style)
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
    public required convenience init(serializedData: Data) throws {
        let proto = try SignalServiceProtos_BodyRange(serializedBytes: serializedData)
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

extension SignalServiceProtosBodyRange {
    @objc
    public static func builder() -> SignalServiceProtosBodyRangeBuilder {
        return SignalServiceProtosBodyRangeBuilder()
    }

    // asBuilder() constructs a builder that reflects the proto's contents.
    @objc
    public func asBuilder() -> SignalServiceProtosBodyRangeBuilder {
        let builder = SignalServiceProtosBodyRangeBuilder()
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
public class SignalServiceProtosBodyRangeBuilder: NSObject {

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
    public func setStyle(_ valueParam: SignalServiceProtosBodyRangeStyle) {
        proto.style = SignalServiceProtosBodyRangeStyleUnwrap(valueParam)
    }

    public func setUnknownFields(_ unknownFields: SwiftProtobuf.UnknownStorage) {
        proto.unknownFields = unknownFields
    }

    @objc
    public func buildInfallibly() -> SignalServiceProtosBodyRange {
        return SignalServiceProtosBodyRange(proto)
    }

    @objc
    public func buildSerializedData() throws -> Data {
        return try SignalServiceProtosBodyRange(proto).serializedData()
    }
}

#if TESTABLE_BUILD

extension SignalServiceProtosBodyRange {
    @objc
    public func serializedDataIgnoringErrors() -> Data? {
        return try! self.serializedData()
    }
}

extension SignalServiceProtosBodyRangeBuilder {
    @objc
    public func buildIgnoringErrors() -> SignalServiceProtosBodyRange? {
        return self.buildInfallibly()
    }
}

#endif

// MARK: - SignalServiceProtosEditMessage

@objc
public class SignalServiceProtosEditMessage: NSObject, Codable, NSSecureCoding {

    fileprivate let proto: SignalServiceProtos_EditMessage

    @objc
    public let dataMessage: SignalServiceProtosDataMessage?

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
                 dataMessage: SignalServiceProtosDataMessage?) {
        self.proto = proto
        self.dataMessage = dataMessage
    }

    @objc
    public func serializedData() throws -> Data {
        return try self.proto.serializedData()
    }

    @objc
    public required convenience init(serializedData: Data) throws {
        let proto = try SignalServiceProtos_EditMessage(serializedBytes: serializedData)
        try self.init(proto)
    }

    fileprivate convenience init(_ proto: SignalServiceProtos_EditMessage) throws {
        var dataMessage: SignalServiceProtosDataMessage?
        if proto.hasDataMessage {
            dataMessage = try SignalServiceProtosDataMessage(proto.dataMessage)
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

extension SignalServiceProtosEditMessage {
    @objc
    public static func builder() -> SignalServiceProtosEditMessageBuilder {
        return SignalServiceProtosEditMessageBuilder()
    }

    // asBuilder() constructs a builder that reflects the proto's contents.
    @objc
    public func asBuilder() -> SignalServiceProtosEditMessageBuilder {
        let builder = SignalServiceProtosEditMessageBuilder()
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
public class SignalServiceProtosEditMessageBuilder: NSObject {

    private var proto = SignalServiceProtos_EditMessage()

    @objc
    fileprivate override init() {}

    @objc
    public func setTargetSentTimestamp(_ valueParam: UInt64) {
        proto.targetSentTimestamp = valueParam
    }

    @objc
    @available(swift, obsoleted: 1.0)
    public func setDataMessage(_ valueParam: SignalServiceProtosDataMessage?) {
        guard let valueParam = valueParam else { return }
        proto.dataMessage = valueParam.proto
    }

    public func setDataMessage(_ valueParam: SignalServiceProtosDataMessage) {
        proto.dataMessage = valueParam.proto
    }

    public func setUnknownFields(_ unknownFields: SwiftProtobuf.UnknownStorage) {
        proto.unknownFields = unknownFields
    }

    @objc
    public func build() throws -> SignalServiceProtosEditMessage {
        return try SignalServiceProtosEditMessage(proto)
    }

    @objc
    public func buildSerializedData() throws -> Data {
        return try SignalServiceProtosEditMessage(proto).serializedData()
    }
}

#if TESTABLE_BUILD

extension SignalServiceProtosEditMessage {
    @objc
    public func serializedDataIgnoringErrors() -> Data? {
        return try! self.serializedData()
    }
}

extension SignalServiceProtosEditMessageBuilder {
    @objc
    public func buildIgnoringErrors() -> SignalServiceProtosEditMessage? {
        return try! self.build()
    }
}

#endif
