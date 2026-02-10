//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import SignalServiceKit

// MARK: - CheckpointStorage Protocol

/// Protocol for checkpoint storage operations, allowing dependency injection for testing.
protocol CheckpointStorage {
    func save(_ data: Data) throws
    func load() throws -> Data?
    func delete() throws
    func exists() -> Bool
}

/// File-based checkpoint storage for production use.
class FileCheckpointStorage: CheckpointStorage {
    private let fileURL: URL
    private let directoryURL: URL

    init(fileURL: URL, directoryURL: URL) {
        self.fileURL = fileURL
        self.directoryURL = directoryURL
    }

    func save(_ data: Data) throws {
        OWSFileSystem.ensureDirectoryExists(directoryURL.path)
        try data.write(to: fileURL, options: .atomic)
    }

    func load() throws -> Data? {
        guard exists() else { return nil }
        return try Data(contentsOf: fileURL)
    }

    func delete() throws {
        if exists() {
            try OWSFileSystem.deleteFile(url: fileURL)
        }
    }

    func exists() -> Bool {
        return OWSFileSystem.fileOrFolderExists(url: fileURL)
    }
}

#if TESTABLE_BUILD
/// In-memory checkpoint storage for testing.
class InMemoryCheckpointStorage: CheckpointStorage {
    var storedData: Data?

    func save(_ data: Data) throws {
        storedData = data
    }

    func load() throws -> Data? {
        return storedData
    }

    func delete() throws {
        storedData = nil
    }

    func exists() -> Bool {
        return storedData != nil
    }
}
#endif

// MARK: - CheckpointDateProvider Protocol

/// Protocol for providing the current date, allowing injection for testing.
protocol CheckpointDateProvider {
    func now() -> Date
}

/// Default date provider that returns the actual current date.
struct SystemCheckpointDateProvider: CheckpointDateProvider {
    func now() -> Date {
        return Date()
    }
}

#if TESTABLE_BUILD
/// Controllable date provider for testing.
class MockCheckpointDateProvider: CheckpointDateProvider {
    var currentDate: Date = Date()

    func now() -> Date {
        return currentDate
    }
}
#endif

// MARK: - DeviceTransferCheckpoint

/// Manages checkpoint state for device transfer resumption.
/// When a transfer is interrupted, the checkpoint allows resumption
/// without re-transferring already completed files.
class DeviceTransferCheckpoint {

    // MARK: - Checkpoint Data

