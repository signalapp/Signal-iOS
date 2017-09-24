//
//  Copyright (c) 2017 Open Whisper Systems. All rights reserved.
//

import Foundation

@objc class GifManager: NSObject {

    // MARK: - Properties

    static let TAG = "[GifManager]"

    static let sharedInstance = GifManager()

    // Force usage as a singleton
    override private init() {}

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    private let kGiphyBaseURL = "https://api.giphy.com/"

    private func giphySessionManager() -> AFHTTPSessionManager? {
        guard let baseUrl = NSURL(string:kGiphyBaseURL) else {
            Logger.error("\(GifManager.TAG) Invalid base URL.")
            return nil
        }
        // TODO: Is this right?
        let sessionConf = URLSessionConfiguration.ephemeral
        // TODO: Is this right?
        sessionConf.connectionProxyDictionary = [
                kCFProxyHostNameKey as String: "giphy-proxy-production.whispersystems.org",
                kCFProxyPortNumberKey as String: "80",
                kCFProxyTypeKey as String: kCFProxyTypeHTTPS
        ]

        let sessionManager = AFHTTPSessionManager(baseURL:baseUrl as URL,
                                                  sessionConfiguration:sessionConf)
        sessionManager.requestSerializer = AFJSONRequestSerializer()
        sessionManager.responseSerializer = AFJSONResponseSerializer()

        return sessionManager
    }

    public func test() {
        guard let sessionManager = giphySessionManager() else {
            Logger.error("\(GifManager.TAG) Couldn't create session manager.")
            return
        }
        guard let baseUrl = NSURL(string:kGiphyBaseURL) else {
            Logger.error("\(GifManager.TAG) Invalid base URL.")
            return
        }

        // TODO: Should we use a separate API key?
        let kGiphyApiKey = "3o6ZsYH6U6Eri53TXy"
        let kGiphyPageSize = 200
        // TODO:
        let kGiphyPageOffset = 0
        // TODO:
        let query = "monkey"
        // TODO:
        guard let queryEncoded = query.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) else {
            Logger.error("\(GifManager.TAG) Could not URL encode query: \(query).")
            return
        }
//        Logger.error("\(GifManager.TAG) queryEncoded: \(queryEncoded) \(queryEncoded).")
        let urlString = "/v1/gifs/search?api_key=\(kGiphyApiKey)&offset=\(kGiphyPageOffset)&limit=\(kGiphyPageSize)&q=\(queryEncoded)"
//        Logger.error("\(GifManager.TAG) urlString: \(urlString).")
//        Logger.error("\(GifManager.TAG) baseUrl: \(baseUrl).")

        sessionManager.get(urlString,
                           parameters: {},
                           progress:nil,
                           success: { _, value in
                            Logger.error("\(GifManager.TAG) ---- success: \(value)")
        },
                           failure: { _, error in
                            Logger.error("\(GifManager.TAG) ---- failure: \(error)")
        })
    }
}
