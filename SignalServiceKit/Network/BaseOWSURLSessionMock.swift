//
// Copyright 2022 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

#if TESTABLE_BUILD

public class BaseOWSURLSessionMock: OWSURLSessionProtocol {

    // MARK: - OWSURLSessionProtocol conformance

    public var endpoint: OWSURLSessionEndpoint

    public var require2xxOr3xx: Bool = true

    public var allowRedirects: Bool = true

    public var customRedirectHandler: ((URLRequest) -> URLRequest?)?

    public static let defaultSecurityPolicy = OWSURLSession.defaultSecurityPolicy

    public static let signalServiceSecurityPolicy = OWSURLSession.signalServiceSecurityPolicy

    public static var defaultConfigurationWithCaching: URLSessionConfiguration = OWSURLSession.defaultConfigurationWithCaching

    public static var defaultConfigurationWithoutCaching: URLSessionConfiguration = OWSURLSession.defaultConfigurationWithoutCaching

    // MARK: Default Headers

    public static var userAgentHeaderKey: String = OWSURLSession.userAgentHeaderKey

    public static var userAgentHeaderValueSignalIos: String = OWSURLSession.userAgentHeaderValueSignalIos

    public static var acceptLanguageHeaderKey: String = OWSURLSession.acceptLanguageHeaderKey

    public static var acceptLanguageHeaderValue: String = OWSURLSession.acceptLanguageHeaderValue

    // MARK: Initializers

    private let configuration: URLSessionConfiguration
    private let maxResponseSize: Int?

    public required init(
        endpoint: OWSURLSessionEndpoint,
        configuration: URLSessionConfiguration,
        maxResponseSize: Int?,
        canUseSignalProxy: Bool
    ) {
        self.endpoint = endpoint
        self.configuration = configuration
        self.maxResponseSize = maxResponseSize
    }

    public convenience init() {
        self.init(
            endpoint: OWSURLSessionEndpoint(
                baseUrl: nil,
                frontingInfo: nil,
                securityPolicy: .systemDefault,
                extraHeaders: [:]
            ),
            configuration: .default,
            maxResponseSize: nil,
            canUseSignalProxy: false
        )
    }

    // MARK: Request Building

    public func buildRequest(
        _ urlString: String,
        method: HTTPMethod,
        headers: [String: String]?,
        body: Data?
    ) throws -> URLRequest {
        // Want different behavior? Write a custom mock class
        return URLRequest(url: URL(string: urlString)!)
    }

    public func performRequest(_ rawRequest: TSRequest) async throws -> any HTTPResponse {
        // Want different behavior? Write a custom mock class
        return HTTPResponseImpl(
            requestUrl: rawRequest.url,
            status: 200,
            headers: HttpHeaders(),
            bodyData: nil
        )
    }

    // MARK: Tasks

    public func performUpload(
        request: URLRequest,
        requestData: Data,
        progress: OWSProgressSource?
    ) async throws -> any HTTPResponse {
        // Want different behavior? Write a custom mock class
        return HTTPResponseImpl(
            requestUrl: request.url!,
            status: 200,
            headers: HttpHeaders(),
            bodyData: nil
        )
    }

    public func performUpload(
        request: URLRequest,
        fileUrl: URL,
        ignoreAppExpiry: Bool,
        progress: OWSProgressSource?
    ) async throws -> any HTTPResponse {
        // Want different behavior? Write a custom mock class
        return HTTPResponseImpl(
            requestUrl: request.url!,
            status: 200,
            headers: HttpHeaders(),
            bodyData: nil
        )
    }

    public func performRequest(request: URLRequest, ignoreAppExpiry: Bool) async throws -> any HTTPResponse {
        // Want different behavior? Write a custom mock class
        return HTTPResponseImpl(
            requestUrl: request.url!,
            status: 200,
            headers: HttpHeaders(),
            bodyData: nil
        )
    }

    public func performDownload(
        request: URLRequest,
        progress: OWSProgressSource?
    ) async throws -> OWSUrlDownloadResponse {
        // Want different behavior? Write a custom mock class
        return OWSUrlDownloadResponse(
            httpUrlResponse: HTTPURLResponse(),
            downloadUrl: URL(fileURLWithPath: request.url!.lastPathComponent)
        )
    }

    public func performDownload(
        requestUrl: URL,
        resumeData: Data,
        progress: OWSProgressSource?
    ) async throws -> OWSUrlDownloadResponse {
        // Want different behavior? Write a custom mock class
        return OWSUrlDownloadResponse(
            httpUrlResponse: HTTPURLResponse(),
            downloadUrl: URL(fileURLWithPath: requestUrl.lastPathComponent)
        )
    }

    public func webSocketTask(
        requestUrl: URL,
        didOpenBlock: @escaping (String?) -> Void,
        didCloseBlock: @escaping (Error) -> Void
    ) -> URLSessionWebSocketTask {
        // Want different behavior? Write a custom mock class
        fatalError("Not implemented.")
    }
}

#endif
