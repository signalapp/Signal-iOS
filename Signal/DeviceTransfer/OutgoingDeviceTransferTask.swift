//
// Copyright 2025 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import CryptoKit
import Foundation
import GRDB
import SignalServiceKit

@MainActor
class OutgoingDeviceTransferTask {
    private let logger = PrefixedLogger(prefix: "[DeviceTransfer][Outgoing]")

    private let db: DB
    private let registrationStateChangeManager: RegistrationStateChangeManager
    private let deviceSleepManager: DeviceSleepManager?

    private let transferredFileIds = AtomicValue<[String]>([], lock: .init())
    private var throughputMonitor: ThroughputMonitor?
    private var session: DeviceTransfer.Session?
    private var transferInProgress = false

    private let sleepBlockObject = DeviceSleepBlockObject(blockReason: "device transfer")

    private let newDeviceServiceBrowser: DeviceTransfer.OutgoingConnection
    private var notificationObservers: [NotificationCenter.Observer] = []
    private var messagesReceiverTask: Task<Void, Never>?
    private var transferFinishedContinuation: CheckedContinuation<Void, Error>?

    private let waitTask = AtomicValue<Task<Void, Error>?>(nil, lock: .init())
    private let sendTask = AtomicValue<Task<Void, Error>?>(nil, lock: .init())

    let pairedPeerStream: AsyncThrowingStream<any DeviceTransfer.Peer, Error>
    let discoveredPeerStream: AsyncThrowingStream<[any DeviceTransfer.Peer], Error>
    private var pairedPeerListenTask: Task<Void, Error>?

    var selectedPeer: (any DeviceTransfer.Peer)? {
        newDeviceServiceBrowser.selectedPeer
    }

    init(
        deviceTransferURL: URL,
        db: DB,
        deviceSleepManager: DeviceSleepManager?,
        deviceTransferConnectionFactory: DeviceTransfer.ConnectionFactory,
        registrationStateChangeManager: RegistrationStateChangeManager,
        tsAccountManager: TSAccountManager,
    ) throws {
        self.db = db
        self.registrationStateChangeManager = registrationStateChangeManager
        self.deviceSleepManager = deviceSleepManager
        self.newDeviceServiceBrowser = try deviceTransferConnectionFactory.buildOutgoingConnection(
            tsAccountManager: tsAccountManager,
            deviceTransferURL: deviceTransferURL,
        )

        (
            self.pairedPeerStream,
            self.discoveredPeerStream,
            self.pairedPeerListenTask,
        ) = DeviceTransfer.Utils.bindPeerDiscoveryStream(
            discoveredPeerStream: self.newDeviceServiceBrowser.discoveredPeerStream,
            logger: logger,
        )
    }

    func connectToNewDevice(peer: any DeviceTransfer.Peer) async throws {
        logger.info("Connecting to new device")
        await stop(error: nil)
        deviceSleepManager?.addBlock(blockObject: sleepBlockObject)
        do {
            if let task = waitTask.get() {
                try await task.value
            } else {
                let task = waitTask.update {
                    let task = Task {
                        self.session = try await newDeviceServiceBrowser.connect(peer: peer)
                    }
                    $0 = task
                    return task
                }
                try await task.value
                _ = waitTask.swap(nil)
            }
        } catch {
            logger.error("Failed to connect \(error)")
            throw error
        }
    }

