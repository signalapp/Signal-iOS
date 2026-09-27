//
// Copyright 2025 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import MultipeerConnectivity
import SignalServiceKit

class MPCDeviceTransferBrowser:
    NSObject,
    DeviceTransfer.OutgoingConnection,
    MCNearbyServiceBrowserDelegate
{
    var selectedPeer: (any DeviceTransfer.Peer)? {
        expectedConnectionData.peerId
    }

    private struct ConnectionData {
        let peerId: MPCDeviceTransferPeer
        let certificateHash: Data
    }

    let identity: SecIdentity
    let browser: MCNearbyServiceBrowser
    let peerId: MPCDeviceTransferPeer

    private let lock = UnfairLock()
    private var session: DeviceTransfer.Session?
    private var inviteContinuation: CheckedContinuation<DeviceTransfer.Session, Error>?
    private var browseTask: Task<DeviceTransfer.Session, Error>?

    private let tsAccountManager: TSAccountManager
    private let expectedConnectionData: ConnectionData

    // This is here to satisfy the PeerDiscovery, but we don't currently notify when
    // peers are discovered, since the peer selection is handled differently in MPC
    let discoveredPeerStream: AsyncThrowingStream<[any DeviceTransfer.Peer], Error>

    @MainActor
    init(
        tsAccountManager: TSAccountManager,
        deviceTransferURL: URL,
    ) throws {
        self.tsAccountManager = tsAccountManager
        self.expectedConnectionData = try Self.parseTransferURL(
            deviceTransferURL,
            tsAccountManager: tsAccountManager,
        )

        self.peerId = MPCDeviceTransferPeer(displayName: UUID().uuidString)
        self.identity = try SelfSignedIdentity.create(name: "OutgoingDeviceTransfer", validForDays: 1)
        browser = MCNearbyServiceBrowser(
            peer: peerId.mcPeerID,
            serviceType: DeviceTransfer.Constants.newDeviceServiceIdentifier,
        )
        (self.discoveredPeerStream, _) = AsyncThrowingStream.makeStream()
        super.init()
        browser.delegate = self
    }

    @MainActor
    func connect(
        peer: any DeviceTransfer.Peer,
    ) async throws -> DeviceTransfer.Session {
        guard
            let targetPeer = peer as? MPCDeviceTransferPeer,
            targetPeer == expectedConnectionData.peerId
        else {
            throw OWSAssertionError("Misconfigured")
        }

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
    func stop(error: Error?) async {
        browser.stopBrowsingForPeers()
        let session = session
        await session?.disconnect(error: error)
        lock.withLock {
            self.session = nil
            inviteContinuation.take()?.resume(throwing: error ?? CancellationError())
        }
    }

    @MainActor
    private static func parseTransferURL(
        _ url: URL,
        tsAccountManager: TSAccountManager,
    ) throws -> ConnectionData {
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

        guard
            let base64PeerId = queryItemsDictionary[DeviceTransfer.UrlConstants.peerIdKey],
            let uriDecodedPeerId = base64PeerId.removingPercentEncoding,
            let peerIdData = Data(base64Encoded: uriDecodedPeerId),
            let peerId = MPCDeviceTransferPeer(with: peerIdData)
        else {
            throw OWSAssertionError("failed to decode MCPeerId")
        }

        return ConnectionData(peerId: peerId, certificateHash: certificateHash)
    }

    @MainActor
    func invitePeer(peerID newDevicePeerID: MCPeerID) {
        let session = MPCDeviceTransferSession(
            identity: identity,
            peerID: peerId.mcPeerID,
            remoteDevicePeerID: newDevicePeerID,
            expectedCertificateHash: expectedConnectionData.certificateHash,
            tsAccountManager: tsAccountManager,
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
    private func connectionError(_ error: Error) async {
        Logger.warn("Connection error: \(error)")
        let session = session
        await session?.disconnect(error: error)
        lock.withLock {
            if let continuation = inviteContinuation.take() {
                continuation.resume(throwing: error)
            }
            self.session = nil
        }
    }

    // MARK: - MCNearbyServiceBrowserDelegate

    func browser(
        _ browser: MCNearbyServiceBrowser,
        foundPeer newDevicePeerID: MCPeerID,
        withDiscoveryInfo info: [String: String]?,
    ) {
        guard newDevicePeerID == expectedConnectionData.peerId.mcPeerID else {
            return
        }

        Task { @MainActor in
            self.invitePeer(peerID: newDevicePeerID)
        }
    }

    func browser(
        _ browser: MCNearbyServiceBrowser,
        didNotStartBrowsingForPeers error: Error,
    ) {
        Task { @MainActor in
            await self.connectionError(error)
        }
    }

    func browser(_ browser: MCNearbyServiceBrowser, lostPeer peerId: MCPeerID) {
        Task { @MainActor in
            await self.connectionError(CancellationError())
        }
    }
}
