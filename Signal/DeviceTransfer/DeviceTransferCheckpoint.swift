//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import SignalServiceKit

/// Manages checkpoint state for device transfer resumption.
/// When a transfer is interrupted, the checkpoint allows resumption
/// without re-transferring already completed files.
class DeviceTransferCheckpoint {

    // MARK: - Checkpoint Data

    struct CheckpointData: Codable {
        /// Unique identifier for this transfer session
        let transferId: String

        /// Whether this is an incoming or outgoing transfer
        let isIncoming: Bool

        /// File identifiers that have been successfully transferred
        var transferredFileIds: Set<String>

        /// File identifiers that were skipped (e.g., missing files)
        var skippedFileIds: Set<String>

        /// Timestamp when the checkpoint was created
        let createdAt: Date

        /// Timestamp when the checkpoint was last updated
        var updatedAt: Date

        /// Estimated total size of the transfer in bytes
        let estimatedTotalSize: UInt64

        /// Hash of the manifest to verify we're resuming the same transfer
        let manifestHash: Data

        init(
            transferId: String = UUID().uuidString,
            isIncoming: Bool,
            transferredFileIds: Set<String> = [],
            skippedFileIds: Set<String> = [],
            estimatedTotalSize: UInt64,
            manifestHash: Data
        ) {
            self.transferId = transferId
            self.isIncoming = isIncoming
            self.transferredFileIds = transferredFileIds
            self.skippedFileIds = skippedFileIds
            self.createdAt = Date()
            self.updatedAt = Date()
            self.estimatedTotalSize = estimatedTotalSize
            self.manifestHash = manifestHash
        }
    }

    // MARK: - Storage

    private static var checkpointFileURL: URL {
        URL(
            fileURLWithPath: "transfer_checkpoint.json",
            relativeTo: DeviceTransferService.pendingTransferDirectory
        )
    }

    private static let checkpointQueue = DispatchQueue(label: "org.signal.device-transfer.checkpoint")

    // MARK: - Public Methods

    /// Saves a checkpoint to disk
    static func save(_ checkpoint: CheckpointData) {
        checkpointQueue.async {
            do {
                var mutableCheckpoint = checkpoint
                mutableCheckpoint.updatedAt = Date()

                OWSFileSystem.ensureDirectoryExists(DeviceTransferService.pendingTransferDirectory.path)

                let encoder = JSONEncoder()
                encoder.dateEncodingStrategy = .iso8601
                let data = try encoder.encode(mutableCheckpoint)
                try data.write(to: checkpointFileURL, options: .atomic)

                Logger.info("Saved transfer checkpoint with \(checkpoint.transferredFileIds.count) transferred files")
            } catch {
                Logger.error("Failed to save transfer checkpoint: \(error)")
            }
        }
    }

    /// Loads the most recent checkpoint from disk, if one exists
    static func load() -> CheckpointData? {
        return checkpointQueue.sync {
            guard OWSFileSystem.fileOrFolderExists(url: checkpointFileURL) else {
                return nil
            }

            do {
                let data = try Data(contentsOf: checkpointFileURL)
                let decoder = JSONDecoder()
                decoder.dateDecodingStrategy = .iso8601
                let checkpoint = try decoder.decode(CheckpointData.self, from: data)

                Logger.info("Loaded transfer checkpoint: \(checkpoint.transferredFileIds.count) transferred, \(checkpoint.skippedFileIds.count) skipped")
                return checkpoint
            } catch {
                Logger.error("Failed to load transfer checkpoint: \(error)")
                return nil
            }
        }
    }

    /// Clears any existing checkpoint
    static func clear() {
        checkpointQueue.async {
            do {
                if OWSFileSystem.fileOrFolderExists(url: checkpointFileURL) {
                    try OWSFileSystem.deleteFile(url: checkpointFileURL)
                    Logger.info("Cleared transfer checkpoint")
                }
            } catch {
                Logger.error("Failed to clear transfer checkpoint: \(error)")
            }
        }
    }

    /// Checks if a valid checkpoint exists that matches the given manifest
    static func hasValidCheckpoint(for manifestHash: Data, isIncoming: Bool) -> Bool {
        guard let checkpoint = load() else {
            return false
        }

        // Verify the checkpoint matches the current transfer
        guard checkpoint.manifestHash == manifestHash,
              checkpoint.isIncoming == isIncoming else {
            Logger.info("Existing checkpoint doesn't match current transfer, will start fresh")
            clear()
            return false
        }

        // Check if the checkpoint is too old (more than 24 hours)
        let maxAge: TimeInterval = 24 * 60 * 60
        guard Date().timeIntervalSince(checkpoint.createdAt) < maxAge else {
            Logger.info("Existing checkpoint is too old, will start fresh")
            clear()
            return false
        }

        return true
    }

    /// Creates a new checkpoint for an outgoing transfer
    static func createForOutgoingTransfer(
        manifest: DeviceTransferProtoManifest,
        manifestHash: Data
    ) -> CheckpointData {
        return CheckpointData(
            isIncoming: false,
            estimatedTotalSize: manifest.estimatedTotalSize,
            manifestHash: manifestHash
        )
    }

    /// Creates a new checkpoint for an incoming transfer
    static func createForIncomingTransfer(
        manifest: DeviceTransferProtoManifest,
        manifestHash: Data
    ) -> CheckpointData {
        return CheckpointData(
            isIncoming: true,
            estimatedTotalSize: manifest.estimatedTotalSize,
            manifestHash: manifestHash
        )
    }

    /// Updates a checkpoint with a newly transferred file
    static func markFileTransferred(_ fileId: String, in checkpoint: inout CheckpointData) {
        checkpoint.transferredFileIds.insert(fileId)
        checkpoint.updatedAt = Date()
        save(checkpoint)
    }

    /// Updates a checkpoint with a skipped file
    static func markFileSkipped(_ fileId: String, in checkpoint: inout CheckpointData) {
        checkpoint.skippedFileIds.insert(fileId)
        checkpoint.updatedAt = Date()
        save(checkpoint)
    }
}
