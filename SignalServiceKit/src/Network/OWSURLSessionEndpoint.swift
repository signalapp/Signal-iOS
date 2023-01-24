//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

@objc
public class OWSURLSessionEndpoint: NSObject {
    /// This is generally the "scheme" & "host" portions of the URL, but it may
    /// also contain a path prefix in some cases.
    public let baseUrl: URL?

    /// If censorship circumvention is enabled, this will contain details that
    /// influence how requests are built.
    public let frontingInfo: OWSUrlFrontingInfo?

    /// If there's extra headers that need to be attached to every outgoing
    /// request, they'll be included here.
    public let extraHeaders: [String: String]

    /// The set of certificates we should use during the TLS handshake.
    public let securityPolicy: OWSHTTPSecurityPolicy

    init(
        baseUrl: URL?,
        frontingInfo: OWSUrlFrontingInfo?,
        securityPolicy: OWSHTTPSecurityPolicy,
        extraHeaders: [String: String]
    ) {
        self.baseUrl = baseUrl
        self.frontingInfo = frontingInfo
        self.securityPolicy = securityPolicy
        self.extraHeaders = extraHeaders
    }

    func buildRequest(
        _ urlString: String,
        method: HTTPMethod,
        headers: [String: String]? = nil,
        body: Data? = nil
    ) throws -> URLRequest {
        guard let url = buildUrl(urlString) else {
            throw OWSAssertionError("Invalid url.")
        }
        var request = URLRequest(url: url)
        request.httpMethod = method.methodName

        let httpHeaders = OWSHttpHeaders()
        httpHeaders.addHeaderMap(headers, overwriteOnConflict: false)
        httpHeaders.addDefaultHeaders()
        httpHeaders.addHeaderMap(extraHeaders, overwriteOnConflict: true)
        request.set(httpHeaders: httpHeaders)

        request.httpBody = body
        request.httpShouldHandleCookies = false
        return request
    }

    /// Resolve the absolute URL for the HTTP request.
    ///
    /// - Parameters:
    ///   - urlString: Typically, this is only the path & query components.
    ///
    /// - Returns:
    ///     An absolute URL that works with this endpoint. The returned URL's
    ///     scheme & host are replaced by the scheme & host of `baseUrl`. In
    ///     some cases, the URL's path may have a component prepended to it.
    private func buildUrl(_ urlString: String) -> URL? {
        let baseUrl: URL? = {
            if let frontingInfo {
                // Never apply fronting twice; if urlString already contains a fronted URL,
                // baseUrl should be nil.
                if frontingInfo.isFrontedUrl(urlString) {
                    Logger.info("URL is already fronted.")
                    return nil
                }
                return frontingInfo.frontingURLWithPathPrefix
            }

            return self.baseUrl
        }()

        guard let requestUrl = OWSURLBuilderUtil.joinUrl(urlString: urlString, baseUrl: baseUrl) else {
            owsFailDebug("Could not build URL.")
            return nil
        }
        return requestUrl
    }
}