    @MainActor
    func transferAccountToNewDevice(initializeProgressBlock: ((Progress) -> Void)? = nil) async throws {
        logger.info("Begin transfer to new device")
        if let task = sendTask.get() {
            // Another task has already started the transfer, wait for it to complete
            try await task.value
            return
        }

        guard let session else {
            throw OWSAssertionError("Not connected")
        }

        notificationObservers.append(
            NotificationCenter.default.addObserver(
                name: .OWSApplicationDidEnterBackground,
                block: didEnterBackground(_:),
            ),
        )

        try await session.waitForConnection()

        logger.info("Begin receiving messages from new device")
        messagesReceiverTask = Task {
            do {
                for try await message in session.messages {
                    switch message {
                    case .message(let message):
                        try await processMessage(message: message, session: session)
                    case .startResource(_, let size, let progress):
                        guard let progress, let size else { return }
                        self.throughputMonitor?.progress.addChild(
                            progress,
                            withPendingUnitCount: Int64(clamping: size),
                        )
                    case .finishResource:
                        break
                    }
                }
            } catch {
                self.transferFinishedContinuation.take()?.resume(throwing: error)
            }
        }

        // We've successfully connected - now mark the transfer as in progress.
        // Marking the transfer as "in progress" does a few things, most notably it:
        //   * prevents any WAL checkpoints while the transfer is in progress
        //   * causes the device to behave is if it's not registered
        await db.awaitableWrite { tx in
            registrationStateChangeManager.setIsTransferInProgress(tx: tx)
        }
        transferInProgress = true

        defer {
            // If we failed to start the transfer, clear the transfer in progress flag
            if !transferInProgress {
                db.write { tx in
                    registrationStateChangeManager.setIsTransferComplete(
                        sendStateUpdateNotification: true,
                        tx: tx,
                    )
                }
            }
            notificationObservers.forEach {
                NotificationCenter.default.removeObserver($0)
            }
            notificationObservers.removeAll()
        }

        let manifest = try buildManifest()
        let progress = Progress(totalUnitCount: Int64(manifest.estimatedTotalSize))
        initializeProgressBlock?(progress)
        throughputMonitor = ThroughputMonitor(progress: progress)
        deviceSleepManager?.addBlock(blockObject: sleepBlockObject)

        // Only send the files if we haven't yet sent the manifest.
        guard !transferredFileIds.get().contains(DeviceTransfer.Constants.manifestIdentifier) else { return }

        logger.info("Start sending files to new device")
        let task = sendTask.update {
            let task = Task {
                do {
                    try await sendManifest(manifest: manifest, session: session)
                    try await sendAllFiles(manifest: manifest, session: session)
                } catch where error is CancellationError {
                    throw error
                } catch {
                    if Task.isCancelled {
                        throw CancellationError()
                    }
                    await self.failTransfer(.assertion, "Failed to send manifest to new device \(error)")
                    throw error
                }
                logger.debug("finished transfer task")
            }
            $0 = task
            return task
        }
        try await task.value
        _ = sendTask.swap(nil)

        // Now that everything has been transferred to the new device, mark this device as deregistered.
        // This helps with the rare case that the transfer is interrupted on the new device before completion,
        // and allows the user to re-register on the old device and try the transfer again before anything
        // destructive happens on the old device.
        await db.awaitableWrite { tx in
            self.registrationStateChangeManager.setIsDeregisteredOrDelinked(
                true,
                notify: false,
                tx: tx,
            )
        }

        logger.info("Finished sending files to new device")

        // wait for message back from caller
        try await withCheckedThrowingContinuation { continuation in
            self.transferFinishedContinuation = continuation
        }
    }

    func stop(error: Error?) async {
        await stopTransfer(error: error)
    }

    private func didEnterBackground(_ notification: Notification) {
        // MCSession automatically disconnects when the app is backgrounded.
        // Send an explicit message to the peer (if connected) telling them
        // that's what happened.
        try? session?.send(message: .backgroundApp)
        Task {
            await stopTransfer(error: CancellationError())
        }
    }

    // MARK: - Sending

    private func sendAllFiles(
        manifest: DeviceTransferProtoManifest,
        session: DeviceTransfer.Session,
    ) async throws {
        guard let database = manifest.database else {
            throw OWSAssertionError("Manifest unexpectedly missing database")
        }

        struct DatabaseCopy {
            let db: DeviceTransferProtoFile
            let wal: DeviceTransferProtoFile
        }

        try await withThrowingTaskGroup(of: Void.self) { taskGroup in
            taskGroup.addTask { @MainActor in
                // Make a copy of the database files within a write transaction so we can be confident
                // they aren't mutated during the copy. We then transfer these copies.
                let dbCopy = try await SSKEnvironment.shared.databaseStorageRef.awaitableWrite { [weak self] tx in
                    // The MultipeerConnectivity framework stalls if we try to send an empty
                    // file. The receiver requires a non-empty file. We can't send garbage
                    // (because that would corrupt the database), so mutate the database, force
                    // it to be written to the WAL file, and then send that result to our peer.
                    let store = NewKeyValueStore(collection: "DeviceTransferWAL")
                    store.writeValue(Randomness.generateRandomBytes(32), forKey: "MustBeNonEmpty", tx: tx)
                    store.removeValue(forKey: "MustBeNonEmpty", tx: tx)
                    sqlite3_db_cacheflush(tx.database.sqliteConnection!)
                    do {
                        let dbCopy = try Self.makeLocalCopy(databaseFile: database.database)
                        let walCopy = try Self.makeLocalCopy(databaseFile: database.wal)
                        return DatabaseCopy(db: dbCopy, wal: walCopy)
                    } catch {
                        self?.logger.error("Failed to copy database files!")
                        throw error
                    }
                }
                defer {
                    for databaseFile in [dbCopy.db, dbCopy.wal] {
                        if let copyUrl = try? Self.urlForCopy(databaseFile: databaseFile) {
                            try? OWSFileSystem.deleteFile(url: copyUrl)
                        }
                    }
                }
                for databaseFile in [dbCopy.db, dbCopy.wal] {
                    try await self.send(
                        session: session,
                        file: databaseFile,
                    )
                }
            }
            for (index, file) in manifest.files.enumerated() {
                if index >= 10 {
                    // If we've already kicked off 10, wait for one to finish before starting the next.
                    try await taskGroup.next()
                }
                taskGroup.addTask {
                    try await self.send(
                        session: session,
                        file: file,
                    )
                }
            }
            // Make sure to wait for whatever's left at the end.
            try await taskGroup.waitForAll()
        }

        try session.send(message: .done)
    }

