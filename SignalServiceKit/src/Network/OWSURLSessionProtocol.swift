//
// Copyright 2022 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import SignalCoreKit

// MARK: - HTTPMethod

@objc
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
    public let task: URLSessionTask
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

@objc
public class OWSUrlFrontingInfo: NSObject, Dependencies {
    public let frontingURLWithoutPathPrefix: URL
    public let frontingURLWithPathPrefix: URL
    public let unfrontedBaseUrl: URL

    @objc
    public init(
        frontingURLWithoutPathPrefix: URL,
        frontingURLWithPathPrefix: URL,
        unfrontedBaseUrl: URL
    ) {
        self.frontingURLWithoutPathPrefix = frontingURLWithoutPathPrefix
        self.frontingURLWithPathPrefix = frontingURLWithPathPrefix
        self.unfrontedBaseUrl = unfrontedBaseUrl
    }

    var logDescription: String {
        "[frontingURLWithoutPathPrefix: \(frontingURLWithoutPathPrefix), frontingURLWithPathPrefix: \(frontingURLWithPathPrefix), unfrontedBaseUrl: \(unfrontedBaseUrl)]"
    }
}

// MARK: - OWSURLSession

// OWSURLSession is typically used for a single REST request.
//
// TODO: If we use OWSURLSession more, we'll need to add support for more features, e.g.:
//
// * Download tasks to memory.
public protocol OWSURLSessionProtocol: AnyObject, Dependencies {

    typealias ProgressBlock = (URLSessionTask, Progress) -> Void

    var baseUrl: URL? { get }
    var frontingInfo: OWSUrlFrontingInfo? { get }

    var failOnError: Bool { get set }
    // By default OWSURLSession treats 4xx and 5xx responses as errors.
    var require2xxOr3xx: Bool { get set }
    var shouldHandleRemoteDeprecation: Bool { get set }
    var allowRedirects: Bool { get set }

    var customRedirectHandler: ((URLRequest) -> URLRequest?)? { get set }

    static var defaultSecurityPolicy: OWSHTTPSecurityPolicy { get }
    static var signalServiceSecurityPolicy: OWSHTTPSecurityPolicy { get }
    static var defaultConfigurationWithCaching: URLSessionConfiguration { get }
    static var defaultConfigurationWithoutCaching: URLSessionConfiguration { get }

    static var userAgentHeaderKey: String { get }
    static var userAgentHeaderValueSignalIos: String { get }
    static var acceptLanguageHeaderKey: String { get }
    static var acceptLanguageHeaderValue: String { get }

    // MARK: Initializer

    init(
        baseUrl: URL?,
        frontingInfo: OWSUrlFrontingInfo?,
        securityPolicy: OWSHTTPSecurityPolicy,
        configuration: URLSessionConfiguration,
        extraHeaders: [String: String],
        maxResponseSize: Int?,
        canUseSignalProxy: Bool
    )

    // MARK: Request Building

    func buildRequest(
        _ urlString: String,
        method: HTTPMethod,
        headers: [String: String]?,
        body: Data?
    ) throws -> URLRequest

    // MARK: Tasks

    func uploadTaskPromise(
        request: URLRequest,
        data requestData: Data,
        progress progressBlock: ProgressBlock?
    ) -> Promise<HTTPResponse>

    func uploadTaskPromise(
        request: URLRequest,
        fileUrl: URL,
        ignoreAppExpiry: Bool,
        progress progressBlock: ProgressBlock?
    ) -> Promise<HTTPResponse>

    func dataTaskPromise(
        request: URLRequest,
        ignoreAppExpiry: Bool
    ) -> Promise<HTTPResponse>

    func downloadTaskPromise(
        requestUrl: URL,
        resumeData: Data,
        progress progressBlock: ProgressBlock?
    ) -> Promise<OWSUrlDownloadResponse>

    func downloadTaskPromise(
        request: URLRequest,
        progress progressBlock: ProgressBlock?
    ) -> Promise<OWSUrlDownloadResponse>
}

extension OWSURLSessionProtocol {
    public var unfrontedBaseUrl: URL? {
        frontingInfo?.unfrontedBaseUrl ?? baseUrl
    }

    public var isUsingCensorshipCircumvention: Bool {
        frontingInfo != nil
    }

    // MARK: Convenience Methods

    public init(
        baseUrl: URL? = nil,
        frontingInfo: OWSUrlFrontingInfo? = nil,
        securityPolicy: OWSHTTPSecurityPolicy,
        configuration: URLSessionConfiguration,
        extraHeaders: [String: String] = [:],
        maxResponseSize: Int? = nil,
        canUseSignalProxy: Bool = false
    ) {
        self.init(
            baseUrl: baseUrl,
            frontingInfo: frontingInfo,
            securityPolicy: securityPolicy,
            configuration: configuration,
            extraHeaders: extraHeaders,
            maxResponseSize: maxResponseSize,
            canUseSignalProxy: canUseSignalProxy
        )
    }

    func buildRequest(
        _ urlString: String,
        method: HTTPMethod,
        headers: [String: String]? = nil,
        body: Data? = nil
    ) throws -> URLRequest {
        try self.buildRequest(
            urlString,
            method: method,
            headers: headers,
            body: body
        )
    }
}

// MARK: -

public extension OWSURLSessionProtocol {

    // MARK: - Upload Tasks Convenience

    func uploadTaskPromise(
        request: URLRequest,
        data requestData: Data,
        progress progressBlock: ProgressBlock? = nil
    ) -> Promise<HTTPResponse> {
        return self.uploadTaskPromise(request: request, data: requestData, progress: progressBlock)
    }

