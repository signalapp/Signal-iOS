//
// Copyright 2021 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import SignalCoreKit

// This class can be used to build "outgoing" headers for requests
// or to parse "incoming" headers for responses.
//
// HTTP headers are case-insensitive.
// This class handles conflict resolution.
public final class OWSHttpHeaders: Dependencies, CustomDebugStringConvertible {
    public private(set) var headers = [String: String]()

    public init() {}

    public convenience init(httpHeaders: [String: String]?, overwriteOnConflict: Bool) {
        self.init()
        addHeaderMap(httpHeaders, overwriteOnConflict: overwriteOnConflict)
    }

    public convenience init(response: HTTPURLResponse) {
        self.init()
        for (key, value) in response.allHeaderFields {
            guard let key = key as? String, let value = value as? String else {
                owsFailDebug("Invalid response header, key: \(key), value: \(value).")
                continue
            }
            addHeader(key, value: value, overwriteOnConflict: true)
        }
    }

    // MARK: -

    public func hasValueForHeader(_ header: String) -> Bool {
        headers.keys.lazy.map { $0.lowercased() }.contains(header.lowercased())
    }

    public func value(forHeader header: String) -> String? {
        let header = header.lowercased()
        for (key, value) in headers {
            if key.lowercased() == header {
                return value
            }
        }
        return nil
    }

    public func removeValueForHeader(_ header: String) {
        headers = headers.filter { $0.key.lowercased() != header.lowercased() }
        owsAssertDebug(!hasValueForHeader(header))
    }

    public func addHeader(_ header: String, value: String, overwriteOnConflict: Bool) {
        addHeaderMap([header: value], overwriteOnConflict: overwriteOnConflict)
    }

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

    public func addHeaderList(_ newHttpHeaders: [String]?, overwriteOnConflict: Bool) {
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

    public static var userAgentHeaderKey: String { "User-Agent" }

    public static var userAgentHeaderValueSignalIos: String {
        "Signal-iOS/\(AppVersionImpl.shared.currentAppVersion4) iOS/\(UIDevice.current.systemVersion)"
    }

    public static var acceptLanguageHeaderKey: String { "Accept-Language" }

    /// See [RFC4647](https://www.rfc-editor.org/rfc/rfc4647#section-2.2).
    private static let languageRangeRegex = try! NSRegularExpression(pattern: #"^(?:\*|[a-z]{1,8})(?:-(?:\*|(?:[a-z0-9]{1,8})))*$"#, options: .caseInsensitive)

    /// Format languages for the `Accept-Language` header per [RFC9110][0].
    ///
    /// Languages should be passed in order of preference.
    ///
    /// Languages that aren't valid per [RFC4647][1] are omitted, because the server also does this validation.
    ///
    /// Up to 10 valid languages are returned.
    /// This is for simplicity, and also to [avoid generating 'q' values that are too long][2].
    ///
    /// [0]: https://www.rfc-editor.org/rfc/rfc9110.html#name-accept-language
    /// [1]: https://www.rfc-editor.org/rfc/rfc4647#section-2.2
    /// [2]: https://www.rfc-editor.org/rfc/rfc9110.html#quality.values
    static func formatAcceptLanguageHeader(_ languages: [String]) -> String {
        let formattedLanguages = languages
            .lazy
            .filter { languageRangeRegex.hasMatch(input: $0) }
            .prefix(10)
            .enumerated()
            .map { idx, language -> String in
                let q = 1.0 - (Float(idx) * 0.1)
                // ["If no 'q' parameter is present, the default weight is 1."][0]
                // [0]: https://www.rfc-editor.org/rfc/rfc9110.html#section-12.4.2
                if q == 1 { return language }
                return String(format: "\(language);q=%0.1g", q)
            }
        return formattedLanguages.isEmpty ? "*" : formattedLanguages.joined(separator: ", ")
    }

    public static var acceptLanguageHeaderValue: String {
        formatAcceptLanguageHeader(Locale.preferredLanguages)
    }

    public func addDefaultHeaders() {
        addHeader(Self.userAgentHeaderKey, value: Self.userAgentHeaderValueSignalIos, overwriteOnConflict: false)
        addHeader(Self.acceptLanguageHeaderKey, value: Self.acceptLanguageHeaderValue, overwriteOnConflict: false)
    }

    // MARK: - Auth Headers

    public static var authHeaderKey: String { "Authorization" }

    public static func authHeaderValue(username: String, password: String) throws -> String {
        guard let data = "\(username):\(password)".data(using: .utf8) else {
            throw OWSAssertionError("Failed to encode auth data.")
        }
        return "Basic " + data.base64EncodedString()
    }

    public func addAuthHeader(username: String, password: String) throws {
        let value = try Self.authHeaderValue(username: username, password: password)
        addHeader(Self.authHeaderKey, value: value, overwriteOnConflict: true)
    }

    public static func fillInMissingDefaultHeaders(request: URLRequest) -> URLRequest {
        var request = request
        let httpHeaders = OWSHttpHeaders()
        httpHeaders.addHeaderMap(request.allHTTPHeaderFields, overwriteOnConflict: true)
        httpHeaders.addDefaultHeaders()
        request.set(httpHeaders: httpHeaders)
        return request
    }

    // MARK: - NSObject Overrides

    static let whitelistedLoggedHeaderKeys = Set([
        "retry-after",
        "x-signal-timestamp"
        // Have a header key who's value you'd like to see logged? Add it here (lowercased)!
    ])

    public var debugDescription: String {
        var headerValues = [String]()
        for (key, value) in headers.sorted(by: { $0.key < $1.key }) {
            if Self.whitelistedLoggedHeaderKeys.contains(key.lowercased()) {
                headerValues.append("\(key): \(value)")
            } else {
                headerValues.append(key)
            }
        }
        return "<\(type(of: self)): [\(headerValues.joined(separator: "; "))]>"
    }
}

// MARK: - HTTP Headers

public extension URLRequest {
    mutating func set(httpHeaders: OWSHttpHeaders) {
        for (headerField, headerValue) in httpHeaders.headers {
            setValue(headerValue, forHTTPHeaderField: headerField)
        }
    }
}
