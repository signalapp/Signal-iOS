//
//  Copyright (c) 2021 Open Whisper Systems. All rights reserved.
//

import Foundation
import PromiseKit

public enum HTTPMethod {
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

// MARK: -

public enum OWSHTTPError: Error {
    case requestError(statusCode: Int, httpUrlResponse: HTTPURLResponse)
}

// MARK: -

public struct OWSHTTPResponse {
    public let task: URLSessionTask
    public let httpUrlResponse: HTTPURLResponse
    public let responseData: Data?

    public var statusCode: Int {
        httpUrlResponse.statusCode
    }

    public var allHeaderFields: [AnyHashable: Any] {
        httpUrlResponse.allHeaderFields
    }
}

// MARK: -

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

// MARK: -

// OWSURLSession is typically used for a single REST request.
//
// TODO: If we use OWSURLSession more, we'll need to add support for more features, e.g.:
//
// * Download tasks to memory.
@objc
public class OWSURLSession: NSObject {

    private static let operationQueue: OperationQueue = {
        let queue = OperationQueue()
        queue.underlyingQueue = .global()
        return queue
    }()

    private let baseUrl: URL?

    private let configuration: URLSessionConfiguration

    // TODO: Replace AFSecurityPolicy.
    private let securityPolicy: AFSecurityPolicy

    private let extraHeaders: [String: String]

    private let httpShouldHandleCookies = AtomicBool(false)

    @objc
    public let censorshipCircumventionHost: String?

    @objc
    public var isUsingCensorshipCircumvention: Bool {
        censorshipCircumventionHost != nil
    }

    private let _failOnError = AtomicBool(true)
    @objc
    public var failOnError: Bool {
        get {
            _failOnError.get()
        }
        set {
            _failOnError.set(newValue)
        }
    }

    // By default OWSURLSession treats 4xx and 5xx responses as errors.
    private let _require2xxOr3xx = AtomicBool(true)
    @objc
    public var require2xxOr3xx: Bool {
        get {
            _require2xxOr3xx.get()
        }
        set {
            _require2xxOr3xx.set(newValue)
        }
    }

    private let _shouldHandleRemoteDeprecation = AtomicBool(false)
    @objc
    public var shouldHandleRemoteDeprecation: Bool {
        get {
            _shouldHandleRemoteDeprecation.get()
        }
        set {
            _shouldHandleRemoteDeprecation.set(newValue)
        }
    }

    private let _allowRedirects = AtomicBool(true)
    @objc
    public var allowRedirects: Bool {
        get {
            _allowRedirects.get()
        }
        set {
            owsAssertDebug(customRedirectHandler == nil || newValue)
            _allowRedirects.set(newValue)
        }
    }

    private let _customRedirectHandler = AtomicOptional<(URLRequest) -> URLRequest?>(nil)
    @objc
    public var customRedirectHandler: ((URLRequest) -> URLRequest?)? {
        get {
            _customRedirectHandler.get()
        }
        set {
            owsAssertDebug(newValue == nil || allowRedirects)
            _customRedirectHandler.set(newValue)
        }
    }

    private lazy var session: URLSession = {
        URLSession(configuration: configuration, delegate: delegateBox, delegateQueue: Self.operationQueue)
    }()

    @objc
    public static var defaultSecurityPolicy: AFSecurityPolicy {
        AFSecurityPolicy.default()
    }

    @objc
    public static var signalServiceSecurityPolicy: AFSecurityPolicy {
        OWSHTTPSecurityPolicy.shared()
    }

    @objc
    public static var defaultConfigurationWithCaching: URLSessionConfiguration {
        .ephemeral
    }

    @objc
    public static var defaultConfigurationWithoutCaching: URLSessionConfiguration {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.urlCache = nil
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        return configuration
    }

    private let maxResponseSize: Int?

    public init(baseUrl: URL? = nil,
                securityPolicy: AFSecurityPolicy,
                configuration: URLSessionConfiguration,
                censorshipCircumventionHost: String? = nil,
                extraHeaders: [String: String] = [:],
                maxResponseSize: Int? = nil) {
        self.baseUrl = baseUrl
        self.securityPolicy = securityPolicy
        self.configuration = configuration
        self.censorshipCircumventionHost = censorshipCircumventionHost
        self.extraHeaders = extraHeaders
        self.maxResponseSize = maxResponseSize

        super.init()

        // Ensure this is set so that we don't try to create it in deinit().
        _ = self.delegateBox
    }

    @objc
    public init(baseUrl: URL? = nil,
                securityPolicy: AFSecurityPolicy,
                configuration: URLSessionConfiguration,
                censorshipCircumventionHost: String? = nil,
                extraHeaders: [String: String] = [:]) {
        self.baseUrl = baseUrl
        self.securityPolicy = securityPolicy
        self.configuration = configuration
        self.censorshipCircumventionHost = censorshipCircumventionHost
        self.extraHeaders = extraHeaders
        self.maxResponseSize = nil

        super.init()

        // Ensure this is set so that we don't try to create it in deinit().
        _ = self.delegateBox
    }

