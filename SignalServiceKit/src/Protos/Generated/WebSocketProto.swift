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

    @objc public let verb: String?
    @objc public let path: String?
    @objc public let body: Data?
    @objc public let headers: [String]
    @objc public let requestId: UInt64

    @objc public init(verb: String?,
                      path: String?,
                      body: Data?,
                      headers: [String],
                      requestId: UInt64) {
        self.verb = verb
        self.path = path
        self.body = body
        self.headers = headers
        self.requestId = requestId
    }

    @objc
    public func serializedData() throws -> Data {
        return try self.asProtobuf.serializedData()
    }

    @objc public class func parseData(_ serializedData: Data) throws -> WebSocketProtoWebSocketRequestMessage {
        let proto = try WebSocketProtos_WebSocketRequestMessage(serializedData: serializedData)
        return try parseProto(proto)
    }

    fileprivate class func parseProto(_ proto: WebSocketProtos_WebSocketRequestMessage) throws -> WebSocketProtoWebSocketRequestMessage {
        var verb: String? = nil
        if proto.hasVerb {
            verb = proto.verb
        }

        var path: String? = nil
        if proto.hasPath {
            path = proto.path
        }

        var body: Data? = nil
        if proto.hasBody {
            body = proto.body
        }

        var headers: [String] = []
        for item in proto.headers {
            let wrapped = item
            headers.append(wrapped)
        }

        var requestId: UInt64 = 0
        if proto.hasRequestId {
            requestId = proto.requestId
        }

        // MARK: - Begin Validation Logic for WebSocketProtoWebSocketRequestMessage -

        // MARK: - End Validation Logic for WebSocketProtoWebSocketRequestMessage -

        let result = WebSocketProtoWebSocketRequestMessage(verb: verb,
                                                           path: path,
                                                           body: body,
                                                           headers: headers,
                                                           requestId: requestId)
        return result
    }

    fileprivate var asProtobuf: WebSocketProtos_WebSocketRequestMessage {
        let proto = WebSocketProtos_WebSocketRequestMessage.with { (builder) in
            if let verb = self.verb {
                builder.verb = verb
            }

            if let path = self.path {
                builder.path = path
            }

            if let body = self.body {
                builder.body = body
            }

            var headersUnwrapped = [String]()
            for item in headers {
                headersUnwrapped.append(item)
            }
            builder.headers = headersUnwrapped

            builder.requestId = self.requestId
        }

        return proto
    }
}

// MARK: - WebSocketProtoWebSocketResponseMessage

@objc public class WebSocketProtoWebSocketResponseMessage: NSObject {

    @objc public let requestId: UInt64
    @objc public let status: UInt32
    @objc public let message: String?
    @objc public let headers: [String]
    @objc public let body: Data?

    @objc public init(requestId: UInt64,
                      status: UInt32,
                      message: String?,
                      headers: [String],
                      body: Data?) {
        self.requestId = requestId
        self.status = status
        self.message = message
        self.headers = headers
        self.body = body
    }

    @objc
    public func serializedData() throws -> Data {
        return try self.asProtobuf.serializedData()
    }

    @objc public class func parseData(_ serializedData: Data) throws -> WebSocketProtoWebSocketResponseMessage {
        let proto = try WebSocketProtos_WebSocketResponseMessage(serializedData: serializedData)
        return try parseProto(proto)
    }

    fileprivate class func parseProto(_ proto: WebSocketProtos_WebSocketResponseMessage) throws -> WebSocketProtoWebSocketResponseMessage {
        var requestId: UInt64 = 0
        if proto.hasRequestId {
            requestId = proto.requestId
        }

        var status: UInt32 = 0
        if proto.hasStatus {
            status = proto.status
        }

        var message: String? = nil
        if proto.hasMessage {
            message = proto.message
        }

        var headers: [String] = []
        for item in proto.headers {
            let wrapped = item
            headers.append(wrapped)
        }

        var body: Data? = nil
        if proto.hasBody {
            body = proto.body
        }

        // MARK: - Begin Validation Logic for WebSocketProtoWebSocketResponseMessage -

        // MARK: - End Validation Logic for WebSocketProtoWebSocketResponseMessage -

        let result = WebSocketProtoWebSocketResponseMessage(requestId: requestId,
                                                            status: status,
                                                            message: message,
                                                            headers: headers,
                                                            body: body)
        return result
    }

    fileprivate var asProtobuf: WebSocketProtos_WebSocketResponseMessage {
        let proto = WebSocketProtos_WebSocketResponseMessage.with { (builder) in
            builder.requestId = self.requestId

            builder.status = self.status

            if let message = self.message {
                builder.message = message
            }

            var headersUnwrapped = [String]()
            for item in headers {
                headersUnwrapped.append(item)
            }
            builder.headers = headersUnwrapped

            if let body = self.body {
                builder.body = body
            }
        }

        return proto
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

    @objc public let type: WebSocketProtoWebSocketMessageType
    @objc public let request: WebSocketProtoWebSocketRequestMessage?
    @objc public let response: WebSocketProtoWebSocketResponseMessage?

    @objc public init(type: WebSocketProtoWebSocketMessageType,
                      request: WebSocketProtoWebSocketRequestMessage?,
                      response: WebSocketProtoWebSocketResponseMessage?) {
        self.type = type
        self.request = request
        self.response = response
    }

    @objc
    public func serializedData() throws -> Data {
        return try self.asProtobuf.serializedData()
    }

    @objc public class func parseData(_ serializedData: Data) throws -> WebSocketProtoWebSocketMessage {
        let proto = try WebSocketProtos_WebSocketMessage(serializedData: serializedData)
        return try parseProto(proto)
    }

    fileprivate class func parseProto(_ proto: WebSocketProtos_WebSocketMessage) throws -> WebSocketProtoWebSocketMessage {
        var type: WebSocketProtoWebSocketMessageType = .unknown
        if proto.hasType {
            type = WebSocketProtoWebSocketMessageTypeWrap(proto.type)
        }

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

        let result = WebSocketProtoWebSocketMessage(type: type,
                                                    request: request,
                                                    response: response)
        return result
    }

    fileprivate var asProtobuf: WebSocketProtos_WebSocketMessage {
        let proto = WebSocketProtos_WebSocketMessage.with { (builder) in
            builder.type = WebSocketProtoWebSocketMessage.WebSocketProtoWebSocketMessageTypeUnwrap(self.type)

            if let request = self.request {
                builder.request = request.asProtobuf
            }

            if let response = self.response {
                builder.response = response.asProtobuf
            }
        }

        return proto
    }
}
