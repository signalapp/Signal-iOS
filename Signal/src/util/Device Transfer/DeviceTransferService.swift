//
//  Copyright (c) 2020 Open Whisper Systems. All rights reserved.
//

import Foundation
import MultipeerConnectivity
import PromiseKit

protocol DeviceTransferServiceObserver: class {
    func deviceTransferServiceDiscoveredNewDevice(peerId: MCPeerID, discoveryInfo: [String: String]?)

    func deviceTransferServiceDidStartTransfer(progress: Progress)
    func deviceTransferServiceDidEndTransfer(error: DeviceTransferService.Error?)
}

class DeviceTransferService: NSObject {
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
            newDeviceCertificateHash: Data?,
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

    private let serialQueue = DispatchQueue(label: "DeviceTransferService")
    private var _transferState: TransferState = .idle
    fileprivate var transferState: TransferState {
        set { serialQueue.sync { _transferState = newValue } }
        get { serialQueue.sync { _transferState } }
    }

    var tsAccountManager: TSAccountManager { .sharedInstance() }
    var databaseStorage: SDSDatabaseStorage { .shared }
    var sleepManager: DeviceSleepManager { .sharedInstance }

    fileprivate static let pendingTransferDirectory = OWSFileSystem.appSharedDataDirectoryPath() + "/transfer/"
    fileprivate static let pendingTransferFilesDirectory = OWSFileSystem.appSharedDataDirectoryPath() + "/transfer/files/"

    private static let manifestIdentifier = "manifest"
    private static let databaseIdentifier = "database"
    private static let databaseWALIdentifier = "database-wal"

    private static let newDeviceServiceIdentifier = "sgnl-new-device"

    private let pendingRestoreKey = "DeviceTransferHasPendingRestore"
    private var hasPendingRestore: Bool {
        get { CurrentAppContext().appUserDefaults().bool(forKey: pendingRestoreKey) }
        set { CurrentAppContext().appUserDefaults().set(newValue, forKey: pendingRestoreKey) }
    }

    fileprivate var identity: SecIdentity?
    fileprivate var session: MCSession? {
        didSet {
            if let oldValue = oldValue {
                sleepManager.removeBlock(blockObject: oldValue)
            }

            if let session = session {
                sleepManager.addBlock(blockObject: session)
            }
        }
    }
    fileprivate lazy var peerId = MCPeerID(displayName: UUID().uuidString)

    private lazy var newDeviceServiceBrowser: MCNearbyServiceBrowser = {
        let browser = MCNearbyServiceBrowser(
            peer: peerId,
            serviceType: DeviceTransferService.newDeviceServiceIdentifier
        )
        browser.delegate = self
        return browser
    }()

    private lazy var newDeviceServiceAdvertiser: MCNearbyServiceAdvertiser = {
        let advertiser = MCNearbyServiceAdvertiser(
            peer: peerId, discoveryInfo: nil,
            serviceType: DeviceTransferService.newDeviceServiceIdentifier
        )
        advertiser.delegate = self
        return advertiser
    }()

    static var shared: DeviceTransferService {
        return AppEnvironment.shared.deviceTransferService
    }

    // MARK: -

    override init() {
        super.init()

        SwiftSingletons.register(self)

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(didEnterBackground),
            name: .OWSApplicationDidEnterBackground,
            object: nil
        )

