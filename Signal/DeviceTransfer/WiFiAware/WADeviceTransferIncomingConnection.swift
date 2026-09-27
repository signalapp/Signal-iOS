//
// Copyright 2026 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import Network
import SignalServiceKit
import WiFiAware

@available(iOS 26.0, *)
class WADeviceTransferIncomingConnection: DeviceTransfer.IncomingConnection {
    private let logger = PrefixedLogger(prefix: "[DeviceTransfer][WiFiAware][Incoming]")

    private var discoveredPeerTask: Task<Void, Never>?
    private let listenerTask = AtomicValue<Task<Void, any Error>?>(nil, lock: .init())

    let discoveredPeerStream: AsyncThrowingStream<[any DeviceTransfer.Peer], any Error>

    /// Internal peer stream broacaster monitored by this class for connection management
    private let peers: AsyncStreamBroadcast<[any DeviceTransfer.Peer]>

    let identity: SecIdentity
    let secIdentity: sec_identity_t

    init() throws {
        self.identity = try SelfSignedIdentity.create(name: "IncomingDeviceTransfer", validForDays: 1)
        guard let secIdentity = sec_identity_create(identity) else {
            throw OWSAssertionError("Unexpected identity format")
        }
        self.secIdentity = secIdentity
        let (internalPeerStream, peerTask) = WiFiAware.createPeerDiscoveryObserver(logger: logger)
        self.discoveredPeerTask = peerTask
        let peers = AsyncStreamBroadcast<[any DeviceTransfer.Peer]>(initialValue: [])
        self.peers = peers
        self.discoveredPeerStream = peers.subscribe()

        Task {
            do {
                for try await peerList in internalPeerStream {
                    // Publish peer data to any internal subscribers
                    peers.update(peerList)
                }
            } catch is CancellationError {
                // Nothing
            } catch {
                owsFailDebug("Peer discovery stream errored! \(error)")
            }
        }
    }

    deinit {
        listenerTask.swap(nil)?.cancel()
        discoveredPeerTask.take()?.cancel()
    }

    func start(mode: DeviceTransfer.Mode) throws -> URL {
        var components = URLComponents()
        components.scheme = UrlOpener.Constants.sgnlPrefix
        components.host = DeviceTransfer.UrlConstants.transferHost
        let queryItems = [
            DeviceTransfer.UrlConstants.versionKey: String(DeviceTransfer.UrlConstants.currentTransferVersion),
            DeviceTransfer.UrlConstants.transferModeKey: mode.rawValue,
            DeviceTransfer.UrlConstants.certificateHashKey:
                try identity.computeCertificateHash().base64EncodedString().encodeURIComponent ?? "",
        ]
        components.queryItems = queryItems.map { URLQueryItem(name: $0.key, value: $0.value) }
        return components.url!
    }

    func waitForConnection(peer: (any DeviceTransfer.Peer)?) async throws -> any DeviceTransfer.Session {
        logger.info("Wait for connection")
        let allowedConnections: WAPublisherListener.Devices = if let waPeer = peer as? WADeviceTransferPeer {
            .selected([waPeer.pairedDevice])
        } else {
            .allPairedDevices
        }

        // Subscribe and wait for the first list of peers
        for try await peerList in peers.subscribe() {
            // Wait for at least one peer to be paired
            guard !peerList.isEmpty else { continue }

            // Set up two tasks - one to open a connection, and one to listen for any new peers.
            let session = try await withThrowingTaskGroup(of: (any DeviceTransfer.Session)?.self) { group in
                group.addTask { [weak self] in
                    // This feels a little hacky, but it seems that newly peered devices take a
                    // little bit to show up at the NetworkListener layer.  If the listener is
                    // opened too quickly, the new peer won't be in the list of allowable connections
                    // and things will stall. Adding a small forced delay helps to let the pairing
                    // info settle before making connections based on it.
                    try await Task.sleep(nanoseconds: 1.clampedNanoseconds)

                    try Task.checkCancellation()
                    // Try to connect and build a session
                    return try await self?.listenForConnection(allowedDevices: allowedConnections)
                }
                group.addTask { @MainActor [weak self] in
                    guard let self else { return nil }
                    // If the list of peers changes, return 'nil' to signify that we need
                    // to cancel the current listener and start over with a new iteration of the
                    // outer for-await loop
                    for try await next in self.peers.subscribe() {
                        let nextSet = Set(next.map(\.id))
                        let peerListSet = Set(peerList.map(\.id))
                        if !nextSet.symmetricDifference(peerListSet).isEmpty {
                            self.logger.info("New peer discovered, restarting listener")
                            return nil
                        }
                    }
                    return nil
                }
                defer { group.cancelAll() }
                return try await group.next() ?? nil
            }

            if let session {
                return session
            }
        }

        try Task.checkCancellation() // If we reached here w/o a result, check for cancellation
        throw OWSAssertionError("Peer stream ended without producing a connection")
    }

