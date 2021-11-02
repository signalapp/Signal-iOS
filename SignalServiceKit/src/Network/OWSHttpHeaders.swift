//
//  Copyright (c) 2021 Open Whisper Systems. All rights reserved.
//

import Foundation
import SignalCoreKit

// This class can be used to build "outgoing" headers for requests
// or to parse "incoming" headers for responses.
//
// HTTP headers are case-insensitive.
// This class handles conflict resolution.
@objc
public class OWSHttpHeaders: NSObject {
    public private(set) var headers = [String: String]()

    @objc
    public override init() {}

    @objc
    public init(httpHeaders: [String: String]?) {}

    @objc
    public init(response: HTTPURLResponse) {
        for (key, value) in response.allHeaderFields {
           guard let key = key as? String,
                 let value = value as? String else {
            owsFailDebug("Invalid response header, key: \(key), value: \(value).")
            continue
           }
            headers[key] = value
        }
    }

    // MARK: -

    @objc
    public func hasValueForHeader(_ header: String) -> Bool {
        Set(headers.keys.map { $0.lowercased() }).contains(header.lowercased())
    }

    @objc
    public func value(forHeader header: String) -> String? {
        let header = header.lowercased()
        for (key, value) in headers {
            if key.lowercased() == header {
                return value
            }
        }
        return nil
    }

    @objc
    public func removeValueForHeader(_ header: String) {
        headers = headers.filter { $0.key.lowercased() != header.lowercased() }
        owsAssertDebug(!hasValueForHeader(header))
    }

    @objc(addHeader:value:overwriteOnConflict:)
    public func addHeader(_ header: String, value: String, overwriteOnConflict: Bool) {
        addHeaderMap([header: value], overwriteOnConflict: overwriteOnConflict)
    }

    @objc
    public func addHeaderMap(_ newHttpHeaders: [String: String]?,
                             overwriteOnConflict: Bool) {
        guard let newHttpHeaders = newHttpHeaders else {
            return
        }
        for (key, value) in newHttpHeaders {
            if let existingValue = self.value(forHeader: key) {
                if value == existingValue {
                    // Don't warn about redundant changes.
                } else if overwriteOnConflict {
                    // We expect to overwrite the User-Agent; don't log it.
                    if key.lowercased() != Self.userAgentHeaderKey.lowercased() {
                        Logger.verbose("Overwriting header: \(key), \(existingValue) -> \(value)")
                    }
                } else if key.lowercased() == Self.acceptLanguageHeaderKey.lowercased() {
                    // Don't warn about default headers.
                    continue
                } else if key.lowercased() == Self.userAgentHeaderKey.lowercased() {
                    // Don't warn about default headers.
                    continue
                } else {
                    owsFailDebug("Skipping redundant header: \(key)")
                    continue
                }
            }

            // Clear any existing value with a key with different casing.
            removeValueForHeader(key)

            headers[key] = value
        }
    }

    @objc
    public func addHeaderList(_ newHttpHeaders: [String]?,
                             overwriteOnConflict: Bool) {
        guard let newHttpHeaders = newHttpHeaders else {
            return
        }
        for header in newHttpHeaders {
            guard let header = header.strippedOrNil else {
                owsFailDebug("Empty header.")
                continue
            }
            guard let index = header.firstIndex(of: ":") else {
                Logger.warn("Invalid header: \(header).")
                owsFailDebug("Invalid header.")
                continue
            }
            let beforeColonIndex = index
            let afterColonIndex = header.index(index, offsetBy: 1)
            guard let key = String(header.prefix(upTo: beforeColonIndex)).strippedOrNil else {
                Logger.warn("Invalid header key: \(header).")
                owsFailDebug("Invalid header key.")
                continue
            }
            guard let value = String(header.suffix(from: afterColonIndex)).strippedOrNil else {
                Logger.warn("Invalid header value: \(header), key: \(key).")
                owsFailDebug("Invalid header value.")
                continue
            }
            self.addHeader(key, value: value, overwriteOnConflict: overwriteOnConflict)
        }
    }

    // MARK: - Default Headers

    @objc
    public static var userAgentHeaderKey: String { "User-Agent" }

    @objc
    public static var userAgentHeaderValueSignalIos: String {
        "Signal-iOS/\(appVersion.currentAppVersion4) iOS/\(UIDevice.current.systemVersion)"
    }

    @objc
    public static var acceptLanguageHeaderKey: String { "Accept-Language" }

    @objc
    public static var acceptLanguageHeaderValue: String {
        // http://www.w3.org/Protocols/rfc2616/rfc2616-sec14.html#sec14.4
        let components = Locale.preferredLanguages.enumerated().compactMap { (index, languageCode) -> String? in
            let qualityWeight: Float = 1.0 - (Float(index) * 0.1)
            guard qualityWeight >= 0.5 else {
                return nil
            }
            return String(format: "\(languageCode);q=%0.1g", qualityWeight)
        }
        return components.joined(separator: ", ")
    }

    @objc
    public func addDefaultHeaders() {
        addHeader(Self.userAgentHeaderKey, value: Self.userAgentHeaderValueSignalIos, overwriteOnConflict: false)
        addHeader(Self.acceptLanguageHeaderKey, value: Self.acceptLanguageHeaderValue, overwriteOnConflict: false)
    }

    // MARK: - Auth Headers

    @objc
    public static var authHeaderKey: String { "Authorization" }

    @objc
    public static func authHeaderValue(username: String, password: String) throws -> String {
        guard let data = "\(username):\(password)".data(using: .utf8) else {
            throw OWSAssertionError("Failed to encode auth data.")
        }
        return "Basic " + data.base64EncodedString()
    }

    @objc
    public func addAuthHeader(username: String, password: String) throws {
        let value = try Self.authHeaderValue(username: username, password: password)
        addHeader(Self.authHeaderKey, value: value, overwriteOnConflict: true)
    }

    public static func fillInMissingDefaultHeaders(request: URLRequest) -> URLRequest {
        var request = request
        let httpHeaders = OWSHttpHeaders()
        httpHeaders.addHeaderMap(request.allHTTPHeaderFields, overwriteOnConflict: true)
        httpHeaders.addDefaultHeaders()
        request.replace(httpHeaders: httpHeaders)
        return request
    }
}

// MARK: - HTTP Headers

public extension URLRequest {
    mutating func add(httpHeaders: OWSHttpHeaders) {
        for (headerField, headerValue) in httpHeaders.headers {
            addValue(headerValue, forHTTPHeaderField: headerField)
        }
    }

    mutating func replace(httpHeaders: OWSHttpHeaders) {
        allHTTPHeaderFields = httpHeaders.headers
    }

    mutating func removeAllHeaders() {
        allHTTPHeaderFields = [:]
    }
}
