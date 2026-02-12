//
// Copyright 2018 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import Reachability
public import LibSignalClient

public protocol NetworkManagerProtocol {
    func asyncRequestImpl(
        _ request: TSRequest,
        retryPolicy: NetworkManager.RetryPolicy,
    ) async throws -> HTTPResponse
}

extension NetworkManagerProtocol {
    public func asyncRequest(
        _ request: TSRequest,
        retryPolicy: NetworkManager.RetryPolicy = .dont,
    ) async throws -> HTTPResponse {
        return try await asyncRequestImpl(request, retryPolicy: retryPolicy)
    }
}

// A class used for making HTTP requests against the main service.
public class NetworkManager: NetworkManagerProtocol {
    private let appReadiness: AppReadiness
    private let reachabilityDidChangeObserver: Task<Void, Never>?
    private var chatConnectionManager: ChatConnectionManager {
        // TODO: Fix circular dependencies.
        DependenciesBridge.shared.chatConnectionManager
    }

    public let libsignalNet: Net?

    public init(appReadiness: AppReadiness, libsignalNet: Net?) {
        self.appReadiness = appReadiness
        self.libsignalNet = libsignalNet
        if let libsignalNet {
            self.reachabilityDidChangeObserver = Task {
                for await notification in NotificationCenter.default.notifications(named: .reachabilityChanged) {
                    let reachability = notification.object as! Reachability
                    Logger.info("New preferred network: \(reachability.currentReachabilityString()!)")
                    do {
                        if !SignalProxy.isEnabled {
                            Self.resetLibsignalNetProxySettings(libsignalNet, appReadiness: appReadiness)
                        }
                        try libsignalNet.networkDidChange()
                    } catch {
                        owsFailDebug("error notify libsignal of network change: \(error)")
                    }
                }
            }

            self.resetLibsignalNetProxySettings()
            Logger.info("Initialized libsignal Net and reset proxy settings (signalProxyEnabled: \(SignalProxy.isEnabled)).")
            appReadiness.runNowOrWhenAppDidBecomeReadyAsync {
                // We did this once already, but doing it properly depends on RemoteConfig.
                self.resetLibsignalNetProxySettings()
                // This is redundant with the instance in ReachabilityManager, but that's ok.
                let reachability = Reachability.forInternetConnection()!
                Logger.info("Initial preferred network: \(reachability.currentReachabilityString()!)")
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

    // MARK: -

    func resetLibsignalNetProxySettings() {
        guard let libsignalNet else {
            // In tests without a libsignal Net instance, no action is needed.
            return
        }
        Self.resetLibsignalNetProxySettings(libsignalNet, appReadiness: appReadiness)
    }

    private static func resetLibsignalNetProxySettings(_ libsignalNet: Net, appReadiness: AppReadiness) {
        if let systemProxy = ProxyConfig.fromCFNetwork() {
            Logger.info("System '\(systemProxy.scheme)' proxy detected")
            do {
                try libsignalNet.setProxy(scheme: systemProxy.scheme, host: systemProxy.host, port: systemProxy.port, username: systemProxy.username, password: systemProxy.password)
                return
            } catch {
                Logger.error("invalid proxy: \(error)")
                // When setProxy(...) fails, it refuses to connect in case your proxy was load-bearing.
                // That makes sense for in-app settings, but less so for system-level proxies, given that we are already ignoring system-level proxies we don't understand.
                // Fall through to the reset call.
            }
        }

        // This may be clearing a system proxy, or a previously set in-app proxy that is no longer in use.
        libsignalNet.clearProxy()
    }

    // MARK: -

    public struct RetryPolicy {
        public struct RetryOn: OptionSet {
            public let rawValue: Int

            public init(rawValue: Int) {
                self.rawValue = rawValue
            }

            static let fiveXXResponse: RetryOn = .init(rawValue: 1 << 0)
            static let networkFailureOrTimeout: RetryOn = .init(rawValue: 1 << 1)
        }

        public let retryOn: [RetryOn]
        public let maxAttempts: Int

        public init(
            retryOn: [RetryOn],
            maxAttempts: Int,
        ) {
            self.retryOn = retryOn
            self.maxAttempts = maxAttempts
        }

        public static let dont: RetryPolicy = RetryPolicy(
            retryOn: [],
            maxAttempts: 1,
        )

        public static let hopefullyRecoverable: RetryPolicy = RetryPolicy(
            retryOn: [.fiveXXResponse, .networkFailureOrTimeout],
            maxAttempts: 3,
        )
    }

    public func asyncRequestImpl(
        _ request: TSRequest,
        retryPolicy: RetryPolicy,
    ) async throws -> HTTPResponse {
        return try await Retry.performWithBackoff(
            maxAttempts: retryPolicy.maxAttempts,
            isRetryable: { error -> Bool in
                if
                    error.isNetworkFailureOrTimeout,
                    retryPolicy.retryOn.contains(.networkFailureOrTimeout)
                {
                    return true
                } else if
                    error.is5xxServiceResponse,
                    retryPolicy.retryOn.contains(.fiveXXResponse)
                {
                    return true
                }

                return false
            },
            block: { try await _asyncRequest(request) },
        )
    }

    private func _asyncRequest(_ request: TSRequest) async throws -> HTTPResponse {
        do {
            return try await chatConnectionManager.makeRequest(request)
        } catch {
            if case OWSHTTPError.wrappedFailure(URLError.cancelled) = error {
                try Task.checkCancellation()
            }
            throw error
        }
    }
}

// MARK: -

private struct ProxyConfig {
    var scheme: String
    var host: String
    var port: UInt16?
    var username: String?
    var password: String?

    static func fromCFNetwork() -> Self? {
        let chatURL = URL(string: TSConstants.mainServiceURL)!
        guard let settings = CFNetworkCopySystemProxySettings()?.takeRetainedValue() else {
            return nil
        }
        let proxies = CFNetworkCopyProxiesForURL(chatURL as CFURL, settings).takeRetainedValue() as! [NSDictionary]

        for proxyConfig in proxies {
            switch proxyConfig[kCFProxyTypeKey] as! NSObject? {
            case kCFProxyTypeNone:
                // CFNetworkCopyProxiesForURL returns a list of proxies to try in order,
                // and that can include "try a direct connection".
                // But libsignal only supports one global proxy setting,
                // so if we get told to try a direct connection, that's what we'll do.
                return nil
            case kCFProxyTypeHTTP:
                return ProxyConfig(
                    scheme: "http",
                    host: proxyConfig[kCFProxyHostNameKey] as! String,
                    port: proxyConfig[kCFProxyPortNumberKey] as! UInt16?,
                    username: proxyConfig[kCFProxyUsernameKey] as! String?,
                    password: proxyConfig[kCFProxyPasswordKey] as! String?,
                )
            case kCFProxyTypeHTTPS:
                // This seems to mean "HTTP proxy for HTTPS connections" rather than "proxy that itself uses TLS".
                // Leave room for the latter interpretation if the port number is traditionally HTTPS.
                let port = proxyConfig[kCFProxyPortNumberKey] as! UInt16?
                return ProxyConfig(
                    scheme: (port == 443 || port == 8443) ? "https" : "http",
                    host: proxyConfig[kCFProxyHostNameKey] as! String,
                    port: port,
                    username: proxyConfig[kCFProxyUsernameKey] as! String?,
                    password: proxyConfig[kCFProxyPasswordKey] as! String?,
                )
            case kCFProxyTypeSOCKS:
                // iOS doesn't distinguish between SOCKS4 and SOCKS5. Defer to libsignal's default.
                return ProxyConfig(
                    scheme: "socks",
                    host: proxyConfig[kCFProxyHostNameKey] as! String,
                    port: proxyConfig[kCFProxyPortNumberKey] as! UInt16?,
                    username: proxyConfig[kCFProxyUsernameKey] as! String?,
                    password: proxyConfig[kCFProxyPasswordKey] as! String?,
                )
            case kCFProxyTypeAutoConfigurationJavaScript, kCFProxyTypeAutoConfigurationURL:
                // CFNetwork provides ways to execute these, but they're not something that can be done synchronously.
                // PAC files are rare, though; we can come back to this if it turns out to be used in practice.
                Logger.warn("Skipping PAC-based proxy configuration")
                continue
            case kCFProxyTypeFTP:
                // Not relevant for an HTTPS request (honestly, it should never be returned in the first place)
                continue
            case let unknownProxyType?:
                Logger.warn("Skipping unknown proxy type '\(unknownProxyType)'")
                continue
            case nil:
                Logger.warn("Skipping proxy with nil kCFProxyType; this is probably an Apple bug!")
                continue
            }
        }

        return nil
    }
}

// MARK: -

#if TESTABLE_BUILD

public class OWSFakeNetworkManager: NetworkManager {

    override public func asyncRequestImpl(
        _ request: TSRequest,
        retryPolicy: RetryPolicy,
    ) async throws -> HTTPResponse {
        Logger.info("Ignoring request: \(request)")
        // Never resolve.
        return try await withUnsafeThrowingContinuation { (_ continuation: UnsafeContinuation<HTTPResponse, any Error>) -> Void in }
    }
}

class MockNetworkManager: NetworkManagerProtocol {
    var asyncRequestHandlers = [(TSRequest, NetworkManager.RetryPolicy) async throws -> HTTPResponse]()
    func asyncRequestImpl(
        _ request: TSRequest,
        retryPolicy: NetworkManager.RetryPolicy,
    ) async throws -> HTTPResponse {
        return try await asyncRequestHandlers.removeFirst()(request, retryPolicy)
    }
}

#endif
