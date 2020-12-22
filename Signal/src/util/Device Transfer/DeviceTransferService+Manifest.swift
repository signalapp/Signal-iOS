//
//  Copyright (c) 2020 Open Whisper Systems. All rights reserved.
//

import Foundation
import PromiseKit
import MultipeerConnectivity

extension DeviceTransferService {
    func buildManifest() throws -> DeviceTransferProtoManifest {
        var manifestBuilder = DeviceTransferProtoManifest.builder(grdbSchemaVersion: UInt64(GRDBSchemaMigrator.grdbSchemaVersionLatest))
        var estimatedTotalSize: UInt64 = 0

        // Database

        do {
            assert(StorageCoordinator.hasGrdbFile)

            let database: DeviceTransferProtoFile = try {
                let file = databaseStorage.grdbStorage.databaseFilePath
                guard let size = OWSFileSystem.fileSize(ofPath: file), size.uint64Value > 0 else {
                    throw OWSAssertionError("Failed to calculate size of database \(file)")
                }
                estimatedTotalSize += size.uint64Value
                let fileBuilder = DeviceTransferProtoFile.builder(
                    identifier: DeviceTransferService.databaseIdentifier,
                    relativePath: try pathRelativeToAppSharedDirectory(file),
                    estimatedSize: size.uint64Value
                )
                return try fileBuilder.build()
            }()

            let wal: DeviceTransferProtoFile = try {
                let file = databaseStorage.grdbStorage.databaseWALFilePath
                guard let size = OWSFileSystem.fileSize(ofPath: file), size.uint64Value > 0 else {
                    throw OWSAssertionError("Failed to calculate size of database wal \(file)")
                }
                estimatedTotalSize += size.uint64Value
                let fileBuilder = DeviceTransferProtoFile.builder(
                    identifier: DeviceTransferService.databaseWALIdentifier,
                    relativePath: try pathRelativeToAppSharedDirectory(file),
                    estimatedSize: size.uint64Value
                )
                return try fileBuilder.build()
            }()

            let databaseBuilder = DeviceTransferProtoDatabase.builder(
                key: try GRDBDatabaseStorageAdapter.keyspec.fetchData(),
                database: database,
                wal: wal
            )
            manifestBuilder.setDatabase(try databaseBuilder.build())
        }

        // Attachments, Avatars, and Stickers

        let foldersToTransfer = ["Attachments/", "ProfileAvatars/", "StickerManager/"]
        let filesToTransfer = try foldersToTransfer.flatMap { folder -> [String] in
            let url = URL(fileURLWithPath: folder, relativeTo: DeviceTransferService.appSharedDataDirectory)
            return try OWSFileSystem.recursiveFilesInDirectory(url.path)
        }

        for file in filesToTransfer {
            guard let size = OWSFileSystem.fileSize(ofPath: file) else {
                throw OWSAssertionError("Failed to calculate size of file \(file)")
            }

            guard size.uint64Value > 0 else {
                owsFailDebug("skipping empty file \(file)")
                continue
            }

            estimatedTotalSize += size.uint64Value
            let fileBuilder = DeviceTransferProtoFile.builder(
                identifier: UUID().uuidString,
                relativePath: try pathRelativeToAppSharedDirectory(file),
                estimatedSize: size.uint64Value
            )
            manifestBuilder.addFiles(try fileBuilder.build())
        }

        // Standard Defaults
        func isAppleKey(_ key: String) -> Bool {
            return key.starts(with: "NS") || key.starts(with: "Apple")
        }

        do {
            for (key, value) in UserDefaults.standard.dictionaryRepresentation() {
                // Filter out any keys we think are managed by Apple, we don't need to transfer them.
                guard !isAppleKey(key) else { continue }

                let defaultBuilder = DeviceTransferProtoDefault.builder(
                    key: key,
                    encodedValue: NSKeyedArchiver.archivedData(withRootObject: value)
                )
                manifestBuilder.addStandardDefaults(try defaultBuilder.build())
            }
        }

        // App Defaults

        do {
            for (key, value) in CurrentAppContext().appUserDefaults().dictionaryRepresentation() {
                // Filter out any keys we think are managed by Apple, we don't need to transfer them.
                guard !isAppleKey(key) else { continue }

                let defaultBuilder = DeviceTransferProtoDefault.builder(
                    key: key,
                    encodedValue: NSKeyedArchiver.archivedData(withRootObject: value)
                )
                manifestBuilder.addAppDefaults(try defaultBuilder.build())
            }
        }

        manifestBuilder.setEstimatedTotalSize(estimatedTotalSize)

        return try manifestBuilder.build()
    }

    func pathRelativeToAppSharedDirectory(_ path: String) throws -> String {
        guard !path.contains("*") else {
            throw OWSAssertionError("path contains invalid character: *")
        }

        let components = path.components(separatedBy: "/")

        guard components.first != "~" else {
            throw OWSAssertionError("path starts with invalid component: ~")
        }

        for component in components {
            guard component != "." else {
                throw OWSAssertionError("path contains invalid component: .")
            }

            guard component != ".." else {
                throw OWSAssertionError("path contains invalid component: ..")
            }
        }

        var path = path.replacingOccurrences(of: DeviceTransferService.appSharedDataDirectory.path, with: "")
        if path.starts(with: "/") { path.removeFirst() }
        return path
    }

