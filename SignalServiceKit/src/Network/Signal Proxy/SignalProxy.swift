//
//  Copyright (c) 2022 Open Whisper Systems. All rights reserved.
//

import Foundation

extension Notification.Name {
    static let isSignalProxyReadyDidChange = Self(SignalProxy.isSignalProxyReadyDidChangeNotificationName)
}

@objc
public class SignalProxy: NSObject {
    @objc
    public static let isSignalProxyReadyDidChangeNotificationName = "isSignalProxyReadyDidChange"

    public static var isEnabled: Bool { host != nil }
    public static var isEnabledAnReady: Bool { isEnabled && relayServer.isReady }

    public static var connectionProxyDictionary: [AnyHashable: Any]? { relayServer.connectionProxyDictionary }

    @Atomic
    public private(set) static var host: String?

    private static let relayServer = RelayServer()

    private static let keyValueStore = SDSKeyValueStore(collection: "SignalProxy")
    private static let proxyUrlHostKey = "proxyUrlHostKey"

    public static func setProxyUrl(url: URL?, transaction: SDSAnyWriteTransaction) {
        let newHost: String?

        if let host = url?.host {
            keyValueStore.setString(host, key: proxyUrlHostKey, transaction: transaction)

            newHost = host
        } else {
            keyValueStore.removeAll(transaction: transaction)

            newHost = nil
        }

        transaction.addSyncCompletion {
            self.host = newHost

            if isEnabled {
                relayServer.start()
            } else {
                relayServer.stop()
            }
        }
    }

    @objc
    public class func warmCaches() {
        AppReadiness.runNowOrWhenAppWillBecomeReady {
            databaseStorage.read { transaction in
                host = keyValueStore.getString(proxyUrlHostKey, transaction: transaction)
            }

            if isEnabled { relayServer.start() }
        }
    }
}
