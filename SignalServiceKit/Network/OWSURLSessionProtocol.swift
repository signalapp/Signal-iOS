//
// Copyright 2022 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

// MARK: - HTTPMethod

public enum HTTPMethod: UInt {
    case get
    case post
    case put
    case head
    case patch
    case delete

    public var methodName: String {
        switch self {
        case .get:
            return "GET"
        case .post:
            return "POST"
        case .put:
            return "PUT"
        case .head:
            return "HEAD"
        case .patch:
            return "PATCH"
        case .delete:
            return "DELETE"
        }
    }

    public static func method(for method: String?) throws -> HTTPMethod {
        switch method {
        case "GET":
            return .get
        case "POST":
            return .post
        case "PUT":
            return .put
        case "HEAD":
            return .head
        case "PATCH":
            return .patch
        case "DELETE":
            return .delete
        default:
            throw OWSAssertionError("Unknown method: \(String(describing: method))")
        }
    }
}

extension HTTPMethod: CustomStringConvertible {
    public var description: String { methodName }
}

// MARK: - OWSUrlDownloadResponse

public struct OWSUrlDownloadResponse {
    public let httpUrlResponse: HTTPURLResponse
    public let downloadUrl: URL

    public var statusCode: Int {
        httpUrlResponse.statusCode
    }

    public var allHeaderFields: [AnyHashable: Any] {
        httpUrlResponse.allHeaderFields
    }
}

// MARK: - OWSUrlFrontingInfo

struct OWSUrlFrontingInfo {
    public let frontingURLWithoutPathPrefix: URL
    public let frontingURLWithPathPrefix: URL
    public let unfrontedBaseUrl: URL

    func isFrontedUrl(_ urlString: String) -> Bool {
        urlString.lowercased().hasPrefix(frontingURLWithoutPathPrefix.absoluteString)
    }
}

// MARK: - OWSURLSession

// OWSURLSession is typically used for a single REST request.
//
// TODO: If we use OWSURLSession more, we'll need to add support for more features, e.g.:
//
// * Download tasks to memory.
public protocol OWSURLSessionProtocol: AnyObject {

    var endpoint: OWSURLSessionEndpoint { get }

    // By default OWSURLSession treats 4xx and 5xx responses as errors.
    var require2xxOr3xx: Bool { get set }
    var allowRedirects: Bool { get set }

    var customRedirectHandler: ((URLRequest) -> URLRequest?)? { get set }

    static var defaultSecurityPolicy: HttpSecurityPolicy { get }
    static var signalServiceSecurityPolicy: HttpSecurityPolicy { get }
    static var defaultConfigurationWithCaching: URLSessionConfiguration { get }
    static var defaultConfigurationWithoutCaching: URLSessionConfiguration { get }

    static var userAgentHeaderKey: String { get }
    static var userAgentHeaderValueSignalIos: String { get }
    static var acceptLanguageHeaderKey: String { get }
    static var acceptLanguageHeaderValue: String { get }

    // MARK: Initializer

    init(
        endpoint: OWSURLSessionEndpoint,
        configuration: URLSessionConfiguration,
        maxResponseSize: Int?,
        canUseSignalProxy: Bool
    )

    // MARK: Tasks

    func performRequest(_ rawRequest: TSRequest) async throws -> HTTPResponse

    func performUpload(
        request: URLRequest,
        requestData: Data,
        progress: OWSProgressSource?
    ) async throws -> HTTPResponse

    func performUpload(
        request: URLRequest,
        fileUrl: URL,
        ignoreAppExpiry: Bool,
        progress: OWSProgressSource?
    ) async throws -> HTTPResponse

    func performRequest(
        request: URLRequest,
        ignoreAppExpiry: Bool
    ) async throws -> HTTPResponse

    func performDownload(
        requestUrl: URL,
        resumeData: Data,
        progress: OWSProgressSource?
    ) async throws -> OWSUrlDownloadResponse

    func performDownload(
        request: URLRequest,
        progress: OWSProgressSource?
    ) async throws -> OWSUrlDownloadResponse

    func webSocketTask(
        requestUrl: URL,
        didOpenBlock: @escaping (String?) -> Void,
        didCloseBlock: @escaping (Error) -> Void
    ) -> URLSessionWebSocketTask
}

extension OWSURLSessionProtocol {
    var unfrontedBaseUrl: URL? {
        endpoint.frontingInfo?.unfrontedBaseUrl ?? endpoint.baseUrl
    }

