//
//  Copyright (c) 2021 Open Whisper Systems. All rights reserved.
//

import Foundation
import PromiseKit

@objc
public class GiphyAPI: NSObject {

    // MARK: - Properties

    static public let shared = GiphyAPI()

    // Force usage as a singleton
    override private init() {
        super.init()
        SwiftSingletons.register(self)
    }

    private let kGiphyBaseURL = URL(string: "https://api.giphy.com/")!

    private func giphyAPISessionManager() -> AFHTTPSessionManager {
        return ContentProxy.jsonSessionManager(baseUrl: kGiphyBaseURL)
    }

    // MARK: Search

    // This is the Signal iOS API key.
    let kGiphyApiKey = "ZsUpUm2L6cVbvei347EQNp7HrROjbOdc"
    let kGiphyPageSize = 100

    public func trending() -> Promise<[GiphyImageInfo]> {
        let sessionManager = giphyAPISessionManager()
        let urlString = "/v1/gifs/trending?api_key=\(kGiphyApiKey)&limit=\(kGiphyPageSize)"

        return firstly(on: .global()) { () -> Promise<AFHTTPSessionManager.Response> in
            guard ContentProxy.configureSessionManager(sessionManager: sessionManager, forUrl: urlString) else {
                throw OWSAssertionError("Could not configure trending")
            }
            return sessionManager.getPromise(urlString)
        }.map(on: .global()) { (_: URLSessionDataTask, responseObject: Any?) in
            Logger.info("pending request succeeded")
            guard let imageInfos = self.parseGiphyImages(responseJson: responseObject) else {
                throw OWSAssertionError("unable to parse trending images")
            }
            return imageInfos
        }
    }

    public func search(query: String, success: @escaping (([GiphyImageInfo]) -> Void), failure: @escaping ((NSError?) -> Void)) {
        let sessionManager = giphyAPISessionManager()

        let kGiphyPageOffset = 0
        guard let queryEncoded = query.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) else {
            owsFailDebug("Could not URL encode query: \(query).")
            failure(nil)
            return
        }
        let urlString = "/v1/gifs/search?api_key=\(kGiphyApiKey)&offset=\(kGiphyPageOffset)&limit=\(kGiphyPageSize)&q=\(queryEncoded)"

        guard ContentProxy.configureSessionManager(sessionManager: sessionManager, forUrl: urlString) else {
            owsFailDebug("Could not configure query: \(query).")
            failure(nil)
            return
        }

        sessionManager.get(urlString,
                           parameters: [:],
                           progress: nil,
                           success: { _, value in
                            Logger.info("search request succeeded")
                            guard let imageInfos = self.parseGiphyImages(responseJson: value) else {
                                failure(nil)
                                return
                            }
                            success(imageInfos)
        },
                           failure: { _, error in
                            Logger.error("search request failed: \(error)")
                            failure(error as NSError)
        })
    }

    // MARK: Parse API Responses

    private func parseGiphyImages(responseJson: Any?) -> [GiphyImageInfo]? {
        guard let responseJson = responseJson else {
            Logger.error("Missing response.")
            return nil
        }
        guard let responseDict = responseJson as? [String: Any] else {
            Logger.error("Invalid response.")
            return nil
        }
        guard let imageDicts = responseDict["data"] as? [[String: Any]] else {
            Logger.error("Invalid response data.")
            return nil
        }
        return imageDicts.compactMap { imageDict in
            GiphyImageInfo(parsing: imageDict)
        }
    }
}
