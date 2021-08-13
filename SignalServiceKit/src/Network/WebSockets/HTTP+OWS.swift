//
//  Copyright (c) 2021 Open Whisper Systems. All rights reserved.
//

import Foundation

// This file contains common interfaces for dealing with
// HTTP request responses, failures and errors in a consistent
// way without concern for whether the request is made via
//
// * REST (e.g. AFNetworking, OWSURLSession, URLSession, etc.).
// * a Websocket (e.g. OWSWebSocket).

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

// TODO: Apply this protocol to OWSUrlSession, network manager, etc?
public protocol HTTPError {
    var requestUrl: URL { get }
    // status is zero by default, if request never made or failed.
    var responseStatusCode: Int { get }
    var responseHeaders: OWSHttpHeaders? { get }
    // TODO: Eradicate NSUnderlyingErrorKey.
    // TODO: Eradice responseError.
    var responseError: Error? { get }
    // TODO: Eradicate extracting response data from AFNetworking.
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

public enum OWSHTTPError: Error, IsRetryableProvider {
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

    /// NSError bridging: the domain of the error.
    /// :nodoc:
    public static var errorDomain: String {
        return "OWSHTTPError"
    }

    public var errorUserInfo: [String: Any] {
        var result = [String: Any]()
        if let responseError = self.responseError {
            result[NSUnderlyingErrorKey] = responseError
        }
        if let customLocalizedRecoverySuggestion = self.customLocalizedRecoverySuggestion {
            result[NSLocalizedDescriptionKey] = customLocalizedRecoverySuggestion
        }
        if let customLocalizedRecoverySuggestion = self.customLocalizedRecoverySuggestion {
            result[NSLocalizedRecoverySuggestionErrorKey] = customLocalizedRecoverySuggestion
        }
        return result
    }

    // MARK: - IsRetryableProvider

    public var isRetryableProvider: Bool {
        if isNetworkConnectivityError {
            return true
        }
        switch self {
        case .invalidAppState, .invalidRequest:
            return false
        case .invalidResponse:
            return true
        case .networkFailure:
            return true
        case .serviceResponse:
            // TODO: We might eventually special-case 413 Rate Limited errors.
            let responseStatus = self.responseStatusCode
            // TODO: What about 5xx?
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

    public var requestUrl: URL {
        switch self {
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
        case .invalidAppState, .invalidRequest, .invalidResponse, .networkFailure:
            return 0
        case .serviceResponse(let serviceResponse):
            return Int(serviceResponse.responseStatus)
        }
    }

    public var responseHeaders: OWSHttpHeaders? {
        switch self {
        case .invalidAppState, .invalidRequest, .invalidResponse, .networkFailure:
            return nil
        case .serviceResponse(let serviceResponse):
            return serviceResponse.responseHeaders
        }
    }

    public var responseError: Error? {
        switch self {
        case .invalidAppState, .invalidRequest, .invalidResponse, .networkFailure:
            return nil
        case .serviceResponse(let serviceResponse):
            return serviceResponse.responseError
        }
    }

    public var responseBodyData: Data? {
        switch self {
        case .invalidAppState, .invalidRequest, .invalidResponse, .networkFailure:
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
        case .invalidAppState, .invalidRequest, .invalidResponse, .networkFailure:
            return nil
        case .serviceResponse(let serviceResponse):
            return serviceResponse.customRetryAfterDate
        }
    }

    public var customLocalizedDescription: String? {
        switch self {
        case .invalidAppState, .invalidRequest, .invalidResponse, .networkFailure:
            return nil
        case .serviceResponse(let serviceResponse):
            return serviceResponse.customLocalizedDescription
        }
    }

    public var customLocalizedRecoverySuggestion: String? {
        switch self {
        case .invalidAppState, .invalidRequest, .invalidResponse, .networkFailure:
            return nil
        case .serviceResponse(let serviceResponse):
            return serviceResponse.customLocalizedRecoverySuggestion
        }
    }

    // NOTE: This function should only be called from NetworkManager.isSwiftNetworkConnectivityError.
    public var isNetworkConnectivityError: Bool {
        switch self {
        case .invalidAppState, .invalidRequest, .invalidResponse:
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
                return IsNetworkConnectivityFailure(responseError)
            }
            return false
        }
    }
}

// MARK: -

extension OWSHttpHeaders {

    // fallback retry-after delay if we fail to parse a non-empty retry-after string
    private static var kOWSFallbackRetryAfter: TimeInterval { 60 }
    private static var kOWSRetryAfterHeaderKey: String { "Retry-After" }

    public var retryAfterDate: Date? {
        Self.retryAfterDate(responseHeaders: headers)
    }

    fileprivate static func retryAfterDate(responseHeaders: [String: String]) -> Date? {
        guard let retryAfterString = responseHeaders[Self.kOWSRetryAfterHeaderKey] else {
            return nil
        }
        return Self.parseRetryAfterHeaderValue(retryAfterString)
    }

    private static func parseRetryAfterHeaderValue(_ rawValue: String?) -> Date? {
        guard let value = rawValue?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty else {
            return nil
        }
        if let result = Date.ows_parseFromHTTPDateString(value) {
            return result
        }
        if let result = Date.ows_parseFromISO8601String(value) {
            return result
        }
        func parseWithScanner() -> Date? {
            // We need to use NSScanner instead of -[NSNumber doubleValue] so we can differentiate
            // because the NSNumber method returns 0.0 on a parse failure. NSScanner lets us detect
            // a parse failure.
            let scanner = Scanner(string: value)
            var delay: TimeInterval = 0
            guard scanner.scanDouble(&delay),
                  scanner.isAtEnd else {
                // Only return the delay if we've made it to the end.
                // Helps to prevent things like: 8/11/1994 being interpreted as delay: 8.
                return nil
            }
            return Date(timeIntervalSinceNow: max(0, delay))
        }
        if let result = parseWithScanner() {
            return result
        }
        if !CurrentAppContext().isRunningTests {
            owsFailDebug("Failed to parse retry-after string: \(String(describing: rawValue))")
        }
        return Date(timeIntervalSinceNow: Self.kOWSFallbackRetryAfter)
    }
}

// MARK: -

public extension Error {
    var httpStatusCode: Int? {
        HTTPStatusCodeForError(self)?.intValue
    }

    var httpRetryAfterDate: Date? {
        HTTPRetryAfterDateForError(self)
    }

    var httpResponseData: Data? {
        HTTPResponseDataForError(self)
    }

    var httpResponseJson: Any? {
        guard let data = httpResponseData else {
            return nil
        }
        do {
            let json = try JSONSerialization.jsonObject(with: data, options: [])
            return json
        } catch {
            owsFailDebug("Could not parse JSON: \(error).")
            return nil
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

    @objc
    public let headers: OWSHttpHeaders

    @objc
    public let bodyData: Data?

    public let stringEncoding: String.Encoding

    private struct JSONValue {
        let json: Any?
    }

    // This property should only be accessed with unfairLock acquired.
    //
    // TODO: Type?
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
        guard let data = data else {
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
