//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

final public class OWSURLSessionEndpoint {
    /// This is generally the "scheme" & "host" portions of the URL, but it may
    /// also contain a path prefix in some cases.
    let baseUrl: URL?

    /// If censorship circumvention is enabled, this will contain details that
    /// influence how requests are built.
    let frontingInfo: OWSUrlFrontingInfo?

    /// If there's extra headers that need to be attached to every outgoing
    /// request, they'll be included here.
    private let extraHeaders: HttpHeaders

    /// The set of certificates we should use during the TLS handshake.
    let securityPolicy: HttpSecurityPolicy

    init(
        baseUrl: URL?,
        frontingInfo: OWSUrlFrontingInfo?,
        securityPolicy: HttpSecurityPolicy,
        extraHeaders: HttpHeaders
    ) {
        self.baseUrl = baseUrl
        self.frontingInfo = frontingInfo
        self.securityPolicy = securityPolicy
        self.extraHeaders = extraHeaders
    }

    func buildRequest(
        _ urlString: String,
        overrideUrlScheme: String? = nil,
        method: HTTPMethod,
        headers: HttpHeaders = HttpHeaders(),
        body: Data? = nil
    ) throws -> URLRequest {
        guard let url = buildUrl(urlString, overrideUrlScheme: overrideUrlScheme) else {
            throw OWSAssertionError("Invalid url.")
        }
        var request = URLRequest(url: url)
        request.httpMethod = method.methodName

        var httpHeaders = HttpHeaders()
        httpHeaders.merge(headers)
        httpHeaders.addDefaultHeaders()
        httpHeaders.merge(extraHeaders)
        request.set(httpHeaders: httpHeaders)

        request.httpBody = body
        request.httpShouldHandleCookies = false
        return request
    }

    /// Resolve the absolute URL for the HTTP request.
    ///
    /// - Parameters:
    ///   - urlString: Typically, this is only the path & query components.
    ///   - overrideUrlScheme: A scheme to use in place of `baseUrl`'s scheme.
    ///
    /// - Returns:
    ///     An absolute URL that works with this endpoint. The returned URL's
    ///     host is replaced by the host of `baseUrl`. In some cases, the URL's
    ///     path may have a component prepended to it. The scheme is set to
    ///     `overrideUrlScheme`; if that value is `nil`, the scheme set to
    ///     `baseUrl`'s scheme.
    private func buildUrl(_ urlString: String, overrideUrlScheme: String?) -> URL? {
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

        return OWSURLBuilderUtil.joinUrl(
            urlString: urlString,
            overrideUrlScheme: overrideUrlScheme,
            baseUrl: baseUrl
        )
    }
}
