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
    private struct ConnectionData {
        let peerId: MPCDeviceTransferPeerId
        let certificateHash: Data
    }

    let identity: SecIdentity?
    let browser: MCNearbyServiceBrowser
    let peerId: MPCDeviceTransferPeerId

    private let lock = UnfairLock()
    private var session: DeviceTransfer.Session?
    private var inviteContinuation: CheckedContinuation<DeviceTransfer.Session, Error>?
    private var browseTask: Task<DeviceTransfer.Session, Error>?

    private var expectedConnectionData: ConnectionData?
    let tsAccountManager: TSAccountManager

    @MainActor
    init(tsAccountManager: TSAccountManager) {
        self.tsAccountManager = tsAccountManager
        self.peerId = MPCDeviceTransferPeerId(displayName: UUID().uuidString)
        self.identity = try? SelfSignedIdentity.create(name: "OutgoingDeviceTransfer", validForDays: 1)
        browser = MCNearbyServiceBrowser(
            peer: peerId.mcPeerID,
            serviceType: DeviceTransfer.Constants.newDeviceServiceIdentifier,
        )
        super.init()
        browser.delegate = self
    }

    @MainActor
    func connect(
        deviceTransferUrl: URL,
    ) async throws -> DeviceTransfer.Session {
        if let session {
            return session
        }
        self.expectedConnectionData = try parseTransferURL(
            deviceTransferUrl,
            tsAccountManager: tsAccountManager,
        )
        browser.startBrowsingForPeers()
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
    private func parseTransferURL(
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
            let peerId = MPCDeviceTransferPeerId(with: peerIdData)
        else {
            throw OWSAssertionError("failed to decode MCPeerId")
        }

        return ConnectionData(peerId: peerId, certificateHash: certificateHash)
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

        guard let expectedConnectionData else {
            inviteContinuation.take()?.resume(throwing: OWSAssertionError("Missing connection data"))
            return
        }

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
