//
//  Copyright (c) 2022 Open Whisper Systems. All rights reserved.
//

import Foundation
import Network

extension SignalProxy {
    class ProxyClient {
        @Atomic
        private(set) var isStarted = false
        let id: UUID

        var didStopCallback: ((Error?) -> Void)?

        private weak var relayClient: RelayClient?
        private var connection: NWConnection?
        private lazy var queue = DispatchQueue(label: "SignalProxy.ProxyClient<\(id)>", attributes: .concurrent)

        init(relayClient: RelayClient) {
            self.id = relayClient.id
            self.relayClient = relayClient
        }

        func start() {
            guard !isStarted else { return }
            isStarted = true

            Logger.verbose("Proxy client \(id) starting...")

            guard let proxyHost = SignalProxy.host else {
                return stop(error: OWSAssertionError("Unexpectedly missing proxy host!"))
            }

            connection = NWConnection(
                to: NWEndpoint.hostPort(
                    host: NWEndpoint.Host(proxyHost),
                    port: NWEndpoint.Port(443)
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
                Logger.verbose("Proxy client \(id) did stop")
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

                Logger.verbose("Proxy client \(self.id) did send data")
            }))
        }

        private func stateDidChange(to state: NWConnection.State) {
            switch state {
            case .ready:
                Logger.verbose("Proxy client \(id) ready!")
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
