//
//  Copyright (c) 2021 Open Whisper Systems. All rights reserved.
//

import Foundation

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

    private func buildURLSession() -> OWSURLSession {
        OWSURLSession(baseUrl: kGiphyBaseURL,
                      securityPolicy: OWSURLSession.defaultSecurityPolicy,
                      configuration: OWSURLSession.defaultConfigurationWithoutCaching)
    }

    // MARK: Search

    // This is the Signal iOS API key.
    let kGiphyApiKey = "ZsUpUm2L6cVbvei347EQNp7HrROjbOdc"
    let kGiphyPageSize = 100

    public func trending() -> Promise<[GiphyImageInfo]> {
        let urlSession = buildURLSession()
        let urlString = "/v1/gifs/trending?api_key=\(kGiphyApiKey)&limit=\(kGiphyPageSize)"

        return firstly(on: .global()) { () -> Promise<HTTPResponse> in
            guard let url = OWSURLSession.joinUrl(urlString: urlString,
                                                  baseUrl: self.kGiphyBaseURL) else {
                throw OWSAssertionError("Invalid URL: \(urlString).")
            }
            var request = URLRequest(url: url)
            request.httpMethod = HTTPMethod.get.methodName
            guard ContentProxy.configureProxiedRequest(request: &request) else {
                throw OWSAssertionError("Invalid URL: \(urlString).")
            }
            return urlSession.dataTaskPromise(request: request)
        }.map(on: .global()) { (response: HTTPResponse) -> [GiphyImageInfo] in
            guard let json = response.responseBodyJson else {
                throw OWSAssertionError("Missing or invalid JSON")
            }
            Logger.info("Request succeeded.")
            guard let imageInfos = self.parseGiphyImages(responseJson: json) else {
                throw OWSAssertionError("unable to parse trending images")
            }
            return imageInfos
        }
    }

    public func search(query: String) -> Promise<[GiphyImageInfo]> {
        let kGiphyPageOffset = 0
        guard let queryEncoded = query.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) else {
            owsFailDebug("Could not URL encode query: \(query).")
            return Promise(error: OWSAssertionError("Could not URL encode query."))
        }
        let urlString = "/v1/gifs/search?api_key=\(kGiphyApiKey)&offset=\(kGiphyPageOffset)&limit=\(kGiphyPageSize)&q=\(queryEncoded)"

        let urlSession = buildURLSession()
        return firstly(on: .global()) { () -> Promise<HTTPResponse> in
            guard let url = OWSURLSession.joinUrl(urlString: urlString, baseUrl: self.kGiphyBaseURL) else {
                throw OWSAssertionError("Invalid URL: \(urlString).")
            }
            var request = URLRequest(url: url)
            request.httpMethod = HTTPMethod.get.methodName
            guard ContentProxy.configureProxiedRequest(request: &request) else {
                throw OWSAssertionError("Invalid URL: \(urlString).")
            }
            return urlSession.dataTaskPromise(request: request)
        }.map(on: .global()) { (response: HTTPResponse) -> [GiphyImageInfo] in
            guard let json = response.responseBodyJson else {
                throw OWSAssertionError("Missing or invalid JSON")
            }
            Logger.info("Request succeeded.")
            guard let imageInfos = self.parseGiphyImages(responseJson: json) else {
                throw OWSAssertionError("unable to parse trending images")
            }
            return imageInfos
        }
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
