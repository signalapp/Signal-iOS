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
    var peerId: DeviceTransferPeerID { get }

    func disconnect()

    func send(
        _ data: Data,
        toPeers peerIDs: [DeviceTransferPeerID],
        with mode: TransferSessionSendDataMode,
    ) throws

    func sendResource(
        url: URL,
        name: String,
        to peer: DeviceTransferPeerID,
        progressBlock: ((Progress?) -> Void),
    ) async throws
}

protocol DeviceTransferServiceBrowser {
    func invitePeer(
        _ peer: DeviceTransferPeerID,
    ) throws -> DeviceTransferSession

    func startBrowsing()

    func stopBrowsing()
}

protocol DeviceTransferServiceAdvertiser {
    func startAdvertising() throws -> DeviceTransferSession

    func stopAdvertising()
}

enum TransferSessionState: String {
    case notConnected
    case connecting
    case connected
}

enum TransferSessionSendDataMode {
    case reliable
    case unreliable
}

protocol DeviceTransferSessionDelegate: AnyObject {
    func session(
        _ session: DeviceTransferSession,
        peer peerId: DeviceTransferPeerID,
        didChange state: TransferSessionState,
    )

    func session(
        _ session: DeviceTransferSession,
        didReceive data: Data,
        fromPeer peerId: DeviceTransferPeerID,
    )

    func session(
        _ session: DeviceTransferSession,
        didStartReceivingResourceWithName resourceName: String,
        fromPeer peerId: DeviceTransferPeerID,
        with fileProgress: Progress,
    )

    func session(
        _ session: DeviceTransferSession,
        didFinishReceivingResourceWithName resourceName: String,
        fromPeer peerId: DeviceTransferPeerID,
        at localURL: URL?,
        withError error: Swift.Error?,
    )

