//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

public import LibSignalClient

extension BackupKey {
    public convenience init?(provisioningMessage: ProvisionMessage) {
        guard let data = provisioningMessage.ephemeralBackupKey else {
            return nil
        }
        try? self.init(contents: Array(data))
    }

    #if TESTABLE_BUILD
    public static func forTesting() -> BackupKey {
        return try! BackupKey(contents: Array(Randomness.generateRandomBytes(UInt(SVR.DerivedKey.backupKeyLength))))
    }
    #endif
}

/// Link'n'Sync errors thrown on the primary device.
public enum PrimaryLinkNSyncError: Error {
    case timedOutWaitingForLinkedDevice
    case errorWaitingForLinkedDevice
    case errorGeneratingBackup
    case errorUploadingBackup
    case networkError
}

/// Used as the label for OWSProgress.
public enum PrimaryLinkNSyncProgressPhase: String {
    case waitingForLinking
    case exportingBackup
    case uploadingBackup
    case finishing

    var percentOfTotalProgress: UInt64 {
        return switch self {
        case .waitingForLinking: 30
        case .exportingBackup: 25
        case .uploadingBackup: 40
        case .finishing: 5
        }
    }
}

/// Link'n'Sync errors thrown on the secondary device.
public enum SecondaryLinkNSyncError: Error {
    case timedOutWaitingForBackup
    case primaryFailedBackupExport
    case errorWaitingForBackup
    case errorDownloadingBackup
    case errorRestoringBackup
    case unsupportedBackupVersion
    case networkError
}

/// Used as the label for OWSProgress.
public enum SecondaryLinkNSyncProgressPhase: String {
    case waitingForBackup
    case downloadingBackup
    case importingBackup

