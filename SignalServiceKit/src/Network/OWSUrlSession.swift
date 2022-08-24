//
//  Copyright (c) 2022 Open Whisper Systems. All rights reserved.
//

import Foundation

@objc
public class OWSURLSession: NSObject, OWSURLSessionProtocol {

    // MARK: - OWSURLSessionProtocol conformance

    public let baseUrl: URL?

    public let frontingInfo: OWSUrlFrontingInfo?

    public var failOnError: Bool {
        get {
            _failOnError.get()
        }
        set {
            _failOnError.set(newValue)
        }
    }

    public var require2xxOr3xx: Bool {
        get {
            _require2xxOr3xx.get()
        }
        set {
            _require2xxOr3xx.set(newValue)
        }
    }

    public var shouldHandleRemoteDeprecation: Bool {
        get {
            _shouldHandleRemoteDeprecation.get()
        }
        set {
            _shouldHandleRemoteDeprecation.set(newValue)
        }
    }

    public var allowRedirects: Bool {
        get {
            _allowRedirects.get()
        }
        set {
            owsAssertDebug(customRedirectHandler == nil || newValue)
            _allowRedirects.set(newValue)
        }
    }

    public var customRedirectHandler: ((URLRequest) -> URLRequest?)? {
        get {
            _customRedirectHandler.get()
        }
        set {
            owsAssertDebug(newValue == nil || allowRedirects)
            _customRedirectHandler.set(newValue)
        }
    }

    // Note: not all protocol methods can be made visible to objc, but those
    // that can be are declared so here. Objc callers must use this implementation
    // directly and not touch the protocol.

    @objc
    public static var defaultSecurityPolicy: OWSHTTPSecurityPolicy {
        OWSHTTPSecurityPolicy.systemDefault()
    }

    public static var signalServiceSecurityPolicy: OWSHTTPSecurityPolicy {
        OWSHTTPSecurityPolicy.shared()
    }

    public static var defaultConfigurationWithCaching: URLSessionConfiguration {
        .ephemeral
    }

    public static var defaultConfigurationWithoutCaching: URLSessionConfiguration {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.urlCache = nil
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        return configuration
    }

    // MARK: Default Headers

    public static var userAgentHeaderKey: String { OWSHttpHeaders.userAgentHeaderKey }

    public static var userAgentHeaderValueSignalIos: String { OWSHttpHeaders.userAgentHeaderValueSignalIos }

    public static var acceptLanguageHeaderKey: String { OWSHttpHeaders.acceptLanguageHeaderKey }

    public static var acceptLanguageHeaderValue: String { OWSHttpHeaders.acceptLanguageHeaderValue }

    // MARK: Initializers

    required public init(
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

        super.init()

        // Ensure this is set so that we don't try to create it in deinit().
        _ = self.delegateBox
    }

