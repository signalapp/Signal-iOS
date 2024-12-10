//
// Copyright 2020 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

public enum OWSURLSessionError: Error, IsRetryableProvider {
    case responseTooLarge

    public var isRetryableProvider: Bool {
        switch self {
        case .responseTooLarge: return false
        }
    }
}

public class OWSURLSession: NSObject, OWSURLSessionProtocol {

    // MARK: - OWSURLSessionProtocol conformance

    public let endpoint: OWSURLSessionEndpoint

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

    public static let defaultSecurityPolicy = HttpSecurityPolicy.systemDefault
    public static let signalServiceSecurityPolicy = HttpSecurityPolicy.signalCaPinned

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
        endpoint: OWSURLSessionEndpoint,
        configuration: URLSessionConfiguration,
        maxResponseSize: Int?,
        canUseSignalProxy: Bool
    ) {
        if canUseSignalProxy {
            configuration.connectionProxyDictionary = SignalProxy.connectionProxyDictionary
        }

        self.endpoint = endpoint
        self.configuration = configuration
        self.maxResponseSize = maxResponseSize
        self.canUseSignalProxy = canUseSignalProxy

        super.init()

        // Ensure this is set so that we don't try to create it in deinit().
        _ = self.delegateBox
    }

    convenience public init(
        securityPolicy: HttpSecurityPolicy,
        configuration: URLSessionConfiguration
    ) {
        self.init(
            endpoint: OWSURLSessionEndpoint(
                baseUrl: nil,
                frontingInfo: nil,
                securityPolicy: securityPolicy,
                extraHeaders: [:]
            ),
            configuration: configuration,
            maxResponseSize: nil,
            canUseSignalProxy: false
        )
    }

    convenience public init(
        baseUrl: URL? = nil,
        securityPolicy: HttpSecurityPolicy,
        configuration: URLSessionConfiguration,
        extraHeaders: [String: String] = [:],
        maxResponseSize: Int? = nil,
        canUseSignalProxy: Bool = false
    ) {
        self.init(
            endpoint: OWSURLSessionEndpoint(
                baseUrl: baseUrl,
                frontingInfo: nil,
                securityPolicy: securityPolicy,
                extraHeaders: extraHeaders
            ),
            configuration: configuration,
            maxResponseSize: maxResponseSize,
            canUseSignalProxy: canUseSignalProxy
        )
    }

    // MARK: Tasks

    public func performUpload(
        request: URLRequest,
        requestData: Data,
        progress: OWSProgressSource?
    ) async throws -> any HTTPResponse {
        return try await performUpload(
            request: request,
            ignoreAppExpiry: false,
            progress: progress,
            taskBlock: { self.session.uploadTask(with: request, from: requestData) }
        )
    }

    public func performUpload(
        request: URLRequest,
        fileUrl: URL,
        ignoreAppExpiry: Bool,
        progress: OWSProgressSource?
    ) async throws -> HTTPResponse {
        return try await performUpload(
            request: request,
            ignoreAppExpiry: ignoreAppExpiry,
            progress: progress,
            taskBlock: { self.session.uploadTask(with: request, fromFile: fileUrl) }
        )
    }

    public func performRequest(request: URLRequest, ignoreAppExpiry: Bool) async throws -> any HTTPResponse {
        if !ignoreAppExpiry && DependenciesBridge.shared.appExpiry.isExpired {
            throw OWSAssertionError("App is expired.")
        }

        let request = prepareRequest(request: request)
        let requestConfig = self.requestConfig(requestUrl: request.url!)
        let task = session.dataTask(with: request)

        let (urlResponse, responseData) = try await runTask(task, taskState: {
            return DataTaskState(progressSource: nil, completion: $0)
        })

        return try handleDataResult(
            urlResponse: urlResponse,
            responseData: responseData,
            originalRequest: task.originalRequest,
            requestConfig: requestConfig
        )
    }

    public func performDownload(
        request: URLRequest,
        progress: OWSProgressSource?
    ) async throws -> OWSUrlDownloadResponse {
        let request = prepareRequest(request: request)
        guard let requestUrl = request.url else {
            throw OWSAssertionError("Request missing url.")
        }
        return try await performDownload(requestUrl: requestUrl, progress: progress) {
            // Don't use a completion block or the delegate will be ignored for download tasks.
            return self.session.downloadTask(with: request)
        }
    }

    public func performDownload(
        requestUrl: URL,
        resumeData: Data,
        progress: OWSProgressSource?
    ) async throws -> OWSUrlDownloadResponse {
        return try await performDownload(requestUrl: requestUrl, progress: progress) {
            // Don't use a completion block or the delegate will be ignored for download tasks.
            return self.session.downloadTask(withResumeData: resumeData)
        }
    }

    public func webSocketTask(requestUrl: URL, didOpenBlock: @escaping (String?) -> Void, didCloseBlock: @escaping (Error) -> Void) -> URLSessionWebSocketTask {
        // We can't pass a URLRequest here since it prevents the proxy from
        // operating correctly. See `SSKWebSocketNative.init(...)` for more details
        // and an example of passing URLRequest options via this web socket.
        let task = session.webSocketTask(with: requestUrl)
        addTask(task, taskState: WebSocketTaskState(openBlock: didOpenBlock, closeBlock: didCloseBlock))
        return task
    }

    // MARK: - Internal Implementation

    private static let operationQueue: OperationQueue = {
        let queue = OperationQueue()
        queue.underlyingQueue = .global()
        return queue
    }()

    // MARK: Backing Vars

    private let _require2xxOr3xx = AtomicBool(true, lock: .sharedGlobal)

    private let _shouldHandleRemoteDeprecation = AtomicBool(false, lock: .sharedGlobal)

    private let _allowRedirects = AtomicBool(true, lock: .sharedGlobal)

    private let _customRedirectHandler = AtomicOptional<(URLRequest) -> URLRequest?>(nil, lock: .sharedGlobal)

    // MARK: Internal vars

    private let configuration: URLSessionConfiguration

    private lazy var session: URLSession = {
        URLSession(configuration: configuration, delegate: delegateBox, delegateQueue: Self.operationQueue)
    }()

    private let maxResponseSize: Int?

    private let canUseSignalProxy: Bool

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
        let requestUrl: URL
        let require2xxOr3xx: Bool
        let shouldHandleRemoteDeprecation: Bool
    }

    private func requestConfig(requestUrl: URL) -> RequestConfig {
        // Snapshot session state at time request is made.
        return RequestConfig(
            requestUrl: requestUrl,
            require2xxOr3xx: require2xxOr3xx,
            shouldHandleRemoteDeprecation: shouldHandleRemoteDeprecation
        )
    }

    private func handleDataResult(urlResponse: URLResponse?, responseData: Data, originalRequest: URLRequest?, requestConfig: RequestConfig) throws -> HTTPResponse {
        let httpUrlResponse = try handleResult(urlResponse: urlResponse, responseData: responseData, originalRequest: originalRequest, requestConfig: requestConfig)
        return HTTPResponseImpl.build(requestUrl: requestConfig.requestUrl, httpUrlResponse: httpUrlResponse, bodyData: responseData)
    }

    private func handleDownloadResult(urlResponse: URLResponse?, downloadUrl: URL, originalRequest: URLRequest?, requestConfig: RequestConfig) throws -> OWSUrlDownloadResponse {
        let httpUrlResponse = try handleResult(urlResponse: urlResponse, responseData: nil, originalRequest: originalRequest, requestConfig: requestConfig)
        return OWSUrlDownloadResponse(httpUrlResponse: httpUrlResponse, downloadUrl: downloadUrl)
    }

    private func handleError(_ error: any Error, originalRequest: URLRequest?, requestConfig: RequestConfig) -> OWSHTTPError {
        if error.isNetworkFailureOrTimeout {
            return .networkFailure
        }

#if TESTABLE_BUILD
        if let originalRequest {
            HTTPUtils.logCurl(for: originalRequest)
        }
#endif

        return .wrappedFailure(error)
    }

    private func handleResult(urlResponse: URLResponse?, responseData: Data?, originalRequest: URLRequest?, requestConfig: RequestConfig) throws -> HTTPURLResponse {
        if requestConfig.shouldHandleRemoteDeprecation {
            handleRemoteDeprecation(inResponse: urlResponse)
        }

        guard let httpUrlResponse = urlResponse as? HTTPURLResponse else {
            throw OWSAssertionError("Invalid response: \(type(of: urlResponse)).")
        }

        if requestConfig.require2xxOr3xx {
            let statusCode = httpUrlResponse.statusCode
            guard statusCode >= 200, statusCode < 400 else {
#if TESTABLE_BUILD
                if let originalRequest {
                    HTTPUtils.logCurl(for: originalRequest)
                }
#endif

                if statusCode > 0 {
                    let requestUrl = requestConfig.requestUrl
                    let responseHeaders = OWSHttpHeaders(response: httpUrlResponse)
                    throw OWSHTTPError.forServiceResponse(
                        requestUrl: requestUrl,
                        responseStatus: statusCode,
                        responseHeaders: responseHeaders,
                        responseError: nil,
                        responseData: responseData
                    )
                } else {
                    owsFailDebug("Missing status code.")
                    throw OWSHTTPError.networkFailure
                }
            }
        }

#if TESTABLE_BUILD
        if DebugFlags.logCurlOnSuccess, let originalRequest {
            HTTPUtils.logCurl(for: originalRequest)
        }
#endif

        return httpUrlResponse
    }

    private func handleRemoteDeprecation(inResponse response: URLResponse?) {
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == AppExpiryImpl.appExpiredStatusCode else {
            return
        }

        let appExpiry = DependenciesBridge.shared.appExpiry
        let db = DependenciesBridge.shared.db
        appExpiry.setHasAppExpiredAtCurrentVersion(db: db)
    }

    private func isResponseTooLarge(bytesReceived: Int64, bytesExpected: Int64) -> Bool {
        if let maxResponseSize {
            if bytesReceived > maxResponseSize {
                return true
            }
            if bytesExpected != NSURLSessionTransferSizeUnknown, bytesExpected > maxResponseSize {
                return true
            }
        }
        return false
    }

    // MARK: Request building

    // Ensure certain invariants for all requests.
    private func prepareRequest(request: URLRequest) -> URLRequest {

        var request = request

        request.httpShouldHandleCookies = false

        request = OWSHttpHeaders.fillInMissingDefaultHeaders(request: request)

        // Only requests to Signal services require CC.
        // If frontingHost is nil, this instance of OWSURLSession does not perform CC.
        if let frontingInfo = endpoint.frontingInfo, let urlString = request.url?.absoluteString.nilIfEmpty {
            owsAssertDebug(frontingInfo.isFrontedUrl(urlString), "Unfronted URL: \(urlString)")
        }

        return request
    }

    // MARK: - Issuing Requests

    public func performRequest(_ rawRequest: TSRequest) async throws -> any HTTPResponse {
        guard let rawRequestUrl = rawRequest.url else {
            owsFailDebug("Missing requestUrl.")
            throw OWSHTTPError.missingRequest
        }

        let appExpiry = DependenciesBridge.shared.appExpiry
        guard !appExpiry.isExpired else {
            owsFailDebug("App is expired.")
            throw OWSHTTPError.invalidAppState
        }

        let httpHeaders = OWSHttpHeaders()

        // Set User-Agent and Accept-Language headers.
        httpHeaders.addDefaultHeaders()

        // Then apply any custom headers for the request
        httpHeaders.addHeaderMap(rawRequest.allHTTPHeaderFields, overwriteOnConflict: true)

        if !rawRequest.isUDRequest, rawRequest.shouldHaveAuthorizationHeaders {
            owsAssertDebug(nil != rawRequest.authUsername?.nilIfEmpty)
            owsAssertDebug(nil != rawRequest.authPassword?.nilIfEmpty)
            do {
                try httpHeaders.addAuthHeader(username: rawRequest.authUsername ?? "", password: rawRequest.authPassword ?? "")
            } catch {
                owsFailDebug("Could not add auth header: \(error).")
                throw OWSHTTPError.invalidAppState
            }
        }

        let method: HTTPMethod
        do {
            method = try HTTPMethod.method(for: rawRequest.httpMethod)
        } catch {
            owsFailDebug("Invalid HTTP method: \(rawRequest.httpMethod)")
            throw OWSHTTPError.invalidRequest
        }

        var requestBody = Data()
        if let httpBody = rawRequest.httpBody {
            owsAssertDebug(rawRequest.parameters.isEmpty)

            requestBody = httpBody
        } else if !rawRequest.parameters.isEmpty {
            let jsonData: Data?
            do {
                jsonData = try JSONSerialization.data(withJSONObject: rawRequest.parameters, options: [])
            } catch {
                owsFailDebug("Could not serialize JSON parameters: \(error).")
                throw OWSHTTPError.invalidRequest
            }

            if let jsonData = jsonData {
                requestBody = jsonData
                // If we're going to use the json serialized parameters as our body, we should overwrite
                // the Content-Type on the request.
                httpHeaders.addHeader("Content-Type", value: "application/json", overwriteOnConflict: true)
            }
        }

        var request: URLRequest
        do {
            request = try self.endpoint.buildRequest(
                rawRequestUrl.absoluteString,
                method: method,
                headers: httpHeaders.headers,
                body: requestBody
            )
        } catch {
            owsFailDebug("Missing or invalid request: \(rawRequestUrl).")
            throw OWSHTTPError.invalidRequest
        }

        let backgroundTask = OWSBackgroundTask(label: "\(#function)")
        defer {
            backgroundTask.end()
        }

        request.timeoutInterval = rawRequest.timeoutInterval

        do {
            Logger.info("Sending… -> \(rawRequest.description)")
            let response = try await performUpload(request: request, requestData: requestBody, progress: nil)
            Logger.info("HTTP \(response.responseStatusCode) <- \(rawRequest.description)")
            return response
        } catch where error.httpStatusCode != nil {
            Logger.warn("HTTP \(error.httpStatusCode!) <- \(rawRequest.description)")
            throw error
        } catch {
            Logger.warn("Failure. <- \(rawRequest.description): \(error)")
            throw error
        }
    }

    private func performUpload(
        request: URLRequest,
        ignoreAppExpiry: Bool,
        progress: OWSProgressSource?,
        taskBlock: () -> URLSessionUploadTask
    ) async throws -> HTTPResponse {
        if !ignoreAppExpiry && DependenciesBridge.shared.appExpiry.isExpired {
            throw OWSAssertionError("App is expired.")
        }

        let request = prepareRequest(request: request)
        let requestConfig = requestConfig(requestUrl: request.url!)
        let task = taskBlock()

        let (urlResponse, responseData): (URLResponse?, Data)
        do {
            (urlResponse, responseData) = try await runTask(task, taskState: {
                return DataTaskState(progressSource: progress, completion: $0)
            })
        } catch {
            throw handleError(error, originalRequest: task.originalRequest, requestConfig: requestConfig)
        }
        return try handleDataResult(
            urlResponse: urlResponse,
            responseData: responseData,
            originalRequest: task.originalRequest,
            requestConfig: requestConfig
        )
    }

    private func performDownload(
        requestUrl: URL,
        progress: OWSProgressSource?,
        taskBlock: () -> URLSessionDownloadTask
    ) async throws -> OWSUrlDownloadResponse {
        let appExpiry = DependenciesBridge.shared.appExpiry
        if appExpiry.isExpired {
            throw OWSAssertionError("App is expired.")
        }

        let requestConfig = self.requestConfig(requestUrl: requestUrl)
        let task = taskBlock()

        let (urlResponse, downloadUrl) = try await runTask(task, taskState: {
            return DownloadTaskState(progressSource: progress, completion: $0)
        })

        return try handleDownloadResult(
            urlResponse: urlResponse,
            downloadUrl: downloadUrl,
            originalRequest: task.originalRequest,
            requestConfig: requestConfig
        )
    }

    private func runTask<T>(_ task: URLSessionTask, taskState: (CheckedContinuation<T, any Error>) -> some TaskState) async throws -> T {
        // It's possible for operation and onCancel to race one another, so we use
        // a counter to ensure that cancellation happens after addTask is invoked.
        // (You can trigger this by sending a request from a canceled Task.)
        let cancelState = AtomicUInt(lock: .init())

        return try await withTaskCancellationHandler(
            operation: {
                return try await withCheckedThrowingContinuation { continuation in
                    self.addTask(task, taskState: taskState(continuation))
                    // If cancel was already called, cancel it now.
                    if cancelState.increment() == 2 {
                        task.cancel()
                    } else {
                        task.resume()
                    }
                }
            },
            onCancel: {
                // If the task was already added, cancel it now.
                if cancelState.increment() == 2 {
                    task.cancel()
                }
            }
        )
    }

    // MARK: - TaskState

    private let taskStates = AtomicValue([TaskIdentifier: TaskState](), lock: .init())
    private lazy var delegateBox = URLSessionDelegateBox(delegate: self)

    typealias TaskIdentifier = Int

    private func updateTaskStates<T>(block: (inout [TaskIdentifier: TaskState]) throws -> T) rethrows -> T {
        return try self.taskStates.update {
            let result = try block(&$0)
            delegateBox.isRetaining = !$0.isEmpty
            return result
        }
    }

    private func addTask(_ task: URLSessionTask, taskState: TaskState) {
        updateTaskStates {
            owsAssertDebug($0[task.taskIdentifier] == nil)
            $0[task.taskIdentifier] = taskState
        }
    }

    private func progressSource(forTask task: URLSessionTask) -> OWSProgressSource? {
        return updateTaskStates {
            return $0[task.taskIdentifier]?.progressSource
        }
    }

    private func dataTaskState(forTask task: URLSessionTask) -> DataTaskState? {
        return updateTaskStates {
            return $0[task.taskIdentifier] as? DataTaskState
        }
    }

    private func webSocketState(forTask task: URLSessionTask) -> WebSocketTaskState? {
        return updateTaskStates {
            return $0[task.taskIdentifier] as? WebSocketTaskState
        }
    }

    private func removeCompletedTaskState(_ task: URLSessionTask) -> TaskState? {
        return updateTaskStates {
            guard let taskState = $0[task.taskIdentifier] else {
                // This isn't necessarily an error or bug.
                // A task might "succeed" after it "fails" in certain edge cases,
                // although we make a best effort to avoid them.
                Logger.warn("Missing TaskState.")
                return nil
            }
            $0[task.taskIdentifier] = nil
            return taskState
        }
    }

    private func downloadTaskDidSucceed(_ task: URLSessionTask, downloadUrl: URL) {
        guard let taskState = removeCompletedTaskState(task) as? DownloadTaskState else {
            owsFailDebug("Missing TaskState.")
            return
        }
        taskState.completion.resume(returning: (task.response, downloadUrl))
    }

    private func dataTaskDidSucceed(_ task: URLSessionTask) {
        guard let taskState = removeCompletedTaskState(task) as? DataTaskState else {
            owsFailDebug("Missing TaskState.")
            return
        }
        let responseData = taskState.pendingData.get()
        taskState.completion.resume(returning: (task.response, responseData))
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

    fileprivate func urlSession(
        didReceive challenge: URLAuthenticationChallenge,
        completionHandler: @escaping URLAuthenticationChallengeCompletion
    ) {
        var disposition: URLSession.AuthChallengeDisposition = .performDefaultHandling
        var credential: URLCredential?

        if challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust,
           let serverTrust = challenge.protectionSpace.serverTrust {
            if endpoint.securityPolicy.evaluate(serverTrust: serverTrust, domain: challenge.protectionSpace.host) {
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

// MARK: - Forwarded Delegate Methods

extension OWSURLSession {

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        if let error {
            taskDidFail(task, error: error)
        } else if let dataTask = task as? URLSessionDataTask {
            dataTaskDidSucceed(dataTask)
        }
    }

    func urlSession(
        _ session: URLSession,
        didReceive challenge: URLAuthenticationChallenge,
        completionHandler: @escaping URLAuthenticationChallengeCompletion
    ) {
        urlSession(didReceive: challenge, completionHandler: completionHandler)
    }

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest: URLRequest,
        completionHandler: @escaping (URLRequest?) -> Void
    ) {
        guard allowRedirects else { return completionHandler(nil) }

        if let customRedirectHandler = customRedirectHandler {
            completionHandler(customRedirectHandler(newRequest))
        } else {
            completionHandler(newRequest)
        }
    }

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        didReceive challenge: URLAuthenticationChallenge,
        completionHandler: @escaping URLAuthenticationChallengeCompletion
    ) {
        urlSession(didReceive: challenge, completionHandler: completionHandler)
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didSendBodyData bytesSent: Int64, totalBytesSent: Int64, totalBytesExpectedToSend: Int64) {
        guard let progressSource = self.progressSource(forTask: task) else {
            return
        }
        // TODO: We could check for NSURLSessionTransferSizeUnknown here.
        if progressSource.completedUnitCount < totalBytesSent {
            progressSource.incrementCompletedUnitCount(by: UInt64(totalBytesSent) - progressSource.completedUnitCount)
        }
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        if let maxResponseSize {
            guard let fileSize = OWSFileSystem.fileSize(of: location) else {
                taskDidFail(downloadTask, error: OWSAssertionError("Unknown download size."))
                return
            }
            guard fileSize.intValue <= maxResponseSize else {
                taskDidFail(downloadTask, error: OWSURLSessionError.responseTooLarge)
                return
            }
        }
        do {
            // Download locations are cleaned up quickly, so we
            // need to move the file synchronously.
            let temporaryUrl = OWSFileSystem.temporaryFileUrl(fileExtension: nil, isAvailableWhileDeviceLocked: true)
            try OWSFileSystem.moveFile(from: location, to: temporaryUrl)
            downloadTaskDidSucceed(downloadTask, downloadUrl: temporaryUrl)
        } catch {
            owsFailDebugUnlessNetworkFailure(error)

            taskDidFail(downloadTask, error: error)
        }
    }

    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didWriteData bytesWritten: Int64,
        totalBytesWritten: Int64,
        totalBytesExpectedToWrite: Int64
    ) {
        if isResponseTooLarge(bytesReceived: totalBytesWritten, bytesExpected: totalBytesExpectedToWrite) {
            taskDidFail(downloadTask, error: OWSURLSessionError.responseTooLarge)
            return
        }
        guard let progressSource = self.progressSource(forTask: downloadTask) else {
            return
        }
        if progressSource.completedUnitCount < totalBytesWritten {
            progressSource.incrementCompletedUnitCount(by: UInt64(totalBytesWritten) - progressSource.completedUnitCount)
        }
    }

    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didResumeAtOffset fileOffset: Int64,
        expectedTotalBytes: Int64
    ) {
        if isResponseTooLarge(bytesReceived: fileOffset, bytesExpected: expectedTotalBytes) {
            taskDidFail(downloadTask, error: OWSURLSessionError.responseTooLarge)
            return
        }
        guard let progressSource = self.progressSource(forTask: downloadTask) else {
            return
        }
        if progressSource.completedUnitCount < fileOffset {
            progressSource.incrementCompletedUnitCount(by: UInt64(fileOffset) - progressSource.completedUnitCount)
        }
    }

    func urlSession(
        _ session: URLSession,
        dataTask: URLSessionDataTask,
        didReceive response: URLResponse,
        completionHandler: @escaping (URLSession.ResponseDisposition) -> Void
    ) {
        if isResponseTooLarge(bytesReceived: 0, bytesExpected: response.expectedContentLength) {
            taskDidFail(dataTask, error: OWSURLSessionError.responseTooLarge)
            completionHandler(.cancel)
            return
        }
        completionHandler(.allow)
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        if isResponseTooLarge(bytesReceived: dataTask.countOfBytesReceived, bytesExpected: dataTask.countOfBytesExpectedToReceive) {
            taskDidFail(dataTask, error: OWSURLSessionError.responseTooLarge)
            return
        }
        dataTaskState(forTask: dataTask)?.pendingData.update { $0 += data }
    }

    func urlSession(_ session: URLSession, webSocketTask: URLSessionWebSocketTask, didOpenWithProtocol: String?) {
        webSocketState(forTask: webSocketTask)?.openBlock(didOpenWithProtocol)
    }

    func urlSession(_ session: URLSession, webSocketTask: URLSessionWebSocketTask, didCloseWith closeCode: URLSessionWebSocketTask.CloseCode, reason: Data?) {
        guard let webSocketState = removeCompletedTaskState(webSocketTask) as? WebSocketTaskState else { return }
        webSocketState.closeBlock(WebSocketError.closeError(statusCode: closeCode.rawValue, closeReason: reason))
    }
}

