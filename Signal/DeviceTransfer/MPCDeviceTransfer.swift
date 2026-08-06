//
// Copyright 2026 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import CryptoKit
import Foundation
import SignalServiceKit

@MainActor
protocol DeviceTransferConnectionFactory {
    @MainActor
    func buildOutgoingConnection() -> DeviceTransferOutgoingConnection
    @MainActor
    func buildIncomingConnection() -> DeviceTransferIncomingConnection
}

extension DeviceTransfer {
    static let defaultFactory: DeviceTransferConnectionFactory = MPCDeviceTransferConnectionFactory()
}

@MainActor
protocol DeviceTransferPeerID: Equatable { }

@MainActor
protocol DeviceTransferSession {
    var identity: SecIdentity { get }
    var localPeerId: any DeviceTransferPeerID { get }
    var remotePeerId: any DeviceTransferPeerID { get }

    @MainActor
    func waitForConnection() async throws
    @MainActor
    func disconnect()

    var messages: AsyncThrowingStream<DeviceTransfer.SessionMessage, Error> { get }

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
    func parseTransferURL(
        _ url: URL,
        tsAccountManager: TSAccountManager,
    ) throws -> (
        peerId: any DeviceTransferPeerID,
        certificateHash: Data,
    )

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

extension DeviceTransfer {
    enum SessionMessage {
        case message(DeviceTransfer.Message)
        case startResource(String, Progress)
        case finishResource(String, URL)
        case certificate(Data, (Bool) -> Void)
    }
}