    deinit {
        // From NSURLSession.h
        // If you do not invalidate the session by calling the invalidateAndCancel() or
        // finishTasksAndInvalidate() method, your app leaks memory until it exits
        //
        // Even though there will be no reference cycle, underlying NSURLSession metadata
        // is malloced and kept around as a root leak.
        session.invalidateAndCancel()
    }

    private struct RequestConfig {
        let task: URLSessionTask
        let require2xxOr3xx: Bool
        let failOnError: Bool
        let shouldHandleRemoteDeprecation: Bool
    }

    private func requestConfig(forTask task: URLSessionTask) -> RequestConfig {
        // Snapshot session state at time request is made.
        RequestConfig(task: task,
                      require2xxOr3xx: require2xxOr3xx,
                      failOnError: failOnError,
                      shouldHandleRemoteDeprecation: shouldHandleRemoteDeprecation)
    }

    private class func uploadOrDataTaskCompletionPromise(requestConfig: RequestConfig,
                                                         responseData: Data?) -> Promise<OWSHTTPResponse> {
        firstly {
            baseCompletionPromise(requestConfig: requestConfig, responseData: responseData)
        }.map(on: .global()) { (httpUrlResponse: HTTPURLResponse) -> OWSHTTPResponse in
            OWSHTTPResponse(task: requestConfig.task,
                            httpUrlResponse: httpUrlResponse,
                            responseData: responseData)
        }
    }

    private class func downloadTaskCompletionPromise(requestConfig: RequestConfig,
                                                     downloadUrl: URL) -> Promise<OWSUrlDownloadResponse> {
        firstly {
            baseCompletionPromise(requestConfig: requestConfig, responseData: nil)
        }.map(on: .global()) { (httpUrlResponse: HTTPURLResponse) -> OWSUrlDownloadResponse in
            return OWSUrlDownloadResponse(task: requestConfig.task,
                                          httpUrlResponse: httpUrlResponse,
                                          downloadUrl: downloadUrl)
        }
    }

    private class func baseCompletionPromise(requestConfig: RequestConfig,
                                             responseData: Data?) -> Promise<HTTPURLResponse> {

        firstly(on: .global()) { () -> HTTPURLResponse in
            let task = requestConfig.task

            if requestConfig.shouldHandleRemoteDeprecation {
                checkForRemoteDeprecation(task: task, response: task.response)
            }

            if let error = task.error {
                if IsNetworkConnectivityFailure(error) {
                    Logger.warn("Request failed: \(error)")
                } else {
                    #if TESTABLE_BUILD
                    TSNetworkManager.logCurl(for: task)

                    if let responseData = responseData,
                       let httpUrlResponse = task.response as? HTTPURLResponse,
                       let contentType = httpUrlResponse.allHeaderFields["Content-Type"] as? String,
                       contentType == OWSMimeTypeJson,
                       let jsonString = String(data: responseData, encoding: .utf8) {
                        Logger.verbose("Response JSON: \(jsonString)")
                    }
                    #endif

                    if requestConfig.failOnError,
                       !error.isUnknownDomainError {
                        owsFailDebugUnlessNetworkFailure(error)
                    } else {
                        Logger.error("Request failed: \(error)")
                    }
                }
                throw error
            }
            guard let httpUrlResponse = task.response as? HTTPURLResponse else {
                throw OWSAssertionError("Invalid response: \(type(of: task.response)).")
            }

            if requestConfig.require2xxOr3xx {
                let statusCode = httpUrlResponse.statusCode
                guard statusCode >= 200, statusCode < 400 else {
                    #if TESTABLE_BUILD
                    TSNetworkManager.logCurl(for: task)
                    Logger.verbose("Status code: \(statusCode)")
                    #endif

                    throw OWSHTTPError.requestError(statusCode: statusCode, httpUrlResponse: httpUrlResponse)
                }
            }

            #if TESTABLE_BUILD
            if DebugFlags.logCurlOnSuccess {
                TSNetworkManager.logCurl(for: task)
            }
            #endif

            return httpUrlResponse
        }
    }

    private class func checkForRemoteDeprecation(task: URLSessionTask,
                                                 response: URLResponse?) {

        guard let httpResponse = response as? HTTPURLResponse,
            httpResponse.statusCode == AppExpiry.appExpiredStatusCode else {
                return
        }

        AppExpiry.shared.setHasAppExpiredAtCurrentVersion()
    }

    // MARK: -

