//
// Copyright 2025 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import MultipeerConnectivity
import SignalServiceKit

class MPCDeviceTransferBrowser:
    NSObject,
    DeviceTransferOutgoingConnection,
    MCNearbyServiceBrowserDelegate
{
    let identity: SecIdentity?
    let browser: MCNearbyServiceBrowser
    let peerId: DeviceTransferPeerID

    private let lock = UnfairLock()
    private var session: DeviceTransferSession?
    private var inviteContinuation: CheckedContinuation<DeviceTransferSession, Error>?
    private var browseTask: Task<DeviceTransferSession, Error>?

    init(peerId: DeviceTransferPeerID) {
        self.identity = try? SelfSignedIdentity.create(name: "OutgoingDeviceTransfer", validForDays: 1)
        browser = MCNearbyServiceBrowser(
            peer: peerId.mcPeerID,
            serviceType: DeviceTransfer.Constants.newDeviceServiceIdentifier,
        )
        self.peerId = peerId
        super.init()
        browser.delegate = self
    }

    @MainActor
    func start() async throws -> DeviceTransferSession {
        if let session {
            return session
        }
        let task = lock.withLock {
            if let browseTask {
                return browseTask
            } else {
                browser.startBrowsingForPeers()
                let task = Task {
                    try await withCheckedThrowingContinuation { continuation in
                        lock.withLock {
                            self.inviteContinuation = continuation
                        }
                    }
                }
                browseTask = task
                return task
            }
        }
        return try await task.value
    }

    @MainActor
    func stop() {
        browser.stopBrowsingForPeers()
        lock.withLock {
            session?.disconnect()
            session = nil
            inviteContinuation.take()?.resume(throwing: CancellationError())
        }
    }

    @MainActor
    func invitePeer(peerID newDevicePeerID: MCPeerID) {
        guard let identity else {
            lock.withLock {
                inviteContinuation.take()?.resume(
                    throwing: OWSAssertionError("Could not create identity for browser"),
                )
            }
            return
        }
        let session = MPCDeviceTransferSession(
            identity: identity,
            peerID: peerId.mcPeerID,
            remoteDevicePeerID: newDevicePeerID,
        )
        browser.invitePeer(
            newDevicePeerID,
            to: session.session,
            withContext: nil,
            timeout: 30,
        )
        lock.withLock {
            self.session = session
            inviteContinuation.take()?.resume(returning: session)
        }
    }

    @MainActor
    private func connectionError(_ error: Error) {
        Logger.warn("Connection error: \(error)")
        lock.withLock {
            if let continuation = inviteContinuation.take() {
                continuation.resume(throwing: CancellationError())
            } else if let session {
                session.disconnect()
            }
        }
    }

    // MARK: - MCNearbyServiceBrowserDelegate

    func browser(
        _ browser: MCNearbyServiceBrowser,
        foundPeer newDevicePeerID: MCPeerID,
        withDiscoveryInfo info: [String: String]?,
    ) {
        Task { @MainActor in
            self.invitePeer(peerID: newDevicePeerID)
        }
    }

    func browser(
        _ browser: MCNearbyServiceBrowser,
        didNotStartBrowsingForPeers error: Swift.Error,
    ) {
        Task { @MainActor in
            self.connectionError(error)
        }
    }

    func browser(_ browser: MCNearbyServiceBrowser, lostPeer peerId: MCPeerID) {
        Task { @MainActor in
            self.connectionError(CancellationError())
        }
    }
}
