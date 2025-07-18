//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

public import LibSignalClient

extension BackupKey {
    #if TESTABLE_BUILD
    public static func forTesting() -> BackupKey {
        return try! BackupKey(contents: Randomness.generateRandomBytes(UInt(SVR.DerivedKey.backupKeyLength)))
    }
    #endif
}

/// For Link'n'Sync errors thrown on the primary device.
public enum PrimaryLinkNSyncError: Error {
    case cancelled(linkedDeviceId: DeviceId?)
    case errorWaitingForLinkedDevice
    case errorGeneratingBackup
    // Only these two types are "retryable" in that we let the
    // user choose whether to reset provisioning to try again
    // or continue linking without syncing.
    case errorUploadingBackup(RetryHandler)
    case errorMarkingBackupUploaded(RetryHandler)

    /// For handling Link'n'Sync errors thrown on the primary device.
    public protocol RetryHandler {
        /// Tells the linked device to reset itself to be ready for relinking.
        ///
        /// Note that this won't necessarily work; we _try_ to tell the linked
        /// device to reset but many things can happen that prevent this
        /// (including this method swallowing e.g. network errors).
        func tryToResetLinkedDevice() async

        /// Tells the linked device to continue linking without syncing.
        ///
        /// Note that this won't necessarily work; we _try_ to tell the linked
        /// device to reset but many things can happen that prevent this
        /// (including this method swallowing e.g. network errors).
        func tryToContinueWithoutSyncing() async
    }
}

/// Used as the label for OWSProgress.
public enum PrimaryLinkNSyncProgressPhase: String {
    case waitingForLinking
    case exportingBackup
    case uploadingBackup
    case finishing

    public var percentOfTotalProgress: UInt64 {
        return switch self {
        case .waitingForLinking: 5
        case .exportingBackup: 50
        case .uploadingBackup: 40
        case .finishing: 5
        }
    }
}

/// Link'n'Sync errors thrown on the secondary device.
public enum SecondaryLinkNSyncError: Error, Equatable {
    case primaryFailedBackupExport(continueWithoutSyncing: Bool)
    case errorWaitingForBackup
    case errorDownloadingBackup
    case errorRestoringBackup
    case unsupportedBackupVersion
    case networkError
    case cancelled
}

/// Used as the label for OWSProgress.
public enum SecondaryLinkNSyncProgressPhase: String, CaseIterable {
    case waitingForBackup
    case downloadingBackup
    case importingBackup

    public var percentOfTotalProgress: UInt64 {
        return switch self {
        case .waitingForBackup: 5
        case .downloadingBackup: 30
        case .importingBackup: 65
        }
    }
}

public protocol LinkAndSyncManager {

    /// **Call this on the primary device!**
    /// Generate an ephemeral backup key on a primary device to be used to link'n'sync a new linked device.
    /// This key should be included in the provisioning message and then used to encrypt the backup proto we send.
    ///
    /// - returns The ephemeral key to use, or nil if link'n'sync should not be used.
    func generateEphemeralBackupKey() -> BackupKey

    /// **Call this on the primary device!**
    /// Once the primary sends the provisioning message to the linked device, call this method
    /// to wait on the linked device to link, generate a backup, and upload it. Once this method returns,
    /// the primary's role is complete and the user can exit.
    ///
    /// Supports cancellation, but note that a network request may be made after
    /// cancellation has occured. Therefore, callers should expect to maybe wait
    /// after cancelling (and indicate this in the UI).
    func waitForLinkingAndUploadBackup(
        ephemeralBackupKey: BackupKey,
        tokenId: DeviceProvisioningTokenId,
        progress: OWSProgressSink
    ) async throws(PrimaryLinkNSyncError)

    /// **Call this on the secondary/linked device!**
    /// Once the secondary links on the server, call this method to wait on the primary
    /// to upload a backup, download that backup, and restore data from it.
    /// Once this method returns, provisioning can continue and finish.
    ///
    /// Supports cancellation.
    func waitForBackupAndRestore(
        localIdentifiers: LocalIdentifiers,
        auth: ChatServiceAuth,
        ephemeralBackupKey: BackupKey,
        progress: OWSProgressSink
    ) async throws(SecondaryLinkNSyncError)
}

