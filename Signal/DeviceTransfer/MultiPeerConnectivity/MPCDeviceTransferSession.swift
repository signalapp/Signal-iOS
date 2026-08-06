//
// Copyright 2025 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import CryptoKit
import Foundation
import MultipeerConnectivity
import SignalServiceKit

class MPCDeviceTransferSession:
    NSObject,
    DeviceTransfer.Session,
    MCSessionDelegate
{
    let identity: SecIdentity
    var localPeerId: any DeviceTransfer.PeerID { MPCDeviceTransferPeerId(mcPeerID: session.myPeerID) }
    let _remotePeerId: MPCDeviceTransferPeerId
    var remotePeerId: any DeviceTransfer.PeerID { _remotePeerId }

    let session: MCSession

    private let messageSink: AsyncThrowingStream<DeviceTransfer.SessionMessage, Error>.Continuation
    let messages: AsyncThrowingStream<DeviceTransfer.SessionMessage, Error>

    private var lock = UnfairLock()
    private var connectionContinuation: CheckedContinuation<Void, Error>?
    private var connected: Bool = false
    private var waitTask: Task<Void, Error>?
    private var activeSends: [URL: CheckedContinuation<Void, any Error>] = [:]

    private let expectedCertificateHash: Data?
    private let tsAccountManager: TSAccountManager

    init(
        identity: SecIdentity,
        peerID: MCPeerID,
        remoteDevicePeerID: MCPeerID,
        expectedCertificateHash: Data?,
        tsAccountManager: TSAccountManager,
    ) {
        self.identity = identity
        self._remotePeerId = MPCDeviceTransferPeerId(mcPeerID: remoteDevicePeerID)
        let session = MCSession(peer: peerID, securityIdentity: [identity], encryptionPreference: .required)
        self.session = session

        (self.messages, self.messageSink) = AsyncThrowingStream.makeStream()
        self.expectedCertificateHash = expectedCertificateHash
        self.tsAccountManager = tsAccountManager

        super.init()
        session.delegate = self
    }

    @MainActor
    func waitForConnection() async throws {
        guard !connected else { return }
        let task = lock.withLock {
            if let waitTask {
                return waitTask
            } else {
                let task = Task {
                    try await withCheckedThrowingContinuation { continuation in
                        self.connectionContinuation = continuation
                    }
                    self.connected = true
                }
                waitTask = task
                return task
            }
        }
        try await task.value
    }

    @MainActor
    func disconnect() {
        lock.withLock {
            self.connected = false
            self.activeSends.values.forEach { $0.resume(throwing: CancellationError()) }
            self.activeSends.removeAll()
            self.connectionContinuation.take()?.resume(throwing: CancellationError())
        }
        self.session.disconnect()
        messageSink.finish()
        connected = false
    }

    @MainActor
    func send(message: DeviceTransfer.Message) throws {
        let mode: MCSessionSendDataMode = switch message {
        case .backgroundApp: .unreliable
        case .done: .reliable
        }
        try session.send(
            message.data,
            toPeers: [_remotePeerId.mcPeerID],
            with: mode,
        )
    }

    @MainActor
    func sendResource(
        url: URL,
        name: String,
        progressBlock: ((Progress?) -> Void),
    ) async throws {
        guard connected else {
            throw OWSAssertionError("Not connected")
        }
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, any Error>) in
            lock.withLock {
                activeSends[url] = continuation
            }
            let progress = session.sendResource(
                at: url,
                withName: name,
                toPeer: _remotePeerId.mcPeerID,
            ) { error in
                guard let savedContinuation = self.lock.withLock({ self.activeSends.removeValue(forKey: url) }) else {
                    return
                }
                if let error {
                    savedContinuation.resume(throwing: error)
                } else {
                    savedContinuation.resume()
                }
            }
            progressBlock(progress)
        }
    }

    // MARK: - MCSessionDelegate

    func session(
        _ session: MCSession,
        peer peerId: MCPeerID,
        didChange state: MCSessionState,
    ) {
        lock.withLock {
            Logger.info("Connection to new device did change: \(state.rawValue)")
            switch state {
            case .connected:
                connected = true
                connectionContinuation.take()?.resume()
            case .connecting:
                break
            case .notConnected:
                connected = false
                connectionContinuation.take()?.resume(throwing: OWSAssertionError("Lost connection to new device"))
            @unknown default:
                connected = false
                connectionContinuation.take()?.resume(throwing: OWSAssertionError("Unexpected connection state: \(state.rawValue)"))
            }
        }
    }

    func session(
        _ session: MCSession,
        didReceive data: Data,
        fromPeer peerId: MCPeerID,
    ) {
        switch data {
        case DeviceTransfer.Message.backgroundApp.data:
            messageSink.yield(.message(.backgroundApp))
            messageSink.finish()
        case DeviceTransfer.Message.done.data:
            messageSink.yield(.message(.done))
            messageSink.finish()
        default:
            messageSink.finish(throwing: OWSAssertionError("Received unexpected message"))
        }
    }

    func session(
        _ session: MCSession,
        didReceive stream: InputStream,
        withName streamName: String,
        fromPeer peerId: MCPeerID,
    ) { }

    func session(
        _ session: MCSession,
        didStartReceivingResourceWithName resourceName: String,
        fromPeer peerId: MCPeerID,
        with fileProgress: Progress,
    ) {
        messageSink.yield(.startResource(resourceName, fileProgress))
    }

    func session(
        _ session: MCSession,
        didFinishReceivingResourceWithName resourceName: String,
        fromPeer peerId: MCPeerID,
        at localURL: URL?,
        withError error: Swift.Error?,
    ) {
        if let error {
            messageSink.finish(throwing: error)
            return
        }
        guard let localURL else {
            messageSink.finish(throwing: OWSAssertionError("No error, but missing url"))
            return
        }
        messageSink.yield(.finishResource(resourceName, localURL))
    }

    func session(
        _ session: MCSession,
        didReceiveCertificate certificates: [Any]?,
        fromPeer peerId: MCPeerID,
        certificateHandler: @escaping (Bool) -> Void,
    ) {
        guard let certificate = certificates?.first else {
            messageSink.finish(throwing: OWSAssertionError("new connection did not provide any certificate"))
            return
        }
        let certificateData = SecCertificateCopyData(certificate as! SecCertificate) as Data

        var certificateIsTrusted = false
        defer {
            certificateHandler(certificateIsTrusted)
            if !certificateIsTrusted {
                messageSink.finish(throwing: OWSAssertionError("Connection from known peer \(peerId) using untrusted certificate"))
            }
        }

        if let expectedCertificateHash {
            // Verify the received certificate matches the expected certificate.
            // Reject any connections where we can't compute the certificate hash
            let certificateHash = Data(SHA256.hash(data: certificateData))

            // Reject any connections where the certificate doesn't match the expected certificate
            certificateIsTrusted = expectedCertificateHash.ows_constantTimeIsEqual(to: certificateHash)

            Logger.info("Successfully verified new device certificate \(peerId)")
        } else {
            // Registered devices can only ever perform outgoing transfers.
            // Accept all connections if we're doing an incoming transfer AND we aren't yet registered.
            certificateIsTrusted = !tsAccountManager.registrationStateWithMaybeSneakyTransaction.isRegistered
        }
    }
}
