//
// Copyright 2025 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import CryptoKit
import Foundation
import GRDB
import SignalServiceKit

@MainActor
class OutgoingDeviceTransferTask: DeviceTransferSessionDelegate {

    let db: DB
    let registrationStateChangeManager: RegistrationStateChangeManager
    let deviceSleepManager: DeviceSleepManager?
    let tsAccountManager: TSAccountManager

    let transferredFileIds = AtomicValue<[String]>([], lock: .init())
    var throughputMonitor: ThroughputMonitor?
    var session: DeviceTransferSession?
    var transferInProgress = false
    var expectedCertificateHash: Data?

    private let sleepBlockObject = DeviceSleepBlockObject(blockReason: "device transfer")

    init(
        db: DB,
        deviceSleepManager: DeviceSleepManager?,
        registrationStateChangeManager: RegistrationStateChangeManager,
        tsAccountManager: TSAccountManager,
    ) {
        self.db = db
        self.registrationStateChangeManager = registrationStateChangeManager
        self.deviceSleepManager = deviceSleepManager
        self.tsAccountManager = tsAccountManager

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(didEnterBackground),
            name: .OWSApplicationDidEnterBackground,
            object: nil,
        )
    }

    private lazy var newDeviceServiceBrowser = {
        MPCDeviceTransfer.Browser(peerId: DeviceTransferPeerID(displayName: UUID().uuidString))
    }()

    func connectToNewDevice(with peerId: DeviceTransferPeerID, certificateHash: Data) async throws {
        cancelTransferToNewDevice()
        deviceSleepManager?.addBlock(blockObject: sleepBlockObject)
        expectedCertificateHash = certificateHash
        self.session = try await newDeviceServiceBrowser.start()
        self.session?.delegate = Weak(value: self)
    }

    private var sendTask: Task<Void, Error>?
    @MainActor
    func transferAccountToNewDevice(initializeProgressBlock: ((Progress) -> Void)? = nil) async throws {
        guard let session else {
            throw OWSAssertionError("Not connected")
        }

        try await session.waitForConnection()

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
            transferInProgress = false
        }

        let manifest = try buildManifest()
        let progress = Progress(totalUnitCount: Int64(manifest.estimatedTotalSize))
        initializeProgressBlock?(progress)
        throughputMonitor = ThroughputMonitor(progress: progress)
        deviceSleepManager?.addBlock(blockObject: sleepBlockObject)

        // Only send the files if we haven't yet sent the manifest.
        guard !transferredFileIds.get().contains(DeviceTransfer.Constants.manifestIdentifier) else { return }

        sendTask = Task {
            do {
                try await self.sendManifest(manifest: manifest, session: session)
                try await self.sendAllFiles(manifest: manifest, session: session)
            } catch where error is CancellationError {
                throw error
            } catch {
                self.failTransfer(.assertion, "Failed to send manifest to new device \(error)")
            }
        }
        try await sendTask?.value
    }

    func cancelTransferToNewDevice() {
        stopTransfer()
    }

    func stopListening() {
        newDeviceServiceBrowser.stop()
    }

    // MARK: - Sending

    private func sendAllFiles(
        manifest: DeviceTransferProtoManifest,
        session: DeviceTransferSession,
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
                let dbCopy = try await SSKEnvironment.shared.databaseStorageRef.awaitableWrite { tx in
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
                        Logger.error("Failed to copy database files!")
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

        await db.awaitableWrite { tx in
            self.registrationStateChangeManager.setWasTransferred(tx: tx)
        }

        try session.send(message: .done)
    }

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

    private func send(session: DeviceTransferSession, file: DeviceTransferProtoFile) async throws {
        try Task.checkCancellation()
        if transferredFileIds.get().contains(file.identifier) {
            Logger.info("File was already transferred, skipping")
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

            Logger.warn("Missing file for transfer, it probably disappeared or was otherwise deleted. Sending missing file placeholder.")

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
            try await session.sendResource(
                url: url,
                name: file.identifier + " " + sha256Digest.hexadecimalString,
            ) { fileProgress in
                guard let fileProgress else { return }
                self.throughputMonitor?.progress.addChild(
                    fileProgress,
                    withPendingUnitCount: Int64(file.estimatedSize),
                )
            }
        } catch where error is CancellationError {
            throw error
        } catch {
            throw OWSGenericError("Transferring file \(file.identifier) failed \(error)")
        }
        Logger.info("Transferring file \(file.identifier) complete")
        transferredFileIds.update { $0.append(file.identifier) }
    }

    @objc
    private func didEnterBackground() {
        // MCSession automatically disconnects when the app is backgrounded.
        // Send an explicit message to the peer (if connected) telling them
        // that's what happened.
        try? session?.send(message: .backgroundApp)
        stopTransfer()
    }

    func stopTransfer(notifyRegState: Bool = true) {
        sendTask?.cancel()
        newDeviceServiceBrowser.stop()
        throughputMonitor?.stop()
        deviceSleepManager?.removeBlock(blockObject: sleepBlockObject)

        // It is possible that we get here because the app was backgrounded
        // after a failed launch. In that case, `tsAccountManager` will not be
        // available, and setting this will crash. It'd probably be safe to more
        // simply return in the .idle case above since none of the values being
        // reset should have values if we are idle, but I am scared of it.
        if transferInProgress {
            db.write { tx in
                self.registrationStateChangeManager.setIsTransferComplete(
                    sendStateUpdateNotification: notifyRegState,
                    tx: tx,
                )
            }
        }
        transferInProgress = false
    }

    func failTransfer(_ error: DeviceTransfer.Error, _ reason: String) {
        Logger.error("Failed transfer \(reason)")
        stopTransfer()
    }

    // MARK: - Utility

    func parseTransferURL(_ url: URL) throws -> (peerId: DeviceTransferPeerID, certificateHash: Data) {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false), let queryItems = components.queryItems else {
            throw OWSAssertionError("Invalid url")
        }

        let queryItemsDictionary = [String: String](uniqueKeysWithValues: queryItems.compactMap { item in
            guard let value = item.value else { return nil }
            return (item.name, value)
        })

        guard
            let version = queryItemsDictionary[DeviceTransfer.UrlConstants.versionKey],
            Int(version) == DeviceTransfer.UrlConstants.currentTransferVersion
        else {
            throw DeviceTransfer.Error.unsupportedVersion
        }

        let currentMode: DeviceTransfer.Mode = tsAccountManager
            .registrationStateWithMaybeSneakyTransaction.isPrimaryDevice == true ? .primary : .linked

        guard
            let rawMode = queryItemsDictionary[DeviceTransfer.UrlConstants.transferModeKey],
            rawMode == currentMode.rawValue
        else {
            throw DeviceTransfer.Error.modeMismatch
        }

        guard
            let base64CertificateHash = queryItemsDictionary[DeviceTransfer.UrlConstants.certificateHashKey],
            let uriDecodedHash = base64CertificateHash.removingPercentEncoding,
            let certificateHash = Data(base64Encoded: uriDecodedHash)
        else {
            throw OWSAssertionError("failed to decode certificate hash")
        }

        guard
            let base64PeerId = queryItemsDictionary[DeviceTransfer.UrlConstants.peerIdKey],
            let uriDecodedPeerId = base64PeerId.removingPercentEncoding,
            let peerIdData = Data(base64Encoded: uriDecodedPeerId),
            let peerId = DeviceTransferPeerID(with: peerIdData)
        else {
            throw OWSAssertionError("failed to decode MCPeerId")
        }

        return (peerId, certificateHash)
    }

    // Delegate

    func session(
        _ session: DeviceTransferSession,
        didReceive data: Data,
    ) {
        switch data {
        case DeviceTransfer.Message.backgroundApp.data:
            return failTransfer(DeviceTransfer.Error.backgroundedDevice, "Received terminate message")
        case DeviceTransfer.Message.done.data:
            break
        default:
            return failTransfer(DeviceTransfer.Error.assertion, "Received unexpected data")
        }

        stopTransfer()

        // When the old device receives the done message from the new device,
        // it can be confident that the transfer has completed successfully and
        // clear out all data from this device. This will crash the app.
        Task { @MainActor in
            SignalApp.shared.resetAppData(keyFetcher: SSKEnvironment.shared.databaseStorageRef.keyFetcher)
            SignalApp.shared.showTransferCompleteAndExit()
        }
    }

    func session(
        _ session: DeviceTransferSession,
        didStartReceivingResourceWithName resourceName: String,
        with fileProgress: Progress,
    ) {
        owsFailDebug("Unexpectedly received a file on old device \(resourceName)")
    }

    func session(
        _ session: DeviceTransferSession,
        didFinishReceivingResourceWithName resourceName: String,
        at localURL: URL?,
        withError error: Swift.Error?,
    ) {
        owsFailDebug("Unexpectedly received a file on old device \(resourceName)")
    }

    func session(
        _ session: DeviceTransferSession,
        didReceiveCertificates certificates: [Any]?,
        certificateHandler: @escaping (Bool) -> Void,
    ) {
        var certificateIsTrusted = false

        defer {
            certificateHandler(certificateIsTrusted)
            if !certificateIsTrusted {
                self.failTransfer(DeviceTransfer.Error.certificateMismatch, "the received certificate did not match the expected certificate")
            }
        }

        // Verify the received certificate matches the expected certificate.
        guard let certificate = certificates?.first else {
            owsFailDebug("new connection did not provide any certificate")
            return
        }

        let certificateData = SecCertificateCopyData(certificate as! SecCertificate) as Data

        // Verify the received certificate matches the expected certificate.
        // Reject any connections where we can't compute the certificate hash
        let certificateHash = Data(SHA256.hash(data: certificateData))

        // Reject any connections where the certificate doesn't match the expected certificate
        guard
            let expectedCertificateHash,
            expectedCertificateHash.ows_constantTimeIsEqual(to: certificateHash)
        else {
            return owsFailDebug("connection from known peer \(session.remotePeerId) using unexpected certificate")
        }
        Logger.info("Successfully verified new device certificate \(session.remotePeerId)")
        certificateIsTrusted = true
    }

    // MANIFEST

    func buildManifest() throws -> DeviceTransferProtoManifest {
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

        var path = path.replacingOccurrences(of: DeviceTransfer.Constants.appSharedDataDirectory.path, with: "")
        if path.starts(with: "/") { path.removeFirst() }
        return path
    }

    @MainActor
    private func sendManifest(manifest: DeviceTransferProtoManifest, session: DeviceTransferSession) async throws {
        Logger.info("Sending manifest to new device.")

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

        try await session.sendResource(
            url: manifestFileURL,
            name: DeviceTransfer.Constants.manifestIdentifier,
            progressBlock: { _ in },
        )

        Logger.info("Successfully sent manifest to new device.")

        transferredFileIds.update {
            $0.append(DeviceTransfer.Constants.manifestIdentifier)
        }
        throughputMonitor?.start()
    }
}