public class LinkAndSyncManagerImpl: LinkAndSyncManager {

    private let appContext: AppContext
    private let attachmentDownloadManager: AttachmentDownloadManager
    private let attachmentUploadManager: AttachmentUploadManager
    private let backupArchiveManager: BackupArchiveManager
    private let dateProvider: DateProvider
    private let db: any DB
    private let deviceSleepManager: (any DeviceSleepManager)?
    private let kvStore: KeyValueStore
    private let messagePipelineSupervisor: MessagePipelineSupervisor
    private let networkManager: NetworkManager
    private let tsAccountManager: TSAccountManager

    public init(
        appContext: AppContext,
        attachmentDownloadManager: AttachmentDownloadManager,
        attachmentUploadManager: AttachmentUploadManager,
        backupArchiveManager: BackupArchiveManager,
        dateProvider: @escaping DateProvider,
        db: any DB,
        deviceSleepManager: (any DeviceSleepManager)?,
        messagePipelineSupervisor: MessagePipelineSupervisor,
        networkManager: NetworkManager,
        tsAccountManager: TSAccountManager
    ) {
        self.appContext = appContext
        self.attachmentDownloadManager = attachmentDownloadManager
        self.attachmentUploadManager = attachmentUploadManager
        self.backupArchiveManager = backupArchiveManager
        self.dateProvider = dateProvider
        self.db = db
        self.deviceSleepManager = deviceSleepManager
        self.kvStore = KeyValueStore(collection: "LinkAndSyncManagerImpl")
        self.messagePipelineSupervisor = messagePipelineSupervisor
        self.networkManager = networkManager
        self.tsAccountManager = tsAccountManager
    }

    public func generateEphemeralBackupKey() -> BackupKey {
        owsAssertDebug(tsAccountManager.registrationStateWithMaybeSneakyTransaction.isPrimaryDevice == true)
        return try! BackupKey(contents: Randomness.generateRandomBytes(UInt(SVR.DerivedKey.backupKeyLength)))
    }