    private func listenForConnection(
        allowedDevices: WAPublisherListener.Devices,
    ) async throws -> DeviceTransfer.Session {
        let continuation = CancellableContinuation<DeviceTransfer.Session>()
        listenerTask.set(Task { [logger, secIdentity] in
            logger.info("Open connection")
            try await NetworkListener(
                for: .wifiAware(
                    .connecting(
                        to: .deviceTransferService,
                        from: allowedDevices,
                    ),
                ),
                using: .parameters {
                    Coder(
                        receiving: WiFiAware.NetworkEvent.self,
                        sending: WiFiAware.NetworkEvent.self,
                        using: NetworkJSONCoder(),
                    ) {
                        TLS() {
                            TCP().keepalive(
                                idleTimeInSeconds: 10,
                                count: 30,
                                intervalInSeconds: 5,
                            )
                        }
                        .localIdentity(secIdentity)
                    }
                },
            ).onStateUpdate { _, state in
                switch state {
                case .setup:
                    logger.info("Connection: setup")
                case .ready:
                    logger.info("Connection: ready")
                case .failed(let error):
                    logger.info("Connection: failed: \(error)")
                case .cancelled:
                    logger.info("Connection: cancelled")
                case .waiting(let error):
                    logger.info("Connection: waiting: \(error)")
                @unknown default:
                    logger.info("Connection: unknown")
                }
            }.onServiceRegistrationUpdate { _, change in
                switch change {
                case .add:
                    logger.info("Connection: add service")
                case .remove:
                    logger.info("Connection: remove service")
                @unknown default:
                    logger.info("Connection: unknown")
                }
            }.run { connection in
                logger.info("Connection from endpoint")
                let session = WADeviceTransferSession(connection: connection)
                continuation.resume(with: .success(session))
                try await session.waitForCompletion()
            }
        })

        let session = try await withTaskCancellationHandler {
            try await continuation.wait()
        } onCancel: {
            listenerTask.swap(nil)?.cancel()
        }
        logger.debug("Returning new session")
        return session
    }

    func stop(error: Error?) {
        listenerTask.swap(nil)?.cancel()
    }
}

private class AsyncStreamBroadcast<T> {

    struct State {
        var latest: T
        var sinks: [UUID: AsyncThrowingStream<T, any Error>.Continuation] = [:]
    }

    let state: AtomicValue<State>

    init(initialValue: T) {
        self.state = AtomicValue(State(latest: initialValue), lock: .init())
    }

    func update(_ value: T) {
        let sinks = state.update {
            $0.latest = value
            return $0.sinks.values
        }
        sinks.forEach { $0.yield(value) }
    }

    func subscribe() -> AsyncThrowingStream<T, any Error> {
        let id = UUID()
        let (stream, sink) = AsyncThrowingStream<T, any Error>.makeStream(bufferingPolicy: .bufferingNewest(1))
        sink.onTermination = { [weak self] _ in self?.unsubscribe(id: id) }
        let latest = state.update {
            $0.sinks[id] = sink
            return $0.latest
        }
        sink.yield(latest)
        return stream
    }

    private func unsubscribe(id: UUID) {
        state.update {
            $0.sinks[id] = nil
        }
    }
}