    private func buildRequest(_ urlString: String,
                              method: HTTPMethod,
                              headers: [String: String]? = nil,
                              body: Data? = nil) throws -> URLRequest {
        guard let url = buildUrl(urlString) else {
            throw OWSAssertionError("Invalid url.")
        }
        var request = URLRequest(url: url)
        request.httpMethod = method.methodName

        let httpHeaders = OWSHttpHeaders()
        httpHeaders.addHeaders(headers, overwriteOnConflict: false)
        httpHeaders.addHeader(Self.kUserAgentHeader, value: Self.signalIosUserAgent, overwriteOnConflict: true)
        httpHeaders.addHeaders(extraHeaders, overwriteOnConflict: true)
        request.add(httpHeaders: httpHeaders)

        request.httpBody = body
        request.httpShouldHandleCookies = httpShouldHandleCookies.get()
        return request
    }

    @objc
    public static let kUserAgentHeader = "User-Agent"

    @objc
    public static var signalIosUserAgent: String {
        "Signal-iOS/\(AppVersion.shared().currentAppVersionLong) iOS/\(UIDevice.current.systemVersion)"
    }

    private func buildUrl(_ urlString: String) -> URL? {
        guard let censorshipCircumventionHost = censorshipCircumventionHost else {
            // Censorship circumvention not active.
            guard let requestUrl = URL(string: urlString, relativeTo: baseUrl) else {
                owsFailDebug("Could not build URL.")
                return nil
            }
            return requestUrl
        }

        // Censorship circumvention active.
        guard !censorshipCircumventionHost.isEmpty else {
            owsFailDebug("Invalid censorshipCircumventionHost.")
            return nil
        }
        guard let baseUrl = baseUrl else {
            owsFailDebug("Censorship circumvention requires baseUrl.")
            return nil
        }

        let hasValidUrl = (urlString.hasPrefix(censorshipCircumventionHost) ||
            urlString.hasPrefix("http://" + censorshipCircumventionHost) ||
            urlString.hasPrefix("https://" + censorshipCircumventionHost))
        if hasValidUrl {
            // urlString has expected protocol/host.
        } else if urlString.lowercased().hasPrefix("http") {
            // Censorship circumvention will work with relative URLs and
            // absolute URLs that match the expected protocol/host prefix.
            // Other absolute URLs should not be used with this session.
            owsFailDebug("Unexpected URL for censorship circumvention.")
        }

        guard let requestUrl = Self.buildUrl(urlString: urlString, baseUrl: baseUrl) else {
            owsFailDebug("Could not build URL.")
            return nil
        }
        return requestUrl
    }

    @objc(buildUrlWithString:baseUrl:)
    public class func buildUrl(urlString: String, baseUrl: URL?) -> URL? {
        guard let baseUrl = baseUrl else {
            guard let requestUrl = URL(string: urlString, relativeTo: nil) else {
                owsFailDebug("Could not build URL.")
                return nil
            }
            return requestUrl
        }

        // Ensure the base URL has a trailing "/".
        let safeBaseUrl: URL = (baseUrl.absoluteString.hasSuffix("/")
            ? baseUrl
            : baseUrl.appendingPathComponent(""))

        guard let requestComponents = URLComponents(string: urlString) else {
            owsFailDebug("Could not rewrite URL.")
            return nil
        }

        var finalComponents = URLComponents()

        // Use scheme and host from baseUrl.
        finalComponents.scheme = baseUrl.scheme
        finalComponents.host = baseUrl.host

        // Use query and fragement from the request.
        finalComponents.query = requestComponents.query
        finalComponents.fragment = requestComponents.fragment

        // Join the paths.
        finalComponents.path = (safeBaseUrl.path as NSString).appendingPathComponent(requestComponents.path)

        guard let finalUrlString = finalComponents.string else {
            owsFailDebug("Could not rewrite URL.")
            return nil
        }

        guard let finalUrl = URL(string: finalUrlString) else {
            owsFailDebug("Could not rewrite URL.")
            return nil
        }
        return finalUrl
    }

    // MARK: - TaskState

    private let lock = UnfairLock()
    lazy private var delegateBox = URLSessionDelegateBox(delegate: self)

    typealias TaskIdentifier = Int
    public typealias ProgressBlock = (URLSessionTask, Progress) -> Void

    private typealias TaskStateMap = [TaskIdentifier: TaskState]
    private var taskStateMap = TaskStateMap() {
        didSet {
            delegateBox.isRetaining = (taskStateMap.count > 0)
        }
    }

    private func addTask(_ task: URLSessionTask, taskState: TaskState) {
        lock.withLock {
            owsAssertDebug(self.taskStateMap[task.taskIdentifier] == nil)
            self.taskStateMap[task.taskIdentifier] = taskState
        }
    }

    private func progressBlock(forTask task: URLSessionTask) -> ProgressBlock? {
        lock.withLock {
            self.taskStateMap[task.taskIdentifier]?.progressBlock
        }
    }

