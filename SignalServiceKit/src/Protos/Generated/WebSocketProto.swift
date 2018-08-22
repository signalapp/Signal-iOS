//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

import Foundation

// WARNING: This code is generated. Only edit within the markers.

public enum WebSocketProtoError: Error {
    case invalidProtobuf(description: String)
}

// MARK: - WebSocketProtoWebSocketRequestMessage

@objc public class WebSocketProtoWebSocketRequestMessage: NSObject {

    // MARK: - WebSocketProtoWebSocketRequestMessageBuilder

    @objc public class WebSocketProtoWebSocketRequestMessageBuilder: NSObject {

        private var proto = WebSocketProtos_WebSocketRequestMessage()

        @objc public override init() {}

        // Initializer for required fields
        @objc public init(verb: String, path: String, requestID: UInt64) {
            super.init()

            setVerb(verb)
            setPath(path)
            setRequestID(requestID)
        }

        @objc public func setVerb(_ valueParam: String) {
            proto.verb = valueParam
        }

        @objc public func setPath(_ valueParam: String) {
            proto.path = valueParam
        }

        @objc public func setBody(_ valueParam: Data) {
            proto.body = valueParam
        }

        @objc public func addHeaders(_ valueParam: String) {
            var items = proto.headers
            items.append(valueParam)
            proto.headers = items
        }

        @objc public func setHeaders(_ wrappedItems: [String]) {
            proto.headers = wrappedItems
        }

        @objc public func setRequestID(_ valueParam: UInt64) {
            proto.requestID = valueParam
        }

        @objc public func build() throws -> WebSocketProtoWebSocketRequestMessage {
            return try WebSocketProtoWebSocketRequestMessage.parseProto(proto)
        }

        @objc public func buildSerializedData() throws -> Data {
            return try WebSocketProtoWebSocketRequestMessage.parseProto(proto).serializedData()
        }
    }

    fileprivate let proto: WebSocketProtos_WebSocketRequestMessage

    @objc public let verb: String

    @objc public let path: String

    @objc public let requestID: UInt64

    @objc public var body: Data? {
        guard proto.hasBody else {
            return nil
        }
        return proto.body
    }
    @objc public var hasBody: Bool {
        return proto.hasBody
    }

    @objc public var headers: [String] {
        return proto.headers
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

    @objc public class func parseData(_ serializedData: Data) throws -> WebSocketProtoWebSocketRequestMessage {
        let proto = try WebSocketProtos_WebSocketRequestMessage(serializedData: serializedData)
        return try parseProto(proto)
    }

    fileprivate class func parseProto(_ proto: WebSocketProtos_WebSocketRequestMessage) throws -> WebSocketProtoWebSocketRequestMessage {
        guard proto.hasVerb else {
            throw WebSocketProtoError.invalidProtobuf(description: "\(logTag) missing required field: verb")
        }
        let verb = proto.verb

        guard proto.hasPath else {
            throw WebSocketProtoError.invalidProtobuf(description: "\(logTag) missing required field: path")
        }
        let path = proto.path

        guard proto.hasRequestID else {
            throw WebSocketProtoError.invalidProtobuf(description: "\(logTag) missing required field: requestID")
        }
        let requestID = proto.requestID

        // MARK: - Begin Validation Logic for WebSocketProtoWebSocketRequestMessage -

        // MARK: - End Validation Logic for WebSocketProtoWebSocketRequestMessage -

        let result = WebSocketProtoWebSocketRequestMessage(proto: proto,
                                                           verb: verb,
                                                           path: path,
                                                           requestID: requestID)
        return result
    }
}

#if DEBUG

extension WebSocketProtoWebSocketRequestMessage {
    @objc public func serializedDataIgnoringErrors() -> Data? {
        return try! self.serializedData()
    }
}

extension WebSocketProtoWebSocketRequestMessage.WebSocketProtoWebSocketRequestMessageBuilder {
    @objc public func buildIgnoringErrors() -> WebSocketProtoWebSocketRequestMessage? {
        return try! self.build()
    }
}

#endif

// MARK: - WebSocketProtoWebSocketResponseMessage

@objc public class WebSocketProtoWebSocketResponseMessage: NSObject {

