//
// Copyright 2021 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

@objc
public class GiphyAPI: NSObject {

    // MARK: - Properties

    private static let kGiphyBaseURL = URL(string: "https://api.giphy.com/")!

    private static func buildURLSession() -> OWSURLSessionProtocol {
        let configuration = ContentProxy.sessionConfiguration()

        // Don't use any caching to protect privacy of these requests.
        configuration.urlCache = nil
        configuration.requestCachePolicy = .reloadIgnoringCacheData

        return OWSURLSession(
            baseUrl: kGiphyBaseURL,
            securityPolicy: OWSURLSession.defaultSecurityPolicy,
            configuration: configuration
        )
    }

    // MARK: Search

    // This is the Signal iOS API key.
    private static let kGiphyApiKey = "ZsUpUm2L6cVbvei347EQNp7HrROjbOdc"
    private static let kGiphyPageSize = 100

    public static func trending() -> Promise<[GiphyImageInfo]> {
        return fetch(urlPath: "/v1/gifs/trending", queryItems: [])
    }

    public static func search(query: String) -> Promise<[GiphyImageInfo]> {
        return fetch(urlPath: "/v1/gifs/search", queryItems: [
            URLQueryItem(name: "q", value: query),
            URLQueryItem(name: "offset", value: "0")
        ])
    }

    private static func fetch(urlPath: String, queryItems: [URLQueryItem]) -> Promise<[GiphyImageInfo]> {
        var urlComponents = URLComponents()
        urlComponents.path = urlPath
        let baseQueryItems: [URLQueryItem] = [
            URLQueryItem(name: "api_key", value: kGiphyApiKey),
            URLQueryItem(name: "limit", value: "\(kGiphyPageSize)")
        ]
        urlComponents.queryItems = baseQueryItems + queryItems
        guard let urlString = urlComponents.string else {
            return Promise(error: OWSAssertionError("Could not encode query."))
        }

        let urlSession = buildURLSession()
        return firstly(on: DispatchQueue.global()) { () -> Promise<HTTPResponse> in
            var request = try urlSession.endpoint.buildRequest(urlString, method: .get)
            guard ContentProxy.configureProxiedRequest(request: &request) else {
                throw OWSAssertionError("Invalid URL")
            }
            return urlSession.dataTaskPromise(request: request)
        }.map(on: DispatchQueue.global()) { (response: HTTPResponse) -> [GiphyImageInfo] in
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

    private static func parseGiphyImages(responseJson: Any?) -> [GiphyImageInfo]? {
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