    private func removeCompletedTaskState(_ task: URLSessionTask) -> TaskState? {
        lock.withLock { () -> TaskState? in
            guard let taskState = self.taskStateMap[task.taskIdentifier] else {
                owsFailDebug("Missing TaskState.")
                return nil
            }
            self.taskStateMap[task.taskIdentifier] = nil
            return taskState
        }
    }

    private func downloadTaskDidSucceed(_ task: URLSessionTask, downloadUrl: URL) {
        guard let taskState = removeCompletedTaskState(task) as? DownloadTaskState else {
            owsFailDebug("Missing TaskState.")
            return
        }
        taskState.resolver.fulfill((task, downloadUrl))
    }

    private func uploadOrDataTaskDidSucceed(_ task: URLSessionTask, responseData: Data?) {
        guard let taskState = removeCompletedTaskState(task) as? UploadOrDataTaskState else {
            owsFailDebug("Missing TaskState.")
            return
        }
        taskState.resolver.fulfill((task, responseData))
    }

    private func taskDidFail(_ task: URLSessionTask, error: Error) {
        guard let taskState = removeCompletedTaskState(task) else {
            owsFailDebug("Missing TaskState.")
            return
        }
        taskState.reject(error: error)
    }

    // MARK: -

    public typealias URLAuthenticationChallengeCompletion = (URLSession.AuthChallengeDisposition, URLCredential?) -> Void

    fileprivate func urlSession(didReceive challenge: URLAuthenticationChallenge,
                                completionHandler: @escaping URLAuthenticationChallengeCompletion) {

        var disposition: URLSession.AuthChallengeDisposition = .performDefaultHandling
        var credential: URLCredential?

        if challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust,
            let serverTrust = challenge.protectionSpace.serverTrust {
            if securityPolicy.evaluateServerTrust(serverTrust, forDomain: challenge.protectionSpace.host) {
                credential = URLCredential(trust: serverTrust)
                disposition = .useCredential
            } else {
                disposition = .cancelAuthenticationChallenge
            }
        } else {
            disposition = .performDefaultHandling
        }

        completionHandler(disposition, credential)
    }
}

// MARK: -

extension OWSURLSession: URLSessionDelegate {

    public func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        if let error = error {
            Logger.info("Error: \(error)")
            taskDidFail(task, error: error)
        }
    }

    public func urlSession(_ session: URLSession,
                           didReceive challenge: URLAuthenticationChallenge,
                           completionHandler: @escaping URLAuthenticationChallengeCompletion) {
        urlSession(didReceive: challenge, completionHandler: completionHandler)
    }

    public func urlSession(_ session: URLSession,
                           task: URLSessionTask,
                           willPerformHTTPRedirection response: HTTPURLResponse,
                           newRequest: URLRequest,
                           completionHandler: @escaping (URLRequest?) -> Void) {
        guard allowRedirects else { return completionHandler(nil) }

        if let customRedirectHandler = customRedirectHandler {
            completionHandler(customRedirectHandler(newRequest))
        } else {
            completionHandler(newRequest)
        }
    }
}

// MARK: -

extension OWSURLSession: URLSessionTaskDelegate {

    public func urlSession(_ session: URLSession,
                           task: URLSessionTask,
                           didReceive challenge: URLAuthenticationChallenge,
                           completionHandler: @escaping URLAuthenticationChallengeCompletion) {

        urlSession(didReceive: challenge, completionHandler: completionHandler)
    }

    public func urlSession(_ session: URLSession, task: URLSessionTask, didSendBodyData bytesSent: Int64, totalBytesSent: Int64, totalBytesExpectedToSend: Int64) {
        guard let progressBlock = self.progressBlock(forTask: task) else {
            return
        }
        let progress = Progress(parent: nil, userInfo: nil)
        // TODO: We could check for NSURLSessionTransferSizeUnknown here.
        progress.totalUnitCount = totalBytesExpectedToSend
        progress.completedUnitCount = totalBytesSent
        progressBlock(task, progress)
    }
}

// MARK: -

extension OWSURLSession: URLSessionDownloadDelegate {

