//
//  Copyright (c) 2022 Open Whisper Systems. All rights reserved.
//

import Foundation

public extension Notification.Name {
    static let isSignalProxyReadyDidChange = Self(SignalProxy.isSignalProxyReadyDidChangeNotificationName)
}

@objc
public class SignalProxy: NSObject {
    @objc
    public static let isSignalProxyReadyDidChangeNotificationName = "isSignalProxyReadyDidChange"

    @objc
    public static var isEnabled: Bool { useProxy && host != nil }

    @objc
    public static var isEnabledAnReady: Bool { isEnabled && relayServer.isReady }

    public static var connectionProxyDictionary: [AnyHashable: Any]? { relayServer.connectionProxyDictionary }

    @Atomic
    public private(set) static var host: String?

    @Atomic
    public private(set) static var useProxy = false

    private static let relayServer = RelayServer()

    private static let keyValueStore = SDSKeyValueStore(collection: "SignalProxy")
    private static let proxyHostKey = "proxyHostKey"
    private static let proxyUseKey = "proxyUseKey"

    public static func setProxyHost(host: String?, useProxy: Bool, transaction: SDSAnyWriteTransaction) {
        let hostToStore = host?.nilIfEmpty
        let useProxyToStore = hostToStore == nil ? false : useProxy
        owsAssertDebug(useProxyToStore == useProxy)

        keyValueStore.setString(hostToStore, key: proxyHostKey, transaction: transaction)
        keyValueStore.setBool(useProxyToStore, key: proxyUseKey, transaction: transaction)

        transaction.addSyncCompletion {
            self.host = hostToStore
            self.useProxy = useProxyToStore
            self.ensureProxyState()
        }
    }

    @objc
    public class func warmCaches() {
        AppReadiness.runNowOrWhenAppWillBecomeReady {
            databaseStorage.read { transaction in
                host = keyValueStore.getString(proxyHostKey, transaction: transaction)
                useProxy = keyValueStore.getBool(proxyUseKey, defaultValue: false, transaction: transaction)
            }

            NotificationCenter.default.addObserver(self, selector: #selector(ensureProxyState), name: .OWSApplicationDidBecomeActive, object: nil)

            ensureProxyState()
        }
    }

    @objc
    public class func isValidProxyLink(_ url: URL) -> Bool {
        (url.scheme.map { ["https", "sgnl"].contains($0) } ?? false) && url.host == "signal.tube" && url.fragment != nil
    }

    @objc
    private class func ensureProxyState() {
        if isEnabled {
            if relayServer.isStarted {
                relayServer.restart(ignoreBackoff: true)
            } else {
                relayServer.start()
            }
        } else {
            relayServer.stop()
        }
    }
}
