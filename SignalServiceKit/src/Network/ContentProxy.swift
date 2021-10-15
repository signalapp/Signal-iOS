//
//  Copyright (c) 2021 Open Whisper Systems. All rights reserved.
//

import Foundation
import SignalCoreKit

@objc
public class ContentProxy: NSObject {

    @available(*, unavailable, message: "do not instantiate this class.")
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

    public static let userAgent = "Signal iOS (+https://signal.org/download)"

    public class func configureProxiedRequest(request: inout URLRequest) -> Bool {
        // Replace user-agent.
        let headers = OWSHttpHeaders(httpHeaders: request.allHTTPHeaderFields)
        headers.addHeader(OWSHttpHeaders.userAgentHeaderKey, value: userAgent, overwriteOnConflict: true)
        request.allHTTPHeaderFields = headers.headers

        padRequestSize(request: &request)

        return request.url?.scheme?.lowercased() == "https"
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