    public func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        if let maxResponseSize = maxResponseSize {
            guard let fileSize = OWSFileSystem.fileSize(of: location) else {
                taskDidFail(downloadTask, error: OWSAssertionError("Unknown download size."))
                return
            }
            guard fileSize.intValue <= maxResponseSize else {
                taskDidFail(downloadTask, error: OWSAssertionError("Oversize download."))
                return
            }
        }
        do {
            // Download locations are cleaned up quickly, so we
            // need to move the file synchronously.
            let temporaryUrl = OWSFileSystem.temporaryFileUrl(fileExtension: nil,
                                                              isAvailableWhileDeviceLocked: true)
            try OWSFileSystem.moveFile(from: location, to: temporaryUrl)
            downloadTaskDidSucceed(downloadTask, downloadUrl: temporaryUrl)
        } catch {
            owsFailDebugUnlessNetworkFailure(error)

            taskDidFail(downloadTask, error: error)
        }
    }

    public func urlSession(_ session: URLSession,
                           downloadTask: URLSessionDownloadTask,
                           didWriteData bytesWritten: Int64,
                           totalBytesWritten: Int64,
                           totalBytesExpectedToWrite: Int64) {
        if let maxResponseSize = maxResponseSize {
            guard totalBytesWritten <= maxResponseSize,
                  totalBytesExpectedToWrite <= maxResponseSize else {
                downloadTask.cancel()
                return
            }
        }
        guard let progressBlock = self.progressBlock(forTask: downloadTask) else {
            return
        }
        let progress = Progress(parent: nil, userInfo: nil)
        progress.totalUnitCount = totalBytesExpectedToWrite
        progress.completedUnitCount = totalBytesWritten
        progressBlock(downloadTask, progress)
    }

    public func urlSession(_ session: URLSession,
                           downloadTask: URLSessionDownloadTask,
                           didResumeAtOffset fileOffset: Int64,
                           expectedTotalBytes: Int64) {
        if let maxResponseSize = maxResponseSize {
            guard fileOffset <= maxResponseSize,
                  expectedTotalBytes <= maxResponseSize else {
                downloadTask.cancel()
                return
            }
        }
        guard let progressBlock = self.progressBlock(forTask: downloadTask) else {
            return
        }
        let progress = Progress(parent: nil, userInfo: nil)
        progress.totalUnitCount = expectedTotalBytes
        progress.completedUnitCount = fileOffset
        progressBlock(downloadTask, progress)
    }

    public func urlSession(_ session: URLSession,
                    dataTask: URLSessionDataTask,
                    didReceive response: URLResponse,
                    completionHandler: @escaping (URLSession.ResponseDisposition) -> Void) {
        guard let maxResponseSize = maxResponseSize else {
            completionHandler(.allow)
            return
        }
        if response.expectedContentLength == NSURLSessionTransferSizeUnknown {
            completionHandler(.allow)
            return
        }
        guard response.expectedContentLength <= maxResponseSize else {
            owsFailDebug("Oversize response: \(response.expectedContentLength) > \(maxResponseSize)")
            completionHandler(.cancel)
            return
        }
        completionHandler(.allow)
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        guard let maxResponseSize = maxResponseSize else {
            return
        }
        guard dataTask.countOfBytesReceived <= maxResponseSize else {
            owsFailDebug("Oversize response: \(dataTask.countOfBytesReceived) > \(maxResponseSize)")
            dataTask.cancel()
            return
        }
    }
}

// MARK: -

public extension OWSURLSession {

    // MARK: - Upload Tasks

    func uploadTaskPromise(_ urlString: String,
                           method: HTTPMethod,
                           headers: [String: String]? = nil,
                           data requestData: Data,
                           progress progressBlock: ProgressBlock? = nil) -> Promise<OWSHTTPResponse> {
        firstly(on: .global()) { () -> Promise<OWSHTTPResponse> in
            let request = try self.buildRequest(urlString, method: method, headers: headers)
            return self.uploadTaskPromise(request: request, data: requestData, progress: progressBlock)
        }
    }

    func uploadTaskPromise(request: URLRequest,
                           data requestData: Data,
                           progress progressBlock: ProgressBlock? = nil) -> Promise<OWSHTTPResponse> {

        guard !Self.appExpiry.isExpired else {
            return Promise(error: OWSAssertionError("App is expired."))
        }

        let taskState = UploadOrDataTaskState(progressBlock: progressBlock)
        var requestConfig: RequestConfig?
        let task = session.uploadTask(with: request, from: requestData) { [weak self] (responseData: Data?, _: URLResponse?, _: Error?) in
            guard let requestConfig = requestConfig else {
                owsFailDebug("Missing requestConfig.")
                return
            }
            self?.uploadOrDataTaskDidSucceed(requestConfig.task, responseData: responseData)
        }
        addTask(task, taskState: taskState)
        requestConfig = self.requestConfig(forTask: task)
        task.resume()

        return firstly { () -> Promise<(URLSessionTask, Data?)> in
            taskState.promise
        }.then(on: .global()) { (_, responseData: Data?) -> Promise<OWSHTTPResponse> in
            guard let requestConfig = requestConfig else {
                throw OWSAssertionError("Missing requestConfig.")
            }
            return Self.uploadOrDataTaskCompletionPromise(requestConfig: requestConfig, responseData: responseData)
        }
    }

