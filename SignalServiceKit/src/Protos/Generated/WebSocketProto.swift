//
//  Copyright (c) 2020 Open Whisper Systems. All rights reserved.
//

import Foundation
import SignalCoreKit
import SwiftProtobuf

// WARNING: This code is generated. Only edit within the markers.

public enum WebSocketProtoError: Error {
    case invalidProtobuf(description: String)
}

// MARK: - WebSocketProtoWebSocketRequestMessage

@objc
public class WebSocketProtoWebSocketRequestMessage: NSObject, Codable {

    // MARK: - WebSocketProtoWebSocketRequestMessageBuilder

    @objc
    public class func builder(verb: String, path: String, requestID: UInt64) -> WebSocketProtoWebSocketRequestMessageBuilder {
        return WebSocketProtoWebSocketRequestMessageBuilder(verb: verb, path: path, requestID: requestID)
    }

    // asBuilder() constructs a builder that reflects the proto's contents.
    @objc
    public func asBuilder() -> WebSocketProtoWebSocketRequestMessageBuilder {
        let builder = WebSocketProtoWebSocketRequestMessageBuilder(verb: verb, path: path, requestID: requestID)
        if let _value = body {
            builder.setBody(_value)
        }
        builder.setHeaders(headers)
        if let _value = unknownFields {
            builder.setUnknownFields(_value)
        }
        return builder
    }

    @objc
    public class WebSocketProtoWebSocketRequestMessageBuilder: NSObject {

        private var proto = WebSocketProtos_WebSocketRequestMessage()

        @objc
        fileprivate override init() {}

        @objc
        fileprivate init(verb: String, path: String, requestID: UInt64) {
            super.init()

            setVerb(verb)
            setPath(path)
            setRequestID(requestID)
        }

        @objc
        @available(swift, obsoleted: 1.0)
        public func setVerb(_ valueParam: String?) {
            guard let valueParam = valueParam else { return }
            proto.verb = valueParam
        }

        public func setVerb(_ valueParam: String) {
            proto.verb = valueParam
        }

        @objc
        @available(swift, obsoleted: 1.0)
        public func setPath(_ valueParam: String?) {
            guard let valueParam = valueParam else { return }
            proto.path = valueParam
        }

        public func setPath(_ valueParam: String) {
            proto.path = valueParam
        }

        @objc
        @available(swift, obsoleted: 1.0)
        public func setBody(_ valueParam: Data?) {
            guard let valueParam = valueParam else { return }
            proto.body = valueParam
        }

        public func setBody(_ valueParam: Data) {
            proto.body = valueParam
        }

        @objc
        public func addHeaders(_ valueParam: String) {
            var items = proto.headers
            items.append(valueParam)
            proto.headers = items
        }

        @objc
        public func setHeaders(_ wrappedItems: [String]) {
            proto.headers = wrappedItems
        }

        @objc
        public func setRequestID(_ valueParam: UInt64) {
            proto.requestID = valueParam
        }

        public func setUnknownFields(_ unknownFields: SwiftProtobuf.UnknownStorage) {
            proto.unknownFields = unknownFields
        }

        @objc
        public func build() throws -> WebSocketProtoWebSocketRequestMessage {
            return try WebSocketProtoWebSocketRequestMessage(proto)
        }

        @objc
        public func buildSerializedData() throws -> Data {
            return try WebSocketProtoWebSocketRequestMessage(proto).serializedData()
        }
    }

    fileprivate let proto: WebSocketProtos_WebSocketRequestMessage

    @objc
    public let verb: String

    @objc
    public let path: String

    @objc
    public let requestID: UInt64

