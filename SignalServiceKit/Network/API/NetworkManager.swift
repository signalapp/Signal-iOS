//
// Copyright 2018 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
public import LibSignalClient

// A class used for making HTTP requests against the main service.
public class NetworkManager {
    private let restNetworkManager = RESTNetworkManager()
    private let reachabilityDidChangeObserver: Task<Void, Never>?
    public let libsignalNet: Net?

    public init(libsignalNet: Net?) {
        self.libsignalNet = libsignalNet
        if let libsignalNet {
            self.reachabilityDidChangeObserver = Task {
                for await _ in NotificationCenter.default.notifications(named: SSKReachability.owsReachabilityDidChange) {
                    do {
                        try libsignalNet.networkDidChange()
                    } catch {
                        owsFailDebug("error notify libsignal of network change: \(error)")
                    }
                }
            }
        } else {
            self.reachabilityDidChangeObserver = nil
        }

        SwiftSingletons.register(self)
    }

    deinit {
        if let reachabilityDidChangeObserver {
            reachabilityDidChangeObserver.cancel()
        }
    }

    public func asyncRequest(_ request: TSRequest, canUseWebSocket: Bool = false) async throws -> HTTPResponse {
        if canUseWebSocket && OWSChatConnection.canAppUseSocketsToMakeRequests {
            return try await DependenciesBridge.shared.chatConnectionManager.makeRequest(request)
        } else {
            return try await restNetworkManager.asyncRequest(request)
        }
    }

    /// Deprecated. Please use ``asyncRequest(_:canUseWebSocket:)``.
    public func makePromise(request: TSRequest, canUseWebSocket: Bool = false) -> Promise<HTTPResponse> {
        // Try the web socket first if it's allowed for this request.
        let useWebSocket = canUseWebSocket && OWSChatConnection.canAppUseSocketsToMakeRequests
        return useWebSocket ? websocketRequestPromise(request: request) : restRequestPromise(request: request)
    }

    private func restRequestPromise(request: TSRequest) -> Promise<HTTPResponse> {
        restNetworkManager.makePromise(request: request)
    }

    private func websocketRequestPromise(request: TSRequest) -> Promise<HTTPResponse> {
        Promise.wrapAsync {
            try await DependenciesBridge.shared.chatConnectionManager.makeRequest(request)
        }
    }
}

// MARK: -

#if TESTABLE_BUILD

public class OWSFakeNetworkManager: NetworkManager {

    public override func asyncRequest(_ request: TSRequest, canUseWebSocket: Bool = false) async throws -> any HTTPResponse {
        Logger.info("Ignoring request: \(request)")
        // Never resolve.
        return try await withUnsafeThrowingContinuation { (_ continuation: UnsafeContinuation<any HTTPResponse, any Error>) -> Void in }
    }

    public override func makePromise(request: TSRequest, canUseWebSocket: Bool = false) -> Promise<HTTPResponse> {
        Logger.info("Ignoring request: \(request)")
        // Never resolve.
        let (promise, _) = Promise<HTTPResponse>.pending()
        return promise
    }
}

#endif