    func uploadTaskPromise(_ urlString: String,
                           method: HTTPMethod,
                           headers: [String: String]? = nil,
                           dataUrl: URL,
                           progress progressBlock: ProgressBlock? = nil) -> Promise<OWSHTTPResponse> {
        firstly(on: .global()) { () -> Promise<OWSHTTPResponse> in
            let request = try self.buildRequest(urlString, method: method, headers: headers)
            return self.uploadTaskPromise(request: request, dataUrl: dataUrl, progress: progressBlock)
        }
    }

    func uploadTaskPromise(request: URLRequest,
                           dataUrl: URL,
                           progress progressBlock: ProgressBlock? = nil) -> Promise<OWSHTTPResponse> {

        guard !Self.appExpiry.isExpired else {
            return Promise(error: OWSAssertionError("App is expired."))
        }

        let taskState = UploadOrDataTaskState(progressBlock: progressBlock)
        var requestConfig: RequestConfig?
        let task = session.uploadTask(with: request, fromFile: dataUrl) { [weak self] (responseData: Data?, _: URLResponse?, _: Error?) in
            guard let requestConfig = requestConfig else {
                owsFailDebug("Missing requestConfig.")
                return
            }
            self?.uploadOrDataTaskDidSucceed(requestConfig.task, responseData: responseData)
        }
        addTask(task, taskState: taskState)
        requestConfig = self.requestConfig(forTask: task)
        task.resume()

        return firstly { () -> Promise<(URLSessionTask, Data?)> in
            taskState.promise
        }.then(on: .global()) { (_, responseData: Data?) -> Promise<OWSHTTPResponse> in
            guard let requestConfig = requestConfig else {
                throw OWSAssertionError("Missing requestConfig.")
            }
            return Self.uploadOrDataTaskCompletionPromise(requestConfig: requestConfig, responseData: responseData)
        }
    }

    // MARK: - Data Tasks

    func dataTaskPromise(_ urlString: String,
                         method: HTTPMethod,
                         headers: [String: String]? = nil,
                         body: Data? = nil) -> Promise<OWSHTTPResponse> {
        firstly(on: .global()) { () -> Promise<OWSHTTPResponse> in
            let request = try self.buildRequest(urlString, method: method, headers: headers, body: body)
            return self.dataTaskPromise(request: request)
        }
    }

    func dataTaskPromise(request: URLRequest) -> Promise<OWSHTTPResponse> {

        guard !Self.appExpiry.isExpired else {
            return Promise(error: OWSAssertionError("App is expired."))
        }

        let taskState = UploadOrDataTaskState(progressBlock: nil)
        var requestConfig: RequestConfig?
        let task = session.dataTask(with: request) { [weak self] (responseData: Data?, _: URLResponse?, _: Error?) in
            guard let self = self else {
                owsFailDebug("Missing session.")
                return
            }
            guard let requestConfig = requestConfig else {
                owsFailDebug("Missing requestConfig.")
                return
            }
            if let responseData = responseData,
               let maxResponseSize = self.maxResponseSize {
                guard responseData.count <= maxResponseSize else {
                    self.taskDidFail(requestConfig.task, error: OWSAssertionError("Oversize download."))
                    return
                }
            }
            self.uploadOrDataTaskDidSucceed(requestConfig.task, responseData: responseData)
        }
        addTask(task, taskState: taskState)
        requestConfig = self.requestConfig(forTask: task)
        task.resume()

        return firstly { () -> Promise<(URLSessionTask, Data?)> in
            taskState.promise
        }.then(on: .global()) { (_, responseData: Data?) -> Promise<OWSHTTPResponse> in
            guard let requestConfig = requestConfig else {
                throw OWSAssertionError("Missing requestConfig.")
            }
            return Self.uploadOrDataTaskCompletionPromise(requestConfig: requestConfig, responseData: responseData)
        }
    }

    // MARK: - Download Tasks

    func urlDownloadTaskPromise(_ urlString: String,
                                method: HTTPMethod,
                                headers: [String: String]? = nil,
                                body: Data? = nil,
                                progress progressBlock: ProgressBlock? = nil) -> Promise<OWSUrlDownloadResponse> {
        firstly(on: .global()) { () -> Promise<OWSUrlDownloadResponse> in
            let request = try self.buildRequest(urlString, method: method, headers: headers, body: body)
            return self.urlDownloadTaskPromise(request: request,
                                               progress: progressBlock)
        }
    }

    func urlDownloadTaskPromise(request: URLRequest,
                                progress progressBlock: ProgressBlock? = nil) -> Promise<OWSUrlDownloadResponse> {
        urlDownloadTaskPromise(progress: progressBlock) {
            // Don't use a completion block or the delegate will be ignored for download tasks.
            session.downloadTask(with: request)
        }
    }

    func urlDownloadTaskPromise(resumeData: Data,
                                progress progressBlock: ProgressBlock? = nil) -> Promise<OWSUrlDownloadResponse> {
        urlDownloadTaskPromise(progress: progressBlock) {
            // Don't use a completion block or the delegate will be ignored for download tasks.
            session.downloadTask(withResumeData: resumeData)
        }
    }

