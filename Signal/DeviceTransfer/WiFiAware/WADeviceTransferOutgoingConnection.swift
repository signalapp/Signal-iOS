//
// Copyright 2026 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import CryptoKit
import Foundation
import Network
import SignalServiceKit
import WiFiAware

@available(iOS 26.0, *)
class WADeviceTransferOutgoingConnection: DeviceTransfer.OutgoingConnection {
    private let logger = PrefixedLogger(prefix: "[DeviceTransfer][WiFiAware][Outgoing]")

    private enum Constants {
        /// How long to wait for the browser to resolve an endpoint.
        static let endpointTimeout: TimeInterval = 15

        /// How long to wait for the connection to leave `preparing`.
        ///
        /// It stays there until the other device publishes its service, which can take a few seconds
        /// The OS seems to have an internal timeout of around 120s, but we should fail sooner.
        static let readyTimeout: TimeInterval = 45
    }

    let selectedPeer: (any DeviceTransfer.Peer)? = nil

    let discoveredPeerStream: AsyncThrowingStream<[any DeviceTransfer.Peer], any Error>
    private let discoveredPeerTask: Task<Void, Never>

    let identity: SecIdentity
    var expectedCertificateHash: Data

    init(
        tsAccountManager: TSAccountManager,
        deviceTransferURL: URL,
    ) throws {
        self.identity = try SelfSignedIdentity.create(name: "OutgoingDeviceTransfer", validForDays: 1)
        self.expectedCertificateHash = try Self.parseTransferURL(
            deviceTransferURL,
            tsAccountManager: tsAccountManager,
        )
        (self.discoveredPeerStream, self.discoveredPeerTask) = WiFiAware.createPeerDiscoveryObserver(logger: logger)
    }

    deinit {
        discoveredPeerTask.cancel()
    }

