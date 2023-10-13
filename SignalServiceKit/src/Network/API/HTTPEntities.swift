//
// Copyright 2021 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import SignalCoreKit

// This file contains common interfaces for dealing with
// HTTP request responses, failures and errors in a consistent
// way without concern for whether the request is made via
//
// * REST (e.g. AFNetworking, OWSURLSession, URLSession, etc.).
// * a Websocket (e.g. OWSWebSocket).

// A common protocol for responses from OWSUrlSession, NetworkManager, SocketManager, etc.
@objc
public protocol HTTPResponse {
    var requestUrl: URL { get }
    var responseStatusCode: Int { get }
    var responseHeaders: [String: String] { get }
    var responseBodyData: Data? { get }
    var responseBodyJson: Any? { get }
    var responseBodyString: String? { get }
}

// MARK: -

// A common protocol for errors from OWSUrlSession, NetworkManager, SocketManager, etc.
public protocol HTTPError {
    var requestUrl: URL? { get }
    // status is zero by default, if request never made or failed.
    var responseStatusCode: Int { get }
    var responseHeaders: OWSHttpHeaders? { get }
    // TODO: Can we eventually eliminate responseError?
    var responseError: Error? { get }
    var responseBodyData: Data? { get }

    var customRetryAfterDate: Date? { get }
    var isNetworkConnectivityError: Bool { get }
}

// MARK: -

public struct HTTPErrorServiceResponse {
    let requestUrl: URL
    let responseStatus: Int
    let responseHeaders: OWSHttpHeaders
    let responseError: Error?
    let responseData: Data?
    let customRetryAfterDate: Date?
    let customLocalizedDescription: String?
    let customLocalizedRecoverySuggestion: String?
}

// MARK: -

public enum OWSHTTPError: Error, CustomDebugStringConvertible, IsRetryableProvider, UserErrorDescriptionProvider {
    case missingRequest
    case invalidAppState(requestUrl: URL)
    case invalidRequest(requestUrl: URL)
    case invalidResponse(requestUrl: URL)
    // Request failed without a response from the service.
    case networkFailure(requestUrl: URL)
    // Request failed with a response from the service.
    case serviceResponse(serviceResponse: HTTPErrorServiceResponse)

    // The first 5 parameters are required (even if nil).
    // The custom parameters are optional.
    public static func forServiceResponse(requestUrl: URL,
                                          responseStatus: Int,
                                          responseHeaders: OWSHttpHeaders,
                                          responseError: Error?,
                                          responseData: Data?,
                                          customRetryAfterDate: Date? = nil,
                                          customLocalizedDescription: String? = nil,
                                          customLocalizedRecoverySuggestion: String? = nil) -> OWSHTTPError {
        let serviceResponse = HTTPErrorServiceResponse(requestUrl: requestUrl,
                                                       responseStatus: responseStatus,
                                                       responseHeaders: responseHeaders,
                                                       responseError: responseError,
                                                       responseData: responseData,
                                                       customRetryAfterDate: customRetryAfterDate,
                                                       customLocalizedDescription: customLocalizedDescription,
                                                       customLocalizedRecoverySuggestion: customLocalizedRecoverySuggestion)
        return .serviceResponse(serviceResponse: serviceResponse)
    }

    // NSError bridging: the domain of the error.
    public static var errorDomain: String {
        return "OWSHTTPError"
    }

    // NSError bridging: the error code within the given domain.
    public var errorUserInfo: [String: Any] {
        var result = [String: Any]()
        result[NSUnderlyingErrorKey] = responseError
        result[NSLocalizedDescriptionKey] = localizedDescription
        result[NSLocalizedRecoverySuggestionErrorKey] = customLocalizedRecoverySuggestion
        return result
    }

    public var localizedDescription: String {
        if let customLocalizedDescription {
            return customLocalizedDescription
        }
        switch self {
        case .missingRequest, .invalidAppState, .invalidRequest, .networkFailure:
            return OWSLocalizedString("ERROR_DESCRIPTION_REQUEST_FAILED",
                                     comment: "Error indicating that a socket request failed.")
        case .invalidResponse, .serviceResponse:
            return OWSLocalizedString("ERROR_DESCRIPTION_RESPONSE_FAILED",
                                     comment: "Error indicating that a socket response failed.")
        }
    }

