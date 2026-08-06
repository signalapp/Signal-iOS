//
// Copyright 2026 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import CryptoKit
import Foundation
import MultipeerConnectivity
import SignalServiceKit

protocol DeviceTransferSession {
    var identity: SecIdentity { get }
    var delegate: Weak<DeviceTransferSessionDelegate>? { get set }

    var localPeerId: DeviceTransferPeerID { get }
    var remotePeerId: DeviceTransferPeerID { get }

    @MainActor
    func waitForConnection() async throws
    @MainActor
    func disconnect()

    @MainActor
    func send(message: DeviceTransfer.Message) throws

    @MainActor
    func sendResource(
        url: URL,
        name: String,
        progressBlock: ((Progress?) -> Void),
    ) async throws
}

protocol DeviceTransferOutgoingConnection {
    @MainActor
    func start() async throws -> DeviceTransferSession
    @MainActor
    func stop()
}

protocol DeviceTransferIncomingConnection {
    @MainActor
    func start(mode: DeviceTransfer.Mode) throws -> URL
    @MainActor
    func waitForConnection() async throws -> DeviceTransferSession
    @MainActor
    func stop()
}

enum TransferSessionState: String {
    case notConnected
    case connecting
    case connected
}

@MainActor
protocol DeviceTransferSessionDelegate {
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
        didReceiveCertificate certificate: Data,
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

public enum MPCDeviceTransfer {
}