    func connect(peer: any DeviceTransfer.Peer) async throws -> any DeviceTransfer.Session {
        guard let peer = peer as? WADeviceTransferPeer else {
            throw OWSAssertionError("Incompatible peer type encountered")
        }

        logger.info("Start connect to \(peer)")

        let browser = NetworkBrowser(
            for: .wifiAware(.connecting(to: .selected([peer.pairedDevice]), from: .deviceTransferService)),
        ).onStateUpdate { [weak self] _, state in
            switch state {
            case .setup:
                self?.logger.info("Connection: setup")
            case .ready:
                self?.logger.info("Connection: ready")
            case .failed(let error):
                self?.logger.info("Connection: failed: \(error)")
            case .cancelled:
                // Cancelled is returned when `.finished` is returned during `run()` below
                self?.logger.info("Connection: finished")
            case .waiting(let error):
                self?.logger.info("Connection: failed: \(error)")
            @unknown default:
                self?.logger.info("Connection: unhandled state: \(state)")
            }
        }

        // `browser.run` has no deadline of its own. When it cannot resolve, it simply
        // never returns, which can wedge the whole flow silently. Instead, wait for
        // a set period of time, and try again.
        logger.info("Waiting for endpoint")
        let endpoint = try await withCooperativeTimeout(seconds: Constants.endpointTimeout) { [weak self] in
            try await browser.run { [weak self] waEndpoints in
                for endpoint in waEndpoints {
                    let discoveredPeer = WADeviceTransferPeer(pairedDevice: endpoint.device)
                    if discoveredPeer.id == peer.id {
                        self?.logger.info("Found endpoint to connect to: \(discoveredPeer)")
                        return .finish(endpoint)
                    } else {
                        self?.logger.info("Found endpoint other than the selected one: \(discoveredPeer) != \(peer)")
                    }
                }
                return .continue
            }
        }

        guard let secIdentity = sec_identity_create(identity) else {
            throw OWSAssertionError("Unexpected identity format")
        }

        logger.info("Connecting")
        let connectionReadyContinuation = CancellableContinuation<Void>()
        let connection = NetworkConnection(
            to: endpoint,
            using: .parameters {
                Coder(
                    receiving: WiFiAware.NetworkEvent.self,
                    sending: WiFiAware.NetworkEvent.self,
                    using: NetworkJSONCoder(),
                ) {
                    TLS() {
                        TCP().keepalive(idleTimeInSeconds: 10, count: 30, intervalInSeconds: 5)
                    }
                    .localIdentity(secIdentity)
                    .certificateValidator { [weak self] _, trust in
                        let secTrust = sec_trust_copy_ref(trust).takeRetainedValue()
                        guard
                            let self,
                            let chain = SecTrustCopyCertificateChain(secTrust) as? [SecCertificate],
                            let leaf = chain.first
                        else {
                            return false
                        }
                        let certificateData = SecCertificateCopyData(leaf) as Data
                        let certificateHash = Data(SHA256.hash(data: certificateData))
                        let certificateIsTrusted = self.expectedCertificateHash.ows_constantTimeIsEqual(to: certificateHash)

                        return certificateIsTrusted
                    }
                }
            }
            .wifiAware { $0.performanceMode = WiFiAware.Constants.appPerformanceMode }
            .serviceClass(WiFiAware.Constants.appServiceClass),
        ).onStateUpdate { [weak self] _, state in
            switch state {
            case .setup:
                self?.logger.info("Session: setup")
            case .preparing:
                // The connection is waiting on the far end to register the service.
                self?.logger.info("Session: preparing")
            case .ready:
                self?.logger.info("Session: ready")
                connectionReadyContinuation.resume(with: .success(()))
            case .failed(let error):
                self?.logger.error("Session: failed: \(error)")
                connectionReadyContinuation.resume(with: .failure(error))
            case .cancelled:
                self?.logger.info("Session: cancelled")
                connectionReadyContinuation.resume(with: .failure(CancellationError()))
            case .waiting(let error):
                self?.logger.info("Session: waiting: \(error)")
            @unknown default:
                // Log the value: without it an unrecognized state looks the same as a stalled one.
                self?.logger.warn("Session: unhandled state: \(state)")
            }
        }

        logger.info("Built connection to endpoint")

        // `NetworkConnection` establishes lazily. Until something reads from or
        // writes to it, it stays inert and `onStateUpdate` never fires at all.
        // `WADeviceTransferSession` immediately begins consuming
        // `connection.messages`. So the session has to exist before there is any
        // point waiting on readiness.
        let session = WADeviceTransferSession(connection: connection)
        do {
            try await withCooperativeTimeout(seconds: Constants.readyTimeout) {
                try await connectionReadyContinuation.wait()
            }
        } catch {
            logger.error("Connection never became ready: \(error)")
            await session.disconnect(error: error)
            throw error
        }
        logger.info("Connection ready")
        return session
    }

    func stop(error: Error?) {
    }

    @MainActor
    private static func parseTransferURL(
        _ url: URL,
        tsAccountManager: TSAccountManager,
    ) throws -> Data {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false), let queryItems = components.queryItems else {
            throw OWSAssertionError("Invalid url")
        }

        let queryItemsDictionary = [String: String](uniqueKeysWithValues: queryItems.compactMap { item in
            guard let value = item.value else { return nil }
            return (item.name, value)
        })

        guard
            let version = queryItemsDictionary[DeviceTransfer.UrlConstants.versionKey],
            Int(version) == DeviceTransfer.UrlConstants.currentTransferVersion
        else {
            throw DeviceTransfer.Error.unsupportedVersion
        }

        let currentMode: DeviceTransfer.Mode = tsAccountManager
            .registrationStateWithMaybeSneakyTransaction.isPrimaryDevice == true ? .primary : .linked

        guard
            let rawMode = queryItemsDictionary[DeviceTransfer.UrlConstants.transferModeKey],
            rawMode == currentMode.rawValue
        else {
            throw DeviceTransfer.Error.modeMismatch
        }

        guard
            let base64CertificateHash = queryItemsDictionary[DeviceTransfer.UrlConstants.certificateHashKey],
            let uriDecodedHash = base64CertificateHash.removingPercentEncoding,
            let certificateHash = Data(base64Encoded: uriDecodedHash)
        else {
            throw OWSAssertionError("failed to decode certificate hash")
        }

        return certificateHash
    }

}
