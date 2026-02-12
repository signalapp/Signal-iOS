//
// Copyright 2022 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

public extension Notification.Name {
    static let isSignalProxyReadyDidChange = Notification.Name("isSignalProxyReadyDidChange")
    static let signalProxyConfigDidChange = Notification.Name("signalProxyConfigDidChange")
}

public class SignalProxy: NSObject {
    public static var isEnabled: Bool { useProxy && host != nil }

    public static var isEnabledAndReady: Bool { isEnabled && relayServer.isReady }

    public static var connectionProxyDictionary: [AnyHashable: Any]? { relayServer.connectionProxyDictionary }

    @Atomic public private(set) static var host: String?

    @Atomic public private(set) static var useProxy = false

    private static let relayServer = RelayServer()

    private static let keyValueStore = KeyValueStore(collection: "SignalProxy")
    private static let proxyHostKey = "proxyHostKey"
    private static let proxyUseKey = "proxyUseKey"

    public static func setProxyHost(host: String?, useProxy: Bool, transaction: DBWriteTransaction) {
        let hostToStore = host?.nilIfEmpty
        let useProxyToStore = hostToStore == nil ? false : useProxy
        owsAssertDebug(useProxyToStore == useProxy)

        keyValueStore.setString(hostToStore, key: proxyHostKey, transaction: transaction)
        keyValueStore.setBool(useProxyToStore, key: proxyUseKey, transaction: transaction)

        transaction.addSyncCompletion {
            self.host = hostToStore
            self.useProxy = useProxyToStore
            self.ensureProxyState(restartIfNeeded: true)
            self.updateLibSignalProxy()
            // Not always on the main thread because it makes ordering easier to reason about
            NotificationCenter.default.post(name: .signalProxyConfigDidChange, object: nil)
        }
    }

    private static var didAddObserver = false

    public class func warmCaches(appReadiness: AppReadiness) {
        appReadiness.runNowOrWhenAppWillBecomeReady {
            SSKEnvironment.shared.databaseStorageRef.read { transaction in
                host = keyValueStore.getString(proxyHostKey, transaction: transaction)
                useProxy = keyValueStore.getBool(proxyUseKey, defaultValue: false, transaction: transaction)
            }

            if !didAddObserver {
                NotificationCenter.default.addObserver(self, selector: #selector(applicationDidBecomeActive), name: .OWSApplicationDidBecomeActive, object: nil)
                didAddObserver = true
            }

            ensureProxyState()
            updateLibSignalProxy()
        }
    }

    @objc
    public class func isValidProxyLink(_ url: URL) -> Bool {
        guard url.user == nil, url.password == nil, url.port == nil else {
            return false
        }

        guard url.host?.caseInsensitiveCompare("signal.tube") == .orderedSame else {
            return false
        }

        guard let scheme = url.scheme else {
            return false
        }
        let isValidScheme = (
            scheme.caseInsensitiveCompare("https") == .orderedSame ||
                scheme.caseInsensitiveCompare("sgnl") == .orderedSame,
        )
        guard isValidScheme else {
            return false
        }

        guard isValidProxyFragment(url.fragment) else { return false }

        return true
    }

    public class func isValidProxyFragment(_ fragment: String?) -> Bool {
        guard
            let fragment = fragment?.nilIfEmpty,
            // To quote [RFC 1034][0]: "the total number of octets that represent a domain name
            // [...] is limited to 255." To be extra careful, we set a maximum of 2048.
            // [0]: https://tools.ietf.org/html/rfc1034
            fragment.utf8.count <= 2048,
            let proxyUrl = URL(string: "fake-protocol://\(fragment)"),
            proxyUrl.scheme == "fake-protocol",
            proxyUrl.user == nil || (DebugFlags.internalSettings && proxyUrl.user == "UNENCRYPTED_FOR_TESTING"),
            proxyUrl.password == nil,
            proxyUrl.path.isEmpty,
            proxyUrl.query == nil,
            proxyUrl.fragment == nil,
            proxyUrl.port != 0,
            let proxyHost = proxyUrl.host
        else {
            return false
        }

        // There must be at least 2 domain labels, and none of them can be empty.
        let labels = proxyHost.split(separator: ".", omittingEmptySubsequences: false)
        guard labels.count >= 2 else {
            return false
        }
        guard labels.allSatisfy({ !$0.isEmpty }) else {
            return false
        }

        return true
    }

    @objc
    private class func applicationDidBecomeActive() {
        ensureProxyState()
    }

    private class func ensureProxyState(restartIfNeeded: Bool = false) {
        // The NSE manages the proxy relay itself
        guard !CurrentAppContext().isNSE else { return }

        if isEnabled {
            if restartIfNeeded, relayServer.isStarted {
                relayServer.restartIfNeeded(ignoreBackoff: true)
            } else {
                relayServer.start()
            }
        } else {
            relayServer.stop()
        }
    }

    private static func updateLibSignalProxy() {
        let networkManager = SSKEnvironment.shared.networkManagerRef
        if isEnabled {
            if let (proxyHost, proxyPort) = host.flatMap({ ProxyClient.parseHost($0) }) {
                if let libsignalNet = networkManager.libsignalNet {
                    Logger.info("Applying signal proxy settings to libsignal Net.")
                    do {
                        try libsignalNet.setProxy(host: proxyHost, port: proxyPort)
                        Logger.info("Applied signal proxy settings to libsignal Net.")
                    } catch {
                        owsFailDebug("failed to set proxy on libsignal-net (need better validation)")
                        // This will poison the Net instance, failing all new connections,
                        // until a valid proxy is set or cleared.
                    }
                }
            } else {
                // We can't print the invalid host in the logs, because that's private!
                owsFailDebug("failed to parse previously-validated proxy host")
            }
        } else {
            networkManager.resetLibsignalNetProxySettings()
        }
    }

    public class func startRelayServer() {
        guard isEnabled else { return }
        Logger.info("Starting the proxy relay server...")
        relayServer.start()
    }

    public class func stopRelayServer() {
        guard isEnabled else { return }
        Logger.info("Stopping the proxy relay server...")
        relayServer.stop()
    }
}