        AppReadiness.runNowOrWhenAppWillBecomeReady { self.launchCleanup() }
    }

    // MARK: - New Device

    enum TransferMode: String {
        case linked
        case primary
    }

    func startAcceptingTransfersFromOldDevices(mode: TransferMode) throws -> URL {
        // Create an identity to use for our TLS sessions, the old device
        // will verify this identity via the QR code
        let identity = try SelfSignedIdentity.create(name: "IncomingDeviceTransfer", validForDays: 1)
        self.identity = identity

        let session = MCSession(peer: peerId, securityIdentity: [identity], encryptionPreference: .required)
        session.delegate = self
        self.session = session

        newDeviceServiceAdvertiser.startAdvertisingPeer()

        return try urlForTransfer(mode: mode)
    }

    func stopAcceptingTransfersFromOldDevices() {
        newDeviceServiceAdvertiser.stopAdvertisingPeer()
    }

    func cancelTransferFromOldDevice() {
        AssertIsOnMainThread()

        guard case .incoming = transferState else { return }

        notifyObservers { $0.deviceTransferServiceDidEndTransfer(error: .cancel) }

        stopTransfer()
    }

    // MARK: - Old Device

    func startListeningForNewDevices() {
        newDeviceServiceBrowser.startBrowsingForPeers()
    }

    func stopListeningForNewDevices() {
        newDeviceServiceBrowser.stopBrowsingForPeers()
    }

    func transferAccountToNewDevice(with peerId: MCPeerID, certificateHash: Data?) throws {
        cancelTransferToNewDevice()

        // Marking the transfer as "in progress" does a few things, most notably it:
        //   * prevents any WAL checkpoints while the transfer is in progress
        //   * causes the device to behave is if it's not registered
        tsAccountManager.isTransferInProgress = true

        defer {
            // If we failed to start the transfer, clear the transfer in progress flag
            if case .idle = transferState { tsAccountManager.isTransferInProgress = false }
        }

        let manifest = try buildManifest()
        let progress = Progress(totalUnitCount: Int64(manifest.estimatedTotalSize))

        // We don't actually need to generate an identity for the old device, the new device
        // doesn't verify this information. We do it anyway, for consistency.
        let identity = try SelfSignedIdentity.create(name: "OutgoingDeviceTransfer", validForDays: 1)
        self.identity = identity

        let session = MCSession(peer: self.peerId, securityIdentity: [identity], encryptionPreference: .required)
        session.delegate = self
        self.session = session

        transferState = .outgoing(
            newDevicePeerId: peerId,
            newDeviceCertificateHash: certificateHash,
            manifest: manifest,
            transferredFileIds: [],
            progress: progress
        )

        newDeviceServiceBrowser.invitePeer(peerId, to: session, withContext: nil, timeout: 30)
    }

    func cancelTransferToNewDevice() {
        guard case .outgoing = transferState else { return }

        notifyObservers { $0.deviceTransferServiceDidEndTransfer(error: .cancel) }

        stopTransfer()
    }

    // MARK: - URL

    private static let currentTransferVersion = 1

    private static let versionKey = "version"
    private static let peerIdKey = "peerId"
    private static let certificateHashKey = "certificateHash"
    private static let transferModeKey = "transferMode"

    private func urlForTransfer(mode: TransferMode) throws -> URL {
        guard let identity = identity else {
            throw OWSAssertionError("unexpectedly missing identity")
        }

        var components = URLComponents()
        components.scheme = kURLSchemeSGNLKey
        components.path = kURLHostTransferPrefix

        guard let base64CertificateHash = try identity.computeCertificateHash().base64EncodedString().encodeURIComponent else {
            throw OWSAssertionError("failed to get base64 certificate hash")
        }

        guard let base64PeerId = NSKeyedArchiver.archivedData(withRootObject: peerId).base64EncodedString().encodeURIComponent else {
            throw OWSAssertionError("failed to get base64 peerId")
        }

        let queryItems = [
            DeviceTransferService.versionKey: String(DeviceTransferService.currentTransferVersion),
            DeviceTransferService.transferModeKey: mode.rawValue,
            DeviceTransferService.certificateHashKey: base64CertificateHash,
            DeviceTransferService.peerIdKey: base64PeerId
        ]

        components.queryItems = queryItems.map { URLQueryItem(name: $0.key, value: $0.value) }

        return components.url!
    }

    func parseTrasnsferURL(_ url: URL) throws -> (peerId: MCPeerID, certificateHash: Data) {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false), let queryItems = components.queryItems else {
            throw OWSAssertionError("Invalid url")
        }

        let queryItemsDictionary = [String: String](uniqueKeysWithValues: queryItems.compactMap { item in
            guard let value = item.value else { return nil }
            return (item.name, value)
        })

        guard let version = queryItemsDictionary[DeviceTransferService.versionKey],
            Int(version) == DeviceTransferService.currentTransferVersion else {
            throw Error.unsupportedVersion
        }

        let currentMode: TransferMode = tsAccountManager.isPrimaryDevice ? .primary : .linked

        guard let rawMode = queryItemsDictionary[DeviceTransferService.transferModeKey],
            rawMode == currentMode.rawValue else {
            throw Error.modeMismatch
        }

        guard let base64CertificateHash = queryItemsDictionary[DeviceTransferService.certificateHashKey],
            let uriDecodedHash = base64CertificateHash.removingPercentEncoding,
            let certificateHash = Data(base64Encoded: uriDecodedHash) else {
                throw OWSAssertionError("failed to decode certificate hash")
        }

        guard let base64PeerId = queryItemsDictionary[DeviceTransferService.peerIdKey],
            let uriDecodedPeerId = base64PeerId.removingPercentEncoding,
            let peerIdData = Data(base64Encoded: uriDecodedPeerId),
            let peerId = try NSKeyedUnarchiver.unarchiveTopLevelObjectWithData(peerIdData) as? MCPeerID else {
                throw OWSAssertionError("failed to decode MCPeerId")
        }

        return (peerId, certificateHash)
    }

    // MARK: - Observation

    private var observers = [Weak<DeviceTransferServiceObserver>]()
    func addObserver(_ observer: DeviceTransferServiceObserver) {
        observers.append(Weak(value: observer))
    }

    func removeObserver(_ observer: DeviceTransferServiceObserver) {
        observers.removeAll { return $0.value === observer }
    }

    func notifyObservers(_ block: @escaping (DeviceTransferServiceObserver) -> Void) {
        DispatchMainThreadSafe {
            self.observers.compactMap { $0.value }.forEach { block($0) }
        }
    }

    // MARK: - Manifest

    private func buildManifest() throws -> DeviceTransferProtoManifest {
        let appSharedDirectory = OWSFileSystem.appSharedDataDirectoryPath()
        let manifestBuilder = DeviceTransferProtoManifest.builder(grdbSchemaVersion: UInt64(GRDBSchemaMigrator.grdbSchemaVersionLatest))
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
                    relativePath: file.replacingOccurrences(of: appSharedDirectory, with: ""),
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
                    relativePath: file.replacingOccurrences(of: appSharedDirectory, with: ""),
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

        var filesToTransfer = [String]()

        filesToTransfer += try OWSFileSystem.allFiles(inDirectoryRecursive: appSharedDirectory + "/Attachments")
        filesToTransfer += try OWSFileSystem.allFiles(inDirectoryRecursive: appSharedDirectory + "/ProfileAvatars")
        filesToTransfer += try OWSFileSystem.allFiles(inDirectoryRecursive: appSharedDirectory + "/StickerManager")

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
                relativePath: file.replacingOccurrences(of: appSharedDirectory, with: ""),
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

    private func handleReceivedManifest(at localURL: URL, fromPeer peerId: MCPeerID) {
        guard case .idle = transferState else {
            return owsFailDebug("Received manifest in unexpected state \(transferState)")
        }
        guard let fileSize = OWSFileSystem.fileSize(of: localURL) else {
            return owsFailDebug("Missing manifest file.")
        }
        guard fileSize.uint64Value < 1024 * 1024 else {
            return owsFailDebug("Unexpectedly received a very large manifest \(fileSize)")
        }
        guard let data = try? Data(contentsOf: localURL) else {
            return owsFailDebug("Failed to read manifest data")
        }
        guard let manifest = try? DeviceTransferProtoManifest.parseData(data) else {
            return owsFailDebug("Failed to parse manifest proto")
        }
        guard !tsAccountManager.isRegistered else {
            return owsFailDebug("Ignoring incoming transfer to a registered device")
        }

        resetTransferDirectory()

        guard OWSFileSystem.moveFilePath(
            localURL.path,
            toFilePath: DeviceTransferService.pendingTransferDirectory + DeviceTransferService.manifestIdentifier
        ) else {
            return owsFailDebug("Failed to move manifest into place")
        }

        let progress = Progress(totalUnitCount: Int64(manifest.estimatedTotalSize))

        transferState = .incoming(
            oldDevicePeerId: peerId,
            manifest: manifest,
            receivedFileIds: [DeviceTransferService.manifestIdentifier],
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
            forPath: DeviceTransferService.pendingTransferDirectory
        ) else {
            return owsFailDebug("failed to calculate available disk space")
        }

        guard let freeSpaceInBytes = fileSystemAttributes[.systemFreeSize] as? UInt64, freeSpaceInBytes > manifest.estimatedTotalSize else {
            return self.failTransfer(.notEnoughSpace, "not enough free space to receive transfer")
        }
    }

    private func sendManifest() throws -> Promise<Void> {
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
        let manifestFileURL = URL(fileURLWithPath: DeviceTransferService.pendingTransferDirectory + DeviceTransferService.manifestIdentifier)
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

    private func readManifestFromTransferDirectory() -> DeviceTransferProtoManifest? {
        let manifestPath = DeviceTransferService.pendingTransferDirectory + DeviceTransferService.manifestIdentifier
        guard OWSFileSystem.fileOrFolderExists(atPath: manifestPath) else { return nil }
        guard let manifestData = try? Data(contentsOf: URL(fileURLWithPath: manifestPath)) else { return nil }
        return try? DeviceTransferProtoManifest.parseData(manifestData)
    }

    // MARK: -

    private func failTransfer(_ error: Error, _ reason: String) {
        owsFailDebug(reason)

        stopTransfer()

        notifyObservers { $0.deviceTransferServiceDidEndTransfer(error: error) }
    }

    private func stopTransfer() {
        switch transferState {
        case .outgoing:
            FileTransferOperation.operationQueue.cancelAllOperations()
        case .incoming:
            newDeviceServiceAdvertiser.stopAdvertisingPeer()
        case .idle:
            break
        }

        session?.disconnect()
        session = nil
        identity = nil

        tsAccountManager.isTransferInProgress = false
        transferState = .idle

        stopThroughputCalculation()
    }

    // MARK: - Restoration

    private func verifyTransferCompletedSuccessfully(receivedFileIds: [String]) -> Bool {
        guard let manifest = readManifestFromTransferDirectory() else {
            owsFailDebug("Missing manifest file")
            return false
        }

        // Check that there aren't any files that we were
        // expecting that are missing.
        for file in manifest.files {
            guard receivedFileIds.contains(file.identifier) else {
                owsFailDebug("did not receive file \(file.identifier)")
                return false
            }
            guard OWSFileSystem.fileOrFolderExists(
                atPath: DeviceTransferService.pendingTransferFilesDirectory + file.identifier
            ) else {
                owsFailDebug("Missing file \(file.identifier)")
                return false
            }
        }

        // Check that the appropriate database files were received
        guard let database = manifest.database else {
            owsFailDebug("missing database proto")
            return false
        }

        guard database.key.count == kSQLCipherKeySpecLength else {
            owsFailDebug("incorrect database key length")
            return false
        }

        guard receivedFileIds.contains(DeviceTransferService.databaseIdentifier) else {
            owsFailDebug("did not receive database file")
            return false
        }

        guard OWSFileSystem.fileOrFolderExists(
            atPath: DeviceTransferService.pendingTransferFilesDirectory + DeviceTransferService.databaseIdentifier
        ) else {
            owsFailDebug("missing database file")
            return false
        }

        guard receivedFileIds.contains(DeviceTransferService.databaseWALIdentifier) else {
            owsFailDebug("did not receive database wal file")
            return false
        }

        guard OWSFileSystem.fileOrFolderExists(
            atPath: DeviceTransferService.pendingTransferFilesDirectory + DeviceTransferService.databaseWALIdentifier
        ) else {
            owsFailDebug("missing database wal file")
            return false
        }

        return true
    }

    private func restoreTransferredData() {
        guard hasPendingRestore else {
            return owsFailDebug("Cannot restore data when there was no pending restore")
        }

        guard let manifest = readManifestFromTransferDirectory() else {
            return owsFailDebug("Unexpectedly tried to restore data when there is no valid manifest")
        }

        guard let database = manifest.database else {
            return owsFailDebug("manifest is missing database")
        }

        do {
            try GRDBDatabaseStorageAdapter.keyspec.store(data: database.key)
        } catch {
            return owsFailDebug("failed to restore database key")
        }

        for userDefault in manifest.standardDefaults {
            UserDefaults.standard.set(
                NSKeyedUnarchiver.unarchiveObject(with: userDefault.encodedValue),
                forKey: userDefault.key
            )
        }

        for userDefault in manifest.appDefaults {
            CurrentAppContext().appUserDefaults().set(
                NSKeyedUnarchiver.unarchiveObject(with: userDefault.encodedValue),
                forKey: userDefault.key
            )
        }

        for file in manifest.files + [database.database, database.wal] {
            let fileIsAwaitingRestoration = OWSFileSystem.fileOrFolderExists(
                atPath: DeviceTransferService.pendingTransferFilesDirectory + file.identifier
            )
            let fileWasAlreadyRestored = OWSFileSystem.fileOrFolderExists(
                atPath: OWSFileSystem.appSharedDataDirectoryPath() + file.relativePath
            )

            if fileIsAwaitingRestoration {
                OWSFileSystem.deleteFileIfExists(OWSFileSystem.appSharedDataDirectoryPath() + file.relativePath)

                let pathComponents = file.relativePath.components(separatedBy: "/")
                var path = ""
                for component in pathComponents where !component.isEmpty {
                    guard component != pathComponents.last else { break }
                    path += "/" + component
                    OWSFileSystem.ensureDirectoryExists(OWSFileSystem.appSharedDataDirectoryPath() + path)
                }

                OWSFileSystem.moveFilePath(
                    DeviceTransferService.pendingTransferFilesDirectory + file.identifier,
                    toFilePath: OWSFileSystem.appSharedDataDirectoryPath() + file.relativePath
                )
            } else if fileWasAlreadyRestored {
                Logger.info("Skipping restoration of file that was already restored: \(file.identifier)")
            } else {
                owsFailDebug("unable to restore file that is missing")
            }
        }

        resetTransferDirectory()

        DispatchMainThreadSafe {
            self.databaseStorage.reload()
            self.tsAccountManager.wasTransferred = false
            self.tsAccountManager.isTransferInProgress = false
            SignalApp.shared().showConversationSplitView()
        }
    }

    private func resetTransferDirectory() {
        do {
            if OWSFileSystem.fileOrFolderExists(atPath: DeviceTransferService.pendingTransferDirectory) {
                try FileManager.default.removeItem(atPath: DeviceTransferService.pendingTransferDirectory)
            }
        } catch {
            owsFailDebug("Failed to delete existing transfer directory \(error)")
        }
        OWSFileSystem.ensureDirectoryExists(DeviceTransferService.pendingTransferDirectory)

        // If we had a pending restore, we no longer do.
        hasPendingRestore = false
    }

    private func launchCleanup() {
        tsAccountManager.isTransferInProgress = false
        if hasPendingRestore && !tsAccountManager.isRegistered {
            restoreTransferredData()
        } else {
            resetTransferDirectory()
        }
    }

    // MARK: -

    @objc func didEnterBackground() {
        if transferState != .idle {
            notifyObservers { $0.deviceTransferServiceDidEndTransfer(error: .cancel) }
        }

        stopTransfer()
    }

    // MARK: - Sending

    private func sendAllFiles() throws {
        guard case .outgoing(let newDevicePeerId, _, let manifest, _, _) = transferState else {
            throw OWSAssertionError("Attempted to send files while no transfer in progress")
        }

        guard let database = manifest.database else {
            throw OWSAssertionError("Manifest unexpectedly missing database")
        }

        var promises = [Promise<Void>]()

        let (databasePromise, databaseResolver) = Promise<Void>.pending()
        promises.append(databasePromise)

        // Transfer the database files within a write transaction so we can be confident
        // they aren't mutated during the transfer. We add them to the queue with high
        // priority so they transfer ASAP, so we only have to block the database for a
        // minimal amount of time.
        databaseStorage.asyncWrite { _ in
            let dbOperation = FileTransferOperation(file: database.database)
            dbOperation.queuePriority = .high
            FileTransferOperation.operationQueue.addOperation(dbOperation)

            let walOperation = FileTransferOperation(file: database.wal)
            walOperation.queuePriority = .high
            FileTransferOperation.operationQueue.addOperation(walOperation)

            when(fulfilled: [dbOperation.promise, walOperation.promise]).done {
                databaseResolver.fulfill(())
            }.catch { error in
                databaseResolver.reject(error)
            }.retainUntilComplete()
        }

        for file in manifest.files {
            let operation = FileTransferOperation(file: file)
            FileTransferOperation.operationQueue.addOperation(operation)

            promises.append(operation.promise)
        }

        when(fulfilled: promises).done {
            if !FeatureFlags.deviceTransferThrowAway {
                self.tsAccountManager.wasTransferred = true
            }
            try self.sendDoneMessage(to: newDevicePeerId)
        }.catch { error in
            self.failTransfer(.assertion, "\(error)")
        }.retainUntilComplete()
    }

    private static let doneMessage = "Transfer Complete".data(using: .utf8)!
    private func sendDoneMessage(to peerId: MCPeerID) throws {
        Logger.info("Sending done message")

        guard let session = session else {
            throw OWSAssertionError("attempted to send done message without an available session")
        }

        try session.send(DeviceTransferService.doneMessage, toPeers: [peerId], with: .reliable)
    }

    // MARK: - Throughput

    private var previouslyCompletedBytes: Double = 0
    private var throughputTimer: Timer?
    private func startThroughputCalculation() {
        guard Thread.isMainThread else {
            DispatchQueue.main.async { self.startThroughputCalculation() }
            return
        }

        // We can only manage throughput + estimated time on the `Progress` object
        // in iOS 11 and later. Since we're imminiently dropping support for iOS 10,
        // don't bother doing this in any other way for old devices. iOS 10 devices
        // will only see a percentage progress without any estimated time.
        guard #available(iOS 11, *) else { return }

        stopThroughputCalculation()

        guard let progress: Progress = {
            switch transferState {
            case .incoming(_, _, _, let progress):
                return progress
            case .outgoing(_, _, _, _, let progress):
                return progress
            case .idle:
                owsFailDebug("Can't start throughput calculation while idle")
                return nil
            }
        }() else {
            return owsFailDebug("Can't start throughput calculations without progress")
        }

        previouslyCompletedBytes = Double(progress.totalUnitCount) * progress.fractionCompleted

        throughputTimer = WeakTimer.scheduledTimer(timeInterval: 1, target: self, userInfo: nil, repeats: true) { _ in
            let completedBytes = Double(progress.totalUnitCount) * progress.fractionCompleted
            let bytesOverLastSecond = completedBytes - self.previouslyCompletedBytes
            let remainingBytes = Double(progress.totalUnitCount) - completedBytes
            self.previouslyCompletedBytes = completedBytes

            if let averageThroughput = progress.throughput {
                // Give more weight to the existing average than the new value
                // to "smooth" changes in throughput and estimated time remaining.
                let newAverageThroughput = 0.2 * Double(bytesOverLastSecond) + 0.8 * Double(averageThroughput)
                progress.throughput = Int(newAverageThroughput)
                progress.estimatedTimeRemaining = remainingBytes / newAverageThroughput
            } else {
                progress.throughput = Int(bytesOverLastSecond)
                progress.estimatedTimeRemaining = remainingBytes / TimeInterval(bytesOverLastSecond)
            }

            self.logProgress(progress, remainingBytes: remainingBytes)
        }
        throughputTimer?.fire()
    }

    @available(iOS 11, *)
    private func logProgress(_ progress: Progress, remainingBytes: Double) {
        guard DebugFlags.deviceTransferVerboseProgressLogging else { return }

        var progressLog = String(format: "Transfer progress %0.2f%%", progress.fractionCompleted * 100)

        var remainingNumber = remainingBytes
        var remainingUnits = "b"
        if remainingNumber / 1024 >= 1 {
            remainingNumber /= 1024
            remainingUnits = "Kb"
        }
        if remainingNumber / 1024 >= 1 {
            remainingNumber /= 1024
            remainingUnits = "Mb"
        }
        if remainingNumber / 1024 >= 1 {
            remainingNumber /= 1024
            remainingUnits = "Gb"
        }

        progressLog += String(format: " / %0.2f %@ remaining", remainingNumber, remainingUnits)

        if let throughput = progress.throughput {
            var transferSpeed = Double(throughput) / 1024
            var transferUnits = "Kbps"
            if transferSpeed / 1024 >= 1 {
                transferSpeed /= 1024
                transferUnits = "Mbps"
            }

            progressLog += String(format: " / %0.2f %@", transferSpeed, transferUnits)
        }

        if let estimatedTime = progress.estimatedTimeRemaining, estimatedTime.isFinite {
            let formatter = DateComponentsFormatter()
            formatter.allowedUnits = [.hour, .minute, .second]
            formatter.unitsStyle = .full
            formatter.maximumUnitCount = 2
            formatter.includesApproximationPhrase = true
            formatter.includesTimeRemainingPhrase = true

            let formattedString = formatter.string(from: estimatedTime)!

            progressLog += " / \(formattedString)"
        }

        Logger.info(progressLog)
    }

    private func stopThroughputCalculation() {
        throughputTimer?.invalidate()
        throughputTimer = nil
        previouslyCompletedBytes = 0
    }
}

extension DeviceTransferService: MCNearbyServiceBrowserDelegate {
    func browser(_ browser: MCNearbyServiceBrowser, foundPeer newDevicePeerID: MCPeerID, withDiscoveryInfo info: [String: String]?) {
        Logger.info("Notifiying of discovered new device \(newDevicePeerID)")
        notifyObservers { $0.deviceTransferServiceDiscoveredNewDevice(peerId: newDevicePeerID, discoveryInfo: info) }
    }

    func browser(_ browser: MCNearbyServiceBrowser, lostPeer peerId: MCPeerID) {}
}

extension DeviceTransferService: MCNearbyServiceAdvertiserDelegate {
    func advertiser(
        _ advertiser: MCNearbyServiceAdvertiser,
        didReceiveInvitationFromPeer peerId: MCPeerID,
        withContext context: Data?,
        invitationHandler: @escaping (Bool, MCSession?) -> Void
    ) {
        Logger.info("Accepting invitation from old device \(peerId)")
        invitationHandler(true, session)
    }
}

extension DeviceTransferService: MCSessionDelegate {
    func session(_ session: MCSession, peer peerId: MCPeerID, didChange state: MCSessionState) {
        Logger.debug("Connection to \(peerId) did change: \(state.rawValue)")

        switch transferState {
        case .outgoing(let newDevicePeerId, _, _, let transferredFiles, let progress):
            // We only care about state changes for the device we're sending to.
            guard peerId == newDevicePeerId else { return }

            Logger.info("Connection to new device did change: \(state.rawValue)")

            switch state {
            case .connected:
                notifyObservers { $0.deviceTransferServiceDidStartTransfer(progress: progress) }

                // Only send the files if we haven't yet sent the manifest.
                guard !transferredFiles.contains(DeviceTransferService.manifestIdentifier) else { return }

                do {
                    try sendManifest().done {
                        try self.sendAllFiles()
                    }.catch { error in
                        self.failTransfer(.assertion, "Failed to send manifest to new device \(error)")
                    }
                } catch {
                    failTransfer(.assertion, "Failed to send manifest to new device \(error)")
                }
            case .connecting:
                break
            case .notConnected:
                failTransfer(.assertion, "Lost connection to new device")
            @unknown default:
                failTransfer(.assertion, "Unexpected connection state: \(state.rawValue)")
            }
        case .incoming(let oldDevicePeerId, _, _, _):
            // We only care about state changes for the device we're receiving from.
            guard peerId == oldDevicePeerId else { return }

            if state == .notConnected { failTransfer(.assertion, "Lost connection to old device") }
        case .idle:
            break
        }
    }

    func session(_ session: MCSession, didReceive data: Data, fromPeer peerId: MCPeerID) {
        switch transferState {
        case .idle:
            break
        case .outgoing(let newDevicePeerId, _, _, _, _):
            guard peerId == newDevicePeerId else {
                return owsFailDebug("Ignoring data from unexpected peer \(peerId)")
            }

            guard data == DeviceTransferService.doneMessage else {
                return failTransfer(.assertion, "Received unexpected data")
            }

            // Notify the UI that the transfer completed successfully.
            notifyObservers { $0.deviceTransferServiceDidEndTransfer(error: nil) }

            stopTransfer()

            // When the old device receives the done message from the new device,
            // it can be confident that the transfer has completed successfully and
            // clear out all data from this device. This will crash the app.
            if FeatureFlags.deviceTransferDestroyOldDevice {
                SignalApp.resetAppData()
            }

        case .incoming(let oldDevicePeerId, _, let receivedFileIds, _):
            guard peerId == oldDevicePeerId else {
                return owsFailDebug("Ignoring data from unexpected peer \(peerId)")
            }

            guard data == DeviceTransferService.doneMessage else {
                return failTransfer(.assertion, "Received unexpected data")
            }

            stopThroughputCalculation()

            // When the new device receives the done message from the old device,
            // it indicates that the old device thinks we should have received
            // everything at this point.

            guard verifyTransferCompletedSuccessfully(receivedFileIds: receivedFileIds) else {
                return failTransfer(.assertion, "transfer is missing data")
            }

            // Record that we have a pending restore, so even if the app exits
            // we can still know to restore the data that was transferred.
            hasPendingRestore = true

            // Try and notify the old device that we agree, everything is done.
            // At this point, we consider the transfer complete regardless of
            // whether or not this message is received by the old device. If the
            // old device misses this message (because the app crashes, etc.) it
            // will continue acting as if it is "unregistered", but it won't delete
            // all data because it doesn't know for sure if the data was safely
            // received by the new device.
            do {
                try sendDoneMessage(to: oldDevicePeerId)
            } catch {
                owsFailDebug("Failed to send done message to old device \(error)")
            }

            // Notify the UI that the transfer completed successfully.
            notifyObservers { $0.deviceTransferServiceDidEndTransfer(error: nil) }

            // Try and restore the received data. If for some reason the app exits
            // or crashes at this point, we will retry the restore when the app next
            // launches.
            restoreTransferredData()

            transferState = .idle
        }
    }

    func session(_ session: MCSession, didReceive stream: InputStream, withName streamName: String, fromPeer peerId: MCPeerID) {}

    func session(
        _ session: MCSession,
        didStartReceivingResourceWithName resourceName: String,
        fromPeer peerId: MCPeerID,
        with fileProgress: Progress
    ) {
        switch transferState {
        case .idle:
            guard resourceName == DeviceTransferService.manifestIdentifier else {
                return Logger.info("Ignoring unexpected incoming file \(resourceName)")
            }
        case .outgoing:
            owsFailDebug("Unexpectedly received a file on old device \(resourceName)")
        case .incoming(let oldDevicePeerId, let manifest, let receivedFileIds, let progress):
            guard peerId == oldDevicePeerId else {
                return owsFailDebug("Ignoring file from unexpected peer \(peerId)")
            }

            let nameComponents = resourceName.components(separatedBy: " ")

            guard let fileIdentifier = nameComponents.first, nameComponents.count == 2 else {
                return owsFailDebug("Received incorrectly formatted resourceName: \(resourceName)")
            }

            guard !receivedFileIds.contains(fileIdentifier) else {
                return Logger.info("Ignoring duplicate file: \(fileIdentifier)")
            }

            guard let file: DeviceTransferProtoFile = {
                switch fileIdentifier {
                case DeviceTransferService.databaseIdentifier:
                    return manifest.database?.database
                case DeviceTransferService.databaseWALIdentifier:
                    return manifest.database?.wal
                default:
                    return manifest.files.first(where: { $0.identifier == fileIdentifier })
                }
            }() else {
                return owsFailDebug("Received unexpected file on new device: \(fileIdentifier)")
            }

            Logger.info("Receiving file: \(file.identifier), estimatedSize: \(file.estimatedSize)")
            progress.addChild(fileProgress, withPendingUnitCount: Int64(file.estimatedSize))
        }
    }

    func session(
        _ session: MCSession,
        didFinishReceivingResourceWithName resourceName: String,
        fromPeer peerId: MCPeerID,
        at localURL: URL?,
        withError error: Swift.Error?
    ) {
        switch transferState {
        case .idle:
            guard resourceName == DeviceTransferService.manifestIdentifier else {
                return Logger.info("Ignoring unexpected incoming file \(resourceName)")
            }

            if let error = error {
                owsFailDebug("Failed to receive manifest \(error)")
            } else if let localURL = localURL {
                handleReceivedManifest(at: localURL, fromPeer: peerId)
            } else {
                owsFailDebug("Unexpectedly completed transfer of resource with no URL or error")
            }
        case .outgoing:
            owsFailDebug("Unexpectedly received a file on old device \(resourceName)")
        case .incoming(let oldDevicePeerId, let manifest, let receivedFileIds, _):
            guard peerId == oldDevicePeerId else {
                return owsFailDebug("Ignoring file from unexpected peer \(peerId)")
            }

            let nameComponents = resourceName.components(separatedBy: " ")

            guard let fileIdentifier = nameComponents.first, let fileHash = nameComponents.last, nameComponents.count == 2 else {
                return owsFailDebug("Received incorrectly formatted resourceName: \(resourceName)")
            }

            guard !receivedFileIds.contains(fileIdentifier) else {
                return Logger.info("Ignoring duplicate file: \(fileIdentifier)")
            }
            guard let file: DeviceTransferProtoFile = {
                switch fileIdentifier {
                case DeviceTransferService.databaseIdentifier:
                    return manifest.database?.database
                case DeviceTransferService.databaseWALIdentifier:
                    return manifest.database?.wal
                default:
                    return manifest.files.first(where: { $0.identifier == fileIdentifier })
                }
            }() else {
                return owsFailDebug("Received unexpected file on new device: \(fileIdentifier)")
            }

            if let error = error {
                failTransfer(.assertion, "Failed to receive file \(file.identifier) \(error)")
            } else if let localURL = localURL {
                OWSFileSystem.ensureDirectoryExists(DeviceTransferService.pendingTransferFilesDirectory)

                guard let computedHash = Cryptography.computeSHA256DigestOfFile(at: localURL) else {
                    return failTransfer(.assertion, "Failed to compute hash for \(file.identifier)")
                }

                guard computedHash.hexadecimalString == fileHash else {
                    return failTransfer(.assertion, "Received file with incorrect hash \(file.identifier)")
                }

                guard OWSFileSystem.moveFilePath(
                    localURL.path,
                    toFilePath: DeviceTransferService.pendingTransferFilesDirectory + file.identifier
                ) else {
                    return failTransfer(.assertion, "Failed to move file into place \(file.identifier)")
                }

                Logger.info("Received file: \(file.identifier)")
                transferState = transferState.appendingFileId(file.identifier)
            } else {
                owsFailDebug("Unexpectedly completed transfer of resource with no URL or error")
            }
        }
    }

    func session(
        _ session: MCSession,
        didReceiveCertificate certificates: [Any]?,
        fromPeer peerId: MCPeerID,
        certificateHandler: @escaping (Bool) -> Void
    ) {
        var certificateIsTrusted = false

        defer {
            certificateHandler(certificateIsTrusted)
            if !certificateIsTrusted {
                self.failTransfer(.certificateMismatch, "the received certificate did not match the expected certificate")
            }
        }

        guard case .outgoing(let newDevicePeerId, let newDeviceCertificateHash, _, _, _) = transferState else {
            // Accept all connections if we're not doing an outgoing transfer AND we aren't yet registered.
            // Registered devices can only ever perform outgoing transfers.
            certificateIsTrusted = !tsAccountManager.isRegistered
            return
        }

        // Reject any connections from unexpected devices.
        guard peerId == newDevicePeerId else { return }

        // Verify the received certificate matches the expected certificate.
        if let expectedCertificateHash = newDeviceCertificateHash {
            // Reject any connections that don't expclitly declare a certificate
            guard let certificate = certificates?.first else {
                return owsFailDebug("new connection did not provide any certificate")
            }

            let certificateData = SecCertificateCopyData(certificate as! SecCertificate) as Data

            // Reject any connections where we can't compute the certificate hash
            guard let certificateHash = Cryptography.computeSHA256Digest(certificateData) else {
                return owsFailDebug("failed to calculate certificate hash")
            }

            // Reject any connections where the certificate doesn't match the expected certificate
            guard expectedCertificateHash.ows_constantTimeIsEqual(to: certificateHash) else {
                return owsFailDebug("connection from known peer \(peerId) using unexpected certificate")
            }

            Logger.info("Successfully verified new device certificate \(peerId)")

            certificateIsTrusted = true
        } else {
            // TODO: This path is useful for testing, but can probably be eliminated once the UI is built out
            Logger.info("Proceeding without certificate verification, because outgoing transfer was not started with a certificate hash")
            certificateIsTrusted = true
        }
    }
}

private class FileTransferOperation: OWSOperation {

    let file: DeviceTransferProtoFile
    var service: DeviceTransferService { .shared }

    let promise: Promise<Void>
    private let resolver: Resolver<Void>

    fileprivate static let operationQueue: OperationQueue = {
        let queue = OperationQueue()
        queue.name = logTag()
        queue.maxConcurrentOperationCount = 1
        return queue
    }()

    fileprivate init(file: DeviceTransferProtoFile) {
        self.file = file
        (self.promise, self.resolver) = Promise<Void>.pending()
        super.init()
        self.remainingRetries = 4
    }

    // MARK: - Run

    override func didSucceed() {
        super.didSucceed()
        resolver.fulfill(())
    }

    override func didFail(error: Error) {
        super.didFail(error: error)
        resolver.reject(error)
    }

    override public func run() {
        Logger.info("Transferring file: \(file.identifier), estimatedSize: \(file.estimatedSize)")

        DispatchQueue.global().async { self.transferFile() }
    }

    private func transferFile() {
        guard case .outgoing(let newDevicePeerId, _, _, let transferredFiles, let progress) = service.transferState else {
            return reportError(OWSAssertionError("Tried to transfer file while in unexpected state: \(service.transferState)"))
        }

        guard let session = service.session else {
            return reportError(OWSAssertionError("Tried to transfer file with no active session"))
        }

        guard !transferredFiles.contains(file.identifier) else {
            Logger.info("File was already transferred, skipping")
            return reportSuccess()
        }

        let url = URL(fileURLWithPath: OWSFileSystem.appSharedDataDirectoryPath() + file.relativePath)

        guard let sha256Digest = Cryptography.computeSHA256DigestOfFile(at: url) else {
            return reportError(OWSAssertionError("Failed to calculate sha256 for file"))
        }

        guard let fileProgress = session.sendResource(
            at: url,
            withName: file.identifier + " " + sha256Digest.hexadecimalString,
            toPeer: newDevicePeerId,
            withCompletionHandler: { [weak self] error in
                guard let self = self else { return }

                if let error = error {
                    self.reportError(OWSAssertionError("Transferring file \(self.file.identifier) failed \(error)"))
                } else {
                    Logger.info("Transferring file \(self.file.identifier) complete")
                    self.service.transferState = self.service.transferState.appendingFileId(self.file.identifier)
                    self.reportSuccess()
                }
            }
        ) else {
            return reportError(OWSAssertionError("Transfer of file failed \(file.identifier)"))
        }

        progress.addChild(fileProgress, withPendingUnitCount: Int64(file.estimatedSize))
    }
}