    public var debugDescription: String {
        switch self {
        case .missingRequest:
            return "missingRequest"
        case .invalidAppState(let requestUrl):
            return "invalidAppState: \(requestUrl.absoluteString)"
        case .invalidRequest(let requestUrl):
            return "invalidRequest: \(requestUrl.absoluteString)"
        case .invalidResponse(let requestUrl):
            return "invalidResponse: \(requestUrl.absoluteString)"
        case .networkFailure(let requestUrl):
            return "networkFailure: \(requestUrl.absoluteString)"
        case .serviceResponse(let serviceResponse):
            return "HTTP \(serviceResponse.responseStatus); \(serviceResponse.responseHeaders); \(serviceResponse.requestUrl.absoluteString); \(serviceResponse.responseError)"
        }
    }

    // MARK: - IsRetryableProvider

    public var isRetryableProvider: Bool {
        if isNetworkConnectivityError {
            return true
        }
        switch self {
        case .missingRequest, .invalidAppState, .invalidRequest:
            return false
        case .invalidResponse:
            return true
        case .networkFailure:
            return true
        case .serviceResponse:
            // TODO: We might eventually special-case 413 Rate Limited errors.
            let responseStatus = self.responseStatusCode
            // We retry 5xx.
            if responseStatus >= 400, responseStatus <= 499 {
                return false
            } else {
                return true
            }
        }
    }
}

// MARK: -

extension OWSHTTPError: HTTPError {

    public var requestUrl: URL? {
        switch self {
        case .missingRequest:
            return nil
        case .invalidAppState(let requestUrl):
            return requestUrl
        case .invalidRequest(let requestUrl):
            return requestUrl
        case .invalidResponse(let requestUrl):
            return requestUrl
        case .networkFailure(let requestUrl):
            return requestUrl
        case .serviceResponse(let serviceResponse):
            return serviceResponse.requestUrl
        }
    }

    // NOTE: This function should only be called from NetworkManager.swiftHTTPStatusCodeForError.
    public var responseStatusCode: Int {
        switch self {
        case .missingRequest, .invalidAppState, .invalidRequest, .invalidResponse, .networkFailure:
            return 0
        case .serviceResponse(let serviceResponse):
            return Int(serviceResponse.responseStatus)
        }
    }

    public var responseHeaders: OWSHttpHeaders? {
        switch self {
        case .missingRequest, .invalidAppState, .invalidRequest, .invalidResponse, .networkFailure:
            return nil
        case .serviceResponse(let serviceResponse):
            return serviceResponse.responseHeaders
        }
    }

    public var responseError: Error? {
        switch self {
        case .missingRequest, .invalidAppState, .invalidRequest, .invalidResponse, .networkFailure:
            return nil
        case .serviceResponse(let serviceResponse):
            return serviceResponse.responseError
        }
    }

    public var responseBodyData: Data? {
        switch self {
        case .missingRequest, .invalidAppState, .invalidRequest, .invalidResponse, .networkFailure:
            return nil
        case .serviceResponse(let serviceResponse):
            return serviceResponse.responseData
        }
    }

    public var customRetryAfterDate: Date? {
        if let responseHeaders = self.responseHeaders,
           let retryAfterDate = responseHeaders.retryAfterDate {
            return retryAfterDate
        }

        switch self {
        case .missingRequest, .invalidAppState, .invalidRequest, .invalidResponse, .networkFailure:
            return nil
        case .serviceResponse(let serviceResponse):
            return serviceResponse.customRetryAfterDate
        }
    }

    fileprivate var customLocalizedDescription: String? {
        switch self {
        case .missingRequest, .invalidAppState, .invalidRequest, .invalidResponse, .networkFailure:
            return nil
        case .serviceResponse(let serviceResponse):
            return serviceResponse.customLocalizedDescription
        }
    }

    fileprivate var customLocalizedRecoverySuggestion: String? {
        switch self {
        case .missingRequest, .invalidAppState, .invalidRequest, .invalidResponse, .networkFailure:
            return nil
        case .serviceResponse(let serviceResponse):
            return serviceResponse.customLocalizedRecoverySuggestion
        }
    }

