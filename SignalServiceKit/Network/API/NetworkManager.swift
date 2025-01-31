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
                        if !SignalProxy.isEnabled {
                            Self.resetLibsignalNetProxySettings(libsignalNet)
                        }
                        try libsignalNet.networkDidChange()
                    } catch {
                        owsFailDebug("error notify libsignal of network change: \(error)")
                    }
                }
            }
            self.resetLibsignalNetProxySettings()
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

    func resetLibsignalNetProxySettings() {
        guard let libsignalNet else {
            // In tests without a libsignal Net instance, no action is needed.
            return
        }
        Self.resetLibsignalNetProxySettings(libsignalNet)
    }

    private static func resetLibsignalNetProxySettings(_ libsignalNet: Net) {
        if let systemProxy = ProxyConfig.fromCFNetwork() {
            Logger.info("System '\(systemProxy.scheme)' proxy detected")
            do {
                try libsignalNet.setProxy(scheme: systemProxy.scheme, host: systemProxy.host, port: systemProxy.port, username: systemProxy.username, password: systemProxy.password)
            } catch {
                Logger.error("invalid proxy: \(error)")
                // When setProxy(...) fails, it refuses to connect in case your proxy was load-bearing.
                // That makes sense for in-app settings, but less so for system-level proxies, given that we are already ignoring system-level proxies we don't understand.
                libsignalNet.clearProxy()
            }
        } else {
            libsignalNet.clearProxy()
        }
    }

    public func asyncRequest(_ request: TSRequest, canUseWebSocket: Bool = true) async throws -> HTTPResponse {
        if canUseWebSocket && OWSChatConnection.canAppUseSocketsToMakeRequests {
            return try await DependenciesBridge.shared.chatConnectionManager.makeRequest(request)
        } else {
            return try await restNetworkManager.asyncRequest(request)
        }
    }

    /// Deprecated. Please use ``asyncRequest(_:canUseWebSocket:)``.
    public func makePromise(request: TSRequest, canUseWebSocket: Bool = true) -> Promise<HTTPResponse> {
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

private struct ProxyConfig {
    var scheme: String
    var host: String
    var port: UInt16?
    var username: String?
    var password: String?

    static func fromCFNetwork() -> Self? {
        let chatURL = URL(string: TSConstants.mainServiceIdentifiedURL)!
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
                    password: proxyConfig[kCFProxyPasswordKey] as! String?)
            case kCFProxyTypeHTTPS:
                // iOS doesn't distinguish HTTP and HTTPS sometimes. Do a bit of extra sniffing by port.
                let port = proxyConfig[kCFProxyPortNumberKey] as! UInt16?
                return ProxyConfig(
                    scheme: (port == 80 || port == 8080) ? "http" : "https",
                    host: proxyConfig[kCFProxyHostNameKey] as! String,
                    port: port,
                    username: proxyConfig[kCFProxyUsernameKey] as! String?,
                    password: proxyConfig[kCFProxyPasswordKey] as! String?)
            case kCFProxyTypeSOCKS:
                // iOS doesn't distinguish between SOCKS4 and SOCKS5. Defer to libsignal's default.
                return ProxyConfig(
                    scheme: "socks",
                    host: proxyConfig[kCFProxyHostNameKey] as! String,
                    port: proxyConfig[kCFProxyPortNumberKey] as! UInt16?,
                    username: proxyConfig[kCFProxyUsernameKey] as! String?,
                    password: proxyConfig[kCFProxyPasswordKey] as! String?)
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

    public override func asyncRequest(_ request: TSRequest, canUseWebSocket: Bool) async throws -> any HTTPResponse {
        Logger.info("Ignoring request: \(request)")
        // Never resolve.
        return try await withUnsafeThrowingContinuation { (_ continuation: UnsafeContinuation<any HTTPResponse, any Error>) -> Void in }
    }

    public override func makePromise(request: TSRequest, canUseWebSocket: Bool) -> Promise<HTTPResponse> {
        Logger.info("Ignoring request: \(request)")
        // Never resolve.
        let (promise, _) = Promise<HTTPResponse>.pending()
        return promise
    }
}

#endif