    public func waitForLinkingAndUploadBackup(
        ephemeralBackupKey: BackupKey,
        tokenId: DeviceProvisioningTokenId,
        progress: OWSProgressSink
    ) async throws(PrimaryLinkNSyncError) {
        let (localIdentifiers, registrationState) = db.read { tx in
            return (
                tsAccountManager.localIdentifiers(tx: tx),
                tsAccountManager.registrationState(tx: tx)
            )
        }
        guard let localIdentifiers else {
            owsFailDebug("Not registered!")
            return
        }
        guard registrationState.isPrimaryDevice == true else {
            owsFailDebug("Non-primary device waiting for secondary linking")
            return
        }

        let blockObject = DeviceSleepBlockObject(blockReason: Constants.sleepBlockingDescription)
        await deviceSleepManager?.addBlock(blockObject: blockObject)
        defer {
            Task {
                await deviceSleepManager?.removeBlock(blockObject: blockObject)
            }
        }

        do {
            try checkCancelledOrAppBackgrounded()
        } catch {
            Logger.info("Cancelled!")
            throw .cancelled(linkedDeviceId: nil)
        }

        // Proportion progress percentages up front.
        let waitForLinkingProgress = await progress.addChild(
            withLabel: PrimaryLinkNSyncProgressPhase.waitingForLinking.rawValue,
            unitCount: PrimaryLinkNSyncProgressPhase.waitingForLinking.percentOfTotalProgress
        )
        let exportingBackupProgress = await progress.addChild(
            withLabel: PrimaryLinkNSyncProgressPhase.exportingBackup.rawValue,
            unitCount: PrimaryLinkNSyncProgressPhase.exportingBackup.percentOfTotalProgress
        )
        let uploadingBackupProgress = await progress.addChild(
            withLabel: PrimaryLinkNSyncProgressPhase.uploadingBackup.rawValue,
            unitCount: PrimaryLinkNSyncProgressPhase.uploadingBackup.percentOfTotalProgress
        )
        let markUploadedProgress = await progress.addChild(
            withLabel: PrimaryLinkNSyncProgressPhase.finishing.rawValue,
            unitCount: PrimaryLinkNSyncProgressPhase.finishing.percentOfTotalProgress
        )

        Logger.info("Beginning link'n'sync")

        let waitForLinkResponse = try await waitForDeviceToLink(
            tokenId: tokenId,
            progress: waitForLinkingProgress
        )

        func handleCancellation() async {
            // If we cancel after linking, we want to let the
            // linked device know we've cancelled.
            try? await self.reportLinkNSyncBackupResultToServer(
                waitForDeviceToLinkResponse: waitForLinkResponse,
                result: .error(.relinkRequested),
                progress: markUploadedProgress
            )
        }

        do {
            try checkCancelledOrAppBackgrounded()
        } catch {
            await handleCancellation()
            throw .cancelled(linkedDeviceId: waitForLinkResponse.id)
        }

        let suspendHandler = messagePipelineSupervisor.suspendMessageProcessing(for: .linkNsync)
        defer { suspendHandler.invalidate() }

        do {
            try checkCancelledOrAppBackgrounded()
        } catch {
            await handleCancellation()
            throw .cancelled(linkedDeviceId: waitForLinkResponse.id)
        }

        let backupMetadata: Upload.EncryptedBackupUploadMetadata
        do {
            backupMetadata = try await generateBackup(
                waitForDeviceToLinkResponse: waitForLinkResponse,
                ephemeralBackupKey: ephemeralBackupKey,
                localIdentifiers: localIdentifiers,
                progress: exportingBackupProgress
            )
        } catch let error {
            switch error {
            case .cancelled:
                await handleCancellation()
            default:
                // At time of writing, iOS _only_ uses the continueWithoutUpload error;
                // no backups errors succeed on retry and even if they did the user could
                // always themselves unlink and relink after they continue.
                try? await reportLinkNSyncBackupResultToServer(
                    waitForDeviceToLinkResponse: waitForLinkResponse,
                    result: .error(.continueWithoutUpload),
                    progress: markUploadedProgress
                )
            }
            throw error
        }

        let uploadResult: Upload.Result<Upload.LinkNSyncUploadMetadata>
        do {
            uploadResult = try await uploadEphemeralBackup(
                waitForDeviceToLinkResponse: waitForLinkResponse,
                metadata: backupMetadata,
                progress: uploadingBackupProgress
            )
        } catch let error {
            switch error {
            case .cancelled:
                await handleCancellation()
            default:
                break
            }
            throw error
        }

        try await reportLinkNSyncBackupResultToServer(
            waitForDeviceToLinkResponse: waitForLinkResponse,
            result: .success(cdnNumber: uploadResult.cdnNumber, cdnKey: uploadResult.cdnKey),
            progress: markUploadedProgress
        )
    }