    struct CheckpointData: Codable, Equatable {
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
            createdAt: Date = Date(),
            estimatedTotalSize: UInt64,
            manifestHash: Data
        ) {
            self.transferId = transferId
            self.isIncoming = isIncoming
            self.transferredFileIds = transferredFileIds
            self.skippedFileIds = skippedFileIds
            self.createdAt = createdAt
            self.updatedAt = createdAt
            self.estimatedTotalSize = estimatedTotalSize
            self.manifestHash = manifestHash
        }
    }

    // MARK: - Configuration

    /// Maximum age for a checkpoint before it's considered expired (24 hours).
    static let maxCheckpointAge: TimeInterval = 24 * 60 * 60

    // MARK: - Instance Properties

    private let storage: CheckpointStorage
    private let dateProvider: CheckpointDateProvider
    private let queue: DispatchQueue

    // MARK: - Initialization

    init(
        storage: CheckpointStorage,
        dateProvider: CheckpointDateProvider = SystemCheckpointDateProvider(),
        queue: DispatchQueue = DispatchQueue(label: "org.signal.device-transfer.checkpoint")
    ) {
        self.storage = storage
        self.dateProvider = dateProvider
        self.queue = queue
    }

    // MARK: - Shared Instance

    private static var _shared: DeviceTransferCheckpoint?
    private static let sharedQueue = DispatchQueue(label: "org.signal.device-transfer.checkpoint.shared")

    static var shared: DeviceTransferCheckpoint {
        return sharedQueue.sync {
            if let existing = _shared {
                return existing
            }
            let fileURL = URL(
                fileURLWithPath: "transfer_checkpoint.json",
                relativeTo: DeviceTransferService.pendingTransferDirectory
            )
            let storage = FileCheckpointStorage(
                fileURL: fileURL,
                directoryURL: DeviceTransferService.pendingTransferDirectory
            )
            let instance = DeviceTransferCheckpoint(storage: storage)
            _shared = instance
            return instance
        }
    }

    #if TESTABLE_BUILD
    static func setShared(_ checkpoint: DeviceTransferCheckpoint?) {
        sharedQueue.sync {
            _shared = checkpoint
        }
    }
    #endif

    // MARK: - Public Methods

    /// Saves a checkpoint to disk
    func save(_ checkpoint: CheckpointData) {
        queue.async {
            do {
                var mutableCheckpoint = checkpoint
                mutableCheckpoint.updatedAt = self.dateProvider.now()

                let encoder = JSONEncoder()
                encoder.dateEncodingStrategy = .iso8601
                let data = try encoder.encode(mutableCheckpoint)
                try self.storage.save(data)

                Logger.info("Saved transfer checkpoint with \(checkpoint.transferredFileIds.count) transferred files")
            } catch {
                Logger.error("Failed to save transfer checkpoint: \(error)")
            }
        }
    }

    /// Loads the most recent checkpoint from disk, if one exists
    func load() -> CheckpointData? {
        return queue.sync {
            guard storage.exists() else {
                return nil
            }

            do {
                guard let data = try storage.load() else {
                    return nil
                }
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
    func clear() {
        queue.async {
            do {
                try self.storage.delete()
                Logger.info("Cleared transfer checkpoint")
            } catch {
                Logger.error("Failed to clear transfer checkpoint: \(error)")
            }
        }
    }

    /// Synchronous clear for when immediate deletion is needed
    func clearSync() {
        queue.sync {
            do {
                try self.storage.delete()
                Logger.info("Cleared transfer checkpoint")
            } catch {
                Logger.error("Failed to clear transfer checkpoint: \(error)")
            }
        }
    }

    /// Checks if a valid checkpoint exists that matches the given manifest
    func hasValidCheckpoint(for manifestHash: Data, isIncoming: Bool) -> Bool {
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

        // Check if the checkpoint is too old
        guard dateProvider.now().timeIntervalSince(checkpoint.createdAt) < Self.maxCheckpointAge else {
            Logger.info("Existing checkpoint is too old, will start fresh")
            clear()
            return false
        }

        return true
    }

    /// Creates a new checkpoint for an outgoing transfer
    func createForOutgoingTransfer(
        estimatedTotalSize: UInt64,
        manifestHash: Data
    ) -> CheckpointData {
        return CheckpointData(
            isIncoming: false,
            createdAt: dateProvider.now(),
            estimatedTotalSize: estimatedTotalSize,
            manifestHash: manifestHash
        )
    }

    /// Creates a new checkpoint for an incoming transfer
    func createForIncomingTransfer(
        estimatedTotalSize: UInt64,
        manifestHash: Data
    ) -> CheckpointData {
        return CheckpointData(
            isIncoming: true,
            createdAt: dateProvider.now(),
            estimatedTotalSize: estimatedTotalSize,
            manifestHash: manifestHash
        )
    }

    /// Updates a checkpoint with a newly transferred file
    func markFileTransferred(_ fileId: String, in checkpoint: inout CheckpointData) {
        checkpoint.transferredFileIds.insert(fileId)
        checkpoint.updatedAt = dateProvider.now()
        save(checkpoint)
    }

    /// Updates a checkpoint with a skipped file
    func markFileSkipped(_ fileId: String, in checkpoint: inout CheckpointData) {
        checkpoint.skippedFileIds.insert(fileId)
        checkpoint.updatedAt = dateProvider.now()
        save(checkpoint)
    }

    // MARK: - Static Convenience Methods (for backwards compatibility)

    static func save(_ checkpoint: CheckpointData) {
        shared.save(checkpoint)
    }

    static func load() -> CheckpointData? {
        return shared.load()
    }

    static func clear() {
        shared.clear()
    }

    static func hasValidCheckpoint(for manifestHash: Data, isIncoming: Bool) -> Bool {
        return shared.hasValidCheckpoint(for: manifestHash, isIncoming: isIncoming)
    }

    static func createForOutgoingTransfer(
        manifest: DeviceTransferProtoManifest,
        manifestHash: Data
    ) -> CheckpointData {
        return shared.createForOutgoingTransfer(
            estimatedTotalSize: manifest.estimatedTotalSize,
            manifestHash: manifestHash
        )
    }

    static func createForIncomingTransfer(
        manifest: DeviceTransferProtoManifest,
        manifestHash: Data
    ) -> CheckpointData {
        return shared.createForIncomingTransfer(
            estimatedTotalSize: manifest.estimatedTotalSize,
            manifestHash: manifestHash
        )
    }

    static func markFileTransferred(_ fileId: String, in checkpoint: inout CheckpointData) {
        shared.markFileTransferred(fileId, in: &checkpoint)
    }

    static func markFileSkipped(_ fileId: String, in checkpoint: inout CheckpointData) {
        shared.markFileSkipped(fileId, in: &checkpoint)
    }
}