    // MARK: Convenience Methods

    init(
        endpoint: OWSURLSessionEndpoint,
        configuration: URLSessionConfiguration,
        maxResponseSize: Int? = nil,
        canUseSignalProxy: Bool = false
    ) {
        self.init(
            endpoint: endpoint,
            configuration: configuration,
            maxResponseSize: maxResponseSize,
            canUseSignalProxy: canUseSignalProxy
        )
    }
}

// MARK: -

public extension OWSURLSessionProtocol {
    // MARK: - Upload Tasks Convenience

    func performUpload(
        _ urlString: String,
        method: HTTPMethod,
        headers: HttpHeaders = HttpHeaders(),
        requestData: Data,
        progress: OWSProgressSource? = nil
    ) async throws -> any HTTPResponse {
        let request = try self.endpoint.buildRequest(urlString, method: method, headers: headers, body: requestData)
        return try await self.performUpload(request: request, requestData: requestData, progress: progress)
    }

    func performUpload(
        _ urlString: String,
        method: HTTPMethod,
        headers: HttpHeaders = HttpHeaders(),
        fileUrl: URL,
        progress: OWSProgressSource? = nil
    ) async throws -> any HTTPResponse {
        let request = try self.endpoint.buildRequest(urlString, method: method, headers: headers)
        return try await self.performUpload(
            request: request,
            fileUrl: fileUrl,
            ignoreAppExpiry: false,
            progress: progress
        )
    }

    // MARK: - Data Tasks Convenience

    func performRequest(
        _ urlString: String,
        method: HTTPMethod,
        headers: HttpHeaders = HttpHeaders(),
        body: Data? = nil,
        ignoreAppExpiry: Bool = false
    ) async throws -> any HTTPResponse {
        let request = try self.endpoint.buildRequest(urlString, method: method, headers: headers, body: body)
        return try await self.performRequest(request: request, ignoreAppExpiry: ignoreAppExpiry)
    }

    // MARK: - Download Tasks Convenience

    func performDownload(
        _ urlString: String,
        method: HTTPMethod,
        headers: HttpHeaders = HttpHeaders(),
        body: Data? = nil,
        progress: OWSProgressSource? = nil
    ) async throws -> OWSUrlDownloadResponse {
        let request = try self.endpoint.buildRequest(urlString, method: method, headers: headers, body: body)
        return try await self.performDownload(request: request, progress: progress)
    }
}

// MARK: - MultiPart Task

extension OWSURLSessionProtocol {

    public func performMultiPartUpload(
        request: URLRequest,
        fileUrl inputFileURL: URL,
        name: String,
        fileName: String,
        mimeType: String,
        textParts textPartsDictionary: OrderedDictionary<String, String>,
        ignoreAppExpiry: Bool = false,
        progress: OWSProgressSource? = nil
    ) async throws -> any HTTPResponse {
        let multipartBodyFileURL = OWSFileSystem.temporaryFileUrl(isAvailableWhileDeviceLocked: true)
        defer {
            do {
                try OWSFileSystem.deleteFileIfExists(url: multipartBodyFileURL)
            } catch {
                owsFailDebug("Error: \(error)")
            }
        }
        let boundary = OWSMultipartBody.createMultipartFormBoundary()
        // Order of form parts matters.
        let textParts = textPartsDictionary.map { (key, value) in
            OWSMultipartTextPart(key: key, value: value)
        }
        try OWSMultipartBody.write(
            inputFile: inputFileURL,
            outputFile: multipartBodyFileURL,
            name: name,
            fileName: fileName,
            mimeType: mimeType,
            boundary: boundary,
            textParts: textParts
        )
        guard let bodyFileSize = OWSFileSystem.fileSize(of: multipartBodyFileURL) else {
            throw OWSAssertionError("Missing bodyFileSize.")
        }

        var request = request
        request.httpMethod = HTTPMethod.post.methodName
        request.setValue(Self.userAgentHeaderValueSignalIos, forHTTPHeaderField: Self.userAgentHeaderKey)
        request.setValue(Self.acceptLanguageHeaderValue, forHTTPHeaderField: Self.acceptLanguageHeaderKey)
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.setValue(String(format: "%llu", bodyFileSize.uint64Value), forHTTPHeaderField: "Content-Length")

        return try await performUpload(
            request: request,
            fileUrl: multipartBodyFileURL,
            ignoreAppExpiry: ignoreAppExpiry,
            progress: progress
        )
    }
}
