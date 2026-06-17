//
// Copyright 2021 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

public enum GiphyAPI {

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
            configuration: configuration,
        )
    }

    // MARK: Search

    // This is the Signal iOS API key.
    private static let kGiphyApiKey = "ZsUpUm2L6cVbvei347EQNp7HrROjbOdc"
    private static let kGiphyPageSize = 100
    // Limit response payload to the renditions and fields we actually consume.
    private static let kGiphyFields = [
        "id",
        "images.original.mp4",
        "images.fixed_width.mp4",
        "images.fixed_width.width",
        "images.fixed_width.height",
    ].joined(separator: ",")

    public static func trending() async throws -> [GiphyImageInfo] {
        try await fetch(urlPath: "/v1/gifs/trending", queryItems: [])
    }

    public static func search(query: String) async throws -> [GiphyImageInfo] {
        try await fetch(urlPath: "/v1/gifs/search", queryItems: [
            URLQueryItem(name: "q", value: query),
            URLQueryItem(name: "offset", value: "0"),
        ])
    }

    private static func fetch(urlPath: String, queryItems: [URLQueryItem]) async throws -> [GiphyImageInfo] {
        var urlComponents = URLComponents()
        urlComponents.path = urlPath
        let baseQueryItems: [URLQueryItem] = [
            URLQueryItem(name: "api_key", value: kGiphyApiKey),
            URLQueryItem(name: "limit", value: "\(kGiphyPageSize)"),
            URLQueryItem(name: "fields", value: kGiphyFields),
        ]
        urlComponents.queryItems = baseQueryItems + queryItems
        guard let urlString = urlComponents.string else {
            throw OWSAssertionError("Could not encode query.")
        }

        let urlSession = buildURLSession()
        do {
            var request = try urlSession.endpoint.buildRequest(urlString, method: .get)
            guard ContentProxy.configureProxiedRequest(request: &request) else {
                throw OWSAssertionError("Invalid URL")
            }
            let response = try await urlSession.performRequest(request: request, maxResponseSize: .max, ignoreAppExpiry: false)
            guard let responseData = response.responseBodyData else {
                throw OWSAssertionError("Missing response body")
            }
            Logger.info("Request succeeded.")
            let parsed = try JSONDecoder().decode(SearchResponse.self, from: responseData)
            return parsed.data.compactMap { imageInfo(from: $0) }
        } catch {
            Logger.warn("Request failed: \(error.shortDescription)")
            throw error
        }
    }

    private static func imageInfo(from apiResponse: APIResponse) -> GiphyImageInfo? {
        // Giphy returns numeric metadata as strings.
        guard
            let width = Int(apiResponse.images.fixedWidth.width),
            let height = Int(apiResponse.images.fixedWidth.height),
            width > 0,
            height > 0
        else {
            return nil
        }

        return GiphyImageInfo(
            giphyId: apiResponse.id,
            fullSize: ProxiedContentAssetDescription(
                url: apiResponse.images.original.mp4 as NSURL,
                fileExtension: GiphyImageInfo.fileExtension,
            ),
            preview: ProxiedContentAssetDescription(
                url: apiResponse.images.fixedWidth.mp4 as NSURL,
                fileExtension: GiphyImageInfo.fileExtension,
            ),
            previewAspectRatio: CGFloat(width) / CGFloat(height),
        )
    }

    private struct SearchResponse: Decodable {
        let data: [APIResponse]
    }

    private struct APIResponse: Decodable {
        let id: String
        let images: Images

        struct Images: Decodable {
            let original: Original
            let fixedWidth: FixedWidth

            private enum CodingKeys: String, CodingKey {
                case original
                case fixedWidth = "fixed_width"
            }

            struct Original: Decodable {
                let mp4: URL
            }

            struct FixedWidth: Decodable {
                let mp4: URL
                let width: String
                let height: String
            }
        }
    }

}
