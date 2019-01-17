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
}
