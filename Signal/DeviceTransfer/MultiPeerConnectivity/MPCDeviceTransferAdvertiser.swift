//
// Copyright 2025 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import MultipeerConnectivity
import SignalServiceKit

class MPCDeviceTransferAdvertiser:
    NSObject,
    DeviceTransfer.IncomingConnection,
    MCNearbyServiceAdvertiserDelegate
{
    let peerId: MPCDeviceTransferPeerId
    let advertiser: MCNearbyServiceAdvertiser
    let tsAccountManager: TSAccountManager

    // Create an identity to use for our TLS sessions, the old device
    // will verify this identity via the QR code
    // We don't actually need to generate an identity for the old device, the new device
    // doesn't verify this information. We do it anyway, for consistency.
    let identity: SecIdentity?

    private let lock = UnfairLock()
    private var session: MPCDeviceTransferSession?
    private var connectionContinuation: CheckedContinuation<DeviceTransfer.Session, Error>?
    private var waitTask: Task<DeviceTransfer.Session, Error>?

    @MainActor
    init(tsAccountManager: TSAccountManager) {
        self.tsAccountManager = tsAccountManager
        self.peerId = MPCDeviceTransferPeerId(displayName: UUID().uuidString)
        self.identity = try? SelfSignedIdentity.create(name: "IncomingDeviceTransfer", validForDays: 1)
        advertiser = MCNearbyServiceAdvertiser(
            peer: peerId.mcPeerID,
            discoveryInfo: nil,
            serviceType: DeviceTransfer.Constants.newDeviceServiceIdentifier,
        )
        super.init()
        advertiser.delegate = self
    }

    @MainActor
    func start(mode: DeviceTransfer.Mode) throws -> URL {
        guard let identity else {
            throw OWSAssertionError("Could not create identity for advertiser")
        }
        advertiser.startAdvertisingPeer()
        return try Self.urlForTransfer(identity: identity, localPeerId: peerId, mode: mode)
    }

    @MainActor
    func waitForConnection() async throws -> DeviceTransfer.Session {
        if let session {
            return session
        }
        let task = lock.withLock {
            if let waitTask {
                return waitTask
            } else {
                let task = Task {
                    try await withCheckedThrowingContinuation { continuation in
                        self.connectionContinuation = continuation
                    }
                }
                waitTask = task
                return task
            }
        }
        return try await task.value
    }

    @MainActor
    func stop() {
        advertiser.stopAdvertisingPeer()
        lock.withLock {
            session?.disconnect()
            session = nil
            connectionContinuation.take()?.resume(throwing: CancellationError())
        }
    }

    @MainActor
    static func urlForTransfer(
        identity: SecIdentity,
        localPeerId: MPCDeviceTransferPeerId,
        mode: DeviceTransfer.Mode,
    ) throws -> URL {
        var components = URLComponents()
        components.scheme = UrlOpener.Constants.sgnlPrefix
        components.host = DeviceTransfer.UrlConstants.transferHost

        guard let base64CertificateHash = try identity.computeCertificateHash().base64EncodedString().encodeURIComponent else {
            throw OWSAssertionError("failed to get base64 certificate hash")
        }

        guard let base64PeerId = try? localPeerId.encoded().base64EncodedString().encodeURIComponent else {
            throw OWSAssertionError("failed to get base64 peerId")
        }

        let queryItems = [
            DeviceTransfer.UrlConstants.versionKey: String(DeviceTransfer.UrlConstants.currentTransferVersion),
            DeviceTransfer.UrlConstants.transferModeKey: mode.rawValue,
            DeviceTransfer.UrlConstants.certificateHashKey: base64CertificateHash,
            DeviceTransfer.UrlConstants.peerIdKey: base64PeerId,
        ]

        components.queryItems = queryItems.map { URLQueryItem(name: $0.key, value: $0.value) }
        return components.url!
    }

    @MainActor
    private func didReceiveInvite(
        peerId: MCPeerID,
        invitationHandler: @escaping (Bool, MCSession?) -> Void,
    ) {
        guard let identity else {
            invitationHandler(false, nil)
            connectionContinuation.take()?.resume(
                throwing: OWSAssertionError("Could not create identity for advertiser"),
            )
            return
        }
        Logger.info("Accepting invitation from old device \(peerId)")
        lock.withLock {
            if let connectionContinuation = connectionContinuation.take() {
                let session = MPCDeviceTransferSession(
                    identity: identity,
                    peerID: self.peerId.mcPeerID,
                    remoteDevicePeerID: peerId,
                    expectedCertificateHash: nil,
                    tsAccountManager: tsAccountManager,
                )
                self.session = session
                invitationHandler(true, session.session)
                connectionContinuation.resume(returning: session)
            } else {
                invitationHandler(false, nil)
            }
        }
    }

    @MainActor
    private func connectionError(error: Error) {
        Logger.warn("Connection error: \(error)")
        lock.withLock {
            connectionContinuation.take()?.resume(throwing: error)
        }
    }

    func advertiser(
        _ advertiser: MCNearbyServiceAdvertiser,
        didReceiveInvitationFromPeer peerId: MCPeerID,
        withContext context: Data?,
        invitationHandler: @escaping (Bool, MCSession?) -> Void,
    ) {
        Task { @MainActor in
            self.didReceiveInvite(
                peerId: peerId,
                invitationHandler: invitationHandler,
            )
        }
    }

    func advertiser(_ advertiser: MCNearbyServiceAdvertiser, didNotStartAdvertisingPeer error: Swift.Error) {
        Task { @MainActor in
            self.connectionError(error: error)
        }
    }
}
