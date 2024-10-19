//
// Copyright 2021 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

private let networkManagerQueue = DispatchQueue(
    label: "org.signal.network-manager",
    autoreleaseFrequency: .workItem)

class RESTNetworkManager {
    fileprivate typealias Success = (HTTPResponse) -> Void
    fileprivate typealias Failure = (OWSHTTPError) -> Void

    private let udSessionManagerPool = OWSSessionManagerPool()
    private let nonUdSessionManagerPool = OWSSessionManagerPool()

    init() {
        SwiftSingletons.register(self)
    }

    private func makeRequest(
        _ request: TSRequest,
        completionQueue: DispatchQueue,
        success: @escaping Success,
        failure: @escaping Failure
    ) {
        networkManagerQueue.async {
            self.makeRequestSync(request, completionQueue: completionQueue, success: success, failure: failure)
        }
    }

    private func makeRequestSync(
        _ request: TSRequest,
        completionQueue: DispatchQueue,
        success successParam: @escaping Success,
        failure failureParam: @escaping Failure
    ) {
        let isUdRequest = request.isUDRequest
        let label = isUdRequest ? "UD request" : "Non-UD request"
        if (isUdRequest) {
            owsPrecondition(!request.shouldHaveAuthorizationHeaders)
        }
        Logger.info("Making \(label): \(request)")

        let sessionManagerPool = isUdRequest ? self.udSessionManagerPool : self.nonUdSessionManagerPool
        let sessionManager = sessionManagerPool.get()

        let success = { (response: HTTPResponse) in
            #if TESTABLE_BUILD
            if DebugFlags.logCurlOnSuccess {
                HTTPUtils.logCurl(for: request as URLRequest)
            }
            #endif

            networkManagerQueue.async {
                sessionManagerPool.returnToPool(sessionManager)
            }
            completionQueue.async {
                Logger.info("\(label) succeeded (\(response.responseStatusCode)) : \(request)")
                successParam(response)
                OutageDetection.shared.reportConnectionSuccess()
            }
        }
        let failure = { (error: OWSHTTPError) in
            networkManagerQueue.async {
                sessionManagerPool.returnToPool(sessionManager)
            }
            completionQueue.async {
                failureParam(error)
            }
        }
        sessionManager.performRequest(request, success: success, failure: failure)
    }

    func makePromise(request: TSRequest) -> Promise<HTTPResponse> {
        let (promise, future) = Promise<HTTPResponse>.pending()
        makeRequest(request,
                    completionQueue: .global(),
                    success: { (response: HTTPResponse) in
                        future.resolve(response)
                    },
                    failure: { (error: OWSHTTPError) in
                        future.reject(error)
                    })
        return promise
    }

    func asyncRequest(_ request: TSRequest) async throws -> HTTPResponse {
        try await withCheckedThrowingContinuation { continuation in
            makeRequest(request, completionQueue: .global(), success: { continuation.resume(returning: $0) }, failure: { continuation.resume(throwing: $0) })
        }
    }
}

// MARK: -

private class RESTSessionManager {

    private let urlSession: OWSURLSessionProtocol
    public let createdDate = Date()

    init() {
        assertOnQueue(networkManagerQueue)
        urlSession = SSKEnvironment.shared.signalServiceRef.urlSessionForMainSignalService()
    }

    public func performRequest(_ request: TSRequest,
                               success: @escaping RESTNetworkManager.Success,
                               failure: @escaping RESTNetworkManager.Failure) {
        assertOnQueue(networkManagerQueue)

        // We should only use the RESTSessionManager for requests to the Signal main service.
        let urlSession = self.urlSession
        owsAssertDebug(urlSession.unfrontedBaseUrl == URL(string: TSConstants.mainServiceIdentifiedURL))

        guard let requestUrl = request.url else {
            owsFailDebug("Missing requestUrl.")
            failure(.missingRequest)
            return
        }

        firstly {
            urlSession.promiseForTSRequest(request)
        }.done(on: DispatchQueue.global()) { (response: HTTPResponse) in
            success(response)
        }.catch(on: DispatchQueue.global()) { error in
            // OWSUrlSession should only throw OWSHTTPError or OWSAssertionError.
            if let httpError = error as? OWSHTTPError {
                HTTPUtils.applyHTTPError(httpError)

                if httpError.httpStatusCode == 401, request.shouldCheckDeregisteredOn401 {
                    networkManagerQueue.async {
                        self.makeIsDeregisteredRequest(
                            originalRequestFailureHandler: failure,
                            originalRequestFailure: httpError
                        )
                    }
                } else {
                    failure(httpError)
                }
            } else {
                owsFailDebug("Unexpected error: \(error)")

                failure(.invalidRequest(requestUrl: requestUrl))
            }
        }
    }

