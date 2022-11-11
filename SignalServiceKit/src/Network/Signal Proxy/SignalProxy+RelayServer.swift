//
// Copyright 2022 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import Network

extension SignalProxy {
    /// An HTTP Proxy server that relays traffic to a Signal TLS Proxy
    class RelayServer {
        @Atomic
        private(set) var isStarted = false

        @Atomic
        private(set) var isReady = false {
            didSet {
                NotificationCenter.default.postNotificationNameAsync(.isSignalProxyReadyDidChange, object: nil)
            }
        }

        var connectionProxyDictionary: [AnyHashable: Any]? {
            guard isReady, let port = listener?.port?.rawValue else { return nil }

            return [
                "HTTPSEnable": true,
                "HTTPSProxy": "localhost",
                "HTTPSPort": port,
                "HTTPEnable": true,
                "HTTPProxy": "localhost",
                "HTTPPort": port
            ]
        }

        @Atomic
        private var listener: NWListener?

        @Atomic
        private var clients = [UUID: RelayClient]()

        @Atomic
        private var backgroundTask: OWSBackgroundTask?

        private let queue = DispatchQueue(label: "SignalProxy.RelayServer", attributes: .concurrent)

        func start() {
            guard !isStarted else { return }
            guard SignalProxy.isEnabled else { return }

            isStarted = true

            backgroundTask = OWSBackgroundTask(label: "RelayServer") { [weak self] status in
                guard status == .expired else { return }
                self?.stop(error: OWSAssertionError("Background time expired"))
            }

            Logger.info("Relay server starting...")

            do {
                listener = try NWListener(using: .tcp, on: .any)
                listener?.stateUpdateHandler = stateDidChange
                listener?.newConnectionHandler = didAccept
                listener?.start(queue: queue)

                restartFailureCount = 0
            } catch {
                restartIfNeeded(error: error)
            }
        }

        func stop(error: Error? = nil) {
            guard isStarted else { return }
            isStarted = false
            isReady = false
            backgroundTask = nil

            listener?.stateUpdateHandler = nil
            listener?.newConnectionHandler = nil
            listener?.cancel()
            listener = nil

            for client in clients.values {
                client.didStopCallback = nil
                client.stop()
            }
            clients.removeAll()

            if let error = error {
                owsFailDebug("Relay server stopped with error \(error)")
            } else {
                restartFailureCount = 0
            }
        }

        @Atomic
        private var restartFailureCount: UInt = 0

        @Atomic
        private var restartBackoffTimer: Timer?

        func restartIfNeeded(error: Error? = nil, ignoreBackoff: Bool = false) {
            guard isStarted else { return }

            restartBackoffTimer?.invalidate()
            restartBackoffTimer = nil

            if error != nil { restartFailureCount += 1 }
            stop(error: error)

            restartBackoffTimer = .scheduledTimer(
                withTimeInterval: ignoreBackoff ? 0 : OWSOperation.retryIntervalForExponentialBackoff(
                    failureCount: restartFailureCount,
                    maxBackoff: 15
                ),
                repeats: false
            ) { [weak self] _ in
                guard let self = self else { return }

                Logger.info("Restarting relay server...")

                self.start()

                self.restartBackoffTimer?.invalidate()
                self.restartBackoffTimer = nil
            }
        }

        func stateDidChange(to newState: NWListener.State) {
            switch newState {
            case .ready:
                Logger.info("Relay server ready.")
                isReady = true
            case .failed(let error):
                restartIfNeeded(error: error)
            default:
                break
            }
        }

        private func didAccept(connection: NWConnection) {
            let client = RelayClient(connection: connection)
            clients[client.id] = client
            client.didStopCallback = { [weak self] _ in
                self?.clientDidStop(client)
            }
            client.start()
        }

        private func clientDidStop(_ client: RelayClient) {
            clients[client.id] = nil
        }
    }
}
