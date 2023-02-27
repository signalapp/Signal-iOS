//
// Copyright 2022 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import Network

extension SignalProxy {
    /// Establishes a connection to a Signal TLS Proxy and relays transmitted data via the provided `RelayClient`
    class ProxyClient {
        @Atomic
        private(set) var isStarted = false
        let id: UUID

        var didStopCallback: ((Error?) -> Void)?

        private weak var relayClient: RelayClient?
        private var connection: NWConnection?
        private lazy var queue = DispatchQueue(label: "org.signal.proxy.client", attributes: .concurrent)

        init(relayClient: RelayClient) {
            self.id = relayClient.id
            self.relayClient = relayClient
        }

        func start() {
            guard !isStarted else { return }
            isStarted = true

            Logger.debug("Proxy client \(id) starting...")

            guard let proxyHostComponents = SignalProxy.host?.components(separatedBy: ":"), let proxyHost = proxyHostComponents[safe: 0] else {
                return stop(error: OWSAssertionError("Unexpectedly missing proxy host!"))
            }

            let proxyPort: UInt16
            if let portString = proxyHostComponents[safe: 1], let port = UInt16(portString) {
                proxyPort = port
            } else {
                proxyPort = 443
            }

            connection = NWConnection(
                to: NWEndpoint.hostPort(
                    host: NWEndpoint.Host(proxyHost),
                    port: NWEndpoint.Port(integerLiteral: proxyPort)
                ),
                using: .tls
            )
            connection?.stateUpdateHandler = stateDidChange
            receive()
            connection?.start(queue: queue)
        }

        func stop(error: Error? = nil) {
            guard isStarted else { return }
            isStarted = false

            if let error = error {
                owsFailDebug("Proxy client \(id) did fail with error \(error)")
            } else {
                Logger.debug("Proxy client \(id) did stop")
            }

            connection?.stateUpdateHandler = nil
            connection?.cancel()

            if let didStopCallback = didStopCallback {
                self.didStopCallback = nil
                didStopCallback(error)
            }
        }

        func send(_ data: Data) {
            connection?.send(content: data, completion: .contentProcessed({ [weak self] error in
                guard let self = self else { return }

                if let error = error {
                    self.stop(error: error)
                    return
                }
            }))
        }

        private func stateDidChange(to state: NWConnection.State) {
            switch state {
            case .ready:
                Logger.debug("Proxy client \(id) ready!")
                relayClient?.send("HTTP/1.1 200\r\n\r\n".data(using: .utf8)!)
            case .failed(let error), .waiting(let error):
                relayClient?.send("HTTP/1.1 503\r\n\r\n".data(using: .utf8)!)
                stop(error: error)
            default:
                break
            }
        }

        private func receive() {
            connection?.receive(minimumIncompleteLength: 1, maximumLength: 65535) { [weak self] content, _, isComplete, error in
                guard let self = self else { return }

                content.map { self.relayClient?.send($0) }

                if isComplete {
                    self.stop()
                } else if let error = error {
                    self.stop(error: error)
                } else {
                    self.receive()
                }
            }
        }
    }
}