    private func urlDownloadTaskPromise(progress progressBlock: ProgressBlock? = nil,
                                        taskBlock: () -> URLSessionDownloadTask) -> Promise<OWSUrlDownloadResponse> {

        guard !Self.appExpiry.isExpired else {
            return Promise(error: OWSAssertionError("App is expired."))
        }

        let taskState = DownloadTaskState(progressBlock: progressBlock)
        var requestConfig: RequestConfig?
        let task = taskBlock()
        addTask(task, taskState: taskState)
        requestConfig = self.requestConfig(forTask: task)
        task.resume()

        return firstly { () -> Promise<(URLSessionTask, URL)> in
            taskState.promise
        }.then(on: .global()) { (_: URLSessionTask, downloadUrl: URL) -> Promise<OWSUrlDownloadResponse> in
            guard let requestConfig = requestConfig else {
                throw OWSAssertionError("Missing requestConfig.")
            }
            return Self.downloadTaskCompletionPromise(requestConfig: requestConfig, downloadUrl: downloadUrl)
        }
    }
}

// MARK: - HTTP Headers

// HTTP headers are case-insensitive.
// This class handles conflict resolution.
@objc
public class OWSHttpHeaders: NSObject {
    @objc
    public var headers = [String: String]()

    @objc
    public override init() {}

    @objc
    public init(httpHeaders: [String: String]?) {}

    @objc
    public func hasValueForHeader(_ header: String) -> Bool {
        Set(headers.keys.map { $0.lowercased() }).contains(header.lowercased())
    }

    @objc
    public func removeValueForHeader(_ header: String) {
        headers = headers.filter { $0.key.lowercased() != header.lowercased() }
        owsAssertDebug(!hasValueForHeader(header))
    }

    @objc(addHeader:value:overwriteOnConflict:)
    public func addHeader(_ header: String, value: String, overwriteOnConflict: Bool) {
        addHeaders([header: value], overwriteOnConflict: overwriteOnConflict)
    }

    @objc
    public func addHeaders(_ newHttpHeaders: [String: String]?,
                           overwriteOnConflict: Bool) {
        guard let newHttpHeaders = newHttpHeaders else {
            return
        }
        for (headerField, headerValue) in newHttpHeaders {
            let hasConflict = hasValueForHeader(headerField)
            if hasConflict {
                if overwriteOnConflict {
                    // We expect to overwrite the User-Agent; don't log it.
                    if headerField.lowercased() != "User-Agent".lowercased() {
                        Logger.verbose("Overwriting header: \(headerField)")
                    }
                    // Remove existing value.
                    removeValueForHeader(headerField)
                } else {
                    owsFailDebug("Skipping redundant header: \(headerField)")
                    continue
                }
            }

            headers[headerField] = headerValue
        }
    }
}

// MARK: - HTTP Headers

public extension URLRequest {
    mutating func add(httpHeaders: OWSHttpHeaders) {
        for (headerField, headerValue) in httpHeaders.headers {
            addValue(headerValue, forHTTPHeaderField: headerField)
        }
    }
}

// MARK: - TaskState

private protocol TaskState {
    typealias ProgressBlock = (URLSessionTask, Progress) -> Void

    var progressBlock: ProgressBlock? { get }

    func reject(error: Error)
}

// MARK: - TaskState

private class DownloadTaskState: TaskState {
    let progressBlock: ProgressBlock?
    let promise: Promise<(URLSessionTask, URL)>
    let resolver: Resolver<(URLSessionTask, URL)>

    init(progressBlock: ProgressBlock?) {
        self.progressBlock = progressBlock

        let (promise, resolver) = Promise<(URLSessionTask, URL)>.pending()
        self.promise = promise
        self.resolver = resolver
    }

    func reject(error: Error) {
        resolver.reject(error)
    }
}

// MARK: - TaskState

private class UploadOrDataTaskState: TaskState {
    let progressBlock: ProgressBlock?
    let promise: Promise<(URLSessionTask, Data?)>
    let resolver: Resolver<(URLSessionTask, Data?)>

    init(progressBlock: ProgressBlock?) {
        self.progressBlock = progressBlock

        let (promise, resolver) = Promise<(URLSessionTask, Data?)>.pending()
        self.promise = promise
        self.resolver = resolver
    }

    func reject(error: Error) {
        resolver.reject(error)
    }
}