    func session(
        _ session: DeviceTransferSession,
        didReceiveCertificates certificates: [Any]?,
        fromPeer peerId: DeviceTransferPeerID,
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

private extension TransferSessionSendDataMode {
    var asMCSessionSendDataMode: MCSessionSendDataMode {
        switch self {
        case .reliable: .reliable
        case .unreliable: .unreliable
        }
    }
}

protocol DeviceTransferServiceBrowserDelegate: AnyObject {
    func deviceTransferServiceDiscoveredNewDevice(peerId: DeviceTransferPeerID)
}

enum MPCDeviceTransfer {

    class Browser: NSObject, DeviceTransferServiceBrowser, MCNearbyServiceBrowserDelegate {

        let identity: SecIdentity?
        let browser: MCNearbyServiceBrowser
        weak var delegate: DeviceTransferServiceBrowserDelegate?
        let peerId: DeviceTransferPeerID
        var session: DeviceTransferSession?

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

        func invitePeer(_ peer: DeviceTransferPeerID) throws -> DeviceTransferSession {
            guard let identity else {
                throw OWSAssertionError("Could not create identity for browser")
            }
            let session = Session(identity: identity, peerID: self.peerId.mcPeerID)
            browser.invitePeer(
                peer.mcPeerID,
                to: session.session,
                withContext: nil,
                timeout: 30,
            )
            self.session = session
            return session
        }

        func startBrowsing() {
            browser.startBrowsingForPeers()
        }

        func stopBrowsing() {
            session?.disconnect()
            browser.stopBrowsingForPeers()
        }

        func browser(
            _ browser: MCNearbyServiceBrowser,
            foundPeer newDevicePeerID: MCPeerID,
            withDiscoveryInfo info: [String: String]?,
        ) {
            Logger.info("Notifying of discovered new device \(newDevicePeerID)")
            let peerIDWrapper = DeviceTransferPeerID(mcPeerID: newDevicePeerID)
            delegate?.deviceTransferServiceDiscoveredNewDevice(peerId: peerIDWrapper)
        }

        func browser(
            _ browser: MCNearbyServiceBrowser,
            didNotStartBrowsingForPeers error: Swift.Error,
        ) {
            Logger.warn("Failed to start browsing for peers \(error)")
        }

        func browser(_ browser: MCNearbyServiceBrowser, lostPeer peerId: MCPeerID) {
            Logger.warn("Lost peer \(peerId)")
        }
    }

    class Advertiser: NSObject, DeviceTransferServiceAdvertiser, MCNearbyServiceAdvertiserDelegate {
        let peerId: DeviceTransferPeerID
        var session: Session!
        let advertiser: MCNearbyServiceAdvertiser

        // Create an identity to use for our TLS sessions, the old device
        // will verify this identity via the QR code
        // We don't actually need to generate an identity for the old device, the new device
        // doesn't verify this information. We do it anyway, for consistency.
        let identity: SecIdentity?

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

        func startAdvertising() throws -> DeviceTransferSession {
            guard let identity else {
                throw OWSAssertionError("Could not create identity for advertiser")
            }
            self.session = Session(identity: identity, peerID: peerId.mcPeerID)
            advertiser.startAdvertisingPeer()
            return session
        }

        func stopAdvertising() {
            session?.disconnect()
            advertiser.stopAdvertisingPeer()
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
            Logger.info("Accepting invitation from old device \(peerId)")
            invitationHandler(true, session.session)
        }

        func advertiser(_ advertiser: MCNearbyServiceAdvertiser, didNotStartAdvertisingPeer error: Swift.Error) {
            Logger.warn("Failed to start advertising for peers \(error)")
        }
    }

    class Session: NSObject, DeviceTransferSession, MCSessionDelegate {

        // Create an identity to use for our TLS sessions, the old device
        // will verify this identity via the QR code
        // We don't actually need to generate an identity for the old device, the new device
        // doesn't verify this information. We do it anyway, for consistency.
        let identity: SecIdentity
        var peerId: DeviceTransferPeerID { DeviceTransferPeerID(mcPeerID: session.myPeerID) }

        fileprivate let session: MCSession
        weak var delegate: DeviceTransferSessionDelegate?

        fileprivate init(
            identity: SecIdentity,
            peerID: MCPeerID,
        ) {
            self.identity = identity
            let session = MCSession(peer: peerID, securityIdentity: [identity], encryptionPreference: .required)
            self.session = session
            super.init()
            session.delegate = self
        }

        func disconnect() {
            self.session.disconnect()
        }

        func send(
            _ data: Data,
            toPeers peerIDs: [DeviceTransferPeerID],
            with mode: TransferSessionSendDataMode,
        ) throws {
            try session.send(
                data,
                toPeers: peerIDs.map(\.mcPeerID),
                with: mode.asMCSessionSendDataMode,
            )
        }

        func sendResource(
            url: URL,
            name: String,
            to peer: DeviceTransferPeerID,
            progressBlock: ((Progress?) -> Void),
        ) async throws {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, any Error>) in
                let progress = session.sendResource(at: url, withName: name, toPeer: peer.mcPeerID) { error in
                    if let error {
                        continuation.resume(throwing: error)
                    } else {
                        continuation.resume()
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
            delegate?.session(
                self,
                peer: DeviceTransferPeerID(mcPeerID: peerId),
                didChange: state.asTransferSessionState,
            )
        }

        func session(
            _ session: MCSession,
            didReceive data: Data,
            fromPeer peerId: MCPeerID,
        ) {
            delegate?.session(
                self,
                didReceive: data,
                fromPeer: DeviceTransferPeerID(mcPeerID: peerId),
            )
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
                fromPeer: DeviceTransferPeerID(mcPeerID: peerId),
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
                fromPeer: DeviceTransferPeerID(mcPeerID: peerId),
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
                fromPeer: DeviceTransferPeerID(mcPeerID: peerId),
                certificateHandler: certificateHandler,
            )
        }
    }
}
