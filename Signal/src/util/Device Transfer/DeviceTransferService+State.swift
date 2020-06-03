//
//  Copyright (c) 2020 Open Whisper Systems. All rights reserved.
//

import Foundation
import MultipeerConnectivity

extension DeviceTransferService {
    enum Error: Swift.Error {
        case assertion
        case cancel
        case certificateMismatch
        case modeMismatch
        case notEnoughSpace
        case unsupportedVersion
    }

    enum TransferState: Equatable {
        case idle
        case incoming(
            oldDevicePeerId: MCPeerID,
            manifest: DeviceTransferProtoManifest,
            receivedFileIds: [String],
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
            case .incoming(let oldDevicePeerId, let manifest, let receivedFileIds, let progress):
                return .incoming(
                    oldDevicePeerId: oldDevicePeerId,
                    manifest: manifest,
                    receivedFileIds: receivedFileIds + [fileId],
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
    }

    enum TransferMode: String {
        case linked
        case primary
    }
}