    public func waitForBackupAndRestore(
        localIdentifiers: LocalIdentifiers,
        auth: ChatServiceAuth,
        ephemeralBackupKey: BackupKey,
        progress: OWSProgressSink
    ) async throws(SecondaryLinkNSyncError) {
        owsAssertDebug(tsAccountManager.registrationStateWithMaybeSneakyTransaction.isPrimaryDevice != true)

        let restoreState = db.read { backupArchiveManager.backupRestoreState(tx: $0) }
        switch restoreState {
        case .finalized:
            // Assume this was from a link'n'sync that was subsequently interrupted
            Logger.info("Skipping link'n'sync; already restored from backup")
            return
        case .unfinalized:
            Logger.info("Finalizing unfinished link'n'sync")
            let blockObject = DeviceSleepBlockObject(blockReason: Constants.sleepBlockingDescription)
            await deviceSleepManager?.addBlock(blockObject: blockObject)
            do {
                try await backupArchiveManager.finalizeBackupImport(progress: progress)
                await deviceSleepManager?.removeBlock(blockObject: blockObject)
            } catch {
                await deviceSleepManager?.removeBlock(blockObject: blockObject)
                if error is CancellationError {
                    throw SecondaryLinkNSyncError.cancelled
                }
                owsFailDebug("Unable to finalize link'n'sync backup restore: \(error)")
                throw SecondaryLinkNSyncError.errorRestoringBackup
            }
        case .none:
            break
        }

        let blockObject = DeviceSleepBlockObject(blockReason: Constants.sleepBlockingDescription)
        await deviceSleepManager?.addBlock(blockObject: blockObject)
        defer {
            Task {
                await deviceSleepManager?.removeBlock(blockObject: blockObject)
            }
        }

        do {
            try checkCancelledOrAppBackgrounded()
        } catch {
            throw .cancelled
        }

        // Proportion progress percentages up front.
        let waitForBackupProgress = await progress.addChild(
            withLabel: SecondaryLinkNSyncProgressPhase.waitingForBackup.rawValue,
            unitCount: SecondaryLinkNSyncProgressPhase.waitingForBackup.percentOfTotalProgress
        )
        let downloadBackupProgress = await progress.addChild(
            withLabel: SecondaryLinkNSyncProgressPhase.downloadingBackup.rawValue,
            unitCount: SecondaryLinkNSyncProgressPhase.downloadingBackup.percentOfTotalProgress
        )
        let importBackupProgress = await progress.addChild(
            withLabel: SecondaryLinkNSyncProgressPhase.importingBackup.rawValue,
            unitCount: SecondaryLinkNSyncProgressPhase.importingBackup.percentOfTotalProgress
        )

        let backupUploadResult = try await waitForPrimaryToUploadBackup(
            auth: auth,
            progress: waitForBackupProgress
        )

        let cdnNumber: UInt32
        let cdnKey: String
        switch backupUploadResult {
        case let .success(_cdnNumber, _cdnKey):
            cdnNumber = _cdnNumber
            cdnKey = _cdnKey
        case .error(let errorResult):
            switch errorResult {
            case .continueWithoutUpload:
                throw .primaryFailedBackupExport(continueWithoutSyncing: true)
            case .relinkRequested:
                throw .primaryFailedBackupExport(continueWithoutSyncing: false)
            }
        }

        do {
            try checkCancelledOrAppBackgrounded()
        } catch {
            throw .cancelled
        }

        let downloadedFileUrl = try await downloadEphemeralBackup(
            cdnNumber: cdnNumber,
            cdnKey: cdnKey,
            ephemeralBackupKey: ephemeralBackupKey,
            progress: downloadBackupProgress
        )

        do {
            try checkCancelledOrAppBackgrounded()
        } catch {
            throw .cancelled
        }

        try await restoreEphemeralBackup(
            fileUrl: downloadedFileUrl,
            localIdentifiers: localIdentifiers,
            ephemeralBackupKey: ephemeralBackupKey,
            progress: importBackupProgress
        )
    }

    // MARK: Primary device steps

    private func waitForDeviceToLink(
        tokenId: DeviceProvisioningTokenId,
        progress: OWSProgressSink
    ) async throws(PrimaryLinkNSyncError) -> Requests.WaitForDeviceToLinkResponse {
        let progressSource = await progress.addSource(
            withLabel: PrimaryLinkNSyncProgressPhase.waitingForLinking.rawValue,
            // Unit count is irrelevant as there's just one child source and we use a timer.
            unitCount: 100
        )
        return try await progressSource.updatePeriodically(
            estimatedTimeToCompletion: 5,
            work: { () async throws(PrimaryLinkNSyncError) -> Requests.WaitForDeviceToLinkResponse in
                try await self._waitForDeviceToLink(tokenId: tokenId)
            }
        )
    }

    private func _waitForDeviceToLink(
        tokenId: DeviceProvisioningTokenId
    ) async throws(PrimaryLinkNSyncError) -> Requests.WaitForDeviceToLinkResponse {
        Logger.info("Waiting for device to link")
        var numNetworkErrors = 0
        whileLoop: while true {
            do {
                // TODO: this cannot use websocket until the websocket implementation
                // supports cooperative cancellation; we need this to be cancellable.
                let response = try await networkManager.asyncRequest(
                    Requests.waitForDeviceToLink(tokenId: tokenId),
                    canUseWebSocket: false
                )
                switch Requests.WaitForDeviceToLinkResponseCodes(rawValue: response.responseStatusCode) {
                case .success:
                    Logger.info("Device linked!")
                    guard
                        let data = response.responseBodyData,
                        let response = try? JSONDecoder().decode(
                            Requests.WaitForDeviceToLinkResponse.self,
                            from: data
                        )
                    else {
                        throw PrimaryLinkNSyncError.errorWaitingForLinkedDevice
                    }
                    return response
                case .timeout:
                    try checkCancelledOrAppBackgrounded()
                    // retry
                    continue whileLoop
                case .invalidParameters:
                    throw PrimaryLinkNSyncError.errorWaitingForLinkedDevice
                case .rateLimited:
                    try await Task.sleep(
                        nanoseconds: HTTPUtils.retryDelayNanoSeconds(response, defaultRetryTime: Constants.defaultRetryTime)
                    )
                    // retry
                    continue whileLoop
                case nil:
                    owsFailDebug("Unexpected response")
                    throw PrimaryLinkNSyncError.errorWaitingForLinkedDevice
                }
            } catch let error as PrimaryLinkNSyncError {
                throw error
            } catch is CancellationError {
                throw .cancelled(linkedDeviceId: nil)
            } catch {
                if error.isNetworkFailureOrTimeout {
                    numNetworkErrors += 1
                    if numNetworkErrors <= 3 {
                        // retry
                        continue
                    }
                }
                throw .errorWaitingForLinkedDevice
            }
        }
    }