// NSURLSession maintains a strong reference to its delegate until explicitly invalidated
// OWSURLSession acts as its own delegate, and may be retained by any number of owners
// We don't really know when to invalidate our session, because a caller may decide to reuse a session
// at any time.
//
// So here's the plan:
// - While we have any outstanding tasks, a strong reference cycle is maintained. Promise holders
//   don't need to hold on to the session while waiting for a promise to resolve.
//   i.e.   OWSURLSession --(session)--> URLSession --(delegate)--> URLSessionDelegateBox
//              ^-----------------------(strongReference)-------------------|
//
// - Once all outstanding tasks have been resolved, the box breaks its reference. If there are no
//   external references to the OWSURLSession, then everything cleans itself up.
//   i.e.   OWSURLSession --(session)--> URLSession --(delegate)--> URLSessionDelegateBox
//                                                x-----(weakDelegate)-----|
//
private class URLSessionDelegateBox: NSObject {

    private weak var weakDelegate: OWSURLSession?
    private var strongReference: OWSURLSession?

    init(delegate: OWSURLSession) {
        self.weakDelegate = delegate
    }

    var isRetaining: Bool {
        get {
            strongReference != nil
        }
        set {
            strongReference = newValue ? weakDelegate : nil
        }
    }
}

// MARK: -

 extension URLSessionDelegateBox: URLSessionDelegate, URLSessionTaskDelegate, URLSessionDownloadDelegate {

    // Any of the optional methods will be forwarded using objc selector forwarding
    // If all goes according to plan, weakDelegate will only go nil once everything is being dealloced
    // But just in case, let's make sure we provide a fallback implementation to the only non-optional method we've conformed to
    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        weakDelegate?.urlSession(session, downloadTask: downloadTask, didFinishDownloadingTo: location)
    }

    func urlSession(_ session: URLSession,
                    downloadTask: URLSessionDownloadTask,
                    didWriteData bytesWritten: Int64,
                    totalBytesWritten: Int64,
                    totalBytesExpectedToWrite: Int64) {
        weakDelegate?.urlSession(session,
                                 downloadTask: downloadTask,
                                 didWriteData: bytesWritten,
                                 totalBytesWritten: totalBytesWritten,
                                 totalBytesExpectedToWrite: totalBytesExpectedToWrite)
    }

    func urlSession(_ session: URLSession,
                    downloadTask: URLSessionDownloadTask,
                    didResumeAtOffset fileOffset: Int64,
                    expectedTotalBytes: Int64) {
        weakDelegate?.urlSession(session,
                                 downloadTask: downloadTask,
                                 didResumeAtOffset: fileOffset,
                                 expectedTotalBytes: expectedTotalBytes)
    }

    public typealias URLAuthenticationChallengeCompletion = OWSURLSession.URLAuthenticationChallengeCompletion

    func urlSession(_ session: URLSession,
                    task: URLSessionTask,
                    didReceive challenge: URLAuthenticationChallenge,
                    completionHandler: @escaping URLAuthenticationChallengeCompletion) {
        weakDelegate?.urlSession(session,
                                 task: task,
                                 didReceive: challenge,
                                 completionHandler: completionHandler)
    }

    func urlSession(_ session: URLSession,
                    task: URLSessionTask,
                    didSendBodyData bytesSent: Int64,
                    totalBytesSent: Int64,
                    totalBytesExpectedToSend: Int64) {
        weakDelegate?.urlSession(session,
                                 task: task,
                                 didSendBodyData: bytesSent,
                                 totalBytesSent: totalBytesSent,
                                 totalBytesExpectedToSend: totalBytesExpectedToSend)
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        weakDelegate?.urlSession(session,
                                 task: task,
                                 didCompleteWithError: error)
    }

    func urlSession(_ session: URLSession,
                    didReceive challenge: URLAuthenticationChallenge,
                    completionHandler: @escaping URLAuthenticationChallengeCompletion) {
        weakDelegate?.urlSession(session,
                                 didReceive: challenge,
                                 completionHandler: completionHandler)
    }

    func urlSession(_ session: URLSession,
                    task: URLSessionTask,
                    willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest: URLRequest,
                    completionHandler: @escaping (URLRequest?) -> Void) {
        weakDelegate?.urlSession(session,
                                 task: task,
                                 willPerformHTTPRedirection: response,
                                 newRequest: newRequest,
                                 completionHandler: completionHandler)
    }

    func urlSession(_ session: URLSession,
                    dataTask: URLSessionDataTask,
                    didReceive response: URLResponse,
                    completionHandler: @escaping (URLSession.ResponseDisposition) -> Void) {
        guard let delegate = weakDelegate else {
            completionHandler(.cancel)
            return
        }
        delegate.urlSession(session,
                            dataTask: dataTask,
                            didReceive: response,
                            completionHandler: completionHandler)
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        weakDelegate?.urlSession(session,
                                 dataTask: dataTask,
                                 didReceive: data)
    }
 }

// MARK: -

extension Error {
    var isUnknownDomainError: Bool {
        let nsError = self as NSError
        return (nsError.domain == NSURLErrorDomain &&
                    nsError.code == -1003)
    }
}
