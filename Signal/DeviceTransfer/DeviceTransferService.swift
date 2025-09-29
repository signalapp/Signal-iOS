//
// Copyright 2020 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import CryptoKit
import Foundation
import MultipeerConnectivity
import SignalServiceKit

protocol DeviceTransferServiceObserver: AnyObject {
    func deviceTransferServiceDiscoveredNewDevice(peerId: MCPeerID, discoveryInfo: [String: String]?)

    func deviceTransferServiceDidStartTransfer(progress: Progress)
    func deviceTransferServiceDidEndTransfer(error: DeviceTransferService.Error?)

    func deviceTransferServiceDidRequestAppRelaunch()
}

///
/// The following service is used to facilitate users in transferring their account from
/// an old device (OD) to a new device (ND) using MultipeerConnectivity. The general steps
/// of the process follow the following flow:
///
/// 1) As you begin setting up a new device (ND), you are asked if you want to transfer data
///    from an old device (OD). This happens *after* the SMS code and reg lock pin are provided,
///    but (importantly) before the service replaces your old account. Accounts are identified
///    by the service as being eligible for transfer by setting the "transfer" capability.
/// 2) In order to notify potential ODs on the network, the ND will begin advertising a
///    “transfer service” using Bonjour. Nearby ODs will be readily browsing for this service,
///     but not establishing any connections until the user takes action. The ND will actively
///     attempt to connect to any other “transfer service” it finds. MC will under-the-hood
///     determine whether it’s best to use peer-to-peer Wi-Fi, Bluetooth, or infrastructure Wi-Fi
/// 3) In order to prepare for a session from the OD, the ND will generate an RSA 2048 private
///    key and self-signed public certificate (used for DTLS). It will then present a QR code
///    that contains:
///      a. The transfer version, so we can eliminate the need for a lot of backwards compatibility
///      b. The MC Peer identifier (an opaque blob of data that represents the ND, that the
///         OD can use to determine what device to connect to)
///      c. A sha256 hash of the public certificate, so we can verify we're connected to
///         the appropriate ND
///      d. A mode flag indicating whether we're expecting to transfer from a primary device
///         or a linked device.
/// 4) On your OD, you will accept the prompt in the Signal app to enter transfer mode.
///    A QR scanner will be presented to you.
/// 5) When the OD scans the QR code presented on the ND, it will:
///      a. Attempt to open an encrypted (DTLS) session with the specified MC session identifier
///      b. Validate the certificate for the connection exactly matches the certificate scanned from the ND
///      c. Start locally behaving as if it is unregistered, without actually unregistering from the
///         service (to prevent two devices registered with the same number)
///      d. Send a manifest to the ND that outlines a list of all the files it should expect, including:
///          i. The SQLCipher DB key
///          ii. The sqlite database file (with no additional encryption beyond SQLCipher)
///          iii. All attachment files stored on the device
///          iv. The user preference dictionary (user defaults)
///      e. Start transferring all the files to the new device
///  6) When all data has been transferred successfully,
///      a. the OD will:
///          i. Flag that it was transferred, it will now remain unregistered regardless of what
///             happens on the ND.
///          ii. Send a "done" message to the ND, to notify that it thinks it's done
///          iii. Wait for a "done" message from the ND – if received, all local data will be deleted.
///      b. the ND will, upon receipt of the "done" message:
///          i. Verify all data that was expected to be received was received
///          ii. Mark itself as pending restore
///          iii. Notify the ND that it is "done" and it's safe to self-destruct
///          iv. Move all the received files into place, set the new database key, etc.
///          v. Hot-swap the new database into place and present the conversation list
///
final class DeviceTransferService: NSObject {

    static let appSharedDataDirectory = URL(fileURLWithPath: OWSFileSystem.appSharedDataDirectoryPath())
    static let pendingTransferDirectory = URL(fileURLWithPath: "transfer", isDirectory: true, relativeTo: appSharedDataDirectory)
    static let pendingTransferFilesDirectory = URL(fileURLWithPath: "files", isDirectory: true, relativeTo: pendingTransferDirectory)

    static let manifestIdentifier = "manifest"
    static let databaseIdentifier = "database"
    static let databaseWALIdentifier = "database-wal"

    static let missingFileData = Data("Missing File".utf8)
    static let missingFileHash = Data(SHA256.hash(data: missingFileData))

    // This must also be updated in the info.plist
    private static let newDeviceServiceIdentifier = "sgnl-new-device"

    private let serialQueue = DispatchQueue(label: "org.signal.device-transfer")
    private var _transferState: TransferState = .idle
    var transferState: TransferState {
        get { serialQueue.sync { _transferState } }
        set { serialQueue.sync { _transferState = newValue } }
    }

    private let sleepBlockObject = DeviceSleepBlockObject(blockReason: "device transfer")

    private(set) var identity: SecIdentity?
    private(set) var session: MCSession?
    private(set) lazy var peerId = MCPeerID(displayName: UUID().uuidString)

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

    // MARK: -

