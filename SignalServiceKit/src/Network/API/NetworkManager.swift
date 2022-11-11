//
// Copyright 2018 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

// A class used for making HTTP requests against the main service.
@objc
public class NetworkManager: NSObject {
    private let restNetworkManager = RESTNetworkManager()

    @objc
    public override init() {
        super.init()

        SwiftSingletons.register(self)
    }

    // This method can be called from any thread.
    public func makePromise(request: TSRequest,
                            websocketSupportsRequest: Bool = false,
                            remainingRetryCount: Int = 0) -> Promise<HTTPResponse> {
        firstly { () -> Promise<HTTPResponse> in
            // Fail over to REST if websocket attempt fails.
            let shouldUseWebsocket: Bool = {
                guard !signalService.isCensorshipCircumventionActive else {
                    return false
                }
                return (remainingRetryCount > 0 &&
                        OWSWebSocket.canAppUseSocketsToMakeRequests &&
                        websocketSupportsRequest)
            }()
            return (shouldUseWebsocket
                        ? websocketRequestPromise(request: request)
                        : restRequestPromise(request: request))
        }.recover(on: .global()) { error -> Promise<HTTPResponse> in
            if error.isRetryable,
               remainingRetryCount > 0 {
                // TODO: Backoff?
                return self.makePromise(request: request,
                                        remainingRetryCount: remainingRetryCount - 1)
            } else {
                throw error
            }
        }
    }

    private func isRESTOnlyEndpoint(request: TSRequest) -> Bool {
        guard let url = request.url else {
            owsFailDebug("Missing url.")
            return true
        }
        guard let urlComponents = URLComponents(string: url.absoluteString) else {
            owsFailDebug("Missing urlComponents.")
            return true
        }
        let path: String = urlComponents.path
        let missingEndpoints = [
            "/v1/payments/auth"
        ]
        return missingEndpoints.contains(path)
    }

    private func restRequestPromise(request: TSRequest) -> Promise<HTTPResponse> {
        restNetworkManager.makePromise(request: request)
    }

    private func websocketRequestPromise(request: TSRequest) -> Promise<HTTPResponse> {
        Self.socketManager.makeRequestPromise(request: request)
    }
}

// MARK: -

#if TESTABLE_BUILD

@objc
public class OWSFakeNetworkManager: NetworkManager {

    public override func makePromise(request: TSRequest,
                                     websocketSupportsRequest: Bool = false,
                                     remainingRetryCount: Int = 0) -> Promise<HTTPResponse> {
        Logger.info("Ignoring request: \(request)")
        // Never resolve.
        let (promise, _) = Promise<HTTPResponse>.pending()
        return promise
    }
}

#endif
