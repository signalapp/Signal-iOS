//
// Copyright 2025 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import MultipeerConnectivity
import SignalServiceKit

extension MPCDeviceTransfer {
    class Session:
        NSObject,
        DeviceTransferSession,
        MCSessionDelegate
    {
        let identity: SecIdentity
        var localPeerId: DeviceTransferPeerID { DeviceTransferPeerID(mcPeerID: session.myPeerID) }
        let remotePeerId: DeviceTransferPeerID

        let session: MCSession
        var delegate: Weak<DeviceTransferSessionDelegate>?

        private var lock = UnfairLock()
        private var connectionContinuation: CheckedContinuation<Void, Error>?
        private var connected: Bool = false
        private var waitTask: Task<Void, Error>?
        private var activeSends: [URL: CheckedContinuation<Void, any Error>] = [:]

        init(
            identity: SecIdentity,
            peerID: MCPeerID,
            remoteDevicePeerID: MCPeerID,
        ) {
            self.identity = identity
            self.remotePeerId = DeviceTransferPeerID(mcPeerID: remoteDevicePeerID)

            let session = MCSession(peer: peerID, securityIdentity: [identity], encryptionPreference: .required)
            self.session = session
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
        }

        @MainActor
        func send(message: DeviceTransfer.Message) throws {
            let mode: MCSessionSendDataMode = switch message {
            case .backgroundApp: .unreliable
            case .done: .reliable
            }
            try session.send(
                message.data,
                toPeers: [remotePeerId.mcPeerID],
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
                    toPeer: remotePeerId.mcPeerID,
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
            Task { @MainActor in
                delegate?.value?.session(self, didReceive: data)
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
            Task { @MainActor in
                delegate?.value?.session(
                    self,
                    didStartReceivingResourceWithName: resourceName,
                    with: fileProgress,
                )
            }
        }

        func session(
            _ session: MCSession,
            didFinishReceivingResourceWithName resourceName: String,
            fromPeer peerId: MCPeerID,
            at localURL: URL?,
            withError error: Swift.Error?,
        ) {
            Task { @MainActor in
                delegate?.value?.session(
                    self,
                    didFinishReceivingResourceWithName: resourceName,
                    at: localURL,
                    withError: error,
                )
            }
        }

        func session(
            _ session: MCSession,
            didReceiveCertificate certificates: [Any]?,
            fromPeer peerId: MCPeerID,
            certificateHandler: @escaping (Bool) -> Void,
        ) {
            Task { @MainActor in
                guard let certificate = certificates?.first else {
                    return owsFailDebug("new connection did not provide any certificate")
                }
                let certificateData = SecCertificateCopyData(certificate as! SecCertificate) as Data
                delegate?.value?.session(
                    self,
                    didReceiveCertificate: certificateData,
                    certificateHandler: certificateHandler,
                )
            }
        }
    }
}