// MARK: - TaskState

private protocol TaskState {
    typealias ProgressBlock = (URLSessionTask, Progress) -> Void
    var progressSource: OWSProgressSource? { get }
    func reject(error: any Error, task: URLSessionTask)
}

// MARK: - DownloadTaskState

private class DownloadTaskState: TaskState {
    typealias CompletionContinuation = CheckedContinuation<(URLResponse?, URL), any Error>
    let progressSource: OWSProgressSource?
    let completion: CompletionContinuation

    init(progressSource: OWSProgressSource?, completion: CompletionContinuation) {
        self.progressSource = progressSource
        self.completion = completion
    }

    func reject(error: any Error, task: URLSessionTask) {
        completion.resume(throwing: error)
    }
}

// MARK: - DataTaskState (& UploadTaskState)

/// Also used for upload tasks, which are a subclass data tasks.
private class DataTaskState: TaskState {
    typealias CompletionContinuation = CheckedContinuation<(URLResponse?, Data), any Error>

    let pendingData = AtomicValue<Data>(Data(), lock: .init())
    let progressSource: OWSProgressSource?
    let completion: CompletionContinuation

    init(progressSource: OWSProgressSource?, completion: CompletionContinuation) {
        self.progressSource = progressSource
        self.completion = completion
    }

