//
// Copyright 2026 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import CryptoKit
import Foundation
import MultipeerConnectivity
import SignalServiceKit

struct DeviceTransferPeerID: Equatable {

    fileprivate let mcPeerID: MCPeerID

    fileprivate init(mcPeerID: MCPeerID) {
        self.mcPeerID = mcPeerID
    }

    init(displayName: String) {
        self.mcPeerID = MCPeerID(displayName: displayName)
    }

    init?(with peerIdData: Data) {
        guard let peerId = try? NSKeyedUnarchiver.unarchivedObject(ofClass: MCPeerID.self, from: peerIdData) else {
            return nil
        }
        self.mcPeerID = peerId
    }

    func encoded() throws -> Data {
        return try NSKeyedArchiver.archivedData(withRootObject: mcPeerID, requiringSecureCoding: true)
    }
}

protocol DeviceTransferSession {

    var identity: SecIdentity { get }
    var delegate: DeviceTransferSessionDelegate? { get set }

    var localPeerId: DeviceTransferPeerID { get }
    var remotePeerId: DeviceTransferPeerID { get }

    func waitForConnection() async throws
    func disconnect()

    func send(message: DeviceTransfer.Message) throws

    func sendResource(
        url: URL,
        name: String,
        progressBlock: ((Progress?) -> Void),
    ) async throws
}

protocol DeviceTransferOutgoingConnection {

    func start() async throws -> DeviceTransferSession

    func stop()
}

protocol DeviceTransferIncomingConnection {

    func start(mode: DeviceTransfer.Mode) throws -> URL

    func waitForConnection() async throws -> DeviceTransferSession

    func stop()
}

enum TransferSessionState: String {
    case notConnected
    case connecting
    case connected
}

protocol DeviceTransferSessionDelegate: AnyObject {
    func session(
        _ session: DeviceTransferSession,
        didReceive data: Data,
    )

    func session(
        _ session: DeviceTransferSession,
        didStartReceivingResourceWithName resourceName: String,
        with fileProgress: Progress,
    )

    func session(
        _ session: DeviceTransferSession,
        didFinishReceivingResourceWithName resourceName: String,
        at localURL: URL?,
        withError error: Swift.Error?,
    )

    func session(
        _ session: DeviceTransferSession,
        didReceiveCertificates certificates: [Any]?,
        certificateHandler: @escaping (Bool) -> Void,
    )
}

private extension MCSessionState {
    var asTransferSessionState: TransferSessionState {
        switch self {
        case .notConnected: .notConnected
        case .connecting: .connecting
        case .connected: .connected
        @unknown default: .notConnected
        }
    }
}

enum MPCDeviceTransfer {

    class Browser:
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

        func stop() {
            browser.stopBrowsingForPeers()
            lock.withLock {
                session?.disconnect()
                session = nil
                inviteContinuation.take()?.resume(throwing: CancellationError())
            }
        }

        // MARK: - MCNearbyServiceBrowserDelegate

