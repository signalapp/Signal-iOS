//
// Copyright 2022 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

public class BaseOWSURLSessionMock: OWSURLSessionProtocol {

    // MARK: - OWSURLSessionProtocol conformance

    public var endpoint: OWSURLSessionEndpoint

    public var failOnError: Bool = true

    public var require2xxOr3xx: Bool = true

    public var allowRedirects: Bool = true

    public var customRedirectHandler: ((URLRequest) -> URLRequest?)?

    @objc
    public static var defaultSecurityPolicy: OWSHTTPSecurityPolicy = OWSURLSession.defaultSecurityPolicy

    public static var signalServiceSecurityPolicy: OWSHTTPSecurityPolicy = OWSURLSession.signalServiceSecurityPolicy

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
                securityPolicy: .systemDefault(),
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

    public func promiseForTSRequest(_ rawRequest: TSRequest) -> Promise<HTTPResponse> {
        // Want different behavior? Write a custom mock class
        return .value(HTTPResponseImpl(
            requestUrl: rawRequest.url!,
            status: 200,
            headers: OWSHttpHeaders(),
            bodyData: nil
        ))
    }

    // MARK: Tasks

    public func uploadTaskPromise(
        request: URLRequest,
        data requestData: Data,
        progress progressBlock: ProgressBlock?
    ) -> Promise<HTTPResponse> {
        // Want different behavior? Write a custom mock class
        return .value(HTTPResponseImpl(
            requestUrl: request.url!,
            status: 200,
            headers: OWSHttpHeaders(),
            bodyData: nil
        ))
    }

    public func uploadTaskPromise(
        request: URLRequest,
        fileUrl: URL,
        ignoreAppExpiry: Bool,
        progress progressBlock: ProgressBlock?
    ) -> Promise<HTTPResponse> {
        // Want different behavior? Write a custom mock class
        return .value(HTTPResponseImpl(
            requestUrl: request.url!,
            status: 200,
            headers: OWSHttpHeaders(),
            bodyData: nil
        ))
    }

    public func dataTaskPromise(request: URLRequest, ignoreAppExpiry: Bool = false) -> Promise<HTTPResponse> {
        // Want different behavior? Write a custom mock class
        return .value(HTTPResponseImpl(
            requestUrl: request.url!,
            status: 200,
            headers: OWSHttpHeaders(),
            bodyData: nil
        ))
    }

    public func downloadTaskPromise(
        request: URLRequest,
        progress progressBlock: ProgressBlock?
    ) -> Promise<OWSUrlDownloadResponse> {
        // Want different behavior? Write a custom mock class
        return .value(OWSUrlDownloadResponse(
            task: URLSessionTask(),
            httpUrlResponse: HTTPURLResponse(),
            downloadUrl: URL(fileURLWithPath: request.url!.lastPathComponent)
        ))
    }

    public func downloadTaskPromise(
        requestUrl: URL,
        resumeData: Data,
        progress progressBlock: ProgressBlock?
    ) -> Promise<OWSUrlDownloadResponse> {
        // Want different behavior? Write a custom mock class
        return .value(OWSUrlDownloadResponse(
            task: URLSessionTask(),
            httpUrlResponse: HTTPURLResponse(),
            downloadUrl: URL(fileURLWithPath: requestUrl.lastPathComponent)
        ))
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