    let appReadiness: AppReadiness
    let deviceSleepManager: DeviceSleepManagerImpl
    let keychainStorage: any KeychainStorage

    init(appReadiness: AppReadiness, deviceSleepManager: DeviceSleepManagerImpl, keychainStorage: any KeychainStorage) {
        self.appReadiness = appReadiness
        self.deviceSleepManager = deviceSleepManager
        self.keychainStorage = keychainStorage

        super.init()

        SwiftSingletons.register(self)

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(didEnterBackground),
            name: .OWSApplicationDidEnterBackground,
            object: nil
        )
    }

    // MARK: - New Device

    func startAcceptingTransfersFromOldDevices(mode: TransferMode) throws -> URL {
        // Create an identity to use for our TLS sessions, the old device
        // will verify this identity via the QR code
        let identity = try SelfSignedIdentity.create(name: "IncomingDeviceTransfer", validForDays: 1)
        self.identity = identity

        let session = MCSession(peer: peerId, securityIdentity: [identity], encryptionPreference: .required)
        session.delegate = self
        self.session = session

        Task {
            await self.deviceSleepManager.addBlock(blockObject: sleepBlockObject)
        }

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

    func transferAccountToNewDevice(with peerId: MCPeerID, certificateHash: Data) throws {
        cancelTransferToNewDevice()

        // Marking the transfer as "in progress" does a few things, most notably it:
        //   * prevents any WAL checkpoints while the transfer is in progress
        //   * causes the device to behave is if it's not registered
        DependenciesBridge.shared.db.write { tx in
            DependenciesBridge.shared.registrationStateChangeManager.setIsTransferInProgress(tx: tx)
        }

        defer {
            // If we failed to start the transfer, clear the transfer in progress flag
            if case .idle = transferState {
                DependenciesBridge.shared.db.write { tx in
                    DependenciesBridge.shared.registrationStateChangeManager.setIsTransferComplete(
                        sendStateUpdateNotification: true,
                        tx: tx
                    )
                }
            }
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

        Task {
            await self.deviceSleepManager.addBlock(blockObject: sleepBlockObject)
        }

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

    // MARK: -

    func failTransfer(_ error: Error, _ reason: String) {
        Logger.error("Failed transfer \(reason)")

        stopTransfer()

        notifyObservers { $0.deviceTransferServiceDidEndTransfer(error: error) }
    }

    func stopTransfer(notifyRegState: Bool = true) {
        switch transferState {
        case .outgoing:
            sendTask?.cancel()
        case .incoming:
            newDeviceServiceAdvertiser.stopAdvertisingPeer()
        case .idle:
            break
        }

        session?.disconnect()
        session = nil
        identity = nil

        Task {
            await self.deviceSleepManager.removeBlock(blockObject: sleepBlockObject)
        }

        // It is possible that we get here because the app was backgrounded
        // after a failed launch. In that case, `tsAccountManager` will not be
        // available, and setting this will crash. It'd probably be safe to more
        // simply return in the .idle case above since none of the values being
        // reset should have values if we are idle, but I am scared of it.
        if case .idle = transferState {} else {
            DependenciesBridge.shared.db.write { tx in
                DependenciesBridge.shared.registrationStateChangeManager.setIsTransferComplete(
                    sendStateUpdateNotification: notifyRegState,
                    tx: tx
                )
            }
        }

        transferState = .idle

        stopThroughputCalculation()
    }

    // MARK: -

    @objc
    private func didEnterBackground() {
        // MCSession automatically disconnects when the app is backgrounded.
        // Send an explicit message to the peer (if connected) telling them
        // that's what happened.
        switch transferState {
        case .idle:
            break
        case .incoming(let oldDevicePeerId, _, _, _, _):
            try? sendBackgroundAppMessage(to: oldDevicePeerId)
            notifyObservers { $0.deviceTransferServiceDidEndTransfer(error: .backgroundedDevice) }
        case .outgoing(let newDevicePeerId, _, _, _, _):
            try? sendBackgroundAppMessage(to: newDevicePeerId)
            notifyObservers { $0.deviceTransferServiceDidEndTransfer(error: .backgroundedDevice) }
        }
        stopTransfer()
    }

    // MARK: - Sending

    private var sendTask: Task<Void, any Swift.Error>?
    func sendAllFiles() throws {
        self.sendTask = Task {
            do {
                try await self._sendAllFiles()
            } catch is CancellationError {
                // Nothing to do.
            } catch {
                self.failTransfer(.assertion, "\(error)")
            }
        }
    }

    @MainActor
    private func _sendAllFiles() async throws {
        guard case .outgoing(let newDevicePeerId, _, let manifest, _, _) = transferState else {
            throw OWSAssertionError("Attempted to send files while no transfer in progress")
        }

        guard let database = manifest.database else {
            throw OWSAssertionError("Manifest unexpectedly missing database")
        }

        struct DatabaseCopy {
            let db: DeviceTransferProtoFile
            let wal: DeviceTransferProtoFile
        }

        try await withThrowingTaskGroup(of: Void.self) { taskGroup in
            taskGroup.addTask {
                // Make a copy of the database files within a write transaction so we can be confident
                // they aren't mutated during the copy. We then transfer these copies.
                let dbCopy = try await SSKEnvironment.shared.databaseStorageRef.awaitableWrite { _ in
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
                    try await DeviceTransferOperation(file: databaseFile).run()
                }
            }
            for (index, file) in manifest.files.enumerated() {
                if index >= 10 {
                    // If we've already kicked off 10, wait for one to finish before starting the next.
                    try await taskGroup.next()
                }
                taskGroup.addTask {
                    try await DeviceTransferOperation(file: file).run()
                }
            }
            // Make sure to wait for whatever's left at the end.
            try await taskGroup.waitForAll()
        }

        await DependenciesBridge.shared.db.awaitableWrite { tx in
            DependenciesBridge.shared.registrationStateChangeManager.setWasTransferred(tx: tx)
        }
        try self.sendDoneMessage(to: newDevicePeerId)
    }

    private static let dbCopyFilename = "db_copy_for_transfer"
    private static let walCopyFilename = "wal_copy_for_transfer"

    private static func urlForCopy(
        databaseFile: DeviceTransferProtoFile
    ) throws -> URL {
        let newFileName: String
        let newFileExtension: String
        if databaseFile.identifier == databaseIdentifier {
            newFileName = Self.dbCopyFilename
            newFileExtension = ".sqlite"
        } else if databaseFile.identifier == databaseWALIdentifier {
            newFileName = Self.walCopyFilename
            newFileExtension = ".sqlite-wal"
        } else {
            throw OWSAssertionError("Unknown db file being copied")
        }
        owsAssertDebug(databaseFile.relativePath.hasSuffix(newFileExtension))
        return OWSFileSystem.temporaryFileUrl(fileName: newFileName, fileExtension: newFileExtension)
    }

    private static func makeLocalCopy(
        databaseFile: DeviceTransferProtoFile
    ) throws -> DeviceTransferProtoFile {
        let url = URL(
            fileURLWithPath: databaseFile.relativePath,
            relativeTo: DeviceTransferService.appSharedDataDirectory
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

    static let doneMessage = Data("Transfer Complete".utf8)
    func sendDoneMessage(to peerId: MCPeerID) throws {
        Logger.info("Sending done message")

        guard let session = session else {
            throw OWSAssertionError("attempted to send done message without an available session")
        }

        try session.send(DeviceTransferService.doneMessage, toPeers: [peerId], with: .reliable)
    }

    static let backgroundAppMessage = Data("App backgrounded".utf8)
    func sendBackgroundAppMessage(to peerId: MCPeerID) throws {
        Logger.info("Sending backgrounded message")

        guard let session = session else {
            throw OWSAssertionError("attempted to send backgrounded message without an available session")
        }

        try session.send(DeviceTransferService.backgroundAppMessage, toPeers: [peerId], with: .unreliable)
    }

    // MARK: - Throughput

    private var previouslyCompletedBytes: Double = 0
    private var lastWholeNumberProgress = 0
    private var throughputTimer: Timer?
    func startThroughputCalculation() {
        guard Thread.isMainThread else {
            DispatchQueue.main.async { self.startThroughputCalculation() }
            return
        }

        stopThroughputCalculation()

        guard let progress: Progress = {
            switch transferState {
            case .incoming(_, _, _, _, let progress):
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

    private func logProgress(_ progress: Progress, remainingBytes: Double) {
        let currentWholeNumberProgress = Int(progress.fractionCompleted * 100)
        let percentChange = currentWholeNumberProgress - lastWholeNumberProgress

        defer { lastWholeNumberProgress = currentWholeNumberProgress }

        // Determine how frequently to log progress updates. If in verbose mode, we log
        // every 1%. Otherwise, every 10%.
        guard percentChange >= (DebugFlags.deviceTransferVerboseProgressLogging ? 1 : 10) else { return }

        var progressLog = String(format: "Transfer progress %d%%", currentWholeNumberProgress)

        var remainingNumber = remainingBytes
        var remainingUnits = "B"
        if remainingNumber / 1024 >= 1 {
            remainingNumber /= 1024
            remainingUnits = "KiB"
        }
        if remainingNumber / 1024 >= 1 {
            remainingNumber /= 1024
            remainingUnits = "MiB"
        }
        if remainingNumber / 1024 >= 1 {
            remainingNumber /= 1024
            remainingUnits = "GiB"
        }

        progressLog += String(format: " / %0.2f %@ remaining", remainingNumber, remainingUnits)

        if let throughput = progress.throughput {
            var transferSpeed = Double(throughput) / 1024
            var transferUnits = "KiB/s"
            if transferSpeed / 1024 >= 1 {
                transferSpeed /= 1024
                transferUnits = "MiB/s"
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

    func stopThroughputCalculation() {
        throughputTimer?.invalidate()
        throughputTimer = nil
        previouslyCompletedBytes = 0
        lastWholeNumberProgress = 0
    }
}
