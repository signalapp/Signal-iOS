//
// Copyright 2022 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

public class OWSURLSessionMock: OWSURLSessionProtocol {

    // MARK: - OWSURLSessionProtocol conformance

    public var baseUrl: URL?

    public var frontingInfo: OWSUrlFrontingInfo?

    public var failOnError: Bool = true

    public var require2xxOr3xx: Bool = true

    public var shouldHandleRemoteDeprecation: Bool = false

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
    private let securityPolicy: OWSHTTPSecurityPolicy
    private let extraHeaders: [String: String]
    private let maxResponseSize: Int?

    public required init(
        baseUrl: URL?,
        frontingInfo: OWSUrlFrontingInfo?,
        securityPolicy: OWSHTTPSecurityPolicy,
        configuration: URLSessionConfiguration,
        extraHeaders: [String: String],
        maxResponseSize: Int?
    ) {
        self.baseUrl = baseUrl
        self.frontingInfo = frontingInfo
        self.securityPolicy = securityPolicy
        self.configuration = configuration
        self.extraHeaders = extraHeaders
        self.maxResponseSize = maxResponseSize
    }

    public convenience init() {
        self.init(
            baseUrl: nil,
            frontingInfo: nil,
            securityPolicy: .systemDefault(),
            configuration: .default,
            extraHeaders: [:],
            maxResponseSize: nil
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
}