    private func generateBackup(
        waitForDeviceToLinkResponse: Requests.WaitForDeviceToLinkResponse,
        ephemeralBackupKey: BackupKey,
        localIdentifiers: LocalIdentifiers,
        progress: OWSProgressSink
    ) async throws(PrimaryLinkNSyncError) -> Upload.EncryptedBackupUploadMetadata {
        do {
            let metadata = try await backupArchiveManager.exportEncryptedBackup(
                localIdentifiers: localIdentifiers,
                backupKey: ephemeralBackupKey,
                backupPurpose: .deviceTransfer,
                progress: progress
            )
            try await backupArchiveManager.validateEncryptedBackup(
                fileUrl: metadata.fileUrl,
                localIdentifiers: localIdentifiers,
                backupKey: ephemeralBackupKey,
                backupPurpose: .deviceTransfer
            )
            return metadata
        } catch let error {
            if error is CancellationError {
                throw .cancelled(linkedDeviceId: waitForDeviceToLinkResponse.id)
            }
            owsFailDebug("Unable to generate link'n'sync backup: \(error)")
            throw .errorGeneratingBackup
        }
    }

    private func uploadEphemeralBackup(
        waitForDeviceToLinkResponse: Requests.WaitForDeviceToLinkResponse,
        metadata: Upload.EncryptedBackupUploadMetadata,
        progress: OWSProgressSink
    ) async throws(PrimaryLinkNSyncError) -> Upload.Result<Upload.LinkNSyncUploadMetadata> {
        do {
            return try await attachmentUploadManager.uploadLinkNSyncAttachment(
                dataSource: try DataSourcePath(
                    fileUrl: metadata.fileUrl,
                    shouldDeleteOnDeallocation: true
                ),
                progress: progress
            )
        } catch {
            if error is CancellationError {
                throw .cancelled(linkedDeviceId: waitForDeviceToLinkResponse.id)
            } else {
                throw .errorUploadingBackup(PrimaryLinkNSyncErrorRetryHandler(
                    waitForDeviceToLinkResponse: waitForDeviceToLinkResponse,
                    linkNSyncManager: self
                ))
            }
        }
    }

    private func reportLinkNSyncBackupResultToServer(
        waitForDeviceToLinkResponse: Requests.WaitForDeviceToLinkResponse,
        result: Requests.ExportAndUploadBackupResult,
        progress: OWSProgressSink
    ) async throws(PrimaryLinkNSyncError) -> Void {
        // Do this in a detachedtask; we want to report a status
        // to the server even if the user cancels the current task.
        let task = Task.detached(priority: Task.currentPriority) {
            let progressSource = await progress.addSource(
                withLabel: PrimaryLinkNSyncProgressPhase.finishing.rawValue,
                // Unit count is irrelevant as there's just one child source and we use a timer.
                unitCount: 100
            )
            return try await progressSource.updatePeriodically(
                estimatedTimeToCompletion: 3,
                work: { () async throws(PrimaryLinkNSyncError) -> Void in
                    try await self._markEphemeralBackupUploaded(
                        waitForDeviceToLinkResponse: waitForDeviceToLinkResponse,
                        result: result
                    )
                }
            )
        }
        // Task.detached doesn't support typed errors until iOS 18;
        // we have to manually unwrap.
        do {
            try await task.value
        } catch let error as PrimaryLinkNSyncError {
            throw error
        } catch {
            owsFailDebug("Invalid error!")
            throw .errorMarkingBackupUploaded(PrimaryLinkNSyncErrorRetryHandler(
                waitForDeviceToLinkResponse: waitForDeviceToLinkResponse,
                linkNSyncManager: self
            ))
        }
    }