    private func makeIsDeregisteredRequest(
        originalRequestFailureHandler: @escaping RESTNetworkManager.Failure,
        originalRequestFailure: OWSHTTPError
    ) {
        let isDeregisteredRequest = WhoAmIRequestFactory.amIDeregisteredRequest()

        let handleDeregisteredResponse: (WhoAmIRequestFactory.Responses.AmIDeregistered?) -> Void = { response in
            switch response {
            case .deregistered:
                Logger.warn("AmIDeregistered response says we are deregistered, marking as such.")
                DependenciesBridge.shared.db.write { tx in
                    DependenciesBridge.shared.registrationStateChangeManager.setIsDeregisteredOrDelinked(true, tx: tx)
                }
            case .notDeregistered:
                Logger.info("AmIDeregistered response says not deregistered; account probably disabled. Doing nothing.")
            case .none, .unexpectedError:
                Logger.error("Got unexpected AmIDeregistered response. Doing nothing.")
            }
        }

        self.performRequest(
            isDeregisteredRequest,
            success: { rawResponse in
                let response = WhoAmIRequestFactory.Responses.AmIDeregistered(rawValue: rawResponse.responseStatusCode)
                handleDeregisteredResponse(response)
                originalRequestFailureHandler(originalRequestFailure)
            }, failure: { rawFailure in
                let response = WhoAmIRequestFactory.Responses.AmIDeregistered(rawValue: rawFailure.responseStatusCode)
                handleDeregisteredResponse(response)
                originalRequestFailureHandler(originalRequestFailure)
            }
        )
    }
}

// MARK: -

// Session managers are stateful (e.g. the headers in the requestSerializer).
// Concurrent requests can interfere with each other. Therefore we use a pool
// do not re-use a session manager until its request succeeds or fails.
private class OWSSessionManagerPool {
    private let maxSessionManagerAge = 5 * kMinuteInterval

    // must only be accessed from the networkManagerQueue for thread-safety
    private var pool: [RESTSessionManager] = []

    // accessed from both networkManagerQueue and the main thread so needs a lock
    @Atomic private var lastDiscardDate: Date?

    init() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(OWSSessionManagerPool.isCensorshipCircumventionActiveDidChange),
            name: Notification.Name.isCensorshipCircumventionActiveDidChange,
            object: nil)
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(OWSSessionManagerPool.isSignalProxyReadyDidChange),
            name: Notification.Name.isSignalProxyReadyDidChange,
            object: nil)
    }

    @objc
    private func isCensorshipCircumventionActiveDidChange() {
        AssertIsOnMainThread()
        lastDiscardDate = Date()
    }

    @objc
    private func isSignalProxyReadyDidChange() {
        AssertIsOnMainThread()
        lastDiscardDate = Date()
    }

    func get() -> RESTSessionManager {
        assertOnQueue(networkManagerQueue)

        // Iterate over the pool, discarding expired session managers
        // until we find an unexpired session manager in the pool or
        // drain the pool and create a new session manager.
        while true {
            guard let sessionManager = pool.popLast() else {
                return RESTSessionManager()
            }
            if shouldDiscardSessionManager(sessionManager) {
                continue
            }
            return sessionManager
        }
    }

    func returnToPool(_ sessionManager: RESTSessionManager) {
        assertOnQueue(networkManagerQueue)

        let maxPoolSize = CurrentAppContext().isNSE ? 5 : 32
        guard pool.count < maxPoolSize && !shouldDiscardSessionManager(sessionManager) else {
            return
        }
        pool.append(sessionManager)
    }

    private func shouldDiscardSessionManager(_ sessionManager: RESTSessionManager) -> Bool {
        if lastDiscardDate?.isAfter(sessionManager.createdDate) ?? false {
            return true
        }
        return fabs(sessionManager.createdDate.timeIntervalSinceNow) > maxSessionManagerAge
    }
}
