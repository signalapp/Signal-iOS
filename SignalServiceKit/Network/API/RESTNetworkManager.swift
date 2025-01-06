//
// Copyright 2021 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

class RESTNetworkManager {
    private let udSessionManagerPool = OWSSessionManagerPool()
    private let nonUdSessionManagerPool = OWSSessionManagerPool()

    init() {
        SwiftSingletons.register(self)
    }

    private func makeRequest(_ request: TSRequest) async throws -> any HTTPResponse {
        let isUdRequest = request.isUDRequest
        if (isUdRequest) {
            owsPrecondition(!request.shouldHaveAuthorizationHeaders)
        }

        let sessionManagerPool = isUdRequest ? self.udSessionManagerPool : self.nonUdSessionManagerPool
        let sessionManager = sessionManagerPool.get()
        defer {
            sessionManagerPool.returnToPool(sessionManager)
        }

        let result = try await sessionManager.performRequest(request)

#if TESTABLE_BUILD
        if DebugFlags.logCurlOnSuccess {
            HTTPUtils.logCurl(for: request as URLRequest)
        }
#endif

        OutageDetection.shared.reportConnectionSuccess()

        return result
    }

    func makePromise(request: TSRequest) -> Promise<HTTPResponse> {
        return Promise.wrapAsync { return try await self.asyncRequest(request) }
    }

    func asyncRequest(_ request: TSRequest) async throws -> HTTPResponse {
        return try await makeRequest(request)
    }
}

// MARK: -

private class RESTSessionManager {

    private let urlSession: OWSURLSessionProtocol
    let createdDate = MonotonicDate()

    init() {
        urlSession = SSKEnvironment.shared.signalServiceRef.urlSessionForMainSignalService()
    }

    public func performRequest(_ request: TSRequest) async throws -> any HTTPResponse {
        // We should only use the RESTSessionManager for requests to the Signal main service.
        let urlSession = self.urlSession
        owsAssertDebug(urlSession.unfrontedBaseUrl == URL(string: TSConstants.mainServiceIdentifiedURL))

        do {
            return try await urlSession.performRequest(request)
        } catch let httpError as OWSHTTPError {
            // OWSUrlSession should only throw OWSHTTPError or OWSAssertionError.
            HTTPUtils.applyHTTPError(httpError)

            if httpError.httpStatusCode == 401, request.shouldCheckDeregisteredOn401 {
                try await makeIsDeregisteredRequest()
            }
            throw httpError
        } catch let error as CancellationError {
            throw error
        } catch {
            owsFailDebug("Unexpected error: \(error)")
            throw OWSHTTPError.invalidRequest
        }
    }

    private func makeIsDeregisteredRequest() async throws(CancellationError) {
        let isDeregisteredRequest = WhoAmIRequestFactory.amIDeregisteredRequest()

        let result: WhoAmIRequestFactory.Responses.AmIDeregistered?
        do {
            let response = try await self.performRequest(isDeregisteredRequest)
            result = WhoAmIRequestFactory.Responses.AmIDeregistered(rawValue: response.responseStatusCode)
        } catch let error as OWSHTTPError {
            result = WhoAmIRequestFactory.Responses.AmIDeregistered(rawValue: error.responseStatusCode)
        } catch let error as CancellationError {
            throw error
        } catch {
            result = nil
        }

        switch result {
        case .deregistered:
            Logger.warn("AmIDeregistered response says we are deregistered, marking as such.")
            await DependenciesBridge.shared.db.awaitableWrite { tx in
                DependenciesBridge.shared.registrationStateChangeManager.setIsDeregisteredOrDelinked(true, tx: tx)
            }
        case .notDeregistered:
            Logger.info("AmIDeregistered response says not deregistered; account probably disabled. Doing nothing.")
        case .none, .unexpectedError:
            Logger.error("Got unexpected AmIDeregistered response. Doing nothing.")
        }
    }
}

// MARK: -

// Session managers are stateful (e.g. the headers in the requestSerializer).
// Concurrent requests can interfere with each other. Therefore we use a pool
// do not re-use a session manager until its request succeeds or fails.
private class OWSSessionManagerPool {
    private let maxSessionManagerAge = 5 * 60 * NSEC_PER_SEC

    private let pool = AtomicValue<[RESTSessionManager]>([], lock: .init())

    // accessed from both networkManagerQueue and the main thread so needs a lock
    @Atomic private var lastDiscardDate: MonotonicDate?

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
        lastDiscardDate = MonotonicDate()
    }

    @objc
    private func isSignalProxyReadyDidChange() {
        AssertIsOnMainThread()
        lastDiscardDate = MonotonicDate()
    }

    func get() -> RESTSessionManager {
        // Iterate over the pool, discarding expired session managers
        // until we find an unexpired session manager in the pool or
        // drain the pool and create a new session manager.
        while true {
            guard let sessionManager = pool.update(block: { $0.popLast() }) else {
                return RESTSessionManager()
            }
            if shouldDiscardSessionManager(sessionManager) {
                continue
            }
            return sessionManager
        }
    }

    func returnToPool(_ sessionManager: RESTSessionManager) {
        if shouldDiscardSessionManager(sessionManager) {
            return
        }
        let maxPoolSize = CurrentAppContext().isNSE ? 5 : 32
        pool.update {
            if $0.count < maxPoolSize {
                $0.append(sessionManager)
            }
        }
    }

    private func shouldDiscardSessionManager(_ sessionManager: RESTSessionManager) -> Bool {
        if let lastDiscardDate, sessionManager.createdDate < lastDiscardDate {
            return true
        }
        return (MonotonicDate() - sessionManager.createdDate) > maxSessionManagerAge
    }
}