    // MARK: - WebSocketProtoWebSocketResponseMessageBuilder

    @objc public class WebSocketProtoWebSocketResponseMessageBuilder: NSObject {

        private var proto = WebSocketProtos_WebSocketResponseMessage()

        @objc public override init() {}

        // Initializer for required fields
        @objc public init(requestID: UInt64, status: UInt32) {
            super.init()

            setRequestID(requestID)
            setStatus(status)
        }

        @objc public func setRequestID(_ valueParam: UInt64) {
            proto.requestID = valueParam
        }

        @objc public func setStatus(_ valueParam: UInt32) {
            proto.status = valueParam
        }

        @objc public func setMessage(_ valueParam: String) {
            proto.message = valueParam
        }

        @objc public func addHeaders(_ valueParam: String) {
            var items = proto.headers
            items.append(valueParam)
            proto.headers = items
        }

        @objc public func setHeaders(_ wrappedItems: [String]) {
            proto.headers = wrappedItems
        }

        @objc public func setBody(_ valueParam: Data) {
            proto.body = valueParam
        }

        @objc public func build() throws -> WebSocketProtoWebSocketResponseMessage {
            return try WebSocketProtoWebSocketResponseMessage.parseProto(proto)
        }

        @objc public func buildSerializedData() throws -> Data {
            return try WebSocketProtoWebSocketResponseMessage.parseProto(proto).serializedData()
        }
    }

    fileprivate let proto: WebSocketProtos_WebSocketResponseMessage

    @objc public let requestID: UInt64

    @objc public let status: UInt32

    @objc public var message: String? {
        guard proto.hasMessage else {
            return nil
        }
        return proto.message
    }
    @objc public var hasMessage: Bool {
        return proto.hasMessage
    }

    @objc public var headers: [String] {
        return proto.headers
    }

    @objc public var body: Data? {
        guard proto.hasBody else {
            return nil
        }
        return proto.body
    }
    @objc public var hasBody: Bool {
        return proto.hasBody
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

    @objc public class func parseData(_ serializedData: Data) throws -> WebSocketProtoWebSocketResponseMessage {
        let proto = try WebSocketProtos_WebSocketResponseMessage(serializedData: serializedData)
        return try parseProto(proto)
    }

    fileprivate class func parseProto(_ proto: WebSocketProtos_WebSocketResponseMessage) throws -> WebSocketProtoWebSocketResponseMessage {
        guard proto.hasRequestID else {
            throw WebSocketProtoError.invalidProtobuf(description: "\(logTag) missing required field: requestID")
        }
        let requestID = proto.requestID

        guard proto.hasStatus else {
            throw WebSocketProtoError.invalidProtobuf(description: "\(logTag) missing required field: status")
        }
        let status = proto.status

        // MARK: - Begin Validation Logic for WebSocketProtoWebSocketResponseMessage -

        // MARK: - End Validation Logic for WebSocketProtoWebSocketResponseMessage -

        let result = WebSocketProtoWebSocketResponseMessage(proto: proto,
                                                            requestID: requestID,
                                                            status: status)
        return result
    }
}

#if DEBUG

extension WebSocketProtoWebSocketResponseMessage {
    @objc public func serializedDataIgnoringErrors() -> Data? {
        return try! self.serializedData()
    }
}

extension WebSocketProtoWebSocketResponseMessage.WebSocketProtoWebSocketResponseMessageBuilder {
    @objc public func buildIgnoringErrors() -> WebSocketProtoWebSocketResponseMessage? {
        return try! self.build()
    }
}

#endif

// MARK: - WebSocketProtoWebSocketMessage

@objc public class WebSocketProtoWebSocketMessage: NSObject {

    // MARK: - WebSocketProtoWebSocketMessageType

    @objc public enum WebSocketProtoWebSocketMessageType: Int32 {
        case unknown = 0
        case request = 1
        case response = 2
    }