    var percentOfTotalProgress: UInt64 {
        return switch self {
        case .waitingForBackup: 50
        case .downloadingBackup: 30
        case .importingBackup: 20
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
    func waitForLinkingAndUploadBackup(
        ephemeralBackupKey: BackupKey,
        tokenId: DeviceProvisioningTokenId,
        progress: OWSProgressSink
    ) async throws(PrimaryLinkNSyncError)

    /// **Call this on the secondary/linked device!**
    /// Once the secondary links on the server, call this method to wait on the primary
    /// to upload a backup, download that backup, and restore data from it.
    /// Once this method returns, provisioning can continue and finish.
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
    private let db: any DB
    private let kvStore: KeyValueStore
    private let messageBackupManager: MessageBackupManager
    private let messagePipelineSupervisor: MessagePipelineSupervisor
    private let networkManager: NetworkManager
    private let tsAccountManager: TSAccountManager

    public init(
        appContext: AppContext,
        attachmentDownloadManager: AttachmentDownloadManager,
        attachmentUploadManager: AttachmentUploadManager,
        db: any DB,
        messageBackupManager: MessageBackupManager,
        messagePipelineSupervisor: MessagePipelineSupervisor,
        networkManager: NetworkManager,
        tsAccountManager: TSAccountManager
    ) {
        self.appContext = appContext
        self.attachmentDownloadManager = attachmentDownloadManager
        self.attachmentUploadManager = attachmentUploadManager
        self.db = db
        self.kvStore = KeyValueStore(collection: "LinkAndSyncManagerImpl")
        self.messageBackupManager = messageBackupManager
        self.messagePipelineSupervisor = messagePipelineSupervisor
        self.networkManager = networkManager
        self.tsAccountManager = tsAccountManager
    }

    public func generateEphemeralBackupKey() -> BackupKey {
        owsAssertDebug(FeatureFlags.linkAndSync)
        owsAssertDebug(tsAccountManager.registrationStateWithMaybeSneakyTransaction.isPrimaryDevice == true)
        return try! BackupKey(contents: Array(Randomness.generateRandomBytes(UInt(SVR.DerivedKey.backupKeyLength))))
    }

    public func waitForLinkingAndUploadBackup(
        ephemeralBackupKey: BackupKey,
        tokenId: DeviceProvisioningTokenId,
        progress: OWSProgressSink
    ) async throws(PrimaryLinkNSyncError) {
        guard FeatureFlags.linkAndSync else {
            owsFailDebug("link'n'sync not available")
            return
        }
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

        await MainActor.run {
            appContext.ensureSleepBlocking(true, blockingObjectsDescription: Constants.sleepBlockingDescription)
        }
        let suspendHandler = messagePipelineSupervisor.suspendMessageProcessing(for: .linkNsync)
        defer {
            suspendHandler.invalidate()
            Task { @MainActor in
                appContext.ensureSleepBlocking(false, blockingObjectsDescription: Constants.sleepBlockingDescription)
            }
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

        let waitForLinkResponse = try await waitForDeviceToLink(
            tokenId: tokenId,
            progress: waitForLinkingProgress
        )

        let backupMetadata: Upload.EncryptedBackupUploadMetadata
        do {
            backupMetadata = try await generateBackup(
                ephemeralBackupKey: ephemeralBackupKey,
                localIdentifiers: localIdentifiers,
                progress: exportingBackupProgress
            )
        } catch let error {
            // At time of writing, iOS _only_ uses the continueWithoutUpload error;
            // no backups errors succeed on retry and even if they did the user could
            // always themselves unlink and relink after they continue.
            try? await reportLinkNSyncBackupResultToServer(
                waitForDeviceToLinkResponse: waitForLinkResponse,
                result: .error(.continueWithoutUpload),
                progress: markUploadedProgress
            )
            throw error
        }

        let uploadResult = try await uploadEphemeralBackup(
            metadata: backupMetadata,
            progress: uploadingBackupProgress
        )

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
        guard FeatureFlags.linkAndSync else {
            owsFailDebug("link'n'sync not available")
            return
        }
        owsAssertDebug(tsAccountManager.registrationStateWithMaybeSneakyTransaction.isPrimaryDevice != true)

        let hasPreviouslyRestored = db.read { messageBackupManager.hasRestoredFromBackup(tx: $0) }
        if hasPreviouslyRestored {
            // Assume this was from a link'n'sync that was subsequently interrupted
            Logger.info("Skipping link'n'sync; already restored from backup")
            return
        }

        await MainActor.run {
            appContext.ensureSleepBlocking(true, blockingObjectsDescription: Constants.sleepBlockingDescription)
        }
        defer {
            Task { @MainActor in
                appContext.ensureSleepBlocking(false, blockingObjectsDescription: Constants.sleepBlockingDescription)
            }
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
        case .error(_):
            // At time of writing, iOS _only_ supports the continueWithoutUpload error;
            // no backups errors succeed on retry and even if they did the user could
            // always themselves unlink and relink after they continue.
            throw .primaryFailedBackupExport
        }

        let downloadedFileUrl = try await downloadEphemeralBackup(
            cdnNumber: cdnNumber,
            cdnKey: cdnKey,
            ephemeralBackupKey: ephemeralBackupKey,
            progress: downloadBackupProgress
        )
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
        let response: HTTPResponse
        do {
            response = try await networkManager.asyncRequest(
                Requests.waitForDeviceToLink(tokenId: tokenId)
            )
        } catch {
            throw PrimaryLinkNSyncError.networkError
        }

        switch Requests.WaitForDeviceToLinkResponseCodes(rawValue: response.responseStatusCode) {
        case .success:
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
            throw PrimaryLinkNSyncError.timedOutWaitingForLinkedDevice
        case .invalidParameters, .rateLimited:
            throw PrimaryLinkNSyncError.errorWaitingForLinkedDevice
        case nil:
            owsFailDebug("Unexpected response")
            throw PrimaryLinkNSyncError.errorWaitingForLinkedDevice
        }
    }

    private func generateBackup(
        ephemeralBackupKey: BackupKey,
        localIdentifiers: LocalIdentifiers,
        progress: OWSProgressSink
    ) async throws(PrimaryLinkNSyncError) -> Upload.EncryptedBackupUploadMetadata {
        do {
            let metadata = try await messageBackupManager.exportEncryptedBackup(
                localIdentifiers: localIdentifiers,
                backupKey: ephemeralBackupKey,
                backupPurpose: .deviceTransfer,
                progress: progress
            )
            try await messageBackupManager.validateEncryptedBackup(
                fileUrl: metadata.fileUrl,
                localIdentifiers: localIdentifiers,
                backupKey: ephemeralBackupKey,
                backupPurpose: .deviceTransfer
            )
            return metadata
        } catch let error {
            owsFailDebug("Unable to generate link'n'sync backup: \(error)")
            throw PrimaryLinkNSyncError.errorGeneratingBackup
        }
    }

    private func uploadEphemeralBackup(
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
            if error.isNetworkFailureOrTimeout {
                throw PrimaryLinkNSyncError.networkError
            } else {
                throw PrimaryLinkNSyncError.errorUploadingBackup
            }
        }
    }

    private func reportLinkNSyncBackupResultToServer(
        waitForDeviceToLinkResponse: Requests.WaitForDeviceToLinkResponse,
        result: Requests.ExportAndUploadBackupResult,
        progress: OWSProgressSink
    ) async throws(PrimaryLinkNSyncError) -> Void {
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
                throw PrimaryLinkNSyncError.errorUploadingBackup
            }
        } catch let error {
            if error.isNetworkFailureOrTimeout {
                throw PrimaryLinkNSyncError.networkError
            } else {
                throw PrimaryLinkNSyncError.errorUploadingBackup
            }
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
        let response: HTTPResponse
        do {
            response = try await networkManager.asyncRequest(
                Requests.waitForLinkNSyncBackupUpload(auth: auth)
            )
        } catch {
            throw SecondaryLinkNSyncError.networkError
        }

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
            throw SecondaryLinkNSyncError.timedOutWaitingForBackup
        case .invalidParameters, .rateLimited:
            throw SecondaryLinkNSyncError.errorWaitingForBackup
        case nil:
            owsFailDebug("Unexpected response")
            throw SecondaryLinkNSyncError.errorWaitingForBackup
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
                    encryptionKey: ephemeralBackupKey.serialize().asData,
                    source: .linkNSyncBackup(cdnKey: cdnKey)
                ),
                progress: progress
            ).awaitable()
        } catch {
            if error.isNetworkFailureOrTimeout {
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
            try await messageBackupManager.importEncryptedBackup(
                fileUrl: fileUrl,
                localIdentifiers: localIdentifiers,
                backupKey: ephemeralBackupKey,
                progress: progress
            )
        } catch {
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

        static let waitForDeviceLinkTimeoutSeconds: UInt32 = FeatureFlags.linkAndSyncTimeoutSeconds
        static let waitForBackupUploadTimeoutSeconds: UInt32 = FeatureFlags.linkAndSyncTimeoutSeconds
    }

    // MARK: -

    private enum Requests {

        struct WaitForDeviceToLinkResponse: Codable {
            /// The deviceId of the linked device
            let id: Int64
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
                value: "\(LinkAndSyncManagerImpl.Constants.waitForDeviceLinkTimeoutSeconds)"
            )]
            let request = TSRequest(
                url: urlComponents.url!,
                method: "GET",
                parameters: nil
            )
            request.shouldHaveAuthorizationHeaders = true
            request.applyRedactionStrategy(.redactURLForSuccessResponses())
            // The timeout is server side; apply wiggle room for our local clock.
            request.timeoutInterval = 30 + TimeInterval(Constants.waitForDeviceLinkTimeoutSeconds)
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
            let request = TSRequest(
                url: URL(string: "v1/devices/transfer_archive")!,
                method: "PUT",
                parameters: [
                    "destinationDeviceId": waitForDeviceToLinkResponse.id,
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
            request.shouldHaveAuthorizationHeaders = true
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
                value: "\(Constants.waitForBackupUploadTimeoutSeconds)"
            )]
            let request = TSRequest(
                url: urlComponents.url!,
                method: "GET",
                parameters: nil
            )
            request.shouldHaveAuthorizationHeaders = true
            request.setAuth(auth)
            request.applyRedactionStrategy(.redactURLForSuccessResponses())
            // The timeout is server side; apply wiggle room for our local clock.
            request.timeoutInterval = 30 + TimeInterval(Constants.waitForBackupUploadTimeoutSeconds)
            return request
        }
    }
}
