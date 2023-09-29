//
// Copyright 2020 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import MultipeerConnectivity
import SignalServiceKit

extension DeviceTransferService {
    enum Error: Swift.Error {
        case assertion
        case cancel
        case backgroundedDevice
        case certificateMismatch
        case modeMismatch
        case notEnoughSpace
        case unsupportedVersion
    }

    enum TransferState {
        case idle
        case incoming(
            oldDevicePeerId: MCPeerID,
            manifest: DeviceTransferProtoManifest,
            receivedFileIds: [String],
            skippedFileIds: [String],
            progress: Progress
        )
        case outgoing(
            newDevicePeerId: MCPeerID,
            newDeviceCertificateHash: Data,
            manifest: DeviceTransferProtoManifest,
            transferredFileIds: [String],
            progress: Progress
        )

        func appendingFileId(_ fileId: String) -> TransferState {
            switch self {
            case .incoming(let oldDevicePeerId, let manifest, let receivedFileIds, let skippedFileIds, let progress):
                return .incoming(
                    oldDevicePeerId: oldDevicePeerId,
                    manifest: manifest,
                    receivedFileIds: receivedFileIds + [fileId],
                    skippedFileIds: skippedFileIds,
                    progress: progress
                )
            case .outgoing(let newDevicePeerId, let newDeviceCertificateHash, let manifest, let transferredFileIds, let progress):
                return .outgoing(
                    newDevicePeerId: newDevicePeerId,
                    newDeviceCertificateHash: newDeviceCertificateHash,
                    manifest: manifest,
                    transferredFileIds: transferredFileIds + [fileId],
                    progress: progress
                )
            case .idle:
                owsFailDebug("unexpectedly tried to append file while idle")
                return .idle
            }
        }

        func appendingSkippedFileId(_ fileId: String) -> TransferState {
            switch self {
            case .incoming(let oldDevicePeerId, let manifest, let receivedFileIds, let skippedFileIds, let progress):
                return .incoming(
                    oldDevicePeerId: oldDevicePeerId,
                    manifest: manifest,
                    receivedFileIds: receivedFileIds,
                    skippedFileIds: skippedFileIds + [fileId],
                    progress: progress
                )
            case .outgoing(let newDevicePeerId, let newDeviceCertificateHash, let manifest, let transferredFileIds, let progress):
                owsFailDebug("unexpectedly tried to append a skipped file on outgoing")
                return .outgoing(
                    newDevicePeerId: newDevicePeerId,
                    newDeviceCertificateHash: newDeviceCertificateHash,
                    manifest: manifest,
                    transferredFileIds: transferredFileIds,
                    progress: progress
                )
            case .idle:
                owsFailDebug("unexpectedly tried to append a skipped file while idle")
                return .idle
            }
        }
    }

    enum TransferMode: String {
        case linked
        case primary
    }
}