        func browser(
            _ browser: MCNearbyServiceBrowser,
            foundPeer newDevicePeerID: MCPeerID,
            withDiscoveryInfo info: [String: String]?,
        ) {
            guard let identity else {
                lock.withLock {
                    inviteContinuation.take()?.resume(
                        throwing: OWSAssertionError("Could not create identity for browser"),
                    )
                }
                return
            }
            let session = Session(
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

        func browser(
            _ browser: MCNearbyServiceBrowser,
            didNotStartBrowsingForPeers error: Swift.Error,
        ) {
            Logger.warn("Failed to start browsing for peers \(error)")
            lock.withLock {
                inviteContinuation.take()?.resume(throwing: error)
            }
        }

        func browser(_ browser: MCNearbyServiceBrowser, lostPeer peerId: MCPeerID) {
            lock.withLock {
                if let continuation = inviteContinuation.take() {
                    continuation.resume(throwing: CancellationError())
                } else if let session {
                    session.disconnect()
                }
            }
        }
    }

    class Advertiser:
        NSObject,
        DeviceTransferIncomingConnection,
        MCNearbyServiceAdvertiserDelegate
    {
        let peerId: DeviceTransferPeerID
        let advertiser: MCNearbyServiceAdvertiser

        // Create an identity to use for our TLS sessions, the old device
        // will verify this identity via the QR code
        // We don't actually need to generate an identity for the old device, the new device
        // doesn't verify this information. We do it anyway, for consistency.
        let identity: SecIdentity?

        private let lock = UnfairLock()
        private var session: Session?
        private var connectionContinuation: CheckedContinuation<DeviceTransferSession, Error>?
        private var waitTask: Task<DeviceTransferSession, Error>?

        init(peerId: DeviceTransferPeerID) {
            self.identity = try? SelfSignedIdentity.create(name: "IncomingDeviceTransfer", validForDays: 1)
            self.peerId = peerId
            advertiser = MCNearbyServiceAdvertiser(
                peer: peerId.mcPeerID,
                discoveryInfo: nil,
                serviceType: DeviceTransfer.Constants.newDeviceServiceIdentifier,
            )
            super.init()
            advertiser.delegate = self
        }

        func start(mode: DeviceTransfer.Mode) throws -> URL {
            guard let identity else {
                throw OWSAssertionError("Could not create identity for advertiser")
            }
            advertiser.startAdvertisingPeer()
            return try Self.urlForTransfer(identity: identity, localPeerId: peerId, mode: mode)
        }

        func waitForConnection() async throws -> DeviceTransferSession {
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

        func stop() {
            advertiser.stopAdvertisingPeer()
            lock.withLock {
                session?.disconnect()
                session = nil
                connectionContinuation.take()?.resume(throwing: CancellationError())
            }
        }

        static func urlForTransfer(
            identity: SecIdentity,
            localPeerId: DeviceTransferPeerID,
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

        func advertiser(
            _ advertiser: MCNearbyServiceAdvertiser,
            didReceiveInvitationFromPeer peerId: MCPeerID,
            withContext context: Data?,
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
                    let session = Session(identity: identity, peerID: self.peerId.mcPeerID, remoteDevicePeerID: peerId)
                    self.session = session
                    invitationHandler(true, session.session)
                    connectionContinuation.resume(returning: session)
                } else {
                    invitationHandler(false, nil)
                }
            }
        }

        func advertiser(_ advertiser: MCNearbyServiceAdvertiser, didNotStartAdvertisingPeer error: Swift.Error) {
            Logger.warn("Failed to start advertising for peers \(error)")
            lock.withLock {
                connectionContinuation.take()?.resume(throwing: error)
            }
        }
    }

    class Session: NSObject, DeviceTransferSession, MCSessionDelegate {
        let identity: SecIdentity
        var localPeerId: DeviceTransferPeerID { DeviceTransferPeerID(mcPeerID: session.myPeerID) }
        let remotePeerId: DeviceTransferPeerID

        fileprivate let session: MCSession
        weak var delegate: DeviceTransferSessionDelegate?

        private var lock = UnfairLock()
        private var connectionContinuation: CheckedContinuation<Void, Error>?
        private var connected: Bool = false
        private var waitTask: Task<Void, Error>?
        private var activeSends: [URL: CheckedContinuation<Void, any Error>] = [:]

        fileprivate init(
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

        func disconnect() {
            lock.withLock {
                self.connected = false
                self.activeSends.values.forEach { $0.resume(throwing: CancellationError()) }
                self.activeSends.removeAll()
                self.connectionContinuation.take()?.resume(throwing: CancellationError())
            }
            self.session.disconnect()
        }

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
            delegate?.session(self, didReceive: data)
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
            delegate?.session(
                self,
                didStartReceivingResourceWithName: resourceName,
                with: fileProgress,
            )
        }

        func session(
            _ session: MCSession,
            didFinishReceivingResourceWithName resourceName: String,
            fromPeer peerId: MCPeerID,
            at localURL: URL?,
            withError error: Swift.Error?,
        ) {
            delegate?.session(
                self,
                didFinishReceivingResourceWithName: resourceName,
                at: localURL,
                withError: error,
            )
        }

        func session(
            _ session: MCSession,
            didReceiveCertificate certificates: [Any]?,
            fromPeer peerId: MCPeerID,
            certificateHandler: @escaping (Bool) -> Void,
        ) {
            delegate?.session(
                self,
                didReceiveCertificates: certificates,
                certificateHandler: certificateHandler,
            )
        }
    }
}