    private func _markEphemeralBackupUploaded(
        waitForDeviceToLinkResponse: Requests.WaitForDeviceToLinkResponse,
        result: Requests.ExportAndUploadBackupResult
    ) async throws(PrimaryLinkNSyncError) -> Void {
        do {
            let response = try await networkManager.asyncRequest(
                Requests.reportLinkNSyncBackupResultToServer(
                    waitForDeviceToLinkResponse: waitForDeviceToLinkResponse,
                    result: result
                )
            )

            guard response.responseStatusCode == 204 || response.responseStatusCode == 200 else {
                throw PrimaryLinkNSyncError.errorMarkingBackupUploaded(PrimaryLinkNSyncErrorRetryHandler(
                    waitForDeviceToLinkResponse: waitForDeviceToLinkResponse,
                    linkNSyncManager: self
                ))
            }
        } catch let error {
            if error is CancellationError {
                throw .cancelled(linkedDeviceId: waitForDeviceToLinkResponse.id)
            } else {
                throw .errorMarkingBackupUploaded(PrimaryLinkNSyncErrorRetryHandler(
                    waitForDeviceToLinkResponse: waitForDeviceToLinkResponse,
                    linkNSyncManager: self
                ))
            }
        }
    }

    private final class PrimaryLinkNSyncErrorRetryHandler: PrimaryLinkNSyncError.RetryHandler {

        let waitForDeviceToLinkResponse: Requests.WaitForDeviceToLinkResponse
        let linkNSyncManager: LinkAndSyncManagerImpl

        init(
            waitForDeviceToLinkResponse: Requests.WaitForDeviceToLinkResponse,
            linkNSyncManager: LinkAndSyncManagerImpl
        ) {
            self.waitForDeviceToLinkResponse = waitForDeviceToLinkResponse
            self.linkNSyncManager = linkNSyncManager
        }

        func tryToResetLinkedDevice() async {
            try? await linkNSyncManager._markEphemeralBackupUploaded(
                waitForDeviceToLinkResponse: waitForDeviceToLinkResponse,
                result: .error(.relinkRequested)
            )
        }

        func tryToContinueWithoutSyncing() async {
            try? await linkNSyncManager._markEphemeralBackupUploaded(
                waitForDeviceToLinkResponse: waitForDeviceToLinkResponse,
                result: .error(.continueWithoutUpload)
            )
        }
    }

    // MARK: Linked device steps

    private func waitForPrimaryToUploadBackup(
        auth: ChatServiceAuth,
        progress: OWSProgressSink
    ) async throws(SecondaryLinkNSyncError) -> Requests.ExportAndUploadBackupResult {
        let progressSource = await progress.addSource(
            withLabel: SecondaryLinkNSyncProgressPhase.waitingForBackup.rawValue,
            // Unit count is irrelevant as there's just one child source and we use a timer.
            unitCount: 100
        )
        return try await progressSource.updatePeriodically(
            estimatedTimeToCompletion: 40,
            work: { () async throws(SecondaryLinkNSyncError) -> Requests.ExportAndUploadBackupResult in
                try await self._waitForPrimaryToUploadBackup(auth: auth)
            }
        )
    }

