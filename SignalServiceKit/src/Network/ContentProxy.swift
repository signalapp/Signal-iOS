//
//  Copyright (c) 2019 Open Whisper Systems. All rights reserved.
//

import Foundation

@objc
public class ContentProxy: NSObject {

    @available(*, unavailable, message:"do not instantiate this class.")
    private override init() {
    }

    @objc
    public class func sessionConfiguration() -> URLSessionConfiguration {
        let configuration = URLSessionConfiguration.ephemeral
        let proxyHost = "contentproxy.signal.org"
        let proxyPort = 443
        configuration.connectionProxyDictionary = [
            "HTTPEnable": 1,
            "HTTPProxy": proxyHost,
            "HTTPPort": proxyPort,
            "HTTPSEnable": 1,
            "HTTPSProxy": proxyHost,
            "HTTPSPort": proxyPort
        ]
        return configuration
    }

    @objc
    public class func sessionManager(baseUrl baseUrlString: String?) -> AFHTTPSessionManager? {
        guard let baseUrlString = baseUrlString else {
            return AFHTTPSessionManager(baseURL: nil, sessionConfiguration: sessionConfiguration())
        }
        guard let baseUrl = URL(string: baseUrlString) else {
            owsFailDebug("Invalid base URL.")
            return nil
        }
        let sessionManager = AFHTTPSessionManager(baseURL: baseUrl,
                                                  sessionConfiguration: sessionConfiguration())
        return sessionManager
    }

    @objc
    public class func jsonSessionManager(baseUrl: String) -> AFHTTPSessionManager? {
        guard let sessionManager = self.sessionManager(baseUrl: baseUrl) else {
            owsFailDebug("Could not create session manager")
            return nil
        }
        sessionManager.requestSerializer = AFJSONRequestSerializer()
        sessionManager.responseSerializer = AFJSONResponseSerializer()
        return sessionManager
    }

    static let userAgent = "Signal iOS (+https://signal.org/download)"

    public class func configureProxiedRequest(request: inout URLRequest) -> Bool {
        request.addValue(userAgent, forHTTPHeaderField: "User-Agent")

        padRequestSize(request: &request)

        guard let url = request.url,
        let scheme = url.scheme,
            scheme.lowercased() == "https" else {
                return false
        }
        return true
    }

    // This mutates the session manager state, so its the caller's obligation to avoid conflicts by:
    //
    // * Using a new session manager for each request.
    // * Pooling session managers.
    // * Using a single session manager on a single queue.
    @objc
    public class func configureSessionManager(sessionManager: AFHTTPSessionManager,
                                              forUrl urlString: String) -> Bool {

        guard let url = URL(string: urlString, relativeTo: sessionManager.baseURL) else {
            owsFailDebug("Invalid URL query: \(urlString).")
            return false
        }

        var request = URLRequest(url: url)

        guard configureProxiedRequest(request: &request) else {
            owsFailDebug("Invalid URL query: \(urlString).")
            return false
        }

        // Remove all headers from the request.
        for headerField in sessionManager.requestSerializer.httpRequestHeaders.keys {
            sessionManager.requestSerializer.setValue(nil, forHTTPHeaderField: headerField)
        }
        // Honor the request's headers.
        if let allHTTPHeaderFields = request.allHTTPHeaderFields {
            for (headerField, headerValue) in allHTTPHeaderFields {
                sessionManager.requestSerializer.setValue(headerValue, forHTTPHeaderField: headerField)
            }
        }
        return true
    }

    public class func padRequestSize(request: inout URLRequest) {
        guard let sizeEstimate: UInt = estimateRequestSize(request: request) else {
            owsFailDebug("Could not estimate request size.")
            return
        }
        // We pad the estimated size to an even multiple of paddingQuantum (plus the
        // extra ": " and "\r\n").  The exact size doesn't matter so long as the
        // padding is consistent.
        let paddingQuantum: UInt = 1024
        let paddingSize = paddingQuantum - (sizeEstimate % paddingQuantum)
        let padding = String(repeating: ".", count: Int(paddingSize))
        request.addValue(padding, forHTTPHeaderField: "X-SignalPadding")
    }

    private class func estimateRequestSize(request: URLRequest) -> UInt? {
        // iOS doesn't offer an exact way to measure request sizes on the wire,
        // but we can reliably estimate request sizes using the "knowns", e.g.
        // HTTP method, path, querystring, headers.  The "unknowns" should be
        // consistent between requests.

        guard let url = request.url?.absoluteString else {
            owsFailDebug("Request missing URL.")
            return nil
        }
        guard let components = URLComponents(string: url) else {
            owsFailDebug("Request has invalid URL.")
            return nil
        }

        var result: Int = 0

        if let httpMethod = request.httpMethod {
            result += httpMethod.count
        }
        result += components.percentEncodedPath.count
        if let percentEncodedQuery = components.percentEncodedQuery {
            result += percentEncodedQuery.count
        }
        if let allHTTPHeaderFields = request.allHTTPHeaderFields {
            for (key, value) in allHTTPHeaderFields {
                // Each header has 4 extra bytes:
                //
                // * Two for the key/value separator ": "
                // * Two for "\r\n", the line break in the HTTP protocol spec.
                result += key.count + value.count + 4
            }
        } else {
            owsFailDebug("Request has no headers.")
        }
        if let httpBody = request.httpBody {
            result += httpBody.count
        }
        return UInt(result)
    }}
