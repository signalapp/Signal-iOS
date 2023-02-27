//
// Copyright 2022 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import Network

extension SignalProxy {
    /// Represents a connection to the `RelayServer`. Establishes a `ProxyClient` to interact with the signal service.
    class RelayClient {
        @Atomic
        private(set) var isStarted = false
        let id = UUID()

        var didStopCallback: ((Error?) -> Void)?

        private let connection: NWConnection
        private lazy var proxyClient = ProxyClient(relayClient: self)
        private lazy var queue = DispatchQueue(label: "org.signal.proxy.relay-client", attributes: .concurrent)

        init(connection: NWConnection) {
            self.connection = connection
        }

        func start() {
            guard !isStarted else { return }
            isStarted = true

            Logger.debug("Relay client \(id) starting...")

            connection.stateUpdateHandler = stateDidChange
            receive()
            connection.start(queue: queue)
        }

        func stop(error: Error? = nil) {
            guard isStarted else { return }
            isStarted = false

            if let error = error {
                owsFailDebug("Relay client \(id) did fail with error \(error)")
            } else {
                Logger.debug("Relay client \(id) did stop")
            }

            proxyClient.didStopCallback = nil
            proxyClient.stop(error: error)

            connection.stateUpdateHandler = nil
            connection.cancel()

            if let didStopCallback = didStopCallback {
                self.didStopCallback = nil
                didStopCallback(error)
            }
        }

        func send(_ data: Data) {
            connection.send(content: data, completion: .contentProcessed({ [weak self] error in
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
                Logger.debug("Relay client \(id) ready!")
            case .failed(let error), .waiting(let error):
                stop(error: error)
            default:
                break
            }
        }

        private func receive() {
            connection.receive(minimumIncompleteLength: 1, maximumLength: 65535) { [weak self] content, _, isComplete, error in
                guard let self = self else { return }

                if let content = content {
                    if self.proxyClient.isStarted {
                        self.proxyClient.send(content)
                    } else {
                        self.startProxyClient(content)
                    }
                }

                if isComplete {
                    self.stop()
                } else if let error = error {
                    self.stop(error: error)
                } else {
                    self.receive()
                }
            }
        }

        private func startProxyClient(_ data: Data) {
            guard
                let request = String(data: data, encoding: .utf8),
                let httpMethod = request
                    .components(separatedBy: .newlines)[safe: 0]?
                    .components(separatedBy: .whitespaces)[safe: 0],
                httpMethod == "CONNECT"
            else {
                stop(error: OWSAssertionError("Relay client \(id) failed to parse CONNECT"))
                return
            }

            proxyClient.didStopCallback = { [weak self] error in
                self?.stop(error: error)
            }
            proxyClient.start()
        }
    }
}