    @objc
    public var body: Data? {
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
    public var headers: [String] {
        return proto.headers
    }

    public var hasUnknownFields: Bool {
        return !proto.unknownFields.data.isEmpty
    }
    public var unknownFields: SwiftProtobuf.UnknownStorage? {
        guard hasUnknownFields else { return nil }
        return proto.unknownFields
    }

    private init(proto: WebSocketProtos_WebSocketRequestMessage,
                 verb: String,
                 path: String,
                 requestID: UInt64) {
        self.proto = proto
        self.verb = verb
        self.path = path
        self.requestID = requestID
    }

    @objc
    public func serializedData() throws -> Data {
        return try self.proto.serializedData()
    }

    @objc
    public convenience init(serializedData: Data) throws {
        let proto = try WebSocketProtos_WebSocketRequestMessage(serializedData: serializedData)
        try self.init(proto)
    }

    fileprivate convenience init(_ proto: WebSocketProtos_WebSocketRequestMessage) throws {
        guard proto.hasVerb else {
            throw WebSocketProtoError.invalidProtobuf(description: "\(Self.logTag) missing required field: verb")
        }
        let verb = proto.verb

        guard proto.hasPath else {
            throw WebSocketProtoError.invalidProtobuf(description: "\(Self.logTag) missing required field: path")
        }
        let path = proto.path

        guard proto.hasRequestID else {
            throw WebSocketProtoError.invalidProtobuf(description: "\(Self.logTag) missing required field: requestID")
        }
        let requestID = proto.requestID

        // MARK: - Begin Validation Logic for WebSocketProtoWebSocketRequestMessage -

        // MARK: - End Validation Logic for WebSocketProtoWebSocketRequestMessage -

        self.init(proto: proto,
                  verb: verb,
                  path: path,
                  requestID: requestID)
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

    @objc
    public override var debugDescription: String {
        return "\(proto)"
    }
}

#if DEBUG

extension WebSocketProtoWebSocketRequestMessage {
    @objc
    public func serializedDataIgnoringErrors() -> Data? {
        return try! self.serializedData()
    }
}

extension WebSocketProtoWebSocketRequestMessage.WebSocketProtoWebSocketRequestMessageBuilder {
    @objc
    public func buildIgnoringErrors() -> WebSocketProtoWebSocketRequestMessage? {
        return try! self.build()
    }
}

#endif

// MARK: - WebSocketProtoWebSocketResponseMessage

@objc
public class WebSocketProtoWebSocketResponseMessage: NSObject, Codable {

    // MARK: - WebSocketProtoWebSocketResponseMessageBuilder

    @objc
    public class func builder(requestID: UInt64, status: UInt32) -> WebSocketProtoWebSocketResponseMessageBuilder {
        return WebSocketProtoWebSocketResponseMessageBuilder(requestID: requestID, status: status)
    }

    // asBuilder() constructs a builder that reflects the proto's contents.
    @objc
    public func asBuilder() -> WebSocketProtoWebSocketResponseMessageBuilder {
        let builder = WebSocketProtoWebSocketResponseMessageBuilder(requestID: requestID, status: status)
        if let _value = message {
            builder.setMessage(_value)
        }
        builder.setHeaders(headers)
        if let _value = body {
            builder.setBody(_value)
        }
        if let _value = unknownFields {
            builder.setUnknownFields(_value)
        }
        return builder
    }

    @objc
    public class WebSocketProtoWebSocketResponseMessageBuilder: NSObject {

        private var proto = WebSocketProtos_WebSocketResponseMessage()

        @objc
        fileprivate override init() {}

        @objc
        fileprivate init(requestID: UInt64, status: UInt32) {
            super.init()

            setRequestID(requestID)
            setStatus(status)
        }

        @objc
        public func setRequestID(_ valueParam: UInt64) {
            proto.requestID = valueParam
        }

        @objc
        public func setStatus(_ valueParam: UInt32) {
            proto.status = valueParam
        }

        @objc
        @available(swift, obsoleted: 1.0)
        public func setMessage(_ valueParam: String?) {
            guard let valueParam = valueParam else { return }
            proto.message = valueParam
        }

        public func setMessage(_ valueParam: String) {
            proto.message = valueParam
        }

        @objc
        public func addHeaders(_ valueParam: String) {
            var items = proto.headers
            items.append(valueParam)
            proto.headers = items
        }

        @objc
        public func setHeaders(_ wrappedItems: [String]) {
            proto.headers = wrappedItems
        }

        @objc
        @available(swift, obsoleted: 1.0)
        public func setBody(_ valueParam: Data?) {
            guard let valueParam = valueParam else { return }
            proto.body = valueParam
        }

        public func setBody(_ valueParam: Data) {
            proto.body = valueParam
        }

        public func setUnknownFields(_ unknownFields: SwiftProtobuf.UnknownStorage) {
            proto.unknownFields = unknownFields
        }

        @objc
        public func build() throws -> WebSocketProtoWebSocketResponseMessage {
            return try WebSocketProtoWebSocketResponseMessage(proto)
        }

        @objc
        public func buildSerializedData() throws -> Data {
            return try WebSocketProtoWebSocketResponseMessage(proto).serializedData()
        }
    }

    fileprivate let proto: WebSocketProtos_WebSocketResponseMessage

    @objc
    public let requestID: UInt64

    @objc
    public let status: UInt32

    @objc
    public var message: String? {
        guard hasMessage else {
            return nil
        }
        return proto.message
    }
    @objc
    public var hasMessage: Bool {
        return proto.hasMessage
    }

    @objc
    public var headers: [String] {
        return proto.headers
    }

    @objc
    public var body: Data? {
        guard hasBody else {
            return nil
        }
        return proto.body
    }
    @objc
    public var hasBody: Bool {
        return proto.hasBody
    }

    public var hasUnknownFields: Bool {
        return !proto.unknownFields.data.isEmpty
    }
    public var unknownFields: SwiftProtobuf.UnknownStorage? {
        guard hasUnknownFields else { return nil }
        return proto.unknownFields
    }

    private init(proto: WebSocketProtos_WebSocketResponseMessage,
                 requestID: UInt64,
                 status: UInt32) {
        self.proto = proto
        self.requestID = requestID
        self.status = status
    }

    @objc
    public func serializedData() throws -> Data {
        return try self.proto.serializedData()
    }

    @objc
    public convenience init(serializedData: Data) throws {
        let proto = try WebSocketProtos_WebSocketResponseMessage(serializedData: serializedData)
        try self.init(proto)
    }

    fileprivate convenience init(_ proto: WebSocketProtos_WebSocketResponseMessage) throws {
        guard proto.hasRequestID else {
            throw WebSocketProtoError.invalidProtobuf(description: "\(Self.logTag) missing required field: requestID")
        }
        let requestID = proto.requestID

        guard proto.hasStatus else {
            throw WebSocketProtoError.invalidProtobuf(description: "\(Self.logTag) missing required field: status")
        }
        let status = proto.status

        // MARK: - Begin Validation Logic for WebSocketProtoWebSocketResponseMessage -

        // MARK: - End Validation Logic for WebSocketProtoWebSocketResponseMessage -

        self.init(proto: proto,
                  requestID: requestID,
                  status: status)
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

    @objc
    public override var debugDescription: String {
        return "\(proto)"
    }
}

#if DEBUG

extension WebSocketProtoWebSocketResponseMessage {
    @objc
    public func serializedDataIgnoringErrors() -> Data? {
        return try! self.serializedData()
    }
}

extension WebSocketProtoWebSocketResponseMessage.WebSocketProtoWebSocketResponseMessageBuilder {
    @objc
    public func buildIgnoringErrors() -> WebSocketProtoWebSocketResponseMessage? {
        return try! self.build()
    }
}

#endif

// MARK: - WebSocketProtoWebSocketMessageType

@objc
public enum WebSocketProtoWebSocketMessageType: Int32 {
    case unknown = 0
    case request = 1
    case response = 2
}

private func WebSocketProtoWebSocketMessageTypeWrap(_ value: WebSocketProtos_WebSocketMessage.TypeEnum) -> WebSocketProtoWebSocketMessageType {
    switch value {
    case .unknown: return .unknown
    case .request: return .request
    case .response: return .response
    }
}

private func WebSocketProtoWebSocketMessageTypeUnwrap(_ value: WebSocketProtoWebSocketMessageType) -> WebSocketProtos_WebSocketMessage.TypeEnum {
    switch value {
    case .unknown: return .unknown
    case .request: return .request
    case .response: return .response
    }
}

// MARK: - WebSocketProtoWebSocketMessage

@objc
public class WebSocketProtoWebSocketMessage: NSObject, Codable {

    // MARK: - WebSocketProtoWebSocketMessageBuilder

    @objc
    public class func builder() -> WebSocketProtoWebSocketMessageBuilder {
        return WebSocketProtoWebSocketMessageBuilder()
    }

    // asBuilder() constructs a builder that reflects the proto's contents.
    @objc
    public func asBuilder() -> WebSocketProtoWebSocketMessageBuilder {
        let builder = WebSocketProtoWebSocketMessageBuilder()
        if let _value = type {
            builder.setType(_value)
        }
        if let _value = request {
            builder.setRequest(_value)
        }
        if let _value = response {
            builder.setResponse(_value)
        }
        if let _value = unknownFields {
            builder.setUnknownFields(_value)
        }
        return builder
    }

    @objc
    public class WebSocketProtoWebSocketMessageBuilder: NSObject {

        private var proto = WebSocketProtos_WebSocketMessage()

        @objc
        fileprivate override init() {}

        @objc
        public func setType(_ valueParam: WebSocketProtoWebSocketMessageType) {
            proto.type = WebSocketProtoWebSocketMessageTypeUnwrap(valueParam)
        }

        @objc
        @available(swift, obsoleted: 1.0)
        public func setRequest(_ valueParam: WebSocketProtoWebSocketRequestMessage?) {
            guard let valueParam = valueParam else { return }
            proto.request = valueParam.proto
        }

        public func setRequest(_ valueParam: WebSocketProtoWebSocketRequestMessage) {
            proto.request = valueParam.proto
        }

        @objc
        @available(swift, obsoleted: 1.0)
        public func setResponse(_ valueParam: WebSocketProtoWebSocketResponseMessage?) {
            guard let valueParam = valueParam else { return }
            proto.response = valueParam.proto
        }

        public func setResponse(_ valueParam: WebSocketProtoWebSocketResponseMessage) {
            proto.response = valueParam.proto
        }

        public func setUnknownFields(_ unknownFields: SwiftProtobuf.UnknownStorage) {
            proto.unknownFields = unknownFields
        }

        @objc
        public func build() throws -> WebSocketProtoWebSocketMessage {
            return try WebSocketProtoWebSocketMessage(proto)
        }

        @objc
        public func buildSerializedData() throws -> Data {
            return try WebSocketProtoWebSocketMessage(proto).serializedData()
        }
    }

    fileprivate let proto: WebSocketProtos_WebSocketMessage

    @objc
    public let request: WebSocketProtoWebSocketRequestMessage?

    @objc
    public let response: WebSocketProtoWebSocketResponseMessage?

    public var type: WebSocketProtoWebSocketMessageType? {
        guard hasType else {
            return nil
        }
        return WebSocketProtoWebSocketMessageTypeWrap(proto.type)
    }
    // This "unwrapped" accessor should only be used if the "has value" accessor has already been checked.
    @objc
    public var unwrappedType: WebSocketProtoWebSocketMessageType {
        if !hasType {
            // TODO: We could make this a crashing assert.
            owsFailDebug("Unsafe unwrap of missing optional: WebSocketMessage.type.")
        }
        return WebSocketProtoWebSocketMessageTypeWrap(proto.type)
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

    private init(proto: WebSocketProtos_WebSocketMessage,
                 request: WebSocketProtoWebSocketRequestMessage?,
                 response: WebSocketProtoWebSocketResponseMessage?) {
        self.proto = proto
        self.request = request
        self.response = response
    }

    @objc
    public func serializedData() throws -> Data {
        return try self.proto.serializedData()
    }

    @objc
    public convenience init(serializedData: Data) throws {
        let proto = try WebSocketProtos_WebSocketMessage(serializedData: serializedData)
        try self.init(proto)
    }

    fileprivate convenience init(_ proto: WebSocketProtos_WebSocketMessage) throws {
        var request: WebSocketProtoWebSocketRequestMessage?
        if proto.hasRequest {
            request = try WebSocketProtoWebSocketRequestMessage(proto.request)
        }

        var response: WebSocketProtoWebSocketResponseMessage?
        if proto.hasResponse {
            response = try WebSocketProtoWebSocketResponseMessage(proto.response)
        }

        // MARK: - Begin Validation Logic for WebSocketProtoWebSocketMessage -

        // MARK: - End Validation Logic for WebSocketProtoWebSocketMessage -

        self.init(proto: proto,
                  request: request,
                  response: response)
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

    @objc
    public override var debugDescription: String {
        return "\(proto)"
    }
}

#if DEBUG

extension WebSocketProtoWebSocketMessage {
    @objc
    public func serializedDataIgnoringErrors() -> Data? {
        return try! self.serializedData()
    }
}

extension WebSocketProtoWebSocketMessage.WebSocketProtoWebSocketMessageBuilder {
    @objc
    public func buildIgnoringErrors() -> WebSocketProtoWebSocketMessage? {
        return try! self.build()
    }
}

#endif
