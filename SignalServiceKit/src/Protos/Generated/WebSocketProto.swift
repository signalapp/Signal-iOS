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

        @objc public func setRequestId(_ valueParam: UInt64) {
            proto.requestId = valueParam
        }

        @objc public func build() throws -> WebSocketProtoWebSocketRequestMessage {
            let wrapper = try WebSocketProtoWebSocketRequestMessage.parseProto(proto)
            return wrapper
        }
    }

    fileprivate let proto: WebSocketProtos_WebSocketRequestMessage

    @objc public var verb: String? {
        guard proto.hasVerb else {
            return nil
        }
        return proto.verb
    }
    @objc public var hasVerb: Bool {
        return proto.hasVerb
    }

    @objc public var path: String? {
        guard proto.hasPath else {
            return nil
        }
        return proto.path
    }
    @objc public var hasPath: Bool {
        return proto.hasPath
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

    @objc public var headers: [String] {
        return proto.headers
    }

    @objc public var requestId: UInt64 {
        return proto.requestId
    }
    @objc public var hasRequestId: Bool {
        return proto.hasRequestId
    }

    private init(proto: WebSocketProtos_WebSocketRequestMessage) {
        self.proto = proto
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
        // MARK: - Begin Validation Logic for WebSocketProtoWebSocketRequestMessage -

        // MARK: - End Validation Logic for WebSocketProtoWebSocketRequestMessage -

        let result = WebSocketProtoWebSocketRequestMessage(proto: proto)
        return result
    }
}

// MARK: - WebSocketProtoWebSocketResponseMessage

@objc public class WebSocketProtoWebSocketResponseMessage: NSObject {

    // MARK: - WebSocketProtoWebSocketResponseMessageBuilder

    @objc public class WebSocketProtoWebSocketResponseMessageBuilder: NSObject {

        private var proto = WebSocketProtos_WebSocketResponseMessage()

        @objc public override init() {}

        @objc public func setRequestId(_ valueParam: UInt64) {
            proto.requestId = valueParam
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

        @objc public func setBody(_ valueParam: Data) {
            proto.body = valueParam
        }

        @objc public func build() throws -> WebSocketProtoWebSocketResponseMessage {
            let wrapper = try WebSocketProtoWebSocketResponseMessage.parseProto(proto)
            return wrapper
        }
    }

    fileprivate let proto: WebSocketProtos_WebSocketResponseMessage

    @objc public var requestId: UInt64 {
        return proto.requestId
    }
    @objc public var hasRequestId: Bool {
        return proto.hasRequestId
    }

    @objc public var status: UInt32 {
        return proto.status
    }
    @objc public var hasStatus: Bool {
        return proto.hasStatus
    }

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

    private init(proto: WebSocketProtos_WebSocketResponseMessage) {
        self.proto = proto
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
        // MARK: - Begin Validation Logic for WebSocketProtoWebSocketResponseMessage -

        // MARK: - End Validation Logic for WebSocketProtoWebSocketResponseMessage -

        let result = WebSocketProtoWebSocketResponseMessage(proto: proto)
        return result
    }
}

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
            let wrapper = try WebSocketProtoWebSocketMessage.parseProto(proto)
            return wrapper
        }
    }

    fileprivate let proto: WebSocketProtos_WebSocketMessage

    @objc public let request: WebSocketProtoWebSocketRequestMessage?
    @objc public let response: WebSocketProtoWebSocketResponseMessage?

    @objc public var type: WebSocketProtoWebSocketMessageType {
        return WebSocketProtoWebSocketMessage.WebSocketProtoWebSocketMessageTypeWrap(proto.type)
    }
    @objc public var hasType: Bool {
        return proto.hasType
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

    @objc public class func parseData(_ serializedData: Data) throws -> WebSocketProtoWebSocketMessage {
        let proto = try WebSocketProtos_WebSocketMessage(serializedData: serializedData)
        return try parseProto(proto)
    }

    fileprivate class func parseProto(_ proto: WebSocketProtos_WebSocketMessage) throws -> WebSocketProtoWebSocketMessage {
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
                                                    request: request,
                                                    response: response)
        return result
    }
}
