//
// Copyright 2025 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import SignalServiceKit

@MainActor
class IncomingDeviceTransferTask {

    // Incoming Device state
    private var manifest: DeviceTransferProtoManifest?
    private let receivedFileIds = AtomicValue<[String]>([], lock: .init())
    private let skippedFileIds = AtomicValue<[String]>([], lock: .init())

    private var session: DeviceTransfer.Session?
    private var throughputMonitor: ThroughputMonitor?
    private var initializeProgressBlock: ((Progress) -> Void)?

    private var transferInProgress = false

    private let sleepBlockObject = DeviceSleepBlockObject(blockReason: "device transfer")
    private let db: DB
    private let deviceTransferRestore: DeviceTransferRestore
    private let registrationStateChangeManager: RegistrationStateChangeManager
    private let deviceSleepManager: DeviceSleepManager?

    private let newDeviceServiceAdvertiser: DeviceTransfer.IncomingConnection
    private var notificationObservers: [NotificationCenter.Observer] = []

    private var messagesReceiverTask: Task<Void, Error>?
    private var transferFinishedContinuation: CheckedContinuation<Void, Error>?

    init(
        db: DB,
        deviceSleepManager: DeviceSleepManager?,
        deviceTransferRestore: DeviceTransferRestore,
        deviceTransferConnectionFactory: DeviceTransfer.ConnectionFactory,
        registrationStateChangeManager: RegistrationStateChangeManager,
        tsAccountManager: TSAccountManager,
    ) {
        self.db = db
        self.deviceSleepManager = deviceSleepManager
        self.registrationStateChangeManager = registrationStateChangeManager
        self.deviceTransferRestore = deviceTransferRestore
        self.newDeviceServiceAdvertiser = deviceTransferConnectionFactory.buildIncomingConnection(
            tsAccountManager: tsAccountManager,
        )
    }

    // MARK: - Public methods

    func start(mode: DeviceTransfer.Mode) async throws -> URL {
        deviceSleepManager?.addBlock(blockObject: sleepBlockObject)
        return try newDeviceServiceAdvertiser.start(mode: mode)
    }

    func stopAcceptingTransfersFromOldDevices() {
        newDeviceServiceAdvertiser.stop(error: nil)
    }

    func waitForTransferFromOldDevice(initializeProgressBlock: ((Progress) -> Void)? = nil) async throws {
        let session = try await newDeviceServiceAdvertiser.waitForConnection()
        self.session = session
        self.initializeProgressBlock = initializeProgressBlock

        notificationObservers.append(
            NotificationCenter.default.addObserver(
                name: .OWSApplicationDidEnterBackground,
                block: didEnterBackground(_:),
            ),
        )

        defer {
            notificationObservers.forEach {
                NotificationCenter.default.removeObserver($0)
            }
            notificationObservers.removeAll()
        }

        messagesReceiverTask = Task {
            do {
                for try await message in session.messages {
                    switch message {
                    case .message(let message):
                        try processMessage(message: message, session: session)
                    case .startResource(let fileName, _, let progress):
                        try startReceiving(fileName: fileName, session: session, progress: progress)
                    case .finishResource(let fileName, let localUrl):
                        try finishReceiving(fileName: fileName, localUrl: localUrl)
                    }
                }
            } catch {
                if let transferFinishedContinuation {
                    transferFinishedContinuation.resume(throwing: error)
                    self.transferFinishedContinuation = nil
                } else {
                    throw error
                }
            }
        }

        try await withCheckedThrowingContinuation { continuation in
            self.transferFinishedContinuation = continuation
        }
    }

    @MainActor
    func cancelTransferFromOldDevice() {
        stopTransfer(error: CancellationError())
    }

    // MARK: - Private methods