    func handleReceivedManifest(at localURL: URL, fromPeer peerId: MCPeerID) {
        guard case .idle = transferState else {
            stopTransfer()
            return owsFailDebug("Received manifest in unexpected state \(transferState)")
        }
        guard let fileSize = OWSFileSystem.fileSize(of: localURL) else {
            stopTransfer()
            return owsFailDebug("Missing manifest file.")
        }
        guard fileSize.uint64Value < 1024 * 1024 * 10 else {
            stopTransfer()
            return owsFailDebug("Unexpectedly received a very large manifest \(fileSize)")
        }
        guard let data = try? Data(contentsOf: localURL) else {
            stopTransfer()
            return owsFailDebug("Failed to read manifest data")
        }
        guard let manifest = try? DeviceTransferProtoManifest(serializedData: data) else {
            stopTransfer()
            return owsFailDebug("Failed to parse manifest proto")
        }
        guard !tsAccountManager.isRegistered else {
            stopTransfer()
            return owsFailDebug("Ignoring incoming transfer to a registered device")
        }

        resetTransferDirectory()

        guard OWSFileSystem.moveFilePath(
            localURL.path,
            toFilePath: URL(
                fileURLWithPath: DeviceTransferService.manifestIdentifier,
                relativeTo: DeviceTransferService.pendingTransferDirectory
            ).path
        ) else {
            return owsFailDebug("Failed to move manifest into place")
        }

        let progress = Progress(totalUnitCount: Int64(manifest.estimatedTotalSize))

        transferState = .incoming(
            oldDevicePeerId: peerId,
            manifest: manifest,
            receivedFileIds: [DeviceTransferService.manifestIdentifier],
            skippedFileIds: [],
            progress: progress
        )

        tsAccountManager.isTransferInProgress = true

        notifyObservers { $0.deviceTransferServiceDidStartTransfer(progress: progress) }

        startThroughputCalculation()

        // Check if the device has a newer version of the database than we understand

        guard manifest.grdbSchemaVersion <= GRDBSchemaMigrator.grdbSchemaVersionLatest else {
            return self.failTransfer(.unsupportedVersion, "Ignoring manifest with unsupported schema version")
        }

        // Check if there is enough space on disk to receive the transfer

        guard let fileSystemAttributes = try? FileManager.default.attributesOfFileSystem(
            forPath: DeviceTransferService.pendingTransferDirectory.path
        ) else {
            return self.failTransfer(.assertion, "failed to calculate available disk space")
        }

        guard let freeSpaceInBytes = fileSystemAttributes[.systemFreeSize] as? UInt64, freeSpaceInBytes > manifest.estimatedTotalSize else {
            return self.failTransfer(.notEnoughSpace, "not enough free space to receive transfer")
        }
    }

    func sendManifest() throws -> Promise<Void> {
        Logger.info("Sending manifest to new device.")

        guard case .outgoing(let newDevicePeerId, _, let manifest, _, _) = transferState else {
            throw OWSAssertionError("attempted to send manifest while no active outgoing transfer")
        }

        guard let session = session else {
            throw OWSAssertionError("attempted to send manifest without an available session")
        }

        resetTransferDirectory()

        // We write the manifest to a temp file, since MCSession only allows sending "typed"
        // data when sending files, unless you do your own stream management.
        let manifestData = try manifest.serializedData()
        let manifestFileURL = URL(
            fileURLWithPath: DeviceTransferService.manifestIdentifier,
            relativeTo: DeviceTransferService.pendingTransferDirectory
        )
        try manifestData.write(to: manifestFileURL, options: .atomic)

        let (promise, resolver) = Promise<Void>.pending()

        session.sendResource(at: manifestFileURL, withName: DeviceTransferService.manifestIdentifier, toPeer: newDevicePeerId) { error in
            if let error = error {
                resolver.reject(error)
            } else {
                resolver.fulfill(())

                Logger.info("Successfully sent manifest to new device.")

                self.transferState = self.transferState.appendingFileId(DeviceTransferService.manifestIdentifier)
                self.startThroughputCalculation()
            }

            OWSFileSystem.deleteFileIfExists(manifestFileURL.path)
        }

        return promise
    }

    func readManifestFromTransferDirectory() -> DeviceTransferProtoManifest? {
        let manifestPath = URL(
            fileURLWithPath: DeviceTransferService.manifestIdentifier,
            relativeTo: DeviceTransferService.pendingTransferDirectory
        ).path
        guard OWSFileSystem.fileOrFolderExists(atPath: manifestPath) else { return nil }
        guard let manifestData = try? Data(contentsOf: URL(fileURLWithPath: manifestPath)) else { return nil }
        return try? DeviceTransferProtoManifest(serializedData: manifestData)
    }
}