    private func send(session: DeviceTransfer.Session, file: DeviceTransferProtoFile) async throws {
        try Task.checkCancellation()
        if transferredFileIds.get().contains(file.identifier) {
            logger.info("File was already transferred, skipping")
            return
        }

        var url = URL(
            fileURLWithPath: file.relativePath,
            relativeTo: DeviceTransfer.Constants.appSharedDataDirectory,
        )

        if !OWSFileSystem.fileOrFolderExists(url: url) {
            guard
                ![
                    DeviceTransfer.Constants.databaseWALIdentifier,
                    DeviceTransfer.Constants.databaseIdentifier,
                ].contains(file.identifier)
            else {
                throw OWSAssertionError("Mandatory database file is missing for transfer")
            }

            logger.warn("Missing file for transfer, it probably disappeared or was otherwise deleted. Sending missing file placeholder.")

            url = OWSFileSystem.temporaryFileUrl(isAvailableWhileDeviceLocked: false)
            guard
                FileManager.default.createFile(
                    atPath: url.path,
                    contents: DeviceTransfer.Constants.missingFileData,
                    attributes: nil,
                )
            else {
                throw OWSAssertionError("Failed to create temp file for missing file \(url)")
            }
        }

        guard let sha256Digest = try? Cryptography.computeSHA256DigestOfFile(at: url) else {
            throw OWSAssertionError("Failed to calculate sha256 for file")
        }

        do {
            try await session.sendFile(
                url: url,
                name: file.identifier + " " + sha256Digest.hexadecimalString,
                size: file.estimatedSize,
            )
        } catch where error is CancellationError {
            throw error
        } catch {
            throw OWSGenericError("Transferring file \(file.identifier) failed \(error)")
        }
        transferredFileIds.update { $0.append(file.identifier) }
    }

    private func stopTransfer(error: Error? = nil, notifyRegState: Bool = true) async {
        if let error {
            switch error {
            case DeviceTransfer.Error.otherDeviceTerminated:
                break
            default:
                try? session?.send(message: .transferFailed)
            }
        }
        sendTask.swap(nil)?.cancel()
        try? await withCooperativeTimeout(seconds: 2) { [weak self] in
            await self?.session.take()?.disconnect(error: error)
        }
        waitTask.swap(nil)?.cancel()
        pairedPeerListenTask.take()?.cancel()
        await newDeviceServiceBrowser.stop(error: error)
        throughputMonitor?.stop()
        deviceSleepManager?.removeBlock(blockObject: sleepBlockObject)

        // It is possible that we get here because the app was backgrounded
        // after a failed launch. In that case, `tsAccountManager` will not be
        // available, and setting this will crash. It'd probably be safe to more
        // simply return in the .idle case above since none of the values being
        // reset should have values if we are idle, but I am scared of it.
        if transferInProgress {
            await db.awaitableWrite { tx in
                self.registrationStateChangeManager.setIsTransferComplete(
                    sendStateUpdateNotification: notifyRegState,
                    tx: tx,
                )
            }
        }
        transferInProgress = false
    }

    private func failTransfer(_ error: DeviceTransfer.Error, _ reason: String) async {
        logger.error("Failed transfer \(reason)")
        await stopTransfer(error: error)
    }