    // NOTE: This function should only be called from NetworkManager.isSwiftNetworkConnectivityError.
    public var isNetworkConnectivityError: Bool {
        switch self {
        case .missingRequest, .invalidAppState, .invalidRequest, .invalidResponse:
            return false
        case .networkFailure:
            return true
        case .serviceResponse:
            if 0 == self.responseStatusCode {
                // statusCode should now be nil, not zero, in this
                // case, but there might be some legacy code that is
                // still using zero.
                owsFailDebug("Unexpected status code.")
                return true
            }
            if let responseError = responseError {
                return responseError.isNetworkFailureOrTimeout
            }
            return false
        }
    }
}

// MARK: -

@objc
public class HTTPResponseImpl: NSObject {

    @objc
    public let requestUrl: URL

    @objc
    public let status: Int

    public let headers: OWSHttpHeaders

    @objc
    public let bodyData: Data?

    public let stringEncoding: String.Encoding

    private struct JSONValue {
        let json: Any?
    }

    // This property should only be accessed with unfairLock acquired.
    private var jsonValue: JSONValue?

    private static let unfairLock = UnfairLock()

    public required init(requestUrl: URL,
                         status: Int,
                         headers: OWSHttpHeaders,
                         bodyData: Data?,
                         stringEncoding: String.Encoding = .utf8) {
        self.requestUrl = requestUrl
        self.status = status
        self.headers = headers
        self.bodyData = bodyData
        self.stringEncoding = stringEncoding
    }

    public static func build(requestUrl: URL,
                             httpUrlResponse: HTTPURLResponse,
                             bodyData: Data?) -> HTTPResponse {
        let headers = OWSHttpHeaders(response: httpUrlResponse)
        let stringEncoding: String.Encoding = httpUrlResponse.parseStringEncoding() ?? .utf8
        return HTTPResponseImpl(requestUrl: requestUrl,
                                status: httpUrlResponse.statusCode,
                                headers: headers,
                                bodyData: bodyData,
                                stringEncoding: stringEncoding)
    }

    @objc
    public var bodyJson: Any? {
        Self.unfairLock.withLock {
            if let jsonValue = self.jsonValue {
                return jsonValue.json
            }
            let jsonValue = Self.parseJSON(data: bodyData)
            self.jsonValue = jsonValue
            return jsonValue.json
        }
    }

    private static func parseJSON(data: Data?) -> JSONValue {
        guard let data = data,
              !data.isEmpty else {
                  return JSONValue(json: nil)
              }
        do {
            let json = try JSONSerialization.jsonObject(with: data, options: [])
            return JSONValue(json: json)
        } catch {
            owsFailDebug("Could not parse JSON: \(error).")
            return JSONValue(json: nil)
        }
    }
}

// MARK: -

extension HTTPResponseImpl: HTTPResponse {
    @objc
    public var responseStatusCode: Int { Int(status) }
    @objc
    public var responseHeaders: [String: String] { headers.headers }
    @objc
    public var responseBodyData: Data? { bodyData }
    @objc
    public var responseBodyJson: Any? { bodyJson }
    @objc
    public var responseBodyString: String? {
        guard let data = bodyData,
              let string = String(data: data, encoding: stringEncoding) else {
                  Logger.warn("Invalid body string.")
                  return nil
              }
        return string
    }
}

// MARK: -

extension HTTPURLResponse {
    fileprivate func parseStringEncoding() -> String.Encoding? {
        guard let encodingName = textEncodingName else {
            return nil
        }
        let encoding = CFStringConvertIANACharSetNameToEncoding(encodingName as CFString)
        guard encoding != kCFStringEncodingInvalidId else {
            return nil
        }
        return String.Encoding(rawValue: CFStringConvertEncodingToNSStringEncoding(encoding))
    }
}

// MARK: -

// Temporary obj-c wrapper for OWSHTTPError until
// OWSWebSocket, etc. have been ported to Swift.
@objc
public class OWSHTTPErrorWrapper: NSObject {
    public let error: OWSHTTPError

    @objc
    public var asNSError: NSError { error as NSError }

    public init(error: OWSHTTPError) {
        self.error = error
    }
}