    private func _waitForPrimaryToUploadBackup(
        auth: ChatServiceAuth
    ) async throws(SecondaryLinkNSyncError) -> Requests.ExportAndUploadBackupResult {
        var numNetworkErrors = 0
        whileLoop: while true {
            do {
                // TODO: this cannot use websocket until the websocket implementation
                // supports cooperative cancellation; we need this to be cancellable.
                let response = try await networkManager.asyncRequest(
                    Requests.waitForLinkNSyncBackupUpload(auth: auth),
                    canUseWebSocket: false
                )
                switch Requests.WaitForLinkNSyncBackupUploadResponseCodes(rawValue: response.responseStatusCode) {
                case .success:
                    guard
                        let data = response.responseBodyData,
                        let rawResponse = try? JSONDecoder().decode(
                            Requests.WaitForLinkNSyncBackupUploadRawResponse.self,
                            from: data
                        )
                    else {
                        throw SecondaryLinkNSyncError.errorWaitingForBackup
                    }
                    if
                        let cdnNumber = rawResponse.cdn,
                        let cdnKey = rawResponse.key
                    {
                        return .success(cdnNumber: cdnNumber, cdnKey: cdnKey)
                    } else if let error = rawResponse.error {
                        return .error(error)
                    } else {
                        owsFailDebug("Unexpected server response!")
                        return .error(.continueWithoutUpload)
                    }
                case .timeout:
                    try checkCancelledOrAppBackgrounded()
                    // retry
                    continue whileLoop
                case .invalidParameters:
                    throw SecondaryLinkNSyncError.errorWaitingForBackup
                case .rateLimited:
                    try await Task.sleep(
                        nanoseconds: HTTPUtils.retryDelayNanoSeconds(response, defaultRetryTime: Constants.defaultRetryTime)
                    )
                    // retry
                    continue whileLoop
                case nil:
                    owsFailDebug("Unexpected response")
                    throw SecondaryLinkNSyncError.errorWaitingForBackup
                }
            } catch let error as SecondaryLinkNSyncError {
                throw error
            } catch is CancellationError {
                throw SecondaryLinkNSyncError.cancelled
            } catch {
                if error .isNetworkFailureOrTimeout {
                    numNetworkErrors += 1
                    if numNetworkErrors <= 3 {
                        // retry
                        continue whileLoop
                    }
                }
                throw SecondaryLinkNSyncError.networkError
            }
        }
    }

    private func downloadEphemeralBackup(
        cdnNumber: UInt32,
        cdnKey: String,
        ephemeralBackupKey: BackupKey,
        progress: OWSProgressSink
    ) async throws(SecondaryLinkNSyncError) -> URL {
        do {
            return try await attachmentDownloadManager.downloadTransientAttachment(
                metadata: AttachmentDownloads.DownloadMetadata(
                    mimeType: MimeType.applicationOctetStream.rawValue,
                    cdnNumber: cdnNumber,
                    encryptionKey: ephemeralBackupKey.serialize(),
                    source: .linkNSyncBackup(cdnKey: cdnKey)
                ),
                progress: progress
            ).awaitable()
        } catch {
            if error is CancellationError {
                throw SecondaryLinkNSyncError.cancelled
            } else if error.isNetworkFailureOrTimeout {
                throw SecondaryLinkNSyncError.networkError
            } else {
                throw SecondaryLinkNSyncError.errorDownloadingBackup
            }
        }
    }

    private func restoreEphemeralBackup(
        fileUrl: URL,
        localIdentifiers: LocalIdentifiers,
        ephemeralBackupKey: BackupKey,
        progress: OWSProgressSink
    ) async throws(SecondaryLinkNSyncError) {
        do {
            try await backupArchiveManager.importEncryptedBackup(
                fileUrl: fileUrl,
                localIdentifiers: localIdentifiers,
                isPrimaryDevice: false,
                backupKey: ephemeralBackupKey,
                // "Device transfer" is libsignal's name for link'n'sync
                backupPurpose: .deviceTransfer,
                progress: progress
            )
        } catch {
            if error is CancellationError {
                throw SecondaryLinkNSyncError.cancelled
            }
            owsFailDebug("Unable to restore link'n'sync backup: \(error)")
            if let backupImportError = error as? BackupImportError {
                switch backupImportError {
                case .unsupportedVersion:
                    throw SecondaryLinkNSyncError.unsupportedBackupVersion
                }
            }
            throw SecondaryLinkNSyncError.errorRestoringBackup
        }
    }

    fileprivate enum Constants {
        static let sleepBlockingDescription = "Link'n'Sync"

        static let enabledOnPrimaryKey = "enabledOnPrimaryKey"

        static let longPollRequestTimeoutSeconds: UInt32 = 60 * 5
        static let defaultRetryTime: TimeInterval = 15
    }

    // MARK: - Helpers