    private func stopTransfer(error: Error? = nil, notifyRegState: Bool = true) {
        newDeviceServiceAdvertiser.stop(error: error)
        throughputMonitor?.stop()
        deviceSleepManager?.removeBlock(blockObject: sleepBlockObject)
        messagesReceiverTask.take()?.cancel()

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
            transferInProgress = false
        }
    }

    private func failTransfer(_ error: DeviceTransfer.Error, _ reason: String) {
        Logger.error("Failed transfer \(reason)")
        stopTransfer(error: error)
    }

    private func handleReceivedManifest(at localURL: URL) {
        guard !transferInProgress else {
            stopTransfer(error: OWSAssertionError("Received manifest in unexpected state"))
            return
        }
        guard let fileSize = (try? OWSFileSystem.fileSize(of: localURL)) else {
            stopTransfer(error: OWSAssertionError("Missing manifest file."))
            return
        }
        // Not sure why this limit exists in the first place, but 1Gb should be
        // plenty high for file descriptors.
        guard fileSize < 1024 * 1024 * 1024 else {
            stopTransfer(error: OWSAssertionError("Unexpectedly received a very large manifest \(fileSize)"))
            return
        }
        guard let data = try? Data(contentsOf: localURL) else {
            stopTransfer(error: OWSAssertionError("Failed to read manifest data"))
            return
        }
        guard let manifest = try? DeviceTransferProtoManifest(serializedData: data) else {
            stopTransfer(error: OWSAssertionError("Failed to parse manifest proto"))
            return
        }
        guard !DependenciesBridge.shared.tsAccountManager.registrationStateWithMaybeSneakyTransaction.isRegistered else {
            stopTransfer(error: OWSAssertionError("Ignoring incoming transfer to a registered device"))
            return
        }

        DeviceTransfer.Utils.resetTransferDirectory(createNewTransferDirectory: true)

        do {
            try OWSFileSystem.moveFilePath(
                localURL.path,
                toFilePath: URL(
                    fileURLWithPath: DeviceTransfer.Constants.manifestIdentifier,
                    relativeTo: DeviceTransfer.Constants.pendingTransferDirectory,
                ).path,
            )
        } catch {
            stopTransfer(error: error)
            return
        }

        // Check if the device has a newer version of the database than we understand

        guard manifest.grdbSchemaVersion <= GRDBSchemaMigrator.grdbSchemaVersionLatest else {
            return self.failTransfer(
                DeviceTransfer.Error.unsupportedVersion,
                "Ignoring manifest with unsupported schema version",
            )
        }

        // Check if there is enough space on disk to receive the transfer
        guard
            let freeSpaceInBytes = try? OWSFileSystem.freeSpaceInBytes(
                forPath: DeviceTransfer.Constants.pendingTransferDirectory,
            )
        else {
            return self.failTransfer(
                DeviceTransfer.Error.assertion,
                "failed to calculate available disk space",
            )
        }

        guard freeSpaceInBytes > manifest.estimatedTotalSize else {
            return self.failTransfer(
                DeviceTransfer.Error.notEnoughSpace,
                "not enough free space to receive transfer",
            )
        }

        self.manifest = manifest
        receivedFileIds.update { $0.append(DeviceTransfer.Constants.manifestIdentifier) }

        db.write { tx in
            registrationStateChangeManager.setIsTransferInProgress(tx: tx)
        }

        transferInProgress = true
        let progress = Progress(totalUnitCount: Int64(manifest.estimatedTotalSize))
        throughputMonitor = ThroughputMonitor(progress: progress)
        throughputMonitor?.start()

        initializeProgressBlock?(progress)
    }

    // MARK: -

    private func didEnterBackground(_ notification: Notification) {
        // MCSession automatically disconnects when the app is backgrounded.
        // Send an explicit message to the peer (if connected) telling them
        // that's what happened.
        try? session?.send(message: .backgroundApp)
        stopTransfer(error: CancellationError())
    }

    private func processMessage(message: DeviceTransfer.Message, session: DeviceTransfer.Session) throws {
        switch message {
        case DeviceTransfer.Message.backgroundApp:
            return failTransfer(DeviceTransfer.Error.backgroundedDevice, "Received backgrounded message")
        case DeviceTransfer.Message.done:
            break
        }

        // When the new device receives the done message from the old device,
        // it indicates that the old device thinks we should have received
        // everything at this point.
        guard
            verifyTransferCompletedSuccessfully(
                receivedFileIds: receivedFileIds,
                skippedFileIds: skippedFileIds,
            )
        else {
            return failTransfer(.assertion, "transfer is missing data")
        }

        deviceTransferRestore.markPendingRestore()

        // Try and notify the old device that we agree, everything is done.
        // At this point, we consider the transfer complete regardless of
        // whether or not this message is received by the old device. If the
        // old device misses this message (because the app crashes, etc.) it
        // will continue acting as if it is "unregistered", but it won't delete
        // all data because it doesn't know for sure if the data was safely
        // received by the new device.
        do {
            try session.send(message: DeviceTransfer.Message.done)
        } catch {
            owsFailDebug("Failed to send done message to old device \(error)")
        }

        // Try and restore the received data. If for some reason the app exits
        // or crashes at this point, we will retry the restore when the app next
        // launches.
        do {
            try deviceTransferRestore.restoreTransferredData()
        } catch {
            owsFail("Restore failed. Will try again on next launch. Error: \(error)")
        }

        stopTransfer(notifyRegState: false)

        Logger.info("Transfer complete")

        transferFinishedContinuation.take()?.resume()
    }

    private func startReceiving(fileName: String, session: DeviceTransfer.Session, progress: Progress?) throws {
        guard transferInProgress else { return }
        guard let manifest else {
            return owsFailDebug("Received file while not expecting one")
        }

        let nameComponents = fileName.components(separatedBy: " ")

        guard let fileIdentifier = nameComponents.first, nameComponents.count == 2 else {
            return owsFailDebug("Received incorrectly formatted resourceName: \(fileName)")
        }

        guard !receivedFileIds.get().contains(fileIdentifier) else {
            return Logger.info("Ignoring duplicate file: \(fileIdentifier)")
        }

        guard !skippedFileIds.get().contains(fileIdentifier) else {
            return Logger.info("Ignoring previously skipped file: \(fileIdentifier)")
        }

        guard
            let file: DeviceTransferProtoFile = {
                switch fileIdentifier {
                case DeviceTransfer.Constants.databaseIdentifier:
                    return manifest.database?.database
                case DeviceTransfer.Constants.databaseWALIdentifier:
                    return manifest.database?.wal
                default:
                    return manifest.files.first(where: { $0.identifier == fileIdentifier })
                }
            }()
        else {
            return owsFailDebug("Received unexpected file on new device: \(fileIdentifier)")
        }

        Logger.info("Receiving file: \(file.identifier), estimatedSize: \(file.estimatedSize)")
        if let progress {
            throughputMonitor?.progress.addChild(progress, withPendingUnitCount: Int64(file.estimatedSize))
        }
    }

    private func finishReceiving(fileName: String, localUrl: URL) throws {
        if !transferInProgress {
            guard fileName == DeviceTransfer.Constants.manifestIdentifier else {
                return Logger.info("Ignoring unexpected incoming file \(fileName)")
            }

            handleReceivedManifest(at: localUrl)
            transferInProgress = true
            return
        }

        guard let manifest else {
            return owsFailDebug("Received file while not expecting one")
        }

        let nameComponents = fileName.components(separatedBy: " ")

        guard let fileIdentifier = nameComponents.first, let fileHash = nameComponents.last, nameComponents.count == 2 else {
            return owsFailDebug("Received incorrectly formatted resourceName: \(fileName)")
        }

        guard !receivedFileIds.get().contains(fileIdentifier) else {
            return Logger.info("Ignoring duplicate file: \(fileIdentifier)")
        }

        guard !skippedFileIds.get().contains(fileIdentifier) else {
            return Logger.info("Ignoring previously skipped file: \(fileIdentifier)")
        }

        guard
            let file: DeviceTransferProtoFile = {
                switch fileIdentifier {
                case DeviceTransfer.Constants.databaseIdentifier:
                    return manifest.database?.database
                case DeviceTransfer.Constants.databaseWALIdentifier:
                    return manifest.database?.wal
                default:
                    return manifest.files.first(where: { $0.identifier == fileIdentifier })
                }
            }()
        else {
            return owsFailDebug("Received unexpected file on new device: \(fileIdentifier)")
        }

        OWSFileSystem.ensureDirectoryExists(DeviceTransfer.Constants.pendingTransferFilesDirectory.path)

        guard let computedHash = try? Cryptography.computeSHA256DigestOfFile(at: localUrl) else {
            return failTransfer(DeviceTransfer.Error.assertion, "Failed to compute hash for \(file.identifier)")
        }

        guard computedHash.hexadecimalString == fileHash else {
            return failTransfer(DeviceTransfer.Error.assertion, "Received file with incorrect hash \(file.identifier)")
        }

        guard computedHash != DeviceTransfer.Constants.missingFileHash else {
            Logger.warn("Received notification of missing file: \(file.identifier), skipping.")
            skippedFileIds.update { $0.append(file.identifier) }
            return
        }

        do {
            try OWSFileSystem.moveFilePath(
                localUrl.path,
                toFilePath: URL(
                    fileURLWithPath: file.identifier,
                    relativeTo: DeviceTransfer.Constants.pendingTransferFilesDirectory,
                ).path,
            )
        } catch {
            Logger.warn("Couldn't move file: \(error.shortDescription)")
            return failTransfer(DeviceTransfer.Error.assertion, "Failed to move file into place \(file.identifier)")
        }

        Logger.info("Received file: \(file.identifier)")
        receivedFileIds.update { $0.append(file.identifier) }
    }

    private func verifyTransferCompletedSuccessfully(
        receivedFileIds: AtomicValue<[String]>,
        skippedFileIds: AtomicValue<[String]>,
    ) -> Bool {
        guard let manifest = DeviceTransfer.Utils.readManifestFromTransferDirectory() else {
            owsFailDebug("Missing manifest file")
            return false
        }

        // Check that there aren't any files that we were
        // expecting that are missing.
        for file in manifest.files {
            guard !skippedFileIds.get().contains(file.identifier) else { continue }

            guard receivedFileIds.get().contains(file.identifier) else {
                owsFailDebug("did not receive file \(file.identifier)")
                return false
            }
            guard
                OWSFileSystem.fileOrFolderExists(
                    atPath: URL(
                        fileURLWithPath: file.identifier,
                        relativeTo: DeviceTransfer.Constants.pendingTransferFilesDirectory,
                    ).path,
                )
            else {
                owsFailDebug("Missing file \(file.identifier)")
                return false
            }
        }

        // Check that the appropriate database files were received
        guard let database = manifest.database else {
            owsFailDebug("missing database proto")
            return false
        }

        guard database.key.count == GRDBKeyFetcher.Constants.kSQLCipherKeySpecLength else {
            owsFailDebug("incorrect database key length")
            return false
        }

        guard receivedFileIds.get().contains(DeviceTransfer.Constants.databaseIdentifier) else {
            owsFailDebug("did not receive database file")
            return false
        }

        guard
            OWSFileSystem.fileOrFolderExists(
                atPath: URL(
                    fileURLWithPath: DeviceTransfer.Constants.databaseIdentifier,
                    relativeTo: DeviceTransfer.Constants.pendingTransferFilesDirectory,
                ).path,
            )
        else {
            owsFailDebug("missing database file")
            return false
        }

        guard receivedFileIds.get().contains(DeviceTransfer.Constants.databaseWALIdentifier) else {
            owsFailDebug("did not receive database wal file")
            return false
        }

        guard
            OWSFileSystem.fileOrFolderExists(
                atPath: URL(
                    fileURLWithPath: DeviceTransfer.Constants.databaseWALIdentifier,
                    relativeTo: DeviceTransfer.Constants.pendingTransferFilesDirectory,
                ).path,
            )
        else {
            owsFailDebug("missing database wal file")
            return false
        }

        return true
    }
}