    private class func WebSocketProtoWebSocketMessageTypeWrap(_ value: WebSocketProtos_WebSocketMessage.TypeEnum) -> WebSocketProtoWebSocketMessageType {
        switch value {
        case .unknown: return .unknown
        case .request: return .request
        case .response: return .response
        }
    }

    private class func WebSocketProtoWebSocketMessageTypeUnwrap(_ value: WebSocketProtoWebSocketMessageType) -> WebSocketProtos_WebSocketMessage.TypeEnum {
        switch value {
        case .unknown: return .unknown
        case .request: return .request
        case .response: return .response
        }
    }

    // MARK: - WebSocketProtoWebSocketMessageBuilder

    @objc public class WebSocketProtoWebSocketMessageBuilder: NSObject {

        private var proto = WebSocketProtos_WebSocketMessage()

        @objc public override init() {}

        // Initializer for required fields
        @objc public init(type: WebSocketProtoWebSocketMessageType) {
            super.init()

            setType(type)
        }

        @objc public func setType(_ valueParam: WebSocketProtoWebSocketMessageType) {
            proto.type = WebSocketProtoWebSocketMessageTypeUnwrap(valueParam)
        }

        @objc public func setRequest(_ valueParam: WebSocketProtoWebSocketRequestMessage) {
            proto.request = valueParam.proto
        }

        @objc public func setResponse(_ valueParam: WebSocketProtoWebSocketResponseMessage) {
            proto.response = valueParam.proto
        }

        @objc public func build() throws -> WebSocketProtoWebSocketMessage {
            return try WebSocketProtoWebSocketMessage.parseProto(proto)
        }

        @objc public func buildSerializedData() throws -> Data {
            return try WebSocketProtoWebSocketMessage.parseProto(proto).serializedData()
        }
    }

    fileprivate let proto: WebSocketProtos_WebSocketMessage

    @objc public let type: WebSocketProtoWebSocketMessageType

    @objc public let request: WebSocketProtoWebSocketRequestMessage?

    @objc public let response: WebSocketProtoWebSocketResponseMessage?

    private init(proto: WebSocketProtos_WebSocketMessage,
                 type: WebSocketProtoWebSocketMessageType,
                 request: WebSocketProtoWebSocketRequestMessage?,
                 response: WebSocketProtoWebSocketResponseMessage?) {
        self.proto = proto
        self.type = type
        self.request = request
        self.response = response
    }

    @objc
    public func serializedData() throws -> Data {
        return try self.proto.serializedData()
    }

    @objc public class func parseData(_ serializedData: Data) throws -> WebSocketProtoWebSocketMessage {
        let proto = try WebSocketProtos_WebSocketMessage(serializedData: serializedData)
        return try parseProto(proto)
    }

    fileprivate class func parseProto(_ proto: WebSocketProtos_WebSocketMessage) throws -> WebSocketProtoWebSocketMessage {
        guard proto.hasType else {
            throw WebSocketProtoError.invalidProtobuf(description: "\(logTag) missing required field: type")
        }
        let type = WebSocketProtoWebSocketMessageTypeWrap(proto.type)

        var request: WebSocketProtoWebSocketRequestMessage? = nil
        if proto.hasRequest {
            request = try WebSocketProtoWebSocketRequestMessage.parseProto(proto.request)
        }

        var response: WebSocketProtoWebSocketResponseMessage? = nil
        if proto.hasResponse {
            response = try WebSocketProtoWebSocketResponseMessage.parseProto(proto.response)
        }

        // MARK: - Begin Validation Logic for WebSocketProtoWebSocketMessage -

        // MARK: - End Validation Logic for WebSocketProtoWebSocketMessage -

        let result = WebSocketProtoWebSocketMessage(proto: proto,
                                                    type: type,
                                                    request: request,
                                                    response: response)
        return result
    }
}

#if DEBUG

extension WebSocketProtoWebSocketMessage {
    @objc public func serializedDataIgnoringErrors() -> Data? {
        return try! self.serializedData()
    }
}

extension WebSocketProtoWebSocketMessage.WebSocketProtoWebSocketMessageBuilder {
    @objc public func buildIgnoringErrors() -> WebSocketProtoWebSocketMessage? {
        return try! self.build()
    }
}

#endif