    private func checkCancelledOrAppBackgrounded() throws {
        guard appContext.isAppForegroundAndActive() else {
            throw CancellationError()
        }
        try Task.checkCancellation()
    }

    // MARK: - Requests

    private enum Requests {

        struct WaitForDeviceToLinkResponse: Codable {
            /// The deviceId of the linked device
            let id: DeviceId
            /// Thename of the linked device.
            let name: String
            /// The timestamp the linked device was last seen on the server.
            let lastSeen: UInt64
            /// The timestamp the linked device was created on the server.
            let created: UInt64
        }

        enum WaitForDeviceToLinkResponseCodes: Int {
            case success = 200
            /// The timeout elapsed without the device linking; clients can request again.
            case timeout = 204
            case invalidParameters = 400
            case rateLimited = 429
        }

        static func waitForDeviceToLink(
            tokenId: DeviceProvisioningTokenId
        ) -> TSRequest {
            var urlComponents = URLComponents(string: "v1/devices/wait_for_linked_device/\(tokenId.id)")!
            urlComponents.queryItems = [URLQueryItem(
                name: "timeout",
                value: "\(LinkAndSyncManagerImpl.Constants.longPollRequestTimeoutSeconds)"
            )]
            var request = TSRequest(
                url: urlComponents.url!,
                method: "GET",
                parameters: nil
            )
            request.applyRedactionStrategy(.redactURLForSuccessResponses())
            // The timeout is server side; apply wiggle room for our local clock.
            request.timeoutInterval = 10 + TimeInterval(Constants.longPollRequestTimeoutSeconds)
            return request
        }

        enum ExportErrorType: String, Codable {
            /// The primary requests the linked device restart the linking process.
            case relinkRequested = "RELINK_REQUESTED"
            /// The primary experienced an unretryable error and wants the linked device
            /// continue without restoring from a backup.
            case continueWithoutUpload = "CONTINUE_WITHOUT_UPLOAD"
        }

        enum ExportAndUploadBackupResult {
            case success(cdnNumber: UInt32, cdnKey: String)
            case error(ExportErrorType)
        }

        static func reportLinkNSyncBackupResultToServer(
            waitForDeviceToLinkResponse: WaitForDeviceToLinkResponse,
            result: ExportAndUploadBackupResult
        ) -> TSRequest {
            var request = TSRequest(
                url: URL(string: "v1/devices/transfer_archive")!,
                method: "PUT",
                parameters: [
                    "destinationDeviceId": waitForDeviceToLinkResponse.id.uint32Value,
                    "destinationDeviceCreated": waitForDeviceToLinkResponse.created,
                    "transferArchive": {
                        switch result {
                        case .success(let cdnNumber, let cdnKey):
                            return [
                                "cdn": cdnNumber,
                                "key": cdnKey
                            ]
                        case .error(let exportErrorType):
                            return [
                                "error": exportErrorType.rawValue
                            ]
                        }
                    }()
                ]
            )
            request.applyRedactionStrategy(.redactURLForSuccessResponses())
            return request
        }

        struct WaitForLinkNSyncBackupUploadRawResponse: Codable {
            /// The cdn number
            let cdn: UInt32?
            /// The cdn key
            let key: String?
            let error: ExportErrorType?
        }

        enum WaitForLinkNSyncBackupUploadResponseCodes: Int {
            case success = 200
            /// The timeout elapsed without any upload; clients can request again.
            case timeout = 204
            case invalidParameters = 400
            case rateLimited = 429
        }

        static func waitForLinkNSyncBackupUpload(auth: ChatServiceAuth) -> TSRequest {
            var urlComponents = URLComponents(string: "v1/devices/transfer_archive")!
            urlComponents.queryItems = [URLQueryItem(
                name: "timeout",
                value: "\(Constants.longPollRequestTimeoutSeconds)"
            )]
            var request = TSRequest(
                url: urlComponents.url!,
                method: "GET",
                parameters: nil
            )
            request.auth = .identified(auth)
            request.applyRedactionStrategy(.redactURLForSuccessResponses())
            // The timeout is server side; apply wiggle room for our local clock.
            request.timeoutInterval = 10 + TimeInterval(Constants.longPollRequestTimeoutSeconds)
            return request
        }
    }
}