    private func processMessage(message: DeviceTransfer.Message, session: DeviceTransfer.Session) async throws {
        switch message {
        case DeviceTransfer.Message.backgroundApp:
            return await failTransfer(DeviceTransfer.Error.backgroundedDevice, "Received terminate message")
        case DeviceTransfer.Message.transferFailed:
            return await failTransfer(DeviceTransfer.Error.otherDeviceTerminated, "Received terminate message")
        case DeviceTransfer.Message.done:
            break
        }

        await stopTransfer()

        // Everything done and acknowledged, mark the local device as transferred
        await db.awaitableWrite { tx in
            self.registrationStateChangeManager.setWasTransferred(tx: tx)
        }

        // When the old device receives the done message from the new device,
        // it can be confident that the transfer has completed successfully and
        // clear out all data from this device. This will crash the app.
        Task { @MainActor in
            SignalApp.shared.resetAppData(keyFetcher: SSKEnvironment.shared.databaseStorageRef.keyFetcher)
            SignalApp.shared.showTransferCompleteAndExit()
        }

        transferFinishedContinuation.take()?.resume()
    }

    // MANIFEST

    private func buildManifest() throws -> DeviceTransferProtoManifest {
        var manifestBuilder = DeviceTransferProtoManifest.builder(grdbSchemaVersion: UInt64(GRDBSchemaMigrator.grdbSchemaVersionLatest))
        var estimatedTotalSize: UInt64 = 0

        // Database

        do {
            let database: DeviceTransferProtoFile = try {
                let file = SSKEnvironment.shared.databaseStorageRef.grdbStorage.databaseFilePath
                let size = try OWSFileSystem.fileSize(ofPath: file)
                guard size > 0 else {
                    throw OWSAssertionError("database is empty")
                }
                estimatedTotalSize += size
                let fileBuilder = DeviceTransferProtoFile.builder(
                    identifier: DeviceTransfer.Constants.databaseIdentifier,
                    relativePath: try pathRelativeToAppSharedDirectory(file),
                    estimatedSize: size,
                )
                return fileBuilder.buildInfallibly()
            }()

            let wal: DeviceTransferProtoFile = try {
                let file = SSKEnvironment.shared.databaseStorageRef.grdbStorage.databaseWALFilePath
                let size = try OWSFileSystem.fileSize(ofPath: file)
                estimatedTotalSize += size
                let fileBuilder = DeviceTransferProtoFile.builder(
                    identifier: DeviceTransfer.Constants.databaseWALIdentifier,
                    relativePath: try pathRelativeToAppSharedDirectory(file),
                    estimatedSize: size,
                )
                return fileBuilder.buildInfallibly()
            }()

            let databaseBuilder = DeviceTransferProtoDatabase.builder(
                key: try SSKEnvironment.shared.databaseStorageRef.keyFetcher.fetchData(),
                database: database,
                wal: wal,
            )
            manifestBuilder.setDatabase(databaseBuilder.buildInfallibly())
        }

        // Attachments, Avatars, and Stickers

        // TODO: Ideally, these paths would reference constants...
        let foldersToTransfer = ["Attachments/", "ProfileAvatars/", "GroupAvatars/", "StickerManager/", "Wallpapers/", "Library/Sounds/", "AvatarHistory/", "attachment_files/"]
        let filesToTransfer = try foldersToTransfer.flatMap { folder -> [String] in
            let url = URL(fileURLWithPath: folder, relativeTo: DeviceTransfer.Constants.appSharedDataDirectory)
            return try OWSFileSystem.recursiveFilesInDirectory(url.path)
        }

        for file in filesToTransfer {
            let size = try OWSFileSystem.fileSize(ofPath: file)

            guard size > 0 else {
                owsFailDebug("skipping empty file \(file)")
                continue
            }

            estimatedTotalSize += size
            let fileBuilder = DeviceTransferProtoFile.builder(
                identifier: UUID().uuidString,
                relativePath: try pathRelativeToAppSharedDirectory(file),
                estimatedSize: size,
            )
            manifestBuilder.addFiles(fileBuilder.buildInfallibly())
        }

        // Standard Defaults
        func isAppleKey(_ key: String) -> Bool {
            return key.starts(with: "NS") || key.starts(with: "Apple")
        }

        do {
            for (key, value) in UserDefaults.standard.dictionaryRepresentation() {
                // Filter out any keys we think are managed by Apple, we don't need to transfer them.
                guard !isAppleKey(key) else { continue }

                guard let encodedValue = try? NSKeyedArchiver.archivedData(withRootObject: value, requiringSecureCoding: true) else { continue }

                let defaultBuilder = DeviceTransferProtoDefault.builder(
                    key: key,
                    encodedValue: encodedValue,
                )
                manifestBuilder.addStandardDefaults(defaultBuilder.buildInfallibly())
            }
        }

        // App Defaults

        do {
            for (key, value) in CurrentAppContext().appUserDefaults().dictionaryRepresentation() {
                // Filter out any keys we think are managed by Apple, we don't need to transfer them.
                guard !isAppleKey(key) else { continue }

                guard let encodedValue = try? NSKeyedArchiver.archivedData(withRootObject: value, requiringSecureCoding: true) else { continue }

                let defaultBuilder = DeviceTransferProtoDefault.builder(
                    key: key,
                    encodedValue: encodedValue,
                )
                manifestBuilder.addAppDefaults(defaultBuilder.buildInfallibly())
            }
        }

        manifestBuilder.setEstimatedTotalSize(estimatedTotalSize)

        return manifestBuilder.buildInfallibly()
    }

