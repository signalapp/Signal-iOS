//
//  Copyright (c) 2020 Open Whisper Systems. All rights reserved.
//

import Foundation
import SignalCoreKit

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

    public class func sessionManager(baseUrl: URL) -> AFHTTPSessionManager {
        return AFHTTPSessionManager(baseURL: baseUrl,
                                    sessionConfiguration: sessionConfiguration())
    }

    public class func jsonSessionManager(baseUrl: URL) -> AFHTTPSessionManager {
        let jsonSessionManager = sessionManager(baseUrl: baseUrl)
        jsonSessionManager.requestSerializer = AFJSONRequestSerializer()
        jsonSessionManager.responseSerializer = AFJSONResponseSerializer()
        return jsonSessionManager
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

        guard let url = OWSURLSession.buildUrl(urlString: urlString, baseUrl: sessionManager.baseURL) else {
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
        // Generate 1-64 chars of padding.
        let paddingLength: Int = 1 + Int(arc4random_uniform(64))
        let padding = self.padding(withLength: paddingLength)
        assert(padding.count == paddingLength)
        request.addValue(padding, forHTTPHeaderField: "X-SignalPadding")
    }

    private class func padding(withLength length: Int) -> String {
        // Pick a random ASCII char in the range 48-122
        var result = ""
        // Min and max values, inclusive.
        let minValue: UInt32 = 48
        let maxValue: UInt32 = 122
        for _ in 1...length {
            let value = minValue + arc4random_uniform(maxValue - minValue + 1)
            assert(value >= minValue)
            assert(value <= maxValue)
            result += String(UnicodeScalar(UInt8(value)))
        }
        return result
    }
}