    @objc
    public convenience init(
        baseUrl: URL? = nil,
        frontingInfo: OWSUrlFrontingInfo? = nil,
        securityPolicy: OWSHTTPSecurityPolicy,
        configuration: URLSessionConfiguration,
        extraHeaders: [String: String] = [:]
    ) {
        self.init(
            baseUrl: baseUrl,
            frontingInfo: frontingInfo,
            securityPolicy: securityPolicy,
            configuration: configuration,
            extraHeaders: extraHeaders,
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
        guard let url = buildUrl(urlString) else {
            throw OWSAssertionError("Invalid url.")
        }
        var request = URLRequest(url: url)
        request.httpMethod = method.methodName

        let httpHeaders = OWSHttpHeaders()
        httpHeaders.addHeaderMap(headers, overwriteOnConflict: false)
        httpHeaders.addDefaultHeaders()
        httpHeaders.addHeaderMap(extraHeaders, overwriteOnConflict: true)
        request.add(httpHeaders: httpHeaders)

        request.httpBody = body
        request.httpShouldHandleCookies = httpShouldHandleCookies.get()
        return request
    }

    // MARK: Tasks

    public func uploadTaskPromise(
        request: URLRequest,
        data requestData: Data,
        progress progressBlock: ProgressBlock?
    ) -> Promise<HTTPResponse> {
        let uploadTaskBuilder = UploadTaskBuilderData(requestData: requestData)
        return uploadTaskPromise(request: request, uploadTaskBuilder: uploadTaskBuilder, progress: progressBlock)
    }

    public func uploadTaskPromise(
        request: URLRequest,
        fileUrl: URL,
        ignoreAppExpiry: Bool,
        progress progressBlock: ProgressBlock?
    ) -> Promise<HTTPResponse> {
        let uploadTaskBuilder = UploadTaskBuilderFileUrl(fileUrl: fileUrl)
        return uploadTaskPromise(
            request: request,
            uploadTaskBuilder: uploadTaskBuilder,
            ignoreAppExpiry: ignoreAppExpiry,
            progress: progressBlock
        )
    }

    public func dataTaskPromise(request: URLRequest, ignoreAppExpiry: Bool = false) -> Promise<HTTPResponse> {

        guard ignoreAppExpiry || !Self.appExpiry.isExpired else {
            return Promise(error: OWSAssertionError("App is expired."))
        }

        let request = prepareRequest(request: request)
        let taskState = UploadOrDataTaskState(progressBlock: nil)
        var requestConfig: RequestConfig?
        let task = session.dataTask(with: request) { [weak self] (responseData: Data?, urlResponse: URLResponse?, _: Error?) in
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
            self.uploadOrDataTaskDidSucceed(requestConfig.task, httpUrlResponse: urlResponse as? HTTPURLResponse, responseData: responseData)
        }
        addTask(task, taskState: taskState)
        guard let requestUrl = request.url else {
            owsFail("Request missing url.")
        }
        requestConfig = self.requestConfig(forTask: task, requestUrl: requestUrl)
        let monitorId = InstrumentsMonitor.startSpan(category: "traffic", parent: "dataTask", name: requestUrl.absoluteString)
        task.resume()

        return firstly { () -> Promise<(URLSessionTask, Data?)> in
            taskState.promise
        }.then(on: .global()) { (_, responseData: Data?) -> Promise<HTTPResponse> in
            guard let requestConfig = requestConfig else {
                throw OWSAssertionError("Missing requestConfig.")
            }
            return Self.uploadOrDataTaskCompletionPromise(requestConfig: requestConfig,
                                                          responseData: responseData,
                                                          monitorId: monitorId)
        }
    }

    @objc
    @available(swift, obsoleted: 1.0)
    func dataTask(_ urlString: String,
                  method: HTTPMethod,
                  headers: [String: String]?,
                  body: Data? = nil,
                  success: @escaping (HTTPResponse) -> Void,
                  failure: @escaping (Error) -> Void) {
        firstly(on: .global()) { () -> Promise<HTTPResponse> in
            self.dataTaskPromise(urlString, method: method, headers: headers, body: body)
        }.done(on: .global()) { response in
            success(response)
        }.catch(on: .global()) { error in
            failure(error)
        }
    }

    public func downloadTaskPromise(
        request: URLRequest,
        progress progressBlock: ProgressBlock?
    ) -> Promise<OWSUrlDownloadResponse> {
        let request = prepareRequest(request: request)
        guard let requestUrl = request.url else {
            return Promise(error: OWSAssertionError("Request missing url."))
        }
        return downloadTaskPromise(requestUrl: requestUrl, progress: progressBlock) {
            // Don't use a completion block or the delegate will be ignored for download tasks.
            session.downloadTask(with: request)
        }
    }

    public func downloadTaskPromise(
        requestUrl: URL,
        resumeData: Data,
        progress progressBlock: ProgressBlock?
    ) -> Promise<OWSUrlDownloadResponse> {
        downloadTaskPromise(requestUrl: requestUrl, progress: progressBlock) {
            // Don't use a completion block or the delegate will be ignored for download tasks.
            session.downloadTask(withResumeData: resumeData)
        }
    }

    // MARK: - Internal Implementation

    private static let operationQueue: OperationQueue = {
        let queue = OperationQueue()
        queue.underlyingQueue = .global()
        return queue
    }()

    // MARK: Backing Vars

    private let _failOnError = AtomicBool(true)

    private let _require2xxOr3xx = AtomicBool(true)

    private let _shouldHandleRemoteDeprecation = AtomicBool(false)

    private let _allowRedirects = AtomicBool(true)

    private let _customRedirectHandler = AtomicOptional<(URLRequest) -> URLRequest?>(nil)

    // MARK: Internal vars

    private let configuration: URLSessionConfiguration

    private let securityPolicy: OWSHTTPSecurityPolicy

    private let extraHeaders: [String: String]

    private let httpShouldHandleCookies = AtomicBool(false)

    private lazy var session: URLSession = {
        URLSession(configuration: configuration, delegate: delegateBox, delegateQueue: Self.operationQueue)
    }()

    private let maxResponseSize: Int?

    // MARK: Deinit

    deinit {
        // From NSURLSession.h
        // If you do not invalidate the session by calling the invalidateAndCancel() or
        // finishTasksAndInvalidate() method, your app leaks memory until it exits
        //
        // Even though there will be no reference cycle, underlying NSURLSession metadata
        // is malloced and kept around as a root leak.
        session.invalidateAndCancel()
    }

    // MARK: Configuration

    private struct RequestConfig {
        let task: URLSessionTask
        let requestUrl: URL
        let require2xxOr3xx: Bool
        let failOnError: Bool
        let shouldHandleRemoteDeprecation: Bool
    }

    private func requestConfig(forTask task: URLSessionTask, requestUrl: URL) -> RequestConfig {
        // Snapshot session state at time request is made.
        RequestConfig(task: task,
                      requestUrl: requestUrl,
                      require2xxOr3xx: require2xxOr3xx,
                      failOnError: failOnError,
                      shouldHandleRemoteDeprecation: shouldHandleRemoteDeprecation)
    }

    private class func uploadOrDataTaskCompletionPromise(requestConfig: RequestConfig,
                                                         responseData: Data?,
                                                         monitorId: UInt64? = nil) -> Promise<HTTPResponse> {
        firstly {
            baseCompletionPromise(requestConfig: requestConfig, responseData: responseData, monitorId: monitorId)
        }.map(on: .global()) { (httpUrlResponse: HTTPURLResponse) -> HTTPResponse in
            HTTPResponseImpl.build(requestUrl: requestConfig.requestUrl,
                                   httpUrlResponse: httpUrlResponse,
                                   bodyData: responseData)
        }
    }

    private class func downloadTaskCompletionPromise(requestConfig: RequestConfig,
                                                     downloadUrl: URL,
                                                     monitorId: UInt64? = nil) -> Promise<OWSUrlDownloadResponse> {
        firstly {
            baseCompletionPromise(requestConfig: requestConfig, responseData: nil, monitorId: monitorId)
        }.map(on: .global()) { (httpUrlResponse: HTTPURLResponse) -> OWSUrlDownloadResponse in
            return OWSUrlDownloadResponse(task: requestConfig.task,
                                          httpUrlResponse: httpUrlResponse,
                                          downloadUrl: downloadUrl)
        }
    }

    private class func baseCompletionPromise(requestConfig: RequestConfig,
                                             responseData: Data?,
                                             monitorId: UInt64? = nil) -> Promise<HTTPURLResponse> {
        firstly(on: .global()) { () -> HTTPURLResponse in
            let task = requestConfig.task

            if requestConfig.shouldHandleRemoteDeprecation {
                checkForRemoteDeprecation(task: task, response: task.response)
            }

            if let error = task.error {
                let requestUrl = requestConfig.requestUrl

                if error.isNetworkConnectivityFailure {
                    Logger.warn("Request failed: \(error)")
                    throw OWSHTTPError.networkFailure(requestUrl: requestUrl)
                } else {
#if TESTABLE_BUILD
                    HTTPUtils.logCurl(for: task)

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

                guard let httpUrlResponse = task.response as? HTTPURLResponse else {
                    throw OWSHTTPError.invalidResponse(requestUrl: requestUrl)
                }
                let statusCode = httpUrlResponse.statusCode
                let responseHeaders = OWSHttpHeaders(response: httpUrlResponse)
                throw OWSHTTPError.forServiceResponse(requestUrl: requestUrl,
                                                      responseStatus: statusCode,
                                                      responseHeaders: responseHeaders,
                                                      responseError: error,
                                                      responseData: responseData)
            }
            guard let httpUrlResponse = task.response as? HTTPURLResponse else {
                throw OWSAssertionError("Invalid response: \(type(of: task.response)).")
            }

            if requestConfig.require2xxOr3xx {
                let statusCode = httpUrlResponse.statusCode
                guard statusCode >= 200, statusCode < 400 else {
#if TESTABLE_BUILD
                    HTTPUtils.logCurl(for: task)
                    Logger.verbose("Status code: \(statusCode)")
#endif

                    let requestUrl = requestConfig.requestUrl
                    if statusCode > 0 {
                        let responseHeaders = OWSHttpHeaders(response: httpUrlResponse)
                        let error = OWSHTTPError.forServiceResponse(requestUrl: requestUrl,
                                                                    responseStatus: statusCode,
                                                                    responseHeaders: responseHeaders,
                                                                    responseError: nil,
                                                                    responseData: responseData)
                        Logger.warn("Request failed: \(error)")
                        throw error
                    } else {
                        owsFailDebug("Missing status code.")
                        let error = OWSHTTPError.networkFailure(requestUrl: requestUrl)
                        Logger.warn("Request failed: \(error)")
                        throw error
                    }
                }
            }

#if TESTABLE_BUILD
            if DebugFlags.logCurlOnSuccess {
                HTTPUtils.logCurl(for: task)
            }
#endif

            InstrumentsMonitor.stopSpan(category: "traffic",
                                        hash: monitorId,
                                        success: httpUrlResponse.statusCode >= 200 && httpUrlResponse.statusCode < 300,
                                        httpUrlResponse.statusCode,
                                        responseData?.count ?? httpUrlResponse.expectedContentLength)

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

    // MARK: Request building

    // Ensure certain invariants for all requests.
    private func prepareRequest(request: URLRequest) -> URLRequest {

        var request = request

        request.httpShouldHandleCookies = httpShouldHandleCookies.get()

        request = OWSHttpHeaders.fillInMissingDefaultHeaders(request: request)

        if let frontingInfo = self.frontingInfo,
           signalService.isCensorshipCircumventionActive,
           let urlString = request.url?.absoluteString.nilIfEmpty {
            // Only requests to Signal services require CC.
            // If frontingHost is nil, this instance of OWSURLSession does not perform CC.
            if !Self.isFrontedUrl(urlString, frontingInfo: frontingInfo) {
                owsFailDebug("Unfronted URL: \(urlString), frontingInfo: \(frontingInfo.logDescription)")
            }
        }

        return request
    }

    // Resolve the absolute URL for the HTTP request.
    //
    // * If urlString is already absolute, no resolution is necessary.
    //   * We might verify that the CC is valid for CC is applicable.
    // * If urlString is relative, we resolve using a base URL.
    //   * If CC is active and enabled for this OWSURLSession, we
    //     resolve using a baseUrl which is the frontingUrl.
    //   * For some requests (CDS, KBS, remote attestation) we target a
    //     "custom host" baseUrl.
    //   * Otherwise we resolve using the baseUrl for this OWSURLSession.
    private func buildUrl(_ urlString: String) -> URL? {

        let baseUrl: URL? = {
            if let frontingInfo = self.frontingInfo,
               signalService.isCensorshipCircumventionActive {

                // Never apply fronting twice; if urlString already contains a fronted
                // URL, baseUrl should be nil.
                if Self.isFrontedUrl(urlString, frontingInfo: frontingInfo) {
                    Logger.info("URL is already fronted.")
                    return nil
                }

                // Only requests to Signal services require CC.
                // If frontingHost is nil, this instance of OWSURLSession does not perform CC.
                let frontingUrl = frontingInfo.frontingURLWithPathPrefix
                return frontingUrl
            }

            return self.baseUrl
        }()

        guard let requestUrl = OWSURLBuilderUtil.joinUrl(urlString: urlString, baseUrl: baseUrl) else {
            owsFailDebug("Could not build URL.")
            return nil
        }
        return requestUrl
    }

    private static func isFrontedUrl(_ urlString: String, frontingInfo: OWSUrlFrontingInfo) -> Bool {
        owsAssertDebug(signalService.isCensorshipCircumventionActive)

        let frontingUrl = frontingInfo.frontingURLWithoutPathPrefix
        return urlString.lowercased().hasPrefix(frontingUrl.absoluteString)
    }

    // MARK: - Issuing Requests

    private func uploadTaskPromise(
        request: URLRequest,
        uploadTaskBuilder: UploadTaskBuilder,
        ignoreAppExpiry: Bool = false,
        progress progressBlock: ProgressBlock? = nil
    ) -> Promise<HTTPResponse> {

        guard ignoreAppExpiry || !Self.appExpiry.isExpired else {
            return Promise(error: OWSAssertionError("App is expired."))
        }

        let request = prepareRequest(request: request)
        let taskState = UploadOrDataTaskState(progressBlock: progressBlock)
        var requestConfig: RequestConfig?
        let task = uploadTaskBuilder.build(session: session, request: request) { [weak self] (responseData: Data?, urlResponse: URLResponse?, _: Error?) in
            guard let requestConfig = requestConfig else {
                owsFailDebug("Missing requestConfig.")
                return
            }
            self?.uploadOrDataTaskDidSucceed(requestConfig.task, httpUrlResponse: urlResponse as? HTTPURLResponse, responseData: responseData)
        }

        addTask(task, taskState: taskState)
        guard let requestUrl = request.url else {
            owsFail("Request missing url.")
        }
        requestConfig = self.requestConfig(forTask: task, requestUrl: requestUrl)
        let monitorId = InstrumentsMonitor.startSpan(category: "traffic", parent: "uploadTask", name: requestUrl.absoluteString)
        task.resume()

        return firstly { () -> Promise<(URLSessionTask, Data?)> in
            taskState.promise
        }.then(on: .global()) { (_, responseData: Data?) -> Promise<HTTPResponse> in
            guard let requestConfig = requestConfig else {
                throw OWSAssertionError("Missing requestConfig.")
            }
            return Self.uploadOrDataTaskCompletionPromise(requestConfig: requestConfig,
                                                          responseData: responseData,
                                                          monitorId: monitorId)
        }
    }

    private func downloadTaskPromise(
        requestUrl: URL,
        progress progressBlock: ProgressBlock? = nil,
        taskBlock: () -> URLSessionDownloadTask
    ) -> Promise<OWSUrlDownloadResponse> {

        guard !Self.appExpiry.isExpired else {
            return Promise(error: OWSAssertionError("App is expired."))
        }

        let taskState = DownloadTaskState(progressBlock: progressBlock)
        var requestConfig: RequestConfig?
        let task = taskBlock()
        addTask(task, taskState: taskState)
        requestConfig = self.requestConfig(forTask: task, requestUrl: requestUrl)

        let monitorId = InstrumentsMonitor.startSpan(category: "traffic", parent: "downloadTask", name: requestUrl.absoluteString)
        task.resume()

        return firstly { () -> Promise<(URLSessionTask, URL)> in
            taskState.promise
        }.then(on: .global()) { (_: URLSessionTask, downloadUrl: URL) -> Promise<OWSUrlDownloadResponse> in
            guard let requestConfig = requestConfig else {
                throw OWSAssertionError("Missing requestConfig.")
            }
            return Self.downloadTaskCompletionPromise(requestConfig: requestConfig, downloadUrl: downloadUrl, monitorId: monitorId)
        }
    }

    // MARK: - TaskState

    private let lock = UnfairLock()
    lazy private var delegateBox = URLSessionDelegateBox(delegate: self)

    typealias TaskIdentifier = Int

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

    @available(iOS 13, *)
    private func webSocketState(forTask task: URLSessionTask) -> WebSocketTaskState? {
        lock.withLock {
            self.taskStateMap[task.taskIdentifier] as? WebSocketTaskState
        }
    }

    private func removeCompletedTaskState(_ task: URLSessionTask) -> TaskState? {
        lock.withLock { () -> TaskState? in
            guard let taskState = self.taskStateMap[task.taskIdentifier] else {
                // This isn't necessarily an error or bug.
                // A task might "succeed" after it "fails" in certain edge cases,
                // although we make a best effort to avoid them.
                Logger.warn("Missing TaskState.")
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
        taskState.future.resolve((task, downloadUrl))
    }

    private func uploadOrDataTaskDidSucceed(_ task: URLSessionTask, httpUrlResponse: HTTPURLResponse?, responseData: Data?, monitorId: UInt64? = nil) {
        guard let taskState = removeCompletedTaskState(task) as? UploadOrDataTaskState else {
            owsFailDebug("Missing TaskState.")
            return
        }
        InstrumentsMonitor.stopSpan(category: "traffic",
                                    hash: monitorId,
                                    success: true,
                                    httpUrlResponse?.statusCode ?? -1,
                                    responseData?.count ?? (httpUrlResponse?.expectedContentLength ?? -1))
        taskState.future.resolve((task, responseData))
    }

    private func taskDidFail(_ task: URLSessionTask, error: Error) {
        guard let taskState = removeCompletedTaskState(task) else {
            Logger.warn("Missing TaskState.")
            return
        }
        taskState.reject(error: error, task: task)
        task.cancel()
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

// MARK: - URLSessionDelegate

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

// MARK: - URLSessionTaskDelegate

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

// MARK: - URLSessionDownloadDelegate

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
        if response.expectedContentLength > 800_000 {
            let formattedContentLength = OWSFormat.formatFileSize(UInt(response.expectedContentLength))
            let urlString = response.url.map { String(describing: $0) } ?? "<unknown URL>"
            Logger.warn("Large response (\(formattedContentLength)) for \(urlString)")
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

// MARK: - WebSocket

extension OWSURLSession: URLSessionWebSocketDelegate {

    @available(iOS 13, *)
    public func webSocketTask(request: URLRequest, didOpenBlock: @escaping (String?) -> Void, didCloseBlock: @escaping (SSKWebSocketNativeError) -> Void) -> URLSessionWebSocketTask {
        let task = session.webSocketTask(with: request)
        addTask(task, taskState: WebSocketTaskState(openBlock: didOpenBlock, closeBlock: didCloseBlock))
        return task
    }

    @available(iOS 13, *)
    public func urlSession(_ session: URLSession, webSocketTask: URLSessionWebSocketTask, didOpenWithProtocol: String?) {
        webSocketState(forTask: webSocketTask)?.openBlock(didOpenWithProtocol)
    }

    @available(iOS 13, *)
    public func urlSession(_ session: URLSession, webSocketTask: URLSessionWebSocketTask, didCloseWith closeCode: URLSessionWebSocketTask.CloseCode, reason: Data?) {
        guard let webSocketState = removeCompletedTaskState(webSocketTask) as? WebSocketTaskState else { return }
        webSocketState.closeBlock(.remoteClosed(closeCode.rawValue, reason))
    }
}

// MARK: - TaskState

private protocol TaskState {
    typealias ProgressBlock = (URLSessionTask, Progress) -> Void
    var progressBlock: ProgressBlock? { get }

    func reject(error: Error, task: URLSessionTask)
}

// MARK: - DownloadTaskState

private class DownloadTaskState: TaskState {
    let progressBlock: ProgressBlock?
    let promise: Promise<(URLSessionTask, URL)>
    let future: Future<(URLSessionTask, URL)>

    init(progressBlock: ProgressBlock?) {
        self.progressBlock = progressBlock

        let (promise, future) = Promise<(URLSessionTask, URL)>.pending()
        self.promise = promise
        self.future = future
    }

    func reject(error: Error, task: URLSessionTask) {
        future.reject(error)
    }
}

// MARK: - UploadOrDataTaskState

private class UploadOrDataTaskState: TaskState {
    let progressBlock: ProgressBlock?
    let promise: Promise<(URLSessionTask, Data?)>
    let future: Future<(URLSessionTask, Data?)>

    init(progressBlock: ProgressBlock?) {
        self.progressBlock = progressBlock

        let (promise, future) = Promise<(URLSessionTask, Data?)>.pending()
        self.promise = promise
        self.future = future
    }

    func reject(error: Error, task: URLSessionTask) {
        future.reject(error)
    }
}

// MARK: - WebSocketTaskState

@available(iOS 13, *)
private class WebSocketTaskState: TaskState {
    typealias OpenBlock = (String?) -> Void
    typealias CloseBlock = (SSKWebSocketNativeError) -> Void

    var progressBlock: ProgressBlock? { nil }
    let openBlock: OpenBlock
    let closeBlock: CloseBlock

    init(openBlock: @escaping OpenBlock, closeBlock: @escaping CloseBlock) {
        self.openBlock = openBlock
        self.closeBlock = closeBlock
    }

    func reject(error: Error, task: URLSessionTask) {
        guard let httpResponse = task.response as? HTTPURLResponse else {
            // We shouldn't have non-HTTP responses, but we might not have a response at all.
            owsAssertDebug(task.response == nil)
            self.closeBlock(.failedToConnect(nil))
            return
        }
        self.closeBlock(.failedToConnect(httpResponse.statusCode))
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

extension URLSessionDelegateBox: URLSessionWebSocketDelegate {
    @available(iOS 13, *)
    public func urlSession(_ session: URLSession, webSocketTask: URLSessionWebSocketTask, didOpenWithProtocol: String?) {
        weakDelegate?.urlSession(session, webSocketTask: webSocketTask, didOpenWithProtocol: didOpenWithProtocol)
    }

    @available(iOS 13, *)
    public func urlSession(_ session: URLSession, webSocketTask: URLSessionWebSocketTask, didCloseWith closeCode: URLSessionWebSocketTask.CloseCode, reason: Data?) {
        weakDelegate?.urlSession(session, webSocketTask: webSocketTask, didCloseWith: closeCode, reason: reason)
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

// MARK: -

private protocol UploadTaskBuilder {
    typealias CompletionBlock = (Data?, URLResponse?, Error?) -> Void

    func build(session: URLSession, request: URLRequest, completionBlock: @escaping CompletionBlock) -> URLSessionUploadTask
}

// MARK: -

private struct UploadTaskBuilderData: UploadTaskBuilder {
    let requestData: Data

    func build(session: URLSession, request: URLRequest, completionBlock: @escaping CompletionBlock) -> URLSessionUploadTask {
        session.uploadTask(with: request, from: requestData, completionHandler: completionBlock)
    }
}

// MARK: -

private struct UploadTaskBuilderFileUrl: UploadTaskBuilder {
    let fileUrl: URL

    func build(session: URLSession, request: URLRequest, completionBlock: @escaping CompletionBlock) -> URLSessionUploadTask {
        session.uploadTask(with: request, fromFile: fileUrl, completionHandler: completionBlock)
    }
}