    func reject(error: any Error, task: URLSessionTask) {
        self.completion.resume(throwing: error)
    }
}

// MARK: - WebSocketTaskState

private class WebSocketTaskState: TaskState {
    typealias OpenBlock = (String?) -> Void
    typealias CloseBlock = (Error) -> Void

    var progressSource: OWSProgressSource? { nil }
    let openBlock: OpenBlock
    let closeBlock: CloseBlock

    init(openBlock: @escaping OpenBlock, closeBlock: @escaping CloseBlock) {
        self.openBlock = openBlock
        self.closeBlock = closeBlock
    }

    func reject(error: any Error, task: URLSessionTask) {
        // We only want to return HTTP errors during the initial web socket
        // upgrade. Once we've switched protocols, the HTTP response is no longer
        // relevant but the property remains defined on the task. We use
        // `badServerResponse` to distinguish errors during the initial handshake
        // from other unexpected errors that occur later (eg losing internet).
        if case URLError.badServerResponse = error, let httpResponse = task.response as? HTTPURLResponse {
            let retryAfter = OWSHttpHeaders(response: httpResponse).retryAfterDate
            closeBlock(WebSocketError.httpError(statusCode: httpResponse.statusCode, retryAfter: retryAfter))
            return
        }
        closeBlock(error)
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

extension URLSessionDelegateBox: URLSessionDelegate, URLSessionTaskDelegate, URLSessionDownloadDelegate, URLSessionDataDelegate {

    // Any of the optional methods will be forwarded using objc selector forwarding
    // If all goes according to plan, weakDelegate will only go nil once everything is being dealloced
    // But just in case, let's make sure we provide a fallback implementation to the only non-optional method we've conformed to
    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        weakDelegate?.urlSession(session, downloadTask: downloadTask, didFinishDownloadingTo: location)
    }

    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didWriteData bytesWritten: Int64,
        totalBytesWritten: Int64,
        totalBytesExpectedToWrite: Int64
    ) {
        weakDelegate?.urlSession(
            session,
            downloadTask: downloadTask,
            didWriteData: bytesWritten,
            totalBytesWritten: totalBytesWritten,
            totalBytesExpectedToWrite: totalBytesExpectedToWrite
        )
    }

    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didResumeAtOffset fileOffset: Int64,
        expectedTotalBytes: Int64
    ) {
        weakDelegate?.urlSession(
            session,
            downloadTask: downloadTask,
            didResumeAtOffset: fileOffset,
            expectedTotalBytes: expectedTotalBytes
        )
    }

    public typealias URLAuthenticationChallengeCompletion = OWSURLSession.URLAuthenticationChallengeCompletion

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        didReceive challenge: URLAuthenticationChallenge,
        completionHandler: @escaping URLAuthenticationChallengeCompletion
    ) {
        weakDelegate?.urlSession(
            session,
            task: task,
            didReceive: challenge,
            completionHandler: completionHandler
        )
    }

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        didSendBodyData bytesSent: Int64,
        totalBytesSent: Int64,
        totalBytesExpectedToSend: Int64
    ) {
        weakDelegate?.urlSession(
            session,
            task: task,
            didSendBodyData: bytesSent,
            totalBytesSent: totalBytesSent,
            totalBytesExpectedToSend: totalBytesExpectedToSend
        )
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        weakDelegate?.urlSession(
            session,
            task: task,
            didCompleteWithError: error
        )
    }

    func urlSession(
        _ session: URLSession,
        didReceive challenge: URLAuthenticationChallenge,
        completionHandler: @escaping URLAuthenticationChallengeCompletion
    ) {
        weakDelegate?.urlSession(
            session,
            didReceive: challenge,
            completionHandler: completionHandler
        )
    }

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest: URLRequest,
        completionHandler: @escaping (URLRequest?) -> Void
    ) {
        weakDelegate?.urlSession(
            session,
            task: task,
            willPerformHTTPRedirection: response,
            newRequest: newRequest,
            completionHandler: completionHandler
        )
    }

    func urlSession(
        _ session: URLSession,
        dataTask: URLSessionDataTask,
        didReceive response: URLResponse,
        completionHandler: @escaping (URLSession.ResponseDisposition) -> Void
    ) {
        guard let delegate = weakDelegate else {
            completionHandler(.cancel)
            return
        }
        delegate.urlSession(
            session,
            dataTask: dataTask,
            didReceive: response,
            completionHandler: completionHandler
        )
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        weakDelegate?.urlSession(session, dataTask: dataTask, didReceive: data)
    }
}

extension URLSessionDelegateBox: URLSessionWebSocketDelegate {
    public func urlSession(_ session: URLSession, webSocketTask: URLSessionWebSocketTask, didOpenWithProtocol: String?) {
        weakDelegate?.urlSession(session, webSocketTask: webSocketTask, didOpenWithProtocol: didOpenWithProtocol)
    }

    public func urlSession(_ session: URLSession, webSocketTask: URLSessionWebSocketTask, didCloseWith closeCode: URLSessionWebSocketTask.CloseCode, reason: Data?) {
        weakDelegate?.urlSession(session, webSocketTask: webSocketTask, didCloseWith: closeCode, reason: reason)
    }
}