    private func pathRelativeToAppSharedDirectory(_ path: String) throws -> String {
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

        var path = path.replacingOccurrences(of: DeviceTransfer.Constants.appSharedDataDirectory.path, with: "")
        if path.starts(with: "/") { path.removeFirst() }
        return path
    }

    @MainActor
    private func sendManifest(manifest: DeviceTransferProtoManifest, session: DeviceTransfer.Session) async throws {
        logger.info("Sending manifest to new device.")

        DeviceTransfer.Utils.resetTransferDirectory(createNewTransferDirectory: true)

        // We write the manifest to a temp file, since MCSession only allows sending "typed"
        // data when sending files, unless you do your own stream management.
        let manifestData = try manifest.serializedData()
        let manifestFileURL = URL(
            fileURLWithPath: DeviceTransfer.Constants.manifestIdentifier,
            relativeTo: DeviceTransfer.Constants.pendingTransferDirectory,
        )
        try manifestData.write(to: manifestFileURL, options: .atomic)

        defer {
            OWSFileSystem.deleteFileIfExists(manifestFileURL.path)
        }

        try await session.sendFile(
            url: manifestFileURL,
            name: DeviceTransfer.Constants.manifestIdentifier,
            size: UInt64(clamping: manifestData.count),
        )

        logger.info("Successfully sent manifest to new device.")

        transferredFileIds.update {
            $0.append(DeviceTransfer.Constants.manifestIdentifier)
        }
        throughputMonitor?.start()
    }

    // MARK: - Utilities

    private static let dbCopyFilename = "db_copy_for_transfer"
    private static let walCopyFilename = "wal_copy_for_transfer"

    private static func urlForCopy(
        databaseFile: DeviceTransferProtoFile,
    ) throws -> URL {
        let newFileName: String
        let newFileExtension: String
        if databaseFile.identifier == DeviceTransfer.Constants.databaseIdentifier {
            newFileName = Self.dbCopyFilename
            newFileExtension = ".sqlite"
        } else if databaseFile.identifier == DeviceTransfer.Constants.databaseWALIdentifier {
            newFileName = Self.walCopyFilename
            newFileExtension = ".sqlite-wal"
        } else {
            throw OWSAssertionError("Unknown db file being copied")
        }
        owsAssertDebug(databaseFile.relativePath.hasSuffix(newFileExtension))
        return OWSFileSystem.temporaryFileUrl(
            fileName: newFileName,
            fileExtension: newFileExtension,
            isAvailableWhileDeviceLocked: false,
        )
    }

    private static func makeLocalCopy(
        databaseFile: DeviceTransferProtoFile,
    ) throws -> DeviceTransferProtoFile {
        let url = URL(
            fileURLWithPath: databaseFile.relativePath,
            relativeTo: DeviceTransfer.Constants.appSharedDataDirectory,
        )

        if !OWSFileSystem.fileOrFolderExists(url: url) {
            throw OWSAssertionError("Mandatory database file is missing for transfer")
        }

        let copyUrl = try Self.urlForCopy(databaseFile: databaseFile)

        if OWSFileSystem.fileOrFolderExists(url: copyUrl) {
            // We might have partially copied before. Delete it.
            try OWSFileSystem.deleteFile(url: copyUrl)
        }
        try OWSFileSystem.copyFile(from: url, to: copyUrl)

        // Note that the receiver doesn't care about the relative path
        // for database files (it does care for other files!) because it
        // forces the path to be that to its own local database.
        var protoBuilder = databaseFile.asBuilder()
        protoBuilder.setRelativePath(copyUrl.relativePath)
        return protoBuilder.buildInfallibly()
    }
}