    func uploadTaskPromise(
        _ urlString: String,
        method: HTTPMethod,
        headers: [String: String]? = nil,
        data requestData: Data,
        progress progressBlock: ProgressBlock? = nil
    ) -> Promise<HTTPResponse> {
        firstly(on: .global()) { () -> Promise<HTTPResponse> in
            let request = try self.buildRequest(urlString, method: method, headers: headers, body: requestData)
            return self.uploadTaskPromise(request: request, data: requestData, progress: progressBlock)
        }
    }

    func uploadTaskPromise(
        request: URLRequest,
        fileUrl: URL,
        ignoreAppExpiry: Bool = false,
        progress progressBlock: ProgressBlock? = nil
    ) -> Promise<HTTPResponse> {
        return self.uploadTaskPromise(
            request: request,
            fileUrl: fileUrl,
            ignoreAppExpiry: ignoreAppExpiry,
            progress: progressBlock
        )
    }

    func uploadTaskPromise(
        _ urlString: String,
        method: HTTPMethod,
        headers: [String: String]? = nil,
        fileUrl: URL,
        progress progressBlock: ProgressBlock? = nil
    ) -> Promise<HTTPResponse> {
        firstly(on: .global()) { () -> Promise<HTTPResponse> in
            let request = try self.buildRequest(urlString, method: method, headers: headers)
            return self.uploadTaskPromise(request: request, fileUrl: fileUrl, progress: progressBlock)
        }
    }

    // MARK: - Data Tasks Convenience

    func dataTaskPromise(
        request: URLRequest,
        ignoreAppExpiry: Bool = false
    ) -> Promise<HTTPResponse> {
        return dataTaskPromise(request: request, ignoreAppExpiry: ignoreAppExpiry)
    }

    func dataTaskPromise(
        _ urlString: String,
        method: HTTPMethod,
        headers: [String: String]? = nil,
        body: Data? = nil,
        ignoreAppExpiry: Bool = false
    ) -> Promise<HTTPResponse> {
        firstly(on: .global()) { () -> Promise<HTTPResponse> in
            let request = try self.buildRequest(urlString, method: method, headers: headers, body: body)
            return self.dataTaskPromise(request: request, ignoreAppExpiry: ignoreAppExpiry)
        }
    }

    // MARK: - Download Tasks Convenience

    func downloadTaskPromise(
        requestUrl: URL,
        resumeData: Data,
        progress progressBlock: ProgressBlock? = nil
    ) -> Promise<OWSUrlDownloadResponse> {
        return self.downloadTaskPromise(requestUrl: requestUrl, resumeData: resumeData, progress: progressBlock)
    }

    func downloadTaskPromise(
        request: URLRequest,
        progress progressBlock: ProgressBlock? = nil
    ) -> Promise<OWSUrlDownloadResponse> {
        return self.downloadTaskPromise(request: request, progress: progressBlock)
    }

    func downloadTaskPromise(
        _ urlString: String,
        method: HTTPMethod,
        headers: [String: String]? = nil,
        body: Data? = nil,
        progress progressBlock: ProgressBlock? = nil
    ) -> Promise<OWSUrlDownloadResponse> {
        firstly(on: .global()) { () -> Promise<OWSUrlDownloadResponse> in
            let request = try self.buildRequest(urlString, method: method, headers: headers, body: body)
            return self.downloadTaskPromise(request: request, progress: progressBlock)
        }
    }
}

// MARK: - MultiPart Task

extension OWSURLSessionProtocol {

    public func multiPartUploadTaskPromise(
        request: URLRequest,
        fileUrl inputFileURL: URL,
        name: String,
        fileName: String,
        mimeType: String,
        textParts textPartsDictionary: OrderedDictionary<String, String>,
        ignoreAppExpiry: Bool = false,
        progress progressBlock: ProgressBlock? = nil
    ) -> Promise<HTTPResponse> {
        do {
            let multipartBodyFileURL = OWSFileSystem.temporaryFileUrl(isAvailableWhileDeviceLocked: true)
            let boundary = OWSMultipartBody.createMultipartFormBoundary()
            // Order of form parts matters.
            let textParts = textPartsDictionary.map { (key, value) in
                OWSMultipartTextPart(key: key, value: value)
            }
            try OWSMultipartBody.write(forInputFileURL: inputFileURL,
                                       outputFileURL: multipartBodyFileURL,
                                       name: name,
                                       fileName: fileName,
                                       mimeType: mimeType,
                                       boundary: boundary,
                                       textParts: textParts)
            guard let bodyFileSize = OWSFileSystem.fileSize(of: multipartBodyFileURL) else {
                return Promise(error: OWSAssertionError("Missing bodyFileSize."))
            }

            var request = request
            request.httpMethod = HTTPMethod.post.methodName
            request.setValue(Self.userAgentHeaderValueSignalIos, forHTTPHeaderField: Self.userAgentHeaderKey)
            request.setValue(Self.acceptLanguageHeaderValue, forHTTPHeaderField: Self.acceptLanguageHeaderKey)
            request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
            request.setValue(String(format: "%llu", bodyFileSize.uint64Value), forHTTPHeaderField: "Content-Length")

            return firstly {
                uploadTaskPromise(request: request,
                                  fileUrl: multipartBodyFileURL,
                                  ignoreAppExpiry: ignoreAppExpiry,
                                  progress: progressBlock)
            }.ensure(on: .global()) {
                do {
                    try OWSFileSystem.deleteFileIfExists(url: multipartBodyFileURL)
                } catch {
                    owsFailDebug("Error: \(error)")
                }
            }
        } catch {
            owsFailDebugUnlessNetworkFailure(error)
            return Promise(error: error)
        }
    }
}
